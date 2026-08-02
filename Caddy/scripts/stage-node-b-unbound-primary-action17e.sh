#!/usr/bin/env bash

set -euo pipefail
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
readonly final_stage=/var/tmp/caddy-unbound-node-b-action17e-primary
readonly later_local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly accepted_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly accepted_live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly accepted_action17d_state_sha256=31862f7b0f86a6cddc9057501fffeff872bc3747a0144bb7d062fddcced9992c
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
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
    ' "$1"
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

validate_baseline() {
    [[ "$(id -u)" -eq 0 ]]
    [[ "$PWD" == / ]]
    [[ "$(hostname)" == "$expected_hostname" ]]
    [[ -f "$live_root" && ! -L "$live_root" ]]
    [[ "$(file_hash "$live_root")" == "$accepted_root_sha256" ]]
    [[ -f "$live_primary" && ! -L "$live_primary" ]]
    [[ "$(file_hash "$live_primary")" == "$accepted_live_primary_sha256" ]]
    [[ "$(stat -c '%U:%G:%a:%s' "$live_primary")" == root:root:644:34342 ]]
    [[ ! -e "$live_local_zone" && ! -L "$live_local_zone" ]]
    [[ "$(action17d_state_snapshot | sha256sum |
        awk '{ print $1 }')" == "$accepted_action17d_state_sha256" ]]
    [[ "$(systemctl is-active unbound.service)" == active ]]
    [[ "$(systemctl is-active pihole-FTL.service)" == active ]]
    unbound-checkconf "$live_root" >/dev/null
    [[ ! -e "$final_stage" && ! -L "$final_stage" ]]
    [[ ! -e "$later_local_zone_stage" && ! -L "$later_local_zone_stage" ]]
    [[ "$(find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-b-action17e-primary.*' -print |
        wc -l)" -eq 0 ]]
}

validate_candidate() {
    local candidate=$1
    local shadow_root=$2
    local server_count local_policy_count

    [[ -f "$candidate" && ! -L "$candidate" ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:600 ]]
    [[ "$(file_hash "$candidate")" == "$candidate_primary_sha256" ]]
    server_count=$(active_directives "$candidate" | grep -Fxc server: || true)
    local_policy_count=$(
        active_directives "$candidate" |
            grep -Ec \
                '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
            true
    )
    [[ "$server_count" -eq 1 ]]
    [[ "$local_policy_count" -eq 0 ]]
    printf 'include-toplevel: "%s"\n' "$candidate" >"$shadow_root"
    chmod 0600 "$shadow_root"
    unbound-checkconf "$shadow_root" >/dev/null
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$accepted_root_sha256" \
        "$accepted_live_primary_sha256" \
        "$accepted_action17d_state_sha256" \
        "$candidate_primary_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$final_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$later_local_zone_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    printf 'action_17e_node_b_unbound_primary_stage_driver_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

transaction_stage=
before_state=
mutation_started=false
transaction_complete=false

rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    set +e
    printf 'action_17e_rollback_started=true\n' >&2
    if [[ -n "$transaction_stage" &&
        (-e "$transaction_stage" || -L "$transaction_stage") ]]; then
        if [[ -d "$transaction_stage" && ! -L "$transaction_stage" ]]; then
            rm -rf -- "$transaction_stage" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    if [[ "$mutation_started" == true &&
        (-e "$final_stage" || -L "$final_stage") ]]; then
        if [[ -d "$final_stage" && ! -L "$final_stage" ]]; then
            rm -rf -- "$final_stage" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    validate_baseline || rollback_failed=true
    if [[ -n "$before_state" && "$(live_state)" != "$before_state" ]]; then
        rollback_failed=true
    fi
    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17e_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17e_rollback_complete=true\n' >&2
    exit "$original_status"
}
trap rollback EXIT

for command in \
    awk chmod chown find grep hostname install mktemp mv readlink rm \
    sha256sum sort stat systemctl tar touch unbound-checkconf wc xargs; do
    command -v "$command" >/dev/null
done

validate_baseline
before_state=$(live_state)
readonly before_state
before_state_sha256=$(
    printf '%s' "$before_state" | sha256sum | awk '{ print $1 }'
)
readonly before_state_sha256
printf 'action_17e_preflight_complete=true\n'
printf 'before_live_state_sha256=%s\n' "$before_state_sha256"
printf 'primary_stage_previously_absent=true\n'
printf 'local_zone_stage_absent=true\n'

transaction_stage=$(mktemp -d \
    /var/tmp/.caddy-unbound-node-b-action17e-primary.XXXXXX)
readonly transaction_stage
mutation_started=true
printf 'action_17e_mutation_started=true\n'

tar -xf - -C "$transaction_stage" \
    --no-same-owner --no-same-permissions
mapfile -t extracted_entries < <(
    find "$transaction_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort
)
[[ "${#extracted_entries[@]}" -eq 1 ]]
[[ "${extracted_entries[0]}" == pihole.conf ]]
chown root:root "$transaction_stage/pihole.conf"
chmod 0600 "$transaction_stage/pihole.conf"
validate_candidate \
    "$transaction_stage/pihole.conf" "$transaction_stage/unbound.conf"
rm -f -- "$transaction_stage/unbound.conf"

printf '%s  pihole.conf\n' "$candidate_primary_sha256" \
    >"$transaction_stage/manifest.sha256"
printf '%s\n' \
    action=17e \
    node_role=node-b \
    artifact=pihole.conf \
    source_sha256="$candidate_primary_sha256" \
    live_activation=false \
    >"$transaction_stage/stage.meta"
touch "$transaction_stage/.complete"
chown root:root \
    "$transaction_stage/manifest.sha256" \
    "$transaction_stage/stage.meta" \
    "$transaction_stage/.complete"
chmod 0600 \
    "$transaction_stage/manifest.sha256" \
    "$transaction_stage/stage.meta" \
    "$transaction_stage/.complete"
chmod 0700 "$transaction_stage"
mv -- "$transaction_stage" "$final_stage"

[[ -d "$final_stage" && ! -L "$final_stage" ]]
[[ "$(stat -c '%U:%G:%a' "$final_stage")" == root:root:700 ]]
[[ "$(find "$final_stage" -mindepth 1 -maxdepth 1 -type f |
    wc -l)" -eq 4 ]]
validate_candidate "$final_stage/pihole.conf" "$final_stage/unbound.conf"
rm -f -- "$final_stage/unbound.conf"
(
    cd "$final_stage"
    sha256sum --check --status manifest.sha256
)
[[ -f "$final_stage/.complete" && ! -L "$final_stage/.complete" ]]
[[ "$(stat -c '%U:%G:%a' "$final_stage/.complete")" == root:root:600 ]]
[[ ! -e "$later_local_zone_stage" && ! -L "$later_local_zone_stage" ]]

after_state=$(live_state)
readonly after_state
after_state_sha256=$(
    printf '%s' "$after_state" | sha256sum | awk '{ print $1 }'
)
readonly after_state_sha256
[[ "$after_state" == "$before_state" ]]

transaction_complete=true
trap - EXIT
printf 'primary_candidate_sha256=%s\n' "$candidate_primary_sha256"
printf 'primary_stage_path=%s\n' "$final_stage"
printf 'primary_stage_owner_mode=root:root:700\n'
printf 'primary_file_owner_mode=root:root:600\n'
printf 'primary_file_parser_valid=true\n'
printf 'primary_ownership_boundary_valid=true\n'
printf 'primary_stage_complete=true\n'
printf 'local_zone_file_staged=false\n'
printf 'live_unbound_configuration_mutated=false\n'
printf 'dns_queries_performed=false\n'
printf 'service_mutations=false\n'
printf 'after_live_state_sha256=%s\n' "$after_state_sha256"
printf 'live_state_unchanged=true\n'
printf 'persistent_mutation_scope=primary_stage_only\n'
printf 'action_17e_node_b_unbound_primary_stage_complete=true\n'
