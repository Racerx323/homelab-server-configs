#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly correction_sha256=f9e998a536ef830c4dc0d4b64d1bc30b86dfdc0fd4ee26853ee6e348e6d455d8
readonly regression_sha256=2a3c6546291931425e16eb2155fc1474afb170e6d275377a0dae84d534260773
readonly historical_collector_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d
readonly historical_runner_sha256=d0fa596f3912288b24645fa6fa9bbbfe15fa0fffd38d7d6308f11041a7bdb4da
readonly rendered_collector_sha256=c99a7be13a20cbc5b2af7bc74790bd06b7f3afe62f9b73b41de42171a2ab4efd
readonly rendered_runner_sha256=5bf1e9a92cc4b1ad63e2a7dfba0467a40edecb9fb7ef0fcb80e66da1f9288263

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly correction="$script_dir/correct-peer-resolution-readonly-shadow-action17c-c-b-retry.sh"
readonly regression="$caddy_root/tests/action17c-c-b-second-resolver-snapshot-regression.sh"
readonly historical_collector="$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"
readonly historical_runner="$script_dir/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source_content() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
    bash -n "$path"
}

verify_source() {
    local path=$1
    local expected_hash=$2

    verify_source_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
}

verify_source_contents() {
    verify_source_content "$correction" "$correction_sha256"
    verify_source_content "$regression" "$regression_sha256"
    verify_source_content \
        "$historical_collector" "$historical_collector_sha256"
    verify_source_content "$historical_runner" "$historical_runner_sha256"
}

verify_sources() {
    verify_source "$correction" "$correction_sha256"
    verify_source "$regression" "$regression_sha256"
    verify_source "$historical_collector" "$historical_collector_sha256"
    verify_source "$historical_runner" "$historical_runner_sha256"
}

prepare_stage() {
    local destination=$1
    local staged_scripts="$destination/Caddy/scripts"
    local collector="$staged_scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b-retry.sh"
    local runner="$staged_scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry-inner.sh"

    install -d -m 0700 "$staged_scripts"
    "$correction" --render-collector "$historical_collector" >"$collector"
    "$correction" --render-runner "$historical_runner" >"$runner"
    chmod 0755 "$collector" "$runner"
    [[ "$(file_hash "$collector")" == "$rendered_collector_sha256" ]]
    [[ "$(file_hash "$runner")" == "$rendered_runner_sha256" ]]
    bash -n "$collector" "$runner"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

validate_success() {
    local transcript=$1
    local conclusion

    for marker in \
        node_a_resolver_state_unchanged=true \
        peer_ssh_invoked=false \
        rsync_invoked=false \
        release_payload_transferred=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_b_node_a_cleanup_complete=true \
        action_17c_c_b_node_a_diagnostic_complete=true \
        node_a_administrative_ssh_status=0 \
        action_17c_c_b_diagnostic_accepted=true \
        action_17c_c_b_local_cleanup_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    conclusion=$(value_for action_17c_c_b_diagnostic_conclusion "$transcript") ||
        return 1
    [[ "$conclusion" =~ ^(all_contexts_resolve_expected_dual_stack|caddy_sync_context_differs|all_contexts_match_non_success|resolution_contexts_differ)$ ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_success_fixture() {
    local destination=$1

    printf '%s\n' \
        node_a_resolver_state_unchanged=true \
        peer_ssh_invoked=false \
        rsync_invoked=false \
        release_payload_transferred=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_b_node_a_cleanup_complete=true \
        action_17c_c_b_node_a_diagnostic_complete=true \
        node_a_administrative_ssh_status=0 \
        action_17c_c_b_diagnostic_conclusion=all_contexts_match_non_success \
        action_17c_c_b_diagnostic_accepted=true \
        action_17c_c_b_local_cleanup_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$correction_sha256" \
        "$regression_sha256" \
        "$historical_collector_sha256" \
        "$historical_runner_sha256" \
        "$rendered_collector_sha256" \
        "$rendered_runner_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_source_contents
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    prepare_stage "$test_dir"
    inner="$test_dir/Caddy/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry-inner.sh"
    "$inner" --self-test >/dev/null
    "$inner" --contract-test >/dev/null
    printf 'action_17c_c_b_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-retry-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_success_fixture "$test_dir/success"
    validate_success "$test_dir/success"
    validate_secret_free "$test_dir/success"
    cp -- "$test_dir/success" "$test_dir/duplicate"
    printf 'action_17c_c_b_diagnostic_accepted=true\n' \
        >>"$test_dir/duplicate"
    if validate_success "$test_dir/duplicate"; then
        printf 'Duplicate retry marker was accepted.\n' >&2
        exit 1
    fi
    cp -- "$test_dir/success" "$test_dir/secret"
    printf 'DOPPLER_TOKEN=forbidden\n' >>"$test_dir/secret"
    if validate_secret_free "$test_dir/secret"; then
        printf 'Secret-bearing retry transcript was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_b_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17c-c-b-retry.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
prepare_stage "$work_dir"
inner="$work_dir/Caddy/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry-inner.sh"
inner_output="$work_dir/inner.out"
inner_error="$work_dir/inner.err"
inner_status=0
"$inner" >"$inner_output" 2>"$inner_error" || inner_status=$?
cat "$inner_output"
cat "$inner_error" >&2
printf 'action_17c_c_b_retry_inner_status=%s\n' "$inner_status"

if [[ "$inner_status" -ne 0 ]] ||
    [[ -s "$inner_error" ]] ||
    ! validate_success "$inner_output" ||
    ! validate_secret_free "$inner_output" "$inner_error"; then
    printf 'Corrected Action 17c-c-b retry evidence is incomplete.\n' >&2
    exit 97
fi

printf 'action_17c_c_b_retry_accepted=true\n'
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_b_retry_local_cleanup_complete=true\n'
