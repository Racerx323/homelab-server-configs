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
readonly builder=$caddy_root/scripts/build-node-a-first-caddy-failover-action28j.sh
readonly inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28j.sh
readonly transaction=$caddy_root/scripts/transact-node-a-caddy-failover-action28j.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-action28j-outer.sh
readonly regression=$test_directory/action28j-node-a-first-caddy-failover-regression.sh
readonly focused=$test_directory/action28j-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-node-a-first-failover-action28j.yaml
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md
readonly accepted_live=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly consumers=$caddy_root/manifests/deployable-live-hash-consumers.tsv
readonly prefix=action_28j_focused

record_check() {
    local action28j_focused_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28j' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
    grep -Fqx '  next_gate: exact_outer_sha256_authorization' "$manifest"
}

record_check syntax /bin/bash -n "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check format /bin/bash "$test_directory/shfmt-canonical.sh" --check "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check builder_self_test /bin/bash "$builder" --self-test
record_check yaml yaml_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check plan_gate grep -Fq 'Action 28j' "$plan"
record_check accepted_live_regular test -f "$accepted_live"
record_check consumer_registry_regular test -f "$consumers"
for action28j_entrypoint in "$builder" "$inspector" "$transaction" "$outer" "$regression" "$focused"; do
    record_check "executable_$(basename "$action28j_entrypoint" | tr '.-' '__')" test -x "$action28j_entrypoint"
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
