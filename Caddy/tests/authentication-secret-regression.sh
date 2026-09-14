#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
auth_secret_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly auth_secret_test_directory
exec python3 "$auth_secret_test_directory/authentication-secret-regression.py"
