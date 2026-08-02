#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly diagnostic_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-b
readonly original_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj
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

if [[ "${1:-}" == --self-test ]]; then
    [[ "${#expected_files[@]}" -eq 5 ]]
    [[ "${#expected_checksums[@]}" -eq 5 ]]
    [[ "$expected_node_b_host_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    [[ "$expected_node_b_sync_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16aj_b_transient_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    local service

    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

identity_state() {
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh
}

tree_state() {
    local root=$1

    find "$root" -printf '%P|%y|%U:%G:%m:%s:%Y:%i\n' | sort
    find "$root" -type f -print0 |
        sort -z |
        xargs -0 -r sha256sum
}

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

protected_state() {
    package_inventory
    identity_state
    protected_service_state
    ss -H -lntup | sort
    tree_state /etc/caddy/releases/bootstrap
    tree_state /var/tmp/caddy-source-node-a-action16af
    tree_state /var/tmp/caddy-cert-node-a-action16ae
    tree_state /var/lib/caddy
    tree_state /var/log/caddy
    find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 \
        -printf '%f|%y|%U:%G:%m:%s:%Y:%i\n' |
        sort
    sha256sum \
        /etc/default/caddy-ha \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /var/tmp/caddy-ha-lighttpd-node-a-action16ab/lighttpd.conf \
        /etc/keepalived/keepalived.conf \
        /etc/sysctl.d/70-caddy-ha.conf
    /usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind
    /usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind
    dpkg --audit
}

validate_live_state() {
    local target

    [[ "$(hostname)" == j1-svpihole0 ]]
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' lsyncd)" == 'ii :2.2.3-1:arm64' ]]
    [[ "$(dpkg-query -W -f='${Version}' rsync)" == '3.2.7-1+deb12u6' ]]
    [[ "$(dpkg-query -W -f='${Version}' openssh-server)" == '1:9.2p1-2+deb12u10' ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
    [[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
    [[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
    [[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh)" == caddy-sync:caddy-sync:700 ]]
    [[ "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')" == "$environment_sha256" ]]
    [[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(readlink -e /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]

    for target in \
        /var/lib/caddy-sync/.ssh/id_ed25519 \
        /var/lib/caddy-sync/.ssh/id_ed25519.pub \
        /var/lib/caddy-sync/.ssh/known_hosts \
        /var/lib/caddy-sync/.ssh/authorized_keys \
        /usr/local/libexec/caddy-sync-rsync-receiver \
        /usr/local/libexec/setup-sync-ssh.sh \
        /usr/local/libexec/validate-sync-ssh.sh \
        /etc/lsyncd/caddy.lua; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
    for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
        systemctl is-active --quiet "$service"
    done

    [[ "$(tree_hash /etc/lighttpd)" == "$live_lighttpd_sha256" ]]
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)" == "$candidate_lighttpd_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf |
        awk '{ print $1 }')" == "$keepalived_sha256" ]]
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf |
        awk '{ print $1 }')" == "$sysctl_sha256" ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
    [[ -z "$(dpkg --audit)" ]]
}

failure_count=0
first_failure=none

mark_result() {
    local label=$1
    local result=$2

    if [[ "$result" != true ]]; then
        failure_count=$((failure_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$label
        fi
    fi
    printf '%s=%s\n' "$label" "$result"
}

record_command() {
    local label=$1
    shift
    local result=false

    if "$@" >/dev/null 2>&1; then
        result=true
    fi
    mark_result "$label" "$result"
}

record_equal() {
    local label=$1
    local observed=$2
    local expected=$3
    local result=false

    if [[ "$observed" == "$expected" ]]; then
        result=true
    fi
    printf '%s_observed=%s\n' "$label" "$observed"
    printf '%s_expected=%s\n' "$label" "$expected"
    mark_result "${label}_match" "$result"
}

record_protected_state() {
    local label=$1
    local result=false

    if [[ "$(protected_state)" == "$protected_before" ]]; then
        result=true
    fi
    mark_result "$label" "$result"
}

validate_live_state
[[ ! -e "$original_stage" && ! -L "$original_stage" ]]
[[ ! -e "$diagnostic_stage" && ! -L "$diagnostic_stage" ]]
protected_before=$(protected_state)
readonly protected_before

success=false
cleanup_valid=false
cleanup_on_exit() {
    local original_rc=$?
    local exit_cleanup_valid=true

    if [[ "$success" == true ]]; then
        return
    fi

    set +e
    rm -rf -- "$diagnostic_stage"
    if [[ -e "$diagnostic_stage" || -L "$diagnostic_stage" ]]; then
        exit_cleanup_valid=false
    fi
    validate_live_state || exit_cleanup_valid=false
    [[ "$(protected_state)" == "$protected_before" ]] ||
        exit_cleanup_valid=false
    printf 'action_16aj_b_exit_cleanup_valid=%s\n' \
        "$exit_cleanup_valid" >&2
    if [[ "$exit_cleanup_valid" == true ]]; then
        exit "$original_rc"
    fi
    printf 'manual_intervention_required=true\n' >&2
    exit 97
}
trap cleanup_on_exit EXIT
set +e

record_command stage_create \
    install -d -o root -g root -m 0750 "$diagnostic_stage"
record_equal stage_root_meta \
    "$(stat -c '%U:%G:%a' "$diagnostic_stage" 2>/dev/null || true)" \
    root:root:750

stage_extract=false
if tar --extract --file - --directory "$diagnostic_stage" \
    --no-same-owner --no-same-permissions; then
    stage_extract=true
fi
mark_result stage_extract "$stage_extract"

mapfile -t actual_files < <(
    find "$diagnostic_stage" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\n' 2>/dev/null |
        sort
)
record_equal stage_file_set "${actual_files[*]}" "${expected_files[*]}"
record_equal stage_file_count "${#actual_files[@]}" 5
symlink_count=$(
    find "$diagnostic_stage" -type l -print 2>/dev/null |
        wc -l
)
record_equal stage_symlink_count "$symlink_count" 0

record_command stage_chown \
    find "$diagnostic_stage" -mindepth 1 -maxdepth 1 -type f \
    -exec chown root:root {} +
record_command stage_script_modes \
    chmod 0750 \
    "$diagnostic_stage/caddy-sync-rsync-receiver" \
    "$diagnostic_stage/setup-sync-ssh.sh" \
    "$diagnostic_stage/validate-sync-ssh.sh"
record_command stage_public_key_modes \
    chmod 0640 \
    "$diagnostic_stage/node-b-host-ed25519.pub" \
    "$diagnostic_stage/node-b-sync-ed25519.pub"

for checksum in "${expected_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    observed_hash=$(
        sha256sum "$diagnostic_stage/$relative_path" 2>/dev/null |
            awk '{ print $1 }'
    )
    label=${relative_path//[^A-Za-z0-9]/_}
    record_equal "hash_$label" "$observed_hash" "$expected_hash"
    record_equal "owner_$label" \
        "$(stat -c '%U:%G' "$diagnostic_stage/$relative_path" \
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
    record_equal "mode_$label" \
        "$(stat -c '%a' "$diagnostic_stage/$relative_path" \
            2>/dev/null || true)" \
        "$expected_mode"
done

host_fingerprint=$(
    ssh-keygen -lf "$diagnostic_stage/node-b-host-ed25519.pub" \
        -E sha256 2>/dev/null |
        awk '{ print $2 }'
)
sync_fingerprint=$(
    ssh-keygen -lf "$diagnostic_stage/node-b-sync-ed25519.pub" \
        -E sha256 2>/dev/null |
        awk '{ print $2 }'
)
record_equal node_b_host_fingerprint \
    "$host_fingerprint" "$expected_node_b_host_fingerprint"
record_equal node_b_sync_fingerprint \
    "$sync_fingerprint" "$expected_node_b_sync_fingerprint"

record_command live_state_while_staged validate_live_state
record_protected_state protected_state_while_staged
record_command original_stage_still_absent \
    test ! -e "$original_stage"

stage_cleanup=false
if rm -rf -- "$diagnostic_stage" &&
    [[ ! -e "$diagnostic_stage" && ! -L "$diagnostic_stage" ]]; then
    stage_cleanup=true
fi
mark_result stage_cleanup "$stage_cleanup"
record_command live_state_after_cleanup validate_live_state
record_protected_state protected_state_after_cleanup

if [[ "$stage_cleanup" == true ]] &&
    validate_live_state &&
    [[ "$(protected_state)" == "$protected_before" ]]; then
    cleanup_valid=true
fi

printf 'diagnostic_failure_count=%s\n' "$failure_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'diagnostic_stage_cleanup_valid=%s\n' "$cleanup_valid"
printf 'action_16aj_b_transient_diagnostic_complete=true\n'
success=true
