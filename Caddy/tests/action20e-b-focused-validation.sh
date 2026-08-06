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
readonly inspector=$caddy_root/scripts/inspect-node-b-runtime-shadow-metadata-action20e-b.sh
readonly runner=$caddy_root/scripts/run-node-b-runtime-shadow-metadata-diagnostic-action20e-b.sh
readonly outer=$caddy_root/scripts/run-node-b-runtime-shadow-metadata-diagnostic-action20e-b-outer.sh
readonly regression=$test_directory/action20e-b-node-b-shadow-metadata-diagnostic-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh
readonly historical_installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry.sh
readonly historical_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry-outer.sh
readonly historical_regression=$test_directory/action20e-retry-runtime-directories-regression.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20e_b_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20e_b_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20e_b_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_path=$2

    [[ "$(sha256sum "$inspected_path" | awk '{ print $1 }')" = "$expected_hash" ]]
}

run_validation sources_syntax /bin/bash -n "$inspector" "$runner" "$outer" "$regression"
run_validation sources_shellcheck shellcheck "$inspector" "$runner" "$outer" "$regression"
run_validation readonly_local_collision_policy /bin/bash "$collision" \
    "$inspector" "$runner" "$outer" "$regression"
run_validation historical_installer_immutable hash_exact \
    36643fcff4505c346d39f8f64a0d90837810a3f7671f79bf5c4e65e80f5f178f \
    "$historical_installer"
run_validation historical_runner_immutable hash_exact \
    cf4fde0ab4bc18c77fb14a4b0b44ca9e6619c5e44282f69521ad842c06ad5668 \
    "$historical_runner"
run_validation historical_outer_immutable hash_exact \
    4b0f4650c8d28d2c6ed6967663a387b2c5681d54fd45e97a7c32818302d66182 \
    "$historical_outer"
run_validation historical_regression_immutable hash_exact \
    0c1e609c9514a36e3e7c5004a15b3df0baa78e9a984c21a3ebe544d7fc681272 \
    "$historical_regression"
run_validation inspector_self_test /bin/bash "$inspector" --self-test
run_validation runner_contract_test /bin/bash "$runner" --contract-test
run_validation regression_production_path /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
printf 'action_20e_b_focused_validation_complete=true\n'
