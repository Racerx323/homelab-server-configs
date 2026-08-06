#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a-outer.sh
readonly regression=$script_directory/action20d-retry10-a-postactivation-regression.sh
readonly accepted_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry10-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh

run_validation() {
    local validation_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_a_focused_%s=true\n' "$validation_label"
        return 0
    fi
    printf 'action_20d_retry10_a_focused_%s=false\n' "$validation_label" >&2
    return 1
}
hash_exact() {
    local expected_hash=$1
    local inspected_file=$2

    [[ "$(sha256sum "$inspected_file" | awk '{ print $1 }')" = "$expected_hash" ]]
}
complete_suite_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh' \
        "$probe" "$runner" "$outer" "$regression"
}
live_execution_absent() {
    ! grep -Eq '/bin/bash[[:space:]]+"?\$?(outer|runner)"?[[:space:]]*$' "$0"
}

run_validation syntax /bin/bash -n "$probe" "$runner" "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$probe" "$runner" "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" \
    --check "$probe" "$runner" "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$probe" "$runner" "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation complete_suite_bypassed complete_suite_absent
run_validation live_execution_absent live_execution_absent
run_validation accepted_outer_immutable hash_exact \
    0bf76de0c4f170b72338d7f7ec2627b7004361c0a59afeab7f410daa4747114c \
    "$accepted_outer"
run_validation probe_exact hash_exact \
    564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84 \
    "$probe"
run_validation runner_exact hash_exact \
    f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978 \
    "$runner"
run_validation regression_exact hash_exact \
    fb70eac7073fcd21434ee695ce4fa70e8412ea8e893ae9832e8a8f68d085e6b3 \
    "$regression"
run_validation outer_exact hash_exact \
    e680404b76803d1c975af60d71f4d18865ab7a04dd6099e550dd1caf142dc44c \
    "$outer"
run_validation probe_self_test /bin/bash "$probe" --self-test
run_validation runner_self_test /bin/bash "$runner" --self-test
run_validation runner_contract_test /bin/bash "$runner" --contract-test
run_validation production_regression /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test

printf 'action_20d_retry10_a_focused_complete_suite_invoked=false\n'
printf 'action_20d_retry10_a_focused_podman_invoked=false\n'
printf 'action_20d_retry10_a_focused_node_contact=false\n'
printf 'action_20d_retry10_a_focused_health_helper_live_invoked=false\n'
printf 'action_20d_retry10_a_focused_notification_invoked=false\n'
printf 'action_20d_retry10_a_focused_service_mutations=false\n'
printf 'action_20d_retry10_a_focused_vrrp_mutations=false\n'
printf 'action_20d_retry10_a_focused_vip_mutations=false\n'
printf 'action_20d_retry10_a_focused_persistent_mutations=false\n'
printf 'action_20d_retry10_a_focused_validation_complete=true\n'
