#!/usr/bin/env bash
# shellcheck disable=SC2016 # Assert literal production shell source.

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=75986f675f0805bea87c7ce01b37fdb6c778575b14e98442556511d73b5044c5
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-a-unbound-dual-stage-action17j-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-unbound-dual-stage-acceptance-action17j-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$inspector" && ! -L "$inspector" ]]
[[ -f "$runner" && ! -L "$runner" ]]
[[ -f "$collision_checker" && ! -L "$collision_checker" ]]
[[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
[[ "$(file_hash "$collision_checker")" == "$collision_checker_sha256" ]]
bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$collision_checker" "$inspector" "$runner" "$0" >/dev/null

grep -Fq \
    'readonly primary_stage=/var/tmp/caddy-unbound-node-a-action17i-primary' \
    "$inspector"
grep -Fq \
    'readonly local_zone_stage=/var/tmp/caddy-unbound-node-a-action17j-local-zone' \
    "$inspector"
grep -Fq \
    'readonly accepted_live_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74' \
    "$inspector"
grep -Fq 'readonly expected_assertion_count=70' "$inspector"
grep -Fq 'action_17j_a_first_failure=' "$inspector"
grep -Fq 'combined_parser_status=' "$inspector"
grep -Fq 'local_zone_absolute_ptr_count' "$inspector"
grep -Fq 'remote_paths_created=false' "$inspector"
grep -Fq 'dns_queries_performed=false' "$inspector"
grep -Fq 'dns_configuration_mutations=false' "$inspector"
grep -Fq 'service_mutations=false' "$inspector"
grep -Fq 'persistent_mutations=false' "$inspector"
grep -Fq "cd / && exec /bin/bash -s --" "$runner"
grep -Fq 'return 97' "$runner"
grep -Fq 'return 1' "$runner"

if grep -Fq 'validate_baseline' "$inspector" "$runner"; then
    printf 'Action 17j-a reintroduced an aggregate baseline boundary.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17j-a inspector contains a filesystem mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17j-a inspector contains a query or service mutation.\n' \
        >&2
    exit 1
fi
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$inspector"; then
    printf 'Action 17j-a inspector contains a secret-bearing token.\n' >&2
    exit 1
fi

printf 'action_17j_a_node_a_dual_stage_acceptance_regression_complete=true\n'
