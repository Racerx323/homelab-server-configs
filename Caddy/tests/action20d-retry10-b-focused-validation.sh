#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-node-b-caddy-environment-provenance-action20d-retry10-b.sh
readonly runner=$caddy_root/scripts/run-node-b-caddy-environment-provenance-action20d-retry10-b.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-environment-provenance-action20d-retry10-b-outer.sh
readonly regression=$test_directory/action20d-retry10-b-node-b-environment-provenance-regression.sh
readonly accepted_failed_outer=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a-outer.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh

run_validation() {
    local validation_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_b_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20d_retry10_b_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_file=$2

    [[ "$(sha256sum "$inspected_file" | awk '{ print $1 }')" = "$expected_hash" ]]
}
multi_file_match_count() {
    local count_pattern=$1
    local count_path
    local count_total=0

    shift
    for count_path in "$@"; do
        count_total=$((count_total + $(grep -Ec "$count_pattern" "$count_path" || true)))
    done
    printf '%s\n' "$count_total"
}
complete_suite_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh' \
        "$probe" "$runner" "$outer" "$regression"
}
live_execution_absent() {
    ! grep -Eq '/bin/bash[[:space:]]+"?[$]?(outer|runner)"?[[:space:]]*$' "$0"
}
static_mutation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del|replace)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$probe" "$runner"
}
node_a_contact_absent() {
    [[ "$(multi_file_match_count \
        'pi@10\.1\.0\.53|HostKeyAlias=pihole0\.local\.theama\.co' \
        "$probe" "$runner" "$outer")" -eq 0 ]]
}
environment_value_output_absent() {
    [[ "$(grep -Ec 'cat[[:space:]]+["]?[$]environment_file["]?|printf.*[$]environment_line([[:space:]]|$)' \
        "$probe" || true)" -eq 0 ]]
}
local_file_modes_exact() {
    local inspected_path

    for inspected_path in "$probe" "$runner" "$outer" "$regression" "$0"; do
        [[ "$(stat -c '%a' "$inspected_path")" = 755 ]] || return 1
    done
}

run_validation syntax /bin/bash -n "$probe" "$runner" "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$probe" "$runner" "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$probe" "$runner" "$outer" "$regression" "$0"
run_validation executable_modes local_file_modes_exact
run_validation collision_policy /bin/bash "$collision" \
    "$probe" "$runner" "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation static_mutation_absent static_mutation_absent
run_validation node_a_contact_absent node_a_contact_absent
run_validation environment_value_output_absent environment_value_output_absent
run_validation accepted_failed_outer_immutable hash_exact \
    e680404b76803d1c975af60d71f4d18865ab7a04dd6099e550dd1caf142dc44c \
    "$accepted_failed_outer"
run_validation probe_exact hash_exact \
    7c9f989f21c09de85810b6e7ffc8b7c77600ec0fffe90ba55ce94a18de7018fe \
    "$probe"
run_validation runner_exact hash_exact \
    6cf8bdd0cfed2699fa3ccd7d9ca00d2673e3ce8b7636f9826b9a7701d4c9d85e \
    "$runner"
run_validation regression_exact hash_exact \
    14bfc20595d4528c652db3597352e6e8359a827521324e180ce335cb0a616fb1 \
    "$regression"
run_validation outer_exact hash_exact \
    1d65abce9e15efaa2052b954dcf1a9029c1d75deb687f2cd33d51d22b675e0fa \
    "$outer"
run_validation probe_self_test /bin/bash "$probe" --self-test
run_validation runner_self_test /bin/bash "$runner" --self-test
run_validation runner_contract_test /bin/bash "$runner" --contract-test
run_validation production_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test

printf 'action_20d_retry10_b_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry10_b_focused_podman_invoked=false\n'
printf 'action_20d_retry10_b_focused_node_contact=false\n'
printf 'action_20d_retry10_b_focused_health_helper_invoked=false\n'
printf 'action_20d_retry10_b_focused_notification_invoked=false\n'
printf 'action_20d_retry10_b_focused_service_mutations=false\n'
printf 'action_20d_retry10_b_focused_vrrp_mutations=false\n'
printf 'action_20d_retry10_b_focused_vip_mutations=false\n'
printf 'action_20d_retry10_b_focused_persistent_mutations=false\n'
printf 'action_20d_retry10_b_focused_validation_complete=true\n'
