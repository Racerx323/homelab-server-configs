#!/usr/bin/env bash
set -euo pipefail

readonly certificate='/etc/caddy/current/tls/leaf.pem'

if [[ ! -r "$certificate" ]]; then
    printf 'Caddy certificate is unavailable: %s\n' "$certificate" >&2
    exit 1
fi

for days in 7 14 30; do
    if ! openssl x509 -in "$certificate" -checkend "$((days * 86400))" -noout; then
        printf 'Caddy certificate expires within %s days\n' "$days" >&2
        exit 1
    fi
done
