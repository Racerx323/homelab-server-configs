#!/usr/bin/env bash

set -uo pipefail
set +e
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole00
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly primary_stage=/var/tmp/caddy-unbound-node-b-action17e-primary
readonly local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly accepted_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly accepted_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly accepted_action17d_state_sha256=31862f7b0f86a6cddc9057501fffeff872bc3747a0144bb7d062fddcced9992c

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

state_for() {
    local path=$1

    if [[ -f "$path" && ! -L "$path" ]]; then
        printf 'regular\n'
    elif [[ -L "$path" ]]; then
        printf 'symlink\n'
    elif [[ -e "$path" ]]; then
        printf 'other\n'
    else
        printf 'absent\n'
    fi
}

hash_or_unavailable() {
    local path=$1

    if [[ -f "$path" && ! -L "$path" ]]; then
        file_hash "$path"
    else
        printf 'unavailable\n'
    fi
}

metadata_or_unavailable() {
    local path=$1

    if [[ -e "$path" && ! -L "$path" ]]; then
        stat -c '%U:%G:%a:%s' "$path"
    else
        printf 'unavailable\n'
    fi
}

action17d_state_snapshot() {
    local path

    for path in "$live_root" "$live_primary" "$live_local_zone"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$path" "$(stat -c '%U:%G:%a:%s' "$path")" \
                "$(file_hash "$path")"
        elif [[ -L "$path" ]]; then
            printf 'link|%s|%s|%s\n' \
                "$path" "$(stat -c '%U:%G:%a' "$path")" \
                "$(readlink -- "$path")"
        else
            printf 'absent|%s\n' "$path"
        fi
    done
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -printf '%f\0' |
        LC_ALL=C sort -z |
        while IFS= read -r -d '' entry; do
            path="$live_conf_dir/$entry"
            if [[ -f "$path" && ! -L "$path" ]]; then
                printf 'entry|%s|file|%s|%s\n' \
                    "$entry" "$(stat -c '%U:%G:%a:%s' "$path")" \
                    "$(file_hash "$path")"
            elif [[ -L "$path" ]]; then
                printf 'entry|%s|link|%s|%s\n' \
                    "$entry" "$(stat -c '%U:%G:%a' "$path")" \
                    "$(readlink -- "$path")"
            else
                printf 'entry|%s|other|%s\n' \
                    "$entry" "$(stat -c '%F:%U:%G:%a' "$path")"
            fi
        done
    systemctl show \
        --property=ActiveState,SubState,UnitFileState \
        pihole-FTL.service unbound.service 2>/dev/null || true
}

live_state() {
    local path service

    for path in "$live_root" "$live_primary" "$live_local_zone"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$path" "$(stat -c '%U:%G:%a:%s:%i' "$path")" \
                "$(file_hash "$path")"
        elif [[ -L "$path" ]]; then
            printf 'link|%s|%s|%s\n' \
                "$path" "$(stat -c '%U:%G:%a:%i' "$path")" \
                "$(readlink -- "$path")"
        else
            printf 'absent|%s\n' "$path"
        fi
    done
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%i\n' |
        LC_ALL=C sort
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    for service in unbound.service pihole-FTL.service; do
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf '%s|enabled=%s\n' \
            "$service" "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$accepted_root_sha256" \
        "$accepted_primary_sha256" \
        "$accepted_action17d_state_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]] || exit 1
    done
    printf 'action_17e_a_node_b_prewrite_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

failed_assertions=0
record_assertion() {
    local label=$1
    local result=$2

    if [[ "$result" == true ]]; then
        printf '%s=true\n' "$label"
    else
        printf '%s=false\n' "$label"
        failed_assertions=$((failed_assertions + 1))
    fi
}

printf 'action_17e_a_remote_reached=true\n'

uid_value=$(id -u 2>/dev/null)
uid_status=$?
uid_is_root=false
[[ "$uid_status" -eq 0 && "$uid_value" == 0 ]] && uid_is_root=true
printf 'effective_uid_status=%s\n' "$uid_status"
printf 'effective_uid=%s\n' "${uid_value:-unavailable}"
record_assertion prewrite_uid_is_root "$uid_is_root"

pwd_value=$(pwd -P 2>/dev/null)
pwd_status=$?
pwd_is_root=false
[[ "$pwd_status" -eq 0 && "$pwd_value" == / ]] && pwd_is_root=true
printf 'working_directory_status=%s\n' "$pwd_status"
printf 'working_directory_is_root=%s\n' "$pwd_is_root"
record_assertion prewrite_working_directory_is_root "$pwd_is_root"

hostname_value=$(hostname 2>/dev/null)
hostname_status=$?
hostname_matches=false
[[ "$hostname_status" -eq 0 &&
    "$hostname_value" == "$expected_hostname" ]] && hostname_matches=true
printf 'hostname_status=%s\n' "$hostname_status"
printf 'hostname_b64=%s\n' "$(printf '%s' "$hostname_value" | base64 -w 0)"
record_assertion prewrite_hostname_matches "$hostname_matches"

root_state=$(state_for "$live_root")
root_sha256=$(hash_or_unavailable "$live_root")
printf 'live_root_state=%s\n' "$root_state"
printf 'live_root_sha256=%s\n' "$root_sha256"
record_assertion prewrite_live_root_regular \
    "$([[ "$root_state" == regular ]] && printf true || printf false)"
record_assertion prewrite_live_root_hash_matches \
    "$([[ "$root_sha256" == "$accepted_root_sha256" ]] &&
        printf true || printf false)"

primary_state=$(state_for "$live_primary")
primary_sha256=$(hash_or_unavailable "$live_primary")
primary_metadata=$(metadata_or_unavailable "$live_primary")
printf 'live_primary_state=%s\n' "$primary_state"
printf 'live_primary_sha256=%s\n' "$primary_sha256"
printf 'live_primary_metadata=%s\n' "$primary_metadata"
record_assertion prewrite_live_primary_regular \
    "$([[ "$primary_state" == regular ]] && printf true || printf false)"
record_assertion prewrite_live_primary_hash_matches \
    "$([[ "$primary_sha256" == "$accepted_primary_sha256" ]] &&
        printf true || printf false)"
record_assertion prewrite_live_primary_metadata_matches \
    "$([[ "$primary_metadata" == root:root:644:34342 ]] &&
        printf true || printf false)"

local_zone_state=$(state_for "$live_local_zone")
printf 'live_local_zone_state=%s\n' "$local_zone_state"
record_assertion prewrite_live_local_zone_absent \
    "$([[ "$local_zone_state" == absent ]] && printf true || printf false)"

snapshot_one=$(action17d_state_snapshot)
snapshot_one_status=$?
snapshot_one_sha256=$(
    printf '%s\n' "$snapshot_one" | sha256sum | awk '{ print $1 }'
)
snapshot_two=$(action17d_state_snapshot)
snapshot_two_status=$?
snapshot_two_sha256=$(
    printf '%s\n' "$snapshot_two" | sha256sum | awk '{ print $1 }'
)
printf 'action17d_snapshot_one_status=%s\n' "$snapshot_one_status"
printf 'action17d_snapshot_one_sha256=%s\n' "$snapshot_one_sha256"
printf 'action17d_snapshot_two_status=%s\n' "$snapshot_two_status"
printf 'action17d_snapshot_two_sha256=%s\n' "$snapshot_two_sha256"
record_assertion prewrite_action17d_snapshot_one_collected \
    "$([[ "$snapshot_one_status" -eq 0 ]] && printf true || printf false)"
record_assertion prewrite_action17d_snapshot_two_collected \
    "$([[ "$snapshot_two_status" -eq 0 ]] && printf true || printf false)"
record_assertion prewrite_action17d_snapshot_one_matches \
    "$([[ "$snapshot_one_sha256" == "$accepted_action17d_state_sha256" ]] &&
        printf true || printf false)"
record_assertion prewrite_action17d_snapshot_two_matches \
    "$([[ "$snapshot_two_sha256" == "$accepted_action17d_state_sha256" ]] &&
        printf true || printf false)"
record_assertion prewrite_action17d_snapshots_stable \
    "$([[ "$snapshot_one_sha256" == "$snapshot_two_sha256" ]] &&
        printf true || printf false)"

unbound_active=$(systemctl is-active unbound.service 2>/dev/null)
unbound_active_status=$?
pihole_active=$(systemctl is-active pihole-FTL.service 2>/dev/null)
pihole_active_status=$?
printf 'unbound_active_status=%s\n' "$unbound_active_status"
printf 'unbound_active=%s\n' "${unbound_active:-unavailable}"
printf 'pihole_ftl_active_status=%s\n' "$pihole_active_status"
printf 'pihole_ftl_active=%s\n' "${pihole_active:-unavailable}"
record_assertion prewrite_unbound_active \
    "$([[ "$unbound_active_status" -eq 0 &&
        "$unbound_active" == active ]] && printf true || printf false)"
record_assertion prewrite_pihole_ftl_active \
    "$([[ "$pihole_active_status" -eq 0 &&
        "$pihole_active" == active ]] && printf true || printf false)"

checkconf_output=$(unbound-checkconf "$live_root" 2>&1)
checkconf_status=$?
checkconf_output_sha256=$(
    printf '%s' "$checkconf_output" | sha256sum | awk '{ print $1 }'
)
printf 'live_checkconf_status=%s\n' "$checkconf_status"
printf 'live_checkconf_output_sha256=%s\n' "$checkconf_output_sha256"
record_assertion prewrite_live_checkconf_valid \
    "$([[ "$checkconf_status" -eq 0 ]] && printf true || printf false)"

primary_stage_state=$(state_for "$primary_stage")
local_zone_stage_state=$(state_for "$local_zone_stage")
transaction_stage_count=$(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17e-primary.*' -print \
        2>/dev/null | wc -l
)
printf 'primary_stage_state=%s\n' "$primary_stage_state"
printf 'local_zone_stage_state=%s\n' "$local_zone_stage_state"
printf 'transaction_stage_count=%s\n' "$transaction_stage_count"
record_assertion prewrite_primary_stage_absent \
    "$([[ "$primary_stage_state" == absent ]] && printf true || printf false)"
record_assertion prewrite_local_zone_stage_absent \
    "$([[ "$local_zone_stage_state" == absent ]] && printf true || printf false)"
record_assertion prewrite_transaction_stage_count_zero \
    "$([[ "$transaction_stage_count" -eq 0 ]] && printf true || printf false)"

live_state_one=$(live_state)
live_state_one_status=$?
live_state_one_sha256=$(
    printf '%s' "$live_state_one" | sha256sum | awk '{ print $1 }'
)
live_state_two=$(live_state)
live_state_two_status=$?
live_state_two_sha256=$(
    printf '%s' "$live_state_two" | sha256sum | awk '{ print $1 }'
)
printf 'live_state_one_status=%s\n' "$live_state_one_status"
printf 'live_state_one_sha256=%s\n' "$live_state_one_sha256"
printf 'live_state_two_status=%s\n' "$live_state_two_status"
printf 'live_state_two_sha256=%s\n' "$live_state_two_sha256"
record_assertion prewrite_live_state_one_collected \
    "$([[ "$live_state_one_status" -eq 0 ]] && printf true || printf false)"
record_assertion prewrite_live_state_two_collected \
    "$([[ "$live_state_two_status" -eq 0 ]] && printf true || printf false)"
record_assertion prewrite_live_state_snapshots_stable \
    "$([[ "$live_state_one_sha256" == "$live_state_two_sha256" ]] &&
        printf true || printf false)"

conclusion=all_prewrite_assertions_pass_and_collectors_stable
if [[ "$snapshot_one_status" -ne 0 || "$snapshot_two_status" -ne 0 ||
    "$snapshot_one_sha256" != "$snapshot_two_sha256" ]]; then
    conclusion=action17d_snapshot_collection_unstable
elif [[ "$live_state_one_status" -ne 0 || "$live_state_two_status" -ne 0 ]]; then
    conclusion=live_state_collection_failed
elif [[ "$live_state_one_sha256" != "$live_state_two_sha256" ]]; then
    conclusion=live_state_collection_unstable
elif [[ "$failed_assertions" -ne 0 ]]; then
    conclusion=prewrite_assertion_mismatch
fi

printf 'prewrite_assertion_count=23\n'
printf 'prewrite_failed_assertion_count=%s\n' "$failed_assertions"
printf 'action_17e_a_conclusion=%s\n' "$conclusion"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
printf 'action_17e_a_node_b_prewrite_diagnostic_complete=true\n'
exit 0
