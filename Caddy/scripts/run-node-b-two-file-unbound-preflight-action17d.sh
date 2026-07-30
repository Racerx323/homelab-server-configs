#!/usr/bin/env bash
# shellcheck disable=SC2016 # Build literal code for the remote Bash process.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=0a9be5bf5f16879ea88092ca056ae52edcfb299b6ca3d274d1d14b29d2480d3f
readonly regression_sha256=7ad9572728d5beeaf38ffb88483b67f42c5a1cd0b1e3b84d2c9222eea05b287e
readonly accepted_dns_runner_sha256=148803926e39164b76f35e637fea200cb6c55a6f9acf18fe740f2d6871cb64d6
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly node_b_target=pi@10.1.0.54
readonly node_b_host_alias=pihole00.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly inspector="$script_dir/inspect-node-b-two-file-unbound-preflight-action17d.sh"
readonly regression="$caddy_root/tests/action17d-node-b-two-file-unbound-preflight-regression.sh"
readonly accepted_dns_runner="$script_dir/run-dns-path-authority-diagnostic-action17c-c-c-retry.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_repo="$workspace_root/homelab-dns"

readonly -a transcript_prefixes=(
    action_17d_node_b_unbound_preflight_remote_reached
    node_role
    node_hostname
    node_identity_matches
    before_state_sha256
    live_root_state
    live_root_sha256
    live_primary_state
    live_primary_sha256
    live_primary_metadata
    live_local_zone_state
    live_local_zone_sha256
    live_baseline_matches
    live_conf_entry_count
    live_conf_entries_b64
    live_conf_tree_sha256
    live_nonregular_conf_count
    root_active_directive_count
    root_active_directives_b64
    root_include_toplevel_count
    root_include_topology_supported
    unbound_package_version_b64
    unbound_binary_version_b64
    unbound_active
    unbound_unit_file_state
    pihole_ftl_active
    service_state_ready
    live_checkconf_status
    live_checkconf_stdout_sha256
    live_checkconf_stderr_sha256
    live_parser_valid
    candidate_primary_sha256
    candidate_local_zone_sha256
    candidate_primary_server_count
    candidate_local_zone_server_count
    candidate_primary_local_policy_count
    candidate_local_zone_forbidden_count
    ownership_boundary_valid
    live_normalized_directive_count
    candidate_normalized_directive_count
    live_normalized_sha256
    candidate_normalized_sha256
    live_only_directive_count
    candidate_only_directive_count
    canonical_directives_equal
    candidate_validation_attempted
    candidate_checkconf_status
    candidate_checkconf_stdout_sha256
    candidate_checkconf_stderr_sha256
    candidate_parser_valid
    after_state_sha256
    node_state_unchanged
    action_17d_node_b_unbound_preflight_conclusion
    dns_queries_performed
    dns_configuration_mutations
    service_mutations
    persistent_mutations
    action_17d_node_b_unbound_preflight_inspection_complete
    action_17d_node_b_remote_stage_cleanup_complete
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file_content() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_source_contents() {
    verify_file_content "$inspector" "$inspector_sha256"
    verify_file_content "$regression" "$regression_sha256"
    verify_file_content \
        "$accepted_dns_runner" "$accepted_dns_runner_sha256"
    bash -n "$inspector"
}

verify_live_sources() {
    verify_source_contents
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$regression")" == aaron:aaron:755 ]]
    [[ "$(stat -c '%U:%G:%a' "$accepted_dns_runner")" == aaron:aaron:755 ]]
}

verify_operator_source() {
    local path=$1
    local expected_hash=$2

    verify_file_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:644 ]]
}

verify_operator_sources() {
    verify_operator_source "$candidate_primary" "$candidate_primary_sha256"
    verify_operator_source \
        "$candidate_local_zone" "$candidate_local_zone_sha256"
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    git -C "$dns_repo" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1 ||
        git -C "$dns_repo" ls-files --error-unmatch \
            Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        printf 'Private Unbound operator sources unexpectedly became tracked.\n' \
            >&2
        return 1
    fi
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

require_value() {
    local prefix=$1
    local expected=$2
    local transcript=$3

    [[ "$(value_for "$prefix" "$transcript")" == "$expected" ]]
}

require_boolean() {
    local prefix=$1
    local transcript=$2
    local value

    value=$(value_for "$prefix" "$transcript") || return 1
    [[ "$value" == true || "$value" == false ]]
}

require_integer() {
    local prefix=$1
    local transcript=$2

    [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9]+$ ]]
}

derive_conclusion() {
    local transcript=$1

    if ! require_value node_identity_matches true "$transcript" ||
        ! require_value live_baseline_matches true "$transcript"; then
        printf 'live_source_drift\n'
    elif ! require_value service_state_ready true "$transcript" ||
        ! require_value live_parser_valid true "$transcript"; then
        printf 'service_or_live_parser_not_ready\n'
    elif ! require_value \
        root_include_topology_supported true "$transcript"; then
        printf 'unsupported_include_topology\n'
    elif ! require_value ownership_boundary_valid true "$transcript" ||
        ! require_value canonical_directives_equal true "$transcript"; then
        printf 'candidate_semantic_drift\n'
    elif ! require_value candidate_parser_valid true "$transcript"; then
        printf 'candidate_parser_rejected\n'
    else
        printf 'ready_for_staged_adoption_design\n'
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
        "$@"
}

validate_transcript() {
    local transcript=$1
    local prefix value expected_conclusion

    [[ "$(wc -l <"$transcript")" -eq "${#transcript_prefixes[@]}" ]]
    if grep -Evq '^[a-z0-9_]+=[A-Za-z0-9_:+./=-]*$' "$transcript"; then
        return 1
    fi
    for prefix in "${transcript_prefixes[@]}"; do
        [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    done
    require_value \
        action_17d_node_b_unbound_preflight_remote_reached true "$transcript"
    require_value node_role node-b "$transcript"
    require_value candidate_primary_sha256 \
        "$candidate_primary_sha256" "$transcript"
    require_value candidate_local_zone_sha256 \
        "$candidate_local_zone_sha256" "$transcript"
    require_value node_state_unchanged true "$transcript"
    require_value dns_queries_performed false "$transcript"
    require_value dns_configuration_mutations false "$transcript"
    require_value service_mutations false "$transcript"
    require_value persistent_mutations false "$transcript"
    require_value \
        action_17d_node_b_unbound_preflight_inspection_complete \
        true "$transcript"
    require_value \
        action_17d_node_b_remote_stage_cleanup_complete true "$transcript"
    [[ "$(value_for before_state_sha256 "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    require_value after_state_sha256 \
        "$(value_for before_state_sha256 "$transcript")" "$transcript"

    for prefix in \
        node_identity_matches \
        live_baseline_matches \
        root_include_topology_supported \
        service_state_ready \
        live_parser_valid \
        ownership_boundary_valid \
        canonical_directives_equal \
        candidate_validation_attempted \
        candidate_parser_valid \
        node_state_unchanged; do
        require_boolean "$prefix" "$transcript" || return 1
    done
    for prefix in \
        live_conf_entry_count \
        live_nonregular_conf_count \
        root_active_directive_count \
        root_include_toplevel_count \
        live_checkconf_status \
        candidate_primary_server_count \
        candidate_local_zone_server_count \
        candidate_primary_local_policy_count \
        candidate_local_zone_forbidden_count \
        live_normalized_directive_count \
        candidate_normalized_directive_count \
        live_only_directive_count \
        candidate_only_directive_count; do
        require_integer "$prefix" "$transcript" || return 1
    done
    value=$(value_for candidate_checkconf_status "$transcript") || return 1
    [[ "$value" == not_run || "$value" =~ ^[0-9]+$ ]]
    for prefix in \
        live_root_sha256 \
        live_primary_sha256 \
        live_local_zone_sha256; do
        value=$(value_for "$prefix" "$transcript") || return 1
        [[ "$value" == unavailable || "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    for prefix in \
        live_conf_tree_sha256 \
        live_checkconf_stdout_sha256 \
        live_checkconf_stderr_sha256 \
        live_normalized_sha256 \
        candidate_normalized_sha256 \
        candidate_checkconf_stdout_sha256 \
        candidate_checkconf_stderr_sha256; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    done

    if require_value node_identity_matches true "$transcript"; then
        require_value node_hostname j1-svpihole00 "$transcript"
    fi
    if require_value live_baseline_matches true "$transcript"; then
        require_value live_primary_state regular "$transcript"
        require_value live_primary_sha256 \
            017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
            "$transcript"
        require_value live_primary_metadata root:root:644:34342 "$transcript"
        require_value live_local_zone_state absent "$transcript"
        require_value live_local_zone_sha256 unavailable "$transcript"
    fi
    if require_value service_state_ready true "$transcript"; then
        require_value unbound_active active "$transcript"
        require_value pihole_ftl_active active "$transcript"
    fi
    if require_value live_parser_valid true "$transcript"; then
        require_value live_checkconf_status 0 "$transcript"
        require_value live_checkconf_stderr_sha256 \
            "$empty_sha256" "$transcript"
    fi
    if require_value ownership_boundary_valid true "$transcript"; then
        require_value candidate_primary_server_count 1 "$transcript"
        require_value candidate_local_zone_server_count 1 "$transcript"
        require_value candidate_primary_local_policy_count 0 "$transcript"
        require_value candidate_local_zone_forbidden_count 0 "$transcript"
    fi
    if require_value canonical_directives_equal true "$transcript"; then
        require_value candidate_normalized_directive_count \
            "$(value_for live_normalized_directive_count "$transcript")" \
            "$transcript"
        require_value candidate_normalized_sha256 \
            "$(value_for live_normalized_sha256 "$transcript")" \
            "$transcript"
        require_value live_only_directive_count 0 "$transcript"
        require_value candidate_only_directive_count 0 "$transcript"
    fi
    if require_value candidate_validation_attempted true "$transcript"; then
        [[ "$(value_for candidate_checkconf_status "$transcript")" =~ ^[0-9]+$ ]]
    else
        require_value candidate_checkconf_status not_run "$transcript"
        require_value candidate_parser_valid false "$transcript"
    fi
    if require_value candidate_parser_valid true "$transcript"; then
        require_value candidate_validation_attempted true "$transcript"
        require_value candidate_checkconf_status 0 "$transcript"
        require_value candidate_checkconf_stderr_sha256 \
            "$empty_sha256" "$transcript"
    fi
    expected_conclusion=$(derive_conclusion "$transcript")
    require_value action_17d_node_b_unbound_preflight_conclusion \
        "$expected_conclusion" "$transcript"
}

write_fixture() {
    local destination=$1
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    printf '%s\n' \
        action_17d_node_b_unbound_preflight_remote_reached=true \
        node_role=node-b \
        node_hostname=j1-svpihole00 \
        node_identity_matches=true \
        "before_state_sha256=$state_hash" \
        live_root_state=regular \
        "live_root_sha256=$state_hash" \
        live_primary_state=regular \
        live_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
        live_primary_metadata=root:root:644:34342 \
        live_local_zone_state=absent \
        live_local_zone_sha256=unavailable \
        live_baseline_matches=true \
        live_conf_entry_count=3 \
        live_conf_entries_b64=cGlob2xlLmNvbmY= \
        "live_conf_tree_sha256=$state_hash" \
        live_nonregular_conf_count=0 \
        root_active_directive_count=1 \
        root_active_directives_b64=aW5jbHVkZS10b3BsZXZlbDo= \
        root_include_toplevel_count=1 \
        root_include_topology_supported=true \
        unbound_package_version_b64=MS4xNy4x \
        unbound_binary_version_b64=VmVyc2lvbg== \
        unbound_active=active \
        unbound_unit_file_state=enabled \
        pihole_ftl_active=active \
        service_state_ready=true \
        live_checkconf_status=0 \
        "live_checkconf_stdout_sha256=$empty_sha256" \
        "live_checkconf_stderr_sha256=$empty_sha256" \
        live_parser_valid=true \
        "candidate_primary_sha256=$candidate_primary_sha256" \
        "candidate_local_zone_sha256=$candidate_local_zone_sha256" \
        candidate_primary_server_count=1 \
        candidate_local_zone_server_count=1 \
        candidate_primary_local_policy_count=0 \
        candidate_local_zone_forbidden_count=0 \
        ownership_boundary_valid=true \
        live_normalized_directive_count=100 \
        candidate_normalized_directive_count=100 \
        "live_normalized_sha256=$state_hash" \
        "candidate_normalized_sha256=$state_hash" \
        live_only_directive_count=0 \
        candidate_only_directive_count=0 \
        canonical_directives_equal=true \
        candidate_validation_attempted=true \
        candidate_checkconf_status=0 \
        "candidate_checkconf_stdout_sha256=$empty_sha256" \
        "candidate_checkconf_stderr_sha256=$empty_sha256" \
        candidate_parser_valid=true \
        "after_state_sha256=$state_hash" \
        node_state_unchanged=true \
        action_17d_node_b_unbound_preflight_conclusion=ready_for_staged_adoption_design \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17d_node_b_unbound_preflight_inspection_complete=true \
        action_17d_node_b_remote_stage_cleanup_complete=true \
        >"$destination"
}

prepare_payload() {
    local destination=$1

    install -d -m 0700 "$destination"
    install -m 0700 "$inspector" \
        "$destination/inspect-node-b-two-file-unbound-preflight-action17d.sh"
    install -m 0600 "$candidate_primary" "$destination/pihole.conf"
    install -m 0600 \
        "$candidate_local_zone" "$destination/pihole0-local-zone.conf"
    [[ "$(find "$destination" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 3 ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$inspector_sha256" \
        "$regression_sha256" \
        "$accepted_dns_runner_sha256" \
        "$candidate_primary_sha256" \
        "$candidate_local_zone_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_source_contents
    "$inspector" --self-test >/dev/null
    "$regression" --self-test >/dev/null
    printf 'action_17d_node_b_unbound_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    verify_operator_sources
    test_dir=$(mktemp -d /tmp/caddy-action17d-source-test.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    prepare_payload "$test_dir/payload"
    printf 'action_17d_node_b_unbound_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17d-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_fixture "$test_dir/ready"
    validate_transcript "$test_dir/ready"
    validate_secret_free "$test_dir/ready"
    sed \
        -e 's/canonical_directives_equal=true/canonical_directives_equal=false/' \
        -e 's/action_17d_node_b_unbound_preflight_conclusion=ready_for_staged_adoption_design/action_17d_node_b_unbound_preflight_conclusion=candidate_semantic_drift/' \
        "$test_dir/ready" >"$test_dir/drift"
    validate_transcript "$test_dir/drift"
    cp -- "$test_dir/ready" "$test_dir/duplicate"
    printf 'node_state_unchanged=true\n' >>"$test_dir/duplicate"
    if validate_transcript "$test_dir/duplicate"; then
        printf 'Duplicate Action 17d evidence was accepted.\n' >&2
        exit 1
    fi
    cp -- "$test_dir/ready" "$test_dir/secret"
    printf 'DOPPLER_TOKEN=forbidden\n' >>"$test_dir/secret"
    if validate_secret_free "$test_dir/secret"; then
        printf 'Secret-bearing Action 17d evidence was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17d_node_b_unbound_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
verify_operator_sources
work_dir=$(mktemp -d /tmp/caddy-action17d-runner.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
prepare_payload "$work_dir/payload"
tar -C "$work_dir/payload" -cf "$work_dir/payload.tar" .

remote_script=$(
    printf '%s\n' \
        'set -euo pipefail' \
        'set +x' \
        'umask 077' \
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
        'export PATH' \
        'stage=$(mktemp -d /run/caddy-action17d.XXXXXX)' \
        'cleanup() { rm -rf -- "$stage"; }' \
        'trap cleanup EXIT' \
        'tar --no-same-owner --no-same-permissions -C "$stage" -xf -' \
        '[[ "$(find "$stage" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 3 ]]' \
        'chmod 0700 "$stage/inspect-node-b-two-file-unbound-preflight-action17d.sh"' \
        'chmod 0600 "$stage/pihole.conf" "$stage/pihole0-local-zone.conf"' \
        'inspector_status=0' \
        'cd /' \
        '/bin/bash "$stage/inspect-node-b-two-file-unbound-preflight-action17d.sh" --node node-b --stage "$stage" || inspector_status=$?' \
        'cleanup' \
        'trap - EXIT' \
        '[[ ! -e "$stage" && ! -L "$stage" ]]' \
        'printf "action_17d_node_b_remote_stage_cleanup_complete=true\n"' \
        'exit "$inspector_status"'
)
readonly remote_script
remote_script_b64=$(printf '%s' "$remote_script" | base64 -w 0)
readonly remote_script_b64
remote_command="sudo -n /bin/bash -c \"\$(printf '%s' '$remote_script_b64' | base64 -d)\""
readonly remote_command

node_b_output="$work_dir/node-b.out"
node_b_error="$work_dir/node-b.err"
node_b_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$node_b_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$node_b_target" \
    "$remote_command" \
    <"$work_dir/payload.tar" >"$node_b_output" 2>"$node_b_error" ||
    node_b_status=$?
cat "$node_b_output"
cat "$node_b_error" >&2
printf 'node_b_administrative_ssh_status=%s\n' "$node_b_status"

if [[ "$node_b_status" -ne 0 ]] ||
    [[ -s "$node_b_error" ]] ||
    ! validate_transcript "$node_b_output" ||
    ! validate_secret_free "$node_b_output" "$node_b_error"; then
    printf 'Action 17d Node B Unbound preflight evidence is incomplete.\n' >&2
    exit 97
fi

printf '%s\n' \
    "action_17d_node_b_unbound_preflight_conclusion=$(value_for action_17d_node_b_unbound_preflight_conclusion "$node_b_output")" \
    action_17d_node_b_unbound_preflight_accepted=true
cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17d_local_cleanup_complete=true\n'
