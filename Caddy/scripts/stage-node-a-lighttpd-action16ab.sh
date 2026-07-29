#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly source_stage=/var/tmp/caddy-ha-lighttpd-node-a-action16ab-source
readonly renderer="$source_stage/scripts/prepare-lighttpd-config.sh"
readonly desired_state="$source_stage/configs/lighttpd/desired-state.conf"
readonly candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly live=/etc/lighttpd
readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly sysctl_target=/etc/sysctl.d/70-caddy-ha.conf

readonly renderer_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027
readonly live_main_sha256=568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1
readonly live_external_sha256=6da587363054a4db69fb742d23bddde06aec866e11fb7a91bff1a8d75a713f7a
readonly keepalived_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_target_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8

transaction_complete=false

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

identity_state() {
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

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

listener_snapshot() {
    ss -H -lntup | sort
}

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

protected_state_matches() {
    [[ "$(package_inventory)" == "$inventory_before" ]] &&
        [[ "$(identity_state)" == "$identities_before" ]] &&
        [[ "$(protected_service_state)" == "$services_before" ]] &&
        [[ "$(listener_snapshot)" == "$listeners_before" ]] &&
        [[ "$(tree_hash "$live")" == "$live_tree_before" ]] &&
        [[ "$(
            sha256sum -- \
                "$live/lighttpd.conf" \
                "$live/conf-enabled/external.conf" \
                /etc/keepalived/keepalived.conf \
                "$sysctl_target"
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

    set +e
    printf 'lighttpd_stage_action16ab_rollback_started=true\n' >&2
    rm -rf -- "$candidate" || rollback_failed=true
    [[ ! -e "$candidate" && ! -L "$candidate" ]] || rollback_failed=true
    protected_state_matches || rollback_failed=true

    if [[ "$rollback_failed" == true ]]; then
        printf 'lighttpd_stage_action16ab_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'lighttpd_stage_action16ab_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$renderer_sha256" == ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f ]]
    [[ "$desired_state_sha256" == 8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027 ]]
    [[ "$sysctl_target_sha256" == d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8 ]]
    printf 'action_16ab_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

for command_path in \
    /usr/bin/find \
    /usr/bin/grep \
    /usr/bin/sha256sum \
    /usr/bin/ss \
    /usr/bin/stat \
    /usr/sbin/lighttpd; do
    [[ -x "$command_path" ]]
done

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' lighttpd)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' lighttpd)" == '1.4.69-1' ]]
[[ -d "$live" && ! -L "$live" ]]
[[ -f "$live/lighttpd.conf" && ! -L "$live/lighttpd.conf" ]]
[[ -f "$live/conf-enabled/external.conf" &&
    ! -L "$live/conf-enabled/external.conf" ]]
[[ "$(sha256sum "$live/lighttpd.conf" | awk '{ print $1 }')" == "$live_main_sha256" ]]
[[ "$(sha256sum "$live/conf-enabled/external.conf" | awk '{ print $1 }')" == "$live_external_sha256" ]]
[[ "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')" == "$keepalived_main_sha256" ]]

[[ -d "$source_stage" && ! -L "$source_stage" ]]
[[ "$(stat -c '%U:%G:%a' "$source_stage")" == root:root:700 ]]
[[ -f "$renderer" && ! -L "$renderer" ]]
[[ "$(stat -c '%U:%G:%a' "$renderer")" == root:root:700 ]]
[[ "$(sha256sum "$renderer" | awk '{ print $1 }')" == "$renderer_sha256" ]]
[[ -f "$desired_state" && ! -L "$desired_state" ]]
[[ "$(stat -c '%U:%G:%a' "$desired_state")" == root:root:600 ]]
[[ "$(sha256sum "$desired_state" | awk '{ print $1 }')" == "$desired_state_sha256" ]]
[[ ! -e "$candidate" && ! -L "$candidate" ]]

[[ -f "$sysctl_target" && ! -L "$sysctl_target" ]]
[[ "$(stat -c '%U:%G:%a:%s' "$sysctl_target")" == root:root:644:136 ]]
[[ "$(sha256sum "$sysctl_target" | awk '{ print $1 }')" == "$sysctl_target_sha256" ]]
[[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
[[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]

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
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process before lighttpd staging.\n' >&2
    exit 1
fi
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]

inventory_before=$(package_inventory)
identities_before=$(identity_state)
services_before=$(protected_service_state)
listeners_before=$(listener_snapshot)
live_tree_before=$(tree_hash "$live")
protected_hashes_before=$(
    sha256sum -- \
        "$live/lighttpd.conf" \
        "$live/conf-enabled/external.conf" \
        /etc/keepalived/keepalived.conf \
        "$sysctl_target"
)
[[ -z "$(dpkg --audit)" ]]

trap rollback EXIT

"$renderer" --source-root "$live" --output "$candidate"

[[ -d "$candidate" && ! -L "$candidate" ]]
[[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:750 ]]
[[ -f "$candidate/lighttpd.conf" && ! -L "$candidate/lighttpd.conf" ]]
grep -Fqx \
    'include "/var/tmp/caddy-ha-lighttpd-node-a-action16ab/conf-enabled/*.conf"' \
    "$candidate/lighttpd.conf"
[[ "$(grep -Ec \
    '^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*8080[[:space:]]*$' \
    "$candidate/lighttpd.conf")" -eq 1 ]]
[[ "$(grep -Ec \
    '^[[:space:]]*server\.bind[[:space:]]*=[[:space:]]*"127\.0\.0\.1"[[:space:]]*$' \
    "$candidate/lighttpd.conf")" -eq 1 ]]
grep -Eq \
    '^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*=[[:space:]]*"enable"' \
    "$candidate/lighttpd.conf"
grep -R -Eq \
    '^[[:space:]]*accesslog\.use-syslog[[:space:]]*:?[+]?=[[:space:]]*"enable"' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"
grep -R -Eq '"mod_accesslog"' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"
if grep -R -qE \
    '/dev/(stderr|stdout)|^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=|ssl\.engine[[:space:]]*=[[:space:]]*"enable"|:443' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"; then
    printf 'Staged tree contains a forbidden logging or HTTPS directive.\n' >&2
    exit 1
fi
[[ ! -e "$candidate/conf-enabled/external.conf" &&
    ! -L "$candidate/conf-enabled/external.conf" ]]
[[ -f "$candidate/conf-disabled-by-caddy-ha/external.conf" ]]
[[ "$(sha256sum "$candidate/conf-disabled-by-caddy-ha/external.conf" |
    awk '{ print $1 }')" == "$live_external_sha256" ]]
/usr/sbin/lighttpd -tt -f "$candidate/lighttpd.conf"

protected_state_matches

printf 'lighttpd_stage=%s\n' "$candidate"
printf 'lighttpd_stage_mode=%s\n' "$(stat -c '%U:%G:%a' "$candidate")"
printf 'lighttpd_stage_main_sha256=%s\n' \
    "$(sha256sum "$candidate/lighttpd.conf" | awk '{ print $1 }')"
printf 'lighttpd_stage_tree_sha256=%s\n' "$(tree_hash "$candidate")"
printf 'lighttpd_live_tree_sha256=%s\n' "$live_tree_before"
printf 'lighttpd_stage_action16ab_complete=true\n'
transaction_complete=true
