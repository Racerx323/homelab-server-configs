#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-group-action20f.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-group-correction-action20f.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-group-correction-action20f-outer.sh
readonly regression=$script_directory/action20f-node-a-health-group-correction-regression.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$script_directory/conditional-validator-errexit-policy-regression.sh
readonly transcript=$script_directory/transcript-contract-ratchet-policy-regression.sh
readonly output_evidence=$script_directory/transaction-output-evidence-policy-regression.sh
readonly outer_policy=$script_directory/outer-local-gate-label-policy-regression.sh
readonly executable_policy=$script_directory/executable-wrapper-policy-regression.sh

run_validation() {
    local action20f_focused_label=$1

    shift
    if "$@"; then
        printf 'action_20f_focused_%s=true\n' "$action20f_focused_label"
        return 0
    fi
    printf 'action_20f_focused_%s=false\n' "$action20f_focused_label" >&2
    return 1
}
hash_exact() {
    local action20f_focused_expected_hash=$1
    local action20f_focused_file=$2

    [[ "$(sha256sum "$action20f_focused_file" | awk '{ print $1 }')" = "$action20f_focused_expected_hash" ]] || return 1
}
complete_suite_dependency_absent() {
    ! grep -Eq 'complete_suite|tests/run\.sh|tests/integration\.sh' \
        "$outer" "$regression" || return 1
}
no_live_path_in_definition() {
    # This is an intentional literal source assertion.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0" || return 1
    ! grep -Eq '^[[:space:]]*(ssh|scp|rsync)[[:space:]]' "$regression" "$0" || return 1
}
no_activation_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)|keepalived[[:space:]]+--|ip[[:space:]].*address[[:space:]]+(add|delete|del|replace)' \
        "$installer" "$runner" || return 1
}

run_validation template_exact hash_exact \
    af384fc989eaf6581579ace9f09477d23c6612618fb8eca194c37db890992779 "$template"
run_validation installer_exact hash_exact \
    186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0 "$installer"
run_validation runner_exact hash_exact \
    f5aca1865ce91f6c80c46f807aa3517e3f37b92715f9b41ff48ec49bc491779b "$runner"
run_validation regression_exact hash_exact \
    fdfa52ccaae8848e05146aff069401237d257680db0c4326994c694222107a64 "$regression"
run_validation outer_exact hash_exact \
    0baca52ef0891f7e511f4f92b486d449c703863805499fbe67123d69d4afbe23 "$outer"
run_validation syntax /bin/bash -n "$installer" "$runner" "$outer" "$regression" "$0"
run_validation shellcheck shellcheck "$installer" "$runner" "$outer" "$regression" "$0"
run_validation canonical_format /bin/bash "$script_directory/shfmt-canonical.sh" --check \
    "$installer" "$runner" "$outer" "$regression" "$0"
run_validation collision_policy /bin/bash "$collision" "$installer" "$runner" \
    "$outer" "$regression" "$0"
run_validation conditional_policy /bin/bash "$conditional"
run_validation transcript_policy /bin/bash "$transcript"
run_validation output_evidence_policy /bin/bash "$output_evidence"
run_validation executable_policy /bin/bash "$executable_policy"
run_validation regression_self_test /bin/bash "$regression" --self-test
run_validation regression_production_path /bin/bash "$regression"
run_validation outer_self_test /bin/bash "$outer" --self-test
run_validation outer_label_policy /bin/bash "$outer_policy" --runner "$outer"
run_validation activation_absent no_activation_contract
run_validation complete_suite_bypassed complete_suite_dependency_absent
run_validation no_live_execution_path no_live_path_in_definition

printf 'action_20f_focused_complete_suite_invoked=false\n'
printf 'action_20f_focused_podman_invoked=false\n'
printf 'action_20f_focused_node_contact=false\n'
printf 'action_20f_focused_keepalived_reload=false\n'
printf 'action_20f_focused_vrrp_transition=false\n'
printf 'action_20f_focused_vip_mutation=false\n'
printf 'action_20f_focused_validation_complete=true\n'
