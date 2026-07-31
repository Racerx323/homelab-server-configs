#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole00
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"
readonly legacy_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly primary_stage=/var/tmp/caddy-unbound-node-b-action17e-primary
readonly local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly backup_dir=/var/backups/caddy-ha/action17g-node-b-unbound-two-file
readonly transaction_primary="$live_conf_dir/.pihole.conf.action17g.new"
readonly transaction_local_zone="$live_conf_dir/.pihole-local-zone.conf.action17g.new"
readonly rollback_primary="$live_conf_dir/.pihole.conf.action17g.before"
readonly expected_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly expected_legacy_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly expected_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly expected_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_primary_meta_sha256=14731d6ae7e968f4752117e53c972bb86ab22bb4da50f1615a5f780049219b56
readonly expected_local_zone_meta_sha256=7f365675e5f9996f2c53647dc4fe98f5e27c7d10ecfda765a7b0290444e26b7c

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17g_a_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17g_a_observed_%s=%s\n' \
            "$assertion_label" "$observed_value"
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        record_assertion "$absent_label" true
    else
        record_assertion "$absent_label" false \
            "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

validate_stage() {
    local stage_label=$1
    local stage_path=$2
    local candidate_name=$3
    local candidate_hash=$4
    local meta_hash=$5
    local manifest_status=0
    local -a stage_entries=()

    if [[ -d "$stage_path" && ! -L "$stage_path" ]]; then
        record_assertion "${stage_label}_directory" true
    else
        record_assertion "${stage_label}_directory" false absent
        return
    fi
    assert_equal "${stage_label}_directory_metadata" \
        "$(stat -c '%U:%G:%a' "$stage_path")" root:root:700
    mapfile -t stage_entries < <(
        find "$stage_path" -mindepth 1 -maxdepth 1 -printf '%f\n' |
            LC_ALL=C sort
    )
    assert_equal "${stage_label}_entry_count" "${#stage_entries[@]}" 4
    assert_equal "${stage_label}_entries" \
        "$(printf '%s\n' "${stage_entries[@]}")" \
        "$(printf '%s\n' .complete manifest.sha256 "$candidate_name" stage.meta)"
    assert_equal "${stage_label}_candidate_hash" \
        "$(file_hash "$stage_path/$candidate_name" 2>/dev/null)" \
        "$candidate_hash"
    assert_equal "${stage_label}_candidate_metadata" \
        "$(stat -c '%U:%G:%a' "$stage_path/$candidate_name" 2>/dev/null)" \
        root:root:600
    assert_equal "${stage_label}_manifest_content" \
        "$(cat "$stage_path/manifest.sha256" 2>/dev/null)" \
        "$candidate_hash  $candidate_name"
    (
        cd "$stage_path" || exit 1
        sha256sum --check --status manifest.sha256
    ) || manifest_status=$?
    assert_equal "${stage_label}_manifest_status" "$manifest_status" 0
    assert_equal "${stage_label}_meta_hash" \
        "$(file_hash "$stage_path/stage.meta" 2>/dev/null)" "$meta_hash"
    assert_equal "${stage_label}_completion_metadata" \
        "$(stat -c '%U:%G:%a:%s' "$stage_path/.complete" 2>/dev/null)" \
        root:root:600:0
}

query_and_assert() {
    local query_label=$1
    local query_server=$2
    local query_port=$3
    local query_name=$4
    local query_type=$5
    local expected_answer=$6
    local query_status=0
    local query_answer

    query_answer=$(
        dig +time=2 +tries=1 +short \
            "@$query_server" -p "$query_port" "$query_name" "$query_type" |
            sed 's/[.]$//' |
            LC_ALL=C sort
    ) || query_status=$?
    assert_equal "${query_label}_status" "$query_status" 0
    assert_equal "${query_label}_answer" "$query_answer" "$expected_answer"
}

state_snapshot() {
    printf '%s\n' \
        "root=$(file_hash "$live_root" 2>/dev/null)" \
        "primary=$(file_hash "$live_primary" 2>/dev/null)" \
        "local_zone=$(file_hash "$live_local_zone" 2>/dev/null)" \
        "backup=$(file_hash "$backup_dir/pihole.conf.before" 2>/dev/null)" \
        "unbound=$(systemctl is-active unbound.service 2>/dev/null)" \
        "unbound_pid=$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" \
        "unbound_restarts=$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" \
        "ftl=$(systemctl is-active pihole-FTL.service 2>/dev/null)" \
        "ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" \
        "ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" \
        "residue=$(find "$live_conf_dir" -mindepth 1 -maxdepth 1 -name '*action17g*' -print 2>/dev/null | LC_ALL=C sort)"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$live_primary" == /etc/unbound/unbound.conf.d/pihole.conf ]]
    [[ "$live_local_zone" == /etc/unbound/unbound.conf.d/pihole-local-zone.conf ]]
    [[ "$legacy_local_zone" == /etc/unbound/unbound.conf.d/pihole0-local-zone.conf ]]
    printf 'action_17g_a_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17g_a_remote_reached=true\n'
for required_command in \
    awk cat dig find hostname id mapfile sed sha256sum sort stat systemctl \
    unbound-checkconf wc; do
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
assert_regular_file live_root_regular "$live_root"
assert_equal live_root_hash "$(file_hash "$live_root" 2>/dev/null)" \
    "$expected_root_sha256"
assert_regular_file live_primary_regular "$live_primary"
assert_equal live_primary_hash "$(file_hash "$live_primary" 2>/dev/null)" \
    "$expected_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a' "$live_primary" 2>/dev/null)" root:root:644
assert_regular_file live_local_zone_regular "$live_local_zone"
assert_equal live_local_zone_hash \
    "$(file_hash "$live_local_zone" 2>/dev/null)" \
    "$expected_local_zone_sha256"
assert_equal live_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone" 2>/dev/null)" root:root:644
assert_absent legacy_local_zone_absent "$legacy_local_zone"
assert_absent transaction_primary_absent "$transaction_primary"
assert_absent transaction_local_zone_absent "$transaction_local_zone"
assert_absent rollback_primary_absent "$rollback_primary"

if [[ -d "$backup_dir" && ! -L "$backup_dir" ]]; then
    record_assertion backup_directory true
else
    record_assertion backup_directory false absent
fi
assert_equal backup_directory_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir" 2>/dev/null)" root:root:700
assert_equal backup_entry_count \
    "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null |
        wc -l)" 3
assert_regular_file backup_primary_regular "$backup_dir/pihole.conf.before"
assert_equal backup_primary_hash \
    "$(file_hash "$backup_dir/pihole.conf.before" 2>/dev/null)" \
    "$expected_legacy_primary_sha256"
assert_equal backup_primary_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir/pihole.conf.before" 2>/dev/null)" \
    root:root:600
assert_equal backup_manifest_content \
    "$(cat "$backup_dir/manifest.sha256" 2>/dev/null)" \
    "$expected_legacy_primary_sha256  pihole.conf.before"
assert_equal backup_manifest_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir/manifest.sha256" 2>/dev/null)" \
    root:root:600
assert_equal backup_action_metadata \
    "$(stat -c '%U:%G:%a' "$backup_dir/action.meta" 2>/dev/null)" \
    root:root:600

validate_stage primary "$primary_stage" pihole.conf \
    "$expected_primary_sha256" "$expected_primary_meta_sha256"
validate_stage local_zone "$local_zone_stage" pihole0-local-zone.conf \
    "$expected_local_zone_sha256" "$expected_local_zone_meta_sha256"

before_snapshot=$(state_snapshot)
readonly before_snapshot
before_snapshot_sha256=$(
    printf '%s' "$before_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly before_snapshot_sha256

parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || parser_status=$?
assert_equal live_parser_status "$parser_status" 0
assert_equal unbound_active "$(systemctl is-active unbound.service 2>/dev/null)" \
    active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

query_and_assert direct_ipv4_node_a \
    127.0.0.1 5335 pihole0.local.theama.co A 10.1.0.53
query_and_assert direct_ipv4_node_b \
    127.0.0.1 5335 pihole00.local.theama.co A 10.1.0.54
query_and_assert direct_ipv6_node_b \
    ::1 5335 pihole00.local.theama.co A 10.1.0.54
query_and_assert direct_ptr_node_b \
    127.0.0.1 5335 54.0.1.10.in-addr.arpa PTR pihole00.local.theama.co
query_and_assert pihole_path_node_b \
    127.0.0.1 53 pihole00.local.theama.co A 10.1.0.54

after_snapshot=$(state_snapshot)
readonly after_snapshot
after_snapshot_sha256=$(
    printf '%s' "$after_snapshot" | sha256sum | awk '{ print $1 }'
)
readonly after_snapshot_sha256
assert_equal state_unchanged "$after_snapshot" "$before_snapshot"

printf 'action_17g_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17g_a_failed_assertion_count=%s\n' "$failed_assertion_count"
printf 'action_17g_a_first_failure=%s\n' "$first_failure"
printf 'action_17g_a_before_state_sha256=%s\n' "$before_snapshot_sha256"
printf 'action_17g_a_after_state_sha256=%s\n' "$after_snapshot_sha256"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=true\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17g_a_conclusion=post_activation_state_verified\n'
    printf 'action_17g_a_remote_complete=true\n'
    exit 0
fi
printf 'action_17g_a_conclusion=post_activation_state_mismatch\n'
printf 'action_17g_a_remote_complete=true\n'
exit 1
