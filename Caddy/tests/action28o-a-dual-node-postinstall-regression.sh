#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28o_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly node_b_inspector=$caddy_root/scripts/inspect-node-b-caddy-service-restoration-action28o-a.sh
readonly node_a_inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-service-restoration-post-action28o-a-outer.sh
fixture_root=$(mktemp -d /tmp/caddy-action28o-a-regression.XXXXXX)
readonly fixture_root
readonly node_b_root=$fixture_root/node-b
readonly node_a_root=$fixture_root/node-a
readonly fake_ssh=$fixture_root/ssh

cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28oa_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28oa_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28oa_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then return 1; fi
    return 0
}
prepare_node_b() {
    install -d -m 0755 "$node_b_root/etc/keepalived/conf.d" "$node_b_root/state" \
        "$node_b_root/run"
    printf '%s\n' 'global_defs {' '    router_id PIHOLE00' '}' \
        'include /etc/keepalived/conf.d/caddy-ha.conf' \
        >"$node_b_root/etc/keepalived/keepalived.conf"
    printf '%s\n' 'vrrp_instance CADDY_IPV4 {' '}' \
        >"$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0644 "$node_b_root/etc/keepalived/keepalived.conf" \
        "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
    node_b_main_hash=$(file_hash "$node_b_root/etc/keepalived/keepalived.conf")
    node_b_fragment_hash=$(file_hash "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf")
    readonly node_b_main_hash node_b_fragment_hash
    printf '%s\n' 'keepalived.service=active' 'lighttpd.service=active' \
        'caddy.service=active' >"$node_b_root/state/services"
    printf '2: eth0 inet 10.1.0.56/22 scope global eth0\n' >"$node_b_root/state/ipv4"
    printf '2: eth0 inet6 fd36:5aa8:6971:1::56/128 scope global\n' \
        >"$node_b_root/state/ipv6"
    printf '%s\n' \
        'localhost|127.0.0.1|/|0|204' \
        'pihole00.local.theama.co|10.1.0.54|/admin/|0|200' \
        'pihole00.local.theama.co|[fd36:5aa8:6971:1::54]|/admin/|0|200' \
        >"$node_b_root/state/https"
}
prepare_node_a() {
    local action28oa_regression_backup=$node_a_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration

    install -d -m 0755 "$node_a_root/etc/keepalived/conf.d" "$node_a_root/state" \
        "$node_a_root/run"
    install -d -m 0700 "$action28oa_regression_backup"
    printf '%s\n' 'global_defs {' '    router_id PIHOLE0' '}' \
        >"$node_a_root/etc/keepalived/keepalived.conf"
    printf '%s\n' 'vrrp_instance CADDY_IPV4 {' '}' \
        >"$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    cp -- "$node_a_root/etc/keepalived/keepalived.conf" \
        "$action28oa_regression_backup/keepalived.conf"
    cp -- "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28oa_regression_backup/caddy-ha.conf"
    node_a_main_hash=$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")
    node_a_baseline_hash=$(file_hash "$action28oa_regression_backup/keepalived.conf")
    node_a_fragment_hash=$(file_hash "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf")
    readonly node_a_main_hash node_a_baseline_hash node_a_fragment_hash
    printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$node_a_baseline_hash" "$node_a_fragment_hash" "$node_a_main_hash" \
        >"$action28oa_regression_backup/manifest"
    chmod 0644 "$node_a_root/etc/keepalived/keepalived.conf" \
        "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$action28oa_regression_backup/manifest"
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
    local action28oa_regression_root=$1

    (
        cd /
        CADDY_ACTION28OA_TEST_MODE=1 \
            CADDY_ACTION28OA_MAIN_SHA256="$node_b_main_hash" \
            CADDY_ACTION28OA_FRAGMENT_SHA256="$node_b_fragment_hash" \
            /bin/bash "$node_b_inspector" --fixture-root "$action28oa_regression_root"
    )
}
run_node_a_producer() {
    (
        cd /
        CADDY_ACTION28MB_TEST_MODE=1 \
            CADDY_ACTION28MB_RETIRED_MAIN_SHA256="$node_a_main_hash" \
            CADDY_ACTION28MB_BASELINE_MAIN_SHA256="$node_a_baseline_hash" \
            CADDY_ACTION28MB_FRAGMENT_SHA256="$node_a_fragment_hash" \
            /bin/bash "$node_a_inspector" --fixture-root "$node_a_root"
    )
}
run_negative_fixture() {
    local action28oa_regression_mode=$1
    local action28oa_regression_case

    action28oa_regression_case=$(mktemp -d "$fixture_root/case.XXXXXX")
    cp -a -- "$node_b_root/." "$action28oa_regression_case/"
    case "$action28oa_regression_mode" in
        main_drift) printf '# drift\n' >>"$action28oa_regression_case/etc/keepalived/keepalived.conf" ;;
        caddy_inactive)
            sed -i 's/caddy[.]service=active/caddy.service=inactive/' \
                "$action28oa_regression_case/state/services"
            ;;
        dns_vip_present)
            printf '2: eth0 inet 10.1.0.55/22 scope global eth0\n' \
                >>"$action28oa_regression_case/state/ipv4"
            ;;
        missing_ipv6_query) rm -f -- "$action28oa_regression_case/state/ipv6" ;;
        https_failure)
            sed -i 's/localhost|127[.]0[.]0[.]1|\/|0|204/localhost|127.0.0.1|\/|28|000/' \
                "$action28oa_regression_case/state/https"
            ;;
        residue) touch "$action28oa_regression_case/run/caddy-action28o-stale" ;;
        *) return 1 ;;
    esac
    command_rejected run_node_b_producer "$action28oa_regression_case"
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
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

received=$(mktemp /tmp/caddy-action28o-a-received.XXXXXX)
readonly received
trap 'rm -f -- "$received"' EXIT
cat >"$received"
[[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]] || exit 90
if [[ " $* " == *' pi@10.1.0.54 '* ]]; then
    [[ " $* " == *' HostKeyAlias=pihole00.local.theama.co '* ]] || exit 91
    [[ "$(sha256sum "$received" | awk '{ print $1 }')" = "$ACTION28OA_NODE_B_SOURCE_HASH" ]] || exit 92
    cat "$ACTION28OA_NODE_B_TRANSCRIPT"
elif [[ " $* " == *' pi@10.1.0.53 '* ]]; then
    [[ " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]] || exit 93
    [[ "$(sha256sum "$received" | awk '{ print $1 }')" = "$ACTION28OA_NODE_A_SOURCE_HASH" ]] || exit 94
    cat "$ACTION28OA_NODE_A_TRANSCRIPT"
else
    exit 95
fi
FAKE_SSH
chmod 0755 "$fake_ssh"

record_check producer_success run_node_b_producer "$node_b_root"
record_check node_a_producer_success run_node_a_producer
record_check main_drift_rejected run_negative_fixture main_drift
record_check caddy_inactive_rejected run_negative_fixture caddy_inactive
record_check dns_vip_present_rejected run_negative_fixture dns_vip_present
record_check failed_address_query_rejected run_negative_fixture missing_ipv6_query
record_check https_failure_rejected run_negative_fixture https_failure
record_check transaction_residue_rejected run_negative_fixture residue

run_outer() {
    CADDY_ACTION28OA_TEST_MODE=1 CADDY_ACTION28OA_SKIP_LOCAL_GATES=true \
        CADDY_ACTION28OA_SSH_BIN="$fake_ssh" \
        CADDY_ACTION28OA_EVIDENCE_ROOT="$fixture_root/evidence" \
        ACTION28OA_NODE_B_SOURCE_HASH="$(file_hash "$node_b_inspector")" \
        ACTION28OA_NODE_A_SOURCE_HASH="$(file_hash "$node_a_inspector")" \
        ACTION28OA_NODE_B_TRANSCRIPT="$fixture_root/node-b.stdout" \
        ACTION28OA_NODE_A_TRANSCRIPT="$fixture_root/node-a.stdout" \
        /bin/bash "$outer"
}

record_check outer_actual_producer_success run_outer
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_caddy_active_before_sample_3=true/d' "$fixture_root/altered.stdout"
record_check missing_label_rejected command_rejected env CADDY_ACTION28OA_TEST_MODE=1 \
    /bin/bash "$outer" --transcript-test "$fixture_root/altered.stdout" \
    "$fixture_root/node-b.stderr" 0 "$fixture_root/node-a.stdout" \
    "$fixture_root/node-a.stderr" 0
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i 's/_check_caddy_active_before_sample_3=true/_check_caddy_active_before_sample_3=false/' \
    "$fixture_root/altered.stdout"
record_check false_label_rejected command_rejected env CADDY_ACTION28OA_TEST_MODE=1 \
    /bin/bash "$outer" --transcript-test "$fixture_root/altered.stdout" \
    "$fixture_root/node-b.stderr" 0 "$fixture_root/node-a.stdout" \
    "$fixture_root/node-a.stderr" 0
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
printf 'action_28o_a_node_b_check_unexpected=true\n' >>"$fixture_root/altered.stdout"
record_check extra_label_rejected command_rejected env CADDY_ACTION28OA_TEST_MODE=1 \
    /bin/bash "$outer" --transcript-test "$fixture_root/altered.stdout" \
    "$fixture_root/node-b.stderr" 0 "$fixture_root/node-a.stdout" \
    "$fixture_root/node-a.stderr" 0
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_caddy_active_before_sample_2=true/{h;d};/_check_caddy_active_before_sample_3=true/{p;x}' \
    "$fixture_root/altered.stdout"
record_check reordered_label_rejected command_rejected env CADDY_ACTION28OA_TEST_MODE=1 \
    /bin/bash "$outer" --transcript-test "$fixture_root/altered.stdout" \
    "$fixture_root/node-b.stderr" 0 "$fixture_root/node-a.stdout" \
    "$fixture_root/node-a.stderr" 0

/bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$node_b_inspector" "$outer" "$0" >/dev/null
record_check dynamic_scope_collision_policy true
printf '%s_complete=true\n' "$prefix"
