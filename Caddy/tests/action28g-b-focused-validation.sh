#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_b_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-protocol-v2-post-action28g-b-inspector.sh
readonly inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28g-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-b-outer.sh
readonly regression=$test_directory/action28g-b-assertion-output-regression.sh
readonly focused=$test_directory/action28g-b-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-post-action28g-b.yaml
readonly action28g_a_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-a-outer.sh
readonly builder_sha256=09f988d332c6ddae7d268ee6de6690bf7e100fbc512f49f9322b307eb24c791e
readonly inspector_sha256=8f0258c07cd1f75f9f0af0fe8a47b295ef8afc229da6952d65d9ba1fff2dea59
readonly outer_sha256=b30a7ec915004491d58f5e4cc94d45a697661559eb1bb250ba640f98ba84fef4
readonly regression_sha256=d05aeb367a0b150c45cdb5efb75068c8f049f1ca7f02f952ed5ab1fdb6000e71
readonly manifest_sha256=7bb8f32fd46004b4cc2344a988b30c8aa1b6a65984448174fdd4bc0b21ca4e03
readonly action28g_a_outer_sha256=3226d93ed2facf7a4fc9952818f636ac0a5d33270353f38c837cbdee81175d01

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_b_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_b_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_b_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28g-b' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  corrected_inspector_sha256: $inspector_sha256" "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest"
}

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28g_a_immutable test "$(file_hash "$action28g_a_outer")" = "$action28g_a_outer_sha256"
record_check syntax /bin/bash -n "$builder" "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$builder" "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$inspector" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check

for action28g_b_focused_entrypoint in "$builder" "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28g_b_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28g_b_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28g_a_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
