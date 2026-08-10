#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28b_a_focused_validation
readonly inspector_sha256=a2b09a7ce5d9ba0481efd5d0eedd3a137ed7f29e4c7b691a102667c8195c66f3
readonly outer_sha256=8e4526e8ea4f9e83680ca8fb6ba04d7014fe944ff1ba9040865657a44f403252
readonly regression_sha256=8910b145d6979845adca9c61436f7c6d8be976d4b4eba490e117271b7ec91189
readonly manifest_sha256=744e58f3a6971c6abde0b5fea9ae5e6ebed9c6db2dcb17f767380a91fd2d8fed

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly inspector=$caddy_root/scripts/inspect-node-a-publisher-postinstall-action28b-a.sh
readonly outer=$caddy_root/scripts/run-node-a-publisher-postinstall-action28b-a-outer.sh
readonly regression=$test_directory/action28b-a-node-a-postinstall-regression.sh
readonly focused=$test_directory/action28b-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-node-a-publisher-postinstall-action28b-a.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28b_a_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28b_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28b_a_focused_label" >&2
    return 1
}
yaml_check() {
    # conditional-validator-explicit-failures-begin
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28b-a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$manifest" || return 1
    grep -Fqx '  cleanup_authorized: false' "$manifest" || return 1
    grep -Fqx '  action_28_rerun_permitted: false' "$manifest" || return 1
    grep -Fqx '  action_28b_rerun_permitted: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
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
record_check outer_local_labels /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check transcript_contract /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action28b_a_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28b_a_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28b_a_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_action_28b_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
