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
readonly core=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-outer.sh
readonly candidate=$caddy_root/configs/wsl/.wslconfig
regression_root=

fail() {
    printf 'action_26_e_regression_failure=%s\n' "$1" >&2
    return 1
}
cleanup() {
    local action26e_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26e_regression_status"
}
run_core() {
    local action26e_core_status=0

    env CADDY_ACTION26D_TARGET="$regression_root/.wslconfig" \
        CADDY_ACTION26D_BACKUP_ROOT="$regression_root/backup" \
        CADDY_ACTION26D_WSLINFO_BIN="$regression_root/bin/wslinfo" \
        CADDY_ACTION26D_IP_BIN="$regression_root/bin/ip" \
        CADDY_ACTION26D_DIG_BIN="$regression_root/bin/dig" \
        CADDY_ACTION26D_CURL_BIN="$regression_root/bin/curl" \
        /bin/bash "$core" --expect-mirrored >"$regression_root/core.stdout" \
        2>"$regression_root/core.stderr" || action26e_core_status=$?
    printf '%s\n' "$action26e_core_status" >"$regression_root/core.status"
}
expect_rejected() {
    local action26e_case_label=$1
    local action26e_case_stdout=$2
    local action26e_case_status=${3:-0}
    local action26e_case_stderr=${4:-$regression_root/empty.stderr}
    local action26e_validator_status=0

    /bin/bash "$outer" --validate-transcript "$action26e_case_stdout" \
        "$action26e_case_status" "$action26e_case_stderr" >/dev/null 2>&1 || action26e_validator_status=$?
    [[ "$action26e_validator_status" -ne 0 ]] || fail "$action26e_case_label"
}

regression_root=$(mktemp -d /tmp/caddy-action26-e-regression.XXXXXX)
trap cleanup EXIT INT TERM
mkdir -p "$regression_root/bin" "$regression_root/backup"
cp -- "$candidate" "$regression_root/.wslconfig"
printf 'action=26c\nbaseline=absent\n' >"$regression_root/backup/manifest"
: >"$regression_root/empty.stderr"
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

run_core
[[ "$(<"$regression_root/core.status")" -eq 0 ]] || fail production_status
[[ ! -s "$regression_root/core.stderr" ]] || fail production_stderr
/bin/bash "$outer" --validate-transcript "$regression_root/core.stdout" 0 \
    "$regression_root/core.stderr" >/dev/null || fail production_transcript

sed '/action_26_d_linux_check_dns_answer_exact=true/d' "$regression_root/core.stdout" \
    >"$regression_root/missing.stdout"
expect_rejected missing_check "$regression_root/missing.stdout"
sed 's/action_26_d_linux_check_dns_answer_exact=true/action_26_d_linux_check_dns_answer_exact=false/' \
    "$regression_root/core.stdout" >"$regression_root/false.stdout"
expect_rejected false_check "$regression_root/false.stdout"
cp -- "$regression_root/core.stdout" "$regression_root/duplicate.stdout"
printf 'action_26_d_linux_check_dns_answer_exact=true\n' >>"$regression_root/duplicate.stdout"
expect_rejected duplicate_check "$regression_root/duplicate.stdout"
awk '
    /action_26_d_linux_check_node_a_route_status_zero=true/ { held=$0; next }
    /action_26_d_linux_check_node_a_route_source_ula=true/ { print; print held; next }
    { print }
' "$regression_root/core.stdout" >"$regression_root/reordered.stdout"
expect_rejected reordered_checks "$regression_root/reordered.stdout"
sed 's/action_26_d_linux_observed_networking_mode=mirrored/action_26_d_linux_observed_networking_mode=nat/' \
    "$regression_root/core.stdout" >"$regression_root/nat.stdout"
expect_rejected wrong_mode "$regression_root/nat.stdout"
expect_rejected nonzero_status "$regression_root/core.stdout" 1
printf 'unexpected stderr\n' >"$regression_root/nonempty.stderr"
expect_rejected nonempty_stderr "$regression_root/core.stdout" 0 "$regression_root/nonempty.stderr"

printf 'action_26_e_regression_complete=true\n'
