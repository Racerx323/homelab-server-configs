#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17o
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly environment_file=/etc/default/caddy-ha
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv4=10.1.0.54
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_fqdn=pihole00.local.theama.co
readonly interface=eth0
readonly denied_command=caddy-action17o-denied-probe
readonly denied_message='Only the rsync server protocol is permitted.'
readonly expected_key_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly expected_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'

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

key_fingerprint() {
    ssh-keygen -lf "$public_key" -E sha256 |
        awk '{ print $2 }'
}

known_host_fingerprint() {
    ssh-keygen -F "$node_b_fqdn" -f "$known_hosts" |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 |
        awk 'NR == 1 { print $2 }'
}

peer_nss_ipv4_matches() {
    # shellcheck disable=SC2317
    getent ahostsv4 "$node_b_fqdn" |
        awk '{ print $1 }' |
        grep -Fxq "$node_b_ipv4"
}

peer_nss_ipv6_matches() {
    # shellcheck disable=SC2317
    getent ahostsv6 "$node_b_fqdn" |
        awk '{ print $1 }' |
        grep -Fxq "$node_b_ipv6"
}

relevant_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$environment_file"
    sha256sum \
        "$private_key" \
        "$public_key" \
        "$known_hosts" \
        "$environment_file"
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    for state_unit in ssh.service lsyncd.service caddy-lsyncd.service; do
        printf 'unit=%s\n' "$state_unit"
        systemctl show "$state_unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$state_unit" 2>/dev/null || true)"
    done
}

classify_ssh_error() {
    local classification_status=$1
    local classification_error_file=$2

    if [[ "$classification_status" -eq 126 ]] &&
        grep -Fqx "$denied_message" "$classification_error_file"; then
        printf 'forced_receiver_rejection\n'
    elif grep -Fq 'Could not resolve hostname' "$classification_error_file"; then
        printf 'name_resolution_failed\n'
    elif grep -Fq 'Cannot assign requested address' "$classification_error_file"; then
        printf 'bind_address_unavailable\n'
    elif grep -Fq 'Network is unreachable' "$classification_error_file"; then
        printf 'network_unreachable\n'
    elif grep -Fq 'No route to host' "$classification_error_file"; then
        printf 'no_route_to_host\n'
    elif grep -Fq 'Connection timed out' "$classification_error_file"; then
        printf 'connection_timed_out\n'
    elif grep -Fq 'Connection refused' "$classification_error_file"; then
        printf 'connection_refused\n'
    elif grep -Fq 'REMOTE HOST IDENTIFICATION HAS CHANGED' \
        "$classification_error_file"; then
        printf 'host_key_mismatch\n'
    elif grep -Fq 'Permission denied' "$classification_error_file"; then
        printf 'publickey_denied\n'
    elif grep -Eq 'Connection closed|Connection reset' \
        "$classification_error_file"; then
        printf 'connection_closed\n'
    else
        printf 'unclassified\n'
    fi
}

debug_marker() {
    local marker_pattern=$1
    local marker_error_file=$2

    if grep -Fq "$marker_pattern" "$marker_error_file"; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$node_b_ipv4" == 10.1.0.54 ]]
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$node_b_fqdn" == pihole00.local.theama.co ]]
    [[ "$expected_key_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$denied_command" != rsync\ --server\ * ]]
    printf 'action_17o_node_a_inspector_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    (
        contract_dir=$(mktemp -d /tmp/caddy-action17o-node-a-contract.XXXXXX)
        trap 'rm -rf -- "$contract_dir"' EXIT
        printf '%s\n' "$denied_message" >"$contract_dir/forced"
        printf '%s\n' \
            'ssh: Could not resolve hostname pihole00.local.theama.co' \
            >"$contract_dir/resolution"
        : >"$contract_dir/empty"
        [[ "$(classify_ssh_error 126 "$contract_dir/forced")" == forced_receiver_rejection ]]
        [[ "$(classify_ssh_error 255 "$contract_dir/resolution")" == name_resolution_failed ]]
        [[ "$(classify_ssh_error 255 "$contract_dir/empty")" == unclassified ]]
    )
    printf 'action_17o_node_a_inspector_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

work_dir=$(mktemp -d /tmp/caddy-action17o-node-a.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

record_command identity test "$(id -un)" = caddy-sync
record_command working_directory test "$(pwd -P)" = /
record_command hostname test "$(hostname)" = j1-svpihole0
record_command architecture test "$(dpkg --print-architecture)" = arm64
record_command environment_file_readable test -r "$environment_file"
record_command environment_role \
    grep -Fxq 'NODE_ROLE=node-a' "$environment_file"
record_command environment_node_ipv6 \
    grep -Fxq "NODE_IPV6=$node_a_ipv6" "$environment_file"
record_command environment_peer_ipv4 \
    grep -Fxq "PEER_IPV4=$node_b_ipv4" "$environment_file"
record_command environment_peer_ipv6 \
    grep -Fxq "PEER_IPV6=$node_b_ipv6" "$environment_file"
record_command environment_sync_target \
    grep -Fxq "SYNC_TARGET=$node_b_fqdn" "$environment_file"
record_command stable_ipv6_present \
    grep -Fq "$node_a_ipv6/64" \
    < <(ip -o -6 address show dev "$interface" 2>/dev/null)
record_command peer_hosts_ipv4_exact \
    grep -Fxq "$node_b_ipv4 $node_b_fqdn" /etc/hosts
record_command peer_hosts_ipv6_exact \
    grep -Fxq "$node_b_ipv6 $node_b_fqdn" /etc/hosts
record_command peer_hosts_ipv4_unique \
    test "$(grep -Fxc "$node_b_ipv4 $node_b_fqdn" /etc/hosts)" -eq 1
record_command peer_hosts_ipv6_unique \
    test "$(grep -Fxc "$node_b_ipv6 $node_b_fqdn" /etc/hosts)" -eq 1
record_command peer_nss_ipv4 peer_nss_ipv4_matches
record_command peer_nss_ipv6 peer_nss_ipv6_matches
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_command public_key_regular test -f "$public_key"
record_command known_hosts_regular test -f "$known_hosts"
record_command ssh_directory_metadata \
    test "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:700
record_command private_key_metadata \
    test "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command known_hosts_metadata \
    test "$(stat -c '%U:%G:%a' "$known_hosts" 2>/dev/null || true)" = \
    caddy-sync:caddy-sync:600
record_command public_key_fingerprint \
    test "$(key_fingerprint 2>/dev/null || true)" = \
    "$expected_key_fingerprint"
record_command known_host_fingerprint \
    test "$(known_host_fingerprint 2>/dev/null || true)" = \
    "$expected_host_fingerprint"
record_command incoming_node_a_absent \
    test ! -e /var/lib/caddy-sync/incoming/node-a
record_command incoming_node_b_absent \
    test ! -e /var/lib/caddy-sync/incoming/node-b
record_command outbound_empty \
    test "$(find /var/lib/caddy-sync/outbound -type f | wc -l)" -eq 0
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive

before_state="$work_dir/state-before"
before_state_error="$work_dir/state-before.err"
before_state_status=0
relevant_state >"$before_state" 2>"$before_state_error" ||
    before_state_status=$?
record_command before_state_status test "$before_state_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_state_error"
if [[ "$before_state_status" -eq 0 ]]; then
    before_state_sha256=$(file_hash "$before_state")
else
    before_state_sha256=unavailable
fi
readonly before_state_sha256
printf 'action_17o_value_before_state_sha256=%s\n' "$before_state_sha256"

transport_probe_attempted=false
rsync_dry_run_attempted=false
probe_status=not_run
probe_error_class=not_run
rsync_status=not_run

if [[ "$checks_failed" -eq 0 ]]; then
    transport_probe_attempted=true
    probe_output="$work_dir/ssh.out"
    probe_error="$work_dir/ssh.err"
    probe_status=0
    ssh -6 -n -T -vv \
        -F /dev/null \
        -b "$node_a_ipv6" \
        -i "$private_key" \
        -o BatchMode=yes \
        -o ClearAllForwardings=yes \
        -o ConnectTimeout=5 \
        -o GlobalKnownHostsFile=/dev/null \
        -o "HostKeyAlias=$node_b_fqdn" \
        -o IdentitiesOnly=yes \
        -o KbdInteractiveAuthentication=no \
        -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey \
        -o ServerAliveCountMax=2 \
        -o ServerAliveInterval=2 \
        -o StrictHostKeyChecking=yes \
        -o UpdateHostKeys=no \
        -o "UserKnownHostsFile=$known_hosts" \
        "caddy-sync@$node_b_fqdn" \
        "$denied_command" \
        >"$probe_output" 2>"$probe_error" || probe_status=$?
    probe_error_class=$(classify_ssh_error "$probe_status" "$probe_error")
    record_command direct_ssh_status test "$probe_status" -eq 126
    record_command direct_ssh_error_class \
        test "$probe_error_class" = forced_receiver_rejection
    record_command direct_ssh_stdout_empty test ! -s "$probe_output"
    record_command direct_ssh_stderr_exact \
        grep -Fqx "$denied_message" "$probe_error"
    record_command direct_ssh_connecting \
        test "$(debug_marker 'Connecting to ' "$probe_error")" = true
    record_command direct_ssh_connection_established \
        test "$(debug_marker 'Connection established.' "$probe_error")" = true
    record_command direct_ssh_host_key_verified \
        test "$(debug_marker "Host '$node_b_fqdn' is known and matches" \
            "$probe_error")" = true
    record_command direct_ssh_public_key_offered \
        test "$(debug_marker 'Offering public key:' "$probe_error")" = true
    record_command direct_ssh_server_accepted_key \
        test "$(debug_marker 'Server accepts key:' "$probe_error")" = true
    record_command direct_ssh_authenticated \
        test "$(debug_marker 'Authenticated to ' "$probe_error")" = true

    if [[ "$checks_failed" -eq 0 ]]; then
        rsync_dry_run_attempted=true
        empty_dir="$work_dir/empty"
        mkdir -m 0700 -- "$empty_dir"
        rsync_output="$work_dir/rsync.out"
        rsync_error="$work_dir/rsync.err"
        rsync_status=0
        remote_shell="ssh -6 -F /dev/null -b $node_a_ipv6"
        remote_shell+=" -i $private_key -o BatchMode=yes"
        remote_shell+=" -o ClearAllForwardings=yes"
        remote_shell+=" -o GlobalKnownHostsFile=/dev/null"
        remote_shell+=" -o HostKeyAlias=$node_b_fqdn"
        remote_shell+=" -o IdentitiesOnly=yes"
        remote_shell+=" -o KbdInteractiveAuthentication=no"
        remote_shell+=" -o PasswordAuthentication=no"
        remote_shell+=" -o PreferredAuthentications=publickey"
        remote_shell+=" -o StrictHostKeyChecking=yes"
        remote_shell+=" -o UpdateHostKeys=no"
        remote_shell+=" -o UserKnownHostsFile=$known_hosts"
        rsync \
            --archive \
            --dry-run \
            --itemize-changes \
            --rsh="$remote_shell" \
            "$empty_dir/" \
            "caddy-sync@$node_b_fqdn:/node-a/" \
            >"$rsync_output" 2>"$rsync_error" || rsync_status=$?
        record_command rsync_dry_run_status test "$rsync_status" -eq 0
        record_command rsync_dry_run_stdout_empty test ! -s "$rsync_output"
        record_command rsync_dry_run_stderr_empty test ! -s "$rsync_error"
    fi
fi

printf 'action_17o_value_transport_probe_attempted=%s\n' \
    "$transport_probe_attempted"
printf 'action_17o_value_direct_ssh_status=%s\n' "$probe_status"
printf 'action_17o_value_direct_ssh_error_class=%s\n' "$probe_error_class"
printf 'action_17o_value_rsync_dry_run_attempted=%s\n' \
    "$rsync_dry_run_attempted"
printf 'action_17o_value_rsync_dry_run_status=%s\n' "$rsync_status"

after_state="$work_dir/state-after"
after_state_error="$work_dir/state-after.err"
after_state_status=0
relevant_state >"$after_state" 2>"$after_state_error" ||
    after_state_status=$?
record_command after_state_status test "$after_state_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_state_error"
if [[ "$after_state_status" -eq 0 ]]; then
    after_state_sha256=$(file_hash "$after_state")
else
    after_state_sha256=unavailable
fi
readonly after_state_sha256
printf 'action_17o_value_after_state_sha256=%s\n' "$after_state_sha256"
record_command node_a_state_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"
record_command release_payload_not_transferred \
    test "$rsync_dry_run_attempted" = true
record_command persistent_configuration_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"
record_command synchronization_service_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive

printf 'action_17o_checks_total=%s\n' "$checks_total"
printf 'action_17o_checks_passed=%s\n' "$checks_passed"
printf 'action_17o_checks_failed=%s\n' "$checks_failed"
printf 'action_17o_first_failure=%s\n' "$first_failure"
printf 'action_17o_release_payload_transferred=false\n'
printf 'action_17o_synchronization_executed=false\n'
printf 'action_17o_service_mutations=false\n'
printf 'action_17o_persistent_mutations=false\n'

if [[ "$checks_failed" -eq 0 ]]; then
    printf 'action_17o_node_a_acceptance=true\n'
    exit 0
fi

printf 'action_17o_node_a_acceptance=false\n'
exit 1
