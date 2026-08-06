#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry-outer.sh
readonly regression=$test_directory/action20d-retry10-d-retry-candidate-stage-regression.sh
readonly builder_sha256=515fbbe96293ce9bc0ba838c2710af4bbba0b04c0f604de87f80d8ab88f0302c
readonly outer_sha256=0db0eeeb2605f76961a081c7b1e124e87e583dfd54921a220edb1191e499a4c1
readonly regression_sha256=190d22ca2be002488fbeffe4ca80dc10d0a5f3456f1dd8d8bffb8f457fe7872c
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly installer_sha256=aa9a7e2a5c5506f6371553605c2f7ceb05d751c3cfd6a711844002ffb91b6f6f
readonly runner_sha256=22812cd547308eef303eb65326caef9e5afeb50c96d603423b8f652365251ab6
readonly stager_sha256=679448f7f3c58afe2d444503c4cf2ac44d6c6fa91d6880fdceed561799171cd9

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20d_d_retry_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$builder")" = "$builder_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
}
generated_hashes_exact() {
    [[ "$(file_hash "$generated_root/check-caddy-instrumented-action20d-retry10-d.sh")" = "$candidate_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = "$installer_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$generated_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh")" = "$stager_sha256" ]] || return 1
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$builder" "$outer" "$generated_root"/* || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$builder" "$outer" "$generated_root"/* || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$builder" "$outer" "$generated_root"/* || return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry-focused.XXXXXX)
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
gate builder_output /bin/bash "$builder" --output "$generated_root"
gate generated_hashes generated_hashes_exact
gate regression /bin/bash "$regression"
gate outer_self_test /bin/bash "$outer" --self-test
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
