#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=outer_local_gate_policy

classify_transcript() {
    local classifier_expected_path=$1
    local classifier_transcript_path=$2
    local classifier_actual_path=$3
    local classifier_expected_count
    local classifier_actual_count
    local classifier_unique_count

    # conditional-validator-explicit-failures-begin
    classifier_expected_count=$(wc -l <"$classifier_expected_path") || return 1
    [[ "$classifier_expected_count" -gt 0 ]] || return 1
    [[ "$(LC_ALL=C sort -u "$classifier_expected_path" | wc -l)" -eq "$classifier_expected_count" ]] || return 1
    if grep -Eq '_outer_gate_[a-zA-Z0-9_]+=false$' \
        "$classifier_transcript_path"; then
        return 1
    fi
    sed -n 's/^.*_outer_gate_\([a-zA-Z0-9_]*\)=true$/\1/p' \
        "$classifier_transcript_path" >"$classifier_actual_path" || return 1
    classifier_actual_count=$(wc -l <"$classifier_actual_path") || return 1
    classifier_unique_count=$(LC_ALL=C sort -u "$classifier_actual_path" | wc -l) ||
        return 1
    [[ "$classifier_actual_count" -eq "$classifier_expected_count" ]] || return 1
    [[ "$classifier_unique_count" -eq "$classifier_expected_count" ]] || return 1
    diff -u <(LC_ALL=C sort "$classifier_expected_path") \
        <(LC_ALL=C sort "$classifier_actual_path") >/dev/null || return 1
    # conditional-validator-explicit-failures-end
    return 0
}

run_policy_self_test() {
    local self_test_root

    self_test_root=$(mktemp -d /tmp/outer-local-gate-policy.XXXXXX)
    trap 'rm -rf -- "$self_test_root"' RETURN
    printf '%s\n' source_gate policy_gate >"$self_test_root/expected"
    printf '%s\n' \
        'sample_outer_gate_source_gate=true' \
        'sample_outer_gate_policy_gate=true' >"$self_test_root/valid"
    classify_transcript "$self_test_root/expected" "$self_test_root/valid" \
        "$self_test_root/valid.actual"
    printf '%s_false_negative_valid_transcript_accepted=true\n' "$prefix"

    printf '%s\n' 'sample_outer_gate_source_gate=true' \
        >"$self_test_root/missing"
    if classify_transcript "$self_test_root/expected" "$self_test_root/missing" \
        "$self_test_root/missing.actual"; then
        printf '%s_false_positive_missing_gate_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_false_positive_missing_gate_rejected=true\n' "$prefix"

    printf '%s\n' \
        'sample_outer_gate_source_gate=true' \
        'sample_outer_gate_source_gate=true' \
        'sample_outer_gate_policy_gate=true' >"$self_test_root/duplicate"
    if classify_transcript "$self_test_root/expected" "$self_test_root/duplicate" \
        "$self_test_root/duplicate.actual"; then
        printf '%s_false_positive_duplicate_gate_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_false_positive_duplicate_gate_rejected=true\n' "$prefix"

    printf '%s\n' \
        'sample_outer_gate_source_gate=true' \
        'sample_outer_gate_policy_gate=false' >"$self_test_root/false"
    if classify_transcript "$self_test_root/expected" "$self_test_root/false" \
        "$self_test_root/false.actual"; then
        printf '%s_false_positive_false_gate_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_false_positive_false_gate_rejected=true\n' "$prefix"

    printf '%s\n' \
        'sample_outer_gate_source_gate=true' \
        'sample_outer_gate_policy_gate=true' \
        'sample_outer_gate_unexpected_gate=true' >"$self_test_root/unexpected"
    if classify_transcript "$self_test_root/expected" "$self_test_root/unexpected" \
        "$self_test_root/unexpected.actual"; then
        printf '%s_false_positive_unexpected_gate_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_false_positive_unexpected_gate_rejected=true\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_policy_self_test
        ;;
    --runner)
        [[ $# -eq 2 ]] || exit 64
        readonly policy_runner=$2
        [[ -f "$policy_runner" && ! -L "$policy_runner" ]] || exit 1
        policy_root=$(mktemp -d /tmp/outer-local-gate-runner.XXXXXX)
        readonly policy_root
        trap 'rm -rf -- "$policy_root"' EXIT
        /bin/bash "$policy_runner" --expected-local-gates \
            >"$policy_root/expected" 2>"$policy_root/expected.stderr"
        [[ ! -s "$policy_root/expected.stderr" ]]
        /bin/bash "$policy_runner" --self-test \
            >"$policy_root/transcript" 2>"$policy_root/transcript.stderr"
        [[ ! -s "$policy_root/transcript.stderr" ]]
        classify_transcript "$policy_root/expected" "$policy_root/transcript" \
            "$policy_root/actual"
        printf '%s_runner_contract_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --self-test | --runner RUNNER\n' "${0##*/}" >&2
        exit 64
        ;;
esac
