#!/usr/bin/env bash

set -euo pipefail
umask 077

expected_lsyncd_version=2.2.3-1
expected_lua_version=5.3.6-2
expected_lsyncd_binary_version='Version: 2.2.3'
expected_init_sha=27e0a67166e36a75f04c6b8548520a59d013442dcbc52542c30836c8e53a3611
baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
policy_target=/usr/sbin/policy-rc.d
work_dir=
policy_created=false
mask_created=false
package_install_started=false
transaction_complete=false

package_status() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true
}

non_target_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        awk -F '\t' \
            '$1 !~ /^(lsyncd|lua5[.]3|liblua5[.]3-0)(:arm64)?$/' |
        sort
}

protected_service_state() {
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
    done
}

rollback() {
    original_rc=$?
    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        return
    fi

    set +e
    printf 'lsyncd_install_rollback_started=true\n' >&2
    rollback_failed=false

    systemctl stop lsyncd.service >/dev/null 2>&1
    installed_target=false
    for package in lsyncd lua5.3 liblua5.3-0; do
        status=$(package_status "$package")
        if [[ -n "$status" && "$status" != 'un ' ]]; then
            installed_target=true
        fi
    done
    if [[ "$installed_target" == true ]]; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get purge --yes lsyncd lua5.3 liblua5.3-0
        purge_rc=$?
        if ((purge_rc != 0)); then
            rollback_failed=true
        fi
    fi

    if [[ "$policy_created" == true ]]; then
        rm -f -- "$policy_target"
        policy_created=false
    fi

    packages_absent=true
    for package in lsyncd lua5.3 liblua5.3-0; do
        status=$(package_status "$package")
        if [[ -n "$status" && "$status" != 'un ' ]]; then
            packages_absent=false
        fi
    done
    if [[ "$packages_absent" == true ]]; then
        if [[ "$package_install_started" == true ]]; then
            rm -rf -- /etc/lsyncd
        fi
        if [[ "$mask_created" == true ]]; then
            systemctl unmask lsyncd.service >/dev/null 2>&1
        fi
        systemctl daemon-reload
        for target in \
            /usr/bin/lsyncd \
            /etc/init.d/lsyncd \
            /etc/default/lsyncd \
            /etc/lsyncd \
            /lib/systemd/system/lsyncd.service \
            /etc/systemd/system/lsyncd.service \
            "$policy_target"; do
            if [[ -e "$target" || -L "$target" ]]; then
                rollback_failed=true
            fi
        done
        if find /etc -maxdepth 2 -type l \
            -path '/etc/rc*.d/*lsyncd' -print -quit |
            grep -q .; then
            rollback_failed=true
        fi
        [[ "$(systemctl show --property=LoadState --value lsyncd.service)" == not-found ]] ||
            rollback_failed=true
        [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]] ||
            rollback_failed=true
        [[ "$(non_target_inventory)" == "$inventory_before" ]] ||
            rollback_failed=true
        [[ "$(protected_service_state)" == "$services_before" ]] ||
            rollback_failed=true
        [[ "$(ss -H -lntup | sort)" == "$listeners_before" ]] ||
            rollback_failed=true
        current_protected_hashes=$(
            sha256sum -- \
                /etc/lighttpd/lighttpd.conf \
                /etc/lighttpd/conf-enabled/external.conf \
                /etc/keepalived/keepalived.conf
        )
        [[ "$current_protected_hashes" == "$protected_hashes_before" ]] ||
            rollback_failed=true
    else
        systemctl mask lsyncd.service >/dev/null 2>&1
        systemctl daemon-reload
        rollback_failed=true
    fi

    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi

    if [[ "$rollback_failed" == true ]]; then
        systemctl mask lsyncd.service >/dev/null 2>&1
        systemctl daemon-reload
        printf 'lsyncd_install_rollback_complete=false\n' >&2
        printf 'The lsyncd mask was retained for service safety.\n' >&2
        exit 97
    fi
    printf 'lsyncd_install_rollback_complete=true\n' >&2
    exit "$original_rc"
}

[[ "$(hostname)" == j1-svpihole0 ]]
ip -o -4 address show dev eth0 |
    grep -Fq '10.1.0.53/22'
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

for package in lsyncd lua5.3 liblua5.3-0; do
    status=$(package_status "$package")
    [[ -z "$status" || "$status" == 'un ' ]]
done
[[ "$(apt-cache policy lsyncd |
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }')" == "$expected_lsyncd_version" ]]
[[ "$(apt-cache policy lua5.3 |
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }')" == "$expected_lua_version" ]]
[[ "$(apt-cache policy liblua5.3-0 |
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }')" == "$expected_lua_version" ]]

for target in \
    /usr/bin/lsyncd \
    /etc/init.d/lsyncd \
    /etc/default/lsyncd \
    /etc/lsyncd \
    /lib/systemd/system/lsyncd.service \
    /etc/systemd/system/lsyncd.service \
    "$policy_target"; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
[[ "$(systemctl show --property=LoadState --value lsyncd.service)" == not-found ]]
[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
lsyncd_enabled=$(
    systemctl is-enabled lsyncd.service 2>/dev/null ||
        true
)
[[ -z "$lsyncd_enabled" || "$lsyncd_enabled" == not-found ]]
if find /etc -maxdepth 2 -type l \
    -path '/etc/rc*.d/*lsyncd' -print -quit |
    grep -q .; then
    printf 'Unexpected lsyncd SysV link before installation.\n' >&2
    exit 1
fi
if find /tmp -mindepth 1 -maxdepth 1 \
    \( -name 'lsyncd-package-audit-node-a.*' \
    -o -name 'lsyncd-inhibited-install-node-a.*' \) \
    -print -quit |
    grep -q .; then
    printf 'Unexpected lsyncd staging before installation.\n' >&2
    exit 1
fi

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process before lsyncd installation.\n' >&2
    exit 1
fi

printf '%s  %s\n' \
    568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1 \
    /etc/lighttpd/lighttpd.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    6da587363054a4db69fb742d23bddde06aec866e11fb7a91bff1a8d75a713f7a \
    /etc/lighttpd/conf-enabled/external.conf |
    sha256sum --check --status
printf '%s  %s\n' \
    cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2 \
    /etc/keepalived/keepalived.conf |
    sha256sum --check --status

[[ -z "$(dpkg --audit)" ]]
inventory_before=$(non_target_inventory)
services_before=$(protected_service_state)
listeners_before=$(ss -H -lntup | sort)
protected_hashes_before=$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done

simulation=$(
    LC_ALL=C apt-get -s install --no-install-recommends \
        "lsyncd=$expected_lsyncd_version" 2>&1
)
printf '%s\n' "$simulation"
[[ "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 3 ]]
[[ "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 3 ]]
[[ "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
grep -Eq '^Inst liblua5[.]3-0 \(5[.]3[.]6-2 .*\[arm64\]\)$' \
    <<<"$simulation"
grep -Eq '^Inst lua5[.]3 \(5[.]3[.]6-2 .*\[arm64\]\)$' <<<"$simulation"
grep -Eq '^Inst lsyncd \(2[.]2[.]3-1 .*\[arm64\]\)$' <<<"$simulation"
grep -Fxq \
    '0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

work_dir=$(mktemp -d /tmp/lsyncd-inhibited-install-node-a.XXXXXX)
trap rollback EXIT
policy_events="$work_dir/policy-events.log"
printf \
    '#!/bin/sh\nprintf "policy_invocation=%%s\\n" "$*" >>"%s"\nexit 101\n' \
    "$policy_events" >"$work_dir/policy-rc.d"
install -o root -g root -m 0755 \
    "$work_dir/policy-rc.d" "$policy_target"
policy_created=true
policy_script_sha=$(sha256sum "$policy_target" | awk '{ print $1 }')
printf 'policy_script_sha256=%s\n' "$policy_script_sha"

set +e
"$policy_target" action16r-exit-probe
policy_probe_rc=$?
set -e
[[ "$policy_probe_rc" -eq 101 ]]
printf 'policy_probe_exit=%s\n' "$policy_probe_rc"

mask_created=true
systemctl mask lsyncd.service
systemctl daemon-reload
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]

install_log="$work_dir/apt-install.log"
package_install_started=true
if ! DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
    apt-get install --yes --no-install-recommends \
    "lsyncd=$expected_lsyncd_version" >"$install_log" 2>&1; then
    sed -n '1,500p' "$install_log" >&2
    exit 1
fi
sed -n '1,500p' "$install_log"
grep -Fq \
    '0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.' \
    "$install_log"

[[ -f "$policy_events" && ! -L "$policy_events" ]]
printf '%s\n' '--- policy invocation evidence ---'
sed -n '1,100p' "$policy_events"
actual_start_events=$(
    awk '
        /policy_invocation=/ &&
        /lsyncd/ &&
        /start/ &&
        !/action16r-exit-probe/ { count++ }
        END { print count + 0 }
    ' "$policy_events"
)
[[ "$actual_start_events" -ge 1 ]]
printf 'policy_start_inhibition_events=%s\n' "$actual_start_events"

systemctl disable lsyncd.service >/dev/null 2>&1 || true
systemctl stop lsyncd.service
systemctl mask lsyncd.service
systemctl daemon-reload

rm -f -- "$policy_target"
policy_created=false
[[ ! -e "$policy_target" && ! -L "$policy_target" ]]

[[ "$(package_status lsyncd)" == 'ii ' ]]
[[ "$(package_status lua5.3)" == 'ii ' ]]
[[ "$(package_status liblua5.3-0)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' lsyncd)" == "$expected_lsyncd_version" ]]
[[ "$(dpkg-query -W -f='${Version}' lua5.3)" == "$expected_lua_version" ]]
[[ "$(dpkg-query -W -f='${Version}' liblua5.3-0)" == "$expected_lua_version" ]]
[[ "$(dpkg-query -W -f='${Architecture}' lsyncd)" == arm64 ]]
[[ "$(dpkg-query -W -f='${Architecture}' lua5.3)" == arm64 ]]
[[ "$(dpkg-query -W -f='${Architecture}' liblua5.3-0)" == arm64 ]]
[[ "$(/usr/bin/lsyncd -version 2>&1 | sed -n '1p')" == "$expected_lsyncd_binary_version" ]]
printf '%s  %s\n' "$expected_init_sha" /etc/init.d/lsyncd |
    sha256sum --check --status
for package in lsyncd lua5.3 liblua5.3-0; do
    [[ -z "$(dpkg --verify "$package")" ]]
done
[[ -z "$(dpkg --audit)" ]]

[[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
if pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected lsyncd process after inhibited installation.\n' >&2
    exit 1
fi
if find /etc -maxdepth 2 -type l \
    -path '/etc/rc*.d/S*lsyncd' -print -quit |
    grep -q .; then
    printf 'An lsyncd SysV start link remains after disablement.\n' >&2
    exit 1
fi
find /etc -maxdepth 2 -type l \
    -path '/etc/rc*.d/K*lsyncd' -print -quit |
    grep -q .

[[ "$(non_target_inventory)" == "$inventory_before" ]]
[[ "$(protected_service_state)" == "$services_before" ]]
[[ "$(ss -H -lntup | sort)" == "$listeners_before" ]]
protected_hashes_after=$(
    sha256sum -- \
        /etc/lighttpd/lighttpd.conf \
        /etc/lighttpd/conf-enabled/external.conf \
        /etc/keepalived/keepalived.conf
)
[[ "$protected_hashes_after" == "$protected_hashes_before" ]]
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected Caddy process after lsyncd installation.\n' >&2
    exit 1
fi

rm -rf -- "$work_dir"
work_dir=
transaction_complete=true
trap - EXIT
printf 'lsyncd_version=%s\n' "$(/usr/bin/lsyncd -version 2>&1 | sed -n '1p')"
printf 'lsyncd_inhibited_install_complete=true\n'
