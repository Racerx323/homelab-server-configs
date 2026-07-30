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

validate_primary_stage() {
    local -a entries

    [[ -d "$primary_stage" && ! -L "$primary_stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$primary_stage")" == root:root:700 ]]
    mapfile -t entries < <(
        find "$primary_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
            LC_ALL=C sort
    )
    [[ "${#entries[@]}" -eq 4 ]]
    [[ "${entries[0]}" == .complete ]]
    [[ "${entries[1]}" == manifest.sha256 ]]
    [[ "${entries[2]}" == pihole.conf ]]
    [[ "${entries[3]}" == stage.meta ]]
    for path in \
        "$primary_stage/.complete" \
        "$primary_stage/manifest.sha256" \
        "$primary_stage/pihole.conf" \
        "$primary_stage/stage.meta"; do
        [[ -f "$path" && ! -L "$path" ]]
        [[ "$(stat -c '%U:%G:%a' "$path")" == root:root:600 ]]
    done
    [[ ! -s "$primary_stage/.complete" ]]
    [[ "$(file_hash "$primary_stage/pihole.conf")" == "$candidate_primary_sha256" ]]
    [[ "$(cat "$primary_stage/manifest.sha256")" == "$candidate_primary_sha256  pihole.conf" ]]
    (
        cd "$primary_stage"
        sha256sum --check --status manifest.sha256
    )
    [[ "$(cat "$primary_stage/stage.meta")" == "$(printf '%s\n' \
        action=17e \
        node_role=node-b \
        artifact=pihole.conf \
        source_sha256="$candidate_primary_sha256" \
        live_activation=false)" ]]
}

validate_baseline() {
    local state_hash

    [[ "$(id -u)" -eq 0 ]]
    [[ "$PWD" == / ]]
    [[ "$(hostname)" == "$expected_hostname" ]]
    [[ -f "$live_root" && ! -L "$live_root" ]]
    [[ "$(file_hash "$live_root")" == "$accepted_root_sha256" ]]
    [[ -f "$live_primary" && ! -L "$live_primary" ]]
    [[ "$(file_hash "$live_primary")" == "$accepted_live_primary_sha256" ]]
    [[ "$(stat -c '%U:%G:%a:%s' "$live_primary")" == root:root:644:34342 ]]
    [[ ! -e "$live_local_zone" && ! -L "$live_local_zone" ]]
    validate_primary_stage
    [[ ! -e "$final_stage" && ! -L "$final_stage" ]]
    [[ "$(find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17f-local-zone.*' -print |
        wc -l)" -eq 0 ]]
    [[ "$(systemctl is-active unbound.service)" == active ]]
    [[ "$(systemctl is-active pihole-FTL.service)" == active ]]
    unbound-checkconf "$live_root" >/dev/null
    state_hash=$(live_state | sha256sum | awk '{ print $1 }')
    [[ "$state_hash" == "$accepted_live_state_sha256" ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$final_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    printf 'action_17f_b_transition_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_17f_b_remote_reached=true\n'
printf 'working_directory_is_root=%s\n' \
    "$([[ "$PWD" == / ]] && printf true || printf false)"

validate_baseline
validate_baseline_status=$?
printf 'transition_validate_baseline_status=%s\n' "$validate_baseline_status"

transition_snapshot=$(live_state)
live_state_assignment_status=$?
printf 'transition_live_state_assignment_status=%s\n' \
    "$live_state_assignment_status"
printf 'transition_snapshot_bytes=%s\n' \
    "$(printf '%s' "$transition_snapshot" | wc -c)"

readonly transition_snapshot
snapshot_readonly_status=$?
printf 'transition_snapshot_readonly_status=%s\n' \
    "$snapshot_readonly_status"

transition_snapshot_sha256=$(
    printf '%s' "$transition_snapshot" | sha256sum | awk '{ print $1 }'
)
snapshot_hash_status=$?
printf 'transition_snapshot_hash_status=%s\n' "$snapshot_hash_status"
printf 'transition_snapshot_sha256=%s\n' "$transition_snapshot_sha256"

readonly transition_snapshot_sha256
snapshot_hash_readonly_status=$?
printf 'transition_snapshot_hash_readonly_status=%s\n' \
    "$snapshot_hash_readonly_status"

set +e
(
    set -Eeuo pipefail
    exact_step=validate_baseline
    trap 'printf "transition_exact_failure_step=%s\ntransition_exact_failure_status=%s\n" "$exact_step" "$?" >&2' ERR

    validate_baseline
    printf 'transition_exact_validate_baseline_status=0\n'

    exact_step=live_state_assignment
    before_state=$(live_state)
    printf 'transition_exact_live_state_assignment_status=0\n'

    exact_step=snapshot_readonly
    readonly before_state
    printf 'transition_exact_snapshot_readonly_status=0\n'

    exact_step=snapshot_hash
    before_state_sha256=$(
        printf '%s' "$before_state" | sha256sum | awk '{ print $1 }'
    )
    printf 'transition_exact_snapshot_hash_status=0\n'

    exact_step=snapshot_hash_readonly
    readonly before_state_sha256
    printf 'transition_exact_snapshot_hash_readonly_status=0\n'
    printf 'transition_exact_snapshot_sha256=%s\n' "$before_state_sha256"

    trap - ERR
    printf 'transition_exact_block_complete=true\n'
)
exact_block_status=$?
set -e

printf 'transition_exact_block_status=%s\n' "$exact_block_status"
printf 'remote_paths_created=false\n'
printf 'dns_queries_performed=false\n'
printf 'dns_configuration_mutations=false\n'
printf 'service_mutations=false\n'
printf 'persistent_mutations=false\n'
printf 'action_17f_b_transition_diagnostic_complete=true\n'
