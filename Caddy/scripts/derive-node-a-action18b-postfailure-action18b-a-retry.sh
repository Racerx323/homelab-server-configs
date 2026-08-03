#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_sha256=f893c433739b0b7c115b7d46c9e13dfd38338f2edbe7259ab3fae52a68545c0a
readonly historical_runner_sha256=75e65cf752a4cf2581438042300a7cb58adc1a55b912b1b0f5864fc344b4e295
readonly historical_regression_sha256=962785f102739d9a653c61d2860a549d09cdb15d7775182226e6c6abee0c9ade
readonly rendered_inspector_name=inspect-node-a-action18b-postfailure-action18b-a-retry.sh
readonly rendered_runner_name=run-node-a-action18b-postfailure-action18b-a-retry.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly historical_inspector="$script_directory/inspect-node-a-action18b-postfailure-action18b-a.sh"
readonly historical_runner="$script_directory/run-node-a-action18b-postfailure-action18b-a.sh"
readonly historical_regression="$caddy_root/tests/action18b-a-node-a-postfailure-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_historical_sources() {
    local expected_hash
    local source_path

    while IFS='|' read -r source_path expected_hash; do
        [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
        [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
    done <<EOF
$historical_inspector|$historical_inspector_sha256
$historical_runner|$historical_runner_sha256
$historical_regression|$historical_regression_sha256
EOF
}

render_inspector() {
    local output_path=$1

    awk '
        function emit_counter() {
            print "transaction_stage_count() {"
            print "    local excluded_path=$1"
            print ""
            print "    shift"
            print "    find \"$@\" -mindepth 1 -maxdepth 1 \\"
            print "        \\( -name \047caddy-action18b-*\047 -o -name \047.caddy-sync-*-v2.*\047 \\) \\"
            print "        ! -path \"$excluded_path\" -printf . 2>/dev/null | wc -c"
            print "}"
            print ""
        }
        BEGIN {
            inserted_counter = 0
            replacing_count = 0
            replacement_complete = 0
        }
        {
            line = $0
            gsub(/action_18b_a/, "action_18b_a_retry", line)
            gsub(/caddy-action18b-a-inspector/, "caddy-action18b-a-retry-inspector", line)
            if (!inserted_counter && line == "is_sha256() {") {
                emit_counter()
                inserted_counter = 1
            }
            if (line == "action18b_stage_count=$(") {
                print "action18b_stage_count=$(transaction_stage_count \"$work_directory\" /run /tmp)"
                replacing_count = 1
                next
            }
            if (replacing_count) {
                if (line == ")") {
                    replacing_count = 0
                    replacement_complete = 1
                }
                next
            }
            print line
        }
        END {
            if (!inserted_counter || !replacement_complete || replacing_count) {
                exit 91
            }
        }
    ' "$historical_inspector" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local inspector_hash=$1
    local output_path=$2

    awk -v rendered_hash="$inspector_hash" '
        {
            line = $0
            gsub(/action_18b_a/, "action_18b_a_retry", line)
            gsub(/inspect-node-a-action18b-postfailure-action18b-a\.sh/,
                "inspect-node-a-action18b-postfailure-action18b-a-retry.sh", line)
            gsub(/caddy-action18b-a-contract/, "caddy-action18b-a-retry-contract", line)
            gsub(/caddy-action18b-a-runner/, "caddy-action18b-a-retry-runner", line)
            if (line ~ /^readonly inspector_sha256=/) {
                line = "readonly inspector_sha256=" rendered_hash
            }
            print line
        }
    ' "$historical_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local rendered_inspector="$output_directory/$rendered_inspector_name"
    local rendered_runner="$output_directory/$rendered_runner_name"
    local rendered_inspector_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    render_inspector "$rendered_inspector"
    rendered_inspector_hash=$(file_hash "$rendered_inspector")
    render_runner "$rendered_inspector_hash" "$rendered_runner"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_historical_sources
        test_directory=$(mktemp -d /tmp/caddy-action18b-a-retry-derive.XXXXXX)
        readonly test_directory
        trap 'rm -rf -- "$test_directory"' EXIT
        render_pair "$test_directory"
        bash -n "$test_directory/$rendered_inspector_name" \
            "$test_directory/$rendered_runner_name"
        "$test_directory/$rendered_inspector_name" --self-test >/dev/null
        printf 'action_18b_a_retry_derivation_self_test_complete=true\n'
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_historical_sources
        render_pair "$2"
        printf 'action_18b_a_retry_derivation_render_complete=true\n'
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
