#!/usr/bin/env bash
set -euo pipefail

readonly current_release=/etc/caddy/releases/bootstrap
readonly current_link=/etc/caddy/current
readonly current_override=/etc/systemd/system/caddy.service.d/override.conf
readonly stage=/var/tmp/caddy-ha-action15-remediation
readonly release=/etc/caddy/releases/action15-health-follow-redirects
readonly release_staging=/etc/caddy/releases/.action15-health-follow-redirects.staging

readonly staged_caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly staged_route_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly staged_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly current_caddyfile_sha256=a42cd4d0c35352b1efe428698e5e0a6946476ab81c77caae607b58e13ef5cc02
readonly current_route_sha256=4b51ce90cc9015579eb441538d44b43165572c9298bff7a78b79fed732373b7c
readonly current_override_sha256=82535a41bbcbc18e4a875f5359bac3c27071c9472feee5c3232d06a138e99921

created_staging=false
created_release=false
rollback() {
    local status=$?

    if [[ $status -ne 0 ]]; then
        if [[ "$created_staging" == true ]]; then
            rm -rf -- "$release_staging"
        fi
        if [[ "$created_release" == true ]]; then
            rm -rf -- "$release"
        fi
    fi
    exit "$status"
}
trap rollback EXIT

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

[[ $EUID -eq 0 ]]
for command_name in caddy chmod chown cp curl date env find install jq lighttpd mv readlink rm runuser sha256sum sort ss stat systemctl touch xargs; do
    command -v "$command_name" >/dev/null
done

[[ -d "$stage" && ! -L "$stage" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:700 ]]
[[ "$(sha256sum "$stage/Caddyfile" | awk '{print $1}')" == "$staged_caddyfile_sha256" ]]
[[ "$(sha256sum "$stage/10-pihole-admin.caddy" | awk '{print $1}')" == "$staged_route_sha256" ]]
[[ "$(sha256sum "$stage/override.conf" | awk '{print $1}')" == "$staged_override_sha256" ]]
for staged_file in "$stage/Caddyfile" "$stage/10-pihole-admin.caddy" "$stage/override.conf"; do
    [[ "$(stat -c '%U:%G:%a' "$staged_file")" == root:root:600 ]]
done

[[ -L "$current_link" ]]
[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(sha256sum "$current_release/Caddyfile" | awk '{print $1}')" == "$current_caddyfile_sha256" ]]
[[ "$(sha256sum "$current_release/conf.d/10-pihole-admin.caddy" | awk '{print $1}')" == "$current_route_sha256" ]]
[[ "$(sha256sum "$current_override" | awk '{print $1}')" == "$current_override_sha256" ]]
[[ ! -e "$release" && ! -L "$release" ]]
[[ ! -e "$release_staging" && ! -L "$release_staging" ]]

[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
[[ "$(systemctl is-enabled lighttpd.service)" == enabled ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd

install -d -o root -g caddy-tls -m 0750 "$release_staging"
created_staging=true
cp -a -- "$current_release/." "$release_staging/"
install -o root -g root -m 0644 "$stage/Caddyfile" "$release_staging/Caddyfile"
install -o root -g root -m 0644 \
    "$stage/10-pihole-admin.caddy" \
    "$release_staging/conf.d/10-pihole-admin.caddy"

rm -f -- \
    "$release_staging/.complete" \
    "$release_staging/manifest.sha256" \
    "$release_staging/release-manifest.json"
jq -n \
    --arg revision action15-health-follow-redirects \
    --arg parent_revision '' \
    --arg parent_path "$current_release" \
    --arg source_node node-b \
    --arg created_at "$(date --iso-8601=seconds)" \
    '{
        revision: $revision,
        parent_revision: $parent_revision,
        parent_path: $parent_path,
        source_node: $source_node,
        created_at: $created_at,
        deployment_action: "15-remediation"
    }' >"$release_staging/release-manifest.json"

(
    cd "$release_staging"
    find . -type f \
        ! -name manifest.sha256 \
        ! -name .complete \
        -print0 |
        sort -z |
        xargs -0 sha256sum
) >"$release_staging/manifest.sha256"
touch "$release_staging/.complete"

chown -R root:caddy-tls "$release_staging"
find "$release_staging" -type d -exec chmod 0550 {} +
find "$release_staging" -type f -exec chmod 0440 {} +

(
    cd "$release_staging"
    sha256sum --check manifest.sha256
)
set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a
runuser -u caddy -- \
    env CADDY_CONFIG_ROOT="$release_staging" \
    caddy validate --config "$release_staging/Caddyfile" --adapter caddyfile

mv -- "$release_staging" "$release"
created_staging=false
created_release=true

[[ "$(stat -c '%U:%G:%a' "$release")" == root:caddy-tls:550 ]]
[[ -f "$release/.complete" ]]
[[ "$(jq -r '.revision' "$release/release-manifest.json")" == action15-health-follow-redirects ]]
[[ "$(jq -r '.parent_revision' "$release/release-manifest.json")" == '' ]]
[[ "$(jq -r '.parent_path' "$release/release-manifest.json")" == "$current_release" ]]
(
    cd "$release"
    sha256sum --check manifest.sha256
)
runuser -u caddy -- \
    env CADDY_CONFIG_ROOT="$release" \
    caddy validate --config "$release/Caddyfile" --adapter caddyfile

[[ "$(readlink -e "$current_link")" == "$current_release" ]]
[[ "$(sha256sum "$current_override" | awk '{print $1}')" == "$current_override_sha256" ]]
[[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lighttpd.service)" == active ]]
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

printf 'release_path=%s\n' "$release"
printf 'release_manifest_sha256=%s\n' \
    "$(sha256sum "$release/release-manifest.json" | awk '{print $1}')"
printf 'content_manifest_sha256=%s\n' \
    "$(sha256sum "$release/manifest.sha256" | awk '{print $1}')"
printf 'action_15_remediation_release_install_complete=true\n'
