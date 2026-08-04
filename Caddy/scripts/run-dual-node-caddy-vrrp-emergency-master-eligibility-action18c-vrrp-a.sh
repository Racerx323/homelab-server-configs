#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_18c_vrrp_a
readonly inspector_sha256=f7d50d5b3ff205e845ab577653dcc373ebd745988c81f9cbbc402664b96e6bc0
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector="$script_directory/inspect-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR }' "$1"
}

safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}

emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if ! safe_stream "$stream_path"; then
        trap - EXIT
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$stream_label" >&2
        printf '%s_%s_protected_evidence=%s\n' \
            "$prefix" "$stream_label" "${stream_path%/*}" >&2
        return 97
    fi
    if [[ ! -s "$stream_path" ]]; then
        printf '%s_%s_classification=empty\n' "$prefix" "$stream_label"
        return 0
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
    printf '%s_%s_safe_content_begin=true\n' "$prefix" "$stream_label"
    cat "$stream_path"
    printf '%s_%s_safe_content_end=true\n' "$prefix" "$stream_label"
}

extract_source_labels() {
    local source_path=$1

    awk '
        /record_command\(\)/ { next }
        /^[[:space:]]*record_command [a-z0-9_]+/ {
            line = $0
            sub(/^[[:space:]]*record_command /, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            next
        }
        /^[[:space:]]*record_command[[:space:]]*\\$/ {
            getline
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
        }
    ' "$source_path"
}

value_for() {
    local value_key=$1
    local transcript_path=$2
    local value_record

    [[ "$(grep -Ec "^${value_key}=" "$transcript_path")" -eq 1 ]] || return 1
    value_record=$(grep -E "^${value_key}=" "$transcript_path")
    printf '%s\n' "${value_record#*=}"
}

require_one() {
    local required_record=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$required_record" "$transcript_path")" -eq 1 ]]
}

is_nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha256() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

validate_remote_transcript() {
    local validation_label=$1
    local transcript_path=$2
    local error_path=$3
    local remote_status=$4
    local expected_role=$5
    local expected_state=$6
    local expected_vip_count=$7
    local expected_labels_path="$work_directory/${validation_label}.expected"
    local observed_labels_path="$work_directory/${validation_label}.observed"
    local expected_count
    local observed_count
    local reported_count
    local reported_failed
    local reported_first
    local before_hash
    local after_hash
    local observed_role
    local observed_state
    local observed_ipv4_count
    local observed_ipv6_count

    extract_source_labels "$inspector" | LC_ALL=C sort >"$expected_labels_path"
    sed -n \
        "s/^action_18c_vrrp_a_remote_assertion_\\([a-z0-9_]*\\)=\\(true\\|false\\)$/\\1/p" \
        "$transcript_path" | LC_ALL=C sort >"$observed_labels_path"
    expected_count=$(wc -l <"$expected_labels_path")
    observed_count=$(wc -l <"$observed_labels_path")
    reported_count=$(value_for action_18c_vrrp_a_remote_assertion_count \
        "$transcript_path") || reported_count=invalid
    reported_failed=$(value_for action_18c_vrrp_a_remote_failed_assertion_count \
        "$transcript_path") || reported_failed=invalid
    reported_first=$(value_for action_18c_vrrp_a_remote_first_failure \
        "$transcript_path") || reported_first=invalid
    before_hash=$(value_for action_18c_vrrp_a_remote_value_before_state_sha256 \
        "$transcript_path") || before_hash=invalid
    after_hash=$(value_for action_18c_vrrp_a_remote_value_after_state_sha256 \
        "$transcript_path") || after_hash=invalid
    observed_role=$(value_for action_18c_vrrp_a_remote_value_node_role \
        "$transcript_path") || observed_role=invalid
    observed_state=$(value_for action_18c_vrrp_a_remote_value_vrrp_state \
        "$transcript_path") || observed_state=invalid
    observed_ipv4_count=$(value_for action_18c_vrrp_a_remote_value_ipv4_vip_count \
        "$transcript_path") || observed_ipv4_count=invalid
    observed_ipv6_count=$(value_for action_18c_vrrp_a_remote_value_ipv6_vip_count \
        "$transcript_path") || observed_ipv6_count=invalid

    record_command "${validation_label}_status_zero" test "$remote_status" -eq 0
    record_command "${validation_label}_stderr_empty" test ! -s "$error_path"
    record_command "${validation_label}_expected_count_positive" test \
        "$expected_count" -gt 0
    record_command "${validation_label}_label_count_exact" test \
        "$observed_count" -eq "$expected_count"
    record_command "${validation_label}_labels_exact" cmp -s \
        "$expected_labels_path" "$observed_labels_path"
    record_command "${validation_label}_labels_unique" test \
        "$(sort -u "$observed_labels_path" | wc -l)" -eq "$observed_count"
    record_command "${validation_label}_reported_count_numeric" \
        is_nonnegative_integer "$reported_count"
    record_command "${validation_label}_reported_count_exact" test \
        "$reported_count" = "$observed_count"
    record_command "${validation_label}_reported_failed_numeric" \
        is_nonnegative_integer "$reported_failed"
    record_command "${validation_label}_reported_failed_zero" test \
        "$reported_failed" = 0
    record_command "${validation_label}_first_failure_none" test \
        "$reported_first" = none
    record_command "${validation_label}_false_assertions_absent" test \
        "$(grep -Ec '^action_18c_vrrp_a_remote_assertion_[a-z0-9_]+=false$' \
            "$transcript_path" || true)" -eq 0
    record_command "${validation_label}_before_hash_format" is_sha256 "$before_hash"
    record_command "${validation_label}_after_hash_format" is_sha256 "$after_hash"
    record_command "${validation_label}_state_unchanged" test \
        "$after_hash" = "$before_hash"
    record_command "${validation_label}_role_exact" test \
        "$observed_role" = "$expected_role"
    record_command "${validation_label}_state_exact" test \
        "$observed_state" = "$expected_state"
    record_command "${validation_label}_ipv4_vip_count_exact" test \
        "$observed_ipv4_count" = "$expected_vip_count"
    record_command "${validation_label}_ipv6_vip_count_exact" test \
        "$observed_ipv6_count" = "$expected_vip_count"
    for required_marker in \
        publisher_invoked=false \
        vrrp_mutations=false \
        service_mutations=false \
        synchronization_mutations=false \
        persistent_mutations=false \
        remote_complete=true; do
        record_command "${validation_label}_${required_marker%%=*}_exact" \
            require_one "action_18c_vrrp_a_remote_${required_marker}" \
            "$transcript_path"
    done
}

run_remote() {
    local remote_target=$1
    local remote_alias=$2
    local remote_role=$3
    local stdout_path=$4
    local stderr_path=$5
    local status_name=$6
    local observed_status=0

    ssh -T -o BatchMode=yes -o ClearAllForwardings=yes -o ConnectTimeout=10 \
        -o "HostKeyAlias=$remote_alias" -o StrictHostKeyChecking=yes \
        "$remote_target" "cd / && sudo -n bash -s -- --$remote_role" \
        <"$inspector" >"$stdout_path" 2>"$stderr_path" || observed_status=$?
    printf -v "$status_name" '%s' "$observed_status"
}

write_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_state=$3
    local fixture_vip_count=$4
    local fixture_label

    while IFS= read -r fixture_label; do
        printf 'action_18c_vrrp_a_remote_assertion_%s=true\n' "$fixture_label"
    done < <(extract_source_labels "$inspector") >"$fixture_path"
    printf '%s\n' \
        "action_18c_vrrp_a_remote_value_node_role=$fixture_role" \
        "action_18c_vrrp_a_remote_value_vrrp_state=$fixture_state" \
        "action_18c_vrrp_a_remote_value_ipv4_vip_count=$fixture_vip_count" \
        "action_18c_vrrp_a_remote_value_ipv6_vip_count=$fixture_vip_count" \
        'action_18c_vrrp_a_remote_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111' \
        'action_18c_vrrp_a_remote_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111' \
        "action_18c_vrrp_a_remote_assertion_count=$(extract_source_labels "$inspector" | wc -l)" \
        'action_18c_vrrp_a_remote_failed_assertion_count=0' \
        'action_18c_vrrp_a_remote_first_failure=none' \
        'action_18c_vrrp_a_remote_publisher_invoked=false' \
        'action_18c_vrrp_a_remote_vrrp_mutations=false' \
        'action_18c_vrrp_a_remote_service_mutations=false' \
        'action_18c_vrrp_a_remote_synchronization_mutations=false' \
        'action_18c_vrrp_a_remote_persistent_mutations=false' \
        'action_18c_vrrp_a_remote_remote_complete=true' >>"$fixture_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ -f "$inspector" && ! -L "$inspector" && -x "$inspector" ]]
        [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
        bash -n "$inspector"
        "$collision_checker" "$inspector" "$0" >/dev/null
        "$inspector" --self-test >/dev/null
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
        work_directory=$(mktemp -d /tmp/caddy-action18c-vrrp-a-contract.XXXXXX)
        trap 'rm -rf -- "$work_directory"' EXIT
        : >"$work_directory/empty.err"
        write_fixture "$work_directory/node-a" node-a BACKUP 0
        validate_remote_transcript node_a "$work_directory/node-a" \
            "$work_directory/empty.err" 0 node-a BACKUP 0 >/dev/null
        [[ "$failed_assertion_count" -eq 0 ]]
        printf '%s_false_negative_valid_transcript_accepted=true\n' "$prefix"
        sed '0,/assertion_identity_root=true/s//assertion_identity_root=false/' \
            "$work_directory/node-a" >"$work_directory/false"
        assertion_count=0 failed_assertion_count=0 first_failure=none
        validate_remote_transcript false_case "$work_directory/false" \
            "$work_directory/empty.err" 1 node-a BACKUP 0 >/dev/null
        [[ "$failed_assertion_count" -gt 0 ]]
        printf '%s_false_positive_failed_assertion_rejected=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

[[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
[[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
work_directory=$(mktemp -d /tmp/caddy-action18c-vrrp-a-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
for stream_name in node-a.out node-a.err node-b.out node-b.err; do
    : >"$work_directory/$stream_name"
    chmod 0600 "$work_directory/$stream_name"
done

node_a_status=0
run_remote "$node_a_target" "$node_a_alias" node-a \
    "$work_directory/node-a.out" "$work_directory/node-a.err" node_a_status
emit_stream node_a_stdout "$work_directory/node-a.out"
emit_stream node_a_stderr "$work_directory/node-a.err"
validate_remote_transcript node_a "$work_directory/node-a.out" \
    "$work_directory/node-a.err" "$node_a_status" node-a BACKUP 0

node_b_status=not_run
if [[ "$failed_assertion_count" -eq 0 ]]; then
    node_b_status=0
    run_remote "$node_b_target" "$node_b_alias" node-b \
        "$work_directory/node-b.out" "$work_directory/node-b.err" node_b_status
    emit_stream node_b_stdout "$work_directory/node-b.out"
    emit_stream node_b_stderr "$work_directory/node-b.err"
    validate_remote_transcript node_b "$work_directory/node-b.out" \
        "$work_directory/node-b.err" "$node_b_status" node-b MASTER 1
fi

record_command single_ipv4_vip_owner test \
    "$(value_for action_18c_vrrp_a_remote_value_ipv4_vip_count \
        "$work_directory/node-a.out")" -eq 0
record_command node_b_owns_ipv4_vip test \
    "$(value_for action_18c_vrrp_a_remote_value_ipv4_vip_count \
        "$work_directory/node-b.out" 2>/dev/null || printf invalid)" -eq 1
record_command single_ipv6_vip_owner test \
    "$(value_for action_18c_vrrp_a_remote_value_ipv6_vip_count \
        "$work_directory/node-a.out")" -eq 0
record_command node_b_owns_ipv6_vip test \
    "$(value_for action_18c_vrrp_a_remote_value_ipv6_vip_count \
        "$work_directory/node-b.out" 2>/dev/null || printf invalid)" -eq 1

printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_a_status=%s\n' "$prefix" "$node_a_status"
printf '%s_node_b_status=%s\n' "$prefix" "$node_b_status"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_action_18c_executed=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
if [[ "$failed_assertion_count" -ne 0 ]]; then
    exit 1
fi
printf '%s_eligibility=true\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_workstation_cleanup_complete=true\n' "$prefix"
