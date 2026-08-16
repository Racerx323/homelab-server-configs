#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=remote_streamed_bash_cwd_policy

check_file() {
    local cwd_policy_source=$1
    local cwd_policy_logical=$2
    local cwd_policy_matches=$3

    [[ -f "$cwd_policy_source" && ! -L "$cwd_policy_source" ]] || return 1
    case "$cwd_policy_source" in
        Caddy/scripts/run-*.sh | */Caddy/scripts/run-*.sh) ;;
        *) return 0 ;;
    esac

    awk '
        {
            line = line $0
            if (line ~ /\\[[:space:]]*$/) {
                sub(/\\[[:space:]]*$/, " ", line)
                next
            }
            print line
            line = ""
        }
        END {
            if (line != "") print line
        }
    ' "$cwd_policy_source" >"$cwd_policy_logical" || return 1

    awk '
        /ssh[[:space:]]/ && /\/bin\/bash -c([[:space:]]|$)/ {
            print NR ": remote Bash -c is unsafe across OpenSSH serialization"
            next
        }
        /bash -s/ && /<"?\$[A-Za-z_][A-Za-z0-9_]*"?/ &&
        !/cd \/ && sudo -n \/bin\/bash -s/ {
            print NR ": streamed remote Bash does not establish cd / before sudo"
        }
    ' "$cwd_policy_logical" >"$cwd_policy_matches" || return 1
    if [[ -s "$cwd_policy_matches" ]]; then
        sed "s|^|${cwd_policy_source}:|" "$cwd_policy_matches" >&2
        return 1
    fi
}
run_checks() {
    local cwd_policy_index=0
    local cwd_policy_source
    local cwd_policy_failures=0

    [[ $# -gt 0 ]] || return 64
    for cwd_policy_source in "$@"; do
        cwd_policy_index=$((cwd_policy_index + 1))
        if ! check_file "$cwd_policy_source" \
            "$work_root/source-${cwd_policy_index}.logical" \
            "$work_root/source-${cwd_policy_index}.matches"; then
            cwd_policy_failures=$((cwd_policy_failures + 1))
        fi
    done
    printf '%s_checked_file_count=%s\n' "$prefix" "$cwd_policy_index"
    printf '%s_failed_file_count=%s\n' "$prefix" "$cwd_policy_failures"
    [[ "$cwd_policy_failures" -eq 0 ]]
}
run_self_test() {
    local cwd_policy_safe=$work_root/Caddy/scripts/run-safe.sh
    local cwd_policy_unsafe=$work_root/Caddy/scripts/run-unsafe.sh
    local cwd_policy_unsafe_command=$work_root/Caddy/scripts/run-unsafe-command.sh
    local cwd_policy_status=0

    install -d -m 0700 "$work_root/Caddy/scripts" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'cd / && sudo -n /bin/bash -s --' <\"\$inspector\"" \
        >"$cwd_policy_safe" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'sudo -n /bin/bash -s' <\"\$inspector\"" \
        >"$cwd_policy_unsafe" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node /bin/bash -c 'set -Eeuo pipefail; install -d \"\$1\"' _ /tmp/example" \
        >"$cwd_policy_unsafe_command" || return 1
    run_checks "$cwd_policy_safe" >/dev/null || return 1
    printf '%s_self_test_root_transition_accepted=true\n' "$prefix"
    run_checks "$cwd_policy_unsafe" >/dev/null 2>&1 || cwd_policy_status=$?
    [[ "$cwd_policy_status" -eq 1 ]] || return 1
    printf '%s_self_test_missing_root_transition_rejected=true\n' "$prefix"
    cwd_policy_status=0
    run_checks "$cwd_policy_unsafe_command" >/dev/null 2>&1 || cwd_policy_status=$?
    [[ "$cwd_policy_status" -eq 1 ]] || return 1
    printf '%s_self_test_remote_bash_c_rejected=true\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

work_root=$(mktemp -d /tmp/caddy-remote-cwd-policy.XXXXXX)
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
