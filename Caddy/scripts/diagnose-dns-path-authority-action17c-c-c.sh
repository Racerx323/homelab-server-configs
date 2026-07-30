#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly zone=local.theama.co
readonly peer_fqdn=pihole00.local.theama.co
readonly peer_ipv4=10.1.0.54
readonly peer_ipv4_ptr=54.0.1.10.in-addr.arpa
readonly peer_ipv4_ptr_target=pihole00.local.theama.co.
readonly caddy_fqdn=pihole-admin.local.theama.co
readonly caddy_ipv4_ptr=56.0.1.10.in-addr.arpa
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly primary_config_file=/etc/unbound/unbound.conf.d/pihole.conf
readonly local_zone_file=/etc/unbound/unbound.conf.d/pihole0-local-zone.conf
readonly resolv_conf=/etc/resolv.conf
readonly unbound_ipv4=127.0.0.1
readonly unbound_port=5335
readonly pihole_ipv4=127.0.0.1
readonly pihole_port=53
readonly configured_ipv4_resolver=10.1.0.1
readonly dns_vip_ipv4=10.1.0.55
readonly dns_vip_ipv6=fd36:5aa8:6971:1::55

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

encode_value() {
    printf '%s' "$1" | base64 -w 0
}

boolean_record() {
    local label=$1
    local status=$2

    if [[ "$status" -eq 0 ]]; then
        printf '%s=true\n' "$label"
    else
        printf '%s=false\n' "$label"
    fi
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

record_file_state() {
    if [[ -f "$primary_config_file" && ! -L "$primary_config_file" ]]; then
        printf 'primary_config_file_state=regular\n'
        printf 'primary_config_file_sha256=%s\n' \
            "$(file_hash "$primary_config_file")"
        printf 'primary_config_file_metadata=%s\n' \
            "$(stat -c '%U:%G:%a:%s' "$primary_config_file")"
    elif [[ -L "$primary_config_file" ]]; then
        printf 'primary_config_file_state=symlink\n'
        printf 'primary_config_file_sha256=unavailable\n'
        printf 'primary_config_file_metadata=%s\n' \
            "$(stat -c '%U:%G:%a:%s' "$primary_config_file")"
    else
        printf 'primary_config_file_state=absent\n'
        printf 'primary_config_file_sha256=unavailable\n'
        printf 'primary_config_file_metadata=unavailable\n'
    fi

    if [[ -f "$local_zone_file" && ! -L "$local_zone_file" ]]; then
        printf 'local_zone_file_state=regular\n'
        printf 'local_zone_file_sha256=%s\n' \
            "$(file_hash "$local_zone_file")"
        printf 'local_zone_file_metadata=%s\n' \
            "$(stat -c '%U:%G:%a:%s' "$local_zone_file")"
    elif [[ -L "$local_zone_file" ]]; then
        printf 'local_zone_file_state=symlink\n'
        printf 'local_zone_file_sha256=unavailable\n'
        printf 'local_zone_file_metadata=%s\n' \
            "$(stat -c '%U:%G:%a:%s' "$local_zone_file")"
    else
        printf 'local_zone_file_state=absent\n'
        printf 'local_zone_file_sha256=unavailable\n'
        printf 'local_zone_file_metadata=unavailable\n'
    fi
}

record_live_source_assertions() {
    local status

    if [[ -f "$primary_config_file" && ! -L "$primary_config_file" ]]; then
        status=0
        grep -Fxq 'server:' "$primary_config_file" || status=$?
        boolean_record live_primary_server_clause_present "$status"
        status=0
        grep -Fxq '    interface: 127.0.0.1' \
            "$primary_config_file" || status=$?
        boolean_record live_primary_ipv4_loopback_present "$status"
        status=0
        grep -Fxq '    interface: ::1' "$primary_config_file" || status=$?
        boolean_record live_primary_ipv6_loopback_present "$status"
        status=0
        grep -Fxq '    port: 5335' "$primary_config_file" || status=$?
        boolean_record live_primary_port_present "$status"
        if grep -Eq \
            '^[[:space:]]*local-zone:[[:space:]]+"local\.theama\.co\."[[:space:]]+static' \
            "$primary_config_file"; then
            printf 'live_primary_contains_local_zone=true\n'
        else
            printf 'live_primary_contains_local_zone=false\n'
        fi
    else
        for label in \
            primary_server_clause_present \
            primary_ipv4_loopback_present \
            primary_ipv6_loopback_present \
            primary_port_present \
            primary_contains_local_zone; do
            printf 'live_%s=unavailable\n' "$label"
        done
    fi

    if [[ ! -f "$local_zone_file" || -L "$local_zone_file" ]]; then
        for label in \
            static_zone_present \
            peer_a_present \
            peer_aaaa_absent \
            peer_ptr_present \
            caddy_names_absent \
            caddy_ipv4_ptr_absent \
            caddy_ipv6_ptr_absent; do
            printf 'live_%s=unavailable\n' "$label"
        done
        return
    fi

    status=0
    grep -Fxq '    local-zone: "local.theama.co." static' \
        "$local_zone_file" || status=$?
    boolean_record live_static_zone_present "$status"

    status=0
    grep -Fxq \
        '    local-data: "pihole00.local.theama.co. IN A 10.1.0.54"' \
        "$local_zone_file" || status=$?
    boolean_record live_peer_a_present "$status"

    if grep -Eq \
        '^[[:space:]]*local-data:[[:space:]]+"pihole00\.local\.theama\.co\.[^"]*[[:space:]]AAAA[[:space:]]' \
        "$local_zone_file"; then
        printf 'live_peer_aaaa_absent=false\n'
    else
        printf 'live_peer_aaaa_absent=true\n'
    fi

    status=0
    grep -Fxq \
        '    local-data-ptr: "10.1.0.54 pihole00.local.theama.co."' \
        "$local_zone_file" || status=$?
    boolean_record live_peer_ptr_present "$status"

    if grep -Eq \
        '^[[:space:]]*local-data:[[:space:]]+"(proxy|pihole-admin)\.local\.theama\.co\.' \
        "$local_zone_file"; then
        printf 'live_caddy_names_absent=false\n'
    else
        printf 'live_caddy_names_absent=true\n'
    fi

    if grep -Eq \
        '^[[:space:]]*local-data-ptr:[[:space:]]+"10\.1\.0\.56[[:space:]]' \
        "$local_zone_file"; then
        printf 'live_caddy_ipv4_ptr_absent=false\n'
    else
        printf 'live_caddy_ipv4_ptr_absent=true\n'
    fi

    if grep -Fq "local-data-ptr: \"$caddy_ipv6 " "$local_zone_file" ||
        grep -Eq \
            '^[[:space:]]*local-data:[[:space:]]+"[^"]*\.ip6\.arpa\.[^"]*[[:space:]]PTR[[:space:]]' \
            "$local_zone_file"; then
        printf 'live_caddy_ipv6_ptr_absent=false\n'
    else
        printf 'live_caddy_ipv6_ptr_absent=true\n'
    fi
}

run_query() {
    local label=$1
    local server=$2
    local port=$3
    local qname=$4
    local qtype=$5
    local expected_value=$6
    local work_dir=$7
    local output="$work_dir/$label.out"
    local error="$work_dir/$label.err"
    local answers="$work_dir/$label.answers"
    local command_status=0
    local rcode=unavailable
    local flags=''
    local answer_count=0
    local expected_present=false
    local class=command_failed

    timeout --signal=TERM 3 \
        dig +time=1 +tries=1 +noall +comments +answer \
        "@$server" -p "$port" "$qname" "$qtype" \
        >"$output" 2>"$error" || command_status=$?

    if [[ "$command_status" -eq 0 ]]; then
        rcode=$(
            sed -n \
                's/^;; ->>HEADER<<- opcode: [^,]*, status: \([^,]*\),.*/\1/p' \
                "$output" | head -1
        )
        [[ -n "$rcode" ]] || rcode=unavailable
        flags=$(
            sed -n 's/^;; flags: \([^;]*\);.*/\1/p' "$output" | head -1
        )
    fi
    awk -v name="${qname%.}." -v type="$qtype" '
        BEGIN {
            IGNORECASE = 1
        }
        $1 == name && $4 == type {
            print $5
        }
    ' "$output" | LC_ALL=C sort -u >"$answers"
    answer_count=$(wc -l <"$answers")

    if [[ "$expected_value" == absent ]]; then
        if [[ "$answer_count" -eq 0 ]]; then
            expected_present=true
        fi
    elif grep -Fxiq "$expected_value" "$answers"; then
        expected_present=true
    fi

    if [[ "$command_status" -eq 124 ]]; then
        class=timed_out
    elif [[ "$command_status" -ne 0 ]]; then
        class=command_failed
    elif [[ "$rcode" == unavailable ]]; then
        class=malformed_response
    elif [[ "$expected_present" == true && "$expected_value" == absent ]]; then
        class=expected_absent
    elif [[ "$expected_present" == true ]]; then
        class=expected_present
    elif [[ "$answer_count" -gt 0 ]]; then
        class=unexpected_answer
    else
        class=expected_answer_missing
    fi

    printf '%s\n' \
        "${label}_server=$server" \
        "${label}_port=$port" \
        "${label}_qname=$qname" \
        "${label}_qtype=$qtype" \
        "${label}_command_status=$command_status" \
        "${label}_rcode=$rcode" \
        "${label}_flags_b64=$(encode_value "$flags")" \
        "${label}_answer_count=$answer_count" \
        "${label}_answers_b64=$(encode_value "$(<"$answers")")" \
        "${label}_expected_match=$expected_present" \
        "${label}_class=$class" \
        "${label}_response_sha256=$(file_hash "$output")" \
        "${label}_stderr_sha256=$(file_hash "$error")"
}

write_fixture() {
    local destination=$1

    printf '%s\n' \
        action_17c_c_c_prestate_complete=true \
        node_role=node-a \
        node_hostname=j1-svpihole0 \
        primary_config_file_state=regular \
        primary_config_file_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
        primary_config_file_metadata=root:root:644:1 \
        local_zone_file_state=regular \
        local_zone_file_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        local_zone_file_metadata=root:root:644:1 \
        live_static_zone_present=true \
        live_primary_server_clause_present=true \
        live_primary_ipv4_loopback_present=true \
        live_primary_ipv6_loopback_present=true \
        live_primary_port_present=true \
        live_primary_contains_local_zone=false \
        live_peer_a_present=true \
        live_peer_aaaa_absent=true \
        live_peer_ptr_present=true \
        live_caddy_names_absent=true \
        live_caddy_ipv4_ptr_absent=true \
        live_caddy_ipv6_ptr_absent=true \
        configured_ipv4_resolver_present=true \
        configured_ipv6_resolver_present=true \
        action_17c_c_c_source_inspection_complete=true \
        action_17c_c_c_query_collection_complete=true \
        after_state_status=0 \
        after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
        after_state_stderr_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
        node_dns_state_unchanged=true \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_c_node_cleanup_complete=true \
        action_17c_c_c_node_diagnostic_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$zone" == local.theama.co ]]
    [[ "$peer_fqdn" == pihole00.local.theama.co ]]
    [[ "$peer_ipv4" == 10.1.0.54 ]]
    [[ "$unbound_port" -eq 5335 ]]
    [[ "$dns_vip_ipv4" == 10.1.0.55 ]]
    [[ "$dns_vip_ipv6" == fd36:5aa8:6971:1::55 ]]
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-collector-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_fixture "$test_dir/fixture"
    grep -Fxq 'live_peer_aaaa_absent=true' "$test_dir/fixture"
    grep -Fxq 'live_caddy_names_absent=true' "$test_dir/fixture"
    printf 'action_17c_c_c_dns_collector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --node || $# -ne 2 ]]; then
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
    exit 2
fi

readonly node_role=$2
case "$node_role" in
    node-a)
        readonly expected_hostname=j1-svpihole0
        ;;
    node-b)
        readonly expected_hostname=j1-svpihole00
        ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 2
        ;;
esac

[[ "$(id -u)" -eq 0 ]]
[[ "$PWD" == / ]]
[[ "$(hostname)" == "$expected_hostname" ]]
for command in awk base64 dig grep head sed sha256sum sort ss stat \
    systemctl timeout wc; do
    command -v "$command" >/dev/null
done
[[ -r "$resolv_conf" ]]

work_dir=$(mktemp -d /run/caddy-action17c-c-c.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

before_state_status=0
state_snapshot >"$work_dir/state-before" 2>"$work_dir/state-before.err" ||
    before_state_status=$?
printf '%s\n' \
    action_17c_c_c_prestate_complete=true \
    "node_role=$node_role" \
    "node_hostname=$(hostname)" \
    "before_state_status=$before_state_status" \
    "before_state_sha256=$(file_hash "$work_dir/state-before")" \
    "before_state_stderr_sha256=$(file_hash "$work_dir/state-before.err")"

record_file_state
record_live_source_assertions
if grep -Fxq "nameserver $configured_ipv4_resolver" "$resolv_conf"; then
    printf 'configured_ipv4_resolver_present=true\n'
else
    printf 'configured_ipv4_resolver_present=false\n'
fi
if grep -Fxq "nameserver $dns_vip_ipv6" "$resolv_conf"; then
    printf 'configured_ipv6_resolver_present=true\n'
else
    printf 'configured_ipv6_resolver_present=false\n'
fi
printf 'action_17c_c_c_source_inspection_complete=true\n'

run_query local_unbound_peer_a \
    "$unbound_ipv4" "$unbound_port" "$peer_fqdn" A "$peer_ipv4" "$work_dir"
run_query local_unbound_peer_aaaa \
    "$unbound_ipv4" "$unbound_port" "$peer_fqdn" AAAA absent "$work_dir"
run_query local_unbound_peer_ptr \
    "$unbound_ipv4" "$unbound_port" "$peer_ipv4_ptr" PTR \
    "$peer_ipv4_ptr_target" "$work_dir"
run_query local_unbound_caddy_a \
    "$unbound_ipv4" "$unbound_port" "$caddy_fqdn" A absent "$work_dir"
run_query local_unbound_caddy_ptr \
    "$unbound_ipv4" "$unbound_port" "$caddy_ipv4_ptr" PTR absent "$work_dir"
run_query local_pihole_peer_a \
    "$pihole_ipv4" "$pihole_port" "$peer_fqdn" A "$peer_ipv4" "$work_dir"

if [[ "$node_role" == node-a ]]; then
    run_query configured_ipv4_peer_a \
        "$configured_ipv4_resolver" 53 "$peer_fqdn" A "$peer_ipv4" "$work_dir"
    run_query dns_vip_ipv4_peer_a \
        "$dns_vip_ipv4" 53 "$peer_fqdn" A "$peer_ipv4" "$work_dir"
    run_query dns_vip_ipv6_peer_a \
        "$dns_vip_ipv6" 53 "$peer_fqdn" A "$peer_ipv4" "$work_dir"
    run_query dns_vip_ipv4_caddy_a \
        "$dns_vip_ipv4" 53 "$caddy_fqdn" A absent "$work_dir"
fi
printf 'action_17c_c_c_query_collection_complete=true\n'

after_state_status=0
state_snapshot >"$work_dir/state-after" 2>"$work_dir/state-after.err" ||
    after_state_status=$?
printf '%s\n' \
    "after_state_status=$after_state_status" \
    "after_state_sha256=$(file_hash "$work_dir/state-after")" \
    "after_state_stderr_sha256=$(file_hash "$work_dir/state-after.err")"
if [[ "$before_state_status" -eq 0 && "$after_state_status" -eq 0 ]] &&
    cmp --silent "$work_dir/state-before" "$work_dir/state-after"; then
    printf 'node_dns_state_unchanged=true\n'
else
    printf 'node_dns_state_unchanged=false\n'
fi
printf '%s\n' \
    dns_configuration_mutations=false \
    service_mutations=false \
    persistent_mutations=false

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf '%s\n' \
    action_17c_c_c_node_cleanup_complete=true \
    action_17c_c_c_node_diagnostic_complete=true
