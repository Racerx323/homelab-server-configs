#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly inspector_sha256=6a7e25823db2eb04e0873e0f71b5f640b1016cfe0789ed52669f8b2aa1e73a81
readonly failed_runner_sha256=db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6
readonly failed_collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-dns-continuity-action17c-c-c-a.sh"
readonly runner="$caddy_root/scripts/run-dns-continuity-action17c-c-c-a.sh"
readonly failed_runner="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh"
readonly failed_collector="$caddy_root/scripts/diagnose-dns-path-authority-action17c-c-c.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
[[ "$(file_hash "$failed_runner")" == "$failed_runner_sha256" ]]
[[ "$(file_hash "$failed_collector")" == "$failed_collector_sha256" ]]
bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq "readonly failed_stage_pattern='caddy-action17c-c-c.*'" "$inspector"
grep -Fq 'continuity_state_matches_failed_prestate' "$inspector"
grep -Fq 'remote_stage_cleanup_not_required=true' "$inspector"
grep -Fq 'action_17c_c_c_a_mismatch_count=' "$inspector"
grep -Fq 'continuity_verified' "$runner"
grep -Fq 'continuity_mismatch' "$runner"
grep -Fq 'node_a_administrative_ssh_status=' "$runner"
grep -Fq 'node_b_administrative_ssh_status=' "$runner"

if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|mktemp)([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17c-c-c-a inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|[[:space:]]dig[[:space:]]' \
    "$inspector" "$runner"; then
    printf 'Action 17c-c-c-a contains a DNS or service mutation/query.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(ip|nft|iptables|ip6tables)[[:space:]]+(address[[:space:]]+(add|delete)|route[[:space:]]+(add|delete)|link[[:space:]]+set|rule[[:space:]]+(add|delete)|add|delete|replace|flush)' \
    "$inspector" "$runner"; then
    printf 'Action 17c-c-c-a contains a network mutation.\n' >&2
    exit 1
fi

printf 'action_17c_c_c_a_dns_continuity_regression_complete=true\n'
