#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
auth_deployment_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly auth_deployment_test_directory
exec /bin/bash "$auth_deployment_test_directory/../scripts/run-serving-health-deployment-outer.sh" \
    --authentication-helper-test
