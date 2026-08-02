#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17o_node_b
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly authorized_keys="$ssh_dir/authorized_keys"
readonly receiver=/usr/local/libexec/caddy-sync-rsync-receiver
readonly accepted_caddy_release=/etc/caddy/releases/action15-health-follow-redirects
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly node_a_sync_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly node_a_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'
readonly expected_authorization="from=\"10.1.0.53,fd36:5aa8:6971:1::53\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_a_public_key"

checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2

    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf '%s_check_%s=true\n' "$action_prefix" "$result_label"
        checks_passed=$((checks_passed + 1))
    else
        printf '%s_check_%s=false\n' "$action_prefix" "$result_label"
        checks_failed=$((checks_failed + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$result_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

authorization_fingerprint() {
    local authorization_key

    authorization_key=$(awk '{ print $(NF-2), $(NF-1), $NF }' "$authorized_keys")
    ssh-keygen -lf <(printf '%s\n' "$authorization_key") -E sha256 |
        awk '{ print $2 }'
}

relevant_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$authorized_keys" \
        "$receiver" \
        /etc/default/caddy-ha
    sha256sum "$authorized_keys" "$receiver" /etc/default/caddy-ha
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    readlink /etc/caddy/current
    readlink -e /etc/caddy/current
    for state_unit in \
        caddy.service ssh.service lsyncd.service caddy-lsyncd.service; do
        printf 'unit=%s\n' "$state_unit"
        systemctl show "$state_unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$state_unit" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$receiver_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_a_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_authorization" == "from=\"10.1.0.53,fd36:5aa8:6971:1::53\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_a_public_key" ]]
    printf 'action_17o_node_b_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

record_command identity test "$(id -u)" -eq 0
record_command hostname test "$(hostname)" = j1-svpihole00
record_command architecture test "$(dpkg --print-architecture)" = arm64
record_command node_ipv4_present \
    grep -Fq '10.1.0.54/22' \
    < <(ip -o -4 address show dev eth0 2>/dev/null)
record_command node_ipv6_present \
    grep -Fq 'fd36:5aa8:6971:1::54/64' \
    < <(ip -o -6 address show dev eth0 2>/dev/null)
record_command authorization_regular test -f "$authorized_keys"
record_command authorization_not_symlink test ! -L "$authorized_keys"
record_command authorization_metadata \
    test "$(stat -c '%U:%G:%a' "$authorized_keys" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command authorization_line_count \
    test "$(wc -l <"$authorized_keys" 2>/dev/null || printf 0)" -eq 1
record_command authorization_exact \
    grep -Fxq "$expected_authorization" "$authorized_keys"
record_command authorization_fingerprint \
    test "$(authorization_fingerprint 2>/dev/null || true)" = \
    "$node_a_sync_fingerprint"
record_command receiver_regular test -f "$receiver"
record_command receiver_not_symlink test ! -L "$receiver"
record_command receiver_metadata \
    test "$(stat -c '%U:%G:%a' "$receiver" 2>/dev/null || true)" = root:root:755
record_command receiver_hash \
    test "$(file_hash "$receiver" 2>/dev/null || true)" = "$receiver_sha256"
record_command receiver_restricted_root \
    grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    "$receiver"
record_command environment_role \
    grep -Fxq 'NODE_ROLE=node-b' /etc/default/caddy-ha
record_command environment_peer_ipv4 \
    grep -Fxq 'PEER_IPV4=10.1.0.53' /etc/default/caddy-ha
record_command environment_peer_ipv6 \
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::53' /etc/default/caddy-ha
record_command current_release_link \
    test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
    "$accepted_caddy_release"
record_command current_release_target \
    test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
    "$accepted_caddy_release"
record_command incoming_node_a_absent \
    test ! -e /var/lib/caddy-sync/incoming/node-a
record_command incoming_node_b_absent \
    test ! -e /var/lib/caddy-sync/incoming/node-b
record_command outbound_empty \
    test "$(find /var/lib/caddy-sync/outbound -type f | wc -l)" -eq 0
record_command lsyncd_configuration_absent test ! -e /etc/lsyncd/caddy.lua
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked \
    test "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive
record_command caddy_lsyncd_disabled \
    test "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = \
    disabled
record_command caddy_active \
    test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command ssh_active \
    test "$(systemctl is-active ssh.service 2>/dev/null || true)" = active

state_file=$(mktemp /tmp/caddy-action17o-node-b-state.XXXXXX)
readonly state_file
cleanup() {
    # shellcheck disable=SC2317
    rm -f -- "$state_file" "$state_file.err"
}
trap cleanup EXIT
state_status=0
relevant_state >"$state_file" 2>"$state_file.err" || state_status=$?
record_command state_status test "$state_status" -eq 0
record_command state_stderr_empty test ! -s "$state_file.err"
if [[ "$state_status" -eq 0 ]]; then
    state_sha256=$(file_hash "$state_file")
else
    state_sha256=unavailable
fi
readonly state_sha256
printf 'action_17o_node_b_value_state_sha256=%s\n' "$state_sha256"
printf 'action_17o_node_b_checks_total=%s\n' "$checks_total"
printf 'action_17o_node_b_checks_passed=%s\n' "$checks_passed"
printf 'action_17o_node_b_checks_failed=%s\n' "$checks_failed"
printf 'action_17o_node_b_first_failure=%s\n' "$first_failure"
printf 'action_17o_node_b_persistent_mutations=false\n'
printf 'action_17o_node_b_synchronization_executed=false\n'

if [[ "$checks_failed" -eq 0 ]]; then
    printf 'action_17o_node_b_acceptance=true\n'
    exit 0
fi

printf 'action_17o_node_b_acceptance=false\n'
exit 1
