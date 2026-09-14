#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
[[ ${CADDY_VALIDATION_CONTAINER:-} = 1 && -f /run/.containerenv ]] || exit 64
auth_release_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly auth_release_test_directory
exec python3 "$auth_release_test_directory/authentication-release-regression.py"
