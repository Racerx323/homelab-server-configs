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
readonly inspector="$caddy_root/scripts/inspect-dual-node-dns-sync-readiness-action17l.sh"
readonly runner="$caddy_root/scripts/run-dual-node-dns-sync-readiness-action17l.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

run_regression() {
    bash -n "$inspector" "$runner"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$runner" >/dev/null

    grep -Fq 'expected_assertion_count=111' "$inspector"
    grep -Fq 'expected_command_assertion_count=22' "$inspector"
    grep -Fq 'expected_non_command_assertion_count=89' "$inspector"
    grep -Fq 'pihole-local-zone.conf' "$inspector"
    grep -Fq "grep -Fq \"\$own_ipv6/64\"" "$inspector"
    grep -Fq 'unbound_peer_aaaa' "$inspector"
    grep -Fq 'unbound_peer_ptr6' "$inspector"
    grep -Fq 'dns_vip_ipv4_peer_aaaa' "$inspector"
    grep -Fq 'dns_vip_ipv6_peer_aaaa' "$inspector"
    grep -Fq 'sync_peer_ipv6' "$inspector"
    grep -Fq 'action_17l_first_failure=' "$inspector"
    grep -Fq 'peer_connections=false' "$inspector"
    grep -Fq 'synchronization_commands_executed=false' "$inspector"
    grep -Fq 'dns_configuration_mutations=false' "$inspector"
    grep -Fq 'service_mutations=false' "$inspector"
    grep -Fq 'persistent_mutations=false' "$inspector"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-a'" \
        "$runner"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node node-b'" \
        "$runner"
    grep -Fq 'finish 1' "$runner"
    grep -Fq 'finish 97' "$runner"

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17l inspector contains a filesystem mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control' \
        "$inspector"; then
        printf 'Action 17l inspector contains a service mutation.\n' >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17l inspector contains a peer connection.\n' >&2
        exit 1
    fi

    printf 'action_17l_regression_complete=true\n'
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
