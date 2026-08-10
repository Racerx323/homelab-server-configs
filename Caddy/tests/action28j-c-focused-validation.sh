#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_c_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly state_inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28j.sh
readonly route_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-c-route.sh
readonly residue_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-a-residue.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-post-action28j-c-outer.sh
readonly regression=$test_directory/action28j-c-resolve-durable-evidence-regression.sh
readonly focused=$test_directory/action28j-c-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-failover-post-action28j-c.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md
readonly state_inspector_sha256=3f4e4ca1c55677f22e997d7cda3a105f2bbc662870885f3df1e343b5049de735
readonly route_inspector_sha256=df1f606c2ab3f92d62daf92cce7dc9575f813ce2ed5216d709435fef69a55075
readonly residue_inspector_sha256=c7ea3f9bc127dc8636bd860aadcf80c15961e84d08910f874615073427a90c5b
readonly outer_sha256=42ff79c0cd335968ffcfcfe2e8a8af8f915aff8fb687beffb5ea8a09ae53f562
readonly regression_sha256=75f512fa4d3eb430388d29103826642befae40df3410047c5fe1de608096da1b
readonly manifest_sha256=641d7ad6154898949b7ad92a90aeef0d22baf46d0b8c2d330a492a35dfd42117

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28j_c_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_c_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_c_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28j-c' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
    grep -Fqx "  outer_sha256: $outer_sha256" "$manifest"
}

record_check state_inspector_hash test "$(file_hash "$state_inspector")" = "$state_inspector_sha256"
record_check route_inspector_hash test "$(file_hash "$route_inspector")" = "$route_inspector_sha256"
record_check residue_inspector_hash test "$(file_hash "$residue_inspector")" = "$residue_inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$route_inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$route_inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$route_inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$route_inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$route_inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$route_inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" \
    --check "$outer"
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check route_inspector_self_test /bin/bash "$route_inspector" --self-test
record_check outer_self_test /bin/bash "$outer" --self-test
record_check resolve_and_durable_evidence_regression /bin/bash "$regression"
record_check plan_gate grep -Fq 'Action 28j-c' "$plan"

for action28j_c_focused_entrypoint in "$route_inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_$(basename "$action28j_c_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28j_c_focused_entrypoint"
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_http_probe=false\n' "$prefix"
printf '%s_live_dns_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
