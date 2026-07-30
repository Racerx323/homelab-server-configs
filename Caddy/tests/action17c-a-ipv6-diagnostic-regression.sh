#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-ipv6-restricted-transport-action17c-a.sh"
readonly node_a_diagnostic="$caddy_root/scripts/diagnose-node-a-to-node-b-ipv6-restricted-transport-action17c-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-to-node-b-ipv6-restricted-transport-diagnostic-action17c-a.sh"
readonly node_b_inspector_sha256=eb348a76e2ebfe64060e9976ffdbbb772c6a4fc1cf61e092288ce36bd6ec83d2
readonly node_a_diagnostic_sha256=39be8c27c5bb35c1aac9d73ad6c34c4f12e0c486b06cf9ebbc5a7240b5573d39
readonly runner_sha256=81b07190e35961dd83d8c947e58e8cc41e592454c88e043b52692c69b3e3a706

assert_hash() {
    local path=$1
    local expected=$2

    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected" ]]
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$node_b_inspector" "$node_b_inspector_sha256"
assert_hash "$node_a_diagnostic" "$node_a_diagnostic_sha256"
assert_hash "$runner" "$runner_sha256"
bash -n "$node_b_inspector" "$node_a_diagnostic" "$runner"
"$node_b_inspector" --self-test >/dev/null
"$node_a_diagnostic" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq 'readonly node_b_ipv6=fd36:5aa8:6971:1::54' \
    "$node_a_diagnostic"
grep -Fq 'readonly node_a_ipv6=fd36:5aa8:6971:1::53' \
    "$node_a_diagnostic"
grep -Fq 'ssh -6 -n -T -vv' "$node_a_diagnostic"
# Intentional literal shell-source assertion.
# shellcheck disable=SC2016
grep -Fq 'ip -6 route get "$node_b_ipv6"' "$node_a_diagnostic"
grep -Fq 'ping -6 -n -c 1 -W 2' "$node_a_diagnostic"
grep -Fq 'node_a_ipv6_ssh_error_class=' "$node_a_diagnostic"
grep -Fq 'node_a_ipv6_ssh_stderr_sha256=' "$node_a_diagnostic"
grep -Fq 'rsync_invoked=false' "$node_a_diagnostic"
grep -Fq 'node_b_ssh_ipv6_listener_present=' "$node_b_inspector"
grep -Fq 'node_b_authorization_source_ipv6_present=' "$node_b_inspector"
grep -Fq 'action_17c_a_diagnostic_conclusion=' "$runner"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_b_inspector" "$node_a_diagnostic"; then
    printf 'Action 17c-a contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'ip[[:space:]]+(-4[[:space:]]+|-6[[:space:]]+)?(address|addr|route|link|neigh)[[:space:]]+(add|append|change|delete|del|flush|replace|set)' \
    "$node_b_inspector" "$node_a_diagnostic"; then
    printf 'Action 17c-a contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(^|[;&|])[[:space:]]*(runuser[^;&|]*[[:space:]])?rsync([[:space:]]|$)' \
    "$node_b_inspector" "$node_a_diagnostic" "$runner"; then
    printf 'Action 17c-a contains an rsync invocation.\n' >&2
    exit 1
fi
if grep -Fq -- '--delete' \
    "$node_b_inspector" "$node_a_diagnostic" "$runner"; then
    printf 'Action 17c-a contains a deletion request.\n' >&2
    exit 1
fi

printf 'action_17c_a_ipv6_diagnostic_regression_complete=true\n'
