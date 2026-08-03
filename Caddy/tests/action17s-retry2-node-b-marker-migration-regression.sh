#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=$(cd -- "$test_directory/.." && pwd)
readonly caddy_root
readonly derivation="$caddy_root/scripts/derive-node-b-retained-release-marker-migration-action17s-retry2.sh"
readonly historical_transaction="$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s-retry.sh"
readonly historical_runner="$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry.sh"
readonly historical_regression="$test_directory/action17s-retry-node-b-marker-migration-regression.sh"
readonly historical_node_a_inspector="$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r-c.sh"
readonly historical_node_b_inspector="$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly historical_readiness_runner="$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh"
readonly historical_readiness_regression="$test_directory/action17r-c-dual-node-protocol-v2-readiness-regression.sh"
readonly derivation_sha256=dd83a8439034f66d69eb9b2e392bb31c62687dff73f23749da3f81c6a119e5e6
readonly corrected_transaction_sha256=e6d0f6a702f986742912707f1bea92c000dfd8cff99f76a589276e52ba591ae3
readonly corrected_runner_sha256=042629e0f095976686e1103d0c9ddd281b136c71eff78e476433e5943099149b
readonly corrected_regression_sha256=37d991bb9ed74679907e1ec3cae21b399a14ed244ee27ef7562797256028ad07

cleanup_root=

cleanup() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$cleanup_root" && -d "$cleanup_root" ]]; then
        rm -rf -- "$cleanup_root"
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_tree() {
    local render_root=$1
    local render_scripts="$render_root/Caddy/scripts"
    local render_tests="$render_root/Caddy/tests"

    install -d -m 0700 "$render_scripts" "$render_tests"
    "$derivation" --render-transaction "$historical_transaction" \
        >"$render_scripts/migrate-node-b-retained-release-marker-action17s-retry2.sh"
    "$derivation" --render-runner "$historical_runner" \
        >"$render_scripts/run-node-b-retained-release-marker-migration-action17s-retry2.sh"
    "$derivation" --render-regression "$historical_regression" \
        >"$render_tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh"
    install -m 0755 -- "$test_directory/check-shell-readonly-local-collisions.sh" \
        "$test_directory/run-source-test-in-context.sh" "$render_tests/"
    install -m 0755 -- "$historical_node_a_inspector" "$historical_node_b_inspector" \
        "$historical_readiness_runner" "$render_scripts/"
    install -m 0755 -- "$historical_readiness_regression" "$render_tests/"
    chmod 0755 "$render_scripts/"* "$render_tests/"*
    [[ "$(file_hash "$render_scripts/migrate-node-b-retained-release-marker-action17s-retry2.sh")" == "$corrected_transaction_sha256" ]]
    [[ "$(file_hash "$render_scripts/run-node-b-retained-release-marker-migration-action17s-retry2.sh")" == "$corrected_runner_sha256" ]]
    [[ "$(file_hash "$render_tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh")" == "$corrected_regression_sha256" ]]
}

run_regression() {
    local rendered_regression

    [[ "$(file_hash "$derivation")" == "$derivation_sha256" ]]
    cleanup_root=$(mktemp -d "$caddy_root/.action17s-retry2-regression-wrapper.XXXXXX")
    trap cleanup EXIT
    render_tree "$cleanup_root"
    rendered_regression="$cleanup_root/Caddy/tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh"
    "$rendered_regression"
    printf 'action_17s_retry2_regression_wrapper_network_contact=false\n'
    printf 'action_17s_retry2_regression_wrapper_complete=true\n'
    rm -rf -- "$cleanup_root"
    cleanup_root=
    trap - EXIT
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$derivation_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf 'action_17s_retry2_regression_wrapper_self_test_complete=true\n'
        ;;
    "")
        run_regression
        ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
