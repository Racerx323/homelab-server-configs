#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_peer
readonly phase=${ACTION20P_PHASE:-}
readonly expected_hostname=j1-svpihole00
readonly interface=eth0
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly dbus_service=org.keepalived.Vrrp1
readonly dbus_interface=org.keepalived.Vrrp1.Instance
readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_observation_bytes=1048576
readonly maximum_observation_lines=4096

action20p_peer_capture_output=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
address_count() {
    local action20p_peer_family=$1
    local action20p_peer_cidr=$2
    local action20p_peer_output

    action20p_peer_output=$(ip -o "-$action20p_peer_family" address show dev "$interface") || return 1
    printf '%s\n' "$action20p_peer_output" |
        awk -v expected="$action20p_peer_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
expected_checks() {
    local action20p_peer_requested_phase=${1:-$phase}

    printf '%s\n' \
        identity_root working_directory_root hostname_exact interface_present \
        phase_valid main_regular main_not_symlink main_metadata main_hash_exact \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        fragment_unicast_ttl_count fragment_peer_ttl_constraints_count \
        health_regular health_not_symlink health_metadata health_hash_exact \
        keepalived_active caddy_active lighttpd_active vrrp_state_backup \
        caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_absent dns_ipv6_absent \
        dbus_service_once dbus_ipv4_object_once dbus_ipv6_object_once \
        dbus_ipv4_state_backup dbus_ipv6_state_backup node_a_https_continuity \
        caddy_vip_https_continuity
    if [[ "$action20p_peer_requested_phase" = post ]]; then
        printf '%s\n' journal_cursor_captured observation_wait_complete \
            journal_query_status ipv4_ttl_hl_rejections_zero \
            ipv6_ttl_hl_rejections_zero
    fi
}
record_check() {
    local action20p_peer_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20p_peer_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20p_peer_label" >&2
    return 1
}
https_probe() {
    local action20p_peer_name=$1
    local action20p_peer_address=$2

    curl --silent --show-error --fail --insecure --head \
        --connect-timeout 3 --max-time 10 \
        --resolve "$action20p_peer_name:443:$action20p_peer_address" \
        "https://$action20p_peer_name/" >/dev/null
}
capture() {
    local action20p_peer_label=$1
    local action20p_peer_status=0

    shift
    action20p_peer_capture_output=$("$@" 2>&1) || action20p_peer_status=$?
    printf '%s_observation_%s_status=%s\n' "$prefix" "$action20p_peer_label" "$action20p_peer_status"
    printf '%s_observation_%s_bytes=%s\n' "$prefix" "$action20p_peer_label" "${#action20p_peer_capture_output}"
    printf '%s_observation_%s_lines=%s\n' "$prefix" "$action20p_peer_label" "$(printf '%s' "$action20p_peer_capture_output" | awk 'END { print NR }')"
    printf '%s_observation_%s_sha256=%s\n' "$prefix" "$action20p_peer_label" "$(printf '%s' "$action20p_peer_capture_output" | sha256sum | awk '{ print $1 }')"
    if [[ ${#action20p_peer_capture_output} -gt $maximum_observation_bytes ]] ||
        [[ "$(printf '%s' "$action20p_peer_capture_output" | awk 'END { print NR }')" -gt "$maximum_observation_lines" ]] ||
        printf '%s' "$action20p_peer_capture_output" | LC_ALL=C grep -q '[^[:print:][:space:]]' ||
        printf '%s' "$action20p_peer_capture_output" | grep -Eqi \
            'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer'; then
        printf '%s_observation_%s_classification=unsafe\n' "$prefix" "$action20p_peer_label" >&2
        return 97
    fi
    printf '%s_observation_%s_classification=bounded_safe\n' "$prefix" "$action20p_peer_label"
    if [[ -n "$action20p_peer_capture_output" ]]; then
        printf '%s_observation_%s_begin\n%s\n%s_observation_%s_end\n' \
            "$prefix" "$action20p_peer_label" "$action20p_peer_capture_output" "$prefix" "$action20p_peer_label"
    else
        printf '%s_observation_%s_content_secured=empty\n' "$prefix" "$action20p_peer_label"
    fi
    [[ "$action20p_peer_status" -eq 0 ]]
}
self_test() {
    local action20p_peer_pre_labels
    local action20p_peer_post_labels

    action20p_peer_pre_labels=$(expected_checks pre) || return 1
    action20p_peer_post_labels=$(expected_checks post) || return 1
    [[ "$(printf '%s\n' "$action20p_peer_pre_labels" | wc -l)" -eq "$(printf '%s\n' "$action20p_peer_pre_labels" | LC_ALL=C sort -u | wc -l)" ]] || return 1
    [[ "$(printf '%s\n' "$action20p_peer_post_labels" | wc -l)" -eq "$(printf '%s\n' "$action20p_peer_post_labels" | LC_ALL=C sort -u | wc -l)" ]] || return 1
    [[ "$(printf '%s\n' "$action20p_peer_post_labels" | wc -l)" -eq "$(($(printf '%s\n' "$action20p_peer_pre_labels" | wc -l) + 5))" ]] || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 2 && ("$2" = pre || "$2" = post) ]] || exit 64
        expected_checks "$2"
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

record_check identity_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$(pwd -P)" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check interface_present test -d "/sys/class/net/$interface" || exit 1
record_check phase_valid test "$phase" = pre -o "$phase" = post || exit 1
record_check main_regular test -f "$main_configuration" || exit 1
record_check main_not_symlink test ! -L "$main_configuration" || exit 1
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644 || exit 1
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256" || exit 1
record_check fragment_regular test -f "$fragment" || exit 1
record_check fragment_not_symlink test ! -L "$fragment" || exit 1
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644 || exit 1
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256" || exit 1
record_check fragment_unicast_ttl_count test "$(grep -Ec '^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$' "$fragment" || true)" -eq 2 || exit 1
record_check fragment_peer_ttl_constraints_count test "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$fragment" || true)" -eq 2 || exit 1
record_check health_regular test -f "$health_helper" || exit 1
record_check health_not_symlink test ! -L "$health_helper" || exit 1
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755 || exit 1
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256" || exit 1
record_check keepalived_active systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active systemctl is-active --quiet lighttpd.service || exit 1
record_check vrrp_state_backup test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
dbus_list=$(timeout 5 busctl --system --no-pager --no-legend list)
dbus_tree=$(timeout 5 busctl --system --no-pager --list tree "$dbus_service")
dbus_ipv4_state=$(timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State)
dbus_ipv6_state=$(timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State)
readonly dbus_list dbus_tree dbus_ipv4_state dbus_ipv6_state
record_check dbus_service_once test "$(printf '%s\n' "$dbus_list" | awk '$1 == "org.keepalived.Vrrp1" { count++ } END { print count + 0 }')" -eq 1 || exit 1
record_check dbus_ipv4_object_once test "$(printf '%s\n' "$dbus_tree" | awk '$0 == "/org/keepalived/Vrrp1/Instance/eth0/110/IPv4" { count++ } END { print count + 0 }')" -eq 1 || exit 1
record_check dbus_ipv6_object_once test "$(printf '%s\n' "$dbus_tree" | awk '$0 == "/org/keepalived/Vrrp1/Instance/eth0/111/IPv6" { count++ } END { print count + 0 }')" -eq 1 || exit 1
record_check dbus_ipv4_state_backup grep -Eq '^\(us\) [0-9]+ "Backup"$' <<<"$dbus_ipv4_state" || exit 1
record_check dbus_ipv6_state_backup grep -Eq '^\(us\) [0-9]+ "Backup"$' <<<"$dbus_ipv6_state" || exit 1
record_check node_a_https_continuity https_probe pihole0.local.theama.co 10.1.0.53 || exit 1
record_check caddy_vip_https_continuity https_probe pihole-admin.local.theama.co 10.1.0.56 || exit 1

if [[ "$phase" = post ]]; then
    journal_cursor=$(journalctl -u keepalived.service -n 0 --show-cursor --no-pager -o cat | sed -n 's/^-- cursor: //p')
    readonly journal_cursor
    record_check journal_cursor_captured test -n "$journal_cursor" || exit 1
    sleep 8
    record_check observation_wait_complete true || exit 1
    capture ttl_quiet_window journalctl -u keepalived.service \
        --after-cursor="$journal_cursor" --no-pager -o short-iso-precise || exit 1
    journal_output=$action20p_peer_capture_output
    readonly journal_output
    record_check journal_query_status true || exit 1
    record_check ipv4_ttl_hl_rejections_zero test "$(printf '%s\n' "$journal_output" | grep -Eic '\(CADDY_IPV4\).*TTL/HL .* not in range' || true)" -eq 0 || exit 1
    record_check ipv6_ttl_hl_rejections_zero test "$(printf '%s\n' "$journal_output" | grep -Eic '\(CADDY_IPV6\).*TTL/HL .* not in range' || true)" -eq 0 || exit 1
fi

printf '%s_value_phase=%s\n' "$prefix" "$phase"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_health_sha256=%s\n' "$prefix" "$health_sha256"
printf '%s_value_check_count=%s\n' "$prefix" "$(expected_checks "$phase" | wc -l)"
printf '%s_read_only=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
