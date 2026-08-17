#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly deployment_window_regression_prefix=deployment_window_policy_regression
deployment_window_regression_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly deployment_window_regression_test_directory
readonly deployment_window_regression_policy=$deployment_window_regression_test_directory/deployment-window-policy.sh
deployment_window_regression_root=$(mktemp -d /tmp/deployment-window-regression.XXXXXX)
readonly deployment_window_regression_root
trap 'rm -rf -- "$deployment_window_regression_root"' EXIT INT TERM

deployment_window_regression_policy_accepts() {
    DEPLOYMENT_WINDOW_TEST_MODE=1 DEPLOYMENT_WINDOW_TEST_ROOT=$deployment_window_regression_root \
        /bin/bash "$deployment_window_regression_policy" --check >/dev/null 2>&1
}

deployment_window_regression_policy_rejects() {
    ! deployment_window_regression_policy_accepts
}

deployment_window_regression_record() {
    local deployment_window_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$deployment_window_regression_prefix" \
            "$deployment_window_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$deployment_window_regression_prefix" \
        "$deployment_window_regression_label" >&2
    return 1
}

deployment_window_regression_write_registry() {
    local deployment_window_regression_state=$1
    local deployment_window_regression_action=$2
    local deployment_window_regression_result=$3
    local deployment_window_regression_tag=$4

    printf '%s\n' \
        $'schema_version\tcomponent\tcomponent_root\tplan\thistory\tsuccessor_registry\tcoverage_registry\twindow_state\taction\tterminal_result\tarchive_tag' \
        "1"$'\t'"caddy"$'\t'"Caddy"$'\t'"Caddy/docs/plan.md"$'\t'"Caddy/HISTORY.md"$'\t'"Caddy/manifests/deployable-successor.tsv"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"$deployment_window_regression_state"$'\t'"$deployment_window_regression_action"$'\t'"$deployment_window_regression_result"$'\t'"$deployment_window_regression_tag" \
        >"$deployment_window_regression_root/deployment-streams.tsv"
}

deployment_window_regression_write_successor() {
    local deployment_window_regression_status=$1
    local deployment_window_regression_action=$2

    printf '%s\n' \
        $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
        "1"$'\t'"$deployment_window_regression_status"$'\t'"$deployment_window_regression_action"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"-" \
        >"$deployment_window_regression_root/Caddy/manifests/deployable-successor.tsv"
}

install -d -m 0700 \
    "$deployment_window_regression_root/Caddy/docs" \
    "$deployment_window_regression_root/Caddy/manifests" \
    "$deployment_window_regression_root/Caddy/scripts" \
    "$deployment_window_regression_root/Caddy/tests"
printf '# Plan\n' >"$deployment_window_regression_root/Caddy/docs/plan.md"
printf '%s\n' '# History' "- Tag: \`caddy-action35-terminal\`" \
    '- Status: terminal-pending' >"$deployment_window_regression_root/Caddy/HISTORY.md"
printf '{}\n' >"$deployment_window_regression_root/Caddy/tests/focused-validation.yaml"
printf '%s\n' $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' \
    >"$deployment_window_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
printf '#!/usr/bin/env bash\nexit 0\n' \
    >"$deployment_window_regression_root/Caddy/scripts/apply-action35.sh"
chmod 0755 "$deployment_window_regression_root/Caddy/scripts/apply-action35.sh"

deployment_window_regression_write_successor none -
deployment_window_regression_write_registry terminal-pending 35 failed-consumed \
    caddy-action35-terminal
deployment_window_regression_record terminal_pending_accepts \
    deployment_window_regression_policy_accepts || exit 1

printf '# historical action\n' \
    >"$deployment_window_regression_root/Caddy/scripts/apply-action34.sh"
deployment_window_regression_record unrelated_action_rejected \
    deployment_window_regression_policy_rejects || exit 1
rm -f -- "$deployment_window_regression_root/Caddy/scripts/apply-action34.sh"

deployment_window_regression_write_successor defined 35
printf '%s\n' $'defined\taccepted-path\ttransaction\treach\tdecisions/defined.tsv\traw/defined.txt' \
    >>"$deployment_window_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
deployment_window_regression_write_registry defined 35 - -
deployment_window_regression_record defined_accepts \
    deployment_window_regression_policy_accepts || exit 1

deployment_window_regression_write_successor defined 35a
deployment_window_regression_record mismatched_successor_rejected \
    deployment_window_regression_policy_rejects || exit 1

rm -f -- "$deployment_window_regression_root/Caddy/scripts/apply-action35.sh"
printf '%s\n' $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' \
    >"$deployment_window_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
deployment_window_regression_write_successor none -
deployment_window_regression_write_registry clean - - caddy-action35-terminal
deployment_window_regression_record clean_accepts \
    deployment_window_regression_policy_accepts || exit 1

printf '# historical action\n' \
    >"$deployment_window_regression_root/Caddy/scripts/apply-action35.sh"
deployment_window_regression_record clean_with_action_rejected \
    deployment_window_regression_policy_rejects || exit 1
rm -f -- "$deployment_window_regression_root/Caddy/scripts/apply-action35.sh"

printf '%s\n' \
    $'1\tduplicate\tCaddy2\tCaddy/docs/plan.md\tCaddy/HISTORY.md\tCaddy/manifests/deployable-successor.tsv\tCaddy/manifests/deployable-successor-coverage.tsv\tclean\t-\t-\t-' \
    >>"$deployment_window_regression_root/deployment-streams.tsv"
deployment_window_regression_record duplicate_stream_rejected \
    deployment_window_regression_policy_rejects || exit 1

printf '%s_complete=true\n' "$deployment_window_regression_prefix"
