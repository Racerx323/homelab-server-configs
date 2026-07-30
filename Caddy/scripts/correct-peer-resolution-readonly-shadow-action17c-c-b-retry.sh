#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_collector_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d
readonly historical_runner_sha256=d0fa596f3912288b24645fa6fa9bbbfe15fa0fffd38d7d6308f11041a7bdb4da
readonly rendered_collector_sha256=c99a7be13a20cbc5b2af7bc74790bd06b7f3afe62f9b73b41de42171a2ab4efd
readonly rendered_runner_sha256=5bf1e9a92cc4b1ad63e2a7dfba0467a40edecb9fb7ef0fcb80e66da1f9288263

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_collector="$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"
readonly historical_runner="$script_dir/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    local source_path=$1
    local expected_hash=$2

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
    bash -n "$source_path"
}

render_collector() {
    local source_path=$1

    verify_source "$source_path" "$historical_collector_sha256"
    awk '
        $0 == "printf '\''action_17c_c_b_prestate_collection_complete=true\\n'\''" {
            in_provenance = 1
            print
            next
        }
        in_provenance && $0 == "resolv_target=$(readlink -f -- \"$resolv_conf\")" {
            print "provenance_resolv_target=$(readlink -f -- \"$resolv_conf\")"
            assignment_changed++
            next
        }
        in_provenance && $0 == "readonly resolv_target" {
            print "readonly provenance_resolv_target"
            readonly_changed++
            next
        }
        in_provenance && index($0, "\"$resolv_target\"") {
            gsub(/"\$resolv_target"/, "\"$provenance_resolv_target\"")
            reference_lines_changed++
            print
            next
        }
        { print }
        END {
            if (assignment_changed != 1 ||
                readonly_changed != 1 ||
                reference_lines_changed != 3) {
                exit 42
            }
        }
    ' "$source_path"
}

render_runner() {
    local source_path=$1

    verify_source "$source_path" "$historical_runner_sha256"
    awk -v collector_hash="$rendered_collector_sha256" '
        $0 == "readonly diagnostic_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d" {
            print "readonly diagnostic_sha256=" collector_hash
            hash_changed++
            next
        }
        $0 == "readonly diagnostic=\"$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh\"" {
            print "readonly diagnostic=\"$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b-retry.sh\""
            path_changed++
            next
        }
        { print }
        END {
            if (hash_changed != 1 || path_changed != 1) {
                exit 42
            }
        }
    ' "$source_path"
}

usage() {
    printf '%s\n' \
        "Usage: ${0##*/} --render-collector SOURCE" \
        "       ${0##*/} --render-runner SOURCE" \
        "       ${0##*/} --self-test"
}

case "${1:-}" in
    --render-collector)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 2
        }
        render_collector "$2"
        ;;
    --render-runner)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 2
        }
        render_runner "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        for value in \
            "$historical_collector_sha256" \
            "$historical_runner_sha256" \
            "$rendered_collector_sha256" \
            "$rendered_runner_sha256"; do
            [[ "$value" =~ ^[0-9a-f]{64}$ ]]
        done
        test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-retry-correction.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_collector "$historical_collector" >"$test_dir/collector"
        render_runner "$historical_runner" >"$test_dir/runner"
        [[ "$(file_hash "$test_dir/collector")" == "$rendered_collector_sha256" ]]
        [[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
        bash -n "$test_dir/collector" "$test_dir/runner"
        # shellcheck disable=SC2016 # Match literal source text.
        grep -Fxq \
            'provenance_resolv_target=$(readlink -f -- "$resolv_conf")' \
            "$test_dir/collector"
        grep -Fxq 'readonly provenance_resolv_target' "$test_dir/collector"
        grep -Fxq \
            "readonly diagnostic_sha256=$rendered_collector_sha256" \
            "$test_dir/runner"
        # shellcheck disable=SC2016 # Match literal source text.
        grep -Fxq \
            'readonly diagnostic="$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b-retry.sh"' \
            "$test_dir/runner"
        printf 'action_17c_c_b_retry_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
