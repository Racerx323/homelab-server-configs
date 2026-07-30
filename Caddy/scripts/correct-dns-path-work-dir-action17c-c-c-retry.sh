#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match literal source text in the rendered artifacts.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly historical_runner_sha256=db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6
readonly rendered_collector_sha256=1a96099b69a1f4a8672e09ec49158f779e612d08a46e8c9333c38aff9f7d6624
readonly rendered_runner_sha256=e1921118134ff70f4ef1d93e0a8df9490fa5b14033f689d3b416c4ebc08071b3

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_collector="$script_dir/diagnose-dns-path-authority-action17c-c-c.sh"
readonly historical_runner="$script_dir/run-dns-path-authority-diagnostic-action17c-c-c.sh"

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
        $0 == "run_query() {" {
            in_run_query = 1
        }
        in_run_query && $0 == "    local work_dir=$7" {
            print "    local query_work_dir=$7"
            parameter_changed++
            next
        }
        in_run_query && $0 == "    local output=\"$work_dir/$label.out\"" {
            print "    local output=\"$query_work_dir/$label.out\""
            output_changed++
            next
        }
        in_run_query && $0 == "    local error=\"$work_dir/$label.err\"" {
            print "    local error=\"$query_work_dir/$label.err\""
            error_changed++
            next
        }
        in_run_query && $0 == "    local answers=\"$work_dir/$label.answers\"" {
            print "    local answers=\"$query_work_dir/$label.answers\""
            answers_changed++
            next
        }
        in_run_query && $0 == "}" {
            in_run_query = 0
        }
        { print }
        END {
            if (parameter_changed != 1 ||
                output_changed != 1 ||
                error_changed != 1 ||
                answers_changed != 1) {
                exit 42
            }
        }
    ' "$source_path"
}

render_runner() {
    local source_path=$1

    verify_source "$source_path" "$historical_runner_sha256"
    awk -v collector_hash="$rendered_collector_sha256" '
        $0 == "readonly collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364" {
            print "readonly collector_sha256=" collector_hash
            hash_changed++
            next
        }
        $0 == "readonly collector=\"$script_dir/diagnose-dns-path-authority-action17c-c-c.sh\"" {
            print "readonly collector=\"$script_dir/diagnose-dns-path-authority-action17c-c-c-retry.sh\""
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
        test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-retry-correction.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_collector "$historical_collector" >"$test_dir/collector"
        render_runner "$historical_runner" >"$test_dir/runner"
        [[ "$(file_hash "$test_dir/collector")" == "$rendered_collector_sha256" ]]
        [[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
        bash -n "$test_dir/collector" "$test_dir/runner"
        grep -Fxq '    local query_work_dir=$7' "$test_dir/collector"
        grep -Fxq \
            '    local output="$query_work_dir/$label.out"' \
            "$test_dir/collector"
        grep -Fxq \
            "readonly collector_sha256=$rendered_collector_sha256" \
            "$test_dir/runner"
        # shellcheck disable=SC2016 # Match literal rendered source text.
        grep -Fxq \
            'readonly collector="$script_dir/diagnose-dns-path-authority-action17c-c-c-retry.sh"' \
            "$test_dir/runner"
        printf 'action_17c_c_c_retry_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
