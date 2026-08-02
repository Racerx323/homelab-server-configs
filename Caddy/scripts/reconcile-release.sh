#!/usr/bin/env bash
set -euo pipefail

readonly incoming_root='/var/lib/caddy-sync/incoming'
readonly releases_root='/etc/caddy/releases'
readonly quarantine_root='/var/lib/caddy-sync/quarantine'

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

install -d -m 0750 "$releases_root" "$quarantine_root"

candidate=$(
    {
        find "$incoming_root" \
            -mindepth 2 \
            -maxdepth 2 \
            -type d \
            -print 2>/dev/null || true
    } |
        sort |
        tail -n 1
)

if [[ -z "$candidate" || ! -f "$candidate/.complete" ]]; then
    exit 0
fi

revision=$(jq -r '.revision // empty' "$candidate/release-manifest.json")
parent_revision=$(jq -r '.parent_revision // ""' "$candidate/release-manifest.json")
if [[ -z "$revision" || "$candidate" != */"$revision" ]]; then
    printf 'Release manifest does not match candidate directory.\n' >&2
    exit 1
fi

active_revision=
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    active_revision=$(jq -r '.revision // ""' /etc/caddy/current/release-manifest.json)
fi

if [[ -n "$active_revision" && "$parent_revision" != "$active_revision" ]]; then
    quarantine_path="$quarantine_root/$revision"
    mv -- "$candidate" "$quarantine_path"
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "Quarantined divergent release $revision; expected parent $active_revision"
    exit 1
fi

(
    cd "$candidate"
    sha256sum --check manifest.sha256
)
CADDY_CONFIG_ROOT="$candidate" \
    caddy validate --config "$candidate/Caddyfile" --adapter caddyfile >/dev/null

destination="$releases_root/$revision"
if [[ ! -d "$destination" ]]; then
    cp -a -- "$candidate" "$destination"
fi
chown -R root:caddy-tls "$destination"
find "$destination" -type d -exec chmod 0550 {} +
find "$destination" -type f -exec chmod 0440 {} +
ln -sfn "$destination" /etc/caddy/current.new
mv -Tf /etc/caddy/current.new /etc/caddy/current
systemctl reload caddy.service
printf 'Activated release %s\n' "$revision"
