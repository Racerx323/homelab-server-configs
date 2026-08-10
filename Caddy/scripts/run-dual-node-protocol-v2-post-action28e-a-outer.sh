#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_a_outer
readonly inspector_sha256=7f3818a125b5201b9330234d3ffa4a77a98eeba4852d20eba3ce3399270e5a2c
readonly regression_sha256=84b3c899bf8d20c354376161285fb6082ea86784376354a01835426f0f52c74f
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly inspector=$script_directory/inspect-protocol-v2-post-action28e-a.sh
readonly regression=$caddy_root/tests/action28e-a-dual-node-post-execution-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
# Invoked indirectly by validate_assert.
# shellcheck disable=SC2317
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
    local action28e_a_outer_expected_hash=$1
    local action28e_a_outer_source=$2

    [[ -f "$action28e_a_outer_source" && ! -L "$action28e_a_outer_source" &&
        -x "$action28e_a_outer_source" ]] || return 1
    [[ "$(file_hash "$action28e_a_outer_source")" = "$action28e_a_outer_expected_hash" ]]
}
run_gate() {
    local action28e_a_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28e_a_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28e_a_outer_label" >&2
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
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|(^|[[:space:]])(install|mv|cp|chmod|chown|rsync)[[:space:]]' \
        "$inspector"
}
run_local_gates() {
    local action28e_a_outer_skip_regression=$1

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
    if [[ "$action28e_a_outer_skip_regression" == true ]]; then
        run_gate regression true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28e_a_outer_stream=$1

    [[ "$(wc -c <"$action28e_a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28e_a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28e_a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28e_a_outer_stream"
}
emit_stream() {
    local action28e_a_outer_label=$1
    local action28e_a_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28e_a_outer_label" "$(wc -c <"$action28e_a_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28e_a_outer_label" "$(line_count "$action28e_a_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28e_a_outer_label" "$(file_hash "$action28e_a_outer_stream")"
    if safe_stream "$action28e_a_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28e_a_outer_label"
        if [[ -s "$action28e_a_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28e_a_outer_label"
            cat "$action28e_a_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28e_a_outer_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action28e_a_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28e_a_outer_label" >&2
    return 97
}
require_one() {
    local action28e_a_outer_line=$1
    local action28e_a_outer_transcript=$2

    [[ "$(grep -Fxc "$action28e_a_outer_line" "$action28e_a_outer_transcript" || true)" -eq 1 ]]
}
extract_value() {
    local action28e_a_outer_key=$1
    local action28e_a_outer_transcript=$2
    local action28e_a_outer_value

    action28e_a_outer_value=$(sed -n "s/^action_28e_a_value_${action28e_a_outer_key}=//p" "$action28e_a_outer_transcript") || return 1
    [[ "$(grep -Ec "^action_28e_a_value_${action28e_a_outer_key}=" "$action28e_a_outer_transcript" || true)" -eq 1 ]] || return 1
    printf '%s\n' "$action28e_a_outer_value"
}
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
validate_assert() {
    local action28e_a_outer_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28e_a_outer_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28e_a_outer_label" >&2
    return 1
}
validate_node() {
    local action28e_a_outer_role=$1
    local action28e_a_outer_stdout=$2
    local action28e_a_outer_stderr=$3
    local action28e_a_outer_status=$4
    local action28e_a_outer_expected=$5
    local action28e_a_outer_actual=$6
    local action28e_a_outer_expected_count
    local action28e_a_outer_candidate_count
    local action28e_a_outer_candidate_state
    local action28e_a_outer_candidate_tree
    local action28e_a_outer_candidate_metadata
    local action28e_a_outer_candidate_request
    local action28e_a_outer_candidate_complete
    local action28e_a_outer_candidate_pending

    /bin/bash "$inspector" --expected-checks >"$action28e_a_outer_expected" || return 1
    sed -n 's/^action_28e_a_check_\([a-zA-Z0-9_]*\)=true$/\1/p' \
        "$action28e_a_outer_stdout" >"$action28e_a_outer_actual"
    action28e_a_outer_expected_count=$(line_count "$action28e_a_outer_expected") || return 1
    validate_assert "${action28e_a_outer_role}_status_zero" test "$action28e_a_outer_status" -eq 0 || return 1
    validate_assert "${action28e_a_outer_role}_stderr_empty" test ! -s "$action28e_a_outer_stderr" || return 1
    validate_assert "${action28e_a_outer_role}_expected_unique" test \
        "$(LC_ALL=C sort -u "$action28e_a_outer_expected" | wc -l)" -eq "$action28e_a_outer_expected_count" || return 1
    validate_assert "${action28e_a_outer_role}_actual_count" test \
        "$(line_count "$action28e_a_outer_actual")" -eq "$action28e_a_outer_expected_count" || return 1
    validate_assert "${action28e_a_outer_role}_actual_unique" test \
        "$(LC_ALL=C sort -u "$action28e_a_outer_actual" | wc -l)" -eq "$action28e_a_outer_expected_count" || return 1
    validate_assert "${action28e_a_outer_role}_ordered_checks" diff -u \
        "$action28e_a_outer_expected" "$action28e_a_outer_actual" || return 1
    validate_assert "${action28e_a_outer_role}_false_absent" test \
        "$(grep -Ec '^action_28e_a_check_[a-zA-Z0-9_]+=false$' "$action28e_a_outer_stdout" || true)" -eq 0 || return 1
    validate_assert "${action28e_a_outer_role}_role_exact" require_one \
        "action_28e_a_value_role=$action28e_a_outer_role" "$action28e_a_outer_stdout" || return 1
    validate_assert "${action28e_a_outer_role}_check_count" require_one \
        "action_28e_a_check_count=$action28e_a_outer_expected_count" "$action28e_a_outer_stdout" || return 1
    validate_assert "${action28e_a_outer_role}_failed_zero" require_one \
        'action_28e_a_failed_check_count=0' "$action28e_a_outer_stdout" || return 1
    validate_assert "${action28e_a_outer_role}_first_failure_none" require_one \
        'action_28e_a_first_failure=none' "$action28e_a_outer_stdout" || return 1
    for action28e_a_outer_marker in \
        publisher_invoked receiver_invoked finalizer_invoked cleanup_executed \
        service_mutations filesystem_mutations lsyncd_enabled \
        reconciliation_executed remote_delete_executed; do
        validate_assert "${action28e_a_outer_role}_${action28e_a_outer_marker}_false" require_one \
            "action_28e_a_${action28e_a_outer_marker}=false" "$action28e_a_outer_stdout" || return 1
    done
    validate_assert "${action28e_a_outer_role}_remote_acceptance" require_one \
        'action_28e_a_acceptance=true' "$action28e_a_outer_stdout" || return 1
    action28e_a_outer_candidate_count=$(extract_value candidate_count "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_state=$(extract_value candidate_state "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_tree=$(extract_value candidate_tree_sha256 "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_metadata=$(extract_value candidate_metadata "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_request=$(extract_value candidate_request_state "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_complete=$(extract_value candidate_complete_state "$action28e_a_outer_stdout") || return 1
    action28e_a_outer_candidate_pending=$(extract_value candidate_pending_state "$action28e_a_outer_stdout") || return 1
    validate_assert "${action28e_a_outer_role}_candidate_count_format" test \
        "$(printf '%s' "$action28e_a_outer_candidate_count" | grep -Ec '^[01]$')" -eq 1 || return 1
    if [[ "$action28e_a_outer_candidate_count" -eq 0 ]]; then
        validate_assert "${action28e_a_outer_role}_candidate_state_absent" test \
            "$action28e_a_outer_candidate_state" = absent || return 1
        validate_assert "${action28e_a_outer_role}_candidate_tree_absent" test \
            "$action28e_a_outer_candidate_tree" = absent || return 1
        validate_assert "${action28e_a_outer_role}_candidate_metadata_absent" test \
            "$action28e_a_outer_candidate_metadata" = absent || return 1
        validate_assert "${action28e_a_outer_role}_candidate_request_absent" test \
            "$action28e_a_outer_candidate_request" = absent || return 1
        validate_assert "${action28e_a_outer_role}_candidate_complete_absent" test \
            "$action28e_a_outer_candidate_complete" = absent || return 1
        validate_assert "${action28e_a_outer_role}_candidate_pending_absent" test \
            "$action28e_a_outer_candidate_pending" = absent || return 1
    else
        validate_assert "${action28e_a_outer_role}_candidate_tree_hash" valid_sha256 \
            "$action28e_a_outer_candidate_tree" || return 1
        validate_assert "${action28e_a_outer_role}_candidate_metadata_format" test \
            "$(printf '%s' "$action28e_a_outer_candidate_metadata" | grep -Ec '^[0-9]+:[0-9]+:550:[0-9]+:[0-9]+$')" -eq 1 || return 1
        validate_assert "${action28e_a_outer_role}_candidate_request_regular_empty" test \
            "$action28e_a_outer_candidate_request" = regular_empty || return 1
        validate_assert "${action28e_a_outer_role}_candidate_pending_absent" test \
            "$action28e_a_outer_candidate_pending" = absent || return 1
        if [[ "$action28e_a_outer_role" == node-a ]]; then
            validate_assert node-a_candidate_complete_absent test \
                "$action28e_a_outer_candidate_complete" = absent || return 1
        else
            validate_assert node-b_candidate_complete_regular_empty test \
                "$action28e_a_outer_candidate_complete" = regular_empty || return 1
        fi
    fi
}
classify_pair() {
    local action28e_a_outer_node_a_stdout=$1
    local action28e_a_outer_node_b_stdout=$2
    local action28e_a_outer_a_state
    local action28e_a_outer_b_state
    local action28e_a_outer_a_count
    local action28e_a_outer_b_count
    local action28e_a_outer_key
    local action28e_a_outer_a_value
    local action28e_a_outer_b_value

    action28e_a_outer_a_state=$(extract_value candidate_state "$action28e_a_outer_node_a_stdout") || return 1
    action28e_a_outer_b_state=$(extract_value candidate_state "$action28e_a_outer_node_b_stdout") || return 1
    action28e_a_outer_a_count=$(extract_value candidate_count "$action28e_a_outer_node_a_stdout") || return 1
    action28e_a_outer_b_count=$(extract_value candidate_count "$action28e_a_outer_node_b_stdout") || return 1
    validate_assert candidate_counts_numeric test \
        "$(printf '%s\n%s\n' "$action28e_a_outer_a_count" "$action28e_a_outer_b_count" | grep -Ec '^[01]$')" -eq 2 || return 1
    if [[ "$action28e_a_outer_a_state" == sender_ready &&
        "$action28e_a_outer_b_state" == receiver_finalized &&
        "$action28e_a_outer_a_count" -eq 1 && "$action28e_a_outer_b_count" -eq 1 ]]; then
        for action28e_a_outer_key in \
            candidate_revision candidate_parent candidate_manifest_sha256 \
            candidate_payload_manifest_sha256; do
            action28e_a_outer_a_value=$(extract_value "$action28e_a_outer_key" "$action28e_a_outer_node_a_stdout") || return 1
            action28e_a_outer_b_value=$(extract_value "$action28e_a_outer_key" "$action28e_a_outer_node_b_stdout") || return 1
            validate_assert "pair_${action28e_a_outer_key}_matches" test \
                "$action28e_a_outer_a_value" = "$action28e_a_outer_b_value" || return 1
        done
        action28e_a_outer_a_value=$(extract_value candidate_revision "$action28e_a_outer_node_a_stdout") || return 1
        action28e_a_outer_b_value=$(extract_value candidate_parent "$action28e_a_outer_node_a_stdout") || return 1
        validate_assert pair_revision_safe test \
            "$(printf '%s' "$action28e_a_outer_a_value" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1 || return 1
        validate_assert pair_parent_safe test \
            "$(printf '%s' "$action28e_a_outer_b_value" | grep -Ec '^[A-Za-z0-9][A-Za-z0-9._-]*$')" -eq 1 || return 1
        printf '%s_value_classification=receiver_finalized\n' "$prefix"
        printf '%s_value_revision=%s\n' "$prefix" "$action28e_a_outer_a_value"
        printf '%s_acceptance=true\n' "$prefix"
        return 0
    fi
    if [[ "$action28e_a_outer_a_state" == absent &&
        "$action28e_a_outer_b_state" == absent &&
        "$action28e_a_outer_a_count" -eq 0 && "$action28e_a_outer_b_count" -eq 0 ]]; then
        printf '%s_value_classification=absent\n' "$prefix"
    else
        printf '%s_value_classification=partial\n' "$prefix"
    fi
    printf '%s_acceptance=false\n' "$prefix"
    return 97
}
cleanup() {
    local action28e_a_outer_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action28e_a_outer_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-validate)
        [[ $# -eq 7 && "${CADDY_ACTION28E_A_TEST_MODE:-}" == 1 ]]
        validation_root=$(mktemp -d /tmp/action28e-a-validation.XXXXXX)
        readonly validation_root
        trap 'rm -rf -- "$validation_root"' EXIT
        validate_node node-b "$2" "$3" "$4" \
            "$validation_root/node-b.expected" "$validation_root/node-b.actual" || exit 97
        validate_node node-a "$5" "$6" "$7" \
            "$validation_root/node-a.expected" "$validation_root/node-a.actual" || exit 97
        classify_pair "$5" "$2" || exit 97
        printf '%s_test_validation_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] ;;
    *) exit 64 ;;
esac

run_local_gates false
work_root=$(mktemp -d /tmp/action28e-a-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
for action28e_a_outer_name in node-b.stdout node-b.stderr node-a.stdout node-a.stderr; do
    : >"$work_root/$action28e_a_outer_name"
done
ssh_binary=${CADDY_ACTION28E_A_SSH_BINARY:-ssh}
readonly ssh_binary
ssh_options=(-T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes)
node_b_status=0
"$ssh_binary" "${ssh_options[@]}" -o "HostKeyAlias=$node_b_alias" "$node_b_target" \
    "cd / && sudo -n /bin/bash -s -- node-b" <"$inspector" \
    >"$work_root/node-b.stdout" 2>"$work_root/node-b.stderr" || node_b_status=$?
readonly node_b_status
emit_stream node_b_stdout "$work_root/node-b.stdout" || exit $?
emit_stream node_b_stderr "$work_root/node-b.stderr" || exit $?
validate_node node-b "$work_root/node-b.stdout" "$work_root/node-b.stderr" "$node_b_status" \
    "$work_root/node-b.expected" "$work_root/node-b.actual" || exit 97
node_a_status=0
"$ssh_binary" "${ssh_options[@]}" -o "HostKeyAlias=$node_a_alias" "$node_a_target" \
    "cd / && sudo -n /bin/bash -s -- node-a" <"$inspector" \
    >"$work_root/node-a.stdout" 2>"$work_root/node-a.stderr" || node_a_status=$?
readonly node_a_status
emit_stream node_a_stdout "$work_root/node-a.stdout" || exit $?
emit_stream node_a_stderr "$work_root/node-a.stderr" || exit $?
validate_node node-a "$work_root/node-a.stdout" "$work_root/node-a.stderr" "$node_a_status" \
    "$work_root/node-a.expected" "$work_root/node-a.actual" || exit 97
classify_pair "$work_root/node-a.stdout" "$work_root/node-b.stdout" || exit 97
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_action_28e_rerun=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
