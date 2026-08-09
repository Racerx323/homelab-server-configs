#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_b_outer
readonly target=pi@10.1.0.54
readonly remote_command='cd / && sudo -n /bin/bash -s --'
readonly inspector_sha256=9e99fda15f3d730916dca95ef91b96864233c22fde9b8dfa7312b1ce220f7a11
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-b-keepalived-dbus-postactivation-action20o-b.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly ssh_binary=${CADDY_ACTION20OB_SSH_BIN:-ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash syntax \
        shellcheck canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy root_cwd_policy inspector_self_test
}
run_gate() {
    local action20ob_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20ob_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20ob_outer_label" >&2
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
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$inspector" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" \
        --check "$inspector" "$0" || return 1
    run_gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" \
        --check "$0" || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
}
safe_stream() {
    local action20ob_outer_stream=$1

    [[ "$(wc -c <"$action20ob_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20ob_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20ob_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20ob_outer_stream"
}
emit_stream() {
    local action20ob_outer_label=$1
    local action20ob_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20ob_outer_label" "$(wc -c <"$action20ob_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20ob_outer_label" "$(line_count "$action20ob_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20ob_outer_label" "$(file_hash "$action20ob_outer_stream")"
    if safe_stream "$action20ob_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20ob_outer_label"
        if [[ -s "$action20ob_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20ob_outer_label"
            cat "$action20ob_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action20ob_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action20ob_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20ob_outer_label" >&2
    return 97
}
exact_line_once() {
    local action20ob_outer_file=$1
    local action20ob_outer_line=$2

    [[ "$(awk -v expected="$action20ob_outer_line" '$0 == expected { count++ } END { print count + 0 }' \
        "$action20ob_outer_file")" -eq 1 ]]
}
verify_transcript() {
    local action20ob_outer_stdout=$1
    local action20ob_outer_expected
    local action20ob_outer_observed
    local action20ob_outer_before
    local action20ob_outer_after
    local action20ob_outer_check_count

    action20ob_outer_expected=$("$inspector" --expected-checks) || return 1
    action20ob_outer_observed=$(sed -n 's/^action_20o_b_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action20ob_outer_stdout") || return 1
    [[ "$action20ob_outer_observed" = "$action20ob_outer_expected" ]] || return 1
    [[ "$(grep -Ec '^action_20o_b_check_[a-z0-9_]+=false$' "$action20ob_outer_stdout" || true)" -eq 0 ]] || return 1
    action20ob_outer_check_count=$(printf '%s\n' "$action20ob_outer_expected" | wc -l) || return 1
    exact_line_once "$action20ob_outer_stdout" \
        "action_20o_b_value_expected_check_count=$action20ob_outer_check_count" || return 1
    exact_line_once "$action20ob_outer_stdout" "action_20o_b_check_count=$action20ob_outer_check_count" || return 1
    exact_line_once "$action20ob_outer_stdout" 'action_20o_b_failed_check_count=0' || return 1
    exact_line_once "$action20ob_outer_stdout" 'action_20o_b_first_failure=none' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3' || return 1
    exact_line_once "$action20ob_outer_stdout" 'action_20o_b_value_dbus_service=org.keepalived.Vrrp1' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6' || return 1
    exact_line_once "$action20ob_outer_stdout" 'action_20o_b_value_dbus_state=Backup' || return 1
    exact_line_once "$action20ob_outer_stdout" \
        'action_20o_b_value_dbus_snapshot_normalization=process_column_busctl_only' || return 1
    for action20ob_outer_observation in \
        ip4_before ip6_before dbus_list_before dbus_tree_before \
        dbus_ipv4_state_before dbus_ipv6_state_before ip4_after ip6_after \
        dbus_list_after dbus_tree_after dbus_ipv4_state_after dbus_ipv6_state_after; do
        exact_line_once "$action20ob_outer_stdout" \
            "action_20o_b_observation_${action20ob_outer_observation}_status=0" || return 1
        exact_line_once "$action20ob_outer_stdout" \
            "action_20o_b_observation_${action20ob_outer_observation}_classification=bounded_safe" || return 1
    done
    action20ob_outer_before=$(sed -n 's/^action_20o_b_value_before_state_sha256=\([0-9a-f]*\)$/\1/p' \
        "$action20ob_outer_stdout") || return 1
    action20ob_outer_after=$(sed -n 's/^action_20o_b_value_after_state_sha256=\([0-9a-f]*\)$/\1/p' \
        "$action20ob_outer_stdout") || return 1
    [[ ${#action20ob_outer_before} -eq 64 ]] || return 1
    [[ "$action20ob_outer_after" = "$action20ob_outer_before" ]] || return 1
    for action20ob_outer_marker in read_only remote_complete; do
        exact_line_once "$action20ob_outer_stdout" "action_20o_b_${action20ob_outer_marker}=true" || return 1
    done
    for action20ob_outer_marker in health_helpers_invoked keepalived_reload keepalived_restart \
        filesystem_mutations service_mutations vrrp_mutations vip_mutations; do
        exact_line_once "$action20ob_outer_stdout" "action_20o_b_${action20ob_outer_marker}=false" || return 1
    done
}
run_action() (
    local action20ob_outer_root
    local action20ob_outer_status=0

    action20ob_outer_root=$(mktemp -d /tmp/caddy-action20o-b-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20ob_outer_root"' EXIT INT TERM
    install -m 0600 /dev/null "$action20ob_outer_root/stdout" || return 1
    install -m 0600 /dev/null "$action20ob_outer_root/stderr" || return 1
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 "$target" "$remote_command" \
        <"$inspector" >"$action20ob_outer_root/stdout" 2>"$action20ob_outer_root/stderr" || action20ob_outer_status=$?
    emit_stream remote_stdout "$action20ob_outer_root/stdout" || return $?
    emit_stream remote_stderr "$action20ob_outer_root/stderr" || return $?
    printf '%s_remote_status=%s\n' "$prefix" "$action20ob_outer_status"
    [[ "$action20ob_outer_status" -eq 0 ]] || return "$action20ob_outer_status"
    [[ ! -s "$action20ob_outer_root/stderr" ]] || return 97
    verify_transcript "$action20ob_outer_root/stdout" || return 97
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_node_a_ssh_contacted=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_health_helpers_invoked=false\n' "$prefix"
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
        printf '%s_node_b_contacted=false\n' "$prefix"
        printf '%s_node_a_ssh_contacted=false\n' "$prefix"
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --validate-transcript)
        [[ $# -eq 2 && -f "$2" ]] || exit 64
        verify_transcript "$2"
        ;;
    --transport-test)
        [[ $# -eq 1 && "$ssh_binary" != ssh ]] || exit 64
        run_action
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates
        run_action
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--validate-transcript FILE|--transport-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
