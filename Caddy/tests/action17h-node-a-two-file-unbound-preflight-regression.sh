#!/usr/bin/env bash
# shellcheck disable=SC2016

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
readonly inspector="$caddy_root/scripts/inspect-node-a-two-file-unbound-preflight-action17h.sh"
readonly runner="$caddy_root/scripts/run-node-a-two-file-unbound-preflight-action17h.sh"

bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$script_dir/check-shell-readonly-local-collisions.sh" \
    "$inspector" "$runner" >/dev/null

grep -Fq 'expected_assertion_count=51' "$runner"
grep -Fq 'working_directory_is_root' "$inspector"
grep -Fq 'command_label=${required_command//-/_}' "$inspector"
grep -Fq 'pihole-local-zone.conf' "$inspector"
grep -Fq 'action_17h_first_failure=' "$inspector"
grep -Fq 'cd /' "$runner"
grep -Fq 'service_mutations=false' "$inspector"
grep -Fq 'persistent_mutations=false' "$inspector"
if grep -Eq \
    '(rm|install|cp|mv|chmod|chown|touch|truncate)[^\n]*(/etc/unbound|/var/lib/unbound|/etc/pihole)' \
    "$inspector"; then
    printf 'Action 17h writes to a persistent DNS path.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 17h contains a DNS query or service mutation.\n' >&2
    exit 1
fi

printf 'action_17h_node_a_preflight_regression_complete=true\n'
