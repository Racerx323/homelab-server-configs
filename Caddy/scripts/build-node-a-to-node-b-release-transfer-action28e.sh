#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly predecessor_builder_sha256=5f7cf9afe81b142ecab17f4fc07570f62cf63a535c710ecf59f443d819d92f4f
readonly predecessor_driver_sha256=be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58
readonly predecessor_inspector_sha256=4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482
readonly predecessor_runner_sha256=df6847bac598b8cd8453809a1fdddf6e28cabcfe45352ed6ed03ffb45aa429cc

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly predecessor_builder=$script_directory/build-node-a-to-node-b-release-transfer-action28d.sh
work_root=$(mktemp -d /tmp/caddy-action28e-builder.XXXXXX)
readonly work_root
readonly predecessor_output=$work_root/predecessor

cleanup() {
    local action28e_builder_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_builder_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_source() {
    local action28e_builder_expected_hash=$1
    local action28e_builder_source=$2

    [[ -f "$action28e_builder_source" && ! -L "$action28e_builder_source" &&
        -x "$action28e_builder_source" ]] || return 1
    [[ "$(file_hash "$action28e_builder_source")" = "$action28e_builder_expected_hash" ]]
}
exact_count() {
    local action28e_builder_pattern=$1
    local action28e_builder_source=$2

    grep -Fc "$action28e_builder_pattern" "$action28e_builder_source" || true
}
render_component() {
    local action28e_builder_source=$1
    local action28e_builder_output=$2

    sed -e 's/action_28d/action_28e/g' \
        -e 's/action28d/action28e/g' \
        -e 's/ACTION28D/ACTION28E/g' \
        "$action28e_builder_source" >"$action28e_builder_output"
}
render_driver() {
    local action28e_builder_source=$1
    local action28e_builder_output=$2

    [[ "$(exact_count 'readonly source_release=/etc/caddy/current' \
        "$action28e_builder_source")" -eq 1 ]] || return 1
    [[ "$(exact_count 'record_preflight() {' "$action28e_builder_source")" -eq 1 ]] || return 1
    # The patterns intentionally match literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(exact_count '    record_command source_release_symlink test -L "$source_release"' \
        "$action28e_builder_source")" -eq 1 ]] || return 1
    # shellcheck disable=SC2016
    [[ "$(exact_count '    "$publisher" --source "$source_release" --node-role node-a' \
        "$action28e_builder_source")" -eq 1 ]] || return 1

    render_component "$action28e_builder_source" "$action28e_builder_output" || return 1
    awk '
        /^readonly source_release=\/etc\/caddy\/current$/ {
            print
            print "# action28e-source-contract-state-begin"
            print "readonly release_root=/etc/caddy/releases"
            print "resolved_source_release="
            print "# action28e-source-contract-state-end"
            next
        }
        /^record_preflight\(\) \{$/ {
            print "# action28e-source-contract-functions-begin"
            print "resolve_source_release() {"
            print "    local action28e_node_a_source_link=$1"
            print "    local action28e_node_a_resolved"
            print ""
            print "    action28e_node_a_resolved=$(readlink -f -- \"$action28e_node_a_source_link\") || return 1"
            print "    [[ -n \"$action28e_node_a_resolved\" ]] || return 1"
            print "    resolved_source_release=$action28e_node_a_resolved"
            print "}"
            print "source_target_absolute() {"
            print "    [[ \"$1\" == /* ]]"
            print "}"
            print "source_target_direct_child() {"
            print "    [[ \"$(dirname -- \"$1\")\" = \"$2\" ]]"
            print "}"
            print "source_contract_test() {"
            print "    local action28e_node_a_source_link=$1"
            print "    local action28e_node_a_release_root=$2"
            print "    local action28e_node_a_expected_tree=$3"
            print ""
            print "    # conditional-validator-explicit-failures-begin"
            print "    [[ -d \"$action28e_node_a_release_root\" ]] || return 1"
            print "    [[ ! -L \"$action28e_node_a_release_root\" ]] || return 1"
            print "    [[ -d \"$action28e_node_a_source_link\" ]] || return 1"
            print "    [[ -L \"$action28e_node_a_source_link\" ]] || return 1"
            print "    resolve_source_release \"$action28e_node_a_source_link\" || return 1"
            print "    source_target_absolute \"$resolved_source_release\" || return 1"
            print "    source_target_direct_child \"$resolved_source_release\" \"$action28e_node_a_release_root\" || return 1"
            print "    [[ -d \"$resolved_source_release\" ]] || return 1"
            print "    [[ ! -L \"$resolved_source_release\" ]] || return 1"
            print "    [[ \"$action28e_node_a_source_link\" -ef \"$resolved_source_release\" ]] || return 1"
            print "    [[ \"$(tree_digest \"$resolved_source_release\")\" = \"$action28e_node_a_expected_tree\" ]] || return 1"
            print "    # conditional-validator-explicit-failures-end"
            print "}"
            print "# action28e-source-contract-functions-end"
        }
        /^    record_command source_release_symlink test -L "[$]source_release"$/ {
            print "    # action28e-source-contract-assertions-begin"
            print "    record_command release_root_directory test -d \"$release_root\""
            print "    record_command release_root_not_symlink test ! -L \"$release_root\""
            print "    record_command source_target_resolved resolve_source_release \"$source_release\""
            print "    record_command source_target_absolute source_target_absolute \"$resolved_source_release\""
            print "    record_command source_target_direct_child source_target_direct_child \"$resolved_source_release\" \"$release_root\""
            print "    record_command source_target_directory test -d \"$resolved_source_release\""
            print "    record_command source_target_not_symlink test ! -L \"$resolved_source_release\""
            print "    record_command source_target_identity test \"$source_release\" -ef \"$resolved_source_release\""
            print "    record_command source_target_tree_exact test \"$(tree_digest \"$resolved_source_release\" 2>/dev/null || true)\" = \"$expected_current_tree_sha256\""
            print "    # action28e-source-contract-assertions-end"
        }
        /^if \[\[ "[$][{]1:-[}]" == --self-test/ {
            print "# action28e-source-contract-test-mode-begin"
            print "if [[ \"${1:-}\" == --source-contract-test ]]; then"
            print "    [[ $# -eq 4 ]] || exit 64"
            print "    source_contract_test \"$2\" \"$3\" \"$4\" || exit 97"
            print "    printf \047%s_source_contract_resolved=%s\\n\047 \"$prefix\" \"$resolved_source_release\""
            print "    printf \047%s_source_contract_complete=true\\n\047 \"$prefix\""
            print "    exit 0"
            print "fi"
            print "# action28e-source-contract-test-mode-end"
        }
        /^    "[$]publisher" --source "[$]source_release" --node-role node-a [\\]$/ {
            print "    # action28e-source-contract-invocation-begin"
            print "    \"$publisher\" --source \"$resolved_source_release\" --node-role node-a \\"
            print "    # action28e-source-contract-invocation-end"
            next
        }
        { print }
    ' "$action28e_builder_output" >"$action28e_builder_output.tmp" || return 1
    mv -- "$action28e_builder_output.tmp" "$action28e_builder_output"

    # The patterns intentionally match literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(exact_count '"$publisher" --source "$resolved_source_release" --node-role node-a' \
        "$action28e_builder_output")" -eq 1 ]] || return 1
    # shellcheck disable=SC2016
    ! grep -Fq '"$publisher" --source "$source_release" --node-role node-a' \
        "$action28e_builder_output"
}
render_runner() {
    local action28e_builder_source=$1
    local action28e_builder_output=$2

    [[ "$(exact_count "$predecessor_driver_sha256" "$action28e_builder_source")" -eq 1 ]] || return 1
    [[ "$(exact_count "$predecessor_inspector_sha256" "$action28e_builder_source")" -eq 1 ]] || return 1
    render_component "$action28e_builder_source" "$action28e_builder_output" || return 1
    sed -i \
        -e 's/be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58/ce27b4b280e8f31ec240d53c930d4140ff3ad809f43313c7d8b8500d6cfc1405/' \
        -e 's/4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482/56caf44ea261f997d177e9bc4cf340538e3a0de7d0fe39097a88d692d93b8e09/' \
        "$action28e_builder_output"
    [[ "$(exact_count 'ce27b4b280e8f31ec240d53c930d4140ff3ad809f43313c7d8b8500d6cfc1405' \
        "$action28e_builder_output")" -eq 1 ]] || return 1
    [[ "$(exact_count '56caf44ea261f997d177e9bc4cf340538e3a0de7d0fe39097a88d692d93b8e09' \
        "$action28e_builder_output")" -eq 1 ]]
}

[[ $# -eq 1 ]]
readonly output_directory=$1
[[ -d "$output_directory" && ! -L "$output_directory" ]]
require_source "$predecessor_builder_sha256" "$predecessor_builder"
mkdir -m 0700 "$predecessor_output"
/bin/bash "$predecessor_builder" "$predecessor_output"
require_source "$predecessor_driver_sha256" \
    "$predecessor_output/transfer-node-a-release-to-node-b-action28d.sh"
require_source "$predecessor_inspector_sha256" \
    "$predecessor_output/inspect-node-b-incoming-release-action28d.sh"
require_source "$predecessor_runner_sha256" \
    "$predecessor_output/run-node-a-to-node-b-release-transfer-action28d.sh"

render_driver \
    "$predecessor_output/transfer-node-a-release-to-node-b-action28d.sh" \
    "$output_directory/transfer-node-a-release-to-node-b-action28e.sh"
render_component \
    "$predecessor_output/inspect-node-b-incoming-release-action28d.sh" \
    "$output_directory/inspect-node-b-incoming-release-action28e.sh"
render_runner \
    "$predecessor_output/run-node-a-to-node-b-release-transfer-action28d.sh" \
    "$output_directory/run-node-a-to-node-b-release-transfer-action28e.sh"
chmod 0755 "$output_directory"/*.sh
