#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23f_a
readonly expected_hostname=j1-svpihole0
readonly live_ftl=/etc/pihole/pihole-FTL.conf
readonly live_domain=/etc/dnsmasq.d/local.theama.co.conf
readonly backup_dir=/var/backups/caddy-ha/action23f-node-a-pihole-ptr-policy
readonly backup_file=$backup_dir/pihole-FTL.conf.before
readonly backup_manifest=$backup_dir/manifest
readonly transaction_file=/etc/pihole/.pihole-FTL.conf.action23f.new
readonly expected_ftl_sha256=c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa
readonly expected_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96
readonly expected_backup_sha256=c96c3591fabd3cbae4c0b32c695e34a2923a5b52b38e935cda3f2bf24fce1d7b
readonly expected_manifest_sha256=c068bce0d2befb08d3f52b961bfae6888575327ea8e8c19ed42775c013904897
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_a_ipv4_cidr=10.1.0.53/22
readonly node_a_ipv6_cidr=fd36:5aa8:6971:1::53/64
readonly pihole_cli=/usr/local/bin/pihole
readonly ftl_binary=/usr/bin/pihole-FTL
readonly old_ptr_line=PIHOLE_PTR=HOSTNAMEFQDN
readonly new_ptr_line=PIHOLE_PTR=NONE
readonly domain_line=domain=local.theama.co
readonly rejected_domain_line=domain=local.thema.co
readonly maximum_capture_bytes=8192
readonly maximum_capture_lines=128
readonly -a required_commands=(
    awk curl dig find getent grep hostname id ip paste sed sha256sum sort stat
    systemctl timeout wc
)
declare -A seen_checks=()

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
service_value() { systemctl show --property="$2" --value "$1"; }
command_available() { command -v "$1" >/dev/null; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
safe_single_value() {
    [[ ${#1} -gt 0 && ${#1} -le 2048 ]] || return 1
    [[ "$1" != *$'\n'* ]] || return 1
    [[ "$1" =~ ^[0-9A-Za-z:.,_=/@+|#-]+$ ]]
}
valid_mode() {
    [[ ${#1} -eq 3 || ${#1} -eq 4 ]] || return 1
    [[ "$1" != *[!0-7]* ]]
}
record_check() {
    local action23fa_check_label=$1

    shift
    if [[ -n "${seen_checks[$action23fa_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action23fa_check_label" >&2
        return 1
    fi
    seen_checks[$action23fa_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action23fa_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23fa_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action23fa_check_label" >&2
    return 1
}
address_count() {
    local action23fa_family=$1
    local action23fa_cidr=$2

    ip -o "-$action23fa_family" address show dev "$interface" |
        awk -v wanted="$action23fa_cidr" '$4 == wanted { count++ } END { print count + 0 }'
}
https_probe() {
    local action23fa_name=$1
    local action23fa_address=$2

    curl -kfsS -o /dev/null --connect-timeout 3 --max-time 5 \
        --resolve "${action23fa_name}:443:${action23fa_address}" \
        "https://${action23fa_name}/"
}
run_dns_query() (
    trap - ERR

    local action23fa_server=$1
    local action23fa_port=$2
    local action23fa_name=$3
    local action23fa_type=$4

    if [[ "$action23fa_type" == PTR ]]; then
        timeout 4 dig +time=2 +tries=1 +short -p "$action23fa_port" \
            "@$action23fa_server" -x "$action23fa_name" 2>/dev/null
    else
        timeout 4 dig +time=2 +tries=1 +short -p "$action23fa_port" \
            "@$action23fa_server" "$action23fa_name" "$action23fa_type" 2>/dev/null
    fi
)
query_and_emit() {
    local action23fa_label=$1
    local action23fa_server=$2
    local action23fa_port=$3
    local action23fa_name=$4
    local action23fa_type=$5
    local action23fa_expected=$6
    local action23fa_answer=
    local action23fa_status=0

    if action23fa_answer=$(run_dns_query "$action23fa_server" "$action23fa_port" \
        "$action23fa_name" "$action23fa_type"); then
        action23fa_status=0
    else
        action23fa_status=$?
    fi
    action23fa_answer=$(printf '%s\n' "$action23fa_answer" | sed '/^$/d' | LC_ALL=C sort -u | paste -sd, -)
    action23fa_answer=${action23fa_answer:-none}
    record_check "${action23fa_label}_status" test "$action23fa_status" -eq 0 || return 1
    record_check "${action23fa_label}_safe" safe_single_value "$action23fa_answer" || return 1
    printf '%s_value_%s=%s\n' "$prefix" "$action23fa_label" "$action23fa_answer"
    if [[ "$action23fa_expected" != classify ]]; then
        record_check "${action23fa_label}_exact" test "$action23fa_answer" = "$action23fa_expected" || return 1
    fi
}
capture_safe() {
    local action23fa_capture=$1

    [[ $(printf '%s' "$action23fa_capture" | wc -c) -le "$maximum_capture_bytes" ]] || return 1
    [[ $(printf '%s\n' "$action23fa_capture" | wc -l) -le "$maximum_capture_lines" ]] || return 1
    ! grep -Eqi 'WEBPASSWORD|PRIVATE KEY|Authorization:|api[_-]?key|token=' \
        <<<"$action23fa_capture"
}
emit_capture() {
    local action23fa_capture_label=$1
    local action23fa_capture_text=$2
    local action23fa_capture_sha256

    action23fa_capture_sha256=$(printf '%s' "$action23fa_capture_text" | sha256sum | awk '{ print $1 }')
    record_check "${action23fa_capture_label}_safe" capture_safe "$action23fa_capture_text" || return 1
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$action23fa_capture_label" "$action23fa_capture_sha256"
    printf '%s_value_%s_begin\n' "$prefix" "$action23fa_capture_label"
    if [[ -n "$action23fa_capture_text" ]]; then
        printf '%s\n' "$action23fa_capture_text"
    else
        printf 'none\n'
    fi
    printf '%s_value_%s_end\n' "$prefix" "$action23fa_capture_label"
}
capture_acl() {
    if command -v getfacl >/dev/null; then
        getfacl -cp -- "$live_ftl" 2>/dev/null
        return
    fi
    printf 'getfacl_unavailable'
}
residue_count() {
    local action23fa_residue_root=$1
    local action23fa_residue_pattern=$2

    find "$action23fa_residue_root" -maxdepth 1 -mindepth 1 \
        -name "$action23fa_residue_pattern" -print | wc -l
}
state_snapshot() {
    printf 'ftl_hash=%s\n' "$(file_hash "$live_ftl")"
    printf 'ftl_stat=%s\n' "$(stat -c '%U:%G:%u:%g:%a:%A:%s:%i:%d:%Y:%Z' "$live_ftl")"
    printf 'domain_hash=%s\n' "$(file_hash "$live_domain")"
    printf 'backup_hash=%s\n' "$(file_hash "$backup_file")"
    printf 'backup_manifest_hash=%s\n' "$(file_hash "$backup_manifest")"
    printf 'unbound_pid=%s\n' "$(service_value unbound.service MainPID)"
    printf 'unbound_restarts=%s\n' "$(service_value unbound.service NRestarts)"
    printf 'ftl_pid=%s\n' "$(service_value pihole-FTL.service MainPID)"
    printf 'ftl_restarts=%s\n' "$(service_value pihole-FTL.service NRestarts)"
    printf 'caddy_pid=%s\n' "$(service_value caddy.service MainPID)"
    printf 'keepalived_pid=%s\n' "$(service_value keepalived.service MainPID)"
    printf 'vrrp=%s\n' "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)"
    printf 'caddy4=%s\n' "$(address_count 4 "$caddy_ipv4_cidr")"
    printf 'caddy6=%s\n' "$(address_count 6 "$caddy_ipv6_cidr")"
    printf 'dns4=%s\n' "$(address_count 4 "$dns_ipv4_cidr")"
    printf 'dns6=%s\n' "$(address_count 6 "$dns_ipv6_cidr")"
    printf 'node4=%s\n' "$(address_count 4 "$node_a_ipv4_cidr")"
    printf 'node6=%s\n' "$(address_count 6 "$node_a_ipv6_cidr")"
}
emit_expected_checks() {
    local action23fa_expected_command

    for action23fa_expected_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action23fa_expected_command//-/_}"
    done
    printf '%s\n' \
        uid_root working_directory_root hostname_exact ftl_regular ftl_not_symlink \
        ftl_stat_status ftl_stat_safe ftl_owner_resolves ftl_group_resolves \
        ftl_mode_octal_valid ftl_metadata_exact ftl_acl_safe ftl_hash_valid \
        ftl_hash_exact ftl_old_policy_absent ftl_new_policy_exact_once \
        pihole_cli_regular pihole_cli_executable ftl_binary_regular \
        ftl_binary_executable pihole_version_status pihole_version_safe \
        pihole_core_v5 pihole_ftl_v5 ftl_parser_status ftl_parser_output_safe \
        domain_regular domain_not_symlink domain_metadata_exact domain_hash_valid \
        domain_hash_exact domain_exact_once domain_typo_absent \
        backup_directory_exists backup_directory_not_symlink \
        backup_directory_metadata backup_file_regular backup_file_not_symlink \
        backup_file_metadata backup_file_hash_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata \
        backup_manifest_hash_exact backup_manifest_line_count_exact \
        backup_manifest_action_exact backup_manifest_node_exact \
        backup_manifest_before_hash_exact backup_manifest_candidate_hash_exact \
        backup_manifest_old_policy_exact backup_manifest_new_policy_exact \
        backup_manifest_domain_exact transaction_absent \
        run_stage_residue_absent version_residue_absent unbound_active_before \
        pihole_ftl_active_before caddy_active_before lighttpd_active_before \
        keepalived_active_before vrrp_master_before caddy_ipv4_owned_before \
        caddy_ipv6_owned_before dns_ipv4_owned_before dns_ipv6_owned_before \
        node_a_ipv4_owned_before node_a_ipv6_owned_before \
        direct_pihole_a_status direct_pihole_a_safe direct_pihole_a_exact \
        direct_pihole_aaaa_status direct_pihole_aaaa_safe direct_pihole_aaaa_exact \
        direct_node_a_a_status direct_node_a_a_safe direct_node_a_a_exact \
        direct_node_a_aaaa_status direct_node_a_aaaa_safe direct_node_a_aaaa_exact \
        direct_node_b_a_status direct_node_b_a_safe direct_node_b_a_exact \
        direct_node_b_aaaa_status direct_node_b_aaaa_safe direct_node_b_aaaa_exact \
        direct_pihole_ptr4_status direct_pihole_ptr4_safe direct_pihole_ptr4_exact \
        direct_pihole_ptr6_status direct_pihole_ptr6_safe direct_pihole_ptr6_exact \
        direct_node_a_ptr4_status direct_node_a_ptr4_safe direct_node_a_ptr4_exact \
        direct_node_a_ptr6_status direct_node_a_ptr6_safe direct_node_a_ptr6_exact \
        direct_node_b_ptr4_status direct_node_b_ptr4_safe direct_node_b_ptr4_exact \
        direct_node_b_ptr6_status direct_node_b_ptr6_safe direct_node_b_ptr6_exact \
        local_pihole_a_status local_pihole_a_safe local_pihole_a_exact \
        local_pihole_aaaa_status local_pihole_aaaa_safe local_pihole_aaaa_exact \
        local_node_a_a_status local_node_a_a_safe local_node_a_a_exact \
        local_node_a_aaaa_status local_node_a_aaaa_safe local_node_a_aaaa_exact \
        local_node_b_a_status local_node_b_a_safe local_node_b_a_exact \
        local_node_b_aaaa_status local_node_b_aaaa_safe local_node_b_aaaa_exact \
        local_pihole_ptr4_status local_pihole_ptr4_safe local_pihole_ptr4_exact \
        local_pihole_ptr6_status local_pihole_ptr6_safe local_pihole_ptr6_exact \
        local_node_a_ptr4_status local_node_a_ptr4_safe local_node_a_ptr4_exact \
        local_node_a_ptr6_status local_node_a_ptr6_safe local_node_a_ptr6_exact \
        local_node_b_ptr4_status local_node_b_ptr4_safe local_node_b_ptr4_exact \
        local_node_b_ptr6_status local_node_b_ptr6_safe local_node_b_ptr6_exact \
        node_a_https caddy_vip_https node_b_https \
        unbound_active_after pihole_ftl_active_after caddy_active_after \
        lighttpd_active_after keepalived_active_after vrrp_master_after \
        caddy_ipv4_owned_after caddy_ipv6_owned_after dns_ipv4_owned_after \
        dns_ipv6_owned_after node_a_ipv4_owned_after node_a_ipv6_owned_after \
        backup_file_hash_stable_after backup_manifest_hash_stable_after \
        transaction_absent_after run_stage_residue_absent_after \
        version_residue_absent_after state_unchanged
}
emit_contract_transcript() {
    local action23fa_contract_label
    local action23fa_contract_count=0
    local action23fa_fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    while IFS= read -r action23fa_contract_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action23fa_contract_label"
        action23fa_contract_count=$((action23fa_contract_count + 1))
    done < <(emit_expected_checks)
    printf '%s_value_ftl_stat=owner=pihole|group=root|uid=999|gid=0|mode_octal=664|mode_symbolic=-rw-rw-r--|size=100|inode=1|device=1|mtime=1|ctime=1\n' "$prefix"
    printf '%s_value_ftl_sha256=%s\n' "$prefix" "$expected_ftl_sha256"
    printf '%s_value_domain_sha256=%s\n' "$prefix" "$expected_domain_sha256"
    printf '%s_value_backup_sha256=%s\n' "$prefix" "$expected_backup_sha256"
    printf '%s_value_backup_manifest_sha256=%s\n' "$prefix" "$expected_manifest_sha256"
    printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action23fa_fixture_hash"
    printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action23fa_fixture_hash"
    printf '%s_check_count=%s\n' "$prefix" "$action23fa_contract_count"
    printf '%s_failed_check_count=0\n' "$prefix"
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_filesystem_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_pihole_restart=false\n' "$prefix"
    printf '%s_action_23e_rerun=false\n' "$prefix"
    printf '%s_action_23f_rerun=false\n' "$prefix"
    printf '%s_peer_ssh=false\n' "$prefix"
    printf '%s_remote_complete=true\n' "$prefix"
}
self_test() {
    [[ "$expected_hostname" == j1-svpihole0 ]] || return 1
    [[ "$old_ptr_line|$new_ptr_line" == 'PIHOLE_PTR=HOSTNAMEFQDN|PIHOLE_PTR=NONE' ]] || return 1
    [[ "$domain_line|$rejected_domain_line" == 'domain=local.theama.co|domain=local.thema.co' ]] || return 1
    [[ "$expected_ftl_sha256" == c77de6654c575e12fa1661f8ec901de67d9a623c3e9b965d4e32b550c132a7aa ]] || return 1
    [[ "$expected_backup_sha256" == c96c3591fabd3cbae4c0b32c695e34a2923a5b52b38e935cda3f2bf24fce1d7b ]] || return 1
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

for action23fa_required_command in "${required_commands[@]}"; do
    record_check "command_${action23fa_required_command//-/_}_available" \
        command_available "$action23fa_required_command" || exit 1
done
record_check uid_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$PWD" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check ftl_regular test -f "$live_ftl" || exit 1
record_check ftl_not_symlink test ! -L "$live_ftl" || exit 1

ftl_stat_status=0
ftl_stat=$(stat -c 'owner=%U|group=%G|uid=%u|gid=%g|mode_octal=%a|mode_symbolic=%A|size=%s|inode=%i|device=%d|mtime=%Y|ctime=%Z' "$live_ftl") || ftl_stat_status=$?
readonly ftl_stat_status ftl_stat
record_check ftl_stat_status test "$ftl_stat_status" -eq 0 || exit 1
record_check ftl_stat_safe safe_single_value "$ftl_stat" || exit 1
printf '%s_value_ftl_stat=%s\n' "$prefix" "$ftl_stat"
ftl_owner=$(stat -c %U "$live_ftl")
ftl_group=$(stat -c %G "$live_ftl")
ftl_mode=$(stat -c %a "$live_ftl")
readonly ftl_owner ftl_group ftl_mode
record_check ftl_owner_resolves getent passwd "$ftl_owner" || exit 1
record_check ftl_group_resolves getent group "$ftl_group" || exit 1
record_check ftl_mode_octal_valid valid_mode "$ftl_mode" || exit 1
record_check ftl_metadata_exact test "$ftl_owner:$ftl_group:$ftl_mode" = pihole:root:664 || exit 1
ftl_acl=$(capture_acl)
readonly ftl_acl
emit_capture ftl_acl "$ftl_acl" || exit 1

ftl_sha256=$(file_hash "$live_ftl")
domain_sha256=$(file_hash "$live_domain")
readonly ftl_sha256 domain_sha256
record_check ftl_hash_valid valid_sha256 "$ftl_sha256" || exit 1
record_check ftl_hash_exact test "$ftl_sha256" = "$expected_ftl_sha256" || exit 1
record_check ftl_old_policy_absent test "$(grep -Fxc "$old_ptr_line" "$live_ftl" || true)" -eq 0 || exit 1
record_check ftl_new_policy_exact_once test "$(grep -Fxc "$new_ptr_line" "$live_ftl" || true)" -eq 1 || exit 1
record_check pihole_cli_regular test -f "$pihole_cli" || exit 1
record_check pihole_cli_executable test -x "$pihole_cli" || exit 1
record_check ftl_binary_regular test -f "$ftl_binary" || exit 1
record_check ftl_binary_executable test -x "$ftl_binary" || exit 1
pihole_version_status=0
pihole_version=$($pihole_cli -v 2>&1) || pihole_version_status=$?
readonly pihole_version_status pihole_version
record_check pihole_version_status test "$pihole_version_status" -eq 0 || exit 1
emit_capture pihole_version "$pihole_version" || exit 1
record_check pihole_core_v5 grep -Eq 'Pi-hole version is v5([.]|$)' <<<"$pihole_version" || exit 1
record_check pihole_ftl_v5 grep -Eq 'FTL version is v5([.]|$)' <<<"$pihole_version" || exit 1
ftl_parser_status=0
ftl_parser_output=$($ftl_binary --test 2>&1) || ftl_parser_status=$?
readonly ftl_parser_status ftl_parser_output
record_check ftl_parser_status test "$ftl_parser_status" -eq 0 || exit 1
emit_capture ftl_parser_output "$ftl_parser_output" || exit 1
record_check domain_regular test -f "$live_domain" || exit 1
record_check domain_not_symlink test ! -L "$live_domain" || exit 1
record_check domain_metadata_exact test "$(stat -c '%U:%G:%a' "$live_domain")" = root:root:644 || exit 1
record_check domain_hash_valid valid_sha256 "$domain_sha256" || exit 1
record_check domain_hash_exact test "$domain_sha256" = "$expected_domain_sha256" || exit 1
record_check domain_exact_once test "$(grep -Fxc "$domain_line" "$live_domain" || true)" -eq 1 || exit 1
record_check domain_typo_absent test "$(grep -Fxc "$rejected_domain_line" "$live_domain" || true)" -eq 0 || exit 1
record_check backup_directory_exists test -d "$backup_dir" || exit 1
record_check backup_directory_not_symlink test ! -L "$backup_dir" || exit 1
record_check backup_directory_metadata test "$(stat -c '%U:%G:%a' "$backup_dir")" = root:root:700 || exit 1
record_check backup_file_regular test -f "$backup_file" || exit 1
record_check backup_file_not_symlink test ! -L "$backup_file" || exit 1
record_check backup_file_metadata test "$(stat -c '%U:%G:%a' "$backup_file")" = root:root:600 || exit 1
record_check backup_file_hash_exact test "$(file_hash "$backup_file")" = "$expected_backup_sha256" || exit 1
record_check backup_manifest_regular test -f "$backup_manifest" || exit 1
record_check backup_manifest_not_symlink test ! -L "$backup_manifest" || exit 1
record_check backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest")" = root:root:600 || exit 1
record_check backup_manifest_hash_exact test "$(file_hash "$backup_manifest")" = "$expected_manifest_sha256" || exit 1
record_check backup_manifest_line_count_exact test "$(wc -l <"$backup_manifest")" -eq 7 || exit 1
record_check backup_manifest_action_exact test "$(grep -Fxc 'action=23f' "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_node_exact test "$(grep -Fxc 'node=j1-svpihole0' "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_before_hash_exact test "$(grep -Fxc "before_sha256=$expected_backup_sha256" "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_candidate_hash_exact test "$(grep -Fxc "candidate_sha256=$expected_ftl_sha256" "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_old_policy_exact test "$(grep -Fxc 'old_policy=HOSTNAMEFQDN' "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_new_policy_exact test "$(grep -Fxc 'new_policy=NONE' "$backup_manifest" || true)" -eq 1 || exit 1
record_check backup_manifest_domain_exact test "$(grep -Fxc 'domain=local.theama.co' "$backup_manifest" || true)" -eq 1 || exit 1
record_check transaction_absent test ! -e "$transaction_file" || exit 1
record_check run_stage_residue_absent test "$(residue_count /run 'caddy-action23f.*')" -eq 0 || exit 1
record_check version_residue_absent test "$(residue_count /tmp 'caddy-action23f-version.*')" -eq 0 || exit 1
record_check unbound_active_before systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_before systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_master_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = MASTER || exit 1
record_check caddy_ipv4_owned_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || exit 1
record_check caddy_ipv6_owned_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || exit 1
record_check dns_ipv4_owned_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 || exit 1
record_check dns_ipv6_owned_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 || exit 1
record_check node_a_ipv4_owned_before test "$(address_count 4 "$node_a_ipv4_cidr")" -eq 1 || exit 1
record_check node_a_ipv6_owned_before test "$(address_count 6 "$node_a_ipv6_cidr")" -eq 1 || exit 1

before_state=$(state_snapshot)
readonly before_state
before_state_sha256=$(printf '%s' "$before_state" | sha256sum | awk '{ print $1 }')
readonly before_state_sha256
query_and_emit direct_pihole_a 127.0.0.1 5335 pihole.local.theama.co A 10.1.0.55 || exit 1
query_and_emit direct_pihole_aaaa 127.0.0.1 5335 pihole.local.theama.co AAAA fd36:5aa8:6971:1::55 || exit 1
query_and_emit direct_node_a_a 127.0.0.1 5335 pihole0.local.theama.co A 10.1.0.53 || exit 1
query_and_emit direct_node_a_aaaa 127.0.0.1 5335 pihole0.local.theama.co AAAA fd36:5aa8:6971:1::53 || exit 1
query_and_emit direct_node_b_a 127.0.0.1 5335 pihole00.local.theama.co A 10.1.0.54 || exit 1
query_and_emit direct_node_b_aaaa 127.0.0.1 5335 pihole00.local.theama.co AAAA fd36:5aa8:6971:1::54 || exit 1
query_and_emit direct_pihole_ptr4 127.0.0.1 5335 10.1.0.55 PTR pihole.local.theama.co. || exit 1
query_and_emit direct_pihole_ptr6 127.0.0.1 5335 fd36:5aa8:6971:1::55 PTR pihole.local.theama.co. || exit 1
query_and_emit direct_node_a_ptr4 127.0.0.1 5335 10.1.0.53 PTR pihole0.local.theama.co. || exit 1
query_and_emit direct_node_a_ptr6 127.0.0.1 5335 fd36:5aa8:6971:1::53 PTR pihole0.local.theama.co. || exit 1
query_and_emit direct_node_b_ptr4 127.0.0.1 5335 10.1.0.54 PTR pihole00.local.theama.co. || exit 1
query_and_emit direct_node_b_ptr6 127.0.0.1 5335 fd36:5aa8:6971:1::54 PTR pihole00.local.theama.co. || exit 1
query_and_emit local_pihole_a 127.0.0.1 53 pihole.local.theama.co A 10.1.0.55 || exit 1
query_and_emit local_pihole_aaaa 127.0.0.1 53 pihole.local.theama.co AAAA fd36:5aa8:6971:1::55 || exit 1
query_and_emit local_node_a_a 127.0.0.1 53 pihole0.local.theama.co A 10.1.0.53 || exit 1
query_and_emit local_node_a_aaaa 127.0.0.1 53 pihole0.local.theama.co AAAA fd36:5aa8:6971:1::53 || exit 1
query_and_emit local_node_b_a 127.0.0.1 53 pihole00.local.theama.co A 10.1.0.54 || exit 1
query_and_emit local_node_b_aaaa 127.0.0.1 53 pihole00.local.theama.co AAAA fd36:5aa8:6971:1::54 || exit 1
query_and_emit local_pihole_ptr4 127.0.0.1 53 10.1.0.55 PTR pihole.local.theama.co. || exit 1
query_and_emit local_pihole_ptr6 127.0.0.1 53 fd36:5aa8:6971:1::55 PTR pihole.local.theama.co. || exit 1
query_and_emit local_node_a_ptr4 127.0.0.1 53 10.1.0.53 PTR pihole0.local.theama.co. || exit 1
query_and_emit local_node_a_ptr6 127.0.0.1 53 fd36:5aa8:6971:1::53 PTR pihole0.local.theama.co. || exit 1
query_and_emit local_node_b_ptr4 127.0.0.1 53 10.1.0.54 PTR pihole00.local.theama.co. || exit 1
query_and_emit local_node_b_ptr6 127.0.0.1 53 fd36:5aa8:6971:1::54 PTR pihole00.local.theama.co. || exit 1
record_check node_a_https https_probe pihole0.local.theama.co 10.1.0.53 || exit 1
record_check caddy_vip_https https_probe pihole-admin.local.theama.co 10.1.0.56 || exit 1
record_check node_b_https https_probe pihole00.local.theama.co 10.1.0.54 || exit 1

record_check unbound_active_after systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_after systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_master_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state)" = MASTER || exit 1
record_check caddy_ipv4_owned_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || exit 1
record_check caddy_ipv6_owned_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || exit 1
record_check dns_ipv4_owned_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 || exit 1
record_check dns_ipv6_owned_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 || exit 1
record_check node_a_ipv4_owned_after test "$(address_count 4 "$node_a_ipv4_cidr")" -eq 1 || exit 1
record_check node_a_ipv6_owned_after test "$(address_count 6 "$node_a_ipv6_cidr")" -eq 1 || exit 1
record_check backup_file_hash_stable_after test "$(file_hash "$backup_file")" = "$expected_backup_sha256" || exit 1
record_check backup_manifest_hash_stable_after test "$(file_hash "$backup_manifest")" = "$expected_manifest_sha256" || exit 1
record_check transaction_absent_after test ! -e "$transaction_file" || exit 1
record_check run_stage_residue_absent_after test "$(residue_count /run 'caddy-action23f.*')" -eq 0 || exit 1
record_check version_residue_absent_after test "$(residue_count /tmp 'caddy-action23f-version.*')" -eq 0 || exit 1
after_state=$(state_snapshot)
readonly after_state
after_state_sha256=$(printf '%s' "$after_state" | sha256sum | awk '{ print $1 }')
readonly after_state_sha256
record_check state_unchanged test "$after_state_sha256" = "$before_state_sha256" || exit 1

expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
[[ "${#seen_checks[@]}" -eq "$expected_count" ]] || exit 97
printf '%s_value_ftl_sha256=%s\n' "$prefix" "$ftl_sha256"
printf '%s_value_domain_sha256=%s\n' "$prefix" "$domain_sha256"
printf '%s_value_backup_sha256=%s\n' "$prefix" "$(file_hash "$backup_file")"
printf '%s_value_backup_manifest_sha256=%s\n' "$prefix" "$(file_hash "$backup_manifest")"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_check_count=%s\n' "$prefix" "${#seen_checks[@]}"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_pihole_restart=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_action_23f_rerun=false\n' "$prefix"
printf '%s_peer_ssh=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
