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
readonly driver="$caddy_root/scripts/activate-node-b-unbound-two-file-action17g.sh"
readonly runner="$caddy_root/scripts/run-node-b-unbound-two-file-activation-action17g.sh"
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
        'readonly local_zone_stage_file="$local_zone_stage/pihole0-local-zone.conf"' \
        "$driver"
    grep -Fq \
        'action_17g_live_local_zone_name=pihole-local-zone.conf' \
        "$driver"
    grep -Fq 'assert_absent legacy_local_zone_absent' "$driver"
    grep -Fq 'command_label=${required_command//-/_}' "$driver"
    grep -Fq 'stage_member_label=${stage_member_label//-/_}' "$driver"
    grep -Fq 'run_step unbound_reload systemctl reload unbound.service' \
        "$driver"
    grep -Fq 'cd / && exec /bin/bash -s --' "$runner"
    grep -Fq 'Action 17g duplicate-check fixture was accepted.' "$runner"
    grep -Fq 'action_17g_rollback_complete=false' "$runner"
    grep -Fq 'manual_intervention_required=true' "$runner"

    printf 'action_17g_node_b_unbound_activation_regression_complete=true\n'
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
