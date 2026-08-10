#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28b
readonly expected_hostname=j1-svpihole0
readonly expected_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
retained_outbound_name=action17p-node-a-to-node-b-bootstrap
retained_outbound_root_metadata=994:990:750:4096:1785461698
retained_outbound_child_metadata=994:990:550:4096:1785461697
retained_outbound_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly -a required_commands=(
    awk bash find grep hostname id install mv readlink rm sha256sum sort stat
    systemctl wc
)
readonly -a continuity_units=(
    caddy.service
    lighttpd.service
    keepalived.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a continuity_properties=(ActiveState SubState UnitFileState)

declare -A seen_checks=()
declare -A state_before=()
test_mode=false
root_prefix=
stage_directory=
mutation_started=false
transaction_complete=false
publisher_install_stage=
sync_tree_before=
current_link_before=
current_target_before=
expected_owner=root:root
install_owner=root
install_group=root

usage() {
    printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
}

root_path() {
    printf '%s%s\n' "$root_prefix" "$1"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}

record_check() {
    local action28b_check_label=$1

    shift
    if [[ -n "${seen_checks[$action28b_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action28b_check_label" >&2
        return 1
    fi
    seen_checks[$action28b_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action28b_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28b_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action28b_check_label" >&2
    return 1
}

effective_uid() {
    if [[ "$test_mode" == true ]]; then
        printf '0\n'
        return 0
    fi
    id -u
}

node_hostname() {
    if [[ "$test_mode" == true ]]; then
        printf '%s\n' "$expected_hostname"
        return 0
    fi
    hostname
}

unit_property() {
    local action28b_property=$1
    local action28b_unit=$2

    if [[ "$test_mode" == true ]]; then
        case "$action28b_property" in
            ActiveState)
                case "$action28b_unit" in
                    caddy.service | lighttpd.service | keepalived.service)
                        printf 'active\n'
                        ;;
                    *) printf 'inactive\n' ;;
                esac
                ;;
            SubState)
                case "$action28b_unit" in
                    caddy.service | lighttpd.service | keepalived.service)
                        printf 'running\n'
                        ;;
                    *) printf 'dead\n' ;;
                esac
                ;;
            UnitFileState)
                case "$action28b_unit" in
                    caddy.service | lighttpd.service | keepalived.service)
                        printf 'enabled\n'
                        ;;
                    lsyncd.service) printf 'masked\n' ;;
                    *) printf 'disabled\n' ;;
                esac
                ;;
            *) return 1 ;;
        esac
        return 0
    fi
    if [[ "$action28b_property" == UnitFileState ]]; then
        systemctl is-enabled "$action28b_unit" 2>/dev/null || true
        return 0
    fi
    systemctl show "$action28b_unit" --no-pager \
        --property "$action28b_property" --value
}

unit_active() {
    [[ "$(unit_property ActiveState "$1")" == active ]]
}

unit_inactive() {
    [[ "$(unit_property ActiveState "$1")" == inactive ]]
}

vrrp_state() {
    sed -n '1p' "$(root_path /run/caddy-ha/vrrp-state)" 2>/dev/null
}

resolve_current_target() {
    local action28b_current_link
    local action28b_link_value

    action28b_current_link=$(root_path /etc/caddy/current)
    action28b_link_value=$(readlink "$action28b_current_link") || return 1
    if [[ "$test_mode" == true && "$action28b_link_value" == /* ]]; then
        readlink -e "$root_prefix$action28b_link_value"
        return
    fi
    readlink -e "$action28b_current_link"
}

tree_digest() {
    local action28b_tree_root=$1

    (
        cd "$action28b_tree_root"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

capture_continuity() {
    local action28b_property
    local action28b_unit
    local action28b_value

    for action28b_unit in "${continuity_units[@]}"; do
        for action28b_property in "${continuity_properties[@]}"; do
            action28b_value=$(unit_property "$action28b_property" "$action28b_unit") ||
                return 1
            [[ -n "$action28b_value" ]] || return 1
            state_before["$action28b_unit:$action28b_property"]=$action28b_value
        done
    done
}

continuity_unchanged() {
    local action28b_property
    local action28b_unit
    local action28b_value

    # conditional-validator-explicit-failures-begin
    for action28b_unit in "${continuity_units[@]}"; do
        for action28b_property in "${continuity_properties[@]}"; do
            action28b_value=$(unit_property "$action28b_property" "$action28b_unit") ||
                return 1 # conditional-validator-requires-return
            [[ "$action28b_value" == "${state_before["$action28b_unit:$action28b_property"]}" ]] || return 1
        done
    done
    # conditional-validator-explicit-failures-end
}

publisher_source_valid() {
    local action28b_source=$1

    # conditional-validator-explicit-failures-begin
    [[ -f "$action28b_source" ]] || return 1
    [[ ! -L "$action28b_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action28b_source")" == "$expected_owner:700" ]] || return 1
    [[ "$(file_hash "$action28b_source")" == "$expected_publisher_sha256" ]] || return 1
    /bin/bash -n "$action28b_source" || return 1
    grep -Fq 'Node B publishing requires --emergency.' "$action28b_source" || return 1
    grep -Fq 'Node B may publish only while CADDY_DUALSTACK is MASTER.' \
        "$action28b_source" || return 1
    # conditional-validator-explicit-failures-end
}

emit_expected_checks() {
    local action28b_command
    local action28b_property
    local action28b_unit
    local action28b_unit_label

    for action28b_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action28b_command//-/_}"
    done
    printf '%s\n' \
        uid_root working_directory_root hostname_node_a stage_directory_regular \
        stage_directory_not_symlink stage_directory_metadata stage_publisher_valid \
        live_publisher_absent live_publisher_absent_not_symlink libexec_directory_metadata \
        rollback_root_directory rollback_root_not_symlink rollback_root_metadata \
        prior_backup_absent install_stage_residue_absent current_link_symlink \
        current_target_directory current_target_not_symlink current_manifest_regular \
        current_complete_regular current_complete_empty caddy_active_before \
        lighttpd_active_before keepalived_active_before lsyncd_inactive_before \
        caddy_lsyncd_inactive_before reconcile_path_inactive_before \
        reconcile_service_inactive_before vrrp_master_before outbound_root_directory \
        outbound_root_not_symlink outbound_root_metadata_exact outbound_child_count_exact \
        retained_child_directory retained_child_not_symlink retained_child_metadata_exact \
        retained_child_tree_hash_exact retained_finalize_request_absent \
        retained_finalize_request_not_symlink retained_complete_regular \
        retained_complete_not_symlink retained_complete_empty \
        retained_complete_pending_absent retained_complete_pending_not_symlink sync_tree_before_hash_valid
    for action28b_unit in "${continuity_units[@]}"; do
        action28b_unit_label=${action28b_unit//[-.]/_}
        for action28b_property in "${continuity_properties[@]}"; do
            printf 'pre_%s_%s_observed\n' "$action28b_unit_label" "$action28b_property"
        done
    done
    printf '%s\n' \
        backup_directory_created backup_manifest_created backup_manifest_exact \
        publisher_install_stage_created live_publisher_regular live_publisher_not_symlink \
        live_publisher_metadata live_publisher_hash_exact live_publisher_syntax \
        live_publisher_node_b_emergency_gate live_publisher_node_b_master_gate \
        post_install_boundary backup_directory_retained backup_manifest_retained \
        backup_manifest_still_exact install_stage_residue_absent_after \
        sync_tree_unchanged current_link_unchanged current_target_unchanged \
        service_state_unchanged vrrp_master_after outbound_root_metadata_unchanged \
        outbound_child_count_unchanged retained_child_directory_after \
        retained_child_not_symlink_after retained_child_metadata_unchanged \
        retained_child_tree_hash_unchanged retained_finalize_request_absent_after \
        retained_finalize_request_not_symlink_after retained_complete_regular_after \
        retained_complete_not_symlink_after retained_complete_empty_after \
        retained_complete_pending_absent_after retained_complete_pending_not_symlink_after
}

emit_contract_transcript() {
    local action28b_contract_count=0
    local action28b_contract_label

    while IFS= read -r action28b_contract_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action28b_contract_label"
        action28b_contract_count=$((action28b_contract_count + 1))
    done < <(emit_expected_checks)
    printf '%s_value_publisher_sha256=%s\n' "$prefix" "$expected_publisher_sha256"
    printf '%s_value_backup_path=/var/backups/caddy-ha/action28b-node-a-publisher\n' "$prefix"
    printf '%s_value_publisher_pre_state=absent\n' "$prefix"
    printf '%s_value_retained_outbound_name=%s\n' "$prefix" "$retained_outbound_name"
    printf '%s_value_retained_outbound_tree_sha256=%s\n' "$prefix" "$retained_outbound_tree_sha256"
    printf '%s_check_count=%s\n' "$prefix" "$action28b_contract_count"
    printf '%s_failed_check_count=0\n' "$prefix"
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_mutation_started=true\n' "$prefix"
    printf '%s_rollback_invoked=false\n' "$prefix"
    printf '%s_publisher_invoked=false\n' "$prefix"
    printf '%s_release_mutated=false\n' "$prefix"
    printf '%s_service_mutations=false\n' "$prefix"
    printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
    printf '%s_action_28_rerun=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}

self_test() {
    local action28b_count

    valid_sha256 "$expected_publisher_sha256" || return 1
    valid_sha256 "$empty_sha256" || return 1
    action28b_count=$(emit_expected_checks | wc -l) || return 1
    [[ "$action28b_count" -gt 0 ]] || return 1
    [[ "$(emit_expected_checks | LC_ALL=C sort -u | wc -l)" -eq "$action28b_count" ]] || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
}

rollback() {
    local action28b_original_status=$?
    local action28b_rollback_failed=false
    local action28b_backup
    local action28b_publisher

    trap - EXIT
    action28b_backup=$(root_path /var/backups/caddy-ha/action28b-node-a-publisher)
    action28b_publisher=$(root_path /usr/local/libexec/publish-release-v2.sh)
    if [[ "$transaction_complete" == true ]]; then
        exit "$action28b_original_status"
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$action28b_original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    set +e
    if [[ -n "$publisher_install_stage" ]]; then
        rm -f -- "$publisher_install_stage" || action28b_rollback_failed=true
    fi
    rm -f -- "$action28b_publisher" || action28b_rollback_failed=true
    rm -rf -- "$action28b_backup" || action28b_rollback_failed=true
    [[ ! -e "$action28b_publisher" && ! -L "$action28b_publisher" ]] ||
        action28b_rollback_failed=true
    [[ ! -e "$action28b_backup" && ! -L "$action28b_backup" ]] ||
        action28b_rollback_failed=true
    [[ "$(tree_digest "$(root_path /var/lib/caddy-sync)")" == "$sync_tree_before" ]] ||
        action28b_rollback_failed=true
    continuity_unchanged || action28b_rollback_failed=true
    [[ "$(readlink "$(root_path /etc/caddy/current)")" == "$current_link_before" ]] ||
        action28b_rollback_failed=true
    [[ "$(resolve_current_target)" == "$current_target_before" ]] ||
        action28b_rollback_failed=true
    set -e
    if [[ "$action28b_rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$action28b_original_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        exit 0
        ;;
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        emit_expected_checks
        exit 0
        ;;
    --contract-transcript)
        [[ $# -eq 1 ]] || exit 64
        emit_contract_transcript
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    --fixture-transaction)
        [[ $# -eq 3 && "${CADDY_ACTION28B_TEST_MODE:-}" == 1 ]] || exit 64
        test_mode=true
        retained_outbound_root_metadata=${CADDY_ACTION28B_TEST_ROOT_METADATA:?}
        retained_outbound_child_metadata=${CADDY_ACTION28B_TEST_CHILD_METADATA:?}
        retained_outbound_tree_sha256=${CADDY_ACTION28B_TEST_TREE_SHA256:?}
        root_prefix=$2
        stage_directory=$3
        expected_owner="$(id -un):$(id -gn)"
        install_owner=$(id -un)
        install_group=$(id -gn)
        ;;
    *)
        usage
        exit 64
        ;;
esac

readonly test_mode root_prefix stage_directory expected_owner install_owner install_group
readonly retained_outbound_name retained_outbound_root_metadata
readonly retained_outbound_child_metadata retained_outbound_tree_sha256
publisher=$(root_path /usr/local/libexec/publish-release-v2.sh)
libexec_directory=$(root_path /usr/local/libexec)
rollback_root=$(root_path /var/backups/caddy-ha)
backup_directory=$(root_path /var/backups/caddy-ha/action28b-node-a-publisher)
current_link=$(root_path /etc/caddy/current)
outbound_root=$(root_path /var/lib/caddy-sync/outbound)
sync_root=$(root_path /var/lib/caddy-sync)
readonly publisher libexec_directory rollback_root backup_directory
readonly current_link outbound_root sync_root
retained_outbound_path=$outbound_root/$retained_outbound_name
readonly retained_outbound_path
readonly publisher_source=$stage_directory/publish-release-v2.sh

trap rollback EXIT
for action28b_required_command in "${required_commands[@]}"; do
    record_check "command_${action28b_required_command//-/_}_available" \
        command -v "$action28b_required_command" || exit 1
done
record_check uid_root test "$(effective_uid)" -eq 0 || exit 1
record_check working_directory_root test "$PWD" = / || exit 1
record_check hostname_node_a test "$(node_hostname)" = "$expected_hostname" || exit 1
record_check stage_directory_regular test -d "$stage_directory" || exit 1
record_check stage_directory_not_symlink test ! -L "$stage_directory" || exit 1
record_check stage_directory_metadata test \
    "$(stat -c '%U:%G:%a' "$stage_directory")" = "$expected_owner:700" || exit 1
record_check stage_publisher_valid publisher_source_valid "$publisher_source" || exit 1
record_check live_publisher_absent test ! -e "$publisher" || exit 1
record_check live_publisher_absent_not_symlink test ! -L "$publisher" || exit 1
record_check libexec_directory_metadata test \
    "$(stat -c '%U:%G:%a' "$libexec_directory")" = "$expected_owner:755" || exit 1
record_check rollback_root_directory test -d "$rollback_root" || exit 1
record_check rollback_root_not_symlink test ! -L "$rollback_root" || exit 1
record_check rollback_root_metadata test \
    "$(stat -c '%U:%G:%a' "$rollback_root")" = "$expected_owner:700" || exit 1
record_check prior_backup_absent test ! -e "$backup_directory" || exit 1
record_check install_stage_residue_absent test -z \
    "$(find "$libexec_directory" -mindepth 1 -maxdepth 1 \
        -name '.publish-release-v2.action28b.*' -print -quit)" || exit 1
record_check current_link_symlink test -L "$current_link" || exit 1
current_link_before=$(readlink "$current_link")
readonly current_link_before
current_target_before=$(resolve_current_target)
readonly current_target_before
record_check current_target_directory test -d "$current_target_before" || exit 1
record_check current_target_not_symlink test ! -L "$current_target_before" || exit 1
record_check current_manifest_regular test -f "$current_target_before/release-manifest.json" || exit 1
record_check current_complete_regular test -f "$current_target_before/.complete" || exit 1
record_check current_complete_empty test ! -s "$current_target_before/.complete" || exit 1
record_check caddy_active_before unit_active caddy.service || exit 1
record_check lighttpd_active_before unit_active lighttpd.service || exit 1
record_check keepalived_active_before unit_active keepalived.service || exit 1
record_check lsyncd_inactive_before unit_inactive lsyncd.service || exit 1
record_check caddy_lsyncd_inactive_before unit_inactive caddy-lsyncd.service || exit 1
record_check reconcile_path_inactive_before unit_inactive caddy-sync-reconcile.path || exit 1
record_check reconcile_service_inactive_before unit_inactive caddy-sync-reconcile.service || exit 1
record_check vrrp_master_before test "$(vrrp_state)" = MASTER || exit 1
record_check outbound_root_directory test -d "$outbound_root" || exit 1
record_check outbound_root_not_symlink test ! -L "$outbound_root" || exit 1
record_check outbound_root_metadata_exact test "$(stat -c '%u:%g:%a:%s:%Y' "$outbound_root")" = "$retained_outbound_root_metadata" || exit 1
record_check outbound_child_count_exact test "$(find "$outbound_root" -mindepth 1 -maxdepth 1 -printf '.' | wc -c)" -eq 1 || exit 1
record_check retained_child_directory test -d "$retained_outbound_path" || exit 1
record_check retained_child_not_symlink test ! -L "$retained_outbound_path" || exit 1
record_check retained_child_metadata_exact test "$(stat -c '%u:%g:%a:%s:%Y' "$retained_outbound_path")" = "$retained_outbound_child_metadata" || exit 1
record_check retained_child_tree_hash_exact test "$(tree_digest "$retained_outbound_path")" = "$retained_outbound_tree_sha256" || exit 1
record_check retained_finalize_request_absent test ! -e "$retained_outbound_path/.finalize-request" || exit 1
record_check retained_finalize_request_not_symlink test ! -L "$retained_outbound_path/.finalize-request" || exit 1
record_check retained_complete_regular test -f "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_not_symlink test ! -L "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_empty test ! -s "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_pending_absent test ! -e "$retained_outbound_path/.complete.pending" || exit 1
record_check retained_complete_pending_not_symlink test ! -L "$retained_outbound_path/.complete.pending" || exit 1
sync_tree_before=$(tree_digest "$sync_root")
readonly sync_tree_before
record_check sync_tree_before_hash_valid valid_sha256 "$sync_tree_before" || exit 1
for action28b_unit in "${continuity_units[@]}"; do
    action28b_unit_label=${action28b_unit//[-.]/_}
    for action28b_property in "${continuity_properties[@]}"; do
        action28b_value=$(unit_property "$action28b_property" "$action28b_unit") || exit 1
        record_check "pre_${action28b_unit_label}_${action28b_property}_observed" \
            test -n "$action28b_value" || exit 1
        state_before["$action28b_unit:$action28b_property"]=$action28b_value
    done
done

mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
install -d -o "$install_owner" -g "$install_group" -m 0700 "$backup_directory"
record_check backup_directory_created test \
    "$(stat -c '%U:%G:%a' "$backup_directory")" = "$expected_owner:700" || exit 1
printf '%s\n' \
    'action=28b' \
    'node=j1-svpihole0' \
    'publisher_pre_state=absent' \
    "publisher_candidate_sha256=$expected_publisher_sha256" \
    >"$backup_directory/manifest"
chmod 0600 "$backup_directory/manifest"
record_check backup_manifest_created test -f "$backup_directory/manifest" || exit 1
expected_manifest=$(printf '%s\n' \
    'action=28b' \
    'node=j1-svpihole0' \
    'publisher_pre_state=absent' \
    "publisher_candidate_sha256=$expected_publisher_sha256")
readonly expected_manifest
record_check backup_manifest_exact test \
    "$(<"$backup_directory/manifest")" = "$expected_manifest" || exit 1
publisher_install_stage=$(mktemp "$libexec_directory/.publish-release-v2.action28b.XXXXXX")
record_check publisher_install_stage_created test -f "$publisher_install_stage" || exit 1
install -o "$install_owner" -g "$install_group" -m 0755 \
    "$publisher_source" "$publisher_install_stage"
mv -fT -- "$publisher_install_stage" "$publisher"
publisher_install_stage=
record_check live_publisher_regular test -f "$publisher" || exit 1
record_check live_publisher_not_symlink test ! -L "$publisher" || exit 1
record_check live_publisher_metadata test \
    "$(stat -c '%U:%G:%a' "$publisher")" = "$expected_owner:755" || exit 1
record_check live_publisher_hash_exact test \
    "$(file_hash "$publisher")" = "$expected_publisher_sha256" || exit 1
record_check live_publisher_syntax /bin/bash -n "$publisher" || exit 1
record_check live_publisher_node_b_emergency_gate grep -Fq \
    'Node B publishing requires --emergency.' "$publisher" || exit 1
record_check live_publisher_node_b_master_gate grep -Fq \
    'Node B may publish only while CADDY_DUALSTACK is MASTER.' "$publisher" || exit 1
if [[ "$test_mode" == true && "${CADDY_ACTION28B_FAIL_AFTER_INSTALL:-}" == 1 ]]; then
    record_check post_install_boundary false || exit 1
else
    record_check post_install_boundary true || exit 1
fi
record_check backup_directory_retained test -d "$backup_directory" || exit 1
record_check backup_manifest_retained test -f "$backup_directory/manifest" || exit 1
record_check backup_manifest_still_exact test \
    "$(<"$backup_directory/manifest")" = "$expected_manifest" || exit 1
record_check install_stage_residue_absent_after test -z \
    "$(find "$libexec_directory" -mindepth 1 -maxdepth 1 \
        -name '.publish-release-v2.action28b.*' -print -quit)" || exit 1
record_check sync_tree_unchanged test "$(tree_digest "$sync_root")" = "$sync_tree_before" || exit 1
record_check current_link_unchanged test "$(readlink "$current_link")" = "$current_link_before" || exit 1
record_check current_target_unchanged test "$(resolve_current_target)" = "$current_target_before" || exit 1
record_check service_state_unchanged continuity_unchanged || exit 1
record_check vrrp_master_after test "$(vrrp_state)" = MASTER || exit 1
record_check outbound_root_metadata_unchanged test "$(stat -c '%u:%g:%a:%s:%Y' "$outbound_root")" = "$retained_outbound_root_metadata" || exit 1
record_check outbound_child_count_unchanged test "$(find "$outbound_root" -mindepth 1 -maxdepth 1 -printf '.' | wc -c)" -eq 1 || exit 1
record_check retained_child_directory_after test -d "$retained_outbound_path" || exit 1
record_check retained_child_not_symlink_after test ! -L "$retained_outbound_path" || exit 1
record_check retained_child_metadata_unchanged test "$(stat -c '%u:%g:%a:%s:%Y' "$retained_outbound_path")" = "$retained_outbound_child_metadata" || exit 1
record_check retained_child_tree_hash_unchanged test "$(tree_digest "$retained_outbound_path")" = "$retained_outbound_tree_sha256" || exit 1
record_check retained_finalize_request_absent_after test ! -e "$retained_outbound_path/.finalize-request" || exit 1
record_check retained_finalize_request_not_symlink_after test ! -L "$retained_outbound_path/.finalize-request" || exit 1
record_check retained_complete_regular_after test -f "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_not_symlink_after test ! -L "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_empty_after test ! -s "$retained_outbound_path/.complete" || exit 1
record_check retained_complete_pending_absent_after test ! -e "$retained_outbound_path/.complete.pending" || exit 1
record_check retained_complete_pending_not_symlink_after test ! -L "$retained_outbound_path/.complete.pending" || exit 1

expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
[[ "${#seen_checks[@]}" -eq "$expected_count" ]] || exit 97
transaction_complete=true
printf '%s_value_publisher_sha256=%s\n' "$prefix" "$expected_publisher_sha256"
printf '%s_value_backup_path=/var/backups/caddy-ha/action28b-node-a-publisher\n' "$prefix"
printf '%s_value_publisher_pre_state=absent\n' "$prefix"
printf '%s_value_retained_outbound_name=%s\n' "$prefix" "$retained_outbound_name"
printf '%s_value_retained_outbound_tree_sha256=%s\n' "$prefix" "$retained_outbound_tree_sha256"
printf '%s_check_count=%s\n' "$prefix" "$expected_count"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_rollback_invoked=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_lsyncd_reconciliation_activation=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
