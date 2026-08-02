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
readonly primary_stage=/var/tmp/caddy-unbound-node-b-action17e-primary
readonly final_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly accepted_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly accepted_live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly accepted_live_state_sha256=3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1

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

validate_local_zone_candidate() {
    local candidate=$1
    local server_count local_policy_count forbidden_count

    [[ -f "$candidate" && ! -L "$candidate" ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:600 ]]
    [[ "$(file_hash "$candidate")" == "$candidate_local_zone_sha256" ]]
    server_count=$(active_directives "$candidate" | grep -Fxc server: || true)
    local_policy_count=$(
        active_directives "$candidate" |
            grep -Ec \
                '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
            true
    )
    forbidden_count=$(
        active_directives "$candidate" |
            grep -Ec \
                '^(interface|port|access-control|forward-zone|forward-addr):' ||
            true
    )
    [[ "$server_count" -eq 1 ]]
    [[ "$local_policy_count" -eq 46 ]]
    [[ "$forbidden_count" -eq 0 ]]
}

validate_combined_pair() {
    local local_zone_candidate=$1
    local scratch=$2

    install -d -o root -g root -m 0700 "$scratch/conf.d"
    install -o root -g root -m 0600 \
        "$primary_stage/pihole.conf" "$scratch/conf.d/pihole.conf"
    install -o root -g root -m 0600 \
        "$local_zone_candidate" "$scratch/conf.d/pihole0-local-zone.conf"
    printf 'include-toplevel: "%s/*.conf"\n' \
        "$scratch/conf.d" >"$scratch/unbound.conf"
    chown root:root "$scratch/unbound.conf"
    chmod 0600 "$scratch/unbound.conf"
    unbound-checkconf "$scratch/unbound.conf" >/dev/null
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$accepted_root_sha256" \
        "$accepted_live_primary_sha256" \
        "$accepted_live_state_sha256" \
        "$candidate_primary_sha256" \
        "$candidate_local_zone_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-b-action17e-primary ]]
    [[ "$final_stage" == /var/tmp/caddy-unbound-node-b-action17f-local-zone ]]
    printf 'action_17f_node_b_unbound_local_zone_stage_driver_self_test_complete=true\n'
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

    if [[ "$mutation_started" == false && -z "$transaction_stage" ]]; then
        printf 'action_17f_prewrite_failure_before_mutation=true\n' >&2
        exit "$original_status"
    fi

    set +e
    printf 'action_17f_rollback_started=true\n' >&2
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
        printf 'action_17f_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17f_rollback_complete=true\n' >&2
    exit "$original_status"
}
trap rollback EXIT

for command in \
    awk base64 cat chmod chown find grep hostname install mapfile mktemp mv \
    readlink rm sha256sum sort stat systemctl tar touch unbound-checkconf wc \
    xargs; do
    command -v "$command" >/dev/null
done

validate_baseline
before_state=$(live_state)
readonly before_state
before_state_sha256=$(
    printf '%s' "$before_state" | sha256sum | awk '{ print $1 }'
)
readonly before_state_sha256
printf 'action_17f_preflight_complete=true\n'
printf 'before_live_state_sha256=%s\n' "$before_state_sha256"
printf 'primary_stage_accepted=true\n'
printf 'local_zone_stage_previously_absent=true\n'

transaction_stage=$(mktemp -d \
    /var/tmp/.caddy-unbound-node-b-action17f-local-zone.XXXXXX)
readonly transaction_stage
mutation_started=true
printf 'action_17f_mutation_started=true\n'

tar -xf - -C "$transaction_stage" \
    --no-same-owner --no-same-permissions
mapfile -t extracted_entries < <(
    find "$transaction_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort
)
[[ "${#extracted_entries[@]}" -eq 1 ]]
[[ "${extracted_entries[0]}" == pihole0-local-zone.conf ]]
chown root:root "$transaction_stage/pihole0-local-zone.conf"
chmod 0600 "$transaction_stage/pihole0-local-zone.conf"
validate_local_zone_candidate \
    "$transaction_stage/pihole0-local-zone.conf"
validate_combined_pair \
    "$transaction_stage/pihole0-local-zone.conf" \
    "$transaction_stage/shadow"
rm -rf -- "$transaction_stage/shadow"

printf '%s  pihole0-local-zone.conf\n' "$candidate_local_zone_sha256" \
    >"$transaction_stage/manifest.sha256"
printf '%s\n' \
    action=17f \
    node_role=node-b \
    artifact=pihole0-local-zone.conf \
    source_sha256="$candidate_local_zone_sha256" \
    requires_action17e_primary_sha256="$candidate_primary_sha256" \
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
validate_local_zone_candidate "$final_stage/pihole0-local-zone.conf"
(
    cd "$final_stage"
    sha256sum --check --status manifest.sha256
)
[[ -f "$final_stage/.complete" && ! -L "$final_stage/.complete" ]]
[[ "$(stat -c '%U:%G:%a' "$final_stage/.complete")" == root:root:600 ]]
validate_primary_stage

after_state=$(live_state)
readonly after_state
after_state_sha256=$(
    printf '%s' "$after_state" | sha256sum | awk '{ print $1 }'
)
readonly after_state_sha256
[[ "$after_state" == "$before_state" ]]

transaction_complete=true
trap - EXIT
printf 'local_zone_candidate_sha256=%s\n' "$candidate_local_zone_sha256"
printf 'local_zone_stage_path=%s\n' "$final_stage"
printf 'local_zone_stage_owner_mode=root:root:700\n'
printf 'local_zone_file_owner_mode=root:root:600\n'
printf 'primary_stage_still_valid=true\n'
printf 'combined_pair_parser_valid=true\n'
printf 'local_zone_ownership_boundary_valid=true\n'
printf 'local_zone_stage_complete=true\n'
printf 'live_unbound_configuration_mutated=false\n'
printf 'dns_queries_performed=false\n'
printf 'service_mutations=false\n'
printf 'after_live_state_sha256=%s\n' "$after_state_sha256"
printf 'live_state_unchanged=true\n'
printf 'persistent_mutation_scope=local_zone_stage_only\n'
printf 'action_17f_node_b_unbound_local_zone_stage_complete=true\n'
