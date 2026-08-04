#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_vrrp_a_remote
readonly interface=eth0
readonly vip_ipv4_cidr=10.1.0.56/22
readonly vip_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly state_file=/run/caddy-ha/vrrp-state
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly stabilization_seconds=4

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev "$interface" 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}

stable_state_snapshot() {
    printf 'fragment_sha256=%s\n' \
        "$(file_hash "$fragment" 2>/dev/null || printf unavailable)"
    printf 'state=%s\n' "$(cat "$state_file" 2>/dev/null || printf unavailable)"
    printf 'vip_ipv4_count=%s\n' "$(address_count 4 "$vip_ipv4_cidr")"
    printf 'vip_ipv6_count=%s\n' "$(address_count 6 "$vip_ipv6_cidr")"
    printf 'current_target=%s\n' \
        "$(readlink -e /etc/caddy/current 2>/dev/null || printf unavailable)"
    printf 'publisher_sha256=%s\n' \
        "$(file_hash "$publisher" 2>/dev/null || printf unavailable)"
    for snapshot_service in keepalived.service caddy.service lighttpd.service; do
        systemctl show "$snapshot_service" --no-pager \
            -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit=%s|enabled=%s\n' "$snapshot_service" \
            "$(systemctl is-enabled "$snapshot_service" 2>/dev/null || true)"
    done
    for snapshot_unit in lsyncd.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-sync-reconcile.service; do
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState
        printf 'unit=%s|enabled=%s\n' "$snapshot_unit" \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$vip_ipv4_cidr" == 10.1.0.56/22 ]]
        [[ "$vip_ipv6_cidr" == fd36:5aa8:6971:1::56/128 ]]
        [[ "$publisher_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$stabilization_seconds" -ge 3 ]]
        printf '%s_inspector_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node-a)
        readonly node_role=node-a
        readonly expected_hostname=j1-svpihole0
        readonly expected_state=BACKUP
        readonly node_ipv4_cidr=10.1.0.53/22
        readonly node_ipv6_cidr=fd36:5aa8:6971:1::53/64
        readonly fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
        readonly expected_vip_count=0
        ;;
    --node-b)
        readonly node_role=node-b
        readonly expected_hostname=j1-svpihole00
        readonly expected_state=MASTER
        readonly node_ipv4_cidr=10.1.0.54/22
        readonly node_ipv6_cidr=fd36:5aa8:6971:1::54/64
        readonly fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
        readonly expected_vip_count=1
        ;;
    *)
        printf 'Usage: %s --node-a|--node-b|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
[[ $# -eq 1 ]] || exit 64

work_directory=$(mktemp -d /tmp/caddy-action18c-vrrp-a-remote.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_exact test "$(hostname)" = "$expected_hostname"
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command interface_present test -d "/sys/class/net/$interface"
record_command physical_ipv4_exact test \
    "$(address_count 4 "$node_ipv4_cidr")" -eq 1
record_command physical_ipv6_exact test \
    "$(address_count 6 "$node_ipv6_cidr")" -eq 1
record_command keepalived_fragment_regular test -f "$fragment"
record_command keepalived_fragment_not_symlink test ! -L "$fragment"
record_command keepalived_fragment_metadata test \
    "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
record_command keepalived_fragment_hash_exact test \
    "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256"
record_command state_file_regular test -f "$state_file"
record_command state_file_not_symlink test ! -L "$state_file"
record_command state_exact test \
    "$(cat "$state_file" 2>/dev/null || true)" = "$expected_state"
record_command ipv4_vip_count_exact test \
    "$(address_count 4 "$vip_ipv4_cidr")" -eq "$expected_vip_count"
record_command ipv6_vip_count_exact test \
    "$(address_count 6 "$vip_ipv6_cidr")" -eq "$expected_vip_count"
record_command keepalived_active test \
    "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active
record_command keepalived_enabled test \
    "$(systemctl is-enabled keepalived.service 2>/dev/null || true)" = enabled
record_command caddy_active test \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lighttpd_active test \
    "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command health_script_regular test -f "$health_script"
record_command health_script_not_symlink test ! -L "$health_script"
record_command health_script_status_zero timeout 10 "$health_script"
record_command publisher_regular test -f "$publisher"
record_command publisher_not_symlink test ! -L "$publisher"
record_command publisher_hash_exact test \
    "$(file_hash "$publisher" 2>/dev/null || true)" = "$publisher_sha256"
record_command lsyncd_inactive test \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
record_command before_snapshot_status_zero test "$before_status" -eq 0
record_command before_snapshot_stderr_empty test ! -s "$before_error"
before_state_sha256=$(file_hash "$before_state")

sleep "$stabilization_seconds"

record_command state_stable_after_window test \
    "$(cat "$state_file" 2>/dev/null || true)" = "$expected_state"
record_command ipv4_vip_stable_after_window test \
    "$(address_count 4 "$vip_ipv4_cidr")" -eq "$expected_vip_count"
record_command ipv6_vip_stable_after_window test \
    "$(address_count 6 "$vip_ipv6_cidr")" -eq "$expected_vip_count"
record_command keepalived_active_after_window test \
    "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active
record_command caddy_active_after_window test \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command health_status_zero_after_window timeout 10 "$health_script"

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
record_command after_snapshot_status_zero test "$after_status" -eq 0
record_command after_snapshot_stderr_empty test ! -s "$after_error"
after_state_sha256=$(file_hash "$after_state")
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_vrrp_state=%s\n' "$prefix" \
    "$(cat "$state_file" 2>/dev/null || printf unavailable)"
printf '%s_value_ipv4_vip_count=%s\n' "$prefix" \
    "$(address_count 4 "$vip_ipv4_cidr")"
printf '%s_value_ipv6_vip_count=%s\n' "$prefix" \
    "$(address_count 6 "$vip_ipv6_cidr")"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_synchronization_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
