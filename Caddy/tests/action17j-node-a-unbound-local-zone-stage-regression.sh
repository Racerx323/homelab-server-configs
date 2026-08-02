#!/usr/bin/env bash
# shellcheck disable=SC2016 # Assert literal production shell source.

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=e8163bfd71240e880663a4016e28ce73e1d87dbb8fffffc59f9b716ca37e785f
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$caddy_root/scripts/stage-node-a-unbound-local-zone-action17j.sh"
readonly runner="$caddy_root/scripts/run-node-a-unbound-local-zone-stage-action17j.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$driver" && ! -L "$driver" ]]
[[ -f "$runner" && ! -L "$runner" ]]
[[ -f "$collision_checker" && ! -L "$collision_checker" ]]
[[ -f "$candidate_local_zone" && ! -L "$candidate_local_zone" ]]
[[ "$(file_hash "$driver")" == "$driver_sha256" ]]
[[ "$(file_hash "$collision_checker")" == "$collision_checker_sha256" ]]
[[ "$(file_hash "$candidate_local_zone")" == "$candidate_local_zone_sha256" ]]
bash -n "$driver" "$runner"
"$driver" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$collision_checker" "$driver" "$runner" "$0" >/dev/null

grep -Fq \
    'readonly primary_stage=/var/tmp/caddy-unbound-node-a-action17i-primary' \
    "$driver"
grep -Fq \
    'readonly final_stage=/var/tmp/caddy-unbound-node-a-action17j-local-zone' \
    "$driver"
grep -Fq \
    'readonly accepted_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74' \
    "$driver"
grep -Fq 'readonly expected_preflight_assertion_count=64' "$driver"
grep -Fq 'readonly expected_total_assertion_count=90' "$driver"
grep -Fq 'primary_stage_metadata_file_hash' "$driver"
grep -Fq 'primary_stage_manifest_file_hash' "$driver"
grep -Fq 'candidate_local_data_count' "$driver"
grep -Fq 'candidate_local_data_ptr_count' "$driver"
grep -Fq 'candidate_absolute_ptr_target_count' "$driver"
grep -Fq 'persistent_mutation_scope=local_zone_stage_only' "$driver"
grep -Fq 'live_unbound_configuration_mutated=false' "$driver"
grep -Fq 'service_mutations=false' "$driver"
grep -Fq 'dns_queries_performed=false' "$driver"
grep -Fq 'action_17j_rollback_primary_stage_preserved=true' "$driver"
grep -Fq 'action_17j_rollback_complete=true' "$driver"
grep -Fq 'manual_intervention_required=true' "$driver"
grep -Fq 'action_17j_conclusion=transaction_stage_creation_failed' "$driver"
grep -Fq 'final_stage_created_by_action=false' "$driver"
grep -Fq 'mv --no-clobber -T -- "$transaction_stage" "$final_stage"' "$driver"
grep -Fq 'if [[ "$final_stage_created_by_action" == true &&' "$driver"
grep -Fq 'readonly expected_target=pi@10.1.0.53' "$runner"
grep -Fq \
    'readonly expected_host_alias=pihole0.local.theama.co' "$runner"
grep -Fq "'cd /'" "$runner"
grep -Fq 'action_17j_remote_source_cleanup_complete=true' "$runner"

if grep -Fq 'validate_baseline' "$driver" "$runner"; then
    printf 'Action 17j reintroduced an aggregate baseline boundary.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|try-restart|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$driver"; then
    printf 'Action 17j contains a DNS query or service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(install|cp|mv|rm|touch|truncate|chmod|chown)[^\n]*(/etc/unbound|/etc/pihole|/var/lib/unbound)' \
    "$driver"; then
    printf 'Action 17j writes to a live DNS path.\n' >&2
    exit 1
fi
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$driver"; then
    printf 'Action 17j contains a secret-bearing token.\n' >&2
    exit 1
fi
if grep -Fq \
    '"$payload_directory/pihole.conf"' "$runner"; then
    printf 'Action 17j runner attempts to transfer the primary candidate.\n' >&2
    exit 1
fi

printf 'action_17j_node_a_unbound_local_zone_stage_regression_complete=true\n'
