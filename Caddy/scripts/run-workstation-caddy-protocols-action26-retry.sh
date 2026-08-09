#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_retry_adapter
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_core=$script_directory/run-workstation-caddy-protocols-action26.sh
readonly source_sha256=f72ceb374f4a8c07f820dc720266458af6f2ae70b4287f84e778f8387b08c046
readonly generated_sha256=683da97c69ed92a31de0adc53c13ee300976b9258038ff3003155bee4c1b6091
action26_retry_adapter_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action26_retry_adapter_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_retry_adapter_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_retry_adapter_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' source_regular source_not_symlink source_hash prefix_count_exact \
        retry_prefix_absent directory_assignment_count_exact generated_hash
}
cleanup() {
    local action26_retry_adapter_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26_retry_adapter_root" ]] || rm -rf -- "$action26_retry_adapter_root"
    exit "$action26_retry_adapter_status"
}
run_adapter() {
    local action26_retry_generated

    action26_retry_adapter_root=$(mktemp -d /tmp/caddy-action26-retry-adapter.XXXXXX)
    trap cleanup EXIT INT TERM
    action26_retry_generated=$action26_retry_adapter_root/core.sh
    check source_regular test -f "$source_core" || return 1
    check source_not_symlink test ! -L "$source_core" || return 1
    check source_hash test "$(file_hash "$source_core")" = "$source_sha256" || return 1
    check prefix_count_exact test "$(grep -Fxc 'readonly prefix=action_26' "$source_core")" -eq 1 || return 1
    check retry_prefix_absent test "$(grep -Fxc 'readonly prefix=action_26_retry' "$source_core")" -eq 0 || return 1
    # Literal source contract; dollar-prefixed expressions must not expand here.
    # shellcheck disable=SC2016
    check directory_assignment_count_exact test \
        "$(grep -Fxc 'script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)' "$source_core")" \
        -eq 1 || return 1
    # Literal source transformation; dollar-prefixed expressions must remain literal.
    # shellcheck disable=SC2016
    sed -e 's/^readonly prefix=action_26$/readonly prefix=action_26_retry/' \
        -e 's|^script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE\[0\]}")" && pwd)$|script_directory=${CADDY_ACTION26_RETRY_SOURCE_SCRIPT_DIRECTORY:?}|' \
        "$source_core" >"$action26_retry_generated"
    check generated_hash test "$(file_hash "$action26_retry_generated")" = "$generated_sha256" || return 1
    CADDY_ACTION26_RETRY_SOURCE_SCRIPT_DIRECTORY=$script_directory \
        /bin/bash "$action26_retry_generated"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    "") run_adapter ;;
    *) exit 64 ;;
esac
