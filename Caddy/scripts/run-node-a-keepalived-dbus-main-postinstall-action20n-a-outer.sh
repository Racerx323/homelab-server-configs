#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20n_a_outer
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=10.1.0.53
readonly expected_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly inspector_sha256=6130fd3716cdc81a3ee08eebd1499a6d18a99664ae5eb48e906074ba834773ec
readonly regression_sha256=b17d6c8b027b5e0ae205814a74622c35055066feac2ed8198dc4069e7bd2859f
readonly expected_check_count=68
readonly expected_remote_line_count=84
readonly expected_backup=/var/backups/caddy-ha/action20n-node-a-dbus-main.s8Qkep
readonly expected_backup_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-a-keepalived-dbus-main-postinstall-action20n-a.sh
readonly regression=$caddy_root/tests/action20n-a-node-a-keepalived-dbus-main-postinstall-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action20na_outer_value=$1

    [[ ${#action20na_outer_value} -eq 64 ]] || return 1
    [[ "$action20na_outer_value" != *[!0-9a-f]* ]]
}
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
require_source() {
    local action20na_outer_expected_hash=$1
    local action20na_outer_source=$2

    [[ -f "$action20na_outer_source" && ! -L "$action20na_outer_source" &&
        -x "$action20na_outer_source" ]] || return 1
    [[ "$(file_hash "$action20na_outer_source")" = "$action20na_outer_expected_hash" ]]
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)' \
        "$inspector"
}
run_gate() {
    local action20na_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20na_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20na_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy accepted_live_hash_policy \
        read_only_contract inspector_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_regular test -f "$inspector" || return 1
    run_gate inspector_executable test -x "$inspector" || return 1
    run_gate inspector_hash require_source "$inspector_sha256" "$inspector" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_source "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash \
        "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate read_only_contract read_only_contract || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20na_outer_stream=$1

    [[ "$(wc -c <"$action20na_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20na_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20na_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20na_outer_stream"
}
emit_stream() {
    local action20na_outer_stream_label=$1
    local action20na_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20na_outer_stream_label" "$(wc -c <"$action20na_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20na_outer_stream_label" "$(line_count "$action20na_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20na_outer_stream_label" "$(file_hash "$action20na_outer_stream")"
    if safe_stream "$action20na_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20na_outer_stream_label"
        if [[ -s "$action20na_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20na_outer_stream_label"
            cat "$action20na_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action20na_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20na_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20na_outer_stream_label" >&2
    return 97
}
require_one() {
    local action20na_outer_line=$1
    local action20na_outer_transcript=$2

    [[ "$(grep -Fxc "$action20na_outer_line" "$action20na_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action20na_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action20na_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action20na_outer_assertion_label" >&2
    return 1
}
generate_expected_checks() {
    local action20na_outer_expected=$1

    /bin/bash "$inspector" --expected-checks >"$action20na_outer_expected"
}
extract_actual_checks() {
    local action20na_outer_stdout=$1
    local action20na_outer_actual=$2

    sed -n 's/^action_20n_a_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action20na_outer_stdout" >"$action20na_outer_actual"
}
validate_success() {
    local action20na_outer_stdout=$1
    local action20na_outer_stderr=$2
    local action20na_outer_status=$3
    local action20na_outer_expected=$4
    local action20na_outer_actual=$5
    local action20na_outer_before_state
    local action20na_outer_after_state

    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action20na_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action20na_outer_stderr" || return 1
    validate_assert remote_line_count test \
        "$(line_count "$action20na_outer_stdout")" -eq "$expected_remote_line_count" || return 1
    validate_assert expected_checks_generated generate_expected_checks \
        "$action20na_outer_expected" || return 1
    validate_assert actual_checks_extracted extract_actual_checks \
        "$action20na_outer_stdout" "$action20na_outer_actual" || return 1
    validate_assert expected_check_count test \
        "$(line_count "$action20na_outer_expected")" -eq "$expected_check_count" || return 1
    validate_assert actual_check_count test \
        "$(line_count "$action20na_outer_actual")" -eq "$expected_check_count" || return 1
    validate_assert unique_check_count test \
        "$(LC_ALL=C sort -u "$action20na_outer_actual" | wc -l)" -eq "$expected_check_count" || return 1
    validate_assert ordered_check_contract diff -u \
        "$action20na_outer_expected" "$action20na_outer_actual" || return 1
    validate_assert false_checks_absent test \
        "$(grep -Ec '^action_20n_a_check_[a-z0-9_]+=false$' "$action20na_outer_stdout" || true)" -eq 0 || return 1
    validate_assert expected_count_value require_one "action_20n_a_value_expected_check_count=$expected_check_count" "$action20na_outer_stdout" || return 1
    validate_assert backup_path_value require_one "action_20n_a_value_backup_path=$expected_backup" "$action20na_outer_stdout" || return 1
    validate_assert main_hash_value require_one "action_20n_a_value_main_sha256=$expected_main_sha256" "$action20na_outer_stdout" || return 1
    validate_assert backup_main_hash_value require_one "action_20n_a_value_backup_main_sha256=$expected_backup_main_sha256" "$action20na_outer_stdout" || return 1
    validate_assert check_count_value require_one "action_20n_a_check_count=$expected_check_count" "$action20na_outer_stdout" || return 1
    validate_assert failed_check_count require_one 'action_20n_a_failed_check_count=0' "$action20na_outer_stdout" || return 1
    validate_assert first_failure_none require_one 'action_20n_a_first_failure=none' "$action20na_outer_stdout" || return 1
    for action20na_outer_marker in \
        helper_execution filesystem_mutations service_mutations vrrp_mutations \
        vip_mutations node_b_contacted; do
        validate_assert "${action20na_outer_marker}_false" require_one "action_20n_a_${action20na_outer_marker}=false" "$action20na_outer_stdout" || return 1
    done
    validate_assert remote_complete require_one 'action_20n_a_remote_complete=true' "$action20na_outer_stdout" || return 1
    action20na_outer_before_state=$(sed -n 's/^action_20n_a_value_before_state_sha256=//p' "$action20na_outer_stdout") || return 1
    action20na_outer_after_state=$(sed -n 's/^action_20n_a_value_after_state_sha256=//p' "$action20na_outer_stdout") || return 1
    validate_assert before_state_valid valid_sha256 "$action20na_outer_before_state" || return 1
    validate_assert after_state_valid valid_sha256 "$action20na_outer_after_state" || return 1
    validate_assert state_unchanged test \
        "$action20na_outer_before_state" = "$action20na_outer_after_state" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
run_transport() (
    local action20na_outer_ssh_binary=${CADDY_ACTION20NA_SSH_BINARY:-ssh}
    local action20na_outer_work_root
    local action20na_outer_stdout
    local action20na_outer_stderr
    local action20na_outer_expected
    local action20na_outer_actual
    local action20na_outer_status=0
    local action20na_outer_stream_failure=false

    if [[ "$action20na_outer_ssh_binary" != ssh ]]; then
        [[ "${CADDY_ACTION20NA_TEST_MODE:-}" = 1 && -x "$action20na_outer_ssh_binary" ]] || return 64
    fi
    action20na_outer_work_root=$(mktemp -d /tmp/caddy-action20n-a-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20na_outer_work_root"' EXIT
    action20na_outer_stdout=$action20na_outer_work_root/remote.stdout
    action20na_outer_stderr=$action20na_outer_work_root/remote.stderr
    action20na_outer_expected=$action20na_outer_work_root/expected
    action20na_outer_actual=$action20na_outer_work_root/actual
    install -m 0600 /dev/null "$action20na_outer_stdout" || return 1
    install -m 0600 /dev/null "$action20na_outer_stderr" || return 1
    "$action20na_outer_ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes \
        -o IdentitiesOnly=no -o HostKeyAlias="$expected_host_alias" \
        "$expected_target" 'cd / && sudo -n /bin/bash -s --' \
        <"$inspector" >"$action20na_outer_stdout" 2>"$action20na_outer_stderr" ||
        action20na_outer_status=$?
    emit_stream remote_stdout "$action20na_outer_stdout" || action20na_outer_stream_failure=true
    emit_stream remote_stderr "$action20na_outer_stderr" || action20na_outer_stream_failure=true
    printf '%s_remote_status=%s\n' "$prefix" "$action20na_outer_status"
    if [[ "$action20na_outer_stream_failure" = true ]]; then
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$action20na_outer_work_root" >&2
        return 97
    fi
    if [[ "$action20na_outer_status" -ne 0 ]]; then
        return "$action20na_outer_status"
    fi
    validate_success "$action20na_outer_stdout" "$action20na_outer_stderr" \
        "$action20na_outer_status" "$action20na_outer_expected" "$action20na_outer_actual" || return 97
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_helper_execution=false\n' "$prefix"
    printf '%s_filesystem_mutations=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_service_mutations=false\n' "$prefix"
    printf '%s_vrrp_mutations=false\n' "$prefix"
    printf '%s_vip_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates || exit $?
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION20NA_TEST_MODE:-}" = 1 ]] || exit 64
        run_transport || exit $?
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates || exit $?
        run_transport || exit $?
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
