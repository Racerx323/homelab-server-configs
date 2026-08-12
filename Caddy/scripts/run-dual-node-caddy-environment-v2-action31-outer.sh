#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_31_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=131072
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/apply-caddy-environment-v2-action31.sh
readonly regression=$caddy_root/tests/action31-caddy-environment-v2-regression.sh
readonly environment_regression=$caddy_root/tests/caddy-environment-v2-regression.sh
readonly template=$caddy_root/templates/caddy-ha.env-v2.in
readonly manifest=$caddy_root/manifests/caddy-environment-v2-action31.yaml
readonly expected_transaction_sha256=7c55166f6bad1830335d8f66aabacb2f0716a82b1dad7dc5b83bcd730f732caf
readonly expected_regression_sha256=22769285f06cda70276f13cc3b2efd240e814fd027325c7887ef4dbf6ce6f509
readonly expected_environment_regression_sha256=b808a098c401752d86b0ab6ce711dcc340f2f3244cc4be95c0043590c0e6b73e
readonly expected_template_sha256=4a3394225b27dde6e3ee079d2ce69ad2efb93190ba80bd8c63f80254c6084db3
evidence_root=${CADDY_ACTION31_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action31}
readonly evidence_root
ssh_binary=${CADDY_ACTION31_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
work_root=
node_a_mutated=false
node_b_mutated=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
manifest_valid_local() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest"
        return
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
}
gate() {
    local action31_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action31_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action31_outer_label" >&2
    return 1
}
safe_stream() {
    local action31_outer_stream=$1

    [[ "$(wc -c <"$action31_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action31_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action31_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action31_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action31_outer_stream"
}
emit_stream() {
    local action31_outer_label=$1
    local action31_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action31_outer_label" "$(wc -c <"$action31_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action31_outer_label" "$(line_count "$action31_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action31_outer_label" "$(file_hash "$action31_outer_stream")"
    if ! safe_stream "$action31_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action31_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action31_outer_label"
    if [[ -s "$action31_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action31_outer_label"
        cat "$action31_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action31_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action31_outer_label"
    fi
}
prepare_capture() {
    local action31_outer_capture

    for action31_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action31_outer_capture" || return 1
    done
}
completion_marker() {
    local action31_outer_mode=$1
    local action31_outer_token=$2

    case "$action31_outer_mode" in
        --apply) printf 'action_31_remote_%s_apply_complete=true\n' "$action31_outer_token" ;;
        --verify-current) printf 'action_31_remote_%s_verify_current_complete=true\n' "$action31_outer_token" ;;
        --verify-legacy) printf 'action_31_remote_%s_verify_legacy_complete=true\n' "$action31_outer_token" ;;
        --rollback-committed) printf 'action_31_remote_%s_rollback_committed_complete=true\n' "$action31_outer_token" ;;
        *) return 64 ;;
    esac
}
run_remote() {
    local action31_outer_label=$1
    local action31_outer_target=$2
    local action31_outer_alias=$3
    local action31_outer_role=$4
    local action31_outer_mode=$5
    local action31_outer_token=${action31_outer_role//-/_}
    local action31_outer_stdout=$work_root/$action31_outer_label.stdout
    local action31_outer_stderr=$work_root/$action31_outer_label.stderr
    local action31_outer_status_file=$work_root/$action31_outer_label.status
    local action31_outer_status=0
    local action31_outer_marker

    prepare_capture "$action31_outer_stdout" "$action31_outer_stderr" \
        "$action31_outer_status_file" || return 1
    chmod 0600 "$action31_outer_stdout" "$action31_outer_stderr" \
        "$action31_outer_status_file" || return 1
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action31_outer_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR \
        "$action31_outer_target" \
        "cd / && sudo -n /bin/bash -s -- $action31_outer_mode $action31_outer_role" \
        <"$transaction" >"$action31_outer_stdout" \
        2>"$action31_outer_stderr" || action31_outer_status=$?
    printf '%s\n' "$action31_outer_status" >"$action31_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action31_outer_label" "$action31_outer_status"
    emit_stream "remote_stdout_$action31_outer_label" "$action31_outer_stdout" || return $?
    emit_stream "remote_stderr_$action31_outer_label" "$action31_outer_stderr" || return $?
    [[ "$action31_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action31_outer_stderr" ]] || return 1
    ! grep -Eq '^action_31_remote_.*_check_.*=false$' "$action31_outer_stdout" || return 1
    action31_outer_marker=$(completion_marker "$action31_outer_mode" "$action31_outer_token") || return 1
    [[ "$(grep -Fxc "$action31_outer_marker" "$action31_outer_stdout")" -eq 1 ]]
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate transaction_hash test "$(file_hash "$transaction")" = "$expected_transaction_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$expected_regression_sha256" || return 1
    gate environment_regression_hash test "$(file_hash "$environment_regression")" = "$expected_environment_regression_sha256" || return 1
    gate template_hash test "$(file_hash "$template")" = "$expected_template_sha256" || return 1
    gate syntax /bin/bash -n "$transaction" "$regression" "$environment_regression" "${BASH_SOURCE[0]}" || return 1
    gate transaction_node_a_self_test /bin/bash "$transaction" --self-test node-a || return 1
    gate transaction_node_b_self_test /bin/bash "$transaction" --self-test node-b || return 1
    gate environment_regression /bin/bash "$environment_regression" || return 1
    if [[ "${CADDY_ACTION31_SKIP_REGRESSION:-false}" != true ]]; then
        gate regression /bin/bash "$regression" || return 1
    fi
    gate environment_policy /bin/bash "$caddy_root/tests/caddy-environment-v2-policy.sh" --check || return 1
    gate template_policy /bin/bash "$caddy_root/tests/template-lifecycle-policy.sh" --check || return 1
    gate shellcheck shellcheck "$transaction" "$regression" "$environment_regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$regression" "$environment_regression" "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "$environment_regression" "${BASH_SOURCE[0]}" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "${BASH_SOURCE[0]}" || return 1
    gate manifest manifest_valid_local || return 1
}
recover() {
    local action31_outer_recovery_failed=false

    if [[ "$node_a_mutated" = true ]]; then
        run_remote node-a-rollback "$node_a_target" pihole0.local.theama.co \
            node-a --rollback-committed || action31_outer_recovery_failed=true
    fi
    if [[ "$node_b_mutated" = true ]]; then
        run_remote node-b-rollback "$node_b_target" pihole00.local.theama.co \
            node-b --rollback-committed || action31_outer_recovery_failed=true
    fi
    run_remote node-a-recovery "$node_a_target" pihole0.local.theama.co \
        node-a --verify-legacy || action31_outer_recovery_failed=true
    run_remote node-b-recovery "$node_b_target" pihole00.local.theama.co \
        node-b --verify-legacy || action31_outer_recovery_failed=true
    if [[ "$action31_outer_recovery_failed" = true ]]; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        return 125
    fi
    printf '%s_recovery_proven=true\n' "$prefix"
    return 1
}
run_action() {
    local action31_outer_started_ns
    local action31_outer_finished_ns

    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/run.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    action31_outer_started_ns=$(date +%s%N) || return 1

    node_b_mutated=true
    if ! run_remote node-b-apply "$node_b_target" pihole00.local.theama.co \
        node-b --apply; then
        recover || return $?
    fi
    if ! run_remote node-a-legacy "$node_a_target" pihole0.local.theama.co \
        node-a --verify-legacy; then
        recover || return $?
    fi
    node_a_mutated=true
    if ! run_remote node-a-apply "$node_a_target" pihole0.local.theama.co \
        node-a --apply; then
        recover || return $?
    fi
    if ! run_remote node-b-final "$node_b_target" pihole00.local.theama.co \
        node-b --verify-current ||
        ! run_remote node-a-final "$node_a_target" pihole0.local.theama.co \
            node-a --verify-current; then
        recover || return $?
    fi

    action31_outer_finished_ns=$(date +%s%N) || return 1
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_elapsed_ms=%s\n' "$prefix" \
        "$(((action31_outer_finished_ns - action31_outer_started_ns) / 1000000))"
    printf '%s_standby_first=true\n' "$prefix"
    printf '%s_reload_scope=caddy-only\n' "$prefix"
    printf '%s_keepalived_mutated=false\n' "$prefix"
    printf '%s_lsyncd_mutated=false\n' "$prefix"
    printf '%s_reconciliation_mutated=false\n' "$prefix"
    printf '%s_release_selection_mutated=false\n' "$prefix"
    printf '%s_recovery_invoked=false\n' "$prefix"
    printf '%s_manual_intervention_required=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}
self_test() {
    run_local_gates || return 1
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test) self_test ;;
    '') run_action ;;
    *) exit 64 ;;
esac
