#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28r_a_focused
readonly inspector_sha256=911c003cf0fc592de67f3aeacc33bec14ea5659e501fb9dbe4ccac2a0fbbbae5
readonly regression_sha256=5154650c567796e2d515eebe2a5dead35b7821e0a2ee2513d159e649d1594f9b
readonly outer_sha256=8fac199d0f83595ca517f7f8975c0dfe07cc9538ddd0001c570fe2c4e454993a
readonly manifest_sha256=3b7bf1deb15309566c9fdfc5c6a2238fad050f6915bca95a2218fd0d14cea5a6
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector=$caddy_root/scripts/inspect-action28r-transition-rollback-action28r-a.sh
readonly regression=$test_directory/action28r-a-transition-rollback-regression.sh
readonly outer=$caddy_root/scripts/run-dual-node-action28r-transition-rollback-action28r-a-outer.sh
readonly focused=$test_directory/action28r-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-action28r-transition-rollback-action28r-a.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28ra_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28ra_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28ra_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28r-a' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
}

check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check syntax /bin/bash -n "$inspector" "$regression" "$outer" "$focused"
check shellcheck shellcheck "$inspector" "$regression" "$outer" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check "$inspector" "$regression" "$outer" "$focused"
check yaml yaml_check
check regression /bin/bash "$regression"
check inspector_self_test "$inspector" --self-test
check outer_self_test "$outer" --self-test
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$regression" "$outer" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check "$inspector" "$regression" "$outer" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check "$inspector" "$regression" "$outer" "$focused"
check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
check ssh_evidence_policy /bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
check outer_labels /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
check plan_gate grep -Fq "Action 28r-a once using outer SHA-256 \`$outer_sha256\`" "$plan"
for action28ra_focused_entrypoint in "$inspector" "$regression" "$outer" "$focused"; do
    check "executable_$(basename "$action28ra_focused_entrypoint" | tr '.-' '__')" test -x "$action28ra_focused_entrypoint"
    check "index_mode_$(basename "$action28ra_focused_entrypoint" | tr '.-' '__')" test "$(git -C "$repository_root" ls-files --stage -- "Caddy/${action28ra_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_28r_rerun=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
