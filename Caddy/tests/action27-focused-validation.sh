#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-caddy-tls-action27.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-outer.sh
readonly regression=$test_directory/action27-tls-trust-regression.sh
readonly focused=$test_directory/action27-focused-validation.sh
readonly manifest=$caddy_root/manifests/tls-validation-action27.yaml
readonly core_sha256=b39eeff2a60beefd4b9e0528a54dda63e6a0f150881b01183a2fc0066efdbfad
readonly outer_sha256=cf3ac9d1bc4c5b21e369d38ed273cbdcfc3c95a0c31e55a93c0b172b2f915cbf
readonly regression_sha256=487b2d7c89650d96d280f8f52de4c7dd1c5a51edad1573293947878940730895
readonly manifest_sha256=ddbea60f456ca532549669c024f9fcaf3dce2ac6e68be1ea3cafcc7f6b1c56e9

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    # This pattern intentionally matches literal runner source.
    # shellcheck disable=SC2016
    grep -Fq -- '-verify_hostname "$hostname" -verify_return_error -CApath /etc/ssl/certs' \
        "$core" || return 1
    grep -Fq -- '-tls1_2 TLSv1.2' "$core" || return 1
    grep -Fq -- '-tls1_3 TLSv1.3' "$core" || return 1
    grep -Fq 'ssl_verify_result=%{ssl_verify_result}' "$core" || return 1
    grep -Fq 'num_certs=%{num_certs}' "$core" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$core" "$outer" "$regression"; then
        return 1
    fi
}

record_check core_hash test "$(file_hash "$core")" = "$core_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$core" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$core" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 12
record_check core_check_count test "$(/bin/bash "$core" --expected-checks | wc -l)" -eq 61
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$core" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
for action27_focused_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
