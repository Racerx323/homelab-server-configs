#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly correction_sha256=214efa540b42de756fb467903af43a8d73161b5f3654987c4697057a0c6b4e48
readonly regression_sha256=baa55af3e211bf44fdbed29b47cc80a47b7d837e04f6d83d4099392861f38035
readonly historical_collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly historical_runner_sha256=db6c273734ed52b43268af6823feeec08ca1aa191d89b970d641fe53453bf1a6
readonly historical_regression_sha256=f5ef1077dc627c8e35248ce439f4c01e419d02b8e431412d66e762813755d825
readonly rendered_collector_sha256=1a96099b69a1f4a8672e09ec49158f779e612d08a46e8c9333c38aff9f7d6624
readonly rendered_runner_sha256=e1921118134ff70f4ef1d93e0a8df9490fa5b14033f689d3b416c4ebc08071b3

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly correction="$script_dir/correct-dns-path-work-dir-action17c-c-c-retry.sh"
readonly regression="$caddy_root/tests/action17c-c-c-first-query-production-regression.sh"
readonly historical_collector="$script_dir/diagnose-dns-path-authority-action17c-c-c.sh"
readonly historical_runner="$script_dir/run-dns-path-authority-diagnostic-action17c-c-c.sh"
readonly historical_regression="$caddy_root/tests/action17c-c-c-dns-path-authority-regression.sh"

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

verify_source_live() {
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
    verify_source_content "$historical_regression" "$historical_regression_sha256"
}

verify_sources_live() {
    verify_source_live "$correction" "$correction_sha256"
    verify_source_live "$regression" "$regression_sha256"
    verify_source_live \
        "$historical_collector" "$historical_collector_sha256"
    verify_source_live "$historical_runner" "$historical_runner_sha256"
    verify_source_live "$historical_regression" "$historical_regression_sha256"
}

prepare_stage() {
    local destination=$1
    local staged_caddy="$destination/homelab-server-configs/Caddy"
    local staged_scripts="$staged_caddy/scripts"
    local staged_tests="$staged_caddy/tests"
    local collector="$staged_scripts/diagnose-dns-path-authority-action17c-c-c-retry.sh"
    local runner="$staged_scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry-inner.sh"

    install -d -m 0700 \
        "$destination/homelab-server-configs" \
        "$staged_caddy" \
        "$staged_scripts" \
        "$staged_tests"
    ln -s -- "$workspace_root/homelab-dns" "$destination/homelab-dns"
    ln -s -- "$caddy_root/manifests" "$staged_caddy/manifests"
    "$correction" --render-collector "$historical_collector" >"$collector"
    "$correction" --render-runner "$historical_runner" >"$runner"
    install -m 0755 "$historical_regression" \
        "$staged_tests/action17c-c-c-dns-path-authority-regression.sh"
    chmod 0755 "$collector" "$runner"
    [[ "$(file_hash "$collector")" == "$rendered_collector_sha256" ]]
    [[ "$(file_hash "$runner")" == "$rendered_runner_sha256" ]]
    bash -n "$collector" "$runner"
}

require_one() {
    local record=$1
    local transcript=$2

    [[ "$(grep -Fxc "$record" "$transcript")" -eq 1 ]]
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
    local value

    for marker in \
        node_a_administrative_ssh_status=0 \
        node_b_administrative_ssh_status=0 \
        action_17c_c_c_dns_diagnostic_accepted=true \
        action_17c_c_c_local_cleanup_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    value=$(value_for action_17c_c_c_two_file_conclusion "$transcript") ||
        return 1
    [[ "$value" =~ ^(legacy_single_file_unbound_configuration|two_file_unbound_prerequisite_converged|two_file_unbound_prerequisite_not_converged)$ ]]
    value=$(value_for action_17c_c_c_path_conclusion "$transcript") ||
        return 1
    [[ "$value" =~ ^(legacy_single_file_unbound_configuration|two_file_unbound_prerequisite_not_converged|unbound_authority_positive_control_failure|unbound_authority_expected_absence_mismatch|local_pihole_forwarding_failure|dns_vip_path_failure|configured_ipv4_resolver_diverges|ipv4_dns_path_positive_controls_pass)$ ]]
    value=$(value_for action_17c_c_c_sync_dns_conclusion "$transcript") ||
        return 1
    [[ "$value" =~ ^(peer_aaaa_not_deployed|peer_aaaa_state_inconsistent|peer_aaaa_deployed)$ ]]
    value=$(value_for action_17c_c_c_caddy_dns_conclusion "$transcript") ||
        return 1
    [[ "$value" =~ ^(caddy_records_not_deployed|caddy_record_state_inconsistent|caddy_records_present)$ ]]
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|AUDIT=' \
        "$@"
}

write_success_fixture() {
    local destination=$1

    printf '%s\n' \
        node_a_administrative_ssh_status=0 \
        node_b_administrative_ssh_status=0 \
        action_17c_c_c_two_file_conclusion=legacy_single_file_unbound_configuration \
        action_17c_c_c_path_conclusion=legacy_single_file_unbound_configuration \
        action_17c_c_c_sync_dns_conclusion=peer_aaaa_state_inconsistent \
        action_17c_c_c_caddy_dns_conclusion=caddy_record_state_inconsistent \
        action_17c_c_c_dns_diagnostic_accepted=true \
        action_17c_c_c_local_cleanup_complete=true >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$correction_sha256" \
        "$regression_sha256" \
        "$historical_collector_sha256" \
        "$historical_runner_sha256" \
        "$historical_regression_sha256" \
        "$rendered_collector_sha256" \
        "$rendered_runner_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_source_contents
    "$correction" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-retry-self-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    prepare_stage "$test_dir"
    inner="$test_dir/homelab-server-configs/Caddy/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry-inner.sh"
    "$inner" --self-test >/dev/null
    "$inner" --contract-test >/dev/null
    printf 'action_17c_c_c_retry_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_sources_live
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-retry-source-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    prepare_stage "$test_dir"
    inner="$test_dir/homelab-server-configs/Caddy/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry-inner.sh"
    "$inner" --source-test >/dev/null
    printf 'action_17c_c_c_retry_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-retry-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_success_fixture "$test_dir/success"
    validate_success "$test_dir/success"
    validate_secret_free "$test_dir/success"
    cp -- "$test_dir/success" "$test_dir/duplicate"
    printf 'action_17c_c_c_dns_diagnostic_accepted=true\n' \
        >>"$test_dir/duplicate"
    if validate_success "$test_dir/duplicate"; then
        printf 'Duplicate corrected retry marker was accepted.\n' >&2
        exit 1
    fi
    cp -- "$test_dir/success" "$test_dir/secret"
    printf 'DOPPLER_TOKEN=forbidden\n' >>"$test_dir/secret"
    if validate_secret_free "$test_dir/secret"; then
        printf 'Secret-bearing corrected retry transcript was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_c_retry_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_sources_live
work_dir=$(mktemp -d /tmp/caddy-action17c-c-c-retry.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
prepare_stage "$work_dir"
inner="$work_dir/homelab-server-configs/Caddy/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry-inner.sh"
inner_output="$work_dir/inner.out"
inner_error="$work_dir/inner.err"
inner_status=0
"$inner" >"$inner_output" 2>"$inner_error" || inner_status=$?
cat "$inner_output"
cat "$inner_error" >&2
printf 'action_17c_c_c_retry_inner_status=%s\n' "$inner_status"

if [[ "$inner_status" -ne 0 ]] ||
    [[ -s "$inner_error" ]] ||
    ! validate_success "$inner_output" ||
    ! validate_secret_free "$inner_output" "$inner_error"; then
    printf 'Corrected Action 17c-c-c retry evidence is incomplete.\n' >&2
    exit 97
fi

printf 'action_17c_c_c_retry_accepted=true\n'
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_c_retry_local_cleanup_complete=true\n'
