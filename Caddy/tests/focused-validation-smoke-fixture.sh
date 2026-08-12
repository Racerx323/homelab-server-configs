#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

printf 'focused_validation_smoke_fixture_container=%s\n' \
    "${CADDY_VALIDATION_CONTAINER:-0}"
printf 'focused_validation_smoke_fixture_complete=true\n'
