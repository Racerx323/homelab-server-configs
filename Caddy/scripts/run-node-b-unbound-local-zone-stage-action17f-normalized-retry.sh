#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly correction_sha256=7fc521452ac1f65c5e1cdc4025daa2f57c41819134af952bd9b60aaf7c493bd8
readonly regression_sha256=f9f373a1ee6c8aa215d27f08ee3e1d40c67f01dbbe0db299dd7f1fd9a29b8ea3
readonly historical_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly instrumented_retry_runner_sha256=6dae2d4b5da2da62e92dc2e42400445905ba0f59692a6024748971472707c83b
readonly accepted_diagnostic_runner_sha256=5c33177beb6809e46d3781bd5c43e3f10ddac095a585b688682ba473baf95456
readonly accepted_action17e_runner_sha256=5354fcd0fa5710ebef77f6751e4094903685d17056891760229c84b08868be92
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly rendered_transactional_driver_sha256=21d94854f678a64c3deb3233af7796fd7c2f194ec31395f7a1e6ad2a48abf269
readonly rendered_driver_sha256=b50d19544a4d25a4d716382f585575fc8bdb34fb25f31da4b6340603f798597b
readonly rendered_correction_sha256=0f561431e5767bf1287b21d49900ac5e994d45b2746679cd94de2d933e115bd9
readonly rendered_regression_sha256=ccc223f3854f62d6340fbdfc472666e3a916470689aac12ccf3dcfd584e82997
readonly rendered_runner_sha256=1a8b2b1b602c4f1d4974fb19a2c93f08d23f6910ff54984e77d5b24ac202ab7a

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly correction="$script_dir/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
readonly instrumentation="$script_dir/instrument-node-b-unbound-local-zone-action17f-retry.sh"
readonly regression="$caddy_root/tests/action17f-normalized-live-state-boundary-regression.sh"
readonly historical_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"
readonly instrumented_retry_runner="$script_dir/run-node-b-unbound-local-zone-stage-action17f-retry.sh"
readonly accepted_diagnostic_runner="$script_dir/run-node-b-unbound-action17f-baseline-second-retry.sh"
readonly accepted_action17e_runner="$script_dir/run-node-b-unbound-primary-stage-action17e-retry.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_repo="$workspace_root/homelab-dns"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local source_path=$1
    local expected_hash=$2

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$correction" "$correction_sha256"
    verify_file "$instrumentation" \
        6335840327e600ee4c2ded4e6e5090ded0e2aafa2c2d25643c6efd063ad5934c
    verify_file "$regression" "$regression_sha256"
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file \
        "$instrumented_retry_runner" "$instrumented_retry_runner_sha256"
    verify_file \
        "$accepted_diagnostic_runner" "$accepted_diagnostic_runner_sha256"
    verify_file \
        "$accepted_action17e_runner" "$accepted_action17e_runner_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$candidate_local_zone" "$candidate_local_zone_sha256"
    bash -n \
        "$correction" "$instrumentation" "$regression" "$historical_driver" \
        "$instrumented_retry_runner" "$accepted_diagnostic_runner" \
        "$accepted_action17e_runner" "$collision_checker"
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in \
        "$correction" "$instrumentation" "$regression" "$historical_driver" \
        "$instrumented_retry_runner" "$accepted_diagnostic_runner" \
        "$accepted_action17e_runner" "$collision_checker"; do
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
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
    local staged_correction_hash staged_regression_hash
    local rendered_transactional_hash

    install -d -m 0700 \
        "$staged_scripts" "$staged_tests" "$staged_historical"
    install -m 0755 \
        "$historical_driver" \
        "$staged_historical/stage-node-b-unbound-local-zone-action17f.sh"
    install -m 0755 \
        "$instrumentation" \
        "$staged_scripts/instrument-node-b-unbound-local-zone-action17f-retry.sh"
    "$correction" --render-transactional-driver \
        >"$destination/transactional-driver"
    verify_file \
        "$destination/transactional-driver" \
        "$rendered_transactional_driver_sha256"
    "$correction" --render-driver \
        >"$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh"
    awk '
        /^readonly historical_driver=/ {
            print "readonly historical_driver=\"$script_dir/../historical/stage-node-b-unbound-local-zone-action17f.sh\""
            changed++
            next
        }
        { print }
        END {
            if (changed != 1) {
                exit 42
            }
        }
    ' "$correction" \
        >"$staged_scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
    chmod 0755 \
        "$staged_scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
    staged_correction_hash=$(
        file_hash \
            "$staged_scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
    )
    [[ "$rendered_correction_sha256" == pending ||
        "$staged_correction_hash" == "$rendered_correction_sha256" ]]
    awk -v correction_hash="$staged_correction_hash" '
        /^readonly correction_sha256=/ {
            print "readonly correction_sha256=" correction_hash
            correction_hash_changed++
            next
        }
        /^readonly historical_driver=/ {
            print "readonly historical_driver=\"$caddy_root/historical/stage-node-b-unbound-local-zone-action17f.sh\""
            driver_path_changed++
            next
        }
        { print }
        END {
            if (correction_hash_changed != 1 || driver_path_changed != 1) {
                exit 42
            }
        }
    ' "$regression" \
        >"$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
    chmod 0755 \
        "$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
    staged_regression_hash=$(
        file_hash \
            "$staged_tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
    )
    [[ "$rendered_regression_sha256" == pending ||
        "$staged_regression_hash" == "$rendered_regression_sha256" ]]
    rendered_transactional_hash=$(
        file_hash "$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh"
    )
    [[ "$rendered_transactional_hash" == "$rendered_driver_sha256" ]]
    "$correction" --render-runner \
        "$rendered_driver_sha256" "$staged_regression_hash" \
        >"$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
    install -m 0755 \
        "$accepted_action17e_runner" \
        "$staged_scripts/run-node-b-unbound-primary-stage-action17e-retry.sh"
    chmod 0755 \
        "$staged_scripts/stage-node-b-unbound-local-zone-action17f.sh" \
        "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
    if [[ "$rendered_runner_sha256" != pending ]]; then
        verify_file \
            "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh" \
            "$rendered_runner_sha256"
    fi
    ln -s -- "$dns_repo" "$staged_workspace/homelab-dns"
    printf '%s\n' \
        "$staged_scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
}

run_local_gates() {
    local destination=$1
    local gate_runner

    printf 'action_17f_normalized_gate_correction_self_test_started=true\n'
    "$correction" --self-test >/dev/null
    printf 'action_17f_normalized_gate_correction_self_test_passed=true\n'
    printf 'action_17f_normalized_gate_boundary_regression_started=true\n'
    "$regression" --production-test >/dev/null
    printf 'action_17f_normalized_gate_boundary_regression_passed=true\n'
    printf 'action_17f_normalized_gate_collision_policy_started=true\n'
    "$collision_checker" "$correction" "$regression" "$0" >/dev/null
    printf 'action_17f_normalized_gate_collision_policy_passed=true\n'
    printf 'action_17f_normalized_gate_render_stage_started=true\n'
    gate_runner=$(render_stage "$destination")
    printf 'action_17f_normalized_gate_render_stage_passed=true\n'
    printf 'action_17f_normalized_gate_rendered_driver_self_test_started=true\n'
    "$destination/workspace/homelab-server-configs/Caddy/scripts/stage-node-b-unbound-local-zone-action17f.sh" \
        --self-test >/dev/null
    printf 'action_17f_normalized_gate_rendered_driver_self_test_passed=true\n'
    printf 'action_17f_normalized_gate_rendered_regression_self_test_started=true\n'
    "$destination/workspace/homelab-server-configs/Caddy/tests/action17f-node-b-unbound-local-zone-stage-regression.sh" \
        --self-test >/dev/null
    printf 'action_17f_normalized_gate_rendered_regression_self_test_passed=true\n'
    printf 'action_17f_normalized_gate_inner_self_test_started=true\n'
    "$gate_runner" --self-test >/dev/null
    printf 'action_17f_normalized_gate_inner_self_test_passed=true\n'
    printf 'action_17f_normalized_gate_inner_contract_test_started=true\n'
    "$gate_runner" --contract-test >/dev/null
    printf 'action_17f_normalized_gate_inner_contract_test_passed=true\n'
}

case "${1:-}" in
    --self-test)
        (($# == 1))
        verify_sources
        test_dir=$(mktemp -d /tmp/caddy-action17f-normalized-self-test.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        run_local_gates "$test_dir"
        printf 'action_17f_normalized_retry_runner_self_test_complete=true\n'
        exit 0
        ;;
    --source-test)
        (($# == 1))
        verify_live_sources
        printf 'action_17f_normalized_retry_runner_source_test_complete=true\n'
        exit 0
        ;;
    --contract-test)
        (($# == 1))
        verify_sources
        test_dir=$(mktemp -d /tmp/caddy-action17f-normalized-contract.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        run_local_gates "$test_dir"
        printf 'action_17f_normalized_retry_runner_contract_test_complete=true\n'
        exit 0
        ;;
    --render-hashes)
        (($# == 1))
        verify_sources
        test_dir=$(mktemp -d /tmp/caddy-action17f-normalized-hashes.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        rendered_hash_runner=$(render_stage "$test_dir")
        printf 'rendered_correction_sha256=%s\n' "$(
            file_hash \
                "$test_dir/workspace/homelab-server-configs/Caddy/scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
        )"
        printf 'rendered_regression_sha256=%s\n' "$(
            file_hash \
                "$test_dir/workspace/homelab-server-configs/Caddy/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
        )"
        printf 'rendered_runner_sha256=%s\n' "$(
            file_hash "$rendered_hash_runner"
        )"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test|--render-hashes]\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

verify_live_sources
"$regression" --production-test >/dev/null
runner_work_dir=$(mktemp -d /tmp/caddy-action17f-normalized-retry.XXXXXX)
readonly runner_work_dir

cleanup() {
    rm -rf -- "$runner_work_dir"
}
trap cleanup EXIT

finish() {
    local final_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$runner_work_dir" || -L "$runner_work_dir" ]]; then
        printf 'action_17f_normalized_retry_outer_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17f_normalized_retry_outer_cleanup_complete=true\n'
    exit "$final_status"
}

rendered_inner_runner=$(render_stage "$runner_work_dir")
readonly rendered_inner_runner
"$rendered_inner_runner" --self-test >/dev/null
"$rendered_inner_runner" --source-test >/dev/null
"$rendered_inner_runner" --contract-test >/dev/null

set +e
"$rendered_inner_runner"
inner_status=$?
set -e
finish "$inner_status"
