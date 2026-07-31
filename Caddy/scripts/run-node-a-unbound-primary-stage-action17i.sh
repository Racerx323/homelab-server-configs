#!/usr/bin/env bash
# shellcheck disable=SC2016 # Assert literal remote shell source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly driver_sha256=d3d482260f679d08e76c6e1dc678e987d379d82d7e0514bd791d55147684fd4f
readonly regression_sha256=0ec724bce4aaa072ff9a1f245bb958d4cc779d83c8542c0a2088aee55b031eba
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly accepted_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly expected_assertion_count=76
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co
readonly expected_stage=/var/tmp/caddy-unbound-node-a-action17i-primary

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly driver="$script_dir/stage-node-a-unbound-primary-action17i.sh"
readonly regression="$caddy_root/tests/action17i-node-a-unbound-primary-stage-regression.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly dns_repo="$workspace_root/homelab-dns"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verified_path=$1
    local expected_hash=$2

    [[ -f "$verified_path" && ! -L "$verified_path" ]]
    [[ "$(file_hash "$verified_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$driver" "$driver_sha256"
    verify_file "$regression" "$regression_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    bash -n "$driver" "$regression" "$collision_checker"
    "$driver" --self-test >/dev/null
    "$collision_checker" "$driver" "$0" "$regression" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in "$driver" "$regression" "$collision_checker" "$0"; do
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
    done
    [[ "$(stat -c '%U:%G:%a' "$candidate_primary")" == aaron:aaron:644 ]]
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1; then
        printf 'Private Unbound primary source unexpectedly became tracked.\n' >&2
        return 1
    fi
}

value_for() {
    local value_key=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$transcript_path")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

require_value() {
    local required_key=$1
    local required_value=$2
    local transcript_path=$3

    [[ "$(value_for "$required_key" "$transcript_path")" == "$required_value" ]]
}

validate_safe_output() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_success() {
    local transcript_path=$1
    local error_path=$2
    local ssh_exit_status=$3
    local true_assertions unique_assertions
    local before_hash after_hash
    local -a required_records=(
        action_17i_remote_reached=true
        action_17i_preflight_complete=true
        primary_stage_previously_absent=true
        local_zone_stage_absent=true
        action_17i_mutation_started=true
        "primary_candidate_sha256=$candidate_primary_sha256"
        "primary_stage_path=$expected_stage"
        primary_stage_owner_mode=root:root:700
        primary_file_owner_mode=root:root:600
        primary_file_parser_valid=true
        primary_ownership_boundary_valid=true
        primary_stage_complete=true
        local_zone_file_staged=false
        live_unbound_configuration_mutated=false
        dns_queries_performed=false
        service_mutations=false
        live_state_unchanged=true
        persistent_mutation_scope=primary_stage_only
        action_17i_conclusion=primary_stage_retained
        action_17i_remote_complete=true
        action_17i_node_a_unbound_primary_stage_complete=true
        action_17i_remote_source_cleanup_complete=true
    )
    local required_record

    [[ "$ssh_exit_status" -eq 0 ]]
    [[ ! -s "$error_path" ]]
    true_assertions=$(
        grep -Ec '^action_17i_assertion_[a-z0-9_]+=true$' "$transcript_path"
    )
    unique_assertions=$(
        grep -E '^action_17i_assertion_[a-z0-9_]+=true$' "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$true_assertions" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertions" -eq "$expected_assertion_count" ]] || return 1
    if grep -Eq \
        '^action_17i_assertion_[a-z0-9_]+=false$|^action_17i_observed_' \
        "$transcript_path"; then
        return 1
    fi
    require_value action_17i_assertion_count \
        "$expected_assertion_count" "$transcript_path" || return 1
    require_value action_17i_failed_assertion_count 0 "$transcript_path" ||
        return 1
    require_value action_17i_first_failure none "$transcript_path" || return 1
    for required_record in "${required_records[@]}"; do
        [[ "$(grep -Fxc "$required_record" "$transcript_path")" -eq 1 ]] ||
            return 1
    done
    before_hash=$(value_for before_live_state_sha256 "$transcript_path")
    after_hash=$(value_for after_live_state_sha256 "$transcript_path")
    [[ "$before_hash" == "$accepted_state_sha256" ]] || return 1
    [[ "$after_hash" == "$before_hash" ]] || return 1
    if grep -Eq 'action_17i_rollback_|manual_intervention_required=true' \
        "$transcript_path" "$error_path"; then
        return 1
    fi
}

validate_failure() {
    local transcript_path=$1
    local error_path=$2
    local ssh_exit_status=$3

    [[ "$ssh_exit_status" -ne 0 ]] || return 97
    if grep -Fq 'manual_intervention_required=true' \
        "$transcript_path" "$error_path" ||
        grep -Fq 'action_17i_rollback_complete=false' \
            "$transcript_path" "$error_path"; then
        return 97
    fi
    if grep -Fq 'action_17i_mutation_started=true' "$transcript_path"; then
        [[ "$(grep -Fxc action_17i_rollback_started=true "$error_path")" -eq 1 ]] ||
            return 97
        [[ "$(grep -Fxc action_17i_rollback_complete=true "$error_path")" -eq 1 ]] ||
            return 97
    elif grep -Eq 'action_17i_rollback_' "$transcript_path" "$error_path"; then
        return 97
    fi
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_index

    printf 'action_17i_remote_reached=true\n' >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        printf 'action_17i_assertion_fixture_%02d=true\n' "$fixture_index"
    done >>"$fixture_path"
    printf '%s\n' \
        action_17i_preflight_complete=true \
        "before_live_state_sha256=$accepted_state_sha256" \
        primary_stage_previously_absent=true \
        local_zone_stage_absent=true \
        action_17i_mutation_started=true \
        "action_17i_assertion_count=$expected_assertion_count" \
        action_17i_failed_assertion_count=0 \
        action_17i_first_failure=none \
        "primary_candidate_sha256=$candidate_primary_sha256" \
        "primary_stage_path=$expected_stage" \
        primary_stage_owner_mode=root:root:700 \
        primary_file_owner_mode=root:root:600 \
        primary_file_parser_valid=true \
        primary_ownership_boundary_valid=true \
        primary_stage_complete=true \
        local_zone_file_staged=false \
        live_unbound_configuration_mutated=false \
        dns_queries_performed=false \
        service_mutations=false \
        "after_live_state_sha256=$accepted_state_sha256" \
        live_state_unchanged=true \
        persistent_mutation_scope=primary_stage_only \
        action_17i_conclusion=primary_stage_retained \
        action_17i_remote_complete=true \
        action_17i_node_a_unbound_primary_stage_complete=true \
        action_17i_remote_source_cleanup_complete=true \
        >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq "'cd /'" "$0"
    printf 'action_17i_node_a_unbound_primary_stage_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17i_node_a_unbound_primary_stage_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17i-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    empty_error="$contract_directory/empty-error"
    false_fixture="$contract_directory/false"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"
    rollback_output="$contract_directory/rollback-output"
    rollback_error="$contract_directory/rollback-error"
    incomplete_error="$contract_directory/incomplete-error"
    : >"$empty_error"
    write_success_fixture "$success_fixture"
    validate_safe_output "$success_fixture" "$empty_error"
    validate_success "$success_fixture" "$empty_error" 0

    cp -- "$success_fixture" "$false_fixture"
    sed -i 's/action_17i_assertion_fixture_17=true/action_17i_assertion_fixture_17=false/' \
        "$false_fixture"
    if validate_success "$false_fixture" "$empty_error" 0; then
        printf 'False Action 17i assertion was accepted.\n' >&2
        exit 1
    fi

    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17i_assertion_fixture_01=true\n' >>"$duplicate_fixture"
    if validate_success "$duplicate_fixture" "$empty_error" 0; then
        printf 'Duplicate Action 17i assertion was accepted.\n' >&2
        exit 1
    fi

    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_safe_output "$unsafe_fixture"; then
        printf 'Private DNS directive output was accepted.\n' >&2
        exit 1
    fi

    printf 'action_17i_mutation_started=true\n' >"$rollback_output"
    printf '%s\n' \
        action_17i_rollback_started=true \
        action_17i_rollback_complete=true >"$rollback_error"
    validate_failure "$rollback_output" "$rollback_error" 1
    printf 'action_17i_rollback_started=true\n' >"$incomplete_error"
    set +e
    validate_failure "$rollback_output" "$incomplete_error" 1
    incomplete_status=$?
    set -e
    [[ "$incomplete_status" -eq 97 ]]
    printf 'action_17i_node_a_unbound_primary_stage_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17i.XXXXXX)
readonly work_directory
readonly payload_directory="$work_directory/payload"
readonly payload_archive="$work_directory/payload.tar"
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

finish() {
    local finish_status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_directory" || -L "$work_directory" ]]; then
        printf 'action_17i_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17i_local_cleanup_complete=true\n'
    exit "$finish_status"
}

install -d -m 0700 "$payload_directory"
install -m 0700 "$driver" \
    "$payload_directory/stage-node-a-unbound-primary-action17i.sh"
install -m 0600 "$candidate_primary" "$payload_directory/pihole.conf"
tar -C "$payload_directory" -cf "$payload_archive" .

remote_script=$(
    printf '%s\n' \
        'set -Eeu -o pipefail' \
        'set +x' \
        'umask 077' \
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
        'export PATH' \
        'cd /' \
        'source_stage=$(mktemp -d /run/caddy-action17i.XXXXXX)' \
        'cleanup_source_stage() { rm -rf -- "$source_stage"; }' \
        'trap cleanup_source_stage EXIT' \
        'tar -C "$source_stage" -xf -' \
        'chown -R root:root "$source_stage"' \
        'chmod 0700 "$source_stage" "$source_stage/stage-node-a-unbound-primary-action17i.sh"' \
        'chmod 0600 "$source_stage/pihole.conf"' \
        'driver_status=0' \
        '/bin/bash "$source_stage/stage-node-a-unbound-primary-action17i.sh" --source-stage "$source_stage" || driver_status=$?' \
        'cleanup_source_stage' \
        'trap - EXIT' \
        '[[ ! -e "$source_stage" && ! -L "$source_stage" ]]' \
        'printf "action_17i_remote_source_cleanup_complete=true\n"' \
        'exit "$driver_status"'
)
readonly remote_script
remote_script_b64=$(printf '%s' "$remote_script" | base64 -w 0)
readonly remote_script_b64
remote_command="sudo -n /bin/bash -c \"\$(printf '%s' '$remote_script_b64' | base64 -d)\""
readonly remote_command

ssh_status=0
set +e
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "$remote_command" \
    <"$payload_archive" >"$remote_output" 2>"$remote_error"
ssh_status=$?
set -e

cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"
if ! validate_safe_output "$remote_output" "$remote_error"; then
    printf 'Unsafe Action 17i output detected.\n' >&2
    finish 97
fi
if [[ "$ssh_status" -eq 0 ]]; then
    if ! validate_success "$remote_output" "$remote_error" "$ssh_status"; then
        printf 'Action 17i success contract failed.\n' >&2
        finish 97
    fi
    printf 'action_17i_node_a_unbound_primary_stage_accepted=true\n'
    finish 0
fi

set +e
validate_failure "$remote_output" "$remote_error" "$ssh_status"
failure_validation_status=$?
set -e
if [[ "$failure_validation_status" -eq 97 ]]; then
    printf 'Action 17i rollback evidence is incomplete.\n' >&2
    finish 97
fi
printf 'action_17i_node_a_unbound_primary_stage_accepted=false\n'
finish "$ssh_status"
