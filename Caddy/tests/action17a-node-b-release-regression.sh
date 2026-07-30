#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_inspector="$caddy_root/scripts/inspect-sync-readiness-before-action17.sh"
readonly historical_inspector_sha256=1193632a867b4a86fd28f4b932b809926498b0b6a2e4751e8ee1f69c5da05ae8
readonly historical_runner="$caddy_root/scripts/run-sync-readiness-before-action17.sh"
readonly historical_runner_sha256=f19e5673d3e86a95282041e9770c8c6d1093cbee9cd985e82957bd78773f16e5
readonly correction="$caddy_root/scripts/correct-sync-readiness-before-action17-retry.sh"
readonly correction_sha256=37d2b822bac699e5feaba9317719931d5264e2ae3281187ee3a0f16b07bfd543
readonly rendered_inspector_sha256=87c910f1c7a5a01c21af8af0b840d339a793a91b9f430539760bfbe94a80b805
readonly rendered_runner_sha256=ffb025e613466b73692002b093041f793bd9c08132842bc83d0944bd937fb9ad
readonly historical_target=/etc/caddy/releases/bootstrap
readonly accepted_target=/etc/caddy/releases/action15-health-follow-redirects

verify_file() {
    local target=$1
    local expected_hash=$2

    [[ -f "$target" && ! -L "$target" ]]
    [[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$target"
}

run_regression() {
    local work_dir expected_inspector rendered_inspector rendered_runner

    verify_file "$historical_inspector" "$historical_inspector_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$correction" "$correction_sha256"
    work_dir=$(mktemp -d /tmp/caddy-action17a-release-regression.XXXXXX)
    trap 'rm -rf -- "$work_dir"' RETURN
    expected_inspector=$work_dir/expected-inspector.sh
    rendered_inspector=$work_dir/inspect-sync-readiness-before-action17.sh
    rendered_runner=$work_dir/run-sync-readiness-before-action17.sh

    sed \
        "s|^        $historical_target\$|        $accepted_target|" \
        "$historical_inspector" >"$expected_inspector"
    "$correction" --render-inspector "$historical_inspector" \
        >"$rendered_inspector"
    cmp --silent "$expected_inspector" "$rendered_inspector"
    [[ "$(sha256sum "$rendered_inspector" | awk '{ print $1 }')" == "$rendered_inspector_sha256" ]]
    [[ "$(grep -Fxc "        $accepted_target" \
        "$rendered_inspector")" -eq 1 ]]
    if grep -Fq "        $historical_target" "$rendered_inspector"; then
        printf 'Rendered inspector retained the stale Node B target.\n' >&2
        return 1
    fi

    "$correction" --render-runner "$historical_runner" \
        "$rendered_inspector_sha256" >"$rendered_runner"
    [[ "$(sha256sum "$rendered_runner" | awk '{ print $1 }')" == "$rendered_runner_sha256" ]]
    grep -Fxq \
        "readonly inspector_sha256=$rendered_inspector_sha256" \
        "$rendered_runner"
    if grep -Fq \
        "readonly inspector_sha256=$historical_inspector_sha256" \
        "$rendered_runner"; then
        printf 'Rendered runner retained the historical inspector hash.\n' \
            >&2
        return 1
    fi

    chmod 0755 "$rendered_inspector" "$rendered_runner"
    bash -n "$rendered_inspector" "$rendered_runner"
    "$rendered_inspector" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
    rm -rf -- "$work_dir"
    trap - RETURN
    printf 'action_17a_node_b_release_regression_complete=true\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$historical_inspector_sha256" \
        "$historical_runner_sha256" \
        "$correction_sha256" \
        "$rendered_inspector_sha256" \
        "$rendered_runner_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    run_regression
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

run_regression
