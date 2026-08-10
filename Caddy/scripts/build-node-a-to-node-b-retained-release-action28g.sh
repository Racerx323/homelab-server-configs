#!/usr/bin/env bash
# shellcheck disable=SC1003,SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_builder
readonly source_sha256=9eebe135098792bb8a5f1bbbbfa4a7f6a1e13bf1cfc89be411b22ef4ed45b7ec

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_runner=$script_directory/run-node-a-to-node-b-retained-release-action28f.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s OUTPUT\n' "${0##*/}" >&2
    exit 64
fi
readonly output_runner=$1
[[ -f "$source_runner" && ! -L "$source_runner" ]]
[[ "$(file_hash "$source_runner")" == "$source_sha256" ]]
[[ ! -e "$output_runner" ]]

validation_revision_count=0
validation_parent_count=0
validation_manifest_count=0
fixture_revision_count=0
fixture_parent_count=0
fixture_manifest_count=0
contract_coverage_count=0

while IFS= read -r source_line || [[ -n "$source_line" ]]; do
    case "$source_line" in
        '        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_revision")"')
            printf '%s\n' '        "$([[ "$transcript_prefix" == action_28f_node_b && "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_revision")"'
            validation_revision_count=$((validation_revision_count + 1))
            ;;
        '        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_parent")"')
            printf '%s\n' '        "$([[ "$transcript_prefix" == action_28f_node_b && "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_parent")"'
            validation_parent_count=$((validation_parent_count + 1))
            ;;
        '        "$([[ "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_manifest_sha256")"')
            printf '%s\n' '        "$([[ "$transcript_prefix" == action_28f_node_b && "$expected_phase" == preflight ]] && printf unavailable || printf %s "$candidate_manifest_sha256")"'
            validation_manifest_count=$((validation_manifest_count + 1))
            ;;
        '        "${fixture_prefix}_value_revision=unavailable" \')
            printf '%s\n' '        "${fixture_prefix}_value_revision=$([[ "$fixture_prefix" == action_28f_node_b && "$fixture_phase" == preflight ]] && printf unavailable || printf %s "$candidate_revision")" \'
            fixture_revision_count=$((fixture_revision_count + 1))
            ;;
        '        "${fixture_prefix}_value_parent_revision=unavailable" \')
            printf '%s\n' '        "${fixture_prefix}_value_parent_revision=$([[ "$fixture_prefix" == action_28f_node_b && "$fixture_phase" == preflight ]] && printf unavailable || printf %s "$candidate_parent")" \'
            fixture_parent_count=$((fixture_parent_count + 1))
            ;;
        '        "${fixture_prefix}_value_manifest_sha256=unavailable" \')
            printf '%s\n' '        "${fixture_prefix}_value_manifest_sha256=$([[ "$fixture_prefix" == action_28f_node_b && "$fixture_phase" == preflight ]] && printf unavailable || printf %s "$candidate_manifest_sha256")" \'
            fixture_manifest_count=$((fixture_manifest_count + 1))
            ;;
        "        printf '%s_contract_test_complete=true\\n' \"\$prefix\"")
            cat <<'ACTION28G_CONTRACT'
        write_fixture "$contract_directory/node-b-valid" action_28f_node_b preflight
        checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
        validate_transcript node_b_valid action_28f_node_b \
            "$contract_directory/node-b-valid" preflight 0 >/dev/null
        [[ "$checks_failed" -eq 0 ]]
        printf 'action_28g_node_b_preflight_unavailable_identity_accepted=true\n'
        for identity_name in revision parent_revision manifest_sha256; do
            sed "s/^action_28f_node_a_value_${identity_name}=.*/action_28f_node_a_value_${identity_name}=unavailable/" \
                "$contract_directory/valid" >"$contract_directory/node-a-${identity_name}-invalid"
            checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
            validate_transcript "node_a_${identity_name}_invalid" action_28f_node_a \
                "$contract_directory/node-a-${identity_name}-invalid" preflight 0 \
                >/dev/null 2>&1
            [[ "$checks_failed" -gt 0 ]]
            printf 'action_28g_node_a_preflight_%s_unavailable_rejected=true\n' "$identity_name"
        done
        sed \
            -e "s/^action_28f_node_b_value_revision=unavailable$/action_28f_node_b_value_revision=$candidate_revision/" \
            -e "s/^action_28f_node_b_value_parent_revision=unavailable$/action_28f_node_b_value_parent_revision=$candidate_parent/" \
            -e "s/^action_28f_node_b_value_manifest_sha256=unavailable$/action_28f_node_b_value_manifest_sha256=$candidate_manifest_sha256/" \
            "$contract_directory/node-b-valid" >"$contract_directory/node-b-identity-invalid"
        checks_total=0 checks_passed=0 checks_failed=0 first_failure=none
        validate_transcript node_b_identity_invalid action_28f_node_b \
            "$contract_directory/node-b-identity-invalid" preflight 0 >/dev/null 2>&1
        [[ "$checks_failed" -gt 0 ]]
        printf 'action_28g_node_b_preflight_candidate_identity_rejected=true\n'
        printf '%s_contract_test_complete=true\n' "$prefix"
ACTION28G_CONTRACT
            contract_coverage_count=$((contract_coverage_count + 1))
            ;;
        *) printf '%s\n' "$source_line" ;;
    esac
done <"$source_runner" >"$output_runner"

[[ "$validation_revision_count" -eq 1 ]]
[[ "$validation_parent_count" -eq 1 ]]
[[ "$validation_manifest_count" -eq 1 ]]
[[ "$fixture_revision_count" -eq 1 ]]
[[ "$fixture_parent_count" -eq 1 ]]
[[ "$fixture_manifest_count" -eq 1 ]]
[[ "$contract_coverage_count" -eq 1 ]]
chmod 0755 "$output_runner"
/bin/bash -n "$output_runner"
printf '%s_source_sha256=%s\n' "$prefix" "$source_sha256"
printf '%s_output_sha256=%s\n' "$prefix" "$(file_hash "$output_runner")"
printf '%s_corrected_identity_expectations=3\n' "$prefix"
printf '%s_corrected_fixture_identities=3\n' "$prefix"
printf '%s_real_producer_contract_coverage=true\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
