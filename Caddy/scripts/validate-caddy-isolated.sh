#!/usr/bin/env bash

# Owner callers require this helper installed before their separately approved rollout.
set -Eeuo pipefail
set +x

if [[ $# != 1 || $1 != /* ]]; then
    printf 'Usage: %s /absolute/path/to/Caddyfile\n' "${0##*/}" >&2
    exit 64
fi

# Root must retain its original user namespace to read receiver-owned inputs.
# The unprivileged caller maps only its existing effective UID/GID. Supplementary
# kernel groups remain, even though unmapped group names appear as overflow IDs.
# No fork: unshare execs the validator, preserving status and signal delivery.
if ((EUID == 0)); then
    exec /usr/bin/unshare --net -- /usr/bin/caddy validate --config "$1" --adapter caddyfile
else
    exec /usr/bin/unshare --user --map-current-user --net -- \
        /usr/bin/caddy validate --config "$1" --adapter caddyfile
fi
