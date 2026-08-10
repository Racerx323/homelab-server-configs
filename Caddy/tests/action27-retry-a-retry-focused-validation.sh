#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry_a_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly immutable_outer=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-outer.sh
readonly corrected_diagnostic=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-retry.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-certificate-identity-action27-retry-a-retry-outer.sh
readonly regression=$test_directory/action27-retry-a-retry-certificate-extraction-regression.sh
readonly focused=$test_directory/action27-retry-a-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/certificate-identity-action27-retry-a-retry.yaml
readonly immutable_outer_sha256=2eee3224eb68721592381f1c74e83a383c36ffb36eebe65b7635275cda9b6d17
readonly corrected_diagnostic_sha256=9cf305773633ab88e6b8f517879594bbf00466f63509d89d7431efe8a019ac2e
readonly outer_sha256=58a7aed3b6e290b31601b5ee0ecd9701090ce0efd5097441f34d5fe6af6fbc71
readonly regression_sha256=8de2dae492809a8b19218539d20d528f7ea1f9e51aa8f07fdc15b2f32816d496
readonly manifest_sha256=ca05cf3df031d46905ba52cf438da655fc31101ce57a07bd7c24a686c09a4daa

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_retry_a_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_a_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_a_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27_retry_a_retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'inside_certificate = 1' "$corrected_diagnostic" || return 1
    grep -Fq 'inside_certificate = 0' "$corrected_diagnostic" || return 1
    grep -Fq 'production-inter-certificate' "$regression" || return 1
    grep -Fq 'malformed-production-inter-certificate' "$regression" || return 1
    grep -Fq 'predecessor_corruption_reproduced=true' "$regression" || return 1
    grep -Fq 'unterminated_block_rejected=true' "$regression" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$corrected_diagnostic" "$outer" "$regression"; then
        return 1
    fi
}
outer_gate_contract() {
    local action27_retry_a_retry_focused_gate_file
    local action27_retry_a_retry_focused_gate_status=0

    action27_retry_a_retry_focused_gate_file=$(mktemp /tmp/caddy-action27-retry-a-retry-gates.XXXXXX)
    /bin/bash "$outer" --expected-local-gates >"$action27_retry_a_retry_focused_gate_file" ||
        action27_retry_a_retry_focused_gate_status=1
    [[ "$(wc -l <"$action27_retry_a_retry_focused_gate_file")" -eq 13 ]] ||
        action27_retry_a_retry_focused_gate_status=1
    [[ "$(LC_ALL=C sort -u "$action27_retry_a_retry_focused_gate_file" | wc -l)" -eq 13 ]] ||
        action27_retry_a_retry_focused_gate_status=1
    rm -f -- "$action27_retry_a_retry_focused_gate_file"
    return "$action27_retry_a_retry_focused_gate_status"
}

record_check immutable_outer_hash test "$(file_hash "$immutable_outer")" = "$immutable_outer_sha256"
record_check corrected_diagnostic_hash test "$(file_hash "$corrected_diagnostic")" = \
    "$corrected_diagnostic_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 13
record_check correction_check_count test \
    "$(/bin/bash "$corrected_diagnostic" --expected-checks | wc -l)" -eq 6
record_check preserved_diagnostic_check_count test \
    "$(/bin/bash "$corrected_diagnostic" --expected-diagnostic-checks | wc -l)" -eq 46
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh" \
    --self-test
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$corrected_diagnostic" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy outer_gate_contract
for action27_retry_a_retry_focused_entrypoint in \
    "$corrected_diagnostic" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_retry_a_retry_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_retry_a_retry_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
