#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly workstation_root=/home/aaron/code/homelab-server-configs/Caddy
readonly container_root=/workspace/homelab-server-configs/Caddy

fail_context() {
    local failure_label=$1
    local observed_value=${2:-unavailable}

    printf 'source_test_context_assertion_%s=false\n' "$failure_label" >&2
    printf 'source_test_context_observed_%s=%s\n' \
        "$failure_label" "$observed_value" >&2
    return 1
}

verify_runner() {
    local verified_runner=$1

    if [[ ! -f "$verified_runner" || -L "$verified_runner" ]]; then
        fail_context runner_regular_file \
            "$(stat -c %F "$verified_runner" 2>/dev/null || printf absent)"
        return 1
    fi
    if [[ ! -x "$verified_runner" ]]; then
        fail_context runner_executable false
        return 1
    fi
    printf 'source_test_context_assertion_runner_regular_file=true\n'
    printf 'source_test_context_assertion_runner_executable=true\n'
}

run_context_gate() {
    local requested_runner=$1
    local canonical_runner
    local runner_metadata

    verify_runner "$requested_runner"
    canonical_runner=$(readlink -f -- "$requested_runner")
    runner_metadata=$(stat -c '%U:%G:%a' "$canonical_runner")

    if [[ "$canonical_runner" == "$workstation_root/"* ]]; then
        if [[ "$runner_metadata" != aaron:aaron:755 ]]; then
            fail_context workstation_owner_mode "$runner_metadata"
            return 1
        fi
        "$canonical_runner" --source-test >/dev/null
        printf 'source_test_context_assertion_workstation_owner_mode=true\n'
        printf 'source_test_context_classification=workstation_source_verified\n'
        return 0
    fi

    if [[ "$canonical_runner" == "$container_root/"* ]]; then
        if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
            fail_context container_marker "${CADDY_VALIDATION_CONTAINER:-absent}"
            return 1
        fi
        if [[ "$runner_metadata" != root:root:755 ]]; then
            fail_context container_bind_owner_mode "$runner_metadata"
            return 1
        fi
        printf 'source_test_context_assertion_container_marker=true\n'
        printf 'source_test_context_assertion_container_bind_owner_mode=true\n'
        printf 'source_test_context_classification=container_bind_projection_verified\n'
        return 0
    fi

    fail_context approved_repository_root "$canonical_runner"
}

self_test() {
    [[ "$workstation_root" == /home/aaron/code/homelab-server-configs/Caddy ]]
    [[ "$container_root" == /workspace/homelab-server-configs/Caddy ]]
    grep -Fq 'aaron:aaron:755' "$0"
    grep -Fq 'root:root:755' "$0"
    grep -Fq 'CADDY_VALIDATION_CONTAINER' "$0"
    # shellcheck disable=SC2016
    grep -Fq '"$canonical_runner" --source-test' "$0"
    printf 'source_test_context_policy_self_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        ;;
    --runner)
        [[ $# -eq 2 ]]
        run_context_gate "$2"
        ;;
    *)
        printf 'Usage: %s --self-test|--runner RUNNER\n' "${0##*/}" >&2
        exit 2
        ;;
esac
