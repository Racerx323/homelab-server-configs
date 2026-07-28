#!/usr/bin/env bash
set -euo pipefail

readonly certificate='/etc/caddy/current/tls/leaf.pem'

if [[ ! -r "$certificate" ]]; then
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "Caddy certificate is unavailable: $certificate"
    exit 1
fi

for days in 7 14 30; do
    if ! openssl x509 -in "$certificate" -checkend "$((days * 86400))" -noout; then
        /usr/local/libexec/lsyncd-sync-failure-notify.sh \
            "Caddy certificate expires within $days days"
        exit 1
    fi
done
