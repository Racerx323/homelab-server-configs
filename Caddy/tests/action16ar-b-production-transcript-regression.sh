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
readonly historical_runner="$caddy_root/scripts/run-node-a-post-correction-acceptance-action16ar-b.sh"
readonly historical_runner_sha256=fe4e09369ee6699bceeb14453546ca6f22523219c5391a383b815f59293635fe
readonly correction="$caddy_root/scripts/correct-node-a-post-correction-acceptance-action16ar-b-retry.sh"
readonly correction_sha256=c2f0ffcf76ea54cb101af03c3223640fc12ff7102aacfc251d793a9dbb304389
readonly rendered_sha256=00ab68767fef384ff0dca13c67d0c0970755d9e8c81861cc5d1c1f57fe49d25e
readonly keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly lighttpd_tree_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372

verify_file() {
    local target=$1
    local expected_hash=$2

    [[ -f "$target" && ! -L "$target" ]]
    [[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$target"
}

run_regression() {
    local work_dir rendered

    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$correction" "$correction_sha256"
    work_dir=$(mktemp -d /tmp/caddy-action16ar-b-production.XXXXXX)
    trap 'rm -rf -- "$work_dir"' RETURN
    rendered=$work_dir/rendered-runner.sh
    "$correction" --render "$historical_runner" >"$rendered"
    [[ "$(sha256sum "$rendered" | awk '{ print $1 }')" == "$rendered_sha256" ]]
    bash -n "$rendered"

    [[ "$(grep -Fxc \
        "readonly keepalived_tree_sha256=$keepalived_tree_sha256" \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "readonly lighttpd_tree_sha256=$lighttpd_tree_sha256" \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "        '^service_record=lsyncd.service\\|masked\\|inactive\\|dead\\|masked\\|' \\" \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "        '^service_record=caddy-api.service\\|masked\\|inactive\\|dead\\|masked\\|' \\" \
        "$rendered")" -eq 1 ]]
    # shellcheck disable=SC2016
    [[ "$(grep -Fxc \
        '        "^process_record=caddy%7C${caddy_pid} .+" "$transcript" ||' \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "            'service_record=lsyncd.service|masked|inactive|dead|masked|success|0|0|0|/lib/systemd/system/lsyncd.service|' \\" \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "            'service_record=caddy-api.service|masked|inactive|dead|masked|success|0|0|0|/etc/systemd/system/caddy-api.service|' \\" \
        "$rendered")" -eq 1 ]]
    [[ "$(grep -Fxc \
        "            \"process_record=caddy%7C\${expected_caddy_pid} /usr/bin/caddy run\" \\" \
        "$rendered")" -eq 1 ]]

    # shellcheck disable=SC2016
    if grep -Fq \
        'service_record=lsyncd.service\|loaded\|inactive' "$rendered" ||
        grep -Fq \
            'service_record=caddy-api.service\|loaded\|inactive' "$rendered" ||
        grep -Fq \
            'process_record=caddy|${expected_caddy_pid}' "$rendered"; then
        printf 'Rendered validator retained a rejected production assumption.\n' \
            >&2
        return 1
    fi

    bash "$rendered" --contract-test >/dev/null
    rm -rf -- "$work_dir"
    trap - RETURN
    printf 'action_16ar_b_production_transcript_regression_complete=true\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$correction_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$rendered_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$keepalived_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$lighttpd_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    run_regression
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

run_regression
