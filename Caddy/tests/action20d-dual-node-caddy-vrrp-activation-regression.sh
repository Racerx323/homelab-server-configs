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
readonly transaction="$caddy_root/scripts/activate-caddy-vrrp-node-action20d.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"

test_root=$(mktemp -d /tmp/caddy-action20d-regression.XXXXXX)
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
printf '%s\n' "$*" >>"$ACTION20D_FAKE_LOG"
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

if [[ "$ACTION20D_FAKE_MODE" = fail-node-b-activate &&
    "$phase" = --activate && "$role" = node-b ]]; then
    printf 'fixture_node_b_activation_failed\n' >&2
    exit 1
fi

if [[ "$phase" = --rollback ]]; then
    printf 'action_20d_node_explicit_rollback_complete=true\n'
    exit 0
fi

if [[ "$phase" = --activate ]]; then
    inventory_option=--expected-checks
    completion_record=action_20d_node_activation_complete=true
else
    inventory_option=--expected-inspection-checks
    completion_record=action_20d_node_inspection_complete=true
fi
while IFS= read -r check_label; do
    printf 'action_20d_node_check_%s=true\n' "$check_label"
done < <(/bin/bash "$ACTION20D_TRANSACTION" "$inventory_option")

if [[ "$role" = node-a ]]; then
    vrrp_state=MASTER
    address_count=1
else
    vrrp_state=BACKUP
    address_count=0
fi
printf '%s\n' \
    "action_20d_node_value_node_role=$role" \
    "action_20d_node_value_vrrp_state=$vrrp_state" \
    "action_20d_node_value_caddy_ipv4_count=$address_count" \
    "action_20d_node_value_caddy_ipv6_count=$address_count" \
    "action_20d_node_value_dns_ipv4_count=$address_count" \
    "action_20d_node_value_dns_ipv6_count=$address_count"
if [[ "$phase" = --activate ]]; then
    printf '%s\n' \
        "action_20d_node_backup_path=/var/backups/caddy-ha/action20d-${role}-caddy-vrrp.FIXTURE" \
        'action_20d_node_notification_helper_transition_invocation_expected=true' \
        'action_20d_node_persistent_mutation_scope=main_include,rollback_backup'
else
    printf '%s\n' \
        'action_20d_node_filesystem_mutations=false' \
        'action_20d_node_service_mutations=false' \
        'action_20d_node_vrrp_mutations=false' \
        'action_20d_node_vip_mutations=false'
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
printf 'action_20d_regression_dynamic_scope_collision_rejected=true\n'

/bin/bash "$collision_checker" "$transaction" "$runner" "$0" >/dev/null
/bin/bash "$transaction" --self-test >/dev/null
/bin/bash "$runner" --self-test >/dev/null
/bin/bash "$runner" --contract-test >/dev/null
printf 'action_20d_regression_early_invalid_later_valid_rejected=true\n'

: >"$test_root/success.log"
ACTION20D_FAKE_LOG="$test_root/success.log" \
    ACTION20D_FAKE_MODE=success \
    ACTION20D_TRANSACTION="$transaction" \
    CADDY_ACTION20D_SSH_BINARY="$test_root/fake-ssh" \
    /bin/bash "$runner" >"$test_root/success.stdout" \
    2>"$test_root/success.stderr"
[[ ! -s "$test_root/success.stderr" ]]
grep -Fxq 'action_20d_activation_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_cross_check_single_ipv4_owner=true' \
    "$test_root/success.stdout"
grep -Fxq 'action_20d_cross_check_single_ipv6_owner=true' \
    "$test_root/success.stdout"
grep -Fxq 'action_20d_cross_check_notification_attempts_expected=true' \
    "$test_root/success.stdout"
[[ "$(grep -c -- '--activate node-a' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--activate node-b' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--inspect node-a' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--inspect node-b' "$test_root/success.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback' "$test_root/success.log" || true)" -eq 0 ]]
printf 'action_20d_regression_valid_activation_accepted=true\n'

: >"$test_root/failure.log"
failure_status=0
ACTION20D_FAKE_LOG="$test_root/failure.log" \
    ACTION20D_FAKE_MODE=fail-node-b-activate \
    ACTION20D_TRANSACTION="$transaction" \
    CADDY_ACTION20D_SSH_BINARY="$test_root/fake-ssh" \
    /bin/bash "$runner" >"$test_root/failure.stdout" \
    2>"$test_root/failure.stderr" || failure_status=$?
[[ "$failure_status" -ne 0 ]]
[[ "$(grep -c -- '--activate node-a' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--activate node-b' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback node-a' "$test_root/failure.log")" -eq 1 ]]
[[ "$(grep -c -- '--rollback node-b' "$test_root/failure.log" || true)" -eq 0 ]]
grep -Fq 'action_20d_rollback_complete=true' "$test_root/failure.stderr"
if grep -Fq 'action_20d_activation_accepted=true' "$test_root/failure.stdout"; then
    printf 'Action 20d accepted a partial activation.\n' >&2
    exit 1
fi
printf 'action_20d_regression_partial_activation_rolled_back=true\n'
printf 'action_20d_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_regression_complete=true\n'
