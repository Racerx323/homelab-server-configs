#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_28o_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly transaction_sha256=8330588d34150d0ed4558ce2d8caf984e8bd73beb7065f760a25081619b42d19
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly regression_sha256=fb0d26a860aa0ae185a4b9e1428197ef8108bb042fe886556b3b8a6d45545bb9
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/restore-node-b-caddy-service-action28o.sh
readonly node_a_inspector=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly regression=$caddy_root/tests/action28o-node-b-caddy-service-restoration-regression.sh
readonly evidence_root=/tmp/caddy-ssh-evidence/action28o
ssh_binary=${CADDY_ACTION28O_SSH_BIN:-/usr/bin/ssh}
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
    local action28o_outer_path=$1

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        [[ "$(stat -c '%U:%G:%a' "$action28o_outer_path")" = root:root:700 ]]
    else
        [[ "$(stat -c '%U:%G:%a' "$action28o_outer_path")" = aaron:aaron:700 ]]
    fi
}
valid_source() {
    local action28o_outer_hash=$1
    local action28o_outer_file=$2

    [[ -f "$action28o_outer_file" && ! -L "$action28o_outer_file" && -x "$action28o_outer_file" ]] || return 1
    [[ "$(file_hash "$action28o_outer_file")" = "$action28o_outer_hash" ]]
}
gate() {
    local action28o_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28o_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28o_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_source node_a_inspector_source regression_source \
        syntax transaction_self_test node_a_inspector_self_test regression shellcheck \
        canonical_format collision_policy conditional_policy multifile_grep_policy \
        portable_awk_policy root_cwd_policy ssh_evidence_policy accepted_live_hash_policy \
        evidence_root_created evidence_directory_created node_a_preflight \
        node_b_transaction node_a_postflight
}
safe_stream() {
    local action28o_outer_stream=$1

    [[ "$(wc -c <"$action28o_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28o_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28o_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action28o_outer_stream"
}
emit_stream() {
    local action28o_outer_label=$1
    local action28o_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28o_outer_label" "$(wc -c <"$action28o_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28o_outer_label" "$(line_count "$action28o_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28o_outer_label" "$(file_hash "$action28o_outer_stream")"
    if safe_stream "$action28o_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28o_outer_label"
        if [[ -s "$action28o_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28o_outer_label"
            cat "$action28o_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28o_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action28o_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28o_outer_label" >&2
    return 97
}
require_one() {
    local action28o_outer_line=$1
    local action28o_outer_file=$2

    [[ "$(grep -Fxc "$action28o_outer_line" "$action28o_outer_file" || true)" -eq 1 ]]
}
validate_ordered_checks() {
    local action28o_outer_source=$1
    local action28o_outer_prefix=$2
    local action28o_outer_stdout=$3
    local action28o_outer_status=$4
    local action28o_outer_expected=$5
    local action28o_outer_actual=$6
    local action28o_outer_expected_option=$7

    [[ "$action28o_outer_status" -eq 0 ]] || return 1
    "$action28o_outer_source" "$action28o_outer_expected_option" >"$action28o_outer_expected" || return 1
    sed -n "s/^${action28o_outer_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28o_outer_stdout" >"$action28o_outer_actual" || return 1
    [[ -s "$action28o_outer_expected" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action28o_outer_expected" | wc -l)" -eq "$(line_count "$action28o_outer_expected")" ]] || return 1
    diff -u "$action28o_outer_expected" "$action28o_outer_actual" >/dev/null || return 1
    [[ "$(grep -Ec "^${action28o_outer_prefix}_check_[a-z0-9_]+=false$" "$action28o_outer_stdout" || true)" -eq 0 ]]
}
validate_node_a() {
    local action28o_outer_stdout=$1
    local action28o_outer_stderr=$2
    local action28o_outer_status=$3
    local action28o_outer_expected=$4
    local action28o_outer_actual=$5

    [[ ! -s "$action28o_outer_stderr" ]] || return 1
    validate_ordered_checks "$node_a_inspector" action_28m_b "$action28o_outer_stdout" \
        "$action28o_outer_status" "$action28o_outer_expected" "$action28o_outer_actual" \
        --expected-checks || return 1
    require_one 'action_28m_b_first_failure=none' "$action28o_outer_stdout" || return 1
    require_one 'action_28m_b_node_b_contacted=false' "$action28o_outer_stdout" || return 1
    require_one 'action_28m_b_mutation=false' "$action28o_outer_stdout" || return 1
    require_one 'action_28m_b_acceptance=true' "$action28o_outer_stdout"
}
validate_transaction() {
    local action28o_outer_stdout=$1
    local action28o_outer_stderr=$2
    local action28o_outer_status=$3
    local action28o_outer_expected=$4
    local action28o_outer_actual=$5

    [[ ! -s "$action28o_outer_stderr" ]] || return 1
    validate_ordered_checks "$transaction" action_28o "$action28o_outer_stdout" \
        "$action28o_outer_status" "$action28o_outer_expected" "$action28o_outer_actual" \
        --expected-checks || return 1
    require_one 'action_28o_value_first_failure=none' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_rollback_invoked=false' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_caddy_start_count=1' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_keepalived_reload_count=0' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_node_a_ssh_contacted=false' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_acceptance=true' "$action28o_outer_stdout"
}
validate_rollback() {
    local action28o_outer_stdout=$1
    local action28o_outer_stderr=$2
    local action28o_outer_status=$3
    local action28o_outer_expected=$4
    local action28o_outer_actual=$5

    [[ ! -s "$action28o_outer_stderr" ]] || return 1
    validate_ordered_checks "$transaction" action_28o_rollback "$action28o_outer_stdout" \
        "$action28o_outer_status" "$action28o_outer_expected" "$action28o_outer_actual" \
        --expected-rollback-checks || return 1
    require_one 'action_28o_rollback_first_failure=none' "$action28o_outer_stdout" || return 1
    require_one 'action_28o_rollback_acceptance=true' "$action28o_outer_stdout"
}
run_remote() {
    local action28o_outer_phase=$1
    local action28o_outer_target=$2
    local action28o_outer_command=$3
    local action28o_outer_source=$4
    local action28o_outer_stdout=$evidence_directory/${action28o_outer_phase}.stdout
    local action28o_outer_stderr=$evidence_directory/${action28o_outer_phase}.stderr
    local action28o_outer_status_file=$evidence_directory/${action28o_outer_phase}.status
    local action28o_outer_status=0

    install -m 0600 /dev/null "$action28o_outer_stdout"
    install -m 0600 /dev/null "$action28o_outer_stderr"
    install -m 0600 /dev/null "$action28o_outer_status_file"
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes "$action28o_outer_target" "$action28o_outer_command" \
        <"$action28o_outer_source" >"$action28o_outer_stdout" 2>"$action28o_outer_stderr" ||
        action28o_outer_status=$?
    printf '%s\n' "$action28o_outer_status" >"$action28o_outer_status_file"
    chmod 0600 "$action28o_outer_stdout" "$action28o_outer_stderr" "$action28o_outer_status_file"
    emit_stream "remote_stdout_${action28o_outer_phase}" "$action28o_outer_stdout" || return 97
    emit_stream "remote_stderr_${action28o_outer_phase}" "$action28o_outer_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action28o_outer_phase" "$action28o_outer_status"
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate transaction_source valid_source "$transaction_sha256" "$transaction" || return 1
    gate node_a_inspector_source valid_source "$node_a_inspector_sha256" "$node_a_inspector" || return 1
    gate regression_source valid_source "$regression_sha256" "$regression" || return 1
    gate syntax /bin/bash -n "$transaction" "$regression" "$0" || return 1
    gate transaction_self_test "$transaction" --self-test || return 1
    gate node_a_inspector_self_test "$node_a_inspector" --self-test || return 1
    if [[ "${CADDY_ACTION28O_TEST_MODE:-}" = 1 ]]; then
        gate regression true || return 1
    else
        gate regression /bin/bash "$regression" || return 1
    fi
    if [[ "${CADDY_ACTION28O_SELF_TEST_MODE:-}" = 1 ]]; then
        gate shellcheck true || return 1
        gate canonical_format true || return 1
        gate collision_policy true || return 1
        gate conditional_policy true || return 1
        gate multifile_grep_policy true || return 1
        gate portable_awk_policy true || return 1
        gate root_cwd_policy true || return 1
        gate ssh_evidence_policy true || return 1
        gate accepted_live_hash_policy true || return 1
    else
        gate shellcheck shellcheck "$transaction" "$regression" "$0" || return 1
        gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
            "$transaction" "$regression" "$0" || return 1
        gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
            "$transaction" "$regression" "$0" || return 1
        gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
        gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
            "$transaction" "$regression" "$0" || return 1
        gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
            "$transaction" "$regression" "$0" || return 1
        gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$0" || return 1
        gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "$0" || return 1
        gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    fi
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
        CADDY_ACTION28O_TEST_MODE=1 CADDY_ACTION28O_SELF_TEST_MODE=1 run_local_gates
        gate evidence_root_created true
        gate evidence_directory_created true
        gate node_a_preflight true
        gate node_b_transaction true
        gate node_a_postflight true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --transaction-transcript-test)
        [[ "${CADDY_ACTION28O_TEST_MODE:-}" = 1 && $# -eq 4 ]]
        transcript_test_root=$(mktemp -d /tmp/caddy-action28o-transcript-test.XXXXXX)
        trap 'rm -rf -- "$transcript_test_root"' EXIT
        validate_transaction "$2" "$3" "$4" "$transcript_test_root/expected" \
            "$transcript_test_root/actual"
        printf '%s_transaction_transcript_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') ;;
    *) exit 64 ;;
esac

run_local_gates
install -d -m 0700 "$evidence_root"
gate evidence_root_created evidence_metadata_expected "$evidence_root"
evidence_directory=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly evidence_directory
chmod 0700 "$evidence_directory"
gate evidence_directory_created evidence_metadata_expected "$evidence_directory"

run_remote node_a_preflight "$node_a_target" 'cd / && sudo -n /bin/bash -s --' "$node_a_inspector"
gate node_a_preflight validate_node_a "$evidence_directory/node_a_preflight.stdout" \
    "$evidence_directory/node_a_preflight.stderr" "$(<"$evidence_directory/node_a_preflight.status")" \
    "$evidence_directory/node_a_preflight.expected" "$evidence_directory/node_a_preflight.actual"

run_remote node_b_transaction "$node_b_target" 'cd / && sudo -n /bin/bash -s -- --execute' "$transaction"
if ! gate node_b_transaction validate_transaction "$evidence_directory/node_b_transaction.stdout" \
    "$evidence_directory/node_b_transaction.stderr" "$(<"$evidence_directory/node_b_transaction.status")" \
    "$evidence_directory/node_b_transaction.expected" "$evidence_directory/node_b_transaction.actual"; then
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

run_remote node_a_postflight "$node_a_target" 'cd / && sudo -n /bin/bash -s --' "$node_a_inspector"
if ! gate node_a_postflight validate_node_a "$evidence_directory/node_a_postflight.stdout" \
    "$evidence_directory/node_a_postflight.stderr" "$(<"$evidence_directory/node_a_postflight.status")" \
    "$evidence_directory/node_a_postflight.expected" "$evidence_directory/node_a_postflight.actual"; then
    run_remote node_b_rollback "$node_b_target" 'cd / && sudo -n /bin/bash -s -- --rollback' "$transaction" || exit 125
    validate_rollback "$evidence_directory/node_b_rollback.stdout" \
        "$evidence_directory/node_b_rollback.stderr" "$(<"$evidence_directory/node_b_rollback.status")" \
        "$evidence_directory/node_b_rollback.expected" "$evidence_directory/node_b_rollback.actual" || exit 125
    printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
    exit 1
fi

printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_node_a_contacted_read_only=true\n' "$prefix"
printf '%s_node_b_caddy_started=true\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
