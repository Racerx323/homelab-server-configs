#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17v_outer
readonly base_derivation_sha256=4e90f157b81110384d50d00fc0d0377a9733787260c056555d0b3c359379a51c
readonly historical_inspector_sha256=38df35f89dc5732320e84ef9ec90ff8b0d5d1cee72d342b025c743c74a0d4210
readonly historical_runner_sha256=facbaeda449522296cb90febf8fc0cbe4472129a35f960f9415e5aa5fb248ea2
readonly derivation_sha256=46adf7d35a306ddb13e68087db9f5191140b78418f0f65a2182f3ebc848c7afd
readonly regression_sha256=1616959e727568eb9e79ade32f75f3a56fad25f76cce1c957678e2a082be9196
readonly corrected_inspector_sha256=216ee51b429048b0304e76d0b75402f4306470d012f170debb1352951efd5910
readonly corrected_runner_sha256=cb85c0c63faba81db701f6d02be092df3150dd38a3b926bc785c0b067f54ebad

outer_script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly outer_script_directory
outer_caddy_root=$(cd -- "$outer_script_directory/.." && pwd)
readonly outer_caddy_root
readonly base_derivation="$outer_script_directory/derive-node-b-action17u-postrepair-acceptance-action17u-c.sh"
readonly historical_inspector="$outer_script_directory/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly historical_runner="$outer_script_directory/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly derivation="$outer_script_directory/derive-node-b-postmigration-acceptance-action17v.sh"
readonly regression="$outer_caddy_root/tests/action17v-node-b-postmigration-acceptance-regression.sh"
readonly collision_checker="$outer_caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly inner_collision_checker="$outer_caddy_root/tests/check-shell-readonly-local-collisions.sh"

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
    verify_file "$base_derivation" "$base_derivation_sha256" || return 1
    verify_file "$historical_inspector" "$historical_inspector_sha256" || return 1
    verify_file "$historical_runner" "$historical_runner_sha256" || return 1
    verify_file "$derivation" "$derivation_sha256" || return 1
    verify_file "$regression" "$regression_sha256" || return 1
    bash -n "$derivation" "$regression" || return 1
    "$collision_checker" "$derivation" "$regression" >/dev/null || return 1
}

render_stage() {
    local stage_root=$1
    local stage_scripts="$stage_root/Caddy/scripts"
    local stage_tests="$stage_root/Caddy/tests"
    local stage_inspector="$stage_scripts/inspect-node-b-postmigration-acceptance-action17v.sh"
    local stage_runner="$stage_scripts/run-node-b-postmigration-acceptance-action17v.sh"

    install -d -m 0700 "$stage_scripts" "$stage_tests"
    "$derivation" --render-inspector >"$stage_inspector"
    "$derivation" --render-runner >"$stage_runner"
    install -m 0755 -- "$inner_collision_checker" \
        "$stage_tests/${inner_collision_checker##*/}"
    chmod 0755 "$stage_inspector" "$stage_runner"
    verify_file "$stage_inspector" "$corrected_inspector_sha256" || return 1
    verify_file "$stage_runner" "$corrected_runner_sha256" || return 1
    printf '%s\n' "$stage_runner"
}

run_local_gates() {
    local gate_root=$1
    local gate_runner

    "$derivation" --self-test >/dev/null || return 1
    "$regression" --production-test >/dev/null || return 1
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
        outer_work_directory=$(mktemp -d /tmp/caddy-action17v-outer-test.XXXXXX)
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
outer_work_directory=$(mktemp -d /tmp/caddy-action17v-outer.XXXXXX)
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
