#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_a_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly immutable_retry_outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry-outer.sh
readonly diagnostic=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-outer.sh
readonly regression=$test_directory/action27-retry-a-certificate-identity-regression.sh
readonly focused=$test_directory/action27-retry-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/certificate-identity-action27-retry-a.yaml
readonly immutable_retry_outer_sha256=07db480bf77f640c14450b19b73fecae494208e989323e203676cb8813d24c30
readonly diagnostic_sha256=4fc72118c8ede79676e6e673951b0321d8add15355e62221d018ffac1b84b8b9
readonly outer_sha256=2eee3224eb68721592381f1c74e83a383c36ffb36eebe65b7635275cda9b6d17
readonly regression_sha256=ee4a67c35e3af2ee05b7d52b3b0692334d9050e7af125587bb67b94611812ffa
readonly manifest_sha256=1021b2eeb9e2606aba542e99d9260519766e4566c6485168aa3f1fc1ebf9814a

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_retry_a_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_a_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27_retry_a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    # These patterns intentionally match literal diagnostic source.
    # shellcheck disable=SC2016
    grep -Fq -- '-outform DER -out "$action27_retry_a_der"' "$diagnostic" || return 1
    # shellcheck disable=SC2016
    grep -Fq -- 'pkey -pubin -in "$action27_retry_a_pubkey" -outform DER' \
        "$diagnostic" || return 1
    grep -Fq 'identity_der_consistent' "$diagnostic" || return 1
    grep -Fq 'identity_spki_consistent' "$diagnostic" || return 1
    grep -Fq 'cross_family_drift_rejected=true' "$regression" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$diagnostic" "$outer" "$regression"; then
        return 1
    fi
}

record_check immutable_retry_outer_hash test "$(file_hash "$immutable_retry_outer")" = \
    "$immutable_retry_outer_sha256"
record_check diagnostic_hash test "$(file_hash "$diagnostic")" = "$diagnostic_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$diagnostic" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$diagnostic" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$diagnostic" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 13
record_check diagnostic_check_count test "$(/bin/bash "$diagnostic" --expected-checks | wc -l)" -eq 46
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$diagnostic" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$diagnostic" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$diagnostic" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
for action27_retry_a_focused_entrypoint in "$diagnostic" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_retry_a_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_retry_a_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
