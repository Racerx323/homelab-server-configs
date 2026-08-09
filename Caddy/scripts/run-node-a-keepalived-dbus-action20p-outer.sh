#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly node_a_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly node_b_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly transaction_sha256=b97d189689e6c6c9f043731c4ae824650c6000b5f609ecb75b7b943cb03bceec
readonly observer_sha256=386032ec1d8f8545e1222acdd81f667a05bd2908a8acc7778f4e5008aa57fc60
readonly regression_sha256=fc8304aa5988e233c9b9bc1b10cc128b6cab2cd33731270840652b3606c0585d
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction=$script_directory/activate-node-a-keepalived-dbus-action20p.sh
readonly observer=$script_directory/inspect-node-b-node-a-dbus-peer-action20p.sh
readonly regression=$caddy_root/tests/action20p-node-a-keepalived-dbus-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly ssh_binary=${CADDY_ACTION20P_SSH_BIN:-/usr/bin/ssh}

work_root=
node_a_activated=false

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
require_hash() {
    local action20p_outer_expected=$1
    local action20p_outer_path=$2

    [[ -f "$action20p_outer_path" && ! -L "$action20p_outer_path" ]] || return 1
    [[ "$(file_hash "$action20p_outer_path")" = "$action20p_outer_expected" ]]
}
run_gate() {
    local action20p_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20p_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20p_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_regular transaction_executable transaction_hash \
        observer_regular observer_executable observer_hash regression_regular \
        regression_executable regression_hash syntax shellcheck canonical_format \
        collision_policy conditional_policy output_evidence_policy multifile_grep_policy \
        portable_awk_policy accepted_live_hash_policy root_cwd_policy \
        transaction_self_test observer_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate transaction_regular test -f "$transaction" || return 1
    run_gate transaction_executable test -x "$transaction" || return 1
    run_gate transaction_hash require_hash "$transaction_sha256" "$transaction" || return 1
    run_gate observer_regular test -f "$observer" || return 1
    run_gate observer_executable test -x "$observer" || return 1
    run_gate observer_hash require_hash "$observer_sha256" "$observer" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$observer" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate transaction_self_test /bin/bash "$transaction" --self-test || return 1
    run_gate observer_self_test /bin/bash "$observer" --self-test || return 1
    if [[ "${CADDY_ACTION20P_TEST_MODE:-}" = 1 ]]; then
        run_gate regression true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action20p_outer_stream=$1

    [[ "$(wc -c <"$action20p_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20p_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20p_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20p_outer_stream"
}
emit_stream() {
    local action20p_outer_label=$1
    local action20p_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20p_outer_label" "$(wc -c <"$action20p_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20p_outer_label" "$(line_count "$action20p_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20p_outer_label" "$(file_hash "$action20p_outer_stream")"
    if ! safe_stream "$action20p_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20p_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20p_outer_label"
    if [[ -s "$action20p_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20p_outer_label"
        cat "$action20p_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action20p_outer_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$action20p_outer_label"
    fi
}
build_payload() {
    local action20p_outer_assignment=$1
    local action20p_outer_source=$2
    local action20p_outer_payload=$3

    {
        printf '%s\n' "$action20p_outer_assignment"
        cat "$action20p_outer_source"
    } >"$action20p_outer_payload" || return 1
    chmod 0600 "$action20p_outer_payload"
    /bin/bash -n "$action20p_outer_payload"
}
run_remote() {
    local action20p_outer_label=$1
    local action20p_outer_target=$2
    local action20p_outer_payload=$3
    local action20p_outer_status=0

    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 "$action20p_outer_target" \
        'cd / && sudo -n /bin/bash -s --' <"$action20p_outer_payload" \
        >"$work_root/$action20p_outer_label.stdout" \
        2>"$work_root/$action20p_outer_label.stderr" || action20p_outer_status=$?
    emit_stream "${action20p_outer_label}_stdout" "$work_root/$action20p_outer_label.stdout" || return 97
    emit_stream "${action20p_outer_label}_stderr" "$work_root/$action20p_outer_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$action20p_outer_label" "$action20p_outer_status"
    [[ "$action20p_outer_status" -eq 0 ]]
}
expected_labels_match() {
    local action20p_outer_transcript=$1
    local action20p_outer_prefix=$2
    local action20p_outer_expected=$3
    local action20p_outer_actual=$4

    sed -n "s/^${action20p_outer_prefix}_check_\([a-z0-9_]*\)=true$/\1/p" \
        "$action20p_outer_transcript" >"$action20p_outer_actual" || return 1
    diff -u "$action20p_outer_expected" "$action20p_outer_actual"
}
validate_observer() {
    local action20p_outer_phase=$1
    local action20p_outer_transcript=$2
    local action20p_outer_error=$3
    local action20p_outer_expected=$work_root/observer-$action20p_outer_phase.expected
    local action20p_outer_actual=$work_root/observer-$action20p_outer_phase.actual

    # conditional-validator-explicit-failures-begin
    [[ ! -s "$action20p_outer_error" ]] || return 1
    ! grep -Eq '^action_20p_peer_check_[a-z0-9_]+=false$' "$action20p_outer_transcript" || return 1
    /bin/bash "$observer" --expected-checks "$action20p_outer_phase" >"$action20p_outer_expected" || return 1
    expected_labels_match "$action20p_outer_transcript" action_20p_peer \
        "$action20p_outer_expected" "$action20p_outer_actual" || return 1
    [[ "$(grep -Fxc "action_20p_peer_value_phase=$action20p_outer_phase" "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "action_20p_peer_value_main_sha256=$node_b_main_sha256" "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_peer_read_only=true' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_peer_complete=true' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}
validate_transaction() {
    local action20p_outer_transcript=$1
    local action20p_outer_error=$2
    local action20p_outer_expected=$work_root/transaction.expected
    local action20p_outer_actual=$work_root/transaction.actual

    # conditional-validator-explicit-failures-begin
    [[ ! -s "$action20p_outer_error" ]] || return 1
    ! grep -Eq '^action_20p_check_[a-z0-9_]+=false$' "$action20p_outer_transcript" || return 1
    /bin/bash "$transaction" --expected-checks >"$action20p_outer_expected" || return 1
    expected_labels_match "$action20p_outer_transcript" action_20p \
        "$action20p_outer_expected" "$action20p_outer_actual" || return 1
    [[ "$(grep -Fxc "action_20p_value_main_sha256=$node_a_main_sha256" "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "action_20p_value_health_sha256=$node_a_health_sha256" "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_value_unicast_ttl=255' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_dbus_runtime_active=true' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_unicast_ttl_runtime_activation=true' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20p_complete=true' "$action20p_outer_transcript" || true)" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}
rollback_node_a() {
    local action20p_outer_payload=$work_root/node-a-rollback.payload

    build_payload 'ACTION20P_MODE=rollback_only' "$transaction" "$action20p_outer_payload" || return 125
    run_remote node_a_rollback "$node_a_target" "$action20p_outer_payload" || return 125
    grep -Fqx 'action_20p_rollback_only_complete=true' "$work_root/node_a_rollback.stdout" || return 125
}
cleanup() {
    local action20p_outer_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ "$node_a_activated" = true ]]; then
        rollback_node_a || action20p_outer_cleanup_status=125
    fi
    if [[ -n "$work_root" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action20p_outer_cleanup_status"
}
self_test() {
    local action20p_outer_gate

    [[ "$(expected_local_gates | wc -l)" -eq 23 ]] || return 1
    [[ "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" -eq 23 ]] || return 1
    [[ "$node_a_target" = pi@10.1.0.53 ]] || return 1
    [[ "$node_b_target" = pi@10.1.0.54 ]] || return 1
    while IFS= read -r action20p_outer_gate; do
        printf '%s_gate_%s=true\n' "$prefix" "$action20p_outer_gate"
    done < <(expected_local_gates)
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        exit 0
        ;;
    --transport-test)
        [[ $# -eq 1 && "${CADDY_ACTION20P_TEST_MODE:-}" = 1 ]] || exit 64
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20p-outer.XXXXXX)
readonly work_root
chmod 0700 "$work_root"
trap cleanup EXIT INT TERM

build_payload 'ACTION20P_PHASE=pre' "$observer" "$work_root/node-b-pre.payload"
run_remote node_b_pre "$node_b_target" "$work_root/node-b-pre.payload"
validate_observer pre "$work_root/node_b_pre.stdout" "$work_root/node_b_pre.stderr"

build_payload 'ACTION20P_MODE=activate' "$transaction" "$work_root/node-a-activate.payload"
run_remote node_a_activate "$node_a_target" "$work_root/node-a-activate.payload"
node_a_activated=true
validate_transaction "$work_root/node_a_activate.stdout" "$work_root/node_a_activate.stderr"

build_payload 'ACTION20P_PHASE=post' "$observer" "$work_root/node-b-post.payload"
run_remote node_b_post "$node_b_target" "$work_root/node-b-post.payload"
validate_observer post "$work_root/node_b_post.stdout" "$work_root/node_b_post.stderr"

node_a_activated=false
printf '%s_node_b_preaccepted=true\n' "$prefix"
printf '%s_node_a_reload=true\n' "$prefix"
printf '%s_node_a_dbus_active=true\n' "$prefix"
printf '%s_node_a_unicast_ttl_active=true\n' "$prefix"
printf '%s_node_b_ttl_hl_quiet_window=true\n' "$prefix"
printf '%s_rollback=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
