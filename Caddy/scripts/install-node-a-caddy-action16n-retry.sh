#!/usr/bin/env bash

set -euo pipefail
umask 077

expected_version=2.11.4
expected_binary_version='v2.11.4 h1:XKxkMTgNSizEvKG6QHue6cAsFOteU2qA61w2tKkCWi0='
source_target=/etc/apt/sources.list.d/caddy-stable.list
key_target=/usr/share/keyrings/caddy-stable-archive-keyring.gpg
expected_source_sha=b27d8e3f353b8e77214793ab7dfa5111cd502978461c43b4e54e0833ba49e199
expected_keyring_sha=c17cd5298a0bab02fda439fff278d9a55df2120cf9dac790c6ce71930db90b37
expected_package_sha=aeab2e38bf77a0162611a1703a5e16c09475b000d41f7edaa9337734d16642fd
baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
policy_target=/usr/sbin/policy-rc.d
work_dir=
policy_created=false
masks_created=false
package_install_started=false
transaction_complete=false

package_status() {
    dpkg-query -W -f='${db:Status-Abbrev}' caddy 2>/dev/null || true
}

non_caddy_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        awk -F '\t' '$1 != "caddy"' |
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
    printf 'caddy_install_retry_rollback_started=true\n' >&2
    rollback_failed=false

    systemctl stop caddy.service caddy-api.service >/dev/null 2>&1
    current_status=$(package_status)
    if [[ -n "$current_status" && "$current_status" != 'un ' ]]; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get purge --yes caddy
        purge_rc=$?
        if ((purge_rc != 0)); then
            rollback_failed=true
        fi
    fi

    if [[ "$policy_created" == true ]]; then
        rm -f -- "$policy_target"
        policy_created=false
    fi
    current_status=$(package_status)
    if [[ -z "$current_status" || "$current_status" == 'un ' ]]; then
        if [[ "$package_install_started" == true ]]; then
            rm -rf -- /etc/caddy /var/lib/caddy /var/log/caddy
        fi
        if [[ "$masks_created" == true ]]; then
            systemctl unmask caddy.service caddy-api.service >/dev/null 2>&1
        fi
        systemctl daemon-reload
        for target in \
            /usr/bin/caddy \
            /lib/systemd/system/caddy.service \
            /lib/systemd/system/caddy-api.service \
            /etc/systemd/system/caddy.service \
            /etc/systemd/system/caddy-api.service; do
            if [[ -e "$target" || -L "$target" ]]; then
                rollback_failed=true
            fi
        done
    else
        systemctl mask caddy.service caddy-api.service >/dev/null 2>&1
        systemctl daemon-reload
        rollback_failed=true
    fi

    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi

    if [[ -z "$current_status" || "$current_status" == 'un ' ]]; then
        if getent passwd caddy >/dev/null ||
            getent group caddy >/dev/null; then
            rollback_failed=true
        fi
        for target in \
            /usr/bin/caddy \
            /etc/caddy \
            /var/lib/caddy \
            /var/log/caddy \
            /lib/systemd/system/caddy.service \
            /lib/systemd/system/caddy-api.service \
            "$policy_target"; do
            if [[ -e "$target" || -L "$target" ]]; then
                rollback_failed=true
            fi
        done
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
    fi

    if [[ "$rollback_failed" == true ]]; then
        systemctl mask caddy.service caddy-api.service >/dev/null 2>&1
        systemctl daemon-reload
        printf 'caddy_install_retry_rollback_complete=false\n' >&2
        printf 'Caddy masks were retained for listener safety.\n' >&2
        exit 97
    fi
    printf 'caddy_install_retry_rollback_complete=true\n' >&2
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

[[ -f "$source_target" && ! -L "$source_target" ]]
[[ -f "$key_target" && ! -L "$key_target" ]]
printf '%s  %s\n' "$expected_source_sha" "$source_target" |
    sha256sum --check --status
printf '%s  %s\n' "$expected_keyring_sha" "$key_target" |
    sha256sum --check --status
initial_package_status=$(package_status)
[[ -z "$initial_package_status" || "$initial_package_status" == 'un ' ]]
if apt-mark showmanual | grep -Fxq caddy; then
    printf 'Caddy remains manually marked before retry.\n' >&2
    exit 1
fi

policy=$(apt-cache policy caddy)
candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$policy"
)
[[ "$candidate" == "$expected_version" ]]
grep -Fq 'https://dl.cloudsmith.io/public/caddy/stable/deb/debian' \
    <<<"$policy"
grep -Fxq 'Architecture: arm64' \
    < <(apt-cache show "caddy=$expected_version")

cached_package=/var/cache/apt/archives/caddy_2.11.4_arm64.deb
if [[ -e "$cached_package" || -L "$cached_package" ]]; then
    [[ -f "$cached_package" && ! -L "$cached_package" ]]
    printf '%s  %s\n' "$expected_package_sha" "$cached_package" |
        sha256sum --check --status
    printf 'accepted_caddy_apt_cache_present=true\n'
else
    printf 'accepted_caddy_apt_cache_present=false\n'
fi

if getent passwd caddy >/dev/null ||
    getent group caddy >/dev/null; then
    printf 'Unexpected active preinstallation Caddy identity.\n' >&2
    exit 1
fi
if getent group www-data |
    awk -F: '{ print $4 }' |
    tr ',' '\n' |
    grep -Fxq caddy; then
    printf 'Caddy remains in the www-data group before retry.\n' >&2
    exit 1
fi
for target in \
    /usr/bin/caddy \
    /etc/caddy \
    /var/lib/caddy \
    /var/log/caddy \
    /lib/systemd/system/caddy.service \
    /lib/systemd/system/caddy-api.service \
    /etc/systemd/system/caddy.service \
    /etc/systemd/system/caddy-api.service \
    "$policy_target"; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
for unit in caddy.service caddy-api.service; do
    [[ "$(systemctl show --property=LoadState --value "$unit")" == not-found ]]
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
done
if pgrep -x caddy >/dev/null; then
    printf 'Unexpected preinstallation Caddy process.\n' >&2
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

tcp_frontend=$(
    ss -H -ltnp |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
[[ -n "$tcp_frontend" ]]
if grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend"; then
    printf 'A non-lighttpd process owns TCP 80 or 443.\n' >&2
    exit 1
fi
grep -Eq '[[:space:]][^[:space:]]*:80[[:space:]]' <<<"$tcp_frontend"
grep -Eq '[[:space:]][^[:space:]]*:443[[:space:]]' <<<"$tcp_frontend"
udp_443=$(
    ss -H -lunp |
        awk '$4 ~ /:443$/ { print }' |
        sort
)
[[ -z "$udp_443" ]]

dpkg_audit_before=$(dpkg --audit)
[[ -z "$dpkg_audit_before" ]]
non_caddy_before=$(non_caddy_inventory)
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
    apt-get -s install --no-install-recommends "caddy=$expected_version" 2>&1
)
printf '%s\n' "$simulation"
[[ "$(
    awk '$1 == "Inst" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 1 ]]
[[ "$(
    awk '$1 == "Conf" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 1 ]]
[[ "$(
    awk '$1 == "Remv" { count++ } END { print count + 0 }' <<<"$simulation"
)" -eq 0 ]]
grep -Eq '^Inst caddy \(2[.]11[.]4 .*\[arm64\]\)$' <<<"$simulation"
grep -Fxq \
    '0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

work_dir=$(mktemp -d /tmp/caddy-inhibited-install-retry-node-a.XXXXXX)
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
"$policy_target" action16n-retry-exit-probe
policy_probe_rc=$?
set -e
[[ "$policy_probe_rc" -eq 101 ]]
printf 'policy_probe_exit=%s\n' "$policy_probe_rc"

masks_created=true
systemctl mask caddy.service caddy-api.service
systemctl daemon-reload
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" == masked ]]

install_log="$work_dir/apt-install.log"
package_install_started=true
if ! DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
    apt-get install --yes --no-install-recommends \
    "caddy=$expected_version" >"$install_log" 2>&1; then
    sed -n '1,500p' "$install_log" >&2
    exit 1
fi
sed -n '1,500p' "$install_log"
grep -Fq \
    '0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.' \
    "$install_log"

[[ -f "$policy_events" && ! -L "$policy_events" ]]
printf '%s\n' '--- policy invocation evidence ---'
sed -n '1,100p' "$policy_events"
actual_start_events=$(
    awk '
        /policy_invocation=/ &&
        /caddy[.]service/ &&
        /start/ &&
        !/action16n-retry-exit-probe/ { count++ }
        END { print count + 0 }
    ' "$policy_events"
)
[[ "$actual_start_events" -ge 1 ]]
printf 'policy_start_inhibition_events=%s\n' "$actual_start_events"

systemctl disable caddy.service caddy-api.service >/dev/null 2>&1 || true
systemctl stop caddy.service caddy-api.service
systemctl mask caddy.service caddy-api.service
systemctl daemon-reload

rm -f -- "$policy_target"
policy_created=false
[[ ! -e "$policy_target" && ! -L "$policy_target" ]]

[[ "$(package_status)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == "$expected_version" ]]
[[ "$(dpkg-query -W -f='${Architecture}' caddy)" == arm64 ]]
[[ "$(/usr/bin/caddy version)" == "$expected_binary_version" ]]
dpkg_verify=$(dpkg --verify caddy)
[[ -z "$dpkg_verify" ]]
dpkg_audit_after=$(dpkg --audit)
[[ -z "$dpkg_audit_after" ]]

non_caddy_after=$(non_caddy_inventory)
[[ "$non_caddy_after" == "$non_caddy_before" ]]
services_after=$(protected_service_state)
[[ "$services_after" == "$services_before" ]]
listeners_after=$(ss -H -lntup | sort)
[[ "$listeners_after" == "$listeners_before" ]]
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
    printf 'Unexpected Caddy process after inhibited retry.\n' >&2
    exit 1
fi

[[ "$(getent passwd caddy | cut -d: -f6)" == /var/lib/caddy ]]
[[ "$(getent passwd caddy | cut -d: -f7)" == /usr/sbin/nologin ]]
getent group caddy >/dev/null
id -nG caddy | tr ' ' '\n' | grep -Fxq www-data
[[ "$(stat -c '%U:%G:%a' /etc/caddy)" == root:root:755 ]]
[[ "$(stat -c '%U:%G:%a' /etc/caddy/Caddyfile)" == root:root:644 ]]
[[ "$(stat -c '%U:%G:%a' /var/lib/caddy)" == caddy:caddy:755 ]]
[[ "$(stat -c '%U:%G:%a' /var/log/caddy)" == caddy:caddy:755 ]]

rm -rf -- "$work_dir"
work_dir=
transaction_complete=true
trap - EXIT
printf 'caddy_version=%s\n' "$(/usr/bin/caddy version)"
printf 'caddy_inhibited_install_retry_complete=true\n'
