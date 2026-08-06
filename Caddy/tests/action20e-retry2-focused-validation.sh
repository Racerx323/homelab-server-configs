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
readonly installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry2.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry2.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry2-outer.sh
readonly regression=$test_directory/action20e-retry2-runtime-directories-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh
readonly source_context=$test_directory/run-source-test-in-context.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20e_retry2_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20e_retry2_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20e_retry2_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_path=$2

    [[ "$(sha256sum "$inspected_path" | awk '{ print $1 }')" = "$expected_hash" ]]
}
check_count_exact() {
    [[ "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq 101 ]]
}
live_parent_contract_exact() {
    grep -Fq 'run_check tmpfiles_parent_regular test -d /etc/tmpfiles.d' "$installer" || return 1
    grep -Fq 'run_check tmpfiles_parent_not_symlink test ! -L /etc/tmpfiles.d' "$installer" || return 1
    grep -Fq 'run_check tmpfiles_parent_owner_exact' "$installer" || return 1
    grep -Fq "live_tmpfiles_parent_metadata" "$installer" || return 1
}

run_validation sources_syntax /bin/bash -n "$installer" "$runner" "$outer" "$regression"
run_validation sources_shellcheck shellcheck "$installer" "$runner" "$outer" "$regression"
run_validation readonly_local_collision_policy /bin/bash "$collision" \
    "$installer" "$runner" "$outer" "$regression"
run_validation historical_installer_immutable hash_exact \
    36643fcff4505c346d39f8f64a0d90837810a3f7671f79bf5c4e65e80f5f178f \
    "$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry.sh"
run_validation historical_runner_immutable hash_exact \
    cf4fde0ab4bc18c77fb14a4b0b44ca9e6619c5e44282f69521ad842c06ad5668 \
    "$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry.sh"
run_validation historical_outer_immutable hash_exact \
    4b0f4650c8d28d2c6ed6967663a387b2c5681d54fd45e97a7c32818302d66182 \
    "$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry-outer.sh"
run_validation accepted_diagnostic_outer_immutable hash_exact \
    7efc185c6a2043fbdb09d60c6b0f0b8bb6c0ce0182b21e98b65b3f68fe382e83 \
    "$caddy_root/scripts/run-node-b-runtime-shadow-metadata-diagnostic-action20e-b-outer.sh"
run_validation expected_check_count check_count_exact
run_validation live_parent_contract live_parent_contract_exact
run_validation installer_self_test /bin/bash "$installer" --self-test
run_validation runner_source_test /bin/bash "$source_context" --runner "$runner"
run_validation regression_production_path /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
printf 'action_20e_retry2_focused_validation_complete=true\n'
