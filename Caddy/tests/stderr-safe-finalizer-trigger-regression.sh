#!/usr/bin/env bash

set -Eeuo pipefail

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

# Preserve the executed regression while exposing its accepted finalizer
# contract through a lifecycle-neutral current-production entry point.
exec /bin/bash "$test_directory/action28ac-stderr-safe-finalizer-trigger-regression.sh"
