#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction="$caddy_root/scripts/activate-caddy-vrrp-node-action20d-retry.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry.sh"
readonly historical_transaction="$caddy_root/scripts/activate-caddy-vrrp-node-action20d.sh"
readonly historical_transaction_sha256=f20e90b0991bdb3aa5b1552496e25a2bfdb3e28a2746ce67eacec6fe603a7e79
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"

test_root=$(mktemp -d /tmp/caddy-action20d-retry-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT

cat >"$test_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

cat >/dev/null
printf '%s\n' "$*" >>"$ACTION20D_RETRY_FAKE_LOG"
phase=
role=
for argument in "$@"; do
    case "$argument" in
        --activate | --inspect | --rollback) phase=$argument ;;
        node-a | node-b) role=$argument ;;
    esac
done
[[ -n "$phase" && -n "$role" ]]
grep -Fq 'sudo -n /bin/bash -s --' <<<"$*"

if [[ "$ACTION20D_RETRY_FAKE_MODE" = fail-node-b-activate &&
    "$phase" = --activate && "$role" = node-b ]]; then
    printf 'fixture_node_b_activation_failed\n' >&2
    exit 1
fi

if [[ "$phase" = --rollback ]]; then
    printf 'action_20d_retry_node_explicit_rollback_complete=true\n'
    exit 0
fi

if [[ "$phase" = --activate ]]; then
    inventory_option=--expected-checks
    completion_record=action_20d_retry_node_activation_complete=true
else
    inventory_option=--expected-inspection-checks
    completion_record=action_20d_retry_node_inspection_complete=true
fi
while IFS= read -r check_label; do
    printf 'action_20d_retry_node_check_%s=true\n' "$check_label"
done < <(/bin/bash "$ACTION20D_RETRY_TRANSACTION" "$inventory_option")

if [[ "$role" = node-a ]]; then
    vrrp_state=MASTER
    address_count=1
else
    vrrp_state=BACKUP
    address_count=0
fi
printf '%s\n' \
    "action_20d_retry_node_value_node_role=$role" \
    "action_20d_retry_node_value_vrrp_state=$vrrp_state" \
    "action_20d_retry_node_value_caddy_ipv4_count=$address_count" \
    "action_20d_retry_node_value_caddy_ipv6_count=$address_count" \
    "action_20d_retry_node_value_dns_ipv4_count=$address_count" \
    "action_20d_retry_node_value_dns_ipv6_count=$address_count"
if [[ "$phase" = --activate ]]; then
    printf '%s\n' \
        "action_20d_retry_node_backup_path=/var/backups/caddy-ha/action20d-retry-${role}-caddy-vrrp.FIXTURE" \
        'action_20d_retry_node_notification_helper_transition_invocation_expected=true' \
        'action_20d_retry_node_validation_scope=sanitized_ephemeral_candidate_only' \
        'action_20d_retry_node_production_fragment_installed_unchanged=true' \
        'action_20d_retry_node_health_helper_execution_context=keepalived_script' \
        'action_20d_retry_node_notification_helper_preflight_invoked=false' \
        'action_20d_retry_node_persistent_mutation_scope=main_include,rollback_backup'
else
    printf '%s\n' \
        'action_20d_retry_node_filesystem_mutations=false' \
        'action_20d_retry_node_service_mutations=false' \
        'action_20d_retry_node_vrrp_mutations=false' \
        'action_20d_retry_node_vip_mutations=false'
fi
printf '%s\n' "$completion_record"
FAKE_SSH
chmod 0755 "$test_root/fake-ssh"

# The dollar-prefixed name is literal fixture source.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly repeated_name=value' \
    'collision() {' \
    '    local repeated_name=other' \
    '    printf '\''%s\n'\'' "$repeated_name"' \
    '}' >"$test_root/collision-fixture.sh"
if /bin/bash "$collision_checker" "$test_root/collision-fixture.sh" \
    >"$test_root/collision.stdout" 2>"$test_root/collision.stderr"; then
    printf 'Action 20d collision fixture was incorrectly accepted.\n' >&2
    exit 1
fi
grep -Fq 'readonly_local_collision=' "$test_root/collision.stderr"
printf 'action_20d_retry_regression_dynamic_scope_collision_rejected=true\n'

/bin/bash "$collision_checker" "$transaction" "$runner" "$0" >/dev/null
/bin/bash "$transaction" --self-test >/dev/null
/bin/bash "$runner" --self-test >/dev/null
/bin/bash "$runner" --contract-test >/dev/null
printf 'action_20d_retry_regression_early_invalid_later_valid_rejected=true\n'

[[ "$(sha256sum "$historical_transaction" | awk '{ print $1 }')" = "$historical_transaction_sha256" ]]
printf 'action_20d_retry_regression_historical_transaction_hash_exact=true\n'
/bin/bash "$historical_transaction" --expected-checks | LC_ALL=C sort \
    >"$test_root/historical-activation-checks"
/bin/bash "$transaction" --expected-checks | LC_ALL=C sort \
    >"$test_root/retry-activation-checks"
[[ -s "$test_root/historical-activation-checks" ]]
printf 'action_20d_retry_regression_historical_activation_inventory_nonempty=true\n'
comm -23 "$test_root/historical-activation-checks" \
    "$test_root/retry-activation-checks" >"$test_root/missing-activation-checks"
[[ ! -s "$test_root/missing-activation-checks" ]]
printf 'action_20d_retry_regression_all_historical_activation_checks_preserved=true\n'
/bin/bash "$historical_transaction" --expected-inspection-checks | LC_ALL=C sort \
    >"$test_root/historical-inspection-checks"
/bin/bash "$transaction" --expected-inspection-checks | LC_ALL=C sort \
    >"$test_root/retry-inspection-checks"
[[ -s "$test_root/historical-inspection-checks" ]]
printf 'action_20d_retry_regression_historical_inspection_inventory_nonempty=true\n'
comm -23 "$test_root/historical-inspection-checks" \
    "$test_root/retry-inspection-checks" >"$test_root/missing-inspection-checks"
[[ ! -s "$test_root/missing-inspection-checks" ]]
printf 'action_20d_retry_regression_all_historical_inspection_checks_preserved=true\n'

[[ "$(grep -Fxc '            expected_production_candidate_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_node_a_production_candidate_hash_pinned=true\n'
[[ "$(grep -Fxc '            expected_production_candidate_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_node_b_production_candidate_hash_pinned=true\n'
[[ "$(grep -Fxc '            expected_sanitized_candidate_sha256=ea8fc2aaba014fa65296e7a6e15ae1fcb9a108d2487b3f5166a36dd3f30785b7' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_node_a_sanitized_candidate_hash_pinned=true\n'
[[ "$(grep -Fxc '            expected_sanitized_candidate_sha256=91eb9f89437c76ae6964cb1ca14278369c4d90c510e2cbfd05562fafbe97d431' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_node_b_sanitized_candidate_hash_pinned=true\n'
[[ "$(grep -Fc 'notify "/d' "$transaction")" -eq 2 ]]
printf 'action_20d_retry_regression_sanitizer_notify_rule_covers_both_sources=true\n'
[[ "$(grep -Fc 's#^[[:space:]]*script "[^"]*"#    script "/bin/true"#' "$transaction")" -eq 2 ]]
printf 'action_20d_retry_regression_sanitizer_script_rule_covers_both_sources=true\n'
[[ "$(grep -Fc 's/^[[:space:]]*user keepalived_script/    user root/' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_sanitizer_user_rule_once=true\n'
[[ "$(grep -Fxc "printf '\\n%s\\n' \"\$include_record\" >>\"\$production_configuration\"" "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_production_include_isolated=true\n'
# The dollar-prefixed name is literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '        "$main_configuration"' "$transaction")" -ge 1 ]]
printf 'action_20d_retry_regression_sanitized_candidate_uses_exact_main=true\n'
# The dollar-prefixed name is literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '        "$fragment"' "$transaction")" -ge 1 ]]
printf 'action_20d_retry_regression_sanitized_candidate_uses_exact_fragment=true\n'
# The trailing backslash is literal transaction source.
# shellcheck disable=SC1003
[[ "$(grep -Fxc 'record_check sanitized_candidate_include_absent test \' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_sanitized_candidate_has_no_include=true\n'
# The dollar-prefixed path is literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '    -f "$candidate_configuration"' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_config_test_uses_sanitized_candidate=true\n'
# The dollar-prefixed paths are literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fxc 'install -o root -g root -m 0644 "$production_configuration" "$main_configuration"' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_install_uses_production_candidate=true\n'
# The dollar-prefixed paths are literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fc 'install -o root -g root -m 0644 "$candidate_configuration" "$main_configuration"' "$transaction")" -eq 0 ]]
printf 'action_20d_retry_regression_sanitized_candidate_never_installed=true\n'
# The dollar-prefixed path is literal transaction source.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '    runuser -u keepalived_script -- "$health_helper"' "$transaction")" -eq 2 ]]
printf 'action_20d_retry_regression_health_context_checked_pre_and_post=true\n'
[[ "$(grep -Fxc "printf '%s_notification_helper_preflight_invoked=false\\n' \"\$prefix\"" "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_notification_preflight_noninvocation=true\n'
[[ "$(grep -Fxc 'readonly notification_execution_user=pi' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_notification_execution_user_pinned=true\n'
[[ "$(grep -Fxc 'readonly notification_state_directory=/run/caddy-ha' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_notification_state_directory_pinned=true\n'
[[ "$(grep -Fxc 'readonly notification_dedupe_directory=/run/caddy-ha-notify' "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_notification_dedupe_directory_pinned=true\n'
[[ "$(grep -Fxc "            runuser -u \"\$notification_execution_user\" -- test -x \"\$notification_helper\"" "$transaction")" -eq 1 ]]
[[ "$(grep -Fxc "    runuser -u \"\$notification_execution_user\" -- test -x \"\$notification_helper\"" "$transaction")" -eq 1 ]]
printf 'action_20d_retry_regression_notification_context_checks_do_not_invoke_helper=true\n'
[[ "$(grep -Fc 'notification_state_directory_writable_as_execution_user' "$transaction")" -eq 4 ]]
printf 'action_20d_retry_regression_notification_state_writability_checked_pre_and_post=true\n'
[[ "$(grep -Fc 'notification_dedupe_directory_writable_as_execution_user' "$transaction")" -eq 4 ]]
printf 'action_20d_retry_regression_notification_dedupe_writability_checked_pre_and_post=true\n'

: >"$test_root/success.log"
ACTION20D_RETRY_FAKE_LOG="$test_root/success.log" \
    ACTION20D_RETRY_FAKE_MODE=success \
    ACTION20D_RETRY_TRANSACTION="$transaction" \
    CADDY_ACTION20D_RETRY_SSH_BINARY="$test_root/fake-ssh" \
    /bin/bash "$runner" >"$test_root/success.stdout" \
    2>"$test_root/success.stderr"
[[ ! -s "$test_root/success.stderr" ]]
grep -Fxq 'action_20d_retry_activation_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry_cross_check_single_ipv4_owner=true' \
    "$test_root/success.stdout"
grep -Fxq 'action_20d_retry_cross_check_single_ipv6_owner=true' \
    "$test_root/success.stdout"
grep -Fxq 'action_20d_retry_cross_check_notification_attempts_expected=true' \
    "$test_root/success.stdout"
[[ "$(grep -c -- '--activate node-a' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--activate node-b' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--inspect node-a' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--inspect node-b' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback' "$test_root/success.log" || true)" -eq 0 ]]
printf 'action_20d_retry_regression_valid_activation_accepted=true\n'

: >"$test_root/failure.log"
failure_status=0
ACTION20D_RETRY_FAKE_LOG="$test_root/failure.log" \
    ACTION20D_RETRY_FAKE_MODE=fail-node-b-activate \
    ACTION20D_RETRY_TRANSACTION="$transaction" \
    CADDY_ACTION20D_RETRY_SSH_BINARY="$test_root/fake-ssh" \
    /bin/bash "$runner" >"$test_root/failure.stdout" \
    2>"$test_root/failure.stderr" || failure_status=$?
[[ "$failure_status" -ne 0 ]]
[[ "$(grep -c -- '--activate node-a' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--activate node-b' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback node-a' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback node-b' "$test_root/failure.log" || true)" -eq 0 ]]
grep -Fq 'action_20d_retry_rollback_complete=true' "$test_root/failure.stderr"
if grep -Fq 'action_20d_retry_activation_accepted=true' "$test_root/failure.stdout"; then
    printf 'Action 20d accepted a partial activation.\n' >&2
    exit 1
fi
printf 'action_20d_retry_regression_partial_activation_rolled_back=true\n'
printf 'action_20d_retry_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_retry_regression_complete=true\n'
