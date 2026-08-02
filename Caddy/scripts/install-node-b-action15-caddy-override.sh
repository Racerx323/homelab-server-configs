#!/usr/bin/env bash
set -euo pipefail

readonly stage=/var/tmp/caddy-ha-action15-remediation
readonly staged_override="$stage/override.conf"
readonly live_override=/etc/systemd/system/caddy.service.d/override.conf
readonly temporary_override=/etc/systemd/system/caddy.service.d/.override.conf.action15
readonly backup_dir=/var/backups/caddy-ha/action15-remediation-unit-override
readonly backup_override="$backup_dir/override.conf.before"
readonly current_link=/etc/caddy/current
readonly current_release=/etc/caddy/releases/bootstrap
readonly remediation_release=/etc/caddy/releases/action15-health-follow-redirects

readonly staged_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly current_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921
readonly remediation_caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly remediation_route_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c

override_replaced=false
cleanup() {
    local status=$?

    rm -f -- "$temporary_override"
    if [[ $status -ne 0 && "$override_replaced" == true ]]; then
        install -o root -g root -m 0644 "$backup_override" "$temporary_override"
        mv -f -- "$temporary_override" "$live_override"
        printf 'action_15_caddy_override_rollback_complete=true\n' >&2
    fi
    exit "$status"
}
trap cleanup EXIT

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in curl install lighttpd mv readlink rm sha256sum ss stat systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$stage" && ! -L "$stage" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:700 ]]
[[ -f "$staged_override" && ! -L "$staged_override" ]]
[[ "$(stat -c '%U:%G:%a' "$staged_override")" == root:root:600 ]]
[[ "$(sha256sum "$staged_override" | awk '{print $1}')" == "$staged_override_sha256" ]]

[[ -f "$live_override" && ! -L "$live_override" ]]
[[ "$(sha256sum "$live_override" | awk '{print $1}')" == "$current_override_sha256" ]]
[[ ! -e "$temporary_override" && ! -L "$temporary_override" ]]
[[ ! -e "$backup_dir" && ! -L "$backup_dir" ]]

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ -d "$remediation_release" && ! -L "$remediation_release" ]]
[[ -f "$remediation_release/.complete" ]]
[[ "$(sha256sum "$remediation_release/Caddyfile" | awk '{print $1}')" == "$remediation_caddyfile_sha256" ]]
[[ "$(sha256sum "$remediation_release/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$remediation_route_sha256" ]]
(
    cd "$remediation_release"
    sha256sum --check manifest.sha256
)

[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd

install -d -o root -g root -m 0700 "$backup_dir"
install -o root -g root -m 0600 "$live_override" "$backup_override"
[[ "$(sha256sum "$backup_override" | awk '{print $1}')" == "$current_override_sha256" ]]

install -o root -g root -m 0644 "$staged_override" "$temporary_override"
mv -f -- "$temporary_override" "$live_override"
override_replaced=true

[[ "$(stat -c '%U:%G:%a' "$live_override")" == root:root:644 ]]
[[ "$(sha256sum "$live_override" | awk '{print $1}')" == "$staged_override_sha256" ]]
[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
if ss -H -lntup | awk '$5 ~ /:(8080|2019)$/ {found=1} END {exit !found}'; then
    exit 1
fi
if ss -H -lunp "sport = :443" | grep -q .; then
    exit 1
fi
lighttpd -tt -f /etc/lighttpd/lighttpd.conf
curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 \
    --resolve pihole00.local.theama.co:443:10.1.0.54 \
    https://pihole00.local.theama.co/admin/ >/dev/null

printf 'override_backup=%s\n' "$backup_override"
printf 'live_override_sha256=%s\n' "$staged_override_sha256"
printf 'systemd_daemon_reload_performed=false\n'
printf 'action_15_caddy_override_install_complete=true\n'
