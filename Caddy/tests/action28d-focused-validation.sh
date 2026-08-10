#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28d_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28d.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28d-outer.sh
readonly regression=$test_directory/action28d-node-a-to-node-b-release-transfer-regression.sh
readonly focused=$test_directory/action28d-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-a-to-b-action28d.yaml
readonly builder_sha256=5f7cf9afe81b142ecab17f4fc07570f62cf63a535c710ecf59f443d819d92f4f
readonly outer_sha256=8c5c1482350c4fd2cd47608f9ea586a63c993d4ecc1bc8364626f5b5da800cae
readonly regression_sha256=038f5a26ee825f2068c1aa2ede798211dc11b438fdff0a0e220d93b33b1a03a8
readonly manifest_sha256=0a65384c25e01e76e44d50e76800f8b3734f0bef5b9804ab159f71fae3328b82
readonly generated_driver_sha256=be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58
readonly generated_inspector_sha256=4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482
readonly generated_runner_sha256=df6847bac598b8cd8453809a1fdddf6e28cabcfe45352ed6ed03ffb45aa429cc

work_root=$(mktemp -d /tmp/caddy-action28d-focused.XXXXXX)
readonly work_root
readonly generated=$work_root/generated

cleanup() {
    local action28d_focused_status=$?

    rm -rf -- "$work_root"
    exit "$action28d_focused_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28d_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28d_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28d_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28d' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest"
}
generated_contract() {
    local action28d_focused_driver=$generated/transfer-node-a-release-to-node-b-action28d.sh
    local action28d_focused_inspector=$generated/inspect-node-b-incoming-release-action28d.sh
    local action28d_focused_runner=$generated/run-node-a-to-node-b-release-transfer-action28d.sh

    mkdir -m 0700 "$generated" || return 1
    /bin/bash "$builder" "$generated" || return 1
    [[ "$(file_hash "$action28d_focused_driver")" = "$generated_driver_sha256" ]] || return 1
    [[ "$(file_hash "$action28d_focused_inspector")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action28d_focused_runner")" = "$generated_runner_sha256" ]] || return 1
    /bin/bash -n "$generated"/*.sh || return 1
    grep -Fq 'record_command action28b_manifest_exact' "$action28d_focused_driver" || return 1
    grep -Fq 'record_command retained_release_tree_exact' "$action28d_focused_driver" || return 1
    grep -Fq 'record_command vrrp_state_master' "$action28d_focused_driver" || return 1
    grep -Fq 'record_command release_complete_regular' "$action28d_focused_inspector" || return 1
    # The pattern intentionally matches literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(grep -Fc '"cd / && sudo -n /bin/bash -s -- $remote_argument"' \
        "$action28d_focused_runner" || true)" -eq 1 ]] || return 1
    ! grep -Fq '/bin/bash -s/' "$action28d_focused_runner" || return 1
    grep -Fq 'remote_delete_executed=false' "$action28d_focused_driver" \
        "$action28d_focused_runner" || return 1
    ! grep -Fq -- '--emergency' "$generated"/*.sh || return 1
    ! grep -Fq -- '--delete' "$generated"/*.sh || return 1
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$generated"/*.sh || return 1
}

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$builder" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$builder" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check generated_contract generated_contract
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action28d_focused_entrypoint in "$builder" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28d_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28d_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = \
        100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28c_rerun=false\n' "$prefix"
printf '%s_publisher_invocation=false\n' "$prefix"
printf '%s_release_transfer=false\n' "$prefix"
printf '%s_finalizer_invocation=false\n' "$prefix"
printf '%s_persistent_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
