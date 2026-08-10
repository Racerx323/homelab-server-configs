#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_b_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-b-outer.sh
readonly regression=$test_directory/action28e-b-dual-node-post-execution-regression.sh
readonly focused=$test_directory/action28e-b-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-post-action28e-b.yaml
readonly action28e_outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28e-outer.sh
readonly action28e_a_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-a-outer.sh
readonly inspector_sha256=ca526b924b751a0e06eb7859cc95c6e72eac4c02158999b093f7ae2af49e99cf
readonly outer_sha256=2048857d11767f12cfaeee30a1f0f68d8cda6738b5a24d36f326bcca1d9823ce
readonly regression_sha256=55eba40a962a6c8106f44ed5a31f62f8d46c4f3221f7a4b05cc07ad1c8002adf
readonly manifest_sha256=de56477519b2473e78f4951fc8d38757051f182390fd133bad56492ccc7517e6
readonly action28e_outer_sha256=d6b87c4991d89d67937c6024368dd745fa24160ebe42d79ce1cd55a4e15efb4f
readonly action28e_a_outer_sha256=01c7727f88ef214d2a0cb539e437d4d4ac916bd7f8f7b703cf265f5db49aea12

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28e_b_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_b_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_b_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28e-b' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  inspector_sha256: $inspector_sha256" "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest" || return 1
    grep -Fqx "  regression_sha256: $regression_sha256" "$manifest"
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28e_immutable test "$(file_hash "$action28e_outer")" = "$action28e_outer_sha256"
record_check action28e_a_immutable test "$(file_hash "$action28e_a_outer")" = "$action28e_a_outer_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check outer_self_test /bin/bash "$outer" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action28e_b_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28e_b_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28e_b_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28e_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
