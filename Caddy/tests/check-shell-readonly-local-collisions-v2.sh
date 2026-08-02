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

readonly -a allowed_legacy_collisions=(
    'scripts/diagnose-dns-path-authority-action17c-c-c.sh|work_dir|5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364'
    'scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh|resolv_target|908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d'
    'scripts/run-node-b-unbound-action17f-transition-diagnostic.sh|transcript|9abfa890b93b5bb3e8ac3f509cf27b9c391c137a56180202f99c8c90c3c88e5d'
    'scripts/run-node-b-unbound-action17f-transition-diagnostic.sh|work_dir|9abfa890b93b5bb3e8ac3f509cf27b9c391c137a56180202f99c8c90c3c88e5d'
    'scripts/run-node-b-unbound-local-zone-stage-action17f-retry.sh|rendered_runner|6dae2d4b5da2da62e92dc2e42400445905ba0f59692a6024748971472707c83b'
    'scripts/run-node-b-unbound-primary-stage-action17e-retry.sh|rendered_runner|5354fcd0fa5710ebef77f6751e4094903685d17056891760229c84b08868be92'
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

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

legacy_collision_allowed() {
    local relative_path=$1
    local variable_name=$2
    local source_hash=$3
    local record

    for record in "${allowed_legacy_collisions[@]}"; do
        [[ "$record" == "$relative_path|$variable_name|$source_hash" ]] &&
            return 0
    done
    return 1
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
    source_hash=$(file_hash "$source_path")
    readonly_names=$(declaration_names readonly "$source_path")
    local_names=$(declaration_names local "$source_path")
    while IFS= read -r variable_name; do
        [[ -n "$variable_name" ]] || continue
        if legacy_collision_allowed \
            "$relative_path" "$variable_name" "$source_hash"; then
            printf 'legacy_readonly_local_collision_allowed=%s|%s|%s\n' \
                "$relative_path" "$variable_name" "$source_hash"
            continue
        fi
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
