#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_runner_sha256=d38a963934d3e063481e8f81a189fe432cd7002683ae6349d341cbde27c0e5e5
readonly historical_driver_sha256=b67d9fe11d535c1767a1a70c8fe334bf74e007ec2915dd19ca254e72bb99121b
readonly historical_regression_sha256=95cb23d0622e29e5e639c3eb259980902911ab7bde41a79567011a59e43f75cb
readonly accepted_action17d_runner_sha256=6e63289a54018514930ae883bb741b6993a9148c77c027b7b16c75cb875ae59d
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly correction_sha256=f0f1ff9413b50cccb5160f80b52b015c2567fccc274e1d51304cf08fa89b3e0d
readonly retry_regression_sha256=ab458946a022635e7d7a8fb88dc30d1df269d436e00c40d8f391a87bfa9743c0
readonly rendered_runner_sha256=918efb1938ca102dbfa228441e7358b329ce733560395e160de2d8d1909273e0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly historical_runner="$script_dir/run-node-b-unbound-primary-stage-action17e.sh"
readonly historical_driver="$script_dir/stage-node-b-unbound-primary-action17e.sh"
readonly historical_regression="$caddy_root/tests/action17e-node-b-unbound-primary-stage-regression.sh"
readonly accepted_action17d_runner="$script_dir/run-node-b-two-file-unbound-preflight-action17d.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly dns_repo="$workspace_root/homelab-dns"
readonly correction="$script_dir/correct-node-b-unbound-primary-working-directory-action17e-retry.sh"
readonly retry_regression="$caddy_root/tests/action17e-working-directory-production-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file "$historical_regression" "$historical_regression_sha256"
    verify_file \
        "$accepted_action17d_runner" "$accepted_action17d_runner_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$correction" "$correction_sha256"
    verify_file "$retry_regression" "$retry_regression_sha256"
    bash -n \
        "$historical_runner" \
        "$historical_driver" \
        "$historical_regression" \
        "$accepted_action17d_runner" \
        "$correction" \
        "$retry_regression"
}

verify_live_sources() {
    local path

    verify_sources
    for path in \
        "$historical_runner" \
        "$historical_driver" \
        "$historical_regression" \
        "$accepted_action17d_runner" \
        "$correction" \
        "$retry_regression"; do
        [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$candidate_primary")" == aaron:aaron:644 ]]
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1; then
        printf 'Private Unbound primary source unexpectedly became tracked.\n' \
            >&2
        return 1
    fi
}

render_stage() {
    local destination=$1
    local staged_workspace="$destination/workspace"
    local staged_caddy="$staged_workspace/homelab-server-configs/Caddy"
    local staged_scripts="$staged_caddy/scripts"
    local staged_tests="$staged_caddy/tests"

    install -d -m 0700 "$staged_scripts" "$staged_tests"
    install -m 0755 \
        "$historical_driver" \
        "$staged_scripts/stage-node-b-unbound-primary-action17e.sh"
    install -m 0755 \
        "$accepted_action17d_runner" \
        "$staged_scripts/run-node-b-two-file-unbound-preflight-action17d.sh"
    install -m 0755 \
        "$historical_regression" \
        "$staged_tests/action17e-node-b-unbound-primary-stage-regression.sh"
    "$correction" --render-runner "$historical_runner" \
        >"$staged_scripts/run-node-b-unbound-primary-stage-action17e.sh"
    chmod 0755 \
        "$staged_scripts/run-node-b-unbound-primary-stage-action17e.sh"
    verify_file \
        "$staged_scripts/run-node-b-unbound-primary-stage-action17e.sh" \
        "$rendered_runner_sha256"
    ln -s -- "$dns_repo" "$staged_workspace/homelab-dns"
    printf '%s\n' \
        "$staged_scripts/run-node-b-unbound-primary-stage-action17e.sh"
}

run_local_gates() {
    local destination=$1
    local rendered_runner

    "$correction" --self-test >/dev/null
    "$retry_regression" --production-test >/dev/null
    rendered_runner=$(render_stage "$destination")
    "$rendered_runner" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    test_dir=$(mktemp -d /tmp/caddy-action17e-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    run_local_gates "$test_dir"
    printf 'action_17e_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17e_retry_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    verify_sources
    test_dir=$(mktemp -d /tmp/caddy-action17e-retry-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    run_local_gates "$test_dir"
    printf 'action_17e_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
"$retry_regression" --production-test >/dev/null
work_dir=$(mktemp -d /tmp/caddy-action17e-retry.XXXXXX)
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
        printf 'action_17e_retry_outer_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17e_retry_outer_cleanup_complete=true\n'
    exit "$status"
}

rendered_runner=$(render_stage "$work_dir")
readonly rendered_runner
"$rendered_runner" --self-test >/dev/null
"$rendered_runner" --source-test >/dev/null
"$rendered_runner" --contract-test >/dev/null

inner_status=0
"$rendered_runner" || inner_status=$?
finish "$inner_status"
