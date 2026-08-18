#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_installation_production_path_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly successor_registry=$repository_root/Caddy/manifests/deployable-successor.tsv

IFS=$'\t' read -r successor_status successor_action transaction_relative outer_relative < <(
    awk -F '\t' 'NR == 2 { print $2 "\t" $3 "\t" $5 "\t" $6 }' \
        "$successor_registry"
)

[[ "$successor_status" = none ]]
[[ "$successor_action" = - ]]
[[ "$transaction_relative" = - ]]
[[ "$outer_relative" = - ]]

printf '%s_no_registered_successor=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
