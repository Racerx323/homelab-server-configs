#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=test_lifecycle_policy_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly policy=$test_directory/test-lifecycle-policy.sh
readonly registry=$test_directory/test-lifecycle.tsv
fixture_root=$(mktemp -d /tmp/caddy-test-lifecycle-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT INT TERM

/bin/bash "$policy" --check >/dev/null

missing=$fixture_root/missing.tsv
sed '2d' "$registry" >"$missing"
if CADDY_TEST_LIFECYCLE_REGISTRY=$missing /bin/bash "$policy" --check >/dev/null 2>&1; then
    printf '%s_missing_entry_rejected=false\n' "$prefix" >&2
    exit 1
fi

wrong_action=$fixture_root/wrong-action.tsv
awk -F '\t' 'BEGIN { OFS = FS }
    /^Caddy\/tests\/action/ && !changed { $2 = "production-current"; $3 = "current-focused"; changed = 1 }
    { print }
' "$registry" >"$wrong_action"
if CADDY_TEST_LIFECYCLE_REGISTRY=$wrong_action /bin/bash "$policy" --check >/dev/null 2>&1; then
    printf '%s_wrong_action_lifecycle_rejected=false\n' "$prefix" >&2
    exit 1
fi

printf '%s_missing_entry_rejected=true\n' "$prefix"
printf '%s_wrong_action_lifecycle_rejected=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
