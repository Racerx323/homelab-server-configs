#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17s_retry2_outer
readonly historical_transaction_sha256=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0
readonly historical_runner_sha256=f5319707d8943eb9f129da5c31b8724cf0ef608eee3847c10ac43e9122a96700
readonly historical_regression_sha256=fbd83338656365058965a30ba974aad7df38c347845af183f0888a9b93572559
readonly action17u_c_runner_sha256=297b7601e83a70dfbe970aeecd57279d847b6348eb4392244bf8a35521301736
readonly derivation_sha256=dd83a8439034f66d69eb9b2e392bb31c62687dff73f23749da3f81c6a119e5e6
readonly wrapper_regression_sha256=29f46ed51b3c301228c8628c3cfd01ef6b100688e4d925b77d33d8cfb708901f
readonly corrected_transaction_sha256=e6d0f6a702f986742912707f1bea92c000dfd8cff99f76a589276e52ba591ae3
readonly corrected_runner_sha256=042629e0f095976686e1103d0c9ddd281b136c71eff78e476433e5943099149b
readonly corrected_regression_sha256=37d991bb9ed74679907e1ec3cae21b399a14ed244ee27ef7562797256028ad07

outer_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly outer_script_directory
outer_caddy_root=$(cd -- "$outer_script_directory/.." && pwd)
readonly outer_caddy_root
readonly historical_transaction="$outer_script_directory/migrate-node-b-retained-release-marker-action17s-retry.sh"
readonly historical_runner="$outer_script_directory/run-node-b-retained-release-marker-migration-action17s-retry.sh"
readonly historical_regression="$outer_caddy_root/tests/action17s-retry-node-b-marker-migration-regression.sh"
readonly action17u_c_runner="$outer_script_directory/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
readonly derivation="$outer_script_directory/derive-node-b-retained-release-marker-migration-action17s-retry2.sh"
readonly wrapper_regression="$outer_caddy_root/tests/action17s-retry2-node-b-marker-migration-regression.sh"
readonly collision_checker="$outer_caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$outer_caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$outer_caddy_root/tests/run-source-test-in-context.sh"
readonly historical_node_a_inspector="$outer_script_directory/inspect-node-a-protocol-v2-readiness-action17r-c.sh"
readonly historical_node_b_inspector="$outer_script_directory/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly historical_readiness_runner="$outer_script_directory/run-dual-node-protocol-v2-readiness-action17r-c.sh"
readonly historical_readiness_regression="$outer_caddy_root/tests/action17r-c-dual-node-protocol-v2-readiness-regression.sh"

outer_work_directory=

# Invoked indirectly by the EXIT trap installed after each private stage.
# shellcheck disable=SC2317
cleanup_outer_work_directory() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$outer_work_directory" && -d "$outer_work_directory" ]]; then
        rm -rf -- "$outer_work_directory"
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verification_path=$1
    local verification_hash=$2

    [[ -f "$verification_path" && ! -L "$verification_path" ]] || return 1
    [[ "$(file_hash "$verification_path")" == "$verification_hash" ]] || return 1
}

verify_sources() {
    verify_file "$historical_transaction" "$historical_transaction_sha256" || return 1
    verify_file "$historical_runner" "$historical_runner_sha256" || return 1
    verify_file "$historical_regression" "$historical_regression_sha256" || return 1
    verify_file "$action17u_c_runner" "$action17u_c_runner_sha256" || return 1
    verify_file "$derivation" "$derivation_sha256" || return 1
    verify_file "$wrapper_regression" "$wrapper_regression_sha256" || return 1
    bash -n "$derivation" "$wrapper_regression" || return 1
    "$collision_checker" "$derivation" "$wrapper_regression" >/dev/null || return 1
}

render_stage() {
    local stage_root=$1
    local stage_scripts="$stage_root/Caddy/scripts"
    local stage_tests="$stage_root/Caddy/tests"
    local stage_runner="$stage_scripts/run-node-b-retained-release-marker-migration-action17s-retry2.sh"

    install -d -m 0700 "$stage_scripts" "$stage_tests"
    "$derivation" --render-transaction "$historical_transaction" \
        >"$stage_scripts/migrate-node-b-retained-release-marker-action17s-retry2.sh"
    "$derivation" --render-runner "$historical_runner" >"$stage_runner"
    "$derivation" --render-regression "$historical_regression" \
        >"$stage_tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh"
    install -m 0755 -- "$inner_collision_checker" "$source_context_policy" "$stage_tests/"
    install -m 0755 -- "$historical_node_a_inspector" "$historical_node_b_inspector" \
        "$historical_readiness_runner" "$stage_scripts/"
    install -m 0755 -- "$historical_readiness_regression" "$stage_tests/"
    chmod 0755 "$stage_scripts/"* "$stage_tests/"*
    verify_file "$stage_scripts/migrate-node-b-retained-release-marker-action17s-retry2.sh" \
        "$corrected_transaction_sha256" || return 1
    verify_file "$stage_runner" "$corrected_runner_sha256" || return 1
    verify_file "$stage_tests/action17s-retry2-node-b-marker-migration-regression.rendered.sh" \
        "$corrected_regression_sha256" || return 1
    printf '%s\n' "$stage_runner"
}

run_local_gates() {
    local gate_root=$1
    local gate_runner

    "$derivation" --self-test >/dev/null || return 1
    "$wrapper_regression" >/dev/null || return 1
    gate_runner=$(render_stage "$gate_root") || return 1
    "$gate_runner" --self-test >/dev/null || return 1
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
        "$gate_runner" --source-test >/dev/null || return 1
    fi
    "$gate_runner" --contract-test >/dev/null || return 1
}

case "${1:-}" in
    --self-test | --contract-test)
        test_mode=${1#--}
        test_mode=${test_mode//-/_}
        readonly test_mode
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        outer_work_directory=$(mktemp -d /tmp/caddy-action17s-retry2-outer-test.XXXXXX)
        trap cleanup_outer_work_directory EXIT
        run_local_gates "$outer_work_directory"
        rm -rf -- "$outer_work_directory"
        outer_work_directory=
        trap - EXIT
        printf '%s_%s_complete=true\n' "$action_prefix" "$test_mode"
        exit 0
        ;;
    --source-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_source_test_complete=true\n' "$action_prefix"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
[[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
outer_work_directory=$(mktemp -d /tmp/caddy-action17s-retry2-outer.XXXXXX)
trap cleanup_outer_work_directory EXIT
run_local_gates "$outer_work_directory/local"
rendered_runner=$(render_stage "$outer_work_directory/live")
readonly rendered_runner
inner_status=0
"$rendered_runner" || inner_status=$?
rm -rf -- "$outer_work_directory"
outer_work_directory=
trap - EXIT
printf '%s_cleanup_complete=true\n' "$action_prefix"
exit "$inner_status"
