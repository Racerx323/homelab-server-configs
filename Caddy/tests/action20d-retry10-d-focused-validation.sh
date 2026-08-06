#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly candidate=$caddy_root/scripts/check-caddy-instrumented-action20d-retry10-d.sh
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-action20d-retry10-d-outer.sh
readonly regression=$test_directory/action20d-retry10-d-health-instrumentation-regression.sh
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly installer_sha256=ade3794ce506be9df2b6117715e33395b98bcd61bfb4dbfd7ed34570e00ee468
readonly runner_sha256=48b3790c24c9dc35be79abf519110cea0145ee5787ed017ca6493314a61f9c25
readonly outer_sha256=ed4e2c6978af1d0a52e251812c515f198342d178e9cbb16dedf42ca84abd91d4
readonly regression_sha256=1b38908b57f66042edfff9d5f1743d440de715b7c1e350f8f0c7b91b9da1b5ff

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20d_d_focused_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20d_d_focused_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20d_d_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$candidate")" = "$candidate_sha256" ]] || return 1
    [[ "$(file_hash "$installer")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$runner")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$candidate" "$installer" "$runner" "$outer" "$regression" || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$candidate" "$installer" "$runner" "$outer" "$regression" || return 1
    [[ "$(grep -Fc 'pi@10.1.0.53' "$runner")" -eq 1 ]] || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' \
        "$candidate" "$installer" "$runner" "$outer" "$regression" || return 1
}

gate source_hashes source_hashes_exact
gate syntax /bin/bash -n "$candidate" "$installer" "$runner" "$outer" "$regression" "$0"
gate shellcheck shellcheck "$candidate" "$installer" "$runner" "$outer" "$regression" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$candidate" "$installer" "$runner" "$outer" "$regression" "$0"
gate executable_policy /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
gate collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$candidate" "$installer" "$runner" "$outer" "$regression" "$0"
gate conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
gate transcript_policy /bin/bash "$test_directory/transcript-contract-ratchet-policy-regression.sh"
gate output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
