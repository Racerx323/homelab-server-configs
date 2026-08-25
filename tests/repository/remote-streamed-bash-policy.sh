#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=remote_streamed_bash_policy

check_file() {
    local remote_bash_source=$1
    local remote_bash_logical=$2
    local remote_bash_matches=$3

    [[ -f "$remote_bash_source" && ! -L "$remote_bash_source" ]] || return 1
    case "$remote_bash_source" in
        scripts/*.sh | */scripts/*.sh) ;;
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
    ' "$remote_bash_source" >"$remote_bash_logical" || return 1

    awk '
        function is_ssh_invocation(value) {
            return value ~ /(^|[[:space:]])ssh[[:space:]]/ ||
                value ~ /"\$[A-Za-z_][A-Za-z0-9_]*ssh(_command)?"[[:space:]]/
        }
        !is_ssh_invocation($0) { next }
        /\/bin\/bash -c([[:space:]]|$)/ {
            print NR ": remote Bash -c is unsafe across OpenSSH serialization"
            next
        }
        /\/bin\/bash -s/ {
            invalid = 0
            if ($0 !~ /cd \/ &&/) invalid = 1
            if ($0 !~ /\/bin\/bash -s --/) invalid = 1
            if ($0 ~ /sudo[[:space:]]/ && $0 !~ /sudo -n \/bin\/bash -s --/) invalid = 1
            if ($0 !~ /</) invalid = 1
            if (invalid)
                print NR ": streamed remote Bash lacks cd /, noninteractive sudo, --, or stdin transport"
        }
    ' "$remote_bash_logical" >"$remote_bash_matches" || return 1
    if [[ -s "$remote_bash_matches" ]]; then
        sed "s|^|${remote_bash_source}:|" "$remote_bash_matches" >&2
        return 1
    fi
}

run_checks() {
    local remote_bash_index=0
    local remote_bash_source
    local remote_bash_failures=0

    [[ $# -gt 0 ]] || return 64
    for remote_bash_source in "$@"; do
        remote_bash_index=$((remote_bash_index + 1))
        if ! check_file "$remote_bash_source" \
            "$work_root/source-${remote_bash_index}.logical" \
            "$work_root/source-${remote_bash_index}.matches"; then
            remote_bash_failures=$((remote_bash_failures + 1))
        fi
    done
    printf '%s_checked_file_count=%s\n' "$prefix" "$remote_bash_index"
    printf '%s_failed_file_count=%s\n' "$prefix" "$remote_bash_failures"
    [[ "$remote_bash_failures" -eq 0 ]]
}

run_self_test() {
    local remote_bash_scripts=$work_root/example/Nautobot/scripts
    local remote_bash_safe=$remote_bash_scripts/run-safe.sh
    local remote_bash_safe_unprivileged=$remote_bash_scripts/run-safe-unprivileged.sh
    local remote_bash_safe_variable=$remote_bash_scripts/run-safe-variable.sh
    local remote_bash_missing_root=$remote_bash_scripts/run-missing-root.sh
    local remote_bash_missing_delimiter=$remote_bash_scripts/run-missing-delimiter.sh
    local remote_bash_unsafe_command=$remote_bash_scripts/run-unsafe-command.sh
    local remote_bash_local_command=$remote_bash_scripts/run-local-command.sh
    local remote_bash_status=0

    install -d -m 0700 "$remote_bash_scripts" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'cd / && sudo -n /bin/bash -s --' <\"\$program\"" \
        >"$remote_bash_safe" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'cd / && /bin/bash -s --' <\"\$program\"" \
        >"$remote_bash_safe_unprivileged" || return 1
    # This writes literal shell source for the policy fixture.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        '"$ssh_command" "$host" "cd / && sudo -n /bin/bash -s -- $mode" <"$program"' \
        >"$remote_bash_safe_variable" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'sudo -n /bin/bash -s --' <\"\$program\"" \
        >"$remote_bash_missing_root" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node 'cd / && sudo -n /bin/bash -s' <\"\$program\"" \
        >"$remote_bash_missing_delimiter" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "ssh pi@node /bin/bash -c 'install -d /tmp/example'" \
        >"$remote_bash_unsafe_command" || return 1
    printf '%s\n' '#!/usr/bin/env bash' \
        "/bin/bash -c 'install -d /tmp/example'" \
        >"$remote_bash_local_command" || return 1

    run_checks "$remote_bash_safe" "$remote_bash_safe_unprivileged" \
        "$remote_bash_safe_variable" "$remote_bash_local_command" >/dev/null || return 1
    printf '%s_self_test_safe_forms_accepted=true\n' "$prefix"
    for remote_bash_invalid in "$remote_bash_missing_root" \
        "$remote_bash_missing_delimiter" "$remote_bash_unsafe_command"; do
        remote_bash_status=0
        run_checks "$remote_bash_invalid" >/dev/null 2>&1 || remote_bash_status=$?
        [[ "$remote_bash_status" -eq 1 ]] || return 1
    done
    printf '%s_self_test_unsafe_forms_rejected=true\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

work_root=$(mktemp -d /tmp/repository-remote-streamed-bash-policy.XXXXXX)
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
