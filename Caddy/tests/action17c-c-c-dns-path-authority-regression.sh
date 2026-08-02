#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly primary_source_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly local_zone_source_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly dns_manifest_sha256=809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly collector="$caddy_root/scripts/diagnose-dns-path-authority-action17c-c-c.sh"
readonly runner="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh"
readonly primary_source="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly local_zone_source="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_manifest="$caddy_root/manifests/dns-records.yaml"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$collector")" == "$collector_sha256" ]]
[[ "$(file_hash "$primary_source")" == "$primary_source_sha256" ]]
[[ "$(file_hash "$local_zone_source")" == "$local_zone_source_sha256" ]]
[[ "$(file_hash "$dns_manifest")" == "$dns_manifest_sha256" ]]
bash -n "$collector" "$runner"
"$collector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fxq \
    'readonly primary_config_file=/etc/unbound/unbound.conf.d/pihole.conf' \
    "$collector"
grep -Fxq \
    'readonly local_zone_file=/etc/unbound/unbound.conf.d/pihole0-local-zone.conf' \
    "$collector"
grep -Fxq 'readonly unbound_port=5335' "$collector"
grep -Fxq 'readonly configured_ipv4_resolver=10.1.0.1' "$collector"
grep -Fxq 'readonly dns_vip_ipv4=10.1.0.55' "$collector"
grep -Fxq 'readonly dns_vip_ipv6=fd36:5aa8:6971:1::55' "$collector"
grep -Fq 'timeout --signal=TERM 3' "$collector"
grep -Fq 'dig +time=1 +tries=1 +noall +comments +answer' "$collector"
[[ "$(grep -Ec '^[[:space:]]*run_query (local_|configured_|dns_)' \
    "$collector")" -eq 10 ]]
grep -Fq 'node_dns_state_unchanged=true' "$collector"
grep -Fq 'dns_configuration_mutations=false' "$collector"
grep -Fq 'service_mutations=false' "$collector"
grep -Fq 'persistent_mutations=false' "$collector"
grep -Fq 'live_primary_contains_local_zone=' "$collector"

[[ "$(grep -Ec '^[[:space:]]+ssh -T \\$' "$runner")" -eq 1 ]]
grep -Fq 'run_node node-a' "$runner"
grep -Fq 'run_node node-b' "$runner"
grep -Fq 'two_file_unbound_prerequisite_not_converged' "$runner"
grep -Fq 'legacy_single_file_unbound_configuration' "$runner"
grep -Fq 'configured_ipv4_resolver_diverges' "$runner"
grep -Fq 'peer_aaaa_not_deployed' "$runner"
grep -Fq 'caddy_records_not_deployed' "$runner"
grep -Fq 'operator_unbound_sources_git_state=ignored_by_repository_policy' \
    "$runner"

if grep -Eq \
    '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' \
    "$collector" "$runner"; then
    printf 'Action 17c-c-c contains a transfer command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control[[:space:]]+(reload|start|stop)|pihole[[:space:]]+restartdns' \
    "$collector" "$runner"; then
    printf 'Action 17c-c-c contains a DNS or service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$collector"; then
    printf 'Action 17c-c-c collector contains a persistent write command.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(ip|nft|iptables|ip6tables)[[:space:]]+(address[[:space:]]+(add|delete)|route[[:space:]]+(add|delete)|link[[:space:]]+set|rule[[:space:]]+(add|delete)|add|delete|replace|flush)' \
    "$collector" "$runner"; then
    printf 'Action 17c-c-c contains a network mutation.\n' >&2
    exit 1
fi

[[ "$(grep -Ec '^server:$' "$primary_source")" -eq 1 ]]
[[ "$(grep -Ec '^server:$' "$local_zone_source")" -eq 1 ]]
grep -Fxq '    port: 5335' "$primary_source"
grep -Fxq '    local-zone: "local.theama.co." static' "$local_zone_source"
grep -Fxq \
    '    local-data: "pihole00.local.theama.co. IN A 10.1.0.54"' \
    "$local_zone_source"
grep -Fxq \
    '    local-data-ptr: "10.1.0.54 pihole00.local.theama.co."' \
    "$local_zone_source"
if grep -Eq \
    '^[[:space:]]*local-data:[[:space:]]+"pihole00\.local\.theama\.co\.[^"]*[[:space:]]AAAA[[:space:]]' \
    "$local_zone_source"; then
    printf 'Peer AAAA is no longer an expected absence.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*local-data:[[:space:]]+"(proxy|pihole-admin)\.local\.theama\.co\.' \
    "$local_zone_source"; then
    printf 'Caddy records are no longer an expected absence.\n' >&2
    exit 1
fi
grep -Fxq 'status: intended' "$dns_manifest"
grep -Fxq 'apply_only_after: caddy_vrrp_activation_and_validation' \
    "$dns_manifest"

printf 'action_17c_c_c_dns_path_authority_regression_complete=true\n'
