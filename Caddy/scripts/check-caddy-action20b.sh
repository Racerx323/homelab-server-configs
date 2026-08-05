#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

runtime_root=$(mktemp -d /tmp/caddy-health.XXXXXX)
readonly runtime_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$runtime_root"
}
trap cleanup EXIT INT TERM

install -d -m 0700 \
    "$runtime_root/home" \
    "$runtime_root/config" \
    "$runtime_root/data"
HOME=$runtime_root/home
XDG_CONFIG_HOME=$runtime_root/config
XDG_DATA_HOME=$runtime_root/data
export HOME XDG_CONFIG_HOME XDG_DATA_HOME

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

systemctl is-active --quiet caddy
validation_status=0
caddy validate \
    --config /etc/caddy/current/Caddyfile \
    --adapter caddyfile \
    >"$runtime_root/validation.stdout" \
    2>"$runtime_root/validation.stderr" || validation_status=$?
readonly validation_status
if [[ "$validation_status" -ne 0 ]]; then
    cat "$runtime_root/validation.stderr" >&2
    exit "$validation_status"
fi
curl \
    --insecure \
    --head \
    --fail \
    --silent \
    --show-error \
    --max-time 3 \
    https://localhost >/dev/null
