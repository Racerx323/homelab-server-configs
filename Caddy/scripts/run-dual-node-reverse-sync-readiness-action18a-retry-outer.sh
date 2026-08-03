#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18a_retry
readonly derivation_sha256=e7228a792d476ea82b8863ac7f01e786ead9e28f23d0e0430f660794aa8c3ba9
readonly regression_sha256=867a8898317542140af40223a29dc7b165bbae7d6389f5da362fd1c0f847306e
readonly rendered_inspector_sha256=eb57a551c7c86ddfc347ca35b6d5d2a90488911d77a002c1d92ad1b7898fd1c3
readonly rendered_runner_sha256=48dc78f8baf7528dbf204c46d2c1c63c18f287815dafcb6ac695c3551f182849

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-dual-node-reverse-sync-readiness-action18a-retry.sh"
readonly regression="$caddy_root/tests/action18a-retry-dual-node-reverse-sync-readiness-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    [[ -f "$derivation" && ! -L "$derivation" ]] || return 1
    [[ -f "$regression" && ! -L "$regression" ]] || return 1
    [[ "$(file_hash "$derivation")" == "$derivation_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" == "$regression_sha256" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$derivation")" == aaron:aaron:755 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$regression")" == aaron:aaron:755 ]] || return 1
}

render_and_verify() {
    local render_directory=$1
    local rendered_inspector="$render_directory/inspect-reverse-sync-readiness-action18a-retry.sh"
    local rendered_runner="$render_directory/run-dual-node-reverse-sync-readiness-action18a-retry.sh"

    "$derivation" --output-directory "$render_directory" >/dev/null
    [[ "$(file_hash "$rendered_inspector")" == "$rendered_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$rendered_runner")" == "$rendered_runner_sha256" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$rendered_inspector")" == aaron:aaron:755 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$rendered_runner")" == aaron:aaron:755 ]] || return 1
    bash -n "$rendered_inspector" "$rendered_runner"
    "$rendered_inspector" --self-test >/dev/null
    "$rendered_runner" --self-test >/dev/null
    "$rendered_runner" --source-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        printf '%s_outer_self_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        printf '%s_outer_source_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        contract_directory=$(mktemp -d /tmp/caddy-action18a-retry-outer-contract.XXXXXX)
        readonly contract_directory
        trap 'rm -rf -- "$contract_directory"' EXIT
        render_and_verify "$contract_directory"
        "$regression" >/dev/null
        printf '%s_outer_contract_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
work_directory=$(mktemp -d /tmp/caddy-action18a-retry-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
render_and_verify "$work_directory"
"$regression" >/dev/null

set +e
"$work_directory/run-dual-node-reverse-sync-readiness-action18a-retry.sh"
readonly runner_status=$?
set -e
printf '%s_outer_runner_status=%s\n' "$action_prefix" "$runner_status"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$action_prefix"
exit "$runner_status"
