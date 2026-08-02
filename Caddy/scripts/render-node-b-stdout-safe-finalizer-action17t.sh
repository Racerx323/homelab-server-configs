#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly expected_input_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_output_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly old_line='        --adapter caddyfile'
readonly new_line='        --adapter caddyfile >/dev/null'

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_input_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_output_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$old_line" != "$new_line" ]]
    printf 'action_17t_renderer_self_test_complete=true\n'
    exit 0
elif [[ $# -ne 4 || "$1" != --input || "$3" != --output ]]; then
    printf 'Usage: %s --input INPUT --output OUTPUT\n' "${0##*/}" >&2
    exit 2
fi

readonly input_path=$2
readonly output_path=$4
readonly output_parent=${output_path%/*}
[[ "$output_parent" != "$output_path" ]]
[[ -f "$input_path" && ! -L "$input_path" ]]
[[ "$(file_hash "$input_path")" = "$expected_input_sha256" ]]
[[ "$(grep -Fxc "$old_line" "$input_path")" -eq 1 ]]
[[ "$(grep -Fxc "$new_line" "$input_path")" -eq 0 ]]
[[ -d "$output_parent" && ! -L "$output_parent" ]]
[[ ! -e "$output_path" && ! -L "$output_path" ]]

pending_path=$(mktemp "$output_parent/.action17t-finalizer.pending.XXXXXX")
readonly pending_path
cleanup() {
    # shellcheck disable=SC2317
    rm -f -- "$pending_path"
}
trap cleanup EXIT

awk -v old="$old_line" -v new="$new_line" '
    $0 == old { print new; next }
    { print }
' "$input_path" >"$pending_path"
chmod 0755 "$pending_path"
[[ "$(file_hash "$pending_path")" = "$expected_output_sha256" ]]
[[ "$(grep -Fxc "$new_line" "$pending_path")" -eq 1 ]]
[[ "$(grep -Fxc "$old_line" "$pending_path")" -eq 0 ]]
bash -n "$pending_path"
mv -T -- "$pending_path" "$output_path"
trap - EXIT

printf 'action_17t_renderer_input_sha256=%s\n' "$expected_input_sha256"
printf 'action_17t_renderer_output_sha256=%s\n' "$expected_output_sha256"
printf 'action_17t_renderer_changed_line_count=1\n'
printf 'action_17t_renderer_complete=true\n'
