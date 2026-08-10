#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28p_a_regression
readonly baseline_main_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly retired_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-relinquish-post-action28p-a-outer.sh
readonly retired_fixture=$test_directory/fixtures/action28p-node-b-retired-main.conf
readonly template=$caddy_root/templates/keepalived-caddy-ha.conf.in
fixture_root=$(mktemp -d /tmp/caddy-action28p-a-regression.XXXXXX)
readonly fixture_root
readonly node_b_root=$fixture_root/node-b
readonly node_a_root=$fixture_root/node-a
readonly fake_ssh=$fixture_root/ssh

cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28pa_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28pa_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28pa_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then return 1; fi
    return 0
}
render_node_b_fragment() {
    sed \
        -e 's/@NETWORK_INTERFACE@/eth0/g' \
        -e 's/@NODE_IPV4@/10.1.0.54/g' \
        -e 's#@NODE_IPV6@#fd36:5aa8:6971:1::54#g' \
        -e 's/@PEER_IPV4@/10.1.0.53/g' \
        -e 's#@PEER_IPV6@#fd36:5aa8:6971:1::53#g' \
        -e 's/@CADDY_PRIORITY@/100/g' \
        -e 's/user keepalived_script$/user keepalived_script caddy-tls/' \
        "$template" >"$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
}
prepare_node_b() {
    local action28pa_regression_backup=$node_b_root/var/backups/caddy-ha/action28p-node-b-caddy-vrrp-relinquish

    install -d -m 0755 "$node_b_root/etc/keepalived/conf.d" "$node_b_root/state" \
        "$node_b_root/run"
    install -d -m 0700 "$action28pa_regression_backup"
    cp -- "$retired_fixture" "$node_b_root/etc/keepalived/keepalived.conf"
    render_node_b_fragment
    cp -- "$retired_fixture" "$action28pa_regression_backup/keepalived.conf"
    printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n' \
        >>"$action28pa_regression_backup/keepalived.conf"
    cp -- "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28pa_regression_backup/caddy-ha.conf"
    printf 'action=28p\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$baseline_main_sha256" "$fragment_sha256" "$retired_main_sha256" \
        >"$action28pa_regression_backup/manifest"
    chmod 0644 "$node_b_root/etc/keepalived/keepalived.conf" \
        "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$action28pa_regression_backup/keepalived.conf" \
        "$action28pa_regression_backup/caddy-ha.conf" "$action28pa_regression_backup/manifest"
    printf '%s\n' 'keepalived.service=active' 'lighttpd.service=active' \
        'caddy.service=active' >"$node_b_root/state/services"
    : >"$node_b_root/state/ipv4"
    : >"$node_b_root/state/ipv6"
    printf '%s\n' \
        'localhost|127.0.0.1|/|0|204' \
        'pihole00.local.theama.co|10.1.0.54|/admin/|0|200' \
        'pihole00.local.theama.co|[fd36:5aa8:6971:1::54]|/admin/|0|200' \
        >"$node_b_root/state/https"
    printf '%s\n' \
        '/org/keepalived/Vrrp1/Instance/eth0/100/IPv4' \
        '/org/keepalived/Vrrp1/Instance/eth0/101/IPv6' \
        >"$node_b_root/state/dbus-tree"
}
prepare_node_a() {
    local action28pa_regression_backup=$node_a_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration

    install -d -m 0755 "$node_a_root/etc/keepalived/conf.d" "$node_a_root/state" \
        "$node_a_root/run"
    install -d -m 0700 "$action28pa_regression_backup"
    printf '%s\n' 'global_defs {' '    router_id PIHOLE0' '}' \
        >"$node_a_root/etc/keepalived/keepalived.conf"
    printf '%s\n' 'vrrp_instance CADDY_IPV4 {' '}' \
        >"$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    cp -- "$node_a_root/etc/keepalived/keepalived.conf" \
        "$action28pa_regression_backup/keepalived.conf"
    cp -- "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28pa_regression_backup/caddy-ha.conf"
    node_a_main_sha256=$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")
    node_a_baseline_sha256=$(file_hash "$action28pa_regression_backup/keepalived.conf")
    node_a_fragment_sha256=$(file_hash "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf")
    readonly node_a_main_sha256 node_a_baseline_sha256 node_a_fragment_sha256
    printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$node_a_baseline_sha256" "$node_a_fragment_sha256" "$node_a_main_sha256" \
        >"$action28pa_regression_backup/manifest"
    chmod 0644 "$node_a_root/etc/keepalived/keepalived.conf" \
        "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$action28pa_regression_backup/manifest"
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
run_node_b_producer() {
    local action28pa_regression_root=$1

    (
        cd /
        CADDY_ACTION28PA_TEST_MODE=1 \
            CADDY_ACTION28PA_MAIN_SHA256="$retired_main_sha256" \
            CADDY_ACTION28PA_FRAGMENT_SHA256="$fragment_sha256" \
            /bin/bash "$node_b_inspector" --fixture-root "$action28pa_regression_root"
    )
}
run_node_a_producer() {
    (
        cd /
        CADDY_ACTION28MB_TEST_MODE=1 \
            CADDY_ACTION28MB_RETIRED_MAIN_SHA256="$node_a_main_sha256" \
            CADDY_ACTION28MB_BASELINE_MAIN_SHA256="$node_a_baseline_sha256" \
            CADDY_ACTION28MB_FRAGMENT_SHA256="$node_a_fragment_sha256" \
            /bin/bash "$node_a_inspector" --fixture-root "$node_a_root"
    )
}
run_negative_fixture() {
    local action28pa_regression_mode=$1
    local action28pa_regression_case

    action28pa_regression_case=$(mktemp -d "$fixture_root/case.XXXXXX")
    cp -a -- "$node_b_root/." "$action28pa_regression_case/"
    case "$action28pa_regression_mode" in
        main_drift) printf '# drift\n' >>"$action28pa_regression_case/etc/keepalived/keepalived.conf" ;;
        caddy_inactive)
            sed -i 's/caddy[.]service=active/caddy.service=inactive/' \
                "$action28pa_regression_case/state/services"
            ;;
        dns_vip_present)
            printf '2: eth0 inet 10.1.0.55/22 scope global eth0\n' \
                >>"$action28pa_regression_case/state/ipv4"
            ;;
        caddy_vip_present)
            printf '2: eth0 inet 10.1.0.56/22 scope global eth0\n' \
                >>"$action28pa_regression_case/state/ipv4"
            ;;
        missing_ipv6_query) rm -f -- "$action28pa_regression_case/state/ipv6" ;;
        https_failure)
            sed -i 's/localhost|127[.]0[.]0[.]1|\/|0|204/localhost|127.0.0.1|\/|28|000/' \
                "$action28pa_regression_case/state/https"
            ;;
        dbus_caddy_object)
            printf '%s\n' '/org/keepalived/Vrrp1/Instance/eth0/110/IPv4' \
                >>"$action28pa_regression_case/state/dbus-tree"
            ;;
        backup_drift)
            printf '# drift\n' \
                >>"$action28pa_regression_case/var/backups/caddy-ha/action28p-node-b-caddy-vrrp-relinquish/manifest"
            ;;
        residue) touch "$action28pa_regression_case/run/caddy-action28p-stale" ;;
        *) return 1 ;;
    esac
    command_rejected run_node_b_producer "$action28pa_regression_case"
}

prepare_node_b
prepare_node_a
run_node_b_producer "$node_b_root" >"$fixture_root/node-b.stdout"
run_node_a_producer >"$fixture_root/node-a.stdout"
install -m 0600 /dev/null "$fixture_root/node-b.stderr"
install -m 0600 /dev/null "$fixture_root/node-a.stderr"

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
received=$(mktemp /tmp/caddy-action28p-a-received.XXXXXX)
readonly received
trap 'rm -f -- "$received"' EXIT
cat >"$received"
[[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]] || exit 90
if [[ " $* " == *' pi@10.1.0.54 '* ]]; then
    [[ " $* " == *' HostKeyAlias=pihole00.local.theama.co '* ]] || exit 91
    [[ "$(sha256sum "$received" | awk '{ print $1 }')" = "$ACTION28PA_NODE_B_SOURCE_HASH" ]] || exit 92
    cat "$ACTION28PA_NODE_B_TRANSCRIPT"
elif [[ " $* " == *' pi@10.1.0.53 '* ]]; then
    [[ " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]] || exit 93
    [[ "$(sha256sum "$received" | awk '{ print $1 }')" = "$ACTION28PA_NODE_A_SOURCE_HASH" ]] || exit 94
    cat "$ACTION28PA_NODE_A_TRANSCRIPT"
else
    exit 95
fi
FAKE_SSH
chmod 0755 "$fake_ssh"

record_check node_b_real_producer_success run_node_b_producer "$node_b_root"
record_check node_a_real_producer_success run_node_a_producer
for action28pa_regression_case in main_drift caddy_inactive dns_vip_present \
    caddy_vip_present missing_ipv6_query https_failure dbus_caddy_object backup_drift residue; do
    record_check "${action28pa_regression_case}_rejected" \
        run_negative_fixture "$action28pa_regression_case"
done

run_outer() {
    CADDY_ACTION28PA_TEST_MODE=1 CADDY_ACTION28PA_SKIP_LOCAL_GATES=true \
        CADDY_ACTION28PA_SSH_BIN="$fake_ssh" \
        CADDY_ACTION28PA_EVIDENCE_ROOT="$fixture_root/evidence" \
        ACTION28PA_NODE_B_SOURCE_HASH="$(file_hash "$node_b_inspector")" \
        ACTION28PA_NODE_A_SOURCE_HASH="$(file_hash "$node_a_inspector")" \
        ACTION28PA_NODE_B_TRANSCRIPT="$fixture_root/node-b.stdout" \
        ACTION28PA_NODE_A_TRANSCRIPT="$fixture_root/node-a.stdout" \
        /bin/bash "$outer"
}
record_check outer_actual_producer_success run_outer

transcript_rejected() {
    CADDY_ACTION28PA_TEST_MODE=1 /bin/bash "$outer" --transcript-test \
        "$fixture_root/altered.stdout" "$fixture_root/node-b.stderr" 0 \
        "$fixture_root/node-a.stdout" "$fixture_root/node-a.stderr" 0
}
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_caddy_active_before_sample_3=true/d' "$fixture_root/altered.stdout"
record_check missing_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i 's/_check_caddy_active_before_sample_3=true/_check_caddy_active_before_sample_3=false/' \
    "$fixture_root/altered.stdout"
record_check false_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
printf 'action_28p_a_node_b_check_unexpected=true\n' >>"$fixture_root/altered.stdout"
record_check extra_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_caddy_active_before_sample_2=true/{h;d};/_check_caddy_active_before_sample_3=true/{p;x}' \
    "$fixture_root/altered.stdout"
record_check reordered_label_rejected command_rejected transcript_rejected

/bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$node_b_inspector" "$outer" "$0" >/dev/null
record_check dynamic_scope_collision_policy true
printf '%s_complete=true\n' "$prefix"
