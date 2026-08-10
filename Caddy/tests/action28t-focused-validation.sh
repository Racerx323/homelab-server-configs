#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28t_focused
readonly transaction_sha256=3489759fec7b38fe0e3ee31f19810085bf1f8fbe363826102b6daf1a25e873db
readonly outer_sha256=9003aa54d8376206a64a2e4c745bbf783ba38a8f7980539bd8f3e3e2046ca2d6
readonly regression_sha256=2701659b25d3bd2cf35bb01c54a7b97991b47dc51f02b4a8a46ded09be7ddc73
readonly manifest_sha256=ed33f2c0e9a68e83a9cb4e2558e1d580df08c9468d91c6eb683bb8fd0ea8178a
readonly node_a_candidate_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_candidate_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly transaction=$caddy_root/scripts/transact-dual-node-protocol-compatible-coupling-action28t.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-compatible-coupling-action28t-outer.sh
readonly regression=$test_directory/action28t-sequential-dual-node-coupling-regression.sh
readonly focused=$test_directory/action28t-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-sequential-dual-node-coupling-action28t.yaml
readonly node_a_candidate=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_candidate=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28t_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28t_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28t_focused_label" >&2
    return 1
}
manifest_contract() {
    grep -Fqx 'action: 28t' "$manifest" || return 1
    grep -Fqx 'mode: bounded_transactional_sequential_dual_node' "$manifest" || return 1
    grep -Fqx 'execution_authorized: false' "$manifest" || return 1
    grep -Fqx '    maximum_seconds: 45' "$manifest" || return 1
    grep -Fqx '    - node_a' "$manifest" || return 1
    grep -Fqx '    - node_b' "$manifest"
}

check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check node_a_candidate_hash test "$(file_hash "$node_a_candidate")" = "$node_a_candidate_sha256"
check node_b_candidate_hash test "$(file_hash "$node_b_candidate")" = "$node_b_candidate_sha256"
check manifest_contract manifest_contract
check syntax /bin/bash -n "$transaction" "$outer" "$regression" "$focused"
check shellcheck shellcheck "$transaction" "$outer" "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check transaction_self_test "$transaction" --self-test
check outer_self_test "$outer" --self-test
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
check outer_labels /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
check plan_gate grep -Fq 'Sequential dual-node protocol-compatible coupling Action 28t' "$plan"
for action28t_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28t_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28t_focused_entrypoint"
    check "index_mode_$(basename "$action28t_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$workspace_root/homelab-server-configs" ls-files -s -- \
            "Caddy/${action28t_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
