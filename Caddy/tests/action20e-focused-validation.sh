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
readonly installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e.sh
readonly transaction_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e.sh
readonly transaction_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-outer.sh
readonly inspector=$caddy_root/scripts/inspect-caddy-runtime-directories-action20e-a.sh
readonly acceptance_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-a.sh
readonly acceptance_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-a-outer.sh
readonly regression=$test_directory/action20e-runtime-directories-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20e_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20e_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20e_focused_%s=false\n' "$validation_label" >&2
    return 1
}

run_validation installer_syntax /bin/bash -n "$installer"
run_validation transaction_runner_syntax /bin/bash -n "$transaction_runner"
run_validation transaction_outer_syntax /bin/bash -n "$transaction_outer"
run_validation inspector_syntax /bin/bash -n "$inspector"
run_validation acceptance_runner_syntax /bin/bash -n "$acceptance_runner"
run_validation acceptance_outer_syntax /bin/bash -n "$acceptance_outer"
run_validation regression_syntax /bin/bash -n "$regression"
run_validation installer_shellcheck shellcheck "$installer"
run_validation transaction_runner_shellcheck shellcheck "$transaction_runner"
run_validation transaction_outer_shellcheck shellcheck "$transaction_outer"
run_validation inspector_shellcheck shellcheck "$inspector"
run_validation acceptance_runner_shellcheck shellcheck "$acceptance_runner"
run_validation acceptance_outer_shellcheck shellcheck "$acceptance_outer"
run_validation regression_shellcheck shellcheck "$regression"
run_validation readonly_local_collision_policy /bin/bash "$collision" \
    "$installer" "$transaction_runner" "$transaction_outer" "$inspector" \
    "$acceptance_runner" "$acceptance_outer" "$regression"
run_validation transaction_outer_self_test /bin/bash "$transaction_outer" --self-test
run_validation acceptance_outer_self_test /bin/bash "$acceptance_outer" --self-test
run_validation transaction_outer_label_policy /bin/bash "$outer_policy" \
    --runner "$transaction_outer"
run_validation acceptance_outer_label_policy /bin/bash "$outer_policy" \
    --runner "$acceptance_outer"
run_validation production_path_regression /bin/bash "$regression"
printf 'action_20e_focused_validation_complete=true\n'
