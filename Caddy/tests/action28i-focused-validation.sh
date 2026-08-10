#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28i.sh
readonly transaction=$caddy_root/scripts/transact-node-a-caddy-failover-action28i.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-action28i-outer.sh
readonly regression=$test_directory/action28i-node-a-first-caddy-failover-regression.sh
readonly focused=$test_directory/action28i-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-node-a-first-failover-action28i.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md
readonly accepted_live=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly consumers=$caddy_root/manifests/deployable-live-hash-consumers.tsv
readonly prefix=action_28i_focused

record_check() {
    local action28i_focused_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28i_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28i_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28i' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
    grep -Fqx '  next_gate: exact_outer_sha256_authorization' "$manifest"
}

record_check syntax /bin/bash -n "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check format /bin/bash "$test_directory/shfmt-canonical.sh" --check "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check regression /bin/bash "$regression"
record_check yaml yaml_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check output_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check plan_gate grep -Fq 'Action 28i' "$plan"
record_check accepted_live_regular test -f "$accepted_live"
record_check consumer_registry_regular test -f "$consumers"
for action28i_entrypoint in "$inspector" "$transaction" "$outer" "$regression" "$focused"; do
    record_check "executable_$(basename "$action28i_entrypoint" | tr '.-' '__')" test -x "$action28i_entrypoint"
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
