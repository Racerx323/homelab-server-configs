#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=ssh_stream_local_evidence_policy
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly repository_agents=$script_directory/../../AGENTS.md
work_root=$(mktemp -d /tmp/caddy-ssh-evidence-policy.XXXXXX)
readonly work_root

cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
check_file() {
    local ssh_evidence_source=$1

    [[ -f "$ssh_evidence_source" && ! -L "$ssh_evidence_source" ]] || return 1
    grep -Fq 'bash -s' "$ssh_evidence_source" || return 0
    grep -Fq 'ssh-local-evidence-contract-v1' "$ssh_evidence_source" || return 1
    grep -Eq '(^|[=/"])tmp/' "$ssh_evidence_source" || return 1
    grep -Fq 'mktemp -d' "$ssh_evidence_source" || return 1
    grep -Fq 'chmod 0700' "$ssh_evidence_source" || return 1
    grep -Fq 'chmod 0600' "$ssh_evidence_source" || return 1
    grep -Eq '>"\$[A-Za-z_][A-Za-z0-9_]*stdout' "$ssh_evidence_source" || return 1
    grep -Eq '2>"\$[A-Za-z_][A-Za-z0-9_]*stderr' "$ssh_evidence_source" || return 1
    grep -Eq '\|\|[[:space:]]*$|\|\|[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?' \
        "$ssh_evidence_source" || return 1
    grep -Eq 'emit_stream[^[:cntrl:]]*"\$[A-Za-z_][A-Za-z0-9_]*stdout"' \
        "$ssh_evidence_source" || return 1
    grep -Eq 'emit_stream[^[:cntrl:]]*"\$[A-Za-z_][A-Za-z0-9_]*stderr"' \
        "$ssh_evidence_source" || return 1
    grep -Eq 'status_file|remote_status' "$ssh_evidence_source" || return 1
    grep -Eq 'evidence_(path|directory|parent)' "$ssh_evidence_source" || return 1
    if grep -Eq '^run_live\(\)' "$ssh_evidence_source"; then
        awk '
            /^run_live\(\)/ { inside = 1 }
            inside && /^}/ { inside = 0 }
            inside && /rm -rf/ { unsafe++ }
            END { exit unsafe ? 1 : 0 }
        ' "$ssh_evidence_source" || return 1
    else
        # Dollar-prefixed tokens are intentionally matched as literal source text.
        # shellcheck disable=SC2016
        ! grep -Eq 'rm -rf -- "\$work_root"|rm -rf -- "\$[A-Za-z_][A-Za-z0-9_]*evidence' \
            "$ssh_evidence_source" || return 1
    fi
}
run_checks() {
    local ssh_evidence_checked=0
    local ssh_evidence_failed=0
    local ssh_evidence_source

    [[ $# -gt 0 ]] || return 64
    for ssh_evidence_source in "$@"; do
        ssh_evidence_checked=$((ssh_evidence_checked + 1))
        if ! check_file "$ssh_evidence_source"; then
            printf '%s: local /tmp SSH evidence contract failed\n' "$ssh_evidence_source" >&2
            ssh_evidence_failed=$((ssh_evidence_failed + 1))
        fi
    done
    printf '%s_checked_file_count=%s\n' "$prefix" "$ssh_evidence_checked"
    printf '%s_failed_file_count=%s\n' "$prefix" "$ssh_evidence_failed"
    [[ "$ssh_evidence_failed" -eq 0 ]]
}
self_test() {
    local ssh_evidence_safe=$work_root/run-safe.sh
    local ssh_evidence_missing_capture=$work_root/run-missing-capture.sh
    local ssh_evidence_deleted_capture=$work_root/run-deleted-capture.sh
    local ssh_evidence_status=0

    cat >"$ssh_evidence_safe" <<'SAFE'
#!/usr/bin/env bash
# ssh-local-evidence-contract-v1
evidence_root=/tmp/example
work_root=$(mktemp -d "$evidence_root/run.XXXXXX")
chmod 0700 "$work_root"
remote_stdout=$work_root/remote.stdout
remote_stderr=$work_root/remote.stderr
status_file=$work_root/remote.status
chmod 0600 "$remote_stdout" "$remote_stderr" "$status_file"
ssh host 'cd / && sudo -n /bin/bash -s --' <"$runner" >"$remote_stdout" 2>"$remote_stderr" ||
    remote_status=$?
emit_stream remote_stdout "$remote_stdout"
emit_stream remote_stderr "$remote_stderr"
printf 'evidence_directory=%s\n' "$work_root"
SAFE
    sed '/ssh-local-evidence-contract-v1/d' "$ssh_evidence_safe" >"$ssh_evidence_missing_capture"
    cp -- "$ssh_evidence_safe" "$ssh_evidence_deleted_capture"
    # shellcheck disable=SC2016
    printf 'rm -rf -- "$work_root"\n' >>"$ssh_evidence_deleted_capture"
    run_checks "$ssh_evidence_safe" >/dev/null || return 1
    run_checks "$ssh_evidence_missing_capture" >/dev/null 2>&1 || ssh_evidence_status=$?
    [[ "$ssh_evidence_status" -eq 1 ]] || return 1
    ssh_evidence_status=0
    run_checks "$ssh_evidence_deleted_capture" >/dev/null 2>&1 || ssh_evidence_status=$?
    [[ "$ssh_evidence_status" -eq 1 ]] || return 1
    # The backticks are literal repository-rule text.
    # shellcheck disable=SC2016
    grep -Fq 'Capture SSH stdout, stderr, and status in workstation files beneath `/tmp`.' \
        "$repository_agents" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'Long-running node commands must write node-local evidence beneath `/tmp`' \
        "$repository_agents" || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --check)
        shift
        run_checks "$@"
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        ;;
    *) exit 64 ;;
esac
