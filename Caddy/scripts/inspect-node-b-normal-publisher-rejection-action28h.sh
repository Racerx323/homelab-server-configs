#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_28h_node_b
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly current_link=/etc/caddy/current
readonly releases_root=/etc/caddy/releases
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly state_file=/run/caddy-ha/vrrp-state
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly expected_rejection='Node B publishing requires --emergency.'
readonly maximum_stream_bytes=4096
readonly maximum_stream_lines=16

check_count=0
failed_check_count=0
first_failure=none

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

record_check() {
    local action28h_node_b_label=$1
    local action28h_node_b_value=$2

    check_count=$((check_count + 1))
    printf '%s_check_%s=%s\n' "$prefix" "$action28h_node_b_label" \
        "$action28h_node_b_value"
    if [[ "$action28h_node_b_value" != true ]]; then
        failed_check_count=$((failed_check_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$action28h_node_b_label
        fi
    fi
}

record_command() {
    local action28h_node_b_command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_check "$action28h_node_b_command_label" true
    else
        record_check "$action28h_node_b_command_label" false
    fi
}

expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact publisher_regular \
        publisher_not_symlink publisher_executable publisher_hash_exact \
        current_link_symlink current_target_directory current_target_not_symlink \
        current_target_direct_child state_file_regular state_file_not_symlink \
        vrrp_state_backup before_ipv4_query_status_zero caddy_ipv4_absent \
        before_ipv6_query_status_zero caddy_ipv6_absent outbound_root_directory \
        outbound_root_not_symlink outbound_symlinks_absent outbound_special_files_absent \
        caddy_active keepalived_active lighttpd_active lsyncd_inactive \
        caddy_lsyncd_inactive reconcile_path_inactive reconcile_service_inactive \
        before_snapshot_valid capture_directory_secure publisher_status_rejected \
        publisher_stdout_empty publisher_stderr_exact publisher_stderr_safe \
        publisher_stdout_safe outbound_entry_count_unchanged snapshot_unchanged \
        vrrp_state_still_backup after_ipv4_query_status_zero caddy_ipv4_still_absent \
        after_ipv6_query_status_zero caddy_ipv6_still_absent \
        caddy_still_active keepalived_still_active lighttpd_still_active
}

address_count() {
    local action28h_node_b_family=$1
    local action28h_node_b_cidr=$2

    ip -o "-$action28h_node_b_family" address show dev "$interface" |
        awk -v expected="$action28h_node_b_cidr" \
            '$4 == expected { count++ } END { print count + 0 }'
}

count_is_zero() {
    local action28h_node_b_count=$1

    [[ "$action28h_node_b_count" =~ ^[0-9]+$ && "$action28h_node_b_count" -eq 0 ]]
}

outbound_entry_count() {
    find "$outbound_root" -mindepth 1 -print | wc -l
}

state_snapshot() {
    {
        printf 'publisher=%s\n' "$(file_hash "$publisher")"
        printf 'current=%s\n' "$(readlink -e -- "$current_link")"
        printf 'vrrp=%s\n' "$(<"$state_file")"
        printf 'caddy_ipv4=%s\n' "$(address_count 4 "$caddy_ipv4_cidr")"
        printf 'caddy_ipv6=%s\n' "$(address_count 6 "$caddy_ipv6_cidr")"
        find "$outbound_root" -xdev -printf 'path=%P|%y|%u:%g:%m:%s\n' |
            LC_ALL=C sort
        find "$outbound_root" -xdev -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum --
        for action28h_node_b_unit in caddy.service keepalived.service lighttpd.service \
            lsyncd.service caddy-lsyncd.service caddy-sync-reconcile.path \
            caddy-sync-reconcile.service; do
            systemctl show "$action28h_node_b_unit" --no-pager \
                -p LoadState -p ActiveState -p SubState
            printf 'unit=%s|enabled=%s\n' "$action28h_node_b_unit" \
                "$(systemctl is-enabled "$action28h_node_b_unit" 2>/dev/null || true)"
        done
    } | sha256sum | awk '{ print $1 }'
}

safe_stream() {
    local action28h_node_b_stream=$1

    [[ "$(wc -c <"$action28h_node_b_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28h_node_b_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28h_node_b_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28h_node_b_stream"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        [[ ${#publisher_sha256} -eq 64 ]]
        [[ "$expected_rejection" == 'Node B publishing requires --emergency.' ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --run)
        [[ $# -eq 1 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s --run|--self-test|--expected-checks\n' "${0##*/}" >&2
        exit 64
        ;;
esac

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$PWD" = /
record_command hostname_exact test "$(hostname)" = j1-svpihole00
record_command publisher_regular test -f "$publisher"
record_command publisher_not_symlink test ! -L "$publisher"
record_command publisher_executable test -x "$publisher"
record_command publisher_hash_exact test "$(file_hash "$publisher" 2>/dev/null || true)" = \
    "$publisher_sha256"
record_command current_link_symlink test -L "$current_link"
current_target=$(readlink -e -- "$current_link" 2>/dev/null || true)
readonly current_target
record_command current_target_directory test -d "$current_target"
record_command current_target_not_symlink test ! -L "$current_target"
record_command current_target_direct_child test "$(dirname -- "$current_target")" = "$releases_root"
record_command state_file_regular test -f "$state_file"
record_command state_file_not_symlink test ! -L "$state_file"
record_command vrrp_state_backup test "$(cat "$state_file" 2>/dev/null || true)" = BACKUP
before_ipv4_status=0
before_ipv4_count=$(address_count 4 "$caddy_ipv4_cidr") || {
    before_ipv4_status=$?
    before_ipv4_count=invalid
}
readonly before_ipv4_status before_ipv4_count
record_command before_ipv4_query_status_zero test "$before_ipv4_status" -eq 0
record_command caddy_ipv4_absent count_is_zero "$before_ipv4_count"
before_ipv6_status=0
before_ipv6_count=$(address_count 6 "$caddy_ipv6_cidr") || {
    before_ipv6_status=$?
    before_ipv6_count=invalid
}
readonly before_ipv6_status before_ipv6_count
record_command before_ipv6_query_status_zero test "$before_ipv6_status" -eq 0
record_command caddy_ipv6_absent count_is_zero "$before_ipv6_count"
record_command outbound_root_directory test -d "$outbound_root"
record_command outbound_root_not_symlink test ! -L "$outbound_root"
record_command outbound_symlinks_absent test -z \
    "$(find "$outbound_root" -xdev -type l -print -quit)"
record_command outbound_special_files_absent test -z \
    "$(find "$outbound_root" -xdev ! -type d ! -type f -print -quit)"
record_command caddy_active test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command keepalived_active test \
    "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active
record_command lighttpd_active test \
    "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command lsyncd_inactive test \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive

before_snapshot=$(state_snapshot 2>/dev/null || true)
readonly before_snapshot
before_entry_count=$(outbound_entry_count)
readonly before_entry_count
record_command before_snapshot_valid test ${#before_snapshot} -eq 64

capture_directory=$(mktemp -d /tmp/caddy-action28h-node-b.XXXXXX)
readonly capture_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$capture_directory"
}
trap cleanup EXIT
record_command capture_directory_secure test \
    "$(stat -c '%U:%G:%a' "$capture_directory")" = root:root:700
readonly publisher_stdout="$capture_directory/publisher.stdout"
readonly publisher_stderr="$capture_directory/publisher.stderr"
: >"$publisher_stdout"
: >"$publisher_stderr"
chmod 0600 "$publisher_stdout" "$publisher_stderr"

publisher_status=0
"$publisher" --source "$current_target" --node-role node-b \
    >"$publisher_stdout" 2>"$publisher_stderr" || publisher_status=$?
readonly publisher_status
record_command publisher_status_rejected test "$publisher_status" -eq 1
record_command publisher_stdout_empty test ! -s "$publisher_stdout"
record_command publisher_stderr_exact test "$(cat "$publisher_stderr")" = "$expected_rejection"
record_command publisher_stderr_safe safe_stream "$publisher_stderr"
record_command publisher_stdout_safe safe_stream "$publisher_stdout"

after_snapshot=$(state_snapshot 2>/dev/null || true)
readonly after_snapshot
after_entry_count=$(outbound_entry_count)
readonly after_entry_count
record_command outbound_entry_count_unchanged test "$after_entry_count" -eq "$before_entry_count"
record_command snapshot_unchanged test "$after_snapshot" = "$before_snapshot"
record_command vrrp_state_still_backup test "$(cat "$state_file" 2>/dev/null || true)" = BACKUP
after_ipv4_status=0
after_ipv4_count=$(address_count 4 "$caddy_ipv4_cidr") || {
    after_ipv4_status=$?
    after_ipv4_count=invalid
}
readonly after_ipv4_status after_ipv4_count
record_command after_ipv4_query_status_zero test "$after_ipv4_status" -eq 0
record_command caddy_ipv4_still_absent count_is_zero "$after_ipv4_count"
after_ipv6_status=0
after_ipv6_count=$(address_count 6 "$caddy_ipv6_cidr") || {
    after_ipv6_status=$?
    after_ipv6_count=invalid
}
readonly after_ipv6_status after_ipv6_count
record_command after_ipv6_query_status_zero test "$after_ipv6_status" -eq 0
record_command caddy_ipv6_still_absent count_is_zero "$after_ipv6_count"
record_command caddy_still_active test \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command keepalived_still_active test \
    "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active
record_command lighttpd_still_active test \
    "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active

printf '%s_value_publisher_status=%s\n' "$prefix" "$publisher_status"
printf '%s_value_publisher_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$publisher_stdout")"
printf '%s_value_publisher_stdout_lines=%s\n' "$prefix" "$(line_count "$publisher_stdout")"
printf '%s_value_publisher_stdout_sha256=%s\n' "$prefix" "$(file_hash "$publisher_stdout")"
printf '%s_value_publisher_stdout_classification=bounded_safe\n' "$prefix"
printf '%s_value_publisher_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$publisher_stderr")"
printf '%s_value_publisher_stderr_lines=%s\n' "$prefix" "$(line_count "$publisher_stderr")"
printf '%s_value_publisher_stderr_sha256=%s\n' "$prefix" "$(file_hash "$publisher_stderr")"
printf '%s_value_publisher_stderr_classification=bounded_safe\n' "$prefix"
printf '%s_value_publisher_stderr_content=%s\n' "$prefix" "$(cat "$publisher_stderr")"
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot"
printf '%s_value_before_outbound_entry_count=%s\n' "$prefix" "$before_entry_count"
printf '%s_value_after_outbound_entry_count=%s\n' "$prefix" "$after_entry_count"
printf '%s_value_vrrp_state=%s\n' "$prefix" "$(cat "$state_file")"
printf '%s_check_count=%s\n' "$prefix" "$check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_publisher_invoked=true\n' "$prefix"
printf '%s_emergency_flag_supplied=false\n' "$prefix"
printf '%s_publication_created=false\n' "$prefix"
printf '%s_ssh_invoked=false\n' "$prefix"
printf '%s_rsync_invoked=false\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"

if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
