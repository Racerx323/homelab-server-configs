#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly accepted=$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-action17u.sh
readonly candidate=$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh
readonly accepted_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly candidate_sha256=fcff15db5b4ea971846a798028f40d2dce86db9cc331825d046dd5321d5f33bd

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

[[ -f "$accepted" && ! -L "$accepted" ]]
[[ -f "$candidate" && ! -L "$candidate" ]]
[[ "$(file_hash "$accepted")" = "$accepted_sha256" ]]
[[ "$(file_hash "$candidate")" = "$candidate_sha256" ]]
/bin/bash -n "$accepted" "$candidate"

grep -Fq 'validate_caddy_configuration()' "$accepted"
# The following patterns are exact source literals, not expressions to expand.
# shellcheck disable=SC2016
grep -Fq '2>"$validation_error"' "$accepted"
# shellcheck disable=SC2016
grep -Fq 'cat -- "$validation_error" >&2 || :' "$accepted"
grep -Fq 'validate_caddy_configuration()' "$candidate"
# shellcheck disable=SC2016
grep -Fq '2>"$validation_error"' "$candidate"
# shellcheck disable=SC2016
grep -Fq 'cat -- "$validation_error" >&2 || :' "$candidate"
grep -Fq 'signal_reconciliation()' "$candidate"
# shellcheck disable=SC2016
grep -Fq 'touch -- "$finalizer_trigger_path"' "$candidate"
# shellcheck disable=SC2016
grep -Fq 'signal_reconciliation "$reconcile_trigger" caddy-sync:caddy-sync:640' \
    "$candidate"

trigger_output=$("$candidate" --reconciliation-trigger-self-test)
for trigger_label in created reused symlink_rejected self_test_complete; do
    grep -Fxq \
        "caddy_sync_finalize_v2_reconciliation_trigger_${trigger_label}=true" \
        <<<"$trigger_output"
done

printf 'action_28ac_finalizer_accepted_source_exact=true\n'
printf 'action_28ac_finalizer_stderr_safe_contract_retained=true\n'
printf 'action_28ac_finalizer_trigger_contract_added=true\n'
printf 'action_28ac_finalizer_trigger_regression_complete=true\n'
