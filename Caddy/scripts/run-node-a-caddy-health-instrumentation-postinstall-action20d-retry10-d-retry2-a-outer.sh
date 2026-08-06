#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_a_outer
readonly inspector_sha256=2904f0e0d6cfbe87d4f041998c7bad294215f93522b37995c93fa57a4b3c18ff
readonly runner_sha256=32ea404878c42b843406dc39054f34186e6b169cd2b2a5e02d0c8ba59f79eebb
readonly regression_sha256=28a154003497ab537dfce9f3ec33bcf6ecbec47c958799656b778ce1680fa272
readonly multifile_policy_sha256=0c8d5453e906964143311bcec93c9c755b0fccd84bcbdf9f8bda7c367ed38655
readonly accepted_transaction_outer_sha256=502c8c6c9afe5b23533d7888f11fc6eb2b5cea2b7763fb204446b7e545e597c3
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly runner=$script_directory/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly regression=$caddy_root/tests/action20d-retry10-d-retry2-a-postinstall-regression.sh
readonly multifile_policy=$caddy_root/tests/multifile-grep-count-policy.sh
readonly accepted_transaction_outer=$script_directory/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2-outer.sh
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
    local action20d_retry2_a_outer_expected_hash=$1
    local action20d_retry2_a_outer_source_path=$2

    [[ -f "$action20d_retry2_a_outer_source_path" &&
        ! -L "$action20d_retry2_a_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20d_retry2_a_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20d_retry2_a_outer_source_path")" = "$action20d_retry2_a_outer_expected_hash" ]] || return 1
}
gate() {
    local action20d_retry2_a_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" \
            "$action20d_retry2_a_outer_gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" \
        "$action20d_retry2_a_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20d_retry2_a_outer_stream_path=$1

    [[ "$(wc -c <"$action20d_retry2_a_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20d_retry2_a_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20d_retry2_a_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20d_retry2_a_outer_stream_path"
}
emit_stream() {
    local action20d_retry2_a_outer_stream_label=$1
    local action20d_retry2_a_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20d_retry2_a_outer_stream_label" \
        "$(wc -c <"$action20d_retry2_a_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20d_retry2_a_outer_stream_label" \
        "$(line_count "$action20d_retry2_a_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20d_retry2_a_outer_stream_label" \
        "$(file_hash "$action20d_retry2_a_outer_stream_path")"
    if ! safe_stream "$action20d_retry2_a_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20d_retry2_a_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20d_retry2_a_outer_stream_label"
    if [[ -s "$action20d_retry2_a_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20d_retry2_a_outer_stream_label"
        cat "$action20d_retry2_a_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20d_retry2_a_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20d_retry2_a_outer_stream_label"
    fi
}
plan_acceptance_exact() {
    grep -Fq \
        'Exact authorized outer `502c8c6c...597c3` returned `0`.' \
        "$governing_plan" || return 1
    grep -Fq \
        '/var/backups/caddy-ha/action20d-retry10-d-retry2-node-a-health-instrumentation.18d7kI' \
        "$governing_plan" || return 1
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate inspector_source source_exact "$inspector_sha256" "$inspector" || return 1
    gate runner_source source_exact "$runner_sha256" "$runner" || return 1
    gate regression_source source_exact "$regression_sha256" "$regression" || return 1
    gate multifile_policy_source source_exact \
        "$multifile_policy_sha256" "$multifile_policy" || return 1
    gate accepted_transaction_source source_exact \
        "$accepted_transaction_outer_sha256" "$accepted_transaction_outer" || return 1
    gate plan_acceptance plan_acceptance_exact || return 1
    gate syntax /bin/bash -n "$inspector" "$runner" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$inspector" "$runner" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$inspector" "$runner" "$regression" "$0" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$runner" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate transcript_policy /bin/bash \
        "$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh" || return 1
    gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate multifile_count_policy /bin/bash "$multifile_policy" --check \
        "$inspector" "$runner" "$regression" "$0" || return 1
    gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    gate runner_self_test /bin/bash "$runner" --self-test || return 1
    gate production_regression /bin/bash "$regression" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory inspector_source runner_source regression_source \
            multifile_policy_source accepted_transaction_source plan_acceptance syntax shellcheck \
            canonical_format collision_policy conditional_policy transcript_policy \
            output_policy multifile_count_policy inspector_self_test runner_self_test \
            production_regression
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-a-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
install -m 0600 /dev/null "$runner_stdout"
install -m 0600 /dev/null "$runner_stderr"
runner_status=0
/bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
emit_stream runner_stdout "$runner_stdout" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream runner_stderr "$runner_stderr" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_full_health_helper_invoked=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
