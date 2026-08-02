#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_name=inspect-sync-readiness-before-action17.sh
readonly historical_inspector_sha256=1193632a867b4a86fd28f4b932b809926498b0b6a2e4751e8ee1f69c5da05ae8
readonly historical_runner_name=run-sync-readiness-before-action17.sh
readonly historical_runner_sha256=f19e5673d3e86a95282041e9770c8c6d1093cbee9cd985e82957bd78773f16e5
readonly correction_name=correct-sync-readiness-before-action17-retry.sh
readonly correction_sha256=37d2b822bac699e5feaba9317719931d5264e2ae3281187ee3a0f16b07bfd543
readonly regression_name=action17a-node-b-release-regression.sh
readonly regression_sha256=2ac139c2a35f7d25c21218da4bdfb98bbcf1b8a9d9716e8d59baf08451f2febc
readonly rendered_inspector_sha256=87c910f1c7a5a01c21af8af0b840d339a793a91b9f430539760bfbe94a80b805
readonly rendered_runner_sha256=ffb025e613466b73692002b093041f793bd9c08132842bc83d0944bd937fb9ad
readonly accepted_node_b_target=/etc/caddy/releases/action15-health-follow-redirects

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_inspector="$script_dir/$historical_inspector_name"
readonly historical_runner="$script_dir/$historical_runner_name"
readonly correction="$script_dir/$correction_name"
readonly regression="$caddy_root/tests/$regression_name"

verify_file() {
    local target=$1
    local expected_hash=$2

    [[ -f "$target" && ! -L "$target" ]]
    [[ "$(stat -c '%U:%G:%a' "$target")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$target"
}

verify_source_artifacts() {
    verify_file "$historical_inspector" "$historical_inspector_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$correction" "$correction_sha256"
    verify_file "$regression" "$regression_sha256"
}

stage_corrected_artifacts() {
    local destination=$1
    local rendered_inspector=$destination/$historical_inspector_name
    local rendered_runner=$destination/$historical_runner_name

    "$correction" --render-inspector "$historical_inspector" \
        >"$rendered_inspector"
    chmod 0755 "$rendered_inspector"
    [[ "$(sha256sum "$rendered_inspector" | awk '{ print $1 }')" == "$rendered_inspector_sha256" ]]
    grep -Fq "$accepted_node_b_target" "$rendered_inspector"

    "$correction" --render-runner "$historical_runner" \
        "$rendered_inspector_sha256" >"$rendered_runner"
    chmod 0755 "$rendered_runner"
    [[ "$(sha256sum "$rendered_runner" | awk '{ print $1 }')" == "$rendered_runner_sha256" ]]
    bash -n "$rendered_inspector" "$rendered_runner"
}

run_local_test() {
    local mode=$1
    local test_dir

    verify_source_artifacts
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17a-retry-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    stage_corrected_artifacts "$test_dir"
    "$test_dir/$historical_runner_name" "$mode" >/dev/null
    rm -rf -- "$test_dir"
    trap - RETURN
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    run_local_test --self-test
    printf 'action_17a_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    run_local_test --contract-test
    printf 'action_17a_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_source_artifacts
work_dir=$(mktemp -d /tmp/caddy-action17a-retry.XXXXXX)
readonly work_dir

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_17a_retry_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17a_retry_local_cleanup_complete=true\n'
    exit "$status"
}

stage_corrected_artifacts "$work_dir"
set +e
"$work_dir/$historical_runner_name"
retry_status=$?
set -e
printf 'action_17a_retry_corrected_runner_status=%s\n' "$retry_status"
if [[ "$retry_status" -eq 0 ]]; then
    printf 'action_17a_retry_sync_readiness_accepted=true\n'
else
    printf 'action_17a_retry_sync_readiness_accepted=false\n'
fi
finish "$retry_status"
