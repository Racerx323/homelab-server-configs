#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_a_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly state_inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28j.sh
readonly route_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-a-route.sh
readonly residue_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-a-residue.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-post-action28j-a-outer.sh
readonly regression=$test_directory/action28j-a-dual-node-failover-post-regression.sh
readonly focused=$test_directory/action28j-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-failover-post-action28j-a.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md
readonly state_inspector_sha256=3f4e4ca1c55677f22e997d7cda3a105f2bbc662870885f3df1e343b5049de735
readonly route_inspector_sha256=33c1ba24aedc557d7c6e09bf9ecac2221b77b569759ebc60247ee7084f414068
readonly residue_inspector_sha256=c7ea3f9bc127dc8636bd860aadcf80c15961e84d08910f874615073427a90c5b
readonly outer_sha256=ec6dc3f86b3dd41f085e59c4df3fa2e3fc6afcbdf98cae19e69d021989fc37e2
readonly regression_sha256=dddc97375ae42544fd5ffac375bd11f3f611a3ba2635ea21191c055b5e281737
readonly manifest_sha256=11b9437909b8cbfb10551224d49a3c949b16069b732dd6666db209755633c1a3

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28j_a_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_a_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28j-a' "$manifest" || return 1
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
record_check syntax /bin/bash -n "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check route_inspector_self_test /bin/bash "$route_inspector" --self-test
record_check residue_inspector_self_test /bin/bash "$residue_inspector" --self-test
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check plan_gate grep -Fq 'Action 28j-a' "$plan"

for action28j_a_focused_entrypoint in "$route_inspector" "$residue_inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_$(basename "$action28j_a_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28j_a_focused_entrypoint"
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_http_probe=false\n' "$prefix"
printf '%s_live_dns_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
