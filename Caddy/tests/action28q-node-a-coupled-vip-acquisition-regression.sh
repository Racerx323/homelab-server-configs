#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_regression
readonly baseline_main_sha256=6162cfb9d83f7e524db1df6a3b041ced90a7639fceaf28eacf713270c2a66a65
readonly coupled_main_sha256=9e3dbf9760733f0ddb46ba51996cfdd9ad9af723d561ee2376de8c7c7d6ee3aa
readonly production_node_a_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly node_a_fixture_fragment_sha256=d54bab23a2fb564d25faa134f65eaa67500c717dfb77fb912fc5526f1f71169a
readonly node_b_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly node_b_baseline_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly node_b_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/acquire-node-a-coupled-vips-action28q.sh
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-node-a-coupled-vip-acquisition-action28q-outer.sh
readonly coupled_fixture=$test_directory/fixtures/action28q-node-a-coupled-main.conf
readonly node_b_fixture=$test_directory/fixtures/action28p-node-b-retired-main.conf
readonly node_a_fragment_fixture=$test_directory/fixtures/action28q-node-a-caddy-fragment.conf
readonly node_b_fragment_fixture=$test_directory/fixtures/action28q-node-b-caddy-fragment.conf
regression_root=$(mktemp -d /tmp/caddy-action28q-regression.XXXXXX)
readonly regression_root
readonly node_b_root=$regression_root/node-b
readonly node_a_root=$regression_root/node-a
readonly fake_bin=$regression_root/bin
readonly fake_ssh=$fake_bin/ssh

cleanup() {
    if [[ "${CADDY_ACTION28Q_KEEP_FIXTURE:-}" = 1 ]]; then
        printf '%s_fixture_root=%s\n' "$prefix" "$regression_root" >&2
    else
        rm -rf -- "$regression_root"
    fi
}
trap cleanup EXIT
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28q_regression_label=$1
    local action28q_regression_stdout=$regression_root/check-$1.stdout
    local action28q_regression_stderr=$regression_root/check-$1.stderr

    shift
    if "$@" >"$action28q_regression_stdout" 2>"$action28q_regression_stderr"; then
        printf '%s_check_%s=true\n' "$prefix" "$action28q_regression_label"
        return 0
    fi
    if [[ -s "$action28q_regression_stdout" ]]; then
        sed "s/^/${prefix}_failure_${action28q_regression_label}_stdout=/" \
            "$action28q_regression_stdout" >&2
    fi
    if [[ -s "$action28q_regression_stderr" ]]; then
        sed "s/^/${prefix}_failure_${action28q_regression_label}_stderr=/" \
            "$action28q_regression_stderr" >&2
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28q_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then return 1; fi
    return 0
}
render_node_b_fragment() {
    cp -- "$node_b_fragment_fixture" "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
}
render_node_a_fragment() {
    cp -- "$node_a_fragment_fixture" "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
}
prepare_node_b() {
    local action28q_regression_backup=$node_b_root/var/backups/caddy-ha/action28p-node-b-caddy-vrrp-relinquish

    install -d -m 0755 "$node_b_root/etc/keepalived/conf.d" "$node_b_root/state" \
        "$node_b_root/run" "$node_b_root/var/backups/caddy-ha"
    install -d -m 0700 "$action28q_regression_backup"
    cp -- "$node_b_fixture" "$node_b_root/etc/keepalived/keepalived.conf"
    render_node_b_fragment
    install -m 0600 "$node_b_fixture" "$action28q_regression_backup/keepalived.conf"
    printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n' \
        >>"$action28q_regression_backup/keepalived.conf"
    install -m 0600 "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28q_regression_backup/caddy-ha.conf"
    printf 'action=28p\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$node_b_baseline_sha256" "$node_b_fragment_sha256" "$node_b_main_sha256" \
        >"$action28q_regression_backup/manifest"
    chmod 0600 "$action28q_regression_backup/manifest"
    chmod 0644 "$node_b_root/etc/keepalived/keepalived.conf" \
        "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
    printf '%s\n' 'keepalived.service=active' 'lighttpd.service=active' \
        'caddy.service=active' >"$node_b_root/state/services"
    : >"$node_b_root/state/ipv4"
    : >"$node_b_root/state/ipv6"
    printf '%s\n' '/org/keepalived/Vrrp1' '/org/keepalived/Vrrp1/Instance' \
        '/org/keepalived/Vrrp1/Instance/eth0/100/IPv4' \
        '/org/keepalived/Vrrp1/Instance/eth0/101/IPv6' >"$node_b_root/state/dbus-tree"
    printf '%s\n' \
        'localhost|127.0.0.1|/|0|204' \
        'pihole00.local.theama.co|10.1.0.54|/admin/|0|200' \
        'pihole00.local.theama.co|[fd36:5aa8:6971:1::54]|/admin/|0|200' \
        >"$node_b_root/state/https"
}
prepare_node_a() {
    local action28q_regression_backup=$node_a_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration

    install -d -m 0755 "$node_a_root/etc/keepalived/conf.d" "$node_a_root/state" \
        "$node_a_root/run"
    install -d -m 0700 "$action28q_regression_backup"
    sed \
        -e '/shared Caddy VIP follows DNS ownership/d' \
        -e '/^        10[.]1[.]0[.]56\/22 dev eth0$/d' \
        -e '/^        fd36:5aa8:6971:1::56\/128 dev eth0 preferred_lft forever$/d' \
        "$coupled_fixture" >"$node_a_root/etc/keepalived/keepalived.conf"
    render_node_a_fragment
    cp -- "$node_a_root/etc/keepalived/keepalived.conf" \
        "$action28q_regression_backup/keepalived.conf"
    cp -- "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28q_regression_backup/caddy-ha.conf"
    printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$baseline_main_sha256" "$node_a_fixture_fragment_sha256" "$baseline_main_sha256" \
        >"$action28q_regression_backup/manifest"
    chmod 0644 "$node_a_root/etc/keepalived/keepalived.conf" \
        "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$action28q_regression_backup/manifest"
    printf '%s\n' 'keepalived.service=active' 'lighttpd.service=active' \
        'caddy.service=active' >"$node_a_root/state/services"
    printf '2: eth0 inet 10.1.0.55/22 scope global eth0\n' >"$node_a_root/state/ipv4"
    printf '2: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global\n' \
        >"$node_a_root/state/ipv6"
    printf '%s\n' \
        'localhost|127.0.0.1|/|0|204' \
        'pihole0.local.theama.co|10.1.0.53|/admin/|0|200' \
        'pihole0.local.theama.co|[fd36:5aa8:6971:1::53]|/admin/|0|200' \
        >"$node_a_root/state/https"
}
write_fake_commands() {
    install -d -m 0755 "$fake_bin"
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        '[[ "${1:-}" = -u ]] && { printf "0\\n"; exit 0; }' \
        'exec /usr/bin/id "$@"' >"$fake_bin/id"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "j1-svpihole0\\n"' >"$fake_bin/hostname"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/sleep"
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'args=()' \
        'while [[ $# -gt 0 ]]; do' \
        '    case "$1" in' \
        '        -o|-g) shift 2 ;;' \
        '        *) args+=("$1"); shift ;;' \
        '    esac' \
        'done' \
        'exec /usr/bin/install "${args[@]}"' >"$fake_bin/install"
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'case "${1:-}" in' \
        '    is-active) grep -Fqx "${3:-}=active" "$ACTION28Q_FIXTURE_ROOT/state/services" ;;' \
        '    reload)' \
        '        [[ "${2:-}" = keepalived.service ]]' \
        '        if grep -Fqx "        10.1.0.56/22 dev eth0" "$ACTION28Q_FIXTURE_ROOT/etc/keepalived/keepalived.conf"; then' \
        '            printf "%s\\n" "2: eth0 inet 10.1.0.55/22 scope global eth0" "2: eth0 inet 10.1.0.56/22 scope global eth0" >"$ACTION28Q_FIXTURE_ROOT/state/ipv4"' \
        '            printf "%s\\n" "2: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global" "2: eth0 inet6 fd36:5aa8:6971:1::56/128 scope global" >"$ACTION28Q_FIXTURE_ROOT/state/ipv6"' \
        '        else' \
        '            printf "2: eth0 inet 10.1.0.55/22 scope global eth0\\n" >"$ACTION28Q_FIXTURE_ROOT/state/ipv4"' \
        '            printf "2: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global\\n" >"$ACTION28Q_FIXTURE_ROOT/state/ipv6"' \
        '        fi' \
        '        ;;' \
        '    *) exit 64 ;;' \
        'esac' >"$fake_bin/systemctl"
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'case " $* " in' \
        '    *" -4 "*) cat "$ACTION28Q_FIXTURE_ROOT/state/ipv4" ;;' \
        '    *" -6 "*) cat "$ACTION28Q_FIXTURE_ROOT/state/ipv6" ;;' \
        '    *) exit 64 ;;' \
        'esac' >"$fake_bin/ip"
    printf '%s\n' '#!/usr/bin/env bash' \
        'case " $* " in' \
        '    *" --show-cursor "*) printf "%s\\n" "-- cursor: s=fixture;i=1" ;;' \
        '    *" --after-cursor "*) printf "%s\\n" "fixture keepalived reload complete" ;;' \
        'esac' >"$fake_bin/journalctl"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "%s\\n" "/org/keepalived/Vrrp1" "/org/keepalived/Vrrp1/Instance"' \
        >"$fake_bin/busctl"
    printf '%s\n' '#!/usr/bin/env bash' 'shift' 'exec "$@"' >"$fake_bin/timeout"
    # The expressions belong to the generated fixture script.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'output=/dev/null' \
        'url=' \
        'while [[ $# -gt 0 ]]; do' \
        '    case "$1" in' \
        '        --output) output=$2; shift 2 ;;' \
        '        http*) url=$1; shift ;;' \
        '        *) shift ;;' \
        '    esac' \
        'done' \
        'if [[ "$url" = "https://pihole-admin.local.theama.co/admin/login.php" ]]; then' \
        '    printf "%s\\n" "<title>Pi-hole - j1-svpihole0</title>" >"$output"' \
        'fi' \
        'printf "200"' >"$fake_bin/curl"
    chmod 0755 "$fake_bin/id" "$fake_bin/hostname" "$fake_bin/sleep" \
        "$fake_bin/install" "$fake_bin/systemctl" "$fake_bin/ip" \
        "$fake_bin/journalctl" "$fake_bin/busctl" "$fake_bin/timeout" "$fake_bin/curl"
}
run_node_b_producer() {
    (
        cd /
        CADDY_ACTION28PA_TEST_MODE=1 \
            CADDY_ACTION28PA_MAIN_SHA256=$node_b_main_sha256 \
            CADDY_ACTION28PA_FRAGMENT_SHA256=$node_b_fragment_sha256 \
            /bin/bash "$node_b_inspector" --fixture-root "$node_b_root"
    )
}
run_node_a_producer() {
    (
        cd /
        CADDY_ACTION28MB_TEST_MODE=1 \
            CADDY_ACTION28MB_RETIRED_MAIN_SHA256=$baseline_main_sha256 \
            CADDY_ACTION28MB_BASELINE_MAIN_SHA256=$baseline_main_sha256 \
            CADDY_ACTION28MB_FRAGMENT_SHA256=$node_a_fixture_fragment_sha256 \
            /bin/bash "$node_a_inspector" --fixture-root "$node_a_root"
    )
}
run_transaction_producer() {
    (
        cd /
        ACTION28Q_FIXTURE_ROOT=$node_a_root \
            CADDY_ACTION28Q_TEST_MODE=1 \
            CADDY_ACTION28Q_FRAGMENT_SHA256=$node_a_fixture_fragment_sha256 \
            CADDY_ACTION28Q_TEST_PATH="$fake_bin:/usr/bin:/bin" \
            CADDY_ACTION28Q_FIXTURE_ROOT=$node_a_root \
            /bin/bash "$transaction" --execute
    )
}
run_outer() {
    CADDY_ACTION28Q_TEST_MODE=1 CADDY_ACTION28Q_SKIP_LOCAL_GATES=true \
        CADDY_ACTION28Q_FRAGMENT_SHA256=$node_a_fixture_fragment_sha256 \
        CADDY_ACTION28Q_SSH_BIN=$fake_ssh \
        CADDY_ACTION28Q_EVIDENCE_ROOT=$regression_root/evidence \
        ACTION28Q_NODE_B_INSPECTOR_HASH="$(file_hash "$node_b_inspector")" \
        ACTION28Q_NODE_A_INSPECTOR_HASH="$(file_hash "$node_a_inspector")" \
        ACTION28Q_TRANSACTION_HASH="$(file_hash "$transaction")" \
        ACTION28Q_NODE_B_ROOT=$node_b_root ACTION28Q_NODE_A_ROOT=$node_a_root \
        ACTION28Q_FAKE_BIN=$fake_bin \
        ACTION28Q_NODE_A_MAIN_HASH=$baseline_main_sha256 \
        ACTION28Q_NODE_A_BASELINE_HASH=$baseline_main_sha256 \
        ACTION28Q_NODE_A_FRAGMENT_HASH=$node_a_fixture_fragment_sha256 \
        /bin/bash "$outer"
}
run_transcript_test() {
    CADDY_ACTION28Q_TEST_MODE=1 \
        CADDY_ACTION28Q_FRAGMENT_SHA256=$node_a_fixture_fragment_sha256 \
        /bin/bash "$outer" --transcript-test \
        "$regression_root/node-b.stdout" "$regression_root/empty" 0 \
        "$regression_root/node-a.stdout" "$regression_root/empty" 0 \
        "$1" "$regression_root/empty" 0
}

prepare_node_b
prepare_node_a
write_fake_commands
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
received=$(mktemp /tmp/caddy-action28q-received.XXXXXX)
trap 'rm -f -- "$received"' EXIT
cat >"$received"
[[ " $* " == *' cd / && sudo -n /bin/bash -s --'* ]] || exit 90
received_hash=$(sha256sum "$received" | awk '{ print $1 }')
if [[ " $* " == *' pi@10.1.0.54 '* && "$received_hash" = "$ACTION28Q_NODE_B_INSPECTOR_HASH" ]]; then
    cd /
    CADDY_ACTION28PA_TEST_MODE=1 \
        CADDY_ACTION28PA_MAIN_SHA256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148 \
        CADDY_ACTION28PA_FRAGMENT_SHA256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518 \
        /bin/bash "$received" --fixture-root "$ACTION28Q_NODE_B_ROOT"
elif [[ " $* " == *' pi@10.1.0.53 '* && "$received_hash" = "$ACTION28Q_NODE_A_INSPECTOR_HASH" ]]; then
    cd /
    CADDY_ACTION28MB_TEST_MODE=1 \
        CADDY_ACTION28MB_RETIRED_MAIN_SHA256=$ACTION28Q_NODE_A_MAIN_HASH \
        CADDY_ACTION28MB_BASELINE_MAIN_SHA256=$ACTION28Q_NODE_A_BASELINE_HASH \
        CADDY_ACTION28MB_FRAGMENT_SHA256=$ACTION28Q_NODE_A_FRAGMENT_HASH \
        /bin/bash "$received" --fixture-root "$ACTION28Q_NODE_A_ROOT"
elif [[ " $* " == *' pi@10.1.0.53 '* && " $* " == *' --execute '* && "$received_hash" = "$ACTION28Q_TRANSACTION_HASH" ]]; then
    cd /
    ACTION28Q_FIXTURE_ROOT=$ACTION28Q_NODE_A_ROOT \
        CADDY_ACTION28Q_TEST_MODE=1 \
        CADDY_ACTION28Q_FRAGMENT_SHA256=$ACTION28Q_NODE_A_FRAGMENT_HASH \
        CADDY_ACTION28Q_TEST_PATH="$ACTION28Q_FAKE_BIN:/usr/bin:/bin" \
        CADDY_ACTION28Q_FIXTURE_ROOT=$ACTION28Q_NODE_A_ROOT \
        /bin/bash "$received" --execute
elif [[ " $* " == *' pi@10.1.0.53 '* && " $* " == *' --rollback '* && "$received_hash" = "$ACTION28Q_TRANSACTION_HASH" ]]; then
    cd /
    ACTION28Q_FIXTURE_ROOT=$ACTION28Q_NODE_A_ROOT \
        CADDY_ACTION28Q_TEST_MODE=1 \
        CADDY_ACTION28Q_FRAGMENT_SHA256=$ACTION28Q_NODE_A_FRAGMENT_HASH \
        CADDY_ACTION28Q_TEST_PATH="$ACTION28Q_FAKE_BIN:/usr/bin:/bin" \
        CADDY_ACTION28Q_FIXTURE_ROOT=$ACTION28Q_NODE_A_ROOT \
        /bin/bash "$received" --rollback
else
    exit 91
fi
FAKE_SSH
chmod 0755 "$fake_ssh"

record_check baseline_main_hash_exact test \
    "$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")" = "$baseline_main_sha256"
record_check coupled_fixture_hash_exact test \
    "$(file_hash "$coupled_fixture")" = "$coupled_main_sha256"
record_check node_a_fragment_hash_exact test \
    "$(file_hash "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf")" = "$node_a_fixture_fragment_sha256"
record_check production_fragment_pin_present grep -Fq \
    "fragment_sha256=$production_node_a_fragment_sha256" "$transaction"
record_check node_b_main_hash_exact test \
    "$(file_hash "$node_b_root/etc/keepalived/keepalived.conf")" = "$node_b_main_sha256"
record_check node_b_fragment_hash_exact test \
    "$(file_hash "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf")" = "$node_b_fragment_sha256"
record_check node_b_real_producer run_node_b_producer
record_check node_a_real_producer run_node_a_producer
run_node_b_producer >"$regression_root/node-b.stdout"
run_node_a_producer >"$regression_root/node-a.stdout"
install -m 0600 /dev/null "$regression_root/empty"
record_check outer_real_producer_path run_outer
record_check coupled_main_installed test \
    "$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")" = "$coupled_main_sha256"
record_check action_28q_backup_manifest grep -Fqx 'action=28q' \
    "$node_a_root/var/backups/caddy-ha/action28q-node-a-coupled-vip-acquisition/manifest"
record_check dns_ipv4_retained grep -Fq '10.1.0.55/22' "$node_a_root/state/ipv4"
record_check dns_ipv6_retained grep -Fq 'fd36:5aa8:6971:1::55/128' "$node_a_root/state/ipv6"
record_check caddy_ipv4_acquired grep -Fq '10.1.0.56/22' "$node_a_root/state/ipv4"
record_check caddy_ipv6_acquired grep -Fq 'fd36:5aa8:6971:1::56/128' "$node_a_root/state/ipv6"
record_check node_b_ipv4_unchanged test ! -s "$node_b_root/state/ipv4"
record_check node_b_ipv6_unchanged test ! -s "$node_b_root/state/ipv6"
cp -- "$regression_root/evidence"/run.*/node_a_transaction.stdout \
    "$regression_root/transaction.stdout"
record_check transcript_valid run_transcript_test "$regression_root/transaction.stdout"
cp -- "$regression_root/transaction.stdout" "$regression_root/altered.stdout"
sed -i '/action_28q_check_caddy_ipv4_owned_after=true/d' "$regression_root/altered.stdout"
record_check missing_label_rejected command_rejected run_transcript_test "$regression_root/altered.stdout"
cp -- "$regression_root/transaction.stdout" "$regression_root/altered.stdout"
sed -i 's/action_28q_check_caddy_ipv4_owned_after=true/action_28q_check_caddy_ipv4_owned_after=false/' \
    "$regression_root/altered.stdout"
record_check false_label_rejected command_rejected run_transcript_test "$regression_root/altered.stdout"
cp -- "$regression_root/transaction.stdout" "$regression_root/altered.stdout"
printf 'action_28q_check_unexpected=true\n' >>"$regression_root/altered.stdout"
record_check extra_label_rejected command_rejected run_transcript_test "$regression_root/altered.stdout"
cp -- "$regression_root/transaction.stdout" "$regression_root/altered.stdout"
sed -i '/action_28q_check_caddy_ipv4_owned_after=true/{h;d};/action_28q_check_caddy_ipv6_owned_after=true/{p;x}' \
    "$regression_root/altered.stdout"
record_check reordered_label_rejected command_rejected run_transcript_test "$regression_root/altered.stdout"
record_check malformed_execute_transport_rejected command_rejected grep -Fq \
    "'cd / && sudo -n /bin/bash -s/ -- --execute'" "$outer"
record_check exact_execute_transport grep -Fq \
    "'cd / && sudo -n /bin/bash -s -- --execute'" "$outer"
record_check candidate_production_boundary "$transaction" --candidate-test \
    "$node_a_root/var/backups/caddy-ha/action28q-node-a-coupled-vip-acquisition/keepalived.conf" \
    "$coupled_fixture"
printf '%s_complete=true\n' "$prefix"
