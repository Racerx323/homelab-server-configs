#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28n_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/relinquish-node-b-caddy-vrrp-action28n.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-vrrp-relinquish-action28n-outer.sh
readonly regression=$test_directory/action28n-node-b-caddy-vrrp-relinquish-regression.sh
readonly focused=$test_directory/action28n-focused-validation.sh
readonly fixture=$test_directory/fixtures/action28n-node-b-retired-main.conf
readonly manifest=$caddy_root/manifests/caddy-node-b-vrrp-relinquish-action28n.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

check() {
    local action28n_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28n_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28n_focused_label" >&2
    return 1
}
hash_exact() {
    local action28n_focused_expected=$1
    local action28n_focused_path=$2

    [[ "$(sha256sum -- "$action28n_focused_path" | awk '{ print $1 }')" = "$action28n_focused_expected" ]]
}

check transaction_hash hash_exact 1df11c08bd40fe8833f65a34fe2f0d762199e763452c8234d79b038f53a3ee70 "$transaction"
check outer_hash hash_exact d1d8fb2f308662686f9a74421cd25d10fa0ab08d8e5cdd0347b826187ad0af68 "$outer"
check regression_hash hash_exact 9bbd2fea546757ad6a1cb65a719ac39a58b8197226d9db0dea695f983e97f651 "$regression"
check fixture_hash hash_exact 9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148 "$fixture"
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
check transaction_self_test "$transaction" --self-test
check outer_self_test "$outer" --self-test
check regression /bin/bash "$regression"
check manifest_action grep -Fqx 'action: 28n' "$manifest"
check manifest_definition grep -Fqx '  definition_only: true' "$manifest"
check manifest_execution_false grep -Fqx '  execution: false' "$manifest"
check manifest_coupled_false grep -Fqx '  coupled_vip_acquisition: prohibited' "$manifest"
check plan_status grep -Fq 'Node B separate-Caddy-VRRP relinquish Action 28n' "$plan"
for action28n_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28n_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28n_focused_entrypoint"
    if [[ -d "$repository_root/.git" ]]; then
        check "index_mode_$(basename "$action28n_focused_entrypoint" | tr '.-' '__')" \
            test "$(git -C "$repository_root" ls-files -s -- \
                "Caddy/${action28n_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
    fi
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
