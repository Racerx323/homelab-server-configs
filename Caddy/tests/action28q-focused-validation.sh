#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_focused
readonly transaction_sha256=dac891ac6e959d5e4f045628072cb38437e4c5698234890e71ae062e614d6363
readonly outer_sha256=90e1d7000b0fc029f538030d3f65716a4e490872185af8790fe5fcacf14df608
readonly regression_sha256=54db732c213ca5406d918ae3a60fea94bfa316f501332854236c24719ed2a41c
readonly candidate_fixture_sha256=9e3dbf9760733f0ddb46ba51996cfdd9ad9af723d561ee2376de8c7c7d6ee3aa
readonly node_a_fragment_fixture_sha256=d54bab23a2fb564d25faa134f65eaa67500c717dfb77fb912fc5526f1f71169a
readonly node_b_fragment_fixture_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly manifest_sha256=49f6f81482728ad097b028915127a48f428c7d5b60ae47a290df25d0d7df3d87
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/acquire-node-a-coupled-vips-action28q.sh
readonly outer=$caddy_root/scripts/run-node-a-coupled-vip-acquisition-action28q-outer.sh
readonly regression=$test_directory/action28q-node-a-coupled-vip-acquisition-regression.sh
readonly focused=$test_directory/action28q-focused-validation.sh
readonly candidate_fixture=$test_directory/fixtures/action28q-node-a-coupled-main.conf
readonly node_a_fragment_fixture=$test_directory/fixtures/action28q-node-a-caddy-fragment.conf
readonly node_b_fragment_fixture=$test_directory/fixtures/action28q-node-b-caddy-fragment.conf
readonly manifest=$caddy_root/manifests/caddy-node-a-coupled-vip-acquisition-action28q.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28q_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28q_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28q_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28q' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
}

check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check candidate_fixture_hash test "$(file_hash "$candidate_fixture")" = "$candidate_fixture_sha256"
check node_a_fragment_fixture_hash test \
    "$(file_hash "$node_a_fragment_fixture")" = "$node_a_fragment_fixture_sha256"
check node_b_fragment_fixture_hash test \
    "$(file_hash "$node_b_fragment_fixture")" = "$node_b_fragment_fixture_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check syntax /bin/bash -n "$transaction" "$outer" "$regression" "$focused"
check shellcheck shellcheck "$transaction" "$outer" "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check yaml yaml_check
check regression /bin/bash "$regression"
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$transaction" "$outer" "$regression" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" \
    --check "$transaction" "$outer" "$regression" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" \
    --check "$transaction" "$outer" "$regression" "$focused"
check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
check ssh_evidence_policy /bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
check outer_local_labels /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
check transaction_self_test "$transaction" --self-test
check outer_self_test "$outer" --self-test
check manifest_action grep -Fqx 'action: 28q' "$manifest"
check manifest_definition grep -Fqx '  definition_only: true' "$manifest"
check manifest_execution_false grep -Fqx '  execution: false' "$manifest"
check plan_gate grep -Fq "Action 28q once using outer SHA-256 \`$outer_sha256\`" "$plan"
for action28q_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28q_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28q_focused_entrypoint"
    check "index_mode_$(basename "$action28q_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28q_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
