#!/usr/bin/env bash

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
readonly driver="$caddy_root/scripts/apply-node-b-dns-nss-correction-action17m.sh"
readonly runner="$caddy_root/scripts/run-node-b-dns-nss-correction-action17m.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

run_regression() {
    local label

    bash -n "$driver" "$runner"
    "$driver" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --source-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$driver" "$runner" >/dev/null

    for label in \
        uid_is_root working_directory_is_root hostname_matches primary_hash \
        live_local_zone_hash candidate_hash backup_absent \
        hosts_marker_begin_absent hosts_marker_end_absent \
        peer_fqdn_hosts_absent candidate_parser backup_created \
        transaction_local_zone_hash transaction_hosts_peer_ipv4_exact \
        transaction_hosts_peer_ipv6_exact atomic_file_switch_complete \
        unbound_reload bounded_dns_readiness root_peer_ipv4 root_peer_ipv6 \
        caddy_sync_peer_ipv4 caddy_sync_peer_ipv6 unbound_pid_preserved \
        unbound_restarts_preserved pihole_ftl_pid_preserved \
        pihole_ftl_restarts_preserved final_local_zone_hash \
        final_hosts_metadata final_local_zone_transaction_absent \
        final_hosts_transaction_absent; do
        grep -Fq "$label" "$driver"
    done

    grep -Fq "readonly accepted_local_zone_sha256=8a7d1c6d" "$driver"
    grep -Fq "readonly candidate_local_zone_sha256=c70f7097" "$driver"
    grep -Fq "readonly source_local_zone_sha256=fdd771af" "$runner"
    grep -Fq "homeassistant[.]local[.]theama[.]co" "$runner"
    grep -Fq "Unbound/configs/pihole0-local-zone.conf" "$runner"
    grep -Fq "git -C \"\$workspace_root/homelab-dns\" check-ignore" "$runner"
    grep -Fq "readonly peer_ipv4=10.1.0.53" "$driver"
    grep -Fq "readonly peer_ipv6=fd36:5aa8:6971:1::53" "$driver"
    grep -Fq "readonly peer_fqdn=pihole0.local.theama.co" "$driver"
    grep -Fq "action_17m_resolv_conf_mutation=false" "$driver"
    grep -Fq "action_17m_peer_connections=false" "$driver"
    grep -Fq "action_17m_synchronization_executed=false" "$driver"
    grep -Fq "action_17m_rollback_complete=false" "$driver"
    grep -Fq "manual_intervention_required=true" "$driver"
    grep -Fq "action_17m_unhandled_boundary=" "$driver"
    grep -Fq "set_boundary identity_and_live_state_preflight" "$driver"
    grep -Fq "set_boundary rollback_backup_creation" "$driver"
    grep -Fq "set_boundary atomic_live_file_switch" "$driver"
    grep -Fq "set_boundary bounded_dns_readiness" "$driver"
    grep -Fq "set_boundary nss_peer_resolution" "$driver"
    grep -Fq "set_boundary service_continuity_validation" "$driver"
    grep -Fq "exit 125" "$driver"

    if grep -Fq '/etc/resolv.conf' "$driver" "$runner"; then
        printf 'Action 17m must not read or mutate /etc/resolv.conf.\n' >&2
        exit 1
    fi
    if grep -Eq 'systemctl[[:space:]]+(restart|start|stop)' "$driver"; then
        printf 'Action 17m must not restart a service.\n' >&2
        exit 1
    fi
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$driver" "$runner"; then
        printf 'Action 17m contains an unapproved synchronization command.\n' >&2
        exit 1
    fi

    printf 'action_17m_regression_complete=true\n'
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
