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
readonly historical_transaction="$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s.sh"
readonly historical_sha256=325a8fff552646073768a619f5ee793423494d7258c8503624f1b44be0a0e5d8
readonly corrected_transaction="$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s-retry.sh"
readonly corrected_transaction_sha256=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0
readonly corrected_runner="$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry.sh"
readonly action17s_a_inspector="$caddy_root/scripts/inspect-node-b-action17s-rollback-output-action17s-a.sh"
readonly action17s_a_runner="$caddy_root/scripts/run-node-b-action17s-rollback-output-action17s-a.sh"
readonly action17t_installer="$caddy_root/scripts/install-node-b-stdout-safe-finalizer-action17t.sh"
readonly action17t_runner="$caddy_root/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh"
readonly action17s_b_runner="$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh"
readonly action17u_runner="$caddy_root/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_same_run_evidence_tokens() {
    local evidence_source=$1
    local evidence_prefix=$2

    grep -Fq "${evidence_prefix}_bytes" "$evidence_source"
    grep -Fq "${evidence_prefix}_lines" "$evidence_source"
    grep -Fq "${evidence_prefix}_sha256" "$evidence_source"
    grep -Fq "${evidence_prefix}_classification" "$evidence_source"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'transaction_output_evidence_policy_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ -f "$historical_transaction" && ! -L "$historical_transaction" ]]
[[ "$(file_hash "$historical_transaction")" = "$historical_sha256" ]]
grep -Fq 'finalizer_stdout_empty' "$historical_transaction"
if require_same_run_evidence_tokens \
    "$historical_transaction" action_17s_value_finalizer_stdout; then
    printf 'Historical Action 17s unexpectedly changed its evidence contract.\n' >&2
    exit 1
fi

[[ -f "$corrected_transaction" && ! -L "$corrected_transaction" ]]
[[ "$(file_hash "$corrected_transaction")" = "$corrected_transaction_sha256" ]]
[[ -f "$corrected_runner" && ! -L "$corrected_runner" ]]
for corrected_evidence_token in bytes lines sha256 classification; do
    grep -Fq "%s_value_%s_${corrected_evidence_token}=%s" \
        "$corrected_transaction"
    grep -Fq "%s_remote_%s_${corrected_evidence_token}=%s" \
        "$corrected_runner"
done
# The dollar-prefixed tokens are intentionally matched as literal source.
# shellcheck disable=SC2016
grep -Fq 'emit_stream_evidence finalizer_stdout "$finalizer_output"' \
    "$corrected_transaction"
# shellcheck disable=SC2016
grep -Fq 'emit_stream_evidence finalizer_stderr "$finalizer_error"' \
    "$corrected_transaction"
# shellcheck disable=SC2016
grep -Fq 'emit_stream_evidence stdout "$remote_output"' "$corrected_runner"
# shellcheck disable=SC2016
grep -Fq 'emit_stream_evidence stderr "$remote_error"' "$corrected_runner"

[[ -f "$action17s_a_inspector" && ! -L "$action17s_a_inspector" ]]
[[ -f "$action17s_a_runner" && ! -L "$action17s_a_runner" ]]
grep -Fq \
    '%s_value_stdout_source_classification=unsuppressed_caddy_validate_success_path' \
    "$action17s_a_inspector"
grep -Fq '%s_prior_stdout_bytes_recoverable=false' \
    "$action17s_a_inspector"
grep -Fq '%s_prior_stdout_lines_recoverable=false' \
    "$action17s_a_inspector"
grep -Fq '%s_prior_stdout_sha256_recoverable=false' \
    "$action17s_a_inspector"
require_same_run_evidence_tokens "$action17s_a_runner" remote_stdout
require_same_run_evidence_tokens "$action17s_a_runner" remote_stderr

[[ -f "$action17t_installer" && ! -L "$action17t_installer" ]]
[[ -f "$action17t_runner" && ! -L "$action17t_runner" ]]
for evidence_token in bytes lines sha256 classification; do
    grep -Fq "%s_value_%s_${evidence_token}=%s" "$action17t_installer"
    grep -Fq "%s_remote_%s_${evidence_token}=%s" "$action17t_runner"
done
grep -Fq "emit_stream_evidence stdout \"\$remote_output\"" "$action17t_runner"
grep -Fq "emit_stream_evidence stderr \"\$remote_error\"" "$action17t_runner"
grep -Fq \
    "validate_success \"\$remote_error\" \"\$remote_output\"" \
    "$action17t_runner"

# The executed corrected Action 17s retry is immutable historical evidence: it
# captured safe content but emitted only metadata. New actions must secure safe
# content before cleanup. Action 17s-b demonstrates and enforces that boundary.
[[ -f "$action17s_b_runner" && ! -L "$action17s_b_runner" ]]
grep -Fq 'remote_%s_safe_content_begin=true' "$action17s_b_runner"
grep -Fq 'remote_%s_safe_content_end=true' "$action17s_b_runner"
grep -Fq 'remote_%s_content_secured=emitted' "$action17s_b_runner"
grep -Fq 'remote_%s_content_secured=protected_retention' "$action17s_b_runner"
grep -Fq 'remote_%s_protected_metadata=%s' "$action17s_b_runner"
grep -Fq 'remote_%s_protected_sha256=%s' "$action17s_b_runner"
grep -Fq 'retain_work_directory=true' "$action17s_b_runner"
metadata_line=$(grep -n -m1 'remote_stdout_classification=%s' \
    "$action17s_b_runner" | cut -d: -f1)
content_line=$(grep -n -m1 'emit_safe_content stdout' \
    "$action17s_b_runner" | cut -d: -f1)
readonly metadata_line content_line
[[ "$metadata_line" -lt "$content_line" ]]

[[ -f "$action17u_runner" && ! -L "$action17u_runner" ]]
grep -Fq 'remote_%s_safe_content_begin=true' "$action17u_runner"
grep -Fq 'remote_%s_safe_content_end=true' "$action17u_runner"
grep -Fq 'remote_%s_content_secured=emitted' "$action17u_runner"
grep -Fq 'remote_%s_content_secured=protected_retention' "$action17u_runner"
grep -Fq 'remote_%s_protected_metadata=%s' "$action17u_runner"
grep -Fq 'remote_%s_protected_sha256=%s' "$action17u_runner"
grep -Fq 'retain_work_directory=true' "$action17u_runner"

stdout_metadata_line=$(
    grep -n -m1 "remote_stdout_bytes=%s" "$action17s_a_runner" | cut -d: -f1
)
stderr_metadata_line=$(
    grep -n -m1 "remote_stderr_bytes=%s" "$action17s_a_runner" | cut -d: -f1
)
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
acceptance_line=$(
    grep -n -m1 'if \[\[ "$stdout_classification"' \
        "$action17s_a_runner" | cut -d: -f1
)
readonly stdout_metadata_line stderr_metadata_line acceptance_line
[[ "$stdout_metadata_line" -lt "$acceptance_line" ]]
[[ "$stderr_metadata_line" -lt "$acceptance_line" ]]
grep -Fq '%s_remote_stderr_raw_emitted=false' "$action17s_a_runner"

grep -Fq 'A live transactional command whose stdout or stderr affects acceptance must' \
    "$caddy_root/../AGENTS.md"
grep -Fq 'capture both streams during that same execution.' \
    "$caddy_root/../AGENTS.md"
grep -Fq 'Metadata alone is not sufficient:' "$caddy_root/../AGENTS.md"
grep -Fq 'capture before its evidence outcome is secured' \
    "$caddy_root/../AGENTS.md"

printf 'historical_action_17s_stdout_evidence_exception_hash=%s\n' \
    "$historical_sha256"
printf 'historical_action_17s_retry_content_exception_hash=%s\n' \
    "$corrected_transaction_sha256"
printf 'transaction_output_evidence_policy_complete=true\n'
