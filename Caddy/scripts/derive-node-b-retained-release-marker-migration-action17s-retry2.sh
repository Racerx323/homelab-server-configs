#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_transaction_sha256=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0
readonly historical_runner_sha256=f5319707d8943eb9f129da5c31b8724cf0ef608eee3847c10ac43e9122a96700
readonly historical_regression_sha256=fbd83338656365058965a30ba974aad7df38c347845af183f0888a9b93572559
readonly historical_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly accepted_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly corrected_transaction_sha256=e6d0f6a702f986742912707f1bea92c000dfd8cff99f76a589276e52ba591ae3
readonly corrected_runner_sha256=042629e0f095976686e1103d0c9ddd281b136c71eff78e476433e5943099149b
readonly corrected_regression_sha256=37d991bb9ed74679907e1ec3cae21b399a14ed244ee27ef7562797256028ad07

derivation_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly derivation_script_directory
derivation_caddy_root=$(cd -- "$derivation_script_directory/.." && pwd)
readonly derivation_caddy_root
readonly historical_transaction="$derivation_script_directory/migrate-node-b-retained-release-marker-action17s-retry.sh"
readonly historical_runner="$derivation_script_directory/run-node-b-retained-release-marker-migration-action17s-retry.sh"
readonly historical_regression="$derivation_caddy_root/tests/action17s-retry-node-b-marker-migration-regression.sh"
readonly collision_checker="$derivation_caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$derivation_caddy_root/tests/run-source-test-in-context.sh"
readonly historical_node_a_inspector="$derivation_script_directory/inspect-node-a-protocol-v2-readiness-action17r-c.sh"
readonly historical_node_b_inspector="$derivation_script_directory/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly historical_readiness_runner="$derivation_script_directory/run-dual-node-protocol-v2-readiness-action17r-c.sh"
readonly historical_readiness_regression="$derivation_caddy_root/tests/action17r-c-dual-node-protocol-v2-readiness-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_input() {
    local input_path=$1
    local input_hash=$2

    [[ -f "$input_path" && ! -L "$input_path" ]] || return 1
    [[ "$(file_hash "$input_path")" == "$input_hash" ]] || return 1
}

render_transaction() {
    local transaction_source=$1

    verify_input "$transaction_source" "$historical_transaction_sha256" || return 1
    awk -v historical_finalizer="$historical_finalizer_sha256" \
        -v accepted_finalizer="$accepted_finalizer_sha256" '
        {
            line = $0
            gsub(/action_17s_retry/, "action_17s_retry2", line)
            gsub(/action17s-retry/, "action17s-retry2", line)
            if (index(line, historical_finalizer)) {
                sub(historical_finalizer, accepted_finalizer, line)
                finalizer_changed++
            }
            print line
        }
        END {
            if (finalizer_changed != 1) {
                exit 42
            }
        }
    ' "$transaction_source"
}

render_runner() {
    local runner_source=$1

    verify_input "$runner_source" "$historical_runner_sha256" || return 1
    awk -v historical_transaction_hash="$historical_transaction_sha256" \
        -v corrected_transaction_hash="$corrected_transaction_sha256" '
        {
            line = $0
            gsub(/action_17s_retry/, "action_17s_retry2", line)
            gsub(/action17s-retry/, "action17s-retry2", line)
            if (index(line, historical_transaction_hash)) {
                sub(historical_transaction_hash, corrected_transaction_hash, line)
                transaction_hash_changed++
            }
            print line
        }
        END {
            if (transaction_hash_changed != 1) {
                exit 42
            }
        }
    ' "$runner_source"
}

render_regression() {
    local regression_source=$1

    verify_input "$regression_source" "$historical_regression_sha256" || return 1
    awk -v historical_transaction_hash="$historical_transaction_sha256" \
        -v corrected_transaction_hash="$corrected_transaction_sha256" \
        -v historical_runner_hash="$historical_runner_sha256" \
        -v corrected_runner_hash="$corrected_runner_sha256" \
        -v historical_finalizer="$historical_finalizer_sha256" \
        -v accepted_finalizer="$accepted_finalizer_sha256" '
        {
            line = $0
            gsub(/action_17s_retry/, "action_17s_retry2", line)
            gsub(/action17s-retry/, "action17s-retry2", line)
            if (index(line, historical_transaction_hash)) {
                sub(historical_transaction_hash, corrected_transaction_hash, line)
                transaction_hash_changed++
            }
            if (index(line, historical_runner_hash)) {
                sub(historical_runner_hash, corrected_runner_hash, line)
                runner_hash_changed++
            }
            if (index(line, historical_finalizer)) {
                sub(historical_finalizer, accepted_finalizer, line)
                finalizer_changed++
            }
            print line
        }
        END {
            if (transaction_hash_changed != 1 || runner_hash_changed != 1 ||
                finalizer_changed != 1) {
                exit 42
            }
        }
    ' "$regression_source"
}

self_test() {
    local self_root self_scripts self_tests
    local rendered_transaction rendered_runner rendered_regression

    self_root=$(mktemp -d "$derivation_caddy_root/.action17s-retry2-derivation.XXXXXX")
    trap '[[ -z ${self_root:-} ]] || rm -rf -- "$self_root"' EXIT
    self_scripts="$self_root/Caddy/scripts"
    self_tests="$self_root/Caddy/tests"
    rendered_transaction="$self_scripts/migrate-node-b-retained-release-marker-action17s-retry2.sh"
    rendered_runner="$self_scripts/run-node-b-retained-release-marker-migration-action17s-retry2.sh"
    rendered_regression="$self_tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh"
    install -d -m 0700 "$self_scripts" "$self_tests"
    install -m 0755 -- "$collision_checker" "$source_context_policy" "$self_tests/"
    install -m 0755 -- "$historical_node_a_inspector" "$historical_node_b_inspector" \
        "$historical_readiness_runner" "$self_scripts/"
    install -m 0755 -- "$historical_readiness_regression" "$self_tests/"
    render_transaction "$historical_transaction" >"$rendered_transaction"
    render_runner "$historical_runner" >"$rendered_runner"
    render_regression "$historical_regression" >"$rendered_regression"
    chmod 0755 "$rendered_transaction" "$rendered_runner" "$rendered_regression"
    [[ "$(file_hash "$rendered_transaction")" == "$corrected_transaction_sha256" ]]
    [[ "$(file_hash "$rendered_runner")" == "$corrected_runner_sha256" ]]
    [[ "$(file_hash "$rendered_regression")" == "$corrected_regression_sha256" ]]
    bash -n "$rendered_transaction" "$rendered_runner" "$rendered_regression"
    "$rendered_transaction" --self-test >/dev/null
    "$rendered_runner" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
    "$rendered_regression" >/dev/null
    rm -rf -- "$self_root"
    self_root=
    trap - EXIT
    printf 'action_17s_retry2_derivation_self_test_complete=true\n'
}

case "${1:-}" in
    --render-transaction)
        [[ $# -eq 2 ]] || exit 64
        render_transaction "$2"
        ;;
    --render-runner)
        [[ $# -eq 2 ]] || exit 64
        render_runner "$2"
        ;;
    --render-regression)
        [[ $# -eq 2 ]] || exit 64
        render_regression "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *)
        printf 'Usage: %s --render-transaction SOURCE | --render-runner SOURCE | --render-regression SOURCE | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
