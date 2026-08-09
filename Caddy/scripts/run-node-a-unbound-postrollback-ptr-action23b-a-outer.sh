#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23b_a_outer
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly inspector_sha256=00e949bd265d6f0e4040a24714707dc4ef85b267b1c89d43323ba0eb897af166
readonly regression_sha256=786e15a482a7d66bde3776b7ac1aaf0f4dca538b457a52985a4c5caae390529b
readonly restored_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly expected_backup=/var/backups/caddy-ha/action23b-node-a-unbound-a-records
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-a-unbound-postrollback-ptr-action23b-a.sh
readonly regression=$caddy_root/tests/action23b-a-node-a-postrollback-ptr-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action23ba_outer_hash_value=$1

    [[ ${#action23ba_outer_hash_value} -eq 64 ]] || return 1
    [[ "$action23ba_outer_hash_value" != *[!0-9a-f]* ]]
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
    local action23ba_outer_expected_hash=$1
    local action23ba_outer_source=$2

    [[ -f "$action23ba_outer_source" && ! -L "$action23ba_outer_source" &&
        -x "$action23ba_outer_source" ]] || return 1
    [[ "$(file_hash "$action23ba_outer_source")" == "$action23ba_outer_expected_hash" ]]
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|unbound-control[[:space:]]+reload|pihole[[:space:]]+restartdns|(^|[[:space:]])(install|mv|rm)[[:space:]]' \
        "$inspector"
}
run_gate() {
    local action23ba_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action23ba_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action23ba_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy \
        output_evidence_policy scalar_grep_policy portable_awk_policy \
        remote_cwd_policy read_only_contract inspector_self_test \
        regression
}
run_local_gates() {
    local action23ba_outer_skip_regression=$1

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
    run_gate read_only_contract read_only_contract || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
    if [[ "$action23ba_outer_skip_regression" == true ]]; then
        run_gate regression_test_bypass test "${CADDY_ACTION23BA_TEST_MODE:-}" == 1 || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action23ba_outer_stream=$1

    [[ "$(wc -c <"$action23ba_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action23ba_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action23ba_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action23ba_outer_stream"
}
emit_stream() {
    local action23ba_outer_stream_label=$1
    local action23ba_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action23ba_outer_stream_label" "$(wc -c <"$action23ba_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action23ba_outer_stream_label" "$(line_count "$action23ba_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action23ba_outer_stream_label" "$(file_hash "$action23ba_outer_stream")"
    if safe_stream "$action23ba_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action23ba_outer_stream_label"
        if [[ -s "$action23ba_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action23ba_outer_stream_label"
            cat "$action23ba_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action23ba_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action23ba_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action23ba_outer_stream_label" >&2
    return 97
}
require_one() {
    local action23ba_outer_line=$1
    local action23ba_outer_transcript=$2

    [[ "$(grep -Fxc "$action23ba_outer_line" "$action23ba_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action23ba_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action23ba_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action23ba_outer_assertion_label" >&2
    return 1
}
valid_ptr_classification() {
    case "$1" in
        authoritative_passthrough | local_hosts_override | local_pihole_override_unattributed)
            return 0
            ;;
        *) return 1 ;;
    esac
}
extract_actual_checks() {
    local action23ba_outer_stdout=$1
    local action23ba_outer_actual=$2

    sed -n 's/^action_23b_a_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action23ba_outer_stdout" >"$action23ba_outer_actual"
}
validate_success() {
    local action23ba_outer_stdout=$1
    local action23ba_outer_stderr=$2
    local action23ba_outer_status=$3
    local action23ba_outer_expected=$4
    local action23ba_outer_actual=$5
    local action23ba_outer_expected_count
    local action23ba_outer_before_state
    local action23ba_outer_after_state
    local action23ba_outer_ptr_key
    local action23ba_outer_ptr_value

    /bin/bash "$inspector" --expected-checks >"$action23ba_outer_expected" || return 1
    extract_actual_checks "$action23ba_outer_stdout" "$action23ba_outer_actual" || return 1
    action23ba_outer_expected_count=$(line_count "$action23ba_outer_expected")
    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action23ba_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action23ba_outer_stderr" || return 1
    validate_assert expected_count_positive test "$action23ba_outer_expected_count" -gt 0 || return 1
    validate_assert expected_count_unique test \
        "$(LC_ALL=C sort -u "$action23ba_outer_expected" | wc -l)" -eq "$action23ba_outer_expected_count" || return 1
    validate_assert actual_count_exact test \
        "$(line_count "$action23ba_outer_actual")" -eq "$action23ba_outer_expected_count" || return 1
    validate_assert actual_count_unique test \
        "$(LC_ALL=C sort -u "$action23ba_outer_actual" | wc -l)" -eq "$action23ba_outer_expected_count" || return 1
    validate_assert ordered_checks diff -u "$action23ba_outer_expected" "$action23ba_outer_actual" || return 1
    validate_assert false_checks_absent test \
        "$(grep -Ec '^action_23b_a_check_[a-z0-9_]+=false$' "$action23ba_outer_stdout" || true)" -eq 0 || return 1
    validate_assert check_count_value require_one "action_23b_a_check_count=$action23ba_outer_expected_count" "$action23ba_outer_stdout" || return 1
    validate_assert failed_check_count require_one 'action_23b_a_failed_check_count=0' "$action23ba_outer_stdout" || return 1
    validate_assert first_failure_none require_one 'action_23b_a_first_failure=none' "$action23ba_outer_stdout" || return 1
    validate_assert restored_hash_value require_one "action_23b_a_value_local_zone_sha256=$restored_sha256" "$action23ba_outer_stdout" || return 1
    validate_assert backup_path_value require_one "action_23b_a_value_backup_path=$expected_backup" "$action23ba_outer_stdout" || return 1
    for action23ba_outer_marker in filesystem_mutation service_mutation peer_ssh; do
        validate_assert "${action23ba_outer_marker}_false" require_one "action_23b_a_${action23ba_outer_marker}=false" "$action23ba_outer_stdout" || return 1
    done
    validate_assert dns_configuration_mutation_false require_one 'action_23b_a_dns_configuration_mutation=false' "$action23ba_outer_stdout" || return 1
    validate_assert pihole_cache_reset_false require_one 'action_23b_a_pihole_cache_reset=false' "$action23ba_outer_stdout" || return 1
    for action23ba_outer_ptr_key in dns_ptr4 dns_ptr6 node_ptr4 node_ptr6; do
        action23ba_outer_ptr_value=$(sed -n \
            "s/^action_23b_a_value_${action23ba_outer_ptr_key}_classification=//p" \
            "$action23ba_outer_stdout") || return 1
        validate_assert "${action23ba_outer_ptr_key}_classification_once" test \
            "$(grep -Ec "^action_23b_a_value_${action23ba_outer_ptr_key}_classification=" \
                "$action23ba_outer_stdout" || true)" -eq 1 || return 1
        validate_assert "${action23ba_outer_ptr_key}_classification_allowed" \
            valid_ptr_classification "$action23ba_outer_ptr_value" || return 1
    done
    validate_assert remote_complete require_one 'action_23b_a_remote_complete=true' "$action23ba_outer_stdout" || return 1
    action23ba_outer_before_state=$(sed -n 's/^action_23b_a_value_before_state_sha256=//p' "$action23ba_outer_stdout") || return 1
    action23ba_outer_after_state=$(sed -n 's/^action_23b_a_value_after_state_sha256=//p' "$action23ba_outer_stdout") || return 1
    validate_assert before_state_valid valid_sha256 "$action23ba_outer_before_state" || return 1
    validate_assert after_state_valid valid_sha256 "$action23ba_outer_after_state" || return 1
    validate_assert state_unchanged test "$action23ba_outer_before_state" = "$action23ba_outer_after_state" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action23ba_outer_cleanup_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action23ba_outer_cleanup_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_local_gates false
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --test-validate)
        [[ $# -eq 4 && "${CADDY_ACTION23BA_TEST_MODE:-}" == 1 ]] || exit 64
        validation_root=$(mktemp -d /tmp/caddy-action23b-a-validation.XXXXXX)
        readonly validation_root
        trap 'rm -rf -- "$validation_root"' EXIT
        if [[ "$4" -ne 0 ]]; then
            exit "$4"
        fi
        validate_success "$2" "$3" "$4" \
            "$validation_root/expected.checks" "$validation_root/actual.checks" || exit 97
        printf '%s_test_validation_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION23BA_TEST_MODE:-}" == 1 ]] || exit 64
        test_transport=true
        ;;
    "")
        [[ $# -eq 0 ]]
        test_transport=false
        ;;
    *) exit 64 ;;
esac

run_local_gates "$test_transport"
work_root=$(mktemp -d /tmp/caddy-action23b-a-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
stdout_capture=$work_root/remote.stdout
stderr_capture=$work_root/remote.stderr
expected_checks=$work_root/expected.checks
actual_checks=$work_root/actual.checks
readonly stdout_capture stderr_capture expected_checks actual_checks
remote_status=0

ssh_binary=${CADDY_ACTION23BA_SSH_BINARY:-ssh}
readonly ssh_binary
ssh_options=(
    -T -o BatchMode=yes -o ConnectTimeout=5
    -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes
    -o "HostKeyAlias=$expected_host_alias"
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
if [[ "$remote_status" -ne 0 ]]; then
    exit "$remote_status"
fi
validate_success "$stdout_capture" "$stderr_capture" "$remote_status" \
    "$expected_checks" "$actual_checks" || exit 97
printf '%s_ssh_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=%s\n' "$prefix" "$(if [[ "$test_transport" == true ]]; then printf false; else printf true; fi)"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
