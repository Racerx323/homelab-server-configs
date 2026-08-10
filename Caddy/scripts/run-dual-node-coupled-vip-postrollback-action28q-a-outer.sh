#!/usr/bin/env bash
# ssh-local-evidence-contract-v1

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_a_outer
readonly node_b_state_sha256=9d835b805b21262b51c50749b5671223ced5f049991ffdf841054e413dec596b
readonly node_b_notifier_sha256=34a89df54cf44bb3a37203f21ee496f15390395b10b303a20cd70275d3b5f9e8
readonly node_a_state_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly predecessor_regression_sha256=8100844d9a8aa0ff8b7446da578a6d69737b81ecc824ce9743c4cb4429c239d6
readonly regression_sha256=39c9c2162e3b82bf350bfaaafcbc673f7a3b252eb5896828b082d762dacf608a
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly node_b_state=$script_directory/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_b_notifier=$script_directory/inspect-node-b-action28q-notifier-evidence.sh
readonly node_a_state=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly predecessor_regression=$caddy_root/tests/action28p-a-dual-node-postrelinquish-regression.sh
readonly regression=$caddy_root/tests/action28q-a-postrollback-convergence-regression.sh
evidence_root=${CADDY_ACTION28QA_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28q-a}
readonly evidence_root
ssh_binary=${CADDY_ACTION28QA_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary

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
valid_source() {
    local action28qa_outer_hash=$1
    local action28qa_outer_file=$2

    # conditional-validator-explicit-failures-begin
    [[ -f "$action28qa_outer_file" && ! -L "$action28qa_outer_file" && -x "$action28qa_outer_file" ]] || return 1
    [[ "$(file_hash "$action28qa_outer_file")" = "$action28qa_outer_hash" ]] || return 1
    # conditional-validator-explicit-failures-end
}
gate() {
    local action28qa_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28qa_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28qa_outer_label" >&2
    return 1
}
validation() {
    local action28qa_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28qa_outer_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28qa_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory node_b_state_source node_b_notifier_source node_a_state_source \
        predecessor_regression_source regression_source syntax node_b_state_self_test \
        node_b_notifier_self_test node_a_state_self_test predecessor_regression regression \
        shellcheck canonical_format collision_policy conditional_policy \
        multifile_grep_policy portable_awk_policy root_cwd_policy ssh_evidence_policy \
        accepted_live_hash_policy evidence_root_created evidence_directory_created \
        node_b_state_read_only node_b_notifier_read_only node_a_state_read_only
}
emit_test_local_gates() {
    local action28qa_outer_test_gate

    [[ "${CADDY_ACTION28QA_TEST_MODE:-}" = 1 ]] || return 1
    while IFS= read -r action28qa_outer_test_gate; do
        case "$action28qa_outer_test_gate" in
            evidence_root_created | evidence_directory_created | node_b_state_read_only | \
                node_b_notifier_read_only | node_a_state_read_only) continue ;;
        esac
        printf '%s_gate_%s=true\n' "$prefix" "$action28qa_outer_test_gate"
    done < <(expected_local_gates)
}
safe_stream() {
    local action28qa_outer_stream=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$action28qa_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28qa_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28qa_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|Cookie:|WEBPASSWORD' \
        "$action28qa_outer_stream" || return 1
    # conditional-validator-explicit-failures-end
}
emit_stream() {
    local action28qa_outer_label=$1
    local action28qa_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28qa_outer_label" \
        "$(wc -c <"$action28qa_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28qa_outer_label" \
        "$(line_count "$action28qa_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28qa_outer_label" \
        "$(file_hash "$action28qa_outer_stream")"
    if ! safe_stream "$action28qa_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28qa_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28qa_outer_label"
    if [[ -s "$action28qa_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action28qa_outer_label"
        cat "$action28qa_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action28qa_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28qa_outer_label"
    fi
}
require_one() {
    local action28qa_outer_line=$1
    local action28qa_outer_file=$2

    [[ "$(grep -Fxc "$action28qa_outer_line" "$action28qa_outer_file" || true)" -eq 1 ]]
}
validate_transcript() {
    local action28qa_outer_name=$1
    local action28qa_outer_source=$2
    local action28qa_outer_record_prefix=$3
    local action28qa_outer_stdout=$4
    local action28qa_outer_stderr=$5
    local action28qa_outer_status=$6
    local action28qa_outer_expected
    local action28qa_outer_actual

    # conditional-validator-explicit-failures-begin
    validation "${action28qa_outer_name}_status_zero" test "$action28qa_outer_status" -eq 0 || return 1
    validation "${action28qa_outer_name}_stderr_empty" test ! -s "$action28qa_outer_stderr" || return 1
    action28qa_outer_expected=$(/bin/bash "$action28qa_outer_source" --expected-checks) || return 1
    action28qa_outer_actual=$(sed -n \
        "s/^${action28qa_outer_record_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28qa_outer_stdout") || return 1
    validation "${action28qa_outer_name}_ordered_checks" test \
        "$action28qa_outer_actual" = "$action28qa_outer_expected" || return 1
    validation "${action28qa_outer_name}_check_count" require_one "${action28qa_outer_record_prefix}_check_count=$(printf '%s\n' "$action28qa_outer_expected" | wc -l)" "$action28qa_outer_stdout" || return 1
    validation "${action28qa_outer_name}_first_failure_none" require_one "${action28qa_outer_record_prefix}_first_failure=none" "$action28qa_outer_stdout" || return 1
    validation "${action28qa_outer_name}_acceptance_true" require_one "${action28qa_outer_record_prefix}_acceptance=true" "$action28qa_outer_stdout" || return 1
    validation "${action28qa_outer_name}_mutation_false" require_one "${action28qa_outer_record_prefix}_mutation=false" "$action28qa_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
validate_node_b_state() {
    validate_transcript node_b_state "$node_b_state" action_28p_a_node_b "$@" || return 1
    # conditional-validator-explicit-failures-begin
    validation node_b_action_28p_not_rerun require_one 'action_28p_a_node_b_action_28p_rerun=false' "$1" || return 1
    # conditional-validator-explicit-failures-end
}
validate_node_b_notifier() {
    validate_transcript node_b_notifier "$node_b_notifier" action_28q_a_notifier "$@" || return 1
    # conditional-validator-explicit-failures-begin
    validation notifier_master_transition_observed require_one 'action_28q_a_notifier_master_transition_observed=true' "$1" || return 1
    validation notifier_backup_transition_observed require_one 'action_28q_a_notifier_backup_transition_observed=true' "$1" || return 1
    validation notifier_backup_delivery_failure_observed require_one 'action_28q_a_notifier_backup_notification_delivery_failed=true' "$1" || return 1
    # conditional-validator-explicit-failures-end
}
validate_node_a_state() {
    validate_transcript node_a_state "$node_a_state" action_28m_b "$@" || return 1
    # conditional-validator-explicit-failures-begin
    validation node_a_action_28m_not_rerun require_one 'action_28m_b_action_28m_rerun=false' "$1" || return 1
    validation node_a_action_28m_a_not_rerun require_one 'action_28m_b_action_28m_a_rerun=false' "$1" || return 1
    # conditional-validator-explicit-failures-end
}
run_local_gates() {
    # conditional-validator-explicit-failures-begin
    gate working_directory working_directory_approved || return 1
    gate node_b_state_source valid_source "$node_b_state_sha256" "$node_b_state" || return 1
    gate node_b_notifier_source valid_source "$node_b_notifier_sha256" "$node_b_notifier" || return 1
    gate node_a_state_source valid_source "$node_a_state_sha256" "$node_a_state" || return 1
    gate predecessor_regression_source valid_source "$predecessor_regression_sha256" \
        "$predecessor_regression" || return 1
    gate regression_source valid_source "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$node_b_notifier" "$regression" "$0" || return 1
    gate node_b_state_self_test /bin/bash "$node_b_state" --self-test || return 1
    gate node_b_notifier_self_test /bin/bash "$node_b_notifier" --self-test || return 1
    gate node_a_state_self_test /bin/bash "$node_a_state" --self-test || return 1
    gate predecessor_regression /bin/bash "$predecessor_regression" || return 1
    gate regression /bin/bash "$regression" || return 1
    gate shellcheck shellcheck "$node_b_notifier" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$node_b_notifier" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$node_b_notifier" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$node_b_notifier" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" \
        --check "$node_b_notifier" "$regression" "$0" || return 1
    gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" \
        --check "$0" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "$0" || return 1
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" \
        --check || return 1
    # conditional-validator-explicit-failures-end
}
run_remote() {
    local action28qa_outer_phase=$1
    local action28qa_outer_target=$2
    local action28qa_outer_alias=$3
    local action28qa_outer_source=$4
    local action28qa_outer_stdout=$evidence_directory/${action28qa_outer_phase}.stdout
    local action28qa_outer_stderr=$evidence_directory/${action28qa_outer_phase}.stderr
    local action28qa_outer_status_file=$evidence_directory/${action28qa_outer_phase}.status
    local action28qa_outer_status=0

    install -m 0600 /dev/null "$action28qa_outer_stdout"
    install -m 0600 /dev/null "$action28qa_outer_stderr"
    install -m 0600 /dev/null "$action28qa_outer_status_file"
    chmod 0600 "$action28qa_outer_stdout" "$action28qa_outer_stderr" \
        "$action28qa_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/home/aaron/.ssh/known_hosts \
        -o HostKeyAlias="$action28qa_outer_alias" "$action28qa_outer_target" \
        "cd / && sudo -n /bin/bash -s --" <"$action28qa_outer_source" \
        >"$action28qa_outer_stdout" 2>"$action28qa_outer_stderr" || action28qa_outer_status=$?
    printf '%s\n' "$action28qa_outer_status" >"$action28qa_outer_status_file"
    case "$action28qa_outer_phase" in
        node_b_state_read_only)
            emit_stream remote_stdout_node_b_state "$action28qa_outer_stdout" || return 97
            emit_stream remote_stderr_node_b_state "$action28qa_outer_stderr" || return 97
            ;;
        node_b_notifier_read_only)
            emit_stream remote_stdout_node_b_notifier "$action28qa_outer_stdout" || return 97
            emit_stream remote_stderr_node_b_notifier "$action28qa_outer_stderr" || return 97
            ;;
        node_a_state_read_only)
            emit_stream remote_stdout_node_a_state "$action28qa_outer_stdout" || return 97
            emit_stream remote_stderr_node_a_state "$action28qa_outer_stderr" || return 97
            ;;
        *) return 64 ;;
    esac
    printf '%s_%s_status=%s\n' "$prefix" "$action28qa_outer_phase" "$action28qa_outer_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_local_gates | wc -l)" -eq "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" ]]
        grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$0"
        while IFS= read -r action28qa_outer_self_test_gate; do
            gate "$action28qa_outer_self_test_gate" true
        done < <(expected_local_gates)
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --transcript-test)
        [[ "${CADDY_ACTION28QA_TEST_MODE:-}" = 1 && $# -eq 10 ]]
        validate_node_b_state "$2" "$3" "$4"
        validate_node_b_notifier "$5" "$6" "$7"
        validate_node_a_state "$8" "$9" "${10}"
        exit 0
        ;;
    "") ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION28QA_SKIP_LOCAL_GATES:-false}" = true ]]; then
    emit_test_local_gates
else
    run_local_gates
fi
gate evidence_root_created install -d -m 0700 "$evidence_root"
evidence_directory=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly evidence_directory
chmod 0700 "$evidence_directory"
gate evidence_directory_created test -d "$evidence_directory"

run_remote node_b_state_read_only pi@10.1.0.54 pihole00.local.theama.co "$node_b_state"
run_remote node_b_notifier_read_only pi@10.1.0.54 pihole00.local.theama.co "$node_b_notifier"
run_remote node_a_state_read_only pi@10.1.0.53 pihole0.local.theama.co "$node_a_state"

node_b_state_status=$(<"$evidence_directory/node_b_state_read_only.status")
node_b_notifier_status=$(<"$evidence_directory/node_b_notifier_read_only.status")
node_a_state_status=$(<"$evidence_directory/node_a_state_read_only.status")
gate node_b_state_read_only validate_node_b_state \
    "$evidence_directory/node_b_state_read_only.stdout" \
    "$evidence_directory/node_b_state_read_only.stderr" "$node_b_state_status"
gate node_b_notifier_read_only validate_node_b_notifier \
    "$evidence_directory/node_b_notifier_read_only.stdout" \
    "$evidence_directory/node_b_notifier_read_only.stderr" "$node_b_notifier_status"
gate node_a_state_read_only validate_node_a_state \
    "$evidence_directory/node_a_state_read_only.stdout" \
    "$evidence_directory/node_a_state_read_only.stderr" "$node_a_state_status"
printf '%s_node_contact_order=node_b_state_then_node_b_notifier_then_node_a_state\n' "$prefix"
printf '%s_action_28q_rerun=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
