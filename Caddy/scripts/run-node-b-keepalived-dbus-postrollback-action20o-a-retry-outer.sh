#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_a_retry_outer
readonly target=pi@10.1.0.54
readonly remote_command='cd / && sudo -n /bin/bash -s --'
readonly inspector_sha256=e67a5d645f3123ff2fad29ec435e9ec9b37a63af02984bfbf2b8fff534ea8265
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-b-keepalived-dbus-postrollback-action20o-a-retry.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly ssh_binary=${CADDY_ACTION20OA_RETRY_SSH_BIN:-ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
expected_local_gates() {
    printf '%s\n' working_directory inspector_regular inspector_executable inspector_hash \
        syntax shellcheck canonical_format collision_policy conditional_policy \
        multifile_grep_policy portable_awk_policy inspector_self_test
}
run_gate() {
    local action20oa_outer_label=$1
    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20oa_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20oa_outer_label" >&2
    return 1
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_regular test -f "$inspector" || return 1
    run_gate inspector_executable test -x "$inspector" || return 1
    run_gate inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$inspector" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check "$inspector" "$0" || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
}
safe_stream() {
    local action20oa_outer_stream=$1
    [[ "$(wc -c <"$action20oa_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20oa_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20oa_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20oa_outer_stream"
}
emit_stream() {
    local action20oa_outer_label=$1
    local action20oa_outer_stream=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action20oa_outer_label" "$(wc -c <"$action20oa_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20oa_outer_label" "$(line_count "$action20oa_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20oa_outer_label" "$(file_hash "$action20oa_outer_stream")"
    if safe_stream "$action20oa_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20oa_outer_label"
        if [[ -s "$action20oa_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20oa_outer_label"
            cat "$action20oa_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action20oa_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action20oa_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20oa_outer_label" >&2
    return 97
}
verify_transcript() {
    local action20oa_outer_stdout=$1
    local action20oa_outer_expected
    local action20oa_outer_observed
    local action20oa_outer_before
    local action20oa_outer_after

    action20oa_outer_expected=$("$inspector" --expected-checks) || return 1
    action20oa_outer_observed=$(sed -n 's/^action_20o_a_check_\([a-z0-9_]*\)=true$/\1/p' "$action20oa_outer_stdout") || return 1
    [[ "$action20oa_outer_observed" = "$action20oa_outer_expected" ]] || return 1
    [[ "$(grep -Ec '^action_20o_a_check_[a-z0-9_]+=false$' "$action20oa_outer_stdout" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fxc 'action_20o_a_value_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20o_a_value_dbus_snapshot_normalization=process_column_busctl_only' "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20o_a_check_count=63' "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20o_a_failed_check_count=0' "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20o_a_first_failure=none' "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    for action20oa_outer_query in ipv4_before ipv6_before dbus_before ipv4_after ipv6_after dbus_after; do
        [[ "$(grep -Fxc "action_20o_a_observation_${action20oa_outer_query}_status=0" "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
        [[ "$(grep -Fxc "action_20o_a_observation_${action20oa_outer_query}_classification=bounded_safe" "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    done
    for action20oa_outer_marker in read_only dbus_tree_invoked keepalived_reload keepalived_restart filesystem_mutations service_mutations vrrp_mutations vip_mutations remote_complete; do
        case "$action20oa_outer_marker" in
            read_only | remote_complete) action20oa_outer_value=true ;;
            *) action20oa_outer_value=false ;;
        esac
        [[ "$(grep -Fxc "action_20o_a_${action20oa_outer_marker}=${action20oa_outer_value}" "$action20oa_outer_stdout" || true)" -eq 1 ]] || return 1
    done
    action20oa_outer_before=$(sed -n 's/^action_20o_a_value_before_state_sha256=\([0-9a-f]*\)$/\1/p' "$action20oa_outer_stdout") || return 1
    action20oa_outer_after=$(sed -n 's/^action_20o_a_value_after_state_sha256=\([0-9a-f]*\)$/\1/p' "$action20oa_outer_stdout") || return 1
    [[ ${#action20oa_outer_before} -eq 64 ]] || return 1
    [[ "$action20oa_outer_after" = "$action20oa_outer_before" ]] || return 1
}
run_action() (
    local action20oa_outer_root
    local action20oa_outer_status=0
    action20oa_outer_root=$(mktemp -d /tmp/caddy-action20o-a-retry-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20oa_outer_root"' EXIT
    install -m 0600 /dev/null "$action20oa_outer_root/stdout" || return 1
    install -m 0600 /dev/null "$action20oa_outer_root/stderr" || return 1
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 "$target" "$remote_command" \
        <"$inspector" >"$action20oa_outer_root/stdout" 2>"$action20oa_outer_root/stderr" || action20oa_outer_status=$?
    emit_stream remote_stdout "$action20oa_outer_root/stdout" || return $?
    emit_stream remote_stderr "$action20oa_outer_root/stderr" || return $?
    printf '%s_remote_status=%s\n' "$prefix" "$action20oa_outer_status"
    [[ "$action20oa_outer_status" -eq 0 ]] || return "$action20oa_outer_status"
    [[ ! -s "$action20oa_outer_root/stderr" ]] || return 97
    verify_transcript "$action20oa_outer_root/stdout" || return 97
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_node_a_ssh_contacted=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_node_b_contacted=false\n%s_node_a_ssh_contacted=false\n%s_self_test_complete=true\n' "$prefix" "$prefix" "$prefix"
        ;;
    --validate-transcript)
        [[ $# -eq 2 && -f "$2" ]] || exit 64
        verify_transcript "$2"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates
        run_action
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--validate-transcript FILE]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
