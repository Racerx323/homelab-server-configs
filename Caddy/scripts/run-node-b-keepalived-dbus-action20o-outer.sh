#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_outer
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=10.1.0.54
readonly expected_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly expected_check_count=77
readonly transaction_sha256=a445f3276231e147b7ee96c9f58561f2287ac50f91503fb64ec2d6581e24226f
readonly regression_sha256=83a5170f6bdc93bbddd04670ae2f070ba701c5eccce5d213a19b369d0f692df0
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/activate-node-b-keepalived-dbus-action20o.sh
readonly regression=$caddy_root/tests/action20o-node-b-keepalived-dbus-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

ssh_binary=/usr/bin/ssh

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
    local action20o_outer_expected_hash=$1
    local action20o_outer_path=$2

    [[ -f "$action20o_outer_path" && ! -L "$action20o_outer_path" ]] || return 1
    [[ "$(file_hash "$action20o_outer_path")" = "$action20o_outer_expected_hash" ]]
}
run_gate() {
    local action20o_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20o_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20o_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_regular transaction_executable transaction_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy accepted_live_hash_policy \
        root_cwd_policy transaction_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate transaction_regular test -f "$transaction" || return 1
    run_gate transaction_executable test -x "$transaction" || return 1
    run_gate transaction_hash require_hash "$transaction_sha256" "$transaction" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$transaction" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$transaction" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$0" || return 1
    run_gate transaction_self_test /bin/bash "$transaction" --self-test || return 1
    if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 ]]; then
        run_gate regression true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action20o_outer_stream=$1

    [[ "$(wc -c <"$action20o_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20o_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20o_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20o_outer_stream"
}
emit_stream() {
    local action20o_outer_stream_label=$1
    local action20o_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20o_outer_stream_label" "$(wc -c <"$action20o_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20o_outer_stream_label" "$(line_count "$action20o_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20o_outer_stream_label" "$(file_hash "$action20o_outer_stream")"
    if ! safe_stream "$action20o_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20o_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20o_outer_stream_label"
    if [[ -s "$action20o_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20o_outer_stream_label"
        cat "$action20o_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action20o_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20o_outer_stream_label"
    fi
}
require_one() {
    local action20o_outer_line=$1
    local action20o_outer_transcript=$2

    [[ "$(grep -Fxc "$action20o_outer_line" "$action20o_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action20o_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action20o_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action20o_outer_assertion_label" >&2
    return 1
}
generate_expected_checks() {
    local action20o_outer_expected=$1

    /bin/bash "$transaction" --expected-checks >"$action20o_outer_expected"
}
capture_contract() {
    local action20o_outer_stdout=$1
    local action20o_outer_capture

    for action20o_outer_capture in reload reload_journal dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state; do
        require_one "action_20o_capture_${action20o_outer_capture}_status=0" "$action20o_outer_stdout" || return 1
        require_one "action_20o_capture_${action20o_outer_capture}_stdout_classification=bounded_safe" "$action20o_outer_stdout" || return 1
        require_one "action_20o_capture_${action20o_outer_capture}_stderr_classification=bounded_safe" "$action20o_outer_stdout" || return 1
    done
}
validate_success() {
    local action20o_outer_stdout=$1
    local action20o_outer_stderr=$2
    local action20o_outer_status=$3
    local action20o_outer_expected=$4
    local action20o_outer_actual=$5

    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action20o_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action20o_outer_stderr" || return 1
    validate_assert expected_checks_generated generate_expected_checks "$action20o_outer_expected" || return 1
    validate_assert expected_check_count test "$(line_count "$action20o_outer_expected")" -eq "$expected_check_count" || return 1
    validate_assert false_checks_absent test "$(grep -Ec '^action_20o_check_[a-z0-9_]+=false$' "$action20o_outer_stdout" || true)" -eq 0 || return 1
    sed -n 's/^action_20o_check_\([a-z0-9_]*\)=true$/\1/p' "$action20o_outer_stdout" >"$action20o_outer_actual" || return 1
    validate_assert actual_check_count test "$(line_count "$action20o_outer_actual")" -eq "$expected_check_count" || return 1
    validate_assert unique_check_count test "$(LC_ALL=C sort -u "$action20o_outer_actual" | wc -l)" -eq "$expected_check_count" || return 1
    validate_assert ordered_check_contract diff -u "$action20o_outer_expected" "$action20o_outer_actual" || return 1
    validate_assert main_hash require_one "action_20o_value_main_sha256=$expected_main_sha256" "$action20o_outer_stdout" || return 1
    validate_assert expected_count_value require_one 'action_20o_value_expected_check_count=77' "$action20o_outer_stdout" || return 1
    validate_assert check_count_value require_one 'action_20o_check_count=77' "$action20o_outer_stdout" || return 1
    validate_assert failed_count_zero require_one 'action_20o_failed_check_count=0' "$action20o_outer_stdout" || return 1
    validate_assert first_failure_none require_one 'action_20o_first_failure=none' "$action20o_outer_stdout" || return 1
    validate_assert reload_true require_one 'action_20o_keepalived_reload=true' "$action20o_outer_stdout" || return 1
    validate_assert restart_false require_one 'action_20o_keepalived_restart=false' "$action20o_outer_stdout" || return 1
    validate_assert dbus_active require_one 'action_20o_dbus_runtime_active=true' "$action20o_outer_stdout" || return 1
    validate_assert filesystem_mutation_false require_one 'action_20o_filesystem_mutation=false' "$action20o_outer_stdout" || return 1
    validate_assert vrrp_transition_false require_one 'action_20o_vrrp_transition=false' "$action20o_outer_stdout" || return 1
    validate_assert vip_mutation_false require_one 'action_20o_vip_mutation=false' "$action20o_outer_stdout" || return 1
    validate_assert node_a_ssh_false require_one 'action_20o_node_a_ssh_contacted=false' "$action20o_outer_stdout" || return 1
    validate_assert node_a_continuity_true require_one 'action_20o_node_a_continuity_verified=true' "$action20o_outer_stdout" || return 1
    validate_assert producer_complete require_one 'action_20o_complete=true' "$action20o_outer_stdout" || return 1
    validate_assert capture_contract capture_contract "$action20o_outer_stdout" || return 1
    validate_assert rollback_absent test "$(grep -Fc 'action_20o_rollback_' "$action20o_outer_stdout" || true)" -eq 0 || return 1
    # conditional-validator-explicit-failures-end
}
contract_self_test() {
    [[ "$(expected_local_gates | wc -l)" -eq 19 ]] || return 1
    [[ "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" -eq 19 ]] || return 1
    [[ "$expected_target" = pi@10.1.0.54 ]] || return 1
    [[ "$expected_host_alias" = 10.1.0.54 ]] || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        contract_self_test
        run_local_gates
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 ]]; then
    [[ -n "${CADDY_ACTION20O_SSH_BIN:-}" ]] || exit 64
    ssh_binary=$CADDY_ACTION20O_SSH_BIN
fi
readonly ssh_binary
if [[ "${CADDY_ACTION20O_TEST_MODE:-}" = 1 &&
    "${CADDY_ACTION20O_TEST_SKIP_LOCAL_GATES:-}" = 1 ]]; then
    printf '%s_gate_test_local_gates_skipped=true\n' "$prefix"
else
    run_local_gates
fi

outer_root=$(mktemp -d /tmp/caddy-action20o-outer.XXXXXX)
readonly outer_root
trap 'rm -rf -- "$outer_root"' EXIT
readonly remote_stdout=$outer_root/remote.stdout
readonly remote_stderr=$outer_root/remote.stderr
readonly expected_checks_file=$outer_root/expected.checks
readonly actual_checks_file=$outer_root/actual.checks
for action20o_outer_capture_path in \
    "$remote_stdout" "$remote_stderr" "$expected_checks_file" "$actual_checks_file"; do
    install -m 0600 /dev/null "$action20o_outer_capture_path"
done

remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=yes "$expected_target" \
    'cd / && sudo -n /bin/bash -s --' <"$transaction" \
    >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status

emit_stream remote_stdout "$remote_stdout"
emit_stream remote_stderr "$remote_stderr"
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
validate_success "$remote_stdout" "$remote_stderr" "$remote_status" \
    "$expected_checks_file" "$actual_checks_file"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_ssh_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=true\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_activation=true\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
