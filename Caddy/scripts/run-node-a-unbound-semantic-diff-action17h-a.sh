#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=e5aa31f2bec9c6390cb7e9ecba7ed5798248c46a2589f7baa73fd0a820ebe789
readonly prior_inspector_sha256=f0e0c89732f0db755623870f0d8f72189936bfed6777ce38a805081bdf010387
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly expected_assertion_count=29
readonly expected_difference_count=24
readonly expected_target=pi@10.1.0.53
readonly expected_host_alias=pihole0.local.theama.co

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly diagnostic="$script_dir/inspect-node-a-unbound-semantic-diff-action17h-a.sh"
readonly prior_inspector="$script_dir/inspect-node-a-two-file-unbound-preflight-action17h.sh"
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
    verify_file "$diagnostic" "$diagnostic_sha256"
    verify_file "$prior_inspector" "$prior_inspector_sha256"
    verify_file "$collision_checker" "$collision_checker_sha256"
    verify_file "$candidate_primary" "$candidate_primary_sha256"
    verify_file "$candidate_local_zone" "$candidate_local_zone_sha256"
    bash -n "$diagnostic" "$prior_inspector" "$collision_checker"
    "$diagnostic" --self-test >/dev/null
    "$prior_inspector" --self-test >/dev/null
    "$collision_checker" "$diagnostic" "$prior_inspector" "$0" >/dev/null
}

verify_live_sources() {
    local source_path

    verify_sources
    for source_path in "$diagnostic" "$prior_inspector" \
        "$collision_checker" "$0"; do
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
    local evidence_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$evidence_path")" -eq 1 ]] ||
        return 1
    value_record=$(grep -E "^${value_key}=" "$evidence_path")
    printf '%s\n' "${value_record#*=}"
}

require_value() {
    local required_key=$1
    local required_value=$2
    local evidence_path=$3

    [[ "$(value_for "$required_key" "$evidence_path")" == "$required_value" ]]
}

validate_raw_secret_free() {
    ! grep -Eiq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
        "$@"
}

validate_decoded_safe() {
    ! grep -Eiq \
        'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|API[_-]?KEY|PASSWORD|SECRET|TOKEN' \
        "$@"
}

decode_records() {
    local record_prefix=$1
    local evidence_path=$2
    local decoded_path=$3
    local record_index
    local record_key
    local encoded_value
    local decoded_value

    : >"$decoded_path"
    for ((record_index = 1; record_index <= expected_difference_count; record_index += 1)); do
        printf -v record_key 'action_17h_a_%s_%03d_b64' \
            "$record_prefix" "$record_index"
        encoded_value=$(value_for "$record_key" "$evidence_path") ||
            return 1
        [[ "$encoded_value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
        decoded_value=$(printf '%s' "$encoded_value" | base64 -d 2>/dev/null) ||
            return 1
        [[ -n "$decoded_value" && "$decoded_value" != *$'\r'* ]] || return 1
        [[ "$(printf '%s' "$decoded_value" | base64 -w 0)" == "$encoded_value" ]] ||
            return 1
        printf '%s\n' "$decoded_value" >>"$decoded_path"
    done
    [[ "$(grep -Ec "^action_17h_a_${record_prefix}_[0-9]{3}_b64=" \
        "$evidence_path")" -eq "$expected_difference_count" ]]
    LC_ALL=C sort -cu "$decoded_path"
    if LC_ALL=C grep -q '[^[:print:][:space:]]' "$decoded_path"; then
        return 1
    fi
    validate_decoded_safe "$decoded_path"
}

validate_transcript() {
    local evidence_path=$1
    local validation_root=$2
    local assertion_total
    local unique_assertion_total
    local decoded_live_path="$validation_root/live-only"
    local decoded_candidate_path="$validation_root/candidate-only"

    assertion_total=$(
        grep -Ec '^action_17h_a_assertion_[a-z0-9_]+=true$' "$evidence_path"
    )
    unique_assertion_total=$(
        grep -E '^action_17h_a_assertion_[a-z0-9_]+=true$' "$evidence_path" |
            cut -d= -f1 |
            LC_ALL=C sort -u |
            wc -l
    )
    [[ "$assertion_total" -eq "$expected_assertion_count" ]] || return 1
    [[ "$unique_assertion_total" -eq "$expected_assertion_count" ]] ||
        return 1
    if grep -Eq \
        '^action_17h_a_assertion_[a-z0-9_]+=false$|^action_17h_a_observed_' \
        "$evidence_path"; then
        return 1
    fi
    require_value action_17h_a_remote_reached true "$evidence_path" ||
        return 1
    require_value action_17h_a_assertion_count \
        "$expected_assertion_count" "$evidence_path" || return 1
    require_value action_17h_a_failed_assertion_count 0 "$evidence_path" ||
        return 1
    require_value action_17h_a_first_failure none "$evidence_path" ||
        return 1
    require_value action_17h_a_live_only_count \
        "$expected_difference_count" "$evidence_path" || return 1
    require_value action_17h_a_candidate_only_count \
        "$expected_difference_count" "$evidence_path" || return 1
    require_value action_17h_a_before_state_sha256 \
        "$expected_state_sha256" "$evidence_path" || return 1
    require_value action_17h_a_after_state_sha256 \
        "$expected_state_sha256" "$evidence_path" || return 1
    require_value action_17h_a_conclusion \
        semantic_difference_captured "$evidence_path" || return 1
    require_value action_17h_a_remote_complete true "$evidence_path" ||
        return 1
    require_value action_17h_a_remote_stage_cleanup_complete \
        true "$evidence_path" || return 1
    require_value remote_stage_created true "$evidence_path" || return 1
    require_value dns_queries_performed false "$evidence_path" || return 1
    require_value dns_configuration_mutations false "$evidence_path" ||
        return 1
    require_value service_mutations false "$evidence_path" || return 1
    require_value persistent_mutations false "$evidence_path" || return 1
    decode_records live_only "$evidence_path" "$decoded_live_path" ||
        return 1
    decode_records candidate_only "$evidence_path" "$decoded_candidate_path" ||
        return 1
    [[ "$(file_hash "$decoded_live_path")" == "$(value_for action_17h_a_live_only_sha256 "$evidence_path")" ]] ||
        return 1
    [[ "$(file_hash "$decoded_candidate_path")" == "$(value_for action_17h_a_candidate_only_sha256 "$evidence_path")" ]] ||
        return 1
    [[ "$(comm -12 "$decoded_live_path" "$decoded_candidate_path" | wc -l)" -eq 0 ]]
}

write_fixture() {
    local fixture_path=$1
    local fixture_directory=$2
    local false_label=${3:-}
    local fixture_index
    local fixture_value
    local fixture_failed=0
    local fixture_first_failure=none
    local fixture_conclusion=semantic_difference_captured
    local fixture_live="$fixture_directory/live"
    local fixture_candidate="$fixture_directory/candidate"

    : >"$fixture_live"
    : >"$fixture_candidate"
    for ((fixture_index = 1; fixture_index <= expected_difference_count; fixture_index += 1)); do
        printf 'fixture-live-%03d\n' "$fixture_index" >>"$fixture_live"
        printf 'fixture-candidate-%03d\n' "$fixture_index" >>"$fixture_candidate"
    done
    printf 'action_17h_a_remote_reached=true\n' >"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_assertion_count; fixture_index += 1)); do
        fixture_value=true
        if [[ "$false_label" == "fixture_${fixture_index}" ]]; then
            fixture_value=false
            fixture_failed=1
            fixture_first_failure=$false_label
            fixture_conclusion=diagnostic_prerequisite_failed
        fi
        printf 'action_17h_a_assertion_fixture_%02d=%s\n' \
            "$fixture_index" "$fixture_value" >>"$fixture_path"
        if [[ "$fixture_value" == false ]]; then
            printf 'action_17h_a_observed_fixture_%02d=mismatch\n' \
                "$fixture_index" >>"$fixture_path"
        fi
    done
    printf '%s\n' \
        "action_17h_a_assertion_count=$expected_assertion_count" \
        "action_17h_a_failed_assertion_count=$fixture_failed" \
        "action_17h_a_first_failure=$fixture_first_failure" \
        "action_17h_a_live_only_count=$expected_difference_count" \
        "action_17h_a_candidate_only_count=$expected_difference_count" \
        "action_17h_a_live_only_sha256=$(file_hash "$fixture_live")" \
        "action_17h_a_candidate_only_sha256=$(file_hash "$fixture_candidate")" \
        "action_17h_a_before_state_sha256=$expected_state_sha256" \
        "action_17h_a_after_state_sha256=$expected_state_sha256" \
        remote_stage_created=true \
        dns_queries_performed=false \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        "action_17h_a_conclusion=$fixture_conclusion" \
        action_17h_a_remote_complete=true \
        action_17h_a_remote_stage_cleanup_complete=true \
        >>"$fixture_path"
    for ((fixture_index = 1; fixture_index <= expected_difference_count; fixture_index += 1)); do
        printf 'action_17h_a_live_only_%03d_b64=%s\n' \
            "$fixture_index" \
            "$(printf 'fixture-live-%03d' "$fixture_index" | base64 -w 0)"
        printf 'action_17h_a_candidate_only_%03d_b64=%s\n' \
            "$fixture_index" \
            "$(printf 'fixture-candidate-%03d' "$fixture_index" | base64 -w 0)"
    done >>"$fixture_path"
}

render_records() {
    local render_prefix=$1
    local decoded_path=$2
    local render_index=0
    local rendered_line

    while IFS= read -r rendered_line || [[ -n "$rendered_line" ]]; do
        ((render_index += 1))
        printf 'action_17h_a_%s_directive_%03d=%s\n' \
            "$render_prefix" "$render_index" "$rendered_line"
    done <"$decoded_path"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    verify_sources
    grep -Fq 'cd /' "$0"
    printf 'action_17h_a_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_live_sources
    printf 'action_17h_a_runner_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_directory=$(mktemp -d /tmp/caddy-action17h-a-contract.XXXXXX)
    trap 'rm -rf -- "$contract_directory"' EXIT
    success_fixture="$contract_directory/success"
    mismatch_fixture="$contract_directory/mismatch"
    duplicate_fixture="$contract_directory/duplicate"
    unsafe_fixture="$contract_directory/unsafe"
    write_fixture "$success_fixture" "$contract_directory"
    validate_transcript "$success_fixture" "$contract_directory"
    write_fixture "$mismatch_fixture" "$contract_directory" fixture_17
    if validate_transcript "$mismatch_fixture" "$contract_directory"; then
        printf 'Action 17h-a mismatch fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$duplicate_fixture"
    printf 'action_17h_a_live_only_001_b64=ZHVwbGljYXRl\n' \
        >>"$duplicate_fixture"
    if validate_transcript "$duplicate_fixture" "$contract_directory"; then
        printf 'Action 17h-a duplicate fixture was accepted.\n' >&2
        exit 1
    fi
    cp -- "$success_fixture" "$unsafe_fixture"
    sed -i \
        's/^action_17h_a_live_only_001_b64=.*/action_17h_a_live_only_001_b64=UEFTU1dPUkQ9dW5zYWZl/' \
        "$unsafe_fixture"
    if validate_transcript "$unsafe_fixture" "$contract_directory"; then
        printf 'Action 17h-a unsafe fixture was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17h_a_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_live_sources
work_directory=$(mktemp -d /tmp/caddy-action17h-a.XXXXXX)
readonly work_directory
readonly payload_directory="$work_directory/payload"
readonly payload_archive="$work_directory/payload.tar"
readonly remote_output="$work_directory/remote.out"
readonly remote_error="$work_directory/remote.err"
readonly validation_directory="$work_directory/validation"

cleanup() {
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

install -d -m 0700 "$payload_directory" "$validation_directory"
install -m 0700 "$diagnostic" \
    "$payload_directory/inspect-node-a-unbound-semantic-diff-action17h-a.sh"
install -m 0700 "$prior_inspector" \
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
        'chmod 0700 "$stage" "$stage/inspect-node-a-unbound-semantic-diff-action17h-a.sh" "$stage/inspect-node-a-two-file-unbound-preflight-action17h.sh"' \
        'chmod 0600 "$stage/pihole.conf" "$stage/pihole-local-zone.conf"' \
        'status=0' \
        '/bin/bash "$stage/inspect-node-a-unbound-semantic-diff-action17h-a.sh" --stage "$stage" || status=$?' \
        'cleanup' \
        'trap - EXIT' \
        '[[ ! -e "$stage" && ! -L "$stage" ]]' \
        'printf "action_17h_a_remote_stage_cleanup_complete=true\n"' \
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

printf 'ssh_exit_status=%s\n' "$ssh_status"
if [[ "$ssh_status" -ne 0 || -s "$remote_error" ]] ||
    ! validate_raw_secret_free "$remote_output" "$remote_error" ||
    ! validate_transcript "$remote_output" "$validation_directory"; then
    printf 'Action 17h-a authoritative evidence contract failed.\n' >&2
    exit 97
fi

cat "$remote_output"
render_records live_only "$validation_directory/live-only"
render_records candidate_only "$validation_directory/candidate-only"
printf 'action_17h_a_node_a_semantic_diff_accepted=true\n'
cleanup
trap - EXIT
[[ ! -e "$work_directory" && ! -L "$work_directory" ]]
printf 'action_17h_a_local_cleanup_complete=true\n'
