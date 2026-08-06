#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_a_focused
readonly inspector_sha256=2904f0e0d6cfbe87d4f041998c7bad294215f93522b37995c93fa57a4b3c18ff
readonly runner_sha256=32ea404878c42b843406dc39054f34186e6b169cd2b2a5e02d0c8ba59f79eebb
readonly regression_sha256=28a154003497ab537dfce9f3ec33bcf6ecbec47c958799656b778ce1680fa272
readonly outer_sha256=66bbba53fba8d7cc91122fbde94f4d6a0d6658436a4196714035c0b6cbb95de5

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly regression=$script_directory/action20d-retry10-d-retry2-a-postinstall-regression.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20d_retry2_a_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_retry2_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20d_retry2_a_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$runner")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]] || return 1
}
entrypoints_executable() {
    local action20d_retry2_a_focused_entrypoint

    for action20d_retry2_a_focused_entrypoint in \
        "$inspector" "$runner" "$regression" "$outer"; do
        [[ "$(stat -c '%a' "$action20d_retry2_a_focused_entrypoint")" = 755 ]] || return 1
    done
}
outer_gate_contract_exact() {
    local action20d_retry2_a_focused_gate_root

    action20d_retry2_a_focused_gate_root=$(mktemp -d \
        /tmp/caddy-action20d-retry10-d-retry2-a-focused-gates.XXXXXX) || return 1
    trap 'rm -rf -- "$action20d_retry2_a_focused_gate_root"; trap - RETURN' RETURN
    /bin/bash "$outer" --expected-local-gates | LC_ALL=C sort \
        >"$action20d_retry2_a_focused_gate_root/observed" || return 1
    printf '%s\n' \
        working_directory inspector_source runner_source regression_source \
        multifile_policy_source accepted_transaction_source plan_acceptance syntax shellcheck \
        canonical_format collision_policy conditional_policy transcript_policy \
        output_policy multifile_count_policy inspector_self_test runner_self_test \
        production_regression |
        LC_ALL=C sort >"$action20d_retry2_a_focused_gate_root/expected"
    cmp -s "$action20d_retry2_a_focused_gate_root/expected" \
        "$action20d_retry2_a_focused_gate_root/observed"
}
definition_only_contract() {
    local action20d_retry2_a_focused_source

    grep -Fq "pi@10.1.0.53 'cd / && sudo /bin/bash -s -- --inspect'" "$runner" || return 1
    for action20d_retry2_a_focused_source in "$inspector" "$runner" "$outer"; do
        [[ "$(grep -Fc 'pi@10.1.0.54' "$action20d_retry2_a_focused_source" || true)" -eq 0 ]] || return 1
        [[ "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
            "$action20d_retry2_a_focused_source" || true)" -eq 0 ]] || return 1
        [[ "$(grep -Ec '(^|[[:space:]])(ip[[:space:]]+address[[:space:]]+(add|del)|keepalived[[:space:]])' \
            "$action20d_retry2_a_focused_source" || true)" -eq 0 ]] || return 1
    done
    [[ "$(grep -Ec '^[[:space:]]*"?\$health_helper"?([[:space:]]*>|$)' \
        "$inspector" || true)" -eq 0 ]] || return 1
    grep -Fq '/bin/bash "$health_helper" --self-test' "$inspector" || return 1
    grep -Fq 'setpriv --reuid "$script_uid" --regid "$tls_gid" --clear-groups --' \
        "$inspector" || return 1
    grep -Fq "printf '%s_full_health_helper_invoked=false\\n' \"\$prefix\"" \
        "$runner" || return 1
}

record_check source_hashes source_hashes_exact
record_check syntax /bin/bash -n "$inspector" "$runner" "$regression" "$outer" "$0"
record_check shellcheck shellcheck "$inspector" "$runner" "$regression" "$outer" "$0"
record_check canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
    "$inspector" "$runner" "$regression" "$outer" "$0"
record_check executable_metadata entrypoints_executable
record_check executable_policy /bin/bash \
    "$script_directory/executable-wrapper-policy-regression.sh"
record_check collision_policy /bin/bash \
    "$script_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$runner" "$regression" "$outer" "$0"
record_check conditional_policy /bin/bash \
    "$script_directory/conditional-validator-errexit-policy-regression.sh"
record_check transcript_policy /bin/bash \
    "$script_directory/transcript-contract-ratchet-policy-regression.sh"
record_check output_policy /bin/bash \
    "$script_directory/transaction-output-evidence-policy-regression.sh"
record_check multifile_count_policy /bin/bash \
    "$script_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$runner" "$regression" "$outer" "$0"
record_check outer_label_policy /bin/bash \
    "$script_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check runner_self_test /bin/bash "$runner" --self-test
record_check production_regression /bin/bash "$regression"
record_check outer_gate_contract outer_gate_contract_exact
record_check outer_self_test /bin/bash "$outer" --self-test
record_check definition_only definition_only_contract

printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
