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
readonly inventory=${CADDY_PRODUCTION_ARTIFACT_INVENTORY:-$repository_root/Caddy/manifests/production-artifacts.tsv}
readonly lifecycle=${CADDY_MANIFEST_LIFECYCLE:-$repository_root/Caddy/manifests/manifest-lifecycle.tsv}

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
validate_inventory_implementation() {
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 9 { exit 1 }
        $1 !~ /^[a-z0-9_]+$/ { exit 1 }
        $2 !~ /^(homelab-server-configs|homelab-dns|runtime-generated)$/ { exit 1 }
        $3 != "-" && $3 !~ /^[A-Za-z0-9._@/-]+$/ { exit 1 }
        $3 ~ /(^|\/)\.\.?(\/|$)/ { exit 1 }
        $4 !~ /^\/[A-Za-z0-9._@/-]+$/ { exit 1 }
        $4 ~ /(^|\/)\.\.?(\/|$)/ { exit 1 }
        $5 !~ /^(node-a|node-b|both)$/ { exit 1 }
        $6 != "-" && (length($6) != 64 || $6 !~ /^[0-9a-f]+$/) { exit 1 }
        length($7) != 64 || $7 !~ /^[0-9a-f]+$/ { exit 1 }
        $8 !~ /^[A-Za-z0-9._-]+$/ { exit 1 }
        $9 != "production-current" { exit 1 }
        $2 == "runtime-generated" && ($3 != "-" || $6 != "-") { exit 1 }
        $2 != "runtime-generated" && ($3 == "-" || $6 == "-") { exit 1 }
        seen[$1]++ { exit 1 }
        END { if (length(seen) == 0) exit 1 }
    ' "$inventory" || return 1
    return 0
}
validate_inventory() {
    # conditional-validator-explicit-failures-begin
    validate_inventory_implementation || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_lifecycle_implementation() {
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 4 { exit 1 }
        $1 !~ /^Caddy\/manifests\/[A-Za-z0-9._-]+\.(yaml|tsv|md)$/ { exit 1 }
        $2 !~ /^(production-current|defined-unexecuted|accepted-executed-definition|failed-consumed|superseded|rejected|workstation-only|deferred)$/ { exit 1 }
        $3 !~ /^(yes|no)$/ { exit 1 }
        $3 == "yes" && $2 != "production-current" { exit 1 }
        $4 !~ /^Caddy\/[A-Za-z0-9._/-]+$/ { exit 1 }
        seen[$1]++ { exit 1 }
        END { if (length(seen) == 0) exit 1 }
    ' "$lifecycle" || return 1
    return 0
}
validate_lifecycle() {
    # conditional-validator-explicit-failures-begin
    validate_lifecycle_implementation || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_inventory_alignment_implementation() {
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        FNR == NR { accepted_hash[$1] = $2; accepted_action[$1] = $3; next }
        !($1 in accepted_hash) { exit 1 }
        accepted_hash[$1] != $7 || accepted_action[$1] != $8 { exit 1 }
        inventory_key[$1]++ { exit 1 }
        END {
            for (key in accepted_hash)
                if (!(key in inventory_key)) exit 1
        }
    ' "$manifest" "$inventory" || return 1
    return 0
}
validate_inventory_alignment() {
    # conditional-validator-explicit-failures-begin
    validate_inventory_alignment_implementation || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_inventory_sources_implementation() {
    local accepted_hash_policy_repository
    local accepted_hash_policy_source_path
    local accepted_hash_policy_source_hash
    local accepted_hash_policy_source

    while IFS=$'\t' read -r accepted_hash_policy_repository \
        accepted_hash_policy_source_path accepted_hash_policy_source_hash; do
        [[ "$accepted_hash_policy_repository" = homelab-server-configs ]] || continue
        accepted_hash_policy_source=$repository_root/$accepted_hash_policy_source_path
        regular_safe_file "$accepted_hash_policy_source" || return 1
        [[ "$(sha256sum "$accepted_hash_policy_source" | awk '{ print $1 }')" = "$accepted_hash_policy_source_hash" ]] || return 1
    done < <(awk -F '\t' '!/^[[:space:]]*(#|$)/ { print $2 FS $3 FS $6 }' "$inventory")
    return 0
}
validate_inventory_sources() {
    # conditional-validator-explicit-failures-begin
    validate_inventory_sources_implementation || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_lifecycle_completeness_implementation() {
    diff -u \
        <(find "$repository_root/Caddy/manifests" -maxdepth 1 -type f \
            -printf 'Caddy/manifests/%f\n' | LC_ALL=C sort) \
        <(awk -F '\t' '!/^[[:space:]]*(#|$)/ { print $1 }' "$lifecycle" | LC_ALL=C sort) \
        >/dev/null || return 1
    return 0
}
validate_lifecycle_completeness() {
    # conditional-validator-explicit-failures-begin
    validate_lifecycle_completeness_implementation || return 1
    # conditional-validator-explicit-failures-end
    return 0
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
        record_check inventory_regular regular_safe_file "$inventory" || exit 1
        record_check lifecycle_regular regular_safe_file "$lifecycle" || exit 1
        record_check manifest_contract validate_manifest || exit 1
        record_check registry_contract validate_registry || exit 1
        record_check inventory_contract validate_inventory || exit 1
        record_check lifecycle_contract validate_lifecycle || exit 1
        record_check inventory_complete validate_inventory_alignment || exit 1
        record_check inventory_sources_current validate_inventory_sources || exit 1
        record_check lifecycle_complete validate_lifecycle_completeness || exit 1
        record_check registered_consumers_current validate_consumers || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check [IGNORED-PRE-COMMIT-PATH ...]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
