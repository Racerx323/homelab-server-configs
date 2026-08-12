#!/usr/bin/env bash

set -Eeuo pipefail

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

# The immutable Action 28ac regression is the accepted producer-contract
# implementation. This neutral entry point is the current profile boundary.
exec /bin/bash "$test_directory/action28ac-lsyncd-command-regression.sh"
