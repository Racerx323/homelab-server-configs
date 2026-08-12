#!/usr/bin/env bash

set -Eeuo pipefail

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

exec /bin/bash "$test_directory/action29b-pihole-v5-config-regression.sh"
