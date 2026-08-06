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
readonly outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-retry-outer.sh
readonly regression=$test_directory/action20d-c-retry-notifier-context-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh
readonly historical_probe=$caddy_root/scripts/inspect-caddy-notifier-context-action20d-c.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh
readonly historical_outer=$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-outer.sh
readonly accepted_runtime_acceptance=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry2-a-outer.sh

run_validation() {
    local validation_label=$1

    shift
    printf 'action_20d_c_retry_focused_%s_begin\n' "$validation_label"
    if "$@"; then
        printf 'action_20d_c_retry_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20d_c_retry_focused_%s=false\n' "$validation_label" >&2
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
run_validation historical_probe_immutable hash_exact \
    defff2a76889c084b9903c2012b3fe16fdb8dd581882e4acb7dd62d6f625524d \
    "$historical_probe"
run_validation historical_runner_immutable hash_exact \
    a492843c8439339a95cc996c437a2dfc7ce7710057940cf82b7dcde25ffad77c \
    "$historical_runner"
run_validation historical_outer_immutable hash_exact \
    db6d6296a4fedc987a2ab2b7a02a01cf11e484c4308262e20ff32617689d7595 \
    "$historical_outer"
run_validation accepted_runtime_acceptance_immutable hash_exact \
    b0f478e67477195c9b5127c1f465ae0bfc588c582853cf693ca0352fef33b21d \
    "$accepted_runtime_acceptance"
run_validation production_label_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
printf 'action_20d_c_retry_focused_validation_complete=true\n'
