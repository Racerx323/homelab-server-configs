#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=focused_validation_selected_shell
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}

record_check() {
    local focused_shell_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$focused_shell_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$focused_shell_label" >&2
    return 1
}

[[ "${1:-}" = --check ]] || {
    printf 'Usage: %s --check FILE [FILE ...]\n' "${0##*/}" >&2
    exit 64
}
shift
[[ $# -gt 0 ]] || exit 64

declare -a focused_shell_files=()
declare -A focused_shell_seen=()
for focused_shell_relative in "$@"; do
    [[ "$focused_shell_relative" =~ ^Caddy/(scripts|tests)/[A-Za-z0-9._/-]+\.sh$ ]] || exit 64
    [[ "$focused_shell_relative" != *..* ]] || exit 64
    [[ -z "${focused_shell_seen[$focused_shell_relative]:-}" ]] || continue
    focused_shell_seen[$focused_shell_relative]=1
    focused_shell_path=$repository_root/$focused_shell_relative
    [[ -f "$focused_shell_path" && ! -L "$focused_shell_path" && -x "$focused_shell_path" ]] || exit 1
    focused_shell_files+=("$focused_shell_path")
done
readonly -a focused_shell_files

record_check syntax /bin/bash -n "${focused_shell_files[@]}" || exit 1
record_check shellcheck shellcheck "${focused_shell_files[@]}" || exit 1
record_check format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "${focused_shell_files[@]}" || exit 1
record_check readonly_local /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "${focused_shell_files[@]}" || exit 1
record_check multifile_grep /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "${focused_shell_files[@]}" || exit 1
record_check portable_awk /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "${focused_shell_files[@]}" || exit 1

printf '%s_file_count=%s\n' "$prefix" "${#focused_shell_files[@]}"
printf '%s_complete=true\n' "$prefix"
