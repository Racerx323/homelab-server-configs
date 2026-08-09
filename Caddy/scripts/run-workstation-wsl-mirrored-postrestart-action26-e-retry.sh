#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_e_retry_adapter
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_inspector=$script_directory/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly source_sha256=c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d
readonly old_target_sha256=6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7
readonly confirmed_target_sha256=04d050670b39c4febb632de69e144a7c3f979c168fe8f326832b1af932300435
readonly generated_inspector_sha256=a8684d98d63282540e003e344694f80f41230943136b5174d838e940f5c16b30
action26e_retry_adapter_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action26e_retry_adapter_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26e_retry_adapter_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26e_retry_adapter_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' source_regular source_not_symlink source_hash old_hash_count_exact \
        confirmed_hash_absent generated_hash
}
cleanup() {
    local action26e_retry_adapter_status=$?

    trap - EXIT INT TERM
    [[ -z "$action26e_retry_adapter_root" ]] || rm -rf -- "$action26e_retry_adapter_root"
    exit "$action26e_retry_adapter_status"
}
run_adapter() {
    local action26e_retry_generated

    action26e_retry_adapter_root=$(mktemp -d /tmp/caddy-action26-e-retry-adapter.XXXXXX)
    trap cleanup EXIT INT TERM
    action26e_retry_generated=$action26e_retry_adapter_root/inspector.sh
    check source_regular test -f "$source_inspector" || return 1
    check source_not_symlink test ! -L "$source_inspector" || return 1
    check source_hash test "$(file_hash "$source_inspector")" = "$source_sha256" || return 1
    check old_hash_count_exact test "$(grep -Foc "$old_target_sha256" "$source_inspector")" -eq 1 || return 1
    check confirmed_hash_absent test "$(grep -Foc "$confirmed_target_sha256" "$source_inspector")" -eq 0 || return 1
    sed "s/$old_target_sha256/$confirmed_target_sha256/" "$source_inspector" >"$action26e_retry_generated"
    check generated_hash test "$(file_hash "$action26e_retry_generated")" = \
        "$generated_inspector_sha256" || return 1
    /bin/bash "$action26e_retry_generated" --expect-mirrored
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    "") run_adapter ;;
    *) exit 64 ;;
esac
