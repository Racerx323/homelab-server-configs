#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry3_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-helper-action20h-retry3.sh
readonly regression=$test_directory/action20h-retry3-environment-regression.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h-retry3-outer.sh
readonly builder_sha256=1097a1c6958bce9145efa94a1f936536218de81fc1a3c617342a461f7566bfe7
readonly regression_sha256=9a5c8377fcaf5926ab33eb9c561e19c2f17a25c44676eaed8561336dd88b40ac
readonly outer_sha256=df3a496def5a0e65066933ac10ace0470c64f6742234bbd24d9e3c2bc90920c9
readonly generated_installer_sha256=21ad902d76816334c7c0ce0893f4d9f64ef0e44a1ffbeb9d0beea8f79bfd58a2
readonly generated_runner_sha256=ca7c63d100e1d9ef76ddadac83cd3d7ff444f76be033d420ddee937036004f99

work_root=$(mktemp -d /tmp/caddy-action20h-retry3-focused.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
gate() {
    local action20h_retry3_focused_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry3_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry3_focused_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$builder")" = "$builder_sha256" ]] || return 1
    [[ "$(file_hash "$regression")" = "$regression_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" = "$outer_sha256" ]]
}
generated_contract_exact() {
    local action20h_retry3_generated_root=$work_root/generated
    local action20h_retry3_generated_installer

    /bin/bash "$builder" --output "$action20h_retry3_generated_root" >/dev/null || return 1
    action20h_retry3_generated_installer=$action20h_retry3_generated_root/install-node-a-caddy-health-helper-action20h-retry3.sh
    [[ "$(file_hash "$action20h_retry3_generated_installer")" = "$generated_installer_sha256" ]] || return 1
    [[ "$(file_hash "$action20h_retry3_generated_root/run-node-a-caddy-health-helper-action20h-retry3.sh")" = "$generated_runner_sha256" ]] || return 1
    [[ "$(grep -Eo '\$\{(NODE_ROLE|NODE_FQDN|NODE_IPV4|NODE_IPV6):\?\}' \
        "$action20h_retry3_generated_installer" | LC_ALL=C sort -u | wc -l)" -eq 4 ]] || return 1
    [[ "$(grep -Fc 'CADDY_CONFIG_ROOT:?' "$action20h_retry3_generated_installer" || true)" -eq 0 ]]
}
definition_only_scope() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$builder" "$regression" "$outer" || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$builder" "$outer"
}

gate source_hashes source_hashes_exact
gate syntax /bin/bash -n "$builder" "$regression" "$outer" "$0"
gate shellcheck shellcheck "$builder" "$regression" "$outer" "$0"
gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$regression" "$outer" "$0"
gate generated_contract generated_contract_exact
gate outer_label_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
gate definition_only definition_only_scope
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
