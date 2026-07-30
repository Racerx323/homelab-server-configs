#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly historical_runner_sha256=700097f301c49bfef34b60dc6fdeb4e8c0b03282f2ccf7831fa306a930fe7c33
readonly historical_regression_sha256=4849d4057405d996415c62e3f44998e145936697420327147cd269209d25ac60
readonly accepted_action17e_runner_sha256=5354fcd0fa5710ebef77f6751e4094903685d17056891760229c84b08868be92
readonly accepted_action17f_a_runner_sha256=4d995823a4b988081bc4ce242e9699ad1e3f5564bafcfb5781e54f2b4d8fe2ee
readonly inspector_sha256=f380b441aad02b981669d8b251bae67633c49d8769d2e424e20c52b6c8cd3081
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly instrumentation_sha256=6335840327e600ee4c2ded4e6e5090ded0e2aafa2c2d25643c6efd063ad5934c
readonly retry_regression_sha256=202a3d54d66eb0bb3b09a04f1ef983ec6db0fa9647548922d0075e39fa5bd004
readonly rendered_driver_sha256=8d51f4f3d070719069653b95a3f584a2bb370f4979779e4684e4bd0f5f8d3ea1
readonly rendered_regression_sha256=40e0c294ef7b1205e7bb26c1d17f68e519fb7b6c596c208804746ca057db49e3
readonly rendered_runner_sha256=b01aae1ebbee47cd4493e54b1a7f73813e831cb64c858716c5596503de6b0107

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly historical_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"
readonly historical_runner="$script_dir/run-node-b-unbound-local-zone-stage-action17f.sh"
readonly historical_regression="$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
readonly accepted_action17e_runner="$script_dir/run-node-b-unbound-primary-stage-action17e-retry.sh"
readonly accepted_action17f_a_runner="$script_dir/run-node-b-unbound-local-zone-prewrite-diagnostic-action17f-a.sh"
readonly inspector="$script_dir/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_repo="$workspace_root/homelab-dns"
readonly instrumentation="$script_dir/instrument-node-b-unbound-local-zone-action17f-retry.sh"
readonly retry_regression="$caddy_root/tests/action17f-instrumented-retry-regression.sh"

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
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file "$historical_runner" "$historical_runner_sha256"
    verify_file "$historical_regression" "$historical_regression_sha256"
    verify_file \
        "$accepted_action17e_runner" "$accepted_action17e_runner_sha256"
    verify_file \
        "$accepted_action17f_a_runner" "$accepted_action17f_a_runner_sha256"
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$candidate_local_zone" "$candidate_local_zone_sha256"
    verify_file "$instrumentation" "$instrumentation_sha256"
    verify_file "$retry_regression" "$retry_regression_sha256"
    bash -n \
        "$historical_driver" "$historical_runner" "$historical_regression" \
        "$accepted_action17e_runner" "$accepted_action17f_a_runner" \
        "$inspector" "$instrumentation" "$retry_regression"
}

verify_live_sources() {
    local path

    verify_sources
    for path in \
        "$historical_driver" "$historical_runner" "$historical_regression" \
        "$accepted_action17e_runner" "$accepted_action17f_a_runner" \
        "$inspector" "$instrumentation" "$retry_regression"; do
        [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$candidate_primary")" == aaron:aaron:644 ]]
    [[ "$(stat -c '%U:%G:%a' "$candidate_local_zone")" == aaron:aaron:644 ]]
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    git -C "$dns_repo" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1 ||
        git -C "$dns_repo" ls-files --error-unmatch \
            Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        printf 'Private Unbound operator sources unexpectedly became tracked.\n' \
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
    local staged_historical="$staged_caddy/historical"

    install -d -m 0700 \
        "$staged_scripts" "$staged_tests" "$staged_historical"
    install -m 0755 \
        "$historical_driver" \
        "$staged_historical/stage-node-b-unbound-local-zone-action17f.sh"
    install -m 0755 \
        "$accepted_action17e_runner" \
        "$staged_scripts/run-node-b-unbound-primary-stage-action17e-retry.sh"
    "$instrumentation" --render-driver \
        >"$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh"
    "$instrumentation" --render-regression \
        >"$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
    "$instrumentation" --render-runner \
        >"$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
    chmod 0755 \
        "$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh" \
        "$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh" \
        "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
    verify_file \
        "$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh" \
        "$rendered_driver_sha256"
    verify_file \
        "$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh" \
        "$rendered_regression_sha256"
    verify_file \
        "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh" \
        "$rendered_runner_sha256"
    ln -s -- "$dns_repo" "$staged_workspace/homelab-dns"
    printf '%s\n' \
        "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
}

run_local_gates() {
    local destination=$1
    local rendered_runner

    "$instrumentation" --self-test >/dev/null
    "$retry_regression" --production-test >/dev/null
    rendered_runner=$(render_stage "$destination")
    "$rendered_runner" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    test_dir=$(mktemp -d /tmp/caddy-action17f-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    run_local_gates "$test_dir"
    printf 'action_17f_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17f_retry_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    verify_sources
    test_dir=$(mktemp -d /tmp/caddy-action17f-retry-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    run_local_gates "$test_dir"
    printf 'action_17f_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
"$retry_regression" --production-test >/dev/null
work_dir=$(mktemp -d /tmp/caddy-action17f-retry.XXXXXX)
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
        printf 'action_17f_retry_outer_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17f_retry_outer_cleanup_complete=true\n'
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
