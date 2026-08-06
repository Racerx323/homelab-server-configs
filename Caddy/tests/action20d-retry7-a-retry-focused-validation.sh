#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry7_a_retry_focused
readonly diagnostic_sha256=1a5a08ad5220eb9e9ffa6e336664bd167c63f6ca4d3b463a744028401be88645
readonly runner_sha256=7c5e96411999f48b8404ad48ff8a5422b15c4ffe4f11138f914916aa3a6db7a6
readonly outer_sha256=30830a62bbb03e048b9edd79eb20a5d3b3229c1284b9776aa8966cbc8f82913a
readonly regression_sha256=3bce38ccda42a06832d1d3e735bb46096405d1e85d10acb214e7375bfb0e486b
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly diagnostic="$caddy_root/scripts/diagnose-node-a-caddy-health-action20d-retry7-a-retry.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-health-action20d-retry7-a-retry.sh"
readonly outer="$caddy_root/scripts/run-node-a-caddy-health-action20d-retry7-a-retry-outer.sh"
readonly regression="$test_directory/action20d-retry7-a-retry-ancestry-regression.sh"
readonly collision="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly outer_policy="$test_directory/outer-local-gate-label-policy-regression.sh"

record_gate() {
    local focused_gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$focused_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$focused_gate_label" >&2
    return 1
}
hash_exact() {
    local focused_expected_hash=$1
    local focused_source_path=$2

    [[ "$(sha256sum "$focused_source_path" | awk '{ print $1 }')" = "$focused_expected_hash" ]]
}
complete_suite_absent() {
    ! grep -Eq 'tests/run\.sh|tests/integration\.sh|complete_suite' \
        "$diagnostic" "$runner" "$outer" "$regression" || return 1
}
entrypoints_executable() {
    local focused_source_path

    for focused_source_path in "$diagnostic" "$runner" "$outer" "$regression" "$0"; do
        [[ -x "$focused_source_path" ]] || return 1
    done
}

record_gate diagnostic_hash_exact hash_exact "$diagnostic_sha256" "$diagnostic"
record_gate runner_hash_exact hash_exact "$runner_sha256" "$runner"
record_gate outer_hash_exact hash_exact "$outer_sha256" "$outer"
record_gate regression_hash_exact hash_exact "$regression_sha256" "$regression"
record_gate syntax /bin/bash -n "$diagnostic" "$runner" "$outer" "$regression" "$0"
record_gate shellcheck shellcheck "$diagnostic" "$runner" "$outer" "$regression" "$0"
record_gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$diagnostic" "$runner" "$outer" "$regression" "$0"
record_gate executable_entrypoints entrypoints_executable
record_gate collision_policy /bin/bash "$collision" \
    "$diagnostic" "$runner" "$outer" "$regression" "$0"
record_gate complete_suite_bypassed complete_suite_absent
record_gate diagnostic_self_test /bin/bash "$diagnostic" --self-test
record_gate runner_self_test /bin/bash "$runner" --self-test
record_gate runner_contract_test /bin/bash "$runner" --contract-test
record_gate outer_local_gate_policy /bin/bash "$outer_policy" --runner "$outer"
record_gate ancestry_regression /bin/bash "$regression"

printf '%s_complete_suite_invoked=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_keepalived_config_test_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_validation_complete=true\n' "$prefix"
