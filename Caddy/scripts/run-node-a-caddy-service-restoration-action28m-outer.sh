#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_outer
readonly driver_sha256=6f4818fe31041f6eaefa0112390ce6e66444c19b241aa737ac9af5506760dc78
readonly regression_sha256=a81f766d65a15f3e3ad8298ff4f38cb62726d6a86ed6b11d58df38629372da1e
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly driver=$script_directory/restore-node-a-caddy-service-action28m.sh
readonly regression=$caddy_root/tests/action28m-caddy-service-restoration-regression.sh

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            return
            ;;
        *) return 1 ;;
    esac
}
valid_source() {
    local action28m_outer_hash=$1
    local action28m_outer_file=$2

    [[ -f "$action28m_outer_file" && ! -L "$action28m_outer_file" && -x "$action28m_outer_file" ]] || return 1
    [[ "$(file_hash "$action28m_outer_file")" = "$action28m_outer_hash" ]]
}
gate() {
    local action28m_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28m_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28m_outer_label" >&2
    return 1
}
safe_stream() {
    local action28m_outer_stream=$1

    [[ "$(wc -c <"$action28m_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28m_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28m_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action28m_outer_stream"
}
emit_stream() {
    local action28m_outer_label=$1
    local action28m_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28m_outer_label" "$(wc -c <"$action28m_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28m_outer_label" "$(line_count "$action28m_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28m_outer_label" "$(file_hash "$action28m_outer_stream")"
    if safe_stream "$action28m_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28m_outer_label"
        if [[ -s "$action28m_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28m_outer_label"
            cat "$action28m_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28m_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action28m_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28m_outer_label" >&2
    return 97
}
require_one() {
    local action28m_outer_line=$1
    local action28m_outer_file=$2

    [[ "$(grep -Fxc "$action28m_outer_line" "$action28m_outer_file" || true)" -eq 1 ]]
}
validate_transcript() {
    local action28m_outer_stdout=$1
    local action28m_outer_stderr=$2
    local action28m_outer_status=$3
    local action28m_outer_expected=$4
    local action28m_outer_actual=$5

    "$driver" --expected-checks >"$action28m_outer_expected" || return 1
    sed -n 's/^action_28m_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action28m_outer_stdout" >"$action28m_outer_actual"
    [[ "$action28m_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action28m_outer_stderr" ]] || return 1
    [[ "$(line_count "$action28m_outer_expected")" -gt 0 ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action28m_outer_expected" | wc -l)" -eq "$(line_count "$action28m_outer_expected")" ]] || return 1
    diff -u "$action28m_outer_expected" "$action28m_outer_actual" >/dev/null || return 1
    [[ "$(grep -Ec '^action_28m_check_[a-z0-9_]+=false$' "$action28m_outer_stdout" || true)" -eq 0 ]] || return 1
    require_one 'action_28m_value_first_failure=none' "$action28m_outer_stdout" || return 1
    require_one 'action_28m_rollback_invoked=false' "$action28m_outer_stdout" || return 1
    require_one 'action_28m_node_b_contacted=false' "$action28m_outer_stdout" || return 1
    require_one 'action_28m_keepalived_reload_count=1' "$action28m_outer_stdout" || return 1
    require_one 'action_28m_caddy_start_count=1' "$action28m_outer_stdout" || return 1
    require_one 'action_28m_acceptance=true' "$action28m_outer_stdout"
}
cleanup() {
    local action28m_outer_status=$?

    [[ -z "${work_root:-}" || ! -d "$work_root" ]] || rm -rf -- "$work_root"
    exit "$action28m_outer_status"
}

case "${1:-}" in
    --source-test)
        [[ $# -eq 1 ]]
        valid_source "$driver_sha256" "$driver"
        valid_source "$regression_sha256" "$regression"
        grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$0"
        printf '%s_source_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        "$driver" --self-test >/dev/null
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") ;;
    *) exit 64 ;;
esac

trap cleanup EXIT HUP INT TERM
gate working_directory working_directory_approved
gate driver_source valid_source "$driver_sha256" "$driver"
gate regression_source valid_source "$regression_sha256" "$regression"
gate driver_syntax /bin/bash -n "$driver"
gate driver_self_test "$driver" --self-test
if [[ "${CADDY_ACTION28M_TEST_MODE:-}" != 1 ]]; then
    gate regression /bin/bash "$regression"
else
    gate test_mode test -n "${CADDY_ACTION28M_SSH_BIN:-}"
fi

work_root=$(mktemp -d /tmp/caddy-action28m-outer.XXXXXX)
chmod 0700 "$work_root"
stdout_file=$work_root/remote.stdout
stderr_file=$work_root/remote.stderr
expected_file=$work_root/expected
actual_file=$work_root/actual
: >"$stdout_file"
: >"$stderr_file"
chmod 0600 "$stdout_file" "$stderr_file"
ssh_status=0
ssh_bin=${CADDY_ACTION28M_SSH_BIN:-/usr/bin/ssh}
"$ssh_bin" -T -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/home/aaron/.ssh/known_hosts \
    pi@10.1.0.53 "cd / && sudo -n /bin/bash -s --" \
    <"$driver" >"$stdout_file" 2>"$stderr_file" || ssh_status=$?
emit_stream remote_stdout "$stdout_file"
emit_stream remote_stderr "$stderr_file"
gate transcript validate_transcript "$stdout_file" "$stderr_file" "$ssh_status" \
    "$expected_file" "$actual_file"
printf '%s_remote_status=%s\n' "$prefix" "$ssh_status"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_execution_authorized=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
