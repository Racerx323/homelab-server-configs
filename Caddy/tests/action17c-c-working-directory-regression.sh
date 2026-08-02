#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly correction="$caddy_root/scripts/correct-source-bound-working-directory-action17c-c-retry.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-source-bound-transport-action17c-c.sh"
readonly historical_runner_sha256=b63cd6e48662ad2a7b1604817da21135e735be0c8319090919760398d98d7cf7
readonly rendered_runner_sha256=1cef934ad56a4e6b5d7e0d2024b12607d4462951fba5e234b1f78504a239b5f2

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

run_static_test() {
    local test_dir

    [[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]]
    bash -n "$correction" "$historical_runner"
    "$correction" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-working-directory-static.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    "$correction" --render-runner "$historical_runner" >"$test_dir/runner"
    [[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
    [[ "$(diff -U0 "$historical_runner" "$test_dir/runner" |
        grep -Ec '^[+-]    .*runuser -u caddy-sync')" -eq 2 ]]
    grep -Fxq \
        "    \"sudo -n /bin/bash -c 'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -s -- --connect'\" \\" \
        "$test_dir/runner"
    printf 'action_17c_c_retry_working_directory_static_regression_complete=true\n'
}

run_production_boundary_test() {
    local test_dir historical_status corrected_status

    [[ "$(id -u)" -eq 0 ]]
    id caddy-sync >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-working-directory-production.XXXXXX)
    trap 'chmod 0700 "$test_dir"; rm -rf -- "$test_dir"' RETURN
    chmod 0700 "$test_dir"

    historical_status=0
    (
        cd "$test_dir"
        /usr/sbin/runuser -u caddy-sync -- \
            /bin/bash -c 'find /tmp -maxdepth 0 >/dev/null'
    ) >"$test_dir/historical.out" 2>"$test_dir/historical.err" ||
        historical_status=$?
    [[ "$historical_status" -ne 0 ]]
    grep -Fq \
        'find: Failed to restore initial working directory:' \
        "$test_dir/historical.err"

    corrected_status=0
    (
        cd "$test_dir"
        /bin/bash -c \
            'cd / && exec /usr/sbin/runuser -u caddy-sync -- /bin/bash -c "find /tmp -maxdepth 0 >/dev/null"'
    ) >"$test_dir/corrected.out" 2>"$test_dir/corrected.err" ||
        corrected_status=$?
    [[ "$corrected_status" -eq 0 ]]
    [[ ! -s "$test_dir/corrected.out" ]]
    [[ ! -s "$test_dir/corrected.err" ]]
    printf 'historical_inaccessible_working_directory_reproduced=true\n'
    printf 'corrected_accessible_working_directory_passed=true\n'
    printf 'action_17c_c_retry_working_directory_production_regression_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_static_test
        ;;
    --production-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_production_boundary_test
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
