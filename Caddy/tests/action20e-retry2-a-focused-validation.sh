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
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry2-a-outer.sh
readonly regression=$test_directory/action20e-retry2-a-postinstall-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh
readonly historical_inspector=$caddy_root/scripts/inspect-caddy-runtime-directories-action20e-retry-a.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry-a.sh
readonly historical_outer=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry-a-outer.sh
readonly accepted_transaction=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry2-outer.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20e_retry2_a_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20e_retry2_a_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20e_retry2_a_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_path=$2

    [[ "$(sha256sum "$inspected_path" | awk '{ print $1 }')" = "$expected_hash" ]]
}

run_validation sources_syntax /bin/bash -n "$outer" "$regression"
run_validation sources_shellcheck shellcheck "$outer" "$regression"
run_validation readonly_local_collision_policy /bin/bash "$collision" "$outer" "$regression"
run_validation historical_inspector_immutable hash_exact \
    6587b6a9b5aad28a9e4f2e4b31773f61017dc449ebfcc05d009991421eb2367d \
    "$historical_inspector"
run_validation historical_runner_immutable hash_exact \
    de66cc0c43524728f2bbdc645cf5439fb87f4edd5c53addbef204c59ddab6871 \
    "$historical_runner"
run_validation historical_outer_immutable hash_exact \
    8a62869fb1bae634a0236cc5770c830aae690cda887e3e8b9f1cd40bf0b00a42 \
    "$historical_outer"
run_validation accepted_transaction_immutable hash_exact \
    54e2182d91690491b39305712ed9277f9be371720db202e6b6ce7d9d49ed15d0 \
    "$accepted_transaction"
run_validation production_label_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
printf 'action_20e_retry2_a_focused_validation_complete=true\n'
