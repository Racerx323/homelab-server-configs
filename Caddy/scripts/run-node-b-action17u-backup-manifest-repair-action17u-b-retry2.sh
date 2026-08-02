#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17u_b_retry2_outer
readonly historical_transaction_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly historical_runner_sha256=19df3282a29ec49fa35f13afdf69a7a2231cac0b8e5e3ae9d5917c71e3a678e5
readonly historical_regression_sha256=a1f95ca15de2f94d00c2982172788d9930f5fa86c8e8032364390bce15b8378a
readonly correction_sha256=842a5a2ab1f54715a8f6f0e9c5b527ff3c6c080ed7094f2677cc604b67b616b7
readonly retry2_regression_sha256=dad4079b558c07d86e4eb59bf8726f37b3a85d68ed718a16e401c0749455a752
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly corrected_transaction_sha256=f92ccbff329c2f6dff015bde47cc13fc3a146549faa69ca5a67619968d9df0d3
readonly corrected_inner_runner_sha256=e3390939cda6a4021701360ae6b43e4d9d77f146211d9cc8217cc0e9188aad0a

retry2_outer_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly retry2_outer_script_directory
retry2_outer_caddy_root=$(cd -- "$retry2_outer_script_directory/.." && pwd)
readonly retry2_outer_caddy_root
readonly historical_transaction="$retry2_outer_script_directory/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly historical_runner="$retry2_outer_script_directory/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh"
readonly historical_regression="$retry2_outer_caddy_root/tests/action17u-b-retry-node-b-backup-manifest-repair-regression.sh"
readonly correction="$retry2_outer_script_directory/correct-node-b-action17u-backup-manifest-hostname-action17u-b-retry2.sh"
readonly retry2_regression="$retry2_outer_caddy_root/tests/action17u-b-retry2-node-b-backup-manifest-repair-regression.sh"
readonly collision_checker="$retry2_outer_caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

retry2_outer_work_directory=

# Invoked indirectly by the EXIT trap installed immediately after mktemp.
# shellcheck disable=SC2317
cleanup_retry2_outer_work_directory() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$retry2_outer_work_directory" &&
        -d "$retry2_outer_work_directory" ]]; then
        if ! rm -rf -- "$retry2_outer_work_directory"; then
            printf '%s_cleanup_complete=false\n' "$action_prefix" >&2
            exit 97
        fi
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verification_path=$1
    local verification_hash=$2

    [[ -f "$verification_path" && ! -L "$verification_path" ]] || return 1
    [[ "$(file_hash "$verification_path")" == "$verification_hash" ]] || return 1
}

verify_sources() {
    verify_file "$historical_transaction" "$historical_transaction_sha256" || return 1
    verify_file "$historical_runner" "$historical_runner_sha256" || return 1
    verify_file "$historical_regression" "$historical_regression_sha256" || return 1
    verify_file "$correction" "$correction_sha256" || return 1
    verify_file "$retry2_regression" "$retry2_regression_sha256" || return 1
    verify_file "$collision_checker" "$collision_checker_sha256" || return 1
    bash -n "$historical_transaction" "$historical_runner" \
        "$historical_regression" "$correction" "$retry2_regression" \
        "$collision_checker" || return 1
    "$collision_checker" "$correction" "$retry2_regression" >/dev/null || return 1
}

render_retry2_stage() {
    local stage_root=$1
    local stage_scripts="$stage_root/Caddy/scripts"
    local stage_tests="$stage_root/Caddy/tests"
    local stage_transaction="$stage_scripts/${historical_transaction##*/}"
    local stage_runner="$stage_scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh"

    install -d -m 0700 "$stage_scripts" "$stage_tests"
    "$correction" --render-transaction "$historical_transaction" \
        >"$stage_transaction"
    "$correction" --render-runner "$historical_runner" >"$stage_runner"
    install -m 0755 -- "$collision_checker" \
        "$stage_tests/${collision_checker##*/}"
    chmod 0755 "$stage_transaction" "$stage_runner"
    verify_file "$stage_transaction" "$corrected_transaction_sha256" || return 1
    verify_file "$stage_runner" "$corrected_inner_runner_sha256" || return 1
    printf '%s\n' "$stage_runner"
}

run_local_gates() {
    local gate_root=$1
    local gate_runner

    "$correction" --self-test >/dev/null || return 1
    "$retry2_regression" --production-test >/dev/null || return 1
    gate_runner=$(render_retry2_stage "$gate_root") || return 1
    "$gate_runner" --self-test >/dev/null || return 1
    "$gate_runner" --source-test >/dev/null || return 1
    "$gate_runner" --contract-test >/dev/null || return 1
}

self_test() {
    local self_test_root

    verify_sources
    self_test_root=$(mktemp -d /tmp/caddy-action17u-b-retry2-outer-self-test.XXXXXX)
    retry2_outer_work_directory=$self_test_root
    trap cleanup_retry2_outer_work_directory EXIT
    run_local_gates "$self_test_root"
    rm -rf -- "$self_test_root"
    retry2_outer_work_directory=
    trap - EXIT
    printf '%s_self_test_complete=true\n' "$action_prefix"
}

contract_test() {
    local contract_root

    verify_sources
    contract_root=$(mktemp -d /tmp/caddy-action17u-b-retry2-outer-contract.XXXXXX)
    retry2_outer_work_directory=$contract_root
    trap cleanup_retry2_outer_work_directory EXIT
    run_local_gates "$contract_root"
    rm -rf -- "$contract_root"
    retry2_outer_work_directory=
    trap - EXIT
    printf '%s_contract_test_complete=true\n' "$action_prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_source_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        contract_test
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
"$correction" --self-test >/dev/null
"$retry2_regression" --production-test >/dev/null

retry2_outer_work_directory=$(mktemp -d /tmp/caddy-action17u-b-retry2-outer.XXXXXX)
trap cleanup_retry2_outer_work_directory EXIT
rendered_retry2_runner=$(render_retry2_stage "$retry2_outer_work_directory")
readonly rendered_retry2_runner
"$rendered_retry2_runner" --self-test >/dev/null
"$rendered_retry2_runner" --source-test >/dev/null
"$rendered_retry2_runner" --contract-test >/dev/null

retry2_inner_status=0
"$rendered_retry2_runner" || retry2_inner_status=$?
rm -rf -- "$retry2_outer_work_directory"
retry2_outer_work_directory=
trap - EXIT
printf '%s_cleanup_complete=true\n' "$action_prefix"
exit "$retry2_inner_status"
