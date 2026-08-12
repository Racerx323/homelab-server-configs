#!/usr/bin/env bash

set -Eeuo pipefail

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

exec /bin/bash "$test_directory/action26-h3-retry-packet-connection-regression.sh"
