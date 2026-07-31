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
readonly policy_runner="$script_dir/run-source-test-in-context.sh"
readonly representative_runner="$caddy_root/scripts/run-node-b-dns-nss-post-correction-action17m-a.sh"

run_regression() {
    local expected_classification
    local fixture_directory
    local policy_output
    local representative_path
    local runner_link

    "$policy_runner" --self-test >/dev/null
    representative_path=$(readlink -f -- "$representative_runner")
    if [[ "$representative_path" == /home/aaron/code/* ]]; then
        expected_classification=workstation_source_verified
    elif [[ "$representative_path" == /workspace/* ]]; then
        [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]
        expected_classification=container_bind_projection_verified
    else
        printf 'source_test_context_regression_assertion_known_root=false\n' >&2
        return 1
    fi

    policy_output=$("$policy_runner" --runner "$representative_runner")
    grep -Fxq \
        "source_test_context_classification=$expected_classification" \
        <<<"$policy_output"
    if "$policy_runner" --runner "$script_dir" >/dev/null 2>&1; then
        printf 'source_test_context_regression_assertion_directory_rejected=false\n' \
            >&2
        return 1
    fi
    if "$policy_runner" --runner /tmp >/dev/null 2>&1; then
        printf 'source_test_context_regression_assertion_unapproved_root_rejected=false\n' \
            >&2
        return 1
    fi
    fixture_directory=$(mktemp -d /tmp/caddy-source-context-policy.XXXXXX)
    runner_link="$fixture_directory/runner-link"
    trap 'rm -rf -- "$fixture_directory"' RETURN
    ln -s -- "$representative_runner" "$runner_link"
    if "$policy_runner" --runner "$runner_link" >/dev/null 2>&1; then
        printf 'source_test_context_regression_assertion_symlink_rejected=false\n' \
            >&2
        return 1
    fi

    printf 'source_test_context_regression_assertion_known_root=true\n'
    printf 'source_test_context_regression_assertion_directory_rejected=true\n'
    printf 'source_test_context_regression_assertion_unapproved_root_rejected=true\n'
    printf 'source_test_context_regression_assertion_symlink_rejected=true\n'
    printf 'source_test_context_policy_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
