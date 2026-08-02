#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly driver="$caddy_root/scripts/activate-node-a-unbound-two-file-action17k.sh"
readonly runner="$caddy_root/scripts/run-node-a-unbound-two-file-activation-action17k.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

run_regression() {
    bash -n "$driver" "$runner"
    "$driver" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$driver" "$runner" >/dev/null

    grep -Fq \
        'readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"' \
        "$driver"
    grep -Fq \
        'readonly local_zone_stage_file="$local_zone_stage/pihole-local-zone.conf"' \
        "$driver"
    grep -Fq \
        'action_17k_live_local_zone_name=pihole-local-zone.conf' \
        "$driver"
    grep -Fq 'assert_absent legacy_local_zone_absent' "$driver"
    grep -Fq 'command_label=${required_command//-/_}' "$driver"
    grep -Fq 'stage_member_label=${stage_member_label//-/_}' "$driver"
    grep -Fq 'run_step unbound_reload systemctl reload unbound.service' \
        "$driver"
    grep -Fq 'cd / && exec /bin/bash -s --' "$runner"
    grep -Fq 'Action 17k duplicate-check fixture was accepted.' "$runner"
    grep -Fq 'action_17k_rollback_complete=false' "$runner"
    grep -Fq 'manual_intervention_required=true' "$runner"
    grep -Fq 'readonly expected_target=pi@10.1.0.53' "$runner"
    grep -Fq 'readonly expected_host_alias=pihole0.local.theama.co' "$runner"
    grep -Fq 'readonly primary_stage=/var/tmp/caddy-unbound-node-a-action17i-primary' "$driver"
    grep -Fq 'readonly local_zone_stage=/var/tmp/caddy-unbound-node-a-action17j-local-zone' "$driver"
    grep -Fq 'root:root:644:33211' "$driver"
    grep -Fq 'current_boundary=accepted_live_baseline' "$driver"
    grep -Fq 'current_boundary=protected_backup_creation' "$driver"
    grep -Fq 'current_boundary=atomic_live_switch' "$driver"
    grep -Fq 'current_boundary=bounded_reload' "$driver"
    grep -Fq 'action_17k_unhandled_boundary=%s' "$driver"
    grep -Fq 'assert_equal primary_stage_preserved' "$driver"
    grep -Fq 'assert_equal local_zone_stage_preserved' "$driver"
    grep -Fq 'readonly expected_check_count=122' "$runner"
    grep -Fq '"$check_count" -eq "$expected_check_count"' "$runner"
    if grep -Eq \
        'j1-svpihole00|pi@10[.]1[.]0[.]54|action17g-node-b' \
        "$driver" "$runner"; then
        printf 'Action 17k contains a stale Node B identity.\n' >&2
        exit 1
    fi

    printf 'action_17k_node_a_unbound_activation_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
