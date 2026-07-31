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
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1

assertion_count=0
failed_assertions=0
first_failure=none

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    ((assertion_count += 1))
    printf 'action_17f_c_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        ((failed_assertions += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

state_for() {
    local inspected_path=$1

    if [[ -f "$inspected_path" && ! -L "$inspected_path" ]]; then
        printf regular
    elif [[ -d "$inspected_path" && ! -L "$inspected_path" ]]; then
        printf directory
    elif [[ -L "$inspected_path" ]]; then
        printf symlink
    elif [[ -e "$inspected_path" ]]; then
        printf other
    else
        printf absent
    fi
}

live_state() {
    local state_path state_service

    for state_path in "$live_root" "$live_primary" "$live_local_zone"; do
        if [[ -f "$state_path" && ! -L "$state_path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$state_path" \
                "$(stat -c '%U:%G:%a:%s:%i' "$state_path")" \
                "$(file_hash "$state_path")"
        elif [[ -L "$state_path" ]]; then
            printf 'link|%s|%s|%s\n' \
                "$state_path" \
                "$(stat -c '%U:%G:%a:%i' "$state_path")" \
                "$(readlink -- "$state_path")"
        else
            printf 'absent|%s\n' "$state_path"
        fi
    done
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%i\n' 2>/dev/null |
        LC_ALL=C sort
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -type f -print0 \
        2>/dev/null |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
    for state_service in unbound.service pihole-FTL.service; do
        systemctl show "$state_service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts 2>/dev/null
        printf '%s|enabled=%s\n' \
            "$state_service" \
            "$(systemctl is-enabled "$state_service" 2>/dev/null || true)"
    done
}

verify_stage() {
    local stage_label=$1
    local stage_path=$2
    local candidate_name=$3
    local candidate_hash=$4
    local expected_meta=$5
    local stage_state stage_metadata candidate_observed_hash
    local stage_manifest_status=1
    local stage_complete_empty=false
    local stage_entry_set=false
    local stage_meta_matches=false
    local stage_manifest_matches=false
    local file_label file_path file_valid
    local -a stage_entries=()

    stage_state=$(state_for "$stage_path")
    stage_metadata=
    [[ "$stage_state" == directory ]] &&
        stage_metadata=$(stat -c '%U:%G:%a' "$stage_path" 2>/dev/null)
    printf '%s_stage_state=%s\n' "$stage_label" "$stage_state"
    printf '%s_stage_metadata=%s\n' \
        "$stage_label" "${stage_metadata:-unavailable}"
    record_assertion "${stage_label}_stage_directory" \
        "$([[ "$stage_state" == directory ]] && printf true || printf false)"
    record_assertion "${stage_label}_stage_metadata" \
        "$([[ "$stage_metadata" == root:root:700 ]] && printf true || printf false)"

    if [[ "$stage_state" == directory ]]; then
        mapfile -t stage_entries < <(
            find "$stage_path" -mindepth 1 -maxdepth 1 -printf '%f\n' \
                2>/dev/null |
                LC_ALL=C sort
        )
    fi
    if [[ "${#stage_entries[@]}" -eq 4 &&
        "${stage_entries[0]:-}" == .complete &&
        "${stage_entries[1]:-}" == manifest.sha256 &&
        "${stage_entries[2]:-}" == "$candidate_name" &&
        "${stage_entries[3]:-}" == stage.meta ]]; then
        stage_entry_set=true
    fi
    record_assertion "${stage_label}_stage_entry_set" "$stage_entry_set"

    for file_label in complete manifest candidate meta; do
        case "$file_label" in
            complete) file_path="$stage_path/.complete" ;;
            manifest) file_path="$stage_path/manifest.sha256" ;;
            candidate) file_path="$stage_path/$candidate_name" ;;
            meta) file_path="$stage_path/stage.meta" ;;
        esac
        file_valid=false
        if [[ -f "$file_path" && ! -L "$file_path" ]] &&
            [[ "$(stat -c '%U:%G:%a' "$file_path" 2>/dev/null)" == root:root:600 ]]; then
            file_valid=true
        fi
        record_assertion \
            "${stage_label}_${file_label}_file_metadata" "$file_valid"
    done

    [[ -f "$stage_path/.complete" && ! -s "$stage_path/.complete" ]] &&
        stage_complete_empty=true
    record_assertion "${stage_label}_complete_empty" "$stage_complete_empty"

    candidate_observed_hash=
    [[ -f "$stage_path/$candidate_name" ]] &&
        candidate_observed_hash=$(file_hash "$stage_path/$candidate_name")
    printf '%s_candidate_sha256=%s\n' \
        "$stage_label" "${candidate_observed_hash:-unavailable}"
    record_assertion "${stage_label}_candidate_hash" \
        "$([[ "$candidate_observed_hash" == "$candidate_hash" ]] && printf true || printf false)"

    if [[ -f "$stage_path/manifest.sha256" ]] &&
        [[ "$(cat "$stage_path/manifest.sha256" 2>/dev/null)" == "$candidate_hash  $candidate_name" ]]; then
        stage_manifest_matches=true
    fi
    record_assertion \
        "${stage_label}_manifest_content" "$stage_manifest_matches"

    if [[ "$stage_state" == directory ]]; then
        (
            cd "$stage_path" || exit
            sha256sum --check --status manifest.sha256
        ) >/dev/null 2>&1
        stage_manifest_status=$?
    fi
    printf '%s_manifest_check_status=%s\n' \
        "$stage_label" "$stage_manifest_status"
    record_assertion "${stage_label}_manifest_check" \
        "$([[ "$stage_manifest_status" -eq 0 ]] && printf true || printf false)"

    if [[ -f "$stage_path/stage.meta" ]] &&
        [[ "$(cat "$stage_path/stage.meta" 2>/dev/null)" == "$expected_meta" ]]; then
        stage_meta_matches=true
    fi
    record_assertion "${stage_label}_meta_content" "$stage_meta_matches"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$local_zone_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    [[ "$candidate_local_zone_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17f_c_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17f_c_remote_reached=true\n'

readonly -a required_commands=(
    awk cat find hostname id mapfile readlink sha256sum sort stat systemctl
    unbound-checkconf wc xargs
)
missing_commands=
for required_command in "${required_commands[@]}"; do
    command_available=false
    command -v "$required_command" >/dev/null 2>&1 &&
        command_available=true
    record_assertion \
        "command_${required_command}_available" "$command_available"
    [[ "$command_available" == true ]] ||
        missing_commands+="${missing_commands:+,}${required_command}"
done
printf 'required_command_count=%s\n' "${#required_commands[@]}"
printf 'missing_commands=%s\n' "${missing_commands:-none}"

effective_uid=$(id -u 2>/dev/null)
effective_uid_status=$?
working_directory=$(pwd -P 2>/dev/null)
working_directory_status=$?
observed_hostname=$(hostname 2>/dev/null)
hostname_status=$?
printf 'effective_uid_status=%s\n' "$effective_uid_status"
printf 'effective_uid=%s\n' "${effective_uid:-unavailable}"
printf 'working_directory_status=%s\n' "$working_directory_status"
printf 'working_directory=%s\n' "${working_directory:-unavailable}"
printf 'hostname_status=%s\n' "$hostname_status"
printf 'hostname=%s\n' "${observed_hostname:-unavailable}"
record_assertion uid_is_root \
    "$([[ "$effective_uid_status" -eq 0 && "$effective_uid" == 0 ]] && printf true || printf false)"
record_assertion working_directory_is_root \
    "$([[ "$working_directory_status" -eq 0 && "$working_directory" == / ]] && printf true || printf false)"
record_assertion hostname_matches \
    "$([[ "$hostname_status" -eq 0 && "$observed_hostname" == "$expected_hostname" ]] && printf true || printf false)"

live_root_state=$(state_for "$live_root")
live_root_hash=
[[ "$live_root_state" == regular ]] &&
    live_root_hash=$(file_hash "$live_root")
printf 'live_root_state=%s\n' "$live_root_state"
printf 'live_root_sha256=%s\n' "${live_root_hash:-unavailable}"
record_assertion live_root_regular \
    "$([[ "$live_root_state" == regular ]] && printf true || printf false)"
record_assertion live_root_hash \
    "$([[ "$live_root_hash" == "$accepted_root_sha256" ]] && printf true || printf false)"

live_primary_state=$(state_for "$live_primary")
live_primary_hash=
live_primary_metadata=
if [[ "$live_primary_state" == regular ]]; then
    live_primary_hash=$(file_hash "$live_primary")
    live_primary_metadata=$(stat -c '%U:%G:%a:%s' "$live_primary" 2>/dev/null)
fi
printf 'live_primary_state=%s\n' "$live_primary_state"
printf 'live_primary_sha256=%s\n' "${live_primary_hash:-unavailable}"
printf 'live_primary_metadata=%s\n' "${live_primary_metadata:-unavailable}"
record_assertion live_primary_regular \
    "$([[ "$live_primary_state" == regular ]] && printf true || printf false)"
record_assertion live_primary_hash \
    "$([[ "$live_primary_hash" == "$accepted_live_primary_sha256" ]] && printf true || printf false)"
record_assertion live_primary_metadata \
    "$([[ "$live_primary_metadata" == root:root:644:34342 ]] && printf true || printf false)"

live_local_zone_state=$(state_for "$live_local_zone")
printf 'live_local_zone_state=%s\n' "$live_local_zone_state"
record_assertion live_local_zone_absent \
    "$([[ "$live_local_zone_state" == absent ]] && printf true || printf false)"

expected_primary_meta=$(printf '%s\n' \
    action=17e \
    node_role=node-b \
    artifact=pihole.conf \
    source_sha256="$candidate_primary_sha256" \
    live_activation=false)
verify_stage primary "$primary_stage" pihole.conf \
    "$candidate_primary_sha256" "$expected_primary_meta"

expected_local_zone_meta=$(printf '%s\n' \
    action=17f \
    node_role=node-b \
    artifact=pihole0-local-zone.conf \
    source_sha256="$candidate_local_zone_sha256" \
    requires_action17e_primary_sha256="$candidate_primary_sha256" \
    live_activation=false)
verify_stage local_zone "$local_zone_stage" pihole0-local-zone.conf \
    "$candidate_local_zone_sha256" "$expected_local_zone_meta"

transaction_stage_count=$(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17f-local-zone.*' -print \
        2>/dev/null |
        wc -l
)
printf 'transaction_stage_count=%s\n' "$transaction_stage_count"
record_assertion transaction_stage_count_zero \
    "$([[ "$transaction_stage_count" -eq 0 ]] && printf true || printf false)"

unbound_state=$(systemctl is-active unbound.service 2>/dev/null)
unbound_status=$?
pihole_ftl_state=$(systemctl is-active pihole-FTL.service 2>/dev/null)
pihole_ftl_status=$?
printf 'unbound_active_status=%s\n' "$unbound_status"
printf 'unbound_active=%s\n' "${unbound_state:-unavailable}"
printf 'pihole_ftl_active_status=%s\n' "$pihole_ftl_status"
printf 'pihole_ftl_active=%s\n' "${pihole_ftl_state:-unavailable}"
record_assertion unbound_active \
    "$([[ "$unbound_status" -eq 0 && "$unbound_state" == active ]] && printf true || printf false)"
record_assertion pihole_ftl_active \
    "$([[ "$pihole_ftl_status" -eq 0 && "$pihole_ftl_state" == active ]] && printf true || printf false)"

unbound-checkconf "$live_root" >/dev/null 2>&1
live_checkconf_status=$?
printf 'live_checkconf_status=%s\n' "$live_checkconf_status"
record_assertion live_checkconf_valid \
    "$([[ "$live_checkconf_status" -eq 0 ]] && printf true || printf false)"

printf 'include-toplevel: "%s"\ninclude-toplevel: "%s"\n' \
    "$primary_stage/pihole.conf" \
    "$local_zone_stage/pihole0-local-zone.conf" |
    unbound-checkconf /dev/stdin >/dev/null 2>&1
combined_checkconf_status=${PIPESTATUS[1]}
printf 'combined_checkconf_status=%s\n' "$combined_checkconf_status"
record_assertion combined_pair_valid \
    "$([[ "$combined_checkconf_status" -eq 0 ]] && printf true || printf false)"

live_state_one=$(live_state)
live_state_one_status=$?
live_state_two=$(live_state)
live_state_two_status=$?
live_state_one_hash=$(
    printf '%s' "$live_state_one" | sha256sum | awk '{ print $1 }'
)
live_state_two_hash=$(
    printf '%s' "$live_state_two" | sha256sum | awk '{ print $1 }'
)
printf 'live_state_one_status=%s\n' "$live_state_one_status"
printf 'live_state_one_sha256=%s\n' "$live_state_one_hash"
printf 'live_state_two_status=%s\n' "$live_state_two_status"
printf 'live_state_two_sha256=%s\n' "$live_state_two_hash"
record_assertion live_state_one_collected \
    "$([[ "$live_state_one_status" -eq 0 ]] && printf true || printf false)"
record_assertion live_state_two_collected \
    "$([[ "$live_state_two_status" -eq 0 ]] && printf true || printf false)"
record_assertion live_state_one_accepted \
    "$([[ "$live_state_one_hash" == "$accepted_live_state_sha256" ]] && printf true || printf false)"
record_assertion live_state_two_accepted \
    "$([[ "$live_state_two_hash" == "$accepted_live_state_sha256" ]] && printf true || printf false)"
record_assertion live_state_stable \
    "$([[ "$live_state_one_hash" == "$live_state_two_hash" ]] && printf true || printf false)"

conclusion=retained_stage_and_node_b_continuity_verified
if ((failed_assertions)); then
    conclusion=retained_stage_or_node_b_continuity_mismatch
fi
printf 'action_17f_c_assertion_count=%s\n' "$assertion_count"
printf 'action_17f_c_failed_assertion_count=%s\n' "$failed_assertions"
printf 'action_17f_c_first_failure=%s\n' "$first_failure"
printf 'action_17f_c_conclusion=%s\n' "$conclusion"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
printf 'action_17f_c_remote_complete=true\n'

((failed_assertions == 0))
