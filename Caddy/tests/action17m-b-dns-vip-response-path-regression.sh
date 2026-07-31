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
readonly inspector="$caddy_root/scripts/inspect-dns-vip-response-path-action17m-b.sh"
readonly runner="$caddy_root/scripts/run-dns-vip-response-path-diagnostic-action17m-b.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"

run_gate() {
    local gate_label=$1
    shift

    if "$@" >/dev/null; then
        printf 'action_17m_b_regression_assertion_%s=true\n' "$gate_label"
    else
        printf 'action_17m_b_regression_assertion_%s=false\n' \
            "$gate_label" >&2
        return 1
    fi
}

run_regression() {
    local required_index=0
    local required_text

    run_gate bash_syntax bash -n "$inspector" "$runner"
    run_gate inspector_self_test "$inspector" --self-test
    run_gate runner_self_test "$runner" --self-test
    run_gate runner_source_context \
        "$source_context_policy" --runner "$runner"
    run_gate runner_contract_test "$runner" --contract-test
    run_gate readonly_local_collision \
        "$collision_checker" "$inspector" "$runner"

    for required_text in \
        'expected_assertion_count=29' \
        'node_a_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1' \
        'node_b_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4' \
        'action_17m_b_value_ipv4_vip_owned=' \
        'action_17m_b_value_ipv6_vip_owned=' \
        'direct_unbound_node_a_aaaa' \
        'local_pihole_node_a_aaaa' \
        'dns_vip_ipv4_node_a_aaaa' \
        'dns_vip_ipv6_node_a_ptr6' \
        'node_a_vip_owner_pending_local_zone_advance' \
        'split_dual_stack_vip_ownership' \
        'invalid_or_duplicate_vip_ownership' \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --" \
        'pi@10.1.0.53' \
        'pi@10.1.0.54' \
        'pihole0.local.theama.co' \
        'pihole00.local.theama.co'; do
        ((required_index += 1))
        if grep -Fq "$required_text" "$inspector" "$runner"; then
            printf 'action_17m_b_regression_assertion_required_text_%02d=true\n' \
                "$required_index"
        else
            printf 'action_17m_b_regression_assertion_required_text_%02d=false\n' \
                "$required_index" >&2
            return 1
        fi
    done

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17m-b inspector contains a filesystem mutation.\n' >&2
        return 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|pihole[[:space:]]+restartdns' \
        "$inspector"; then
        printf 'Action 17m-b inspector contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17m-b inspector contains a peer connection.\n' >&2
        return 1
    fi
    for required_text in \
        remote_paths_created=false \
        peer_connections=false \
        synchronization_commands_executed=false \
        dns_configuration_mutations=false \
        nss_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false; do
        ((required_index += 1))
        if grep -Fq "$required_text" "$inspector"; then
            printf 'action_17m_b_regression_assertion_required_text_%02d=true\n' \
                "$required_index"
        else
            printf 'action_17m_b_regression_assertion_required_text_%02d=false\n' \
                "$required_index" >&2
            return 1
        fi
    done
    printf 'action_17m_b_dns_vip_response_path_regression_complete=true\n'
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
