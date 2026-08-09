#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_b_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-wsl-ipv6-provenance-action26-b.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-ipv6-provenance-action26-b-outer.sh

record_check() {
    local action26b_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action26b_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action26b_regression_label" >&2
    return 1
}
expect_rejected() {
    local action26b_regression_transcript=$1
    local action26b_regression_stderr=$2

    ! /bin/bash "$outer" --validate-transcript "$action26b_regression_transcript" 0 \
        "$action26b_regression_stderr" >/dev/null 2>&1
}
run_fixture() {
    local action26b_regression_name=$1
    shift

    printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 test\n' \
        >"$action26b_regression_root/${action26b_regression_name}.proc-version"
    : >"$action26b_regression_root/${action26b_regression_name}.if-inet6"
    printf '[boot]\nsystemd=true\n' >"$action26b_regression_root/${action26b_regression_name}.wsl.conf"
    printf 'nameserver 10.255.255.254\n' \
        >"$action26b_regression_root/${action26b_regression_name}.resolv.conf"
    : >"$action26b_regression_root/${action26b_regression_name}.ip.args"
    : >"$action26b_regression_root/${action26b_regression_name}.sysctl.args"
    env "$@" \
        CADDY_ACTION26B_IP_BIN="$action26b_regression_root/fake-ip" \
        CADDY_ACTION26B_UNAME_BIN="$action26b_regression_root/fake-uname" \
        CADDY_ACTION26B_SYSCTL_BIN="$action26b_regression_root/fake-sysctl" \
        CADDY_ACTION26B_WSLINFO_BIN="$action26b_regression_root/fake-wslinfo" \
        CADDY_ACTION26B_PROC_VERSION_PATH="$action26b_regression_root/${action26b_regression_name}.proc-version" \
        CADDY_ACTION26B_IF_INET6_PATH="$action26b_regression_root/${action26b_regression_name}.if-inet6" \
        CADDY_ACTION26B_WSL_CONF_PATH="$action26b_regression_root/${action26b_regression_name}.wsl.conf" \
        CADDY_ACTION26B_RESOLV_CONF_PATH="$action26b_regression_root/${action26b_regression_name}.resolv.conf" \
        CADDY_ACTION26B_IP_LOG="$action26b_regression_root/${action26b_regression_name}.ip.args" \
        CADDY_ACTION26B_SYSCTL_LOG="$action26b_regression_root/${action26b_regression_name}.sysctl.args" \
        /bin/bash "$core" >"$action26b_regression_root/${action26b_regression_name}.stdout" \
        2>"$action26b_regression_root/${action26b_regression_name}.stderr"
}

action26b_regression_root=$(mktemp -d /tmp/caddy-action26-b-regression.XXXXXX)
readonly action26b_regression_root
trap 'rm -rf -- "$action26b_regression_root"' EXIT INT TERM

cat >"$action26b_regression_root/fake-ip" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26B_IP_LOG:?}"
case "$*" in
    '-4 route get 10.1.0.1')
        printf '10.1.0.1 via 172.20.0.1 dev eth0 src 172.20.0.2\n'
        ;;
    '-6 addr show')
        printf '1: lo: <LOOPBACK>\n    inet6 ::1/128 scope host\n'
        ;;
    '-6 route show table all')
        printf 'local ::1 dev lo table local\n'
        ;;
    '-6 rule show')
        printf '0: from all lookup local\n32766: from all lookup main\n'
        ;;
    '-6 route get fd36:5aa8:6971:1::56')
        if [[ "${CADDY_ACTION26B_FAKE_ROUTE_PRESENT:-false}" = true ]]; then
            printf 'fd36:5aa8:6971:1::56 dev eth0 src fd36:5aa8:6971:1::100\n'
        else
            printf 'RTNETLINK answers: Network is unreachable\n' >&2
            exit 2
        fi
        ;;
    *) exit 64 ;;
esac
EOF
chmod 0700 "$action26b_regression_root/fake-ip"

cat >"$action26b_regression_root/fake-uname" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'Linux test 6.6.87.2-microsoft-standard-WSL2 x86_64 GNU/Linux\n'
EOF
chmod 0700 "$action26b_regression_root/fake-uname"

cat >"$action26b_regression_root/fake-sysctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26B_SYSCTL_LOG:?}"
case "${2:-}" in
    net.ipv6.conf.all.disable_ipv6 | net.ipv6.conf.eth0.disable_ipv6)
        if [[ "${CADDY_ACTION26B_FAKE_IPV6_DISABLED:-false}" = true ]]; then
            printf '1\n'
        else
            printf '0\n'
        fi
        ;;
    net.ipv6.conf.eth0.accept_ra) printf '1\n' ;;
    net.ipv6.conf.all.forwarding) printf '0\n' ;;
    *) exit 64 ;;
esac
EOF
chmod 0700 "$action26b_regression_root/fake-sysctl"

cat >"$action26b_regression_root/fake-wslinfo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${CADDY_ACTION26B_FAKE_NETWORKING_MODE:-nat}"
EOF
chmod 0700 "$action26b_regression_root/fake-wslinfo"

run_fixture nat
record_check nat_stderr_empty test ! -s "$action26b_regression_root/nat.stderr"
record_check nat_classification grep -Fqx \
    'action_26_b_observed_classification=wsl_nat_no_ula_route' \
    "$action26b_regression_root/nat.stdout"
record_check nat_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26b_regression_root/nat.stdout" 0 "$action26b_regression_root/nat.stderr"
printf '%s_observed_ip_invocation_count=%s\n' "$prefix" \
    "$(wc -l <"$action26b_regression_root/nat.ip.args")"
printf '%s_observed_sysctl_invocation_count=%s\n' "$prefix" \
    "$(wc -l <"$action26b_regression_root/nat.sysctl.args")"
record_check ip_invocation_count test "$(wc -l <"$action26b_regression_root/nat.ip.args")" -eq 5
record_check sysctl_invocation_count test \
    "$(wc -l <"$action26b_regression_root/nat.sysctl.args")" -eq 4
record_check route_lookup_exact grep -Fqx -- '-6 route get fd36:5aa8:6971:1::56' \
    "$action26b_regression_root/nat.ip.args"
record_check sysctl_read_only test \
    "$(grep -Evc '^-n net[.]ipv6[.]conf[.][a-zA-Z0-9_.:-]+[.](disable_ipv6|accept_ra|forwarding)$' \
        "$action26b_regression_root/nat.sysctl.args" || true)" -eq 0

run_fixture mirrored CADDY_ACTION26B_FAKE_NETWORKING_MODE=mirrored
record_check mirrored_classification grep -Fqx \
    'action_26_b_observed_classification=wsl_mirrored_no_ula_route' \
    "$action26b_regression_root/mirrored.stdout"
record_check mirrored_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26b_regression_root/mirrored.stdout" 0 "$action26b_regression_root/mirrored.stderr"

run_fixture disabled CADDY_ACTION26B_FAKE_IPV6_DISABLED=true
record_check disabled_classification grep -Fqx \
    'action_26_b_observed_classification=ipv6_disabled' \
    "$action26b_regression_root/disabled.stdout"
record_check disabled_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26b_regression_root/disabled.stdout" 0 "$action26b_regression_root/disabled.stderr"

run_fixture route-present CADDY_ACTION26B_FAKE_ROUTE_PRESENT=true
record_check route_present_classification grep -Fqx \
    'action_26_b_observed_classification=ula_route_present' \
    "$action26b_regression_root/route-present.stdout"
record_check route_present_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26b_regression_root/route-present.stdout" 0 \
    "$action26b_regression_root/route-present.stderr"

run_fixture unknown CADDY_ACTION26B_FAKE_NETWORKING_MODE=unavailable
record_check unknown_mode_classification grep -Fqx \
    'action_26_b_observed_classification=wsl_unknown_mode_no_ula_route' \
    "$action26b_regression_root/unknown.stdout"
record_check unknown_mode_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26b_regression_root/unknown.stdout" 0 "$action26b_regression_root/unknown.stderr"

: >"$action26b_regression_root/empty.stderr"
sed '/action_26_b_check_accepted_action26a_outer_hash=true/d' \
    "$action26b_regression_root/nat.stdout" >"$action26b_regression_root/missing"
record_check missing_check_rejected expect_rejected "$action26b_regression_root/missing" \
    "$action26b_regression_root/empty.stderr"
sed 's/action_26_b_check_accepted_action26a_outer_hash=true/action_26_b_check_accepted_action26a_outer_hash=false/' \
    "$action26b_regression_root/nat.stdout" >"$action26b_regression_root/false"
record_check false_check_rejected expect_rejected "$action26b_regression_root/false" \
    "$action26b_regression_root/empty.stderr"
cp "$action26b_regression_root/nat.stdout" "$action26b_regression_root/duplicate"
grep -F 'action_26_b_check_accepted_action26a_outer_hash=true' \
    "$action26b_regression_root/nat.stdout" >>"$action26b_regression_root/duplicate"
record_check duplicate_check_rejected expect_rejected "$action26b_regression_root/duplicate" \
    "$action26b_regression_root/empty.stderr"
sed 's/action_26_b_observed_classification=wsl_nat_no_ula_route/action_26_b_observed_classification=unknown/' \
    "$action26b_regression_root/nat.stdout" >"$action26b_regression_root/bad-classification"
record_check bad_classification_rejected expect_rejected \
    "$action26b_regression_root/bad-classification" "$action26b_regression_root/empty.stderr"
printf 'bounded stderr\n' >"$action26b_regression_root/nonempty.stderr"
record_check stderr_rejected expect_rejected "$action26b_regression_root/nat.stdout" \
    "$action26b_regression_root/nonempty.stderr"
if /bin/bash "$outer" --validate-transcript "$action26b_regression_root/nat.stdout" 1 \
    "$action26b_regression_root/empty.stderr" >/dev/null 2>&1; then
    printf '%s_nonzero_status_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_nonzero_status_rejected=true\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
