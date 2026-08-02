#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_transaction_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly corrected_transaction_sha256=f92ccbff329c2f6dff015bde47cc13fc3a146549faa69ca5a67619968d9df0d3
readonly historical_runner_sha256=19df3282a29ec49fa35f13afdf69a7a2231cac0b8e5e3ae9d5917c71e3a678e5
readonly corrected_inner_runner_sha256=e3390939cda6a4021701360ae6b43e4d9d77f146211d9cc8217cc0e9188aad0a

correction_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly correction_script_directory
readonly historical_transaction="$correction_script_directory/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly historical_runner="$correction_script_directory/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_transaction() {
    local transaction_source=$1

    [[ -f "$transaction_source" && ! -L "$transaction_source" ]] || return 1
    [[ "$(file_hash "$transaction_source")" == "$historical_transaction_sha256" ]] || return 1
    awk '
        $0 == "require_check hostname_node_b test \"$(hostname -s)\" = pihole00" {
            print "require_check hostname_node_b test \"$(hostname -s)\" = j1-svpihole00"
            changed++
            next
        }
        { print }
        END {
            if (changed != 1) {
                exit 42
            }
        }
    ' "$transaction_source"
}

render_runner() {
    local runner_source=$1

    [[ -f "$runner_source" && ! -L "$runner_source" ]] || return 1
    [[ "$(file_hash "$runner_source")" == "$historical_runner_sha256" ]] || return 1
    awk '
        $0 == "readonly runner_revision=action17u-b-retry" {
            print "readonly runner_revision=action17u-b-retry2"
            revision_changed++
            next
        }
        $0 == "readonly repair_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de" {
            print "readonly repair_sha256=f92ccbff329c2f6dff015bde47cc13fc3a146549faa69ca5a67619968d9df0d3"
            hash_changed++
            next
        }
        $0 == "work_directory=$(mktemp -d /tmp/caddy-action17u-b-retry-runner.XXXXXX)" {
            print "work_directory=$(mktemp -d /tmp/caddy-action17u-b-retry2-runner.XXXXXX)"
            directory_changed++
            next
        }
        { print }
        END {
            if (revision_changed != 1 || hash_changed != 1 || directory_changed != 1) {
                exit 42
            }
        }
    ' "$runner_source"
}

self_test() {
    local correction_test_directory
    local rendered_transaction
    local rendered_runner
    local transaction_diff
    local runner_diff

    correction_test_directory=$(mktemp -d /tmp/caddy-action17u-b-retry2-correction.XXXXXX)
    trap 'rm -rf -- "$correction_test_directory"' EXIT
    rendered_transaction="$correction_test_directory/transaction"
    rendered_runner="$correction_test_directory/runner"
    transaction_diff="$correction_test_directory/transaction.diff"
    runner_diff="$correction_test_directory/runner.diff"

    render_transaction "$historical_transaction" >"$rendered_transaction"
    render_runner "$historical_runner" >"$rendered_runner"
    [[ "$(file_hash "$rendered_transaction")" == "$corrected_transaction_sha256" ]]
    [[ "$(file_hash "$rendered_runner")" == "$corrected_inner_runner_sha256" ]]
    bash -n "$rendered_transaction" "$rendered_runner"

    diff -u -- "$historical_transaction" "$rendered_transaction" \
        >"$transaction_diff" || [[ $? -eq 1 ]]
    [[ "$(grep -Ec '^[+-]require_check hostname_node_b ' "$transaction_diff")" -eq 2 ]]
    [[ "$(grep -Ec '^[+-][^+-]' "$transaction_diff")" -eq 2 ]]
    # Match the literal command substitution in the immutable source diff.
    # shellcheck disable=SC2016
    grep -Fxq -- \
        '-require_check hostname_node_b test "$(hostname -s)" = pihole00' \
        "$transaction_diff"
    # shellcheck disable=SC2016
    grep -Fxq -- \
        '+require_check hostname_node_b test "$(hostname -s)" = j1-svpihole00' \
        "$transaction_diff"

    diff -u -- "$historical_runner" "$rendered_runner" \
        >"$runner_diff" || [[ $? -eq 1 ]]
    [[ "$(grep -Ec '^[+-][^+-]' "$runner_diff")" -eq 6 ]]
    grep -Fxq -- '-readonly runner_revision=action17u-b-retry' "$runner_diff"
    grep -Fxq -- '+readonly runner_revision=action17u-b-retry2' "$runner_diff"
    grep -Fxq -- \
        "-readonly repair_sha256=$historical_transaction_sha256" "$runner_diff"
    grep -Fxq -- \
        "+readonly repair_sha256=$corrected_transaction_sha256" "$runner_diff"
    # Match the literal mktemp command in the immutable runner diff.
    # shellcheck disable=SC2016
    grep -Fxq -- \
        '-work_directory=$(mktemp -d /tmp/caddy-action17u-b-retry-runner.XXXXXX)' \
        "$runner_diff"
    # shellcheck disable=SC2016
    grep -Fxq -- \
        '+work_directory=$(mktemp -d /tmp/caddy-action17u-b-retry2-runner.XXXXXX)' \
        "$runner_diff"

    rm -rf -- "$correction_test_directory"
    trap - EXIT
    printf 'action_17u_b_retry2_hostname_correction_self_test_complete=true\n'
}

case "${1:-}" in
    --render-transaction)
        [[ $# -eq 2 ]] || exit 64
        render_transaction "$2"
        ;;
    --render-runner)
        [[ $# -eq 2 ]] || exit 64
        render_runner "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *)
        printf 'Usage: %s --render-transaction SOURCE | --render-runner SOURCE | --self-test\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
