#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match literal source text in rendered artifacts.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_runner_sha256=d38a963934d3e063481e8f81a189fe432cd7002683ae6349d341cbde27c0e5e5
readonly rendered_runner_sha256=918efb1938ca102dbfa228441e7358b329ce733560395e160de2d8d1909273e0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_runner="$script_dir/run-node-b-unbound-primary-stage-action17e.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_runner() {
    local source_path=$1

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$historical_runner_sha256" ]]
    awk '
        $0 == "printf -v remote_command \\" {
            getline first_argument
            getline second_argument
            if (first_argument != "    \047sudo -n /bin/bash -c \"$(printf %%s %q | base64 -d)\"\047 \\" ||
                second_argument != "    \"$remote_script\"") {
                exit 42
            }
            print "printf -v remote_command \\"
            print "    \"sudo -n /bin/bash -c \047cd / && exec /bin/bash -c \\\"\\$(printf %%s %s | base64 -d)\\\"\047\" \\"
            print second_argument
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
        test_dir=$(mktemp -d /tmp/caddy-action17e-retry-correction.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_runner "$historical_runner" >"$test_dir/runner"
        [[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
        bash -n "$test_dir/runner"
        grep -Fxq \
            "    \"sudo -n /bin/bash -c 'cd / && exec /bin/bash -c \\\"\\\$(printf %%s %s | base64 -d)\\\"'\" \\" \
            "$test_dir/runner"
        if grep -Fq \
            'sudo -n /bin/bash -c "$(printf %%s %q | base64 -d)"' \
            "$test_dir/runner"; then
            printf 'Historical working-directory command remains.\n' >&2
            exit 1
        fi
        printf 'action_17e_retry_working_directory_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
