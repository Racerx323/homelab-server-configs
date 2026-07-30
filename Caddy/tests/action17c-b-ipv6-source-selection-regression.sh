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
readonly node_a_diagnostic="$caddy_root/scripts/diagnose-node-a-ipv6-source-selection-action17c-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-ipv6-source-selection-diagnostic-action17c-b.sh"
readonly node_b_inspector_sha256=eb348a76e2ebfe64060e9976ffdbbb772c6a4fc1cf61e092288ce36bd6ec83d2
readonly node_a_diagnostic_sha256=e3fe442b4fcb0a275fb29e5c1e9b4171b3588a27fa51a077cb18cf464c385a82
readonly runner_sha256=14bf3d9735df906f65cbdd037392d57ef394b14bc8921548f11289ab71878e55

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

grep -Fq 'readonly node_a_ipv6=fd36:5aa8:6971:1::53' \
    "$node_a_diagnostic"
grep -Fq 'readonly node_b_ipv6=fd36:5aa8:6971:1::54' \
    "$node_a_diagnostic"
grep -Fq 'selected_source=' "$node_a_diagnostic"
# Intentional literal shell-source assertions.
# shellcheck disable=SC2016
grep -Fq 'bind_options=(-b "$bind_address")' "$node_a_diagnostic"
[[ "$(grep -Fc 'run_probe' "$node_a_diagnostic")" -eq 3 ]]
grep -Fq '    unbound none' "$node_a_diagnostic"
# shellcheck disable=SC2016
grep -Fq '    bound "$node_a_ipv6"' "$node_a_diagnostic"
[[ "$(grep -Fc 'ssh -6 -n -T -vv' "$node_a_diagnostic")" -eq 1 ]]
grep -Fq 'stable_source_binding_restores_authorization' "$runner"
grep -Fq 'rsync_invoked=false' "$node_a_diagnostic"

if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_diagnostic"; then
    printf 'Action 17c-b contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'ip[[:space:]]+(-4[[:space:]]+|-6[[:space:]]+)?(address|addr|route|link|neigh)[[:space:]]+(add|append|change|delete|del|flush|replace|set)' \
    "$node_a_diagnostic"; then
    printf 'Action 17c-b contains a network mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(^|[;&|])[[:space:]]*(runuser[^;&|]*[[:space:]])?rsync([[:space:]]|$)' \
    "$node_a_diagnostic" "$runner"; then
    printf 'Action 17c-b contains an rsync invocation.\n' >&2
    exit 1
fi
if grep -Fq -- '--delete' "$node_a_diagnostic" "$runner"; then
    printf 'Action 17c-b contains a deletion request.\n' >&2
    exit 1
fi

printf 'action_17c_b_ipv6_source_selection_regression_complete=true\n'
