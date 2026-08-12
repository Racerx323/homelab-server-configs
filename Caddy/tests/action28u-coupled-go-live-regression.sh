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
readonly outer=$caddy_root/scripts/run-dual-node-coupled-go-live-action28u-outer.sh
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly reconciler=$caddy_root/scripts/reconcile-release-v2.sh
readonly node_a_lsyncd=$caddy_root/configs/lsyncd/caddy-node-a.lua
readonly node_b_lsyncd=$caddy_root/configs/lsyncd/caddy-node-b.lua

require_text() {
    local action28u_regression_file=$1
    local action28u_regression_text=$2

    grep -Fq -- "$action28u_regression_text" "$action28u_regression_file"
}
reject_text() {
    local action28u_regression_file=$1
    local action28u_regression_text=$2

    ! grep -Fq -- "$action28u_regression_text" "$action28u_regression_file"
}
line_number() {
    local action28u_regression_file=$1
    local action28u_regression_text=$2

    grep -Fn -- "$action28u_regression_text" "$action28u_regression_file" |
        awk -F: 'NR == 1 { print $1 }'
}
require_order() {
    local action28u_regression_file=$1
    local action28u_regression_previous=0
    local action28u_regression_text
    local action28u_regression_current

    shift
    for action28u_regression_text in "$@"; do
        action28u_regression_current=$(line_number \
            "$action28u_regression_file" "$action28u_regression_text")
        [[ -n "$action28u_regression_current" ]]
        [[ "$action28u_regression_current" -gt "$action28u_regression_previous" ]]
        action28u_regression_previous=$action28u_regression_current
    done
}

/bin/bash -n "$transaction" "$outer" "$publisher" "$reconciler"
"$transaction" --self-test | grep -Fxq \
    'action_28u_remote_self_test_complete=true'

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
require_text "$outer" '/tmp/caddy-ssh-evidence/action28u'
require_text "$outer" "'cd / && sudo -n /bin/bash -s --'"
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
for action28u_regression_config in "$node_a_lsyncd" "$node_b_lsyncd"; do
    require_text "$action28u_regression_config" 'delete = false'
    require_text "$action28u_regression_config" '"--exclude=.complete"'
    require_text "$action28u_regression_config" 'IdentitiesOnly = "yes"'
done

printf 'action_28u_regression_complete=true\n'
