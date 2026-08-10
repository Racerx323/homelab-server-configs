#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_b
readonly historical_name=action17p-node-a-to-node-b-bootstrap
readonly historical_outbound_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly historical_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly accepted_current_tree_sha256=b7f3dfba3b0dc2aa278f0d1e6dd02fc7d2be6ef0eb656f12f7bc7288df12ebd9
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly -a continuity_units=(
    caddy.service
    lighttpd.service
    keepalived.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)

declare -A seen_checks=()
root_prefix=
test_mode=false
role=
expected_hostname=
release_root=
historical_release=
expected_vrrp=
physical_ipv4_cidr=
physical_ipv6_cidr=
candidate_name=absent
candidate_revision=absent
candidate_parent=absent
candidate_manifest_sha256=absent
candidate_payload_manifest_sha256=absent
candidate_tree_sha256=absent
candidate_metadata=absent
candidate_request_state=absent
candidate_complete_state=absent
candidate_pending_state=absent
candidate_state=absent
snapshot_before=

root_path() { printf '%s%s\n' "$root_prefix" "$1"; }
file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
record_check() {
    local action28e_b_label=$1

    shift
    if [[ -n "${seen_checks[$action28e_b_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action28e_b_label" >&2
        return 1
    fi
    seen_checks[$action28e_b_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_b_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_b_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action28e_b_label" >&2
    return 1
}
valid_revision() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
marker_state() {
    local action28e_b_marker=$1

    if [[ ! -e "$action28e_b_marker" && ! -L "$action28e_b_marker" ]]; then
        printf 'absent\n'
    elif [[ -f "$action28e_b_marker" && ! -L "$action28e_b_marker" &&
        ! -s "$action28e_b_marker" ]]; then
        printf 'regular_empty\n'
    else
        printf 'other\n'
    fi
}
tree_digest() {
    local action28e_b_tree=$1

    (
        cd "$action28e_b_tree"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
manifest_paths_safe() {
    awk '
        length($0) == 0 { bad = 1; next }
        {
            hash = substr($0, 1, 64)
            separator = substr($0, 65, 2)
            path = substr($0, 67)
            if (length(hash) != 64 || hash !~ /^[0-9a-f]+$/ ||
                separator != "  " || path !~ /^[.][/][^[:cntrl:]]+$/ ||
                path ~ /(^|[/])[.][.]([/]|$)/ || path ~ /[/][/]/ ||
                path ~ /[/][.]([/]|$)/ || path ~ /[/]$/) bad = 1
        }
        END { exit bad ? 1 : 0 }
    ' "$1"
}
manifest_file_set_matches() {
    local action28e_b_release=$1
    local action28e_b_expected
    local action28e_b_observed

    action28e_b_expected=$(mktemp /tmp/action28e-b-expected.XXXXXX) || return 1
    action28e_b_observed=$(mktemp /tmp/action28e-b-observed.XXXXXX) || {
        rm -f -- "$action28e_b_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action28e_b_release/manifest.sha256" |
        LC_ALL=C sort -u >"$action28e_b_expected"
    (
        cd "$action28e_b_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print | LC_ALL=C sort
    ) >"$action28e_b_observed"
    local action28e_b_status=0
    cmp -s "$action28e_b_expected" "$action28e_b_observed" || action28e_b_status=$?
    rm -f -- "$action28e_b_expected" "$action28e_b_observed"
    return "$action28e_b_status"
}
manifest_hashes_valid() {
    local action28e_b_release=$1

    (cd "$action28e_b_release" && sha256sum --strict --check manifest.sha256 >/dev/null)
}
current_tree_accepted() {
    local action28e_b_observed_tree

    action28e_b_observed_tree=$(tree_digest "$(root_path /etc/caddy/current)") || return 1
    if [[ "$role" == node-a ]]; then
        [[ "$action28e_b_observed_tree" = "$accepted_current_tree_sha256" ]]
    else
        valid_sha256 "$action28e_b_observed_tree"
    fi
}
unit_state() {
    local action28e_b_unit=$1

    if [[ "$test_mode" == true ]]; then
        case "$action28e_b_unit" in
            caddy.service | lighttpd.service | keepalived.service) printf 'active\n' ;;
            *) printf 'inactive\n' ;;
        esac
    else
        systemctl show "$action28e_b_unit" --no-pager --property ActiveState --value
    fi
}
address_count() {
    local action28e_b_family=$1
    local action28e_b_cidr=$2

    if [[ "$test_mode" == true ]]; then
        if [[ "$action28e_b_cidr" == "$physical_ipv4_cidr" ||
            "$action28e_b_cidr" == "$physical_ipv6_cidr" ]]; then
            printf '1\n'
        elif [[ "$role" == node-a ]]; then
            printf '1\n'
        else
            printf '0\n'
        fi
        return 0
    fi
    case "$action28e_b_family" in
        4) ip -o -4 addr show dev "$interface" | awk -v cidr="$action28e_b_cidr" '$4 == cidr { count++ } END { print count + 0 }' ;;
        6) ip -o -6 addr show dev "$interface" | awk -v cidr="$action28e_b_cidr" '$4 == cidr { count++ } END { print count + 0 }' ;;
        *) return 1 ;;
    esac
}
vrrp_state() {
    if [[ "$test_mode" == true ]]; then
        printf '%s\n' "$expected_vrrp"
    else
        sed -n '1p' "$(root_path /run/caddy-ha/vrrp-state)"
    fi
}
snapshot() {
    local action28e_b_unit
    local action28e_b_current

    action28e_b_current=$(root_path /etc/caddy/current)
    {
        printf 'hostname=%s\n' "$expected_hostname"
        printf 'vrrp=%s\n' "$(vrrp_state)"
        printf 'current_link=%s\n' "$(readlink -- "$action28e_b_current")"
        printf 'current_target=%s\n' "$(readlink -f -- "$action28e_b_current")"
        printf 'current_tree=%s\n' "$(tree_digest "$action28e_b_current")"
        for action28e_b_unit in "${continuity_units[@]}"; do
            printf 'unit=%s|%s\n' "$action28e_b_unit" "$(unit_state "$action28e_b_unit")"
        done
        printf 'caddy4=%s\n' "$(address_count 4 "$caddy_ipv4_cidr")"
        printf 'caddy6=%s\n' "$(address_count 6 "$caddy_ipv6_cidr")"
        printf 'dns4=%s\n' "$(address_count 4 "$dns_ipv4_cidr")"
        printf 'dns6=%s\n' "$(address_count 6 "$dns_ipv6_cidr")"
        printf 'physical4=%s\n' "$(address_count 4 "$physical_ipv4_cidr")"
        printf 'physical6=%s\n' "$(address_count 6 "$physical_ipv6_cidr")"
        find "$release_root" -mindepth 1 -maxdepth 2 \
            -printf 'release=%P|%y|%m|%u|%g|%s\n' | LC_ALL=C sort
    } | sha256sum | awk '{ print $1 }'
}
expected_checks() {
    printf '%s\n' \
        root_identity hostname_exact release_root_directory release_root_not_symlink \
        historical_directory historical_not_symlink historical_request_state \
        historical_complete_regular historical_complete_empty historical_pending_absent \
        historical_integrity_exact hidden_stage_residue_absent candidate_count_bounded \
        current_directory current_symlink current_target_directory current_tree_accepted \
        caddy_active lighttpd_active keepalived_active lsyncd_inactive \
        caddy_lsyncd_inactive reconcile_path_inactive reconcile_service_inactive \
        vrrp_state_exact caddy_ipv4_ownership caddy_ipv6_ownership dns_ipv4_ownership \
        dns_ipv6_ownership physical_ipv4_ownership physical_ipv6_ownership \
        candidate_name_safe candidate_directory candidate_not_symlink \
        candidate_manifest_regular candidate_manifest_not_symlink \
        candidate_payload_manifest_regular candidate_payload_manifest_not_symlink \
        candidate_revision_exact candidate_source_node_a candidate_manifest_schema \
        candidate_paths_safe candidate_file_set_exact candidate_hashes_valid \
        candidate_symlinks_absent candidate_special_files_absent candidate_hardlinks_absent \
        candidate_directories_locked candidate_files_locked candidate_request_regular \
        candidate_request_empty candidate_pending_absent candidate_role_marker_state \
        snapshot_stable
}
configure_role() {
    case "$role" in
        node-a)
            expected_hostname=j1-svpihole0
            release_root=$(root_path /var/lib/caddy-sync/outbound)
            expected_vrrp=MASTER
            physical_ipv4_cidr=10.1.0.53/22
            physical_ipv6_cidr=fd36:5aa8:6971:1::53/64
            ;;
        node-b)
            expected_hostname=j1-svpihole00
            release_root=$(root_path /var/lib/caddy-sync/incoming/node-a)
            expected_vrrp=BACKUP
            physical_ipv4_cidr=10.1.0.54/22
            physical_ipv6_cidr=fd36:5aa8:6971:1::54/64
            ;;
        *) return 1 ;;
    esac
    historical_release=$release_root/$historical_name
}
historical_integrity() {
    [[ "$historical_observed_identity" == "$historical_expected_identity" ]]
}
emit_historical_identity_and_check() {
    printf '%s_value_historical_identity_kind=%s\n' "$prefix" "$historical_identity_kind"
    printf '%s_value_historical_expected_identity=%s\n' "$prefix" "$historical_expected_identity"
    printf '%s_value_historical_observed_identity=%s\n' "$prefix" "$historical_observed_identity"
    record_check historical_integrity_exact historical_integrity
}
historical_request_state() {
    if [[ "$role" == node-a ]]; then
        [[ ! -e "$historical_release/.finalize-request" ]]
    else
        [[ -f "$historical_release/.finalize-request" &&
            ! -L "$historical_release/.finalize-request" &&
            ! -s "$historical_release/.finalize-request" ]]
    fi
}
candidate_role_marker_state() {
    local action28e_b_release=$1

    if [[ "$role" == node-a ]]; then
        [[ ! -e "$action28e_b_release/.complete" ]]
    else
        [[ -f "$action28e_b_release/.complete" &&
            ! -L "$action28e_b_release/.complete" &&
            ! -s "$action28e_b_release/.complete" ]]
    fi
}
candidate_optional_check() {
    local action28e_b_label=$1

    shift
    if [[ "$candidate_name" == absent ]]; then
        record_check "$action28e_b_label" true
    else
        record_check "$action28e_b_label" "$@"
    fi
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-historical-identity)
        [[ $# -eq 4 && "${CADDY_ACTION28E_B_TEST_MODE:-}" == 1 ]]
        historical_identity_kind=$2
        historical_expected_identity=$3
        historical_observed_identity=$4
        readonly historical_identity_kind historical_expected_identity historical_observed_identity
        emit_historical_identity_and_check
        exit 0
        ;;
    node-a | node-b)
        [[ $# -eq 1 ]]
        role=$1
        ;;
    --test-root)
        [[ $# -eq 3 && "${CADDY_ACTION28E_B_TEST_MODE:-}" == 1 ]]
        test_mode=true
        root_prefix=$2
        role=$3
        ;;
    *) exit 64 ;;
esac

configure_role
readonly role expected_hostname release_root historical_release expected_vrrp
readonly physical_ipv4_cidr physical_ipv6_cidr

record_check root_identity test "$(if [[ "$test_mode" == true ]]; then printf 0; else id -u; fi)" -eq 0
record_check hostname_exact test "$(if [[ "$test_mode" == true ]]; then printf '%s' "$expected_hostname"; else hostname; fi)" = "$expected_hostname"
record_check release_root_directory test -d "$release_root"
record_check release_root_not_symlink test ! -L "$release_root"
record_check historical_directory test -d "$historical_release"
record_check historical_not_symlink test ! -L "$historical_release"
record_check historical_request_state historical_request_state
record_check historical_complete_regular test -f "$historical_release/.complete"
record_check historical_complete_empty test ! -s "$historical_release/.complete"
record_check historical_pending_absent test ! -e "$historical_release/.complete.pending"
if [[ "$role" == node-a ]]; then
    historical_identity_kind=tree
    historical_expected_identity=$historical_outbound_tree_sha256
    historical_observed_identity=$(tree_digest "$historical_release")
else
    historical_identity_kind=release_manifest
    historical_expected_identity=$historical_manifest_sha256
    historical_observed_identity=$(file_hash "$historical_release/release-manifest.json")
fi
readonly historical_identity_kind historical_expected_identity historical_observed_identity
emit_historical_identity_and_check
record_check hidden_stage_residue_absent test "$(find "$release_root" -mindepth 1 -maxdepth 1 -name '.*' -print | wc -l)" -eq 0
mapfile -t candidates < <(find "$release_root" -mindepth 1 -maxdepth 1 -type d ! -name "$historical_name" ! -name '.*' -printf '%f\n' | LC_ALL=C sort)
record_check candidate_count_bounded test "${#candidates[@]}" -le 1
if [[ ${#candidates[@]} -eq 1 ]]; then
    candidate_name=${candidates[0]}
fi
readonly candidate_name
readonly candidate_path=$release_root/$candidate_name
current_path=$(root_path /etc/caddy/current)
readonly current_path
record_check current_directory test -d "$current_path"
record_check current_symlink test -L "$current_path"
record_check current_target_directory test -d "$(readlink -f -- "$current_path")"
record_check current_tree_accepted current_tree_accepted
record_check caddy_active test "$(unit_state caddy.service)" = active
record_check lighttpd_active test "$(unit_state lighttpd.service)" = active
record_check keepalived_active test "$(unit_state keepalived.service)" = active
record_check lsyncd_inactive test "$(unit_state lsyncd.service)" = inactive
record_check caddy_lsyncd_inactive test "$(unit_state caddy-lsyncd.service)" = inactive
record_check reconcile_path_inactive test "$(unit_state caddy-sync-reconcile.path)" = inactive
record_check reconcile_service_inactive test "$(unit_state caddy-sync-reconcile.service)" = inactive
record_check vrrp_state_exact test "$(vrrp_state)" = "$expected_vrrp"
expected_vip_count=0
if [[ "$role" == node-a ]]; then expected_vip_count=1; fi
readonly expected_vip_count
record_check caddy_ipv4_ownership test "$(address_count 4 "$caddy_ipv4_cidr")" -eq "$expected_vip_count"
record_check caddy_ipv6_ownership test "$(address_count 6 "$caddy_ipv6_cidr")" -eq "$expected_vip_count"
record_check dns_ipv4_ownership test "$(address_count 4 "$dns_ipv4_cidr")" -eq "$expected_vip_count"
record_check dns_ipv6_ownership test "$(address_count 6 "$dns_ipv6_cidr")" -eq "$expected_vip_count"
record_check physical_ipv4_ownership test "$(address_count 4 "$physical_ipv4_cidr")" -eq 1
record_check physical_ipv6_ownership test "$(address_count 6 "$physical_ipv6_cidr")" -eq 1

candidate_optional_check candidate_name_safe valid_revision "$candidate_name"
candidate_optional_check candidate_directory test -d "$candidate_path"
candidate_optional_check candidate_not_symlink test ! -L "$candidate_path"
candidate_optional_check candidate_manifest_regular test -f "$candidate_path/release-manifest.json"
candidate_optional_check candidate_manifest_not_symlink test ! -L "$candidate_path/release-manifest.json"
candidate_optional_check candidate_payload_manifest_regular test -f "$candidate_path/manifest.sha256"
candidate_optional_check candidate_payload_manifest_not_symlink test ! -L "$candidate_path/manifest.sha256"
if [[ "$candidate_name" != absent ]]; then
    candidate_revision=$(jq -r '.revision // empty' "$candidate_path/release-manifest.json")
    candidate_parent=$(jq -r '.parent_revision // empty' "$candidate_path/release-manifest.json")
    candidate_manifest_sha256=$(file_hash "$candidate_path/release-manifest.json")
    candidate_payload_manifest_sha256=$(file_hash "$candidate_path/manifest.sha256")
    candidate_tree_sha256=$(tree_digest "$candidate_path")
    candidate_metadata=$(stat -c '%u:%g:%a:%s:%Y' "$candidate_path")
    candidate_request_state=$(marker_state "$candidate_path/.finalize-request")
    candidate_complete_state=$(marker_state "$candidate_path/.complete")
    candidate_pending_state=$(marker_state "$candidate_path/.complete.pending")
fi
readonly candidate_revision candidate_parent candidate_manifest_sha256 candidate_payload_manifest_sha256
readonly candidate_tree_sha256 candidate_metadata candidate_request_state
readonly candidate_complete_state candidate_pending_state
candidate_optional_check candidate_revision_exact test "$candidate_revision" = "$candidate_name"
candidate_optional_check candidate_source_node_a test "$(if [[ "$candidate_name" == absent ]]; then printf node-a; else jq -r '.source_node // empty' "$candidate_path/release-manifest.json"; fi)" = node-a
candidate_optional_check candidate_manifest_schema jq -e '(.revision | type == "string" and length > 0) and (.parent_revision | type == "string") and .source_node == "node-a" and (.created_at | type == "string" and length > 0)' "$candidate_path/release-manifest.json"
candidate_optional_check candidate_paths_safe manifest_paths_safe "$candidate_path/manifest.sha256"
candidate_optional_check candidate_file_set_exact manifest_file_set_matches "$candidate_path"
candidate_optional_check candidate_hashes_valid manifest_hashes_valid "$candidate_path"
candidate_optional_check candidate_symlinks_absent test -z "$(if [[ "$candidate_name" == absent ]]; then printf ''; else find "$candidate_path" -type l -print -quit; fi)"
candidate_optional_check candidate_special_files_absent test -z "$(if [[ "$candidate_name" == absent ]]; then printf ''; else find "$candidate_path" ! -type d ! -type f -print -quit; fi)"
candidate_optional_check candidate_hardlinks_absent test -z "$(if [[ "$candidate_name" == absent ]]; then printf ''; else find "$candidate_path" -type f -links +1 -print -quit; fi)"
candidate_optional_check candidate_directories_locked test -z "$(if [[ "$candidate_name" == absent ]]; then printf ''; else find "$candidate_path" -type d ! -perm 0550 -print -quit; fi)"
candidate_optional_check candidate_files_locked test -z "$(if [[ "$candidate_name" == absent ]]; then printf ''; else find "$candidate_path" -type f ! -perm 0440 -print -quit; fi)"
candidate_optional_check candidate_request_regular test -f "$candidate_path/.finalize-request"
candidate_optional_check candidate_request_empty test ! -s "$candidate_path/.finalize-request"
candidate_optional_check candidate_pending_absent test ! -e "$candidate_path/.complete.pending"
candidate_optional_check candidate_role_marker_state candidate_role_marker_state "$candidate_path"

if [[ "$candidate_name" != absent ]]; then
    if [[ "$role" == node-a ]]; then candidate_state=sender_ready; else candidate_state=receiver_finalized; fi
fi
readonly candidate_state
snapshot_before=$(snapshot)
readonly snapshot_before
record_check snapshot_stable test "$(snapshot)" = "$snapshot_before"

printf '%s_value_role=%s\n' "$prefix" "$role"
printf '%s_value_candidate_count=%s\n' "$prefix" "${#candidates[@]}"
printf '%s_value_candidate_state=%s\n' "$prefix" "$candidate_state"
printf '%s_value_candidate_revision=%s\n' "$prefix" "$candidate_revision"
printf '%s_value_candidate_parent=%s\n' "$prefix" "$candidate_parent"
printf '%s_value_candidate_manifest_sha256=%s\n' "$prefix" "$candidate_manifest_sha256"
printf '%s_value_candidate_payload_manifest_sha256=%s\n' "$prefix" "$candidate_payload_manifest_sha256"
printf '%s_value_candidate_tree_sha256=%s\n' "$prefix" "$candidate_tree_sha256"
printf '%s_value_candidate_metadata=%s\n' "$prefix" "$candidate_metadata"
printf '%s_value_candidate_request_state=%s\n' "$prefix" "$candidate_request_state"
printf '%s_value_candidate_complete_state=%s\n' "$prefix" "$candidate_complete_state"
printf '%s_value_candidate_pending_state=%s\n' "$prefix" "$candidate_pending_state"
printf '%s_value_snapshot_sha256=%s\n' "$prefix" "$snapshot_before"
printf '%s_check_count=%s\n' "$prefix" "${#seen_checks[@]}"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_receiver_invoked=false\n' "$prefix"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_executed=false\n' "$prefix"
printf '%s_remote_delete_executed=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
