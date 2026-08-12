#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_29b_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=131072
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/apply-pihole-v5-config-action29b.sh
readonly regression=$caddy_root/tests/action29b-pihole-v5-config-regression.sh
readonly manifest=$caddy_root/manifests/pihole-v5-config-action29b.yaml
readonly ftl_source=/home/aaron/code/homelab-dns/Pi-Hole/configs/pihole-FTL.conf
readonly domain_source=/home/aaron/code/homelab-dns/Pi-Hole/configs/local.theama.co.conf
readonly expected_transaction_sha256=13e0a65088f33c2e1dfd8c4c789fcaa949749d8b84bb1b293690c1a8dcf484c0
readonly expected_regression_sha256=7f9b9cf9e082d71ef77db475d44eeca3e68ad71577f5586e79602a1c550cc266
readonly expected_ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3
readonly expected_domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026
evidence_root=${CADDY_ACTION29B_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action29b}
readonly evidence_root
ssh_binary=${CADDY_ACTION29B_SSH_BIN:-/usr/bin/ssh}
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
source_files_valid() {
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        return 0
    fi
    [[ "$(file_hash "$ftl_source")" = "$expected_ftl_sha256" ]] || return 1
    [[ "$(file_hash "$domain_source")" = "$expected_domain_sha256" ]]
}
manifest_valid_local() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest"
        return
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
}
gate() {
    local action29b_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action29b_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action29b_label" >&2
    return 1
}
safe_stream() {
    local action29b_stream=$1

    [[ "$(wc -c <"$action29b_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action29b_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action29b_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action29b_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action29b_stream"
}
emit_stream() {
    local action29b_label=$1
    local action29b_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action29b_label" "$(wc -c <"$action29b_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action29b_label" "$(line_count "$action29b_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action29b_label" "$(file_hash "$action29b_stream")"
    if ! safe_stream "$action29b_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action29b_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action29b_label"
    if [[ -s "$action29b_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action29b_label"
        cat "$action29b_stream"
        printf '%s_%s_end\n' "$prefix" "$action29b_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action29b_label"
    fi
}
prepare_capture() {
    local action29b_capture

    for action29b_capture in "$@"; do
        install -m 0600 /dev/null "$action29b_capture" || return 1
    done
}
completion_marker() {
    local action29b_mode=$1
    local action29b_token=$2

    case "$action29b_mode" in
        --apply) printf 'action_29b_remote_%s_complete=true\n' "$action29b_token" ;;
        --verify-target) printf 'action_29b_remote_%s_verify_target_complete=true\n' "$action29b_token" ;;
        --rollback-committed) printf 'action_29b_remote_%s_rollback_committed_complete=true\n' "$action29b_token" ;;
        --verify-continuity) printf 'action_29b_remote_%s_check_dns_record_families=true\n' "$action29b_token" ;;
        *) return 64 ;;
    esac
}
run_remote() {
    local action29b_label=$1
    local action29b_target=$2
    local action29b_alias=$3
    local action29b_role=$4
    local action29b_mode=$5
    local action29b_token=${action29b_role//-/_}
    local action29b_stdout=$work_root/$action29b_label.stdout
    local action29b_stderr=$work_root/$action29b_label.stderr
    local action29b_status_file=$work_root/$action29b_label.status
    local action29b_status=0
    local action29b_marker

    prepare_capture "$action29b_stdout" "$action29b_stderr" "$action29b_status_file" || return 1
    chmod 0600 "$action29b_stdout" "$action29b_stderr" "$action29b_status_file" || return 1
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action29b_alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o LogLevel=ERROR "$action29b_target" \
        "cd / && sudo -n /bin/bash -s -- $action29b_mode $action29b_role" \
        <"$transaction" >"$action29b_stdout" 2>"$action29b_stderr" || action29b_status=$?
    printf '%s\n' "$action29b_status" >"$action29b_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action29b_label" "$action29b_status"
    emit_stream "remote_stdout_$action29b_label" "$action29b_stdout" || return $?
    emit_stream "remote_stderr_$action29b_label" "$action29b_stderr" || return $?
    [[ "$action29b_status" -eq 0 ]] || return 1
    [[ ! -s "$action29b_stderr" ]] || return 1
    ! grep -Eq '^action_29b_remote_.*_check_.*=false$' "$action29b_stdout" || return 1
    action29b_marker=$(completion_marker "$action29b_mode" "$action29b_token") || return 1
    [[ "$(grep -Fxc "$action29b_marker" "$action29b_stdout")" -eq 1 ]]
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate transaction_hash test "$(file_hash "$transaction")" = "$expected_transaction_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$expected_regression_sha256" || return 1
    gate source_files source_files_valid || return 1
    gate syntax /bin/bash -n "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate transaction_node_a_self_test /bin/bash "$transaction" --self-test node-a || return 1
    gate transaction_node_b_self_test /bin/bash "$transaction" --self-test node-b || return 1
    if [[ "${CADDY_ACTION29B_SKIP_REGRESSION:-false}" != true ]]; then
        gate regression /bin/bash "$regression" || return 1
    fi
    gate shellcheck shellcheck "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "${BASH_SOURCE[0]}" || return 1
    gate manifest manifest_valid_local || return 1
}
recover() {
    local action29b_recovery_failed=false

    if [[ "$node_a_mutated" = true ]]; then
        run_remote node-a-rollback "$node_a_target" pihole0.local.theama.co node-a \
            --rollback-committed || action29b_recovery_failed=true
    fi
    if [[ "$node_b_mutated" = true ]]; then
        run_remote node-b-rollback "$node_b_target" pihole00.local.theama.co node-b \
            --rollback-committed || action29b_recovery_failed=true
    fi
    run_remote node-a-recovery "$node_a_target" pihole0.local.theama.co node-a \
        --verify-continuity || action29b_recovery_failed=true
    run_remote node-b-recovery "$node_b_target" pihole00.local.theama.co node-b \
        --verify-continuity || action29b_recovery_failed=true
    if [[ "$action29b_recovery_failed" = true ]]; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        return 125
    fi
    printf '%s_recovery_proven=true\n' "$prefix"
    return 1
}
run_action() {
    local action29b_started_ns
    local action29b_finished_ns

    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/run.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    action29b_started_ns=$(date +%s%N) || return 1

    if ! run_remote node-b-apply "$node_b_target" pihole00.local.theama.co node-b --apply; then
        recover || return $?
    fi
    node_b_mutated=true
    if ! run_remote node-a-after-node-b "$node_a_target" pihole0.local.theama.co node-a \
        --verify-continuity; then
        recover || return $?
    fi
    if ! run_remote node-a-apply "$node_a_target" pihole0.local.theama.co node-a --apply; then
        recover || return $?
    fi
    node_a_mutated=true
    if ! run_remote node-b-final "$node_b_target" pihole00.local.theama.co node-b --verify-target ||
        ! run_remote node-a-final "$node_a_target" pihole0.local.theama.co node-a --verify-target; then
        recover || return $?
    fi

    action29b_finished_ns=$(date +%s%N) || return 1
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_elapsed_ms=%s\n' "$prefix" \
        "$(((action29b_finished_ns - action29b_started_ns) / 1000000))"
    printf '%s_standby_first=true\n' "$prefix"
    printf '%s_restart_order=node-b,node-a\n' "$prefix"
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
