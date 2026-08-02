#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly caddy_version=2.11.4
readonly caddy_uid=995
readonly caddy_gid=992
readonly caddy_home=/var/lib/caddy
readonly caddy_shell=/usr/sbin/nologin

transaction_complete=false
rollback_armed=false
created_caddy_tls_group=false
created_caddy_sync_group=false
created_keepalived_group=false
created_caddy_sync_user=false
created_keepalived_user=false
added_caddy_tls_membership=false

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

group_names_with() {
    local existing=$1
    local addition=$2

    printf '%s\n%s\n' "$existing" "$addition" |
        sed '/^$/d' |
        sort -u
}

group_members() {
    local group=$1

    getent group "$group" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

identity_absent() {
    local identity=$1

    ! getent passwd "$identity" >/dev/null &&
        ! getent group "$identity" >/dev/null
}

path_absent() {
    local path=$1

    [[ ! -e "$path" && ! -L "$path" ]]
}

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

rollback() {
    local original_rc=$?
    local rollback_failed=false
    local target

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        return
    fi
    if [[ "$rollback_armed" != true ]]; then
        exit "$original_rc"
    fi

    set +e
    printf 'service_identity_rollback_started=true\n' >&2

    if [[ "$added_caddy_tls_membership" == true ]] &&
        getent group caddy-tls >/dev/null &&
        group_names caddy | grep -Fxq caddy-tls; then
        gpasswd --delete caddy caddy-tls >/dev/null 2>&1 ||
            rollback_failed=true
    fi
    if [[ "$created_keepalived_user" == true ]] &&
        getent passwd keepalived_script >/dev/null; then
        userdel keepalived_script >/dev/null 2>&1 ||
            rollback_failed=true
    fi
    if [[ "$created_caddy_sync_user" == true ]] &&
        getent passwd caddy-sync >/dev/null; then
        userdel caddy-sync >/dev/null 2>&1 ||
            rollback_failed=true
    fi
    if [[ "$created_keepalived_group" == true ]] &&
        getent group keepalived_script >/dev/null; then
        groupdel keepalived_script >/dev/null 2>&1 ||
            rollback_failed=true
    fi
    if [[ "$created_caddy_sync_group" == true ]] &&
        getent group caddy-sync >/dev/null; then
        groupdel caddy-sync >/dev/null 2>&1 ||
            rollback_failed=true
    fi
    if [[ "$created_caddy_tls_group" == true ]] &&
        getent group caddy-tls >/dev/null; then
        groupdel caddy-tls >/dev/null 2>&1 ||
            rollback_failed=true
    fi

    for target in \
        /etc/caddy/releases \
        /var/lib/caddy-sync/.ssh \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync; do
        if [[ -d "$target" && ! -L "$target" ]]; then
            rmdir -- "$target" >/dev/null 2>&1 || true
        fi
    done

    for identity in caddy-sync keepalived_script caddy-tls; do
        identity_absent "$identity" || rollback_failed=true
    done
    for target in \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /home/keepalived_script; do
        path_absent "$target" || rollback_failed=true
    done
    [[ "$(group_names caddy)" == "$caddy_groups_before" ]] ||
        rollback_failed=true
    [[ "$(package_inventory)" == "$inventory_before" ]] ||
        rollback_failed=true
    [[ "$(protected_service_state)" == "$services_before" ]] ||
        rollback_failed=true
    [[ "$(ss -H -lntup | sort)" == "$listeners_before" ]] ||
        rollback_failed=true
    [[ "$(
        sha256sum -- \
            /etc/lighttpd/lighttpd.conf \
            /etc/lighttpd/conf-enabled/external.conf \
            /etc/keepalived/keepalived.conf
    )" == "$protected_hashes_before" ]] ||
        rollback_failed=true
    [[ -z "$(dpkg --audit)" ]] || rollback_failed=true

    if [[ "$rollback_failed" == true ]]; then
        printf 'service_identity_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'service_identity_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    sample=$'caddy\nwww-data'
    [[ "$(group_names_with "$sample" caddy-tls)" == $'caddy\ncaddy-tls\nwww-data' ]]
    [[ "$(group_names_with "$sample" www-data)" == "$sample" ]]
    printf 'action_16y_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
ipv4_state=$(ip -o -4 address show dev eth0)
grep -Fq '10.1.0.53/22' <<<"$ipv4_state"
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == "$caddy_version" ]]
[[ "$(id -u caddy)" -eq "$caddy_uid" ]]
[[ "$(id -g caddy)" -eq "$caddy_gid" ]]
[[ "$(getent passwd caddy | cut -d: -f6)" == "$caddy_home" ]]
[[ "$(getent passwd caddy | cut -d: -f7)" == "$caddy_shell" ]]
[[ "$(getent group caddy | cut -d: -f3)" -eq "$caddy_gid" ]]
caddy_groups_before=$(group_names caddy)
[[ "$caddy_groups_before" == $'caddy\nwww-data' ]]

for identity in caddy-sync keepalived_script caddy-tls; do
    identity_absent "$identity"
done
for target in \
    /etc/caddy/releases \
    /var/lib/caddy-sync \
    /home/keepalived_script; do
    path_absent "$target"
done
for command_path in \
    /usr/sbin/groupadd \
    /usr/sbin/groupdel \
    /usr/bin/gpasswd \
    /usr/sbin/useradd \
    /usr/sbin/userdel \
    /usr/sbin/usermod \
    /usr/bin/passwd \
    /usr/bin/install; do
    [[ -x "$command_path" && ! -L "$command_path" ]]
done

for unit in \
    caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
    assert_masked_inactive "$unit"
done
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process before identity installation.\n' >&2
    exit 1
fi

inventory_before=$(package_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
protected_hashes_before=$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)
[[ -z "$(dpkg --audit)" ]]

rollback_armed=true
trap rollback EXIT

groupadd --system caddy-tls
created_caddy_tls_group=true
groupadd --system caddy-sync
created_caddy_sync_group=true
groupadd --system keepalived_script
created_keepalived_group=true
useradd \
    --system \
    --gid caddy-sync \
    --home-dir /var/lib/caddy-sync \
    --no-create-home \
    --shell /bin/sh \
    caddy-sync
created_caddy_sync_user=true
usermod --shell /bin/sh caddy-sync >/dev/null
passwd --lock caddy-sync >/dev/null
useradd \
    --system \
    --gid keepalived_script \
    --no-create-home \
    --shell /usr/sbin/nologin \
    keepalived_script
created_keepalived_user=true
usermod --append --groups caddy-tls caddy
added_caddy_tls_membership=true
usermod --append --groups caddy-tls caddy-sync
usermod --append --groups caddy-tls keepalived_script

install -d -o root -g caddy-tls -m 0750 /etc/caddy/releases
install -d -o caddy-sync -g caddy-sync -m 0750 /var/lib/caddy-sync
install -d -o caddy-sync -g caddy-sync -m 0750 \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine
install -d -o caddy-sync -g caddy-sync -m 0700 \
    /var/lib/caddy-sync/.ssh

[[ "$(group_names caddy)" == "$(group_names_with "$caddy_groups_before" caddy-tls)" ]]
[[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
[[ "$(group_names keepalived_script)" == $'caddy-tls\nkeepalived_script' ]]

caddy_sync_passwd=$(getent passwd caddy-sync)
caddy_sync_group=$(getent group caddy-sync)
keepalived_passwd=$(getent passwd keepalived_script)
keepalived_group=$(getent group keepalived_script)
caddy_tls_group=$(getent group caddy-tls)
[[ -n "$caddy_sync_passwd" && -n "$caddy_sync_group" ]]
[[ -n "$keepalived_passwd" && -n "$keepalived_group" ]]
[[ -n "$caddy_tls_group" ]]

[[ "$(cut -d: -f3 <<<"$caddy_sync_passwd")" -gt 0 ]]
[[ "$(cut -d: -f3 <<<"$caddy_sync_passwd")" -lt 1000 ]]
[[ "$(cut -d: -f4 <<<"$caddy_sync_passwd")" == "$(cut -d: -f3 <<<"$caddy_sync_group")" ]]
[[ "$(cut -d: -f3 <<<"$caddy_sync_group")" -gt 0 ]]
[[ "$(cut -d: -f3 <<<"$caddy_sync_group")" -lt 1000 ]]
[[ -z "$(cut -d: -f4 <<<"$caddy_sync_group")" ]]
[[ "$(cut -d: -f6 <<<"$caddy_sync_passwd")" == /var/lib/caddy-sync ]]
[[ "$(cut -d: -f7 <<<"$caddy_sync_passwd")" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{ print $2 }')" == L ]]
[[ "$(cut -d: -f3 <<<"$keepalived_passwd")" -gt 0 ]]
[[ "$(cut -d: -f3 <<<"$keepalived_passwd")" -lt 1000 ]]
[[ "$(cut -d: -f4 <<<"$keepalived_passwd")" == "$(cut -d: -f3 <<<"$keepalived_group")" ]]
[[ "$(cut -d: -f3 <<<"$keepalived_group")" -gt 0 ]]
[[ "$(cut -d: -f3 <<<"$keepalived_group")" -lt 1000 ]]
[[ -z "$(cut -d: -f4 <<<"$keepalived_group")" ]]
[[ "$(cut -d: -f7 <<<"$keepalived_passwd")" == /usr/sbin/nologin ]]
[[ "$(passwd --status keepalived_script | awk '{ print $2 }')" == L ]]
[[ ! -e /home/keepalived_script && ! -L /home/keepalived_script ]]
[[ "$(cut -d: -f3 <<<"$caddy_tls_group")" -gt 0 ]]
[[ "$(cut -d: -f3 <<<"$caddy_tls_group")" -lt 1000 ]]
[[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]

[[ "$(stat -c '%U:%G:%a' /etc/caddy/releases)" == root:caddy-tls:750 ]]
for target in \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/outbound \
    /var/lib/caddy-sync/incoming \
    /var/lib/caddy-sync/quarantine; do
    [[ "$(stat -c '%U:%G:%a' "$target")" == caddy-sync:caddy-sync:750 ]]
done
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy-sync/.ssh)" == caddy-sync:caddy-sync:700 ]]

[[ "$(package_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
[[ "$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)" == "$protected_hashes_before" ]]
[[ -z "$(dpkg --audit)" ]]

printf 'caddy_identity=%s\n' "$(id caddy)"
printf 'caddy_sync_identity=%s\n' "$(id caddy-sync)"
printf 'keepalived_script_identity=%s\n' "$(id keepalived_script)"
printf 'caddy_tls_group=%s\n' "$caddy_tls_group"
printf 'service_identity_install_action16y_complete=true\n'
transaction_complete=true
