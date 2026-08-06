#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly candidate=$caddy_root/scripts/check-caddy-vrrp-action20h.sh
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-helper-action20h.sh
readonly stager=$caddy_root/scripts/stage-node-a-caddy-health-helper-action20h.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h-outer.sh
readonly regression=$test_directory/action20h-health-helper-regression.sh
readonly candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly installer_sha256=dd8b6c8fbbbc3360ce9aef2c460297d56e1753f62e2ec54a7544016c67c7b692
readonly stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly runner_sha256=82a99e77530f1e53c923dde17e7ce26f646e80fa51e5af357d2068da5c291194
readonly outer_sha256=f69afd17aa7cbaac0144fb9fdaaef82241b42ae6a926fd35052186554f617a1b
readonly regression_sha256=172f4b90cc5c97cd928226e840d2cb1a1b6152aa72af03af5208b6ed8903c159

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20h_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$candidate")" = "$candidate_sha256" ]] || return 1
    [[ "$(file_hash "$installer")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$stager")" = "$stager_sha256" ]] || return 1
    [[ "$(file_hash "$runner")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$candidate" "$installer" "$stager" "$runner" "$outer" "$regression" || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$candidate" "$installer" "$stager" "$runner" "$outer" "$regression" || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' \
        "$candidate" "$installer" "$stager" "$runner" "$outer" || return 1
}
health_architecture_exact() {
    grep -Fq 'health_run_stage service systemctl is-active --quiet caddy' "$candidate" || return 1
    grep -Fq 'health_run_stage endpoint curl' "$candidate" || return 1
    [[ "$(grep -Fc 'caddy validate' "$candidate" || true)" -eq 0 ]] || return 1
    grep -Fq 'caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' \
        "$installer" || return 1
    grep -Fq 'full_caddy_validation_exact_context' "$installer" || return 1
}

gate source_hashes source_hashes_exact
gate syntax /bin/bash -n "$candidate" "$installer" "$stager" "$runner" "$outer" \
    "$regression" "$0"
gate shellcheck shellcheck "$candidate" "$installer" "$stager" "$runner" "$outer" \
    "$regression" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$candidate" "$installer" "$stager" "$runner" "$outer" "$regression" "$0"
gate executable_policy /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
gate collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$candidate" "$installer" "$stager" "$runner" "$outer" "$regression" "$0"
gate conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
gate multi_file_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" \
    --check "$candidate" "$installer" "$stager" "$runner" "$outer" \
    "$regression" "$0"
gate portable_awk_policy /bin/bash "$test_directory/portable-awk-policy-regression.sh"
gate stale_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy-regression.sh"
gate transcript_policy /bin/bash "$test_directory/transcript-contract-ratchet-policy-regression.sh"
gate output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate health_architecture health_architecture_exact
gate production_regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
