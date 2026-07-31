#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=f0e0c89732f0db755623870f0d8f72189936bfed6777ce38a805081bdf010387
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_assertion_count=51
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly inspector="$script_dir/inspect-node-a-two-file-unbound-preflight-action17h.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly candidate_primary="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly candidate_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
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
    verify_file "$inspector" "$inspector_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$candidate_local_zone" "$candidate_local_zone_sha256"
    bash -n "$inspector" "$collision_checker"
    "$inspector" --self-test >/dev/null
    "$collision_checker" "$inspector" "$0" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in "$inspector" "$collision_checker" "$0"; do
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:755 ]]
    done
    for source_path in "$candidate_primary" "$candidate_local_zone"; do
        [[ "$(stat -c '%U:%G:%a' "$source_path")" == aaron:aaron:644 ]]
    done
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    git -C "$dns_repo" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
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

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=|private-domain:|local-data(-ptr)?:' \
        "$@"
}

validate_transcript() {
    local transcript_path=$1
    local assertion_count unique_assertion_count
    local before_state after_state

    assertion_count=$(
        grep -Ec '^action_17h_assertion_[a-z0-9_]+=true$' "$transcript_path"
    )
    unique_assertion_count=$(
        grep -E '^action_17h_assertion_[a-z0-9_]+=true$' "$transcript_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$assertion_count" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertion_count" -eq "$expected_assertion_count" ]] ||
        return 1
    if grep -Eq '^action_17h_assertion_[a-z0-9_]+=false$|^action_17h_observed_' \
        "$transcript_path"; then
        return 1
    fi
    require_value action_17h_remote_reached true "$transcript_path" ||
        return 1
    require_value action_17h_assertion_count \
        "$expected_assertion_count" "$transcript_path" || return 1
    require_value action_17h_failed_assertion_count 0 "$transcript_path" ||
        return 1
    require_value action_17h_first_failure none "$transcript_path" ||
        return 1
    require_value action_17h_conclusion \
        ready_for_node_a_staged_adoption "$transcript_path" || return 1
    require_value action_17h_remote_complete true "$transcript_path" ||
        return 1
    require_value action_17h_remote_stage_cleanup_complete \
        true "$transcript_path" || return 1
    require_value remote_stage_created true "$transcript_path" || return 1
    require_value dns_queries_performed false "$transcript_path" || return 1
    require_value dns_configuration_mutations false "$transcript_path" ||
        return 1
    require_value service_mutations false "$transcript_path" || return 1
    require_value persistent_mutations false "$transcript_path" || return 1
    before_state=$(value_for action_17h_before_state_sha256 "$transcript_path")
    after_state=$(value_for action_17h_after_state_sha256 "$transcript_path")
    [[ "$before_state" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$after_state" == "$before_state" ]] || return 1
}

write_fixture() {
    local fixture_path=$1
    local false_label=${2:-}
    local fixture_index fixture_value
    local failed_count=0
    local first_failure=none
    local conclusion=ready_for_node_a_staged_adoption

    printf 'action_17h_remote_reached=true\n' >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        fixture_value=true
        if [[ "$false_label" == "fixture_${fixture_index}" ]]; then
            fixture_value=false
            failed_count=1
            first_failure=$false_label
            conclusion=node_a_preflight_mismatch
        fi
        printf 'action_17h_assertion_fixture_%02d=%s\n' \
            "$fixture_index" "$fixture_value"
        if [[ "$fixture_value" == false ]]; then
            printf 'action_17h_observed_fixture_%02d=mismatch\n' \
                "$fixture_index"
        fi
    done >>"$fixture_path"
    printf '%s\n' \
        "action_17h_assertion_count=$expected_assertion_count" \
        "action_17h_failed_assertion_count=$failed_count" \
        "action_17h_first_failure=$first_failure" \
        action_17h_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        action_17h_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        remote_stage_created=true \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        "action_17h_conclusion=$conclusion" \
        action_17h_remote_complete=true \
        action_17h_remote_stage_cleanup_complete=true \
        >>"$fixture_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq 'cd /' "$0"
    printf 'action_17h_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17h_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17h-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"
    write_fixture "$success_fixture"
    validate_transcript "$success_fixture"
    write_fixture "$mismatch_fixture" fixture_17
    if validate_transcript "$mismatch_fixture"; then
        printf 'Action 17h mismatch fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17h_assertion_fixture_01=true\n' >>"$duplicate_fixture"
    if validate_transcript "$duplicate_fixture"; then
        printf 'Action 17h duplicate fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$unsafe_fixture"
    printf '%s\n' 'local-data: "private.example. A 192.0.2.1"' \
        >>"$unsafe_fixture"
    if validate_secret_free "$unsafe_fixture"; then
        printf 'Action 17h unsafe fixture was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17h_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17h.XXXXXX)
readonly work_directory
readonly payload_directory="$work_directory/payload"
readonly payload_archive="$work_directory/payload.tar"
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

install -d -m 0700 "$payload_directory"
install -m 0700 "$inspector" \
    "$payload_directory/inspect-node-a-two-file-unbound-preflight-action17h.sh"
install -m 0600 "$candidate_primary" "$payload_directory/pihole.conf"
install -m 0600 "$candidate_local_zone" \
    "$payload_directory/pihole-local-zone.conf"
tar -C "$payload_directory" -cf "$payload_archive" .

remote_script=$(
    printf '%s\n' \
        'set -Eeu -o pipefail' \
        'set +x' \
        'umask 077' \
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
        'export PATH' \
        'cd /' \
        'stage=$(mktemp -d /run/caddy-action17h.XXXXXX)' \
        'cleanup() { rm -rf -- "$stage"; }' \
        'trap cleanup EXIT' \
        'tar -C "$stage" -xf -' \
        'chown -R root:root "$stage"' \
        'chmod 0700 "$stage" "$stage/inspect-node-a-two-file-unbound-preflight-action17h.sh"' \
        'chmod 0600 "$stage/pihole.conf" "$stage/pihole-local-zone.conf"' \
        'status=0' \
        '/bin/bash "$stage/inspect-node-a-two-file-unbound-preflight-action17h.sh" --stage "$stage" || status=$?' \
        'cleanup' \
        'trap - EXIT' \
        '[[ ! -e "$stage" && ! -L "$stage" ]]' \
        'printf "action_17h_remote_stage_cleanup_complete=true\n"' \
        'exit "$status"'
)
readonly remote_script
remote_script_b64=$(printf '%s' "$remote_script" | base64 -w 0)
readonly remote_script_b64
remote_command="sudo -n /bin/bash -c \"\$(printf '%s' '$remote_script_b64' | base64 -d)\""
readonly remote_command

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$expected_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$expected_target" \
    "$remote_command" \
    <"$payload_archive" >"$remote_output" 2>"$remote_error" ||
    ssh_status=$?
cat "$remote_output"
cat "$remote_error" >&2
printf 'ssh_exit_status=%s\n' "$ssh_status"

if [[ "$ssh_status" -ne 0 || -s "$remote_error" ]] ||
    ! validate_secret_free "$remote_output" "$remote_error" ||
    ! validate_transcript "$remote_output"; then
    printf 'Action 17h authoritative evidence contract failed.\n' >&2
    exit 97
fi
printf 'action_17h_node_a_preflight_accepted=true\n'
cleanup
trap - EXIT
[[ ! -e "$work_directory" && ! -L "$work_directory" ]]
printf 'action_17h_local_cleanup_complete=true\n'
