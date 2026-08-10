#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28c_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28c.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28c-outer.sh
readonly regression=$test_directory/action28c-node-a-to-node-b-release-transfer-regression.sh
readonly focused=$test_directory/action28c-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-a-to-b-action28c.yaml
readonly builder_sha256=bc17385186d282412e7f89f9bcdb150bf17eaa6427d09667b57e7d38debef86f
readonly outer_sha256=a1447de2c7cfc22e7559dd2dfaea18907e152a9850853407ee4c35ac53644dfe
readonly regression_sha256=30ab67e021f49d0ae308b4b112074c707700d75954877044ef84798410f5633f
readonly manifest_sha256=85674eae2e529f6a8d10fe4d78f7c0806640d2e9b0de4638fba981d804f84795
readonly generated_driver_sha256=175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9
readonly generated_inspector_sha256=475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513
readonly generated_runner_sha256=15689ce1b521c32d10fd927a69f346f8499fff60b422a2ce375fe9aa16c23eaf

work_root=$(mktemp -d /tmp/caddy-action28c-focused.XXXXXX)
readonly work_root
readonly generated=$work_root/generated
cleanup() {
    local action28c_focused_status=$?

    rm -rf -- "$work_root"
    exit "$action28c_focused_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28c_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28c_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28c_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28c' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest"
}
generated_contract() {
    local action28c_focused_driver=$generated/transfer-node-a-release-to-node-b-action28c.sh
    local action28c_focused_inspector=$generated/inspect-node-b-incoming-release-action28c.sh
    local action28c_focused_runner=$generated/run-node-a-to-node-b-release-transfer-action28c.sh

    mkdir -m 0700 "$generated" || return 1
    /bin/bash "$builder" "$generated" || return 1
    [[ "$(file_hash "$action28c_focused_driver")" = "$generated_driver_sha256" ]] || return 1
    [[ "$(file_hash "$action28c_focused_inspector")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action28c_focused_runner")" = "$generated_runner_sha256" ]] || return 1
    /bin/bash -n "$generated"/*.sh || return 1
    grep -Fq 'record_command action28b_manifest_exact' "$action28c_focused_driver" || return 1
    grep -Fq 'record_command retained_release_tree_exact' "$action28c_focused_driver" || return 1
    grep -Fq 'record_command vrrp_state_master' "$action28c_focused_driver" || return 1
    grep -Fq 'record_command release_complete_regular' "$action28c_focused_inspector" || return 1
    grep -Fq 'readonly node_a_ipv6=fd36:5aa8:6971:1::53' \
        "$action28c_focused_driver" || return 1
    # The pattern intentionally matches literal generated shell source.
    # shellcheck disable=SC2016
    grep -Fq '[[ "$(remote_shell_value)" == *"-b $node_a_ipv6"* ]]' \
        "$action28c_focused_driver" || return 1
    grep -Fq 'remote_delete_executed=false' "$action28c_focused_driver" \
        "$action28c_focused_runner" || return 1
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

for action28c_focused_entrypoint in "$builder" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28c_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28c_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = \
        100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_publisher_invocation=false\n' "$prefix"
printf '%s_release_transfer=false\n' "$prefix"
printf '%s_finalizer_invocation=false\n' "$prefix"
printf '%s_persistent_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
