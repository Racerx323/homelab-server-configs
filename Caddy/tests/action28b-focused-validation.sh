#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28b_focused_validation
readonly builder_sha256=a0713c4dde25a1a6bd368b16d9e9fdf881ae1014204d619fe5cbc6475b45a4d5
readonly driver_sha256=f7b6af461dcd2ca108e3cb097424646a3604382081d0be4e162b2f933e822591
readonly outer_sha256=95ed2baf51916979b62ba986db1a3cb292f0f55262bd6e7474a5cead811bc282
readonly regression_sha256=d6afb947a016fc19ad3ece8cb825ae76a5ca901a1bb40c61b834c06126c1f9dd
readonly manifest_sha256=5f77d29abc123ba75c6b6195211657d474d19f46f847e7b406f352f56c75e851

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly builder=$caddy_root/scripts/build-node-a-protocol-v2-publisher-action28b.sh
readonly driver=$caddy_root/scripts/install-node-a-protocol-v2-publisher-action28b.sh
readonly outer=$caddy_root/scripts/run-node-a-protocol-v2-publisher-action28b-outer.sh
readonly regression=$test_directory/action28b-node-a-publisher-install-regression.sh
readonly focused=$test_directory/action28b-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-node-a-publisher-action28b.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28b_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28b_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28b_focused_label" >&2
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
    grep -Fqx 'action: 28b' "$manifest" || return 1
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
record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$publisher" "$builder" "$driver" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$publisher" "$builder" "$driver" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$driver" "$outer" "$regression" "$focused"
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

for action28b_focused_entrypoint in "$builder" "$driver" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28b_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28b_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
