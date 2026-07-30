#!/usr/bin/env bash

set -uo pipefail
set +x
umask 077
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
readonly accepted_live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8

failed_assertions=0

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

record_assertion() {
    local label=$1
    local value=$2

    printf 'prewrite_%s=%s\n' "$label" "$value"
    if [[ "$value" != true ]]; then
        ((failed_assertions += 1))
    fi
}

bool_for() {
    if "$@"; then
        printf true
    else
        printf false
    fi
}

state_for() {
    local path=$1

    if [[ -f "$path" && ! -L "$path" ]]; then
        printf regular
    elif [[ -d "$path" && ! -L "$path" ]]; then
        printf directory
    elif [[ -L "$path" ]]; then
        printf symlink
    elif [[ -e "$path" ]]; then
        printf other
    else
        printf absent
    fi
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
        -printf '%f|%y|%U:%G:%m:%s:%i\n' 2>/dev/null |
        LC_ALL=C sort
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -type f -print0 \
        2>/dev/null |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    for service in unbound.service pihole-FTL.service; do
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts 2>/dev/null
        printf '%s|enabled=%s\n' \
            "$service" "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$local_zone_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    printf 'action_17f_a_node_b_unbound_prewrite_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17f_a_remote_reached=true\n'

readonly -a required_commands=(
    awk base64 cat chmod chown find grep hostname install mapfile mktemp mv
    readlink rm sha256sum sort stat systemctl tar touch unbound-checkconf wc
    xargs
)
missing_commands=
for command_name in "${required_commands[@]}"; do
    command_available=false
    if command -v "$command_name" >/dev/null 2>&1; then
        command_available=true
    else
        missing_commands+="${missing_commands:+,}${command_name}"
    fi
    record_assertion "command_${command_name}_available" "$command_available"
done
missing_command_count=0
if [[ -n "$missing_commands" ]]; then
    missing_command_count=$(
        tr -cd ',' <<<"$missing_commands" | wc -c | awk '{ print $1 + 1 }'
    )
fi
printf 'required_command_count=%s\n' "${#required_commands[@]}"
printf 'missing_command_count=%s\n' "$missing_command_count"
printf 'missing_commands_b64=%s\n' \
    "$(printf '%s' "$missing_commands" | base64 -w 0)"

effective_uid=$(id -u 2>/dev/null)
uid_status=$?
pwd_value=$(pwd -P 2>/dev/null)
pwd_status=$?
hostname_value=$(hostname 2>/dev/null)
hostname_status=$?
printf 'effective_uid_status=%s\n' "$uid_status"
printf 'effective_uid=%s\n' "${effective_uid:-unavailable}"
printf 'working_directory_status=%s\n' "$pwd_status"
printf 'working_directory_is_root=%s\n' \
    "$([[ "$pwd_status" -eq 0 && "$pwd_value" == / ]] && printf true || printf false)"
printf 'hostname_status=%s\n' "$hostname_status"
printf 'hostname_b64=%s\n' \
    "$(printf '%s' "$hostname_value" | base64 -w 0)"
record_assertion uid_is_root \
    "$([[ "$uid_status" -eq 0 && "$effective_uid" == 0 ]] && printf true || printf false)"
record_assertion working_directory_is_root \
    "$([[ "$pwd_status" -eq 0 && "$pwd_value" == / ]] && printf true || printf false)"
record_assertion hostname_matches \
    "$([[ "$hostname_status" -eq 0 && "$hostname_value" == "$expected_hostname" ]] && printf true || printf false)"

live_root_state=$(state_for "$live_root")
live_root_sha256=
[[ "$live_root_state" == regular ]] && live_root_sha256=$(file_hash "$live_root")
printf 'live_root_state=%s\n' "$live_root_state"
printf 'live_root_sha256=%s\n' "${live_root_sha256:-unavailable}"
record_assertion live_root_regular \
    "$([[ "$live_root_state" == regular ]] && printf true || printf false)"
record_assertion live_root_hash_matches \
    "$([[ "$live_root_sha256" == "$accepted_root_sha256" ]] && printf true || printf false)"

live_primary_state=$(state_for "$live_primary")
live_primary_sha256=
live_primary_metadata=
if [[ "$live_primary_state" == regular ]]; then
    live_primary_sha256=$(file_hash "$live_primary")
    live_primary_metadata=$(stat -c '%U:%G:%a:%s' "$live_primary" 2>/dev/null)
fi
printf 'live_primary_state=%s\n' "$live_primary_state"
printf 'live_primary_sha256=%s\n' "${live_primary_sha256:-unavailable}"
printf 'live_primary_metadata=%s\n' "${live_primary_metadata:-unavailable}"
record_assertion live_primary_regular \
    "$([[ "$live_primary_state" == regular ]] && printf true || printf false)"
record_assertion live_primary_hash_matches \
    "$([[ "$live_primary_sha256" == "$accepted_live_primary_sha256" ]] && printf true || printf false)"
record_assertion live_primary_metadata_matches \
    "$([[ "$live_primary_metadata" == root:root:644:34342 ]] && printf true || printf false)"

live_local_zone_state=$(state_for "$live_local_zone")
printf 'live_local_zone_state=%s\n' "$live_local_zone_state"
record_assertion live_local_zone_absent \
    "$([[ "$live_local_zone_state" == absent ]] && printf true || printf false)"

primary_stage_state=$(state_for "$primary_stage")
primary_stage_metadata=
[[ "$primary_stage_state" == directory ]] &&
    primary_stage_metadata=$(stat -c '%U:%G:%a' "$primary_stage" 2>/dev/null)
printf 'primary_stage_state=%s\n' "$primary_stage_state"
printf 'primary_stage_metadata=%s\n' "${primary_stage_metadata:-unavailable}"
record_assertion primary_stage_directory_valid \
    "$([[ "$primary_stage_state" == directory ]] && printf true || printf false)"
record_assertion primary_stage_metadata_matches \
    "$([[ "$primary_stage_metadata" == root:root:700 ]] && printf true || printf false)"

primary_entry_set_matches=false
primary_files_metadata_match=true
if [[ "$primary_stage_state" == directory ]]; then
    mapfile -t primary_entries < <(
        find "$primary_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null |
            LC_ALL=C sort
    )
    if [[ "${#primary_entries[@]}" -eq 4 &&
        "${primary_entries[0]:-}" == .complete &&
        "${primary_entries[1]:-}" == manifest.sha256 &&
        "${primary_entries[2]:-}" == pihole.conf &&
        "${primary_entries[3]:-}" == stage.meta ]]; then
        primary_entry_set_matches=true
    fi
else
    primary_files_metadata_match=false
fi
record_assertion primary_stage_entry_set_matches "$primary_entry_set_matches"

for file_label in complete manifest candidate meta; do
    case "$file_label" in
        complete) file_path="$primary_stage/.complete" ;;
        manifest) file_path="$primary_stage/manifest.sha256" ;;
        candidate) file_path="$primary_stage/pihole.conf" ;;
        meta) file_path="$primary_stage/stage.meta" ;;
    esac
    file_valid=false
    if [[ -f "$file_path" && ! -L "$file_path" ]] &&
        [[ "$(stat -c '%U:%G:%a' "$file_path" 2>/dev/null)" == root:root:600 ]]; then
        file_valid=true
    else
        primary_files_metadata_match=false
    fi
    record_assertion "primary_${file_label}_file_valid" "$file_valid"
done
record_assertion primary_files_metadata_match "$primary_files_metadata_match"

primary_complete_empty=false
[[ -f "$primary_stage/.complete" && ! -s "$primary_stage/.complete" ]] &&
    primary_complete_empty=true
record_assertion primary_complete_empty "$primary_complete_empty"

primary_candidate_sha256=
[[ -f "$primary_stage/pihole.conf" ]] &&
    primary_candidate_sha256=$(file_hash "$primary_stage/pihole.conf")
printf 'primary_candidate_sha256=%s\n' \
    "${primary_candidate_sha256:-unavailable}"
record_assertion primary_candidate_hash_matches \
    "$([[ "$primary_candidate_sha256" == "$candidate_primary_sha256" ]] && printf true || printf false)"

primary_manifest_content_matches=false
if [[ -f "$primary_stage/manifest.sha256" ]] &&
    [[ "$(cat "$primary_stage/manifest.sha256" 2>/dev/null)" == "$candidate_primary_sha256  pihole.conf" ]]; then
    primary_manifest_content_matches=true
fi
record_assertion primary_manifest_content_matches \
    "$primary_manifest_content_matches"

primary_manifest_check_status=1
if [[ "$primary_stage_state" == directory ]]; then
    (
        cd "$primary_stage" || exit
        sha256sum --check --status manifest.sha256
    ) >/dev/null 2>&1
    primary_manifest_check_status=$?
fi
printf 'primary_manifest_check_status=%s\n' \
    "$primary_manifest_check_status"
record_assertion primary_manifest_check_passes \
    "$([[ "$primary_manifest_check_status" -eq 0 ]] && printf true || printf false)"

expected_primary_meta=$(printf '%s\n' \
    action=17e \
    node_role=node-b \
    artifact=pihole.conf \
    source_sha256="$candidate_primary_sha256" \
    live_activation=false)
primary_meta_content_matches=false
if [[ -f "$primary_stage/stage.meta" ]] &&
    [[ "$(cat "$primary_stage/stage.meta" 2>/dev/null)" == "$expected_primary_meta" ]]; then
    primary_meta_content_matches=true
fi
record_assertion primary_meta_content_matches "$primary_meta_content_matches"

local_zone_stage_state=$(state_for "$local_zone_stage")
transaction_stage_count=$(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17f-local-zone.*' -print \
        2>/dev/null | wc -l
)
printf 'local_zone_stage_state=%s\n' "$local_zone_stage_state"
printf 'transaction_stage_count=%s\n' "$transaction_stage_count"
record_assertion local_zone_stage_absent \
    "$([[ "$local_zone_stage_state" == absent ]] && printf true || printf false)"
record_assertion transaction_stage_count_zero \
    "$([[ "$transaction_stage_count" -eq 0 ]] && printf true || printf false)"

unbound_active=$(systemctl is-active unbound.service 2>/dev/null)
unbound_status=$?
pihole_ftl_active=$(systemctl is-active pihole-FTL.service 2>/dev/null)
pihole_ftl_status=$?
printf 'unbound_active_status=%s\n' "$unbound_status"
printf 'unbound_active=%s\n' "${unbound_active:-unavailable}"
printf 'pihole_ftl_active_status=%s\n' "$pihole_ftl_status"
printf 'pihole_ftl_active=%s\n' "${pihole_ftl_active:-unavailable}"
record_assertion unbound_active \
    "$([[ "$unbound_status" -eq 0 && "$unbound_active" == active ]] && printf true || printf false)"
record_assertion pihole_ftl_active \
    "$([[ "$pihole_ftl_status" -eq 0 && "$pihole_ftl_active" == active ]] && printf true || printf false)"

unbound-checkconf "$live_root" >/dev/null 2>&1
live_checkconf_status=$?
printf 'live_checkconf_status=%s\n' "$live_checkconf_status"
record_assertion live_checkconf_valid \
    "$([[ "$live_checkconf_status" -eq 0 ]] && printf true || printf false)"

live_state_one=$(live_state)
live_state_one_status=$?
live_state_two=$(live_state)
live_state_two_status=$?
live_state_one_sha256=$(
    printf '%s' "$live_state_one" | sha256sum | awk '{ print $1 }'
)
live_state_two_sha256=$(
    printf '%s' "$live_state_two" | sha256sum | awk '{ print $1 }'
)
printf 'live_state_one_status=%s\n' "$live_state_one_status"
printf 'live_state_one_sha256=%s\n' "$live_state_one_sha256"
printf 'live_state_two_status=%s\n' "$live_state_two_status"
printf 'live_state_two_sha256=%s\n' "$live_state_two_sha256"
record_assertion live_state_one_collected \
    "$([[ "$live_state_one_status" -eq 0 ]] && printf true || printf false)"
record_assertion live_state_two_collected \
    "$([[ "$live_state_two_status" -eq 0 ]] && printf true || printf false)"
record_assertion live_state_one_matches \
    "$([[ "$live_state_one_sha256" == "$accepted_live_state_sha256" ]] && printf true || printf false)"
record_assertion live_state_two_matches \
    "$([[ "$live_state_two_sha256" == "$accepted_live_state_sha256" ]] && printf true || printf false)"
record_assertion live_state_snapshots_stable \
    "$([[ "$live_state_one_sha256" == "$live_state_two_sha256" ]] && printf true || printf false)"

conclusion=all_prewrite_prerequisites_pass
if ((failed_assertions)); then
    conclusion=prewrite_prerequisite_mismatch
fi
printf 'prewrite_assertion_count=55\n'
printf 'prewrite_failed_assertion_count=%s\n' "$failed_assertions"
printf 'action_17f_a_conclusion=%s\n' "$conclusion"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
printf 'action_17f_a_node_b_prewrite_diagnostic_complete=true\n'
