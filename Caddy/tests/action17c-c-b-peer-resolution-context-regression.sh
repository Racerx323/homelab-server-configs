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
readonly diagnostic="$caddy_root/scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh"
readonly action17c_c_a_runner="$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh"
readonly diagnostic_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d
readonly runner_sha256=d0fa596f3912288b24645fa6fa9bbbfe15fa0fffd38d7d6308f11041a7bdb4da
readonly action17c_c_a_runner_sha256=f460262cded8b056818f27b0d82cd637627aa6440a67d6eb409325ac73c301d2

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$diagnostic")" == "$diagnostic_sha256" ]]
[[ "$(file_hash "$runner")" == "$runner_sha256" ]]
[[ "$(file_hash "$action17c_c_a_runner")" == "$action17c_c_a_runner_sha256" ]]
if [[ "$(id -un)" == aaron ]]; then
    [[ "$(stat -c '%U:%G:%a' "$diagnostic")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$runner")" == aaron:aaron:755 ]]
fi
bash -n "$diagnostic" "$runner"
"$diagnostic" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq 'readonly -a context_labels=(administrative root caddy_sync)' \
    "$diagnostic"
grep -Fq 'readonly -a context_users=(pi root caddy-sync)' "$diagnostic"
grep -Fq 'readonly -a databases=(ahostsv4 ahostsv6)' "$diagnostic"
grep -Fq '/usr/bin/timeout --signal=TERM 5' "$diagnostic"
grep -Fq "/usr/bin/getent \"\$database\" \"\$peer_fqdn\"" "$diagnostic"
grep -Fq 'resolv_conf_canonical_target_b64=' "$diagnostic"
grep -Fq 'nsswitch_hosts_line_b64=' "$diagnostic"
grep -Fq 'resolver_nameserver_count=' "$diagnostic"
grep -Fq '_address_set_b64=%s' "$diagnostic"
grep -Fq '_output_truncated=true' "$diagnostic"
grep -Fq 'node_a_resolver_state_unchanged=true' "$diagnostic"
grep -Fq 'peer_ssh_invoked=false' "$diagnostic"
grep -Fq 'rsync_invoked=false' "$diagnostic"
grep -Fq 'persistent_mutations=false' "$diagnostic"
grep -Fq "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" "$runner"
grep -Fq 'caddy_sync_context_differs' "$runner"
[[ "$(grep -Fc "printf '%s_identity=%s" "$diagnostic")" -eq 1 ]]

if grep -Eq '^[[:space:]]*ssh([[:space:]]|$)' "$diagnostic"; then
    printf 'Action 17c-c-b Node A diagnostic contains a peer SSH command.\n' >&2
    exit 1
fi
if [[ "$(grep -Ec '^[[:space:]]*ssh -T \\$' "$runner")" -ne 1 ]]; then
    printf 'Action 17c-c-b runner must contain one administrative SSH call.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-b contains a transfer command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-b contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(ip|nft|iptables|ip6tables)[[:space:]]+(address[[:space:]]+(add|delete)|route[[:space:]]+(add|delete)|link[[:space:]]+set|rule[[:space:]]+(add|delete)|add|delete|replace|flush)' \
    "$diagnostic" "$runner"; then
    printf 'Action 17c-c-b contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17c-c-b Node A diagnostic contains a persistent write command.\n' >&2
    exit 1
fi

printf 'action_17c_c_b_peer_resolution_context_regression_complete=true\n'
