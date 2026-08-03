#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-dual-node-reverse-sync-readiness-action18a-retry.sh"
readonly historical_inspector="$caddy_root/scripts/inspect-reverse-sync-readiness-action18a.sh"
readonly historical_runner="$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh"
readonly historical_regression="$test_directory/action18a-dual-node-reverse-sync-readiness-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly derivation_sha256=e7228a792d476ea82b8863ac7f01e786ead9e28f23d0e0430f660794aa8c3ba9
readonly historical_inspector_sha256=209eadc6ff077e829c0b5fc2f3c867728b9ad279372e663cb9f6eebf09a45673
readonly historical_runner_sha256=6979f14c06c51a5f7eee5708cc5b58946aebbc065e2ab46c326946e2e661d832
readonly historical_regression_sha256=fd75ae21a34f1d1fcea0c0a4350795f896560ede6caf0de22d13dcb737ba5fc8
readonly rendered_inspector_sha256=eb57a551c7c86ddfc347ca35b6d5d2a90488911d77a002c1d92ad1b7898fd1c3
readonly rendered_runner_sha256=48dc78f8baf7528dbf204c46d2c1c63c18f287815dafcb6ac695c3551f182849

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_hash() {
    local hash_label=$1
    local hash_path=$2
    local expected_hash=$3

    if [[ "$(file_hash "$hash_path")" != "$expected_hash" ]]; then
        printf 'action_18a_retry_regression_assertion_%s=false\n' "$hash_label" >&2
        return 1
    fi
    printf 'action_18a_retry_regression_assertion_%s=true\n' "$hash_label"
}

require_hash derivation_hash_exact "$derivation" "$derivation_sha256"
require_hash historical_inspector_immutable "$historical_inspector" \
    "$historical_inspector_sha256"
require_hash historical_runner_immutable "$historical_runner" \
    "$historical_runner_sha256"
require_hash historical_regression_immutable "$historical_regression" \
    "$historical_regression_sha256"

work_directory=$(mktemp -d /tmp/caddy-action18a-retry-regression.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

"$derivation" --output-directory "$work_directory" >/dev/null
readonly inspector="$work_directory/inspect-reverse-sync-readiness-action18a-retry.sh"
readonly runner="$work_directory/run-dual-node-reverse-sync-readiness-action18a-retry.sh"
require_hash rendered_inspector_hash_exact "$inspector" "$rendered_inspector_sha256"
require_hash rendered_runner_hash_exact "$runner" "$rendered_runner_sha256"

bash -n "$derivation" "$inspector" "$runner"
"$collision_checker" "$derivation" "$inspector" "$runner" >/dev/null
"$derivation" --self-test >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --source-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq 'readonly action_prefix=action_18a_retry' "$inspector"
grep -Fq 'readonly finalizer_v2_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d' \
    "$inspector"
grep -Fq '! -name .complete.pending ! -name .finalize-request -print0' "$inspector"
# Literal production-source contracts; expansion is intentionally suppressed.
# shellcheck disable=SC2016
grep -Fq 'observed_payload_sha256=$(payload_digest "$release")' "$inspector"
# shellcheck disable=SC2016
grep -Fq 'observed_manifest_sha256=$(hash_or_absent "$release/manifest.sha256")' \
    "$inspector"
# shellcheck disable=SC2016
grep -Fq 'observed_receiver_v2_sha256=$(hash_or_absent "$receiver_v2")' "$inspector"
# shellcheck disable=SC2016
grep -Fq 'observed_finalizer_v2_sha256=$(hash_or_absent "$finalizer_v2")' "$inspector"
grep -Fq 'record_command observed_payload_sha256_format' "$inspector"
grep -Fq 'record_command observed_manifest_sha256_format' "$inspector"
grep -Fq 'record_command observed_receiver_v2_sha256_format' "$inspector"
grep -Fq 'record_command observed_finalizer_v2_sha256_format' "$inspector"
grep -Fq 'for ancestry_field in revision parent_revision observed_payload_sha256 observed_manifest_sha256; do' \
    "$runner"
grep -Fq 'value_observed_payload_sha256=invalid' "$runner"

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$inspector"; then
    printf 'Action 18a retry inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' "$inspector"; then
    printf 'Action 18a retry inspector contains a peer-transfer command.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*ssh[[:space:]]+(-[46][[:space:]]+)?[^-G]' "$inspector"; then
    printf 'Action 18a retry inspector contains a connecting SSH command.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' "$inspector"; then
    printf 'Action 18a retry inspector contains a persistent write command.\n' >&2
    exit 1
fi

payload_function=$(sed -n '/^payload_digest() {$/,/^}$/p' "$inspector")
readonly payload_function
[[ -n "$payload_function" ]]
payload_fixture="$work_directory/payload"
mkdir "$payload_fixture"
printf 'payload\n' >"$payload_fixture/content"
baseline_digest=$(bash -c "$payload_function"$'\n''payload_digest "$1"' _ "$payload_fixture")
readonly baseline_digest
for marker_name in .complete .complete.pending .finalize-request; do
    printf 'receiver control\n' >"$payload_fixture/$marker_name"
done
marker_digest=$(bash -c "$payload_function"$'\n''payload_digest "$1"' _ "$payload_fixture")
readonly marker_digest
[[ "$marker_digest" == "$baseline_digest" ]]
printf 'changed payload\n' >"$payload_fixture/content"
changed_digest=$(bash -c "$payload_function"$'\n''payload_digest "$1"' _ "$payload_fixture")
readonly changed_digest
[[ "$changed_digest" != "$baseline_digest" ]]

printf 'action_18a_retry_regression_false_positive_rejected=true\n'
printf 'action_18a_retry_regression_false_negative_rejected=true\n'
printf 'action_18a_retry_dual_node_reverse_sync_readiness_regression_complete=true\n'
