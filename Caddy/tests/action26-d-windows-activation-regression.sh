#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly powershell_action=$caddy_root/scripts/Invoke-WorkstationWslMirroredActivationAction26d.ps1
readonly linux_inspector=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly candidate=$caddy_root/configs/wsl/.wslconfig
regression_root=
run_windows_cases=true

case "${1:-}" in
    "") ;;
    --linux-only) run_windows_cases=false ;;
    *) exit 64 ;;
esac

fail() {
    printf 'action_26_d_regression_failure=%s\n' "$1" >&2
    return 1
}
cleanup() {
    local action26d_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26d_regression_status"
}
run_powershell_case() {
    local action26d_case_name=$1
    local action26d_case_mode=$2
    local action26d_case_root=$regression_root/$action26d_case_name
    local action26d_case_target=$action26d_case_root/.wslconfig
    local action26d_case_status=0

    mkdir -p "$action26d_case_root"
    cp -- "$candidate" "$action26d_case_target"
    : >"$action26d_case_root/calls"
    ACTION26D_FAKE_MODE=$action26d_case_mode \
        ACTION26D_FAKE_CALLS=$action26d_case_root/calls \
        pwsh -NoProfile -File "$powershell_action" \
        -AllowNonWindowsTest \
        -WslExe "$regression_root/fake-wsl.exe" \
        -Target "$action26d_case_target" \
        >"$action26d_case_root/stdout" 2>"$action26d_case_root/stderr" || action26d_case_status=$?
    printf '%s\n' "$action26d_case_status" >"$action26d_case_root/status"
}

regression_root=$(mktemp -d /tmp/caddy-action26-d-regression.XXXXXX)
trap cleanup EXIT INT TERM

cat >"$regression_root/fake-wsl.exe" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$ACTION26D_FAKE_CALLS"
case "$1" in
    --shutdown) exit 0 ;;
    --list)
        [[ "$*" != '--list --quiet' ]] || printf 'Ubuntu\n'
        exit 0
        ;;
    --distribution)
        case "${ACTION26D_FAKE_MODE:?}:$*" in
            success:*--expect-mirrored)
                printf '%s\n' \
                    action_26_d_linux_check_fixture=true \
                    action_26_d_linux_persistent_mutation=false \
                    action_26_d_linux_acceptance=true
                exit 0
                ;;
            rollback:*--expect-mirrored)
                printf 'fixture mirrored acceptance failed\n' >&2
                exit 1
                ;;
            rollback:*--expect-nat)
                printf '%s\n' \
                    action_26_d_linux_check_fixture=true \
                    action_26_d_linux_persistent_mutation=false \
                    action_26_d_linux_rollback_acceptance=true
                exit 0
                ;;
        esac
        ;;
esac
exit 64
EOF
chmod 0755 "$regression_root/fake-wsl.exe"

if [[ "$run_windows_cases" = true ]]; then
    command -v pwsh >/dev/null || fail pwsh_required
    run_powershell_case success success
    if [[ "$(<"$regression_root/success/status")" -ne 0 ]]; then
        sed 's/^/success_stdout: /' "$regression_root/success/stdout" >&2
        sed 's/^/success_stderr: /' "$regression_root/success/stderr" >&2
        fail success_status
    fi
    [[ -f "$regression_root/success/.wslconfig" ]] || fail success_target_retained
    [[ "$(awk '$0 == "--shutdown" { count++ } END { print count + 0 }' \
        "$regression_root/success/calls")" -eq 1 ]] || fail success_shutdown_once
    grep -Fqx 'action_26_d_acceptance=true' "$regression_root/success/stdout" || fail success_marker
    grep -Fqx 'action_26_d_rollback_required=false' "$regression_root/success/stdout" || fail success_no_rollback
    ! grep -Fq 'action_26_d_rollback_started=true' "$regression_root/success/stdout" || fail success_rollback_absent

    run_powershell_case rollback rollback
    [[ "$(<"$regression_root/rollback/status")" -eq 1 ]] || fail rollback_original_failure_status
    [[ ! -e "$regression_root/rollback/.wslconfig" && ! -L "$regression_root/rollback/.wslconfig" ]] ||
        fail rollback_target_absent
    [[ "$(awk '$0 == "--shutdown" { count++ } END { print count + 0 }' \
        "$regression_root/rollback/calls")" -eq 2 ]] || fail rollback_shutdown_twice
    grep -Fqx 'action_26_d_rollback_complete=true' "$regression_root/rollback/stdout" || fail rollback_marker
    grep -Fq -- '--expect-nat' "$regression_root/rollback/calls" || fail rollback_nat_inspector

    mkdir -p "$regression_root/preflight"
    printf 'changed\n' >"$regression_root/preflight/.wslconfig"
    : >"$regression_root/preflight/calls"
    preflight_status=0
    ACTION26D_FAKE_MODE=success ACTION26D_FAKE_CALLS=$regression_root/preflight/calls \
        pwsh -NoProfile -File "$powershell_action" -AllowNonWindowsTest \
        -WslExe "$regression_root/fake-wsl.exe" -Target "$regression_root/preflight/.wslconfig" \
        >"$regression_root/preflight/stdout" 2>"$regression_root/preflight/stderr" || preflight_status=$?
    [[ "$preflight_status" -eq 1 ]] || fail preflight_status
    [[ ! -s "$regression_root/preflight/calls" ]] || fail preflight_no_shutdown
fi

mkdir -p "$regression_root/linux/bin" "$regression_root/linux/backup"
cp -- "$candidate" "$regression_root/linux/.wslconfig"
printf 'action=26c\nbaseline=absent\n' >"$regression_root/linux/backup/manifest"
cat >"$regression_root/linux/bin/wslinfo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${ACTION26D_FAKE_NETWORKING_MODE:?}"
EOF
cat >"$regression_root/linux/bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == '-6 addr show' ]]; then
    printf '2: eth0 inet6 fd36:5aa8:6971:1::100/64 scope global\n'
    exit 0
fi
if [[ "$1 $2 $3" == '-6 route get' ]]; then
    if [[ "${ACTION26D_FAKE_NETWORKING_MODE:?}" = nat ]]; then
        printf 'RTNETLINK answers: Network is unreachable\n' >&2
        exit 2
    fi
    printf '%s dev eth0 src fd36:5aa8:6971:1::100 metric 0\n' "$4"
    exit 0
fi
exit 64
EOF
cat >"$regression_root/linux/bin/dig" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' fd36:5aa8:6971:1::56
[[ "${ACTION26D_FAKE_EXTRA_DNS:-false}" = false ]] || printf '%s\n' fd36:5aa8:6971:1::99
EOF
cat >"$regression_root/linux/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' protocol=1.1 status=204 remote_ip=fd36:5aa8:6971:1::56 body_bytes=0 redirects=0
EOF
chmod 0755 "$regression_root/linux/bin/"*

env CADDY_ACTION26D_TARGET="$regression_root/linux/.wslconfig" \
    CADDY_ACTION26D_BACKUP_ROOT="$regression_root/linux/backup" \
    CADDY_ACTION26D_WSLINFO_BIN="$regression_root/linux/bin/wslinfo" \
    CADDY_ACTION26D_IP_BIN="$regression_root/linux/bin/ip" \
    CADDY_ACTION26D_DIG_BIN="$regression_root/linux/bin/dig" \
    CADDY_ACTION26D_CURL_BIN="$regression_root/linux/bin/curl" \
    ACTION26D_FAKE_NETWORKING_MODE=mirrored \
    /bin/bash "$linux_inspector" --expect-mirrored >"$regression_root/linux/mirrored.out"
grep -Fqx 'action_26_d_linux_acceptance=true' "$regression_root/linux/mirrored.out" ||
    fail linux_mirrored_marker

extra_dns_status=0
env CADDY_ACTION26D_TARGET="$regression_root/linux/.wslconfig" \
    CADDY_ACTION26D_BACKUP_ROOT="$regression_root/linux/backup" \
    CADDY_ACTION26D_WSLINFO_BIN="$regression_root/linux/bin/wslinfo" \
    CADDY_ACTION26D_IP_BIN="$regression_root/linux/bin/ip" \
    CADDY_ACTION26D_DIG_BIN="$regression_root/linux/bin/dig" \
    CADDY_ACTION26D_CURL_BIN="$regression_root/linux/bin/curl" \
    ACTION26D_FAKE_NETWORKING_MODE=mirrored ACTION26D_FAKE_EXTRA_DNS=true \
    /bin/bash "$linux_inspector" --expect-mirrored >/dev/null 2>&1 || extra_dns_status=$?
[[ "$extra_dns_status" -ne 0 ]] || fail linux_extra_dns_rejected

rm -- "$regression_root/linux/.wslconfig"
env CADDY_ACTION26D_TARGET="$regression_root/linux/.wslconfig" \
    CADDY_ACTION26D_BACKUP_ROOT="$regression_root/linux/backup" \
    CADDY_ACTION26D_WSLINFO_BIN="$regression_root/linux/bin/wslinfo" \
    CADDY_ACTION26D_IP_BIN="$regression_root/linux/bin/ip" \
    ACTION26D_FAKE_NETWORKING_MODE=nat \
    /bin/bash "$linux_inspector" --expect-nat >"$regression_root/linux/nat.out"
grep -Fqx 'action_26_d_linux_rollback_acceptance=true' "$regression_root/linux/nat.out" ||
    fail linux_nat_marker

printf 'action_26_d_regression_complete=true\n'
