#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly correction_sha256=693a75d7cfb1c308a1367111c5891e3eae3fac7dc1e4bfd8ea4a43604f2229b6
readonly regression_sha256=4a54669e56e3386dd9a3335ec1ffe51aee4485111460ce6be01219b967ac1d62
readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly historical_driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0
readonly historical_runner_sha256=d2b8672f7b3c336e4dfe9e1bf7f12b61290e8a993a8c92eef252b3a5b03f510b
readonly rendered_driver_sha256=3259b979e64ccee667e2a81ac9683c21d140331c0d1f44d6c6e41bf88a7b31dd
readonly rendered_runner_sha256=c88ab6f91f3adaeab6a7cd5ba7c2013d8d62bc7d393601a370c140f50e1eb795

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly correction="$script_dir/correct-restricted-transport-action17c-retry.sh"
readonly regression="$caddy_root/tests/action17c-streamed-stdin-continuity-regression.sh"
readonly inspector="$script_dir/inspect-node-b-restricted-transport-state-action17c.sh"
readonly historical_driver="$script_dir/validate-node-a-to-node-b-restricted-transport-action17c.sh"
readonly historical_runner="$script_dir/run-node-a-to-node-b-restricted-transport-action17c.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
    bash -n "$path"
}

verify_sources() {
    verify_source "$correction" "$correction_sha256"
    verify_source "$regression" "$regression_sha256"
    verify_source "$inspector" "$inspector_sha256"
    verify_source "$historical_driver" "$historical_driver_sha256"
    verify_source "$historical_runner" "$historical_runner_sha256"
}

prepare_stage() {
    local destination=$1

    install -m 0755 "$inspector" \
        "$destination/inspect-node-b-restricted-transport-state-action17c.sh"
    "$correction" --render-driver "$historical_driver" \
        >"$destination/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh"
    "$correction" --render-runner "$historical_runner" \
        >"$destination/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh"
    chmod 0755 \
        "$destination/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh" \
        "$destination/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh"

    [[ "$(file_hash \
        "$destination/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh")" == "$rendered_driver_sha256" ]]
    [[ "$(file_hash \
        "$destination/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh")" == "$rendered_runner_sha256" ]]
    bash -n \
        "$destination/validate-node-a-to-node-b-restricted-transport-action17c-retry.sh" \
        "$destination/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

validate_nested_success() {
    local transcript=$1
    local marker

    for marker in \
        ipv4_restricted_authentication=true \
        ipv4_forced_receiver_rejection=true \
        ipv6_restricted_authentication=true \
        ipv6_forced_receiver_rejection=true \
        ipv4_rsync_dry_run=true \
        node_a_protected_state_unchanged=true \
        release_payload_transferred=false \
        node_b_before_ssh_status=0 \
        node_a_probe_ssh_status=0 \
        node_b_after_ssh_status=0 \
        node_b_before_state_valid=true \
        node_b_after_state_valid=true \
        node_b_protected_state_unchanged=true \
        action_17c_restricted_transport_validation_complete=true \
        action_17c_restricted_transport_accepted=true \
        action_17c_local_cleanup_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    [[ "$(grep -Ec '^node_b_before_state_digest=[0-9a-f]{64}$' \
        "$transcript")" -eq 1 ]]
    [[ "$(grep -Ec '^node_b_after_state_digest=[0-9a-f]{64}$' \
        "$transcript")" -eq 1 ]]
    before_digest=$(grep -E '^node_b_before_state_digest=[0-9a-f]{64}$' \
        "$transcript")
    after_digest=$(grep -E '^node_b_after_state_digest=[0-9a-f]{64}$' \
        "$transcript")
    [[ "${before_digest#*=}" == "${after_digest#*=}" ]]
}

validate_nested_semantic_failure() {
    local transcript=$1

    require_one release_payload_transferred=false "$transcript" &&
        require_one node_a_protected_state_unchanged=true "$transcript" &&
        require_one node_b_protected_state_unchanged=true "$transcript" &&
        require_one \
            action_17c_restricted_transport_validation_complete=false \
            "$transcript" &&
        require_one action_17c_restricted_transport_accepted=false "$transcript" &&
        require_one action_17c_local_cleanup_complete=true "$transcript"
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_success_fixture() {
    local destination=$1
    local digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        ipv4_restricted_authentication=true \
        ipv4_forced_receiver_rejection=true \
        ipv6_restricted_authentication=true \
        ipv6_forced_receiver_rejection=true \
        ipv4_rsync_dry_run=true \
        node_a_protected_state_unchanged=true \
        release_payload_transferred=false \
        action_17c_restricted_transport_validation_complete=true \
        node_b_before_ssh_status=0 \
        node_a_probe_ssh_status=0 \
        node_b_after_ssh_status=0 \
        node_b_before_state_valid=true \
        "node_b_before_state_digest=$digest" \
        node_b_after_state_valid=true \
        "node_b_after_state_digest=$digest" \
        node_b_protected_state_unchanged=true \
        action_17c_restricted_transport_accepted=true \
        action_17c_local_cleanup_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$correction_sha256" \
        "$regression_sha256" \
        "$inspector_sha256" \
        "$historical_driver_sha256" \
        "$historical_runner_sha256" \
        "$rendered_driver_sha256" \
        "$rendered_runner_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_sources
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    self_test_dir=$(mktemp -d /tmp/caddy-action17c-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$self_test_dir"' EXIT
    prepare_stage "$self_test_dir"
    "$self_test_dir/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh" \
        --self-test >/dev/null
    "$self_test_dir/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh" \
        --contract-test >/dev/null
    printf 'action_17c_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17c-retry-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    write_success_fixture "$contract_dir/success"
    validate_nested_success "$contract_dir/success"
    validate_secret_free "$contract_dir/success"

    cp -- "$contract_dir/success" "$contract_dir/duplicate"
    printf 'ipv6_restricted_authentication=true\n' >>"$contract_dir/duplicate"
    if validate_nested_success "$contract_dir/duplicate"; then
        printf 'Duplicate nested marker was accepted.\n' >&2
        exit 1
    fi

    printf '%s\n' \
        release_payload_transferred=false \
        node_a_protected_state_unchanged=true \
        node_b_protected_state_unchanged=true \
        action_17c_restricted_transport_validation_complete=false \
        action_17c_restricted_transport_accepted=false \
        action_17c_local_cleanup_complete=true \
        >"$contract_dir/semantic-failure"
    validate_nested_semantic_failure "$contract_dir/semantic-failure"

    cp -- "$contract_dir/success" "$contract_dir/secret"
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$contract_dir/secret"
    if validate_secret_free "$contract_dir/secret"; then
        printf 'Secret-bearing nested output was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17c-retry.XXXXXX)
readonly work_dir

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

prepare_stage "$work_dir"
inner_output=$work_dir/inner.out
inner_error=$work_dir/inner.err
inner_status=0
"$work_dir/run-node-a-to-node-b-restricted-transport-action17c-retry-inner.sh" \
    >"$inner_output" 2>"$inner_error" || inner_status=$?

cat "$inner_output"
cat "$inner_error" >&2
printf 'action_17c_retry_inner_status=%s\n' "$inner_status"
if ! validate_secret_free "$inner_output" "$inner_error"; then
    printf 'Unsafe corrected Action 17c output detected.\n' >&2
    exit 97
fi

if [[ "$inner_status" -eq 0 ]]; then
    if [[ -s "$inner_error" ]] ||
        ! validate_nested_success "$inner_output"; then
        printf 'Corrected Action 17c success evidence is malformed.\n' >&2
        exit 97
    fi
    printf 'action_17c_retry_accepted=true\n'
    cleanup
    trap - EXIT
    [[ ! -e "$work_dir" && ! -L "$work_dir" ]]
    printf 'action_17c_retry_local_cleanup_complete=true\n'
    exit 0
fi

if [[ "$inner_status" -eq 1 ]] &&
    [[ ! -s "$inner_error" ]] &&
    validate_nested_semantic_failure "$inner_output"; then
    printf 'action_17c_retry_accepted=false\n'
    cleanup
    trap - EXIT
    [[ ! -e "$work_dir" && ! -L "$work_dir" ]]
    printf 'action_17c_retry_local_cleanup_complete=true\n'
    exit 1
fi

printf 'Corrected Action 17c failure evidence is malformed or incomplete.\n' >&2
exit 97
