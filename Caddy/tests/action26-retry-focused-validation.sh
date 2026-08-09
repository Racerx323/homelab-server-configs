#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly source_core=$caddy_root/scripts/run-workstation-caddy-protocols-action26.sh
readonly adapter=$caddy_root/scripts/run-workstation-caddy-protocols-action26-retry.sh
readonly validator=$caddy_root/scripts/run-workstation-caddy-protocols-action26-outer.sh
readonly accepted_ipv6=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-retry-outer.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-protocols-action26-retry-outer.sh
readonly regression=$test_directory/action26-retry-protocol-negotiation-regression.sh
readonly focused=$test_directory/action26-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-validation-action26-retry.yaml
readonly source_sha256=f72ceb374f4a8c07f820dc720266458af6f2ae70b4287f84e778f8387b08c046
readonly adapter_sha256=f167e5a8d735025e46a3f4cc213d62fc603358b004c13f9ecee364439f8fcd51
readonly validator_sha256=58edc2c10115dcd2b74e9b1b65e4afda7eaab3d6801301a698991d65ced943fc
readonly accepted_ipv6_sha256=b2f313b4713c9af2c668d21130642838522d6e921fb959387d93ab50191f0270
readonly outer_sha256=8458f79c24c56f70ab39cd6ad80d99519821227adca272da5f1a618a8a1b0a15
readonly regression_sha256=2ae39beaaa08a4c135d7f7eba025185cee0b94f79c787023a1c462b36f73cd4d
readonly manifest_sha256=e081d422816ca4cbad7607395ec16375e191bd0536f83a8fab1ccc22b21dec4c

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26_retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'generated_sha256: 683da97c69ed92a31de0adc53c13ee300976b9258038ff3003155bee4c1b6091' \
        "$manifest" || return 1
    grep -Fq 'exact_probe_count: 6' "$manifest" || return 1
    grep -Fq 'immutable_failed_predecessor: 26' "$manifest" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$adapter" "$outer" "$regression"
}

record_check source_hash test "$(file_hash "$source_core")" = "$source_sha256"
record_check adapter_hash test "$(file_hash "$adapter")" = "$adapter_sha256"
record_check validator_hash test "$(file_hash "$validator")" = "$validator_sha256"
record_check accepted_ipv6_hash test "$(file_hash "$accepted_ipv6")" = "$accepted_ipv6_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$adapter" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$adapter" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    export CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN=true
fi
record_check outer_self_test env \
    CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN="${CADDY_ACTION26_CONTAINER_NO_GO_TOOLCHAIN:-false}" \
    /bin/bash "$outer" --self-test
record_check core_check_count test "$(/bin/bash "$source_core" --expected-checks | wc -l)" -eq 59
record_check adapter_check_count test "$(/bin/bash "$adapter" --expected-checks | wc -l)" -eq 7
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$adapter" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
for action26_retry_entrypoint in "$adapter" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26_retry_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26_retry_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
