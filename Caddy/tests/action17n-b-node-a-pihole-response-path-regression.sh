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
readonly inspector="$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"

run_gate() {
    local gate_label=$1
    shift

    if "$@" >/dev/null; then
        printf 'action_17n_b_regression_assertion_%s=true\n' "$gate_label"
    else
        printf 'action_17n_b_regression_assertion_%s=false\n' "$gate_label" >&2
        return 1
    fi
}

run_regression() {
    local required_text

    run_gate bash_syntax bash -n "$inspector" "$runner"
    run_gate inspector_self_test "$inspector" --self-test
    run_gate runner_self_test "$runner" --self-test
    run_gate runner_source_context \
        "$source_context_policy" --runner "$runner"
    run_gate readonly_local_collision \
        "$collision_checker" "$inspector" "$runner"

    # shellcheck disable=SC2016
    for required_text in \
        'Pi-hole version is v5' \
        'FTL version is v5' \
        'pihole_restartdns_interface_present' \
        'PIHOLE_DNS_[0-9]+=127' \
        'server=127' \
        'direct_unbound_peer_aaaa' \
        'direct_unbound_peer_ptr6' \
        'local_pihole_peer_aaaa_first' \
        'local_pihole_peer_ptr6_second' \
        'pihole_cache_reset_performed=false' \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
        'pi@10.1.0.53' \
        'HostKeyAlias="$expected_host_alias"'; do
        grep -Fq "$required_text" "$inspector" "$runner"
    done

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17n-b inspector contains a filesystem mutation.\n' >&2
        return 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|pihole[[:space:]]+restartdns' \
        "$inspector"; then
        printf 'Action 17n-b inspector contains a service/cache mutation.\n' >&2
        return 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17n-b inspector contains a peer connection.\n' >&2
        return 1
    fi
    printf 'action_17n_b_node_a_pihole_response_path_regression_complete=true\n'
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
