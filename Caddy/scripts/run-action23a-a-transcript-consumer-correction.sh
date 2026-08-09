#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a_consumer_correction
readonly inspector_sha256=f348010dc1de51317cf49047ef52cfc2122a5f3c0624ea848c2be22e6cf4399b
readonly outer_sha256=25c4f430edd1bb0fee0ff636e14a6844dd2fe80a12f57643a0d1bd368f34a50e
readonly captured_stdout_sha256=98c0d305f35b0b6d8bb849cd40abcce416ecdc159be0a4059e33cc6561ff3021
readonly captured_stdout_bytes=5790
readonly captured_stdout_lines=114
readonly captured_stderr_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly captured_status=0
readonly observed_state_sha256=20805a7caa251b6263112a245e1e6b5acb67a3a94a0156ba96574cbd511fd85a
readonly installed_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly missing_label=unbound_configuration_valid
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly inspector=$script_directory/inspect-node-b-unbound-a-records-post-action23a-a.sh
readonly outer=$script_directory/run-node-b-unbound-a-records-post-action23a-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
record_check() {
    local action23aa_consumer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23aa_consumer_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23aa_consumer_label" >&2
    return 1
}
safe_stream() {
    local action23aa_consumer_stream=$1

    [[ "$(wc -c <"$action23aa_consumer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action23aa_consumer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action23aa_consumer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action23aa_consumer_stream"
}
emit_stream() {
    local action23aa_consumer_stream_label=$1
    local action23aa_consumer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action23aa_consumer_stream_label" "$(wc -c <"$action23aa_consumer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action23aa_consumer_stream_label" "$(line_count "$action23aa_consumer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action23aa_consumer_stream_label" "$(file_hash "$action23aa_consumer_stream")"
    if safe_stream "$action23aa_consumer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action23aa_consumer_stream_label"
        if [[ -s "$action23aa_consumer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action23aa_consumer_stream_label"
            cat "$action23aa_consumer_stream"
            printf '%s_%s_end\n' "$prefix" "$action23aa_consumer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action23aa_consumer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action23aa_consumer_stream_label" >&2
    return 97
}
require_one() {
    local action23aa_consumer_line=$1
    local action23aa_consumer_file=$2

    [[ "$(grep -Fxc "$action23aa_consumer_line" "$action23aa_consumer_file" || true)" -eq 1 ]]
}
build_captured_fixture() {
    local action23aa_consumer_fixture=$1

    /bin/bash "$inspector" --contract-transcript |
        awk -v observed_state="$observed_state_sha256" '
            {
                if ($0 == "action_23a_a_check_unbound_configuration_valid=true") next
                gsub(/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/, observed_state)
                print
                if ($0 == "action_23a_a_check_direct_proxy_a_answer_exact=true") print "action_23a_a_value_direct_proxy_a_answer=10.1.0.56"
                if ($0 == "action_23a_a_check_direct_admin_a_answer_exact=true") print "action_23a_a_value_direct_admin_a_answer=10.1.0.56"
                if ($0 == "action_23a_a_check_local_proxy_a_answer_exact=true") print "action_23a_a_value_local_proxy_a_answer=10.1.0.56"
                if ($0 == "action_23a_a_check_local_admin_a_answer_exact=true") print "action_23a_a_value_local_admin_a_answer=10.1.0.56"
                if ($0 == "action_23a_a_check_direct_pihole_a_answer_exact=true") print "action_23a_a_value_direct_pihole_a_answer=10.1.0.55"
                if ($0 == "action_23a_a_check_direct_pihole_aaaa_answer_exact=true") print "action_23a_a_value_direct_pihole_aaaa_answer=fd36:5aa8:6971:1::55"
                if ($0 == "action_23a_a_check_direct_pihole_ptr4_answer_exact=true") print "action_23a_a_value_direct_pihole_ptr4_answer=pihole.local.theama.co."
                if ($0 == "action_23a_a_check_local_pihole_a_answer_exact=true") print "action_23a_a_value_local_pihole_a_answer=10.1.0.55"
                if ($0 == "action_23a_a_check_local_pihole_aaaa_answer_exact=true") print "action_23a_a_value_local_pihole_aaaa_answer=fd36:5aa8:6971:1::55"
                if ($0 == "action_23a_a_check_local_pihole_ptr4_answer_exact=true") print "action_23a_a_value_local_pihole_ptr4_answer=pihole.local.theama.co."
            }
        ' >"$action23aa_consumer_fixture"
}
validate_source_boundary() {
    local action23aa_consumer_home_line
    local action23aa_consumer_parser_line
    local action23aa_consumer_backup_line

    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$outer")" == "$outer_sha256" ]] || return 1
    # The literal verifies that the historical source references its own variable.
    # shellcheck disable=SC2016
    grep -Fqx 'record_check unbound_configuration_valid unbound-checkconf "$live_root" >/dev/null || exit 1' "$inspector" || return 1
    action23aa_consumer_home_line=$(grep -nF 'record_check local_zone_homeassistant_absent ' "$inspector" | awk -F: 'NR == 1 { print $1 }') || return 1
    action23aa_consumer_parser_line=$(grep -nF 'record_check unbound_configuration_valid ' "$inspector" | awk -F: 'NR == 1 { print $1 }') || return 1
    action23aa_consumer_backup_line=$(grep -nF 'record_check backup_directory_metadata ' "$inspector" | awk -F: 'NR == 1 { print $1 }') || return 1
    [[ "$action23aa_consumer_home_line" -lt "$action23aa_consumer_parser_line" ]] || return 1
    [[ "$action23aa_consumer_parser_line" -lt "$action23aa_consumer_backup_line" ]]
}
validate_captured_fixture() {
    local action23aa_consumer_fixture=$1
    local action23aa_consumer_root=$2
    local action23aa_consumer_expected=$action23aa_consumer_root/expected.checks
    local action23aa_consumer_actual=$action23aa_consumer_root/actual.checks
    local action23aa_consumer_missing=$action23aa_consumer_root/missing.checks
    local action23aa_consumer_unexpected=$action23aa_consumer_root/unexpected.checks

    [[ "$(wc -c <"$action23aa_consumer_fixture")" -eq "$captured_stdout_bytes" ]] || return 1
    [[ "$(line_count "$action23aa_consumer_fixture")" -eq "$captured_stdout_lines" ]] || return 1
    [[ "$(file_hash "$action23aa_consumer_fixture")" == "$captured_stdout_sha256" ]] || return 1
    safe_stream "$action23aa_consumer_fixture" || return 1
    /bin/bash "$inspector" --expected-checks >"$action23aa_consumer_expected" || return 1
    sed -n 's/^action_23a_a_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action23aa_consumer_fixture" >"$action23aa_consumer_actual" || return 1
    [[ "$(line_count "$action23aa_consumer_expected")" -eq 93 ]] || return 1
    [[ "$(line_count "$action23aa_consumer_actual")" -eq 92 ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action23aa_consumer_actual" | wc -l)" -eq 92 ]] || return 1
    comm -23 <(LC_ALL=C sort "$action23aa_consumer_expected") \
        <(LC_ALL=C sort "$action23aa_consumer_actual") >"$action23aa_consumer_missing" || return 1
    comm -13 <(LC_ALL=C sort "$action23aa_consumer_expected") \
        <(LC_ALL=C sort "$action23aa_consumer_actual") >"$action23aa_consumer_unexpected" || return 1
    [[ "$(line_count "$action23aa_consumer_missing")" -eq 1 ]] || return 1
    grep -Fqx "$missing_label" "$action23aa_consumer_missing" || return 1
    [[ ! -s "$action23aa_consumer_unexpected" ]] || return 1
    require_one 'action_23a_a_check_count=93' "$action23aa_consumer_fixture" || return 1
    require_one 'action_23a_a_failed_check_count=0' "$action23aa_consumer_fixture" || return 1
    require_one 'action_23a_a_first_failure=none' "$action23aa_consumer_fixture" || return 1
    require_one "action_23a_a_value_before_state_sha256=$observed_state_sha256" "$action23aa_consumer_fixture" || return 1
    require_one "action_23a_a_value_after_state_sha256=$observed_state_sha256" "$action23aa_consumer_fixture" || return 1
    require_one "action_23a_a_value_local_zone_sha256=$installed_sha256" "$action23aa_consumer_fixture" || return 1
    require_one 'action_23a_a_remote_complete=true' "$action23aa_consumer_fixture" || return 1
}
correct_transcript() {
    local action23aa_consumer_fixture=$1
    local action23aa_consumer_corrected=$2

    awk '
        { print }
        $0 == "action_23a_a_check_local_zone_homeassistant_absent=true" {
            print "action_23a_a_check_unbound_configuration_valid=true"
            inserted++
        }
        END { if (inserted != 1) exit 42 }
    ' "$action23aa_consumer_fixture" >"$action23aa_consumer_corrected"
}
consume_fixture() {
    local action23aa_consumer_fixture=$1
    local action23aa_consumer_root=$2
    local action23aa_consumer_corrected=$action23aa_consumer_root/corrected.stdout
    local action23aa_consumer_empty_stderr=$action23aa_consumer_root/captured.stderr
    local action23aa_consumer_validator_stdout=$action23aa_consumer_root/validator.stdout
    local action23aa_consumer_validator_stderr=$action23aa_consumer_root/validator.stderr
    local action23aa_consumer_validator_status=0

    : >"$action23aa_consumer_empty_stderr"
    record_check source_boundary_exact validate_source_boundary || return 1
    record_check captured_status_zero test "$captured_status" -eq 0 || return 1
    record_check captured_stderr_hash_empty test \
        "$(file_hash "$action23aa_consumer_empty_stderr")" = "$captured_stderr_sha256" || return 1
    record_check captured_fixture_exact validate_captured_fixture \
        "$action23aa_consumer_fixture" "$action23aa_consumer_root" || return 1
    record_check corrected_transcript_create correct_transcript \
        "$action23aa_consumer_fixture" "$action23aa_consumer_corrected" || return 1
    record_check corrected_check_count test \
        "$(sed -n 's/^action_23a_a_check_[a-z0-9_]*=true$/x/p' "$action23aa_consumer_corrected" | wc -l)" -eq 93 || return 1
    if CADDY_ACTION23AA_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action23aa_consumer_corrected" "$action23aa_consumer_empty_stderr" 0 \
        >"$action23aa_consumer_validator_stdout" 2>"$action23aa_consumer_validator_stderr"; then
        action23aa_consumer_validator_status=0
    else
        action23aa_consumer_validator_status=$?
    fi
    record_check validator_status_zero test "$action23aa_consumer_validator_status" -eq 0 || return 1
    record_check validator_stderr_empty test ! -s "$action23aa_consumer_validator_stderr" || return 1
    record_check validator_complete require_one \
        'action_23a_a_outer_test_validation_complete=true' "$action23aa_consumer_validator_stdout" || return 1
    emit_stream validator_stdout "$action23aa_consumer_validator_stdout" || return 1
    emit_stream validator_stderr "$action23aa_consumer_validator_stderr" || return 1
}
cleanup() {
    local action23aa_consumer_cleanup_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action23aa_consumer_cleanup_status"
}

mode=${1:-execute}
case "$mode" in
    execute) [[ $# -eq 0 ]] ;;
    --self-test) [[ $# -eq 1 ]] ;;
    --build-fixture) [[ $# -eq 2 && "${CADDY_ACTION23AA_CONSUMER_TEST_MODE:-}" == 1 ]] ;;
    --test-fixture) [[ $# -eq 2 && "${CADDY_ACTION23AA_CONSUMER_TEST_MODE:-}" == 1 ]] ;;
    *) exit 64 ;;
esac

if [[ "$mode" == --build-fixture ]]; then
    build_captured_fixture "$2"
    exit 0
fi
work_root=$(mktemp -d /tmp/caddy-action23a-a-consumer.XXXXXX)
readonly work_root
trap cleanup EXIT
if [[ "$mode" == --test-fixture ]]; then
    fixture=$2
else
    fixture=$work_root/captured.stdout
    build_captured_fixture "$fixture"
fi
readonly fixture
consume_fixture "$fixture" "$work_root"
printf '%s_captured_stdout_sha256=%s\n' "$prefix" "$captured_stdout_sha256"
printf '%s_missing_label=%s\n' "$prefix" "$missing_label"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23a_rerun=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
if [[ "$mode" == execute ]]; then
    printf '%s_action_executed=true\n' "$prefix"
else
    printf '%s_action_executed=false\n' "$prefix"
fi
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
