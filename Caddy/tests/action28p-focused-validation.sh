#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28p_focused
readonly transaction_sha256=cca0516cd058013deadba32ea7502ee64faa2a436a8132bd74137c74c3f67d5f
readonly outer_sha256=0b42f91726778aef58a298d74c562d9d2c8501d3d0ac640bafcf164eebd100d6
readonly regression_sha256=eb00f02f33b9616d0340af69c70ca1a47cbb9ce2d715f9c08628d0214c128a7c
readonly fixture_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly manifest_sha256=791c6055153361643117c01fcbf2f02250a4edc2e67b1679d96911c62c33e24a
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/relinquish-node-b-caddy-vrrp-action28p.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-vrrp-relinquish-action28p-outer.sh
readonly regression=$test_directory/action28p-node-b-caddy-vrrp-relinquish-regression.sh
readonly focused=$test_directory/action28p-focused-validation.sh
readonly fixture=$test_directory/fixtures/action28p-node-b-retired-main.conf
readonly manifest=$caddy_root/manifests/caddy-node-b-vrrp-relinquish-action28p.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28p_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28p_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28p_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28p' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
}

check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check fixture_hash test "$(file_hash "$fixture")" = "$fixture_sha256"
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
check manifest_action grep -Fqx 'action: 28p' "$manifest"
check manifest_definition grep -Fqx '  definition_only: true' "$manifest"
check manifest_execution_false grep -Fqx '  execution: false' "$manifest"
check plan_gate grep -Fq "Action 28p once using outer SHA-256 \`$outer_sha256\`" "$plan"
for action28p_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28p_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28p_focused_entrypoint"
    check "index_mode_$(basename "$action28p_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28p_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
