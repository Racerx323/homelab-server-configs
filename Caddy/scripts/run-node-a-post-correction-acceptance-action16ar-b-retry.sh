#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_name=diagnose-node-a-action16ar-recovery-action16ar-a.sh
readonly historical_inspector_sha256=c63146c3c2d7e3201bb5a90d3456333a3ccdcb4bf6a287721607e8f046ff28cb
readonly historical_inner_runner_name=run-node-a-action16ar-recovery-diagnostic-action16ar-a.sh
readonly historical_inner_runner_sha256=52302f2394c51c20945947e0b454ab94023a158f8bed7bd39e88295aa9b484d9
readonly deriver_name=derive-node-a-post-correction-acceptance-action16ar-b.sh
readonly deriver_sha256=f3f07ddd688373eef38d56b6361ddd897e83d38f492120516797693afb4f0a47
readonly historical_outer_runner_name=run-node-a-post-correction-acceptance-action16ar-b.sh
readonly historical_outer_runner_sha256=fe4e09369ee6699bceeb14453546ca6f22523219c5391a383b815f59293635fe
readonly correction_name=correct-node-a-post-correction-acceptance-action16ar-b-retry.sh
readonly correction_sha256=c2f0ffcf76ea54cb101af03c3223640fc12ff7102aacfc251d793a9dbb304389
readonly regression_name=action16ar-b-production-transcript-regression.sh
readonly regression_sha256=6e66134ec1a0ef1d6d27a18e423a4d9629bac85401747ec2b3dccd0483dcb215
readonly rendered_runner_name=run-node-a-post-correction-acceptance-action16ar-b-retry-rendered.sh
readonly rendered_runner_sha256=00ab68767fef384ff0dca13c67d0c0970755d9e8c81861cc5d1c1f57fe49d25e
readonly expected_host_key_alias=HostKeyAlias=pihole0.local.theama.co
readonly expected_ssh_target=pi@10.1.0.53

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_inspector="$script_dir/$historical_inspector_name"
readonly historical_inner_runner="$script_dir/$historical_inner_runner_name"
readonly deriver="$script_dir/$deriver_name"
readonly historical_outer_runner="$script_dir/$historical_outer_runner_name"
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
    verify_file "$historical_inner_runner" "$historical_inner_runner_sha256"
    verify_file "$deriver" "$deriver_sha256"
    verify_file "$historical_outer_runner" "$historical_outer_runner_sha256"
    verify_file "$correction" "$correction_sha256"
    verify_file "$regression" "$regression_sha256"
}

stage_corrected_runner() {
    local destination=$1
    local rendered_runner=$destination/$rendered_runner_name

    install -m 0755 -- "$historical_inspector" \
        "$destination/$historical_inspector_name"
    install -m 0755 -- "$historical_inner_runner" \
        "$destination/$historical_inner_runner_name"
    install -m 0755 -- "$deriver" "$destination/$deriver_name"
    "$correction" --render "$historical_outer_runner" >"$rendered_runner"
    chmod 0755 "$rendered_runner"
    [[ "$(sha256sum "$rendered_runner" | awk '{ print $1 }')" == "$rendered_runner_sha256" ]]
    bash -n "$rendered_runner"
    grep -Fq "$expected_host_key_alias" "$rendered_runner"
    grep -Fq "$expected_ssh_target" "$rendered_runner"
}

run_local_test() {
    local mode=$1
    local test_dir

    verify_source_artifacts
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action16ar-b-retry-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    stage_corrected_runner "$test_dir"
    "$test_dir/$rendered_runner_name" "$mode" >/dev/null
    rm -rf -- "$test_dir"
    trap - RETURN
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    run_local_test --self-test
    printf 'action_16ar_b_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    run_local_test --contract-test
    printf 'action_16ar_b_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_source_artifacts
work_dir=$(mktemp -d /tmp/caddy-action16ar-b-retry.XXXXXX)
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
        printf 'action_16ar_b_retry_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_16ar_b_retry_local_cleanup_complete=true\n'
    exit "$status"
}

stage_corrected_runner "$work_dir"
set +e
"$work_dir/$rendered_runner_name"
retry_status=$?
set -e
printf 'action_16ar_b_retry_corrected_runner_status=%s\n' "$retry_status"
if [[ "$retry_status" -eq 0 ]]; then
    printf 'action_16ar_b_retry_post_correction_accepted=true\n'
fi
finish "$retry_status"
