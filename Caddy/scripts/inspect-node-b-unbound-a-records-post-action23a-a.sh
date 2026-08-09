#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a
readonly expected_hostname=j1-svpihole00
readonly live_root=/etc/unbound/unbound.conf
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly installed_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly prior_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly backup_dir=/var/backups/caddy-ha/action23a-node-b-unbound-a-records
readonly backup_file=$backup_dir/pihole-local-zone.conf.before
readonly backup_manifest=$backup_dir/manifest
readonly transaction_file=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action23a.new
readonly caddy_ipv4=10.1.0.56
readonly node_a_ipv4=10.1.0.53
readonly pihole_ipv4=10.1.0.55
readonly pihole_ipv6=fd36:5aa8:6971:1::55
readonly pihole_fqdn=pihole.local.theama.co
readonly proxy_fqdn=proxy.local.theama.co
readonly admin_fqdn=pihole-admin.local.theama.co
readonly node_a_fqdn=pihole0.local.theama.co
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
declare -A seen_checks=()

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
service_value() { systemctl show --property="$2" --value "$1"; }
address_count() {
    local action23aa_address_family=$1
    local action23aa_address_value=$2

    ip -o "-$action23aa_address_family" address show dev eth0 |
        awk -v wanted="$action23aa_address_value" '$4 == wanted { count++ } END { print count + 0 }'
}
valid_sha256() {
    local action23aa_hash_value=$1

    [[ ${#action23aa_hash_value} -eq 64 ]] || return 1
    [[ "$action23aa_hash_value" != *[!0-9a-f]* ]]
}
record_check() {
    local action23aa_check_label=$1

    shift
    if [[ -n "${seen_checks[$action23aa_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action23aa_check_label" >&2
        return 1
    fi
    seen_checks[$action23aa_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action23aa_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23aa_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action23aa_check_label" >&2
    return 1
}
https_probe() {
    local action23aa_https_name=$1
    local action23aa_https_address=$2

    curl -kfsS -o /dev/null --connect-timeout 3 --max-time 5 \
        --resolve "${action23aa_https_name}:443:${action23aa_https_address}" \
        "https://${action23aa_https_name}/"
}
safe_answer() {
    local action23aa_answer=$1

    [[ ${#action23aa_answer} -le 512 ]] || return 1
    [[ "$action23aa_answer" != *$'\n'* ]] || return 1
    [[ "$action23aa_answer" != *[!0-9A-Za-z:.,_-]* ]]
}
dns_check() {
    local action23aa_dns_label=$1
    local action23aa_dns_port=$2
    local action23aa_dns_name=$3
    local action23aa_dns_type=$4
    local action23aa_dns_expected=$5
    local action23aa_dns_output=
    local action23aa_dns_status=0

    if [[ "$action23aa_dns_type" == PTR ]]; then
        if action23aa_dns_output=$(timeout 3 dig +time=2 +tries=1 +short \
            -p "$action23aa_dns_port" @127.0.0.1 -x "$action23aa_dns_name" 2>/dev/null); then
            action23aa_dns_status=0
        else
            action23aa_dns_status=$?
        fi
    elif action23aa_dns_output=$(timeout 3 dig +time=2 +tries=1 +short \
        -p "$action23aa_dns_port" @127.0.0.1 \
        "$action23aa_dns_name" "$action23aa_dns_type" 2>/dev/null); then
        action23aa_dns_status=0
    else
        action23aa_dns_status=$?
    fi
    action23aa_dns_output=$(printf '%s\n' "$action23aa_dns_output" |
        sed '/^$/d' | LC_ALL=C sort -u | paste -sd, -)
    record_check "${action23aa_dns_label}_command_status" \
        test "$action23aa_dns_status" -eq 0 || return 1
    record_check "${action23aa_dns_label}_answer_safe" \
        safe_answer "$action23aa_dns_output" || return 1
    record_check "${action23aa_dns_label}_answer_exact" \
        test "$action23aa_dns_output" = "$action23aa_dns_expected" || return 1
    printf '%s_value_%s_answer=%s\n' "$prefix" "$action23aa_dns_label" "$action23aa_dns_output"
}
state_snapshot() {
    printf 'primary=%s\n' "$(file_hash "$live_primary")"
    printf 'local_zone=%s\n' "$(file_hash "$live_local_zone")"
    printf 'local_zone_meta=%s\n' "$(stat -c '%U:%G:%a' "$live_local_zone")"
    printf 'backup=%s\n' "$(file_hash "$backup_file")"
    printf 'manifest=%s\n' "$(file_hash "$backup_manifest")"
    printf 'unbound_pid=%s\n' "$(service_value unbound.service MainPID)"
    printf 'unbound_restarts=%s\n' "$(service_value unbound.service NRestarts)"
    printf 'ftl_pid=%s\n' "$(service_value pihole-FTL.service MainPID)"
    printf 'ftl_restarts=%s\n' "$(service_value pihole-FTL.service NRestarts)"
    printf 'vrrp=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)"
    printf 'caddy4=%s\n' "$(address_count 4 "$caddy_ipv4_cidr")"
    printf 'caddy6=%s\n' "$(address_count 6 "$caddy_ipv6_cidr")"
    printf 'dns4=%s\n' "$(address_count 4 "$dns_ipv4_cidr")"
    printf 'dns6=%s\n' "$(address_count 6 "$dns_ipv6_cidr")"
}
emit_expected_checks() {
    printf '%s\n' \
        uid_root working_directory_root hostname_exact \
        live_root_regular live_root_not_symlink primary_regular \
        primary_not_symlink primary_hash_exact local_zone_regular \
        local_zone_not_symlink local_zone_metadata local_zone_hash_exact \
        local_zone_admin_a_once local_zone_proxy_a_once \
        local_zone_caddy_aaaa_absent local_zone_caddy_ptr_absent \
        local_zone_caddy_srv_absent local_zone_homeassistant_absent \
        unbound_configuration_valid backup_directory_metadata \
        backup_file_regular backup_file_not_symlink backup_file_metadata \
        backup_file_hash_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata \
        backup_manifest_line_count backup_manifest_action \
        backup_manifest_node backup_manifest_record_family \
        backup_manifest_before_hash backup_manifest_after_hash \
        transaction_entry_absent transaction_symlink_absent \
        remote_stage_residue_absent unbound_active_before \
        pihole_ftl_active_before caddy_active_before lighttpd_active_before \
        keepalived_active_before unbound_pid_before_numeric \
        unbound_restarts_before_numeric pihole_ftl_pid_before_numeric \
        pihole_ftl_restarts_before_numeric vrrp_state_backup_before \
        caddy_ipv4_absent_before caddy_ipv6_absent_before \
        dns_ipv4_absent_before dns_ipv6_absent_before \
        direct_proxy_a_command_status direct_proxy_a_answer_safe \
        direct_proxy_a_answer_exact direct_admin_a_command_status \
        direct_admin_a_answer_safe direct_admin_a_answer_exact \
        local_proxy_a_command_status local_proxy_a_answer_safe \
        local_proxy_a_answer_exact local_admin_a_command_status \
        local_admin_a_answer_safe local_admin_a_answer_exact \
        direct_pihole_a_command_status direct_pihole_a_answer_safe \
        direct_pihole_a_answer_exact direct_pihole_aaaa_command_status \
        direct_pihole_aaaa_answer_safe direct_pihole_aaaa_answer_exact \
        direct_pihole_ptr4_command_status direct_pihole_ptr4_answer_safe \
        direct_pihole_ptr4_answer_exact local_pihole_a_command_status \
        local_pihole_a_answer_safe local_pihole_a_answer_exact \
        local_pihole_aaaa_command_status local_pihole_aaaa_answer_safe \
        local_pihole_aaaa_answer_exact local_pihole_ptr4_command_status \
        local_pihole_ptr4_answer_safe local_pihole_ptr4_answer_exact \
        node_a_management_https caddy_vip_https unbound_active_after \
        pihole_ftl_active_after caddy_active_after lighttpd_active_after \
        keepalived_active_after vrrp_state_backup_after \
        caddy_ipv4_absent_after caddy_ipv6_absent_after \
        dns_ipv4_absent_after dns_ipv6_absent_after state_unchanged
}
emit_contract_transcript() {
    local action23aa_contract_label
    local action23aa_contract_count=0
    local action23aa_fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    while IFS= read -r action23aa_contract_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action23aa_contract_label"
        action23aa_contract_count=$((action23aa_contract_count + 1))
    done < <(emit_expected_checks)
    printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action23aa_fixture_hash"
    printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action23aa_fixture_hash"
    printf '%s_value_local_zone_sha256=%s\n' "$prefix" "$installed_sha256"
    printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
    printf '%s_check_count=%s\n' "$prefix" "$action23aa_contract_count"
    printf '%s_failed_check_count=0\n' "$prefix"
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_filesystem_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_peer_ssh=false\n' "$prefix"
    printf '%s_remote_complete=true\n' "$prefix"
}
self_test() {
    [[ "$expected_hostname" == j1-svpihole00 ]] || return 1
    [[ "$installed_sha256" == b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160 ]] || return 1
    [[ "$prior_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]] || return 1
    [[ "$(emit_expected_checks | wc -l)" -eq "$(emit_expected_checks | LC_ALL=C sort -u | wc -l)" ]] || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
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
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

for action23aa_required_command in awk curl dig grep hostname id ip paste sed \
    sha256sum sort stat systemctl timeout unbound-checkconf wc; do
    command -v "$action23aa_required_command" >/dev/null || exit 1
done

record_check uid_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$(pwd -P)" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check live_root_regular test -f "$live_root" || exit 1
record_check live_root_not_symlink test ! -L "$live_root" || exit 1
record_check primary_regular test -f "$live_primary" || exit 1
record_check primary_not_symlink test ! -L "$live_primary" || exit 1
record_check primary_hash_exact test "$(file_hash "$live_primary")" = "$primary_sha256" || exit 1
record_check local_zone_regular test -f "$live_local_zone" || exit 1
record_check local_zone_not_symlink test ! -L "$live_local_zone" || exit 1
record_check local_zone_metadata test "$(stat -c '%U:%G:%a' "$live_local_zone")" = root:root:644 || exit 1
record_check local_zone_hash_exact test "$(file_hash "$live_local_zone")" = "$installed_sha256" || exit 1
record_check local_zone_admin_a_once test "$(grep -Fxc '    local-data: "pihole-admin.local.theama.co. IN A 10.1.0.56"' "$live_local_zone" || true)" -eq 1 || exit 1
record_check local_zone_proxy_a_once test "$(grep -Fxc '    local-data: "proxy.local.theama.co. IN A 10.1.0.56"' "$live_local_zone" || true)" -eq 1 || exit 1
record_check local_zone_caddy_aaaa_absent test "$(grep -Ec '(pihole-admin|proxy)[.]local[.]theama[.]co[.].* IN AAAA ' "$live_local_zone" || true)" -eq 0 || exit 1
record_check local_zone_caddy_ptr_absent test "$(grep -Ec 'local-data-ptr: "(10[.]1[.]0[.]56|fd36:5aa8:6971:1::56) ' "$live_local_zone" || true)" -eq 0 || exit 1
record_check local_zone_caddy_srv_absent test "$(grep -Fc '_https._tcp.proxy.local.theama.co.' "$live_local_zone" || true)" -eq 0 || exit 1
record_check local_zone_homeassistant_absent test "$(grep -Fc 'homeassistant.local.theama.co' "$live_local_zone" || true)" -eq 0 || exit 1
record_check unbound_configuration_valid unbound-checkconf "$live_root" >/dev/null || exit 1
record_check backup_directory_metadata test "$(stat -c '%U:%G:%a' "$backup_dir" 2>/dev/null || true)" = root:root:700 || exit 1
record_check backup_file_regular test -f "$backup_file" || exit 1
record_check backup_file_not_symlink test ! -L "$backup_file" || exit 1
record_check backup_file_metadata test "$(stat -c '%U:%G:%a' "$backup_file")" = root:root:600 || exit 1
record_check backup_file_hash_exact test "$(file_hash "$backup_file")" = "$prior_sha256" || exit 1
record_check backup_manifest_regular test -f "$backup_manifest" || exit 1
record_check backup_manifest_not_symlink test ! -L "$backup_manifest" || exit 1
record_check backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest")" = root:root:600 || exit 1
record_check backup_manifest_line_count test "$(wc -l <"$backup_manifest")" -eq 5 || exit 1
record_check backup_manifest_action grep -Fqx 'action=23a' "$backup_manifest" || exit 1
record_check backup_manifest_node grep -Fqx 'node=j1-svpihole00' "$backup_manifest" || exit 1
record_check backup_manifest_record_family grep -Fqx 'record_family=A' "$backup_manifest" || exit 1
record_check backup_manifest_before_hash grep -Fqx "local_zone_before_sha256=$prior_sha256" "$backup_manifest" || exit 1
record_check backup_manifest_after_hash grep -Fqx "local_zone_after_sha256=$installed_sha256" "$backup_manifest" || exit 1
record_check transaction_entry_absent test ! -e "$transaction_file" || exit 1
record_check transaction_symlink_absent test ! -L "$transaction_file" || exit 1
record_check remote_stage_residue_absent test -z "$(compgen -G '/run/caddy-action23a.*' || true)" || exit 1

before_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly before_state
record_check unbound_active_before systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_before systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check unbound_pid_before_numeric test "$(service_value unbound.service MainPID)" -gt 0 || exit 1
record_check unbound_restarts_before_numeric test "$(service_value unbound.service NRestarts)" -ge 0 || exit 1
record_check pihole_ftl_pid_before_numeric test "$(service_value pihole-FTL.service MainPID)" -gt 0 || exit 1
record_check pihole_ftl_restarts_before_numeric test "$(service_value pihole-FTL.service NRestarts)" -ge 0 || exit 1
record_check vrrp_state_backup_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1

dns_check direct_proxy_a 5335 "$proxy_fqdn" A "$caddy_ipv4" || exit 1
dns_check direct_admin_a 5335 "$admin_fqdn" A "$caddy_ipv4" || exit 1
dns_check local_proxy_a 53 "$proxy_fqdn" A "$caddy_ipv4" || exit 1
dns_check local_admin_a 53 "$admin_fqdn" A "$caddy_ipv4" || exit 1
dns_check direct_pihole_a 5335 "$pihole_fqdn" A "$pihole_ipv4" || exit 1
dns_check direct_pihole_aaaa 5335 "$pihole_fqdn" AAAA "$pihole_ipv6" || exit 1
dns_check direct_pihole_ptr4 5335 "$pihole_ipv4" PTR "${pihole_fqdn}." || exit 1
dns_check local_pihole_a 53 "$pihole_fqdn" A "$pihole_ipv4" || exit 1
dns_check local_pihole_aaaa 53 "$pihole_fqdn" AAAA "$pihole_ipv6" || exit 1
dns_check local_pihole_ptr4 53 "$pihole_ipv4" PTR "${pihole_fqdn}." || exit 1
record_check node_a_management_https https_probe "$node_a_fqdn" "$node_a_ipv4" || exit 1
record_check caddy_vip_https https_probe "$admin_fqdn" "$caddy_ipv4" || exit 1
record_check unbound_active_after systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_after systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_state_backup_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
after_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly after_state
record_check state_unchanged test "$before_state" = "$after_state" || exit 1

expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
record_check_count=${#seen_checks[@]}
readonly record_check_count
[[ "$record_check_count" -eq "$expected_count" ]] || exit 1
valid_sha256 "$before_state" || exit 1
valid_sha256 "$after_state" || exit 1
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state"
printf '%s_value_local_zone_sha256=%s\n' "$prefix" "$installed_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
printf '%s_check_count=%s\n' "$prefix" "$record_check_count"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_peer_ssh=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
