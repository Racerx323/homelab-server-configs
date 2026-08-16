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

wrong_lifecycle=$fixture_root/wrong-lifecycle.tsv
awk -F '\t' 'BEGIN { OFS = FS }
    NR == 2 { $2 = "historical-preserved"; $3 = "historical-opt-in" }
    { print }
' "$registry" >"$wrong_lifecycle"
if CADDY_TEST_LIFECYCLE_REGISTRY=$wrong_lifecycle /bin/bash "$policy" --check >/dev/null 2>&1; then
    printf '%s_noncurrent_lifecycle_rejected=false\n' "$prefix" >&2
    exit 1
fi

action_current=$fixture_root/action-current.tsv
awk -F '\t' 'BEGIN { OFS = FS }
    NR == 2 { $4 = "action999-terminal-archive" }
    { print }
' "$registry" >"$action_current"
if CADDY_TEST_LIFECYCLE_REGISTRY=$action_current /bin/bash "$policy" --check >/dev/null 2>&1; then
    printf '%s_action_current_rejected=false\n' "$prefix" >&2
    exit 1
fi

printf '%s_missing_entry_rejected=true\n' "$prefix"
printf '%s_noncurrent_lifecycle_rejected=true\n' "$prefix"
printf '%s_action_current_rejected=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
