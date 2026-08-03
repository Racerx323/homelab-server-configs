#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18b_a_retry_outer
readonly derivation_sha256=f6d2584afced3f503f7ad36aff518e9c3b73809a94d4f6d1ec390a8e4f6a53a1
readonly regression_sha256=b3132608ad3316693d0c6c658ce979b99a3c279864055a1339379824e7658843
readonly rendered_inspector_sha256=e8a4caf2c0fd17924ed7d1aff96383b9d38d28a5864d10ce434697b343428a02
readonly rendered_runner_sha256=d14a3c73a4058d702e872af868ce038af4e926084a7516c76d2c8e2ad28ab0cc
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly derivation="$script_directory/derive-node-a-action18b-postfailure-action18b-a-retry.sh"
readonly regression="$caddy_root/tests/action18b-a-retry-node-a-postfailure-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    local source_path=$1
    local expected_hash=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]] || return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    verify_source "$derivation" "$derivation_sha256" || return 1
    verify_source "$regression" "$regression_sha256" || return 1
    verify_source "$collision_checker" "$collision_checker_sha256" || return 1
    bash -n "$derivation" "$regression" "$0" || return 1
    "$collision_checker" "$derivation" "$regression" "$0" >/dev/null || return 1
}

render_and_validate() {
    local output_directory=$1
    local rendered_inspector="$output_directory/inspect-node-a-action18b-postfailure-action18b-a-retry.sh"
    local rendered_runner="$output_directory/run-node-a-action18b-postfailure-action18b-a-retry.sh"

    install -d -m 0700 "$output_directory" "$output_directory/../tests" || return 1
    install -m 0755 "$collision_checker" "$output_directory/../tests/" || return 1
    "$derivation" --output-directory "$output_directory" >/dev/null || return 1
    [[ "$(file_hash "$rendered_inspector")" == "$rendered_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$rendered_runner")" == "$rendered_runner_sha256" ]] || return 1
    bash -n "$rendered_inspector" "$rendered_runner" || return 1
    shellcheck "$rendered_inspector" "$rendered_runner" || return 1
    "$collision_checker" "$rendered_inspector" "$rendered_runner" >/dev/null || return 1
    "$rendered_inspector" --self-test >/dev/null || return 1
    "$rendered_runner" --self-test >/dev/null || return 1
    "$rendered_runner" --source-test >/dev/null || return 1
    "$rendered_runner" --contract-test >/dev/null || return 1
}

run_local_gates() {
    local gate_root

    gate_root=$(mktemp -d /tmp/caddy-action18b-a-retry-outer-gate.XXXXXX) || return 1
    if ! render_and_validate "$gate_root/Caddy/scripts"; then
        rm -rf -- "$gate_root"
        return 1
    fi
    rm -rf -- "$gate_root"
    "$regression" >/dev/null || return 1
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action18b-a-retry-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
render_and_validate "$work_directory/Caddy/scripts"
readonly staged_runner="$work_directory/Caddy/scripts/run-node-a-action18b-postfailure-action18b-a-retry.sh"
action_status=0
"$staged_runner" || action_status=$?
readonly action_status
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
exit "$action_status"
