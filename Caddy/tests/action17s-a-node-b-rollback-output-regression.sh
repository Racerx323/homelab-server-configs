#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-b-action17s-rollback-output-action17s-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-action17s-rollback-output-action17s-a.sh"
readonly finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly expected_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_validate_block_sha256=d198df3898fdb385b54d0c95bc99c0d8ad4ad6ed0045e1d51dccee3e6e02aefb

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_validate_block_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17s_a_regression_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$inspector" && ! -L "$inspector" ]]
[[ -f "$runner" && ! -L "$runner" ]]
[[ "$(file_hash "$finalizer")" = "$expected_finalizer_sha256" ]]
bash -n "$inspector"
bash -n "$runner"
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" --runner "$runner" >/dev/null
"$caddy_root/tests/check-shell-readonly-local-collisions.sh" \
    "$inspector" "$runner" >/dev/null

expected_count=$("$inspector" --expected-checks | wc -l)
unique_count=$("$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)
readonly expected_count unique_count
[[ "$expected_count" -gt 50 ]]
[[ "$expected_count" -eq "$unique_count" ]]

mutation_command_count=$(grep -Ec \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$inspector" || true)
readonly mutation_command_count
[[ "$mutation_command_count" -eq 1 ]]
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
grep -Fxq '    rm -rf -- "$work_directory"' "$inspector"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$inspector"; then
    printf 'Action 17s-a inspector contains a service mutation.\n' >&2
    exit 1
fi
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
if grep -Eq 'runuser[^\n]*finalizer|"\$finalizer"[[:space:]]+--source-role' \
    "$inspector"; then
    printf 'Action 17s-a inspector can invoke the finalizer.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' "$inspector"; then
    printf 'Action 17s-a inspector contains a peer connection.\n' >&2
    exit 1
fi

validate_block_hash=$(
    awk '
        /^[[:space:]]*require_check caddy_configuration_valid/ {
            capture = 1
        }
        capture { print }
        capture && /--adapter caddyfile/ { exit }
    ' "$finalizer" | sha256sum | awk '{ print $1 }'
)
readonly validate_block_hash
[[ "$validate_block_hash" = "$expected_validate_block_sha256" ]]
grep -Fq 'if "$@"; then' "$finalizer"
[[ "$(grep -Ec '^[[:space:]]*caddy validate ' "$finalizer")" -eq 1 ]]

"$caddy_root/tests/transaction-output-evidence-policy-regression.sh" >/dev/null
printf 'action_17s_a_false_positive_regression=true\n'
printf 'action_17s_a_false_negative_regression=true\n'
printf 'action_17s_a_node_b_rollback_output_regression_complete=true\n'
