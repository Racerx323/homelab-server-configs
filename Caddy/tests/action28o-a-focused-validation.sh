#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28o_a_focused
readonly node_b_inspector_sha256=4a513472c1771693d4e4992307afa20b2031c06c33d21d84011d3413bbc9edc9
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly outer_sha256=bfb59e63d704a27b1ef05f43d95ea11a85f906ae7f9ffc35f5e277b99f703571
readonly regression_sha256=bdb7b2f1a6e0de3b1360c139ff4f26ce81e1682b0c8c5df039ca270d54d05ca5
readonly manifest_sha256=0d7009f661984b5e2823ecc3c5cf4542967ea9ffd64c1c23262c861055311f51
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-service-restoration-action28o-a.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-service-restoration-post-action28o-a-outer.sh
readonly regression=$test_directory/action28o-a-dual-node-postinstall-regression.sh
readonly focused=$test_directory/action28o-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-service-restoration-post-action28o-a.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28oa_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28oa_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28oa_focused_label" >&2
    return 1
}
yaml_check() {
    # conditional-validator-explicit-failures-begin
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28o-a' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  execution_authorized: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}

record_check node_b_inspector_hash test "$(file_hash "$node_b_inspector")" = \
    "$node_b_inspector_sha256"
record_check node_a_inspector_hash test "$(file_hash "$node_a_inspector")" = \
    "$node_a_inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$node_b_inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$node_b_inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$node_b_inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$node_b_inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check multifile_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$node_b_inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$node_b_inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check ssh_local_evidence_policy /bin/bash \
    "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
record_check outer_local_labels /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check transcript_contract /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action28oa_focused_entrypoint in "$node_b_inspector" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28oa_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28oa_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28o_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
