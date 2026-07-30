#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_runner_sha256=b63cd6e48662ad2a7b1604817da21135e735be0c8319090919760398d98d7cf7
readonly rendered_runner_sha256=1cef934ad56a4e6b5d7e0d2024b12607d4462951fba5e234b1f78504a239b5f2

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_runner="$script_dir/run-node-a-source-bound-transport-action17c-c.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_runner() {
    local source_path=$1

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$historical_runner_sha256" ]]
    awk '
        $0 == "    '\''sudo -n /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect'\'' \\" {
            print "    \"sudo -n /bin/bash -c '\''cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect'\''\" \\"
            changed++
            next
        }
        { print }
        END {
            if (changed != 1) {
                exit 42
            }
        }
    ' "$source_path"
}

usage() {
    printf '%s\n' \
        "Usage: ${0##*/} --render-runner SOURCE" \
        "       ${0##*/} --self-test"
}

case "${1:-}" in
    --render-runner)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 2
        }
        render_runner "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$historical_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$rendered_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]]
        test_dir=$(mktemp -d /tmp/caddy-action17c-c-retry-correction.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_runner "$historical_runner" >"$test_dir/runner"
        [[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
        bash -n "$test_dir/runner"
        grep -Fxq \
            "    \"sudo -n /bin/bash -c 'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect'\" \\" \
            "$test_dir/runner"
        if grep -Fq \
            "    'sudo -n /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect' \\" \
            "$test_dir/runner"; then
            printf 'Historical inaccessible-directory command remains.\n' >&2
            exit 1
        fi
        printf 'action_17c_c_retry_working_directory_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
