#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_outer
readonly builder_sha256=9306f430153e2c5083ddf263893a1b692b2ae3e6dbfac66d89b5d2f2ce93e01a
readonly generated_inspector_sha256=7497358ba86fa72fbf7b25fa699c7cfdb71b98be90e452674e4f403e56d19423
readonly generated_runner_sha256=d5b91e604123ad7e59e44d98062494cc80e2da8e153fb4e0fb4af3e67365c961
readonly generated_regression_sha256=8ecbbe8fdc7e48c48636cee80c2021fe7988f239e465ecb3f5c89d8cba18d799
readonly executed_outer_sha256=ac30cd2bd356026cf1e9cc737976cdbf51e58e7763e0a3a34f8543df1f8a8ee1
readonly accepted_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
readonly executed_outer=$script_directory/run-node-b-caddy-health-helper-postinstall-action20i-a-outer.sh
readonly accepted_manifest=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly consumer_manifest=$caddy_root/manifests/deployable-live-hash-consumers.tsv
readonly governing_plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
source_exact() {
    local action20i_a_retry_outer_expected_hash=$1
    local action20i_a_retry_outer_source_path=$2

    [[ -f "$action20i_a_retry_outer_source_path" &&
        ! -L "$action20i_a_retry_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20i_a_retry_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20i_a_retry_outer_source_path")" = "$action20i_a_retry_outer_expected_hash" ]] || return 1
}
gate() {
    local action20i_a_retry_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" \
            "$action20i_a_retry_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" \
        "$action20i_a_retry_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20i_a_retry_outer_stream_path=$1

    [[ "$(wc -c <"$action20i_a_retry_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20i_a_retry_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20i_a_retry_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20i_a_retry_outer_stream_path"
}
emit_stream() {
    local action20i_a_retry_outer_stream_label=$1
    local action20i_a_retry_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" \
        "$action20i_a_retry_outer_stream_label" \
        "$(wc -c <"$action20i_a_retry_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" \
        "$action20i_a_retry_outer_stream_label" \
        "$(line_count "$action20i_a_retry_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" \
        "$action20i_a_retry_outer_stream_label" \
        "$(file_hash "$action20i_a_retry_outer_stream_path")"
    if ! safe_stream "$action20i_a_retry_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" \
            "$action20i_a_retry_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" \
        "$action20i_a_retry_outer_stream_label"
    if [[ -s "$action20i_a_retry_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" \
            "$action20i_a_retry_outer_stream_label"
        cat "$action20i_a_retry_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" \
            "$action20i_a_retry_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" \
            "$action20i_a_retry_outer_stream_label"
    fi
}
accepted_state_exact() {
    awk -F '\t' -v expected="$accepted_health_sha256" '
        $1 == "node_b_health_helper" {
            count++
            valid = ($2 == expected && $3 == "20i")
        }
        END { exit !(count == 1 && valid) }
    ' "$accepted_manifest" || return 1
}
consumer_registration_exact() {
    awk -F '\t' '
        $1 == "node_b_health_helper" &&
        $2 == "Caddy/scripts/build-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh" &&
        $3 == "expected_health_sha256" { count++ }
        END { exit !(count == 1) }
    ' "$consumer_manifest" || return 1
}
plan_failure_exact() {
    # Backticks are literal Markdown evidence in the governing plan.
    # shellcheck disable=SC2016
    grep -Fq \
        '66 passed and exactly `keepalived_script_uid_exact` and `caddy_tls_gid_exact` failed' \
        "$governing_plan" || return 1
    # shellcheck disable=SC2016
    grep -Fq \
        'The accepted Node B identity baseline is UID `992` and `caddy-tls` GID `990`' \
        "$governing_plan" || return 1
}
generated_sources_exact() {
    local action20i_a_retry_outer_generated_root=$1

    source_exact "$generated_inspector_sha256" \
        "$action20i_a_retry_outer_generated_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh" || return 1
    source_exact "$generated_runner_sha256" \
        "$action20i_a_retry_outer_generated_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh" || return 1
    source_exact "$generated_regression_sha256" \
        "$action20i_a_retry_outer_generated_root/tests/action20i-a-retry-postinstall-regression.sh" || return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory builder_source executed_outer_source accepted_state \
        consumer_registration governing_plan_failure syntax shellcheck \
        canonical_format collision_policy conditional_policy \
        multifile_grep_policy portable_awk_policy stale_hash_policy \
        builder_status generated_sources regression_status
}
run_static_gates() {
    gate working_directory working_directory_approved || return 1
    gate builder_source source_exact "$builder_sha256" "$builder" || return 1
    gate executed_outer_source source_exact \
        "$executed_outer_sha256" "$executed_outer" || return 1
    gate accepted_state accepted_state_exact || return 1
    gate consumer_registration consumer_registration_exact || return 1
    gate governing_plan_failure plan_failure_exact || return 1
    gate syntax /bin/bash -n "$builder" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$0" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$0" || return 1
    gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy-regression.sh" || return 1
    gate stale_hash_policy /bin/bash \
        "$caddy_root/tests/accepted-live-hash-policy-regression.sh" || return 1
}
run_capture() {
    local action20i_a_retry_outer_capture_label=$1
    local action20i_a_retry_outer_capture_stdout=$work_root/$action20i_a_retry_outer_capture_label.stdout
    local action20i_a_retry_outer_capture_stderr=$work_root/$action20i_a_retry_outer_capture_label.stderr

    shift
    install -m 0600 /dev/null "$action20i_a_retry_outer_capture_stdout"
    install -m 0600 /dev/null "$action20i_a_retry_outer_capture_stderr"
    capture_status=0
    "$@" >"$action20i_a_retry_outer_capture_stdout" \
        2>"$action20i_a_retry_outer_capture_stderr" || capture_status=$?
    emit_stream "${action20i_a_retry_outer_capture_label}_stdout" \
        "$action20i_a_retry_outer_capture_stdout" || return 97
    emit_stream "${action20i_a_retry_outer_capture_label}_stderr" \
        "$action20i_a_retry_outer_capture_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" \
        "$action20i_a_retry_outer_capture_label" "$capture_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        readonly action20i_a_retry_outer_mode=${1#--}
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        readonly action20i_a_retry_outer_mode=execute
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_static_gates
work_root=$(mktemp -d /tmp/caddy-action20i-a-retry-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
run_capture builder /bin/bash "$builder" --output "$generated_root"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate builder_status true
gate generated_sources generated_sources_exact "$generated_root"
run_capture regression /bin/bash \
    "$generated_root/tests/action20i-a-retry-postinstall-regression.sh"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate regression_status true

if [[ "$action20i_a_retry_outer_mode" != execute ]]; then
    printf '%s_mode=%s\n' "$prefix" "$action20i_a_retry_outer_mode"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_persistent_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
    exit 0
fi

run_capture remote /bin/bash \
    "$generated_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
printf '%s_remote_status=0\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
