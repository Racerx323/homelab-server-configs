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
readonly inspector="$caddy_root/scripts/inspect-node-a-dns-nss-post-rollback-action17n-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-dns-nss-post-rollback-action17n-a.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"
readonly readiness_policy="$script_dir/labeled-dns-readiness-policy-regression.sh"

production_count_regression() {
    local fixture_root=$1
    local rendered_inspector="$fixture_root/inspector"
    local fixture_output="$fixture_root/output"
    local fixture_status

    install -d -m 0700 "$fixture_root/bin"
    # shellcheck disable=SC2016
    sed \
        's|^PATH=/usr/sbin:/usr/bin:/sbin:/bin$|PATH="$ACTION17N_A_TEST_ROOT/bin:/usr/sbin:/usr/bin:/sbin:/bin"|' \
        "$inspector" >"$rendered_inspector"
    chmod 0700 "$rendered_inspector"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$fixture_root/bin/dig"
    chmod 0700 "$fixture_root/bin/dig"
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

    set +e
    ACTION17N_A_TEST_ROOT="$fixture_root" \
        /bin/bash "$rendered_inspector" >"$fixture_output" 2>&1
    fixture_status=$?
    set -e

    [[ "$fixture_status" -eq 1 ]]
    grep -Fxq 'action_17n_a_assertion_count=87' "$fixture_output"
    grep -Fxq 'action_17n_a_remote_complete=true' "$fixture_output"
    grep -Fxq \
        'action_17n_a_conclusion=post_rollback_state_mismatch' \
        "$fixture_output"
    [[ "$(grep -Ec \
        '^action_17n_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$fixture_output")" -eq 87 ]]
    [[ "$(grep -E \
        '^action_17n_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$fixture_output" |
        cut -d= -f1 |
        LC_ALL=C sort -u |
        wc -l)" -eq 87 ]]
    [[ "$(grep -Ec \
        '^action_17n_a_value_[a-z0-9_]+_answer=none$' \
        "$fixture_output")" -eq 6 ]]
    grep -Fxq 'remote_paths_created=false' "$fixture_output"
    grep -Fxq 'peer_connections=false' "$fixture_output"
    grep -Fxq 'synchronization_commands_executed=false' "$fixture_output"
    grep -Fxq 'dns_configuration_mutations=false' "$fixture_output"
    grep -Fxq 'nss_configuration_mutations=false' "$fixture_output"
    grep -Fxq 'service_mutations=false' "$fixture_output"
    grep -Fxq 'persistent_mutations=false' "$fixture_output"
    printf 'action_17n_a_production_count_regression_complete=true\n'
}

run_regression() {
    local regression_root
    local required_label

    bash -n "$inspector" "$runner" "$readiness_policy"
    "$inspector" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$source_context_policy" --runner "$runner" >/dev/null
    "$runner" --contract-test >/dev/null
    "$readiness_policy" --production-test >/dev/null
    "$collision_checker" "$inspector" "$runner" "$readiness_policy" >/dev/null

    for required_label in \
        live_local_zone_hash backup_directory backup_directory_not_symlink \
        backup_local_zone_hash \
        backup_manifest_action backup_manifest_hosts_hash_matches_backup \
        live_hosts_hash_matches_backup \
        hosts_marker_begin_absent \
        hosts_marker_end_absent peer_fqdn_hosts_absent unbound_active \
        pihole_ftl_active direct_unbound_peer_aaaa \
        direct_unbound_node_a_aaaa direct_unbound_peer_ptr6 \
        local_pihole_peer_aaaa local_pihole_node_a_aaaa \
        local_pihole_peer_ptr6; do
        grep -Fq "$required_label" "$inspector"
    done
    grep -Fq "assert_equal \"\${probe_label}_status\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${probe_label}_answer_safe\"" "$inspector"
    grep -Fq \
        "assert_equal \"\${reverse_probe_label}_status\"" "$inspector"
    grep -Fq \
        "record_assertion \"\${reverse_probe_label}_answer_safe\"" "$inspector"
    grep -Fq 'expected_assertion_count=87' "$inspector"
    grep -Fq 'expected_assertion_count=87' "$runner"
    grep -Fq 'expected_dns_value_count=6' "$runner"
    grep -Fq 'remote_paths_created=false' "$inspector"
    grep -Fq 'dns_configuration_mutations=false' "$inspector"
    grep -Fq 'nss_configuration_mutations=false' "$inspector"
    grep -Fq 'service_mutations=false' "$inspector"
    grep -Fq 'persistent_mutations=false' "$inspector"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$runner"
    grep -Fq 'action_17n_a_runner_classification=%s' "$runner"
    grep -Fq 'action_17n_a_runner_classification=evidence_failure' "$runner"

    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17n-a inspector contains a filesystem mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control' \
        "$inspector"; then
        printf 'Action 17n-a inspector contains a service mutation.\n' >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17n-a inspector contains a peer connection.\n' >&2
        exit 1
    fi

    regression_root=$(mktemp -d /tmp/caddy-action17n-a-regression.XXXXXX)
    trap 'rm -rf -- "$regression_root"' RETURN
    production_count_regression "$regression_root"
    printf 'action_17n_a_regression_complete=true\n'
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
