#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0
readonly historical_runner_sha256=d2b8672f7b3c336e4dfe9e1bf7f12b61290e8a993a8c92eef252b3a5b03f510b
readonly rendered_driver_sha256=3259b979e64ccee667e2a81ac9683c21d140331c0d1f44d6c6e41bf88a7b31dd
readonly rendered_runner_sha256=c88ab6f91f3adaeab6a7cd5ba7c2013d8d62bc7d393601a370c140f50e1eb795

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_driver="$script_dir/validate-node-a-to-node-b-restricted-transport-action17c.sh"
readonly historical_runner="$script_dir/run-node-a-to-node-b-restricted-transport-action17c.sh"

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

render_driver() {
    local source_path=$1

    verify_source "$source_path" "$historical_driver_sha256"
    awk '
        $0 == "        ssh \"$address_family\" -T \\" {
            print "        ssh \"$address_family\" -n -T \\"
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

render_runner() {
    local source_path=$1

    verify_source "$source_path" "$historical_runner_sha256"
    awk -v driver_hash="$rendered_driver_sha256" '
        $0 == "readonly driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0" {
            print "readonly driver_sha256=" driver_hash
            hash_changed++
            next
        }
        $0 == "readonly driver=\"$script_dir/validate-node-a-to-node-b-restricted-transport-action17c.sh\"" {
            print "readonly driver=\"$script_dir/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh\""
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
        "Usage: ${0##*/} --render-driver SOURCE" \
        "       ${0##*/} --render-runner SOURCE" \
        "       ${0##*/} --self-test"
}

case "${1:-}" in
    --render-driver)
        [[ $# -eq 2 ]] || {
            usage >&2
            exit 2
        }
        render_driver "$2"
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
            "$historical_driver_sha256" \
            "$historical_runner_sha256"; do
            [[ "$value" =~ ^[0-9a-f]{64}$ ]]
        done
        [[ "$rendered_driver_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$rendered_runner_sha256" =~ ^[0-9a-f]{64}$ ]]
        self_test_dir=$(mktemp -d /tmp/caddy-action17c-correction-self-test.XXXXXX)
        trap 'rm -rf -- "$self_test_dir"' EXIT
        render_driver "$historical_driver" >"$self_test_dir/driver"
        render_runner "$historical_runner" >"$self_test_dir/runner"
        [[ "$(file_hash "$self_test_dir/driver")" == "$rendered_driver_sha256" ]]
        [[ "$(file_hash "$self_test_dir/runner")" == "$rendered_runner_sha256" ]]
        expected_driver_line="        ssh \"\$address_family\" -n -T \\"
        expected_runner_path="readonly driver=\"\$script_dir/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh\""
        grep -Fxq "$expected_driver_line" "$self_test_dir/driver"
        [[ "$(grep -Fxc "$expected_driver_line" \
            "$self_test_dir/driver")" -eq 1 ]]
        grep -Fxq \
            "readonly driver_sha256=$rendered_driver_sha256" \
            "$self_test_dir/runner"
        grep -Fxq "$expected_runner_path" "$self_test_dir/runner"
        printf 'action_17c_retry_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
