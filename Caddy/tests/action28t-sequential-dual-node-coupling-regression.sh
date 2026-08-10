#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28t_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-dual-node-protocol-compatible-coupling-action28t-outer.sh
readonly transaction=$caddy_root/scripts/transact-dual-node-protocol-compatible-coupling-action28t.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh

check() {
    local action28t_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28t_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28t_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then return 1; fi
    return 0
}
write_mock() {
    local action28t_regression_mock=$1

    # The single-quoted body is the generated mock program.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/bin:/bin' 'export PATH' \
            'count_file=${ACTION28T_MOCK_COUNT_FILE:?}' \
            'capture_root=${ACTION28T_MOCK_CAPTURE_ROOT:?}' \
            'transaction=${ACTION28T_MOCK_TRANSACTION:?}' \
            'node_a_inspector=${ACTION28T_MOCK_NODE_A_INSPECTOR:?}' \
            'node_b_inspector=${ACTION28T_MOCK_NODE_B_INSPECTOR:?}' \
            'count=0' '[[ ! -s "$count_file" ]] || read -r count <"$count_file"' \
            'count=$((count + 1))' 'printf '\''%s\n'\'' "$count" >"$count_file"' \
            'input=$capture_root/call-$count.input' 'cat >"$input"' \
            'printf '\''%s\n'\'' "$*" >"$capture_root/call-$count.args"' \
            'target=' 'for argument in "$@"; do case "$argument" in pi@*) target=$argument ;; esac; done' \
            'printf '\''%s\n'\'' "$target" >"$capture_root/call-$count.target"' \
            'emit_checks() { local source=$1 option=$2 output_prefix=$3 label; while IFS= read -r label; do printf '\''%s_check_%s=true\n'\'' "$output_prefix" "$label"; done < <("$source" "$option"); }' \
            'if grep -Fq '\''set -- --accept node_b'\'' "$input" && [[ "${ACTION28T_MOCK_FAIL_NODE_B_ACCEPT:-}" = 1 ]]; then exit 1; fi' \
            'if grep -Fq -- '\''--apply node_b'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-apply-checks action_28t_remote_apply' \
            '  printf '\''%s\n'\'' action_28t_remote_apply_first_failure=none action_28t_remote_apply_role=node_b action_28t_remote_apply_transition_ttl_permitted=true action_28t_remote_apply_acceptance=true' \
            'elif grep -Fq -- '\''--apply node_a'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-apply-checks action_28t_remote_apply' \
            '  printf '\''%s\n'\'' action_28t_remote_apply_first_failure=none action_28t_remote_apply_role=node_a action_28t_remote_apply_transition_ttl_permitted=false action_28t_remote_apply_acceptance=true' \
            'elif grep -Fq '\''set -- --accept node_a'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-accept-checks action_28t_remote_accept' \
            '  printf '\''%s\n'\'' action_28t_remote_accept_first_failure=none action_28t_remote_accept_role=node_a action_28t_remote_accept_acceptance=true' \
            'elif grep -Fq '\''set -- --accept node_b'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-accept-checks action_28t_remote_accept' \
            '  printf '\''%s\n'\'' action_28t_remote_accept_first_failure=none action_28t_remote_accept_role=node_b action_28t_remote_accept_acceptance=true' \
            'elif grep -Fq '\''set -- --rollback node_a'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-rollback-checks action_28t_remote_rollback' \
            '  printf '\''%s\n'\'' action_28t_remote_rollback_role=node_a action_28t_remote_rollback_acceptance=true action_28t_remote_rollback_first_failure=none' \
            'elif grep -Fq '\''set -- --rollback node_b'\'' "$input"; then' \
            '  emit_checks "$transaction" --expected-rollback-checks action_28t_remote_rollback' \
            '  printf '\''%s\n'\'' action_28t_remote_rollback_role=node_b action_28t_remote_rollback_acceptance=true action_28t_remote_rollback_first_failure=none' \
            'elif [[ "$target" = pi@10.1.0.53 ]]; then' \
            '  emit_checks "$node_a_inspector" --expected-checks action_28m_b' \
            '  printf '\''%s\n'\'' action_28m_b_first_failure=none action_28m_b_mutation=false action_28m_b_acceptance=true' \
            'elif [[ "$target" = pi@10.1.0.54 ]]; then' \
            '  emit_checks "$node_b_inspector" --expected-checks action_28p_a_node_b' \
            '  printf '\''%s\n'\'' action_28p_a_node_b_first_failure=none action_28p_a_node_b_mutation=false action_28p_a_node_b_acceptance=true' \
            'else exit 64; fi'
    } >"$action28t_regression_mock"
    chmod 0700 "$action28t_regression_mock"
}
run_scenario() {
    local action28t_regression_root=$1
    local action28t_regression_failure=$2
    local action28t_regression_status=0

    install -d -m 0700 "$action28t_regression_root/capture" "$action28t_regression_root/evidence"
    install -m 0600 /dev/null "$action28t_regression_root/count"
    write_mock "$action28t_regression_root/mock-ssh"
    ACTION28T_MOCK_COUNT_FILE=$action28t_regression_root/count \
        ACTION28T_MOCK_CAPTURE_ROOT=$action28t_regression_root/capture \
        ACTION28T_MOCK_TRANSACTION=$transaction \
        ACTION28T_MOCK_NODE_A_INSPECTOR=$node_a_inspector \
        ACTION28T_MOCK_NODE_B_INSPECTOR=$node_b_inspector \
        ACTION28T_MOCK_FAIL_NODE_B_ACCEPT=$action28t_regression_failure \
        CADDY_ACTION28T_TEST_MODE=1 \
        CADDY_ACTION28T_TEST_SKIP_LOCAL_GATES=1 \
        CADDY_ACTION28T_SSH_BIN=$action28t_regression_root/mock-ssh \
        CADDY_ACTION28T_EVIDENCE_ROOT=$action28t_regression_root/evidence \
        /bin/bash "$outer" >"$action28t_regression_root/stdout" \
        2>"$action28t_regression_root/stderr" || action28t_regression_status=$?
    printf '%s\n' "$action28t_regression_status" >"$action28t_regression_root/status"
}

root=$(mktemp -d /tmp/caddy-action28t-regression.XXXXXX)
readonly root
cleanup() { rm -rf -- "$root"; }
trap cleanup EXIT

run_scenario "$root/success" 0
printf '%s\n' \
    '2026-08-10 node Keepalived_vrrp[1]: (PIHOLE_IPV6) TTL/HL 64 not in range 255 - 255' \
    >"$root/allowed-ttl"
printf '%s\n' \
    '2026-08-10 node Keepalived_vrrp[1]: (PIHOLE_IPV6) TTL/HL 63 not in range 255 - 255' \
    >"$root/rejected-ttl"
check exact_transitional_ttl_accepted "$transaction" --transition-test "$root/allowed-ttl"
check altered_transitional_ttl_rejected command_rejected \
    "$transaction" --transition-test "$root/rejected-ttl"
check success_status_zero grep -Fqx 0 "$root/success/status"
check success_call_count grep -Fqx 6 "$root/success/count"
check success_node_order test "$(cat "$root/success/capture"/call-{1..6}.target | paste -sd, -)" = \
    pi@10.1.0.53,pi@10.1.0.54,pi@10.1.0.54,pi@10.1.0.53,pi@10.1.0.54,pi@10.1.0.53
check node_b_apply_contract grep -Fq -- '--apply node_b' "$root/success/capture/call-3.input"
check node_a_apply_contract grep -Fq -- '--apply node_a' "$root/success/capture/call-4.input"
check node_b_candidate_bundled grep -Fq 'keepalived-node_b.conf' "$root/success/capture/call-3.input"
check node_a_candidate_bundled grep -Fq 'keepalived-node_a.conf' "$root/success/capture/call-4.input"
check node_b_accept_contract grep -Fq 'set -- --accept node_b' "$root/success/capture/call-5.input"
check node_a_accept_contract grep -Fq 'set -- --accept node_a' "$root/success/capture/call-6.input"
check sequential_declaration grep -Fqx 'action_28t_outer_simultaneous_reload=false' "$root/success/stdout"
check transition_gate grep -Fqx 'action_28t_outer_gate_transition_window_bounded=true' "$root/success/stdout"
check success_complete grep -Fqx 'action_28t_outer_complete=true' "$root/success/stdout"

run_scenario "$root/failure" 1
check failure_rejected command_rejected grep -Fqx 0 "$root/failure/status"
check failure_call_count grep -Fqx 7 "$root/failure/count"
check rollback_node_a_first grep -Fq 'set -- --rollback node_a' "$root/failure/capture/call-6.input"
check rollback_node_b_second grep -Fq 'set -- --rollback node_b' "$root/failure/capture/call-7.input"
check failure_not_complete test "$(grep -Fxc 'action_28t_outer_complete=true' "$root/failure/stdout" || true)" -eq 0

printf '%s_check_count=19\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_production_path_exercised=true\n' "$prefix"
printf '%s_reverse_rollback_verified=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
