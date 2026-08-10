#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry3_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly executed_retry2_outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry2-outer.sh
readonly successor=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry3.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-tls-action27-retry3-outer.sh
readonly regression=$test_directory/action27-retry3-tls-trust-regression.sh
readonly focused=$test_directory/action27-retry3-focused-validation.sh
readonly manifest=$caddy_root/manifests/tls-validation-action27-retry3.yaml
readonly executed_retry2_outer_sha256=2f183a44de5ccca561cacc1e274f8609d2b1e69187410b3fbab033ce5b54cb01
readonly successor_sha256=5c1073f35ffc7966b01fd4d0ab1405e66f46627300730f17fce58a2eafac3b18
readonly outer_sha256=954c708830e3e695e329496830d7b3a53ca71d1d30521b9ac6d7b0fe28f4de0d
readonly regression_sha256=d404678acf3621b719e4a98fab2fa61c910a24d8ab63ca4f2cc3f8f51c4779d5
readonly manifest_sha256=2498cb4bc6b114f0262b71791ee045f734ccded3e8dfdf2060ff598255d927a6

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action27_retry3_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry3_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry3_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 27_retry3' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'readonly inherited_url=https://proxy.local.theama.co/healthz' "$successor" || return 1
    grep -Fq 'readonly corrected_url=https://proxy.local.theama.co/' "$successor" || return 1
    grep -Fq 'status_200_rejected=true' "$regression" || return 1
    if grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$successor" "$outer" "$regression"; then
        return 1
    fi
}
outer_gate_contract() {
    local action27_retry3_focused_gate_file
    local action27_retry3_focused_gate_status=0

    action27_retry3_focused_gate_file=$(mktemp /tmp/caddy-action27-retry3-gates.XXXXXX)
    /bin/bash "$outer" --expected-local-gates >"$action27_retry3_focused_gate_file" ||
        action27_retry3_focused_gate_status=1
    [[ "$(wc -l <"$action27_retry3_focused_gate_file")" -eq 13 ]] ||
        action27_retry3_focused_gate_status=1
    [[ "$(LC_ALL=C sort -u "$action27_retry3_focused_gate_file" | wc -l)" -eq 13 ]] ||
        action27_retry3_focused_gate_status=1
    rm -f -- "$action27_retry3_focused_gate_file"
    return "$action27_retry3_focused_gate_status"
}

record_check executed_retry2_outer_hash test "$(file_hash "$executed_retry2_outer")" = \
    "$executed_retry2_outer_sha256"
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
record_check retry3_check_count test "$(/bin/bash "$successor" --expected-checks | wc -l)" -eq 7
record_check retry2_check_count test "$(/bin/bash "$successor" --expected-retry2-checks | wc -l)" -eq 10
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
for action27_retry3_focused_entrypoint in "$successor" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action27_retry3_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action27_retry3_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_tls_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
