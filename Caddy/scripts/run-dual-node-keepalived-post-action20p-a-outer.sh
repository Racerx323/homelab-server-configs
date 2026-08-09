#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_a_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_remote_command='cd / && sudo -n /bin/bash -s -- --node node-a'
readonly node_b_remote_command='cd / && sudo -n /bin/bash -s -- --node node-b'
readonly inspector_sha256=55bf9878744e75ff7f79cb93d565cd4c5bb3e500bc2a575c04333e94456ee2f8
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-dual-node-keepalived-post-action20p-a.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly ssh_binary=${CADDY_ACTION20PA_SSH_BIN:-ssh}

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
    local action20pa_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20pa_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20pa_outer_gate_label" >&2
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
    local action20pa_outer_stream=$1

    [[ "$(wc -c <"$action20pa_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20pa_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20pa_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20pa_outer_stream"
}
emit_stream() {
    local action20pa_outer_stream_label=$1
    local action20pa_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20pa_outer_stream_label" "$(wc -c <"$action20pa_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20pa_outer_stream_label" "$(line_count "$action20pa_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20pa_outer_stream_label" "$(file_hash "$action20pa_outer_stream")"
    if safe_stream "$action20pa_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20pa_outer_stream_label"
        if [[ -s "$action20pa_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20pa_outer_stream_label"
            cat "$action20pa_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action20pa_outer_stream_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action20pa_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20pa_outer_stream_label" >&2
    return 97
}
exact_line_once() {
    local action20pa_outer_file=$1
    local action20pa_outer_line=$2

    [[ "$(awk -v expected="$action20pa_outer_line" '$0 == expected { count++ } END { print count + 0 }' \
        "$action20pa_outer_file")" -eq 1 ]]
}
verify_transcript() {
    local action20pa_outer_stdout=$1
    local action20pa_outer_role=$2
    local action20pa_outer_node_label=${action20pa_outer_role//-/_}
    local action20pa_outer_remote_prefix=action_20p_a_${action20pa_outer_node_label}
    local action20pa_outer_expected
    local action20pa_outer_observed
    local action20pa_outer_expected_count
    local action20pa_outer_before_hash
    local action20pa_outer_after_hash
    local action20pa_outer_expected_main
    local action20pa_outer_expected_fragment
    local action20pa_outer_expected_state
    local action20pa_outer_expected_count_value

    action20pa_outer_expected=$("$inspector" --expected-checks) || return 1
    action20pa_outer_observed=$(sed -n \
        "s/^${action20pa_outer_remote_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action20pa_outer_stdout") || return 1
    [[ "$action20pa_outer_observed" = "$action20pa_outer_expected" ]] || return 1
    [[ "$(grep -Ec "^${action20pa_outer_remote_prefix}_check_[a-z0-9_]+=false$" \
        "$action20pa_outer_stdout" || true)" -eq 0 ]] || return 1
    action20pa_outer_expected_count=$(printf '%s\n' "$action20pa_outer_expected" | wc -l) || return 1
    case "$action20pa_outer_role" in
        node-a)
            action20pa_outer_expected_main=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
            action20pa_outer_expected_fragment=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
            action20pa_outer_expected_state=Master
            action20pa_outer_expected_count_value=1
            ;;
        node-b)
            action20pa_outer_expected_main=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
            action20pa_outer_expected_fragment=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
            action20pa_outer_expected_state=Backup
            action20pa_outer_expected_count_value=0
            ;;
        *) return 1 ;;
    esac
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_expected_check_count=$action20pa_outer_expected_count" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_check_count=$action20pa_outer_expected_count" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_failed_check_count=0" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_first_failure=none" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_main_sha256=$action20pa_outer_expected_main" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_fragment_sha256=$action20pa_outer_expected_fragment" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_dbus_state=$action20pa_outer_expected_state" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_caddy_ipv4_count=$action20pa_outer_expected_count_value" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_value_caddy_ipv6_count=$action20pa_outer_expected_count_value" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_observation_ttl_hl_quiet_window_status=0" || return 1
    exact_line_once "$action20pa_outer_stdout" \
        "${action20pa_outer_remote_prefix}_observation_ttl_hl_quiet_window_classification=bounded_safe" || return 1
    action20pa_outer_before_hash=$(sed -n \
        "s/^${action20pa_outer_remote_prefix}_value_before_state_sha256=\\([0-9a-f]*\\)$/\\1/p" \
        "$action20pa_outer_stdout") || return 1
    action20pa_outer_after_hash=$(sed -n \
        "s/^${action20pa_outer_remote_prefix}_value_after_state_sha256=\\([0-9a-f]*\\)$/\\1/p" \
        "$action20pa_outer_stdout") || return 1
    [[ ${#action20pa_outer_before_hash} -eq 64 ]] || return 1
    [[ "$action20pa_outer_after_hash" = "$action20pa_outer_before_hash" ]] || return 1
    for action20pa_outer_true_marker in read_only remote_complete; do
        exact_line_once "$action20pa_outer_stdout" \
            "${action20pa_outer_remote_prefix}_${action20pa_outer_true_marker}=true" || return 1
    done
    for action20pa_outer_false_marker in keepalived_reload keepalived_restart \
        filesystem_mutations service_mutations vrrp_mutations vip_mutations; do
        exact_line_once "$action20pa_outer_stdout" \
            "${action20pa_outer_remote_prefix}_${action20pa_outer_false_marker}=false" || return 1
    done
}
run_remote() {
    local action20pa_outer_target=$1
    local action20pa_outer_remote_command_value=$2
    local action20pa_outer_stdout=$3
    local action20pa_outer_stderr=$4
    local action20pa_outer_status_variable=$5
    local action20pa_outer_remote_status=0

    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        "$action20pa_outer_target" "$action20pa_outer_remote_command_value" \
        <"$inspector" >"$action20pa_outer_stdout" 2>"$action20pa_outer_stderr" || action20pa_outer_remote_status=$?
    printf -v "$action20pa_outer_status_variable" '%s' "$action20pa_outer_remote_status"
}
run_action() (
    local action20pa_outer_root
    local action20pa_outer_node_a_status=0
    local action20pa_outer_node_b_status=0

    action20pa_outer_root=$(mktemp -d /tmp/caddy-action20p-a-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_outer_root"' EXIT INT TERM
    for action20pa_outer_capture in node-a.stdout node-a.stderr node-b.stdout node-b.stderr; do
        install -m 0600 /dev/null "$action20pa_outer_root/$action20pa_outer_capture" || return 1
    done
    run_remote "$node_a_target" "$node_a_remote_command" \
        "$action20pa_outer_root/node-a.stdout" "$action20pa_outer_root/node-a.stderr" \
        action20pa_outer_node_a_status
    run_remote "$node_b_target" "$node_b_remote_command" \
        "$action20pa_outer_root/node-b.stdout" "$action20pa_outer_root/node-b.stderr" \
        action20pa_outer_node_b_status
    for action20pa_outer_node in node-a node-b; do
        emit_stream "${action20pa_outer_node//-/_}_stdout" \
            "$action20pa_outer_root/$action20pa_outer_node.stdout" || return $?
        emit_stream "${action20pa_outer_node//-/_}_stderr" \
            "$action20pa_outer_root/$action20pa_outer_node.stderr" || return $?
    done
    printf '%s_node_a_status=%s\n' "$prefix" "$action20pa_outer_node_a_status"
    printf '%s_node_b_status=%s\n' "$prefix" "$action20pa_outer_node_b_status"
    [[ "$action20pa_outer_node_a_status" -eq 0 ]] || return "$action20pa_outer_node_a_status"
    [[ "$action20pa_outer_node_b_status" -eq 0 ]] || return "$action20pa_outer_node_b_status"
    [[ ! -s "$action20pa_outer_root/node-a.stderr" ]] || return 97
    [[ ! -s "$action20pa_outer_root/node-b.stderr" ]] || return 97
    verify_transcript "$action20pa_outer_root/node-a.stdout" node-a || return 97
    verify_transcript "$action20pa_outer_root/node-b.stdout" node-b || return 97
    printf '%s_single_caddy_ipv4_owner=true\n' "$prefix"
    printf '%s_single_caddy_ipv6_owner=true\n' "$prefix"
    printf '%s_node_a_master=true\n' "$prefix"
    printf '%s_node_b_backup=true\n' "$prefix"
    printf '%s_dual_node_ttl_hl_quiet=true\n' "$prefix"
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=true\n' "$prefix"
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
        printf '%s_node_a_contacted=false\n' "$prefix"
        printf '%s_node_b_contacted=false\n' "$prefix"
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --validate-transcript)
        [[ $# -eq 3 && -f "$2" && ("$3" = node-a || "$3" = node-b) ]] || exit 64
        verify_transcript "$2" "$3"
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
    *) exit 64 ;;
esac
