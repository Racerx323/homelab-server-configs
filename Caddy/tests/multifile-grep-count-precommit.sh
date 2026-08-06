#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=multifile_grep_count_precommit
readonly historical_candidate_path=Caddy/tests/action20d-retry10-d-retry-candidate-stage-regression.sh
readonly historical_candidate_sha256=190d22ca2be002488fbeffe4ca80dc10d0a5f3456f1dd8d8bffb8f457fe7872c
readonly historical_complete_path=Caddy/tests/action20d-retry10-d-retry2-complete-path-regression.sh
readonly historical_complete_sha256=4fba7ad2744639a321dab5e35cc93abcf5480dbb6a86344bdbb9fca844fa8b83

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly policy=$script_directory/multifile-grep-count-policy.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
classify_exception() {
    local grep_precommit_source_path=$1
    local grep_precommit_expected_path=$2
    local grep_precommit_expected_hash=$3

    [[ "$grep_precommit_source_path" = "$grep_precommit_expected_path" ]] || return 1
    [[ "$(file_hash "$grep_precommit_source_path")" = "$grep_precommit_expected_hash" ]]
}
is_immutable_exception() {
    local grep_precommit_source_path=$1

    case "$grep_precommit_source_path" in
        "$historical_candidate_path")
            classify_exception "$grep_precommit_source_path" \
                "$historical_candidate_path" "$historical_candidate_sha256"
            ;;
        "$historical_complete_path")
            classify_exception "$grep_precommit_source_path" \
                "$historical_complete_path" "$historical_complete_sha256"
            ;;
        *) return 1 ;;
    esac
}
run_self_test() {
    local grep_precommit_test_root
    local grep_precommit_test_path
    local grep_precommit_test_hash

    grep_precommit_test_root=$(mktemp -d /tmp/multifile-grep-precommit.XXXXXX)
    trap 'rm -rf -- "$grep_precommit_test_root"' RETURN
    grep_precommit_test_path=$grep_precommit_test_root/historical.sh
    printf '%s\n' '#!/usr/bin/env bash' 'printf test' >"$grep_precommit_test_path"
    grep_precommit_test_hash=$(file_hash "$grep_precommit_test_path")
    classify_exception "$grep_precommit_test_path" "$grep_precommit_test_path" \
        "$grep_precommit_test_hash"
    printf '%s_exact_hash_accepted=true\n' "$prefix"
    printf '%s\n' '# changed' >>"$grep_precommit_test_path"
    if classify_exception "$grep_precommit_test_path" "$grep_precommit_test_path" \
        "$grep_precommit_test_hash"; then
        printf '%s_changed_hash_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_changed_hash_rejected=true\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

if [[ "${1:-}" = --self-test ]]; then
    [[ $# -eq 1 ]] || exit 64
    run_self_test
    exit 0
fi
[[ $# -gt 0 ]] || exit 64
declare -a checked_paths=()
exception_count=0
for grep_precommit_source_path in "$@"; do
    if is_immutable_exception "$grep_precommit_source_path"; then
        exception_count=$((exception_count + 1))
        continue
    fi
    checked_paths+=("$grep_precommit_source_path")
done
readonly exception_count
printf '%s_hash_pinned_exception_count=%s\n' "$prefix" "$exception_count"
if [[ "${#checked_paths[@]}" -eq 0 ]]; then
    printf '%s_checked_file_count=0\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
    exit 0
fi
/bin/bash "$policy" --check "${checked_paths[@]}"
printf '%s_checked_file_count=%s\n' "$prefix" "${#checked_paths[@]}"
printf '%s_complete=true\n' "$prefix"
