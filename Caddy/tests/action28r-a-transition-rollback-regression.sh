#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28r_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-action28r-transition-rollback-action28r-a.sh
readonly outer=$caddy_root/scripts/run-dual-node-action28r-transition-rollback-action28r-a-outer.sh
fixture_root=$(mktemp -d /tmp/caddy-action28r-a-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
readonly node_a_root=$fixture_root/node-a
readonly node_b_root=$fixture_root/node-b
readonly fake_ssh=$fixture_root/ssh

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28ra_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28ra_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28ra_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then return 1; fi
    return 0
}
prepare_role() {
    local action28ra_regression_root=$1
    local action28ra_regression_role=$2

    install -d -m 0755 "$action28ra_regression_root/etc/keepalived/conf.d"
    printf 'global_defs {\n    router_id %s\n}\n' "$action28ra_regression_role" >"$action28ra_regression_root/etc/keepalived/keepalived.conf"
    printf 'vrrp_instance RETAINED_%s {\n}\n' "$action28ra_regression_role" >"$action28ra_regression_root/etc/keepalived/conf.d/caddy-ha.conf"
    printf '%s\n' keepalived.service=active caddy.service=active lighttpd.service=active >"$action28ra_regression_root/services"
    if [[ "$action28ra_regression_role" = node_a ]]; then
        printf '2: eth0 inet 10.1.0.55/22 scope global eth0\n' >"$action28ra_regression_root/ipv4"
        printf '2: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global\n' >"$action28ra_regression_root/ipv6"
        printf '(us) 2 "Master"\n' >"$action28ra_regression_root/ipv4-state"
        printf '(us) 2 "Master"\n' >"$action28ra_regression_root/ipv6-state"
    else
        : >"$action28ra_regression_root/ipv4"
        : >"$action28ra_regression_root/ipv6"
        printf '(us) 1 "Backup"\n' >"$action28ra_regression_root/ipv4-state"
        printf '(us) 1 "Backup"\n' >"$action28ra_regression_root/ipv6-state"
    fi
    printf '%s keepalived: Action 28r transition evidence role=%s MASTER BACKUP\n' '2026-08-10T15:16:08-0500' "$action28ra_regression_role" >"$action28ra_regression_root/keepalived-journal"
    printf '%s keepalived-notify: role=%s state MASTER\n%s keepalived-notify: role=%s state BACKUP\n' '2026-08-10T15:16:09-0500' "$action28ra_regression_role" '2026-08-10T15:16:29-0500' "$action28ra_regression_role" >"$action28ra_regression_root/notifier-journal"
}
run_inspector() {
    local action28ra_regression_role=$1
    local action28ra_regression_root=$2

    (
        cd /
        CADDY_ACTION28RA_TEST_MODE=1 \
            CADDY_ACTION28RA_FIXTURE_ROOT="$action28ra_regression_root" \
            CADDY_ACTION28RA_NODE_A_MAIN_SHA256="$node_a_main_sha256" \
            CADDY_ACTION28RA_NODE_A_FRAGMENT_SHA256="$node_a_fragment_sha256" \
            CADDY_ACTION28RA_NODE_B_MAIN_SHA256="$node_b_main_sha256" \
            CADDY_ACTION28RA_NODE_B_FRAGMENT_SHA256="$node_b_fragment_sha256" \
            /bin/bash "$inspector" "--$action28ra_regression_role"
    )
}

prepare_role "$node_a_root" node_a
prepare_role "$node_b_root" node_b
node_a_main_sha256=$(file_hash "$node_a_root/etc/keepalived/keepalived.conf")
node_a_fragment_sha256=$(file_hash "$node_a_root/etc/keepalived/conf.d/caddy-ha.conf")
node_b_main_sha256=$(file_hash "$node_b_root/etc/keepalived/keepalived.conf")
node_b_fragment_sha256=$(file_hash "$node_b_root/etc/keepalived/conf.d/caddy-ha.conf")
readonly node_a_main_sha256 node_a_fragment_sha256 node_b_main_sha256 node_b_fragment_sha256
run_inspector node-a "$node_a_root" >"$fixture_root/node-a.stdout"
run_inspector node-b "$node_b_root" >"$fixture_root/node-b.stdout"
install -m 0600 /dev/null "$fixture_root/node-a.stderr"
install -m 0600 /dev/null "$fixture_root/node-b.stderr"
record_check node_a_actual_producer_success run_inspector node-a "$node_a_root"
record_check node_b_actual_producer_success run_inspector node-b "$node_b_root"

cp -a -- "$node_b_root" "$fixture_root/node-b-wrong"
printf '(us) 2 "Master"\n' >"$fixture_root/node-b-wrong/ipv4-state"
wrong_status=0
run_inspector node-b "$fixture_root/node-b-wrong" >"$fixture_root/wrong.stdout" || wrong_status=$?
record_check false_assertion_returns_nonzero test "$wrong_status" -ne 0
record_check false_assertion_emitted grep -Fqx 'action_28r_a_check_ipv4_state_exact=false' "$fixture_root/wrong.stdout"
record_check false_assertion_acceptance_false grep -Fqx 'action_28r_a_acceptance=false' "$fixture_root/wrong.stdout"
record_check later_journal_evidence_still_emitted grep -Fqx 'action_28r_a_capture_notifier_journal_stdout_end' "$fixture_root/wrong.stdout"

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
received=$(mktemp /tmp/caddy-action28r-a-received.XXXXXX)
readonly received
trap 'rm -f -- "$received"' EXIT
cat >"$received"
if [[ " $* " == *' pi@10.1.0.54 '* && " $* " == *' --node-b'* ]]; then
    role=node-b
    root=$ACTION28RA_NODE_B_ROOT
elif [[ " $* " == *' pi@10.1.0.53 '* && " $* " == *' --node-a'* ]]; then
    role=node-a
    root=$ACTION28RA_NODE_A_ROOT
else
    exit 90
fi
cd /
CADDY_ACTION28RA_TEST_MODE=1 CADDY_ACTION28RA_FIXTURE_ROOT="$root" \
    CADDY_ACTION28RA_NODE_A_MAIN_SHA256="$ACTION28RA_NODE_A_MAIN_HASH" \
    CADDY_ACTION28RA_NODE_A_FRAGMENT_SHA256="$ACTION28RA_NODE_A_FRAGMENT_HASH" \
    CADDY_ACTION28RA_NODE_B_MAIN_SHA256="$ACTION28RA_NODE_B_MAIN_HASH" \
    CADDY_ACTION28RA_NODE_B_FRAGMENT_SHA256="$ACTION28RA_NODE_B_FRAGMENT_HASH" \
    /bin/bash "$received" "--$role"
FAKE_SSH
chmod 0755 "$fake_ssh"
export ACTION28RA_NODE_A_ROOT=$node_a_root ACTION28RA_NODE_B_ROOT=$node_b_root
export ACTION28RA_NODE_A_MAIN_HASH=$node_a_main_sha256 ACTION28RA_NODE_A_FRAGMENT_HASH=$node_a_fragment_sha256
export ACTION28RA_NODE_B_MAIN_HASH=$node_b_main_sha256 ACTION28RA_NODE_B_FRAGMENT_HASH=$node_b_fragment_sha256
run_outer() {
    CADDY_ACTION28RA_TEST_MODE=1 CADDY_ACTION28RA_SKIP_LOCAL_GATES=true \
        CADDY_ACTION28RA_SSH_BIN="$fake_ssh" \
        CADDY_ACTION28RA_EVIDENCE_ROOT="$fixture_root/evidence" /bin/bash "$outer"
}
record_check outer_actual_producer_path_success run_outer

transcript_rejected() {
    CADDY_ACTION28RA_TEST_MODE=1 /bin/bash "$outer" --transcript-test \
        "$fixture_root/altered.stdout" "$fixture_root/node-b.stderr" 0 \
        "$fixture_root/node-a.stdout" "$fixture_root/node-a.stderr" 0
}
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_dns_ipv4_count_exact=true/d' "$fixture_root/altered.stdout"
record_check missing_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i 's/_check_dns_ipv4_count_exact=true/_check_dns_ipv4_count_exact=false/' "$fixture_root/altered.stdout"
record_check false_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
printf 'action_28r_a_check_unexpected=true\n' >>"$fixture_root/altered.stdout"
record_check extra_label_rejected command_rejected transcript_rejected
cp -- "$fixture_root/node-b.stdout" "$fixture_root/altered.stdout"
sed -i '/_check_main_regular=true/{h;d};/_check_main_not_symlink=true/{G}' "$fixture_root/altered.stdout"
record_check reordered_label_rejected command_rejected transcript_rejected
# The literal variable reference is the unsafe command-construction shape under test.
# shellcheck disable=SC2016
record_check cursor_not_in_ssh_command test "$(grep -F '$retained_cursor' "$outer" || true)" = ""
record_check action_28r_not_invoked test "$(grep -En 'run-node-a-coupled-vip-acquisition-action28r-outer[.]sh|acquire-node-a-coupled-vips-action28r[.]sh' "$outer" "$inspector" || true)" = ""
record_check no_mutation_commands test "$(grep -En 'systemctl (reload|restart|start|stop)|install .*etc/|mv .*etc/' "$outer" "$inspector" || true)" = ""
/bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$outer" "$0" >/dev/null
record_check dynamic_scope_collision_policy true
printf '%s_complete=true\n' "$prefix"
