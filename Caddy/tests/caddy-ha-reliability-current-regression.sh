#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory

/bin/bash "$script_directory/caddy-ha-reliability-action33o-regression.sh"
printf 'caddy_ha_reliability_current_regression_complete=true\n'
