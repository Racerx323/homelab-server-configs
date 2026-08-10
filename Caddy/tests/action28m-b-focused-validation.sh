#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_b_focused
readonly inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly outer_sha256=694f41444928a68cbbc2b04e82fd55b24c9fc60ca2976fd9e886f89953080090
readonly regression_sha256=259e3c1fd179412db7eb90453303d908d0b043e0392c4b450e6889d501f9f1bb
readonly ssh_evidence_policy_sha256=ab2eabf1be9053459a0124a8ec5970aef6a9e828de7dca788ef8bba04fff87ff
readonly manifest_sha256=193f3a2208920e56b981f22335970e0b02e3b9750d61aade086f1eac09f4e333
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-post-action28m-b-outer.sh
readonly regression=$test_directory/action28m-b-node-a-postinstall-regression.sh
readonly ssh_evidence_policy=$test_directory/ssh-stream-local-evidence-policy.sh
readonly focused=$test_directory/action28m-b-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-service-restoration-post-action28m-b.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28mb_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28mb_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28mb_focused_label" >&2
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
    grep -Fqx 'action: 28m-b' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  execution_authorized: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check ssh_evidence_policy_hash test \
    "$(file_hash "$ssh_evidence_policy")" = "$ssh_evidence_policy_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" \
    "$ssh_evidence_policy" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" \
    "$ssh_evidence_policy" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$ssh_evidence_policy" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$ssh_evidence_policy" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$ssh_evidence_policy" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$ssh_evidence_policy" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check ssh_local_evidence_policy /bin/bash "$ssh_evidence_policy" --check "$outer"
record_check ssh_local_evidence_self_test /bin/bash "$ssh_evidence_policy" --self-test
record_check outer_local_labels /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check transcript_contract /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action28mb_focused_entrypoint in "$inspector" "$outer" "$regression" \
    "$ssh_evidence_policy" "$focused"; do
    record_check "index_mode_$(basename "$action28mb_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28mb_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28m_rerun=false\n' "$prefix"
printf '%s_action_28m_a_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
