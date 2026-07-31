#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_root=/etc/unbound/unbound.conf
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly live_hosts=/etc/hosts
readonly backup_dir=/var/backups/caddy-ha/action17n-node-a-dns-nss
readonly backup_local_zone="$backup_dir/pihole-local-zone.conf.before"
readonly backup_hosts="$backup_dir/hosts.before"
readonly backup_manifest="$backup_dir/manifest"
readonly local_zone_transaction=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action17n.new
readonly hosts_transaction=/etc/.hosts.action17n.new
readonly expected_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_live_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_candidate_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly peer_ipv6=fd36:5aa8:6971:1::54
readonly peer_fqdn=pihole00.local.theama.co
readonly marker_begin='# BEGIN CADDY HA SYNC PEER'
readonly marker_end='# END CADDY HA SYNC PEER'
readonly expected_assertion_count=87

assertion_count=0
failed_assertion_count=0
first_failure=none
declare -A emitted_assertion_labels=()

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_assertion() {
    local record_label=$1
    local record_status=$2
    local record_observed=${3:-unavailable}

    if [[ ! "$record_label" =~ ^[a-z0-9_]+$ ]] ||
        [[ -n "${emitted_assertion_labels[$record_label]+present}" ]]; then
        printf 'action_17n_a_assertion_contract_failure=true\n' >&2
        exit 97
    fi
    emitted_assertion_labels[$record_label]=1
    ((assertion_count += 1))
    printf 'action_17n_a_assertion_%s=%s\n' "$record_label" "$record_status"
    if [[ "$record_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$record_label
        fi
        printf 'action_17n_a_observed_%s=%s\n' \
            "$record_label" "$record_observed"
    fi
}

assert_equal() {
    local equality_label=$1
    local equality_observed=$2
    local equality_expected=$3

    if [[ "$equality_observed" == "$equality_expected" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$equality_observed"
    fi
}

assert_file_shape() {
    local file_shape_label=$1
    local file_shape_path=$2

    if [[ -f "$file_shape_path" ]]; then
        record_assertion "${file_shape_label}_regular" true
    else
        record_assertion "${file_shape_label}_regular" false \
            "$(stat -c %F "$file_shape_path" 2>/dev/null || printf absent)"
    fi
    if [[ ! -L "$file_shape_path" ]]; then
        record_assertion "${file_shape_label}_not_symlink" true
    else
        record_assertion "${file_shape_label}_not_symlink" false symlink
    fi
}

assert_path_absent() {
    local path_absent_label=$1
    local path_absent_path=$2

    if [[ ! -e "$path_absent_path" ]]; then
        record_assertion "${path_absent_label}_entry_absent" true
    else
        record_assertion "${path_absent_label}_entry_absent" false \
            "$(stat -c %F "$path_absent_path" 2>/dev/null || printf present)"
    fi
    if [[ ! -L "$path_absent_path" ]]; then
        record_assertion "${path_absent_label}_symlink_absent" true
    else
        record_assertion "${path_absent_label}_symlink_absent" false symlink
    fi
}

manifest_value() {
    local manifest_key=$1

    awk -F= -v key="$manifest_key" \
        '$1 == key { print substr($0, index($0, "=") + 1) }' \
        "$backup_manifest" 2>/dev/null
}

dns_probe() {
    local probe_label=$1
    local probe_server=$2
    local probe_port=$3
    local probe_name=$4
    local probe_type=$5
    local probe_status=0
    local probe_answer
    local probe_safe_answer

    probe_answer=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$probe_server" -p "$probe_port" "$probe_name" "$probe_type" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u |
            awk 'BEGIN { separator = "" }
                NF { printf "%s%s", separator, $0; separator = "," }
                END { print "" }'
    ) || probe_status=$?
    assert_equal "${probe_label}_status" "$probe_status" 0
    probe_safe_answer=${probe_answer:-none}
    if [[ "$probe_safe_answer" =~ ^[0-9A-Za-z:._,-]+$ ]]; then
        record_assertion "${probe_label}_answer_safe" true
        printf 'action_17n_a_value_%s_answer=%s\n' \
            "$probe_label" "$probe_safe_answer"
    else
        record_assertion "${probe_label}_answer_safe" false unsafe
        printf 'action_17n_a_value_%s_answer=unsafe\n' "$probe_label"
    fi
}

reverse_dns_probe() {
    local reverse_probe_label=$1
    local reverse_probe_server=$2
    local reverse_probe_port=$3
    local reverse_probe_address=$4
    local reverse_probe_status=0
    local reverse_probe_answer
    local reverse_probe_safe_answer

    reverse_probe_answer=$(
        timeout 5 dig +time=2 +tries=1 +short \
            "@$reverse_probe_server" -p "$reverse_probe_port" \
            -x "$reverse_probe_address" |
            sed 's/[.]$//' |
            LC_ALL=C sort -u |
            awk 'BEGIN { separator = "" }
                NF { printf "%s%s", separator, $0; separator = "," }
                END { print "" }'
    ) || reverse_probe_status=$?
    assert_equal "${reverse_probe_label}_status" "$reverse_probe_status" 0
    reverse_probe_safe_answer=${reverse_probe_answer:-none}
    if [[ "$reverse_probe_safe_answer" =~ ^[0-9A-Za-z:._,-]+$ ]]; then
        record_assertion "${reverse_probe_label}_answer_safe" true
        printf 'action_17n_a_value_%s_answer=%s\n' \
            "$reverse_probe_label" "$reverse_probe_safe_answer"
    else
        record_assertion "${reverse_probe_label}_answer_safe" false unsafe
        printf 'action_17n_a_value_%s_answer=unsafe\n' "$reverse_probe_label"
    fi
}

state_snapshot() {
    printf '%s\n' \
        "root=$(file_hash "$live_root" 2>/dev/null)" \
        "primary=$(file_hash "$live_primary" 2>/dev/null)" \
        "local_zone=$(file_hash "$live_local_zone" 2>/dev/null)" \
        "hosts=$(file_hash "$live_hosts" 2>/dev/null)" \
        "backup_local_zone=$(file_hash "$backup_local_zone" 2>/dev/null)" \
        "backup_hosts=$(file_hash "$backup_hosts" 2>/dev/null)" \
        "backup_manifest=$(file_hash "$backup_manifest" 2>/dev/null)" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" \
        "local_zone_transaction=$(stat -c %F "$local_zone_transaction" 2>/dev/null || printf absent)" \
        "hosts_transaction=$(stat -c %F "$hosts_transaction" 2>/dev/null || printf absent)"
}

snapshot_value() {
    local snapshot_key=$1
    local snapshot_text=$2

    awk -F= -v key="$snapshot_key" \
        '$1 == key { print substr($0, index($0, "=") + 1) }' \
        <<<"$snapshot_text"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_assertion_count" -eq 87 ]]
    [[ "$expected_hostname" == j1-svpihole0 ]]
    [[ "$peer_fqdn" == pihole00.local.theama.co ]]
    printf 'action_17n_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17n_a_remote_reached=true\n'
for required_command in \
    awk cut dig find grep hostname id sed sha256sum sort stat systemctl \
    timeout wc; do
    command_label=${required_command//-/_}
    if command -v "$required_command" >/dev/null; then
        record_assertion "command_${command_label}_available" true
    else
        record_assertion "command_${command_label}_available" false missing
    fi
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
assert_file_shape live_root "$live_root"
assert_equal live_root_hash "$(file_hash "$live_root" 2>/dev/null)" \
    "$expected_root_sha256"
assert_file_shape live_primary "$live_primary"
assert_equal live_primary_hash "$(file_hash "$live_primary" 2>/dev/null)" \
    "$expected_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a' "$live_primary" 2>/dev/null)" root:root:644
assert_file_shape live_local_zone "$live_local_zone"
assert_equal live_local_zone_hash \
    "$(file_hash "$live_local_zone" 2>/dev/null)" \
    "$expected_live_local_zone_sha256"
assert_equal live_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone" 2>/dev/null)" root:root:644
assert_file_shape live_hosts "$live_hosts"
assert_equal live_hosts_metadata \
    "$(stat -c '%U:%G:%a' "$live_hosts" 2>/dev/null)" root:root:644

if [[ -d "$backup_dir" ]]; then
    record_assertion backup_directory true
else
    record_assertion backup_directory false absent
fi
if [[ ! -L "$backup_dir" ]]; then
    record_assertion backup_directory_not_symlink true
else
    record_assertion backup_directory_not_symlink false symlink
fi
assert_equal backup_directory_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir" 2>/dev/null)" root:root:700
assert_equal backup_entry_count \
    "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' \
        2>/dev/null | wc -l)" 3
assert_file_shape backup_local_zone "$backup_local_zone"
assert_equal backup_local_zone_hash \
    "$(file_hash "$backup_local_zone" 2>/dev/null)" \
    "$expected_live_local_zone_sha256"
assert_equal backup_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$backup_local_zone" 2>/dev/null)" root:root:600
assert_file_shape backup_hosts "$backup_hosts"
assert_equal backup_hosts_metadata \
    "$(stat -c '%U:%G:%a' "$backup_hosts" 2>/dev/null)" root:root:644
assert_file_shape backup_manifest "$backup_manifest"
assert_equal backup_manifest_metadata \
    "$(stat -c '%U:%G:%a' "$backup_manifest" 2>/dev/null)" root:root:600
assert_equal backup_manifest_action "$(manifest_value action)" 17n
assert_equal backup_manifest_node "$(manifest_value node)" "$expected_hostname"
assert_equal backup_manifest_before_hash \
    "$(manifest_value local_zone_before_sha256)" \
    "$expected_live_local_zone_sha256"
assert_equal backup_manifest_after_hash \
    "$(manifest_value local_zone_after_sha256)" \
    "$expected_candidate_local_zone_sha256"
assert_equal backup_manifest_hosts_hash_matches_backup \
    "$(manifest_value hosts_before_sha256)" \
    "$(file_hash "$backup_hosts" 2>/dev/null)"
assert_equal live_hosts_hash_matches_backup \
    "$(file_hash "$live_hosts" 2>/dev/null)" \
    "$(file_hash "$backup_hosts" 2>/dev/null)"

assert_path_absent local_zone_transaction "$local_zone_transaction"
assert_path_absent hosts_transaction "$hosts_transaction"
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
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

before_state_text=$(state_snapshot)
readonly before_state_text
before_state=$(printf '%s\n' "$before_state_text" | sha256sum | awk '{ print $1 }')
readonly before_state

# BEGIN LABELED DNS READINESS
dns_probe direct_unbound_peer_aaaa \
    127.0.0.1 5335 pihole00.local.theama.co AAAA
dns_probe direct_unbound_node_a_aaaa \
    127.0.0.1 5335 pihole0.local.theama.co AAAA
reverse_dns_probe direct_unbound_peer_ptr6 \
    127.0.0.1 5335 "$peer_ipv6"
dns_probe local_pihole_peer_aaaa \
    127.0.0.1 53 pihole00.local.theama.co AAAA
dns_probe local_pihole_node_a_aaaa \
    127.0.0.1 53 pihole0.local.theama.co AAAA
reverse_dns_probe local_pihole_peer_ptr6 \
    127.0.0.1 53 "$peer_ipv6"
# END LABELED DNS READINESS

after_state_text=$(state_snapshot)
readonly after_state_text
after_state=$(printf '%s\n' "$after_state_text" | sha256sum | awk '{ print $1 }')
readonly after_state
for state_component in \
    root primary local_zone hosts backup_local_zone backup_hosts \
    backup_manifest unbound unbound_pid unbound_restarts ftl ftl_pid \
    ftl_restarts local_zone_transaction hosts_transaction; do
    assert_equal "state_${state_component}_unchanged" \
        "$(snapshot_value "$state_component" "$after_state_text")" \
        "$(snapshot_value "$state_component" "$before_state_text")"
done

printf 'action_17n_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17n_a_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17n_a_first_failure=%s\n' "$first_failure"
printf 'action_17n_a_before_state_sha256=%s\n' "$before_state"
printf 'action_17n_a_after_state_sha256=%s\n' "$after_state"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=true\n'
printf 'peer_connections=false\n'
printf 'synchronization_commands_executed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'nss_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

if [[ "$assertion_count" -ne "$expected_assertion_count" ]]; then
    printf 'action_17n_a_assertion_contract_failure=true\n' >&2
    exit 97
fi
if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17n_a_conclusion=post_rollback_state_verified\n'
    printf 'action_17n_a_remote_complete=true\n'
    exit 0
fi
printf 'action_17n_a_conclusion=post_rollback_state_mismatch\n'
printf 'action_17n_a_remote_complete=true\n'
exit 1
