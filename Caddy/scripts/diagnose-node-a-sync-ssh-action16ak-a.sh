#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly public_key="$private_key.pub"
readonly known_hosts="$ssh_dir/known_hosts"
readonly authorized_keys="$ssh_dir/authorized_keys"
readonly libexec=/usr/local/libexec
readonly receiver="$libexec/caddy-sync-rsync-receiver"
readonly setup_helper="$libexec/setup-sync-ssh.sh"
readonly validator="$libexec/validate-sync-ssh.sh"
readonly lsyncd_config=/etc/lsyncd/caddy.lua

readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly expected_node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

readonly -a expected_stage_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_stage_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
)
readonly -a target_labels=(
    private_key
    public_key
    known_hosts
    authorized_keys
    receiver
    setup_helper
    validator
    lsyncd_config
)
readonly -a live_targets=(
    "$private_key"
    "$public_key"
    "$known_hosts"
    "$authorized_keys"
    "$receiver"
    "$setup_helper"
    "$validator"
    "$lsyncd_config"
)

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_stage_files[@]}" -eq 5 ]]
    [[ "${#expected_stage_checksums[@]}" -eq 5 ]]
    [[ "${#target_labels[@]}" -eq 8 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    [[ "$retained_stage" == /var/tmp/caddy-sync-ssh-node-a-action16aj-e ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16ak_a_sync_ssh_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

set +e
mismatch_count=0
first_failure=none

record_result() {
    local label=$1
    local matched=$2

    if [[ "$matched" != true ]]; then
        mismatch_count=$((mismatch_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$label
        fi
    fi
    printf '%s=%s\n' "$label" "$matched"
}

record_equal() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" == "$expected" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_command() {
    local label=$1
    shift

    if "$@" >/dev/null 2>&1; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_absent() {
    local label=$1
    local target=$2

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

observe_boolean() {
    local label=$1
    local value=$2

    printf '%s=%s\n' "$label" "$value"
}

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

target_state() {
    local label=$1
    local target=$2
    local state=absent
    local owner_mode=absent

    if [[ -L "$target" ]]; then
        state=symlink
        owner_mode=$(stat -c '%U:%G:%a' "$target" 2>/dev/null || true)
    elif [[ -f "$target" ]]; then
        state=regular
        owner_mode=$(stat -c '%U:%G:%a' "$target" 2>/dev/null || true)
    elif [[ -d "$target" ]]; then
        state=directory
        owner_mode=$(stat -c '%U:%G:%a' "$target" 2>/dev/null || true)
    elif [[ -e "$target" ]]; then
        state=other
        owner_mode=$(stat -c '%U:%G:%a' "$target" 2>/dev/null || true)
    fi

    printf 'live_target_%s_state=%s\n' "$label" "$state"
    printf 'live_target_%s_owner_mode=%s\n' "$label" "$owner_mode"
}

printf 'action_16ak_a_remote_reached=true\n'

# Action 16ak validate_accepted_state(), preserved in its original order.
record_equal root_effective_uid "$(id -u 2>/dev/null || true)" 0
record_equal node_hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
record_command node_ipv4_present \
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0 2>/dev/null)
record_equal node_architecture \
    "$(dpkg --print-architecture 2>/dev/null || true)" arm64
record_equal caddy_package \
    "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy 2>/dev/null || true)" \
    'ii :2.11.4:arm64'
record_equal lsyncd_package \
    "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' lsyncd 2>/dev/null || true)" \
    'ii :2.2.3-1:arm64'
record_equal rsync_version \
    "$(dpkg-query -W -f='${Version}' rsync 2>/dev/null || true)" \
    '3.2.7-1+deb12u6'
record_equal openssh_server_version \
    "$(dpkg-query -W -f='${Version}' openssh-server 2>/dev/null || true)" \
    '1:9.2p1-2+deb12u10'
record_equal caddy_sync_home \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f6 || true)" \
    /var/lib/caddy-sync
record_equal caddy_sync_shell \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f7 || true)" /bin/sh
record_equal caddy_sync_password_state \
    "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }' || true)" L
record_equal caddy_sync_ssh_dir_meta \
    "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:700
record_equal caddy_environment_hash \
    "$(sha256sum /etc/default/caddy-ha 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$environment_sha256"
record_command environment_node_role \
    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
record_command environment_peer_ipv4 \
    grep -Fxq 'PEER_IPV4=10.1.0.54' /etc/default/caddy-ha
record_command environment_peer_ipv6 \
    grep -Fxq 'PEER_IPV6=fd36:5aa8:6971:1::54' /etc/default/caddy-ha
record_command environment_sync_target \
    grep -Fxq 'SYNC_TARGET=pihole00.local.theama.co' /etc/default/caddy-ha
record_equal caddy_current_target \
    "$(readlink /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
record_equal caddy_current_resolved \
    "$(readlink -e /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
record_equal live_lighttpd_tree_hash \
    "$(tree_hash /etc/lighttpd 2>/dev/null || true)" \
    "$live_lighttpd_sha256"
record_equal candidate_lighttpd_tree_hash \
    "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab \
        2>/dev/null || true)" \
    "$candidate_lighttpd_sha256"
record_equal keepalived_hash \
    "$(sha256sum /etc/keepalived/keepalived.conf 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$keepalived_sha256"
record_equal sysctl_file_hash \
    "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$sysctl_sha256"
record_equal ipv4_nonlocal_bind \
    "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null || true)" 1
record_equal ipv6_nonlocal_bind \
    "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" 1
dpkg_audit_status=0
dpkg_audit=$(dpkg --audit 2>/dev/null) || dpkg_audit_status=$?
record_equal dpkg_audit_status "$dpkg_audit_status" 0
record_equal dpkg_audit_bytes "$(printf '%s' "$dpkg_audit" | wc -c)" 0
record_equal caddy_active \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" inactive
record_equal caddy_enabled \
    "$(systemctl is-enabled caddy.service 2>/dev/null || true)" masked
record_equal lsyncd_active \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" inactive
record_equal lsyncd_enabled \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" masked
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    record_equal "${service//-/_}_active" \
        "$(systemctl is-active "$service" 2>/dev/null || true)" active
done
record_equal caddy_process_count "$(pgrep -xc caddy 2>/dev/null || true)" 0
record_equal lsyncd_process_count "$(pgrep -xc lsyncd 2>/dev/null || true)" 0

# Action 16ak validate_stage(), preserved in its original order.
record_command retained_stage_directory \
    test -d "$retained_stage"
record_command retained_stage_not_symlink \
    test ! -L "$retained_stage"
record_equal retained_stage_meta \
    "$(stat -c '%U:%G:%a' "$retained_stage" 2>/dev/null || true)" \
    root:root:750
stage_symlink_count=$(
    find "$retained_stage" -type l -print 2>/dev/null |
        wc -l
)
record_equal retained_stage_symlink_count "$stage_symlink_count" 0
mapfile -t actual_stage_files < <(
    find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\n' 2>/dev/null |
        sort
)
record_equal retained_stage_file_set \
    "${actual_stage_files[*]}" "${expected_stage_files[*]}"

for checksum in "${expected_stage_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    label=${relative_path//[^A-Za-z0-9]/_}
    case "$relative_path" in
        *.sh | caddy-sync-rsync-receiver)
            expected_mode=750
            ;;
        *)
            expected_mode=640
            ;;
    esac
    record_command "stage_${label}_regular" \
        test -f "$retained_stage/$relative_path"
    record_command "stage_${label}_not_symlink" \
        test ! -L "$retained_stage/$relative_path"
    record_equal "stage_${label}_hash" \
        "$(sha256sum "$retained_stage/$relative_path" 2>/dev/null |
            awk '{ print $1 }' || true)" \
        "$expected_hash"
    record_equal "stage_${label}_meta" \
        "$(stat -c '%U:%G:%a' "$retained_stage/$relative_path" \
            2>/dev/null || true)" \
        "root:root:$expected_mode"
done

record_equal node_b_host_fingerprint \
    "$(ssh-keygen -lf "$retained_stage/node-b-host-ed25519.pub" \
        -E sha256 2>/dev/null | awk '{ print $2 }' || true)" \
    "$expected_node_b_host_fingerprint"
record_equal node_b_sync_fingerprint \
    "$(ssh-keygen -lf "$retained_stage/node-b-sync-ed25519.pub" \
        -E sha256 2>/dev/null | awk '{ print $2 }' || true)" \
    "$expected_node_b_sync_fingerprint"
record_equal node_b_host_key_line_count \
    "$(wc -l <"$retained_stage/node-b-host-ed25519.pub" 2>/dev/null || true)" 1
record_equal node_b_sync_key_line_count \
    "$(wc -l <"$retained_stage/node-b-sync-ed25519.pub" 2>/dev/null || true)" 1
record_command node_b_host_key_type \
    grep -Eq '^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$' \
    "$retained_stage/node-b-host-ed25519.pub"
record_command node_b_sync_key_type \
    grep -Eq '^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$' \
    "$retained_stage/node-b-sync-ed25519.pub"

# Action 16ak validate_targets_absent(), with every target characterized.
for index in "${!live_targets[@]}"; do
    record_absent "live_target_${target_labels[$index]}_absent" \
        "${live_targets[$index]}"
    target_state "${target_labels[$index]}" "${live_targets[$index]}"
done

# Action 16ak validate_libexec_prestate().
libexec_prestate_valid=false
if [[ ! -e "$libexec" && ! -L "$libexec" ]]; then
    libexec_prestate_valid=true
    printf 'libexec_state=absent\n'
    printf 'libexec_owner_mode=absent\n'
elif [[ -d "$libexec" && ! -L "$libexec" ]] &&
    [[ "$(stat -c '%U:%G:%a' "$libexec" 2>/dev/null || true)" == root:root:755 ]]; then
    libexec_prestate_valid=true
    printf 'libexec_state=directory\n'
    printf 'libexec_owner_mode=root:root:755\n'
else
    printf 'libexec_state=unexpected\n'
    printf 'libexec_owner_mode=%s\n' \
        "$(stat -c '%U:%G:%a' "$libexec" 2>/dev/null || true)"
fi
record_result libexec_prestate_valid "$libexec_prestate_valid"

# Additional protected-state continuity checks.
record_equal caddy_api_active \
    "$(systemctl is-active caddy-api.service 2>/dev/null || true)" inactive
record_equal caddy_api_enabled \
    "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" masked
record_equal uuidd_active \
    "$(systemctl is-active uuidd.service 2>/dev/null || true)" inactive
record_equal uuidd_enabled \
    "$(systemctl is-enabled uuidd.service 2>/dev/null || true)" masked
record_equal uuidd_socket_active \
    "$(systemctl is-active uuidd.socket 2>/dev/null || true)" inactive
record_equal uuidd_socket_enabled \
    "$(systemctl is-enabled uuidd.socket 2>/dev/null || true)" masked
record_command source_stage_present \
    test -d /var/tmp/caddy-source-node-a-action16af
record_command certificate_stage_present \
    test -d /var/tmp/caddy-cert-node-a-action16ae
record_command installed_certificate_matches_stage \
    cmp --silent \
    /var/tmp/caddy-cert-node-a-action16ae/privkey.pem \
    /etc/caddy/releases/bootstrap/tls/privkey.pem
record_command rollback_baseline_valid \
    bash -c '
        cd /var/backups/caddy-ha/predeploy-node-a-20260728T184626Z &&
        sha256sum --check --status configuration.tar.sha256 &&
        grep -Fxq "backup_complete=true" backup-manifest.txt
    '
tcp_frontend=$(
    ss -H -ltnp 2>/dev/null |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
record_command tcp_frontend_present test -n "$tcp_frontend"
tcp_frontend_lighttpd_only=true
if [[ -n "$tcp_frontend" ]] &&
    grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend" >/dev/null; then
    tcp_frontend_lighttpd_only=false
fi
record_result tcp_frontend_lighttpd_only "$tcp_frontend_lighttpd_only"
udp_443_listener_count=$(
    ss -H -lunp 2>/dev/null |
        awk '$4 ~ /:443$/ { count++ } END { print count + 0 }'
)
record_equal udp_443_listener_count "$udp_443_listener_count" 0
package_inventory_sha256=$(
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' \
        2>/dev/null |
        sort |
        sha256sum |
        awk '{ print $1 }'
)
printf 'protected_package_inventory_sha256=%s\n' \
    "$package_inventory_sha256"

# Characterize a possible complete installation without exposing key material.
installed_shape_valid=false
node_a_public_fingerprint=unavailable
if [[ -f "$private_key" && ! -L "$private_key" &&
    -f "$public_key" && ! -L "$public_key" &&
    -f "$known_hosts" && ! -L "$known_hosts" &&
    -f "$authorized_keys" && ! -L "$authorized_keys" &&
    -f "$receiver" && ! -L "$receiver" &&
    -f "$setup_helper" && ! -L "$setup_helper" &&
    -f "$validator" && ! -L "$validator" ]]; then
    node_b_host_key=$(awk '{ print $1, $2 }' \
        "$retained_stage/node-b-host-ed25519.pub" 2>/dev/null)
    node_b_sync_key=$(<"$retained_stage/node-b-sync-ed25519.pub")
    expected_authorization="from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_b_sync_key"
    derived_public=$(ssh-keygen -y -f "$private_key" 2>/dev/null |
        awk '{ print $1, $2 }')
    recorded_public=$(awk '{ print $1, $2 }' "$public_key" 2>/dev/null)
    if [[ "$(stat -c '%U:%G:%a' "$private_key")" == caddy-sync:caddy-sync:600 &&
    "$(stat -c '%U:%G:%a' "$public_key")" == caddy-sync:caddy-sync:644 &&
    "$(stat -c '%U:%G:%a' "$known_hosts")" == caddy-sync:caddy-sync:600 &&
    "$(stat -c '%U:%G:%a' "$authorized_keys")" == caddy-sync:caddy-sync:600 &&
    "$(stat -c '%U:%G:%a' "$receiver")" == root:root:755 &&
    "$(stat -c '%U:%G:%a' "$setup_helper")" == root:root:755 &&
    "$(stat -c '%U:%G:%a' "$validator")" == root:root:755 &&
    "$derived_public" == "$recorded_public" &&
    "$(<"$known_hosts")" == "pihole00.local.theama.co $node_b_host_key" &&
    "$(<"$authorized_keys")" == "$expected_authorization" &&
    "$(sha256sum "$receiver" | awk '{ print $1 }')" == 65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134 &&
    "$(sha256sum "$setup_helper" | awk '{ print $1 }')" == d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140 &&
    "$(sha256sum "$validator" | awk '{ print $1 }')" == 85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072 &&
    ! -e "$lsyncd_config" && ! -L "$lsyncd_config" ]]; then
        installed_shape_valid=true
        node_a_public_fingerprint=$(
            ssh-keygen -lf "$public_key" -E sha256 2>/dev/null |
                awk '{ print $2 }'
        )
    fi
fi
observe_boolean installed_shape_valid "$installed_shape_valid"
printf 'node_a_public_fingerprint=%s\n' "$node_a_public_fingerprint"

preflight_would_pass=false
if [[ "$mismatch_count" -eq 0 ]]; then
    preflight_would_pass=true
fi
printf 'diagnostic_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'action_16ak_preflight_would_pass=%s\n' "$preflight_would_pass"
printf 'action_16ak_a_read_only_inspection_complete=true\n'

if [[ "$preflight_would_pass" == true ]]; then
    exit 0
fi
exit 1
