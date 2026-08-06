#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry2_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-helper-action20h-retry2.sh
readonly regression=$test_directory/action20h-retry2-environment-regression.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h-retry2-outer.sh
readonly builder_sha256=272c45dff2975f3b6f0fbbcae39b5054fd25ec4302c73f2213d7cda44094787d
readonly regression_sha256=1b281b216fe18355899556268de04336b71c498929522368995e88ad35c85313
readonly outer_sha256=accc8c83a8f34429ea14b4a433db8e8190c807c7cecb2fb1cce58ab62579ca89
readonly generated_installer_sha256=702f4ed558dccf213a0d24d1587118eabc3fe5da5c1d342a0c8ddac8a8d14dc2
readonly generated_runner_sha256=aff13c6c73cce6ce5f6067f0b10b8c33e3a20b33e1358a3fe4e7f742602cdb3a

work_root=$(mktemp -d /tmp/caddy-action20h-retry2-focused.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20h_retry2_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry2_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry2_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$builder")" = "$builder_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]]
}
generated_hashes_exact() {
    local action20h_retry2_generated_root=$work_root/generated

    /bin/bash "$builder" --output "$action20h_retry2_generated_root" >/dev/null || return 1
    [[ "$(file_hash "$action20h_retry2_generated_root/install-node-a-caddy-health-helper-action20h-retry2.sh")" = "$generated_installer_sha256" ]] || return 1
    [[ "$(file_hash "$action20h_retry2_generated_root/run-node-a-caddy-health-helper-action20h-retry2.sh")" = "$generated_runner_sha256" ]]
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$builder" "$regression" "$outer" || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$builder" "$regression" "$outer" || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$builder" "$outer" || return 1
}
environment_contract_exact() {
    local action20h_retry2_generated_installer=$work_root/generated/install-node-a-caddy-health-helper-action20h-retry2.sh

    grep -Fq 'set -a; source /etc/default/caddy-ha; set +a' \
        "$action20h_retry2_generated_installer" || return 1
    [[ "$(grep -Eo '\$\{(NODE_ROLE|NODE_FQDN|NODE_IPV4|NODE_IPV6|CADDY_CONFIG_ROOT):\?\}' \
        "$action20h_retry2_generated_installer" | LC_ALL=C sort -u | wc -l)" -eq 5 ]] || return 1
    [[ "$(grep -Fc 'source /etc/default/caddy-ha' \
        "$action20h_retry2_generated_installer" || true)" -eq 1 ]]
}

gate source_hashes source_hashes_exact
gate syntax /bin/bash -n "$builder" "$regression" "$outer" "$0"
gate shellcheck shellcheck "$builder" "$regression" "$outer" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$regression" "$outer" "$0"
gate generated_hashes generated_hashes_exact
gate environment_contract environment_contract_exact
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
