#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly primary_config_file=/etc/unbound/unbound.conf.d/pihole.conf
readonly local_zone_file=/etc/unbound/unbound.conf.d/pihole0-local-zone.conf
readonly resolv_conf=/etc/resolv.conf
readonly failed_stage_pattern='caddy-action17c-c-c.*'
readonly node_a_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae
readonly node_a_primary_metadata=root:root:644:33211
readonly node_a_prestate_sha256=0c6c2c57bc69b7fb2121a0e810ab9f3a31928bf853eafd5b2098a64d3057e102
readonly node_b_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly node_b_primary_metadata=root:root:644:34342
readonly node_b_prestate_sha256=af5b993ae06da8d4cf0199c046887a9d7c9874f8b0b1a547e854f15f2e765744

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

state_snapshot() {
    local target

    for target in \
        "$primary_config_file" \
        "$local_zone_file" \
        "$resolv_conf" \
        /etc/nsswitch.conf \
        /etc/hosts; do
        if [[ -f "$target" && ! -L "$target" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$target" "$(stat -c '%U:%G:%a:%s' "$target")" \
                "$(file_hash "$target")"
        elif [[ -L "$target" ]]; then
            printf 'link|%s|%s|%s\n' \
                "$target" "$(stat -c '%U:%G:%a' "$target")" \
                "$(readlink -- "$target")"
        else
            printf 'absent|%s\n' "$target"
        fi
    done
    systemctl show \
        --property=ActiveState,SubState,UnitFileState \
        pihole-FTL.service unbound.service 2>/dev/null || true
    ss -H -lunp 2>/dev/null |
        awk '$5 ~ /:(53|5335)$/ { print }' |
        sed -E 's/pid=[0-9]+/pid=PID/g; s/fd=[0-9]+/fd=FD/g' |
        LC_ALL=C sort
}

record_check() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" == "$expected" ]]; then
        printf '%s=true\n' "$label"
    else
        printf '%s=false\n' "$label"
        mismatch_count=$((mismatch_count + 1))
    fi
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$node_a_primary_sha256" \
        "$node_a_prestate_sha256" \
        "$node_b_primary_sha256" \
        "$node_b_prestate_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$node_a_primary_metadata" =~ ^root:root:[0-7]{3,4}:[0-9]+$ ]]
    [[ "$node_b_primary_metadata" =~ ^root:root:[0-7]{3,4}:[0-9]+$ ]]
    [[ "$failed_stage_pattern" == 'caddy-action17c-c-c.*' ]]
    printf 'action_17c_c_c_a_continuity_inspector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --node || $# -ne 2 ]]; then
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly node_role=$2
case "$node_role" in
    node-a)
        readonly expected_hostname=j1-svpihole0
        readonly expected_primary_sha256=$node_a_primary_sha256
        readonly expected_primary_metadata=$node_a_primary_metadata
        readonly expected_prestate_sha256=$node_a_prestate_sha256
        ;;
    node-b)
        readonly expected_hostname=j1-svpihole00
        readonly expected_primary_sha256=$node_b_primary_sha256
        readonly expected_primary_metadata=$node_b_primary_metadata
        readonly expected_prestate_sha256=$node_b_prestate_sha256
        ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 2
        ;;
esac

[[ "$(id -u)" -eq 0 ]]
[[ "$PWD" == / ]]
for command in awk find grep readlink sed sha256sum sort ss stat systemctl wc; do
    command -v "$command" >/dev/null
done

mismatch_count=0
printf '%s\n' \
    action_17c_c_c_a_remote_reached=true \
    "node_role=$node_role" \
    "node_hostname=$(hostname)"

record_check node_hostname_matches "$(hostname)" "$expected_hostname"

failed_stage_count=$(
    find /run -mindepth 1 -maxdepth 1 \
        -name "$failed_stage_pattern" -print 2>/dev/null |
        wc -l
)
printf 'failed_action_stage_count=%s\n' "$failed_stage_count"
record_check failed_action_stage_absent "$failed_stage_count" 0

primary_state=absent
primary_sha256=unavailable
primary_metadata=unavailable
if [[ -f "$primary_config_file" && ! -L "$primary_config_file" ]]; then
    primary_state=regular
    primary_sha256=$(file_hash "$primary_config_file")
    primary_metadata=$(stat -c '%U:%G:%a:%s' "$primary_config_file")
elif [[ -L "$primary_config_file" ]]; then
    primary_state=symlink
fi
printf '%s\n' \
    "primary_config_file_state=$primary_state" \
    "primary_config_file_sha256=$primary_sha256" \
    "primary_config_file_metadata=$primary_metadata"
record_check primary_config_file_state_matches "$primary_state" regular
record_check primary_config_file_sha256_matches \
    "$primary_sha256" "$expected_primary_sha256"
record_check primary_config_file_metadata_matches \
    "$primary_metadata" "$expected_primary_metadata"

local_zone_state=absent
if [[ -f "$local_zone_file" && ! -L "$local_zone_file" ]]; then
    local_zone_state=regular
elif [[ -L "$local_zone_file" ]]; then
    local_zone_state=symlink
fi
printf 'local_zone_file_state=%s\n' "$local_zone_state"
record_check local_zone_file_absent "$local_zone_state" absent

record_check primary_server_clause_present \
    "$(grep -Fxc 'server:' "$primary_config_file" 2>/dev/null || true)" 1
record_check primary_ipv4_loopback_present \
    "$(grep -Fxc '    interface: 127.0.0.1' "$primary_config_file" 2>/dev/null || true)" 1
record_check primary_ipv6_loopback_present \
    "$(grep -Fxc '    interface: ::1' "$primary_config_file" 2>/dev/null || true)" 1
record_check primary_port_present \
    "$(grep -Fxc '    port: 5335' "$primary_config_file" 2>/dev/null || true)" 1
local_zone_directive_count=$(
    grep -Ec \
        '^[[:space:]]*local-zone:[[:space:]]+"local\.theama\.co\."[[:space:]]+static' \
        "$primary_config_file" 2>/dev/null || true
)
record_check primary_contains_local_zone "$local_zone_directive_count" 1

record_check unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null || true)" active
record_check pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null || true)" active

continuity_state_sha256=$(state_snapshot | sha256sum | awk '{ print $1 }')
printf '%s\n' \
    "expected_prestate_sha256=$expected_prestate_sha256" \
    "continuity_state_sha256=$continuity_state_sha256"
record_check continuity_state_matches_failed_prestate \
    "$continuity_state_sha256" "$expected_prestate_sha256"

printf '%s\n' \
    "action_17c_c_c_a_mismatch_count=$mismatch_count" \
    dns_queries_performed=false \
    dns_configuration_mutations=false \
    service_mutations=false \
    persistent_mutations=false \
    remote_write_paths_created=false \
    remote_stage_cleanup_not_required=true \
    action_17c_c_c_a_continuity_inspection_complete=true

if [[ "$mismatch_count" -ne 0 ]]; then
    exit 1
fi
