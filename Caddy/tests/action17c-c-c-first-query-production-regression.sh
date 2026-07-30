#!/usr/bin/env bash
# shellcheck disable=SC1003,SC2016 # Generate and match literal Bash source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly historical_runner_sha256=db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6
readonly correction_sha256=214efa540b42de756fb467903af43a8d73161b5f3654987c4697057a0c6b4e48
readonly rendered_collector_sha256=1a96099b69a1f4a8672e09ec49158f779e612d08a46e8c9333c38aff9f7d6624
readonly rendered_runner_sha256=e1921118134ff70f4ef1d93e0a8df9490fa5b14033f689d3b416c4ebc08071b3

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_collector="$caddy_root/scripts/diagnose-dns-path-authority-action17c-c-c.sh"
readonly historical_runner="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh"
readonly correction="$caddy_root/scripts/correct-dns-path-work-dir-action17c-c-c-retry.sh"

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

extract_run_query() {
    local source=$1

    awk '
        $0 == "run_query() {" {
            emit = 1
        }
        emit {
            print
        }
        emit && $0 == "}" {
            exit
        }
    ' "$source"
}

write_production_fixture() {
    local source=$1
    local destination=$2

    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'set +x' \
            'PATH=/usr/bin:/bin' \
            'export PATH' \
            'file_hash() {' \
            '    sha256sum "$1" | awk '\''{ print $1 }'\''' \
            '}' \
            'encode_value() {' \
            '    printf '\''%s'\'' "$1" | base64 -w 0' \
            '}'
        extract_run_query "$source"
        # The function shadows the external command and returns a deterministic
        # response, so this regression performs no DNS or network operation.
        printf '%s\n' \
            'timeout() {' \
            '    printf "%s\n" \' \
            '        ";; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1" \' \
            '        ";; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0" \' \
            '        "pihole00.local.theama.co. 60 IN A 10.1.0.54"' \
            '}' \
            'work_dir=$(mktemp -d /tmp/caddy-action17c-c-c-first-query-fixture.XXXXXX)' \
            'readonly work_dir' \
            'trap '\''rm -rf -- "$work_dir"'\'' EXIT' \
            'run_query local_unbound_peer_a 127.0.0.1 5335 pihole00.local.theama.co A 10.1.0.54 "$work_dir"' \
            'printf "first_query_completed=true\n"'
    } >"$destination"
}

run_static_test() {
    local test_dir

    verify_hash "$historical_collector" "$historical_collector_sha256"
    verify_hash "$historical_runner" "$historical_runner_sha256"
    verify_hash "$correction" "$correction_sha256"
    "$correction" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-first-query-static.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    render_artifacts "$test_dir"
    diff -U0 "$historical_collector" "$test_dir/collector" \
        >"$test_dir/collector.diff" || true
    [[ "$(grep -Ec '^-[^-]' "$test_dir/collector.diff")" -eq 4 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/collector.diff")" -eq 4 ]]
    [[ "$(grep -Ec '^[+-][^+-]' "$test_dir/collector.diff")" -eq 8 ]]
    grep -Fxq '    local work_dir=$7' "$historical_collector"
    grep -Fxq '    local query_work_dir=$7' "$test_dir/collector"
    [[ "$(grep -Fxc '    local work_dir=$7' "$test_dir/collector" || true)" -eq 0 ]]
    grep -Fxq \
        "readonly collector_sha256=$rendered_collector_sha256" \
        "$test_dir/runner"
    # shellcheck disable=SC2016 # Match literal rendered source text.
    grep -Fxq \
        'readonly collector="$script_dir/diagnose-dns-path-authority-action17c-c-c-retry.sh"' \
        "$test_dir/runner"
    printf 'action_17c_c_c_first_query_static_regression_complete=true\n'
}

run_production_test() {
    local test_dir historical_status corrected_status

    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-first-query-production.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    "$correction" --render-collector "$historical_collector" \
        >"$test_dir/corrected-collector"
    write_production_fixture "$historical_collector" "$test_dir/historical.sh"
    write_production_fixture "$test_dir/corrected-collector" "$test_dir/corrected.sh"
    bash -n "$test_dir/historical.sh" "$test_dir/corrected.sh"

    historical_status=0
    /bin/bash "$test_dir/historical.sh" \
        >"$test_dir/historical.out" 2>"$test_dir/historical.err" ||
        historical_status=$?
    [[ "$historical_status" -eq 1 ]]
    [[ ! -s "$test_dir/historical.out" ]]
    grep -Fq 'work_dir: readonly variable' "$test_dir/historical.err"

    corrected_status=0
    /bin/bash "$test_dir/corrected.sh" \
        >"$test_dir/corrected.out" 2>"$test_dir/corrected.err" ||
        corrected_status=$?
    [[ "$corrected_status" -eq 0 ]]
    [[ ! -s "$test_dir/corrected.err" ]]
    grep -Fxq 'local_unbound_peer_a_class=expected_present' \
        "$test_dir/corrected.out"
    grep -Fxq 'local_unbound_peer_a_expected_match=true' \
        "$test_dir/corrected.out"
    grep -Fxq 'first_query_completed=true' "$test_dir/corrected.out"

    printf 'historical_first_query_readonly_collision_reproduced=true\n'
    printf 'corrected_first_query_completed=true\n'
    printf 'dns_network_operations_performed=false\n'
    printf 'action_17c_c_c_first_query_production_regression_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_static_test
        ;;
    --production-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_production_test
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
