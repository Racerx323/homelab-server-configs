#!/usr/bin/env bash

set -Eeuo pipefail

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

# The accepted Action 24 producer regression remains immutable; current
# selection consumes its reverse-query contract through this neutral boundary.
exec /bin/bash "$test_directory/action24-retry-dig-x-regression.sh"
