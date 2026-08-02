#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match literal protected-path source text.

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly accepted_action17e_runner_sha256=5354fcd0fa5710ebef77f6751e4094903685d17056891760229c84b08868be92

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly accepted_action17e_runner="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_hash() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

active_directives() {
    awk '
        /^[[:space:]]*(#|$)/ { next }
        {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/[[:space:]]+/, " ")
            print
        }
    ' "$1"
}

run_static_test() {
    local local_policy_count forbidden_count

    verify_hash "$driver" "$driver_sha256"
    verify_hash "$candidate_primary" "$candidate_primary_sha256"
    verify_hash "$candidate_local_zone" "$candidate_local_zone_sha256"
    verify_hash \
        "$accepted_action17e_runner" "$accepted_action17e_runner_sha256"
    bash -n "$driver"
    "$driver" --self-test >/dev/null

    [[ "$(active_directives "$candidate_primary" |
        grep -Fxc server:)" -eq 1 ]]
    [[ "$(active_directives "$candidate_primary" |
        grep -Ec \
            '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
        true)" -eq 0 ]]
    [[ "$(active_directives "$candidate_local_zone" |
        grep -Fxc server:)" -eq 1 ]]
    local_policy_count=$(
        active_directives "$candidate_local_zone" |
            grep -Ec \
                '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
            true
    )
    forbidden_count=$(
        active_directives "$candidate_local_zone" |
            grep -Ec \
                '^(interface|port|access-control|forward-zone|forward-addr):' ||
            true
    )
    [[ "$local_policy_count" -eq 46 ]]
    [[ "$forbidden_count" -eq 0 ]]

    grep -Fq \
        'readonly primary_stage=/var/tmp/caddy-unbound-node-b-action17e-primary' \
        "$driver"
    grep -Fq \
        'readonly final_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone' \
        "$driver"
    grep -Fq 'validate_primary_stage' "$driver"
    grep -Fq 'validate_combined_pair' "$driver"
    grep -Fq 'combined_pair_parser_valid=true' "$driver"
    grep -Fq 'persistent_mutation_scope=local_zone_stage_only' "$driver"
    grep -Fq 'action_17f_rollback_complete=true' "$driver"
    grep -Fq 'action_17f_prewrite_failure_before_mutation=true' "$driver"
    grep -Fq 'manual_intervention_required=true' "$driver"

    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|try-restart|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
        "$driver"; then
        printf 'Action 17f contains a DNS query or service mutation.\n' >&2
        exit 1
    fi
    if grep -Eq \
        '(install|cp|mv|rm|touch|truncate|chmod|chown)[^\n]*(/etc/unbound|/etc/pihole|/var/lib/unbound)' \
        "$driver"; then
        printf 'Action 17f writes to a live DNS path.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'rm -rf -- "\$primary_stage"|mv -- .+ "\$primary_stage"' \
        "$driver"; then
        printf 'Action 17f can mutate the accepted primary stage.\n' >&2
        exit 1
    fi
    printf 'action_17f_node_b_unbound_local_zone_stage_static_regression_complete=true\n'
}

run_parser_test() {
    local test_dir

    command -v unbound-checkconf >/dev/null
    [[ -f /run/.containerenv ]]
    install -d -m 0755 /var/log/unbound
    test_dir=$(mktemp -d /tmp/caddy-action17f-parser.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    install -d -m 0700 "$test_dir/conf.d"
    install -m 0600 "$candidate_primary" "$test_dir/conf.d/pihole.conf"
    install -m 0600 \
        "$candidate_local_zone" "$test_dir/conf.d/pihole0-local-zone.conf"
    printf 'include-toplevel: "%s/*.conf"\n' \
        "$test_dir/conf.d" >"$test_dir/unbound.conf"
    chmod 0600 "$test_dir/unbound.conf"
    unbound-checkconf "$test_dir/unbound.conf" >/dev/null
    printf 'action_17f_combined_pair_parser_regression_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_static_test
        ;;
    --parser-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_parser_test
        ;;
    *)
        printf 'Usage: %s --self-test|--parser-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
