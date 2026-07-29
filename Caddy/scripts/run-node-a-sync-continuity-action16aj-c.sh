#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=b347376da9c8975ff3ccdba0d87b7f56d77ad77ce11392ccab3222a90eb365a6

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-node-a-sync-continuity-action16aj-c.sh"

verify_sources() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    bash -n "$inspector"
    "$inspector" --self-test >/dev/null
    printf 'action_16aj_c_continuity_runner_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources

work_dir=$(mktemp -d /tmp/caddy-action16aj-c.XXXXXX)
readonly work_dir
readonly remote_output="$work_dir/remote.out"
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o HostKeyAlias=pihole0.local.theama.co \
    -o StrictHostKeyChecking=yes \
    pi@10.1.0.53 \
    'sudo -n /bin/bash -s --' \
    <"$inspector" >"$remote_output" || ssh_status=$?

cat "$remote_output"
printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 ]]; then
    exit "$ssh_status"
fi

grep -Fxq 'action_16aj_c_remote_reached=true' "$remote_output"
grep -Fxq 'original_stage_absent=true' "$remote_output"
grep -Fxq 'diagnostic_stage_absent=true' "$remote_output"
grep -Fxq 'action_staging_count=true' "$remote_output"
grep -Fxq 'first_failure=none' "$remote_output"
[[ "$(grep -Fxc 'first_failure=none' "$remote_output")" -eq 1 ]]
[[ "$(grep -c '^first_failure=' "$remote_output")" -eq 1 ]]
grep -Fxq 'action_16aj_c_continuity_valid=true' "$remote_output"
grep -Fxq \
    'action_16aj_c_continuity_inspection_complete=true' \
    "$remote_output"
if grep -Eq '=false$' "$remote_output"; then
    printf 'Unexpected failed continuity marker.\n' >&2
    exit 1
fi

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_16aj_c_local_cleanup_complete=true\n'
