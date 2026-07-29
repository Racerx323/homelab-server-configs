#!/usr/bin/env bash

set -euo pipefail
umask 077

expected_version=2.38.1-5+deb12u3
expected_init_sha=4b93a446c6094a1ea265699d794171f358ea611d974eae6f728652c81e3df6ad
expected_service_sha=a8090eeb6f09b0e895c97e2f27f9c656b27c269d3755f8da26e7f85f3aaaa4b9
expected_socket_sha=21f7cc7b5ffaf73b27f00689e628797a2be947df144b1a0f7ba9356c8d0a4897
baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
policy_target=/usr/sbin/policy-rc.d
work_dir=
policy_created=false
package_install_started=false
transaction_complete=false

package_status() {
    dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime 2>/dev/null || true
}

non_target_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        awk -F '\t' '$1 !~ /^uuid-runtime(:arm64)?$/' |
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

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

rollback() {
    original_rc=$?
    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        return
    fi

    set +e
    printf 'uuid_runtime_install_rollback_started=true\n' >&2
    rollback_failed=false

    systemctl stop uuidd.socket uuidd.service >/dev/null 2>&1
    systemctl mask uuidd.service uuidd.socket >/dev/null 2>&1
    systemctl daemon-reload

    if [[ "$policy_created" == true ]]; then
        rm -f -- "$policy_target"
        policy_created=false
    fi

    current_status=$(package_status)
    if [[ -n "$current_status" && "$current_status" != 'un ' ]]; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
            apt-get purge --yes uuid-runtime
        purge_rc=$?
        if ((purge_rc != 0)); then
            rollback_failed=true
        fi
    fi

    current_status=$(package_status)
    if [[ -z "$current_status" || "$current_status" == 'un ' ]]; then
        if [[ "$package_install_started" == true ]]; then
            if pgrep -x uuidd >/dev/null; then
                pkill -x uuidd
            fi
            if getent passwd uuidd >/dev/null; then
                if ! userdel uuidd; then
                    rollback_failed=true
                fi
            fi
            if getent group uuidd >/dev/null; then
                if ! groupdel uuidd; then
                    rollback_failed=true
                fi
            fi
            rm -rf -- /var/lib/libuuid /run/uuidd
        fi

        systemctl mask uuidd.service uuidd.socket >/dev/null 2>&1
        systemctl daemon-reload
        for target in \
            /usr/bin/uuidgen \
            /usr/bin/uuidparse \
            /usr/sbin/uuidd \
            /etc/init.d/uuidd \
            /lib/systemd/system/uuidd.service \
            /lib/systemd/system/uuidd.socket \
            "$policy_target"; do
            if [[ -e "$target" || -L "$target" ]]; then
                rollback_failed=true
            fi
        done
        if [[ -e /var/lib/libuuid || -L /var/lib/libuuid ]] ||
            getent passwd uuidd >/dev/null ||
            getent group uuidd >/dev/null ||
            pgrep -x uuidd >/dev/null; then
            rollback_failed=true
        fi
        if find /etc -maxdepth 2 -type l \
            -path '/etc/rc*.d/*uuidd' -print -quit |
            grep -q .; then
            rollback_failed=true
        fi
        assert_masked_inactive uuidd.service || rollback_failed=true
        assert_masked_inactive uuidd.socket || rollback_failed=true
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
        rollback_failed=true
    fi

    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi

    if [[ "$rollback_failed" == true ]]; then
        systemctl mask uuidd.service uuidd.socket >/dev/null 2>&1
        systemctl daemon-reload
        printf 'uuid_runtime_install_rollback_complete=false\n' >&2
        printf 'uuidd masks were retained for service safety.\n' >&2
        exit 97
    fi
    printf 'uuid_runtime_install_rollback_complete=true\n' >&2
    printf 'uuidd masks were retained pending independent inspection.\n' >&2
    exit "$original_rc"
}

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

initial_status=$(package_status)
[[ -z "$initial_status" || "$initial_status" == 'un ' ]]
uuid_policy=$(apt-cache policy uuid-runtime)
candidate=$(
    awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<<"$uuid_policy"
)
[[ "$candidate" == "$expected_version" ]]

if getent passwd uuidd >/dev/null ||
    getent group uuidd >/dev/null; then
    printf 'Unexpected uuidd identity before installation.\n' >&2
    exit 1
fi
for target in \
    /var/lib/libuuid \
    /usr/bin/uuidgen \
    /usr/bin/uuidparse \
    /usr/sbin/uuidd \
    /etc/init.d/uuidd \
    /lib/systemd/system/uuidd.service \
    /lib/systemd/system/uuidd.socket \
    /etc/systemd/system/uuidd.service \
    /etc/systemd/system/uuidd.socket \
    "$policy_target"; do
    [[ ! -e "$target" && ! -L "$target" ]]
done
for unit in uuidd.service uuidd.socket; do
    [[ "$(systemctl show --property=LoadState --value "$unit")" == not-found ]]
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    enabled=$(
        systemctl is-enabled "$unit" 2>/dev/null ||
            true
    )
    [[ -z "$enabled" || "$enabled" == not-found ]]
done
if pgrep -x uuidd >/dev/null; then
    printf 'Unexpected uuidd process before installation.\n' >&2
    exit 1
fi
if find /etc -maxdepth 4 -type l \
    \( -name 'uuidd.service' -o -name 'uuidd.socket' \
    -o -name '[SK][0-9][0-9]uuidd' \) \
    -print -quit |
    grep -q .; then
    printf 'Unexpected uuidd link before installation.\n' >&2
    exit 1
fi
if find /tmp -mindepth 1 -maxdepth 1 \
    -name 'uuid-runtime-*' -print -quit |
    grep -q .; then
    printf 'Unexpected uuid-runtime staging before installation.\n' >&2
    exit 1
fi

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' caddy)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' caddy)" == 2.11.4 ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' lsyncd)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' lsyncd)" == 2.2.3-1 ]]
for unit in caddy.service caddy-api.service lsyncd.service; do
    assert_masked_inactive "$unit"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected Caddy or lsyncd process before installation.\n' >&2
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
        "uuid-runtime=$expected_version" 2>&1
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
grep -Eq \
    '^Inst uuid-runtime \(2[.]38[.]1-5[+]deb12u3 .*\[arm64\]\)$' \
    <<<"$simulation"
grep -Fxq \
    '0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.' \
    <<<"$simulation"

work_dir=$(mktemp -d /tmp/uuid-runtime-inhibited-install-node-a.XXXXXX)
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
"$policy_target" action16w-exit-probe
policy_probe_rc=$?
set -e
[[ "$policy_probe_rc" -eq 101 ]]
printf 'policy_probe_exit=%s\n' "$policy_probe_rc"

systemctl mask uuidd.service uuidd.socket
systemctl daemon-reload
assert_masked_inactive uuidd.service
assert_masked_inactive uuidd.socket

install_log="$work_dir/apt-install.log"
package_install_started=true
if ! DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
    apt-get install --yes --no-install-recommends \
    "uuid-runtime=$expected_version" >"$install_log" 2>&1; then
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
        /uuidd/ &&
        /start/ &&
        !/action16w-exit-probe/ { count++ }
        END { print count + 0 }
    ' "$policy_events"
)
[[ "$actual_start_events" -ge 1 ]]
printf 'policy_start_inhibition_events=%s\n' "$actual_start_events"

systemctl disable uuidd.service uuidd.socket >/dev/null 2>&1 || true
update-rc.d uuidd disable
systemctl stop uuidd.socket uuidd.service
systemctl mask uuidd.service uuidd.socket
systemctl daemon-reload

rm -f -- "$policy_target"
policy_created=false
[[ ! -e "$policy_target" && ! -L "$policy_target" ]]

[[ "$(package_status)" == 'ii ' ]]
[[ "$(dpkg-query -W -f='${Version}' uuid-runtime)" == "$expected_version" ]]
[[ "$(dpkg-query -W -f='${Architecture}' uuid-runtime)" == arm64 ]]
[[ -z "$(dpkg --verify uuid-runtime)" ]]
[[ -z "$(dpkg --audit)" ]]

uuidgen_version=$(/usr/bin/uuidgen --version)
uuidparse_version=$(/usr/bin/uuidparse --version)
uuidd_version=$(/usr/sbin/uuidd --version)
grep -Fxq 'uuidgen from util-linux 2.38.1' <<<"$uuidgen_version"
grep -Fxq 'uuidparse from util-linux 2.38.1' <<<"$uuidparse_version"
grep -Fxq 'uuidd from util-linux 2.38.1' <<<"$uuidd_version"

printf '%s  %s\n' "$expected_init_sha" /etc/init.d/uuidd |
    sha256sum --check --status
printf '%s  %s\n' "$expected_service_sha" \
    /lib/systemd/system/uuidd.service |
    sha256sum --check --status
printf '%s  %s\n' "$expected_socket_sha" \
    /lib/systemd/system/uuidd.socket |
    sha256sum --check --status

uuidd_passwd=$(getent passwd uuidd)
uuidd_group=$(getent group uuidd)
[[ -n "$uuidd_passwd" && -n "$uuidd_group" ]]
[[ "$(cut -d: -f1 <<<"$uuidd_passwd")" == uuidd ]]
[[ "$(cut -d: -f6 <<<"$uuidd_passwd")" == /run/uuidd ]]
[[ "$(cut -d: -f1 <<<"$uuidd_group")" == uuidd ]]
uuidd_uid=$(cut -d: -f3 <<<"$uuidd_passwd")
uuidd_primary_gid=$(cut -d: -f4 <<<"$uuidd_passwd")
uuidd_group_gid=$(cut -d: -f3 <<<"$uuidd_group")
[[ "$uuidd_uid" =~ ^[0-9]+$ && "$uuidd_uid" -ne 0 ]]
[[ "$uuidd_primary_gid" == "$uuidd_group_gid" ]]
uuidd_password_state=$(passwd -S uuidd)
[[ "$(awk '{ print $2 }' <<<"$uuidd_password_state")" == L ]]
[[ "$(stat -c '%U:%G %a' /var/lib/libuuid)" == 'uuidd:uuidd 2775' ]]

assert_masked_inactive uuidd.service
assert_masked_inactive uuidd.socket
if pgrep -x uuidd >/dev/null; then
    printf 'Unexpected uuidd process after inhibited installation.\n' >&2
    exit 1
fi
if find /etc -maxdepth 2 -type l \
    -path '/etc/rc*.d/S*uuidd' -print -quit |
    grep -q .; then
    printf 'A uuidd SysV start link remains after disablement.\n' >&2
    exit 1
fi
find /etc -maxdepth 2 -type l \
    -path '/etc/rc*.d/K*uuidd' -print -quit |
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
for unit in caddy.service caddy-api.service lsyncd.service; do
    assert_masked_inactive "$unit"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null; then
    printf 'Unexpected Caddy or lsyncd process after installation.\n' >&2
    exit 1
fi

rm -rf -- "$work_dir"
work_dir=
transaction_complete=true
trap - EXIT
printf 'uuidgen_version=%s\n' "$uuidgen_version"
printf 'uuidd_identity=%s\n' "$uuidd_passwd"
printf 'uuidd_state_directory=%s\n' \
    "$(stat -c '%U:%G:%a' /var/lib/libuuid)"
printf 'uuid_runtime_inhibited_install_complete=true\n'
