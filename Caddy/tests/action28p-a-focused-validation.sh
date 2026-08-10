#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28p_a_focused
readonly node_b_inspector_sha256=9d835b805b21262b51c50749b5671223ced5f049991ffdf841054e413dec596b
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly outer_sha256=240d5274693cdc7fb9bf3106790369616dedd7bf6845b83db09c8ff543835433
readonly regression_sha256=8100844d9a8aa0ff8b7446da578a6d69737b81ecc824ce9743c4cb4429c239d6
readonly manifest_sha256=a2bfd114cba90bc710a54d3b1213ef96589e7d3b4418f8b142c9bfa2ea0b9e51
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-relinquish-post-action28p-a-outer.sh
readonly regression=$test_directory/action28p-a-dual-node-postrelinquish-regression.sh
readonly focused=$test_directory/action28p-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-vrrp-relinquish-post-action28p-a.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28pa_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28pa_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28pa_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28p-a' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  execution_authorized: false' "$manifest" || return 1
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

for action28pa_focused_entrypoint in "$node_b_inspector" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28pa_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28pa_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28p_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
