#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28i_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28i.sh
readonly transaction=$caddy_root/scripts/transact-node-a-caddy-failover-action28i.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-action28i-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh

check_count=0
failed_check_count=0
first_failure=none
record_check() {
    local action28i_regression_label=$1
    shift
    check_count=$((check_count + 1))
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28i_regression_label"
    else
        printf '%s_check_%s=false\n' "$prefix" "$action28i_regression_label"
        failed_check_count=$((failed_check_count + 1))
        [[ "$first_failure" != none ]] || first_failure=$action28i_regression_label
    fi
    return 0
}
command_fails() { ! "$@"; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

work_directory=$(mktemp -d /tmp/caddy-action28i-regression.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT

fake_ssh=$work_directory/ssh
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${CADDY_ACTION28I_FAKE_LOG:?}"
: "${CADDY_ACTION28I_INSPECTOR:?}"
: "${CADDY_ACTION28I_TRANSACTION:?}"
printf '%s\n' "$*" >>"$CADDY_ACTION28I_FAKE_LOG"
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
        emit_checks "$CADDY_ACTION28I_INSPECTOR" action_28i_node_a_baseline
        ;;
    *'--node node-b --phase baseline'*)
        emit_checks "$CADDY_ACTION28I_INSPECTOR" action_28i_node_b_baseline
        ;;
    *'--node node-a --phase failed'*)
        emit_checks "$CADDY_ACTION28I_INSPECTOR" action_28i_node_a_failed
        printf '%s\n' \
            action_28i_node_a_failed_value_vrrp_state=FAULT \
            action_28i_node_a_failed_value_caddy_ipv4_count=0 \
            action_28i_node_a_failed_value_caddy_ipv6_count=0 \
            action_28i_node_a_failed_value_dns_ipv4_count=1 \
            action_28i_node_a_failed_value_dns_ipv6_count=1
        ;;
    *'--node node-b --phase failed'*)
        emit_checks "$CADDY_ACTION28I_INSPECTOR" action_28i_node_b_failed
        if [[ "${CADDY_ACTION28I_FAKE_CASE:-valid}" = wrong_node_b_state ]]; then
            printf 'action_28i_node_b_failed_value_vrrp_state=BACKUP\n'
        else
            printf 'action_28i_node_b_failed_value_vrrp_state=MASTER\n'
        fi
        printf '%s\n' \
            action_28i_node_b_failed_value_caddy_ipv4_count=1 \
            action_28i_node_b_failed_value_caddy_ipv6_count=1 \
            action_28i_node_b_failed_value_dns_ipv4_count=0 \
            action_28i_node_b_failed_value_dns_ipv6_count=0
        ;;
    *'--failover'*)
        emit_checks "$CADDY_ACTION28I_TRANSACTION" action_28i_transaction
        printf '%s\n' action_28i_transaction_value_mode=failover \
            action_28i_transaction_value_mutation_started=true
        ;;
    *'--rollback'*)
        emit_checks "$CADDY_ACTION28I_TRANSACTION" action_28i_transaction
        printf '%s\n' action_28i_transaction_value_mode=rollback \
            action_28i_transaction_value_mutation_started=true
        ;;
    *) exit 64 ;;
esac
FAKE_SSH
chmod 0755 "$fake_ssh"

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
CADDY_ACTION28I_TEST_MODE=1 \
    CADDY_ACTION28I_SSH_PROGRAM="$fake_ssh" \
    CADDY_ACTION28I_FAKE_LOG="$work_directory/ssh.log" \
    CADDY_ACTION28I_INSPECTOR="$inspector" \
    CADDY_ACTION28I_TRANSACTION="$transaction" \
    /bin/bash "$outer" >"$valid_stdout" 2>"$valid_stderr" || valid_status=$?
record_check production_status_zero test "$valid_status" -eq 0
record_check production_stderr_empty test ! -s "$valid_stderr"
record_check production_acceptance grep -Fqx 'action_28i_outer_acceptance=true' "$valid_stdout"
record_check production_node_a_stopped grep -Fqx 'action_28i_outer_node_a_caddy_stopped=true' "$valid_stdout"
record_check production_node_b_master grep -Fqx 'action_28i_outer_node_b_master=true' "$valid_stdout"
record_check production_publisher_absent grep -Fqx 'action_28i_outer_emergency_publisher_invoked=false' "$valid_stdout"
record_check production_failover_once test "$(awk 'index($0, "--failover") { count++ } END { print count + 0 }' "$work_directory/ssh.log")" -eq 1
record_check production_rollback_absent command_fails grep -q -- '--rollback' "$work_directory/ssh.log"
record_check production_node_a_contacted grep -Fq 'pi@10.1.0.53' "$work_directory/ssh.log"
record_check production_node_b_contacted grep -Fq 'pi@10.1.0.54' "$work_directory/ssh.log"
record_check production_remote_cwd grep -Fq 'cd / && sudo -n /bin/bash -s --' "$work_directory/ssh.log"

: >"$work_directory/ssh-negative.log"
negative_status=0
CADDY_ACTION28I_TEST_MODE=1 \
    CADDY_ACTION28I_SSH_PROGRAM="$fake_ssh" \
    CADDY_ACTION28I_FAKE_LOG="$work_directory/ssh-negative.log" \
    CADDY_ACTION28I_FAKE_CASE=wrong_node_b_state \
    CADDY_ACTION28I_INSPECTOR="$inspector" \
    CADDY_ACTION28I_TRANSACTION="$transaction" \
    /bin/bash "$outer" >"$work_directory/negative.stdout" \
    2>"$work_directory/negative.stderr" || negative_status=$?
record_check wrong_node_b_state_rejected test "$negative_status" -eq 1
record_check wrong_node_b_state_rollback_once test "$(awk 'index($0, "--rollback") { count++ } END { print count + 0 }' "$work_directory/ssh-negative.log")" -eq 1
record_check wrong_node_b_state_not_accepted command_fails grep -Fqx 'action_28i_outer_acceptance=true' "$work_directory/negative.stdout"

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
