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
readonly inspector="$caddy_root/scripts/inspect-node-b-dns-nss-post-correction-action17m-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-dns-nss-post-correction-action17m-a.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"

production_count_regression() {
    local fixture_root=$1
    local rendered_inspector="$fixture_root/inspector"
    local fixture_output="$fixture_root/output"
    local fixture_status
    local stub_name

    install -d -m 0700 "$fixture_root/bin"
    # shellcheck disable=SC2016
    sed \
        's|^PATH=/usr/sbin:/usr/bin:/sbin:/bin$|PATH="$ACTION17M_A_TEST_ROOT/bin:/usr/sbin:/usr/bin:/sbin:/bin"|' \
        "$inspector" >"$rendered_inspector"
    chmod 0700 "$rendered_inspector"

    for stub_name in dig getent runuser; do
        printf '%s\n' '#!/bin/sh' 'exit 1' >"$fixture_root/bin/$stub_name"
        chmod 0700 "$fixture_root/bin/$stub_name"
    done
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" fixture-node' \
        >"$fixture_root/bin/hostname"
    chmod 0700 "$fixture_root/bin/hostname"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  is-active) printf "%s\n" active ;;' \
        '  show) printf "%s\n" 1 ;;' \
        'esac' \
        'exit 0' \
        >"$fixture_root/bin/systemctl"
    chmod 0700 "$fixture_root/bin/systemctl"
    printf '%s\n' '#!/bin/sh' 'exit 0' \
        >"$fixture_root/bin/unbound-checkconf"
    chmod 0700 "$fixture_root/bin/unbound-checkconf"

    set +e
    ACTION17M_A_TEST_ROOT="$fixture_root" \
        /bin/bash "$rendered_inspector" >"$fixture_output" 2>&1
    fixture_status=$?
    set -e

    [[ "$fixture_status" -eq 1 ]]
    grep -Fxq 'action_17m_a_assertion_count=98' "$fixture_output"
    grep -Fxq 'action_17m_a_remote_complete=true' "$fixture_output"
    grep -Fxq \
        'action_17m_a_conclusion=post_correction_state_mismatch' \
        "$fixture_output"
    grep -Fxq 'remote_paths_created=false' "$fixture_output"
    grep -Fxq 'peer_connections=false' "$fixture_output"
    grep -Fxq 'synchronization_commands_executed=false' "$fixture_output"
    grep -Fxq 'dns_configuration_mutations=false' "$fixture_output"
    grep -Fxq 'nss_configuration_mutations=false' "$fixture_output"
    grep -Fxq 'service_mutations=false' "$fixture_output"
    grep -Fxq 'persistent_mutations=false' "$fixture_output"
    [[ "$(grep -Ec \
        '^action_17m_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$fixture_output")" -eq 98 ]]
    [[ "$(grep -E \
        '^action_17m_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$fixture_output" |
        cut -d= -f1 |
        LC_ALL=C sort -u |
        wc -l)" -eq 98 ]]
    printf 'action_17m_a_production_count_regression_complete=true\n'
}

run_regression() {
    local test_root
    local required_label

    bash -n "$inspector" "$runner"
    "$inspector" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$source_context_policy" --runner "$runner" >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$inspector" "$runner" >/dev/null

    for required_label in \
        live_local_zone_hash backup_directory backup_local_zone_hash \
        backup_manifest_hosts_hash hosts_managed_block_exact \
        hosts_vip_mapping_absent local_zone_homeassistant_a_absent \
        local_zone_caddy_records_absent pihole_vip_aaaa node_a_ptr6 \
        live_parser_status unbound_active direct_pihole_vip_aaaa \
        direct_node_a_ptr6 pihole_local_node_a_aaaa \
        dns_vip_ipv4_node_a_ptr6 dns_vip_ipv6_node_a_aaaa \
        root_peer_ipv4 root_peer_ipv6 \
        caddy_sync_peer_ipv4 caddy_sync_peer_ipv6 state_unchanged; do
        grep -Fq "$required_label" "$inspector"
    done
    grep -Fq 'expected_assertion_count=98' "$inspector"
    grep -Fq 'expected_assertion_count=98' "$runner"
    grep -Fq 'remote_paths_created=false' "$inspector"
    grep -Fq 'peer_connections=false' "$inspector"
    grep -Fq 'synchronization_commands_executed=false' "$inspector"
    grep -Fq 'dns_configuration_mutations=false' "$inspector"
    grep -Fq 'nss_configuration_mutations=false' "$inspector"
    grep -Fq 'service_mutations=false' "$inspector"
    grep -Fq 'persistent_mutations=false' "$inspector"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$runner"
    grep -Fq 'action_17m_a_runner_classification=%s' "$runner"
    grep -Fq 'printf verified' "$runner"
    grep -Fq 'printf semantic_mismatch' "$runner"
    grep -Fq 'action_17m_a_runner_classification=evidence_failure' "$runner"

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17m-a inspector contains a filesystem mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control' \
        "$inspector"; then
        printf 'Action 17m-a inspector contains a service mutation.\n' >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17m-a inspector contains a peer connection.\n' >&2
        exit 1
    fi

    test_root=$(mktemp -d /tmp/caddy-action17m-a-regression.XXXXXX)
    trap 'rm -rf -- "$test_root"' RETURN
    production_count_regression "$test_root"
    printf 'action_17m_a_regression_complete=true\n'
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
