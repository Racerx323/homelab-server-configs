#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_d
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly release_manifest_sha256=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly payload_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly registry_sha256=9a3abce23f57bb17b4ff1415b28846c9792229f53d99a0b73a3a9a81033886f9
readonly action28e_c_outer_sha256=edc88d827a9bdd60a62832d452ac5508c0a1ae2f35f14740bdd5c4bf7d5e8230
readonly action28e_c_manifest_sha256=47ff366203ad28fe4e5f4f63a3d6f2e02282e6f7fe19bd802177a41831bd0256

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly registry=$caddy_root/manifests/protocol-v2-historical-identities-action28e-d.tsv
readonly action28e_c_outer=$script_directory/run-dual-node-historical-release-manifest-action28e-c-outer.sh
readonly action28e_c_manifest=$caddy_root/manifests/protocol-v2-historical-release-manifest-action28e-c.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
record_check() {
    local action28e_d_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_d_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_d_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action28e_d_label" >&2
    return 1
}
regular_not_symlink() {
    [[ -f "$1" && ! -L "$1" ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]
            ;;
        *) return 1 ;;
    esac
}
validate_registry_contract() {
    local action28e_d_registry=$1

    awk -F '\t' \
        -v revision="$revision" \
        -v release_hash="$release_manifest_sha256" \
        -v payload_hash="$payload_manifest_sha256" '
        BEGIN { expected_header = "# revision\tidentity-kind\trelative-path\tsha256\taccepted-action" }
        NR == 1 { if ($0 != expected_header) bad = 1; next }
        {
            if (NF != 5 || $1 != revision || $5 != "28e-c") bad = 1
            if (length($4) != 64 || $4 !~ /^[0-9a-f]+$/) bad = 1
            key = $2 SUBSEP $3
            if (seen[key]++) bad = 1
            if ($2 == "release_manifest" && $3 == "release-manifest.json" && $4 == release_hash) release++
            else if ($2 == "payload_manifest" && $3 == "manifest.sha256" && $4 == payload_hash) payload++
            else bad = 1
            rows++
        }
        END { exit !(bad == 0 && rows == 2 && release == 1 && payload == 1) }
    ' "$action28e_d_registry"
}
lookup_identity() {
    local action28e_d_registry=$1
    local action28e_d_kind=$2
    local action28e_d_path=$3

    awk -F '\t' -v kind="$action28e_d_kind" -v path="$action28e_d_path" '
        $2 == kind && $3 == path { print $4; found++ }
        END { if (found != 1) exit 1 }
    ' "$action28e_d_registry"
}
validate_mapping() {
    local action28e_d_registry=$1
    local action28e_d_release_observed
    local action28e_d_payload_observed

    action28e_d_release_observed=$(lookup_identity "$action28e_d_registry" \
        release_manifest release-manifest.json) || return 1
    action28e_d_payload_observed=$(lookup_identity "$action28e_d_registry" \
        payload_manifest manifest.sha256) || return 1
    printf '%s_value_release_manifest_expected_sha256=%s\n' "$prefix" "$release_manifest_sha256"
    printf '%s_value_release_manifest_observed_sha256=%s\n' "$prefix" "$action28e_d_release_observed"
    printf '%s_value_payload_manifest_expected_sha256=%s\n' "$prefix" "$payload_manifest_sha256"
    printf '%s_value_payload_manifest_observed_sha256=%s\n' "$prefix" "$action28e_d_payload_observed"
    record_check registry_contract validate_registry_contract "$action28e_d_registry" || return 1
    record_check release_manifest_hash_valid valid_sha256 "$action28e_d_release_observed" || return 1
    record_check payload_manifest_hash_valid valid_sha256 "$action28e_d_payload_observed" || return 1
    record_check release_manifest_identity_exact test \
        "$action28e_d_release_observed" = "$release_manifest_sha256" || return 1
    record_check payload_manifest_identity_exact test \
        "$action28e_d_payload_observed" = "$payload_manifest_sha256" || return 1
    record_check identity_hashes_distinct test \
        "$action28e_d_release_observed" != "$action28e_d_payload_observed" || return 1
}
validate_repository() {
    record_check working_directory working_directory_approved || return 1
    record_check registry_regular regular_not_symlink "$registry" || return 1
    record_check registry_hash test "$(file_hash "$registry")" = "$registry_sha256" || return 1
    record_check action28e_c_outer_regular regular_not_symlink "$action28e_c_outer" || return 1
    record_check action28e_c_outer_immutable test \
        "$(file_hash "$action28e_c_outer")" = "$action28e_c_outer_sha256" || return 1
    record_check action28e_c_manifest_regular regular_not_symlink "$action28e_c_manifest" || return 1
    record_check action28e_c_manifest_immutable test \
        "$(file_hash "$action28e_c_manifest")" = "$action28e_c_manifest_sha256" || return 1
    record_check evidence_release_manifest_exact grep -Fqx \
        "  observed_node_b_manifest_sha256: $release_manifest_sha256" "$action28e_c_manifest" || return 1
    record_check evidence_payload_manifest_exact grep -Fqx \
        "  expected_manifest_sha256: $payload_manifest_sha256" "$action28e_c_manifest" || return 1
    validate_mapping "$registry" || return 1
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        validate_repository
        printf '%s_action_executed=false\n' "$prefix"
        ;;
    --test-registry)
        [[ $# -eq 2 && "${CADDY_ACTION28E_D_TEST_MODE:-}" == 1 ]]
        validate_mapping "$2"
        printf '%s_action_executed=false\n' "$prefix"
        ;;
    "")
        [[ $# -eq 0 ]]
        validate_repository
        printf '%s_action_executed=true\n' "$prefix"
        ;;
    *) exit 64 ;;
esac

printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
