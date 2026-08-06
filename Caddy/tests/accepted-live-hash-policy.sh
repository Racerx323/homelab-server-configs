#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=accepted_live_hash_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly default_root=${test_directory%/Caddy/tests}
readonly repository_root=${CADDY_ACCEPTED_LIVE_HASH_ROOT:-$default_root}
readonly manifest=${CADDY_ACCEPTED_LIVE_HASH_MANIFEST:-$repository_root/Caddy/manifests/accepted-live-artifacts.tsv}
readonly registry=${CADDY_ACCEPTED_LIVE_HASH_REGISTRY:-$repository_root/Caddy/manifests/deployable-live-hash-consumers.tsv}

record_check() {
    local accepted_hash_policy_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$accepted_hash_policy_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$accepted_hash_policy_label" >&2
    return 1
}
regular_safe_file() {
    local accepted_hash_policy_path=$1

    [[ -f "$accepted_hash_policy_path" ]] || return 1
    [[ ! -L "$accepted_hash_policy_path" ]]
}
validate_manifest() {
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 3 { exit 1 }
        $1 !~ /^[a-z0-9_]+$/ { exit 1 }
        length($2) != 64 || $2 !~ /^[0-9a-f]+$/ { exit 1 }
        $3 !~ /^[A-Za-z0-9._-]+$/ { exit 1 }
        seen[$1]++ { exit 1 }
        END { if (length(seen) == 0) exit 1 }
    ' "$manifest"
}
validate_registry() {
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 3 { exit 1 }
        $1 !~ /^[a-z0-9_]+$/ { exit 1 }
        $2 !~ /^Caddy\/(scripts|tests)\/[A-Za-z0-9._-]+\.sh$/ { exit 1 }
        $3 !~ /^[a-z][a-z0-9_]*_sha256$/ { exit 1 }
        seen[$1 FS $2 FS $3]++ { exit 1 }
        END { if (length(seen) == 0) exit 1 }
    ' "$registry"
}
lookup_hash() {
    local accepted_hash_policy_key=$1

    awk -F '\t' -v key="$accepted_hash_policy_key" '
        $1 == key { print $2; found++ }
        END { if (found != 1) exit 1 }
    ' "$manifest"
}
validate_consumers() {
    local accepted_hash_policy_key
    local accepted_hash_policy_path
    local accepted_hash_policy_variable
    local accepted_hash_policy_hash
    local accepted_hash_policy_consumer

    while IFS=$'\t' read -r accepted_hash_policy_key accepted_hash_policy_path \
        accepted_hash_policy_variable; do
        [[ -n "$accepted_hash_policy_key" ]] || continue
        [[ "$accepted_hash_policy_key" != \#* ]] || continue
        accepted_hash_policy_hash=$(lookup_hash "$accepted_hash_policy_key") || return 1
        accepted_hash_policy_consumer=$repository_root/$accepted_hash_policy_path
        regular_safe_file "$accepted_hash_policy_consumer" || return 1
        [[ "$(grep -Fxc \
            "readonly $accepted_hash_policy_variable=$accepted_hash_policy_hash" \
            "$accepted_hash_policy_consumer")" -eq 1 ]] || return 1
    done <"$registry"
}

case "${1:-}" in
    --check)
        [[ $# -ge 1 ]] || exit 64
        record_check manifest_regular regular_safe_file "$manifest" || exit 1
        record_check registry_regular regular_safe_file "$registry" || exit 1
        record_check manifest_contract validate_manifest || exit 1
        record_check registry_contract validate_registry || exit 1
        record_check registered_consumers_current validate_consumers || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check [IGNORED-PRE-COMMIT-PATH ...]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
