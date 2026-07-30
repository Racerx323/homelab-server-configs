#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_sha256=1193632a867b4a86fd28f4b932b809926498b0b6a2e4751e8ee1f69c5da05ae8
readonly historical_runner_sha256=f19e5673d3e86a95282041e9770c8c6d1093cbee9cd985e82957bd78773f16e5
readonly historical_node_b_target=/etc/caddy/releases/bootstrap
readonly accepted_node_b_target=/etc/caddy/releases/action15-health-follow-redirects
readonly inspector_hash_placeholder=RENDERED_INSPECTOR_SHA256

verify_source() {
    local source=$1
    local expected_hash=$2

    [[ -f "$source" && ! -L "$source" ]]
    [[ "$(sha256sum "$source" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$source"
}

render_inspector() {
    local source=$1

    verify_source "$source" "$historical_inspector_sha256"
    [[ "$(grep -Fxc \
        "        $historical_node_b_target" "$source")" -eq 1 ]]
    sed \
        "s|^        $historical_node_b_target\$|        $accepted_node_b_target|" \
        "$source"
}

render_runner() {
    local source=$1
    local rendered_inspector_sha256=$2

    verify_source "$source" "$historical_runner_sha256"
    [[ "$rendered_inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(grep -Fxc \
        "readonly inspector_sha256=$historical_inspector_sha256" \
        "$source")" -eq 1 ]]
    sed \
        "s|^readonly inspector_sha256=$historical_inspector_sha256\$|readonly inspector_sha256=$rendered_inspector_sha256|" \
        "$source"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$historical_inspector_sha256" \
        "$historical_runner_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$historical_node_b_target" != "$accepted_node_b_target" ]]
    [[ "$inspector_hash_placeholder" == RENDERED_INSPECTOR_SHA256 ]]
    printf 'action_17a_retry_correction_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --render-inspector && $# -eq 2 ]]; then
    render_inspector "$2"
    exit 0
elif [[ "${1:-}" == --render-runner && $# -eq 3 ]]; then
    render_runner "$2" "$3"
    exit 0
fi

printf 'Usage: %s --self-test | --render-inspector HISTORICAL_INSPECTOR | --render-runner HISTORICAL_RUNNER RENDERED_INSPECTOR_SHA256\n' \
    "${0##*/}" >&2
exit 2
