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
readonly installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry-outer.sh
readonly acceptance_inspector=$caddy_root/scripts/inspect-caddy-runtime-directories-action20e-retry-a.sh
readonly acceptance_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry-a.sh
readonly acceptance_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry-a-outer.sh
readonly regression=$test_directory/action20e-retry-runtime-directories-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh
readonly historical_installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e.sh
readonly historical_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-outer.sh
readonly historical_regression=$test_directory/action20e-runtime-directories-regression.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20e_retry_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20e_retry_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20e_retry_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_path=$2

    [[ "$(sha256sum "$inspected_path" | awk '{ print $1 }')" = "$expected_hash" ]]
}

run_validation installer_syntax /bin/bash -n "$installer"
run_validation runner_syntax /bin/bash -n "$runner"
run_validation outer_syntax /bin/bash -n "$outer"
run_validation acceptance_inspector_syntax /bin/bash -n "$acceptance_inspector"
run_validation acceptance_runner_syntax /bin/bash -n "$acceptance_runner"
run_validation acceptance_outer_syntax /bin/bash -n "$acceptance_outer"
run_validation regression_syntax /bin/bash -n "$regression"
run_validation installer_shellcheck shellcheck "$installer"
run_validation runner_shellcheck shellcheck "$runner"
run_validation outer_shellcheck shellcheck "$outer"
run_validation acceptance_inspector_shellcheck shellcheck "$acceptance_inspector"
run_validation acceptance_runner_shellcheck shellcheck "$acceptance_runner"
run_validation acceptance_outer_shellcheck shellcheck "$acceptance_outer"
run_validation regression_shellcheck shellcheck "$regression"
run_validation readonly_local_collision_policy /bin/bash "$collision" \
    "$installer" "$runner" "$outer" "$acceptance_inspector" \
    "$acceptance_runner" "$acceptance_outer" "$regression"
run_validation historical_installer_immutable hash_exact \
    f8a138085e74e264f2b450e9d90ec6cf0fce25f2cbf6d878097cf00caa1cc8ab \
    "$historical_installer"
run_validation historical_runner_immutable hash_exact \
    6af6df0054d312e6f34843be5e5f3ab5edc6a11d58e647eed40111d1133f54b7 \
    "$historical_runner"
run_validation historical_outer_immutable hash_exact \
    466cf7b94eb930bb87e6ad14c35a3654cef9f1302a343cb83cebf758212b0b7f \
    "$historical_outer"
run_validation historical_regression_immutable hash_exact \
    9b061f77249fc7ebc34dcb5b8631b5e6fcba32708a44a48c310e2ae9fcb84ff1 \
    "$historical_regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation acceptance_outer_self_test /bin/bash "$acceptance_outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
run_validation acceptance_outer_label_policy /bin/bash "$outer_policy" \
    --runner "$acceptance_outer"
run_validation production_path_regression /bin/bash "$regression"
printf 'action_20e_retry_focused_validation_complete=true\n'
