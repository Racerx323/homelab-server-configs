#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly target=/etc/sysctl.d/70-caddy-ha.conf
readonly expected_artifact_sha=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8

stage=
target_created=false
ipv4_changed=false
ipv6_changed=false
transaction_complete=false
rollback_armed=false

render_sysctl() {
    printf '%s\n' \
        '# Permit Caddy to bind the inactive floating addresses on the BACKUP node.' \
        'net.ipv4.ip_nonlocal_bind = 1' \
        'net.ipv6.ip_nonlocal_bind = 1' \
        ''
}

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
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

group_names() {
    id -nG "$1" |
        tr ' ' '\n' |
        sed '/^$/d' |
        sort
}

group_members() {
    getent group "$1" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

identity_permission_state() {
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n %U:%G:%a' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh
}

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

staging_paths() {
    find /tmp /var/tmp /etc/sysctl.d \
        -mindepth 1 -maxdepth 1 \
        \( -name 'caddy-sysctl-node-a*' \
        -o -name 'caddy-ha-sysctl-node-a*' \
        -o -name '.70-caddy-ha.conf*' \) \
        -print |
        sort
}

protected_state_matches() {
    [[ "$(package_inventory)" == "$inventory_before" ]] &&
        [[ "$(identity_permission_state)" == "$identities_before" ]] &&
        [[ "$(protected_service_state)" == "$services_before" ]] &&
        [[ "$(ss -H -lntup | sort)" == "$listeners_before" ]] &&
        [[ "$(
            sha256sum -- \
                /etc/lighttpd/lighttpd.conf \
                /etc/lighttpd/conf-enabled/external.conf \
                /etc/keepalived/keepalived.conf
        )" == "$protected_hashes_before" ]] &&
        [[ -z "$(dpkg --audit)" ]]
}

rollback() {
    local original_rc=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        return
    fi
    if [[ "$rollback_armed" != true ]]; then
        exit "$original_rc"
    fi

    set +e
    printf 'sysctl_install_action16aa_rollback_started=true\n' >&2

    if [[ "$ipv6_changed" == true ]]; then
        /usr/sbin/sysctl -w \
            "net.ipv6.ip_nonlocal_bind=$ipv6_before" >/dev/null ||
            rollback_failed=true
    fi
    if [[ "$ipv4_changed" == true ]]; then
        /usr/sbin/sysctl -w \
            "net.ipv4.ip_nonlocal_bind=$ipv4_before" >/dev/null ||
            rollback_failed=true
    fi
    if [[ "$target_created" == true ]]; then
        rm -f -- "$target" || rollback_failed=true
    elif [[ -n "$stage" && -e "$stage" && -e "$target" ]] &&
        [[ "$(stat -c '%d:%i' "$stage")" == "$(stat -c '%d:%i' "$target")" ]]; then
        rm -f -- "$target" || rollback_failed=true
    fi
    if [[ -n "$stage" && (-e "$stage" || -L "$stage") ]]; then
        rm -f -- "$stage" || rollback_failed=true
    fi

    [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == "$ipv4_before" ]] ||
        rollback_failed=true
    [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == "$ipv6_before" ]] ||
        rollback_failed=true
    [[ ! -e "$target" && ! -L "$target" ]] || rollback_failed=true
    mapfile -t rollback_staging < <(staging_paths)
    [[ "${#rollback_staging[@]}" -eq 0 ]] || rollback_failed=true
    protected_state_matches || rollback_failed=true

    if [[ "$rollback_failed" == true ]]; then
        printf 'sysctl_install_action16aa_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'sysctl_install_action16aa_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    rendered_sha=$(render_sysctl | sha256sum | awk '{ print $1 }')
    [[ "$rendered_sha" == "$expected_artifact_sha" ]]
    [[ "$(render_sysctl | wc -c)" -eq 136 ]]
    printf 'action_16aa_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_address_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_address_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

[[ -x /usr/sbin/sysctl ]]
[[ "$(/usr/sbin/sysctl --version)" == 'sysctl from procps-ng 4.0.2' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' procps)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' procps)" == '2:4.0.2-3' ]]
procps_verification=$(dpkg --verify procps)
[[ "$procps_verification" == '??5?????? c /etc/sysctl.conf' ]]

[[ ! -e "$target" && ! -L "$target" ]]
mapfile -t staging_before < <(staging_paths)
[[ "${#staging_before[@]}" -eq 0 ]]
[[ -d /etc/sysctl.d && ! -L /etc/sysctl.d ]]
[[ "$(stat -c '%U:%G:%a' /etc/sysctl.d)" == root:root:755 ]]
for command_path in \
    /usr/bin/ln \
    /usr/bin/mktemp \
    /usr/bin/rm \
    /usr/bin/sha256sum \
    /usr/bin/stat \
    /usr/sbin/sysctl; do
    [[ -x "$command_path" ]]
done

[[ "$(id -u caddy)" -eq 995 ]]
[[ "$(id -g caddy)" -eq 992 ]]
[[ "$(group_names caddy)" == $'caddy\ncaddy-tls\nwww-data' ]]
[[ "$(id -u caddy-sync)" -eq 994 ]]
[[ "$(id -g caddy-sync)" -eq 990 ]]
[[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
[[ "$(getent passwd caddy-sync | cut -d: -f6)" == /var/lib/caddy-sync ]]
[[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
[[ "$(id -u keepalived_script)" -eq 993 ]]
[[ "$(id -g keepalived_script)" -eq 989 ]]
[[ "$(group_names keepalived_script)" == $'caddy-tls\nkeepalived_script' ]]
[[ "$(getent passwd keepalived_script | cut -d: -f7)" == /usr/sbin/nologin ]]
[[ "$(passwd --status keepalived_script | awk '{ print $2 }')" == L ]]
[[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]]
[[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]

[[ "$(stat -c '%U:%G:%a' /etc/caddy/releases)" == root:caddy-tls:750 ]]
for path in \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine; do
    [[ "$(stat -c '%U:%G:%a' "$path")" == caddy-sync:caddy-sync:750 ]]
done
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh)" == caddy-sync:caddy-sync:700 ]]

for unit in \
    caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
    assert_masked_inactive "$unit"
done
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process before sysctl installation.\n' >&2
    exit 1
fi
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]

inventory_before=$(package_inventory)
identities_before=$(identity_permission_state)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
protected_hashes_before=$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)
[[ -z "$(dpkg --audit)" ]]

ipv4_before=$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)
ipv6_before=$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)
[[ "$ipv4_before" == 1 ]]
[[ "$ipv6_before" == 0 ]]

rollback_armed=true
trap rollback EXIT

stage=$(mktemp --tmpdir=/etc/sysctl.d .70-caddy-ha.conf.action16aa.XXXXXX)
render_sysctl >"$stage"
[[ "$(sha256sum "$stage" | awk '{ print $1 }')" == "$expected_artifact_sha" ]]
[[ "$(stat -c '%U:%G:%a:%s' "$stage")" == root:root:600:136 ]]

ln -- "$stage" "$target"
target_created=true
chmod 0644 "$target"
rm -f -- "$stage"
stage=

[[ -f "$target" && ! -L "$target" ]]
[[ "$(stat -c '%U:%G:%a:%s' "$target")" == root:root:644:136 ]]
[[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_artifact_sha" ]]

if [[ "$ipv4_before" != 1 ]]; then
    ipv4_changed=true
    /usr/sbin/sysctl -w net.ipv4.ip_nonlocal_bind=1
fi
if [[ "$ipv6_before" != 1 ]]; then
    ipv6_changed=true
    /usr/sbin/sysctl -w net.ipv6.ip_nonlocal_bind=1
fi

[[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
[[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
[[ -f "$target" && ! -L "$target" ]]
[[ "$(stat -c '%U:%G:%a:%s' "$target")" == root:root:644:136 ]]
[[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_artifact_sha" ]]
mapfile -t staging_after < <(staging_paths)
[[ "${#staging_after[@]}" -eq 0 ]]
protected_state_matches

printf 'sysctl_target=%s\n' "$target"
printf 'sysctl_target_sha256=%s\n' "$expected_artifact_sha"
printf 'ipv4_nonlocal_bind_before=%s\n' "$ipv4_before"
printf 'ipv4_nonlocal_bind_after=1\n'
printf 'ipv4_runtime_write_performed=%s\n' "$ipv4_changed"
printf 'ipv6_nonlocal_bind_before=%s\n' "$ipv6_before"
printf 'ipv6_nonlocal_bind_after=1\n'
printf 'ipv6_runtime_write_performed=%s\n' "$ipv6_changed"
printf 'sysctl_install_action16aa_complete=true\n'
transaction_complete=true
