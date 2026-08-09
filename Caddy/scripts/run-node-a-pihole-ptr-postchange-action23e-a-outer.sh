#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23e_a_outer
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly expected_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96
readonly expected_empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly inspector_sha256=ac2855a9d9d77438720ef0f072e1adacf1feb4cb21c31fbb06116dc9c60659f4
readonly regression_sha256=023660761e137360e5b5bc47d1d3eef75be564f9366011892e0677d20d5dce10
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly inspector=$script_directory/inspect-node-a-pihole-ptr-postchange-action23e-a.sh
readonly regression=$caddy_root/tests/action23e-a-node-a-postchange-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
valid_ftl_stat() {
    [[ "$1" =~ ^owner=[^|]+\|group=[^|]+\|uid=[0-9]+\|gid=[0-9]+\|mode_octal=[0-7]{3,4}\|mode_symbolic=.{10}\|size=[0-9]+\|inode=[0-9]+\|device=[0-9]+\|mtime=[0-9]+\|ctime=[0-9]+$ ]]
}
exact_ftl_metadata() {
    [[ "$1" =~ ^owner=pihole\|group=root\|uid=999\|gid=0\|mode_octal=664\|mode_symbolic=-rw-rw-r--\| ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
require_source() {
    local action23ea_outer_expected_hash=$1
    local action23ea_outer_source=$2

    [[ -f "$action23ea_outer_source" && ! -L "$action23ea_outer_source" &&
        -x "$action23ea_outer_source" ]] || return 1
    [[ "$(file_hash "$action23ea_outer_source")" == "$action23ea_outer_expected_hash" ]]
}
run_gate() {
    local action23ea_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action23ea_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action23ea_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        scalar_grep_policy portable_awk_policy remote_cwd_policy inspector_self_test \
        read_only_contract regression
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|pihole[[:space:]]+restartdns|(^|[[:space:]])(install|mv|rm)[[:space:]]' \
        "$inspector"
}
run_local_gates() {
    local action23ea_outer_skip_regression=$1

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
    run_gate scalar_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate remote_cwd_policy /bin/bash \
        "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    run_gate read_only_contract read_only_contract || return 1
    if [[ "$action23ea_outer_skip_regression" == true ]]; then
        run_gate regression_test_bypass test "${CADDY_ACTION23EA_TEST_MODE:-}" == 1 || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action23ea_outer_stream=$1

    [[ "$(wc -c <"$action23ea_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action23ea_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action23ea_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|WEBPASSWORD|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action23ea_outer_stream"
}
emit_stream() {
    local action23ea_outer_stream_label=$1
    local action23ea_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action23ea_outer_stream_label" "$(wc -c <"$action23ea_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action23ea_outer_stream_label" "$(line_count "$action23ea_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action23ea_outer_stream_label" "$(file_hash "$action23ea_outer_stream")"
    if safe_stream "$action23ea_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action23ea_outer_stream_label"
        if [[ -s "$action23ea_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action23ea_outer_stream_label"
            cat "$action23ea_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action23ea_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action23ea_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action23ea_outer_stream_label" >&2
    return 97
}
require_one() {
    local action23ea_outer_line=$1
    local action23ea_outer_transcript=$2

    [[ "$(grep -Fxc "$action23ea_outer_line" "$action23ea_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action23ea_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action23ea_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action23ea_outer_assertion_label" >&2
    return 1
}
extract_actual_checks() {
    local action23ea_outer_stdout=$1
    local action23ea_outer_actual=$2

    sed -n 's/^action_23e_a_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action23ea_outer_stdout" >"$action23ea_outer_actual"
}
validate_success() {
    local action23ea_outer_stdout=$1
    local action23ea_outer_stderr=$2
    local action23ea_outer_status=$3
    local action23ea_outer_expected=$4
    local action23ea_outer_actual=$5
    local action23ea_outer_expected_count
    local action23ea_outer_ftl_hash
    local action23ea_outer_domain_hash
    local action23ea_outer_custom_cname_hash
    local action23ea_outer_parser_hash
    local action23ea_outer_before_hash
    local action23ea_outer_after_hash
    local action23ea_outer_ftl_stat

    /bin/bash "$inspector" --expected-checks >"$action23ea_outer_expected" || return 1
    extract_actual_checks "$action23ea_outer_stdout" "$action23ea_outer_actual" || return 1
    action23ea_outer_expected_count=$(line_count "$action23ea_outer_expected")
    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action23ea_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action23ea_outer_stderr" || return 1
    validate_assert expected_count_positive test "$action23ea_outer_expected_count" -gt 0 || return 1
    validate_assert expected_count_unique test \
        "$(LC_ALL=C sort -u "$action23ea_outer_expected" | wc -l)" -eq "$action23ea_outer_expected_count" || return 1
    validate_assert actual_count_exact test \
        "$(line_count "$action23ea_outer_actual")" -eq "$action23ea_outer_expected_count" || return 1
    validate_assert actual_count_unique test \
        "$(LC_ALL=C sort -u "$action23ea_outer_actual" | wc -l)" -eq "$action23ea_outer_expected_count" || return 1
    validate_assert ordered_checks diff -u "$action23ea_outer_expected" "$action23ea_outer_actual" || return 1
    validate_assert false_checks_absent test \
        "$(grep -Ec '^action_23e_a_check_[a-z0-9_]+=false$' "$action23ea_outer_stdout" || true)" -eq 0 || return 1
    validate_assert check_count require_one "action_23e_a_check_count=$action23ea_outer_expected_count" "$action23ea_outer_stdout" || return 1
    validate_assert failed_count require_one 'action_23e_a_failed_check_count=0' "$action23ea_outer_stdout" || return 1
    validate_assert first_failure require_one 'action_23e_a_first_failure=none' "$action23ea_outer_stdout" || return 1
    action23ea_outer_ftl_stat=$(sed -n 's/^action_23e_a_value_ftl_stat=//p' "$action23ea_outer_stdout") || return 1
    validate_assert ftl_stat_once test \
        "$(grep -Ec '^action_23e_a_value_ftl_stat=' "$action23ea_outer_stdout" || true)" -eq 1 || return 1
    validate_assert ftl_stat_format valid_ftl_stat "$action23ea_outer_ftl_stat" || return 1
    validate_assert ftl_metadata_exact exact_ftl_metadata "$action23ea_outer_ftl_stat" || return 1
    action23ea_outer_ftl_hash=$(sed -n 's/^action_23e_a_value_ftl_sha256=//p' "$action23ea_outer_stdout") || return 1
    action23ea_outer_domain_hash=$(sed -n 's/^action_23e_a_value_domain_sha256=//p' "$action23ea_outer_stdout") || return 1
    action23ea_outer_custom_cname_hash=$(sed -n 's/^action_23e_a_value_custom_cname_sha256=//p' "$action23ea_outer_stdout") || return 1
    action23ea_outer_parser_hash=$(sed -n 's/^action_23e_a_value_parser_output_sha256=//p' "$action23ea_outer_stdout") || return 1
    action23ea_outer_before_hash=$(sed -n 's/^action_23e_a_value_before_state_sha256=//p' "$action23ea_outer_stdout") || return 1
    action23ea_outer_after_hash=$(sed -n 's/^action_23e_a_value_after_state_sha256=//p' "$action23ea_outer_stdout") || return 1
    validate_assert ftl_hash_valid valid_sha256 "$action23ea_outer_ftl_hash" || return 1
    validate_assert domain_hash_valid valid_sha256 "$action23ea_outer_domain_hash" || return 1
    validate_assert domain_hash_exact test "$action23ea_outer_domain_hash" = "$expected_domain_sha256" || return 1
    validate_assert custom_cname_hash_exact test "$action23ea_outer_custom_cname_hash" = "$expected_empty_sha256" || return 1
    validate_assert parser_hash_valid valid_sha256 "$action23ea_outer_parser_hash" || return 1
    validate_assert parser_hash_once test \
        "$(grep -Ec '^action_23e_a_value_parser_output_sha256=' "$action23ea_outer_stdout" || true)" -eq 1 || return 1
    validate_assert before_hash_valid valid_sha256 "$action23ea_outer_before_hash" || return 1
    validate_assert after_hash_valid valid_sha256 "$action23ea_outer_after_hash" || return 1
    validate_assert state_hashes_equal test "$action23ea_outer_before_hash" = "$action23ea_outer_after_hash" || return 1
    validate_assert filesystem_mutation_false require_one 'action_23e_a_filesystem_mutation=false' "$action23ea_outer_stdout" || return 1
    validate_assert service_mutation_false require_one 'action_23e_a_service_mutation=false' "$action23ea_outer_stdout" || return 1
    validate_assert pihole_restart_false require_one 'action_23e_a_pihole_restart=false' "$action23ea_outer_stdout" || return 1
    validate_assert action23b_rerun_false require_one 'action_23e_a_action_23b_rerun=false' "$action23ea_outer_stdout" || return 1
    validate_assert action23e_rerun_false require_one 'action_23e_a_action_23e_rerun=false' "$action23ea_outer_stdout" || return 1
    validate_assert peer_ssh_false require_one 'action_23e_a_peer_ssh=false' "$action23ea_outer_stdout" || return 1
    validate_assert remote_complete require_one 'action_23e_a_remote_complete=true' "$action23ea_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action23ea_outer_cleanup_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action23ea_outer_cleanup_status"
}

case "${1:-}" in
    --source-test)
        [[ $# -eq 1 ]]
        working_directory_approved
        require_source "$inspector_sha256" "$inspector"
        require_source "$regression_sha256" "$regression"
        grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$0"
        printf '%s_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION23EA_TEST_MODE:-}" == 1 ]] || exit 64
        test_transport=true
        ;;
    --test-validate)
        [[ $# -eq 4 && "${CADDY_ACTION23EA_TEST_MODE:-}" == 1 ]] || exit 64
        validation_root=$(mktemp -d /tmp/caddy-action23ea-validation.XXXXXX)
        readonly validation_root
        trap 'rm -rf -- "$validation_root"' EXIT
        [[ "$4" -eq 0 ]] || exit "$4"
        validate_success "$2" "$3" "$4" \
            "$validation_root/expected.checks" "$validation_root/actual.checks" || exit 97
        printf '%s_test_validation_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        test_transport=false
        ;;
    *) exit 64 ;;
esac

run_local_gates "$test_transport"
work_root=$(mktemp -d /tmp/caddy-action23ea-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
readonly stdout_capture=$work_root/remote.stdout
readonly stderr_capture=$work_root/remote.stderr
readonly expected_checks=$work_root/expected.checks
readonly actual_checks=$work_root/actual.checks
remote_status=0
ssh_binary=${CADDY_ACTION23EA_SSH_BINARY:-ssh}
readonly ssh_binary
ssh_options=(
    -T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1
    -o StrictHostKeyChecking=yes -o "HostKeyAlias=$expected_host_alias"
)
if "$ssh_binary" "${ssh_options[@]}" "$expected_target" \
    "cd / && sudo -n /bin/bash -s --" \
    <"$inspector" >"$stdout_capture" 2>"$stderr_capture"; then
    remote_status=0
else
    remote_status=$?
fi
emit_stream remote_stdout "$stdout_capture" || exit $?
emit_stream remote_stderr "$stderr_capture" || exit $?
[[ "$remote_status" -eq 0 ]] || exit "$remote_status"
validate_success "$stdout_capture" "$stderr_capture" "$remote_status" \
    "$expected_checks" "$actual_checks" || exit 97
printf '%s_ssh_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=%s\n' "$prefix" "$(if [[ "$test_transport" == true ]]; then printf false; else printf true; fi)"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
