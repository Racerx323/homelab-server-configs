#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly containerfile="$script_dir/Containerfile"
readonly integration_test="$script_dir/integration.sh"

assert_fixed() {
    local assertion_label=$1
    local expected_text=$2
    local inspected_file=$3

    if grep -Fq "$expected_text" "$inspected_file"; then
        printf 'validation_runtime_assertion_%s=true\n' "$assertion_label"
    else
        printf 'validation_runtime_assertion_%s=false\n' \
            "$assertion_label" >&2
        return 1
    fi
}

assert_regex() {
    local assertion_label=$1
    local expected_pattern=$2
    local inspected_file=$3

    if grep -Eq "$expected_pattern" "$inspected_file"; then
        printf 'validation_runtime_assertion_%s=true\n' "$assertion_label"
    else
        printf 'validation_runtime_assertion_%s=false\n' \
            "$assertion_label" >&2
        return 1
    fi
}

run_regression() {
    assert_fixed unbound_log_directory_image_install \
        'install -d -o unbound -g unbound -m 0750 /var/log/unbound' \
        "$containerfile"
    assert_fixed unbound_log_directory_runtime_stat \
        "stat -c '%U:%G:%a' /var/log/unbound" \
        "$integration_test"
    assert_fixed unbound_log_directory_runtime_metadata \
        'unbound:unbound:750' "$integration_test"
    assert_regex git_image_package \
        '^[[:space:]]+git \\$' "$containerfile"
    assert_fixed git_runtime_command \
        'command -v git >/dev/null' "$integration_test"
    printf '%s\n' \
        unbound_validation_log_directory_image_owned=true \
        unbound_validation_log_directory_runtime_asserted=true \
        validation_git_image_dependency_declared=true \
        validation_git_runtime_asserted=true \
        unbound_validation_runtime_regression_complete=true
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
