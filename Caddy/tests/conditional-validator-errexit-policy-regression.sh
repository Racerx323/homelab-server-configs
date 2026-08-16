#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}

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

bad_validator_fixture() {
    local later_value=later

    [[ "$1" = valid ]]
    [[ "$later_value" = later ]]
}

good_validator_fixture() {
    local later_value=later

    [[ "$1" = valid ]] || return 1
    [[ "$later_value" = later ]] || return 1
}

if bad_validator_fixture invalid; then
    printf 'conditional_validator_errexit_suppression_reproduced=true\n'
else
    exit 1
fi
if good_validator_fixture invalid; then
    exit 1
fi
good_validator_fixture valid

marked_count=0
while IFS= read -r marked_file; do
    [[ "$(readlink -f "$marked_file")" != "$(readlink -f "$0")" ]] || continue
    validate_marked_file "$marked_file"
    marked_count=$((marked_count + 1))
done < <(find "$caddy_root" -type f -name '*.sh' -exec \
    grep -l 'conditional-validator-explicit-failures-begin' {} + | LC_ALL=C sort)
[[ "$marked_count" -gt 0 ]]
printf 'conditional_validator_marked_file_count=%s\n' "$marked_count"
printf 'conditional_validator_errexit_policy_complete=true\n'
