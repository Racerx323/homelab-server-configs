#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_17s
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly source_root=/var/lib/caddy-sync/incoming/node-a
readonly release="$source_root/$revision"
readonly request_marker="$release/.finalize-request"
readonly pending_marker="$release/.complete.pending"
readonly complete_marker="$release/.complete"
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly rollback_root=/var/backups/caddy-ha
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly -a continuity_units=(
    caddy.service
    lighttpd.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a continuity_common_properties=(
    ActiveState
    SubState
)
readonly -a continuity_service_properties=(
    MainPID
    NRestarts
)

declare -A service_state_before=()
assertion_count=0
failed_assertion_count=0
first_failure=none
mutation_started=false
transaction_complete=false
rollback_directory=
work_directory=

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_check() {
    local check_label=$1

    shift
    assertion_count=$((assertion_count + 1))
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    failed_assertion_count=$((failed_assertion_count + 1))
    if [[ "$first_failure" == none ]]; then
        first_failure=$check_label
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

payload_digest() {
    (
        cd "$release"
        find . -type f \
            ! -name .complete \
            ! -name .complete.pending \
            ! -name .finalize-request \
            -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

manifest_hashes_valid() {
    (
        cd "$release"
        sha256sum --strict --check manifest.sha256 >/dev/null
    )
}

release_entries_snapshot() {
    (
        cd "$release"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f \
            ! -name .complete \
            ! -name .complete.pending \
            ! -name .finalize-request \
            -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    )
}

expected_check_labels() {
    local expected_property
    local expected_property_label
    local expected_service_property
    local expected_service_property_label
    local expected_unit
    local expected_unit_label

    printf '%s\n' \
        identity_root \
        working_directory_root \
        hostname_node_b \
        architecture_arm64 \
        finalizer_regular \
        finalizer_not_symlink \
        finalizer_metadata \
        finalizer_hash_exact \
        finalizer_syntax \
        caddy_sync_identity_exact \
        source_root_directory \
        source_root_not_symlink \
        source_root_metadata \
        incoming_only_node_a \
        source_root_only_expected_release \
        release_directory \
        release_not_symlink \
        release_realpath_exact \
        release_metadata \
        release_manifest_regular \
        release_manifest_not_symlink \
        hash_manifest_regular \
        hash_manifest_not_symlink \
        manifest_revision_exact \
        manifest_parent_exact \
        manifest_source_exact \
        manifest_hash_exact \
        manifest_hashes_valid \
        payload_symlinks_absent \
        payload_special_files_absent \
        payload_hardlinks_absent \
        nested_control_files_absent \
        release_directories_locked \
        release_files_locked \
        complete_absent \
        complete_not_symlink \
        pending_absent \
        pending_not_symlink \
        request_absent \
        request_not_symlink \
        payload_hash_exact \
        release_not_writable_by_sync \
        current_link_exact \
        current_target_exact \
        caddy_active \
        lighttpd_active \
        lsyncd_inactive \
        lsyncd_masked \
        caddy_lsyncd_inactive \
        caddy_lsyncd_disabled \
        reconcile_path_inactive \
        reconcile_service_inactive \
        lsyncd_configuration_absent \
        lsyncd_configuration_not_symlink \
        action17s_backup_count_zero
    for expected_unit in "${continuity_units[@]}"; do
        expected_unit_label=${expected_unit//[-.]/_}
        for expected_property in "${continuity_common_properties[@]}"; do
            expected_property_label=${expected_property,,}
            printf 'pre_%s_%s_observed\n' \
                "$expected_unit_label" "$expected_property_label"
        done
        if [[ "$expected_unit" == *.service ]]; then
            for expected_service_property in \
                "${continuity_service_properties[@]}"; do
                expected_service_property_label=${expected_service_property,,}
                printf 'pre_%s_%s_observed\n' \
                    "$expected_unit_label" "$expected_service_property_label"
            done
        fi
        printf 'pre_%s_unit_file_state_observed\n' "$expected_unit_label"
    done
    printf '%s\n' \
        rollback_directory_regular \
        rollback_directory_not_symlink \
        rollback_directory_metadata \
        rollback_snapshot_regular \
        rollback_snapshot_not_symlink \
        rollback_snapshot_metadata \
        rollback_snapshot_hash_record_regular \
        rollback_snapshot_hash_record_not_symlink \
        rollback_snapshot_hash_record_metadata \
        rollback_snapshot_hash_record_exact \
        request_regular \
        request_not_symlink_after \
        request_empty \
        request_metadata \
        complete_regular \
        complete_not_symlink_after \
        complete_empty \
        complete_metadata \
        pending_absent_after \
        pending_not_symlink_after \
        finalizer_stdout_empty \
        finalizer_stderr_empty \
        release_directories_relocked \
        release_files_relocked \
        payload_hash_unchanged \
        manifest_hash_unchanged \
        manifest_hashes_still_valid \
        source_root_still_only_expected_release \
        current_link_unchanged \
        current_target_unchanged \
        lsyncd_configuration_still_absent \
        release_not_writable_after
    for expected_unit in "${continuity_units[@]}"; do
        expected_unit_label=${expected_unit//[-.]/_}
        for expected_property in "${continuity_common_properties[@]}"; do
            expected_property_label=${expected_property,,}
            printf 'post_%s_%s_unchanged\n' \
                "$expected_unit_label" "$expected_property_label"
        done
        if [[ "$expected_unit" == *.service ]]; then
            for expected_service_property in \
                "${continuity_service_properties[@]}"; do
                expected_service_property_label=${expected_service_property,,}
                printf 'post_%s_%s_unchanged\n' \
                    "$expected_unit_label" "$expected_service_property_label"
            done
        fi
        printf 'post_%s_unit_file_state_unchanged\n' "$expected_unit_label"
    done
}

expected_rollback_check_labels() {
    local rollback_property
    local rollback_property_label
    local rollback_service_property
    local rollback_service_property_label
    local rollback_unit
    local rollback_unit_label

    printf '%s\n' \
        release_directory \
        release_not_symlink \
        request_absent \
        request_not_symlink \
        pending_absent \
        pending_not_symlink \
        complete_absent \
        complete_not_symlink \
        directories_locked \
        files_locked \
        payload_hash_exact \
        manifest_hash_exact \
        manifest_hashes_valid \
        current_link_exact \
        current_target_exact \
        lsyncd_configuration_absent
    for rollback_unit in "${continuity_units[@]}"; do
        rollback_unit_label=${rollback_unit//[-.]/_}
        for rollback_property in "${continuity_common_properties[@]}"; do
            rollback_property_label=${rollback_property,,}
            printf '%s_%s_unchanged\n' \
                "$rollback_unit_label" "$rollback_property_label"
        done
        if [[ "$rollback_unit" == *.service ]]; then
            for rollback_service_property in \
                "${continuity_service_properties[@]}"; do
                rollback_service_property_label=${rollback_service_property,,}
                printf '%s_%s_unchanged\n' \
                    "$rollback_unit_label" "$rollback_service_property_label"
            done
        fi
        printf '%s_unit_file_state_unchanged\n' "$rollback_unit_label"
    done
    printf '%s\n' \
        backup_absent \
        work_directory_absent
}

rollback_require() {
    local rollback_label=$1

    shift
    if "$@"; then
        printf '%s_rollback_assertion_%s=true\n' \
            "$prefix" "$rollback_label" >&2
        return 0
    fi
    printf '%s_rollback_assertion_%s=false\n' \
        "$prefix" "$rollback_label" >&2
    return 1
}

capture_service_state() {
    local observed_property
    local observed_property_label
    local observed_service_property
    local observed_service_property_label
    local observed_unit
    local observed_unit_label
    local observed_value

    for observed_unit in "${continuity_units[@]}"; do
        observed_unit_label=${observed_unit//[-.]/_}
        for observed_property in "${continuity_common_properties[@]}"; do
            observed_property_label=${observed_property,,}
            observed_value=$(
                systemctl show "$observed_unit" --no-pager \
                    --property "$observed_property" --value
            )
            require_check \
                "pre_${observed_unit_label}_${observed_property_label}_observed" \
                test -n "$observed_value"
            service_state_before["$observed_unit:$observed_property"]=$observed_value
        done
        if [[ "$observed_unit" == *.service ]]; then
            for observed_service_property in \
                "${continuity_service_properties[@]}"; do
                observed_service_property_label=${observed_service_property,,}
                observed_value=$(
                    systemctl show "$observed_unit" --no-pager \
                        --property "$observed_service_property" --value
                )
                require_check \
                    "pre_${observed_unit_label}_${observed_service_property_label}_observed" \
                    test -n "$observed_value"
                service_state_before["$observed_unit:$observed_service_property"]=$observed_value
            done
        fi
        observed_value=$(systemctl is-enabled "$observed_unit" 2>/dev/null || true)
        require_check "pre_${observed_unit_label}_unit_file_state_observed" \
            test -n "$observed_value"
        service_state_before["$observed_unit:UnitFileState"]=$observed_value
    done
}

validate_service_continuity() {
    local current_property
    local current_property_label
    local current_service_property
    local current_service_property_label
    local current_unit
    local current_unit_label
    local current_value

    for current_unit in "${continuity_units[@]}"; do
        current_unit_label=${current_unit//[-.]/_}
        for current_property in "${continuity_common_properties[@]}"; do
            current_property_label=${current_property,,}
            current_value=$(
                systemctl show "$current_unit" --no-pager \
                    --property "$current_property" --value
            )
            require_check \
                "post_${current_unit_label}_${current_property_label}_unchanged" \
                test "$current_value" = \
                "${service_state_before["$current_unit:$current_property"]}"
        done
        if [[ "$current_unit" == *.service ]]; then
            for current_service_property in \
                "${continuity_service_properties[@]}"; do
                current_service_property_label=${current_service_property,,}
                current_value=$(
                    systemctl show "$current_unit" --no-pager \
                        --property "$current_service_property" --value
                )
                require_check \
                    "post_${current_unit_label}_${current_service_property_label}_unchanged" \
                    test "$current_value" = \
                    "${service_state_before["$current_unit:$current_service_property"]}"
            done
        fi
        current_value=$(systemctl is-enabled "$current_unit" 2>/dev/null || true)
        require_check "post_${current_unit_label}_unit_file_state_unchanged" \
            test "$current_value" = \
            "${service_state_before["$current_unit:UnitFileState"]}"
    done
}

validate_prestate() {
    local backup_count

    require_check identity_root test "$(id -u)" -eq 0
    require_check working_directory_root test "$(pwd -P)" = /
    require_check hostname_node_b test "$(hostname)" = j1-svpihole00
    require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64
    require_check finalizer_regular test -f "$finalizer"
    require_check finalizer_not_symlink test ! -L "$finalizer"
    require_check finalizer_metadata \
        test "$(stat -c '%U:%G:%a' "$finalizer")" = root:root:755
    require_check finalizer_hash_exact \
        test "$(file_hash "$finalizer")" = "$expected_finalizer_sha256"
    require_check finalizer_syntax bash -n "$finalizer"
    require_check caddy_sync_identity_exact \
        test "$(id -un caddy-sync)" = caddy-sync
    require_check source_root_directory test -d "$source_root"
    require_check source_root_not_symlink test ! -L "$source_root"
    require_check source_root_metadata \
        test "$(stat -c '%U:%G:%a' "$source_root")" = caddy-sync:caddy-sync:750
    require_check incoming_only_node_a \
        test "$(find /var/lib/caddy-sync/incoming -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C sort)" = node-a
    require_check source_root_only_expected_release \
        test "$(find "$source_root" -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C sort)" = "$revision"
    require_check release_directory test -d "$release"
    require_check release_not_symlink test ! -L "$release"
    require_check release_realpath_exact \
        test "$(readlink -e "$release")" = "$release"
    require_check release_metadata \
        test "$(stat -c '%U:%G:%a' "$release")" = caddy-sync:caddy-sync:550
    require_check release_manifest_regular test -f "$release/release-manifest.json"
    require_check release_manifest_not_symlink \
        test ! -L "$release/release-manifest.json"
    require_check hash_manifest_regular test -f "$release/manifest.sha256"
    require_check hash_manifest_not_symlink test ! -L "$release/manifest.sha256"
    require_check manifest_revision_exact \
        test "$(jq -r '.revision // empty' "$release/release-manifest.json")" = \
        "$revision"
    require_check manifest_parent_exact \
        test "$(jq -r '.parent_revision // empty' "$release/release-manifest.json")" = \
        "$parent_revision"
    require_check manifest_source_exact \
        test "$(jq -r '.source_node // empty' "$release/release-manifest.json")" = \
        node-a
    require_check manifest_hash_exact \
        test "$(file_hash "$release/manifest.sha256")" = \
        "$expected_manifest_sha256"
    require_check manifest_hashes_valid manifest_hashes_valid
    require_check payload_symlinks_absent \
        test -z "$(find "$release" -type l -print -quit)"
    require_check payload_special_files_absent \
        test -z "$(find "$release" ! -type d ! -type f -print -quit)"
    require_check payload_hardlinks_absent \
        test -z "$(find "$release" -type f -links +1 -print -quit)"
    require_check nested_control_files_absent \
        test -z "$(find "$release" -mindepth 2 \
            \( -name .complete -o -name .complete.pending \
            -o -name .finalize-request -o -name manifest.sha256 \) \
            -print -quit)"
    require_check release_directories_locked \
        test -z "$(find "$release" -type d ! -perm 0550 -print -quit)"
    require_check release_files_locked \
        test -z "$(find "$release" -type f ! -perm 0440 -print -quit)"
    require_check complete_absent test ! -e "$complete_marker"
    require_check complete_not_symlink test ! -L "$complete_marker"
    require_check pending_absent test ! -e "$pending_marker"
    require_check pending_not_symlink test ! -L "$pending_marker"
    require_check request_absent test ! -e "$request_marker"
    require_check request_not_symlink test ! -L "$request_marker"
    require_check payload_hash_exact \
        test "$(payload_digest)" = "$expected_payload_sha256"
    require_check release_not_writable_by_sync \
        runuser -u caddy-sync -- test ! -w "$release"
    require_check current_link_exact \
        test "$(readlink /etc/caddy/current)" = "$expected_active_release"
    require_check current_target_exact \
        test "$(readlink -e /etc/caddy/current)" = "$expected_active_release"
    require_check caddy_active \
        test "$(systemctl is-active caddy.service)" = active
    require_check lighttpd_active \
        test "$(systemctl is-active lighttpd.service)" = active
    require_check lsyncd_inactive \
        test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
    require_check lsyncd_masked \
        test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
    require_check caddy_lsyncd_inactive \
        test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
    require_check caddy_lsyncd_disabled \
        test "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = disabled
    require_check reconcile_path_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
    require_check reconcile_service_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
    require_check lsyncd_configuration_absent test ! -e "$lsyncd_config"
    require_check lsyncd_configuration_not_symlink test ! -L "$lsyncd_config"
    backup_count=$(
        find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action17s-node-b-marker-migration.*' -printf '.' 2>/dev/null |
            wc -c
    )
    require_check action17s_backup_count_zero test "$backup_count" -eq 0
}

rollback() {
    local rollback_property
    local rollback_property_label
    local rollback_service_property
    local rollback_service_property_label
    local rollback_unit
    local rollback_unit_label
    local rollback_value
    local original_status=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi
    set +e
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ "$mutation_started" == true && -d "$release" && ! -L "$release" ]]; then
        chmod 0750 "$release" || rollback_failed=true
        rm -f -- "$request_marker" "$pending_marker" "$complete_marker" ||
            rollback_failed=true
        find "$release" -type d -exec chmod 0550 {} + || rollback_failed=true
        find "$release" -type f -exec chmod 0440 {} + || rollback_failed=true
    fi
    rollback_require release_directory test -d "$release" || rollback_failed=true
    rollback_require release_not_symlink test ! -L "$release" ||
        rollback_failed=true
    rollback_require request_absent test ! -e "$request_marker" ||
        rollback_failed=true
    rollback_require request_not_symlink test ! -L "$request_marker" ||
        rollback_failed=true
    rollback_require pending_absent test ! -e "$pending_marker" ||
        rollback_failed=true
    rollback_require pending_not_symlink test ! -L "$pending_marker" ||
        rollback_failed=true
    rollback_require complete_absent test ! -e "$complete_marker" ||
        rollback_failed=true
    rollback_require complete_not_symlink test ! -L "$complete_marker" ||
        rollback_failed=true
    rollback_require directories_locked \
        test -z "$(find "$release" -type d ! -perm 0550 -print -quit)" ||
        rollback_failed=true
    rollback_require files_locked \
        test -z "$(find "$release" -type f ! -perm 0440 -print -quit)" ||
        rollback_failed=true
    rollback_require payload_hash_exact \
        test "$(payload_digest)" = "$expected_payload_sha256" ||
        rollback_failed=true
    rollback_require manifest_hash_exact \
        test "$(file_hash "$release/manifest.sha256")" = \
        "$expected_manifest_sha256" || rollback_failed=true
    rollback_require manifest_hashes_valid manifest_hashes_valid ||
        rollback_failed=true
    rollback_require current_link_exact \
        test "$(readlink /etc/caddy/current)" = "$expected_active_release" ||
        rollback_failed=true
    rollback_require current_target_exact \
        test "$(readlink -e /etc/caddy/current)" = "$expected_active_release" ||
        rollback_failed=true
    rollback_require lsyncd_configuration_absent test ! -e "$lsyncd_config" ||
        rollback_failed=true
    for rollback_unit in "${continuity_units[@]}"; do
        rollback_unit_label=${rollback_unit//[-.]/_}
        for rollback_property in "${continuity_common_properties[@]}"; do
            rollback_property_label=${rollback_property,,}
            rollback_value=$(
                systemctl show "$rollback_unit" --no-pager \
                    --property "$rollback_property" --value
            )
            rollback_require \
                "${rollback_unit_label}_${rollback_property_label}_unchanged" \
                test "$rollback_value" = \
                "${service_state_before["$rollback_unit:$rollback_property"]}" ||
                rollback_failed=true
        done
        if [[ "$rollback_unit" == *.service ]]; then
            for rollback_service_property in \
                "${continuity_service_properties[@]}"; do
                rollback_service_property_label=${rollback_service_property,,}
                rollback_value=$(
                    systemctl show "$rollback_unit" --no-pager \
                        --property "$rollback_service_property" --value
                )
                rollback_require \
                    "${rollback_unit_label}_${rollback_service_property_label}_unchanged" \
                    test "$rollback_value" = \
                    "${service_state_before["$rollback_unit:$rollback_service_property"]}" ||
                    rollback_failed=true
            done
        fi
        rollback_value=$(systemctl is-enabled "$rollback_unit" 2>/dev/null || true)
        rollback_require "${rollback_unit_label}_unit_file_state_unchanged" \
            test "$rollback_value" = \
            "${service_state_before["$rollback_unit:UnitFileState"]}" ||
            rollback_failed=true
    done
    if [[ -n "$rollback_directory" &&
        (-e "$rollback_directory" || -L "$rollback_directory") ]]; then
        if [[ -d "$rollback_directory" && ! -L "$rollback_directory" ]]; then
            rm -rf -- "$rollback_directory" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    rollback_require backup_absent \
        test ! -e "$rollback_directory" || rollback_failed=true
    if [[ -n "$work_directory" &&
        (-e "$work_directory" || -L "$work_directory") ]]; then
        if [[ -d "$work_directory" && ! -L "$work_directory" ]]; then
            rm -rf -- "$work_directory" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    rollback_require work_directory_absent \
        test ! -e "$work_directory" || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$original_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$revision" = action17p-node-a-to-node-b-bootstrap ]]
        [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_payload_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
        if ! expected_check_labels | awk '
            $0 !~ /^[a-z0-9_]+$/ { bad = 1 }
            END { exit bad ? 1 : 0 }
        '; then
            exit 1
        fi
        [[ "$(expected_check_labels | wc -l)" -gt 100 ]]
        [[ "$(expected_check_labels | LC_ALL=C sort -u | wc -l)" = "$(expected_check_labels | wc -l)" ]]
        if ! expected_rollback_check_labels | awk '
            $0 !~ /^[a-z0-9_]+$/ { bad = 1 }
            END { exit bad ? 1 : 0 }
        '; then
            exit 1
        fi
        [[ "$(expected_rollback_check_labels | wc -l)" -gt 40 ]]
        [[ "$(expected_rollback_check_labels | LC_ALL=C sort -u | wc -l)" = "$(expected_rollback_check_labels | wc -l)" ]]
        printf '%s_transaction_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_check_labels
        exit 0
        ;;
    --expected-rollback-checks)
        [[ $# -eq 1 ]]
        expected_rollback_check_labels
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--expected-checks|--expected-rollback-checks]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

validate_prestate
capture_service_state
work_directory=$(mktemp -d /run/caddy-action17s-node-b.XXXXXX)
readonly work_directory
readonly before_snapshot="$work_directory/release.before"
readonly finalizer_output="$work_directory/finalizer.out"
readonly finalizer_error="$work_directory/finalizer.err"
release_entries_snapshot >"$before_snapshot"
before_snapshot_sha256=$(file_hash "$before_snapshot")
readonly before_snapshot_sha256
printf '%s_preflight_complete=true\n' "$prefix"

trap rollback EXIT
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
install -d -o root -g root -m 0700 "$rollback_root"
rollback_directory=$(
    mktemp -d "$rollback_root/action17s-node-b-marker-migration.XXXXXX"
)
chmod 0700 "$rollback_directory"
install -o root -g root -m 0600 \
    "$before_snapshot" "$rollback_directory/release.before"
printf '%s\n' "$before_snapshot_sha256" \
    >"$rollback_directory/release.before.sha256"
chmod 0600 "$rollback_directory/release.before.sha256"

require_check rollback_directory_regular test -d "$rollback_directory"
require_check rollback_directory_not_symlink test ! -L "$rollback_directory"
require_check rollback_directory_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700
require_check rollback_snapshot_regular \
    test -f "$rollback_directory/release.before"
require_check rollback_snapshot_not_symlink \
    test ! -L "$rollback_directory/release.before"
require_check rollback_snapshot_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory/release.before")" = \
    root:root:600
require_check rollback_snapshot_hash_record_regular \
    test -f "$rollback_directory/release.before.sha256"
require_check rollback_snapshot_hash_record_not_symlink \
    test ! -L "$rollback_directory/release.before.sha256"
require_check rollback_snapshot_hash_record_metadata \
    test "$(stat -c '%U:%G:%a' \
        "$rollback_directory/release.before.sha256")" = root:root:600
require_check rollback_snapshot_hash_record_exact \
    test "$(tr -d '\n' <"$rollback_directory/release.before.sha256")" = \
    "$before_snapshot_sha256"

chmod 0750 "$release"
install -o caddy-sync -g caddy-sync -m 0440 /dev/null "$request_marker"
runuser -u caddy-sync -- "$finalizer" --source-role node-a \
    >"$finalizer_output" 2>"$finalizer_error"

require_check request_regular test -f "$request_marker"
require_check request_not_symlink_after test ! -L "$request_marker"
require_check request_empty test ! -s "$request_marker"
require_check request_metadata \
    test "$(stat -c '%U:%G:%a' "$request_marker")" = caddy-sync:caddy-sync:440
require_check complete_regular test -f "$complete_marker"
require_check complete_not_symlink_after test ! -L "$complete_marker"
require_check complete_empty test ! -s "$complete_marker"
require_check complete_metadata \
    test "$(stat -c '%U:%G:%a' "$complete_marker")" = caddy-sync:caddy-sync:440
require_check pending_absent_after test ! -e "$pending_marker"
require_check pending_not_symlink_after test ! -L "$pending_marker"
require_check finalizer_stdout_empty test ! -s "$finalizer_output"
require_check finalizer_stderr_empty test ! -s "$finalizer_error"
require_check release_directories_relocked \
    test -z "$(find "$release" -type d ! -perm 0550 -print -quit)"
require_check release_files_relocked \
    test -z "$(find "$release" -type f ! -perm 0440 -print -quit)"
require_check payload_hash_unchanged \
    test "$(payload_digest)" = "$expected_payload_sha256"
require_check manifest_hash_unchanged \
    test "$(file_hash "$release/manifest.sha256")" = \
    "$expected_manifest_sha256"
require_check manifest_hashes_still_valid manifest_hashes_valid
require_check source_root_still_only_expected_release \
    test "$(find "$source_root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort)" = "$revision"
require_check current_link_unchanged \
    test "$(readlink /etc/caddy/current)" = "$expected_active_release"
require_check current_target_unchanged \
    test "$(readlink -e /etc/caddy/current)" = "$expected_active_release"
require_check lsyncd_configuration_still_absent test ! -e "$lsyncd_config"
require_check release_not_writable_after \
    runuser -u caddy-sync -- test ! -w "$release"
validate_service_continuity

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_payload_sha256=%s\n' "$prefix" "$expected_payload_sha256"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$expected_manifest_sha256"
printf '%s_value_before_snapshot_sha256=%s\n' \
    "$prefix" "$before_snapshot_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_finalizer_invoked=true\n' "$prefix"
printf '%s_marker_migration=true\n' "$prefix"
printf '%s_payload_content_mutation=false\n' "$prefix"
printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
printf '%s_caddy_selection_changed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_persistent_mutation_scope=finalize_request,complete,rollback_metadata\n' \
    "$prefix"

transaction_complete=true
trap - EXIT
rm -rf -- "$work_directory"
printf '%s_node_b_marker_migration_complete=true\n' "$prefix"
