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
readonly inspector="$caddy_root/scripts/inspect-node-b-action17s-retry-stderr-action17s-b.sh"
readonly runner="$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh"
readonly corrected_finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly renderer="$caddy_root/scripts/render-node-b-stdout-safe-finalizer-action17t.sh"
readonly expected_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_validate_block_sha256=be85e806dfefe0781806e8f95f00c2e1e1d4ef9393aca24efa2a382bad99ccde

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17s_b_regression_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$inspector" && ! -L "$inspector" ]]
[[ -f "$runner" && ! -L "$runner" ]]
work_directory=$(mktemp -d /tmp/caddy-action17s-b-regression.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
readonly rendered_finalizer="$work_directory/finalize-incoming-release-v2.sh"
"$renderer" --input "$corrected_finalizer" --output "$rendered_finalizer" >/dev/null
[[ "$(file_hash "$rendered_finalizer")" = "$expected_finalizer_sha256" ]]
bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" --runner "$runner" >/dev/null
"$caddy_root/tests/check-shell-readonly-local-collisions.sh" "$inspector" "$runner" >/dev/null

expected_count=$("$inspector" --expected-checks | wc -l)
unique_count=$("$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)
readonly expected_count unique_count
[[ "$expected_count" -eq 53 && "$expected_count" -eq "$unique_count" ]]

mutation_command_count=$(grep -Ec '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' "$inspector" || true)
readonly mutation_command_count
[[ "$mutation_command_count" -eq 0 ]]
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$inspector"; then
    printf 'Action 17s-b inspector contains a service mutation.\n' >&2
    exit 1
fi
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
if grep -Eq 'runuser[^\n]*finalizer|"\$finalizer"[[:space:]]+--source-role' "$inspector"; then
    printf 'Action 17s-b inspector can invoke the finalizer.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' "$inspector"; then
    printf 'Action 17s-b inspector contains a peer connection.\n' >&2
    exit 1
fi

validate_block_hash=$(awk '
    /^[[:space:]]*require_check caddy_configuration_valid/ { capture = 1 }
    capture { print }
    capture && /--adapter caddyfile/ { exit }
' "$rendered_finalizer" | sha256sum | awk '{ print $1 }')
readonly validate_block_hash
[[ "$validate_block_hash" = "$expected_validate_block_sha256" ]]
[[ "$(grep -Fxc '        --adapter caddyfile >/dev/null' "$rendered_finalizer")" -eq 1 ]]
[[ "$(grep -Fxc '        --adapter caddyfile' "$rendered_finalizer")" -eq 0 ]]

grep -Fq 'remote_%s_safe_content_begin=true' "$runner"
grep -Fq 'remote_%s_safe_content_end=true' "$runner"
grep -Fq 'remote_%s_content_secured=emitted' "$runner"
grep -Fq 'remote_%s_content_secured=protected_retention' "$runner"
grep -Fq 'remote_%s_protected_path=%s' "$runner"
grep -Fq 'remote_%s_protected_metadata=%s' "$runner"
grep -Fq 'remote_%s_protected_sha256=%s' "$runner"
grep -Fq 'retain_work_directory=true' "$runner"
grep -Fq 'workstation_evidence_retained=true' "$runner"
metadata_line=$(grep -n -m1 'remote_stdout_classification=%s' "$runner" | cut -d: -f1)
content_line=$(grep -n -m1 'emit_safe_content stdout' "$runner" | cut -d: -f1)
readonly metadata_line content_line
[[ "$metadata_line" -lt "$content_line" ]]

printf 'action_17s_b_false_positive_regression=true\n'
printf 'action_17s_b_false_negative_regression=true\n'
printf 'action_17s_b_node_b_rollback_stderr_regression_complete=true\n'
