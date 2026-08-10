#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28j.sh
readonly transaction=$caddy_root/scripts/transact-node-a-caddy-failover-action28j.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-action28j-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly predecessor_inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28i.sh
readonly predecessor_inspector_sha256=44e52b61b09f1aa0e117c1da404e781de39111103d79573c6f2f3e6551952f5e
readonly node_a_installer=$caddy_root/scripts/install-node-a-protocol-v2-publisher-action28b.sh
readonly node_a_installer_sha256=f7b6af461dcd2ca108e3cb097424646a3604382081d0be4e162b2f933e822591
readonly node_a_acceptance=$caddy_root/scripts/inspect-node-a-publisher-postinstall-action28b-a.sh
readonly node_a_acceptance_sha256=a2b09a7ce5d9ba0481efd5d0eedd3a137ed7f29e4c7b691a102667c8195c66f3
readonly node_b_installer=$caddy_root/scripts/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh
readonly node_b_installer_sha256=b26eab687ed6dc19f118d532ae14dacf85b0aa9e8a39f031bf2ed2369fe7a0a5
readonly corrected_publisher=/usr/local/libexec/publish-release-v2.sh
readonly stale_publisher=/usr/local/sbin/caddy-publish-release

check_count=0
failed_check_count=0
first_failure=none
record_check() {
    local action28j_regression_label=$1
    shift
    check_count=$((check_count + 1))
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_regression_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action28j_regression_label"
        failed_check_count=$((failed_check_count + 1))
        [[ "$first_failure" != none ]] || first_failure=$action28j_regression_label
    fi
    return 0
}
command_fails() { ! "$@"; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

work_directory=$(mktemp -d /tmp/caddy-action28j-regression.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT

fake_ssh=$work_directory/ssh
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${CADDY_ACTION28J_FAKE_LOG:?}"
: "${CADDY_ACTION28J_INSPECTOR:?}"
: "${CADDY_ACTION28J_TRANSACTION:?}"
printf '%s\n' "$*" >>"$CADDY_ACTION28J_FAKE_LOG"
cat >/dev/null
command_line=$*
emit_checks() {
    local producer=$1
    local record_prefix=$2
    local label
    while IFS= read -r label; do
        printf '%s_check_%s=true\n' "$record_prefix" "$label"
    done < <(/bin/bash "$producer" --expected-checks)
    printf '%s_check_count=%s\n' "$record_prefix" "$(/bin/bash "$producer" --expected-checks | wc -l)"
    printf '%s_failed_check_count=0\n' "$record_prefix"
    printf '%s_first_failure=none\n' "$record_prefix"
    printf '%s_publisher_invoked=false\n' "$record_prefix"
    printf '%s_acceptance=true\n' "$record_prefix"
}
case "$command_line" in
    *'--node node-a --phase baseline'*)
        emit_checks "$CADDY_ACTION28J_INSPECTOR" action_28j_node_a_baseline
        ;;
    *'--node node-b --phase baseline'*)
        emit_checks "$CADDY_ACTION28J_INSPECTOR" action_28j_node_b_baseline
        ;;
    *'--node node-a --phase failed'*)
        emit_checks "$CADDY_ACTION28J_INSPECTOR" action_28j_node_a_failed
        printf '%s\n' \
            action_28j_node_a_failed_value_vrrp_state=FAULT \
            action_28j_node_a_failed_value_caddy_ipv4_count=0 \
            action_28j_node_a_failed_value_caddy_ipv6_count=0 \
            action_28j_node_a_failed_value_dns_ipv4_count=1 \
            action_28j_node_a_failed_value_dns_ipv6_count=1
        ;;
    *'--node node-b --phase failed'*)
        emit_checks "$CADDY_ACTION28J_INSPECTOR" action_28j_node_b_failed
        if [[ "${CADDY_ACTION28J_FAKE_CASE:-valid}" = wrong_node_b_state ]]; then
            printf 'action_28j_node_b_failed_value_vrrp_state=BACKUP\n'
        else
            printf 'action_28j_node_b_failed_value_vrrp_state=MASTER\n'
        fi
        printf '%s\n' \
            action_28j_node_b_failed_value_caddy_ipv4_count=1 \
            action_28j_node_b_failed_value_caddy_ipv6_count=1 \
            action_28j_node_b_failed_value_dns_ipv4_count=0 \
            action_28j_node_b_failed_value_dns_ipv6_count=0
        ;;
    *'--failover'*)
        emit_checks "$CADDY_ACTION28J_TRANSACTION" action_28j_transaction
        printf '%s\n' action_28j_transaction_value_mode=failover \
            action_28j_transaction_value_mutation_started=true
        ;;
    *'--rollback'*)
        emit_checks "$CADDY_ACTION28J_TRANSACTION" action_28j_transaction
        printf '%s\n' action_28j_transaction_value_mode=rollback \
            action_28j_transaction_value_mutation_started=true
        ;;
    *) exit 64 ;;
esac
FAKE_SSH
chmod 0755 "$fake_ssh"

expected_inspector=$work_directory/expected-inspector
sed -e "s/action_28i/action_28j/g" -e "s/action28i/action28j/g" -e "s#${stale_publisher}#${corrected_publisher}#g" "$predecessor_inspector" >"$expected_inspector"
record_check predecessor_inspector_immutable test "$(file_hash "$predecessor_inspector")" = "$predecessor_inspector_sha256"
record_check inspector_single_contract_change cmp -s "$expected_inspector" "$inspector"
record_check node_a_installer_immutable test "$(file_hash "$node_a_installer")" = "$node_a_installer_sha256"
record_check node_a_acceptance_immutable test "$(file_hash "$node_a_acceptance")" = "$node_a_acceptance_sha256"
record_check node_b_installer_immutable test "$(file_hash "$node_b_installer")" = "$node_b_installer_sha256"
record_check node_a_installer_path grep -Fq "$corrected_publisher" "$node_a_installer"
record_check node_a_acceptance_path grep -Fq "$corrected_publisher" "$node_a_acceptance"
record_check node_b_installer_path grep -Fq "$corrected_publisher" "$node_b_installer"
record_check stale_path_absent command_fails grep -Fq "$stale_publisher" "$inspector"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check transaction_self_test /bin/bash "$transaction" --self-test
record_check collision_policy /bin/bash "$collision_policy" "$inspector" "$transaction" "$outer" "$0"
# Exact literal verifies the production command boundary.
# shellcheck disable=SC2016
record_check stop_command_exact grep -Fq 'systemctl "$systemctl_verb" caddy.service' "$transaction"
record_check failover_verb_exact grep -Fq 'readonly systemctl_verb=stop' "$transaction"
record_check rollback_verb_exact grep -Fq 'readonly systemctl_verb=start' "$transaction"
record_check publisher_command_absent command_fails grep -Eq '^[[:space:]]*(caddy-publish-release|/usr/local/sbin/caddy-publish-release)[[:space:]]' "$transaction"
record_check emergency_flag_absent command_fails grep -Fq -- '--emergency' "$transaction"
record_check node_a_fault_contract grep -Fq 'expected_after_vrrp=FAULT' "$transaction"
record_check failover_before_emergency_plan grep -Fq 'emergency_publisher_invoked=false' "$outer"

valid_stdout=$work_directory/valid.stdout
valid_stderr=$work_directory/valid.stderr
: >"$work_directory/ssh.log"
valid_status=0
CADDY_ACTION28J_TEST_MODE=1 \
    CADDY_ACTION28J_SSH_PROGRAM="$fake_ssh" \
    CADDY_ACTION28J_FAKE_LOG="$work_directory/ssh.log" \
    CADDY_ACTION28J_INSPECTOR="$inspector" \
    CADDY_ACTION28J_TRANSACTION="$transaction" \
    /bin/bash "$outer" >"$valid_stdout" 2>"$valid_stderr" || valid_status=$?
record_check production_status_zero test "$valid_status" -eq 0
record_check production_stderr_empty test ! -s "$valid_stderr"
record_check production_acceptance grep -Fqx 'action_28j_outer_acceptance=true' "$valid_stdout"
record_check production_node_a_stopped grep -Fqx 'action_28j_outer_node_a_caddy_stopped=true' "$valid_stdout"
record_check production_node_b_master grep -Fqx 'action_28j_outer_node_b_master=true' "$valid_stdout"
record_check production_publisher_absent grep -Fqx 'action_28j_outer_emergency_publisher_invoked=false' "$valid_stdout"
record_check production_failover_once test "$(awk 'index($0, "--failover") { count++ } END { print count + 0 }' "$work_directory/ssh.log")" -eq 1
record_check production_rollback_absent command_fails grep -q -- '--rollback' "$work_directory/ssh.log"
record_check production_node_a_contacted grep -Fq 'pi@10.1.0.53' "$work_directory/ssh.log"
record_check production_node_b_contacted grep -Fq 'pi@10.1.0.54' "$work_directory/ssh.log"
record_check production_remote_cwd grep -Fq 'cd / && sudo -n /bin/bash -s --' "$work_directory/ssh.log"

record_check predecessor_negative_coverage grep -Fq wrong_node_b_state_rejected "$caddy_root/tests/action28i-node-a-first-caddy-failover-regression.sh"
printf '%s_check_count=%s\n' "$prefix" "$check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_real_outer_path_exercised=true\n' "$prefix"
printf '%s_live_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
