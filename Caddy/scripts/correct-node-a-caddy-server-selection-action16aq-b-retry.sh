#!/usr/bin/env bash

# This file is appended to the hash-pinned, executed Action 16aq-b collector.
# The original collector leaves its production evidence in shell variables.

decode_probe_code() {
    local metadata=$1
    local decoded
    local -a fields

    [[ "$metadata" != missing ]] || return 1
    [[ "$metadata" != *"|"* ]] || return 1
    decoded=${metadata//%7C/$'\n'}
    mapfile -t fields <<<"$decoded"
    [[ "${#fields[@]}" -eq 5 ]] || return 1
    [[ "${fields[0]}" =~ ^[0-9]{3}$ ]] || return 1
    [[ -n "${fields[1]}" ]] || return 1
    [[ -n "${fields[2]}" ]] || return 1
    [[ "${fields[3]}" =~ ^[0-9]+$ ]] || return 1
    [[ "${fields[4]}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${fields[0]}"
}

emit_corrected_selection() {
    local metadata=$1
    local selection_summaries=$2
    local selection_known_deltas=$3
    local selection_unknown_deltas=$4
    local selection_curl_status=$5
    local corrected_unknown_code corrected_decode_status
    local corrected_selection

    printf 'corrected_selection_schema=1\n'
    corrected_unknown_code=$(decode_probe_code "$metadata")
    corrected_decode_status=$?
    printf 'corrected_probe_decode_status=%s\n' "$corrected_decode_status"
    printf 'corrected_unknown_http_code=%s\n' \
        "${corrected_unknown_code:-missing}"

    if [[ "$corrected_decode_status" -eq 0 ]]; then
        corrected_selection=$(
            derive_selection "$selection_summaries" \
                "$selection_known_deltas" "$selection_unknown_deltas" \
                "$selection_curl_status" "$corrected_unknown_code"
        )
    else
        corrected_selection='unresolved|probe_decode_failed|false'
    fi
    printf 'corrected_server_selection_record=%s\n' "$corrected_selection"
    printf '%s\n' \
        'action_16aq_b_retry_selection_correction_complete=true'
}

if [[ "${1:-}" == --decode-probe-code && $# -eq 1 ]]; then
    decode_probe_code "$(cat)"
    exit
elif [[ "${1:-}" == --extension-self-test && $# -eq 1 ]]; then
    set -e
    [[ "$(
        decode_probe_code '200%7C10.1.0.53%7C2%7C0%7C0'
    )" == 200 ]]
    [[ "$(
        decode_probe_code '421%7C10.1.0.53%7C2%7C0%7C0'
    )" == 421 ]]
    if decode_probe_code '200|10.1.0.53|2|0|0' >/dev/null 2>&1; then
        exit 1
    fi
    if decode_probe_code missing >/dev/null 2>&1; then
        exit 1
    fi
    if decode_probe_code \
        '200%7C10.1.0.53%7C2%7C0' >/dev/null 2>&1; then
        exit 1
    fi
    derive_selection() {
        [[ "$5" == 200 ]]
        printf '%s\n' \
            'srv0|exact_listener_control_plus_unhandled_200|true'
    }
    correction_output=$(
        emit_corrected_selection \
            '200%7C10.1.0.53%7C2%7C0%7C0' \
            sample_summaries sample_known_deltas '' 0
    )
    grep -Fxq 'corrected_selection_schema=1' <<<"$correction_output"
    grep -Fxq 'corrected_probe_decode_status=0' <<<"$correction_output"
    grep -Fxq 'corrected_unknown_http_code=200' <<<"$correction_output"
    grep -Fxq \
        'corrected_server_selection_record=srv0|exact_listener_control_plus_unhandled_200|true' \
        <<<"$correction_output"
    printf '%s\n' \
        'action_16aq_b_retry_selection_correction_self_test_complete=true'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--decode-probe-code|--extension-self-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

# The original collector defines all five inputs before this extension runs.
# shellcheck disable=SC2154
emit_corrected_selection "$unknown_metadata" "$summaries" "$known_deltas" \
    "$unknown_deltas" "$unknown_curl_status"
