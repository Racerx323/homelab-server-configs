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
readonly adapter=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-retry.sh
readonly validator=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-outer.sh
regression_root=

fail() {
    printf 'action_26_e_retry_regression_failure=%s\n' "$1" >&2
    return 1
}
cleanup() {
    local action26e_retry_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26e_retry_regression_status"
}
run_adapter() {
    local action26e_retry_run_status=0

    env CADDY_ACTION26D_TARGET="$regression_root/.wslconfig" \
        CADDY_ACTION26D_BACKUP_ROOT="$regression_root/backup" \
        CADDY_ACTION26D_WSLINFO_BIN="$regression_root/bin/wslinfo" \
        CADDY_ACTION26D_IP_BIN="$regression_root/bin/ip" \
        CADDY_ACTION26D_DIG_BIN="$regression_root/bin/dig" \
        CADDY_ACTION26D_CURL_BIN="$regression_root/bin/curl" \
        /bin/bash "$adapter" >"$regression_root/adapter.stdout" \
        2>"$regression_root/adapter.stderr" || action26e_retry_run_status=$?
    printf '%s\n' "$action26e_retry_run_status" >"$regression_root/adapter.status"
}

regression_root=$(mktemp -d /tmp/caddy-action26-e-retry-regression.XXXXXX)
trap cleanup EXIT INT TERM
mkdir -p "$regression_root/bin" "$regression_root/backup"
printf '[wsl2]\r\nnetworkingMode=Mirrored\r\ndnsProxy=false\r\n\r\n[experimental]\r\nhostAddressLoopback=true\r\nbestEffortDnsParsing=true' \
    >"$regression_root/.wslconfig"
printf 'action=26c\nbaseline=absent\n' >"$regression_root/backup/manifest"
cat >"$regression_root/bin/wslinfo" <<'EOF'
#!/usr/bin/env bash
printf 'mirrored\n'
EOF
cat >"$regression_root/bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == '-6 addr show' ]]; then
    printf '3: eth1 inet6 fd36:5aa8:6971:1::100/64 scope global\n'
    exit 0
fi
if [[ "$1 $2 $3" == '-6 route get' ]]; then
    printf '%s from :: dev eth1 src fd36:5aa8:6971:1::100 metric 31\n' "$4"
    exit 0
fi
exit 64
EOF
cat >"$regression_root/bin/dig" <<'EOF'
#!/usr/bin/env bash
printf 'fd36:5aa8:6971:1::56\n'
EOF
cat >"$regression_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' protocol=1.1 status=204 remote_ip=fd36:5aa8:6971:1::56 body_bytes=0 redirects=0
EOF
chmod 0755 "$regression_root/bin/"*

run_adapter
[[ "$(<"$regression_root/adapter.status")" -eq 0 ]] || fail production_status
[[ ! -s "$regression_root/adapter.stderr" ]] || fail production_stderr
/bin/bash "$validator" --validate-transcript "$regression_root/adapter.stdout" 0 \
    "$regression_root/adapter.stderr" >/dev/null || fail production_core_transcript

expected_adapter=$(/bin/bash "$adapter" --expected-checks)
actual_adapter=$(sed -n 's/^action_26_e_retry_adapter_check_\([^=]*\)=true$/\1/p' \
    "$regression_root/adapter.stdout")
[[ "$actual_adapter" = "$expected_adapter" ]] || fail production_adapter_transcript

printf '[wsl2]\nnetworkingMode=mirrored\n' >"$regression_root/.wslconfig"
run_adapter
[[ "$(<"$regression_root/adapter.status")" -ne 0 ]] || fail rejected_old_candidate
grep -Fqx 'action_26_d_linux_check_target_hash=false' "$regression_root/adapter.stderr" ||
    fail rejected_old_candidate_label

printf '[wsl2]\r\nnetworkingMode=Mirrored\r\ndnsProxy=false\r\n\r\n[experimental]\r\nhostAddressLoopback=true\r\nbestEffortDnsParsing=false' \
    >"$regression_root/.wslconfig"
run_adapter
[[ "$(<"$regression_root/adapter.status")" -ne 0 ]] || fail rejected_altered_setting

printf 'action_26_e_retry_regression_complete=true\n'
