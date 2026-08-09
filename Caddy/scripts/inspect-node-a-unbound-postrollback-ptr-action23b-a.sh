#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23b_a
readonly expected_hostname=j1-svpihole0
readonly live_root=/etc/unbound/unbound.conf
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly hosts_file=/etc/hosts
readonly hostname_file=/etc/hostname
readonly setup_vars=/etc/pihole/setupVars.conf
readonly ftl_config=/etc/pihole/pihole-FTL.conf
readonly dnsmasq_dir=/etc/dnsmasq.d
readonly primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly restored_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly candidate_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly backup_dir=/var/backups/caddy-ha/action23b-node-a-unbound-a-records
readonly backup_file=$backup_dir/pihole-local-zone.conf.before
readonly backup_manifest=$backup_dir/manifest
readonly transaction_file=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action23b.new
readonly interface=eth0
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly dns_fqdn=pihole.local.theama.co
readonly node_ipv4=10.1.0.53
readonly node_ipv6=fd36:5aa8:6971:1::53
readonly node_ipv4_cidr=10.1.0.53/22
readonly node_ipv6_cidr=fd36:5aa8:6971:1::53/64
readonly node_fqdn=pihole0.local.theama.co
readonly caddy_ipv4=10.1.0.56
readonly admin_fqdn=pihole-admin.local.theama.co
readonly maximum_evidence_bytes=8192
readonly maximum_evidence_lines=100
readonly -a required_commands=(
    awk curl dig find getent grep hostname id ip paste sed sha256sum sort
    stat systemctl timeout unbound-checkconf wc
)
readonly -a query_paths=(direct_unbound local_pihole dns_vip_ipv4 dns_vip_ipv6 node_ipv4 node_ipv6)
readonly -a record_keys=(dns_a dns_aaaa dns_ptr4 dns_ptr6 node_a node_aaaa node_ptr4 node_ptr6)
declare -Ar query_servers=(
    [direct_unbound]=127.0.0.1 [local_pihole]=127.0.0.1
    [dns_vip_ipv4]="$dns_ipv4" [dns_vip_ipv6]="$dns_ipv6"
    [node_ipv4]="$node_ipv4" [node_ipv6]="$node_ipv6"
)
declare -Ar query_ports=(
    [direct_unbound]=5335 [local_pihole]=53 [dns_vip_ipv4]=53
    [dns_vip_ipv6]=53 [node_ipv4]=53 [node_ipv6]=53
)
declare -Ar record_names=(
    [dns_a]="$dns_fqdn" [dns_aaaa]="$dns_fqdn"
    [dns_ptr4]="$dns_ipv4" [dns_ptr6]="$dns_ipv6"
    [node_a]="$node_fqdn" [node_aaaa]="$node_fqdn"
    [node_ptr4]="$node_ipv4" [node_ptr6]="$node_ipv6"
)
declare -Ar record_types=(
    [dns_a]=A [dns_aaaa]=AAAA [dns_ptr4]=PTR [dns_ptr6]=PTR
    [node_a]=A [node_aaaa]=AAAA [node_ptr4]=PTR [node_ptr6]=PTR
)
declare -Ar record_expected=(
    [dns_a]="$dns_ipv4" [dns_aaaa]="$dns_ipv6"
    [dns_ptr4]="${dns_fqdn}." [dns_ptr6]="${dns_fqdn}."
    [node_a]="$node_ipv4" [node_aaaa]="$node_ipv6"
    [node_ptr4]="${node_fqdn}." [node_ptr6]="${node_fqdn}."
)
declare -A seen_checks=()
declare -A observed_answers=()

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
service_value() { systemctl show --property="$2" --value "$1"; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
safe_value() {
    [[ ${#1} -le 1024 ]] || return 1
    [[ "$1" != *$'\n'* ]] || return 1
    [[ "$1" =~ ^[0-9A-Za-z:.,_=/@#-]+$ ]]
}
record_check() {
    local action23ba_check_label=$1

    shift
    if [[ -n "${seen_checks[$action23ba_check_label]+set}" ]]; then
        printf '%s_duplicate_check=%s\n' "$prefix" "$action23ba_check_label" >&2
        return 1
    fi
    seen_checks[$action23ba_check_label]=true
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action23ba_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23ba_check_label" >&2
    printf '%s_failed_check=%s\n' "$prefix" "$action23ba_check_label" >&2
    return 1
}
address_count() {
    local action23ba_family=$1
    local action23ba_cidr=$2

    ip -o "-$action23ba_family" address show dev "$interface" |
        awk -v wanted="$action23ba_cidr" '$4 == wanted { count++ } END { print count + 0 }'
}
validate_unbound() { unbound-checkconf "$live_root" >/dev/null; }
https_probe() {
    curl -kfsS -o /dev/null --connect-timeout 3 --max-time 5 \
        --resolve "${admin_fqdn}:443:${caddy_ipv4}" "https://${admin_fqdn}/"
}
canonical_answer() {
    sed '/^$/d' | LC_ALL=C sort -u | paste -sd, -
}
run_dns_query() (
    trap - ERR

    local action23ba_server=$1
    local action23ba_port=$2
    local action23ba_name=$3
    local action23ba_type=$4

    if [[ "$action23ba_type" == PTR ]]; then
        timeout 4 dig +time=2 +tries=1 +short -p "$action23ba_port" \
            "@$action23ba_server" -x "$action23ba_name" 2>/dev/null
    else
        timeout 4 dig +time=2 +tries=1 +short -p "$action23ba_port" \
            "@$action23ba_server" "$action23ba_name" "$action23ba_type" 2>/dev/null
    fi
)
query_and_record() {
    local action23ba_path=$1
    local action23ba_key=$2
    local action23ba_label="${action23ba_path}_${action23ba_key}"
    local action23ba_output=
    local action23ba_status=0

    if action23ba_output=$(run_dns_query \
        "${query_servers[$action23ba_path]}" "${query_ports[$action23ba_path]}" \
        "${record_names[$action23ba_key]}" "${record_types[$action23ba_key]}"); then
        action23ba_status=0
    else
        action23ba_status=$?
    fi
    action23ba_output=$(printf '%s\n' "$action23ba_output" | canonical_answer)
    action23ba_output=${action23ba_output:-none}
    record_check "${action23ba_label}_command_status" \
        test "$action23ba_status" -eq 0 || return 1
    record_check "${action23ba_label}_answer_safe" \
        safe_value "$action23ba_output" || return 1
    observed_answers["$action23ba_label"]=$action23ba_output
    printf '%s_value_%s_answer=%s\n' "$prefix" "$action23ba_label" "$action23ba_output"
    if [[ "$action23ba_path" == direct_unbound ||
        "${record_types[$action23ba_key]}" != PTR ]]; then
        record_check "${action23ba_label}_answer_exact" test \
            "$action23ba_output" = "${record_expected[$action23ba_key]}" || return 1
    fi
}
hosts_targets() {
    local action23ba_address=$1

    awk -v wanted="$action23ba_address" '
        $1 == wanted {
            for (field = 2; field <= NF; field++) { print $field }
        }
    ' "$hosts_file" | LC_ALL=C sort -u | paste -sd, -
}
source_capture_safe() {
    local action23ba_text=$1

    [[ $(printf '%s' "$action23ba_text" | wc -c) -le "$maximum_evidence_bytes" ]] || return 1
    [[ $(printf '%s\n' "$action23ba_text" | wc -l) -le "$maximum_evidence_lines" ]] || return 1
    ! grep -Eqi 'WEBPASSWORD|PRIVATE KEY|Authorization:|api[_-]?key|token=' \
        <<<"$action23ba_text"
}
emit_source_capture() {
    local action23ba_capture_label=$1
    local action23ba_capture_text=$2
    local action23ba_capture_hash

    action23ba_capture_hash=$(printf '%s' "$action23ba_capture_text" | sha256sum | awk '{ print $1 }')
    record_check "${action23ba_capture_label}_safe" \
        source_capture_safe "$action23ba_capture_text" || return 1
    printf '%s_value_%s_sha256=%s\n' "$prefix" "$action23ba_capture_label" "$action23ba_capture_hash"
    printf '%s_value_%s_begin\n' "$prefix" "$action23ba_capture_label"
    if [[ -n "$action23ba_capture_text" ]]; then
        printf '%s\n' "$action23ba_capture_text"
    else
        printf 'none\n'
    fi
    printf '%s_value_%s_end\n' "$prefix" "$action23ba_capture_label"
}
ptr_classification() {
    local action23ba_key=$1
    local action23ba_hosts=$2
    local action23ba_direct=${observed_answers["direct_unbound_${action23ba_key}"]}
    local action23ba_pihole=${observed_answers["local_pihole_${action23ba_key}"]}
    local action23ba_expected=${record_expected[$action23ba_key]}

    if [[ "$action23ba_direct" != "$action23ba_expected" ]]; then
        printf direct_authority_mismatch
    elif [[ "$action23ba_pihole" == "$action23ba_expected" ]]; then
        printf authoritative_passthrough
    elif [[ ",$action23ba_hosts," == *",${action23ba_pihole%.},"* ]]; then
        printf local_hosts_override
    else
        printf local_pihole_override_unattributed
    fi
}
state_snapshot() {
    printf 'primary=%s\n' "$(file_hash "$live_primary")"
    printf 'local_zone=%s\n' "$(file_hash "$live_local_zone")"
    printf 'hosts=%s\n' "$(file_hash "$hosts_file")"
    printf 'hostname=%s\n' "$(file_hash "$hostname_file")"
    printf 'setup_vars=%s\n' "$(file_hash "$setup_vars")"
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
    printf 'node4=%s\n' "$(address_count 4 "$node_ipv4_cidr")"
    printf 'node6=%s\n' "$(address_count 6 "$node_ipv6_cidr")"
}
emit_expected_checks() {
    local action23ba_expected_command
    local action23ba_expected_path
    local action23ba_expected_key

    for action23ba_expected_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action23ba_expected_command//-/_}"
    done
    printf '%s\n' \
        uid_root working_directory_root hostname_exact live_root_regular \
        live_root_not_symlink primary_regular primary_not_symlink primary_hash_exact \
        local_zone_regular local_zone_not_symlink local_zone_metadata \
        local_zone_hash_restored local_zone_caddy_a_absent unbound_configuration_valid \
        hosts_regular hosts_not_symlink hostname_file_regular hostname_file_not_symlink \
        setup_vars_regular setup_vars_not_symlink pihole_cli_regular \
        pihole_cli_not_symlink pihole_cli_executable pihole_version_status \
        pihole_core_v5 pihole_ftl_v5 \
        backup_directory_metadata backup_file_regular backup_file_not_symlink \
        backup_file_metadata backup_file_hash_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata backup_manifest_line_count \
        backup_manifest_action backup_manifest_node backup_manifest_record_family \
        backup_manifest_before_hash backup_manifest_after_hash transaction_entry_absent \
        transaction_symlink_absent remote_stage_residue_absent unbound_active_before \
        pihole_ftl_active_before caddy_active_before lighttpd_active_before \
        keepalived_active_before vrrp_state_master_before caddy_ipv4_owned_before \
        caddy_ipv6_owned_before dns_ipv4_owned_before dns_ipv6_owned_before \
        node_ipv4_owned_before node_ipv6_owned_before hosts_dns_ipv4_targets_safe \
        hosts_dns_ipv6_targets_safe hosts_node_ipv4_targets_safe \
        hosts_node_ipv6_targets_safe hosts_relevant_safe setup_vars_relevant_safe \
        ftl_config_relevant_safe dnsmasq_relevant_safe
    for action23ba_expected_path in "${query_paths[@]}"; do
        for action23ba_expected_key in "${record_keys[@]}"; do
            printf '%s_%s_command_status\n' "$action23ba_expected_path" "$action23ba_expected_key"
            printf '%s_%s_answer_safe\n' "$action23ba_expected_path" "$action23ba_expected_key"
            if [[ "$action23ba_expected_path" == direct_unbound ||
                "${record_types[$action23ba_expected_key]}" != PTR ]]; then
                printf '%s_%s_answer_exact\n' "$action23ba_expected_path" "$action23ba_expected_key"
            fi
        done
    done
    printf '%s\n' \
        dns_ptr4_pihole_paths_consistent dns_ptr6_pihole_paths_consistent \
        node_ptr4_pihole_paths_consistent node_ptr6_pihole_paths_consistent \
        caddy_vip_https unbound_active_after pihole_ftl_active_after \
        caddy_active_after lighttpd_active_after keepalived_active_after \
        vrrp_state_master_after caddy_ipv4_owned_after caddy_ipv6_owned_after \
        dns_ipv4_owned_after dns_ipv6_owned_after node_ipv4_owned_after \
        node_ipv6_owned_after state_unchanged
}
emit_contract_transcript() {
    local action23ba_contract_label
    local action23ba_contract_count=0
    local action23ba_fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    while IFS= read -r action23ba_contract_label; do
        printf '%s_check_%s=true\n' "$prefix" "$action23ba_contract_label"
        action23ba_contract_count=$((action23ba_contract_count + 1))
    done < <(emit_expected_checks)
    for action23ba_contract_ptr in dns_ptr4 dns_ptr6 node_ptr4 node_ptr6; do
        printf '%s_value_%s_classification=local_hosts_override\n' \
            "$prefix" "$action23ba_contract_ptr"
    done
    printf '%s_value_before_state_sha256=%s\n' "$prefix" "$action23ba_fixture_hash"
    printf '%s_value_after_state_sha256=%s\n' "$prefix" "$action23ba_fixture_hash"
    printf '%s_value_local_zone_sha256=%s\n' "$prefix" "$restored_sha256"
    printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
    printf '%s_check_count=%s\n' "$prefix" "$action23ba_contract_count"
    printf '%s_failed_check_count=0\n' "$prefix"
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_filesystem_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_dns_configuration_mutation=false\n' "$prefix"
    printf '%s_pihole_cache_reset=false\n' "$prefix"
    printf '%s_peer_ssh=false\n' "$prefix"
    printf '%s_remote_complete=true\n' "$prefix"
}
self_test() {
    [[ "$expected_hostname" == j1-svpihole0 ]] || return 1
    [[ "$restored_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]] || return 1
    [[ "$dns_fqdn|$dns_ipv4|$dns_ipv6" == 'pihole.local.theama.co|10.1.0.55|fd36:5aa8:6971:1::55' ]] || return 1
    [[ "$node_fqdn|$node_ipv4|$node_ipv6" == 'pihole0.local.theama.co|10.1.0.53|fd36:5aa8:6971:1::53' ]] || return 1
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

for action23ba_required_command in "${required_commands[@]}"; do
    record_check "command_${action23ba_required_command//-/_}_available" \
        command -v "$action23ba_required_command" || exit 1
done
record_check uid_root test "$(id -u)" -eq 0 || exit 1
record_check working_directory_root test "$PWD" = / || exit 1
record_check hostname_exact test "$(hostname)" = "$expected_hostname" || exit 1
record_check live_root_regular test -f "$live_root" || exit 1
record_check live_root_not_symlink test ! -L "$live_root" || exit 1
record_check primary_regular test -f "$live_primary" || exit 1
record_check primary_not_symlink test ! -L "$live_primary" || exit 1
record_check primary_hash_exact test "$(file_hash "$live_primary")" = "$primary_sha256" || exit 1
record_check local_zone_regular test -f "$live_local_zone" || exit 1
record_check local_zone_not_symlink test ! -L "$live_local_zone" || exit 1
record_check local_zone_metadata test "$(stat -c '%U:%G:%a' "$live_local_zone")" = root:root:644 || exit 1
record_check local_zone_hash_restored test "$(file_hash "$live_local_zone")" = "$restored_sha256" || exit 1
record_check local_zone_caddy_a_absent test \
    "$(grep -Ec '(pihole-admin|proxy)[.]local[.]theama[.]co[.].* IN A ' "$live_local_zone" || true)" -eq 0 || exit 1
record_check unbound_configuration_valid validate_unbound || exit 1
record_check hosts_regular test -f "$hosts_file" || exit 1
record_check hosts_not_symlink test ! -L "$hosts_file" || exit 1
record_check hostname_file_regular test -f "$hostname_file" || exit 1
record_check hostname_file_not_symlink test ! -L "$hostname_file" || exit 1
record_check setup_vars_regular test -f "$setup_vars" || exit 1
record_check setup_vars_not_symlink test ! -L "$setup_vars" || exit 1
record_check pihole_cli_regular test -f /usr/local/bin/pihole || exit 1
record_check pihole_cli_not_symlink test ! -L /usr/local/bin/pihole || exit 1
record_check pihole_cli_executable test -x /usr/local/bin/pihole || exit 1
pihole_version_status=0
if pihole_version=$(/usr/local/bin/pihole -v 2>&1); then
    pihole_version_status=0
else
    pihole_version_status=$?
fi
record_check pihole_version_status test "$pihole_version_status" -eq 0 || exit 1
record_check pihole_core_v5 grep -Eq 'Pi-hole version is v5([.]|$)' <<<"$pihole_version" || exit 1
record_check pihole_ftl_v5 grep -Eq 'FTL version is v5([.]|$)' <<<"$pihole_version" || exit 1
record_check backup_directory_metadata test "$(stat -c '%U:%G:%a' "$backup_dir" 2>/dev/null || true)" = root:root:700 || exit 1
record_check backup_file_regular test -f "$backup_file" || exit 1
record_check backup_file_not_symlink test ! -L "$backup_file" || exit 1
record_check backup_file_metadata test "$(stat -c '%U:%G:%a' "$backup_file")" = root:root:600 || exit 1
record_check backup_file_hash_exact test "$(file_hash "$backup_file")" = "$restored_sha256" || exit 1
record_check backup_manifest_regular test -f "$backup_manifest" || exit 1
record_check backup_manifest_not_symlink test ! -L "$backup_manifest" || exit 1
record_check backup_manifest_metadata test "$(stat -c '%U:%G:%a' "$backup_manifest")" = root:root:600 || exit 1
record_check backup_manifest_line_count test "$(wc -l <"$backup_manifest")" -eq 5 || exit 1
record_check backup_manifest_action grep -Fqx 'action=23b' "$backup_manifest" || exit 1
record_check backup_manifest_node grep -Fqx 'node=j1-svpihole0' "$backup_manifest" || exit 1
record_check backup_manifest_record_family grep -Fqx 'record_family=A' "$backup_manifest" || exit 1
record_check backup_manifest_before_hash grep -Fqx "local_zone_before_sha256=$restored_sha256" "$backup_manifest" || exit 1
record_check backup_manifest_after_hash grep -Fqx "local_zone_after_sha256=$candidate_sha256" "$backup_manifest" || exit 1
record_check transaction_entry_absent test ! -e "$transaction_file" || exit 1
record_check transaction_symlink_absent test ! -L "$transaction_file" || exit 1
record_check remote_stage_residue_absent test -z "$(find /run -mindepth 1 -maxdepth 1 -name 'caddy-action23b.*' -print -quit 2>/dev/null)" || exit 1

before_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly before_state
record_check unbound_active_before systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_before systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_before systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_before systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_before systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_state_master_before test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER || exit 1
record_check caddy_ipv4_owned_before test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || exit 1
record_check caddy_ipv6_owned_before test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || exit 1
record_check dns_ipv4_owned_before test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 || exit 1
record_check dns_ipv6_owned_before test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 || exit 1
record_check node_ipv4_owned_before test "$(address_count 4 "$node_ipv4_cidr")" -eq 1 || exit 1
record_check node_ipv6_owned_before test "$(address_count 6 "$node_ipv6_cidr")" -eq 1 || exit 1

hosts_dns_ipv4=$(hosts_targets "$dns_ipv4")
hosts_dns_ipv4=${hosts_dns_ipv4:-none}
hosts_dns_ipv6=$(hosts_targets "$dns_ipv6")
hosts_dns_ipv6=${hosts_dns_ipv6:-none}
hosts_node_ipv4=$(hosts_targets "$node_ipv4")
hosts_node_ipv4=${hosts_node_ipv4:-none}
hosts_node_ipv6=$(hosts_targets "$node_ipv6")
hosts_node_ipv6=${hosts_node_ipv6:-none}
for action23ba_hosts_key in dns_ipv4 dns_ipv6 node_ipv4 node_ipv6; do
    action23ba_hosts_value_name="hosts_${action23ba_hosts_key}"
    action23ba_hosts_value=${!action23ba_hosts_value_name}
    record_check "hosts_${action23ba_hosts_key}_targets_safe" \
        safe_value "$action23ba_hosts_value" || exit 1
    printf '%s_value_hosts_%s_targets=%s\n' "$prefix" "$action23ba_hosts_key" "$action23ba_hosts_value"
done
hosts_relevant=$(grep -E "(^|[[:space:]])(${dns_ipv4//./[.]}|${node_ipv4//./[.]}|${dns_ipv6}|${node_ipv6})([[:space:]]|$)|pihole(0)?[.]local[.]theama[.]co|j1-svpihole0" "$hosts_file" || true)
setup_vars_relevant=$(grep -E '^(HOSTRECORD|PIHOLE_PTR|LOCAL_IPV4|IPV6_ADDRESS|DNSMASQ_LISTENING|PIHOLE_DOMAIN|DNS_FQDN_REQUIRED|DNS_BOGUS_PRIV)=' "$setup_vars" || true)
ftl_config_relevant=$(grep -E '^(PIHOLE_PTR|LOCAL_IPV4|IPV6_ADDRESS|HOSTRECORD)=' "$ftl_config" 2>/dev/null || true)
dnsmasq_relevant=$(find "$dnsmasq_dir" -maxdepth 1 -type f -name '*.conf' -exec \
    grep -EH '^[[:space:]]*(host-record|ptr-record|interface|listen-address)=|^[[:space:]]*server=127[.]0[.]0[.]1#5335' {} + 2>/dev/null || true)
emit_source_capture hosts_relevant "$hosts_relevant" || exit 1
emit_source_capture setup_vars_relevant "$setup_vars_relevant" || exit 1
emit_source_capture ftl_config_relevant "$ftl_config_relevant" || exit 1
emit_source_capture dnsmasq_relevant "$dnsmasq_relevant" || exit 1

for action23ba_query_path in "${query_paths[@]}"; do
    for action23ba_record_key in "${record_keys[@]}"; do
        query_and_record "$action23ba_query_path" "$action23ba_record_key" || exit 1
    done
done
for action23ba_ptr_key in dns_ptr4 dns_ptr6 node_ptr4 node_ptr6; do
    action23ba_ptr_reference=${observed_answers["local_pihole_${action23ba_ptr_key}"]}
    action23ba_ptr_consistent=true
    for action23ba_ptr_path in dns_vip_ipv4 dns_vip_ipv6 node_ipv4 node_ipv6; do
        if [[ "${observed_answers["${action23ba_ptr_path}_${action23ba_ptr_key}"]}" != "$action23ba_ptr_reference" ]]; then
            action23ba_ptr_consistent=false
        fi
    done
    record_check "${action23ba_ptr_key}_pihole_paths_consistent" \
        test "$action23ba_ptr_consistent" = true || exit 1
done
printf '%s_value_dns_ptr4_classification=%s\n' "$prefix" \
    "$(ptr_classification dns_ptr4 "$hosts_dns_ipv4")"
printf '%s_value_dns_ptr6_classification=%s\n' "$prefix" \
    "$(ptr_classification dns_ptr6 "$hosts_dns_ipv6")"
printf '%s_value_node_ptr4_classification=%s\n' "$prefix" \
    "$(ptr_classification node_ptr4 "$hosts_node_ipv4")"
printf '%s_value_node_ptr6_classification=%s\n' "$prefix" \
    "$(ptr_classification node_ptr6 "$hosts_node_ipv6")"
record_check caddy_vip_https https_probe || exit 1
record_check unbound_active_after systemctl is-active --quiet unbound.service || exit 1
record_check pihole_ftl_active_after systemctl is-active --quiet pihole-FTL.service || exit 1
record_check caddy_active_after systemctl is-active --quiet caddy.service || exit 1
record_check lighttpd_active_after systemctl is-active --quiet lighttpd.service || exit 1
record_check keepalived_active_after systemctl is-active --quiet keepalived.service || exit 1
record_check vrrp_state_master_after test "$(sed -n '1p' /run/caddy-ha/vrrp-state 2>/dev/null || true)" = MASTER || exit 1
record_check caddy_ipv4_owned_after test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 || exit 1
record_check caddy_ipv6_owned_after test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 || exit 1
record_check dns_ipv4_owned_after test "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 || exit 1
record_check dns_ipv6_owned_after test "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 || exit 1
record_check node_ipv4_owned_after test "$(address_count 4 "$node_ipv4_cidr")" -eq 1 || exit 1
record_check node_ipv6_owned_after test "$(address_count 6 "$node_ipv6_cidr")" -eq 1 || exit 1
after_state=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly after_state
record_check state_unchanged test "$before_state" = "$after_state" || exit 1
expected_count=$(emit_expected_checks | wc -l)
readonly expected_count
[[ ${#seen_checks[@]} -eq "$expected_count" ]] || exit 97
valid_sha256 "$before_state" || exit 1
valid_sha256 "$after_state" || exit 1
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state"
printf '%s_value_local_zone_sha256=%s\n' "$prefix" "$restored_sha256"
printf '%s_value_backup_path=%s\n' "$prefix" "$backup_dir"
printf '%s_check_count=%s\n' "$prefix" "${#seen_checks[@]}"
printf '%s_failed_check_count=0\n' "$prefix"
printf '%s_first_failure=none\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_configuration_mutation=false\n' "$prefix"
printf '%s_pihole_cache_reset=false\n' "$prefix"
printf '%s_peer_ssh=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
