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
server_root=$(cd -- "$caddy_root/.." && pwd)
readonly server_root
workspace_root=$(cd -- "$server_root/.." && pwd)
readonly workspace_root
readonly local_zone_source="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_gitignore="$workspace_root/homelab-dns/.gitignore"
readonly historical_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly current_local_zone_sha256=e59624fdbb47e7e059177ea7ca86c39179a71e77fdcdbf640753cc73be44a23f
readonly expected_homeassistant_a='    local-data: "homeassistant.local.theama.co. IN A 10.1.2.120"'
readonly expected_homeassistant_ptr='    local-data-ptr: "10.1.2.120 homeassistant.local.theama.co."'
readonly -a historical_source_artifacts=(
    "db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6|$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh"
    "f5ef1077dc627c8e35248ce439f4c01e419d02b8e431412d66e762813755d825|$caddy_root/tests/action17c-c-c-dns-path-authority-regression.sh"
    "6e63289a54018514930ae883bb741b6993a9148c77c027b7b16c75cb875ae59d|$caddy_root/scripts/run-node-b-two-file-unbound-preflight-action17d.sh"
    "700097f301c49bfef34b60dc6fdeb4e8c0b03282f2ccf7831fa306a930fe7c33|$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
    "4849d4057405d996415c62e3f44998e145936697420327147cd269209d25ac60|$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
    "6dae2d4b5da2da62e92dc2e42400445905ba0f59692a6024748971472707c83b|$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-retry.sh"
    "7abff23f8227e2c059d02484eb83f28c9aabd11f6054d12caff7adf5496f1f1b|$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-normalized-retry.sh"
    "85e1c8404837f5e7d10a6924c8b86adbb119df2c87d1fbf8403c0f01c318ebd6|$caddy_root/scripts/run-node-a-two-file-unbound-preflight-action17h.sh"
    "b930166207e674ef97b7eebc7a2d5b0a88035aaa747205a474d999f54c5bb871|$caddy_root/scripts/run-node-a-unbound-semantic-diff-action17h-a.sh"
    "d13108ab496b2829e750c8a475225e5fdd448f9cf47bdaac8d96efecc53a00e6|$caddy_root/scripts/run-node-a-unbound-local-zone-stage-action17j.sh"
    "fb0015c718667ec0dea1a5362b9f94e43753b0d77cd7d2c7c3077634e370a8eb|$caddy_root/tests/action17j-node-a-unbound-local-zone-stage-regression.sh"
)
readonly -a historical_source_dependent_artifacts=(
    "9576d69475c2d170e57e51690e0023e4fee3f1d4341deee90d0366269f4e9708|$caddy_root/tests/action17h-node-a-two-file-unbound-preflight-regression.sh"
    "4063c66367c7aec45e1911dd72fc2540be4d96d8a966afdc88a98a1bd6066ec9|$caddy_root/tests/action17h-a-node-a-semantic-diff-regression.sh"
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assertion_failure_count=0

record_assertion() {
    local assertion_record_label=$1
    local assertion_record_status=$2

    printf 'action_17l_historical_assertion_%s=%s\n' \
        "$assertion_record_label" "$assertion_record_status"
    if [[ "$assertion_record_status" != true ]]; then
        assertion_failure_count=$((assertion_failure_count + 1))
    fi
}

run_regression() {
    local historical_artifact_index
    local historical_artifact_record
    local historical_artifact_expected_hash
    local historical_artifact_path
    local historical_artifact_observed_hash
    local observed_source_hash
    local observed_ignore_count
    local observed_homeassistant_a_count
    local observed_homeassistant_ptr_count
    local observed_homeassistant_ipv6_count

    if [[ -f "$local_zone_source" && ! -L "$local_zone_source" ]]; then
        record_assertion local_zone_source_regular true
        observed_source_hash=$(file_hash "$local_zone_source")
        observed_homeassistant_a_count=$(
            grep -Fxc "$expected_homeassistant_a" "$local_zone_source" || true
        )
        observed_homeassistant_ptr_count=$(
            grep -Fxc "$expected_homeassistant_ptr" "$local_zone_source" || true
        )
        observed_homeassistant_ipv6_count=$(
            grep -Ec \
                'homeassistant[.]local[.]theama[.]co[.].*IN AAAA|local-data-ptr:.*(2600:|fe80:).*homeassistant' \
                "$local_zone_source" || true
        )
    else
        record_assertion local_zone_source_regular false
        observed_source_hash=unavailable
        observed_homeassistant_a_count=-1
        observed_homeassistant_ptr_count=-1
        observed_homeassistant_ipv6_count=-1
    fi
    if [[ "$observed_source_hash" == "$current_local_zone_sha256" ]]; then
        record_assertion current_source_hash true
    else
        record_assertion current_source_hash false
    fi
    if [[ "$current_local_zone_sha256" != "$historical_local_zone_sha256" ]]; then
        record_assertion source_hash_advanced true
    else
        record_assertion source_hash_advanced false
    fi

    if [[ -f "$dns_gitignore" && ! -L "$dns_gitignore" ]]; then
        record_assertion dns_gitignore_regular true
        observed_ignore_count=$(
            grep -Fxc \
                'Unbound/configs/pihole0-local-zone.conf' "$dns_gitignore" ||
                true
        )
    else
        record_assertion dns_gitignore_regular false
        observed_ignore_count=-1
    fi
    if [[ "$observed_ignore_count" -eq 1 ]]; then
        record_assertion private_source_ignore_exact true
    else
        record_assertion private_source_ignore_exact false
    fi
    if [[ "$observed_homeassistant_a_count" -eq 1 ]]; then
        record_assertion homeassistant_a_exact true
    else
        record_assertion homeassistant_a_exact false
    fi
    if [[ "$observed_homeassistant_ptr_count" -eq 1 ]]; then
        record_assertion homeassistant_ptr_exact true
    else
        record_assertion homeassistant_ptr_exact false
    fi
    if [[ "$observed_homeassistant_ipv6_count" -eq 0 ]]; then
        record_assertion homeassistant_ipv6_absent true
    else
        record_assertion homeassistant_ipv6_absent false
    fi

    for historical_artifact_index in \
        "${!historical_source_artifacts[@]}"; do
        historical_artifact_record=${historical_source_artifacts[$historical_artifact_index]}
        historical_artifact_expected_hash=${historical_artifact_record%%|*}
        historical_artifact_path=${historical_artifact_record#*|}
        if [[ -f "$historical_artifact_path" &&
            ! -L "$historical_artifact_path" ]]; then
            record_assertion \
                "historical_artifact_${historical_artifact_index}_regular" true
            historical_artifact_observed_hash=$(
                file_hash "$historical_artifact_path"
            )
        else
            record_assertion \
                "historical_artifact_${historical_artifact_index}_regular" false
            historical_artifact_observed_hash=unavailable
        fi
        if [[ "$historical_artifact_observed_hash" == "$historical_artifact_expected_hash" ]]; then
            record_assertion \
                "historical_artifact_${historical_artifact_index}_hash" true
        else
            record_assertion \
                "historical_artifact_${historical_artifact_index}_hash" false
        fi
        if grep -Fq \
            "$historical_local_zone_sha256" "$historical_artifact_path" \
            2>/dev/null; then
            record_assertion \
                "historical_artifact_${historical_artifact_index}_pin" true
        else
            record_assertion \
                "historical_artifact_${historical_artifact_index}_pin" false
        fi
    done
    for historical_artifact_index in \
        "${!historical_source_dependent_artifacts[@]}"; do
        historical_artifact_record=${historical_source_dependent_artifacts[$historical_artifact_index]}
        historical_artifact_expected_hash=${historical_artifact_record%%|*}
        historical_artifact_path=${historical_artifact_record#*|}
        if [[ -f "$historical_artifact_path" &&
            ! -L "$historical_artifact_path" ]]; then
            record_assertion \
                "historical_dependent_${historical_artifact_index}_regular" true
            historical_artifact_observed_hash=$(
                file_hash "$historical_artifact_path"
            )
        else
            record_assertion \
                "historical_dependent_${historical_artifact_index}_regular" false
            historical_artifact_observed_hash=unavailable
        fi
        if [[ "$historical_artifact_observed_hash" == "$historical_artifact_expected_hash" ]]; then
            record_assertion \
                "historical_dependent_${historical_artifact_index}_hash" true
        else
            record_assertion \
                "historical_dependent_${historical_artifact_index}_hash" false
        fi
    done

    if [[ "$assertion_failure_count" -eq 0 ]]; then
        printf '%s\n' \
            action_17l_historical_source_regression_complete=true \
            action_17l_historical_unbound_source_advance_valid=true \
            action_17l_historical_runner_mutations=false \
            action_17l_live_node_connections=false \
            action_17l_historical_failed_assertion_count=0
        return 0
    fi
    printf '%s\n' \
        action_17l_historical_source_regression_complete=true \
        action_17l_historical_unbound_source_advance_valid=false \
        action_17l_historical_runner_mutations=false \
        action_17l_live_node_connections=false \
        "action_17l_historical_failed_assertion_count=$assertion_failure_count"
    return 1
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
