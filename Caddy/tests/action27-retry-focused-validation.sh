#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly immutable_core=$caddy_root/scripts/run-workstation-caddy-tls-action27.sh
readonly immutable_outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-outer.sh
readonly retry_core=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry.sh
readonly retry_outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry-outer.sh
readonly regression=$test_directory/action27-retry-tls-trust-regression.sh
readonly focused=$test_directory/action27-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/tls-validation-action27-retry.yaml
readonly immutable_core_sha256=b39eeff2a60beefd4b9e0528a54dda63e6a0f150881b01183a2fc0066efdbfad
readonly immutable_outer_sha256=cf3ac9d1bc4c5b21e369d38ed273cbdcfc3c95a0c31e55a93c0b172b2f915cbf
readonly retry_core_sha256=49597b0cbf2bbc5851f956a0015c0f3ab3468c04695f707a11dd8a1ee5d99a9c
readonly retry_outer_sha256=07db480bf77f640c14450b19b73fecae494208e989323e203676cb8813d24c30
readonly regression_sha256=4d1276b3e43c2855311a02bab60554e1755fb1529ee2671cedb6b5d5c3889402
readonly manifest_sha256=1cf8b827e4a0ca4ea92297c705b434604dd19f75764bcef6576c9dd273060001

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27_retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'normalization_scope=exact_success_verification_line_whitespace_only' \
        "$retry_core" || return 1
    grep -Fq "Verify return code: 0 (ok)   " "$regression" || return 1
    grep -Fq "Verify return code: %s (unable to get local issuer certificate)" \
        "$regression" || return 1
    grep -Fq 'CADDY_ACTION27_RETRY_FAKE_VERIFY_CODE=20' "$regression" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$retry_core" "$retry_outer" "$regression"; then
        return 1
    fi
}

record_check immutable_core_hash test "$(file_hash "$immutable_core")" = "$immutable_core_sha256"
record_check immutable_outer_hash test "$(file_hash "$immutable_outer")" = "$immutable_outer_sha256"
record_check retry_core_hash test "$(file_hash "$retry_core")" = "$retry_core_sha256"
record_check retry_outer_hash test "$(file_hash "$retry_outer")" = "$retry_outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$retry_core" "$retry_outer" "$regression" "$0"
record_check shellcheck shellcheck "$retry_core" "$retry_outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$retry_core" "$retry_outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$retry_outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$retry_outer" --expected-local-gates | wc -l)" -eq 13
record_check retry_check_count test "$(/bin/bash "$retry_core" --expected-checks | wc -l)" -eq 5
record_check preserved_core_check_count test \
    "$(/bin/bash "$retry_core" --expected-core-checks | wc -l)" -eq 61
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$retry_core" "$retry_outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$retry_core" "$retry_outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$retry_core" "$retry_outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$retry_outer"
for action27_retry_focused_entrypoint in "$retry_core" "$retry_outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_retry_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_retry_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
