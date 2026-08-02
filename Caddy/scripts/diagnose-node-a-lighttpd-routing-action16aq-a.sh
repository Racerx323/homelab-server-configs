#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly lighttpd_root=/etc/lighttpd
readonly lighttpd_config=/etc/lighttpd/lighttpd.conf
readonly lighttpd_enabled=/etc/lighttpd/conf-enabled
readonly caddy_current=/etc/caddy/current
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_admin=http://127.0.0.1:2019
readonly node_fqdn=pihole0.local.theama.co
readonly node_ipv4=10.1.0.53
readonly unknown_fqdn=unexpected.local.theama.co

probe_header_count=0

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/[|]/%7C/g'
}

collect_lines() {
    local prefix=$1
    local content=$2
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        printf '%s=%s\n' "$prefix" \
            "$(printf '%s' "$line" | sanitize_line)"
    done <<<"$content"
}

route_summary() {
    jq -c '
        to_entries[] as $server
        | ($server.value.routes // [])
        | to_entries[]
        | {
            server: $server.key,
            index: .key,
            listen: ($server.value.listen // []),
            hosts: ([.value.match[]?.host[]?] | sort),
            terminal: (.value.terminal // false),
            handlers: [.value.handle[]? | (.handler // "nested")]
        }
    '
}

run_probe() {
    local label=$1
    local url=$2
    local resolve_record=$3
    local host_header=$4
    local output status meta headers header
    local -a host_args=()

    if [[ "$host_header" != none ]]; then
        host_args=(--header "Host: $host_header")
    fi
    output=$(
        curl --noproxy '*' --insecure --silent --show-error \
            --connect-timeout 1 --max-time 4 \
            --resolve "$resolve_record" \
            "${host_args[@]}" \
            --dump-header - --output /dev/null \
            --write-out $'\n__META__%{http_code}|%{remote_ip}|%{http_version}|%{num_redirects}|%{size_download}|%{content_type}\n' \
            "$url" 2>/dev/null
    )
    status=$?
    meta=$(
        sed -n 's/^__META__//p' <<<"$output" |
            tail -n 1 |
            sanitize_line
    )
    printf 'probe_record=%s|%s|%s\n' "$label" "$status" "${meta:-missing}"

    headers=$(
        sed '/^__META__/,$d' <<<"$output" |
            awk '
                BEGIN { IGNORECASE = 1 }
                /^HTTP\// ||
                /^(server|location|content-type|content-length):/ {
                    print
                }
            '
    )
    while IFS= read -r header; do
        [[ -n "$header" ]] || continue
        ((probe_header_count += 1))
        printf 'probe_header_record=%s|%s\n' "$label" \
            "$(printf '%s' "$header" | sanitize_line)"
    done <<<"$headers"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$(printf ' a|b  c ' | sanitize_line)" == 'a%7Cb c' ]]
    sample_routes='{"srv0":{"listen":[":443"],"routes":[{"match":[{"host":["example.test"]}],"handle":[{"handler":"static_response"}]}]}}'
    [[ "$(route_summary <<<"$sample_routes")" == '{"server":"srv0","index":0,"listen":[":443"],"hosts":["example.test"],"terminal":false,"handlers":["static_response"]}' ]]
    printf 'action_16aq_a_lighttpd_routing_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16aq_a_remote_reached=true\n'
printf 'node_hostname=%s\n' "$(hostname 2>/dev/null | sanitize_line)"
printf 'node_architecture=%s\n' \
    "$(dpkg --print-architecture 2>/dev/null | sanitize_line)"

for command_name in \
    awk caddy curl dpkg find grep hostname jq lighttpd readlink sed ss \
    stat systemctl tail; do
    command -v "$command_name" >/dev/null 2>&1
    printf 'command_status=%s|%s\n' "$command_name" "$?"
done
printf 'command_record_count=15\n'

lighttpd -tt -f "$lighttpd_config" >/dev/null 2>&1
printf 'lighttpd_native_parse_status=%s\n' "$?"

directive_output=$(
    grep -RInE \
        '^[[:space:]]*(server[.](bind|port)|ssl[.]engine)[[:space:]]*=' \
        "$lighttpd_root" 2>/dev/null || true
)
directive_output=${directive_output//"$lighttpd_root/"/}
directive_count=$(grep -c . <<<"$directive_output")
if [[ -z "$directive_output" ]]; then
    directive_count=0
fi
printf 'lighttpd_directive_record_count=%s\n' "$directive_count"
collect_lines lighttpd_directive_record "$directive_output"

include_output=$(
    grep -nE '^[[:space:]]*include(_shell)?[[:space:]]' \
        "$lighttpd_config" 2>/dev/null || true
)
include_count=$(grep -c . <<<"$include_output")
if [[ -z "$include_output" ]]; then
    include_count=0
fi
printf 'lighttpd_include_record_count=%s\n' "$include_count"
collect_lines lighttpd_include_record "$include_output"

enabled_output=$(
    find "$lighttpd_enabled" -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%l\n' 2>/dev/null |
        sort
)
enabled_count=$(grep -c . <<<"$enabled_output")
if [[ -z "$enabled_output" ]]; then
    enabled_count=0
fi
printf 'lighttpd_enabled_record_count=%s\n' "$enabled_count"
collect_lines lighttpd_enabled_record "$enabled_output"

effective_output=$(
    lighttpd -p -f "$lighttpd_config" 2>/dev/null
)
effective_status=$?
printf 'lighttpd_effective_print_status=%s\n' "$effective_status"
effective_output=$(
    grep -nE \
        '^[[:space:]]*(server[.](bind|port)|ssl[.]engine)[[:space:]]*=' \
        <<<"$effective_output" 2>/dev/null || true
)
effective_count=$(grep -c . <<<"$effective_output")
if [[ -z "$effective_output" ]]; then
    effective_count=0
fi
printf 'lighttpd_effective_record_count=%s\n' "$effective_count"
collect_lines lighttpd_effective_record "$effective_output"

listener_output=$(
    ss -H -lntp 'sport = :8080' 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
)
listener_count=$(grep -c . <<<"$listener_output")
if [[ -z "$listener_output" ]]; then
    listener_count=0
fi
printf 'lighttpd_listener_record_count=%s\n' "$listener_count"
collect_lines lighttpd_listener_record "$listener_output"

adapted_json=$(
    (
        set -a
        # shellcheck disable=SC1090
        source "$caddy_environment"
        set +a
        caddy adapt --config "$caddy_current/Caddyfile" \
            --adapter caddyfile
    ) 2>/dev/null
)
adapted_status=$?
printf 'caddy_adapt_status=%s\n' "$adapted_status"
adapted_routes=$(
    jq -c '.apps.http.servers' <<<"$adapted_json" 2>/dev/null |
        route_summary 2>/dev/null
)
adapted_route_status=$?
adapted_route_count=$(grep -c . <<<"$adapted_routes")
if [[ -z "$adapted_routes" ]]; then
    adapted_route_count=0
fi
printf 'adapted_route_status=%s\n' "$adapted_route_status"
printf 'adapted_route_record_count=%s\n' "$adapted_route_count"
collect_lines adapted_route_record "$adapted_routes"

runtime_json=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/config/apps/http/servers" 2>/dev/null
)
runtime_status=$?
printf 'runtime_config_status=%s\n' "$runtime_status"
runtime_routes=$(
    route_summary <<<"$runtime_json" 2>/dev/null
)
runtime_route_status=$?
runtime_route_count=$(grep -c . <<<"$runtime_routes")
if [[ -z "$runtime_routes" ]]; then
    runtime_route_count=0
fi
printf 'runtime_route_status=%s\n' "$runtime_route_status"
printf 'runtime_route_record_count=%s\n' "$runtime_route_count"
collect_lines runtime_route_record "$runtime_routes"

printf 'probe_record_count=5\n'
run_probe unknown_default \
    "https://$unknown_fqdn/" "$unknown_fqdn:443:$node_ipv4" none
run_probe known_default \
    "https://$node_fqdn/" "$node_fqdn:443:$node_ipv4" none
run_probe known_sni_unknown_host \
    "https://$node_fqdn/" "$node_fqdn:443:$node_ipv4" "$unknown_fqdn"
run_probe unknown_sni_known_host \
    "https://$unknown_fqdn/" "$unknown_fqdn:443:$node_ipv4" "$node_fqdn"
run_probe ip_sni_unknown_host \
    "https://$node_ipv4/" "$node_ipv4:443:$node_ipv4" "$unknown_fqdn"
printf 'probe_header_record_count=%s\n' "$probe_header_count"

printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
printf 'action_16aq_a_lighttpd_routing_diagnostic_complete=true\n'
