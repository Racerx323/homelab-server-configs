#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_d_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly runner=$caddy_root/scripts/run-action28e-c-historical-identity-consumer-correction.sh
readonly regression=$test_directory/action28e-d-historical-identity-consumer-correction-regression.sh
readonly focused=$test_directory/action28e-d-focused-validation.sh
readonly registry=$caddy_root/manifests/protocol-v2-historical-identities-action28e-d.tsv
readonly manifest=$caddy_root/manifests/protocol-v2-historical-identity-consumer-correction-action28e-d.yaml
readonly action28e_c_outer=$caddy_root/scripts/run-dual-node-historical-release-manifest-action28e-c-outer.sh
readonly runner_sha256=a600e6ca0b8b9536dae30cbf48b725eaac7582c3c5b8fb9326d90a81384a2726
readonly regression_sha256=01dafce8777b56278fec5ecb43a7ec14b0a395156891ecddde424854883b212a
readonly registry_sha256=9a3abce23f57bb17b4ff1415b28846c9792229f53d99a0b73a3a9a81033886f9
readonly manifest_sha256=b9fd3e9e35635d6f53a27b3820cc542e85ae10769deec6a9e1d74fe7bc708e5b
readonly action28e_c_outer_sha256=edc88d827a9bdd60a62832d452ac5508c0a1ae2f35f14740bdd5c4bf7d5e8230

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28e_d_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_d_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_d_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28e-d' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  runner_sha256: $runner_sha256" "$manifest" || return 1
    grep -Fqx "  regression_sha256: $regression_sha256" "$manifest"
}

record_check runner_hash test "$(file_hash "$runner")" = "$runner_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check registry_hash test "$(file_hash "$registry")" = "$registry_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28e_c_immutable test \
    "$(file_hash "$action28e_c_outer")" = "$action28e_c_outer_sha256"
record_check syntax /bin/bash -n "$runner" "$regression" "$focused"
record_check shellcheck shellcheck "$runner" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$runner" "$regression" "$focused"
record_check yaml yaml_check
record_check runner_self_test /bin/bash "$runner" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$runner" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$runner" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$runner" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action28e_d_focused_entrypoint in "$runner" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28e_d_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28e_d_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
