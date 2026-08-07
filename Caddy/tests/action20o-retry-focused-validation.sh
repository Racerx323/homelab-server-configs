#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_retry_focused_validation
readonly transaction_sha256=8c23b508159844839bb36f8c007eaa784b7c16076cb645bb06357ef65a8b9058
readonly regression_sha256=a1b56fc6760b27292301b643d26cd62bc355b9437a384b9d306fb6bb8b820282
readonly outer_sha256=799442774f62d00b29290aa6b6a7b7a1e6d6e54df7a705fa552dc3c8cde81836
readonly original_transaction_sha256=a445f3276231e147b7ee96c9f58561f2287ac50f91503fb64ec2d6581e24226f
readonly stale_source_sha256=9aa36b63bd42ff813074479820d3b0cd0137518f4cb03aa098a0781be9f1f148
readonly corrected_source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/activate-node-b-keepalived-dbus-action20o-retry.sh
readonly original_transaction=$caddy_root/scripts/activate-node-b-keepalived-dbus-action20o.sh
readonly regression=$test_directory/action20o-retry-node-b-keepalived-dbus-regression.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-action20o-retry-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20o_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20o_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20o_focused_label" >&2
    return 1
}
reload_scope_exact() {
    [[ "$(grep -Ec 'systemctl reload keepalived\.service' "$transaction" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Ec 'systemctl restart keepalived\.service' "$transaction" || true)" -eq 2 ]] || return 1
    grep -Fq 'mutation_started=true' "$transaction" || return 1
    grep -Fq 'rollback_transaction' "$transaction" || return 1
    grep -Fq 'expected_rollback_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' "$transaction" || return 1
}
dbus_contract_exact() {
    grep -Fq 'readonly dbus_service=org.keepalived.Vrrp1' "$transaction" || return 1
    grep -Fq 'readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4' "$transaction" || return 1
    grep -Fq 'readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6' "$transaction" || return 1
    # These assertions search for literal production expressions.
    # shellcheck disable=SC2016
    grep -Fq 'get-property "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State' "$transaction" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'get-property "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State' "$transaction" || return 1
}
definition_only_contract() {
    ! grep -Eq '(^|[[:space:]])ssh[[:space:]]' "$transaction" || return 1
    grep -Fq 'readonly expected_target=pi@10.1.0.54' "$outer" || return 1
    grep -Fq "printf '%s_node_a_ssh_contacted=false" "$outer" || return 1
}
source_correction_exact() {
    cmp -s \
        <(sed "s/$stale_source_sha256/$corrected_source_sha256/" "$original_transaction") \
        "$transaction" || return 1
    [[ "$(grep -Foc "$stale_source_sha256" "$original_transaction")" -eq 1 ]] || return 1
    [[ "$(grep -Foc "$corrected_source_sha256" "$original_transaction" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Foc "$stale_source_sha256" "$transaction" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Foc "$corrected_source_sha256" "$transaction")" -eq 1 ]]
}

record_check original_transaction_hash test "$(file_hash "$original_transaction")" = "$original_transaction_sha256"
record_check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check syntax /bin/bash -n "$transaction" "$regression" "$outer" "$0"
record_check shellcheck shellcheck "$transaction" "$regression" "$outer" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$regression" "$outer" "$0"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$transaction" "$regression" "$outer" "$0"
record_check executable_policy /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
record_check outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$transaction" "$regression" "$outer" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$transaction" "$regression" "$outer" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
record_check transaction_self_test /bin/bash "$transaction" --self-test
record_check source_correction_exact source_correction_exact
record_check reload_scope reload_scope_exact
record_check dbus_contract dbus_contract_exact
record_check definition_only definition_only_contract
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_activation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_persistent_live_mutations=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
