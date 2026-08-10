#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_a_focused
readonly notifier_sha256=34a89df54cf44bb3a37203f21ee496f15390395b10b303a20cd70275d3b5f9e8
readonly outer_sha256=490ef116ed10d5082d0a741c1a0e7a8d27691e2549fa627f0172c0410cf90816
readonly regression_sha256=39c9c2162e3b82bf350bfaaafcbc673f7a3b252eb5896828b082d762dacf608a
readonly manifest_sha256=fba6eb39eca46928d0a133916158d2ddb64d98b9d8c7cbf355af5bffe4f1b5da
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly notifier=$caddy_root/scripts/inspect-node-b-action28q-notifier-evidence.sh
readonly outer=$caddy_root/scripts/run-dual-node-coupled-vip-postrollback-action28q-a-outer.sh
readonly regression=$test_directory/action28q-a-postrollback-convergence-regression.sh
readonly focused=$test_directory/action28q-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-coupled-vip-postrollback-action28q-a.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28qa_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28qa_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28qa_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28q-a' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
}

record_check notifier_hash test "$(file_hash "$notifier")" = "$notifier_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$notifier" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$notifier" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$notifier" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$notifier" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check multifile_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$notifier" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$notifier" "$outer" "$regression" "$focused"
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

for action28qa_focused_entrypoint in "$notifier" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action28qa_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28qa_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28q_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
