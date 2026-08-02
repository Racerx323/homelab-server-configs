#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=0a9be5bf5f16879ea88092ca056ae52edcfb299b6ca3d274d1d14b29d2480d3f
readonly accepted_dns_runner_sha256=148803926e39164b76f35e637fea200cb6c55a6f9acf18fe740f2d6871cb64d6
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-b-two-file-unbound-preflight-action17d.sh"
readonly accepted_dns_runner="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$inspector" && ! -L "$inspector" ]]
[[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
[[ "$(file_hash "$accepted_dns_runner")" == "$accepted_dns_runner_sha256" ]]
bash -n "$inspector"
"$inspector" --self-test >/dev/null

for value in \
    "$inspector_sha256" \
    "$accepted_dns_runner_sha256" \
    "$candidate_primary_sha256" \
    "$candidate_local_zone_sha256"; do
    [[ "$value" =~ ^[0-9a-f]{64}$ ]]
done

grep -Fq "readonly live_primary=\"\$live_conf_dir/pihole.conf\"" "$inspector"
grep -Fq \
    "readonly live_local_zone=\"\$live_conf_dir/pihole0-local-zone.conf\"" \
    "$inspector"
grep -Fq 'readonly accepted_live_primary_sha256=017aa255' "$inspector"
grep -Fq 'root_include_topology_supported=' "$inspector"
grep -Fq 'canonical_directives_equal=' "$inspector"
grep -Fq 'candidate_parser_valid=' "$inspector"
grep -Fq 'node_state_unchanged=' "$inspector"
grep -Fq 'ready_for_staged_adoption_design' "$inspector"
grep -Fq 'candidate_semantic_drift' "$inspector"
grep -Fq 'candidate_parser_rejected' "$inspector"
grep -Fq 'unsupported_include_topology' "$inspector"
grep -Fq 'dns_configuration_mutations=false' "$inspector"
grep -Fq 'service_mutations=false' "$inspector"
grep -Fq 'persistent_mutations=false' "$inspector"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17d inspector contains a DNS or service mutation/query.\n' \
        >&2
    exit 1
fi
if grep -Eq \
    '(^|[[:space:]])(nft|iptables|ip6tables)[[:space:]]|(^|[[:space:]])ip[[:space:]]+(address|route|link|rule)[[:space:]]+(add|delete|replace|flush|set)' \
    "$inspector"; then
    printf 'Action 17d inspector contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(rm|install|cp|mv|chmod|chown|touch|truncate)[^\n]*(/etc/unbound|/var/lib/unbound|/etc/pihole)' \
    "$inspector"; then
    printf 'Action 17d inspector writes to a persistent DNS path.\n' >&2
    exit 1
fi
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$inspector"; then
    printf 'Action 17d inspector contains a secret-bearing token.\n' >&2
    exit 1
fi

printf 'action_17d_node_b_unbound_preflight_regression_complete=true\n'
