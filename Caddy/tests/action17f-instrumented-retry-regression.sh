#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match and execute literal rendered production source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly instrumentation_sha256=6335840327e600ee4c2ded4e6e5090ded0e2aafa2c2d25643c6efd063ad5934c
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
readonly instrumentation="$caddy_root/scripts/instrument-node-b-unbound-local-zone-action17f-retry.sh"
readonly historical_driver="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"
readonly historical_runner="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
readonly historical_regression="$script_dir/action17f-node-b-unbound-local-zone-stage-regression.sh"
readonly inspector="$caddy_root/scripts/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

render_all() {
    local destination=$1

    "$instrumentation" --render-driver >"$destination/driver"
    "$instrumentation" --render-regression >"$destination/regression"
    "$instrumentation" --render-runner >"$destination/runner"
}

verify_embedded_payload() {
    local variable_name=$1
    local expected_hash=$2
    local source=$3
    local encoded

    encoded=$(
        awk -F= -v variable_name="$variable_name" '
            $1 == "readonly " variable_name {
                print substr($0, index($0, "=") + 1)
                found++
            }
            END {
                if (found != 1) {
                    exit 42
                }
            }
        ' "$source"
    )
    [[ "$(printf '%s' "$encoded" | base64 -d | sha256sum |
        awk '{ print $1 }')" == "$expected_hash" ]]
}

run_static_test() {
    local test_dir

    verify_file "$instrumentation" "$instrumentation_sha256"
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$historical_regression" "$historical_regression_sha256"
    verify_file "$inspector" "$inspector_sha256"
    bash -n \
        "$instrumentation" "$historical_driver" "$historical_runner" \
        "$historical_regression" "$inspector"

    test_dir=$(mktemp -d /tmp/caddy-action17f-retry-static.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    render_all "$test_dir"
    verify_file "$test_dir/driver" "$rendered_driver_sha256"
    verify_file "$test_dir/regression" "$rendered_regression_sha256"
    verify_file "$test_dir/runner" "$rendered_runner_sha256"
    bash -n "$test_dir/driver" "$test_dir/regression" "$test_dir/runner"
    /bin/bash "$test_dir/driver" --self-test >/dev/null
    verify_embedded_payload \
        instrumentation_script_b64 "$inspector_sha256" "$test_dir/driver"
    verify_embedded_payload \
        transactional_driver_b64 "$historical_driver_sha256" "$test_dir/driver"

    diff -U0 "$historical_runner" "$test_dir/runner" \
        >"$test_dir/runner.diff" || true
    [[ "$(grep -Ec '^-[^-]' "$test_dir/runner.diff")" -eq 2 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/runner.diff")" -eq 2 ]]
    diff -U0 "$historical_regression" "$test_dir/regression" \
        >"$test_dir/regression.diff" || true
    [[ "$(grep -Ec '^-[^-]' "$test_dir/regression.diff")" -eq 1 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/regression.diff")" -eq 1 ]]
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -c" \
        "$test_dir/runner"
    grep -Fq 'action_17f_retry_instrumented_prewrite_accepted=true' \
        "$test_dir/driver"
    grep -Fq 'action_17f_retry_instrumented_prewrite_rejected=true' \
        "$test_dir/driver"
    grep -Fq \
        'exec /bin/bash -c "$(printf "%s" "$transactional_driver_b64" | base64 -d)"' \
        "$test_dir/driver"
    printf 'action_17f_retry_instrumented_static_regression_complete=true\n'
}

rewrite_fixture_payloads() {
    local source=$1
    local instrumentation_payload=$2
    local driver_payload=$3
    local destination=$4

    awk \
        -v instrumentation_payload="$instrumentation_payload" \
        -v driver_payload="$driver_payload" '
        /^readonly instrumentation_script_b64=/ {
            print "readonly instrumentation_script_b64=" instrumentation_payload
            instrumentation_changed++
            next
        }
        /^readonly transactional_driver_b64=/ {
            print "readonly transactional_driver_b64=" driver_payload
            driver_changed++
            next
        }
        { print }
        END {
            if (instrumentation_changed != 1 || driver_changed != 1) {
                exit 42
            }
        }
    ' "$source" >"$destination"
}

run_production_test() {
    local test_dir success_inspector mismatch_inspector fixture_driver
    local success_inspector_b64 mismatch_inspector_b64 fixture_driver_b64
    local mismatch_status

    test_dir=$(mktemp -d /tmp/caddy-action17f-retry-production.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    install -d -m 0700 "$test_dir/inherited" "$test_dir/payload"
    printf 'candidate\n' >"$test_dir/payload/pihole0-local-zone.conf"
    "$instrumentation" --render-driver >"$test_dir/production-driver"

    success_inspector=$(
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'printf "observed_instrumentation_pwd=%s\n" "$PWD"' \
            'readonly -a records=(' \
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
            'printf "%s\n" "${records[@]}"'
    )
    mismatch_inspector=$(
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'printf "observed_instrumentation_pwd=%s\n" "$PWD"' \
            'readonly -a records=(' \
            '    working_directory_is_root=true' \
            '    prewrite_working_directory_is_root=true' \
            '    prewrite_assertion_count=55' \
            '    prewrite_failed_assertion_count=1' \
            '    action_17f_a_conclusion=prewrite_prerequisite_mismatch' \
            '    action_17f_a_node_b_prewrite_diagnostic_complete=true' \
            ')' \
            'printf "%s\n" "${records[@]}"'
    )
    fixture_driver=$(
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'printf "transactional_driver_reached=true\n"' \
            'printf "observed_transactional_pwd=%s\n" "$PWD"' \
            'tar -tf -'
    )
    success_inspector_b64=$(printf '%s' "$success_inspector" | base64 -w 0)
    mismatch_inspector_b64=$(printf '%s' "$mismatch_inspector" | base64 -w 0)
    fixture_driver_b64=$(printf '%s' "$fixture_driver" | base64 -w 0)
    rewrite_fixture_payloads \
        "$test_dir/production-driver" \
        "$success_inspector_b64" "$fixture_driver_b64" \
        "$test_dir/success-driver"
    rewrite_fixture_payloads \
        "$test_dir/production-driver" \
        "$mismatch_inspector_b64" "$fixture_driver_b64" \
        "$test_dir/mismatch-driver"
    bash -n "$test_dir/success-driver" "$test_dir/mismatch-driver"

    (
        cd "$test_dir/inherited"
        tar -C "$test_dir/payload" -cf - pihole0-local-zone.conf |
            /bin/bash -c \
                "cd / && exec /bin/bash '$test_dir/success-driver'"
    ) >"$test_dir/success.out" 2>"$test_dir/success.err"
    [[ ! -s "$test_dir/success.err" ]]
    grep -Fxq 'observed_instrumentation_pwd=/' "$test_dir/success.out"
    grep -Fxq 'action_17f_retry_instrumented_prewrite_accepted=true' \
        "$test_dir/success.out"
    grep -Fxq 'transactional_driver_reached=true' "$test_dir/success.out"
    grep -Fxq 'observed_transactional_pwd=/' "$test_dir/success.out"
    grep -Fxq 'pihole0-local-zone.conf' "$test_dir/success.out"

    set +e
    (
        cd "$test_dir/inherited"
        tar -C "$test_dir/payload" -cf - pihole0-local-zone.conf |
            /bin/bash -c \
                "cd / && exec /bin/bash '$test_dir/mismatch-driver'"
    ) >"$test_dir/mismatch.out" 2>"$test_dir/mismatch.err"
    mismatch_status=$?
    set -e
    [[ "$mismatch_status" -ne 0 ]]
    grep -Fxq 'observed_instrumentation_pwd=/' "$test_dir/mismatch.out"
    grep -Fxq 'action_17f_retry_instrumented_prewrite_rejected=true' \
        "$test_dir/mismatch.err"
    if grep -Fq 'transactional_driver_reached=true' \
        "$test_dir/mismatch.out" "$test_dir/mismatch.err"; then
        printf 'Transactional driver ran after rejected instrumentation.\n' >&2
        exit 1
    fi
    printf 'action_17f_retry_instrumented_root_pwd_passed=true\n'
    printf 'action_17f_retry_tar_payload_continuity_passed=true\n'
    printf 'action_17f_retry_mismatch_blocked_driver=true\n'
    printf 'ssh_network_contact_performed=false\n'
    printf 'action_17f_retry_instrumented_production_regression_complete=true\n'
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
