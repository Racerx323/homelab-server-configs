#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_c_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-historical-release-manifest-action28e-c.sh
readonly outer=$caddy_root/scripts/run-dual-node-historical-release-manifest-action28e-c-outer.sh
readonly accepted_raw=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly unaccepted_raw=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly canonical=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly changed_canonical=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
readonly payload=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

work_root=$(mktemp -d /tmp/action28e-c-regression.XXXXXX)
readonly work_root
cleanup() {
    local action28e_c_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_c_regression_status"
}
trap cleanup EXIT

record_check() {
    local action28e_c_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_c_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_c_regression_label" >&2
    return 1
}
extract_test_value() {
    local action28e_c_regression_key=$1
    local action28e_c_regression_file=$2

    sed -n "s/^action_28e_c_value_test_${action28e_c_regression_key}=//p" \
        "$action28e_c_regression_file"
}
inspect_fixture() {
    local action28e_c_regression_input=$1
    local action28e_c_regression_output=$2

    CADDY_ACTION28E_C_TEST_MODE=1 /bin/bash "$inspector" --test-file \
        "$action28e_c_regression_input" >"$action28e_c_regression_output"
}
make_transcript() {
    local action28e_c_regression_output=$1
    local action28e_c_regression_raw=$2
    local action28e_c_regression_canonical=$3

    printf '%s\n' \
        "action_28e_c_value_manifest_raw_sha256=$action28e_c_regression_raw" \
        "action_28e_c_value_manifest_canonical_payload_sha256=$action28e_c_regression_canonical" \
        "action_28e_c_value_payload_manifest_raw_sha256=$payload" \
        'action_28e_c_value_revision=action17p-node-a-to-node-b-bootstrap' \
        'action_28e_c_value_parent_revision=action15-health-follow-redirects' \
        'action_28e_c_value_source_node=node-a' \
        'action_28e_c_value_created_at=2026-07-30T00:00:00Z' \
        >"$action28e_c_regression_output"
}
classification_is() {
    local action28e_c_regression_expected=$1
    local action28e_c_regression_a_raw=$2
    local action28e_c_regression_b_raw=$3
    local action28e_c_regression_a_canonical=$4
    local action28e_c_regression_b_canonical=$5
    local action28e_c_regression_case=$work_root/classification-$action28e_c_regression_expected

    mkdir -m 0700 "$action28e_c_regression_case"
    make_transcript "$action28e_c_regression_case/a" \
        "$action28e_c_regression_a_raw" "$action28e_c_regression_a_canonical"
    make_transcript "$action28e_c_regression_case/b" \
        "$action28e_c_regression_b_raw" "$action28e_c_regression_b_canonical"
    CADDY_ACTION28E_C_TEST_MODE=1 /bin/bash "$outer" --test-compare \
        "$action28e_c_regression_case/a" "$action28e_c_regression_case/b" \
        >"$action28e_c_regression_case/output"
    grep -Fqx "action_28e_c_outer_value_classification=$action28e_c_regression_expected" \
        "$action28e_c_regression_case/output" || return 1
    grep -Fqx 'action_28e_c_outer_diagnostic_complete=true' \
        "$action28e_c_regression_case/output"
}

printf '{"b":2,"a":1}' >"$work_root/no-newline.json"
printf '{ "a": 1, "b": 2 }\n' >"$work_root/one-newline.json"
printf '{"a":1,"b":2}\n\n' >"$work_root/extra-line.json"
printf '{"a":1,"b":3}\n' >"$work_root/semantic-drift.json"
for action28e_c_regression_name in no-newline one-newline extra-line semantic-drift; do
    inspect_fixture "$work_root/$action28e_c_regression_name.json" \
        "$work_root/$action28e_c_regression_name.output"
done

record_check inspector_self_test /bin/bash "$inspector" --self-test
for action28e_c_regression_name in no-newline one-newline extra-line semantic-drift; do
    record_check "${action28e_c_regression_name}_raw_hash_exact" test \
        "$(extract_test_value raw_sha256 "$work_root/$action28e_c_regression_name.output")" = \
        "$(sha256sum -- "$work_root/$action28e_c_regression_name.json" | awk '{ print $1 }')"
done
record_check no_newline_last_byte_exact test \
    "$(extract_test_value last_byte_hex "$work_root/no-newline.output")" = 7d
record_check one_newline_last_byte_exact test \
    "$(extract_test_value last_byte_hex "$work_root/one-newline.output")" = 0a
record_check extra_line_count_exact test \
    "$(extract_test_value lines "$work_root/extra-line.output")" -eq 2
record_check raw_newline_changes_identity test \
    "$(extract_test_value raw_sha256 "$work_root/no-newline.output")" != \
    "$(extract_test_value raw_sha256 "$work_root/one-newline.output")"
record_check raw_extra_line_changes_identity test \
    "$(extract_test_value raw_sha256 "$work_root/one-newline.output")" != \
    "$(extract_test_value raw_sha256 "$work_root/extra-line.output")"
record_check canonical_ignores_formatting test \
    "$(extract_test_value canonical_payload_sha256 "$work_root/no-newline.output")" = \
    "$(extract_test_value canonical_payload_sha256 "$work_root/one-newline.output")"
record_check canonical_ignores_extra_blank_line test \
    "$(extract_test_value canonical_payload_sha256 "$work_root/one-newline.output")" = \
    "$(extract_test_value canonical_payload_sha256 "$work_root/extra-line.output")"
record_check canonical_detects_semantic_drift test \
    "$(extract_test_value canonical_payload_sha256 "$work_root/one-newline.output")" != \
    "$(extract_test_value canonical_payload_sha256 "$work_root/semantic-drift.output")"
record_check exact_accepted_classified classification_is exact_accepted \
    "$accepted_raw" "$accepted_raw" "$canonical" "$canonical"
record_check serialization_only_classified classification_is serialization_only \
    "$accepted_raw" "$unaccepted_raw" "$canonical" "$canonical"
record_check shared_unaccepted_classified classification_is shared_unaccepted_bytes \
    "$unaccepted_raw" "$unaccepted_raw" "$canonical" "$canonical"
record_check semantic_drift_classified classification_is semantic_drift \
    "$accepted_raw" "$unaccepted_raw" "$canonical" "$changed_canonical"
record_check direct_raw_sha_command grep -Fq \
    "sha256sum -- \"\$action28e_c_file\"" "$inspector"
record_check no_command_substitution_hash_input test \
    "$(grep -Ec 'printf.*sha256sum|echo.*sha256sum|cat.*sha256sum' "$inspector" || true)" -eq 0
record_check exact_node_b_remote_command grep -Fq \
    '"cd / && sudo -n /bin/bash -s -- node-b"' "$outer"
record_check exact_node_a_remote_command grep -Fq \
    '"cd / && sudo -n /bin/bash -s -- node-a"' "$outer"
record_check predecessors_not_invoked test \
    "$(grep -Ec "(/bin/bash|bash)[[:space:]]+\"?\\\$action28e_[ab]_outer\"?" "$outer" || true)" -eq 0

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
