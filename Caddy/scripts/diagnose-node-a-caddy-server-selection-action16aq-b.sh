#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly caddy_admin=http://127.0.0.1:2019
readonly node_fqdn=pihole0.local.theama.co
readonly node_ipv4=10.1.0.53
readonly unknown_fqdn=unexpected.local.theama.co
readonly target_listener=10.1.0.53:443
readonly wildcard_listener=:443

sanitize_line() {
    tr '\t\r\n' '   ' |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/[|]/%7C/g'
}

server_summary() {
    jq -c \
        --arg target "$target_listener" \
        --arg wildcard "$wildcard_listener" '
        to_entries[]
        | .key as $server
        | (.value.listen // []) as $listen
        | ([.value.routes[]?.match[]?.host[]?] | unique | sort) as $hosts
        | {
            server: $server,
            listen: $listen,
            exact_target: any($listen[]?; . == $target),
            wildcard_target: any($listen[]?; . == $wildcard),
            hosts: $hosts,
            hostless_static_421: any(
                .value.routes[]?;
                ([.match[]?.host[]?] | length) == 0
                and any(
                    .handle[]?;
                    .handler == "static_response"
                    and (.status_code // 200) == 421
                )
            )
        }
    '
}

metric_rows() {
    local method=$1
    local host=$2

    awk -v wanted_method="$method" -v wanted_host="$host" '
        function label_value(labels, wanted, fields, pair, count, i, key, value) {
            count = split(labels, fields, ",")
            for (i = 1; i <= count; i++) {
                split(fields[i], pair, "=")
                key = pair[1]
                value = substr(fields[i], length(key) + 2)
                gsub(/^"|"$/, "", value)
                if (key == wanted) {
                    return value
                }
            }
            return ""
        }

        /^caddy_http_request_duration_seconds_count[{]/ {
            labels = $0
            sub(/^[^{]+[{]/, "", labels)
            sub(/[}].*$/, "", labels)
            value = $NF
            method = label_value(labels, "method")
            host = label_value(labels, "host")
            if (method == wanted_method && host == wanted_host) {
                server = label_value(labels, "server")
                handler = label_value(labels, "handler")
                code = label_value(labels, "code")
                if (server ~ /^srv[0-9]+$/ &&
                    handler ~ /^[A-Za-z0-9_.-]+$/ &&
                    code ~ /^[0-9][0-9][0-9]$/ &&
                    value ~ /^[0-9]+([.][0-9]+)?$/) {
                    print server "|" handler "|" host "|" code "|" value
                }
            }
        }
    ' | sort -u
}

metric_deltas() {
    local before=$1
    local after=$2

    {
        while IFS= read -r row; do
            [[ -n "$row" ]] && printf 'before|%s\n' "$row"
        done <<<"$before"
        while IFS= read -r row; do
            [[ -n "$row" ]] && printf 'after|%s\n' "$row"
        done <<<"$after"
    } |
        awk -F '|' '
            $1 == "before" {
                key = $2 FS $3 FS $4 FS $5
                before[key] = $6
            }
            $1 == "after" {
                key = $2 FS $3 FS $4 FS $5
                after[key] = $6
            }
            END {
                for (key in after) {
                    delta = after[key] - before[key]
                    if (delta > 0) {
                        print key FS delta
                    }
                }
            }
        ' | sort
}

run_probe() {
    local method=$1
    local fqdn=$2
    local output status metadata
    local -a request_args

    if [[ "$method" == HEAD ]]; then
        request_args=(--head)
    else
        request_args=(--request "$method" --dump-header - --output /dev/null)
    fi

    output=$(
        curl --noproxy '*' --insecure --silent --show-error \
            "${request_args[@]}" \
            --connect-timeout 1 --max-time 4 \
            --resolve "$fqdn:443:$node_ipv4" \
            --write-out \
            $'\n__META__%{http_code}|%{remote_ip}|%{http_version}|%{num_redirects}|%{size_download}\n' \
            "https://$fqdn/" 2>/dev/null
    )
    status=$?
    metadata=$(
        sed -n 's/^__META__//p' <<<"$output" |
            tail -n 1 |
            sanitize_line
    )
    printf '%s|%s\n' "$status" "${metadata:-missing}"
}

unique_delta_servers() {
    cut -d '|' -f 1 | sort -u
}

derive_selection() {
    local summaries=$1
    local known_deltas=$2
    local unknown_deltas=$3
    local unknown_status=$4
    local unknown_code=$5
    local exact_servers wildcard_421_servers known_servers unknown_servers
    local matching_unknown_deltas
    local exact_count wildcard_count known_count unknown_count
    local unknown_delta_count matching_unknown_delta_count selected

    exact_servers=$(
        jq -r 'select(.exact_target == true) | .server' <<<"$summaries" |
            sort -u
    )
    wildcard_421_servers=$(
        jq -r '
            select(
                .wildcard_target == true
                and .hostless_static_421 == true
            )
            | .server
        ' <<<"$summaries" | sort -u
    )
    known_servers=$(unique_delta_servers <<<"$known_deltas")
    matching_unknown_deltas=$(
        awk -F '|' -v expected_code="$unknown_code" \
            '$4 == expected_code { print }' <<<"$unknown_deltas"
    )
    unknown_servers=$(
        unique_delta_servers <<<"$matching_unknown_deltas"
    )
    exact_count=$(grep -c . <<<"$exact_servers")
    wildcard_count=$(grep -c . <<<"$wildcard_421_servers")
    known_count=$(grep -c . <<<"$known_servers")
    unknown_count=$(grep -c . <<<"$unknown_servers")
    unknown_delta_count=$(grep -c . <<<"$unknown_deltas")
    matching_unknown_delta_count=$(grep -c . <<<"$matching_unknown_deltas")
    [[ -n "$exact_servers" ]] || exact_count=0
    [[ -n "$wildcard_421_servers" ]] || wildcard_count=0
    [[ -n "$known_servers" ]] || known_count=0
    [[ -n "$unknown_servers" ]] || unknown_count=0
    [[ -n "$unknown_deltas" ]] || unknown_delta_count=0
    [[ -n "$matching_unknown_deltas" ]] ||
        matching_unknown_delta_count=0

    if
        [[ "$unknown_count" -eq 1 ]] &&
            [[ "$unknown_delta_count" -eq "$matching_unknown_delta_count" ]]
    then
        selected=$unknown_servers
        printf '%s|metrics_handler_delta|true\n' "$selected"
    elif
        [[ "$unknown_delta_count" -eq 0 ]] &&
            [[ "$unknown_status" -eq 0 ]] &&
            [[ "$unknown_code" == 200 ]] &&
            [[ "$exact_count" -eq 1 ]] &&
            [[ "$wildcard_count" -ge 1 ]] &&
            [[ "$known_count" -eq 1 ]] &&
            [[ "$known_servers" == "$exact_servers" ]]
    then
        selected=$exact_servers
        printf '%s|exact_listener_control_plus_unhandled_200|true\n' \
            "$selected"
    else
        printf 'unresolved|insufficient_or_concurrent_evidence|false\n'
    fi
}

if [[ "${1:-}" == --summarize-servers && $# -eq 1 ]]; then
    server_summary
    exit 0
elif [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    set -e
    sample_servers='{"srv0":{"listen":["10.1.0.53:443"],"routes":[{"match":[{"host":["pihole0.local.theama.co"]}],"handle":[{"handler":"subroute"}]}]},"srv3":{"listen":[":443"],"routes":[{"handle":[{"handler":"static_response","status_code":421}]}]}}'
    summaries=$(server_summary <<<"$sample_servers")
    grep -Fqx \
        '{"server":"srv0","listen":["10.1.0.53:443"],"exact_target":true,"wildcard_target":false,"hosts":["pihole0.local.theama.co"],"hostless_static_421":false}' \
        <<<"$summaries"
    grep -Fqx \
        '{"server":"srv3","listen":[":443"],"exact_target":false,"wildcard_target":true,"hosts":[],"hostless_static_421":true}' \
        <<<"$summaries"

    sample_metrics='caddy_http_request_duration_seconds_count{code="200",handler="subroute",host="pihole0.local.theama.co",method="HEAD",server="srv0"} 7'
    [[ "$(
        metric_rows HEAD "$node_fqdn" <<<"$sample_metrics"
    )" == 'srv0|subroute|pihole0.local.theama.co|200|7' ]]
    sample_trace_metrics='caddy_http_request_duration_seconds_count{code="421",handler="static_response",host="_other",method="TRACE",server="srv3"} 1'
    [[ "$(
        metric_rows TRACE _other <<<"$sample_trace_metrics"
    )" == 'srv3|static_response|_other|421|1' ]]
    [[ "$(
        metric_deltas \
            'srv0|subroute|pihole0.local.theama.co|200|6' \
            'srv0|subroute|pihole0.local.theama.co|200|7'
    )" == 'srv0|subroute|pihole0.local.theama.co|200|1' ]]
    [[ "$(
        derive_selection "$summaries" \
            'srv0|subroute|pihole0.local.theama.co|200|1' \
            '' 0 200
    )" == 'srv0|exact_listener_control_plus_unhandled_200|true' ]]
    [[ "$(
        derive_selection "$summaries" \
            'srv0|subroute|pihole0.local.theama.co|200|1' \
            'srv3|static_response|_other|421|1' 0 421
    )" == 'srv3|metrics_handler_delta|true' ]]
    [[ "$(
        derive_selection "$summaries" \
            'srv0|subroute|pihole0.local.theama.co|200|1' \
            'srv3|static_response|_other|421|1' 0 200
    )" == 'unresolved|insufficient_or_concurrent_evidence|false' ]]
    printf 'action_16aq_b_server_selection_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--summarize-servers]\n' \
        "${0##*/}" >&2
    exit 2
fi

printf 'action_16aq_b_remote_reached=true\n'
printf 'node_hostname=%s\n' "$(hostname 2>/dev/null | sanitize_line)"
printf 'node_architecture=%s\n' \
    "$(dpkg --print-architecture 2>/dev/null | sanitize_line)"

for command_name in awk curl cut dpkg grep hostname jq sed sort tail; do
    command -v "$command_name" >/dev/null 2>&1
    printf 'command_status=%s|%s\n' "$command_name" "$?"
done
printf 'command_record_count=10\n'

runtime_json=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/config/apps/http/servers" 2>/dev/null
)
runtime_status=$?
printf 'runtime_config_status=%s\n' "$runtime_status"
summaries=$(server_summary <<<"$runtime_json" 2>/dev/null)
summary_status=$?
summary_count=$(grep -c . <<<"$summaries")
[[ -n "$summaries" ]] || summary_count=0
printf 'server_summary_status=%s\n' "$summary_status"
printf 'server_summary_record_count=%s\n' "$summary_count"
while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    printf 'server_summary_record=%s\n' "$record"
done <<<"$summaries"

known_before_raw=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/metrics" 2>/dev/null
)
known_before_status=$?
known_before_rows=$(
    metric_rows HEAD "$node_fqdn" <<<"$known_before_raw"
)
known_probe=$(run_probe HEAD "$node_fqdn")
known_after_raw=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/metrics" 2>/dev/null
)
known_after_status=$?
known_after_rows=$(
    metric_rows HEAD "$node_fqdn" <<<"$known_after_raw"
)
known_deltas=$(metric_deltas "$known_before_rows" "$known_after_rows")

unknown_before_raw=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/metrics" 2>/dev/null
)
unknown_before_status=$?
unknown_before_rows=$(
    metric_rows TRACE _other <<<"$unknown_before_raw"
)
unknown_probe=$(run_probe TRACE "$unknown_fqdn")
unknown_after_raw=$(
    curl --noproxy '*' --silent --show-error --fail \
        --connect-timeout 1 --max-time 3 \
        "$caddy_admin/metrics" 2>/dev/null
)
unknown_after_status=$?
unknown_after_rows=$(
    metric_rows TRACE _other <<<"$unknown_after_raw"
)
unknown_deltas=$(metric_deltas "$unknown_before_rows" "$unknown_after_rows")

printf 'known_metrics_before_status=%s\n' "$known_before_status"
printf 'known_metrics_after_status=%s\n' "$known_after_status"
printf 'unknown_metrics_before_status=%s\n' "$unknown_before_status"
printf 'unknown_metrics_after_status=%s\n' "$unknown_after_status"
printf 'probe_record_count=2\n'
printf 'probe_record=known_control|%s\n' "$known_probe"
printf 'probe_record=unknown_default|%s\n' "$unknown_probe"

known_delta_count=$(grep -c . <<<"$known_deltas")
unknown_delta_count=$(grep -c . <<<"$unknown_deltas")
[[ -n "$known_deltas" ]] || known_delta_count=0
[[ -n "$unknown_deltas" ]] || unknown_delta_count=0
printf 'known_metric_delta_record_count=%s\n' "$known_delta_count"
while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    printf 'known_metric_delta_record=%s\n' "$record"
done <<<"$known_deltas"
printf 'unknown_metric_delta_record_count=%s\n' "$unknown_delta_count"
while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    printf 'unknown_metric_delta_record=%s\n' "$record"
done <<<"$unknown_deltas"

unknown_curl_status=${unknown_probe%%|*}
unknown_metadata=${unknown_probe#*|}
unknown_code=${unknown_metadata%%|*}
selection=$(
    derive_selection "$summaries" "$known_deltas" "$unknown_deltas" \
        "$unknown_curl_status" "$unknown_code"
)
printf 'server_selection_record=%s\n' "$selection"

printf 'runtime_metrics_counter_effect=true\n'
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'configuration_mutations=false\n'
printf 'filesystem_mutations=false\n'
printf 'action_16aq_b_server_selection_diagnostic_complete=true\n'
