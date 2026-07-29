#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly expected_stage_inode=1670964
readonly expected_stage_device=66306
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c
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
readonly -a live_target_labels=(
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
    /var/lib/caddy-sync/.ssh/id_ed25519
    /var/lib/caddy-sync/.ssh/id_ed25519.pub
    /var/lib/caddy-sync/.ssh/known_hosts
    /var/lib/caddy-sync/.ssh/authorized_keys
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /etc/lsyncd/caddy.lua
)

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#expected_stage_files[@]}" -eq 5 ]]
    [[ "${#expected_stage_checksums[@]}" -eq 5 ]]
    [[ "${#live_target_labels[@]}" -eq 8 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    [[ "$expected_stage_inode" =~ ^[0-9]+$ ]]
    [[ "$expected_stage_device" =~ ^[0-9]+$ ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16ak_d_post_repair_continuity_self_test_complete=true\n'
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

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

printf 'action_16ak_d_remote_reached=true\n'
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
    "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh \
        2>/dev/null || true)" \
    caddy-sync:caddy-sync:700

record_command retained_stage_directory test -d "$retained_stage"
record_command retained_stage_not_symlink test ! -L "$retained_stage"
record_equal retained_stage_meta \
    "$(stat -c '%U:%G:%a' "$retained_stage" 2>/dev/null || true)" \
    root:root:750
record_equal retained_stage_inode \
    "$(stat -c '%i' "$retained_stage" 2>/dev/null || true)" \
    "$expected_stage_inode"
record_equal retained_stage_device \
    "$(stat -c '%d' "$retained_stage" 2>/dev/null || true)" \
    "$expected_stage_device"
record_equal retained_stage_parent_meta \
    "$(stat -c '%U:%G:%a' /var/tmp 2>/dev/null || true)" root:root:1777
record_equal retained_stage_symlink_count \
    "$(find "$retained_stage" -type l -print 2>/dev/null | wc -l)" 0
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

for index in "${!live_targets[@]}"; do
    record_absent "live_target_${live_target_labels[$index]}_absent" \
        "${live_targets[$index]}"
done
record_absent libexec_absent /usr/local/libexec

record_equal caddy_environment_hash \
    "$(sha256sum /etc/default/caddy-ha 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$environment_sha256"
record_command environment_node_role \
    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
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

record_equal caddy_active \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" inactive
record_equal caddy_enabled \
    "$(systemctl is-enabled caddy.service 2>/dev/null || true)" masked
record_equal lsyncd_active \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" inactive
record_equal lsyncd_enabled \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" masked
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
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    record_equal "${service//-/_}_active" \
        "$(systemctl is-active "$service" 2>/dev/null || true)" active
done
record_equal caddy_process_count "$(pgrep -xc caddy 2>/dev/null || true)" 0
record_equal lsyncd_process_count "$(pgrep -xc lsyncd 2>/dev/null || true)" 0

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
dpkg_audit_status=0
dpkg_audit=$(dpkg --audit 2>/dev/null) || dpkg_audit_status=$?
record_equal dpkg_audit_status "$dpkg_audit_status" 0
record_equal dpkg_audit_bytes "$(printf '%s' "$dpkg_audit" | wc -c)" 0

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
record_equal udp_443_listener_count \
    "$(ss -H -lunp 2>/dev/null |
        awk '$4 ~ /:443$/ { count++ } END { print count + 0 }')" 0

observed_package_inventory_sha256=$(
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' \
        2>/dev/null |
        sort |
        sha256sum |
        awk '{ print $1 }'
)
printf 'protected_package_inventory_sha256=%s\n' \
    "$observed_package_inventory_sha256"
record_equal protected_package_inventory \
    "$observed_package_inventory_sha256" "$package_inventory_sha256"
printf 'continuity_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'service_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_16ak_d_continuity_valid=true\n'
    printf 'action_16ak_d_read_only_inspection_complete=true\n'
    exit 0
fi
printf 'action_16ak_d_continuity_valid=false\n'
printf 'action_16ak_d_read_only_inspection_complete=true\n'
exit 1
