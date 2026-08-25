#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=portable_awk_policy
readonly awk_command_regex='(^|[[:space:];|&(])awk([[:space:]]|$)'
readonly interval_regex='\{[0-9]+(,[0-9]*)?\}'
readonly double_quoted_regex='"([^"\\]|\\.)*"'
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/tests/repository}

scan_file() {
    local portable_awk_path=$1
    local portable_awk_line
    local portable_awk_quotes
    local portable_awk_quote_count
    local portable_awk_code
    local portable_awk_in_program=false
    local portable_awk_line_number=0

    [[ -f "$portable_awk_path" && ! -L "$portable_awk_path" ]] || return 1
    while IFS= read -r portable_awk_line || [[ -n "$portable_awk_line" ]]; do
        portable_awk_line_number=$((portable_awk_line_number + 1))
        if [[ "$portable_awk_in_program" = false &&
            ! "$portable_awk_line" =~ $awk_command_regex ]]; then
            continue
        fi
        portable_awk_code=$portable_awk_line
        while [[ "$portable_awk_code" =~ $double_quoted_regex ]]; do
            portable_awk_code=${portable_awk_code/"${BASH_REMATCH[0]}"/}
        done
        if [[ "$portable_awk_code" =~ $interval_regex ]]; then
            printf '%s_violation=%s:%s\n' "$prefix" "$portable_awk_path" \
                "$portable_awk_line_number" >&2
            return 1
        fi
        portable_awk_quotes=${portable_awk_line//[^\']/}
        portable_awk_quote_count=${#portable_awk_quotes}
        if ((portable_awk_quote_count % 2 == 1)); then
            if [[ "$portable_awk_in_program" = true ]]; then
                portable_awk_in_program=false
            else
                portable_awk_in_program=true
            fi
        fi
    done <"$portable_awk_path"
    [[ "$portable_awk_in_program" = false ]]
}

run_self_test() {
    local portable_awk_root
    local portable_awk_invalid_interval='{64}'

    portable_awk_root=$(mktemp -d /tmp/repository-portable-awk-policy.XXXXXX)
    {
        printf '%s\n' '#!/usr/bin/env bash' "awk '"
        # These are literal source fixtures, not expressions for this shell.
        # shellcheck disable=SC2016
        printf '%s\n' '    length($2) != 64 || $2 !~ /^[0-9a-f]+$/ { exit 1 }'
        # shellcheck disable=SC2016
        printf '%s\n' "' input" '[[ "$value" =~ ^[0-9a-f]{64}$ ]]'
    } >"$portable_awk_root/valid.sh"
    scan_file "$portable_awk_root/valid.sh" || {
        rm -rf -- "$portable_awk_root"
        return 1
    }
    printf '%s\n' '#!/usr/bin/env bash' \
        "awk '\$2 !~ /^[0-9a-f]${portable_awk_invalid_interval}\$/ { exit 1 }' input" \
        >"$portable_awk_root/invalid-inline.sh"
    ! scan_file "$portable_awk_root/invalid-inline.sh" || {
        rm -rf -- "$portable_awk_root"
        return 1
    }
    printf '%s\n' '#!/usr/bin/env bash' "awk '" \
        "    \$2 !~ /^[0-9a-f]${portable_awk_invalid_interval}\$/ { exit 1 }" \
        "' input" >"$portable_awk_root/invalid-multiline.sh"
    ! scan_file "$portable_awk_root/invalid-multiline.sh" || {
        rm -rf -- "$portable_awk_root"
        return 1
    }
    rm -rf -- "$portable_awk_root"
    printf '%s_self_test=true\n' "$prefix"
}

case "${1:---self-test}" in
    --check)
        shift
        portable_awk_checked=0
        portable_awk_failed=0
        if [[ $# -eq 0 ]]; then
            mapfile -t portable_awk_paths < <(
                git -C "$repository_root" ls-files --cached --others \
                    --exclude-standard '*.sh' |
                    while IFS= read -r portable_awk_relative; do
                        [[ -f "$repository_root/$portable_awk_relative" ]] &&
                            printf '%s\n' "$portable_awk_relative"
                    done |
                    LC_ALL=C sort -u
            )
            for portable_awk_index in "${!portable_awk_paths[@]}"; do
                portable_awk_paths[portable_awk_index]=$repository_root/${portable_awk_paths[portable_awk_index]}
            done
        else
            portable_awk_paths=("$@")
        fi
        for portable_awk_path in "${portable_awk_paths[@]}"; do
            portable_awk_checked=$((portable_awk_checked + 1))
            if ! scan_file "$portable_awk_path"; then
                portable_awk_failed=$((portable_awk_failed + 1))
            fi
        done
        printf '%s_checked_file_count=%s\n' "$prefix" "$portable_awk_checked"
        printf '%s_failed_file_count=%s\n' "$prefix" "$portable_awk_failed"
        [[ "$portable_awk_checked" -gt 0 && "$portable_awk_failed" -eq 0 ]]
        printf '%s_complete=true\n' "$prefix"
        ;;
    --self-test)
        [[ $# -le 1 ]] || exit 64
        run_self_test || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check [FILE ...]|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
