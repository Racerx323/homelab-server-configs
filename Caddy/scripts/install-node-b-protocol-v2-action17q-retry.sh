#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly revision=action17p-node-a-to-node-b-bootstrap
readonly retained_release="/var/lib/caddy-sync/incoming/node-a/$revision"
readonly libexec=/usr/local/libexec
readonly receiver_v1="$libexec/caddy-sync-rsync-receiver"
readonly receiver_v2="$libexec/caddy-sync-release-receiver-v2"
readonly finalizer_v2="$libexec/finalize-incoming-release-v2.sh"
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly authorized_keys="$ssh_dir/authorized_keys"
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly rollback_root=/var/backups/caddy-ha
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_receiver_v1_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly expected_receiver_v2_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly expected_finalizer_v2_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly expected_old_authorization_sha256=2d07f2dd0bdd1be96f5e6eb227cd23ddc407876925f01849ffa3333c50b553e1
readonly expected_new_authorization_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'

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
stage_directory=
rollback_directory=
receiver_install_stage=
finalizer_install_stage=
authorization_install_stage=
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
        printf 'action_17q_retry_check_%s=true\n' "$check_label"
        return 0
    fi
    printf 'action_17q_retry_check_%s=false\n' "$check_label" >&2
    return 1
}

payload_digest() {
    (
        cd "$retained_release"
        find . -type f ! -name .complete -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

retained_tree_digest() {
    (
        cd "$retained_release"
        find . -printf '%P|%y|%U:%G:%m:%s:%i\n' |
            LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

authorization_fingerprint() {
    local authorization_path=$1

    awk '{ print $(NF-2), $(NF-1), $NF }' "$authorization_path" |
        ssh-keygen -lf - -E sha256 |
        awk '{ print $2 }'
}

capture_service_state() {
    local property
    local property_value
    local service_property
    local service_property_value
    local unit
    local unit_label

    for unit in "${continuity_units[@]}"; do
        unit_label=${unit//[-.]/_}
        for property in "${continuity_common_properties[@]}"; do
            property_value=$(
                systemctl show "$unit" --no-pager \
                    --property "$property" --value
            )
            require_check \
                "pre_${unit_label}_${property}_observed" \
                test -n "$property_value"
            service_state_before["$unit:$property"]=$property_value
        done
        if [[ "$unit" == *.service ]]; then
            for service_property in \
                "${continuity_service_properties[@]}"; do
                service_property_value=$(
                    systemctl show "$unit" --no-pager \
                        --property "$service_property" --value
                )
                require_check \
                    "pre_${unit_label}_${service_property}_observed" \
                    test -n "$service_property_value"
                service_state_before["$unit:$service_property"]=$service_property_value
            done
        fi
        property_value=$(systemctl is-enabled "$unit" 2>/dev/null || true)
        require_check \
            "pre_${unit_label}_UnitFileState_observed" \
            test -n "$property_value"
        service_state_before["$unit:UnitFileState"]=$property_value
    done
}

validate_service_continuity() {
    local property
    local property_value
    local service_property
    local service_property_value
    local unit
    local unit_label

    for unit in "${continuity_units[@]}"; do
        unit_label=${unit//[-.]/_}
        for property in "${continuity_common_properties[@]}"; do
            property_value=$(
                systemctl show "$unit" --no-pager \
                    --property "$property" --value
            )
            require_check \
                "post_${unit_label}_${property}_unchanged" \
                test "$property_value" = \
                "${service_state_before["$unit:$property"]}"
        done
        if [[ "$unit" == *.service ]]; then
            for service_property in \
                "${continuity_service_properties[@]}"; do
                service_property_value=$(
                    systemctl show "$unit" --no-pager \
                        --property "$service_property" --value
                )
                require_check \
                    "post_${unit_label}_${service_property}_unchanged" \
                    test "$service_property_value" = \
                    "${service_state_before["$unit:$service_property"]}"
            done
        fi
        property_value=$(systemctl is-enabled "$unit" 2>/dev/null || true)
        require_check \
            "post_${unit_label}_UnitFileState_unchanged" \
            test "$property_value" = \
            "${service_state_before["$unit:UnitFileState"]}"
    done
}

cleanup_install_stages() {
    local cleanup_path

    for cleanup_path in \
        "$receiver_install_stage" \
        "$finalizer_install_stage" \
        "$authorization_install_stage"; do
        if [[ -n "$cleanup_path" &&
            (-e "$cleanup_path" || -L "$cleanup_path") ]]; then
            if [[ -f "$cleanup_path" && ! -L "$cleanup_path" ]]; then
                rm -f -- "$cleanup_path"
            else
                return 1
            fi
        fi
    done
}

validate_prestate() {
    require_check identity_root test "$(id -u)" -eq 0
    require_check working_directory_root test "$(pwd -P)" = /
    require_check hostname_node_b test "$(hostname)" = j1-svpihole00
    require_check architecture_arm64 \
        test "$(dpkg --print-architecture)" = arm64
    require_check stage_directory_regular test -d "$stage_directory"
    require_check stage_directory_not_symlink test ! -L "$stage_directory"
    require_check stage_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700

    require_check stage_receiver_regular \
        test -f "$stage_directory/caddy-sync-release-receiver-v2"
    require_check stage_receiver_not_symlink \
        test ! -L "$stage_directory/caddy-sync-release-receiver-v2"
    require_check stage_receiver_hash \
        test "$(file_hash "$stage_directory/caddy-sync-release-receiver-v2")" = \
        "$expected_receiver_v2_sha256"
    require_check stage_receiver_syntax \
        bash -n "$stage_directory/caddy-sync-release-receiver-v2"
    require_check stage_finalizer_regular \
        test -f "$stage_directory/finalize-incoming-release-v2.sh"
    require_check stage_finalizer_not_symlink \
        test ! -L "$stage_directory/finalize-incoming-release-v2.sh"
    require_check stage_finalizer_hash \
        test "$(file_hash "$stage_directory/finalize-incoming-release-v2.sh")" = \
        "$expected_finalizer_v2_sha256"
    require_check stage_finalizer_syntax \
        bash -n "$stage_directory/finalize-incoming-release-v2.sh"
    require_check stage_authorization_regular \
        test -f "$stage_directory/authorized_keys"
    require_check stage_authorization_not_symlink \
        test ! -L "$stage_directory/authorized_keys"
    require_check stage_authorization_hash \
        test "$(file_hash "$stage_directory/authorized_keys")" = \
        "$expected_new_authorization_sha256"
    require_check stage_authorization_single_line \
        test "$(wc -l <"$stage_directory/authorized_keys")" -eq 1
    require_check stage_authorization_fingerprint \
        test "$(authorization_fingerprint \
            "$stage_directory/authorized_keys")" = \
        "$expected_node_a_fingerprint"

    require_check live_receiver_v1_regular test -f "$receiver_v1"
    require_check live_receiver_v1_not_symlink test ! -L "$receiver_v1"
    require_check live_receiver_v1_hash \
        test "$(file_hash "$receiver_v1")" = \
        "$expected_receiver_v1_sha256"
    require_check live_receiver_v2_absent test ! -e "$receiver_v2"
    require_check live_receiver_v2_not_symlink test ! -L "$receiver_v2"
    require_check live_finalizer_v2_absent test ! -e "$finalizer_v2"
    require_check live_finalizer_v2_not_symlink test ! -L "$finalizer_v2"
    require_check authorized_keys_regular test -f "$authorized_keys"
    require_check authorized_keys_not_symlink test ! -L "$authorized_keys"
    require_check authorized_keys_metadata \
        test "$(stat -c '%U:%G:%a' "$authorized_keys")" = \
        caddy-sync:caddy-sync:600
    require_check authorized_keys_single_line \
        test "$(wc -l <"$authorized_keys")" -eq 1
    require_check authorized_keys_old_hash \
        test "$(file_hash "$authorized_keys")" = \
        "$expected_old_authorization_sha256"
    require_check authorized_keys_node_a_fingerprint \
        test "$(authorization_fingerprint "$authorized_keys")" = \
        "$expected_node_a_fingerprint"

    require_check retained_release_regular_directory \
        test -d "$retained_release"
    require_check retained_release_not_symlink test ! -L "$retained_release"
    require_check retained_release_metadata \
        test "$(stat -c '%U:%G:%a' "$retained_release")" = \
        caddy-sync:caddy-sync:550
    require_check retained_complete_absent \
        test ! -e "$retained_release/.complete"
    require_check retained_complete_not_symlink \
        test ! -L "$retained_release/.complete"
    require_check retained_pending_absent \
        test ! -e "$retained_release/.complete.pending"
    require_check retained_pending_not_symlink \
        test ! -L "$retained_release/.complete.pending"
    require_check retained_finalize_request_absent \
        test ! -e "$retained_release/.finalize-request"
    require_check retained_finalize_request_not_symlink \
        test ! -L "$retained_release/.finalize-request"
    require_check retained_payload_hash \
        test "$(payload_digest)" = "$expected_payload_sha256"
    require_check retained_manifest_hash \
        test "$(file_hash "$retained_release/manifest.sha256")" = \
        "$expected_manifest_sha256"
    require_check retained_not_writable_by_sync \
        runuser -u caddy-sync -- test ! -w "$retained_release"

    require_check current_link_exact \
        test "$(readlink /etc/caddy/current)" = \
        "$expected_active_release"
    require_check current_target_exact \
        test "$(readlink -e /etc/caddy/current)" = \
        "$expected_active_release"
    require_check caddy_active \
        test "$(systemctl is-active caddy.service)" = active
    require_check lsyncd_inactive \
        test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = \
        inactive
    require_check lsyncd_masked \
        test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = \
        masked
    require_check caddy_lsyncd_inactive \
        test "$(systemctl is-active caddy-lsyncd.service \
            2>/dev/null || true)" = inactive
    require_check caddy_lsyncd_disabled \
        test "$(systemctl is-enabled caddy-lsyncd.service \
            2>/dev/null || true)" = disabled
    require_check reconcile_path_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.path \
            2>/dev/null || true)" = inactive
    require_check reconcile_service_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.service \
            2>/dev/null || true)" = inactive
    require_check lsyncd_configuration_absent test ! -e "$lsyncd_config"
    require_check lsyncd_configuration_not_symlink test ! -L "$lsyncd_config"
    require_check rollback_root_regular_directory test -d "$rollback_root"
    require_check rollback_root_not_symlink test ! -L "$rollback_root"
    require_check rollback_root_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700
}

validate_installed_state() {
    require_check installed_receiver_v2_regular test -f "$receiver_v2"
    require_check installed_receiver_v2_not_symlink test ! -L "$receiver_v2"
    require_check installed_receiver_v2_metadata \
        test "$(stat -c '%U:%G:%a' "$receiver_v2")" = root:root:755
    require_check installed_receiver_v2_hash \
        test "$(file_hash "$receiver_v2")" = \
        "$expected_receiver_v2_sha256"
    require_check installed_receiver_v2_syntax bash -n "$receiver_v2"
    require_check installed_finalizer_v2_regular test -f "$finalizer_v2"
    require_check installed_finalizer_v2_not_symlink test ! -L "$finalizer_v2"
    require_check installed_finalizer_v2_metadata \
        test "$(stat -c '%U:%G:%a' "$finalizer_v2")" = root:root:755
    require_check installed_finalizer_v2_hash \
        test "$(file_hash "$finalizer_v2")" = \
        "$expected_finalizer_v2_sha256"
    require_check installed_finalizer_v2_syntax bash -n "$finalizer_v2"
    require_check installed_authorized_keys_regular test -f "$authorized_keys"
    require_check installed_authorized_keys_not_symlink \
        test ! -L "$authorized_keys"
    require_check installed_authorized_keys_metadata \
        test "$(stat -c '%U:%G:%a' "$authorized_keys")" = \
        caddy-sync:caddy-sync:600
    require_check installed_authorized_keys_single_line \
        test "$(wc -l <"$authorized_keys")" -eq 1
    require_check installed_authorized_keys_hash \
        test "$(file_hash "$authorized_keys")" = \
        "$expected_new_authorization_sha256"
    require_check installed_authorized_keys_fingerprint \
        test "$(authorization_fingerprint "$authorized_keys")" = \
        "$expected_node_a_fingerprint"
    require_check preserved_receiver_v1_hash \
        test "$(file_hash "$receiver_v1")" = \
        "$expected_receiver_v1_sha256"
}

rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    set +e
    printf 'action_17q_retry_rollback_started=true\n' >&2
    cleanup_install_stages || rollback_failed=true
    if [[ "$mutation_started" == true ]]; then
        rm -f -- "$receiver_v2" || rollback_failed=true
        rm -f -- "$finalizer_v2" || rollback_failed=true
        if [[ -n "$rollback_directory" &&
            -f "$rollback_directory/authorized_keys.before" &&
            ! -L "$rollback_directory/authorized_keys.before" ]]; then
            install -o caddy-sync -g caddy-sync -m 0600 \
                "$rollback_directory/authorized_keys.before" \
                "$authorized_keys" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    if [[ -n "$rollback_directory" &&
        (-e "$rollback_directory" || -L "$rollback_directory") ]]; then
        if [[ -d "$rollback_directory" && ! -L "$rollback_directory" ]]; then
            rm -rf -- "$rollback_directory" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    validate_prestate >/dev/null 2>&1 || rollback_failed=true
    validate_service_continuity >/dev/null 2>&1 || rollback_failed=true
    if [[ -n "${retained_tree_before:-}" &&
        "$(retained_tree_digest)" != "$retained_tree_before" ]]; then
        rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17q_retry_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17q_retry_rollback_complete=true\n' >&2
    exit "$original_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for self_test_hash in \
        "$expected_receiver_v1_sha256" \
        "$expected_receiver_v2_sha256" \
        "$expected_finalizer_v2_sha256" \
        "$expected_old_authorization_sha256" \
        "$expected_new_authorization_sha256" \
        "$expected_payload_sha256" \
        "$expected_manifest_sha256"; do
        [[ "$self_test_hash" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$expected_node_a_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_17q_retry_installer_self_test_complete=true\n'
    exit 0
fi

if [[ $# -ne 2 || "$1" != --stage ]]; then
    usage
    exit 2
fi
stage_directory=$2
readonly stage_directory

validate_prestate
capture_service_state
retained_tree_before=$(retained_tree_digest)
readonly retained_tree_before
printf 'action_17q_retry_preflight_complete=true\n'

trap rollback EXIT
mutation_started=true
printf 'action_17q_retry_mutation_started=true\n'
install -d -o root -g root -m 0700 "$rollback_root"
rollback_directory=$(
    mktemp -d "$rollback_root/action17q-retry-node-b-protocol-v2.XXXXXX"
)
chmod 0700 "$rollback_directory"
install -o root -g root -m 0600 \
    "$authorized_keys" "$rollback_directory/authorized_keys.before"
printf '%s\n' "$expected_old_authorization_sha256" \
    >"$rollback_directory/authorized_keys.before.sha256"
chmod 0600 "$rollback_directory/authorized_keys.before.sha256"

receiver_install_stage=$(mktemp "$libexec/.caddy-sync-receiver-v2.XXXXXX")
finalizer_install_stage=$(mktemp "$libexec/.caddy-sync-finalizer-v2.XXXXXX")
authorization_install_stage=$(mktemp "$ssh_dir/.authorized-keys-v2.XXXXXX")
install -o root -g root -m 0755 \
    "$stage_directory/caddy-sync-release-receiver-v2" \
    "$receiver_install_stage"
install -o root -g root -m 0755 \
    "$stage_directory/finalize-incoming-release-v2.sh" \
    "$finalizer_install_stage"
install -o caddy-sync -g caddy-sync -m 0600 \
    "$stage_directory/authorized_keys" \
    "$authorization_install_stage"
mv -fT -- "$receiver_install_stage" "$receiver_v2"
receiver_install_stage=
mv -fT -- "$finalizer_install_stage" "$finalizer_v2"
finalizer_install_stage=
mv -fT -- "$authorization_install_stage" "$authorized_keys"
authorization_install_stage=

validate_installed_state
require_check retained_tree_unchanged \
    test "$(retained_tree_digest)" = "$retained_tree_before"
require_check retained_payload_hash_unchanged \
    test "$(payload_digest)" = "$expected_payload_sha256"
require_check retained_manifest_hash_unchanged \
    test "$(file_hash "$retained_release/manifest.sha256")" = \
    "$expected_manifest_sha256"
require_check retained_complete_still_absent \
    test ! -e "$retained_release/.complete"
require_check retained_pending_still_absent \
    test ! -e "$retained_release/.complete.pending"
require_check retained_finalize_request_still_absent \
    test ! -e "$retained_release/.finalize-request"
require_check current_link_still_exact \
    test "$(readlink /etc/caddy/current)" = "$expected_active_release"
require_check current_target_still_exact \
    test "$(readlink -e /etc/caddy/current)" = "$expected_active_release"
require_check lsyncd_configuration_still_absent test ! -e "$lsyncd_config"
validate_service_continuity
require_check rollback_directory_regular test -d "$rollback_directory"
require_check rollback_directory_not_symlink test ! -L "$rollback_directory"
require_check rollback_directory_metadata \
    test "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700
require_check rollback_authorization_hash \
    test "$(file_hash "$rollback_directory/authorized_keys.before")" = \
    "$expected_old_authorization_sha256"

printf 'action_17q_retry_receiver_invoked=false\n'
printf 'action_17q_retry_finalizer_invoked=false\n'
printf 'action_17q_retry_release_mutated=false\n'
printf 'action_17q_retry_lsyncd_enabled=false\n'
printf 'action_17q_retry_reconciliation_enabled=false\n'
printf 'action_17q_retry_service_mutations=false\n'
printf 'action_17q_retry_backup_path=%s\n' "$rollback_directory"
printf 'action_17q_retry_persistent_mutation_scope=receiver_v2,finalizer_v2,authorized_keys,rollback_backup\n'

transaction_complete=true
trap - EXIT
printf 'action_17q_retry_node_b_protocol_v2_install_complete=true\n'
