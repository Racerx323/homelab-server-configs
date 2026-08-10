#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28h_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-node-b-normal-publisher-rejection-action28h.sh
readonly outer=$caddy_root/scripts/run-node-b-normal-publisher-rejection-action28h-outer.sh
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly action28g_c_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-c-outer.sh
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly action28g_c_outer_sha256=24f7a4fc6e37a5c878fc6cc89f145a1ba3422e773ceabf780ef83f194a99ec8b
readonly expected_rejection='Node B publishing requires --emergency.'

check_count=0
failed_check_count=0
first_failure=none

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

record_check() {
    local action28h_regression_label=$1

    shift
    check_count=$((check_count + 1))
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28h_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28h_regression_label" >&2
    failed_check_count=$((failed_check_count + 1))
    if [[ "$first_failure" == none ]]; then
        first_failure=$action28h_regression_label
    fi
    return 0
}

command_fails() { ! "$@"; }

write_valid_transcript() {
    local action28h_regression_transcript=$1
    local action28h_regression_snapshot=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    sed 's/^/action_28h_node_b_check_/; s/$/=true/' < <("$probe" --expected-checks) \
    >"$action28h_regression_transcript"
    printf '%s\n' \
        'action_28h_node_b_value_publisher_status=1' \
        'action_28h_node_b_value_publisher_stdout_bytes=0' \
        'action_28h_node_b_value_publisher_stdout_lines=0' \
        'action_28h_node_b_value_publisher_stdout_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
        'action_28h_node_b_value_publisher_stdout_classification=bounded_safe' \
        'action_28h_node_b_value_publisher_stderr_bytes=40' \
        'action_28h_node_b_value_publisher_stderr_lines=1' \
        'action_28h_node_b_value_publisher_stderr_sha256=5a0cfb38d9dc7d58f9024dd72eff955e6ea9a881200bf1d16a0ba896a67366b7' \
        'action_28h_node_b_value_publisher_stderr_classification=bounded_safe' \
        "action_28h_node_b_value_publisher_stderr_content=$expected_rejection" \
        "action_28h_node_b_value_before_snapshot_sha256=$action28h_regression_snapshot" \
        "action_28h_node_b_value_after_snapshot_sha256=$action28h_regression_snapshot" \
        'action_28h_node_b_value_before_outbound_entry_count=12' \
        'action_28h_node_b_value_after_outbound_entry_count=12' \
        'action_28h_node_b_value_vrrp_state=BACKUP' \
        "action_28h_node_b_check_count=$("$probe" --expected-checks | wc -l)" \
        'action_28h_node_b_failed_check_count=0' \
        'action_28h_node_b_first_failure=none' \
        'action_28h_node_b_publisher_invoked=true' \
        'action_28h_node_b_emergency_flag_supplied=false' \
        'action_28h_node_b_publication_created=false' \
        'action_28h_node_b_ssh_invoked=false' \
        'action_28h_node_b_rsync_invoked=false' \
        'action_28h_node_b_node_a_contacted=false' \
        'action_28h_node_b_filesystem_mutations=false' \
        'action_28h_node_b_service_mutations=false' \
        'action_28h_node_b_acceptance=true' >>"$action28h_regression_transcript"
}

run_validation() {
    local action28h_regression_transcript=$1
    local action28h_regression_stderr=$2
    local action28h_regression_status=$3

    CADDY_ACTION28H_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28h_regression_transcript" "$action28h_regression_stderr" \
        "$action28h_regression_status"
}

work_directory=$(mktemp -d /tmp/caddy-action28h-regression.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly valid_transcript=$work_directory/valid.transcript
readonly empty_stderr=$work_directory/empty.stderr
: >"$empty_stderr"
write_valid_transcript "$valid_transcript"

record_check publisher_hash_exact test "$(file_hash "$publisher")" = "$publisher_sha256"
record_check action28g_c_outer_immutable test "$(file_hash "$action28g_c_outer")" = \
    "$action28g_c_outer_sha256"
record_check probe_self_test /bin/bash "$probe" --self-test

fixture_source=$work_directory/source
mkdir -m 0700 "$fixture_source"
printf 'sentinel\n' >"$fixture_source/sentinel"
before_fixture_hash=$(file_hash "$fixture_source/sentinel")
publisher_stdout=$work_directory/publisher.stdout
publisher_stderr=$work_directory/publisher.stderr
publisher_status=0
/bin/bash "$publisher" --source "$fixture_source" --node-role node-b \
    >"$publisher_stdout" 2>"$publisher_stderr" || publisher_status=$?
record_check real_publisher_status_rejected test "$publisher_status" -eq 1
record_check real_publisher_stdout_empty test ! -s "$publisher_stdout"
record_check real_publisher_stderr_exact test "$(cat "$publisher_stderr")" = "$expected_rejection"
record_check real_publisher_fixture_unchanged test "$(file_hash "$fixture_source/sentinel")" = \
    "$before_fixture_hash"
record_check real_publisher_fixture_entry_count test \
    "$(find "$fixture_source" -mindepth 1 -maxdepth 1 -print | wc -l)" -eq 1

# Exact literal source is intentional for the production-order assertion.
# shellcheck disable=SC2016
role_gate_line=$(grep -n 'if \[\[ "$node_role" == node-b \]\]; then' "$publisher" |
    cut -d: -f1)
source_validation_line=$(grep -n 'for required_path in' "$publisher" | cut -d: -f1)
outbound_line=$(grep -n 'readonly outbound_root=' "$publisher" | cut -d: -f1)
record_check role_gate_precedes_source_validation test "$role_gate_line" -lt "$source_validation_line"
record_check role_gate_precedes_outbound_path test "$role_gate_line" -lt "$outbound_line"
record_check normal_probe_omits_emergency command_fails grep -Fq -- \
    '--node-role node-b --emergency' "$probe"
record_check probe_ssh_command_absent command_fails grep -Eq \
    '^[[:space:]]*ssh[[:space:]]' "$probe"
record_check probe_rsync_command_absent command_fails grep -Eq \
    '^[[:space:]]*rsync[[:space:]]' "$probe"
record_check valid_transcript_accepted run_validation "$valid_transcript" "$empty_stderr" 0

false_transcript=$work_directory/false.transcript
sed '0,/_check_identity_root=true/s//_check_identity_root=false/' \
    "$valid_transcript" >"$false_transcript"
record_check false_assertion_rejected command_fails run_validation \
    "$false_transcript" "$empty_stderr" 1

wrong_rejection=$work_directory/wrong-rejection.transcript
sed "s/$expected_rejection/Node B publishing was accepted./" \
    "$valid_transcript" >"$wrong_rejection"
record_check altered_rejection_rejected command_fails run_validation \
    "$wrong_rejection" "$empty_stderr" 0

changed_snapshot=$work_directory/changed-snapshot.transcript
sed 's/action_28h_node_b_value_after_snapshot_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/action_28h_node_b_value_after_snapshot_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' \
    "$valid_transcript" >"$changed_snapshot"
record_check changed_snapshot_rejected command_fails run_validation \
    "$changed_snapshot" "$empty_stderr" 0

publication_true=$work_directory/publication-true.transcript
sed 's/action_28h_node_b_publication_created=false/action_28h_node_b_publication_created=true/' \
    "$valid_transcript" >"$publication_true"
record_check publication_claim_rejected command_fails run_validation \
    "$publication_true" "$empty_stderr" 0

printf 'unexpected stderr\n' >"$work_directory/nonempty.stderr"
record_check nonempty_stderr_rejected command_fails run_validation \
    "$valid_transcript" "$work_directory/nonempty.stderr" 0
record_check nonzero_status_rejected command_fails run_validation \
    "$valid_transcript" "$empty_stderr" 255

fake_ssh=$work_directory/fake-ssh
# Exact literals are the generated fixture script body.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    ': "${CADDY_ACTION28H_FAKE_TRANSCRIPT:?}"' \
    ': "${CADDY_ACTION28H_FAKE_LOG:?}"' \
    'printf "%s\n" "$*" >>"$CADDY_ACTION28H_FAKE_LOG"' \
    'cat >/dev/null' \
    'cat "$CADDY_ACTION28H_FAKE_TRANSCRIPT"' >"$fake_ssh"
chmod 0755 "$fake_ssh"
production_stdout=$work_directory/production.stdout
production_stderr=$work_directory/production.stderr
production_status=0
CADDY_ACTION28H_TEST_MODE=1 \
    CADDY_ACTION28H_SSH_PROGRAM="$fake_ssh" \
    CADDY_ACTION28H_FAKE_TRANSCRIPT="$valid_transcript" \
    CADDY_ACTION28H_FAKE_LOG="$work_directory/ssh.log" \
    /bin/bash "$outer" >"$production_stdout" 2>"$production_stderr" ||
    production_status=$?
record_check intercepted_production_status_zero test "$production_status" -eq 0
record_check intercepted_production_stderr_empty test ! -s "$production_stderr"
record_check intercepted_production_one_ssh test \
    "$(wc -l <"$work_directory/ssh.log")" -eq 1
record_check intercepted_production_node_b_only grep -Fq 'pi@10.1.0.54' \
    "$work_directory/ssh.log"
record_check intercepted_production_node_a_absent command_fails grep -Fq '10.1.0.53' \
    "$work_directory/ssh.log"
record_check intercepted_production_acceptance grep -Fqx \
    'action_28h_outer_acceptance=true' "$production_stdout"

printf '%s_check_count=%s\n' "$prefix" "$check_count"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_real_publisher_path_exercised=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"

if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
