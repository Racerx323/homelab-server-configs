#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --payload DIRECTORY\n' "${0##*/}"
}

payload=
while (($#)); do
    case "$1" in
        --payload)
            payload=${2:-}
            shift 2
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

readonly current_release=/etc/caddy/releases/bootstrap
readonly current_link=/etc/caddy/current
readonly current_override=/etc/systemd/system/caddy.service.d/override.conf
readonly stage=/var/tmp/caddy-ha-action15-remediation

readonly desired_caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly desired_route_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly desired_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly current_caddyfile_sha256=a42cd4d0c35352b1efe428698e5e0a6946476ab81c77caae607b58e13ef5cc02
readonly current_route_sha256=4b51ce90cc9015579eb441538d44b43165572c9298bff7a78b79fed732373b7c
readonly current_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921

created=false
temporary_config=
cleanup() {
    local status=$?

    if [[ -n "$temporary_config" && -d "$temporary_config" ]]; then
        rm -rf -- "$temporary_config"
    fi
    if [[ $status -ne 0 && "$created" == true ]]; then
        rm -rf -- "$stage"
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
[[ -n "$payload" && -d "$payload" && ! -L "$payload" ]]
for command_name in caddy curl env install lighttpd mktemp readlink rm runuser sha256sum ss stat systemctl; do
    command -v "$command_name" >/dev/null
done

readonly payload_caddyfile="$payload/configs/caddy/Caddyfile"
readonly payload_route="$payload/configs/caddy/conf.d/10-pihole-admin.caddy"
readonly payload_override="$payload/systemd/caddy.service.d/override.conf"

[[ -f "$payload_caddyfile" && ! -L "$payload_caddyfile" ]]
[[ -f "$payload_route" && ! -L "$payload_route" ]]
[[ -f "$payload_override" && ! -L "$payload_override" ]]
[[ "$(sha256sum "$payload_caddyfile" | awk '{print $1}')" == "$desired_caddyfile_sha256" ]]
[[ "$(sha256sum "$payload_route" | awk '{print $1}')" == "$desired_route_sha256" ]]
[[ "$(sha256sum "$payload_override" | awk '{print $1}')" == "$desired_override_sha256" ]]

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(sha256sum "$current_release/Caddyfile" | awk '{print $1}')" == "$current_caddyfile_sha256" ]]
[[ "$(sha256sum "$current_release/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$current_route_sha256" ]]
[[ "$(sha256sum "$current_override" | awk '{print $1}')" == "$current_override_sha256" ]]
[[ ! -e "$stage" && ! -L "$stage" ]]

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

install -d -o root -g root -m 0700 "$stage"
created=true
install -o root -g root -m 0600 "$payload_caddyfile" "$stage/Caddyfile"
install -o root -g root -m 0600 "$payload_route" "$stage/10-pihole-admin.caddy"
install -o root -g root -m 0600 "$payload_override" "$stage/override.conf"

[[ "$(sha256sum "$stage/Caddyfile" | awk '{print $1}')" == "$desired_caddyfile_sha256" ]]
[[ "$(sha256sum "$stage/10-pihole-admin.caddy" | awk '{print $1}')" == "$desired_route_sha256" ]]
[[ "$(sha256sum "$stage/override.conf" | awk '{print $1}')" == "$desired_override_sha256" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:700 ]]
for staged_file in "$stage/Caddyfile" "$stage/10-pihole-admin.caddy" "$stage/override.conf"; do
    [[ "$(stat -c '%U:%G:%a' "$staged_file")" == root:root:600 ]]
done

temporary_config=$(mktemp -d /var/tmp/.caddy-action15-validate.XXXXXX)
install -d -o root -g caddy-tls -m 0750 \
    "$temporary_config" \
    "$temporary_config/conf.d" \
    "$temporary_config/tls"
install -o root -g root -m 0644 "$stage/Caddyfile" "$temporary_config/Caddyfile"
install -o root -g root -m 0644 \
    "$current_release/conf.d/00-health.caddy" \
    "$temporary_config/conf.d/00-health.caddy"
install -o root -g root -m 0644 \
    "$stage/10-pihole-admin.caddy" \
    "$temporary_config/conf.d/10-pihole-admin.caddy"
install -o root -g root -m 0644 \
    "$current_release/conf.d/90-default-deny.caddy" \
    "$temporary_config/conf.d/90-default-deny.caddy"
for tls_file in certificate-manifest.json fullchain.pem intermediates.pem leaf.pem; do
    install -o root -g root -m 0644 \
        "$current_release/tls/$tls_file" \
        "$temporary_config/tls/$tls_file"
done
install -o root -g caddy-tls -m 0640 \
    "$current_release/tls/privkey.pem" \
    "$temporary_config/tls/privkey.pem"

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a
runuser -u caddy -- \
    env CADDY_CONFIG_ROOT="$temporary_config" \
    caddy validate --config "$temporary_config/Caddyfile" --adapter caddyfile
rm -rf -- "$temporary_config"
temporary_config=

[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(sha256sum "$current_override" | awk '{print $1}')" == "$current_override_sha256" ]]
[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd

printf 'staged_caddyfile_sha256=%s\n' "$desired_caddyfile_sha256"
printf 'staged_route_sha256=%s\n' "$desired_route_sha256"
printf 'staged_override_sha256=%s\n' "$desired_override_sha256"
printf 'action_15_caddy_remediation_stage_complete=true\n'
