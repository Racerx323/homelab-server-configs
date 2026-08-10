#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_c_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-c-outer.sh
readonly regression=$test_directory/action28g-c-residue-consumer-regression.sh
readonly focused=$test_directory/action28g-c-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-post-action28g-c.yaml
readonly predecessor=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-b-outer.sh
readonly outer_sha256=24f7a4fc6e37a5c878fc6cc89f145a1ba3422e773ceabf780ef83f194a99ec8b
readonly regression_sha256=67fde79b7768af1868584fa73dc542863d01a48bbc2c29741a5c24da39e5789a
readonly manifest_sha256=8d922b9d38a10741aa383169e311cd9270a095120a03f411fa30390485416adb
readonly predecessor_sha256=b30a7ec915004491d58f5e4cc94d45a697661559eb1bb250ba640f98ba84fef4

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_c_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_c_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_c_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28g-c' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest"
}

record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check predecessor_immutable test "$(file_hash "$predecessor")" = "$predecessor_sha256"
record_check syntax /bin/bash -n "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check

for action28g_c_focused_entrypoint in "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28g_c_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28g_c_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
