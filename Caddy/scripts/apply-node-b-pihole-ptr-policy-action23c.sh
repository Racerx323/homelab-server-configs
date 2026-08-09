#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23c
readonly expected_hostname=j1-svpihole00
readonly live_ftl=/etc/pihole/pihole-FTL.conf
readonly live_domain=/etc/dnsmasq.d/local.theama.co.conf
readonly backup_dir=/var/backups/caddy-ha/action23c-node-b-pihole-ptr-policy
readonly transaction_file=/etc/pihole/.pihole-FTL.conf.action23c.new
readonly old_ptr_line=PIHOLE_PTR=HOSTNAMEFQDN
readonly new_ptr_line=PIHOLE_PTR=NONE
readonly domain_line=domain=local.theama.co
readonly misspelled_domain_line=domain=local.thema.co
readonly pihole_cli=/usr/local/bin/pihole
readonly ftl_binary=/usr/bin/pihole-FTL
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly node_b_ipv4_cidr=10.1.0.54/22
readonly node_b_ipv6_cidr=fd36:5aa8:6971:1::54/64
readonly caddy_fqdn=pihole-admin.local.theama.co
readonly node_a_fqdn=pihole0.local.theama.co
readonly node_b_fqdn=pihole00.local.theama.co
readonly -a required_commands=(
    awk chmod curl dig grep hostname id install ip mktemp mv rm sed sha256sum
    sleep sort stat systemctl timeout wc
)
declare -A seen_checks=()
mutation_started=false
transaction_complete=false
stage_dir=
before_ftl_sha256=
candidate_ftl_sha256=
before_domain_sha256=
pre_unbound_pid=
pre_unbound_restarts=
pre_caddy_pid=
pre_caddy_restarts=
pre_keepalived_pid=
pre_keepalived_restarts=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
service_value() { systemctl show --property="$2" --value "$1"; }
address_count() {
    local action23c_family=$1
    local action23c_cidr=$2

    ip -o "-$action23c_family" address show dev "$interface" |
        awk -v wanted="$action23c_cidr" '$4 == wanted { count++ } END { print count + 0 }'
}
record_check() {
    local action23c_check_label=$1

    shift
    if [[ -n "${seen_checks[$action23c_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action23c_check_label" >&2
        return 1
    fi
    seen_checks[$action23c_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action23c_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23c_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action23c_check_label" >&2
    return 1
}
run_dns_query() (
    trap - ERR

    local action23c_server=$1
    local action23c_port=$2
    local action23c_name=$3
    local action23c_type=$4

    if [[ "$action23c_type" == PTR ]]; then
        timeout 4 dig +time=2 +tries=1 +short -p "$action23c_port" \
            "@$action23c_server" -x "$action23c_name" 2>/dev/null
    else
        timeout 4 dig +time=2 +tries=1 +short -p "$action23c_port" \
            "@$action23c_server" "$action23c_name" "$action23c_type" 2>/dev/null
    fi
)
query_exact() {
    local action23c_server=$1
    local action23c_port=$2
    local action23c_name=$3
    local action23c_type=$4
    local action23c_expected=$5
    local action23c_answer=

    action23c_answer=$(run_dns_query "$action23c_server" "$action23c_port" \
        "$action23c_name" "$action23c_type") || return 1
    action23c_answer=$(printf '%s\n' "$action23c_answer" | sed '/^$/d' | sort -u)
    [[ "$action23c_answer" == "$action23c_expected" ]]
}
https_probe() {
    local action23c_name=$1
    local action23c_address=$2

    curl -kfsS -o /dev/null --connect-timeout 3 --max-time 5 \
        --resolve "${action23c_name}:443:${action23c_address}" \
        "https://${action23c_name}/"
}
capture_pihole_version() {
    local action23c_version_output=$1

    "$pihole_cli" -v >"$action23c_version_output" 2>&1
}
validate_ftl_configuration() {
    "$ftl_binary" --test >/dev/null 2>&1
}
validate_candidate_delta() {
    local action23c_candidate=$1
    local action23c_reconstructed=$2

    [[ "$(grep -Fxc "$new_ptr_line" "$action23c_candidate" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "$old_ptr_line" "$action23c_candidate" || true)" -eq 0 ]] || return 1
    awk -v old="$old_ptr_line" -v new="$new_ptr_line" '
        $0 == new { print old; changed++; next }
        { print }
        END { if (changed != 1) exit 42 }
    ' "$action23c_candidate" >"$action23c_reconstructed" || return 1
    [[ "$(file_hash "$action23c_reconstructed")" == "$before_ftl_sha256" ]]
}
validate_all_records() {
    local action23c_path=$1
    local action23c_server=$2
    local action23c_port=$3

    record_check "${action23c_path}_pihole_a" query_exact "$action23c_server" "$action23c_port" \
        pihole.local.theama.co A 10.1.0.55 || return 1
    record_check "${action23c_path}_pihole_aaaa" query_exact "$action23c_server" "$action23c_port" \
        pihole.local.theama.co AAAA fd36:5aa8:6971:1::55 || return 1
    record_check "${action23c_path}_node_a_a" query_exact "$action23c_server" "$action23c_port" \
        pihole0.local.theama.co A 10.1.0.53 || return 1
    record_check "${action23c_path}_node_a_aaaa" query_exact "$action23c_server" "$action23c_port" \
        pihole0.local.theama.co AAAA fd36:5aa8:6971:1::53 || return 1
    record_check "${action23c_path}_node_b_a" query_exact "$action23c_server" "$action23c_port" \
        pihole00.local.theama.co A 10.1.0.54 || return 1
    record_check "${action23c_path}_node_b_aaaa" query_exact "$action23c_server" "$action23c_port" \
        pihole00.local.theama.co AAAA fd36:5aa8:6971:1::54 || return 1
    record_check "${action23c_path}_pihole_ptr4" query_exact "$action23c_server" "$action23c_port" \
        10.1.0.55 PTR pihole.local.theama.co. || return 1
    record_check "${action23c_path}_pihole_ptr6" query_exact "$action23c_server" "$action23c_port" \
        fd36:5aa8:6971:1::55 PTR pihole.local.theama.co. || return 1
    record_check "${action23c_path}_node_a_ptr4" query_exact "$action23c_server" "$action23c_port" \
        10.1.0.53 PTR pihole0.local.theama.co. || return 1
    record_check "${action23c_path}_node_a_ptr6" query_exact "$action23c_server" "$action23c_port" \
        fd36:5aa8:6971:1::53 PTR pihole0.local.theama.co. || return 1
    record_check "${action23c_path}_node_b_ptr4" query_exact "$action23c_server" "$action23c_port" \
        10.1.0.54 PTR pihole00.local.theama.co. || return 1
    record_check "${action23c_path}_node_b_ptr6" query_exact "$action23c_server" "$action23c_port" \
        fd36:5aa8:6971:1::54 PTR pihole00.local.theama.co. || return 1
}
wait_for_ptr_passthrough() {
    local action23c_attempt

    for action23c_attempt in 1 2 3 4 5; do
        if query_exact 127.0.0.1 53 10.1.0.55 PTR pihole.local.theama.co.; then
            printf '%s_value_ptr_readiness_attempt=%s\n' "$prefix" "$action23c_attempt"
            return 0
        fi
        sleep 1
    done
    return 1
}
emit_expected_checks() {
    local action23c_expected_command

    for action23c_expected_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action23c_expected_command//-/_}"
    done
    printf '%s\n' \
        uid_root working_directory_root hostname_exact ftl_regular ftl_not_symlink \
        ftl_metadata ftl_old_ptr_exact_once ftl_new_ptr_absent domain_regular \
        domain_not_symlink domain_metadata domain_exact_once domain_misspelling_absent \
        pihole_cli_regular pihole_cli_executable ftl_binary_regular ftl_binary_executable \
        pihole_core_v5 pihole_ftl_v5 unbound_active_before pihole_ftl_active_before \
        caddy_active_before lighttpd_active_before keepalived_active_before \
        vrrp_state_backup_before caddy_ipv4_absent_before caddy_ipv6_absent_before \
        dns_ipv4_absent_before dns_ipv6_absent_before node_b_ipv4_owned_before \
        node_b_ipv6_owned_before backup_absent transaction_absent pihole_version_capture \
        direct_unbound_pihole_a direct_unbound_pihole_aaaa direct_unbound_node_a_a \
        direct_unbound_node_a_aaaa direct_unbound_node_b_a direct_unbound_node_b_aaaa \
        direct_unbound_pihole_ptr4 direct_unbound_pihole_ptr6 direct_unbound_node_a_ptr4 \
        direct_unbound_node_a_ptr6 direct_unbound_node_b_ptr4 direct_unbound_node_b_ptr6 \
        stage_directory_metadata candidate_old_ptr_absent candidate_new_ptr_exact_once candidate_exact_delta \
        backup_directory_created backup_file_created backup_file_hash_exact \
        backup_manifest_created live_candidate_installed live_candidate_hash_exact \
        ftl_candidate_test pihole_restartdns pihole_ftl_active_after_restart \
        ptr_readiness direct_after_pihole_a direct_after_pihole_aaaa \
        direct_after_node_a_a direct_after_node_a_aaaa direct_after_node_b_a \
        direct_after_node_b_aaaa direct_after_pihole_ptr4 direct_after_pihole_ptr6 \
        direct_after_node_a_ptr4 direct_after_node_a_ptr6 direct_after_node_b_ptr4 \
        direct_after_node_b_ptr6 pihole_after_pihole_a pihole_after_pihole_aaaa \
        pihole_after_node_a_a pihole_after_node_a_aaaa pihole_after_node_b_a \
        pihole_after_node_b_aaaa pihole_after_pihole_ptr4 pihole_after_pihole_ptr6 \
        pihole_after_node_a_ptr4 pihole_after_node_a_ptr6 pihole_after_node_b_ptr4 \
        pihole_after_node_b_ptr6 unbound_active_after caddy_active_after \
        lighttpd_active_after keepalived_active_after vrrp_state_backup_after \
        caddy_ipv4_absent_after caddy_ipv6_absent_after dns_ipv4_absent_after \
        dns_ipv6_absent_after node_b_ipv4_owned_after node_b_ipv6_owned_after \
        unbound_pid_stable unbound_restarts_stable caddy_pid_stable \
        caddy_restarts_stable keepalived_pid_stable keepalived_restarts_stable \
        node_a_https caddy_vip_https node_b_https transaction_absent_after \
        final_ftl_hash final_ptr_policy final_domain_policy domain_hash_unchanged
}
emit_contract_transcript() {
    local action23c_contract_label
    local action23c_contract_count=0
    local action23c_before_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local action23c_candidate_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

    while IFS= read -r action23c_contract_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action23c_contract_label"
        action23c_contract_count=$((action23c_contract_count + 1))
    done < <(emit_expected_checks)
    printf '%s_value_before_ftl_sha256=%s\n' "$prefix" "$action23c_before_hash"
    printf '%s_value_candidate_ftl_sha256=%s\n' "$prefix" "$action23c_candidate_hash"
    printf '%s_value_before_domain_sha256=%s\n' "$prefix" "$action23c_before_hash"
    printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
    printf '%s_value_old_ptr_policy=HOSTNAMEFQDN\n' "$prefix"
    printf '%s_value_new_ptr_policy=NONE\n' "$prefix"
    printf '%s_value_domain_policy=local.theama.co\n' "$prefix"
    printf '%s_check_count=%s\n' "$prefix" "$action23c_contract_count"
    printf '%s_failed_check_count=0\n' "$prefix"
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_rollback_invoked=false\n' "$prefix"
    printf '%s_node_a_ssh=false\n' "$prefix"
    printf '%s_unbound_configuration_mutation=false\n' "$prefix"
    printf '%s_domain_configuration_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
}
self_test() {
    local action23c_test_root
    local action23c_test_live
    local action23c_test_candidate
    local action23c_test_reconstructed

    action23c_test_root=$(mktemp -d /tmp/caddy-action23c-self-test.XXXXXX) || return 1
    trap 'rm -rf -- "$action23c_test_root"' RETURN
    action23c_test_live=$action23c_test_root/live.conf
    action23c_test_candidate=$action23c_test_root/candidate.conf
    action23c_test_reconstructed=$action23c_test_root/reconstructed.conf
    printf 'alpha=true\n%s\nomega=true\n' "$old_ptr_line" >"$action23c_test_live"
    before_ftl_sha256=$(file_hash "$action23c_test_live")
    awk -v old="$old_ptr_line" -v new="$new_ptr_line" '
        $0 == old { print new; changed++; next }
        { print }
        END { if (changed != 1) exit 42 }
    ' "$action23c_test_live" >"$action23c_test_candidate" || return 1
    validate_candidate_delta "$action23c_test_candidate" "$action23c_test_reconstructed" || return 1
    [[ "$(emit_expected_checks | wc -l)" -eq "$(emit_expected_checks | LC_ALL=C sort -u | wc -l)" ]] || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
}
rollback() {
    local action23c_original_status=$?
    local action23c_rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        [[ -z "${pihole_version_file:-}" || ! -e "$pihole_version_file" ]] || rm -f -- "$pihole_version_file"
        [[ -z "$stage_dir" || ! -d "$stage_dir" ]] || rm -rf -- "$stage_dir"
        exit "$action23c_original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    set +e
    if [[ "$mutation_started" == true ]]; then
        if ! install -o root -g root -m 0644 "$backup_dir/pihole-FTL.conf.before" "$transaction_file"; then
            action23c_rollback_failed=true
        fi
        if ! mv -fT -- "$transaction_file" "$live_ftl"; then
            action23c_rollback_failed=true
        fi
        if ! timeout 15 "$pihole_cli" restartdns >/dev/null 2>&1; then
            action23c_rollback_failed=true
        fi
        if ! systemctl is-active --quiet pihole-FTL.service; then
            action23c_rollback_failed=true
        fi
        [[ "$(file_hash "$live_ftl" 2>/dev/null)" == "$before_ftl_sha256" ]] ||
            action23c_rollback_failed=true
    fi
    rm -f -- "$transaction_file"
    [[ -z "${pihole_version_file:-}" || ! -e "$pihole_version_file" ]] || rm -f -- "$pihole_version_file"
    [[ -z "$stage_dir" || ! -d "$stage_dir" ]] || rm -rf -- "$stage_dir"
    set -e
    if [[ "$action23c_rollback_failed" == true ]]; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$action23c_original_status"
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

trap rollback EXIT
for action23c_required_command in "${required_commands[@]}"; do
    record_check "command_${action23c_required_command//-/_}_available" \
        command -v "$action23c_required_command" || exit 1
done
record_check uid_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$PWD" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check ftl_regular test -f "$live_ftl" || exit 1
record_check ftl_not_symlink test ! -L "$live_ftl" || exit 1
record_check ftl_metadata test "$(stat -c '%U:%G:%a' "$live_ftl")" = root:root:644 || exit 1
record_check ftl_old_ptr_exact_once test "$(grep -Fxc "$old_ptr_line" "$live_ftl" || true)" -eq 1 || exit 1
record_check ftl_new_ptr_absent test "$(grep -Fxc "$new_ptr_line" "$live_ftl" || true)" -eq 0 || exit 1
record_check domain_regular test -f "$live_domain" || exit 1
record_check domain_not_symlink test ! -L "$live_domain" || exit 1
record_check domain_metadata test "$(stat -c '%U:%G:%a' "$live_domain")" = root:root:644 || exit 1
record_check domain_exact_once test "$(grep -Fxc "$domain_line" "$live_domain" || true)" -eq 1 || exit 1
record_check domain_misspelling_absent test "$(grep -Fxc "$misspelled_domain_line" "$live_domain" || true)" -eq 0 || exit 1
record_check pihole_cli_regular test -f "$pihole_cli" || exit 1
record_check pihole_cli_executable test -x "$pihole_cli" || exit 1
record_check ftl_binary_regular test -f "$ftl_binary" || exit 1
record_check ftl_binary_executable test -x "$ftl_binary" || exit 1
pihole_version_file=$(mktemp /tmp/caddy-action23c-version.XXXXXX)
readonly pihole_version_file
record_check pihole_version_capture capture_pihole_version "$pihole_version_file" || exit 1
pihole_version=$(<"$pihole_version_file")
rm -f -- "$pihole_version_file"
record_check pihole_core_v5 grep -Eq 'Pi-hole version is v5([.]|$)' <<<"$pihole_version" || exit 1
record_check pihole_ftl_v5 grep -Eq 'FTL version is v5([.]|$)' <<<"$pihole_version" || exit 1
record_check unbound_active_before systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_before systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_state_backup_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
record_check node_b_ipv4_owned_before test "$(address_count 4 "$node_b_ipv4_cidr")" -eq 1 || exit 1
record_check node_b_ipv6_owned_before test "$(address_count 6 "$node_b_ipv6_cidr")" -eq 1 || exit 1
record_check backup_absent test ! -e "$backup_dir" || exit 1
record_check transaction_absent test ! -e "$transaction_file" || exit 1
validate_all_records direct_unbound 127.0.0.1 5335 || exit 1

before_ftl_sha256=$(file_hash "$live_ftl")
readonly before_ftl_sha256
before_domain_sha256=$(file_hash "$live_domain")
readonly before_domain_sha256
pre_unbound_pid=$(service_value unbound.service MainPID)
pre_unbound_restarts=$(service_value unbound.service NRestarts)
pre_caddy_pid=$(service_value caddy.service MainPID)
pre_caddy_restarts=$(service_value caddy.service NRestarts)
pre_keepalived_pid=$(service_value keepalived.service MainPID)
pre_keepalived_restarts=$(service_value keepalived.service NRestarts)
readonly pre_unbound_pid pre_unbound_restarts pre_caddy_pid pre_caddy_restarts
readonly pre_keepalived_pid pre_keepalived_restarts
stage_dir=$(mktemp -d /run/caddy-action23c.XXXXXX)
chmod 0700 "$stage_dir"
record_check stage_directory_metadata test "$(stat -c '%U:%G:%a' "$stage_dir")" = root:root:700 || exit 1
candidate=$stage_dir/pihole-FTL.conf
reconstructed=$stage_dir/pihole-FTL.conf.reconstructed
readonly candidate reconstructed
awk -v old="$old_ptr_line" -v new="$new_ptr_line" '
    $0 == old { print new; changed++; next }
    { print }
    END { if (changed != 1) exit 42 }
' "$live_ftl" >"$candidate"
chmod 0600 "$candidate"
candidate_ftl_sha256=$(file_hash "$candidate")
readonly candidate_ftl_sha256
record_check candidate_old_ptr_absent test "$(grep -Fxc "$old_ptr_line" "$candidate" || true)" -eq 0 || exit 1
record_check candidate_new_ptr_exact_once test "$(grep -Fxc "$new_ptr_line" "$candidate" || true)" -eq 1 || exit 1
record_check candidate_exact_delta validate_candidate_delta "$candidate" "$reconstructed" || exit 1

install -d -o root -g root -m 0700 "$backup_dir"
record_check backup_directory_created test "$(stat -c '%U:%G:%a' "$backup_dir")" = root:root:700 || exit 1
install -o root -g root -m 0600 "$live_ftl" "$backup_dir/pihole-FTL.conf.before"
record_check backup_file_created test -f "$backup_dir/pihole-FTL.conf.before" || exit 1
record_check backup_file_hash_exact test "$(file_hash "$backup_dir/pihole-FTL.conf.before")" = "$before_ftl_sha256" || exit 1
{
    printf 'action=23c\n'
    printf 'node=%s\n' "$expected_hostname"
    printf 'before_sha256=%s\n' "$before_ftl_sha256"
    printf 'candidate_sha256=%s\n' "$candidate_ftl_sha256"
    printf 'old_policy=HOSTNAMEFQDN\n'
    printf 'new_policy=NONE\n'
    printf 'domain=local.theama.co\n'
} >"$backup_dir/manifest"
chmod 0600 "$backup_dir/manifest"
record_check backup_manifest_created test "$(stat -c '%U:%G:%a' "$backup_dir/manifest")" = root:root:600 || exit 1

install -o root -g root -m 0644 "$candidate" "$transaction_file"
mutation_started=true
mv -fT -- "$transaction_file" "$live_ftl"
record_check live_candidate_installed test "$(stat -c '%U:%G:%a' "$live_ftl")" = root:root:644 || exit 1
record_check live_candidate_hash_exact test "$(file_hash "$live_ftl")" = "$candidate_ftl_sha256" || exit 1
record_check ftl_candidate_test validate_ftl_configuration || exit 1
record_check pihole_restartdns timeout 15 "$pihole_cli" restartdns || exit 1
record_check pihole_ftl_active_after_restart systemctl is-active --quiet pihole-FTL.service || exit 1
record_check ptr_readiness wait_for_ptr_passthrough || exit 1
validate_all_records direct_after 127.0.0.1 5335 || exit 1
validate_all_records pihole_after 127.0.0.1 53 || exit 1

record_check unbound_active_after systemctl is-active --quiet unbound.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_state_backup_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = BACKUP || exit 1
record_check caddy_ipv4_absent_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0 || exit 1
record_check caddy_ipv6_absent_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0 || exit 1
record_check dns_ipv4_absent_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0 || exit 1
record_check dns_ipv6_absent_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0 || exit 1
record_check node_b_ipv4_owned_after test "$(address_count 4 "$node_b_ipv4_cidr")" -eq 1 || exit 1
record_check node_b_ipv6_owned_after test "$(address_count 6 "$node_b_ipv6_cidr")" -eq 1 || exit 1
record_check unbound_pid_stable test "$(service_value unbound.service MainPID)" = "$pre_unbound_pid" || exit 1
record_check unbound_restarts_stable test "$(service_value unbound.service NRestarts)" = "$pre_unbound_restarts" || exit 1
record_check caddy_pid_stable test "$(service_value caddy.service MainPID)" = "$pre_caddy_pid" || exit 1
record_check caddy_restarts_stable test "$(service_value caddy.service NRestarts)" = "$pre_caddy_restarts" || exit 1
record_check keepalived_pid_stable test "$(service_value keepalived.service MainPID)" = "$pre_keepalived_pid" || exit 1
record_check keepalived_restarts_stable test "$(service_value keepalived.service NRestarts)" = "$pre_keepalived_restarts" || exit 1
record_check node_a_https https_probe "$node_a_fqdn" 10.1.0.53 || exit 1
record_check caddy_vip_https https_probe "$caddy_fqdn" 10.1.0.56 || exit 1
record_check node_b_https https_probe "$node_b_fqdn" 10.1.0.54 || exit 1
record_check transaction_absent_after test ! -e "$transaction_file" || exit 1
record_check final_ftl_hash test "$(file_hash "$live_ftl")" = "$candidate_ftl_sha256" || exit 1
record_check final_ptr_policy test "$(grep -Fxc "$new_ptr_line" "$live_ftl" || true)" -eq 1 || exit 1
record_check final_domain_policy test "$(grep -Fxc "$domain_line" "$live_domain" || true)" -eq 1 || exit 1
record_check domain_hash_unchanged test "$(file_hash "$live_domain")" = "$before_domain_sha256" || exit 1

expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
[[ "${#seen_checks[@]}" -eq "$expected_count" ]] || exit 97
valid_sha256 "$before_ftl_sha256" || exit 1
valid_sha256 "$candidate_ftl_sha256" || exit 1
transaction_complete=true
rm -rf -- "$stage_dir"
stage_dir=
printf '%s_value_before_ftl_sha256=%s\n' "$prefix" "$before_ftl_sha256"
printf '%s_value_candidate_ftl_sha256=%s\n' "$prefix" "$candidate_ftl_sha256"
printf '%s_value_before_domain_sha256=%s\n' "$prefix" "$before_domain_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
printf '%s_value_old_ptr_policy=HOSTNAMEFQDN\n' "$prefix"
printf '%s_value_new_ptr_policy=NONE\n' "$prefix"
printf '%s_value_domain_policy=local.theama.co\n' "$prefix"
printf '%s_check_count=%s\n' "$prefix" "${#seen_checks[@]}"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_rollback_invoked=false\n' "$prefix"
printf '%s_node_a_ssh=false\n' "$prefix"
printf '%s_unbound_configuration_mutation=false\n' "$prefix"
printf '%s_domain_configuration_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
