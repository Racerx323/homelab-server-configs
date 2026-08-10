#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28a_focused_validation
readonly driver_sha256=6e1580798f40e5d056018f52bc9346f0366326f21685810b906b60a66da2c8bd
readonly outer_sha256=ea67aa3ed4443d9ec793d63c13870dddfdb6e5d1d367c6b489ce6e82a5999bec
readonly regression_sha256=1047406e88b2f2c1bb058d53adf75bea56e6a14d1a1f70586170440d36e6e455
readonly manifest_sha256=8691a7f0c9e7af5c4fa9f6c1891c97ff762d2cfc8437bf1771c7d1de41ada8b8

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly driver=$caddy_root/scripts/install-node-a-protocol-v2-publisher-action28a.sh
readonly outer=$caddy_root/scripts/run-node-a-protocol-v2-publisher-action28a-outer.sh
readonly regression=$test_directory/action28a-node-a-publisher-install-regression.sh
readonly focused=$test_directory/action28a-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-node-a-publisher-action28a.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28a_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28a_focused_label" >&2
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
    grep -Fqx 'action: 28a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$manifest" || return 1
    grep -Fqx '  action_28_rerun_permitted: false' "$manifest" || return 1
    grep -Fqx '  publisher_pre_state: absent' "$manifest" || return 1
    grep -Fqx '  publisher_invoked: false' "$manifest" || return 1
    grep -Fqx '  release_mutated: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}

record_check publisher_hash test "$(file_hash "$publisher")" = \
    e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$publisher" "$driver" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$publisher" "$driver" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check source_context /bin/bash \
    "$test_directory/run-source-test-in-context.sh" --runner "$outer"
record_check outer_local_labels /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check transcript_contract /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action28a_focused_entrypoint in "$driver" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28a_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28a_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
