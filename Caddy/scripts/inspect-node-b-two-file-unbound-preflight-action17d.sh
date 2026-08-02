#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly expected_hostname=j1-svpihole00
readonly accepted_live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_root_include='include-toplevel: "/etc/unbound/unbound.conf.d/*.conf"'

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

encode() {
    base64 -w 0
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

normalized_directives() {
    active_directives "$@" |
        awk '$0 != "server:" { print }' |
        LC_ALL=C sort
}

state_snapshot() {
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

metadata_or_unavailable() {
    local path=$1

    if [[ -e "$path" && ! -L "$path" ]]; then
        stat -c '%U:%G:%a:%s' "$path"
    else
        printf 'unavailable\n'
    fi
}

state_for() {
    local path=$1

    if [[ -f "$path" && ! -L "$path" ]]; then
        printf 'regular\n'
    elif [[ -L "$path" ]]; then
        printf 'symlink\n'
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

derive_conclusion() {
    local identity_ok=$1
    local baseline_ok=$2
    local service_ok=$3
    local live_parser_ok=$4
    local topology_ok=$5
    local ownership_ok=$6
    local candidate_equal=$7
    local candidate_parser_ok=$8

    if [[ "$identity_ok" != true || "$baseline_ok" != true ]]; then
        printf 'live_source_drift\n'
    elif [[ "$service_ok" != true || "$live_parser_ok" != true ]]; then
        printf 'service_or_live_parser_not_ready\n'
    elif [[ "$topology_ok" != true ]]; then
        printf 'unsupported_include_topology\n'
    elif [[ "$ownership_ok" != true || "$candidate_equal" != true ]]; then
        printf 'candidate_semantic_drift\n'
    elif [[ "$candidate_parser_ok" != true ]]; then
        printf 'candidate_parser_rejected\n'
    else
        printf 'ready_for_staged_adoption_design\n'
    fi
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$accepted_live_primary_sha256" \
        "$candidate_primary_sha256" \
        "$candidate_local_zone_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    test_dir=$(mktemp -d /tmp/caddy-action17d-inspector-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    printf '%s\n' \
        'server:' \
        '    interface: 127.0.0.1' \
        '    local-data: "host.example. IN A 192.0.2.1"' \
        >"$test_dir/live"
    printf '%s\n' \
        'server:' \
        '    interface: 127.0.0.1' \
        >"$test_dir/primary"
    printf '%s\n' \
        'server:' \
        '    local-data: "host.example. IN A 192.0.2.1"' \
        >"$test_dir/local"
    normalized_directives "$test_dir/live" >"$test_dir/live.normalized"
    normalized_directives \
        "$test_dir/primary" "$test_dir/local" \
        >"$test_dir/candidate.normalized"
    cmp -s "$test_dir/live.normalized" "$test_dir/candidate.normalized"
    [[ "$(derive_conclusion true true true true true true true true)" == ready_for_staged_adoption_design ]]
    [[ "$(derive_conclusion true true true true true true false true)" == candidate_semantic_drift ]]
    [[ "$(derive_conclusion true true true true true true true false)" == candidate_parser_rejected ]]
    printf 'action_17d_node_b_unbound_inspector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --node || "${2:-}" != node-b ||
    "${3:-}" != --stage || $# -ne 4 ]]; then
    printf 'Usage: %s --node node-b --stage /run/caddy-action17d.*\n' \
        "${0##*/}" >&2
    exit 2
fi

readonly stage=$4
[[ "$stage" =~ ^/run/caddy-action17d\.[A-Za-z0-9]+$ ]]
[[ -d "$stage" && ! -L "$stage" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:700 ]]
readonly candidate_primary="$stage/pihole.conf"
readonly candidate_local_zone="$stage/pihole0-local-zone.conf"
for candidate in "$candidate_primary" "$candidate_local_zone"; do
    [[ -f "$candidate" && ! -L "$candidate" ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:600 ]]
done
[[ "$(file_hash "$candidate_primary")" == "$candidate_primary_sha256" ]]
[[ "$(file_hash "$candidate_local_zone")" == "$candidate_local_zone_sha256" ]]

for command in \
    awk base64 cmp comm cp dpkg-query find grep hostname install readlink \
    rm sed sha256sum sort stat systemctl unbound unbound-checkconf wc; do
    command -v "$command" >/dev/null
done
[[ "$(id -u)" -eq 0 ]]
[[ "$PWD" == / ]]

before_state_sha256=$(state_snapshot | sha256sum | awk '{ print $1 }')
readonly before_state_sha256
node_hostname=$(hostname)
readonly node_hostname
identity_matches=false
if [[ "$node_hostname" == "$expected_hostname" ]]; then
    identity_matches=true
fi

live_root_state=$(state_for "$live_root")
live_primary_state=$(state_for "$live_primary")
live_local_zone_state=$(state_for "$live_local_zone")
live_root_sha256=$(hash_or_unavailable "$live_root")
live_primary_sha256=$(hash_or_unavailable "$live_primary")
live_local_zone_sha256=$(hash_or_unavailable "$live_local_zone")
live_primary_metadata=$(metadata_or_unavailable "$live_primary")
baseline_matches=false
if [[ "$live_primary_state" == regular &&
    "$live_primary_sha256" == "$accepted_live_primary_sha256" &&
    "$live_primary_metadata" == root:root:644:34342 &&
    "$live_local_zone_state" == absent ]]; then
    baseline_matches=true
fi

conf_entries=$(
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort
)
conf_entry_count=$(sed '/^$/d' <<<"$conf_entries" | wc -l)
conf_entries_b64=$(printf '%s' "$conf_entries" | encode)
conf_tree_sha256=$(state_snapshot | sha256sum | awk '{ print $1 }')
nonregular_conf_count=$(
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -name '*.conf' ! -type f -printf '.' |
        wc -c
)

root_active="$stage/root-active"
active_directives "$live_root" >"$root_active"
root_active_directive_count=$(wc -l <"$root_active")
root_active_directives_b64=$(encode <"$root_active")
root_include_toplevel_count=$(
    grep -Fxc "$expected_root_include" "$root_active" || true
)
root_include_topology_supported=false
if [[ "$live_root_state" == regular &&
    "$root_active_directive_count" -eq 1 &&
    "$root_include_toplevel_count" -eq 1 &&
    "$nonregular_conf_count" -eq 0 ]]; then
    root_include_topology_supported=true
fi

unbound_package_version=$(
    dpkg-query -W -f='${Version}' unbound 2>/dev/null || true
)
unbound_package_version_b64=$(printf '%s' "$unbound_package_version" | encode)
unbound_binary_version_b64=$(
    unbound -V 2>/dev/null | sed -n '1p' | encode
)
unbound_active=$(systemctl is-active unbound.service 2>/dev/null || true)
unbound_unit_file_state=$(
    systemctl show unbound.service -p UnitFileState --value 2>/dev/null || true
)
pihole_ftl_active=$(
    systemctl is-active pihole-FTL.service 2>/dev/null || true
)
service_state_ready=false
if [[ "$unbound_active" == active && "$pihole_ftl_active" == active ]]; then
    service_state_ready=true
fi

empty_hash=$(printf '' | sha256sum | awk '{ print $1 }')
live_checkconf_stdout="$stage/live-checkconf.out"
live_checkconf_stderr="$stage/live-checkconf.err"
live_checkconf_status=0
unbound-checkconf "$live_root" \
    >"$live_checkconf_stdout" 2>"$live_checkconf_stderr" ||
    live_checkconf_status=$?
live_parser_valid=false
if [[ "$live_checkconf_status" -eq 0 &&
    ! -s "$live_checkconf_stderr" ]]; then
    live_parser_valid=true
fi

candidate_primary_server_count=$(
    active_directives "$candidate_primary" |
        grep -Fxc server: || true
)
candidate_local_zone_server_count=$(
    active_directives "$candidate_local_zone" |
        grep -Fxc server: || true
)
candidate_primary_local_policy_count=$(
    active_directives "$candidate_primary" |
        grep -Ec \
            '^(private-domain|domain-insecure|local-zone|local-data|local-data-ptr):' ||
        true
)
candidate_local_zone_forbidden_count=$(
    active_directives "$candidate_local_zone" |
        awk -F: '
            $1 != "server" &&
            $1 != "private-domain" &&
            $1 != "domain-insecure" &&
            $1 != "local-zone" &&
            $1 != "local-data" &&
            $1 != "local-data-ptr" { count++ }
            END { print count + 0 }
        '
)
ownership_boundary_valid=false
if [[ "$candidate_primary_server_count" -eq 1 &&
    "$candidate_local_zone_server_count" -eq 1 &&
    "$candidate_primary_local_policy_count" -eq 0 &&
    "$candidate_local_zone_forbidden_count" -eq 0 ]]; then
    ownership_boundary_valid=true
fi

live_normalized="$stage/live.normalized"
candidate_normalized="$stage/candidate.normalized"
normalized_directives "$live_primary" >"$live_normalized"
normalized_directives \
    "$candidate_primary" "$candidate_local_zone" \
    >"$candidate_normalized"
live_normalized_count=$(wc -l <"$live_normalized")
candidate_normalized_count=$(wc -l <"$candidate_normalized")
live_normalized_sha256=$(file_hash "$live_normalized")
candidate_normalized_sha256=$(file_hash "$candidate_normalized")
live_only_count=$(
    comm -23 "$live_normalized" "$candidate_normalized" | wc -l
)
candidate_only_count=$(
    comm -13 "$live_normalized" "$candidate_normalized" | wc -l
)
canonical_directives_equal=false
if cmp -s "$live_normalized" "$candidate_normalized"; then
    canonical_directives_equal=true
fi

candidate_validation_attempted=false
candidate_checkconf_status=not_run
candidate_checkconf_stdout_sha256=$empty_hash
candidate_checkconf_stderr_sha256=$empty_hash
candidate_parser_valid=false
if [[ "$root_include_topology_supported" == true ]]; then
    shadow="$stage/shadow"
    install -d -o root -g root -m 0700 "$shadow/conf.d"
    cp -a -- "$live_conf_dir/." "$shadow/conf.d/"
    rm -f -- \
        "$shadow/conf.d/pihole.conf" \
        "$shadow/conf.d/pihole0-local-zone.conf"
    install -o root -g root -m 0600 \
        "$candidate_primary" "$shadow/conf.d/pihole.conf"
    install -o root -g root -m 0600 \
        "$candidate_local_zone" \
        "$shadow/conf.d/pihole0-local-zone.conf"
    printf 'include-toplevel: "%s/*.conf"\n' \
        "$shadow/conf.d" >"$shadow/unbound.conf"
    candidate_checkconf_stdout="$stage/candidate-checkconf.out"
    candidate_checkconf_stderr="$stage/candidate-checkconf.err"
    candidate_checkconf_status=0
    candidate_validation_attempted=true
    unbound-checkconf "$shadow/unbound.conf" \
        >"$candidate_checkconf_stdout" 2>"$candidate_checkconf_stderr" ||
        candidate_checkconf_status=$?
    candidate_checkconf_stdout_sha256=$(
        file_hash "$candidate_checkconf_stdout"
    )
    candidate_checkconf_stderr_sha256=$(
        file_hash "$candidate_checkconf_stderr"
    )
    if [[ "$candidate_checkconf_status" -eq 0 &&
        ! -s "$candidate_checkconf_stderr" ]]; then
        candidate_parser_valid=true
    fi
fi

after_state_sha256=$(state_snapshot | sha256sum | awk '{ print $1 }')
node_state_unchanged=false
if [[ "$after_state_sha256" == "$before_state_sha256" ]]; then
    node_state_unchanged=true
fi
conclusion=$(
    derive_conclusion \
        "$identity_matches" \
        "$baseline_matches" \
        "$service_state_ready" \
        "$live_parser_valid" \
        "$root_include_topology_supported" \
        "$ownership_boundary_valid" \
        "$canonical_directives_equal" \
        "$candidate_parser_valid"
)

printf '%s\n' \
    action_17d_node_b_unbound_preflight_remote_reached=true \
    node_role=node-b \
    "node_hostname=$node_hostname" \
    "node_identity_matches=$identity_matches" \
    "before_state_sha256=$before_state_sha256" \
    "live_root_state=$live_root_state" \
    "live_root_sha256=$live_root_sha256" \
    "live_primary_state=$live_primary_state" \
    "live_primary_sha256=$live_primary_sha256" \
    "live_primary_metadata=$live_primary_metadata" \
    "live_local_zone_state=$live_local_zone_state" \
    "live_local_zone_sha256=$live_local_zone_sha256" \
    "live_baseline_matches=$baseline_matches" \
    "live_conf_entry_count=$conf_entry_count" \
    "live_conf_entries_b64=$conf_entries_b64" \
    "live_conf_tree_sha256=$conf_tree_sha256" \
    "live_nonregular_conf_count=$nonregular_conf_count" \
    "root_active_directive_count=$root_active_directive_count" \
    "root_active_directives_b64=$root_active_directives_b64" \
    "root_include_toplevel_count=$root_include_toplevel_count" \
    "root_include_topology_supported=$root_include_topology_supported" \
    "unbound_package_version_b64=$unbound_package_version_b64" \
    "unbound_binary_version_b64=$unbound_binary_version_b64" \
    "unbound_active=$unbound_active" \
    "unbound_unit_file_state=$unbound_unit_file_state" \
    "pihole_ftl_active=$pihole_ftl_active" \
    "service_state_ready=$service_state_ready" \
    "live_checkconf_status=$live_checkconf_status" \
    "live_checkconf_stdout_sha256=$(file_hash "$live_checkconf_stdout")" \
    "live_checkconf_stderr_sha256=$(file_hash "$live_checkconf_stderr")" \
    "live_parser_valid=$live_parser_valid" \
    "candidate_primary_sha256=$(file_hash "$candidate_primary")" \
    "candidate_local_zone_sha256=$(file_hash "$candidate_local_zone")" \
    "candidate_primary_server_count=$candidate_primary_server_count" \
    "candidate_local_zone_server_count=$candidate_local_zone_server_count" \
    "candidate_primary_local_policy_count=$candidate_primary_local_policy_count" \
    "candidate_local_zone_forbidden_count=$candidate_local_zone_forbidden_count" \
    "ownership_boundary_valid=$ownership_boundary_valid" \
    "live_normalized_directive_count=$live_normalized_count" \
    "candidate_normalized_directive_count=$candidate_normalized_count" \
    "live_normalized_sha256=$live_normalized_sha256" \
    "candidate_normalized_sha256=$candidate_normalized_sha256" \
    "live_only_directive_count=$live_only_count" \
    "candidate_only_directive_count=$candidate_only_count" \
    "canonical_directives_equal=$canonical_directives_equal" \
    "candidate_validation_attempted=$candidate_validation_attempted" \
    "candidate_checkconf_status=$candidate_checkconf_status" \
    "candidate_checkconf_stdout_sha256=$candidate_checkconf_stdout_sha256" \
    "candidate_checkconf_stderr_sha256=$candidate_checkconf_stderr_sha256" \
    "candidate_parser_valid=$candidate_parser_valid" \
    "after_state_sha256=$after_state_sha256" \
    "node_state_unchanged=$node_state_unchanged" \
    "action_17d_node_b_unbound_preflight_conclusion=$conclusion" \
    dns_queries_performed=false \
    dns_configuration_mutations=false \
    service_mutations=false \
    persistent_mutations=false \
    action_17d_node_b_unbound_preflight_inspection_complete=true
