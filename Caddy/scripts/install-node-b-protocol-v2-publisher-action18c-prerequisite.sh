#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_publisher_prerequisite
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly receiver=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys
readonly retained_release=/var/lib/caddy-sync/incoming/node-a/action17p-node-a-to-node-b-bootstrap
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly lsyncd_configuration=/etc/lsyncd/caddy.lua
readonly rollback_root=/var/backups/caddy-ha
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly expected_receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly expected_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly expected_authorized_keys_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

readonly -a continuity_units=(
    caddy.service
    lighttpd.service
    keepalived.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a common_properties=(ActiveState SubState UnitFileState)
readonly -a service_properties=(MainPID NRestarts)

declare -A state_before=()
stage_directory=
publisher_install_stage=
rollback_directory=
sync_tree_before=
mutation_started=false
transaction_complete=false

usage() {
    printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

tree_digest() {
    local digest_root=$1

    (
        cd "$digest_root"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

payload_digest() {
    (
        cd "$retained_release"
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

unit_property() {
    local property_name=$1
    local unit_name=$2

    if [[ "$property_name" == UnitFileState ]]; then
        systemctl is-enabled "$unit_name" 2>/dev/null || true
        return 0
    fi
    systemctl show "$unit_name" --no-pager \
        --property "$property_name" --value
}

capture_service_state() {
    local property_name
    local property_value
    local unit_label
    local unit_name

    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            property_value=$(unit_property "$property_name" "$unit_name") ||
                return 1
            require_check "pre_${unit_label}_${property_name}_observed" \
                test -n "$property_value" || return 1
            state_before["$unit_name:$property_name"]=$property_value
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                property_value=$(unit_property "$property_name" "$unit_name") ||
                    return 1
                require_check "pre_${unit_label}_${property_name}_observed" \
                    test -n "$property_value" || return 1
                state_before["$unit_name:$property_name"]=$property_value
            done
        fi
    done
}

validate_service_continuity() {
    local property_name
    local property_value
    local unit_label
    local unit_name

    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            property_value=$(unit_property "$property_name" "$unit_name") ||
                return 1
            require_check "post_${unit_label}_${property_name}_unchanged" \
                test "$property_value" = \
                "${state_before["$unit_name:$property_name"]}" || return 1
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                property_value=$(unit_property "$property_name" "$unit_name") ||
                    return 1
                require_check "post_${unit_label}_${property_name}_unchanged" \
                    test "$property_value" = \
                    "${state_before["$unit_name:$property_name"]}" || return 1
            done
        fi
    done
}

validate_publisher_source() {
    local source_path=$1

    require_check stage_publisher_regular test -f "$source_path" || return 1
    require_check stage_publisher_not_symlink test ! -L "$source_path" ||
        return 1
    require_check stage_publisher_metadata \
        test "$(stat -c '%U:%G:%a' "$source_path")" = root:root:700 ||
        return 1
    require_check stage_publisher_hash_exact \
        test "$(file_hash "$source_path")" = \
        "$expected_publisher_sha256" || return 1
    require_check stage_publisher_syntax bash -n "$source_path" || return 1
    require_check stage_publisher_emergency_gate grep -Fq \
        'Node B publishing requires --emergency.' "$source_path" || return 1
    require_check stage_publisher_master_gate grep -Fq \
        'Node B may publish only while CADDY_DUALSTACK is MASTER.' \
        "$source_path" || return 1
}

validate_accepted_baseline() {
    require_check live_publisher_absent test ! -e "$publisher" || return 1
    require_check live_publisher_not_symlink test ! -L "$publisher" || return 1
    require_check libexec_directory_metadata \
        test "$(stat -c '%U:%G:%a' /usr/local/libexec)" = root:root:755 ||
        return 1
    require_check receiver_regular test -f "$receiver" || return 1
    require_check receiver_not_symlink test ! -L "$receiver" || return 1
    require_check receiver_metadata \
        test "$(stat -c '%U:%G:%a' "$receiver")" = root:root:755 ||
        return 1
    require_check receiver_hash_exact \
        test "$(file_hash "$receiver")" = "$expected_receiver_sha256" ||
        return 1
    require_check finalizer_regular test -f "$finalizer" || return 1
    require_check finalizer_not_symlink test ! -L "$finalizer" || return 1
    require_check finalizer_metadata \
        test "$(stat -c '%U:%G:%a' "$finalizer")" = root:root:755 ||
        return 1
    require_check finalizer_hash_exact \
        test "$(file_hash "$finalizer")" = "$expected_finalizer_sha256" ||
        return 1
    require_check authorized_keys_regular test -f "$authorized_keys" ||
        return 1
    require_check authorized_keys_not_symlink test ! -L "$authorized_keys" ||
        return 1
    require_check authorized_keys_metadata \
        test "$(stat -c '%U:%G:%a' "$authorized_keys")" = \
        caddy-sync:caddy-sync:600 || return 1
    require_check authorized_keys_hash_exact \
        test "$(file_hash "$authorized_keys")" = \
        "$expected_authorized_keys_sha256" || return 1

    require_check retained_release_directory test -d "$retained_release" ||
        return 1
    require_check retained_release_not_symlink test ! -L "$retained_release" ||
        return 1
    require_check retained_release_metadata \
        test "$(stat -c '%U:%G:%a' "$retained_release")" = \
        caddy-sync:caddy-sync:550 || return 1
    require_check request_marker_regular \
        test -f "$retained_release/.finalize-request" || return 1
    require_check request_marker_not_symlink \
        test ! -L "$retained_release/.finalize-request" || return 1
    require_check request_marker_empty \
        test ! -s "$retained_release/.finalize-request" || return 1
    require_check request_marker_hash_exact \
        test "$(file_hash "$retained_release/.finalize-request")" = \
        "$expected_empty_sha256" || return 1
    require_check completion_marker_regular \
        test -f "$retained_release/.complete" || return 1
    require_check completion_marker_not_symlink \
        test ! -L "$retained_release/.complete" || return 1
    require_check completion_marker_empty \
        test ! -s "$retained_release/.complete" || return 1
    require_check completion_marker_hash_exact \
        test "$(file_hash "$retained_release/.complete")" = \
        "$expected_empty_sha256" || return 1
    require_check pending_marker_absent \
        test ! -e "$retained_release/.complete.pending" || return 1
    require_check pending_marker_not_symlink \
        test ! -L "$retained_release/.complete.pending" || return 1
    require_check retained_payload_hash_exact \
        test "$(payload_digest)" = "$expected_payload_sha256" || return 1
    require_check retained_manifest_hash_exact \
        test "$(file_hash "$retained_release/manifest.sha256")" = \
        "$expected_manifest_sha256" || return 1
    require_check outbound_root_directory test -d "$outbound_root" || return 1
    require_check outbound_root_not_symlink test ! -L "$outbound_root" ||
        return 1
    require_check outbound_release_absent \
        test -z "$(find "$outbound_root" -mindepth 1 -maxdepth 1 -print -quit)" ||
        return 1

    require_check current_link_exact \
        test "$(readlink /etc/caddy/current)" = "$expected_active_release" ||
        return 1
    require_check current_target_exact \
        test "$(readlink -e /etc/caddy/current)" = "$expected_active_release" ||
        return 1
    require_check caddy_active \
        test "$(systemctl is-active caddy.service)" = active || return 1
    require_check lighttpd_active \
        test "$(systemctl is-active lighttpd.service)" = active || return 1
    require_check lsyncd_inactive \
        test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = \
        inactive || return 1
    require_check lsyncd_masked \
        test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = \
        masked || return 1
    require_check caddy_lsyncd_inactive \
        test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
        inactive || return 1
    require_check caddy_lsyncd_disabled \
        test "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = \
        disabled || return 1
    require_check reconcile_path_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = \
        inactive || return 1
    require_check reconcile_service_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = \
        inactive || return 1
    require_check lsyncd_configuration_absent \
        test ! -e "$lsyncd_configuration" || return 1
    require_check lsyncd_configuration_not_symlink \
        test ! -L "$lsyncd_configuration" || return 1
    # The child shell must evaluate the live state path.
    # shellcheck disable=SC2016
    require_check emergency_publish_inhibited bash -c \
        '[[ ! -r /run/caddy-ha/vrrp-state || "$(</run/caddy-ha/vrrp-state)" != MASTER ]]' ||
        return 1
}

validate_prestate() {
    require_check identity_root test "$(id -u)" -eq 0 || return 1
    require_check working_directory_root test "$(pwd -P)" = / || return 1
    require_check hostname_node_b test "$(hostname)" = j1-svpihole00 || return 1
    require_check architecture_arm64 \
        test "$(dpkg --print-architecture)" = arm64 || return 1
    require_check stage_directory_regular test -d "$stage_directory" || return 1
    require_check stage_directory_not_symlink test ! -L "$stage_directory" ||
        return 1
    require_check stage_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 ||
        return 1
    validate_publisher_source "$stage_directory/publish-release-v2.sh" ||
        return 1
    validate_accepted_baseline || return 1
    require_check rollback_root_directory test -d "$rollback_root" || return 1
    require_check rollback_root_not_symlink test ! -L "$rollback_root" ||
        return 1
    require_check rollback_root_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700 ||
        return 1
    require_check prior_action_backup_absent \
        test -z "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action18c-publisher-prerequisite.*' -print -quit)" || return 1
    require_check prior_install_stage_absent \
        test -z "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.publish-release-v2.action18c.*' -print -quit)" || return 1
    sync_tree_before=$(tree_digest /var/lib/caddy-sync) || return 1
    # The child shell validates its positional parameter.
    # shellcheck disable=SC2016
    require_check sync_tree_before_hash_format \
        bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' _ "$sync_tree_before" ||
        return 1
    capture_service_state || return 1
}

validate_backup() {
    local expected_manifest

    expected_manifest=$(printf '%s\n' \
        'action=action18c-publisher-prerequisite' \
        'publisher_pre_state=absent' \
        "publisher_candidate_sha256=$expected_publisher_sha256") || return 1
    require_check backup_directory_regular test -d "$rollback_directory" ||
        return 1
    require_check backup_directory_not_symlink test ! -L "$rollback_directory" ||
        return 1
    require_check backup_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700 ||
        return 1
    require_check backup_manifest_regular \
        test -f "$rollback_directory/manifest" || return 1
    require_check backup_manifest_not_symlink \
        test ! -L "$rollback_directory/manifest" || return 1
    require_check backup_manifest_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_directory/manifest")" = \
        root:root:600 || return 1
    require_check backup_manifest_content_exact \
        test "$(<"$rollback_directory/manifest")" = "$expected_manifest" ||
        return 1
}

validate_poststate() {
    require_check live_publisher_regular test -f "$publisher" || return 1
    require_check live_publisher_not_symlink test ! -L "$publisher" || return 1
    require_check live_publisher_metadata \
        test "$(stat -c '%U:%G:%a' "$publisher")" = root:root:755 ||
        return 1
    require_check live_publisher_hash_exact \
        test "$(file_hash "$publisher")" = "$expected_publisher_sha256" ||
        return 1
    require_check live_publisher_syntax bash -n "$publisher" || return 1
    require_check live_publisher_emergency_gate grep -Fq \
        'Node B publishing requires --emergency.' "$publisher" || return 1
    require_check live_publisher_master_gate grep -Fq \
        'Node B may publish only while CADDY_DUALSTACK is MASTER.' \
        "$publisher" || return 1
    validate_backup || return 1
    require_check sync_tree_unchanged \
        test "$(tree_digest /var/lib/caddy-sync)" = "$sync_tree_before" ||
        return 1
    require_check current_link_still_exact \
        test "$(readlink /etc/caddy/current)" = "$expected_active_release" ||
        return 1
    require_check current_target_still_exact \
        test "$(readlink -e /etc/caddy/current)" = "$expected_active_release" ||
        return 1
    # The child shell must evaluate the live state path.
    # shellcheck disable=SC2016
    require_check emergency_publish_still_inhibited bash -c \
        '[[ ! -r /run/caddy-ha/vrrp-state || "$(</run/caddy-ha/vrrp-state)" != MASTER ]]' ||
        return 1
    validate_service_continuity || return 1
}

cleanup_install_stage() {
    if [[ -n "$publisher_install_stage" &&
        (-e "$publisher_install_stage" || -L "$publisher_install_stage") ]]; then
        rm -f -- "$publisher_install_stage" || return 1
    fi
}

rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - ERR INT TERM EXIT
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    cleanup_install_stage || rollback_failed=true
    if [[ -e "$publisher" || -L "$publisher" ]]; then
        rm -f -- "$publisher" || rollback_failed=true
    fi
    [[ ! -e "$publisher" && ! -L "$publisher" ]] || rollback_failed=true
    if [[ -n "$rollback_directory" && -d "$rollback_directory" &&
        ! -L "$rollback_directory" ]]; then
        rm -rf -- "$rollback_directory" || rollback_failed=true
    elif [[ -n "$rollback_directory" &&
        (-e "$rollback_directory" || -L "$rollback_directory") ]]; then
        rollback_failed=true
    fi
    [[ "$(tree_digest /var/lib/caddy-sync)" == "$sync_tree_before" ]] ||
        rollback_failed=true
    validate_service_continuity >/dev/null 2>&1 || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$original_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$expected_publisher_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_receiver_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_authorized_keys_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_payload_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    *)
        usage
        exit 64
        ;;
esac

trap rollback ERR INT TERM EXIT
validate_prestate
printf '%s_preflight_complete=true\n' "$prefix"

mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
rollback_directory=$(mktemp -d \
    "$rollback_root/action18c-publisher-prerequisite.XXXXXX")
chmod 0700 "$rollback_directory"
printf '%s\n' \
    'action=action18c-publisher-prerequisite' \
    'publisher_pre_state=absent' \
    "publisher_candidate_sha256=$expected_publisher_sha256" \
    >"$rollback_directory/manifest"
chmod 0600 "$rollback_directory/manifest"
publisher_install_stage=$(mktemp \
    /usr/local/libexec/.publish-release-v2.action18c.XXXXXX)
install -o root -g root -m 0755 \
    "$stage_directory/publish-release-v2.sh" "$publisher_install_stage"
mv -- "$publisher_install_stage" "$publisher"
publisher_install_stage=

validate_poststate
transaction_complete=true
trap - ERR INT TERM EXIT

printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_persistent_mutation_scope=publisher_v2,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
