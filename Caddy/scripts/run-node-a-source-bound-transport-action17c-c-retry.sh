#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly correction_sha256=0201ae3e39e496ae5a297c51e40d0375042974dcf7d27c18a38a3ffcced07d9c
readonly regression_sha256=288b7619c3ed869062ba0264aa7f34e6ecedb7067d662179dfade1e8f7acca95
readonly historical_runner_sha256=b63cd6e48662ad2a7b1604817da21135e735be0c8319090919760398d98d7cf7
readonly rendered_runner_sha256=1cef934ad56a4e6b5d7e0d2024b12607d4462951fba5e234b1f78504a239b5f2
readonly validator_sha256=a7da9a9190595e17f8e563c25845648cfe062faed554fde7e8cdcf56059c27dc
readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111
readonly renderer_sha256=36c048b75f865ab31a8f8d18a24d09b3bad0610355e752ea7bbe3ef9593eb5f3
readonly template_sha256=f7e1e481b4cc0ab1e5f0b503a1f90fa4d42a76b3e68c1cdd5c48f2e9736be976

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly correction="$script_dir/correct-source-bound-working-directory-action17c-c-retry.sh"
readonly regression="$caddy_root/tests/action17c-c-working-directory-regression.sh"
readonly historical_runner="$script_dir/run-node-a-source-bound-transport-action17c-c.sh"
readonly validator="$script_dir/validate-sync-ssh-source-bound.sh"
readonly inspector="$script_dir/inspect-node-b-restricted-transport-state-action17c.sh"
readonly renderer="$script_dir/render-source-bound-sync-config-action17c-c.sh"
readonly template="$caddy_root/templates/lsyncd-caddy-source-bound.lua.in"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_source() {
    local path=$1
    local expected_hash=$2
    local expected_mode=$3

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(stat -c '%U:%G:%a' "$path")" == "aaron:aaron:$expected_mode" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_source "$correction" "$correction_sha256" 755
    verify_source "$regression" "$regression_sha256" 755
    verify_source "$historical_runner" "$historical_runner_sha256" 755
    verify_source "$validator" "$validator_sha256" 755
    verify_source "$inspector" "$inspector_sha256" 755
    verify_source "$renderer" "$renderer_sha256" 755
    verify_source "$template" "$template_sha256" 644
}

prepare_stage() {
    local destination=$1
    local staged_scripts="$destination/Caddy/scripts"
    local staged_templates="$destination/Caddy/templates"

    install -d -m 0700 "$staged_scripts" "$staged_templates"
    install -m 0755 \
        "$validator" \
        "$inspector" \
        "$renderer" \
        "$staged_scripts/"
    install -m 0644 "$template" "$staged_templates/"
    "$correction" --render-runner "$historical_runner" \
        >"$staged_scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh"
    chmod 0755 \
        "$staged_scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh"
    [[ "$(file_hash \
        "$staged_scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh")" == "$rendered_runner_sha256" ]]
    bash -n \
        "$staged_scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

validate_success() {
    local transcript=$1
    local marker
    local before_digest
    local after_digest

    for marker in \
        source_bound_ssh_configuration_valid=true \
        source_bound_direct_ssh_reached_forced_receiver=true \
        source_bound_rsync_dry_run=true \
        node_relevant_state_unchanged=true \
        release_payload_transferred=false \
        node_b_before_ssh_status=0 \
        node_a_source_bound_ssh_status=0 \
        node_b_after_ssh_status=0 \
        node_b_protected_state_unchanged=true \
        action_17c_c_source_bound_transport_accepted=true \
        action_17c_c_local_cleanup_complete=true; do
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

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_success_fixture() {
    local destination=$1
    local digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        source_bound_ssh_configuration_valid=true \
        source_bound_direct_ssh_reached_forced_receiver=true \
        source_bound_rsync_dry_run=true \
        node_relevant_state_unchanged=true \
        release_payload_transferred=false \
        node_b_before_ssh_status=0 \
        node_a_source_bound_ssh_status=0 \
        node_b_after_ssh_status=0 \
        "node_b_before_state_digest=$digest" \
        "node_b_after_state_digest=$digest" \
        node_b_protected_state_unchanged=true \
        action_17c_c_source_bound_transport_accepted=true \
        action_17c_c_local_cleanup_complete=true \
        >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$correction_sha256" \
        "$regression_sha256" \
        "$historical_runner_sha256" \
        "$rendered_runner_sha256" \
        "$validator_sha256" \
        "$inspector_sha256" \
        "$renderer_sha256" \
        "$template_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_sources
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    prepare_stage "$test_dir"
    inner="$test_dir/Caddy/scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh"
    "$inner" --self-test >/dev/null
    "$inner" --contract-test >/dev/null
    printf 'action_17c_c_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-retry-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_success_fixture "$test_dir/success"
    validate_success "$test_dir/success"
    validate_secret_free "$test_dir/success"
    cp -- "$test_dir/success" "$test_dir/duplicate"
    printf 'source_bound_rsync_dry_run=true\n' >>"$test_dir/duplicate"
    if validate_success "$test_dir/duplicate"; then
        printf 'Duplicate retry marker was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_sources
work_dir=$(mktemp -d /tmp/caddy-action17c-c-retry.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
prepare_stage "$work_dir"
inner="$work_dir/Caddy/scripts/run-node-a-source-bound-transport-action17c-c-retry-inner.sh"
inner_output="$work_dir/inner.out"
inner_error="$work_dir/inner.err"
inner_status=0
"$inner" >"$inner_output" 2>"$inner_error" || inner_status=$?
cat "$inner_output"
cat "$inner_error" >&2
printf 'action_17c_c_retry_inner_status=%s\n' "$inner_status"

if [[ "$inner_status" -ne 0 ]] ||
    [[ -s "$inner_error" ]] ||
    ! validate_success "$inner_output" ||
    ! validate_secret_free "$inner_output" "$inner_error"; then
    printf 'Corrected Action 17c-c retry evidence is incomplete.\n' >&2
    exit 97
fi

printf 'action_17c_c_retry_accepted=true\n'
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_retry_local_cleanup_complete=true\n'
