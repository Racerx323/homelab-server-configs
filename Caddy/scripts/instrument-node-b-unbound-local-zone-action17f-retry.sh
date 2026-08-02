#!/usr/bin/env bash
# shellcheck disable=SC2016 # Render literal Bash source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly historical_runner_sha256=700097f301c49bfef34b60dc6fdeb4e8c0b03282f2ccf7831fa306a930fe7c33
readonly historical_regression_sha256=4849d4057405d996415c62e3f44998e145936697420327147cd269209d25ac60
readonly inspector_sha256=f380b441aad02b981669d8b251bae67633c49d8769d2e424e20c52b6c8cd3081
readonly rendered_driver_sha256=8d51f4f3d070719069653b95a3f584a2bb370f4979779e4684e4bd0f5f8d3ea1
readonly rendered_regression_sha256=40e0c294ef7b1205e7bb26c1d17f68e519fb7b6c596c208804746ca057db49e3
readonly rendered_runner_sha256=b01aae1ebbee47cd4493e54b1a7f73813e831cb64c858716c5596503de6b0107

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"
readonly historical_runner="$script_dir/run-node-b-unbound-local-zone-stage-action17f.sh"
readonly historical_regression="$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
readonly inspector="$script_dir/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_historical_sources() {
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$historical_regression" "$historical_regression_sha256"
    verify_file "$inspector" "$inspector_sha256"
    bash -n \
        "$historical_driver" "$historical_runner" \
        "$historical_regression" "$inspector"
}

render_driver() {
    local instrumentation_script transactional_driver

    verify_historical_sources
    instrumentation_script=$(base64 -w 0 <"$inspector")
    transactional_driver=$(base64 -w 0 <"$historical_driver")
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '' \
        'set -euo pipefail' \
        'set +x' \
        'umask 077' \
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
        'export PATH' \
        'readonly PATH' \
        '' \
        "readonly instrumentation_script_b64=$instrumentation_script" \
        "readonly transactional_driver_b64=$transactional_driver" \
        "readonly instrumentation_script_sha256=$inspector_sha256" \
        "readonly transactional_driver_sha256=$historical_driver_sha256" \
        '' \
        'file_hash_from_b64() {' \
        '    printf "%s" "$1" | base64 -d | sha256sum | awk '"'"'{ print $1 }'"'"'' \
        '}' \
        '' \
        'require_one() {' \
        '    local record=$1' \
        '    local transcript=$2' \
        '' \
        '    [[ "$(grep -Fxc "$record" <<<"$transcript")" -eq 1 ]]' \
        '}' \
        '' \
        'if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then' \
        '    [[ "$(file_hash_from_b64 "$instrumentation_script_b64")" == "$instrumentation_script_sha256" ]]' \
        '    [[ "$(file_hash_from_b64 "$transactional_driver_b64")" == "$transactional_driver_sha256" ]]' \
        '    printf "%s" "$transactional_driver_b64" | base64 -d | /bin/bash -s -- --self-test >/dev/null' \
        '    printf "action_17f_retry_instrumented_driver_self_test_complete=true\n"' \
        '    exit 0' \
        'elif (($#)); then' \
        '    printf "Usage: %s [--self-test]\n" "${0##*/}" >&2' \
        '    exit 2' \
        'fi' \
        '' \
        'instrumentation_status=0' \
        'instrumentation_output=$(' \
        '    printf "%s" "$instrumentation_script_b64" |' \
        '        base64 -d | /bin/bash -s --' \
        ') || instrumentation_status=$?' \
        'printf "%s\n" "$instrumentation_output"' \
        'instrumentation_valid=true' \
        '[[ "$instrumentation_status" -eq 0 ]] || instrumentation_valid=false' \
        'readonly -a required_records=(' \
        '    working_directory_is_root=true' \
        '    prewrite_working_directory_is_root=true' \
        '    prewrite_assertion_count=55' \
        '    prewrite_failed_assertion_count=0' \
        '    action_17f_a_conclusion=all_prewrite_prerequisites_pass' \
        '    remote_paths_created=false' \
        '    dns_queries_performed=false' \
        '    dns_configuration_mutations=false' \
        '    service_mutations=false' \
        '    persistent_mutations=false' \
        '    action_17f_a_node_b_prewrite_diagnostic_complete=true' \
        ')' \
        'for required_record in "${required_records[@]}"; do' \
        '    require_one "$required_record" "$instrumentation_output" ||' \
        '        instrumentation_valid=false' \
        'done' \
        'if [[ "$instrumentation_valid" != true ]]; then' \
        '    printf "action_17f_retry_instrumented_prewrite_rejected=true\n" >&2' \
        '    exit 1' \
        'fi' \
        'printf "action_17f_retry_instrumented_prewrite_accepted=true\n"' \
        'exec /bin/bash -c "$(printf "%s" "$transactional_driver_b64" | base64 -d)"'
}

render_regression() {
    verify_historical_sources
    awk '
        $0 == "readonly driver=\"$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh\"" {
            print "readonly driver=\"$caddy_root/historical/stage-node-b-unbound-local-zone-action17f.sh\""
            changed++
            next
        }
        { print }
        END {
            if (changed != 1) {
                exit 42
            }
        }
    ' "$historical_regression"
}

render_runner() {
    verify_historical_sources
    awk \
        -v driver_hash="$rendered_driver_sha256" \
        -v regression_hash="$rendered_regression_sha256" '
        /^readonly driver_sha256=/ {
            print "readonly driver_sha256=" driver_hash
            driver_changed++
            next
        }
        /^readonly regression_sha256=/ {
            print "readonly regression_sha256=" regression_hash
            regression_changed++
            next
        }
        { print }
        END {
            if (driver_changed != 1 || regression_changed != 1) {
                exit 42
            }
        }
    ' "$historical_runner"
}

usage() {
    printf '%s\n' \
        "Usage: ${0##*/} --render-driver" \
        "       ${0##*/} --render-regression" \
        "       ${0##*/} --render-runner" \
        "       ${0##*/} --self-test"
}

case "${1:-}" in
    --render-driver)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 2
        }
        render_driver
        ;;
    --render-regression)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 2
        }
        render_regression
        ;;
    --render-runner)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 2
        }
        render_runner
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        verify_historical_sources
        test_dir=$(mktemp -d /tmp/caddy-action17f-retry-instrument.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_driver >"$test_dir/driver"
        render_regression >"$test_dir/regression"
        render_runner >"$test_dir/runner"
        verify_file "$test_dir/driver" "$rendered_driver_sha256"
        verify_file "$test_dir/regression" "$rendered_regression_sha256"
        verify_file "$test_dir/runner" "$rendered_runner_sha256"
        bash -n "$test_dir/driver" "$test_dir/regression" "$test_dir/runner"
        /bin/bash "$test_dir/driver" --self-test >/dev/null
        printf 'action_17f_retry_instrumentation_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
