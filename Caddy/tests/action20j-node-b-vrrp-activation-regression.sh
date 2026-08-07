#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-vrrp-activation-action20j.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20j_regression_label" >&2
    return 1
}
run_runner() {
    local action20j_regression_mode=$1
    local action20j_regression_stdout=$2
    local action20j_regression_stderr=$3
    local action20j_regression_status=0

    : >"$call_log"
    ACTION20J_TRANSACTION="$transaction" \
        ACTION20J_TRANSACTION_SHA256="$(file_hash "$transaction")" \
        ACTION20J_CALL_LOG="$call_log" \
        ACTION20J_FAIL_MODE="$action20j_regression_mode" \
        CADDY_ACTION20J_SSH_BINARY="$fake_ssh" \
        /bin/bash "$runner" >"$action20j_regression_stdout" \
        2>"$action20j_regression_stderr" || action20j_regression_status=$?
    printf '%s\n' "$action20j_regression_status"
}
call_log_exact() {
    local action20j_regression_expected=$1

    cmp -s "$action20j_regression_expected" "$call_log"
}

work_root=$(mktemp -d /tmp/caddy-action20j-regression.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
/bin/bash "$builder" --output "$generated_root" >/dev/null
readonly transaction=$generated_root/scripts/activate-node-b-caddy-vrrp-action20j.sh
readonly runner=$generated_root/scripts/run-node-b-caddy-vrrp-activation-action20j.sh
readonly fake_ssh=$work_root/fake-ssh
readonly call_log=$work_root/calls

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

phase=
role=
previous=
for argument in "$@"; do
    if [[ "$previous" = phase ]]; then
        role=$argument
        break
    fi
    case "$argument" in
        --activate | --inspect | --rollback)
            phase=$argument
            previous=phase
            ;;
    esac
done
[[ -n "$phase" && -n "$role" ]]
capture=$(mktemp /tmp/caddy-action20j-fake-ssh.XXXXXX)
trap 'rm -f -- "$capture"' EXIT
cat >"$capture"
[[ "$(sha256sum "$capture" | awk '{ print $1 }')" = \
    "$ACTION20J_TRANSACTION_SHA256" ]]
printf '%s %s\n' "$phase" "$role" >>"$ACTION20J_CALL_LOG"
call_count=$(wc -l <"$ACTION20J_CALL_LOG")

if [[ "$ACTION20J_FAIL_MODE" = node_a_pre && "$call_count" -eq 1 ]] ||
    [[ "$ACTION20J_FAIL_MODE" = node_b_activate && "$call_count" -eq 2 ]] ||
    [[ "$ACTION20J_FAIL_MODE" = node_a_post && "$call_count" -eq 4 ]]; then
    exit 1
fi

emit_inspection() {
    local inspected_role=$1
    local state
    local count
    local dns_count
    local label

    if [[ "$inspected_role" = node-a ]]; then
        state=MASTER
        count=1
        dns_count=1
    else
        state=BACKUP
        count=0
        dns_count=0
    fi
    while IFS= read -r label; do
        printf 'action_20j_node_check_%s=true\n' "$label"
    done < <(/bin/bash "$ACTION20J_TRANSACTION" --expected-inspection-checks)
    printf '%s\n' \
        "action_20j_node_value_node_role=$inspected_role" \
        "action_20j_node_value_vrrp_state=$state" \
        "action_20j_node_value_caddy_ipv4_count=$count" \
        "action_20j_node_value_caddy_ipv6_count=$count" \
        "action_20j_node_value_dns_ipv4_count=$dns_count" \
        "action_20j_node_value_dns_ipv6_count=$dns_count" \
        'action_20j_node_filesystem_mutations=false' \
        'action_20j_node_service_mutations=false' \
        'action_20j_node_vrrp_mutations=false' \
        'action_20j_node_vip_mutations=false' \
        'action_20j_node_inspection_complete=true'
}
emit_activation() {
    local label

    while IFS= read -r label; do
        printf 'action_20j_node_check_%s=true\n' "$label"
    done < <(/bin/bash "$ACTION20J_TRANSACTION" --expected-checks)
    printf '%s\n' \
        'action_20j_node_value_node_role=node-b' \
        'action_20j_node_value_vrrp_state=BACKUP' \
        'action_20j_node_value_caddy_ipv4_count=0' \
        'action_20j_node_value_caddy_ipv6_count=0' \
        'action_20j_node_value_dns_ipv4_count=0' \
        'action_20j_node_value_dns_ipv6_count=0' \
        'action_20j_node_notification_helper_transition_invocation_expected=true' \
        'action_20j_node_validation_scope=static_candidates_plus_bounded_live_reload' \
        'action_20j_node_production_fragment_installed_unchanged=true' \
        'action_20j_node_health_helper_execution_context=keepalived_script' \
        'action_20j_node_notification_helper_preflight_invoked=false' \
        'action_20j_node_persistent_mutation_scope=main_include,rollback_backup' \
        'action_20j_node_backup_path=/var/backups/caddy-ha/action20j-node-b-caddy-vrrp.FIXTURE' \
        'action_20j_node_activation_complete=true'
}

case "$phase:$role" in
    --inspect:node-a | --inspect:node-b) emit_inspection "$role" ;;
    --activate:node-b) emit_activation ;;
    --rollback:node-b)
        printf '%s\n' \
            'action_20j_node_explicit_rollback_complete=true'
        ;;
    *) exit 64 ;;
esac
FAKE_SSH
chmod 0755 "$fake_ssh"

readonly success_stdout=$work_root/success.stdout
readonly success_stderr=$work_root/success.stderr
success_status=$(run_runner success "$success_stdout" "$success_stderr")
readonly success_status
cat >"$work_root/success.expected" <<'EOF'
--inspect node-a
--activate node-b
--inspect node-b
--inspect node-a
EOF
record_check success_status test "$success_status" -eq 0
record_check success_stderr_empty test ! -s "$success_stderr"
record_check success_order call_log_exact "$work_root/success.expected"
record_check success_accepted grep -Fqx \
    'action_20j_activation_accepted=true' "$success_stdout"
record_check success_node_a_unchanged grep -Fqx \
    'action_20j_node_a_persistent_mutations=false' "$success_stdout"
record_check success_node_b_backup grep -Fqx \
    'action_20j_check_node_b_backup_state=true' "$success_stdout"

readonly pre_stdout=$work_root/pre.stdout
readonly pre_stderr=$work_root/pre.stderr
pre_status=$(run_runner node_a_pre "$pre_stdout" "$pre_stderr")
readonly pre_status
printf '%s\n' '--inspect node-a' >"$work_root/pre.expected"
record_check node_a_pre_failure_status test "$pre_status" -eq 1
record_check node_a_pre_blocks_activation call_log_exact "$work_root/pre.expected"

readonly activation_stdout=$work_root/activation.stdout
readonly activation_stderr=$work_root/activation.stderr
activation_status=$(run_runner node_b_activate "$activation_stdout" \
    "$activation_stderr")
readonly activation_status
cat >"$work_root/activation.expected" <<'EOF'
--inspect node-a
--activate node-b
EOF
record_check node_b_failure_status test "$activation_status" -eq 1
record_check node_b_failure_blocks_postchecks call_log_exact \
    "$work_root/activation.expected"

readonly rollback_stdout=$work_root/rollback.stdout
readonly rollback_stderr=$work_root/rollback.stderr
rollback_status=$(run_runner node_a_post "$rollback_stdout" "$rollback_stderr")
readonly rollback_status
cat >"$work_root/rollback.expected" <<'EOF'
--inspect node-a
--activate node-b
--inspect node-b
--inspect node-a
--rollback node-b
--inspect node-a
EOF
record_check postfailure_status test "$rollback_status" -eq 1
record_check postfailure_rollback_order call_log_exact \
    "$work_root/rollback.expected"
record_check postfailure_rollback_complete grep -Fqx \
    'action_20j_rollback_complete=true' "$rollback_stderr"
record_check postfailure_manual_intervention_absent test \
    "$(grep -Fxc 'action_20j_manual_intervention_required=true' \
        "$rollback_stderr" || true)" -eq 0

record_check transaction_self_test /bin/bash "$transaction" --self-test
record_check transaction_candidate_contract /bin/bash "$transaction" \
    --candidate-contract-test
record_check runner_self_test /bin/bash "$runner" --self-test
record_check runner_contract_test /bin/bash "$runner" --contract-test
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
