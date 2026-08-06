#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly diagnostic=$caddy_root/scripts/diagnose-node-a-caddy-managed-context-action20d-retry8-a.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-managed-context-action20d-retry8-a.sh

require_regression() {
    local regression_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry8_a_regression_%s=true\n' "$regression_label"
        return 0
    fi
    printf 'action_20d_retry8_a_regression_%s=false\n' "$regression_label" >&2
    return 1
}
expected_labels_unique() {
    local regression_root

    regression_root=$(mktemp -d /tmp/caddy-action20d-retry8-a-labels.XXXXXX) || return 1
    /bin/bash "$diagnostic" --expected-assertions >"$regression_root/labels" || {
        rm -rf -- "$regression_root"
        return 1
    }
    [[ "$(wc -l <"$regression_root/labels")" -gt 50 ]] || {
        rm -rf -- "$regression_root"
        return 1
    }
    [[ "$(wc -l <"$regression_root/labels")" -eq "$(LC_ALL=C sort -u "$regression_root/labels" | wc -l)" ]] || {
        rm -rf -- "$regression_root"
        return 1
    }
    if grep -Ev '^[a-z0-9_]+$' "$regression_root/labels" | grep -q .; then
        rm -rf -- "$regression_root"
        return 1
    fi
    rm -rf -- "$regression_root"
}
stage_order_exact() {
    local regression_bare_line
    local regression_sourced_line
    local regression_full_line
    local regression_primary_line

    regression_bare_line=$(grep -n '^run_probe bare_root_caddy ' "$diagnostic" | cut -d: -f1)
    regression_sourced_line=$(grep -n '^run_probe sourced_root_caddy ' "$diagnostic" | cut -d: -f1)
    regression_full_line=$(grep -n '^run_probe full_group_helper ' "$diagnostic" | cut -d: -f1)
    regression_primary_line=$(grep -n '^run_probe primary_group_helper ' "$diagnostic" | cut -d: -f1)
    [[ "$regression_bare_line" -lt "$regression_sourced_line" ]] || return 1
    [[ "$regression_sourced_line" -lt "$regression_full_line" ]] || return 1
    [[ "$regression_full_line" -lt "$regression_primary_line" ]] || return 1
}
read_only_scope_exact() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable|mask|unmask)' \
        "$diagnostic" "$runner" || return 1
    ! grep -Eq 'ip[[:space:]].*address[[:space:]]+(add|delete|del|replace)' \
        "$diagnostic" "$runner" || return 1
    ! grep -Eq '(install|cp|mv)[[:space:]].*(/etc/keepalived|/usr/local/libexec|/var/backups)' \
        "$diagnostic" "$runner" || return 1
    [[ "$(grep -Fc 'pi@10.1.0.53' "$runner")" -eq 1 ]] || return 1
    [[ "$(grep -Fc 'HostKeyAlias=pihole0.local.theama.co' "$runner")" -eq 1 ]] || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$diagnostic" "$runner" || return 1
}
environment_scope_explicit() {
    grep -Fq 'value_environment_scope=vrrp_parent_inherited_environment' "$diagnostic" || return 1
    grep -Fq 'value_historical_check_child_environment_recoverable=false' "$diagnostic" || return 1
    # This is an intentional literal source assertion.
    # shellcheck disable=SC2016
    grep -Fq '/proc/$vrrp_pid/environ' "$diagnostic" || return 1
    grep -Fq -- '--clear-groups' "$diagnostic" || return 1
    grep -Fq 'value_bare_root_environment_dependency=' "$diagnostic" || return 1
}
stage_labels_independent() {
    local regression_stage

    for regression_stage in bare_root_caddy sourced_root_caddy full_group_helper \
        primary_group_interpreter primary_group_environment primary_group_service \
        primary_group_caddy primary_group_curl primary_group_helper; do
        [[ "$(grep -Ec "^run_probe ${regression_stage}([[:space:]]|$)" "$diagnostic")" -eq 1 ]] || return 1
        [[ "$(grep -Ec "^run_assertion ${regression_stage}_captured([[:space:]]|$)" "$diagnostic")" -eq 1 ]] || return 1
    done
}

require_regression diagnostic_self_test /bin/bash "$diagnostic" --self-test
require_regression classification_contract /bin/bash "$diagnostic" --classification-test
require_regression runner_self_test /bin/bash "$runner" --self-test
require_regression runner_classification_contract /bin/bash "$runner" --classification-test
require_regression assertion_labels_unique expected_labels_unique
require_regression stage_order stage_order_exact
require_regression read_only_scope read_only_scope_exact
require_regression environment_scope environment_scope_explicit
require_regression independently_labeled_stages stage_labels_independent
printf 'action_20d_retry8_a_regression_node_contact=false\n'
printf 'action_20d_retry8_a_regression_complete=true\n'
