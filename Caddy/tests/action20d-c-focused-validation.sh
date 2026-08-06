#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly probe="$caddy_root/scripts/inspect-caddy-notifier-context-action20d-c.sh"
readonly runner="$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh"
readonly outer="$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-outer.sh"
readonly regression="$test_directory/action20d-c-dual-node-notifier-context-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly outer_policy="$test_directory/outer-local-gate-label-policy-regression.sh"

bash -n "$probe" "$runner" "$outer" "$regression"
shellcheck "$probe" "$runner" "$outer" "$regression"
/bin/bash "$collision_checker" "$probe" "$runner" "$outer" "$regression"
/bin/bash "$outer_policy" --runner "$outer"
printf 'action_20d_c_focused_validation_complete=true\n'
