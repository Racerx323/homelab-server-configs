#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_a_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly main_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-e.sh
readonly residue_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28g-a-residue.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-a-outer.sh
readonly regression=$test_directory/action28g-a-dual-node-post-execution-regression.sh
readonly focused=$test_directory/action28g-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-post-action28g-a.yaml
readonly action28g_outer=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28g-outer.sh
readonly main_inspector_sha256=96b159653883c5a67ae384b1129ce619f2e74f0b44c4846da1d44ae898cd96d9
readonly residue_inspector_sha256=b4d5672ad87de72852683578df484991de02ce382242b2d7235b67c729fbdb26
readonly outer_sha256=3226d93ed2facf7a4fc9952818f636ac0a5d33270353f38c837cbdee81175d01
readonly regression_sha256=a99bc920ed0c66106bf5e3318fdc2a052998d04b68193aac54fd5e0bbbe503d9
readonly manifest_sha256=f04314a489715ebb5c829077414538ff6451d3075482f29b0d28bb19fca687d3
readonly action28g_outer_sha256=ffc572b7c84d76288f293af814cfe917dc52128f878509ca160c5fd2d6bd2642

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_a_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_a_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28g-a' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  residue_inspector_sha256: $residue_inspector_sha256" "$manifest" || return 1
    grep -Fqx "  regression_sha256: $regression_sha256" "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest"
}

record_check main_inspector_hash test "$(file_hash "$main_inspector")" = "$main_inspector_sha256"
record_check residue_inspector_hash test "$(file_hash "$residue_inspector")" = "$residue_inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28g_immutable test "$(file_hash "$action28g_outer")" = "$action28g_outer_sha256"
record_check syntax /bin/bash -n "$main_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$main_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$main_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check main_inspector_self_test /bin/bash "$main_inspector" --self-test
record_check residue_inspector_self_test /bin/bash "$residue_inspector" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$main_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check

for action28g_a_focused_entrypoint in "$residue_inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28g_a_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28g_a_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28g_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
