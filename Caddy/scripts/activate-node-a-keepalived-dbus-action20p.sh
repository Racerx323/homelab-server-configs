#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20p
readonly expected_hostname=j1-svpihole0
readonly interface=eth0
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly rollback_directory=/var/backups/caddy-ha/action20n-node-a-dbus-main.s8Qkep
readonly rollback_main=$rollback_directory/keepalived.conf.before
readonly rollback_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
readonly rollback_manifest=$rollback_directory/manifest
readonly source_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly dbus_service=org.keepalived.Vrrp1
readonly dbus_interface=org.keepalived.Vrrp1.Instance
readonly dbus_ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/110/IPv4
readonly dbus_ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/111/IPv6
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_a_fqdn=pihole0.local.theama.co
readonly caddy_vip_fqdn=pihole-admin.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly action_mode=${ACTION20P_MODE:-activate}

transaction_root=
mutation_started=false
transaction_complete=false
before_main_pid=
before_restarts=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local action20p_family=$1
    local action20p_cidr=$2
    local action20p_output

    action20p_output=$(ip -o "-$action20p_family" address show dev "$interface") || return 1
    printf '%s\n' "$action20p_output" |
        awk -v expected="$action20p_cidr" '$4 == expected { count++ } END { print count + 0 }'
}
exact_address_once() {
    local action20p_family=$1
    local action20p_cidr=$2
    local action20p_count

    action20p_count=$(address_count "$action20p_family" "$action20p_cidr") || return 1
    [[ "$action20p_count" -eq 1 ]]
}
global_defs_contains_enable_dbus() {
    local action20p_configuration=$1

    awk '
        /^[[:space:]]*global_defs[[:space:]]*\{/ { in_global=1; blocks++; next }
        in_global && /^[[:space:]]*enable_dbus([[:space:]]|$)/ { found++ }
        in_global && /^[[:space:]]*\}[[:space:]]*$/ { in_global=0 }
        END { exit(blocks == 1 && found == 1 ? 0 : 1) }
    ' "$action20p_configuration"
}
unicast_ttl_placement_valid() {
    local action20p_fragment_path=$1

    awk '
        /^[[:space:]]*unicast_src_ip[[:space:]]+/ {
            source_count++
            expect_ttl=1
            next
        }
        expect_ttl {
            if ($0 ~ /^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$/) {
                ttl_count++
                expect_ttl=0
                next
            }
            if ($0 !~ /^[[:space:]]*$/) invalid=1
        }
        END { exit(source_count == 2 && ttl_count == 2 && invalid == 0 ? 0 : 1) }
    ' "$action20p_fragment_path"
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_exact interface_present \
        main_regular main_not_symlink main_metadata main_hash_exact \
        main_enable_dbus_once main_enable_dbus_in_global_defs main_include_once \
        main_include_terminal fragment_regular fragment_not_symlink \
        fragment_metadata fragment_hash_exact fragment_unicast_ttl_count \
        fragment_unicast_ttl_placement fragment_peer_ttl_constraints_count \
        fragment_hoplimit_absent health_regular health_not_symlink health_metadata \
        health_hash_exact rollback_directory_present rollback_directory_not_symlink \
        rollback_directory_metadata rollback_main_regular rollback_main_not_symlink \
        rollback_main_metadata rollback_main_hash_exact rollback_manifest_regular \
        rollback_manifest_not_symlink rollback_manifest_metadata rollback_manifest_lines \
        rollback_manifest_action rollback_manifest_node rollback_manifest_source \
        rollback_manifest_before rollback_manifest_candidate keepalived_active_before \
        caddy_active_before lighttpd_active_before keepalived_pid_numeric_before \
        keepalived_restarts_numeric_before vrrp_state_master_before \
        caddy_ipv4_once_before caddy_ipv6_once_before dns_ipv4_once_before \
        dns_ipv6_once_before dbus_service_absent_before node_a_https_before \
        caddy_vip_https_before journal_cursor_captured reload_status \
        runtime_ready reload_journal_status reload_journal_no_fatal_errors \
        reload_journal_no_ttl_rejections dbus_list_status dbus_tree_status \
        dbus_ipv4_state_status dbus_ipv6_state_status dbus_service_present_after \
        dbus_ipv4_object_present dbus_ipv6_object_present dbus_ipv4_state_master \
        dbus_ipv6_state_master keepalived_active_after caddy_active_after \
        lighttpd_active_after keepalived_pid_unchanged keepalived_restarts_unchanged \
        vrrp_state_master_after caddy_ipv4_once_after caddy_ipv6_once_after \
        dns_ipv4_once_after dns_ipv6_once_after main_hash_unchanged \
        fragment_hash_unchanged health_hash_unchanged health_root_context \
        health_keepalived_context node_a_https_after caddy_vip_https_after
}
record_check() {
    local action20p_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20p_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20p_label" >&2
    return 1
}
safe_stream() {
    local action20p_stream=$1

    [[ "$(wc -c <"$action20p_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20p_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20p_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action20p_stream"
}
emit_stream() {
    local action20p_label=$1
    local action20p_stream=$2

    printf '%s_capture_%s_bytes=%s\n' "$prefix" "$action20p_label" "$(wc -c <"$action20p_stream")"
    printf '%s_capture_%s_lines=%s\n' "$prefix" "$action20p_label" "$(line_count "$action20p_stream")"
    printf '%s_capture_%s_sha256=%s\n' "$prefix" "$action20p_label" "$(file_hash "$action20p_stream")"
    if ! safe_stream "$action20p_stream"; then
        printf '%s_capture_%s_classification=unsafe_retained\n' "$prefix" "$action20p_label" >&2
        return 97
    fi
    printf '%s_capture_%s_classification=bounded_safe\n' "$prefix" "$action20p_label"
    if [[ -s "$action20p_stream" ]]; then
        printf '%s_capture_%s_begin\n' "$prefix" "$action20p_label"
        sed "s/^/${prefix}_capture_${action20p_label}_content=/" "$action20p_stream"
        printf '%s_capture_%s_end\n' "$prefix" "$action20p_label"
    else
        printf '%s_capture_%s_content_secured=empty\n' "$prefix" "$action20p_label"
    fi
}
run_captured() {
    local action20p_label=$1
    local action20p_status=0

    shift
    install -m 0600 /dev/null "$transaction_root/$action20p_label.stdout" || return 1
    install -m 0600 /dev/null "$transaction_root/$action20p_label.stderr" || return 1
    "$@" >"$transaction_root/$action20p_label.stdout" \
        2>"$transaction_root/$action20p_label.stderr" || action20p_status=$?
    emit_stream "${action20p_label}_stdout" "$transaction_root/$action20p_label.stdout" || return 97
    emit_stream "${action20p_label}_stderr" "$transaction_root/$action20p_label.stderr" || return 97
    printf '%s_capture_%s_status=%s\n' "$prefix" "$action20p_label" "$action20p_status"
    [[ "$action20p_status" -eq 0 ]]
}
https_probe() {
    local action20p_name=$1
    local action20p_address=$2

    curl --silent --show-error --fail --insecure --head \
        --connect-timeout 3 --max-time 10 \
        --resolve "$action20p_name:443:$action20p_address" \
        "https://$action20p_name/" >/dev/null
}
dbus_name_present() {
    local action20p_list=$1

    awk '$1 == "org.keepalived.Vrrp1" { found++ } END { exit(found == 1 ? 0 : 1) }' "$action20p_list"
}
dbus_name_absent_live() {
    ! timeout 3 busctl --system --no-pager --no-legend list 2>/dev/null |
        awk '$1 == "org.keepalived.Vrrp1" { found=1 } END { exit(found ? 0 : 1) }'
}
dbus_object_present() {
    local action20p_tree=$1
    local action20p_object=$2

    grep -Fqx "$action20p_object" "$action20p_tree"
}
dbus_state_is_master() {
    local action20p_state=$1

    grep -Eq '^\(us\) [0-9]+ "Master"$' "$action20p_state"
}
wait_for_runtime() {
    for _ in $(seq 1 30); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER ]] &&
            exact_address_once 4 "$caddy_ipv4_cidr" &&
            exact_address_once 6 "$caddy_ipv6_cidr" &&
            dbus_name_present <(timeout 3 busctl --system --no-pager --no-legend list 2>/dev/null); then
            return 0
        fi
        sleep 1
    done
    return 1
}
rollback_transaction() {
    local action20p_rollback_ok=true

    printf '%s_rollback_started=true\n' "$prefix" >&2
    install -o root -g root -m 0644 "$rollback_main" "$main_configuration" || action20p_rollback_ok=false
    if [[ "$action20p_rollback_ok" = true ]]; then
        if systemctl is-active --quiet keepalived.service; then
            run_captured rollback_reload systemctl reload keepalived.service ||
                run_captured rollback_restart systemctl restart keepalived.service || action20p_rollback_ok=false
        else
            run_captured rollback_restart systemctl restart keepalived.service || action20p_rollback_ok=false
        fi
    fi
    for _ in $(seq 1 30); do
        if systemctl is-active --quiet keepalived.service &&
            [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER ]] &&
            exact_address_once 4 "$caddy_ipv4_cidr" && exact_address_once 6 "$caddy_ipv6_cidr"; then
            break
        fi
        sleep 1
    done
    [[ "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$rollback_main_sha256" ]] || action20p_rollback_ok=false
    [[ "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256" ]] || action20p_rollback_ok=false
    systemctl is-active --quiet keepalived.service || action20p_rollback_ok=false
    [[ "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER ]] || action20p_rollback_ok=false
    exact_address_once 4 "$caddy_ipv4_cidr" || action20p_rollback_ok=false
    exact_address_once 6 "$caddy_ipv6_cidr" || action20p_rollback_ok=false
    exact_address_once 4 "$dns_ipv4_cidr" || action20p_rollback_ok=false
    exact_address_once 6 "$dns_ipv6_cidr" || action20p_rollback_ok=false
    https_probe "$node_a_fqdn" 10.1.0.53 || action20p_rollback_ok=false
    https_probe "$caddy_vip_fqdn" 10.1.0.56 || action20p_rollback_ok=false
    dbus_name_absent_live || action20p_rollback_ok=false
    if [[ "$action20p_rollback_ok" = true ]]; then
        printf '%s_rollback_complete=true\n' "$prefix" >&2
        return 0
    fi
    printf '%s_rollback_complete=false\n' "$prefix" >&2
    return 125
}
cleanup() {
    local action20p_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ "$mutation_started" = true && "$transaction_complete" != true ]]; then
        rollback_transaction || action20p_cleanup_status=125
    fi
    if [[ -n "$transaction_root" && -d "$transaction_root" ]]; then
        rm -rf -- "$transaction_root"
    fi
    exit "$action20p_cleanup_status"
}
self_test() {
    local action20p_labels

    action20p_labels=$(expected_checks) || return 1
    [[ "$(printf '%s\n' "$action20p_labels" | wc -l)" -gt 70 ]] || return 1
    [[ "$(printf '%s\n' "$action20p_labels" | wc -l)" -eq "$(printf '%s\n' "$action20p_labels" | LC_ALL=C sort -u | wc -l)" ]] || return 1
    unicast_ttl_placement_valid <(printf '%s\n' \
        'unicast_src_ip 10.1.0.53' 'unicast_ttl 255' \
        'unicast_src_ip fd36:5aa8:6971:1::53' 'unicast_ttl 255') || return 1
    if unicast_ttl_placement_valid <(printf '%s\n' \
        'unicast_src_ip 10.1.0.53' 'track_src_ip' 'unicast_ttl 255' \
        'unicast_src_ip fd36:5aa8:6971:1::53' 'unicast_ttl 255'); then
        return 1
    fi
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
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

transaction_root=$(mktemp -d /run/caddy-action20p.XXXXXX)
readonly transaction_root
chmod 0700 "$transaction_root"
trap cleanup EXIT INT TERM

if [[ "$action_mode" = rollback_only ]]; then
    [[ "$(id -u)" -eq 0 ]] || exit 1
    [[ "$(pwd -P)" = / ]] || exit 1
    [[ "$(hostname)" = "$expected_hostname" ]] || exit 1
    [[ "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256" ]] || exit 1
    [[ "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256" ]] || exit 1
    [[ "$(file_hash "$rollback_main" 2>/dev/null || true)" = "$rollback_main_sha256" ]] || exit 1
    mutation_started=true
    rollback_transaction || exit $?
    transaction_complete=true
    printf '%s_rollback_only_complete=true\n' "$prefix"
    exit 0
fi
[[ "$action_mode" = activate ]] || exit 64

record_check identity_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$(pwd -P)" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check interface_present test -d "/sys/class/net/$interface" || exit 1
record_check main_regular test -f "$main_configuration" || exit 1
record_check main_not_symlink test ! -L "$main_configuration" || exit 1
record_check main_metadata test "$(stat -c '%U:%G:%a' "$main_configuration" 2>/dev/null || true)" = root:root:644 || exit 1
record_check main_hash_exact test "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$main_sha256" || exit 1
record_check main_enable_dbus_once test "$(grep -Ec '^[[:space:]]*enable_dbus([[:space:]]|$)' "$main_configuration" || true)" -eq 1 || exit 1
record_check main_enable_dbus_in_global_defs global_defs_contains_enable_dbus "$main_configuration" || exit 1
record_check main_include_once test "$(grep -Fxc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$main_configuration" || true)" -eq 1 || exit 1
record_check main_include_terminal test "$(tail -n 1 "$main_configuration")" = 'include /etc/keepalived/conf.d/caddy-ha.conf' || exit 1
record_check fragment_regular test -f "$fragment" || exit 1
record_check fragment_not_symlink test ! -L "$fragment" || exit 1
record_check fragment_metadata test "$(stat -c '%U:%G:%a' "$fragment" 2>/dev/null || true)" = root:root:644 || exit 1
record_check fragment_hash_exact test "$(file_hash "$fragment" 2>/dev/null || true)" = "$fragment_sha256" || exit 1
record_check fragment_unicast_ttl_count test "$(grep -Ec '^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$' "$fragment" || true)" -eq 2 || exit 1
record_check fragment_unicast_ttl_placement unicast_ttl_placement_valid "$fragment" || exit 1
record_check fragment_peer_ttl_constraints_count test "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$fragment" || true)" -eq 2 || exit 1
record_check fragment_hoplimit_absent test "$(grep -Ec '^[[:space:]]*hoplimit([[:space:]]|$)' "$fragment" || true)" -eq 0 || exit 1
record_check health_regular test -f "$health_helper" || exit 1
record_check health_not_symlink test ! -L "$health_helper" || exit 1
record_check health_metadata test "$(stat -c '%U:%G:%a' "$health_helper" 2>/dev/null || true)" = root:root:755 || exit 1
record_check health_hash_exact test "$(file_hash "$health_helper" 2>/dev/null || true)" = "$health_sha256" || exit 1
record_check rollback_directory_present test -d "$rollback_directory" || exit 1
record_check rollback_directory_not_symlink test ! -L "$rollback_directory" || exit 1
record_check rollback_directory_metadata test "$(stat -c '%U:%G:%a' "$rollback_directory" 2>/dev/null || true)" = root:root:700 || exit 1
record_check rollback_main_regular test -f "$rollback_main" || exit 1
record_check rollback_main_not_symlink test ! -L "$rollback_main" || exit 1
record_check rollback_main_metadata test "$(stat -c '%U:%G:%a' "$rollback_main" 2>/dev/null || true)" = root:root:600 || exit 1
record_check rollback_main_hash_exact test "$(file_hash "$rollback_main" 2>/dev/null || true)" = "$rollback_main_sha256" || exit 1
record_check rollback_manifest_regular test -f "$rollback_manifest" || exit 1
record_check rollback_manifest_not_symlink test ! -L "$rollback_manifest" || exit 1
record_check rollback_manifest_metadata test "$(stat -c '%U:%G:%a' "$rollback_manifest" 2>/dev/null || true)" = root:root:600 || exit 1
record_check rollback_manifest_lines test "$(line_count "$rollback_manifest")" -eq 5 || exit 1
record_check rollback_manifest_action grep -Fqx action=20n "$rollback_manifest" || exit 1
record_check rollback_manifest_node grep -Fqx node=node-a "$rollback_manifest" || exit 1
record_check rollback_manifest_source grep -Fqx "source_sha256=$source_sha256" "$rollback_manifest" || exit 1
record_check rollback_manifest_before grep -Fqx "before_sha256=$rollback_main_sha256" "$rollback_manifest" || exit 1
record_check rollback_manifest_candidate grep -Fqx "candidate_sha256=$main_sha256" "$rollback_manifest" || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
before_main_pid=$(systemctl show keepalived.service -p MainPID --value)
before_restarts=$(systemctl show keepalived.service -p NRestarts --value)
readonly before_main_pid before_restarts
record_check keepalived_pid_numeric_before test "$before_main_pid" -gt 0 || exit 1
record_check keepalived_restarts_numeric_before test "$before_restarts" -ge 0 || exit 1
record_check vrrp_state_master_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER || exit 1
record_check caddy_ipv4_once_before exact_address_once 4 "$caddy_ipv4_cidr" || exit 1
record_check caddy_ipv6_once_before exact_address_once 6 "$caddy_ipv6_cidr" || exit 1
record_check dns_ipv4_once_before exact_address_once 4 "$dns_ipv4_cidr" || exit 1
record_check dns_ipv6_once_before exact_address_once 6 "$dns_ipv6_cidr" || exit 1
record_check dbus_service_absent_before dbus_name_absent_live || exit 1
record_check node_a_https_before https_probe "$node_a_fqdn" 10.1.0.53 || exit 1
record_check caddy_vip_https_before https_probe "$caddy_vip_fqdn" 10.1.0.56 || exit 1

journal_cursor=$(journalctl -u keepalived.service -n 0 --show-cursor --no-pager -o cat | sed -n 's/^-- cursor: //p')
readonly journal_cursor
record_check journal_cursor_captured test -n "$journal_cursor" || exit 1
mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
record_check reload_status run_captured reload systemctl reload keepalived.service || exit 1
record_check runtime_ready wait_for_runtime || exit 1
record_check reload_journal_status run_captured reload_journal journalctl -u keepalived.service --after-cursor="$journal_cursor" --no-pager -o short-iso-precise || exit 1
record_check reload_journal_no_fatal_errors test "$(grep -Eic 'configuration error|unknown keyword|syntax error|security violation|segmentation fault|fatal|unable to open dbus|disabling dbus|lost the name' "$transaction_root/reload_journal.stdout" || true)" -eq 0 || exit 1
record_check reload_journal_no_ttl_rejections test "$(grep -Eic 'TTL/HL .* not in range' "$transaction_root/reload_journal.stdout" || true)" -eq 0 || exit 1
record_check dbus_list_status run_captured dbus_list timeout 5 busctl --system --no-pager --no-legend list || exit 1
record_check dbus_tree_status run_captured dbus_tree timeout 5 busctl --system --no-pager --list tree "$dbus_service" || exit 1
record_check dbus_ipv4_state_status run_captured dbus_ipv4_state timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv4_object" "$dbus_interface" State || exit 1
record_check dbus_ipv6_state_status run_captured dbus_ipv6_state timeout 5 busctl --system --no-pager get-property "$dbus_service" "$dbus_ipv6_object" "$dbus_interface" State || exit 1
record_check dbus_service_present_after dbus_name_present "$transaction_root/dbus_list.stdout" || exit 1
record_check dbus_ipv4_object_present dbus_object_present "$transaction_root/dbus_tree.stdout" "$dbus_ipv4_object" || exit 1
record_check dbus_ipv6_object_present dbus_object_present "$transaction_root/dbus_tree.stdout" "$dbus_ipv6_object" || exit 1
record_check dbus_ipv4_state_master dbus_state_is_master "$transaction_root/dbus_ipv4_state.stdout" || exit 1
record_check dbus_ipv6_state_master dbus_state_is_master "$transaction_root/dbus_ipv6_state.stdout" || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_pid_unchanged test "$(systemctl show keepalived.service -p MainPID --value)" = "$before_main_pid" || exit 1
record_check keepalived_restarts_unchanged test "$(systemctl show keepalived.service -p NRestarts --value)" = "$before_restarts" || exit 1
record_check vrrp_state_master_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER || exit 1
record_check caddy_ipv4_once_after exact_address_once 4 "$caddy_ipv4_cidr" || exit 1
record_check caddy_ipv6_once_after exact_address_once 6 "$caddy_ipv6_cidr" || exit 1
record_check dns_ipv4_once_after exact_address_once 4 "$dns_ipv4_cidr" || exit 1
record_check dns_ipv6_once_after exact_address_once 6 "$dns_ipv6_cidr" || exit 1
record_check main_hash_unchanged test "$(file_hash "$main_configuration")" = "$main_sha256" || exit 1
record_check fragment_hash_unchanged test "$(file_hash "$fragment")" = "$fragment_sha256" || exit 1
record_check health_hash_unchanged test "$(file_hash "$health_helper")" = "$health_sha256" || exit 1
record_check health_root_context "$health_helper" || exit 1
record_check health_keepalived_context runuser -u keepalived_script -- "$health_helper" || exit 1
record_check node_a_https_after https_probe "$node_a_fqdn" 10.1.0.53 || exit 1
record_check caddy_vip_https_after https_probe "$caddy_vip_fqdn" 10.1.0.56 || exit 1

printf '%s_value_main_sha256=%s\n' "$prefix" "$main_sha256"
printf '%s_value_fragment_sha256=%s\n' "$prefix" "$fragment_sha256"
printf '%s_value_health_sha256=%s\n' "$prefix" "$health_sha256"
printf '%s_value_dbus_service=%s\n' "$prefix" "$dbus_service"
printf '%s_value_unicast_ttl=255\n' "$prefix"
printf '%s_value_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_keepalived_reload=true\n' "$prefix"
printf '%s_dbus_runtime_active=true\n' "$prefix"
printf '%s_unicast_ttl_runtime_activation=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
transaction_complete=true
