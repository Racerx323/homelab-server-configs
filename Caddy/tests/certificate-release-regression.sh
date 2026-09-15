#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
    printf 'certificate_release_host_deferred_to_debian=true\n'
    exit 0
fi
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/certificate-release-regression.py"
