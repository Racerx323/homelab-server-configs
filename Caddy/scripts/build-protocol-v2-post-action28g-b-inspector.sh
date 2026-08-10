#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_b_builder
readonly source_sha256=96b159653883c5a67ae384b1129ce619f2e74f0b44c4846da1d44ae898cd96d9

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_inspector=$script_directory/inspect-protocol-v2-post-action28e-e.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

[[ $# -eq 1 ]]
readonly output_inspector=$1
[[ -f "$source_inspector" && ! -L "$source_inspector" && -x "$source_inspector" ]]
[[ "$(file_hash "$source_inspector")" = "$source_sha256" ]]
[[ ! -e "$output_inspector" ]]

isolation_count=0
test_mode_count=0
while IFS= read -r action28g_b_builder_line || [[ -n "$action28g_b_builder_line" ]]; do
    case "$action28g_b_builder_line" in
        '    if "$@"; then')
            printf '%s\n' '    if "$@" >/dev/null 2>&1; then'
            isolation_count=$((isolation_count + 1))
            ;;
        '    --test-historical-identity)')
            cat <<'ACTION28G_B_TEST_MODE'
    --test-assertion-output)
        [[ $# -eq 2 && "${CADDY_ACTION28G_B_TEST_MODE:-}" == 1 ]]
        record_check candidate_manifest_schema jq -e \
            '(.revision | type == "string" and length > 0) and (.parent_revision | type == "string") and .source_node == "node-a" and (.created_at | type == "string" and length > 0)' \
            "$2"
        exit 0
        ;;
ACTION28G_B_TEST_MODE
            printf '%s\n' "$action28g_b_builder_line"
            test_mode_count=$((test_mode_count + 1))
            ;;
        *) printf '%s\n' "$action28g_b_builder_line" ;;
    esac
done <"$source_inspector" >"$output_inspector"

[[ "$isolation_count" -eq 1 ]]
[[ "$test_mode_count" -eq 1 ]]
chmod 0755 "$output_inspector"
/bin/bash -n "$output_inspector"
printf '%s_source_sha256=%s\n' "$prefix" "$source_sha256"
printf '%s_assertion_output_boundary_corrections=1\n' "$prefix"
printf '%s_production_jq_regression_entrypoint=1\n' "$prefix"
printf '%s_output_sha256=%s\n' "$prefix" "$(file_hash "$output_inspector")"
printf '%s_acceptance=true\n' "$prefix"
