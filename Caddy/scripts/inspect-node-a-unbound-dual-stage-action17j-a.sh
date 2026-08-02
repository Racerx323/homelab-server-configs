#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"
readonly legacy_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly primary_stage=/var/tmp/caddy-unbound-node-a-action17i-primary
readonly local_zone_stage=/var/tmp/caddy-unbound-node-a-action17j-local-zone
readonly accepted_live_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae
readonly accepted_live_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_root_include='include-toplevel: "/etc/unbound/unbound.conf.d/*.conf"'
readonly expected_assertion_count=70

assertion_count=0
failed_assertion_count=0
first_failure=none

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

active_directives() {
    awk '
        /^[[:space:]]*(#|$)/ { next }
        {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/[[:space:]]+/, " ")
            print
        }
    ' "$@"
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17j_a_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17j_a_observed_%s=%s\n' \
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

assert_directory() {
    local directory_label=$1
    local directory_path=$2

    if [[ -d "$directory_path" && ! -L "$directory_path" ]]; then
        record_assertion "$directory_label" true
    else
        record_assertion "$directory_label" false \
            "$(stat -c %F "$directory_path" 2>/dev/null || printf absent)"
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

state_snapshot() {
    local snapshot_path

    for snapshot_path in "$live_root" "$live_primary" "$live_local_zone" \
        "$legacy_local_zone"; do
        if [[ -f "$snapshot_path" && ! -L "$snapshot_path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$snapshot_path" \
                "$(stat -c '%U:%G:%a:%s' "$snapshot_path")" \
                "$(file_hash "$snapshot_path")"
        elif [[ -L "$snapshot_path" ]]; then
            printf 'link|%s|%s\n' "$snapshot_path" \
                "$(readlink -- "$snapshot_path")"
        else
            printf 'absent|%s\n' "$snapshot_path"
        fi
    done
    systemctl show --property=ActiveState,SubState,UnitFileState \
        pihole-FTL.service unbound.service 2>/dev/null || true
}

verify_stage() {
    local stage_label=$1
    local stage_path=$2
    local candidate_name=$3
    local candidate_hash=$4
    local expected_metadata=$5
    local stage_manifest_status=1
    local stage_entries_text
    local stage_file
    local -a expected_files=(
        .complete manifest.sha256 "$candidate_name" stage.meta
    )

    assert_directory "${stage_label}_stage_directory" "$stage_path"
    assert_equal "${stage_label}_stage_metadata" \
        "$(stat -c '%U:%G:%a' "$stage_path" 2>/dev/null)" root:root:700
    stage_entries_text=$(
        find "$stage_path" -mindepth 1 -maxdepth 1 -printf '%f\n' \
            2>/dev/null |
            LC_ALL=C sort
    )
    assert_equal "${stage_label}_stage_entry_set" \
        "$stage_entries_text" "$(printf '%s\n' "${expected_files[@]}" |
            LC_ALL=C sort)"

    for stage_file in .complete manifest.sha256 "$candidate_name" stage.meta; do
        assert_regular_file \
            "${stage_label}_${stage_file//[.-]/_}_regular" \
            "$stage_path/$stage_file"
        assert_equal \
            "${stage_label}_${stage_file//[.-]/_}_metadata" \
            "$(stat -c '%U:%G:%a' "$stage_path/$stage_file" 2>/dev/null)" \
            root:root:600
    done

    assert_equal "${stage_label}_complete_size" \
        "$(stat -c %s "$stage_path/.complete" 2>/dev/null)" 0
    printf '%s_candidate_sha256=%s\n' \
        "$stage_label" "$(file_hash "$stage_path/$candidate_name")"
    assert_equal "${stage_label}_candidate_hash" \
        "$(file_hash "$stage_path/$candidate_name")" "$candidate_hash"
    assert_equal "${stage_label}_manifest_content" \
        "$(cat "$stage_path/manifest.sha256" 2>/dev/null)" \
        "$candidate_hash  $candidate_name"
    (
        cd "$stage_path" || exit 1
        sha256sum --check --status manifest.sha256
    ) >/dev/null 2>&1
    stage_manifest_status=$?
    printf '%s_manifest_check_status=%s\n' \
        "$stage_label" "$stage_manifest_status"
    assert_equal "${stage_label}_manifest_check" \
        "$stage_manifest_status" 0
    assert_equal "${stage_label}_meta_content" \
        "$(cat "$stage_path/stage.meta" 2>/dev/null)" "$expected_metadata"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_assertion_count" -eq 70 ]]
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-a-action17i-primary ]]
    [[ "$local_zone_stage" == /var/tmp/caddy-unbound-node-a-action17j-local-zone ]]
    printf 'action_17j_a_node_a_dual_stage_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17j_a_remote_reached=true\n'
for required_command in \
    awk cat find grep hostname id readlink sha256sum sort stat systemctl \
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
assert_equal root_active_directive_count \
    "$(active_directives "$live_root" | wc -l)" 1
assert_equal root_include_count \
    "$(active_directives "$live_root" |
        grep -Fxc "$expected_root_include" || true)" 1
assert_equal nonregular_conf_count \
    "$(find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -name '*.conf' ! -type f -printf '.' | wc -c)" 0
assert_regular_file live_primary_regular "$live_primary"
printf 'live_primary_sha256=%s\n' "$(file_hash "$live_primary")"
assert_equal live_primary_hash \
    "$(file_hash "$live_primary")" "$accepted_live_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a:%s' "$live_primary" 2>/dev/null)" \
    root:root:644:33211
assert_absent live_local_zone_absent "$live_local_zone"
assert_absent legacy_local_zone_absent "$legacy_local_zone"
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active
live_parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || live_parser_status=$?
printf 'live_parser_status=%s\n' "$live_parser_status"
assert_equal live_parser_status "$live_parser_status" 0

expected_primary_metadata=$(printf '%s\n' \
    action=17i \
    node_role=node-a \
    artifact=pihole.conf \
    source_sha256="$candidate_primary_sha256" \
    live_activation=false)
readonly expected_primary_metadata
verify_stage primary "$primary_stage" pihole.conf \
    "$candidate_primary_sha256" "$expected_primary_metadata"

expected_local_zone_metadata=$(printf '%s\n' \
    action=17j \
    node_role=node-a \
    artifact=pihole-local-zone.conf \
    source_sha256="$candidate_local_zone_sha256" \
    parent_action=17i \
    parent_sha256="$candidate_primary_sha256" \
    live_activation=false)
readonly expected_local_zone_metadata
verify_stage local_zone "$local_zone_stage" pihole-local-zone.conf \
    "$candidate_local_zone_sha256" "$expected_local_zone_metadata"

assert_equal transaction_residue_count \
    "$(find /var/tmp -mindepth 1 -maxdepth 1 \
        \( -name '.caddy-unbound-node-a-action17i-primary.*' \
        -o -name '.caddy-unbound-node-a-action17j-local-zone.*' \) \
        -print 2>/dev/null |
        wc -l)" 0

combined_parser_status=0
printf 'include-toplevel: "%s"\ninclude-toplevel: "%s"\n' \
    "$primary_stage/pihole.conf" \
    "$local_zone_stage/pihole-local-zone.conf" |
    unbound-checkconf /dev/stdin >/dev/null 2>&1
combined_parser_status=${PIPESTATUS[1]}
printf 'combined_parser_status=%s\n' "$combined_parser_status"
assert_equal combined_parser_status "$combined_parser_status" 0
assert_equal local_zone_local_data_count \
    "$(active_directives "$local_zone_stage/pihole-local-zone.conf" |
        grep -Ec '^local-data:' || true)" 23
assert_equal local_zone_ptr_count \
    "$(active_directives "$local_zone_stage/pihole-local-zone.conf" |
        grep -Ec '^local-data-ptr:' || true)" 20
assert_equal local_zone_absolute_ptr_count \
    "$(active_directives "$local_zone_stage/pihole-local-zone.conf" |
        grep -Ec '^local-data-ptr: "[^ ]+ [^"]+\."$' || true)" 20

live_state_one=$(state_snapshot)
live_state_one_status=$?
live_state_two=$(state_snapshot)
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
assert_equal live_state_one_collected "$live_state_one_status" 0
assert_equal live_state_two_collected "$live_state_two_status" 0
assert_equal live_state_one_accepted \
    "$live_state_one_sha256" "$accepted_live_state_sha256"
assert_equal live_state_two_accepted \
    "$live_state_two_sha256" "$accepted_live_state_sha256"
assert_equal live_state_stable \
    "$live_state_one_sha256" "$live_state_two_sha256"

if [[ "$assertion_count" -ne "$expected_assertion_count" ]]; then
    record_assertion internal_assertion_count false "$assertion_count"
fi

printf 'action_17j_a_assertion_count=%s\n' "$assertion_count"
printf 'action_17j_a_failed_assertion_count=%s\n' \
    "$failed_assertion_count"
printf 'action_17j_a_first_failure=%s\n' "$first_failure"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'

if [[ "$failed_assertion_count" -eq 0 ]]; then
    printf 'action_17j_a_conclusion=dual_stage_and_live_continuity_verified\n'
    printf 'action_17j_a_remote_complete=true\n'
    exit 0
fi
printf 'action_17j_a_conclusion=dual_stage_or_live_continuity_mismatch\n'
printf 'action_17j_a_remote_complete=true\n'
exit 1
