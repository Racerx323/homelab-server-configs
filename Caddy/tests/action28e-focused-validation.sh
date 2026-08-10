#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28e.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28e-outer.sh
readonly regression=$test_directory/action28e-node-a-to-node-b-release-transfer-regression.sh
readonly focused=$test_directory/action28e-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-a-to-b-action28e.yaml
readonly builder_sha256=a72079d2511e0f21378571b36664c96e2627fc9e35ae869ab0780ab304b46aba
readonly outer_sha256=d6b87c4991d89d67937c6024368dd745fa24160ebe42d79ce1cd55a4e15efb4f
readonly regression_sha256=4d725765b16c82c377880145d8e241f67b0060e3f5d026a1a7ab130f422c87a5
readonly manifest_sha256=e78c5ed8c2158cc7646ea5a7731c66d6e48918e9e338400ced258da8a307a7f7
readonly generated_driver_sha256=ce27b4b280e8f31ec240d53c930d4140ff3ad809f43313c7d8b8500d6cfc1405
readonly generated_inspector_sha256=56caf44ea261f997d177e9bc4cf340538e3a0de7d0fe39097a88d692d93b8e09
readonly generated_runner_sha256=1c89e740b361426f534e3ad6abf697c194b64ede40b2e4ec72f9711490d33702

work_root=$(mktemp -d /tmp/caddy-action28e-focused.XXXXXX)
readonly work_root
readonly generated=$work_root/generated

cleanup() {
    local action28e_focused_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_focused_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28e_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28e' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest"
}
generated_contract() {
    local action28e_focused_driver=$generated/transfer-node-a-release-to-node-b-action28e.sh
    local action28e_focused_inspector=$generated/inspect-node-b-incoming-release-action28e.sh
    local action28e_focused_runner=$generated/run-node-a-to-node-b-release-transfer-action28e.sh

    mkdir -m 0700 "$generated" || return 1
    /bin/bash "$builder" "$generated" || return 1
    [[ "$(file_hash "$action28e_focused_driver")" = "$generated_driver_sha256" ]] || return 1
    [[ "$(file_hash "$action28e_focused_inspector")" = "$generated_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action28e_focused_runner")" = "$generated_runner_sha256" ]] || return 1
    /bin/bash -n "$generated"/*.sh || return 1
    grep -Fq 'readonly release_root=/etc/caddy/releases' "$action28e_focused_driver" || return 1
    grep -Fq 'record_command release_root_directory' "$action28e_focused_driver" || return 1
    grep -Fq 'record_command release_root_not_symlink' "$action28e_focused_driver" || return 1
    grep -Fq 'record_command source_target_resolved' "$action28e_focused_driver" || return 1
    grep -Fq 'record_command source_target_direct_child' "$action28e_focused_driver" || return 1
    grep -Fq 'record_command source_target_tree_exact' "$action28e_focused_driver" || return 1
    # The patterns intentionally match literal generated shell source.
    # shellcheck disable=SC2016
    grep -Fq '"$publisher" --source "$resolved_source_release" --node-role node-a' \
        "$action28e_focused_driver" || return 1
    # shellcheck disable=SC2016
    ! grep -Fq '"$publisher" --source "$source_release" --node-role node-a' \
        "$action28e_focused_driver" || return 1
    grep -Fq 'record_command release_complete_regular' "$action28e_focused_inspector" || return 1
    # shellcheck disable=SC2016
    [[ "$(grep -Fc '"cd / && sudo -n /bin/bash -s -- $remote_argument"' \
        "$action28e_focused_runner" || true)" -eq 1 ]] || return 1
    grep -Fq 'remote_delete_executed=false' "$action28e_focused_driver" \
        "$action28e_focused_runner" || return 1
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
record_check outer_label_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check \
    "$builder" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action28e_focused_entrypoint in "$builder" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28e_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28e_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = \
        100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28d_rerun=false\n' "$prefix"
printf '%s_publisher_invocation=false\n' "$prefix"
printf '%s_release_transfer=false\n' "$prefix"
printf '%s_finalizer_invocation=false\n' "$prefix"
printf '%s_persistent_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
