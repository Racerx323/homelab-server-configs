#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_28r_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly transaction_sha256=3ee0fffaee6b87f81ecb86d530d46b9b8df1b88ddee8827d13cfc5b8af702c7a
readonly node_b_inspector_sha256=9d835b805b21262b51c50749b5671223ced5f049991ffdf841054e413dec596b
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly observation_start_sha256=e2ee99023e5050fd98cad86185dd29ff55fe37771906e33ffa06da5493fc3bd5
readonly convergence_inspector_sha256=b310bca423a74d64706c3d23b99bba683bf8c60066d0cac5ccbfbe9b3839c113
readonly accepted_action_28q_a_sha256=490ef116ed10d5082d0a741c1a0e7a8d27691e2549fa627f0172c0410cf90816
readonly regression_sha256=caf0157369f44a431ee8b4464e28497ba4b3d7abca68dcda8f7405abf2384347
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/acquire-node-a-coupled-vips-action28r.sh
readonly node_b_inspector=$script_directory/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_inspector=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly observation_start=$script_directory/capture-node-b-coupled-vip-observation-start-action28r.sh
readonly convergence_inspector=$script_directory/inspect-coupled-vip-convergence-action28r.sh
readonly accepted_action_28q_a=$script_directory/run-dual-node-coupled-vip-postrollback-action28q-a-outer.sh
readonly regression=$caddy_root/tests/action28r-node-a-coupled-vip-acquisition-regression.sh
evidence_root=${CADDY_ACTION28R_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28r}
readonly evidence_root
ssh_binary=${CADDY_ACTION28R_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
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
evidence_metadata_expected() {
    local action28r_outer_path=$1

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$action28r_outer_path")" = root:root:700 ]]
    else
        [[ "$(stat -c '%U:%G:%a' "$action28r_outer_path")" = aaron:aaron:700 ]]
    fi
}
valid_source() {
    local action28r_outer_hash=$1
    local action28r_outer_file=$2

    [[ -f "$action28r_outer_file" && ! -L "$action28r_outer_file" && -x "$action28r_outer_file" ]] || return 1
    [[ "$(file_hash "$action28r_outer_file")" = "$action28r_outer_hash" ]]
}
gate() {
    local action28r_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28r_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28r_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_source node_b_inspector_source \
        node_a_inspector_source observation_start_source convergence_inspector_source \
        accepted_action_28q_a_source regression_source syntax transaction_self_test \
        node_b_inspector_self_test node_a_inspector_self_test observation_start_self_test \
        convergence_inspector_self_test regression \
        shellcheck canonical_format collision_policy conditional_policy \
        multifile_grep_policy portable_awk_policy root_cwd_policy ssh_evidence_policy \
        accepted_live_hash_policy evidence_root_created evidence_directory_created \
        node_b_preflight node_a_preflight node_b_observation_start \
        node_b_observation_cursor_safe node_a_transaction \
        node_b_convergence node_b_final_state node_a_final_state
}
safe_stream() {
    local action28r_outer_stream=$1

    [[ "$(wc -c <"$action28r_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28r_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28r_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action28r_outer_stream"
}
emit_stream() {
    local action28r_outer_label=$1
    local action28r_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28r_outer_label" "$(wc -c <"$action28r_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28r_outer_label" "$(line_count "$action28r_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28r_outer_label" "$(file_hash "$action28r_outer_stream")"
    if safe_stream "$action28r_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28r_outer_label"
        if [[ -s "$action28r_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28r_outer_label"
            cat "$action28r_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28r_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action28r_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28r_outer_label" >&2
    return 97
}
require_one() {
    local action28r_outer_line=$1
    local action28r_outer_file=$2

    [[ "$(grep -Fxc "$action28r_outer_line" "$action28r_outer_file" || true)" -eq 1 ]]
}
validate_ordered_checks() {
    local action28r_outer_source=$1
    local action28r_outer_prefix=$2
    local action28r_outer_stdout=$3
    local action28r_outer_status=$4
    local action28r_outer_expected=$5
    local action28r_outer_actual=$6
    local action28r_outer_expected_option=$7

    [[ "$action28r_outer_status" -eq 0 ]] || return 1
    "$action28r_outer_source" "$action28r_outer_expected_option" >"$action28r_outer_expected" || return 1
    sed -n "s/^${action28r_outer_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28r_outer_stdout" >"$action28r_outer_actual" || return 1
    [[ -s "$action28r_outer_expected" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action28r_outer_expected" | wc -l)" -eq "$(line_count "$action28r_outer_expected")" ]] || return 1
    diff -u "$action28r_outer_expected" "$action28r_outer_actual" >/dev/null || return 1
    [[ "$(grep -Ec "^${action28r_outer_prefix}_check_[a-z0-9_]+=false$" "$action28r_outer_stdout" || true)" -eq 0 ]]
}
validate_node_a() {
    local action28r_outer_stdout=$1
    local action28r_outer_stderr=$2
    local action28r_outer_status=$3
    local action28r_outer_expected=$4
    local action28r_outer_actual=$5

    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$node_a_inspector" action_28m_b "$action28r_outer_stdout" \
        "$action28r_outer_status" "$action28r_outer_expected" "$action28r_outer_actual" \
        --expected-checks || return 1
    require_one 'action_28m_b_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one 'action_28m_b_node_b_contacted=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28m_b_mutation=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28m_b_action_28m_rerun=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28m_b_action_28m_a_rerun=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28m_b_acceptance=true' "$action28r_outer_stdout"
}
validate_node_b() {
    local action28r_outer_stdout=$1
    local action28r_outer_stderr=$2
    local action28r_outer_status=$3
    local action28r_outer_expected=$4
    local action28r_outer_actual=$5

    # conditional-validator-explicit-failures-begin
    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$node_b_inspector" action_28p_a_node_b "$action28r_outer_stdout" \
        "$action28r_outer_status" "$action28r_outer_expected" "$action28r_outer_actual" \
        --expected-checks || return 1
    require_one 'action_28p_a_node_b_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_node_a_contacted=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_mutation=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_action_28p_rerun=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_acceptance=true' "$action28r_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
validate_observation_start() {
    local action28r_outer_stdout=$1
    local action28r_outer_stderr=$2
    local action28r_outer_status=$3
    local action28r_outer_expected=$4
    local action28r_outer_actual=$5

    # conditional-validator-explicit-failures-begin
    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$observation_start" action_28r_observation_start \
        "$action28r_outer_stdout" "$action28r_outer_status" "$action28r_outer_expected" \
        "$action28r_outer_actual" --expected-checks || return 1
    require_one 'action_28r_observation_start_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_observation_start_mutation=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_observation_start_acceptance=true' "$action28r_outer_stdout" || return 1
    [[ "$(grep -Ec '^action_28r_observation_start_value_journal_cursor=[A-Za-z0-9:;=._-]+$' "$action28r_outer_stdout" || true)" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}
validate_convergence() {
    local action28r_outer_role=$1
    local action28r_outer_stdout=$2
    local action28r_outer_stderr=$3
    local action28r_outer_status=$4
    local action28r_outer_expected=$5
    local action28r_outer_actual=$6
    local action28r_outer_expected_option

    # conditional-validator-explicit-failures-begin
    case "$action28r_outer_role" in
        node_b) action28r_outer_expected_option=--expected-node-b-checks ;;
        node_a) action28r_outer_expected_option=--expected-node-a-checks ;;
        *) return 1 ;;
    esac
    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$convergence_inspector" action_28r_convergence \
        "$action28r_outer_stdout" "$action28r_outer_status" "$action28r_outer_expected" \
        "$action28r_outer_actual" "$action28r_outer_expected_option" || return 1
    require_one 'action_28r_convergence_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one "action_28r_convergence_role=${action28r_outer_role}" "$action28r_outer_stdout" || return 1
    require_one 'action_28r_convergence_notifier_delivery_is_gate=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_convergence_mutation=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_convergence_acceptance=true' "$action28r_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
validate_transaction() {
    local action28r_outer_stdout=$1
    local action28r_outer_stderr=$2
    local action28r_outer_status=$3
    local action28r_outer_expected=$4
    local action28r_outer_actual=$5

    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$transaction" action_28r "$action28r_outer_stdout" \
        "$action28r_outer_status" "$action28r_outer_expected" "$action28r_outer_actual" \
        --expected-checks || return 1
    require_one 'action_28r_value_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_rollback_invoked=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_keepalived_reload_count=1' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_node_b_ssh_contacted=false' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_acceptance=true' "$action28r_outer_stdout"
}
validate_rollback() {
    local action28r_outer_stdout=$1
    local action28r_outer_stderr=$2
    local action28r_outer_status=$3
    local action28r_outer_expected=$4
    local action28r_outer_actual=$5

    [[ ! -s "$action28r_outer_stderr" ]] || return 1
    validate_ordered_checks "$transaction" action_28r_rollback "$action28r_outer_stdout" \
        "$action28r_outer_status" "$action28r_outer_expected" "$action28r_outer_actual" \
        --expected-rollback-checks || return 1
    require_one 'action_28r_rollback_first_failure=none' "$action28r_outer_stdout" || return 1
    require_one 'action_28r_rollback_acceptance=true' "$action28r_outer_stdout"
}
run_remote() {
    local action28r_outer_phase=$1
    local action28r_outer_target=$2
    local action28r_outer_command=$3
    local action28r_outer_source=$4
    local action28r_outer_stdout=$evidence_directory/${action28r_outer_phase}.stdout
    local action28r_outer_stderr=$evidence_directory/${action28r_outer_phase}.stderr
    local action28r_outer_status_file=$evidence_directory/${action28r_outer_phase}.status
    local action28r_outer_status=0

    install -m 0600 /dev/null "$action28r_outer_stdout"
    install -m 0600 /dev/null "$action28r_outer_stderr"
    install -m 0600 /dev/null "$action28r_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes "$action28r_outer_target" "$action28r_outer_command" \
        <"$action28r_outer_source" >"$action28r_outer_stdout" 2>"$action28r_outer_stderr" ||
        action28r_outer_status=$?
    printf '%s\n' "$action28r_outer_status" >"$action28r_outer_status_file"
    chmod 0600 "$action28r_outer_stdout" "$action28r_outer_stderr" "$action28r_outer_status_file"
    emit_stream "remote_stdout_${action28r_outer_phase}" "$action28r_outer_stdout" || return 97
    emit_stream "remote_stderr_${action28r_outer_phase}" "$action28r_outer_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action28r_outer_phase" "$action28r_outer_status"
}
rollback_and_reaccept() {
    run_remote node_a_rollback "$node_a_target" \
        'cd / && sudo -n /bin/bash -s -- --rollback' "$transaction" || return 125
    validate_rollback "$evidence_directory/node_a_rollback.stdout" \
        "$evidence_directory/node_a_rollback.stderr" \
        "$(<"$evidence_directory/node_a_rollback.status")" \
        "$evidence_directory/node_a_rollback.expected" \
        "$evidence_directory/node_a_rollback.actual" || return 125
    run_remote rollback_node_b_state "$node_b_target" \
        'cd / && sudo -n /bin/bash -s --' "$node_b_inspector" || return 125
    validate_node_b "$evidence_directory/rollback_node_b_state.stdout" \
        "$evidence_directory/rollback_node_b_state.stderr" \
        "$(<"$evidence_directory/rollback_node_b_state.status")" \
        "$evidence_directory/rollback_node_b_state.expected" \
        "$evidence_directory/rollback_node_b_state.actual" || return 125
    run_remote rollback_node_a_state "$node_a_target" \
        'cd / && sudo -n /bin/bash -s --' "$node_a_inspector" || return 125
    validate_node_a "$evidence_directory/rollback_node_a_state.stdout" \
        "$evidence_directory/rollback_node_a_state.stderr" \
        "$(<"$evidence_directory/rollback_node_a_state.status")" \
        "$evidence_directory/rollback_node_a_state.expected" \
        "$evidence_directory/rollback_node_a_state.actual" || return 125
    printf '%s_rollback_reacceptance=true\n' "$prefix"
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate transaction_source valid_source "$transaction_sha256" "$transaction" || return 1
    gate node_b_inspector_source valid_source "$node_b_inspector_sha256" "$node_b_inspector" || return 1
    gate node_a_inspector_source valid_source "$node_a_inspector_sha256" "$node_a_inspector" || return 1
    gate observation_start_source valid_source "$observation_start_sha256" "$observation_start" || return 1
    gate convergence_inspector_source valid_source "$convergence_inspector_sha256" \
        "$convergence_inspector" || return 1
    gate accepted_action_28q_a_source valid_source "$accepted_action_28q_a_sha256" \
        "$accepted_action_28q_a" || return 1
    gate regression_source valid_source "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$transaction" "$node_b_inspector" "$node_a_inspector" \
        "$observation_start" "$convergence_inspector" "$regression" "$0" || return 1
    gate transaction_self_test "$transaction" --self-test || return 1
    gate node_b_inspector_self_test "$node_b_inspector" --self-test || return 1
    gate node_a_inspector_self_test "$node_a_inspector" --self-test || return 1
    gate observation_start_self_test "$observation_start" --self-test || return 1
    gate convergence_inspector_self_test "$convergence_inspector" --self-test || return 1
    if [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]]; then
        gate regression true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
    gate shellcheck shellcheck "$transaction" "$node_b_inspector" "$node_a_inspector" \
        "$observation_start" "$convergence_inspector" "$regression" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$node_b_inspector" "$node_a_inspector" "$observation_start" \
        "$convergence_inspector" "$regression" "$0" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$node_b_inspector" "$node_a_inspector" "$observation_start" \
        "$convergence_inspector" "$regression" "$0" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$node_b_inspector" "$node_a_inspector" "$observation_start" \
        "$convergence_inspector" "$regression" "$0" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$node_b_inspector" "$node_a_inspector" "$observation_start" \
        "$convergence_inspector" "$regression" "$0" || return 1
    gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$0" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "$0" || return 1
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
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
        grep -Fq "'cd / && sudo -n /bin/bash -s -- --execute'" "$0"
        grep -Fq "'cd / && sudo -n /bin/bash -s -- --rollback'" "$0"
        grep -Fq 'accepted_action_28q_a_source' "$0"
        while IFS= read -r action28r_outer_self_test_gate; do
            gate "$action28r_outer_self_test_gate" true
        done < <(expected_local_gates)
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --transcript-test)
        [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 && $# -eq 22 ]]
        action28r_outer_transcript_root=$(mktemp -d /tmp/caddy-action28r-transcript.XXXXXX)
        trap 'rm -rf -- "$action28r_outer_transcript_root"' EXIT
        validate_node_b "$2" "$3" "$4" \
            "$action28r_outer_transcript_root/node-b.expected" \
            "$action28r_outer_transcript_root/node-b.actual"
        validate_node_a "$5" "$6" "$7" \
            "$action28r_outer_transcript_root/node-a.expected" \
            "$action28r_outer_transcript_root/node-a.actual"
        validate_observation_start "$8" "$9" "${10}" \
            "$action28r_outer_transcript_root/observation.expected" \
            "$action28r_outer_transcript_root/observation.actual"
        validate_transaction "${11}" "${12}" "${13}" \
            "$action28r_outer_transcript_root/transaction.expected" \
            "$action28r_outer_transcript_root/transaction.actual"
        validate_convergence node_b "${14}" "${15}" "${16}" \
            "$action28r_outer_transcript_root/node-b-convergence.expected" \
            "$action28r_outer_transcript_root/node-b-convergence.actual"
        validate_node_b "${17}" "${18}" "${19}" \
            "$action28r_outer_transcript_root/node-b-final.expected" \
            "$action28r_outer_transcript_root/node-b-final.actual"
        validate_convergence node_a "${20}" "${21}" "${22}" \
            "$action28r_outer_transcript_root/node-a-final.expected" \
            "$action28r_outer_transcript_root/node-a-final.actual"
        exit 0
        ;;
    '') ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION28R_SKIP_LOCAL_GATES:-}" = true ]]; then
    [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]]
else
    run_local_gates
fi
install -d -m 0700 "$evidence_root"
gate evidence_root_created evidence_metadata_expected "$evidence_root"
evidence_directory=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly evidence_directory
chmod 0700 "$evidence_directory"
gate evidence_directory_created evidence_metadata_expected "$evidence_directory"

run_remote node_b_preflight "$node_b_target" 'cd / && sudo -n /bin/bash -s --' "$node_b_inspector"
gate node_b_preflight validate_node_b "$evidence_directory/node_b_preflight.stdout" \
    "$evidence_directory/node_b_preflight.stderr" "$(<"$evidence_directory/node_b_preflight.status")" \
    "$evidence_directory/node_b_preflight.expected" "$evidence_directory/node_b_preflight.actual"

run_remote node_a_preflight "$node_a_target" 'cd / && sudo -n /bin/bash -s --' "$node_a_inspector"
gate node_a_preflight validate_node_a "$evidence_directory/node_a_preflight.stdout" \
    "$evidence_directory/node_a_preflight.stderr" "$(<"$evidence_directory/node_a_preflight.status")" \
    "$evidence_directory/node_a_preflight.expected" "$evidence_directory/node_a_preflight.actual"

run_remote node_b_observation_start "$node_b_target" \
    'cd / && sudo -n /bin/bash -s --' "$observation_start"
gate node_b_observation_start validate_observation_start \
    "$evidence_directory/node_b_observation_start.stdout" \
    "$evidence_directory/node_b_observation_start.stderr" \
    "$(<"$evidence_directory/node_b_observation_start.status")" \
    "$evidence_directory/node_b_observation_start.expected" \
    "$evidence_directory/node_b_observation_start.actual"
journal_cursor=$(sed -n \
    's/^action_28r_observation_start_value_journal_cursor=//p' \
    "$evidence_directory/node_b_observation_start.stdout")
readonly journal_cursor
gate node_b_observation_cursor_safe test -n "$journal_cursor"
convergence_command="cd / && sudo -n /bin/bash -s -- --node-b $journal_cursor"
readonly convergence_command

run_remote node_a_transaction "$node_a_target" 'cd / && sudo -n /bin/bash -s -- --execute' "$transaction"
if ! gate node_a_transaction validate_transaction "$evidence_directory/node_a_transaction.stdout" \
    "$evidence_directory/node_a_transaction.stderr" "$(<"$evidence_directory/node_a_transaction.status")" \
    "$evidence_directory/node_a_transaction.expected" "$evidence_directory/node_a_transaction.actual"; then
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

run_remote node_b_convergence "$node_b_target" "$convergence_command" "$convergence_inspector"
if ! gate node_b_convergence validate_convergence node_b \
    "$evidence_directory/node_b_convergence.stdout" \
    "$evidence_directory/node_b_convergence.stderr" \
    "$(<"$evidence_directory/node_b_convergence.status")" \
    "$evidence_directory/node_b_convergence.expected" \
    "$evidence_directory/node_b_convergence.actual"; then
    rollback_and_reaccept || exit 125
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

run_remote node_b_final_state "$node_b_target" \
    'cd / && sudo -n /bin/bash -s --' "$node_b_inspector"
if ! gate node_b_final_state validate_node_b \
    "$evidence_directory/node_b_final_state.stdout" \
    "$evidence_directory/node_b_final_state.stderr" \
    "$(<"$evidence_directory/node_b_final_state.status")" \
    "$evidence_directory/node_b_final_state.expected" \
    "$evidence_directory/node_b_final_state.actual"; then
    rollback_and_reaccept || exit 125
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

run_remote node_a_final_state "$node_a_target" \
    'cd / && sudo -n /bin/bash -s -- --node-a' "$convergence_inspector"
if ! gate node_a_final_state validate_convergence node_a \
    "$evidence_directory/node_a_final_state.stdout" \
    "$evidence_directory/node_a_final_state.stderr" \
    "$(<"$evidence_directory/node_a_final_state.status")" \
    "$evidence_directory/node_a_final_state.expected" \
    "$evidence_directory/node_a_final_state.actual"; then
    rollback_and_reaccept || exit 125
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_accepted_action_28q_a_baseline_consumed=true\n' "$prefix"
printf '%s_action_28q_rerun=false\n' "$prefix"
printf '%s_transient_node_b_master_is_observation=true\n' "$prefix"
printf '%s_notifier_delivery_is_gate=false\n' "$prefix"
printf '%s_node_b_contacted_read_only=true\n' "$prefix"
printf '%s_node_a_mutated=true\n' "$prefix"
printf '%s_coupled_vip_acquisition=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
