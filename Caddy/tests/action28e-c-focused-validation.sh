#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_c_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-historical-release-manifest-action28e-c.sh
readonly outer=$caddy_root/scripts/run-dual-node-historical-release-manifest-action28e-c-outer.sh
readonly regression=$test_directory/action28e-c-historical-release-manifest-regression.sh
readonly focused=$test_directory/action28e-c-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-historical-release-manifest-action28e-c.yaml
readonly action28e_b_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-b-outer.sh
readonly inspector_sha256=b90ad77e54c653ee431aac1ea479ff00ffe51034f38b08fd12b00bcdeca878cd
readonly outer_sha256=edc88d827a9bdd60a62832d452ac5508c0a1ae2f35f14740bdd5c4bf7d5e8230
readonly regression_sha256=a06ced0189913888f1357811b4119ca3ed0c4f5f4ab57239c7eb02662d221af5
readonly manifest_sha256=47ff366203ad28fe4e5f4f63a3d6f2e02282e6f7fe19bd802177a41831bd0256
readonly action28e_b_outer_sha256=2048857d11767f12cfaeee30a1f0f68d8cda6738b5a24d36f326bcca1d9823ce

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28e_c_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_c_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_c_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28e-c' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  inspector_sha256: $inspector_sha256" "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest" || return 1
    grep -Fqx "  regression_sha256: $regression_sha256" "$manifest"
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28e_b_immutable test "$(file_hash "$action28e_b_outer")" = "$action28e_b_outer_sha256"
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

for action28e_c_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28e_c_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28e_c_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28e_b_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
