#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=4d61418345542d51b72a7b9dfe48ce84cbca4c4c356db601a1baf6c9331dd29e
readonly failed_runner_sha256=d38a963934d3e063481e8f81a189fe432cd7002683ae6349d341cbde27c0e5e5
readonly failed_driver_sha256=b67d9fe11d535c1767a1a70c8fe334bf74e007ec2915dd19ca254e72bb99121b

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/diagnose-node-b-unbound-primary-prewrite-action17e-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-unbound-primary-prewrite-diagnostic-action17e-a.sh"
readonly failed_runner="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh"
readonly failed_driver="$caddy_root/scripts/stage-node-b-unbound-primary-action17e.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
[[ "$(file_hash "$failed_runner")" == "$failed_runner_sha256" ]]
[[ "$(file_hash "$failed_driver")" == "$failed_driver_sha256" ]]
bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq 'prewrite_assertion_count=23' "$inspector"
grep -Fq 'prewrite_working_directory_is_root' "$inspector"
grep -Fq 'prewrite_action17d_snapshot_one_matches' "$inspector"
grep -Fq 'prewrite_action17d_snapshot_two_matches' "$inspector"
grep -Fq 'prewrite_action17d_snapshots_stable' "$inspector"
grep -Fq 'prewrite_live_state_one_collected' "$inspector"
grep -Fq 'prewrite_live_state_two_collected' "$inspector"
grep -Fq 'prewrite_live_state_snapshots_stable' "$inspector"
grep -Fq 'primary_stage_state=' "$inspector"
grep -Fq 'local_zone_stage_state=' "$inspector"
grep -Fq 'transaction_stage_count=' "$inspector"
grep -Fq 'remote_paths_created=false' "$inspector"
grep -Fq 'persistent_mutations=false' "$inspector"
grep -Fq 'readonly expected_target=pi@10.1.0.54' "$runner"
grep -Fq \
    'readonly expected_host_alias=pihole00.local.theama.co' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|try-restart|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17e-a contains a DNS query or service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(^|[[:space:]])(install|cp|mv|rm|touch|truncate|chmod|chown|mkdir|mktemp)([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17e-a contains a filesystem mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$inspector"; then
    printf 'Action 17e-a contains a secret-bearing token.\n' >&2
    exit 1
fi

printf 'action_17e_a_node_b_unbound_prewrite_regression_complete=true\n'
