#!/usr/bin/env bash
set -euo pipefail

readonly current_link=/etc/caddy/current
readonly temporary_link=/etc/caddy/current.action15-new
readonly bootstrap_release=/etc/caddy/releases/bootstrap
readonly remediation_release=/etc/caddy/releases/action15-health-follow-redirects
readonly live_override=/etc/systemd/system/caddy.service.d/override.conf
readonly override_backup=/var/backups/caddy-ha/action15-remediation-unit-override/override.conf.before

readonly remediation_caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly remediation_route_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly release_manifest_sha256=c4612a541796902cdd7a58ff96e1db86485fb7d1a5d58d7dd8f41153c0e86dc3
readonly content_manifest_sha256=cd255a0c55d73f8628782ab85bdd9f0c4f3a9b866e830e7f756fc152f16eb6c2
readonly live_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly backup_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921

link_switched=false
cleanup() {
    local status=$?

    rm -f -- "$temporary_link"
    if [[ $status -ne 0 && "$link_switched" == true ]]; then
        ln -s "$bootstrap_release" "$temporary_link"
        mv -Tf -- "$temporary_link" "$current_link"
        printf 'action_15_release_selection_rollback_complete=true\n' >&2
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
for command_name in caddy curl env jq lighttpd ln mv readlink rm runuser sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$bootstrap_release" ]]
[[ ! -e "$temporary_link" && ! -L "$temporary_link" ]]
[[ -d "$remediation_release" && ! -L "$remediation_release" ]]
[[ -f "$remediation_release/.complete" ]]
[[ "$(sha256sum "$remediation_release/Caddyfile" | awk '{print $1}')" == "$remediation_caddyfile_sha256" ]]
[[ "$(sha256sum "$remediation_release/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$remediation_route_sha256" ]]
[[ "$(sha256sum "$remediation_release/release-manifest.json" | awk '{print $1}')" == "$release_manifest_sha256" ]]
[[ "$(sha256sum "$remediation_release/manifest.sha256" | awk '{print $1}')" == "$content_manifest_sha256" ]]
[[ "$(jq -r '.revision' "$remediation_release/release-manifest.json")" == action15-health-follow-redirects ]]
[[ "$(jq -r '.parent_revision' "$remediation_release/release-manifest.json")" == '' ]]
[[ "$(jq -r '.parent_path' "$remediation_release/release-manifest.json")" == "$bootstrap_release" ]]
(
    cd "$remediation_release"
    sha256sum --check manifest.sha256
)

[[ "$(sha256sum "$live_override" | awk '{print $1}')" == "$live_override_sha256" ]]
[[ "$(sha256sum "$override_backup" | awk '{print $1}')" == "$backup_override_sha256" ]]
[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a
runuser -u caddy -- \
    env CADDY_CONFIG_ROOT="$remediation_release" \
    caddy validate --config "$remediation_release/Caddyfile" --adapter caddyfile

ln -s "$remediation_release" "$temporary_link"
mv -Tf -- "$temporary_link" "$current_link"
link_switched=true

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$remediation_release" ]]
runuser -u caddy -- \
    env CADDY_CONFIG_ROOT="$current_link" \
    caddy validate --config "$current_link/Caddyfile" --adapter caddyfile
(
    cd "$current_link"
    sha256sum --check manifest.sha256
)

[[ "$(sha256sum "$live_override" | awk '{print $1}')" == "$live_override_sha256" ]]
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

printf 'previous_release=%s\n' "$bootstrap_release"
printf 'selected_release=%s\n' "$(readlink -e "$current_link")"
printf 'systemd_daemon_reload_performed=false\n'
printf 'action_15_remediation_release_selection_complete=true\n'
