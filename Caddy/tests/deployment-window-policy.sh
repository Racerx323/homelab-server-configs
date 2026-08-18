#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly deployment_window_prefix=deployment_window_policy
deployment_window_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly deployment_window_test_directory
readonly deployment_window_default_root=${deployment_window_test_directory%/Caddy/tests}

if [[ -n "${DEPLOYMENT_WINDOW_TEST_ROOT:-}" ]]; then
    [[ "${DEPLOYMENT_WINDOW_TEST_MODE:-}" = 1 ]] || exit 64
    [[ "$DEPLOYMENT_WINDOW_TEST_ROOT" = /tmp/* ]] || exit 64
    deployment_window_repository_root=$DEPLOYMENT_WINDOW_TEST_ROOT
else
    deployment_window_repository_root=$deployment_window_default_root
fi
readonly deployment_window_repository_root
readonly deployment_window_registry=${DEPLOYMENT_WINDOW_REGISTRY:-$deployment_window_repository_root/deployment-streams.tsv}

deployment_window_record_check() {
    local deployment_window_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$deployment_window_prefix" "$deployment_window_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$deployment_window_prefix" "$deployment_window_label" >&2
    return 1
}

deployment_window_regular_file() {
    local deployment_window_path=$1

    [[ -f "$deployment_window_path" && ! -L "$deployment_window_path" ]]
}

deployment_window_schema_valid() {
    deployment_window_regular_file "$deployment_window_registry" || return 1
    [[ "$(sed -n '1p' "$deployment_window_registry")" = $'schema_version\tcomponent\tcomponent_root\tplan\thistory\tsuccessor_registry\tcoverage_registry\twindow_state\taction\tterminal_result\tarchive_tag' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 11 || $1 != "1" { invalid = 1; exit }
        $2 !~ /^[a-z][a-z0-9-]*$/ { invalid = 1; exit }
        $3 !~ /^[A-Za-z0-9][A-Za-z0-9._/-]*$/ || $3 ~ /(^|\/)\.\.?($|\/)/ { invalid = 1; exit }
        $4 !~ /^[A-Za-z0-9][A-Za-z0-9._/-]*\.md$/ { invalid = 1; exit }
        $5 !~ /^[A-Za-z0-9][A-Za-z0-9._/-]*\.md$/ { invalid = 1; exit }
        $6 !~ /^[A-Za-z0-9][A-Za-z0-9._/-]*\.tsv$/ { invalid = 1; exit }
        $7 !~ /^[A-Za-z0-9][A-Za-z0-9._/-]*\.tsv$/ { invalid = 1; exit }
        $8 !~ /^(clean|defined|terminal-pending)$/ { invalid = 1; exit }
        $9 !~ /^(-|[0-9]+[a-z0-9-]*)$/ { invalid = 1; exit }
        $10 !~ /^(-|accepted|failed-consumed|manual-intervention)$/ { invalid = 1; exit }
        $11 !~ /^(-|[a-z0-9][a-z0-9._-]*)$/ { invalid = 1; exit }
        seen_component[$2]++ || seen_root[$3]++ { invalid = 1; exit }
        END { exit invalid || NR <= 1 }
    ' "$deployment_window_registry"
}

deployment_window_successor_fields() {
    local deployment_window_successor=$1

    [[ "$(sed -n '1p' "$deployment_window_successor")" = $'schema_version\tstatus\taction\toperation_spec\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' ]] || return 1
    [[ "$(wc -l <"$deployment_window_successor")" -eq 2 ]] || return 1
    awk -F '\t' 'NR == 2 && NF == 10 { print $2 "\t" $3 }' \
        "$deployment_window_successor"
}

deployment_window_action_files_valid() {
    local deployment_window_component_root=$1
    local deployment_window_path deployment_window_name

    while IFS= read -r deployment_window_path; do
        deployment_window_name=${deployment_window_path##*/}
        [[ "$deployment_window_name" =~ action[0-9] ]] || continue
        return 1
    done < <(
        find "$deployment_window_component_root" \
            \( -path '*/scripts/*' -o -path '*/manifests/*' -o -path '*/tests/*' \) \
            -type f -print | LC_ALL=C sort
    )

    return 0
}

deployment_window_stream_valid() {
    local deployment_window_component=$1
    local deployment_window_root_relative=$2
    local deployment_window_plan_relative=$3
    local deployment_window_history_relative=$4
    local deployment_window_successor_relative=$5
    local deployment_window_coverage_relative=$6
    local deployment_window_state=$7
    local deployment_window_action=$8
    local deployment_window_result=$9
    local deployment_window_tag=${10}
    local deployment_window_component_root=$deployment_window_repository_root/$deployment_window_root_relative
    local deployment_window_plan=$deployment_window_repository_root/$deployment_window_plan_relative
    local deployment_window_history=$deployment_window_repository_root/$deployment_window_history_relative
    local deployment_window_successor=$deployment_window_repository_root/$deployment_window_successor_relative
    local deployment_window_coverage=$deployment_window_repository_root/$deployment_window_coverage_relative
    local deployment_window_successor_status deployment_window_successor_action

    [[ -d "$deployment_window_component_root" && ! -L "$deployment_window_component_root" ]] || return 1
    deployment_window_regular_file "$deployment_window_plan" || return 1
    deployment_window_regular_file "$deployment_window_history" || return 1
    deployment_window_regular_file "$deployment_window_successor" || return 1
    deployment_window_regular_file "$deployment_window_coverage" || return 1
    [[ "$(sed -n '1p' "$deployment_window_coverage")" = $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' ]] || return 1
    IFS=$'\t' read -r deployment_window_successor_status deployment_window_successor_action < <(
        deployment_window_successor_fields "$deployment_window_successor"
    ) || return 1

    case "$deployment_window_state" in
        clean)
            [[ "$deployment_window_action" = - && "$deployment_window_result" = - ]] || return 1
            [[ "$deployment_window_successor_status" = none && "$deployment_window_successor_action" = - ]] || return 1
            [[ "$(wc -l <"$deployment_window_coverage")" -eq 1 ]] || return 1
            if [[ "$deployment_window_tag" != - && "$deployment_window_repository_root" = "$deployment_window_default_root" ]]; then
                [[ "$(git -C "$deployment_window_repository_root" cat-file -t "refs/tags/$deployment_window_tag" 2>/dev/null)" = tag ]] || return 1
            fi
            ;;
        defined)
            [[ "$deployment_window_action" != - && "$deployment_window_result" = - && "$deployment_window_tag" = - ]] || return 1
            [[ "$deployment_window_successor_status" = defined && "$deployment_window_successor_action" = "$deployment_window_action" ]] || return 1
            [[ "$(wc -l <"$deployment_window_coverage")" -gt 1 ]] || return 1
            ;;
        terminal-pending)
            [[ "$deployment_window_action" != - && "$deployment_window_result" != - && "$deployment_window_tag" != - ]] || return 1
            [[ "$deployment_window_successor_status" = none && "$deployment_window_successor_action" = - ]] || return 1
            [[ "$(wc -l <"$deployment_window_coverage")" -eq 1 ]] || return 1
            grep -Fq -- "Tag: \`$deployment_window_tag\`" "$deployment_window_history" || return 1
            grep -Fq -- 'Status: terminal-pending' "$deployment_window_history" || return 1
            ;;
        *) return 1 ;;
    esac

    deployment_window_action_files_valid "$deployment_window_component_root" || return 1
    ! jq -e '
        [.profiles[].host_tests[], .profiles[].debian_tests[],
         .profiles[].shell_files[]] |
        any(test("(^|/)[^/]*action[0-9]"))
    ' "$deployment_window_component_root/tests/focused-validation.yaml" >/dev/null || return 1
    printf '%s_stream_%s=true\n' "$deployment_window_prefix" "$deployment_window_component"
}

deployment_window_streams_valid() {
    local deployment_window_schema deployment_window_component deployment_window_root
    local deployment_window_plan deployment_window_history deployment_window_successor
    local deployment_window_coverage deployment_window_state deployment_window_action
    local deployment_window_result deployment_window_tag

    while IFS=$'\t' read -r deployment_window_schema deployment_window_component \
        deployment_window_root deployment_window_plan deployment_window_history \
        deployment_window_successor deployment_window_coverage deployment_window_state \
        deployment_window_action deployment_window_result deployment_window_tag; do
        [[ "$deployment_window_schema" = schema_version ]] ||
            deployment_window_stream_valid "$deployment_window_component" \
                "$deployment_window_root" "$deployment_window_plan" \
                "$deployment_window_history" "$deployment_window_successor" \
                "$deployment_window_coverage" "$deployment_window_state" \
                "$deployment_window_action" "$deployment_window_result" \
                "$deployment_window_tag" || return 1
    done <"$deployment_window_registry"
}

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        deployment_window_record_check schema deployment_window_schema_valid || exit 1
        deployment_window_record_check streams deployment_window_streams_valid || exit 1
        printf '%s_complete=true\n' "$deployment_window_prefix"
        ;;
    *)
        printf 'Usage: %s --check\n' "${0##*/}" >&2
        exit 64
        ;;
esac
