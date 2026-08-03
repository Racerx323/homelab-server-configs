#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18a
readonly ssh_directory=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_directory/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_directory/known_hosts"
readonly authorized_keys="$ssh_directory/authorized_keys"
readonly receiver_v1=/usr/local/libexec/caddy-sync-rsync-receiver
readonly receiver_v2=/usr/local/libexec/caddy-sync-release-receiver-v2
readonly finalizer_v2=/usr/local/libexec/finalize-incoming-release-v2.sh
readonly publisher_v2=/usr/local/libexec/publish-release-v2.sh
readonly lsyncd_configuration=/etc/lsyncd/caddy.lua
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly receiver_v1_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly receiver_v2_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_v2_sha256=15d85877c94c091af472988c4cb30ba99ad2d239714737fe52131d6cf2fa902d
readonly node_a_sync_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'
readonly node_a_host_fingerprint='SHA256:tuPVPiBenlqqCDmfqEFfQMpM0q90zj94QMGlNZNC1QI'
readonly node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly node_b_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for digest_value in "$payload_sha256" "$manifest_sha256" \
        "$receiver_v1_sha256" "$receiver_v2_sha256" "$finalizer_v2_sha256"; do
        [[ "$digest_value" =~ ^[0-9a-f]{64}$ ]] || exit 1
    done
    printf '%s_inspector_self_test_complete=true\n' "$action_prefix"
    exit 0
elif [[ $# -ne 2 || "$1" != --node || ! "$2" =~ ^node-[ab]$ ]]; then
    printf 'Usage: %s --node node-a|node-b\n' "${0##*/}" >&2
    exit 64
fi
readonly node_role=$2
readonly prefix="${action_prefix}_${node_role//-/_}"

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

key_fingerprint() {
    ssh-keygen -lf "$1" -E sha256 2>/dev/null | awk '{ print $2 }'
}

known_host_fingerprint() {
    local lookup_host=$1

    ssh-keygen -F "$lookup_host" -f "$known_hosts" 2>/dev/null |
        sed '/^#/d' |
        ssh-keygen -lf - -E sha256 2>/dev/null |
        awk 'NR == 1 { print $2 }'
}

payload_digest() {
    local payload_root=$1

    (
        cd "$payload_root" || exit 1
        find . -type f ! -name .complete -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

# Invoked indirectly through record_command.
# shellcheck disable=SC2317
ssh_option_exact() {
    local option_name=$1
    local option_value=$2
    local option_file=$3

    [[ "$(awk -v key="$option_name" '$1 == key { print $2 }' "$option_file")" == "$option_value" ]]
}

stable_state_snapshot() {
    stat -c '%n|%U:%G:%a:%s:%i' /etc/caddy/current \
        /var/lib/caddy-sync "$ssh_directory" "$private_key" "$public_key" \
        "$known_hosts" 2>/dev/null
    sha256sum "$public_key" "$known_hosts" 2>/dev/null
    if [[ -e "$authorized_keys" || -L "$authorized_keys" ]]; then
        stat -c '%n|%U:%G:%a:%s:%i' "$authorized_keys"
        sha256sum "$authorized_keys"
    fi
    for snapshot_unit in caddy.service lighttpd.service lsyncd.service \
        caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-sync-reconcile.service; do
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState -p FragmentPath
        printf '%s_enabled=%s\n' "$snapshot_unit" \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

work_directory=$(mktemp -d /tmp/caddy-action18a-inspector.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"
readonly ipv4_options="$work_directory/ipv4.options"
readonly ipv4_error="$work_directory/ipv4.err"
readonly ipv6_options="$work_directory/ipv6.options"
readonly ipv6_error="$work_directory/ipv6.err"

if [[ "$node_role" == node-a ]]; then
    readonly expected_hostname=j1-svpihole0
    readonly node_ipv4=10.1.0.53
    readonly node_ipv6=fd36:5aa8:6971:1::53
    readonly peer_ipv4=10.1.0.54
    readonly peer_ipv6=fd36:5aa8:6971:1::54
    readonly peer_fqdn=pihole00.local.theama.co
    readonly expected_sync_fingerprint="$node_a_sync_fingerprint"
    readonly expected_host_fingerprint="$node_b_host_fingerprint"
    readonly release=/var/lib/caddy-sync/outbound/action17p-node-a-to-node-b-bootstrap
else
    readonly expected_hostname=j1-svpihole00
    readonly node_ipv4=10.1.0.54
    readonly node_ipv6=fd36:5aa8:6971:1::54
    readonly peer_ipv4=10.1.0.53
    readonly peer_ipv6=fd36:5aa8:6971:1::53
    readonly peer_fqdn=pihole0.local.theama.co
    readonly expected_sync_fingerprint="$node_b_sync_fingerprint"
    readonly expected_host_fingerprint="$node_a_host_fingerprint"
    readonly release=/var/lib/caddy-sync/incoming/node-a/action17p-node-a-to-node-b-bootstrap
fi

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_exact test "$(hostname)" = "$expected_hostname"
record_command architecture_arm64 test "$(dpkg --print-architecture)" = arm64
record_command node_ipv4_present grep -Fq "$node_ipv4/22" \
    < <(ip -o -4 address show dev eth0)
record_command node_ipv6_present grep -Fq "$node_ipv6/64" \
    < <(ip -o -6 address show dev eth0)
record_command peer_hosts_ipv4_exact grep -Fxq "$peer_ipv4 $peer_fqdn" /etc/hosts
record_command peer_hosts_ipv6_exact grep -Fxq "$peer_ipv6 $peer_fqdn" /etc/hosts
record_command caddy_sync_home test \
    "$(getent passwd caddy-sync | cut -d: -f6)" = /var/lib/caddy-sync
record_command caddy_sync_shell test \
    "$(getent passwd caddy-sync | cut -d: -f7)" = /bin/sh
record_command caddy_sync_password_locked test \
    "$(passwd --status caddy-sync | awk '{ print $2 }')" = L
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_command private_key_metadata test \
    "$(stat -c '%U:%G:%a' "$private_key")" = caddy-sync:caddy-sync:600
record_command public_key_regular test -f "$public_key"
record_command public_key_not_symlink test ! -L "$public_key"
record_command public_key_metadata test \
    "$(stat -c '%U:%G:%a' "$public_key")" = caddy-sync:caddy-sync:644
record_command public_key_fingerprint_exact test \
    "$(key_fingerprint "$public_key")" = "$expected_sync_fingerprint"
record_command private_public_key_match test \
    "$(ssh-keygen -y -f "$private_key" | awk '{ print $1, $2 }')" = \
    "$(awk '{ print $1, $2 }' "$public_key")"
record_command known_hosts_regular test -f "$known_hosts"
record_command known_hosts_not_symlink test ! -L "$known_hosts"
record_command known_hosts_metadata test \
    "$(stat -c '%U:%G:%a' "$known_hosts")" = caddy-sync:caddy-sync:600
record_command known_hosts_single_line test "$(wc -l <"$known_hosts")" -eq 1
record_command peer_host_fingerprint_exact test \
    "$(known_host_fingerprint "$peer_fqdn")" = "$expected_host_fingerprint"
record_command release_directory test -d "$release"
record_command release_not_symlink test ! -L "$release"
record_command release_revision_exact test \
    "$(jq -r '.revision // empty' "$release/release-manifest.json")" = "$revision"
record_command release_parent_exact test \
    "$(jq -r '.parent_revision // empty' "$release/release-manifest.json")" = \
    "$parent_revision"
record_command release_source_node_a test \
    "$(jq -r '.source_node // empty' "$release/release-manifest.json")" = node-a
record_command release_payload_hash_exact test \
    "$(payload_digest "$release")" = "$payload_sha256"
record_command release_manifest_hash_exact test \
    "$(file_hash "$release/manifest.sha256")" = "$manifest_sha256"
record_command caddy_active test "$(systemctl is-active caddy.service)" = active
record_command lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
record_command lsyncd_inactive test \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked test \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = inactive
record_command reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = inactive
record_command lsyncd_configuration_absent test ! -e "$lsyncd_configuration"
record_command lsyncd_configuration_not_symlink test ! -L "$lsyncd_configuration"

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256

ipv4_status=0
runuser -u caddy-sync -- ssh -G -T -F /dev/null -4 -b "$node_ipv4" \
    -i "$private_key" -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv4_options" 2>"$ipv4_error" || ipv4_status=$?
readonly ipv4_status
record_command ipv4_ssh_g_status_zero test "$ipv4_status" -eq 0
record_command ipv4_ssh_g_stderr_empty test ! -s "$ipv4_error"
record_command ipv4_address_family_exact ssh_option_exact \
    addressfamily inet "$ipv4_options"
record_command ipv4_bind_address_exact ssh_option_exact \
    bindaddress "$node_ipv4" "$ipv4_options"
record_command ipv4_identity_file_exact ssh_option_exact \
    identityfile "$private_key" "$ipv4_options"
record_command ipv4_identities_only_yes ssh_option_exact \
    identitiesonly yes "$ipv4_options"

ipv6_status=0
runuser -u caddy-sync -- ssh -G -T -F /dev/null -6 -b "$node_ipv6" \
    -i "$private_key" -o BatchMode=yes -o ClearAllForwardings=yes \
    -o "HostKeyAlias=$peer_fqdn" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
    "caddy-sync@$peer_fqdn" >"$ipv6_options" 2>"$ipv6_error" || ipv6_status=$?
readonly ipv6_status
record_command ipv6_ssh_g_status_zero test "$ipv6_status" -eq 0
record_command ipv6_ssh_g_stderr_empty test ! -s "$ipv6_error"
record_command ipv6_address_family_exact ssh_option_exact \
    addressfamily inet6 "$ipv6_options"
record_command ipv6_bind_address_exact ssh_option_exact \
    bindaddress "$node_ipv6" "$ipv6_options"
record_command ipv6_identity_file_exact ssh_option_exact \
    identityfile "$private_key" "$ipv6_options"
record_command ipv6_identities_only_yes ssh_option_exact \
    identitiesonly yes "$ipv6_options"

if [[ "$node_role" == node-a ]]; then
    expected_authorization="from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-release-receiver-v2 --source-role node-b\" $node_b_public_key"
    record_command receiver_v2_regular test -f "$receiver_v2"
    record_command receiver_v2_not_symlink test ! -L "$receiver_v2"
    record_command receiver_v2_hash_exact test \
        "$(file_hash "$receiver_v2")" = "$receiver_v2_sha256"
    record_command legacy_receiver_v1_regular test -f "$receiver_v1"
    record_command legacy_receiver_v1_hash_exact test \
        "$(file_hash "$receiver_v1")" = "$receiver_v1_sha256"
    record_command finalizer_v2_regular test -f "$finalizer_v2"
    record_command finalizer_v2_not_symlink test ! -L "$finalizer_v2"
    record_command finalizer_v2_hash_exact test \
        "$(file_hash "$finalizer_v2")" = "$finalizer_v2_sha256"
    record_command authorization_v2_exact test \
        "$(<"$authorized_keys")" = "$expected_authorization"
    record_command authorization_single_line test \
        "$(wc -l <"$authorized_keys")" -eq 1
    record_command incoming_node_b_absent test ! -e /var/lib/caddy-sync/incoming/node-b
    record_command incoming_node_b_not_symlink test ! -L /var/lib/caddy-sync/incoming/node-b
else
    record_command publisher_v2_regular test -f "$publisher_v2"
    record_command publisher_v2_not_symlink test ! -L "$publisher_v2"
    record_command publisher_v2_syntax bash -n "$publisher_v2"
    record_command publisher_requires_emergency grep -Fq \
        'Node B publishing requires --emergency.' "$publisher_v2"
    record_command publisher_requires_master grep -Fq \
        'Node B may publish only while CADDY_DUALSTACK is MASTER.' "$publisher_v2"
    # The child shell must evaluate the live state path itself.
    # shellcheck disable=SC2016
    record_command emergency_publish_inhibited bash -c \
        '[[ ! -r /run/caddy-ha/vrrp-state || "$(</run/caddy-ha/vrrp-state)" != MASTER ]]'
    record_command receiver_v2_regular test -f "$receiver_v2"
    record_command receiver_v2_hash_exact test \
        "$(file_hash "$receiver_v2")" = "$receiver_v2_sha256"
    record_command finalizer_v2_regular test -f "$finalizer_v2"
    record_command finalizer_v2_hash_exact test \
        "$(file_hash "$finalizer_v2")" = "$finalizer_v2_sha256"
    record_command request_marker_regular test -f "$release/.finalize-request"
    record_command request_marker_empty test ! -s "$release/.finalize-request"
    record_command completion_marker_regular test -f "$release/.complete"
    record_command completion_marker_empty test ! -s "$release/.complete"
    record_command pending_marker_absent test ! -e "$release/.complete.pending"
    record_command outbound_node_b_payload_absent test \
        -z "$(find /var/lib/caddy-sync/outbound -mindepth 1 -maxdepth 1 -print -quit)"
fi

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"

printf '%s_value_revision=%s\n' "$prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$prefix" "$parent_revision"
printf '%s_value_payload_sha256=%s\n' "$prefix" "$payload_sha256"
printf '%s_value_manifest_sha256=%s\n' "$prefix" "$manifest_sha256"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_peer_connection_executed=false\n' "$prefix"
printf '%s_restricted_command_executed=false\n' "$prefix"
printf '%s_release_transfer_executed=false\n' "$prefix"
printf '%s_finalizer_invoked=false\n' "$prefix"
printf '%s_lsyncd_enabled=false\n' "$prefix"
printf '%s_reconciliation_enabled=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_assertion_count" -eq 0 ]]; then
    exit 0
fi
exit 1
