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
readonly final_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly accepted_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly accepted_live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8

current_assertion=not_started

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
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

mark_passed() {
    printf 'exact_assertion_%s=true\n' "$current_assertion"
    printf 'exact_assertion_%s_status=0\n' "$current_assertion"
}

validate_primary_stage_labeled() {
    local entry_index path
    local -a entries
    local -a file_labels=(complete manifest candidate meta)
    local -a file_paths=(
        "$primary_stage/.complete"
        "$primary_stage/manifest.sha256"
        "$primary_stage/pihole.conf"
        "$primary_stage/stage.meta"
    )

    current_assertion=primary_stage_directory
    [[ -d "$primary_stage" && ! -L "$primary_stage" ]]
    mark_passed
    current_assertion=primary_stage_metadata
    [[ "$(stat -c '%U:%G:%a' "$primary_stage")" == root:root:700 ]]
    mark_passed
    current_assertion=primary_stage_entry_collection
    mapfile -t entries < <(
        find "$primary_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
            LC_ALL=C sort
    )
    mark_passed
    current_assertion=primary_stage_entry_count
    [[ "${#entries[@]}" -eq 4 ]]
    mark_passed
    for entry_index in 0 1 2 3; do
        current_assertion="primary_stage_entry_${entry_index}"
        [[ "${entries[$entry_index]}" == "${file_paths[$entry_index]##*/}" ]]
        mark_passed
    done
    for entry_index in 0 1 2 3; do
        path=${file_paths[$entry_index]}
        current_assertion="primary_${file_labels[$entry_index]}_regular"
        [[ -f "$path" && ! -L "$path" ]]
        mark_passed
        current_assertion="primary_${file_labels[$entry_index]}_metadata"
        [[ "$(stat -c '%U:%G:%a' "$path")" == root:root:600 ]]
        mark_passed
    done
    current_assertion=primary_complete_empty
    [[ ! -s "$primary_stage/.complete" ]]
    mark_passed
    current_assertion=primary_candidate_hash
    [[ "$(file_hash "$primary_stage/pihole.conf")" == "$candidate_primary_sha256" ]]
    mark_passed
    current_assertion=primary_manifest_content
    [[ "$(cat "$primary_stage/manifest.sha256")" == "$candidate_primary_sha256  pihole.conf" ]]
    mark_passed
    current_assertion=primary_manifest_check
    (
        cd "$primary_stage"
        sha256sum --check --status manifest.sha256
    )
    mark_passed
    current_assertion=primary_meta_content
    [[ "$(cat "$primary_stage/stage.meta")" == "$(printf '%s\n' \
        action=17e \
        node_role=node-b \
        artifact=pihole.conf \
        source_sha256="$candidate_primary_sha256" \
        live_activation=false)" ]]
    mark_passed
}

validate_baseline_labeled() {
    local state_hash

    current_assertion=baseline_uid_root
    [[ "$(id -u)" -eq 0 ]]
    mark_passed
    current_assertion=baseline_pwd_root
    [[ "$PWD" == / ]]
    mark_passed
    current_assertion=baseline_hostname
    [[ "$(hostname)" == "$expected_hostname" ]]
    mark_passed
    current_assertion=baseline_live_root_regular
    [[ -f "$live_root" && ! -L "$live_root" ]]
    mark_passed
    current_assertion=baseline_live_root_hash
    [[ "$(file_hash "$live_root")" == "$accepted_root_sha256" ]]
    mark_passed
    current_assertion=baseline_live_primary_regular
    [[ -f "$live_primary" && ! -L "$live_primary" ]]
    mark_passed
    current_assertion=baseline_live_primary_hash
    [[ "$(file_hash "$live_primary")" == "$accepted_live_primary_sha256" ]]
    mark_passed
    current_assertion=baseline_live_primary_metadata
    [[ "$(stat -c '%U:%G:%a:%s' "$live_primary")" == root:root:644:34342 ]]
    mark_passed
    current_assertion=baseline_live_local_zone_absent
    [[ ! -e "$live_local_zone" && ! -L "$live_local_zone" ]]
    mark_passed
    validate_primary_stage_labeled
    current_assertion=baseline_local_zone_stage_absent
    [[ ! -e "$final_stage" && ! -L "$final_stage" ]]
    mark_passed
    current_assertion=baseline_transaction_count_zero
    [[ "$(find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17f-local-zone.*' -print |
        wc -l)" -eq 0 ]]
    mark_passed
    current_assertion=baseline_unbound_active
    [[ "$(systemctl is-active unbound.service)" == active ]]
    mark_passed
    current_assertion=baseline_pihole_ftl_active
    [[ "$(systemctl is-active pihole-FTL.service)" == active ]]
    mark_passed
    current_assertion=baseline_live_parser
    unbound-checkconf "$live_root" >/dev/null
    mark_passed
    current_assertion=baseline_live_state_collection
    state_hash=$(live_state | sha256sum | awk '{ print $1 }')
    mark_passed
    current_assertion=baseline_live_state_hash
    [[ "$state_hash" == "$accepted_live_state_sha256" ]]
    mark_passed
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$final_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    printf 'action_17f_b_retry_labeled_trace_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17f_b_retry_trace_remote_reached=true\n'
set +e
(
    set -euo pipefail
    trap 'printf "exact_assertion_%s=false\nexact_assertion_%s_status=%s\n" "$current_assertion" "$current_assertion" "$?" >&2' ERR
    validate_baseline_labeled
    trap - ERR
    printf 'action_17f_b_retry_exact_baseline_complete=true\n'
)
exact_status=$?
set -e

printf 'action_17f_b_retry_exact_baseline_status=%s\n' "$exact_status"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
printf 'action_17f_b_retry_labeled_trace_complete=true\n'
