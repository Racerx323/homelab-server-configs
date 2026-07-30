#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_runner_sha256=fe4e09369ee6699bceeb14453546ca6f22523219c5391a383b815f59293635fe
readonly observed_keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly observed_lighttpd_tree_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372

verify_source() {
    local source=$1

    [[ -f "$source" && ! -L "$source" ]]
    [[ "$(sha256sum "$source" | awk '{ print $1 }')" == "$historical_runner_sha256" ]]
    bash -n "$source"
}

render_correction() {
    local source=$1

    verify_source "$source"
    awk \
        -v keepalived_hash="$observed_keepalived_tree_sha256" \
        -v lighttpd_hash="$observed_lighttpd_tree_sha256" '
        function replace_literal(value, old, new, position) {
            while ((position = index(value, old)) != 0) {
                value = substr(value, 1, position - 1) new \
                    substr(value, position + length(old))
            }
            return value
        }

        {
            line = $0
            line = replace_literal(line, "dad64e4a5893e37a101081e5272ea1b8b924c5e66a10d7f52bfb408fb0c92f66", keepalived_hash)
            line = replace_literal(line, "95a8752f36371996b5fc55c30cdffdcfd548cbed588c2e7eb52a4c79248d3372", lighttpd_hash)
            line = replace_literal(line, "service_record=lsyncd.service\\|loaded\\|inactive", "service_record=lsyncd.service\\|masked\\|inactive")
            line = replace_literal(line, "service_record=caddy-api.service\\|loaded\\|inactive", "service_record=caddy-api.service\\|masked\\|inactive")
            line = replace_literal(line, "service_record=lsyncd.service|loaded|inactive", "service_record=lsyncd.service|masked|inactive")
            line = replace_literal(line, "service_record=caddy-api.service|loaded|inactive", "service_record=caddy-api.service|masked|inactive")
            line = replace_literal(line, "^process_record=caddy\\\\|${caddy_pid} .+", "^process_record=caddy%7C${caddy_pid} .+")
            line = replace_literal(line, "process_record=caddy|${expected_caddy_pid} ", "process_record=caddy%7C${expected_caddy_pid} ")
            print line
        }
    ' "$source"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$historical_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$observed_keepalived_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$observed_lighttpd_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    sample=$(mktemp /tmp/caddy-action16ar-b-retry-correction.XXXXXX)
    trap 'rm -f -- "$sample"' EXIT
    {
        # shellcheck disable=SC2016
        printf '%s\n' \
            'dad64e4a5893e37a101081e5272ea1b8b924c5e66a10d7f52bfb408fb0c92f66' \
            '95a8752f36371996b5fc55c30cdffdcfd548cbed588c2e7eb52a4c79248d3372' \
            'service_record=lsyncd.service\|loaded\|inactive' \
            'service_record=caddy-api.service\|loaded\|inactive' \
            'service_record=lsyncd.service|loaded|inactive' \
            'service_record=caddy-api.service|loaded|inactive' \
            '^process_record=caddy\\|${caddy_pid} .+' \
            'process_record=caddy|${expected_caddy_pid} '
    } >"$sample"
    sample_hash=$(sha256sum "$sample" | awk '{ print $1 }')
    output=$(
        awk \
            -v keepalived_hash="$observed_keepalived_tree_sha256" \
            -v lighttpd_hash="$observed_lighttpd_tree_sha256" '
            function replace_literal(value, old, new, position) {
                while ((position = index(value, old)) != 0) {
                    value = substr(value, 1, position - 1) new \
                        substr(value, position + length(old))
                }
                return value
            }
            {
                line = $0
                line = replace_literal(line,
                    "dad64e4a5893e37a101081e5272ea1b8b924c5e66a10d7f52bfb408fb0c92f66",
                    keepalived_hash)
                line = replace_literal(line,
                    "95a8752f36371996b5fc55c30cdffdcfd548cbed588c2e7eb52a4c79248d3372",
                    lighttpd_hash)
                line = replace_literal(line,
                    "service_record=lsyncd.service\\|loaded\\|inactive",
                    "service_record=lsyncd.service\\|masked\\|inactive")
                line = replace_literal(line,
                    "service_record=caddy-api.service\\|loaded\\|inactive",
                    "service_record=caddy-api.service\\|masked\\|inactive")
                line = replace_literal(line,
                    "service_record=lsyncd.service|loaded|inactive",
                    "service_record=lsyncd.service|masked|inactive")
                line = replace_literal(line,
                    "service_record=caddy-api.service|loaded|inactive",
                    "service_record=caddy-api.service|masked|inactive")
                line = replace_literal(line,
                    "^process_record=caddy\\\\|${caddy_pid} .+",
                    "^process_record=caddy%7C${caddy_pid} .+")
                line = replace_literal(line,
                    "process_record=caddy|${expected_caddy_pid} ",
                    "process_record=caddy%7C${expected_caddy_pid} ")
                print line
            }
        ' "$sample"
    )
    [[ "$sample_hash" =~ ^[0-9a-f]{64}$ ]]
    grep -Fq "$observed_keepalived_tree_sha256" <<<"$output"
    grep -Fq "$observed_lighttpd_tree_sha256" <<<"$output"
    grep -Fq \
        'service_record=lsyncd.service\|masked\|inactive' <<<"$output"
    grep -Fq \
        'service_record=caddy-api.service\|masked\|inactive' <<<"$output"
    grep -Fq 'service_record=lsyncd.service|masked|inactive' <<<"$output"
    grep -Fq 'service_record=caddy-api.service|masked|inactive' <<<"$output"
    # shellcheck disable=SC2016
    grep -Fq '^process_record=caddy%7C${caddy_pid} .+' <<<"$output"
    # shellcheck disable=SC2016
    grep -Fq \
        'process_record=caddy%7C${expected_caddy_pid} ' <<<"$output"
    printf 'action_16ar_b_retry_correction_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --render && $# -eq 2 ]]; then
    render_correction "$2"
    exit 0
fi

printf 'Usage: %s --self-test | --render HISTORICAL_RUNNER\n' \
    "${0##*/}" >&2
exit 2
