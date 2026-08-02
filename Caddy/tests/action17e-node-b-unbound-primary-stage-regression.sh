#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=b67d9fe11d535c1767a1a70c8fe334bf74e007ec2915dd19ca254e72bb99121b
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$caddy_root/scripts/stage-node-b-unbound-primary-action17e.sh"
readonly runner="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$driver" && ! -L "$driver" ]]
[[ -f "$runner" && ! -L "$runner" ]]
[[ -f "$candidate_primary" && ! -L "$candidate_primary" ]]
[[ "$(file_hash "$driver")" == "$driver_sha256" ]]
[[ "$(file_hash "$candidate_primary")" == "$candidate_primary_sha256" ]]
bash -n "$driver" "$runner"
"$driver" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq \
    'readonly final_stage=/var/tmp/caddy-unbound-node-b-action17e-primary' \
    "$driver"
grep -Fq \
    'readonly later_local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone' \
    "$driver"
grep -Fq \
    'readonly accepted_action17d_state_sha256=31862f7b0f86a6cddc9057501fffeff872bc3747a0144bb7d062fddcced9992c' \
    "$driver"
grep -Fq 'persistent_mutation_scope=primary_stage_only' "$driver"
grep -Fq 'local_zone_file_staged=false' "$driver"
grep -Fq 'live_unbound_configuration_mutated=false' "$driver"
grep -Fq 'service_mutations=false' "$driver"
grep -Fq 'dns_queries_performed=false' "$driver"
grep -Fq 'action_17e_rollback_complete=true' "$driver"
grep -Fq 'manual_intervention_required=true' "$driver"
grep -Fq 'readonly expected_target=pi@10.1.0.54' "$runner"
grep -Fq \
    'readonly expected_host_alias=pihole00.local.theama.co' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|try-restart|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$driver"; then
    printf 'Action 17e contains a DNS query or service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(install|cp|mv|rm|touch|truncate|chmod|chown)[^\n]*(/etc/unbound|/etc/pihole|/var/lib/unbound)' \
    "$driver"; then
    printf 'Action 17e writes to a live DNS path.\n' >&2
    exit 1
fi
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$driver"; then
    printf 'Action 17e contains a secret-bearing token.\n' >&2
    exit 1
fi

printf 'action_17e_node_b_unbound_primary_stage_regression_complete=true\n'
