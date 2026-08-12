#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly repository_root="$caddy_root/.."
readonly action_regression="$script_directory/action17u-a-node-b-postinstall-regression.sh"
readonly action19c_definition_regression="$script_directory/action19c-a-node-a-keepalived-prerequisite-definition-regression.sh"
readonly immutable_action28ad="$caddy_root/scripts/transact-coupled-go-live-action28ad.sh"
readonly immutable_action28ad_sha256=5fa6a8fe85b3d9f4c8f2333d1a3f2ebab3117ecc3b4eb0bf8f7ac734a48f310f

report_error() {
    local error_line=$1
    local error_status=$2
    printf 'conditional_validator_policy_failure_line=%s\n' "$error_line" >&2
    printf 'conditional_validator_policy_failure_status=%s\n' "$error_status" >&2
}
trap 'report_error "$LINENO" "$?"' ERR

bad_validator_fixture() {
    local bad_later_value=later
    [[ "$1" = valid ]]
    [[ "$bad_later_value" = later ]]
}

good_validator_fixture() {
    local good_later_value=later
    [[ "$1" = valid ]] || return 1
    [[ "$good_later_value" = later ]] || return 1
}

validate_marked_file() {
    local policy_file=$1
    local marker_counts
    marker_counts=$(awk '
        /conditional-validator-explicit-failures-begin/ { begin++ }
        /conditional-validator-explicit-failures-end/ { end++ }
        END { printf "%d:%d", begin, end }
    ' "$policy_file")
    [[ "$marker_counts" != 0:0 ]] || return 1
    [[ "${marker_counts%:*}" = "${marker_counts#*:}" ]] || return 1
    awk '
        /conditional-validator-explicit-failures-begin/ { inside = 1; next }
        /conditional-validator-explicit-failures-end/ { inside = 0; next }
        !inside { next }
        /^[[:space:]]*($|#|for[[:space:]]|done$)/ { next }
        /^[[:space:]]*if[[:space:]]/ { next }
        /^[[:space:]]*\047/ { next }
        /\[\[|cmp -s|is_[a-z_]+|transcript_grammar_valid|secret_free|validate_assertion_set|require_one|value_for|conditional-validator-requires-return/ {
            marked_return = index($0,
                "conditional-validator-requires-return") != 0 &&
                $0 ~ /return[[:space:]]+[0-9]+/
            if (index($0, "|| return") == 0 && !marked_return) {
                printf "conditional_validator_missing_explicit_return=%s:%d:%s\n", FILENAME, FNR, $0 > "/dev/stderr"
                invalid++
            }
        }
        END { exit invalid ? 1 : 0 }
    ' "$policy_file"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    printf 'conditional_validator_errexit_policy_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

if bad_validator_fixture invalid; then
    printf 'conditional_validator_historical_errexit_suppression_reproduced=true\n'
else
    printf 'Failed to reproduce conditional-function errexit suppression.\n' >&2
    exit 1
fi
if good_validator_fixture invalid; then
    printf 'Explicit-return validator accepted an early-invalid fixture.\n' >&2
    exit 1
fi
good_validator_fixture valid
printf 'conditional_validator_explicit_return_false_positive_rejected=true\n'
printf 'conditional_validator_explicit_return_false_negative_accepted=true\n'

# Backticks are required as literal policy text.
# shellcheck disable=SC2016
grep -Fq 'Never rely on `set -e` or `set -E`' "$repository_root/AGENTS.md"
grep -Fq 'conditional-validator-explicit-failures-begin' "$repository_root/AGENTS.md"

marked_count=0
immutable_exception_count=0
while IFS= read -r marked_file; do
    [[ "$(readlink -f "$marked_file")" != "$(readlink -f "$0")" ]] || continue
    if [[ "$(readlink -f "$marked_file")" = "$(readlink -f "$immutable_action28ad")" ]]; then
        [[ "$(sha256sum "$marked_file" | awk '{ print $1 }')" = "$immutable_action28ad_sha256" ]]
        immutable_exception_count=$((immutable_exception_count + 1))
        continue
    fi
    validate_marked_file "$marked_file"
    marked_count=$((marked_count + 1))
done < <(find "$caddy_root" -type f -name '*.sh' -exec \
    grep -l 'conditional-validator-explicit-failures-begin' {} + | LC_ALL=C sort)
[[ "$marked_count" -gt 0 ]]
[[ "$immutable_exception_count" -eq 1 ]]
printf 'conditional_validator_marked_file_count=%s\n' "$marked_count"
printf 'conditional_validator_immutable_exception_count=%s\n' \
    "$immutable_exception_count"

regression_output=$("$action_regression")
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    grep -Fxq action_17u_a_production_runner_behavior=skipped_host_authoritative \
        <<<"$regression_output"
else
    grep -Fxq action_17u_a_regression_duplicate_status=97 <<<"$regression_output"
fi
grep -Fxq action_17u_a_false_positive_duplicate_rejected=true <<<"$regression_output"
grep -Fxq action_17u_a_false_negative_valid_success_accepted=true <<<"$regression_output"
grep -Fxq action_17u_a_false_negative_semantic_mismatch_preserved=true <<<"$regression_output"

action19c_output=$(mktemp /tmp/caddy-action19c-conditional.stdout.XXXXXX)
readonly action19c_output
action19c_error=$(mktemp /tmp/caddy-action19c-conditional.stderr.XXXXXX)
readonly action19c_error
# shellcheck disable=SC2317
cleanup_action19c() { rm -f -- "$action19c_output" "$action19c_error"; }
trap cleanup_action19c EXIT
"$action19c_definition_regression" >"$action19c_output" \
    2>"$action19c_error"
[[ ! -s "$action19c_error" ]]
grep -Fxq \
    action_19c_a_definition_regression_dynamic_scope_collision_rejected=true \
    "$action19c_output"
grep -Fxq \
    action_19c_a_definition_regression_early_invalid_later_valid_rejected=true \
    "$action19c_output"
grep -Fxq \
    action_19c_a_definition_regression_valid_policy_fixture_accepted=true \
    "$action19c_output"
grep -Fxq action_19c_a_definition_regression_complete=true \
    "$action19c_output"

printf 'conditional_validator_errexit_policy_regression_complete=true\n'
