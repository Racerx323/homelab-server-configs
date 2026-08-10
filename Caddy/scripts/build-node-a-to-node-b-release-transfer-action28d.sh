#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly predecessor_builder_sha256=bc17385186d282412e7f89f9bcdb150bf17eaa6427d09667b57e7d38debef86f
readonly predecessor_driver_sha256=175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9
readonly predecessor_inspector_sha256=475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513
readonly predecessor_runner_sha256=15689ce1b521c32d10fd927a69f346f8499fff60b422a2ce375fe9aa16c23eaf

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly predecessor_builder=$script_directory/build-node-a-to-node-b-release-transfer-action28c.sh
work_root=$(mktemp -d /tmp/caddy-action28d-builder.XXXXXX)
readonly work_root
readonly predecessor_output=$work_root/predecessor

cleanup() {
    local action28d_builder_status=$?

    rm -rf -- "$work_root"
    exit "$action28d_builder_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_source() {
    local action28d_builder_expected_hash=$1
    local action28d_builder_source=$2

    [[ -f "$action28d_builder_source" && ! -L "$action28d_builder_source" &&
        -x "$action28d_builder_source" ]] || return 1
    [[ "$(file_hash "$action28d_builder_source")" = "$action28d_builder_expected_hash" ]]
}
exact_count() {
    local action28d_builder_pattern=$1
    local action28d_builder_source=$2

    grep -Fc "$action28d_builder_pattern" "$action28d_builder_source" || true
}
render_component() {
    local action28d_builder_source=$1
    local action28d_builder_output=$2

    sed -e 's/action_28c/action_28d/g' \
        -e 's/action28c/action28d/g' \
        -e 's/ACTION28C/ACTION28D/g' \
        "$action28d_builder_source" >"$action28d_builder_output"
}
render_runner() {
    local action28d_builder_source=$1
    local action28d_builder_output=$2

    # The pattern intentionally matches literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(exact_count \
        '"cd / && sudo -n /bin/bash -s/ -- $remote_argument"' \
        "$action28d_builder_source")" -eq 1 ]] || return 1
    render_component "$action28d_builder_source" "$action28d_builder_output" || return 1
    # The expression intentionally rewrites literal generated shell source.
    # shellcheck disable=SC2016
    sed -i \
        -e 's/175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9/be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58/' \
        -e 's/475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513/4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482/' \
        -e \
        's|sudo -n /bin/bash -s/ -- $remote_argument|sudo -n /bin/bash -s -- $remote_argument|' \
        "$action28d_builder_output"
    # The pattern intentionally matches literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(exact_count \
        '"cd / && sudo -n /bin/bash -s -- $remote_argument"' \
        "$action28d_builder_output")" -eq 1 ]] || return 1
    ! grep -Fq '/bin/bash -s/' "$action28d_builder_output"
}

[[ $# -eq 1 ]]
readonly output_directory=$1
[[ -d "$output_directory" && ! -L "$output_directory" ]]
require_source "$predecessor_builder_sha256" "$predecessor_builder"
mkdir -m 0700 "$predecessor_output"
/bin/bash "$predecessor_builder" "$predecessor_output"
require_source "$predecessor_driver_sha256" \
    "$predecessor_output/transfer-node-a-release-to-node-b-action28c.sh"
require_source "$predecessor_inspector_sha256" \
    "$predecessor_output/inspect-node-b-incoming-release-action28c.sh"
require_source "$predecessor_runner_sha256" \
    "$predecessor_output/run-node-a-to-node-b-release-transfer-action28c.sh"

render_component \
    "$predecessor_output/transfer-node-a-release-to-node-b-action28c.sh" \
    "$output_directory/transfer-node-a-release-to-node-b-action28d.sh"
render_component \
    "$predecessor_output/inspect-node-b-incoming-release-action28c.sh" \
    "$output_directory/inspect-node-b-incoming-release-action28d.sh"
render_runner \
    "$predecessor_output/run-node-a-to-node-b-release-transfer-action28c.sh" \
    "$output_directory/run-node-a-to-node-b-release-transfer-action28d.sh"
chmod 0755 "$output_directory"/*.sh
