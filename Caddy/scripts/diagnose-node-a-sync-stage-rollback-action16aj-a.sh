#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-sync-ssh-node-a-action16aj
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly node_b_host_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDsoJtJAFw7LCD85Jwfen/kzYhH13I5NuvkmgIy1jmyJ root@(none)'
readonly node_b_sync_public_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e caddy-ha-sync'
readonly expected_node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

if [[ "${1:-}" == --self-test ]]; then
    [[ "$environment_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16aj_a_rollback_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

set +e
mismatch_count=0

record_equal() {
    local label=$1
    local observed=$2
    local expected=$3
    local match=false

    if [[ "$observed" == "$expected" ]]; then
        match=true
    else
        mismatch_count=$((mismatch_count + 1))
    fi
    printf '%s_observed=%s\n' "$label" "$observed"
    printf '%s_expected=%s\n' "$label" "$expected"
    printf '%s_match=%s\n' "$label" "$match"
}

record_command() {
    local label=$1
    shift
    local match=false

    if "$@" >/dev/null 2>&1; then
        match=true
    else
        mismatch_count=$((mismatch_count + 1))
    fi
    printf '%s=%s\n' "$label" "$match"
}

record_absent() {
    local label=$1
    local target=$2
    local match=false

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        match=true
    else
        mismatch_count=$((mismatch_count + 1))
    fi
    printf '%s=%s\n' "$label" "$match"
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

record_equal node_hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
record_command node_ipv4_present \
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
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
    "$(getent passwd caddy-sync | cut -d: -f6)" /var/lib/caddy-sync
record_equal caddy_sync_shell \
    "$(getent passwd caddy-sync | cut -d: -f7)" /bin/sh
record_equal caddy_sync_password_state \
    "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }')" L
record_equal caddy_sync_ssh_dir_meta \
    "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh 2>/dev/null || true)" \
    caddy-sync:caddy-sync:700

record_absent stage_absent "$stage"
staging_count=$(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name 'caddy-sync-ssh-node-a-action16aj*' -print 2>/dev/null |
        wc -l
)
record_equal action_staging_count "$staging_count" 0

live_targets=(
    /var/lib/caddy-sync/.ssh/id_ed25519
    /var/lib/caddy-sync/.ssh/id_ed25519.pub
    /var/lib/caddy-sync/.ssh/known_hosts
    /var/lib/caddy-sync/.ssh/authorized_keys
    /usr/local/libexec/caddy-sync-rsync-receiver
    /usr/local/libexec/setup-sync-ssh.sh
    /usr/local/libexec/validate-sync-ssh.sh
    /etc/lsyncd/caddy.lua
)
for target in "${live_targets[@]}"; do
    label=${target//[^A-Za-z0-9]/_}
    record_absent "live_target${label}_absent" "$target"
done

record_equal caddy_environment_hash \
    "$(sha256sum /etc/default/caddy-ha 2>/dev/null | awk '{ print $1 }')" \
    "$environment_sha256"
record_equal caddy_current_target \
    "$(readlink /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
record_equal caddy_current_resolved \
    "$(readlink -e /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
record_equal caddy_release_meta \
    "$(stat -c '%U:%G:%a' /etc/caddy/releases/bootstrap 2>/dev/null || true)" \
    root:caddy-tls:750

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

record_equal live_lighttpd_tree_hash \
    "$(tree_hash /etc/lighttpd 2>/dev/null || true)" \
    "$live_lighttpd_sha256"
record_equal candidate_lighttpd_tree_hash \
    "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab 2>/dev/null || true)" \
    "$candidate_lighttpd_sha256"
record_equal keepalived_hash \
    "$(sha256sum /etc/keepalived/keepalived.conf 2>/dev/null |
        awk '{ print $1 }')" \
    "$keepalived_sha256"
record_equal sysctl_file_hash \
    "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null |
        awk '{ print $1 }')" \
    "$sysctl_sha256"
record_equal ipv4_nonlocal_bind \
    "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null || true)" 1
record_equal ipv6_nonlocal_bind \
    "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" 1

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
record_equal dpkg_audit_bytes "$(dpkg --audit 2>/dev/null | wc -c)" 0

record_equal tar_path "$(command -v tar 2>/dev/null || true)" /usr/bin/tar
record_equal install_path \
    "$(command -v install 2>/dev/null || true)" /usr/bin/install
record_equal ssh_keygen_path \
    "$(command -v ssh-keygen 2>/dev/null || true)" /usr/bin/ssh-keygen
record_command tar_no_same_owner_supported \
    grep -Fq -- '--no-same-owner' < <(tar --help)
record_command tar_no_same_permissions_supported \
    grep -Fq -- '--no-same-permissions' < <(tar --help)

node_b_host_fingerprint=$(
    ssh-keygen -lf <(printf '%s\n' "$node_b_host_public_key") -E sha256 \
        2>/dev/null |
        awk '{ print $2 }'
)
node_b_sync_fingerprint=$(
    ssh-keygen -lf <(printf '%s\n' "$node_b_sync_public_key") -E sha256 \
        2>/dev/null |
        awk '{ print $2 }'
)
record_equal node_b_host_key_parse \
    "$node_b_host_fingerprint" "$expected_node_b_host_fingerprint"
record_equal node_b_sync_key_parse \
    "$node_b_sync_fingerprint" "$expected_node_b_sync_fingerprint"

tcp_frontend=$(
    ss -H -ltnp 2>/dev/null |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
record_command tcp_frontend_present test -n "$tcp_frontend"
if [[ -n "$tcp_frontend" ]] &&
    grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend" >/dev/null; then
    mismatch_count=$((mismatch_count + 1))
    printf 'tcp_frontend_lighttpd_only=false\n'
else
    printf 'tcp_frontend_lighttpd_only=true\n'
fi
udp_443=$(
    ss -H -lunp 2>/dev/null |
        awk '$4 ~ /:443$/ { print }' |
        sort
)
record_equal udp_443_listener_count \
    "$(grep -c . <<<"$udp_443")" 0

rollback_state_valid=false
if [[ "$mismatch_count" -eq 0 ]]; then
    rollback_state_valid=true
fi
printf 'diagnostic_mismatch_count=%s\n' "$mismatch_count"
printf 'rollback_state_valid=%s\n' "$rollback_state_valid"
printf 'action_16aj_a_rollback_diagnostic_complete=true\n'
