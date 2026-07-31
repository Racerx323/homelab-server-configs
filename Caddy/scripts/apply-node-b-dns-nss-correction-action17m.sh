#!/usr/bin/env bash

set -Eeu -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole00
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly live_hosts=/etc/hosts
readonly backup_dir=/var/backups/caddy-ha/action17m-node-b-dns-nss
readonly local_zone_transaction=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action17m.new
readonly hosts_transaction=/etc/.hosts.action17m.new
readonly accepted_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly accepted_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly candidate_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly peer_ipv4=10.1.0.53
readonly peer_ipv6=fd36:5aa8:6971:1::53
readonly peer_fqdn=pihole0.local.theama.co
readonly marker_begin='# BEGIN CADDY HA SYNC PEER'
readonly marker_end='# END CADDY HA SYNC PEER'

mutation_started=false
transaction_complete=false
pre_unbound_pid=
pre_unbound_restarts=
pre_ftl_pid=
pre_ftl_restarts=
pre_hosts_meta=
current_boundary=initialization

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

pass_check() {
    local check_label=$1

    printf 'action_17m_check_%s=true\n' "$check_label"
}

fail_check() {
    local check_label=$1
    local observed_value=${2:-unavailable}

    printf 'action_17m_check_%s=false\n' "$check_label" >&2
    printf 'action_17m_failed_check=%s\n' "$check_label" >&2
    printf 'action_17m_failed_observed=%s\n' "$observed_value" >&2
    return 1
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        pass_check "$equality_label"
    else
        fail_check "$equality_label" "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        pass_check "$regular_label"
    else
        fail_check "$regular_label" \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        pass_check "$absent_label"
    else
        fail_check "$absent_label" \
            "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

run_check() {
    local operation_label=$1

    shift
    if "$@"; then
        pass_check "$operation_label"
    else
        fail_check "$operation_label"
    fi
}

set_boundary() {
    current_boundary=$1
    printf 'action_17m_boundary=%s\n' "$current_boundary"
}

service_pid() {
    systemctl show --property=MainPID --value "$1"
}

service_restarts() {
    systemctl show --property=NRestarts --value "$1"
}

query_exact() {
    local query_server=$1
    local query_name=$2
    local query_type=$3
    local expected_answer=$4
    local query_output

    query_output=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$query_server" "$query_name" "$query_type"
    )
    [[ "$(printf '%s\n' "$query_output" | sed '/^$/d' | sort -u)" == "$expected_answer" ]]
}

query_reverse_exact() {
    local query_server=$1
    local query_address=$2
    local expected_answer=$3
    local query_output

    query_output=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$query_server" -x "$query_address"
    )
    [[ "$(printf '%s\n' "$query_output" | sed '/^$/d' | sort -u)" == "$expected_answer" ]]
}

validate_candidate_records() {
    local record_label
    local record_text
    local -a record_labels=(
        pihole_vip_aaaa
        node_a_aaaa
        node_b_aaaa
        pihole_vip_ptr6
        node_a_ptr6
        node_b_ptr6
    )
    local -a record_texts=(
        '    local-data: "pihole.local.theama.co. IN AAAA fd36:5aa8:6971:1::55"'
        '    local-data: "pihole0.local.theama.co. IN AAAA fd36:5aa8:6971:1::53"'
        '    local-data: "pihole00.local.theama.co. IN AAAA fd36:5aa8:6971:1::54"'
        '    local-data-ptr: "fd36:5aa8:6971:1::55 pihole.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::53 pihole0.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::54 pihole00.local.theama.co."'
    )
    local record_index

    for record_index in "${!record_labels[@]}"; do
        record_label=${record_labels[$record_index]}
        record_text=${record_texts[$record_index]}
        assert_equal "candidate_${record_label}_exact_once" \
            "$(grep -Fxc "$record_text" "$candidate_local_zone" || true)" 1
        assert_equal "live_${record_label}_absent" \
            "$(grep -Fxc "$record_text" "$live_local_zone" || true)" 0
    done
    assert_equal candidate_homeassistant_a_absent \
        "$(grep -Fc 'homeassistant.local.theama.co. IN A ' \
            "$candidate_local_zone" || true)" 0
    assert_equal candidate_homeassistant_ptr_absent \
        "$(grep -Fc 'homeassistant.local.theama.co."' \
            "$candidate_local_zone" || true)" 0
    assert_equal candidate_caddy_records_absent \
        "$(grep -Ec 'proxy[.]local[.]theama[.]co|pihole-admin[.]local[.]theama[.]co|::56|10[.]1[.]0[.]56' \
            "$candidate_local_zone" || true)" 0
}

validate_shadow_parser() {
    local shadow_parser_path=$1

    {
        printf 'include-toplevel: "%s"\n' "$live_primary"
        printf 'include-toplevel: "%s"\n' "$candidate_local_zone"
    } >"$shadow_parser_path"
    unbound-checkconf "$shadow_parser_path" >/dev/null
}

rollback() {
    local original_status=$?
    local rollback_failed=false
    local rollback_status=0

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    set +e
    printf 'action_17m_rollback_started=true\n' >&2
    if [[ "$mutation_started" == true ]]; then
        install -o root -g root -m 0644 \
            "$backup_dir/pihole-local-zone.conf.before" "$live_local_zone"
        rollback_status=$?
        printf 'action_17m_rollback_local_zone_restore_status=%s\n' \
            "$rollback_status" >&2
        [[ "$rollback_status" -eq 0 ]] || rollback_failed=true

        cp -a -- "$backup_dir/hosts.before" "$live_hosts"
        rollback_status=$?
        printf 'action_17m_rollback_hosts_restore_status=%s\n' \
            "$rollback_status" >&2
        [[ "$rollback_status" -eq 0 ]] || rollback_failed=true

        unbound-control reload >/dev/null 2>&1
        rollback_status=$?
        printf 'action_17m_rollback_unbound_reload_status=%s\n' \
            "$rollback_status" >&2
        [[ "$rollback_status" -eq 0 ]] || rollback_failed=true
    fi

    rm -f -- "$local_zone_transaction" "$hosts_transaction"
    rollback_status=$?
    printf 'action_17m_rollback_transaction_cleanup_status=%s\n' \
        "$rollback_status" >&2
    [[ "$rollback_status" -eq 0 ]] || rollback_failed=true

    if [[ "$mutation_started" == true ]]; then
        [[ "$(file_hash "$live_local_zone" 2>/dev/null)" == "$accepted_local_zone_sha256" ]] || rollback_failed=true
        [[ "$(stat -c '%U:%G:%a' "$live_hosts" 2>/dev/null)" == "$pre_hosts_meta" ]] || rollback_failed=true
        [[ "$(service_pid unbound.service)" == "$pre_unbound_pid" ]] ||
            rollback_failed=true
        [[ "$(service_restarts unbound.service)" == "$pre_unbound_restarts" ]] ||
            rollback_failed=true
        [[ "$(service_pid pihole-FTL.service)" == "$pre_ftl_pid" ]] ||
            rollback_failed=true
        [[ "$(service_restarts pihole-FTL.service)" == "$pre_ftl_restarts" ]] ||
            rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17m_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17m_rollback_complete=true\n' >&2
    exit "$original_status"
}

unhandled_error() {
    local error_status=$?
    local error_line=$1
    local error_command=$2

    printf 'action_17m_unhandled_error=true\n' >&2
    printf 'action_17m_unhandled_status=%s\n' "$error_status" >&2
    printf 'action_17m_unhandled_boundary=%s\n' "$current_boundary" >&2
    printf 'action_17m_unhandled_line=%s\n' "$error_line" >&2
    printf 'action_17m_unhandled_command_sha256=%s\n' \
        "$(printf '%s' "$error_command" | sha256sum | awk '{ print $1 }')" >&2
    return "$error_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_hostname" == j1-svpihole00 ]]
    [[ "$candidate_local_zone_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]]
    printf 'action_17m_driver_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --candidate || $# -ne 2 ]]; then
    printf 'Usage: %s --candidate /run/caddy-action17m.*/pihole-local-zone.conf\n' \
        "${0##*/}" >&2
    exit 2
fi

candidate_local_zone=$2
readonly candidate_local_zone
candidate_parent=$(dirname -- "$candidate_local_zone")
readonly candidate_parent
parser_root="$candidate_parent/unbound-action17m.conf"
readonly parser_root

trap 'unhandled_error "$LINENO" "$BASH_COMMAND"' ERR
trap rollback EXIT

printf 'action_17m_remote_reached=true\n'
set_boundary required_command_preflight
for required_command in \
    awk chmod chown cp dig dirname getent grep hostname id install mktemp mv \
    rm runuser sed sha256sum sleep sort stat systemctl timeout \
    unbound-checkconf unbound-control; do
    if command -v "$required_command" >/dev/null; then
        pass_check "command_${required_command//-/_}_available"
    else
        fail_check "command_${required_command//-/_}_available" missing
    fi
done

set_boundary identity_and_live_state_preflight
assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
assert_regular_file primary_regular "$live_primary"
assert_equal primary_hash "$(file_hash "$live_primary")" \
    "$accepted_primary_sha256"
assert_regular_file live_local_zone_regular "$live_local_zone"
assert_equal live_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$accepted_local_zone_sha256"
assert_regular_file live_hosts_regular "$live_hosts"
assert_regular_file candidate_regular "$candidate_local_zone"
assert_equal candidate_parent_pattern \
    "$(if [[ "$candidate_parent" =~ ^/run/caddy-action17m\.[A-Za-z0-9]+$ ]]; then
        printf valid
    else
        printf invalid
    fi)" valid
assert_equal candidate_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_local_zone")" root:root:600
assert_equal candidate_hash "$(file_hash "$candidate_local_zone")" \
    "$candidate_local_zone_sha256"
assert_absent backup_absent "$backup_dir"
assert_absent local_zone_transaction_absent "$local_zone_transaction"
assert_absent hosts_transaction_absent "$hosts_transaction"
assert_equal hosts_marker_begin_absent \
    "$(grep -Fxc "$marker_begin" "$live_hosts" || true)" 0
assert_equal hosts_marker_end_absent \
    "$(grep -Fxc "$marker_end" "$live_hosts" || true)" 0
assert_equal peer_fqdn_hosts_absent \
    "$(awk -v name="$peer_fqdn" '
        /^[[:space:]]*#/ { next }
        {
            for (field = 2; field <= NF; field++) {
                if ($field == name) {
                    found++
                }
            }
        }
        END { print found + 0 }
    ' "$live_hosts")" 0
run_check unbound_active systemctl is-active --quiet unbound.service
run_check pihole_ftl_active systemctl is-active --quiet pihole-FTL.service
set_boundary candidate_record_preflight
validate_candidate_records
set_boundary candidate_parser_preflight
run_check candidate_parser validate_shadow_parser "$parser_root"
rm -f -- "$parser_root"
pass_check parser_root_cleanup

set_boundary service_continuity_capture
pre_unbound_pid=$(service_pid unbound.service)
pre_unbound_restarts=$(service_restarts unbound.service)
pre_ftl_pid=$(service_pid pihole-FTL.service)
pre_ftl_restarts=$(service_restarts pihole-FTL.service)
pre_hosts_meta=$(stat -c '%U:%G:%a' "$live_hosts")

set_boundary rollback_backup_creation
install -d -o root -g root -m 0700 "$backup_dir"
install -o root -g root -m 0600 \
    "$live_local_zone" "$backup_dir/pihole-local-zone.conf.before"
cp -a -- "$live_hosts" "$backup_dir/hosts.before"
{
    printf 'action=17m\n'
    printf 'node=%s\n' "$expected_hostname"
    printf 'local_zone_before_sha256=%s\n' "$accepted_local_zone_sha256"
    printf 'local_zone_after_sha256=%s\n' "$candidate_local_zone_sha256"
    printf 'hosts_before_sha256=%s\n' "$(file_hash "$live_hosts")"
} >"$backup_dir/manifest"
chmod 0600 "$backup_dir/manifest"
pass_check backup_created

set_boundary transaction_file_preparation
install -o root -g root -m 0644 \
    "$candidate_local_zone" "$local_zone_transaction"
cp -a -- "$live_hosts" "$hosts_transaction"
{
    printf '\n%s\n' "$marker_begin"
    printf '%s %s\n' "$peer_ipv4" "$peer_fqdn"
    printf '%s %s\n' "$peer_ipv6" "$peer_fqdn"
    printf '%s\n' "$marker_end"
} >>"$hosts_transaction"
chown root:root "$hosts_transaction"
chmod "$(stat -c %a "$live_hosts")" "$hosts_transaction"
assert_equal transaction_local_zone_hash \
    "$(file_hash "$local_zone_transaction")" "$candidate_local_zone_sha256"
assert_equal transaction_hosts_peer_ipv4_exact \
    "$(grep -Fxc "$peer_ipv4 $peer_fqdn" "$hosts_transaction")" 1
assert_equal transaction_hosts_peer_ipv6_exact \
    "$(grep -Fxc "$peer_ipv6 $peer_fqdn" "$hosts_transaction")" 1

set_boundary atomic_live_file_switch
mutation_started=true
mv -f -- "$local_zone_transaction" "$live_local_zone"
mv -f -- "$hosts_transaction" "$live_hosts"
pass_check atomic_file_switch_complete

set_boundary unbound_reload
run_check unbound_reload unbound-control reload

set_boundary bounded_dns_readiness
readiness_passed=false
for readiness_iteration in {1..20}; do
    if query_exact 127.0.0.1 pihole0.local.theama.co AAAA "$peer_ipv6" &&
        query_exact 127.0.0.1 pihole00.local.theama.co AAAA \
            fd36:5aa8:6971:1::54 &&
        query_reverse_exact 127.0.0.1 "$peer_ipv6" \
            pihole0.local.theama.co.; then
        readiness_passed=true
        printf 'action_17m_readiness_iteration=%s\n' "$readiness_iteration"
        break
    fi
    sleep 1
done
assert_equal bounded_dns_readiness "$readiness_passed" true
set_boundary nss_peer_resolution
assert_equal root_peer_ipv4 \
    "$(getent ahostsv4 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal root_peer_ipv6 \
    "$(getent ahostsv6 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv6"
assert_equal caddy_sync_peer_ipv4 \
    "$(runuser -u caddy-sync -- getent ahostsv4 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal caddy_sync_peer_ipv6 \
    "$(runuser -u caddy-sync -- getent ahostsv6 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv6"
set_boundary service_continuity_validation
assert_equal unbound_pid_preserved "$(service_pid unbound.service)" \
    "$pre_unbound_pid"
assert_equal unbound_restarts_preserved \
    "$(service_restarts unbound.service)" "$pre_unbound_restarts"
assert_equal pihole_ftl_pid_preserved "$(service_pid pihole-FTL.service)" \
    "$pre_ftl_pid"
assert_equal pihole_ftl_restarts_preserved \
    "$(service_restarts pihole-FTL.service)" "$pre_ftl_restarts"
set_boundary final_file_validation
assert_equal final_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$candidate_local_zone_sha256"
assert_equal final_hosts_metadata "$(stat -c '%U:%G:%a' "$live_hosts")" \
    "$pre_hosts_meta"
assert_absent final_local_zone_transaction_absent "$local_zone_transaction"
assert_absent final_hosts_transaction_absent "$hosts_transaction"

set_boundary acceptance
transaction_complete=true
printf 'action_17m_backup_dir=%s\n' "$backup_dir"
printf 'action_17m_local_zone_sha256=%s\n' "$candidate_local_zone_sha256"
printf 'action_17m_dns_configuration_mutation=true\n'
printf 'action_17m_nss_configuration_mutation=true\n'
printf 'action_17m_resolv_conf_mutation=false\n'
printf 'action_17m_peer_connections=false\n'
printf 'action_17m_synchronization_executed=false\n'
printf 'action_17m_service_restart=false\n'
printf 'action_17m_acceptance=true\n'
