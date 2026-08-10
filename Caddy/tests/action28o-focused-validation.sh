#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28o_focused
readonly transaction_sha256=8330588d34150d0ed4558ce2d8caf984e8bd73beb7065f760a25081619b42d19
readonly outer_sha256=39491118d59e9aad649d883b46638bcc793ec4205f09e13d3e2357f3d693be2f
readonly regression_sha256=fb0d26a860aa0ae185a4b9e1428197ef8108bb042fe886556b3b8a6d45545bb9
readonly manifest_sha256=11f37552abb0354bf763c97738f0f98dcca8754b3694c0ef316d1db7cdd9ed5b
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/restore-node-b-caddy-service-action28o.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-service-restoration-action28o-outer.sh
readonly regression=$test_directory/action28o-node-b-caddy-service-restoration-regression.sh
readonly focused=$test_directory/action28o-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-node-b-service-restoration-action28o.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

check() {
    local action28o_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28o_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28o_focused_label" >&2
    return 1
}
hash_exact() {
    local action28o_focused_expected=$1
    local action28o_focused_path=$2

    [[ "$(sha256sum -- "$action28o_focused_path" | awk '{ print $1 }')" = "$action28o_focused_expected" ]]
}

check transaction_hash hash_exact "$transaction_sha256" "$transaction"
check outer_hash hash_exact "$outer_sha256" "$outer"
check regression_hash hash_exact "$regression_sha256" "$regression"
check manifest_hash hash_exact "$manifest_sha256" "$manifest"
check syntax /bin/bash -n "$transaction" "$outer" "$regression" "$focused"
check shellcheck shellcheck "$transaction" "$outer" "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$transaction" "$outer" "$regression" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
check ssh_evidence_policy /bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
check transaction_self_test "$transaction" --self-test
check regression /bin/bash "$regression"
check manifest_action grep -Fqx 'action: 28o' "$manifest"
check manifest_definition grep -Fqx '  definition_only: true' "$manifest"
check manifest_execution_false grep -Fqx '  execution: false' "$manifest"
check manifest_reload_prohibited grep -Fqx '  keepalived_reload_or_restart: prohibited' "$manifest"
check plan_status grep -Fq 'Node B Caddy service-restoration Action 28o' "$plan"
for action28o_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28o_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28o_focused_entrypoint"
    if [[ -d "$repository_root/.git" ]]; then
        check "index_mode_$(basename "$action28o_focused_entrypoint" | tr '.-' '__')" \
            test "$(git -C "$repository_root" ls-files -s -- \
                "Caddy/${action28o_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
    fi
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
