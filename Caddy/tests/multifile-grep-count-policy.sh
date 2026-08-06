#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=multifile_grep_count_policy

check_file() {
    local multifile_grep_policy_source_path=$1
    local multifile_grep_policy_ast_path=$2
    local multifile_grep_policy_match_path=$3

    [[ -f "$multifile_grep_policy_source_path" &&
        ! -L "$multifile_grep_policy_source_path" ]] || return 1
    shfmt --to-json <"$multifile_grep_policy_source_path" \
        >"$multifile_grep_policy_ast_path" || return 1
    jq -r '
        .. | objects |
        select(.Type? == "CallExpr") |
        select((.Args[0].Parts[0].Value? // "") == "grep") |
        select(any(.Args[1:][]?;
            ([.Parts[]? | select(.Type == "Lit") | .Value] | join("")) as $arg |
            $arg == "--count" or ($arg | test("^-[^-]*c")))) |
        select((.Args | length) >= 5) |
        "\(.Pos.Line): grep count mode has a non-scalar or ambiguous multi-operand shape"
    ' "$multifile_grep_policy_ast_path" >"$multifile_grep_policy_match_path" || return 1
    if [[ -s "$multifile_grep_policy_match_path" ]]; then
        sed "s|^|${multifile_grep_policy_source_path}:|" \
            "$multifile_grep_policy_match_path" >&2
        return 1
    fi
}
run_checks() {
    local multifile_grep_policy_source_index=0
    local multifile_grep_policy_source_path
    local multifile_grep_policy_failure_count=0

    [[ $# -gt 0 ]] || return 64
    for multifile_grep_policy_source_path in "$@"; do
        multifile_grep_policy_source_index=$((multifile_grep_policy_source_index + 1))
        if ! check_file "$multifile_grep_policy_source_path" \
            "$work_root/source-${multifile_grep_policy_source_index}.json" \
            "$work_root/source-${multifile_grep_policy_source_index}.matches"; then
            multifile_grep_policy_failure_count=$((multifile_grep_policy_failure_count + 1))
        fi
    done
    printf '%s_checked_file_count=%s\n' "$prefix" "$multifile_grep_policy_source_index"
    printf '%s_failed_file_count=%s\n' "$prefix" "$multifile_grep_policy_failure_count"
    [[ "$multifile_grep_policy_failure_count" -eq 0 ]]
}
run_self_test() {
    local multifile_grep_policy_safe=$work_root/safe.sh
    local multifile_grep_policy_unsafe=$work_root/unsafe.sh
    local multifile_grep_policy_long_unsafe=$work_root/long-unsafe.sh
    local multifile_grep_policy_status=0

    cat >"$multifile_grep_policy_safe" <<'SAFE'
#!/usr/bin/env bash
first_count=$(grep -Ec 'needle' "$first_file" || true)
second_count=$(grep -c 'needle' "$second_file" || true)
for source_path in "$@"; do
    [[ "$(grep -Fc 'needle' "$source_path" || true)" -eq 0 ]] || exit 1
done
SAFE
    cat >"$multifile_grep_policy_unsafe" <<'UNSAFE'
#!/usr/bin/env bash
combined_count=$(grep -Ec 'needle' "$first_file" "$second_file" || true)
UNSAFE
    cat >"$multifile_grep_policy_long_unsafe" <<'LONG_UNSAFE'
#!/usr/bin/env bash
combined_count=$(grep --count -- 'needle' \
    "$first_file" \
    "$second_file" || true)
LONG_UNSAFE
    chmod 0700 "$multifile_grep_policy_safe" \
        "$multifile_grep_policy_unsafe" "$multifile_grep_policy_long_unsafe"
    run_checks "$multifile_grep_policy_safe" >/dev/null
    printf '%s_self_test_single_file_forms_accepted=true\n' "$prefix"
    multifile_grep_policy_status=0
    run_checks "$multifile_grep_policy_unsafe" >/dev/null 2>&1 ||
        multifile_grep_policy_status=$?
    [[ "$multifile_grep_policy_status" -eq 1 ]]
    printf '%s_self_test_short_multifile_rejected=true\n' "$prefix"
    multifile_grep_policy_status=0
    run_checks "$multifile_grep_policy_long_unsafe" >/dev/null 2>&1 ||
        multifile_grep_policy_status=$?
    [[ "$multifile_grep_policy_status" -eq 1 ]]
    printf '%s_self_test_long_multifile_rejected=true\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

work_root=$(mktemp -d /tmp/caddy-multifile-grep-count-policy.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

case "${1:-}" in
    --check)
        shift
        run_checks "$@"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_self_test
        ;;
    *)
        printf 'Usage: %s --check FILE [FILE ...] | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
