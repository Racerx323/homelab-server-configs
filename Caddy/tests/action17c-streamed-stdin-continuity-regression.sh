#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly correction="$caddy_root/scripts/correct-restricted-transport-action17c-retry.sh"
readonly historical_driver="$caddy_root/scripts/validate-node-a-to-node-b-restricted-transport-action17c.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c.sh"
readonly correction_sha256=693a75d7cfb1c308a1367111c5891e3eae3fac7dc1e4bfd8ea4a43604f2229b6
readonly historical_driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0
readonly historical_runner_sha256=d2b8672f7b3c336e4dfe9e1bf7f12b61290e8a993a8c92eef252b3a5b03f510b
readonly rendered_driver_sha256=3259b979e64ccee667e2a81ac9683c21d140331c0d1f44d6c6e41bf88a7b31dd
readonly rendered_runner_sha256=c88ab6f91f3adaeab6a7cd5ba7c2013d8d62bc7d393601a370c140f50e1eb795

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

run_stream_fixture() {
    local mode=$1
    local destination=$2
    local fake_path=$3
    local ssh_options='-4 -T'

    if [[ "$mode" == corrected ]]; then
        ssh_options='-4 -n -T'
    fi

    {
        # Intentional literal Bash fixture.
        # shellcheck disable=SC2016
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -u' \
            'status=0' \
            "ssh $ssh_options caddy-sync@10.1.0.54 probe || status=\$?" \
            '[[ "$status" -eq 126 ]]'
        sleep 0.2
        printf '%s\n' \
            "printf 'post_probe_marker=%s\\n' '$mode'"
    } | env PATH="$fake_path:/usr/bin:/bin" bash -s >"$destination"
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$correction")" == "$correction_sha256" ]]
[[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
[[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]]
"$correction" --self-test >/dev/null

test_dir=$(mktemp -d /tmp/caddy-action17c-stream-regression.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT
"$correction" --render-driver "$historical_driver" >"$test_dir/driver"
"$correction" --render-runner "$historical_runner" >"$test_dir/runner"
[[ "$(file_hash "$test_dir/driver")" == "$rendered_driver_sha256" ]]
[[ "$(file_hash "$test_dir/runner")" == "$rendered_runner_sha256" ]]
bash -n "$test_dir/driver" "$test_dir/runner"

historical_line="        ssh \"\$address_family\" -T \\"
corrected_line="        ssh \"\$address_family\" -n -T \\"
[[ "$(grep -Fxc "$historical_line" "$historical_driver")" -eq 1 ]]
[[ "$(grep -Fxc "$corrected_line" "$test_dir/driver")" -eq 1 ]]
[[ "$(grep -Fxc "$historical_line" "$test_dir/driver")" -eq 0 ]]

mkdir "$test_dir/fake-bin"
# Intentional literal Bash fixture.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'detached=false' \
    'for argument in "$@"; do' \
    '    if [[ "$argument" == -n ]]; then' \
    '        detached=true' \
    '    fi' \
    'done' \
    'if [[ "$detached" == false ]]; then' \
    '    cat >/dev/null' \
    'fi' \
    'exit 126' >"$test_dir/fake-bin/ssh"
chmod 0755 "$test_dir/fake-bin/ssh"

historical_status=0
run_stream_fixture historical "$test_dir/historical.out" \
    "$test_dir/fake-bin" || historical_status=$?
[[ "$historical_status" -eq 0 || "$historical_status" -eq 126 ]]
[[ ! -s "$test_dir/historical.out" ]]

run_stream_fixture corrected "$test_dir/corrected.out" "$test_dir/fake-bin"
grep -Fxq 'post_probe_marker=corrected' "$test_dir/corrected.out"
[[ "$(wc -l <"$test_dir/corrected.out")" -eq 1 ]]

printf 'action_17c_streamed_stdin_continuity_regression_complete=true\n'
