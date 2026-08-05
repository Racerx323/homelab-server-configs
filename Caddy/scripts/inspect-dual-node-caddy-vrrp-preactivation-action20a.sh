#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_probe
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly notification_script=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=65536
readonly maximum_stream_lines=512

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}
snapshot_state() {
    local unit_name

    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration")"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment")"
    printf 'current=%s\n' "$(readlink -f /etc/caddy/current)"
    printf 'addresses_sha256=%s\n' \
        "$(ip -o address show dev eth0 | sha256sum | awk '{ print $1 }')"
    for unit_name in keepalived.service caddy.service lighttpd.service; do
        printf 'unit=%s active=%s enabled=%s\n' "$unit_name" \
            "$(systemctl is-active "$unit_name" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit_name" 2>/dev/null || true)"
    done
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact \
        architecture_arm64 physical_ipv4_exact physical_ipv6_exact \
        fragment_regular fragment_not_symlink fragment_metadata_exact \
        fragment_hash_exact fragment_priority_exact fragment_ipv4_vrid_exact \
        fragment_ipv6_vrid_exact fragment_ipv4_source_exact \
        fragment_ipv4_peer_exact fragment_ipv6_source_exact \
        fragment_ipv6_peer_exact fragment_ipv4_vip_exact \
        fragment_ipv6_vip_exact main_configuration_regular \
        main_configuration_not_symlink main_configuration_excludes_fragment \
        main_configuration_caddy_names_clear main_configuration_vrids_clear \
        main_configuration_terminal_newline main_hash_matches_backup \
        health_script_exact notification_script_exact ipv4_nonlocal_bind \
        ipv6_nonlocal_bind keepalived_active keepalived_enabled caddy_active \
        lighttpd_active active_release_exact caddy_ipv4_vip_absent \
        caddy_ipv6_vip_absent dns_ipv4_vip_count_supported \
        dns_ipv6_vip_count_supported dns_vip_dualstack_coherent \
        health_probe_status_zero health_probe_streams_safe \
        before_state_status_zero after_state_status_zero state_unchanged
}
record_command() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test_root=$(mktemp -d /tmp/caddy-action20a-probe-self.XXXXXX)
        readonly self_test_root
        trap 'rm -rf -- "$self_test_root"' EXIT
        expected_assertions >"$self_test_root/labels"
        [[ "$(wc -l <"$self_test_root/labels")" -eq 46 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/labels" | wc -l)" -eq 46 ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/labels" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --self-test|--expected-assertions|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_ipv4=10.1.0.53/22
        expected_ipv6=fd36:5aa8:6971:1::53/64
        expected_priority=140
        expected_ipv4_source=10.1.0.53
        expected_ipv4_peer=10.1.0.54
        expected_ipv6_source=fd36:5aa8:6971:1::53
        expected_ipv6_peer=fd36:5aa8:6971:1::54
        expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
        expected_backup=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS
        expected_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_ipv4=10.1.0.54/22
        expected_ipv6=fd36:5aa8:6971:1::54/64
        expected_priority=100
        expected_ipv4_source=10.1.0.54
        expected_ipv4_peer=10.1.0.53
        expected_ipv6_source=fd36:5aa8:6971:1::54
        expected_ipv6_peer=fd36:5aa8:6971:1::53
        expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
        expected_backup=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.no5a5x
        expected_release=/etc/caddy/releases/action15-health-follow-redirects
        ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 64
        ;;
esac
readonly node_role expected_hostname expected_ipv4 expected_ipv6
readonly expected_priority expected_ipv4_source expected_ipv4_peer
readonly expected_ipv6_source expected_ipv6_peer expected_fragment_sha256
readonly expected_backup expected_release

work_directory=$(mktemp -d /tmp/caddy-action20a-probe.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state=$work_directory/before.state
readonly after_state=$work_directory/after.state
readonly health_stdout=$work_directory/health.stdout
readonly health_stderr=$work_directory/health.stderr
: >"$before_state"
: >"$after_state"
: >"$health_stdout"
: >"$health_stderr"
chmod 0600 "$before_state" "$after_state" "$health_stdout" "$health_stderr"

before_status=0
snapshot_state >"$before_state" 2>/dev/null || before_status=$?
readonly before_status
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256

failed_count=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if ! record_command "$assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion node_role_exact test "$node_role" = "$2"
run_assertion hostname_exact test "$(hostname)" = "$expected_hostname"
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion physical_ipv4_exact test "$(address_count 4 "$expected_ipv4")" -eq 1
run_assertion physical_ipv6_exact test "$(address_count 6 "$expected_ipv6")" -eq 1
run_assertion fragment_regular test -f "$fragment"
run_assertion fragment_not_symlink test ! -L "$fragment"
run_assertion fragment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644
run_assertion fragment_hash_exact test \
    "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion fragment_priority_exact grep -Fq \
    "priority $expected_priority" "$fragment"
run_assertion fragment_ipv4_vrid_exact grep -Fq 'virtual_router_id 110' "$fragment"
run_assertion fragment_ipv6_vrid_exact grep -Fq 'virtual_router_id 111' "$fragment"
run_assertion fragment_ipv4_source_exact grep -Fq \
    "unicast_src_ip $expected_ipv4_source" "$fragment"
run_assertion fragment_ipv4_peer_exact grep -Fq \
    "$expected_ipv4_peer min_ttl 255 max_ttl 255" "$fragment"
run_assertion fragment_ipv6_source_exact grep -Fq \
    "unicast_src_ip $expected_ipv6_source" "$fragment"
run_assertion fragment_ipv6_peer_exact grep -Fq \
    "$expected_ipv6_peer min_ttl 255 max_ttl 255" "$fragment"
run_assertion fragment_ipv4_vip_exact grep -Fq \
    '10.1.0.56/22 dev eth0' "$fragment"
run_assertion fragment_ipv6_vip_exact grep -Fq \
    'fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' "$fragment"
run_assertion main_configuration_regular test -f "$main_configuration"
run_assertion main_configuration_not_symlink test ! -L "$main_configuration"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
run_assertion main_configuration_excludes_fragment bash -c \
    '! grep -Eq "^[[:space:]]*(include|include_dir).*conf\\.d|caddy-ha\\.conf" "$1"' \
    _ "$main_configuration"
# shellcheck disable=SC2016
run_assertion main_configuration_caddy_names_clear bash -c \
    '! grep -Eq "^[[:space:]]*(vrrp_sync_group|vrrp_instance)[[:space:]]+CADDY_(DUALSTACK|IPV4|IPV6)([[:space:]]|$)" "$1"' \
    _ "$main_configuration"
# shellcheck disable=SC2016
run_assertion main_configuration_vrids_clear bash -c \
    '! grep -Eq "^[[:space:]]*virtual_router_id[[:space:]]+(110|111)([[:space:]]|$)" "$1"' \
    _ "$main_configuration"
run_assertion main_configuration_terminal_newline test \
    "$(tail -c 1 "$main_configuration" | wc -l)" -eq 1
main_sha256=$(file_hash "$main_configuration")
readonly main_sha256
run_assertion main_hash_matches_backup grep -Fqx \
    "main_configuration_sha256=$main_sha256" "$expected_backup/manifest"
# shellcheck disable=SC2016
run_assertion health_script_exact bash -c \
    '[[ -f "$1" && ! -L "$1" && "$(stat -c "%U:%G:%a" "$1")" = root:root:755 && "$(sha256sum "$1" | awk "{ print \$1 }")" = "$2" ]]' \
    _ "$health_script" "$health_sha256"
# shellcheck disable=SC2016
run_assertion notification_script_exact bash -c \
    '[[ -f "$1" && ! -L "$1" && "$(stat -c "%U:%G:%a" "$1")" = root:root:755 && "$(sha256sum "$1" | awk "{ print \$1 }")" = "$2" ]]' \
    _ "$notification_script" "$notification_sha256"
run_assertion ipv4_nonlocal_bind test "$(sysctl -n net.ipv4.ip_nonlocal_bind)" = 1
run_assertion ipv6_nonlocal_bind test "$(sysctl -n net.ipv6.ip_nonlocal_bind)" = 1
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion keepalived_enabled test "$(systemctl is-enabled keepalived.service)" = enabled
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion active_release_exact test "$(readlink -f /etc/caddy/current)" = \
    "$expected_release"

caddy_ipv4_count=$(address_count 4 "$caddy_ipv4_cidr")
readonly caddy_ipv4_count
caddy_ipv6_count=$(address_count 6 "$caddy_ipv6_cidr")
readonly caddy_ipv6_count
dns_ipv4_count=$(address_count 4 "$dns_ipv4_cidr")
readonly dns_ipv4_count
dns_ipv6_count=$(address_count 6 "$dns_ipv6_cidr")
readonly dns_ipv6_count
run_assertion caddy_ipv4_vip_absent test "$caddy_ipv4_count" -eq 0
run_assertion caddy_ipv6_vip_absent test "$caddy_ipv6_count" -eq 0
run_assertion dns_ipv4_vip_count_supported test "$dns_ipv4_count" -le 1
run_assertion dns_ipv6_vip_count_supported test "$dns_ipv6_count" -le 1
run_assertion dns_vip_dualstack_coherent test "$dns_ipv4_count" -eq \
    "$dns_ipv6_count"

health_status=0
runuser -u keepalived_script -- "$health_script" >"$health_stdout" \
    2>"$health_stderr" || health_status=$?
readonly health_status
health_streams_safe=false
if safe_stream "$health_stdout" && safe_stream "$health_stderr"; then
    health_streams_safe=true
fi
readonly health_streams_safe
run_assertion health_probe_status_zero test "$health_status" -eq 0
run_assertion health_probe_streams_safe test "$health_streams_safe" = true
run_assertion before_state_status_zero test "$before_status" -eq 0

after_status=0
snapshot_state >"$after_state" 2>/dev/null || after_status=$?
readonly after_status
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
run_assertion after_state_status_zero test "$after_status" -eq 0
run_assertion state_unchanged test "$before_state_sha256" = "$after_state_sha256"

expected_assertion_count=$(expected_assertions | wc -l)
readonly expected_assertion_count
printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_priority=%s\n' "$prefix" "$expected_priority"
printf '%s_value_ipv4_vrid=110\n' "$prefix"
printf '%s_value_ipv6_vrid=111\n' "$prefix"
printf '%s_value_ipv4_source=%s\n' "$prefix" "$expected_ipv4_source"
printf '%s_value_ipv4_peer=%s\n' "$prefix" "$expected_ipv4_peer"
printf '%s_value_ipv6_source=%s\n' "$prefix" "$expected_ipv6_source"
printf '%s_value_ipv6_peer=%s\n' "$prefix" "$expected_ipv6_peer"
printf '%s_value_dns_ipv4_vip_count=%s\n' "$prefix" "$dns_ipv4_count"
printf '%s_value_dns_ipv6_vip_count=%s\n' "$prefix" "$dns_ipv6_count"
printf '%s_value_caddy_ipv4_vip_count=%s\n' "$prefix" "$caddy_ipv4_count"
printf '%s_value_caddy_ipv6_vip_count=%s\n' "$prefix" "$caddy_ipv6_count"
printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$expected_fragment_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_value_health_status=%s\n' "$prefix" "$health_status"
printf '%s_value_health_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$health_stdout")"
printf '%s_value_health_stdout_lines=%s\n' "$prefix" "$(line_count "$health_stdout")"
printf '%s_value_health_stdout_sha256=%s\n' "$prefix" "$(file_hash "$health_stdout")"
printf '%s_value_health_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$health_stderr")"
printf '%s_value_health_stderr_lines=%s\n' "$prefix" "$(line_count "$health_stderr")"
printf '%s_value_health_stderr_sha256=%s\n' "$prefix" "$(file_hash "$health_stderr")"
printf '%s_value_health_stream_classification=%s\n' "$prefix" "$health_streams_safe"
if [[ "$health_streams_safe" = true ]]; then
    if [[ -s "$health_stdout" ]]; then
        printf '%s_health_stdout_begin\n' "$prefix"
        cat "$health_stdout"
        printf '%s_health_stdout_end\n' "$prefix"
    else
        printf '%s_health_stdout_content_secured=empty\n' "$prefix"
    fi
    if [[ -s "$health_stderr" ]]; then
        printf '%s_health_stderr_begin\n' "$prefix"
        cat "$health_stderr"
        printf '%s_health_stderr_end\n' "$prefix"
    else
        printf '%s_health_stderr_content_secured=empty\n' "$prefix"
    fi
fi
printf '%s_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
