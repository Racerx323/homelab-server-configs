#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_c_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/install-workstation-wsl-mirrored-action26-c.sh

record_check() {
    local action26c_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action26c_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action26c_regression_label" >&2
    return 1
}
run_fixture() {
    local action26c_regression_name=$1
    shift
    local action26c_regression_fixture=$action26c_regression_root/$action26c_regression_name

    install -d -m 0700 "$action26c_regression_fixture/windows"
    printf 'Linux version test-microsoft-standard-WSL2\n' >"$action26c_regression_fixture/proc-version"
    env "$@" \
        CADDY_ACTION26C_TARGET="$action26c_regression_fixture/windows/.wslconfig" \
        CADDY_ACTION26C_BACKUP_ROOT="$action26c_regression_fixture/backup" \
        CADDY_ACTION26C_PROC_VERSION_PATH="$action26c_regression_fixture/proc-version" \
        CADDY_ACTION26C_WSLINFO_BIN="$action26c_regression_root/fake-wslinfo" \
        /bin/bash "$core" >"$action26c_regression_fixture/stdout" \
        2>"$action26c_regression_fixture/stderr"
}

action26c_regression_root=$(mktemp -d /tmp/caddy-action26-c-regression.XXXXXX)
readonly action26c_regression_root
trap 'rm -rf -- "$action26c_regression_root"' EXIT INT TERM

cat >"$action26c_regression_root/fake-wslinfo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
test "${1:-}" = --networking-mode
printf '%s\n' "${CADDY_ACTION26C_FAKE_MODE:-nat}"
EOF
chmod 0700 "$action26c_regression_root/fake-wslinfo"

run_fixture success
record_check success_stderr_empty test ! -s "$action26c_regression_root/success/stderr"
record_check target_exact cmp -s "$caddy_root/configs/wsl/.wslconfig" \
    "$action26c_regression_root/success/windows/.wslconfig"
record_check backup_mode test "$(stat -c %a "$action26c_regression_root/success/backup")" = 700
record_check manifest_mode test \
    "$(stat -c %a "$action26c_regression_root/success/backup/manifest")" = 600
record_check manifest_absent_baseline grep -Fqx 'baseline=absent' \
    "$action26c_regression_root/success/backup/manifest"
record_check acceptance grep -Fqx 'action_26_c_acceptance=true' \
    "$action26c_regression_root/success/stdout"
record_check activation_pending grep -Fqx 'action_26_c_activation_pending=true' \
    "$action26c_regression_root/success/stdout"
record_check shutdown_false grep -Fqx 'action_26_c_wsl_shutdown=false' \
    "$action26c_regression_root/success/stdout"
record_check dns_mutation_false grep -Fqx 'action_26_c_dns_mutation=false' \
    "$action26c_regression_root/success/stdout"
record_check node_contact_false grep -Fqx 'action_26_c_node_contact=false' \
    "$action26c_regression_root/success/stdout"

if run_fixture rollback CADDY_ACTION26C_FORCE_POSTINSTALL_FAILURE=true; then
    printf '%s_forced_failure_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_forced_failure_rejected=true\n' "$prefix"
record_check rollback_target_absent test ! -e \
    "$action26c_regression_root/rollback/windows/.wslconfig"
record_check rollback_complete grep -Fqx 'action_26_c_rollback_complete=true' \
    "$action26c_regression_root/rollback/stderr"
record_check rollback_backup_retained test -f "$action26c_regression_root/rollback/backup/manifest"

if run_fixture non-nat CADDY_ACTION26C_FAKE_MODE=mirrored; then
    printf '%s_non_nat_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_non_nat_rejected=true\n' "$prefix"
record_check non_nat_unmodified test ! -e "$action26c_regression_root/non-nat/windows/.wslconfig"

install -d -m 0700 "$action26c_regression_root/existing/windows"
printf '[wsl2]\nmemory=8GB\n' >"$action26c_regression_root/existing/windows/.wslconfig"
if run_fixture existing; then
    printf '%s_existing_target_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_existing_target_rejected=true\n' "$prefix"
record_check existing_target_preserved grep -Fqx 'memory=8GB' \
    "$action26c_regression_root/existing/windows/.wslconfig"

record_check no_shutdown_command test \
    "$(grep -Eci 'wsl(\.exe)?[[:space:]]+--shutdown' "$core" || true)" -eq 0
record_check no_dns_edit test \
    "$(grep -Eci 'resolv[.]conf|dnsTunneling|dnsProxy' "$core" || true)" -eq 0
record_check no_node_transport test \
    "$(grep -Eci '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$core" || true)" -eq 0
printf '%s_complete=true\n' "$prefix"
