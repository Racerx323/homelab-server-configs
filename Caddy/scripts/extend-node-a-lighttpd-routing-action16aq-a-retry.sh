#!/usr/bin/env bash

# This file is appended to the hash-pinned Action 16aq-a collector by the
# retry runner. The original collector defines adapted_json and runtime_json.

static_response_summary() {
    jq -c '
        to_entries[] as $server
        | (($server.value.routes // []) | to_entries[]) as $route
        | (($route.value.handle // []) | to_entries[]) as $handler
        | select($handler.value.handler == "static_response")
        | {
            server: $server.key,
            route_index: $route.key,
            handler_index: $handler.key,
            listen: ($server.value.listen // []),
            hosts: ([$route.value.match[]?.host[]?] | sort),
            status_code_present: ($handler.value | has("status_code")),
            effective_status_code: ($handler.value.status_code // 200),
            body_length: (($handler.value.body // "") | length),
            body_is_421: (($handler.value.body // "") == "421")
        }
    '
}

if [[ "${1:-}" == --summarize-servers && $# -eq 1 ]]; then
    static_response_summary
    exit 0
elif [[ "${1:-}" == --extension-self-test && $# -eq 1 ]]; then
    sample_servers='{"srv0":{"listen":[":443"],"routes":[{"handle":[{"handler":"static_response","body":"421"}]}]}}'
    expected='{"server":"srv0","route_index":0,"handler_index":0,"listen":[":443"],"hosts":[],"status_code_present":false,"effective_status_code":200,"body_length":3,"body_is_421":true}'
    [[ "$(static_response_summary <<<"$sample_servers")" == "$expected" ]]
    printf '%s\n' \
        'action_16aq_a_retry_static_response_extension_self_test_complete=true'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--extension-self-test|--summarize-servers]\n' \
        "${0##*/}" >&2
    exit 2
fi

printf 'static_response_summary_schema=1\n'

# The original collector defines adapted_json before this extension runs.
# shellcheck disable=SC2154
adapted_static_response_records=$(
    jq -c '.apps.http.servers' <<<"$adapted_json" 2>/dev/null |
        static_response_summary 2>/dev/null
)
adapted_static_response_status=$?
adapted_static_response_count=$(grep -c . <<<"$adapted_static_response_records")
if [[ -z "$adapted_static_response_records" ]]; then
    adapted_static_response_count=0
fi
printf 'adapted_static_response_status=%s\n' \
    "$adapted_static_response_status"
printf 'adapted_static_response_record_count=%s\n' \
    "$adapted_static_response_count"
collect_lines adapted_static_response_record \
    "$adapted_static_response_records"

# The original collector defines runtime_json before this extension runs.
# shellcheck disable=SC2154
runtime_static_response_records=$(
    static_response_summary <<<"$runtime_json" 2>/dev/null
)
runtime_static_response_status=$?
runtime_static_response_count=$(grep -c . <<<"$runtime_static_response_records")
if [[ -z "$runtime_static_response_records" ]]; then
    runtime_static_response_count=0
fi
printf 'runtime_static_response_status=%s\n' \
    "$runtime_static_response_status"
printf 'runtime_static_response_record_count=%s\n' \
    "$runtime_static_response_count"
collect_lines runtime_static_response_record \
    "$runtime_static_response_records"

if [[ "$adapted_static_response_records" == "$runtime_static_response_records" ]]; then
    printf 'static_response_summaries_equal=true\n'
else
    printf 'static_response_summaries_equal=false\n'
fi

printf '%s\n' \
    'action_16aq_a_retry_static_response_extension_complete=true'
