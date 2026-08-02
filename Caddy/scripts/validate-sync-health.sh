#!/usr/bin/env bash
set -euo pipefail

readonly status_file='/run/caddy-lsyncd/status'
readonly max_status_age=120

if ! systemctl is-active --quiet caddy-lsyncd.service; then
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        'caddy-lsyncd.service is not active'
    exit 1
fi

if [[ ! -s "$status_file" ]]; then
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "lsyncd status file is missing or empty: $status_file"
    exit 1
fi

now=$(date +%s)
modified=$(stat -c %Y "$status_file")
if ((now - modified > max_status_age)); then
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "lsyncd status file is older than $max_status_age seconds"
    exit 1
fi
