#!/usr/bin/env bash
set -euo pipefail

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

systemctl is-active --quiet caddy
caddy validate \
    --config /etc/caddy/current/Caddyfile \
    --adapter caddyfile >/dev/null
curl \
    --insecure \
    --head \
    --fail \
    --silent \
    --show-error \
    --max-time 3 \
    https://localhost >/dev/null
