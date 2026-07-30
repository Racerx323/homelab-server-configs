#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly diagnostic="$caddy_root/scripts/diagnose-node-a-source-bound-transport-action17c-c-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh"
readonly inspector="$caddy_root/scripts/inspect-node-b-restricted-transport-state-action17c.sh"
readonly diagnostic_sha256=3011cd5498729b8b3fff9731975f51f737610e41d0b9ee60e857ec3ff83b0609
readonly runner_sha256=f460262cded8b056818f27b0d82cd637627aa6440a67d6eb409325ac73c301d2
readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$diagnostic")" == "$diagnostic_sha256" ]]
[[ "$(file_hash "$runner")" == "$runner_sha256" ]]
[[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
if [[ "$(id -un)" == aaron ]]; then
    [[ "$(stat -c '%U:%G:%a' "$diagnostic")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$runner")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
fi
bash -n "$diagnostic" "$runner" "$inspector"
"$diagnostic" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

[[ "$(grep -Ec '^[[:space:]]*ssh -6 -n -T -vv \\$' "$diagnostic")" -eq 1 ]]
grep -Fq -- "-b \"\$node_a_ipv6\"" "$diagnostic"
grep -Fq "\"caddy-sync@\$node_b_fqdn\"" "$diagnostic"
grep -Fq 'readonly node_b_fqdn=pihole00.local.theama.co' "$diagnostic"
grep -Fq "sudo -n /bin/bash -c 'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s --'" \
    "$runner"
grep -Fq 'source_bound_ssh_error_class=' "$diagnostic"
grep -Fq 'source_bound_ssh_stdout_sha256=' "$diagnostic"
grep -Fq 'source_bound_ssh_stderr_sha256=' "$diagnostic"
grep -Fq 'source_bound_ssh_authenticated=' "$diagnostic"
grep -Fq 'source_bound_forced_receiver_message=' "$diagnostic"
grep -Fq 'prestate_checks_total=' "$diagnostic"
grep -Fq 'node_b_protected_state_unchanged=true' "$runner"
grep -Fq 'release_payload_transferred=false' "$diagnostic"
grep -Fq 'rsync_invoked=false' "$diagnostic"
grep -Fq 'service_mutations=false' "$diagnostic"

if grep -Eq \
    '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-a contains a transfer command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-a contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(ip|nft|iptables|ip6tables)[[:space:]]+(address[[:space:]]+(add|delete)|route[[:space:]]+(add|delete)|link[[:space:]]+set|rule[[:space:]]+(add|delete)|add|delete|replace|flush)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-a contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17c-c-a Node A diagnostic contains a persistent write command.\n' >&2
    exit 1
fi

printf 'action_17c_c_a_source_bound_diagnostic_regression_complete=true\n'
