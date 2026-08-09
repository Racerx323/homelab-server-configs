#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_24_retry_focused_validation
readonly retry_outer_sha256=daaa1904cab02dbf9a83aa6f8d4479582d6d571bc3fd008f4cd1393878fdc6f6
readonly regression_sha256=c0b6732426a8fdefd3ca2381133a036e7297c9004e6d07430846c8b3683d13b6
readonly manifest_sha256=aa8cb3759337fe8e6d8586b867d7f8066cff4d2d74dd068edac08963ae3329fa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly retry_outer=$caddy_root/scripts/run-dual-node-dns-record-families-action24-retry-outer.sh
readonly regression=$test_directory/action24-retry-dig-x-regression.sh
readonly focused=$test_directory/action24-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action24-retry-record-family-validation.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action24_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action24_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action24_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    grep -Fqx 'action: 24-retry' "$manifest" && grep -Fqx 'status: defined' "$manifest"
}

record_check retry_outer_hash test "$(file_hash "$retry_outer")" = "$retry_outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$retry_outer" "$regression" "$focused"
record_check shellcheck shellcheck "$retry_outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$retry_outer" "$regression" "$focused"
record_check yaml yaml_check
record_check retry_outer_self_test /bin/bash "$retry_outer" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$retry_outer" "$regression" "$focused"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$retry_outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$retry_outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$retry_outer"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$retry_outer"
record_check outer_gate_inventory_unique test \
    "$("$retry_outer" --expected-local-gates | wc -l)" -eq \
    "$("$retry_outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
for action24_retry_focused_entrypoint in "$retry_outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action24_retry_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action24_retry_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
