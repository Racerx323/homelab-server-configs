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
readonly transaction=$caddy_root/scripts/transact-coupled-go-live-action28u.sh
readonly outer=$caddy_root/scripts/run-dual-node-coupled-go-live-action28v-outer.sh
readonly consumed_outer=$caddy_root/scripts/run-dual-node-coupled-go-live-action28u-outer.sh
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly reconciler=$caddy_root/scripts/reconcile-release-v2.sh
readonly node_a_lsyncd=$caddy_root/configs/lsyncd/caddy-node-a.lua
readonly node_b_lsyncd=$caddy_root/configs/lsyncd/caddy-node-b.lua

require_text() {
    local action28v_regression_file=$1
    local action28v_regression_text=$2

    grep -Fq -- "$action28v_regression_text" "$action28v_regression_file"
}
reject_text() {
    local action28v_regression_file=$1
    local action28v_regression_text=$2

    ! grep -Fq -- "$action28v_regression_text" "$action28v_regression_file"
}
line_number() {
    local action28v_regression_file=$1
    local action28v_regression_text=$2

    grep -Fn -- "$action28v_regression_text" "$action28v_regression_file" |
        awk -F: 'NR == 1 { print $1 }'
}
require_order() {
    local action28v_regression_file=$1
    local action28v_regression_previous=0
    local action28v_regression_text
    local action28v_regression_current

    shift
    for action28v_regression_text in "$@"; do
        action28v_regression_current=$(line_number \
            "$action28v_regression_file" "$action28v_regression_text")
        [[ -n "$action28v_regression_current" ]]
        [[ "$action28v_regression_current" -gt "$action28v_regression_previous" ]]
        action28v_regression_previous=$action28v_regression_current
    done
}

/bin/bash -n "$transaction" "$outer" "$publisher" "$reconciler"
[[ "$(sha256sum "$consumed_outer" | awk '{ print $1 }')" = 10ea10051be0db4be07c4f924eedfa5e488871b3c6d7f56b5472e1775d6c2633 ]]
"$transaction" --self-test | grep -Fxq \
    'action_28u_remote_self_test_complete=true'
action28v_regression_producer_output=$(/bin/bash "$outer" --producer-self-test)
grep -Fxq 'action_28v_outer_producer_remote_valid=true' \
    <<<"$action28v_regression_producer_output"
grep -Fxq 'action_28v_outer_producer_capture_files_valid=true' \
    <<<"$action28v_regression_producer_output"
grep -Fxq 'action_28v_outer_producer_malformed_rejected=true' \
    <<<"$action28v_regression_producer_output"
grep -Fxq 'action_28v_outer_producer_self_test_complete=true' \
    <<<"$action28v_regression_producer_output"
action28v_regression_recovery_output=$(
    /bin/bash "$outer" --pre-mutation-recovery-self-test
)
grep -Fxq 'action_28v_outer_recovery_started=true' \
    <<<"$action28v_regression_recovery_output"
grep -Fxq 'action_28v_outer_recovery_not_required=true' \
    <<<"$action28v_regression_recovery_output"
grep -Fxq 'action_28v_outer_recovery_proven=true' \
    <<<"$action28v_regression_recovery_output"
grep -Fxq 'action_28v_outer_pre_mutation_recovery_self_test_complete=true' \
    <<<"$action28v_regression_recovery_output"
if grep -Fq 'phase_recovery_' <<<"$action28v_regression_recovery_output"; then
    exit 1
fi

# The quoted fragments are exact source text, not expressions to expand.
# shellcheck disable=SC2016
require_order "$outer" \
    'must_phase node_b_preflight node-b preflight' \
    'must_phase node_a_preflight node-a preflight' \
    'must_phase node_b_install node-b install' \
    'must_phase node_a_install node-a install' \
    'must_phase node_a_promote_retained node-a promote "$retained_revision"' \
    'must_phase node_b_promote_retained node-b promote "$retained_revision"' \
    'must_phase node_b_activate_sync node-b activate' \
    'must_phase node_a_activate_sync node-a activate' \
    'must_phase node_a_relinquish node-a relinquish' \
    'must_phase node_b_master node-b state' \
    'must_phase node_b_normal_publish_rejected node-b reject-normal' \
    'must_phase node_b_emergency_publish node-b publish' \
    'must_phase node_a_receive_emergency node-a accept-release' \
    'must_phase node_a_restore_owner node-a restore-owner' \
    'must_phase node_a_master node-a state' \
    'must_phase node_b_backup node-b state' \
    'must_phase node_a_normal_publish node-a publish' \
    'must_phase node_b_receive_normal node-b accept-release' \
    'must_phase node_a_final_state node-a state' \
    'must_phase node_b_final_state node-b state' \
    'must_phase node_a_commit node-a commit' \
    'must_phase node_b_commit node-b commit'

require_text "$outer" 'exit 125'
require_text "$outer" 'recovery_proven='
require_text "$outer" '/tmp/caddy-ssh-evidence/action28v'
require_text "$outer" "'cd / && sudo -n /bin/bash -s --'"
# These are exact source literals, not expressions to expand.
# shellcheck disable=SC2016
require_text "$outer" \
    'printf '\''/bin/bash "$stage/transact-coupled-go-live-action28u.sh" --mode %q'
# shellcheck disable=SC2016
require_text "$outer" \
    'prepare_capture_files "$remote_stdout" "$remote_stderr" "$status_file"'
# shellcheck disable=SC2016
reject_text "$outer" \
    'install -m 0600 /dev/null "$remote_stdout" "$remote_stderr" "$status_file"'
require_text "$outer" 'recovery_not_required=true'
require_text "$outer" 'notifier_delivery_nonblocking=true'
reject_text "$outer" 'action18c'
reject_text "$outer" 'CADDY_DUALSTACK'

require_text "$publisher" 'coupled_master'
require_text "$publisher" 'PIHOLE_IPV4 and PIHOLE_IPV6'
require_text "$publisher" "'(us) 2 \"Master\"'"
reject_text "$publisher" '/run/caddy-ha/vrrp-state'
reject_text "$publisher" 'CADDY_DUALSTACK is MASTER'
require_text "$reconciler" 'Protocol-v2 release %s is already active.'
require_text "$reconciler" 'active_destination_exact'

require_text "$node_a_lsyncd" 'host = "pihole00.local.theama.co"'
require_text "$node_a_lsyncd" 'BindAddress = "fd36:5aa8:6971:1::53"'
require_text "$node_b_lsyncd" 'host = "pihole0.local.theama.co"'
require_text "$node_b_lsyncd" 'BindAddress = "fd36:5aa8:6971:1::54"'
for action28v_regression_config in "$node_a_lsyncd" "$node_b_lsyncd"; do
    require_text "$action28v_regression_config" 'delete = false'
    require_text "$action28v_regression_config" '"--exclude=.complete"'
    require_text "$action28v_regression_config" 'IdentitiesOnly = "yes"'
done

printf 'action_28v_regression_complete=true\n'
