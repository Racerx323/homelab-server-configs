#!/usr/bin/env bash
# shellcheck disable=SC2016 # Extract and evaluate literal production source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_runner_sha256=d38a963934d3e063481e8f81a189fe432cd7002683ae6349d341cbde27c0e5e5
readonly historical_driver_sha256=b67d9fe11d535c1767a1a70c8fe334bf74e007ec2915dd19ca254e72bb99121b
readonly correction_sha256=f0f1ff9413b50cccb5160f80b52b015c2567fccc274e1d51304cf08fa89b3e0d
readonly rendered_runner_sha256=918efb1938ca102dbfa228441e7358b329ce733560395e160de2d8d1909273e0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_runner="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh"
readonly historical_driver="$caddy_root/scripts/stage-node-b-unbound-primary-action17e.sh"
readonly correction="$caddy_root/scripts/correct-node-b-unbound-primary-working-directory-action17e-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_hash() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

extract_remote_command_block() {
    local source=$1

    awk '
        $0 == "printf -v remote_command \\" {
            print
            getline
            print
            getline
            print
            found++
        }
        END {
            if (found != 1) {
                exit 42
            }
        }
    ' "$source"
}

write_command_harness() {
    local source=$1
    local encoded_driver=$2
    local destination=$3

    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            "remote_script=$encoded_driver"
        extract_remote_command_block "$source"
        printf '%s\n' 'printf "%s\n" "$remote_command"'
    } >"$destination"
}

run_static_test() {
    local test_dir

    verify_hash "$historical_runner" "$historical_runner_sha256"
    verify_hash "$historical_driver" "$historical_driver_sha256"
    verify_hash "$correction" "$correction_sha256"
    bash -n "$historical_runner" "$historical_driver" "$correction"
    "$correction" --self-test >/dev/null

    test_dir=$(mktemp -d /tmp/caddy-action17e-working-directory-static.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    "$correction" --render-runner "$historical_runner" >"$test_dir/runner"
    verify_hash "$test_dir/runner" "$rendered_runner_sha256"
    bash -n "$test_dir/runner"
    diff -U0 "$historical_runner" "$test_dir/runner" \
        >"$test_dir/runner.diff" || true
    [[ "$(grep -Ec '^-[^-]' "$test_dir/runner.diff")" -eq 1 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/runner.diff")" -eq 1 ]]
    grep -Fq \
        'sudo -n /bin/bash -c "$(printf %%s %q | base64 -d)"' \
        "$historical_runner"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -c" \
        "$test_dir/runner"
    cmp --silent "$historical_driver" "$historical_driver"
    printf 'action_17e_working_directory_static_regression_complete=true\n'
}

run_production_test() {
    local test_dir fixture_driver encoded_driver
    local historical_command corrected_command

    test_dir=$(mktemp -d /tmp/caddy-action17e-working-directory-production.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    install -d -m 0700 \
        "$test_dir/inherited" "$test_dir/payload"
    printf 'candidate\n' >"$test_dir/payload/pihole.conf"

    fixture_driver=$(
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'printf "observed_pwd=%s\n" "$PWD"' \
            'tar -tf -'
    )
    encoded_driver=$(printf '%s' "$fixture_driver" | base64 -w 0)

    "$correction" --render-runner "$historical_runner" >"$test_dir/runner"
    write_command_harness \
        "$historical_runner" "$encoded_driver" "$test_dir/historical-harness"
    write_command_harness \
        "$test_dir/runner" "$encoded_driver" "$test_dir/corrected-harness"
    bash -n "$test_dir/historical-harness" "$test_dir/corrected-harness"
    historical_command=$(/bin/bash "$test_dir/historical-harness")
    corrected_command=$(/bin/bash "$test_dir/corrected-harness")
    historical_command=${historical_command#sudo -n }
    corrected_command=${corrected_command#sudo -n }

    (
        cd "$test_dir/inherited"
        tar -C "$test_dir/payload" -cf - pihole.conf |
            /bin/bash -c "$historical_command"
    ) >"$test_dir/historical.out" 2>"$test_dir/historical.err"
    (
        cd "$test_dir/inherited"
        tar -C "$test_dir/payload" -cf - pihole.conf |
            /bin/bash -c "$corrected_command"
    ) >"$test_dir/corrected.out" 2>"$test_dir/corrected.err"

    [[ ! -s "$test_dir/historical.err" ]]
    [[ ! -s "$test_dir/corrected.err" ]]
    grep -Fxq "observed_pwd=$test_dir/inherited" \
        "$test_dir/historical.out"
    grep -Fxq 'observed_pwd=/' "$test_dir/corrected.out"
    grep -Fxq 'pihole.conf' "$test_dir/historical.out"
    grep -Fxq 'pihole.conf' "$test_dir/corrected.out"
    printf 'historical_non_root_working_directory_reproduced=true\n'
    printf 'corrected_root_working_directory_passed=true\n'
    printf 'tar_payload_continuity_passed=true\n'
    printf 'ssh_network_contact_performed=false\n'
    printf 'action_17e_working_directory_production_regression_complete=true\n'
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
