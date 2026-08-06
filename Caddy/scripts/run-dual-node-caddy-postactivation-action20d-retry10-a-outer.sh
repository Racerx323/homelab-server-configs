#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_a
readonly probe_sha256=564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84
readonly runner_sha256=f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978
readonly regression_sha256=fb70eac7073fcd21434ee695ce4fa70e8412ea8e893ae9832e8a8f68d085e6b3
readonly accepted_outer_sha256=0bf76de0c4f170b72338d7f7ec2627b7004361c0a59afeab7f410daa4747114c
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly probe=$script_directory/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly runner=$script_directory/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly regression=$caddy_root/tests/action20d-retry10-a-postactivation-regression.sh
readonly accepted_outer=$script_directory/run-node-a-caddy-vrrp-activation-action20d-retry10-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
require_hash() {
    local expected_source_hash=$1
    local inspected_source_path=$2

    [[ -f "$inspected_source_path" && ! -L "$inspected_source_path" && -x "$inspected_source_path" ]] || return 1
    [[ "$(file_hash "$inspected_source_path")" = "$expected_source_hash" ]]
}
run_gate() {
    local gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory probe_hash runner_hash regression_hash \
        accepted_outer_hash collision_hash conditional_hash output_evidence_hash \
        syntax collision_policy conditional_policy output_evidence_policy \
        probe_self_test runner_self_test runner_contract_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate probe_hash require_hash "$probe_sha256" "$probe" || return 1
    run_gate runner_hash require_hash "$runner_sha256" "$runner" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate accepted_outer_hash require_hash "$accepted_outer_sha256" "$accepted_outer" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$probe" "$runner" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$probe" "$runner" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate probe_self_test /bin/bash "$probe" --self-test || return 1
    run_gate runner_self_test /bin/bash "$runner" --self-test || return 1
    run_gate runner_contract_test /bin/bash "$runner" --contract-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
    if safe_stream "$stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
        if [[ -s "$stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$stream_label"
            cat "$stream_path"
            printf '%s_%s_end\n' "$prefix" "$stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
    return 97
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
[[ -z "${CADDY_ACTION20D_RETRY10_A_INTERCEPTED_TEST:-}" ]]
work_directory=$(mktemp -d /tmp/caddy-action20d-retry10-a-outer.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly stdout_path=$work_directory/runner.stdout
readonly stderr_path=$work_directory/runner.stderr
: >"$stdout_path"
: >"$stderr_path"
chmod 0600 "$stdout_path" "$stderr_path"

runner_status=0
/bin/bash "$runner" >"$stdout_path" 2>"$stderr_path" || runner_status=$?
readonly runner_status
stream_failure=0
emit_stream runner_stdout "$stdout_path" || stream_failure=1
emit_stream runner_stderr "$stderr_path" || stream_failure=1
if [[ "$stream_failure" -ne 0 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    exit 97
fi
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
if [[ "$runner_status" -eq 0 ]] &&
    [[ "$(grep -Fxc 'action_20d_retry10_a_acceptance_complete=true' "$stdout_path")" -eq 1 ]]; then
    printf '%s_acceptance_accepted=true\n' "$prefix"
else
    printf '%s_acceptance_accepted=false\n' "$prefix" >&2
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_boundary_cleanup_complete=true\n' "$prefix"
[[ "$runner_status" -eq 0 ]]
