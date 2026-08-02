#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly original_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj
readonly failed_diagnostic_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-b
readonly transient_diagnostic_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-d
readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly expected_node_b_host_fingerprint='SHA256:eDdqL/bS/EuVysKQ7yxJ6lpjJWf2PcymtfPwMlzacbo'
readonly expected_node_b_sync_fingerprint='SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g'

readonly -a expected_files=(
    caddy-sync-rsync-receiver
    node-b-host-ed25519.pub
    node-b-sync-ed25519.pub
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)
readonly -a expected_checksums=(
    '65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134  caddy-sync-rsync-receiver'
    '909ee3ca843757d8d956ac6d442d6079134b0235fa7d37c97d80590eb5870fbd  node-b-host-ed25519.pub'
    'c9a2ecfcc6a44c0cd30d06bbb2841ec50ffd11866ce1da77ff69f2b5ff8320b0  node-b-sync-ed25519.pub'
    'd1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140  setup-sync-ssh.sh'
    '85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072  validate-sync-ssh.sh'
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

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_files[@]}" -eq 5 ]]
    [[ "${#expected_checksums[@]}" -eq 5 ]]
    [[ "${#live_targets[@]}" -eq 8 ]]
    [[ "$environment_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16aj_e_retained_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

validate_live_state() {
    local service target
    local valid=true

    [[ "$(hostname 2>/dev/null || true)" == j1-svpihole0 ]] || valid=false
    grep -Fq '10.1.0.53/22' \
        < <(ip -o -4 address show dev eth0 2>/dev/null) || valid=false
    [[ "$(dpkg --print-architecture 2>/dev/null || true)" == arm64 ]] ||
        valid=false
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy 2>/dev/null || true)" == 'ii :2.11.4:arm64' ]] ||
        valid=false
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' lsyncd 2>/dev/null || true)" == 'ii :2.2.3-1:arm64' ]] ||
        valid=false
    [[ "$(dpkg-query -W -f='${Version}' rsync 2>/dev/null || true)" == '3.2.7-1+deb12u6' ]] ||
        valid=false
    [[ "$(dpkg-query -W -f='${Version}' openssh-server 2>/dev/null || true)" == '1:9.2p1-2+deb12u10' ]] ||
        valid=false
    [[ "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f6 || true)" == /var/lib/caddy-sync ]] ||
        valid=false
    [[ "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f7 || true)" == /bin/sh ]] ||
        valid=false
    [[ "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }' || true)" == L ]] ||
        valid=false
    [[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh 2>/dev/null || true)" == caddy-sync:caddy-sync:700 ]] ||
        valid=false
    [[ "$(sha256sum /etc/default/caddy-ha 2>/dev/null |
        awk '{ print $1 }' || true)" == "$environment_sha256" ]] ||
        valid=false
    [[ "$(readlink /etc/caddy/current 2>/dev/null || true)" == /etc/caddy/releases/bootstrap ]] ||
        valid=false
    [[ "$(readlink -e /etc/caddy/current 2>/dev/null || true)" == /etc/caddy/releases/bootstrap ]] ||
        valid=false

    for target in "${live_targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]] || valid=false
    done

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]] ||
        valid=false
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]] ||
        valid=false
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]] ||
        valid=false
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]] ||
        valid=false
    for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
        systemctl is-active --quiet "$service" 2>/dev/null || valid=false
    done

    [[ "$(tree_hash /etc/lighttpd 2>/dev/null || true)" == "$live_lighttpd_sha256" ]] ||
        valid=false
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab 2>/dev/null || true)" == "$candidate_lighttpd_sha256" ]] ||
        valid=false
    [[ "$(sha256sum /etc/keepalived/keepalived.conf 2>/dev/null |
        awk '{ print $1 }' || true)" == "$keepalived_sha256" ]] ||
        valid=false
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null |
        awk '{ print $1 }' || true)" == "$sysctl_sha256" ]] ||
        valid=false
    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null || true)" == 1 ]] ||
        valid=false
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" == 1 ]] ||
        valid=false
    [[ -z "$(dpkg --audit 2>/dev/null || true)" ]] || valid=false

    [[ "$valid" == true ]]
}

protected_state() {
    local service

    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' \
        2>/dev/null | sort || printf 'package_inventory_unavailable\n'
    id caddy 2>/dev/null || printf 'caddy_identity_unavailable\n'
    id caddy-sync 2>/dev/null || printf 'caddy_sync_identity_unavailable\n'
    id keepalived_script 2>/dev/null ||
        printf 'keepalived_script_identity_unavailable\n'
    passwd --status caddy-sync 2>/dev/null ||
        printf 'caddy_sync_password_state_unavailable\n'
    passwd --status keepalived_script 2>/dev/null ||
        printf 'keepalived_script_password_state_unavailable\n'
    getent group caddy-tls 2>/dev/null ||
        printf 'caddy_tls_group_unavailable\n'
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh 2>/dev/null ||
        printf 'identity_path_state_unavailable\n'

    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            2>/dev/null || printf 'show_unavailable\n'
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done

    ss -H -lntup 2>/dev/null | sort || printf 'listeners_unavailable\n'
    for root in \
        /etc/caddy/releases/bootstrap \
        /var/tmp/caddy-source-node-a-action16af \
        /var/tmp/caddy-cert-node-a-action16ae \
        /var/lib/caddy /var/log/caddy; do
        find "$root" -printf '%P|%y|%U:%G:%m:%s:%Y:%i\n' 2>/dev/null |
            sort || printf 'tree_metadata_unavailable\n'
        find "$root" -type f -print0 2>/dev/null |
            sort -z |
            xargs -0 -r sha256sum 2>/dev/null ||
            printf 'tree_hashes_unavailable\n'
    done
    find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%Y:%i\n' 2>/dev/null |
        sort || printf 'backup_state_unavailable\n'
    sha256sum \
        /etc/default/caddy-ha \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /var/tmp/caddy-ha-lighttpd-node-a-action16ab/lighttpd.conf \
        /etc/keepalived/keepalived.conf \
        /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null ||
        printf 'configuration_hashes_unavailable\n'
    /usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null ||
        printf 'ipv4_nonlocal_bind_unavailable\n'
    /usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null ||
        printf 'ipv6_nonlocal_bind_unavailable\n'
    dpkg --audit 2>/dev/null || printf 'dpkg_audit_unavailable\n'
}

fail_before_write() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    printf 'action_16aj_e_preflight_valid=false\n'
    exit 1
}

require_preflight_command() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        fail_before_write "$label"
    fi
    printf '%s=true\n' "$label"
}

require_preflight_absent() {
    local label=$1
    local target=$2

    if [[ -e "$target" || -L "$target" ]]; then
        fail_before_write "$label"
    fi
    printf '%s=true\n' "$label"
}

printf 'action_16aj_e_remote_reached=true\n'
require_preflight_command preflight_live_state validate_live_state
require_preflight_absent preflight_original_stage_absent "$original_stage"
require_preflight_absent preflight_failed_diagnostic_stage_absent \
    "$failed_diagnostic_stage"
require_preflight_absent preflight_transient_diagnostic_stage_absent \
    "$transient_diagnostic_stage"
require_preflight_absent preflight_retained_stage_absent "$retained_stage"
staging_count=$(
    find /var/tmp -mindepth 1 -maxdepth 1 \
        -name 'caddy-sync-ssh-node-a-action16aj*' -print 2>/dev/null |
        wc -l
)
if [[ "$staging_count" != 0 ]]; then
    fail_before_write preflight_action_staging_count_zero
fi
printf 'preflight_action_staging_count_zero=true\n'

protected_before=$(protected_state)
readonly protected_before
if [[ -z "$protected_before" ]]; then
    fail_before_write preflight_protected_state_capture
fi
printf 'preflight_protected_state_capture=true\n'
printf 'action_16aj_e_preflight_valid=true\n'

success=false
stage_mutation_started=false
rollback() {
    local original_rc=$?
    local rollback_valid=true

    if [[ "$success" == true ]]; then
        return
    fi

    set +e
    if [[ "$stage_mutation_started" == true ]]; then
        rm -rf -- "$retained_stage"
    fi
    if [[ -e "$retained_stage" || -L "$retained_stage" ]]; then
        rollback_valid=false
    fi
    validate_live_state || rollback_valid=false
    [[ "$(protected_state)" == "$protected_before" ]] || rollback_valid=false
    printf 'action_16aj_e_stage_rollback_complete=%s\n' \
        "$rollback_valid" >&2
    if [[ "$rollback_valid" == true ]]; then
        exit "$original_rc"
    fi
    printf 'manual_intervention_required=true\n' >&2
    exit 97
}
trap rollback EXIT

stage_fail() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    exit 1
}

require_stage_command() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        stage_fail "$label"
    fi
    printf '%s=true\n' "$label"
}

require_stage_equal() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" != "$expected" ]]; then
        stage_fail "$label"
    fi
    printf '%s=true\n' "$label"
}

stage_mutation_started=true
require_stage_command stage_create \
    install -d -o root -g root -m 0750 "$retained_stage"
require_stage_equal stage_root_meta \
    "$(stat -c '%U:%G:%a' "$retained_stage" 2>/dev/null || true)" \
    root:root:750
require_stage_command stage_extract \
    tar --extract --file - --directory "$retained_stage" \
    --no-same-owner --no-same-permissions
require_stage_command stage_root_post_extract_owner \
    chown root:root "$retained_stage"
require_stage_command stage_root_post_extract_mode \
    chmod 0750 "$retained_stage"
require_stage_equal stage_root_post_extract_meta \
    "$(stat -c '%U:%G:%a' "$retained_stage" 2>/dev/null || true)" \
    root:root:750

mapfile -t actual_files < <(
    find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\n' 2>/dev/null |
        sort
)
require_stage_equal stage_file_set \
    "${actual_files[*]}" "${expected_files[*]}"
require_stage_equal stage_file_count "${#actual_files[@]}" 5
symlink_count=$(
    find "$retained_stage" -type l -print 2>/dev/null |
        wc -l
)
require_stage_equal stage_symlink_count "$symlink_count" 0

require_stage_command stage_chown \
    find "$retained_stage" -mindepth 1 -maxdepth 1 -type f \
    -exec chown root:root {} +
require_stage_command stage_script_modes \
    chmod 0750 \
    "$retained_stage/caddy-sync-rsync-receiver" \
    "$retained_stage/setup-sync-ssh.sh" \
    "$retained_stage/validate-sync-ssh.sh"
require_stage_command stage_public_key_modes \
    chmod 0640 \
    "$retained_stage/node-b-host-ed25519.pub" \
    "$retained_stage/node-b-sync-ed25519.pub"

for checksum in "${expected_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    label=${relative_path//[^A-Za-z0-9]/_}
    require_stage_equal "hash_$label" \
        "$(sha256sum "$retained_stage/$relative_path" 2>/dev/null |
            awk '{ print $1 }')" \
        "$expected_hash"
    require_stage_equal "owner_$label" \
        "$(stat -c '%U:%G' "$retained_stage/$relative_path" \
            2>/dev/null || true)" \
        root:root
    case "$relative_path" in
        *.sh | caddy-sync-rsync-receiver)
            expected_mode=750
            ;;
        *)
            expected_mode=640
            ;;
    esac
    require_stage_equal "mode_$label" \
        "$(stat -c '%a' "$retained_stage/$relative_path" \
            2>/dev/null || true)" \
        "$expected_mode"
done

require_stage_equal node_b_host_fingerprint \
    "$(ssh-keygen -lf "$retained_stage/node-b-host-ed25519.pub" \
        -E sha256 2>/dev/null | awk '{ print $2 }')" \
    "$expected_node_b_host_fingerprint"
require_stage_equal node_b_sync_fingerprint \
    "$(ssh-keygen -lf "$retained_stage/node-b-sync-ed25519.pub" \
        -E sha256 2>/dev/null | awk '{ print $2 }')" \
    "$expected_node_b_sync_fingerprint"
require_stage_command live_state_with_retained_stage validate_live_state
require_stage_equal protected_state_unchanged \
    "$(protected_state)" "$protected_before"
require_stage_absent() {
    local label=$1
    local target=$2

    if [[ -e "$target" || -L "$target" ]]; then
        stage_fail "$label"
    fi
    printf '%s=true\n' "$label"
}
require_stage_absent original_stage_still_absent "$original_stage"
require_stage_absent failed_diagnostic_stage_still_absent \
    "$failed_diagnostic_stage"
require_stage_absent transient_diagnostic_stage_still_absent \
    "$transient_diagnostic_stage"

printf 'first_failure=none\n'
printf 'stage_path=%s\n' "$retained_stage"
printf 'stage_owner_mode=%s\n' \
    "$(stat -c '%U:%G:%a' "$retained_stage")"
printf 'stage_file_count=5\n'
printf 'stage_retained=true\n'
printf 'action_16aj_e_retained_stage_complete=true\n'
success=true
