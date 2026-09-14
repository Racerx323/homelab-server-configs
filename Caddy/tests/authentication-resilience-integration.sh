#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
[[ ${CADDY_VALIDATION_CONTAINER:-} = 1 ]] || {
    printf 'Run in the isolated authentication validation container.\n' >&2
    exit 64
}
auth_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly auth_test_directory
exec python3 "$auth_test_directory/authentication-resilience-integration.py"
