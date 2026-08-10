#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28b_a_outer
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly inspector_sha256=a2b09a7ce5d9ba0481efd5d0eedd3a137ed7f29e4c7b691a102667c8195c66f3
readonly regression_sha256=8910b145d6979845adca9c61436f7c6d8be976d4b4eba490e117271b7ec91189
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly inspector=$script_directory/inspect-node-a-publisher-postinstall-action28b-a.sh
readonly regression=$caddy_root/tests/action28b-a-node-a-postinstall-regression.sh
readonly expected_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly expected_backup_path=/var/backups/caddy-ha/action28b-node-a-publisher
expected_outbound_root_metadata=994:990:750:4096:1785461698
readonly expected_retained_name=action17p-node-a-to-node-b-bootstrap
expected_retained_child_metadata=994:990:550:4096:1785461697
expected_retained_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
if [[ "${CADDY_ACTION28B_A_TEST_MODE:-}" == 1 ]]; then
    expected_outbound_root_metadata=${ACTION28B_A_FIXTURE_ROOT_METADATA:?}
    expected_retained_child_metadata=${ACTION28B_A_FIXTURE_CHILD_METADATA:?}
    expected_retained_tree_sha256=${ACTION28B_A_FIXTURE_TREE_SHA256:?}
fi
readonly expected_outbound_root_metadata expected_retained_child_metadata
readonly expected_retained_tree_sha256
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
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
    local action28b_a_outer_expected_hash=$1
    local action28b_a_outer_source=$2

    [[ -f "$action28b_a_outer_source" && ! -L "$action28b_a_outer_source" &&
        -x "$action28b_a_outer_source" ]] || return 1
    [[ "$(file_hash "$action28b_a_outer_source")" == "$action28b_a_outer_expected_hash" ]]
}
run_gate() {
    local action28b_a_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28b_a_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28b_a_outer_gate_label" >&2
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
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|(^|[[:space:]])(install|mv)[[:space:]]' \
        "$inspector"
}
run_local_gates() {
    local action28b_a_outer_skip_regression=$1

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
    if [[ "$action28b_a_outer_skip_regression" == true ]]; then
        run_gate regression test "$action28b_a_outer_skip_regression" == true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28b_a_outer_stream=$1

    [[ "$(wc -c <"$action28b_a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28b_a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28b_a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28b_a_outer_stream"
}
emit_stream() {
    local action28b_a_outer_stream_label=$1
    local action28b_a_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28b_a_outer_stream_label" \
        "$(wc -c <"$action28b_a_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28b_a_outer_stream_label" \
        "$(line_count "$action28b_a_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28b_a_outer_stream_label" \
        "$(file_hash "$action28b_a_outer_stream")"
    if safe_stream "$action28b_a_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28b_a_outer_stream_label"
        if [[ -s "$action28b_a_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28b_a_outer_stream_label"
            cat "$action28b_a_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28b_a_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action28b_a_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28b_a_outer_stream_label" >&2
    return 97
}
require_one() {
    local action28b_a_outer_line=$1
    local action28b_a_outer_transcript=$2

    [[ "$(grep -Fxc "$action28b_a_outer_line" "$action28b_a_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action28b_a_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28b_a_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28b_a_outer_assertion_label" >&2
    return 1
}
extract_actual_checks() {
    local action28b_a_outer_stdout=$1
    local action28b_a_outer_actual=$2

    sed -n 's/^action_28b_a_check_\([a-zA-Z0-9_]*\)=true$/\1/p' \
        "$action28b_a_outer_stdout" >"$action28b_a_outer_actual"
}
validate_inventory() {
    local action28b_a_outer_stdout=$1
    local action28b_a_outer_child_count=$2
    local action28b_a_outer_expected_hash=$3
    local action28b_a_outer_records=$4
    local action28b_a_outer_encoded
    local action28b_a_outer_index
    local action28b_a_outer_record

    : >"$action28b_a_outer_records" || return 1
    for ((action28b_a_outer_index = 1; action28b_a_outer_index <= action28b_a_outer_child_count; action28b_a_outer_index++)); do
        action28b_a_outer_encoded=$(sed -n \
            "s/^action_28b_a_value_outbound_child_$(printf '%04d' "$action28b_a_outer_index")_b64=//p" \
            "$action28b_a_outer_stdout") || return 1
        [[ -n "$action28b_a_outer_encoded" ]] || return 1
        [[ "$(grep -Ec "^action_28b_a_value_outbound_child_$(printf '%04d' "$action28b_a_outer_index")_b64=" "$action28b_a_outer_stdout" || true)" -eq 1 ]] || return 1
        action28b_a_outer_record=$(printf '%s' "$action28b_a_outer_encoded" | base64 -d) || return 1
        [[ "$(awk -F '|' '{ print NF }' <<<"$action28b_a_outer_record")" -eq 8 ]] || return 1
        [[ "${action28b_a_outer_record%%|*}" == "$(printf '%04d' "$action28b_a_outer_index")" ]] || return 1
        printf '%s\n' "$action28b_a_outer_record" >>"$action28b_a_outer_records" || return 1
    done
    [[ "$(grep -Ec '^action_28b_a_value_outbound_child_[0-9][0-9][0-9][0-9]_b64=' "$action28b_a_outer_stdout" || true)" -eq "$action28b_a_outer_child_count" ]] || return 1
    [[ "$(file_hash "$action28b_a_outer_records")" == "$action28b_a_outer_expected_hash" ]]
}
validate_success() {
    local action28b_a_outer_stdout=$1
    local action28b_a_outer_stderr=$2
    local action28b_a_outer_status=$3
    local action28b_a_outer_expected=$4
    local action28b_a_outer_actual=$5
    local action28b_a_outer_records=$6
    local action28b_a_outer_expected_count
    local action28b_a_outer_child_count
    local action28b_a_outer_inventory_hash
    local action28b_a_outer_sync_hash
    local action28b_a_outer_current_hash
    local action28b_a_outer_publisher_hash
    local action28b_a_outer_root_metadata
    local action28b_a_outer_retained_name
    local action28b_a_outer_retained_tree_hash
    local action28b_a_outer_expected_record

    /bin/bash "$inspector" --expected-checks >"$action28b_a_outer_expected" || return 1
    extract_actual_checks "$action28b_a_outer_stdout" "$action28b_a_outer_actual" || return 1
    action28b_a_outer_expected_count=$(line_count "$action28b_a_outer_expected") || return 1
    action28b_a_outer_child_count=$(sed -n 's/^action_28b_a_value_outbound_child_count=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_inventory_hash=$(sed -n 's/^action_28b_a_value_outbound_inventory_sha256=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_sync_hash=$(sed -n 's/^action_28b_a_value_sync_tree_sha256=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_current_hash=$(sed -n 's/^action_28b_a_value_current_tree_sha256=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_publisher_hash=$(sed -n 's/^action_28b_a_value_publisher_sha256=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_root_metadata=$(sed -n 's/^action_28b_a_value_outbound_root_metadata=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_retained_name=$(sed -n 's/^action_28b_a_value_retained_outbound_name=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_retained_tree_hash=$(sed -n 's/^action_28b_a_value_retained_outbound_tree_sha256=//p' "$action28b_a_outer_stdout") || return 1
    action28b_a_outer_expected_record=$(printf '0001|%s|%s|%s|%s|absent|regular_empty|absent' \
        "$(printf '%s\n' "$expected_retained_name" | base64 -w 0)" \
        "$(printf '%s' directory | base64 -w 0)" \
        "$expected_retained_child_metadata" "$expected_retained_tree_sha256") || return 1
    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action28b_a_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action28b_a_outer_stderr" || return 1
    validate_assert expected_count_positive test "$action28b_a_outer_expected_count" -gt 0 || return 1
    validate_assert expected_count_unique test \
        "$(LC_ALL=C sort -u "$action28b_a_outer_expected" | wc -l)" -eq "$action28b_a_outer_expected_count" || return 1
    validate_assert actual_count_exact test \
        "$(line_count "$action28b_a_outer_actual")" -eq "$action28b_a_outer_expected_count" || return 1
    validate_assert actual_count_unique test \
        "$(LC_ALL=C sort -u "$action28b_a_outer_actual" | wc -l)" -eq "$action28b_a_outer_expected_count" || return 1
    validate_assert ordered_checks diff -u "$action28b_a_outer_expected" "$action28b_a_outer_actual" || return 1
    validate_assert false_checks_absent test \
        "$(grep -Ec '^action_28b_a_check_[a-zA-Z0-9_]+=false$' "$action28b_a_outer_stdout" || true)" -eq 0 || return 1
    validate_assert check_count require_one "action_28b_a_check_count=$action28b_a_outer_expected_count" "$action28b_a_outer_stdout" || return 1
    validate_assert failed_count require_one 'action_28b_a_failed_check_count=0' "$action28b_a_outer_stdout" || return 1
    validate_assert first_failure require_one 'action_28b_a_first_failure=none' "$action28b_a_outer_stdout" || return 1
    validate_assert child_count_exact test "$action28b_a_outer_child_count" -eq 1 || return 1
    validate_assert publisher_hash_exact test "$action28b_a_outer_publisher_hash" = "$expected_publisher_sha256" || return 1
    validate_assert backup_path_exact require_one "action_28b_a_value_backup_path=$expected_backup_path" "$action28b_a_outer_stdout" || return 1
    validate_assert outbound_root_metadata_exact test "$action28b_a_outer_root_metadata" = "$expected_outbound_root_metadata" || return 1
    validate_assert retained_name_exact test "$action28b_a_outer_retained_name" = "$expected_retained_name" || return 1
    validate_assert retained_tree_hash_exact test "$action28b_a_outer_retained_tree_hash" = "$expected_retained_tree_sha256" || return 1
    validate_assert inventory_hash_valid valid_sha256 "$action28b_a_outer_inventory_hash" || return 1
    validate_assert sync_hash_valid valid_sha256 "$action28b_a_outer_sync_hash" || return 1
    validate_assert current_hash_valid valid_sha256 "$action28b_a_outer_current_hash" || return 1
    validate_assert inventory_exact validate_inventory "$action28b_a_outer_stdout" \
        "$action28b_a_outer_child_count" "$action28b_a_outer_inventory_hash" \
        "$action28b_a_outer_records" || return 1
    validate_assert retained_record_exact grep -Fqx "$action28b_a_outer_expected_record" "$action28b_a_outer_records" || return 1
    validate_assert stage_residue_zero require_one 'action_28b_a_value_install_stage_residue_count=0' "$action28b_a_outer_stdout" || return 1
    validate_assert publisher_not_invoked require_one 'action_28b_a_publisher_invoked=false' "$action28b_a_outer_stdout" || return 1
    validate_assert release_not_mutated require_one 'action_28b_a_release_mutated=false' "$action28b_a_outer_stdout" || return 1
    validate_assert services_not_mutated require_one 'action_28b_a_service_mutations=false' "$action28b_a_outer_stdout" || return 1
    validate_assert filesystem_not_mutated require_one 'action_28b_a_filesystem_mutations=false' "$action28b_a_outer_stdout" || return 1
    validate_assert node_b_not_contacted require_one 'action_28b_a_node_b_contacted=false' "$action28b_a_outer_stdout" || return 1
    validate_assert action28_not_rerun require_one 'action_28b_a_action_28_rerun=false' "$action28b_a_outer_stdout" || return 1
    validate_assert action28b_not_rerun require_one 'action_28b_a_action_28b_rerun=false' "$action28b_a_outer_stdout" || return 1
    validate_assert remote_acceptance require_one 'action_28b_a_acceptance=true' "$action28b_a_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action28b_a_outer_cleanup_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action28b_a_outer_cleanup_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_local_gates | wc -l)" -eq "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" ]]
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION28B_A_TEST_MODE:-}" == 1 ]] || exit 64
        test_transport=true
        ;;
    --test-validate)
        [[ $# -eq 4 && "${CADDY_ACTION28B_A_TEST_MODE:-}" == 1 ]] || exit 64
        validation_root=$(mktemp -d /tmp/caddy-action28b-a-validation.XXXXXX)
        readonly validation_root
        trap 'rm -rf -- "$validation_root"' EXIT
        [[ "$4" -eq 0 ]] || exit "$4"
        validate_success "$2" "$3" "$4" \
            "$validation_root/expected.checks" "$validation_root/actual.checks" \
            "$validation_root/inventory.records" || exit 97
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
work_root=$(mktemp -d /tmp/caddy-action28b-a-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
readonly stdout_capture=$work_root/remote.stdout
readonly stderr_capture=$work_root/remote.stderr
readonly expected_checks=$work_root/expected.checks
readonly actual_checks=$work_root/actual.checks
readonly inventory_records=$work_root/inventory.records
remote_status=0
ssh_binary=${CADDY_ACTION28B_A_SSH_BINARY:-ssh}
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
    "$expected_checks" "$actual_checks" "$inventory_records" || exit 97
printf '%s_ssh_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=%s\n' "$prefix" "$(if [[ "$test_transport" == true ]]; then printf false; else printf true; fi)"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_action_28b_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
