#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry7_a_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly diagnostic="$caddy_root/scripts/diagnose-node-a-caddy-health-action20d-retry7-a-retry.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-health-action20d-retry7-a-retry.sh"

record_gate() {
    local regression_gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$regression_gate_label" >&2
    return 1
}
expected_ancestry_inventory() {
    printf '%s\n' \
        ancestry_root_searchable ancestry_tmp_searchable \
        ancestry_work_searchable ancestry_runtime_searchable \
        ancestry_home_searchable ancestry_config_searchable \
        ancestry_data_searchable ancestry_work_metadata_exact \
        ancestry_runtime_metadata_exact ancestry_home_metadata_exact \
        ancestry_config_metadata_exact ancestry_data_metadata_exact \
        ancestry_gate_complete
}
ancestry_inventory_exact() (
    local regression_inventory_root

    regression_inventory_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-inventory.XXXXXX)
    trap 'rm -rf -- "$regression_inventory_root"' EXIT
    expected_ancestry_inventory | LC_ALL=C sort >"$regression_inventory_root/expected"
    /bin/bash "$diagnostic" --expected-assertions |
        grep -E '^ancestry_' | LC_ALL=C sort >"$regression_inventory_root/actual"
    cmp -s "$regression_inventory_root/expected" "$regression_inventory_root/actual"
)
production_order_exact() {
    local regression_gate_line
    local regression_probe_line

    # The dollar expression is intentionally matched as literal source.
    # shellcheck disable=SC2016
    regression_gate_line=$(grep -n -m1 '^if \[\[ "$ancestry_failed_count" -eq 0 \]\]; then$' \
        "$diagnostic" | cut -d: -f1)
    regression_probe_line=$(grep -n -m1 '^    runuser -u keepalived_script -- env' \
        "$diagnostic" | cut -d: -f1)
    [[ "$regression_gate_line" =~ ^[0-9]+$ ]] || return 1
    [[ "$regression_probe_line" =~ ^[0-9]+$ ]] || return 1
    [[ "$regression_gate_line" -lt "$regression_probe_line" ]]
}
root0700_boundary_test() (
    local regression_boundary_root

    regression_boundary_root=$(mktemp -d /tmp/caddy-action20d-retry7-a-retry-boundary.XXXXXX)
    trap 'rm -rf -- "$regression_boundary_root"' EXIT
    /bin/bash "$diagnostic" --ancestry-contract-test \
        >"$regression_boundary_root/stdout" 2>"$regression_boundary_root/stderr"
    [[ ! -s "$regression_boundary_root/stderr" ]] || return 1
    if [[ "$(id -u)" -eq 0 ]]; then
        grep -Fxq \
            'action_20d_retry7_a_retry_ancestry_contract_root0700_rejected=true' \
            "$regression_boundary_root/stdout" || return 1
        grep -Fxq \
            'action_20d_retry7_a_retry_ancestry_contract_searchable_parent_accepted=true' \
            "$regression_boundary_root/stdout" || return 1
        ! grep -Fq 'skipped_nonroot' "$regression_boundary_root/stdout" || return 1
    else
        grep -Fxq \
            'action_20d_retry7_a_retry_ancestry_contract_skipped_nonroot=true' \
            "$regression_boundary_root/stdout" || return 1
    fi
)
static_read_only_scope() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable)|keepalived[[:space:]].*--config-test|notify/apprise|10\.1\.0\.54|pi@10\.1\.0\.54' \
        "$diagnostic" "$runner" || return 1
    grep -Fq 'pi@10.1.0.53' "$runner" || return 1
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$runner" || return 1
}
classification_requires_ancestry() {
    grep -Fq 'classification=ancestry_gate_failed' "$diagnostic" || return 1
    grep -Fq 'classification=caddy_validate_passed_after_searchable_ancestry' \
        "$diagnostic" || return 1
    grep -Fq 'classification=caddy_validate_failed_after_searchable_ancestry' \
        "$diagnostic" || return 1
    # The dollar expression is intentionally matched as literal source.
    # shellcheck disable=SC2016
    grep -Fq '[[ "$runner_ancestry_failed" -eq 0 ]] || return 97' "$runner" || return 1
}

record_gate diagnostic_self_test /bin/bash "$diagnostic" --self-test
record_gate runner_self_test /bin/bash "$runner" --self-test
record_gate runner_contract_test /bin/bash "$runner" --contract-test
record_gate ancestry_inventory_exact ancestry_inventory_exact
record_gate ancestry_before_probe production_order_exact
record_gate root0700_parent_rejected root0700_boundary_test
record_gate static_read_only_scope static_read_only_scope
record_gate classification_gated classification_requires_ancestry

printf '%s_false_positive_unsearchable_parent_rejected=true\n' "$prefix"
printf '%s_false_negative_searchable_parent_accepted=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_invoked=false\n' "$prefix"
printf '%s_keepalived_config_test_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_regression_complete=true\n' "$prefix"
