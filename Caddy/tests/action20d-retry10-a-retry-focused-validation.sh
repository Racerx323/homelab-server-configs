#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh
readonly regression=$test_directory/action20d-retry10-a-retry-postactivation-regression.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a-retry-outer.sh
readonly historical_probe=$caddy_root/scripts/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly accepted_provenance_outer=$caddy_root/scripts/run-node-b-caddy-environment-provenance-action20d-retry10-b-outer.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh

run_validation() {
    local focused_validation_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_a_retry_focused_%s=true\n' "$focused_validation_label"
        return 0
    fi
    printf 'action_20d_retry10_a_retry_focused_%s=false\n' \
        "$focused_validation_label" >&2
    return 1
}
hash_exact() {
    local focused_expected_hash=$1
    local focused_inspected_file=$2

    [[ "$(sha256sum "$focused_inspected_file" | awk '{ print $1 }')" = "$focused_expected_hash" ]]
}
local_file_modes_exact() {
    local focused_mode_path

    for focused_mode_path in "$builder" "$regression" "$outer" "$0"; do
        [[ "$(stat -c '%a' "$focused_mode_path")" = 755 ]] || return 1
    done
}
complete_suite_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh' \
        "$builder" "$regression" "$outer"
}
live_execution_absent() {
    ! grep -Eq '/bin/bash[[:space:]]+"?[$]?(outer|corrected_runner)"?[[:space:]]*$' "$0"
}
static_live_mutation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del|replace)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$builder" "$regression" "$outer"
}
node_b_activation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|replace)' \
        "$builder" "$regression" "$outer"
}

run_validation syntax /bin/bash -n "$builder" "$regression" "$outer" "$0"
run_validation shellcheck shellcheck "$builder" "$regression" "$outer" "$0"
run_validation canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$builder" "$regression" "$outer" "$0"
run_validation executable_modes local_file_modes_exact
run_validation collision_policy /bin/bash "$collision" \
    "$builder" "$regression" "$outer" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation static_live_mutation_absent static_live_mutation_absent
run_validation node_b_activation_absent node_b_activation_absent
run_validation historical_probe_immutable hash_exact \
    564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84 \
    "$historical_probe"
run_validation historical_runner_immutable hash_exact \
    f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978 \
    "$historical_runner"
run_validation accepted_provenance_outer_immutable hash_exact \
    1d65abce9e15efaa2052b954dcf1a9029c1d75deb687f2cd33d51d22b675e0fa \
    "$accepted_provenance_outer"
run_validation builder_exact hash_exact \
    b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3 \
    "$builder"
run_validation regression_exact hash_exact \
    fb2a038d52e3889018c8887d584a6c77ce3444ec2dbefec974c0186f7d79da1a \
    "$regression"
run_validation outer_exact hash_exact \
    56471ced5c32b305f9b678cdeb8ed09fbce1a5afe5cd6ef7c6628b63c2ec4b15 \
    "$outer"
run_validation builder_self_test /bin/bash "$builder" --self-test
run_validation builder_contract_test /bin/bash "$builder" --contract-test
run_validation production_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test

printf 'action_20d_retry10_a_retry_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry10_a_retry_focused_podman_invoked=false\n'
printf 'action_20d_retry10_a_retry_focused_node_contact=false\n'
printf 'action_20d_retry10_a_retry_focused_health_helper_live_invoked=false\n'
printf 'action_20d_retry10_a_retry_focused_notification_invoked=false\n'
printf 'action_20d_retry10_a_retry_focused_service_mutations=false\n'
printf 'action_20d_retry10_a_retry_focused_vrrp_mutations=false\n'
printf 'action_20d_retry10_a_retry_focused_vip_mutations=false\n'
printf 'action_20d_retry10_a_retry_focused_persistent_mutations=false\n'
printf 'action_20d_retry10_a_retry_focused_validation_complete=true\n'
