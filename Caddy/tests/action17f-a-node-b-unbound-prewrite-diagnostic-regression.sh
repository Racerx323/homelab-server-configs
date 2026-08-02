#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match and evaluate literal production source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=f380b441aad02b981669d8b251bae67633c49d8769d2e424e20c52b6c8cd3081
readonly failed_runner_sha256=700097f301c49bfef34b60dc6fdeb4e8c0b03282f2ccf7831fa306a930fe7c33
readonly failed_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"
readonly failed_runner="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
readonly failed_driver="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"

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
    verify_hash "$inspector" "$inspector_sha256"
    verify_hash "$failed_runner" "$failed_runner_sha256"
    verify_hash "$failed_driver" "$failed_driver_sha256"
    bash -n "$inspector" "$failed_runner" "$failed_driver"
    "$inspector" --self-test >/dev/null

    grep -Fq 'prewrite_assertion_count=55' "$inspector"
    grep -Fq 'record_assertion working_directory_is_root' "$inspector"
    grep -Fq 'record_assertion primary_meta_content_matches' "$inspector"
    grep -Fq 'record_assertion live_state_snapshots_stable' "$inspector"
    grep -Fq 'remote_paths_created=false' "$inspector"
    grep -Fq 'persistent_mutations=false' "$inspector"
    grep -Fq \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -c" \
        "$failed_runner"
    grep -Fq '[[ "$PWD" == / ]]' "$failed_driver"

    if grep -Eq \
        '^[[:space:]]*(install|cp|mv|rm|touch|truncate|chmod|chown|tee)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17f-a inspector contains a write command.\n' >&2
        exit 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|try-restart|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17f-a inspector contains a query or service mutation.\n' \
            >&2
        exit 1
    fi
    printf 'action_17f_a_node_b_unbound_prewrite_static_regression_complete=true\n'
}

run_production_cd_test() {
    local test_dir fixture_driver encoded_driver remote_command

    test_dir=$(mktemp -d /tmp/caddy-action17f-a-cd-production.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    install -d -m 0700 "$test_dir/inherited" "$test_dir/payload"
    printf 'candidate\n' >"$test_dir/payload/pihole0-local-zone.conf"
    fixture_driver=$(
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'printf "observed_pwd=%s\n" "$PWD"' \
            'tar -tf -'
    )
    encoded_driver=$(printf '%s' "$fixture_driver" | base64 -w 0)
    write_command_harness \
        "$failed_runner" "$encoded_driver" "$test_dir/command-harness"
    bash -n "$test_dir/command-harness"
    remote_command=$(/bin/bash "$test_dir/command-harness")
    remote_command=${remote_command#sudo -n }
    (
        cd "$test_dir/inherited"
        tar -C "$test_dir/payload" -cf - pihole0-local-zone.conf |
            /bin/bash -c "$remote_command"
    ) >"$test_dir/output" 2>"$test_dir/error"
    [[ ! -s "$test_dir/error" ]]
    grep -Fxq 'observed_pwd=/' "$test_dir/output"
    grep -Fxq 'pihole0-local-zone.conf' "$test_dir/output"
    printf 'action_17f_remote_command_cd_root_passed=true\n'
    printf 'action_17f_tar_payload_continuity_passed=true\n'
    printf 'ssh_network_contact_performed=false\n'
    printf 'action_17f_a_cd_production_regression_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_static_test
        ;;
    --production-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_production_cd_test
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
