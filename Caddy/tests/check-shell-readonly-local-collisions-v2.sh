#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root

declaration_names() {
    local declaration_kind=$1
    local source_path=$2

    awk -v kind="$declaration_kind" '
        function emit_names(text, count, fields, field_index, name) {
            count = split(text, fields, /[[:space:]]+/)
            for (field_index = 1; field_index <= count; field_index++) {
                name = fields[field_index]
                if (name ~ /^-[A-Za-z]+$/) {
                    continue
                }
                sub(/=.*/, "", name)
                if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
                    print name
                }
            }
        }
        kind == "readonly" && /^[[:space:]]*readonly[[:space:]]/ {
            text = $0
            sub(/^[[:space:]]*readonly[[:space:]]+/, "", text)
            emit_names(text)
        }
        kind == "local" && /^[[:space:]]+local[[:space:]]/ {
            text = $0
            sub(/^[[:space:]]+local[[:space:]]+/, "", text)
            emit_names(text)
        }
    ' "$source_path" | LC_ALL=C sort -u
}

collision_count=0
if (($#)); then
    source_paths=("$@")
else
    mapfile -d '' -t source_paths < <(
        find "$caddy_root/scripts" "$caddy_root/tests" \
            -type f -name '*.sh' -print0 | LC_ALL=C sort -z
    )
fi
for source_path in "${source_paths[@]}"; do
    relative_path=${source_path#"$caddy_root/"}
    readonly_names=$(declaration_names readonly "$source_path")
    local_names=$(declaration_names local "$source_path")
    while IFS= read -r variable_name; do
        [[ -n "$variable_name" ]] || continue
        printf 'readonly_local_collision=%s|%s\n' \
            "$relative_path" "$variable_name" >&2
        ((collision_count += 1))
    done < <(
        comm -12 \
            <(printf '%s\n' "$readonly_names") \
            <(printf '%s\n' "$local_names")
    )
done

printf 'readonly_local_collision_count=%s\n' "$collision_count"
[[ "$collision_count" -eq 0 ]]
printf 'shell_readonly_local_collision_policy_v2_complete=true\n'
