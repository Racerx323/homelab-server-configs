#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28q_a_regression
readonly node_b_main_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly node_b_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly node_b_baseline_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly node_b_state=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_b_notifier=$caddy_root/scripts/inspect-node-b-action28q-notifier-evidence.sh
readonly node_a_state=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-dual-node-coupled-vip-postrollback-action28q-a-outer.sh
readonly retired_fixture=$test_directory/fixtures/action28p-node-b-retired-main.conf
readonly template=$caddy_root/templates/keepalived-caddy-ha.conf.in
fixture_root=$(mktemp -d /tmp/caddy-action28q-a-regression.XXXXXX)
readonly fixture_root
readonly node_b_root=$fixture_root/node-b
readonly node_a_root=$fixture_root/node-a
readonly notifier_root=$fixture_root/notifier
readonly fake_ssh=$fixture_root/ssh

cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28qa_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28qa_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28qa_regression_label" >&2
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
    local action28qa_regression_backup=$node_b_root/var/backups/caddy-ha/action28p-node-b-caddy-vrrp-relinquish

    install -d -m 0755 "$node_b_root/etc/keepalived/conf.d" "$node_b_root/state" \
        "$node_b_root/run"
    install -d -m 0700 "$action28qa_regression_backup"
    install -m 0644 "$retired_fixture" "$node_b_root/etc/keepalived/keepalived.conf"
    render_node_b_fragment
    chmod 0644 "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf"
    cp -- "$retired_fixture" "$action28qa_regression_backup/keepalived.conf"
    printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n' \
        >>"$action28qa_regression_backup/keepalived.conf"
    cp -- "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28qa_regression_backup/caddy-ha.conf"
    printf 'action=28p\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$node_b_baseline_sha256" "$node_b_fragment_sha256" "$node_b_main_sha256" \
        >"$action28qa_regression_backup/manifest"
    chmod 0600 "$action28qa_regression_backup/keepalived.conf" \
        "$action28qa_regression_backup/caddy-ha.conf" "$action28qa_regression_backup/manifest"
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
    local action28qa_regression_backup=$node_a_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration

    install -d -m 0755 "$node_a_root/etc/keepalived/conf.d" "$node_a_root/state" \
        "$node_a_root/run"
    install -d -m 0700 "$action28qa_regression_backup"
    printf '%s\n' 'global_defs {' '    router_id PIHOLE0' '}' \
        >"$node_a_root/etc/keepalived/keepalived.conf"
    printf '%s\n' 'vrrp_instance CADDY_IPV4 {' '}' \
        >"$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    cp -- "$node_a_root/etc/keepalived/keepalived.conf" \
        "$action28qa_regression_backup/keepalived.conf"
    cp -- "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$action28qa_regression_backup/caddy-ha.conf"
    node_a_main_sha256=$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")
    node_a_baseline_sha256=$(file_hash "$action28qa_regression_backup/keepalived.conf")
    node_a_fragment_sha256=$(file_hash "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf")
    readonly node_a_main_sha256 node_a_baseline_sha256 node_a_fragment_sha256
    printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$node_a_baseline_sha256" "$node_a_fragment_sha256" "$node_a_main_sha256" \
        >"$action28qa_regression_backup/manifest"
    chmod 0644 "$node_a_root/etc/keepalived/keepalived.conf" \
        "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$action28qa_regression_backup/manifest"
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
prepare_notifier() {
    install -d -m 0755 "$notifier_root"
    printf '%s\n' \
        'Aug 10 13:54:13 j1-svpihole00 keepalived-notify[1]: Instance PIHOLE_DUALSTACK (GROUP) changed to state: MASTER' \
        'Aug 10 13:54:13 j1-svpihole00 keepalived-notify[2]: Apprise notification delivered for PIHOLE_DUALSTACK (GROUP) state MASTER' \
        'Aug 10 13:54:20 j1-svpihole00 keepalived-notify[3]: Instance PIHOLE_DUALSTACK (GROUP) changed to state: BACKUP' \
        'Aug 10 13:54:25 j1-svpihole00 keepalived-notify[4]: Apprise notification failed for PIHOLE_DUALSTACK (GROUP) state BACKUP: curl exit 28: curl: (28) Operation timed out after 5001 milliseconds with 0 bytes received' \
        >"$notifier_root/journal"
    printf '(us) 1 "Backup"\n' >"$notifier_root/ipv4-state"
    printf '(us) 1 "Backup"\n' >"$notifier_root/ipv6-state"
}
run_node_b_state() {
    (
        cd /
        CADDY_ACTION28PA_TEST_MODE=1 \
            CADDY_ACTION28PA_MAIN_SHA256="$node_b_main_sha256" \
            CADDY_ACTION28PA_FRAGMENT_SHA256="$node_b_fragment_sha256" \
            /bin/bash "$node_b_state" --fixture-root "$node_b_root"
    )
}
run_node_a_state() {
    (
        cd /
        CADDY_ACTION28MB_TEST_MODE=1 \
            CADDY_ACTION28MB_RETIRED_MAIN_SHA256="$node_a_main_sha256" \
            CADDY_ACTION28MB_BASELINE_MAIN_SHA256="$node_a_baseline_sha256" \
            CADDY_ACTION28MB_FRAGMENT_SHA256="$node_a_fragment_sha256" \
            /bin/bash "$node_a_state" --fixture-root "$node_a_root"
    )
}
run_notifier() {
    local action28qa_regression_root=$1

    (
        cd /
        CADDY_ACTION28QA_TEST_MODE=1 /bin/bash "$node_b_notifier" \
            --fixture-root "$action28qa_regression_root"
    )
}
notifier_case_rejected() {
    local action28qa_regression_mode=$1
    local action28qa_regression_case

    action28qa_regression_case=$(mktemp -d "$fixture_root/notifier-case.XXXXXX")
    cp -a -- "$notifier_root/." "$action28qa_regression_case/"
    case "$action28qa_regression_mode" in
        missing_backup) sed -i '/changed to state: BACKUP/d' "$action28qa_regression_case/journal" ;;
        wrong_ipv4_state) printf '(us) 2 "Master"\n' >"$action28qa_regression_case/ipv4-state" ;;
        wrong_ipv6_state) printf '(us) 2 "Master"\n' >"$action28qa_regression_case/ipv6-state" ;;
        delivery_not_failed) sed -i 's/notification failed/notification delivered/' \
            "$action28qa_regression_case/journal" ;;
        duplicate_master)
            action28qa_regression_duplicate=$(head -n 1 "$action28qa_regression_case/journal")
            printf '%s\n' "$action28qa_regression_duplicate" \
                >>"$action28qa_regression_case/journal"
            ;;
        reordered)
            mapfile -t action28qa_regression_journal_lines \
                <"$action28qa_regression_case/journal"
            printf '%s\n' \
                "${action28qa_regression_journal_lines[2]}" \
                "${action28qa_regression_journal_lines[1]}" \
                "${action28qa_regression_journal_lines[0]}" \
                "${action28qa_regression_journal_lines[3]}" \
                >"$action28qa_regression_case/journal.reordered"
            mv -- "$action28qa_regression_case/journal.reordered" \
                "$action28qa_regression_case/journal"
            ;;
        *) return 1 ;;
    esac
    command_rejected run_notifier "$action28qa_regression_case"
}

prepare_node_b
prepare_node_a
prepare_notifier
run_node_b_state >"$fixture_root/node-b.stdout"
run_notifier "$notifier_root" >"$fixture_root/notifier.stdout"
run_node_a_state >"$fixture_root/node-a.stdout"
install -m 0600 /dev/null "$fixture_root/node-b.stderr"
install -m 0600 /dev/null "$fixture_root/notifier.stderr"
install -m 0600 /dev/null "$fixture_root/node-a.stderr"

record_check node_b_real_producer_success run_node_b_state
record_check notifier_real_producer_success run_notifier "$notifier_root"
record_check node_a_real_producer_success run_node_a_state
for action28qa_regression_case in missing_backup wrong_ipv4_state wrong_ipv6_state \
    delivery_not_failed duplicate_master reordered; do
    record_check "notifier_${action28qa_regression_case}_rejected" \
        notifier_case_rejected "$action28qa_regression_case"
done

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
received=$(mktemp /tmp/caddy-action28q-a-received.XXXXXX)
readonly received
trap 'rm -f -- "$received"' EXIT
cat >"$received"
[[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]] || exit 90
received_hash=$(sha256sum "$received" | awk '{ print $1 }')
if [[ " $* " == *' pi@10.1.0.54 '* && \
    "$received_hash" = "$ACTION28QA_NODE_B_STATE_HASH" ]]; then
    cat "$ACTION28QA_NODE_B_STATE_TRANSCRIPT"
elif [[ " $* " == *' pi@10.1.0.54 '* && \
    "$received_hash" = "$ACTION28QA_NOTIFIER_HASH" ]]; then
    cat "$ACTION28QA_NOTIFIER_TRANSCRIPT"
elif [[ " $* " == *' pi@10.1.0.53 '* && \
    "$received_hash" = "$ACTION28QA_NODE_A_STATE_HASH" ]]; then
    cat "$ACTION28QA_NODE_A_STATE_TRANSCRIPT"
else
    exit 91
fi
FAKE_SSH
chmod 0755 "$fake_ssh"

run_outer() {
    CADDY_ACTION28QA_TEST_MODE=1 CADDY_ACTION28QA_SKIP_LOCAL_GATES=true \
        CADDY_ACTION28QA_SSH_BIN="$fake_ssh" \
        CADDY_ACTION28QA_EVIDENCE_ROOT="$fixture_root/evidence" \
        ACTION28QA_NODE_B_STATE_HASH="$(file_hash "$node_b_state")" \
        ACTION28QA_NOTIFIER_HASH="$(file_hash "$node_b_notifier")" \
        ACTION28QA_NODE_A_STATE_HASH="$(file_hash "$node_a_state")" \
        ACTION28QA_NODE_B_STATE_TRANSCRIPT="$fixture_root/node-b.stdout" \
        ACTION28QA_NOTIFIER_TRANSCRIPT="$fixture_root/notifier.stdout" \
        ACTION28QA_NODE_A_STATE_TRANSCRIPT="$fixture_root/node-a.stdout" \
        /bin/bash "$outer"
}
record_check outer_actual_producer_path_success run_outer

transcript_rejected() {
    CADDY_ACTION28QA_TEST_MODE=1 /bin/bash "$outer" --transcript-test \
        "$fixture_root/altered.stdout" "$fixture_root/node-b.stderr" 0 \
        "$fixture_root/notifier.stdout" "$fixture_root/notifier.stderr" 0 \
        "$fixture_root/node-a.stdout" "$fixture_root/node-a.stderr" 0
}
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_dns_ipv4_absent_before=true/d' "$fixture_root/altered.stdout"
record_check missing_state_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i 's/_check_dns_ipv4_absent_before=true/_check_dns_ipv4_absent_before=false/' \
    "$fixture_root/altered.stdout"
record_check false_state_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
printf 'action_28p_a_node_b_check_unexpected=true\n' >>"$fixture_root/altered.stdout"
record_check extra_state_label_rejected command_rejected transcript_rejected

record_check action_28q_not_invoked \
    test "$(grep -En 'run-node-a-coupled-vip-acquisition-action28q-outer[.]sh' "$outer" || true)" = ""
record_check no_mutation_commands test \
    "$(grep -En 'systemctl (reload|restart|start|stop)|install .*etc/|mv .*etc/' "$outer" \
        "$node_b_notifier" || true)" = ""
/bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$node_b_notifier" "$outer" "$0" >/dev/null
record_check dynamic_scope_collision_policy true
printf '%s_complete=true\n' "$prefix"
