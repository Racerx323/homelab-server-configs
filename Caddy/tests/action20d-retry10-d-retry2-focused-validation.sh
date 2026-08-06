#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2-outer.sh
readonly regression=$test_directory/action20d-retry10-d-retry2-complete-path-regression.sh
readonly builder_sha256=f4eec61014fe68ee0367a24e982b688b60025c8e07e6add655c82aff1bceb346
readonly outer_sha256=502c8c6c9afe5b23533d7888f11fc6eb2b5cea2b7763fb204446b7e545e597c3
readonly regression_sha256=4fba7ad2744639a321dab5e35cc93abcf5480dbb6a86344bdbb9fca844fa8b83
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly installer_sha256=9845137186eeb3bc6e16e83972bf8aec70f2ff82b0ee5f49110df48784ddc830
readonly runner_sha256=459e1b85037d82184e7daf586776bbee03d27df5ce8f40a6ca463f66c9edd409
readonly stager_sha256=2b8affebe56181007250c2a3cf859c25f18e7942bd62062ce353213488eca058

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20d_d_retry2_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry2_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry2_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$builder")" = "$builder_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
}
generated_hashes_exact() {
    [[ "$(file_hash "$generated_root/check-caddy-instrumented-action20d-retry10-d.sh")" = "$candidate_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh")" = "$stager_sha256" ]] || return 1
}
durable_staging_rule_exact() {
    grep -Fq 'Any staged artifact consumed by an unprivileged identity must be placed in a' \
        "$repository_root/AGENTS.md" || return 1
    grep -Fq 'never nest the unprivileged consumer' "$repository_root/AGENTS.md" || return 1
    grep -Fq 'exact runtime UID,' "$repository_root/AGENTS.md" || return 1
    grep -Fq 'Static immediate-directory metadata is never sufficient.' \
        "$repository_root/AGENTS.md" || return 1
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$builder" "$outer" "$generated_root"/* || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$builder" "$outer" "$generated_root"/* || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$builder" "$outer" "$generated_root"/* || return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-focused.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
readonly generated_root=$fixture_root/generated

gate source_hashes source_hashes_exact
gate syntax /bin/bash -n "$builder" "$outer" "$regression" "$0"
gate shellcheck shellcheck "$builder" "$outer" "$regression" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$outer" "$regression" "$0"
gate executable_policy /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
gate collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$outer" "$regression" "$0"
gate conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
gate transcript_policy /bin/bash "$test_directory/transcript-contract-ratchet-policy-regression.sh"
gate output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate durable_staging_rule durable_staging_rule_exact
gate builder_output /bin/bash "$builder" --output "$generated_root"
gate generated_hashes generated_hashes_exact
gate regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
