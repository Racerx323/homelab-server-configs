#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry2_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly accepted_identity_outer=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-retry-outer.sh
readonly successor=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry2.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry2-outer.sh
readonly regression=$test_directory/action27-retry2-tls-trust-regression.sh
readonly focused=$test_directory/action27-retry2-focused-validation.sh
readonly manifest=$caddy_root/manifests/tls-validation-action27-retry2.yaml
readonly accepted_identity_outer_sha256=58a7aed3b6e290b31601b5ee0ecd9701090ce0efd5097441f34d5fe6af6fbc71
readonly successor_sha256=039dedbde868d795132b5b2ad538f7be2720ddf3c4dd53c2ea909e90f45b05e1
readonly outer_sha256=2f183a44de5ccca561cacc1e274f8609d2b1e69187410b3fbab033ce5b54cb01
readonly regression_sha256=049a49bca42711aaa2dfdda39295b721d380004bcf80664b4f68653c93e5d6c4
readonly manifest_sha256=97131960a7b49748fa01441fa74a21c2d0f08287712457b0635030d519d2af54

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_retry2_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry2_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry2_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27_retry2' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'canonical_leaf_der_sha256' "$successor" || return 1
    grep -Fq 'inside_certificate = 0' "$successor" || return 1
    grep -Fq 'production-inter-certificate' "$regression" || return 1
    grep -Fq 'wrong_der_rejected=true' "$regression" || return 1
    grep -Fq 'nonzero_verify_rejected=true' "$regression" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$successor" "$outer" "$regression"; then
        return 1
    fi
}
outer_gate_contract() {
    local action27_retry2_focused_gate_file
    local action27_retry2_focused_gate_status=0

    action27_retry2_focused_gate_file=$(mktemp /tmp/caddy-action27-retry2-gates.XXXXXX)
    /bin/bash "$outer" --expected-local-gates >"$action27_retry2_focused_gate_file" ||
        action27_retry2_focused_gate_status=1
    [[ "$(wc -l <"$action27_retry2_focused_gate_file")" -eq 13 ]] ||
        action27_retry2_focused_gate_status=1
    [[ "$(LC_ALL=C sort -u "$action27_retry2_focused_gate_file" | wc -l)" -eq 13 ]] ||
        action27_retry2_focused_gate_status=1
    rm -f -- "$action27_retry2_focused_gate_file"
    return "$action27_retry2_focused_gate_status"
}

record_check accepted_identity_outer_hash test "$(file_hash "$accepted_identity_outer")" = \
    "$accepted_identity_outer_sha256"
record_check successor_hash test "$(file_hash "$successor")" = "$successor_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$successor" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$successor" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$successor" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 13
record_check successor_check_count test "$(/bin/bash "$successor" --expected-checks | wc -l)" -eq 10
record_check preserved_core_check_count test \
    "$(/bin/bash "$successor" --expected-core-checks | wc -l)" -eq 61
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$successor" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh" \
    --self-test
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$successor" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$successor" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy outer_gate_contract
for action27_retry2_focused_entrypoint in "$successor" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_retry2_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_retry2_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
