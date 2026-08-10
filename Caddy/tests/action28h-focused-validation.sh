#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28h_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-node-b-normal-publisher-rejection-action28h.sh
readonly outer=$caddy_root/scripts/run-node-b-normal-publisher-rejection-action28h-outer.sh
readonly regression=$test_directory/action28h-node-b-normal-publisher-rejection-regression.sh
readonly focused=$test_directory/action28h-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-node-b-normal-publisher-rejection-action28h.yaml
readonly action28g_c_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-c-outer.sh
readonly probe_sha256=d6c69b9b43d807986c647c6a449e3c431f76cfb1c4fddf976b24473161a2d300
readonly outer_sha256=f4d9c9ced5b48453de2a85d5c1e52d9c1ba5a903baca2e8eb0cf0a2eefb59a11
readonly regression_sha256=55d64b819bd6893802436be1219ee15583ac24e3539585c8fb070c7a06597e5e
readonly manifest_sha256=f462d59ffcd670a4d030ca438b800bcc4b9384870173e8badbdb31c917b06322
readonly action28g_c_outer_sha256=24f7a4fc6e37a5c878fc6cc89f145a1ba3422e773ceabf780ef83f194a99ec8b

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

record_check() {
    local action28h_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28h_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28h_focused_label" >&2
    return 1
}

yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28h' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest"
}

record_check probe_hash test "$(file_hash "$probe")" = "$probe_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check action28g_c_outer_immutable test "$(file_hash "$action28g_c_outer")" = \
    "$action28g_c_outer_sha256"
record_check syntax /bin/bash -n "$probe" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$probe" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$probe" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$probe" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" \
    --check "$probe" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" \
    --check "$probe" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" \
    --check "$outer"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check

for action28h_focused_entrypoint in "$probe" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28h_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28h_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
