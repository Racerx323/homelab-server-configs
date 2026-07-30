#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_collector_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d
readonly historical_runner_sha256=d0fa596f3912288b24645fa6fa9bbbfe15fa0fffd38d7d6308f11041a7bdb4da
readonly correction_sha256=f9e998a536ef830c4dc0d4b64d1bc30b86dfdc0fd4ee26853ee6e348e6d455d8
readonly rendered_collector_sha256=c99a7be13a20cbc5b2af7bc74790bd06b7f3afe62f9b73b41de42171a2ab4efd
readonly rendered_runner_sha256=5bf1e9a92cc4b1ad63e2a7dfba0467a40edecb9fb7ef0fcb80e66da1f9288263

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_collector="$caddy_root/scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh"
readonly correction="$caddy_root/scripts/correct-peer-resolution-readonly-shadow-action17c-c-b-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_hash() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

render_artifacts() {
    local destination=$1

    "$correction" --render-collector "$historical_collector" \
        >"$destination/collector"
    "$correction" --render-runner "$historical_runner" \
        >"$destination/runner"
    verify_hash "$destination/collector" "$rendered_collector_sha256"
    verify_hash "$destination/runner" "$rendered_runner_sha256"
    bash -n "$destination/collector" "$destination/runner"
}

run_static_test() {
    local test_dir function_start function_end

    verify_hash "$historical_collector" "$historical_collector_sha256"
    verify_hash "$historical_runner" "$historical_runner_sha256"
    verify_hash "$correction" "$correction_sha256"
    "$correction" --self-test >/dev/null

    test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-second-snapshot-static.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    render_artifacts "$test_dir"
    diff -U0 "$historical_collector" "$test_dir/collector" \
        >"$test_dir/collector.diff" || true
    [[ "$(grep -Ec '^[+-][^+-]' "$test_dir/collector.diff")" -eq 10 ]]
    [[ "$(grep -Ec '^-[^-]' "$test_dir/collector.diff")" -eq 5 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/collector.diff")" -eq 5 ]]

    function_start=$(
        grep -n '^resolver_state() {' "$test_dir/collector" | cut -d: -f1
    )
    function_end=$(
        awk -v start="$function_start" \
            'NR > start && $0 == "}" { print NR; exit }' \
            "$test_dir/collector"
    )
    [[ "$function_start" =~ ^[0-9]+$ && "$function_end" =~ ^[0-9]+$ ]]
    [[ "$(sed -n "${function_start},${function_end}p" "$test_dir/collector" |
        grep -Fxc '    local resolv_target')" -eq 1 ]]
    [[ "$(grep -Fxc 'readonly resolv_target' "$test_dir/collector" || true)" -eq 0 ]]
    [[ "$(grep -Fxc 'readonly provenance_resolv_target' "$test_dir/collector")" -eq 1 ]]
    [[ "$(grep -Ec '^resolver_state >.*state-before' "$test_dir/collector")" -eq 1 ]]
    [[ "$(grep -Ec '^resolver_state >.*state-after' "$test_dir/collector")" -eq 1 ]]
    [[ "$(grep -Fxc \
        'readonly diagnostic_sha256=c99a7be13a20cbc5b2af7bc74790bd06b7f3afe62f9b73b41de42171a2ab4efd' \
        "$test_dir/runner")" -eq 1 ]]
    # shellcheck disable=SC2016 # Match literal source text.
    [[ "$(grep -Fxc \
        'readonly diagnostic="$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b-retry.sh"' \
        "$test_dir/runner")" -eq 1 ]]

    printf 'action_17c_c_b_second_snapshot_static_regression_complete=true\n'
}

write_boundary_fixture() {
    local destination=$1
    local provenance_name=$2

    {
        # shellcheck disable=SC2016 # Write literal Bash fixture source.
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'resolver_state() {' \
            '    local label=$1' \
            '    local resolv_target' \
            '    resolv_target=/etc/resolv.conf' \
            '    printf "%s_snapshot=%s\n" "$label" "$resolv_target"' \
            '}' \
            'resolver_state before'
        if [[ "$provenance_name" == resolv_target ]]; then
            printf '%s\n' \
                'resolv_target=/etc/resolv.conf' \
                'readonly resolv_target'
        else
            printf '%s\n' \
                'provenance_resolv_target=/etc/resolv.conf' \
                'readonly provenance_resolv_target'
        fi
        printf '%s\n' 'resolver_state after'
    } >"$destination"
}

run_production_boundary_test() {
    local test_dir historical_status corrected_status

    test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-second-snapshot-production.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    write_boundary_fixture "$test_dir/historical.sh" resolv_target
    write_boundary_fixture "$test_dir/corrected.sh" provenance_resolv_target

    historical_status=0
    /bin/bash "$test_dir/historical.sh" \
        >"$test_dir/historical.out" 2>"$test_dir/historical.err" ||
        historical_status=$?
    [[ "$historical_status" -eq 1 ]]
    grep -Fqx 'before_snapshot=/etc/resolv.conf' "$test_dir/historical.out"
    [[ "$(wc -l <"$test_dir/historical.out")" -eq 1 ]]
    grep -Fq 'resolv_target: readonly variable' "$test_dir/historical.err"

    corrected_status=0
    /bin/bash "$test_dir/corrected.sh" \
        >"$test_dir/corrected.out" 2>"$test_dir/corrected.err" ||
        corrected_status=$?
    [[ "$corrected_status" -eq 0 ]]
    grep -Fqx 'before_snapshot=/etc/resolv.conf' "$test_dir/corrected.out"
    grep -Fqx 'after_snapshot=/etc/resolv.conf' "$test_dir/corrected.out"
    [[ "$(wc -l <"$test_dir/corrected.out")" -eq 2 ]]
    [[ ! -s "$test_dir/corrected.err" ]]

    printf 'historical_second_snapshot_readonly_collision_reproduced=true\n'
    printf 'corrected_second_snapshot_completed=true\n'
    printf 'action_17c_c_b_second_snapshot_production_regression_complete=true\n'
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
