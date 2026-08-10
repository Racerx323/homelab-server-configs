#!/usr/bin/env bash
# ssh-local-evidence-contract-v1

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_b_outer
readonly inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly regression_sha256=259e3c1fd179412db7eb90453303d908d0b043e0392c4b450e6889d501f9f1bb
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly regression=$caddy_root/tests/action28m-b-node-a-postinstall-regression.sh
work_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    # conditional-validator-explicit-failures-begin
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}
source_valid() {
    local action28mb_outer_hash=$1
    local action28mb_outer_file=$2

    # conditional-validator-explicit-failures-begin
    [[ "$(file_hash "$action28mb_outer_file")" = "$action28mb_outer_hash" ]] || return 1
    # conditional-validator-explicit-failures-end
}
gate() {
    local action28mb_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28mb_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28mb_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy remote_cwd_policy \
        ssh_local_evidence_policy inspector_self_test regression
}
run_local_gates() {
    local action28mb_outer_skip_regression=$1

    # conditional-validator-explicit-failures-begin
    gate working_directory working_directory_approved || return 1
    gate inspector_regular test -f "$inspector" || return 1
    gate inspector_executable test -x "$inspector" || return 1
    gate inspector_hash source_valid "$inspector_sha256" "$inspector" || return 1
    gate regression_regular test -f "$regression" || return 1
    gate regression_executable test -x "$regression" || return 1
    gate regression_hash source_valid "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$inspector" "$regression" "$0" || return 1
    gate shellcheck shellcheck "$inspector" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$inspector" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" \
        --check "$inspector" "$regression" "$0" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" \
        --check "$0" || return 1
    gate ssh_local_evidence_policy /bin/bash \
        "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "$0" || return 1
    gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    if [[ "$action28mb_outer_skip_regression" = true ]]; then
        gate regression test "$action28mb_outer_skip_regression" = true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
    # conditional-validator-explicit-failures-end
}
emit_test_local_gates() {
    local action28mb_outer_test_gate

    [[ "${CADDY_ACTION28MB_TEST_MODE:-}" = 1 ]] || return 1
    while IFS= read -r action28mb_outer_test_gate; do
        printf '%s_gate_%s=true\n' "$prefix" "$action28mb_outer_test_gate"
    done < <(expected_local_gates)
}
safe_stream() {
    local action28mb_outer_stream=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$action28mb_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28mb_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28mb_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:' \
        "$action28mb_outer_stream" || return 1
    # conditional-validator-explicit-failures-end
}
emit_stream() {
    local action28mb_outer_label=$1
    local action28mb_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28mb_outer_label" \
        "$(wc -c <"$action28mb_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28mb_outer_label" \
        "$(line_count "$action28mb_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28mb_outer_label" \
        "$(file_hash "$action28mb_outer_stream")"
    if ! safe_stream "$action28mb_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28mb_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28mb_outer_label"
    if [[ -s "$action28mb_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action28mb_outer_label"
        cat "$action28mb_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action28mb_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28mb_outer_label"
    fi
}
validation() {
    local action28mb_outer_validation_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28mb_outer_validation_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28mb_outer_validation_label" >&2
    return 1
}
validate_transcript() {
    local action28mb_outer_stdout=$1
    local action28mb_outer_stderr=$2
    local action28mb_outer_status=$3
    local action28mb_outer_expected
    local action28mb_outer_actual
    local action28mb_outer_expected_count
    local action28mb_outer_actual_count

    # conditional-validator-explicit-failures-begin
    validation status_zero test "$action28mb_outer_status" -eq 0 || return 1
    validation stderr_empty test ! -s "$action28mb_outer_stderr" || return 1
    action28mb_outer_expected=$(/bin/bash "$inspector" --expected-checks) || return 1
    action28mb_outer_actual=$(sed -n \
        's/^action_28m_b_check_\([a-z0-9_]*\)=true$/\1/p' "$action28mb_outer_stdout") || return 1
    validation ordered_checks test "$action28mb_outer_actual" = "$action28mb_outer_expected" || return 1
    action28mb_outer_expected_count=$(printf '%s\n' "$action28mb_outer_expected" | wc -l) || return 1
    action28mb_outer_actual_count=$(grep -Ec \
        '^action_28m_b_check_[a-z0-9_]+=(true|false)$' "$action28mb_outer_stdout" || true) || return 1
    validation check_count_exact test "$action28mb_outer_actual_count" -eq \
        "$action28mb_outer_expected_count" || return 1
    validation declared_count grep -Fqx \
        "action_28m_b_check_count=$action28mb_outer_expected_count" "$action28mb_outer_stdout" || return 1
    validation false_checks_absent test \
        "$(grep -Ec '^action_28m_b_check_[a-z0-9_]+=false$' "$action28mb_outer_stdout" || true)" \
        -eq 0 || return 1
    validation first_failure_none grep -Fqx 'action_28m_b_first_failure=none' \
        "$action28mb_outer_stdout" || return 1
    validation node_b_not_contacted grep -Fqx 'action_28m_b_node_b_contacted=false' \
        "$action28mb_outer_stdout" || return 1
    validation mutation_false grep -Fqx 'action_28m_b_mutation=false' \
        "$action28mb_outer_stdout" || return 1
    validation action_28m_not_rerun grep -Fqx 'action_28m_b_action_28m_rerun=false' \
        "$action28mb_outer_stdout" || return 1
    validation action_28m_a_not_rerun grep -Fqx 'action_28m_b_action_28m_a_rerun=false' \
        "$action28mb_outer_stdout" || return 1
    validation acceptance grep -Fqx 'action_28m_b_acceptance=true' \
        "$action28mb_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action28mb_outer_status=$?

    trap - EXIT INT TERM
    exit "$action28mb_outer_status"
}
run_action() {
    local action28mb_outer_evidence_root
    local action28mb_outer_ssh_status=0
    local action28mb_outer_ssh_bin
    local action28mb_outer_stdout
    local action28mb_outer_stderr
    local action28mb_outer_status_file

    if [[ "${CADDY_ACTION28MB_TEST_MODE:-}" = 1 ]]; then
        action28mb_outer_evidence_root=${CADDY_ACTION28MB_EVIDENCE_ROOT:?}
    else
        action28mb_outer_evidence_root=/tmp/caddy-ssh-evidence/action28m-b
    fi
    install -d -m 0700 "$action28mb_outer_evidence_root"
    work_root=$(mktemp -d "$action28mb_outer_evidence_root/run.XXXXXX")
    chmod 0700 "$work_root"
    trap cleanup EXIT INT TERM
    action28mb_outer_stdout=$work_root/remote.stdout
    action28mb_outer_stderr=$work_root/remote.stderr
    action28mb_outer_status_file=$work_root/remote.status
    : >"$action28mb_outer_stdout"
    : >"$action28mb_outer_stderr"
    : >"$action28mb_outer_status_file"
    chmod 0600 "$action28mb_outer_stdout" "$action28mb_outer_stderr" \
        "$action28mb_outer_status_file"
    if [[ "${CADDY_ACTION28MB_SKIP_LOCAL_GATES:-false}" = true ]]; then
        emit_test_local_gates || return 1
    else
        run_local_gates "${CADDY_ACTION28MB_SKIP_REGRESSION:-false}" || return 1
    fi
    action28mb_outer_ssh_bin=${CADDY_ACTION28MB_SSH_BIN:-/usr/bin/ssh}
    "$action28mb_outer_ssh_bin" -T -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile=/home/aaron/.ssh/known_hosts \
        -o HostKeyAlias=pihole0.local.theama.co \
        pi@10.1.0.53 "cd / && sudo -n /bin/bash -s --" \
        <"$inspector" >"$action28mb_outer_stdout" 2>"$action28mb_outer_stderr" ||
        action28mb_outer_ssh_status=$?
    printf '%s\n' "$action28mb_outer_ssh_status" >"$action28mb_outer_status_file"
    emit_stream remote_stdout "$action28mb_outer_stdout" || return $?
    emit_stream remote_stderr "$action28mb_outer_stderr" || return $?
    validate_transcript "$action28mb_outer_stdout" "$action28mb_outer_stderr" \
        "$action28mb_outer_ssh_status" || return 1
    printf '%s_remote_status=%s\n' "$prefix" "$action28mb_outer_ssh_status"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_mutation=false\n' "$prefix"
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_evidence_status_file=%s\n' "$prefix" "$action28mb_outer_status_file"
    printf '%s_acceptance=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --source-test)
        source_valid "$inspector_sha256" "$inspector"
        source_valid "$regression_sha256" "$regression"
        grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$0"
        printf '%s_source_test_complete=true\n' "$prefix"
        ;;
    --self-test)
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    "") run_action ;;
    *) exit 64 ;;
esac
