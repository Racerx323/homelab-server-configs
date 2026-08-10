#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28b_a
readonly expected_hostname=j1-svpihole0
readonly expected_publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
expected_owner=root:root
expected_outbound_root_metadata=994:990:750:4096:1785461698
expected_outbound_child_metadata=994:990:550:4096:1785461697
expected_outbound_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_a_ipv4_cidr=10.1.0.53/22
readonly node_a_ipv6_cidr=fd36:5aa8:6971:1::53/64
readonly -a required_commands=(
    awk base64 basename find hostname id ip mktemp readlink sed sha256sum sort stat systemctl wc xargs
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
readonly -a common_properties=(ActiveState SubState UnitFileState)
readonly -a service_properties=(MainPID NRestarts)

declare -A seen_checks=()
declare -A state_before=()
test_mode=false
root_prefix=
inventory_count=0
inventory_sha256=
stage_residue_count=0
sync_tree_before=
current_link_before=
current_target_before=
current_tree_before=

root_path() { printf '%s%s\n' "$root_prefix" "$1"; }
file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
record_check() {
    local action28b_a_check_label=$1

    shift
    if [[ -n "${seen_checks[$action28b_a_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action28b_a_check_label" >&2
        return 1
    fi
    seen_checks[$action28b_a_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action28b_a_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28b_a_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action28b_a_check_label" >&2
    return 1
}
effective_uid() {
    if [[ "$test_mode" == true ]]; then
        printf '0\n'
    else
        id -u
    fi
}
node_hostname() {
    if [[ "$test_mode" == true ]]; then
        printf '%s\n' "$expected_hostname"
    else
        hostname
    fi
}
unit_property() {
    local action28b_a_property=$1
    local action28b_a_unit=$2

    if [[ "$test_mode" == true ]]; then
        case "$action28b_a_property" in
            ActiveState)
                case "$action28b_a_unit" in
                    caddy.service | lighttpd.service | keepalived.service) printf 'active\n' ;;
                    *) printf 'inactive\n' ;;
                esac
                ;;
            SubState)
                case "$action28b_a_unit" in
                    caddy.service | lighttpd.service | keepalived.service) printf 'running\n' ;;
                    *) printf 'dead\n' ;;
                esac
                ;;
            UnitFileState)
                case "$action28b_a_unit" in
                    caddy.service | lighttpd.service | keepalived.service) printf 'enabled\n' ;;
                    lsyncd.service) printf 'masked\n' ;;
                    *) printf 'disabled\n' ;;
                esac
                ;;
            MainPID) printf '4242\n' ;;
            NRestarts) printf '0\n' ;;
            *) return 1 ;;
        esac
        return 0
    fi
    if [[ "$action28b_a_property" == UnitFileState ]]; then
        systemctl is-enabled "$action28b_a_unit" 2>/dev/null || true
        return 0
    fi
    systemctl show "$action28b_a_unit" --no-pager \
        --property "$action28b_a_property" --value
}
unit_active() { [[ "$(unit_property ActiveState "$1")" == active ]]; }
unit_inactive() { [[ "$(unit_property ActiveState "$1")" == inactive ]]; }
vrrp_state() { sed -n '1p' "$(root_path /run/caddy-ha/vrrp-state)" 2>/dev/null; }
address_count() {
    local action28b_a_family=$1
    local action28b_a_cidr=$2

    if [[ "$test_mode" == true ]]; then
        case "$action28b_a_cidr" in
            "$caddy_ipv4_cidr" | "$caddy_ipv6_cidr" | "$dns_ipv4_cidr" | \
                "$dns_ipv6_cidr" | "$node_a_ipv4_cidr" | "$node_a_ipv6_cidr")
                printf '1\n'
                ;;
            *) printf '0\n' ;;
        esac
        return 0
    fi
    ip -o "-$action28b_a_family" address show dev "$interface" |
        awk -v wanted="$action28b_a_cidr" \
            '$4 == wanted { count++ } END { print count + 0 }'
}
resolve_current_target() {
    local action28b_a_link
    local action28b_a_value

    action28b_a_link=$(root_path /etc/caddy/current)
    action28b_a_value=$(readlink "$action28b_a_link") || return 1
    if [[ "$test_mode" == true && "$action28b_a_value" == /* ]]; then
        readlink -e "$root_prefix$action28b_a_value"
    else
        readlink -e "$action28b_a_link"
    fi
}
tree_digest() {
    local action28b_a_tree_root=$1

    (
        cd "$action28b_a_tree_root"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
marker_state() {
    local action28b_a_marker=$1

    if [[ ! -e "$action28b_a_marker" && ! -L "$action28b_a_marker" ]]; then
        printf 'absent\n'
    elif [[ -f "$action28b_a_marker" && ! -L "$action28b_a_marker" &&
        ! -s "$action28b_a_marker" ]]; then
        printf 'regular_empty\n'
    elif [[ -f "$action28b_a_marker" && ! -L "$action28b_a_marker" ]]; then
        printf 'regular_nonempty\n'
    else
        printf 'other\n'
    fi
}
capture_inventory() {
    local action28b_a_outbound=$1
    local action28b_a_records=$2
    local action28b_a_emit_records=$3
    local action28b_a_child
    local action28b_a_content_hash
    local action28b_a_index=0
    local action28b_a_kind
    local action28b_a_metadata
    local action28b_a_name_b64
    local action28b_a_record
    local action28b_a_record_b64
    local -a action28b_a_children=()

    mapfile -d '' action28b_a_children < <(
        find "$action28b_a_outbound" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z
    ) || return 1
    : >"$action28b_a_records" || return 1
    for action28b_a_child in "${action28b_a_children[@]}"; do
        action28b_a_index=$((action28b_a_index + 1))
        action28b_a_kind=$(stat -c '%F' -- "$action28b_a_child") || return 1
        action28b_a_metadata=$(stat -c '%u:%g:%a:%s:%Y' -- "$action28b_a_child") || return 1
        action28b_a_name_b64=$(basename -- "$action28b_a_child" | base64 -w 0) || return 1
        if [[ -d "$action28b_a_child" && ! -L "$action28b_a_child" ]]; then
            action28b_a_content_hash=$(tree_digest "$action28b_a_child") || return 1
        elif [[ -f "$action28b_a_child" && ! -L "$action28b_a_child" ]]; then
            action28b_a_content_hash=$(file_hash "$action28b_a_child") || return 1
        else
            action28b_a_content_hash=unavailable
        fi
        action28b_a_record=$(printf '%04d|%s|%s|%s|%s|%s|%s|%s' \
            "$action28b_a_index" "$action28b_a_name_b64" \
            "$(printf '%s' "$action28b_a_kind" | base64 -w 0)" \
            "$action28b_a_metadata" "$action28b_a_content_hash" \
            "$(marker_state "$action28b_a_child/.finalize-request")" \
            "$(marker_state "$action28b_a_child/.complete")" \
            "$(marker_state "$action28b_a_child/.complete.pending")") || return 1
        printf '%s\n' "$action28b_a_record" >>"$action28b_a_records" || return 1
        if [[ "$action28b_a_emit_records" == true ]]; then
            action28b_a_record_b64=$(printf '%s' "$action28b_a_record" | base64 -w 0) || return 1
            printf '%s_value_outbound_child_%04d_b64=%s\n' \
                "$prefix" "$action28b_a_index" "$action28b_a_record_b64"
        fi
    done
    inventory_count=$action28b_a_index
    inventory_sha256=$(file_hash "$action28b_a_records") || return 1
}
emit_expected_checks() {
    local action28b_a_command
    local action28b_a_property
    local action28b_a_unit
    local action28b_a_unit_label

    for action28b_a_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action28b_a_command//-/_}"
    done
    printf '%s\n' \
        uid_root working_directory_root hostname_node_a publisher_regular \
        publisher_not_symlink publisher_metadata publisher_hash_exact publisher_syntax \
        publisher_node_b_emergency_gate publisher_node_b_master_gate \
        action28b_backup_directory action28b_backup_not_symlink action28b_backup_metadata \
        action28b_manifest_regular action28b_manifest_not_symlink action28b_manifest_metadata \
        action28b_manifest_exact \
        install_stage_residue_absent outbound_root_directory outbound_root_not_symlink \
        outbound_root_metadata_exact outbound_inventory_capture \
        outbound_child_count_exact outbound_inventory_hash_valid outbound_child_exact \
        sync_tree_before_hash_valid current_link_symlink current_target_directory \
        current_target_not_symlink current_manifest_regular current_complete_regular \
        current_complete_empty current_tree_before_hash_valid caddy_active_before \
        lighttpd_active_before keepalived_active_before lsyncd_inactive_before \
        caddy_lsyncd_inactive_before reconcile_path_inactive_before \
        reconcile_service_inactive_before vrrp_master_before \
        caddy_ipv4_query_success caddy_ipv6_query_success \
        dns_ipv4_query_success dns_ipv6_query_success \
        node_a_ipv4_query_success node_a_ipv6_query_success \
        caddy_ipv4_owned caddy_ipv6_owned dns_ipv4_owned \
        dns_ipv6_owned node_a_ipv4_owned node_a_ipv6_owned
    for action28b_a_unit in "${continuity_units[@]}"; do
        action28b_a_unit_label=${action28b_a_unit//[-.]/_}
        for action28b_a_property in "${common_properties[@]}"; do
            printf 'pre_%s_%s_observed\n' "$action28b_a_unit_label" "$action28b_a_property"
        done
        if [[ "$action28b_a_unit" == *.service ]]; then
            for action28b_a_property in "${service_properties[@]}"; do
                printf 'pre_%s_%s_observed\n' "$action28b_a_unit_label" "$action28b_a_property"
            done
        fi
    done
    printf '%s\n' \
        publisher_still_regular publisher_metadata_unchanged publisher_hash_unchanged \
        action28b_backup_still_directory action28b_manifest_still_exact \
        install_stage_residue_still_absent outbound_inventory_recapture \
        outbound_inventory_count_unchanged outbound_inventory_hash_unchanged \
        sync_tree_unchanged current_link_unchanged \
        current_target_unchanged current_tree_unchanged service_state_unchanged \
        vrrp_master_after caddy_ipv4_still_owned caddy_ipv6_still_owned \
        dns_ipv4_still_owned dns_ipv6_still_owned node_a_ipv4_still_owned \
        node_a_ipv6_still_owned
}
continuity_unchanged() {
    local action28b_a_property
    local action28b_a_unit
    local action28b_a_value

    # conditional-validator-explicit-failures-begin
    for action28b_a_unit in "${continuity_units[@]}"; do
        for action28b_a_property in "${common_properties[@]}"; do
            action28b_a_value=$(unit_property "$action28b_a_property" "$action28b_a_unit") || return 1
            [[ "$action28b_a_value" == "${state_before["$action28b_a_unit:$action28b_a_property"]}" ]] || return 1
        done
        if [[ "$action28b_a_unit" == *.service ]]; then
            for action28b_a_property in "${service_properties[@]}"; do
                action28b_a_value=$(unit_property "$action28b_a_property" "$action28b_a_unit") || return 1
                [[ "$action28b_a_value" == "${state_before["$action28b_a_unit:$action28b_a_property"]}" ]] || return 1
            done
        fi
    done
    # conditional-validator-explicit-failures-end
}
cleanup() {
    local action28b_a_cleanup_status=$?

    [[ -z "${work_root:-}" || ! -d "$work_root" ]] || rm -rf -- "$work_root"
    exit "$action28b_a_cleanup_status"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        emit_expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(emit_expected_checks | wc -l)" -eq "$(emit_expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --fixture-root)
        [[ $# -eq 2 && "${CADDY_ACTION28B_A_TEST_MODE:-}" == 1 ]] || exit 64
        test_mode=true
        expected_owner="$(id -un):$(id -gn)"
        expected_outbound_root_metadata=${CADDY_ACTION28B_A_TEST_ROOT_METADATA:?}
        expected_outbound_child_metadata=${CADDY_ACTION28B_A_TEST_CHILD_METADATA:?}
        expected_outbound_tree_sha256=${CADDY_ACTION28B_A_TEST_TREE_SHA256:?}
        root_prefix=$2
        ;;
    *) [[ $# -eq 0 ]] || exit 64 ;;
esac
readonly test_mode root_prefix expected_owner
readonly expected_outbound_root_metadata expected_outbound_child_metadata
readonly expected_outbound_tree_sha256
publisher=$(root_path /usr/local/libexec/publish-release-v2.sh)
backup=$(root_path /var/backups/caddy-ha/action28b-node-a-publisher)
libexec=$(root_path /usr/local/libexec)
outbound=$(root_path /var/lib/caddy-sync/outbound)
sync_root=$(root_path /var/lib/caddy-sync)
current=$(root_path /etc/caddy/current)
readonly publisher backup libexec outbound sync_root current

work_root=$(mktemp -d /tmp/caddy-action28b-a.XXXXXX)
readonly work_root
trap cleanup EXIT
inventory_before_file=$work_root/inventory.before
inventory_after_file=$work_root/inventory.after
readonly inventory_before_file inventory_after_file

for action28b_a_command in "${required_commands[@]}"; do
    record_check "command_${action28b_a_command//-/_}_available" \
        command -v "$action28b_a_command" || exit 1
done
record_check uid_root test "$(effective_uid)" -eq 0 || exit 1
record_check working_directory_root test "$PWD" = / || exit 1
record_check hostname_node_a test "$(node_hostname)" = "$expected_hostname" || exit 1
record_check publisher_regular test -f "$publisher" || exit 1
record_check publisher_not_symlink test ! -L "$publisher" || exit 1
record_check publisher_metadata test \
    "$(stat -c '%U:%G:%a' "$publisher")" = "$expected_owner:755" || exit 1
record_check publisher_hash_exact test \
    "$(file_hash "$publisher")" = "$expected_publisher_sha256" || exit 1
record_check publisher_syntax /bin/bash -n "$publisher" || exit 1
record_check publisher_node_b_emergency_gate grep -Fq \
    'Node B publishing requires --emergency.' "$publisher" || exit 1
record_check publisher_node_b_master_gate grep -Fq \
    'Node B may publish only while CADDY_DUALSTACK is MASTER.' "$publisher" || exit 1
record_check action28b_backup_directory test -d "$backup" || exit 1
record_check action28b_backup_not_symlink test ! -L "$backup" || exit 1
record_check action28b_backup_metadata test \
    "$(stat -c '%U:%G:%a' "$backup")" = "$expected_owner:700" || exit 1
record_check action28b_manifest_regular test -f "$backup/manifest" || exit 1
record_check action28b_manifest_not_symlink test ! -L "$backup/manifest" || exit 1
record_check action28b_manifest_metadata test \
    "$(stat -c '%U:%G:%a' "$backup/manifest")" = "$expected_owner:600" || exit 1
expected_manifest=$(printf '%s\n' \
    'action=28b' \
    'node=j1-svpihole0' \
    'publisher_pre_state=absent' \
    "publisher_candidate_sha256=$expected_publisher_sha256")
readonly expected_manifest
record_check action28b_manifest_exact test \
    "$(<"$backup/manifest")" = "$expected_manifest" || exit 1
stage_residue_count=$(find "$libexec" -mindepth 1 -maxdepth 1 \
    -name '.publish-release-v2.action28b.*' -print | wc -l)
readonly stage_residue_count
record_check install_stage_residue_absent test "$stage_residue_count" -eq 0 || exit 1
record_check outbound_root_directory test -d "$outbound" || exit 1
record_check outbound_root_not_symlink test ! -L "$outbound" || exit 1
outbound_root_metadata=$(stat -c '%u:%g:%a:%s:%Y' "$outbound")
readonly outbound_root_metadata
record_check outbound_root_metadata_exact test \
    "$outbound_root_metadata" = "$expected_outbound_root_metadata" || exit 1
record_check outbound_inventory_capture capture_inventory \
    "$outbound" "$inventory_before_file" true || exit 1
inventory_count_before=$inventory_count
inventory_sha256_before=$inventory_sha256
readonly inventory_count_before inventory_sha256_before
record_check outbound_child_count_exact test "$inventory_count_before" -eq 1 || exit 1
record_check outbound_inventory_hash_valid valid_sha256 "$inventory_sha256_before" || exit 1
expected_child_record=$(printf '0001|%s|%s|%s|%s|absent|regular_empty|absent' \
    "$(printf '%s\n' action17p-node-a-to-node-b-bootstrap | base64 -w 0)" \
    "$(printf '%s' directory | base64 -w 0)" \
    "$expected_outbound_child_metadata" "$expected_outbound_tree_sha256")
readonly expected_child_record
record_check outbound_child_exact grep -Fqx "$expected_child_record" "$inventory_before_file" || exit 1
sync_tree_before=$(tree_digest "$sync_root")
readonly sync_tree_before
record_check sync_tree_before_hash_valid valid_sha256 "$sync_tree_before" || exit 1
record_check current_link_symlink test -L "$current" || exit 1
current_link_before=$(readlink "$current")
readonly current_link_before
current_target_before=$(resolve_current_target)
readonly current_target_before
record_check current_target_directory test -d "$current_target_before" || exit 1
record_check current_target_not_symlink test ! -L "$current_target_before" || exit 1
record_check current_manifest_regular test -f "$current_target_before/release-manifest.json" || exit 1
record_check current_complete_regular test -f "$current_target_before/.complete" || exit 1
record_check current_complete_empty test ! -s "$current_target_before/.complete" || exit 1
current_tree_before=$(tree_digest "$current_target_before")
readonly current_tree_before
record_check current_tree_before_hash_valid valid_sha256 "$current_tree_before" || exit 1
record_check caddy_active_before unit_active caddy.service || exit 1
record_check lighttpd_active_before unit_active lighttpd.service || exit 1
record_check keepalived_active_before unit_active keepalived.service || exit 1
record_check lsyncd_inactive_before unit_inactive lsyncd.service || exit 1
record_check caddy_lsyncd_inactive_before unit_inactive caddy-lsyncd.service || exit 1
record_check reconcile_path_inactive_before unit_inactive caddy-sync-reconcile.path || exit 1
record_check reconcile_service_inactive_before unit_inactive caddy-sync-reconcile.service || exit 1
record_check vrrp_master_before test "$(vrrp_state)" = MASTER || exit 1
caddy_ipv4_status=0
caddy_ipv6_status=0
dns_ipv4_status=0
dns_ipv6_status=0
node_a_ipv4_status=0
node_a_ipv6_status=0
caddy_ipv4_count=$(address_count 4 "$caddy_ipv4_cidr") || caddy_ipv4_status=$?
caddy_ipv6_count=$(address_count 6 "$caddy_ipv6_cidr") || caddy_ipv6_status=$?
dns_ipv4_count=$(address_count 4 "$dns_ipv4_cidr") || dns_ipv4_status=$?
dns_ipv6_count=$(address_count 6 "$dns_ipv6_cidr") || dns_ipv6_status=$?
node_a_ipv4_count=$(address_count 4 "$node_a_ipv4_cidr") || node_a_ipv4_status=$?
node_a_ipv6_count=$(address_count 6 "$node_a_ipv6_cidr") || node_a_ipv6_status=$?
readonly caddy_ipv4_status caddy_ipv6_status dns_ipv4_status dns_ipv6_status
readonly node_a_ipv4_status node_a_ipv6_status
readonly caddy_ipv4_count caddy_ipv6_count dns_ipv4_count dns_ipv6_count
readonly node_a_ipv4_count node_a_ipv6_count
record_check caddy_ipv4_query_success test "$caddy_ipv4_status" -eq 0 || exit 1
record_check caddy_ipv6_query_success test "$caddy_ipv6_status" -eq 0 || exit 1
record_check dns_ipv4_query_success test "$dns_ipv4_status" -eq 0 || exit 1
record_check dns_ipv6_query_success test "$dns_ipv6_status" -eq 0 || exit 1
record_check node_a_ipv4_query_success test "$node_a_ipv4_status" -eq 0 || exit 1
record_check node_a_ipv6_query_success test "$node_a_ipv6_status" -eq 0 || exit 1
record_check caddy_ipv4_owned test "$caddy_ipv4_count" -eq 1 || exit 1
record_check caddy_ipv6_owned test "$caddy_ipv6_count" -eq 1 || exit 1
record_check dns_ipv4_owned test "$dns_ipv4_count" -eq 1 || exit 1
record_check dns_ipv6_owned test "$dns_ipv6_count" -eq 1 || exit 1
record_check node_a_ipv4_owned test "$node_a_ipv4_count" -eq 1 || exit 1
record_check node_a_ipv6_owned test "$node_a_ipv6_count" -eq 1 || exit 1
for action28b_a_unit in "${continuity_units[@]}"; do
    action28b_a_unit_label=${action28b_a_unit//[-.]/_}
    for action28b_a_property in "${common_properties[@]}"; do
        action28b_a_value=$(unit_property "$action28b_a_property" "$action28b_a_unit") || exit 1
        record_check "pre_${action28b_a_unit_label}_${action28b_a_property}_observed" \
            test -n "$action28b_a_value" || exit 1
        state_before["$action28b_a_unit:$action28b_a_property"]=$action28b_a_value
    done
    if [[ "$action28b_a_unit" == *.service ]]; then
        for action28b_a_property in "${service_properties[@]}"; do
            action28b_a_value=$(unit_property "$action28b_a_property" "$action28b_a_unit") || exit 1
            record_check "pre_${action28b_a_unit_label}_${action28b_a_property}_observed" \
                test -n "$action28b_a_value" || exit 1
            state_before["$action28b_a_unit:$action28b_a_property"]=$action28b_a_value
        done
    fi
done

record_check publisher_still_regular test -f "$publisher" || exit 1
record_check publisher_metadata_unchanged test \
    "$(stat -c '%U:%G:%a' "$publisher")" = "$expected_owner:755" || exit 1
record_check publisher_hash_unchanged test \
    "$(file_hash "$publisher")" = "$expected_publisher_sha256" || exit 1
record_check action28b_backup_still_directory test -d "$backup" || exit 1
record_check action28b_manifest_still_exact test \
    "$(<"$backup/manifest")" = "$expected_manifest" || exit 1
record_check install_stage_residue_still_absent test \
    "$(find "$libexec" -mindepth 1 -maxdepth 1 \
        -name '.publish-release-v2.action28b.*' -print | wc -l)" -eq 0 || exit 1
record_check outbound_inventory_recapture capture_inventory \
    "$outbound" "$inventory_after_file" false || exit 1
record_check outbound_inventory_count_unchanged test \
    "$inventory_count" -eq "$inventory_count_before" || exit 1
record_check outbound_inventory_hash_unchanged test \
    "$inventory_sha256" = "$inventory_sha256_before" || exit 1
record_check sync_tree_unchanged test "$(tree_digest "$sync_root")" = "$sync_tree_before" || exit 1
record_check current_link_unchanged test "$(readlink "$current")" = "$current_link_before" || exit 1
record_check current_target_unchanged test "$(resolve_current_target)" = "$current_target_before" || exit 1
record_check current_tree_unchanged test \
    "$(tree_digest "$current_target_before")" = "$current_tree_before" || exit 1
record_check service_state_unchanged continuity_unchanged || exit 1
record_check vrrp_master_after test "$(vrrp_state)" = MASTER || exit 1
record_check caddy_ipv4_still_owned test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || exit 1
record_check caddy_ipv6_still_owned test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || exit 1
record_check dns_ipv4_still_owned test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 || exit 1
record_check dns_ipv6_still_owned test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 || exit 1
record_check node_a_ipv4_still_owned test "$(address_count 4 "$node_a_ipv4_cidr")" -eq 1 || exit 1
record_check node_a_ipv6_still_owned test "$(address_count 6 "$node_a_ipv6_cidr")" -eq 1 || exit 1

expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
[[ "${#seen_checks[@]}" -eq "$expected_count" ]] || exit 97
printf '%s_value_outbound_root_metadata=%s\n' "$prefix" "$outbound_root_metadata"
printf '%s_value_publisher_sha256=%s\n' "$prefix" "$expected_publisher_sha256"
printf '%s_value_backup_path=/var/backups/caddy-ha/action28b-node-a-publisher\n' "$prefix"
printf '%s_value_retained_outbound_name=action17p-node-a-to-node-b-bootstrap\n' "$prefix"
printf '%s_value_retained_outbound_tree_sha256=%s\n' "$prefix" "$expected_outbound_tree_sha256"
printf '%s_value_outbound_child_count=%s\n' "$prefix" "$inventory_count_before"
printf '%s_value_outbound_inventory_sha256=%s\n' "$prefix" "$inventory_sha256_before"
printf '%s_value_sync_tree_sha256=%s\n' "$prefix" "$sync_tree_before"
printf '%s_value_current_link=%s\n' "$prefix" "$current_link_before"
printf '%s_value_current_tree_sha256=%s\n' "$prefix" "$current_tree_before"
printf '%s_value_install_stage_residue_count=%s\n' "$prefix" "$stage_residue_count"
printf '%s_check_count=%s\n' "$prefix" "$expected_count"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_action_28b_rerun=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
