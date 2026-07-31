#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17o_b
readonly environment_file=/etc/default/caddy-ha
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly known_hosts="$ssh_dir/known_hosts"
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv4=10.1.0.54
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_fqdn=pihole00.local.theama.co
readonly expected_stdout_bytes=40
readonly expected_stdout_lines=2
readonly expected_stdout_sha256=9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f
readonly expected_line_1_bytes=25
readonly expected_line_1_fields=3
readonly expected_line_1_sha256=22cfede9db41c0993dc68b423c8a7d7e635bf96a9b5fbdf898d52848c31c6365
readonly expected_line_2_bytes=15
readonly expected_line_2_fields=2
readonly expected_line_2_sha256=eba5068def7651e8e469a6d7a6de11b826dd450934ff4600489ef450ea494d49

checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2

    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf '%s_check_%s=true\n' "$action_prefix" "$result_label"
        checks_passed=$((checks_passed + 1))
    else
        printf '%s_check_%s=false\n' "$action_prefix" "$result_label"
        checks_failed=$((checks_failed + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$result_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

peer_nss_ipv4_matches() {
    # shellcheck disable=SC2317
    getent ahostsv4 "$node_b_fqdn" |
        awk '{ print $1 }' |
        grep -Fxq "$node_b_ipv4"
}

peer_nss_ipv6_matches() {
    # shellcheck disable=SC2317
    getent ahostsv6 "$node_b_fqdn" |
        awk '{ print $1 }' |
        grep -Fxq "$node_b_ipv6"
}

relevant_state() {
    stat -c '%n|%U:%G:%a:%s:%i' \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        "$ssh_dir" \
        "$private_key" \
        "$private_key.pub" \
        "$known_hosts" \
        "$environment_file"
    sha256sum \
        "$private_key" \
        "$private_key.pub" \
        "$known_hosts" \
        "$environment_file"
    find \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/quarantine \
        -printf '%p|%y|%U:%G:%m:%s:%i\n' |
        sort
    for state_unit in ssh.service lsyncd.service caddy-lsyncd.service; do
        printf 'unit=%s\n' "$state_unit"
        systemctl show "$state_unit" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$state_unit" 2>/dev/null || true)"
    done
}

# ACTION17O_B_CLASSIFIER_BEGIN
classify_refined_line() {
    local refined_path=$1

    refined_line_bytes=$(wc -c <"$refined_path")
    refined_line_fields=$(awk 'NR == 1 { print NF + 0 }' "$refined_path")
    refined_line_sha256=$(sha256sum "$refined_path" | awk '{ print $1 }')
    refined_line_printable=true
    if ! od -An -tu1 -v "$refined_path" |
        awk '
            {
                for (field = 1; field <= NF; field++) {
                    byte = $field + 0
                    if (byte != 9 && byte != 10 && byte != 13 && (byte < 32 || byte > 126)) {
                        exit 1
                    }
                }
            }
        '; then
        refined_line_printable=false
    fi
    refined_line_secret_free=true
    if grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$refined_path"; then
        refined_line_secret_free=false
    fi
    refined_line_relative_scope=true
    if grep -Eq \
        '(^|[[:space:]])/|(^|[[:space:]])\.\./|/(etc|var|home|root|run|proc|sys)/' \
        "$refined_path"; then
        refined_line_relative_scope=false
    fi

    if [[ "$refined_line_printable" != true ||
        "$refined_line_secret_free" != true ||
        "$refined_line_relative_scope" != true ]]; then
        refined_line_classification=unsafe
    elif awk '
        NR == 1 && NF == 3 &&
        $1 == "created" &&
        $2 == "directory" &&
        $3 == "node-a" &&
        $0 == "created directory node-a" {
            matched = 1
        }
        END { exit matched ? 0 : 1 }
    ' "$refined_path"; then
        refined_line_classification=created_expected_relative_directory
    elif awk '
        NR == 1 && NF == 2 &&
        length($1) == 11 &&
        $2 == "./" {
            matched = 1
        }
        END { exit matched ? 0 : 1 }
    ' "$refined_path"; then
        refined_line_classification=itemized_current_directory
    elif awk '
        NR == 1 && NF == 2 &&
        length($1) == 11 &&
        $2 !~ /^\// &&
        $2 !~ /^\.\.\// {
            matched = 1
        }
        END { exit matched ? 0 : 1 }
    ' "$refined_path"; then
        refined_line_classification=itemized_relative_path
    else
        refined_line_classification=bounded_safe_other
    fi
}
# ACTION17O_B_CLASSIFIER_END

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_stdout_bytes" -eq 40 ]]
    [[ "$expected_stdout_lines" -eq 2 ]]
    [[ "$expected_stdout_sha256" == 9860f687cf32c9f2a700974bfabf3fe65d8b16f3446a6cd12f206853ed68860f ]]
    [[ "$expected_line_1_bytes" -eq 25 ]]
    [[ "$expected_line_2_bytes" -eq 15 ]]
    printf 'action_17o_b_node_a_refinement_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --classifier-test && $# -eq 1 ]]; then
    (
        classifier_dir=$(mktemp -d /tmp/caddy-action17o-b-classifier.XXXXXX)
        trap 'rm -rf -- "$classifier_dir"' EXIT
        printf 'created directory node-a\n' >"$classifier_dir/line-1"
        printf '.d..t...... ./\n' >"$classifier_dir/line-2"
        classify_refined_line "$classifier_dir/line-1"
        [[ "$refined_line_classification" == created_expected_relative_directory ]]
        [[ "$refined_line_sha256" == "$expected_line_1_sha256" ]]
        classify_refined_line "$classifier_dir/line-2"
        [[ "$refined_line_classification" == itemized_current_directory ]]
        [[ "$refined_line_sha256" == "$expected_line_2_sha256" ]]
        printf '/etc/passwd\n' >"$classifier_dir/unsafe"
        classify_refined_line "$classifier_dir/unsafe"
        [[ "$refined_line_classification" == unsafe ]]
    )
    printf 'action_17o_b_node_a_classifier_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--classifier-test]\n' "${0##*/}" >&2
    exit 2
fi

work_dir=$(mktemp -d /tmp/caddy-action17o-b-node-a.XXXXXX)
readonly work_dir
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

record_command identity test "$(id -un)" = caddy-sync
record_command working_directory test "$(pwd -P)" = /
record_command hostname test "$(hostname)" = j1-svpihole0
record_command architecture test "$(dpkg --print-architecture)" = arm64
record_command environment_role \
    grep -Fxq 'NODE_ROLE=node-a' "$environment_file"
record_command environment_node_ipv6 \
    grep -Fxq "NODE_IPV6=$node_a_ipv6" "$environment_file"
record_command environment_peer_ipv4 \
    grep -Fxq "PEER_IPV4=$node_b_ipv4" "$environment_file"
record_command environment_peer_ipv6 \
    grep -Fxq "PEER_IPV6=$node_b_ipv6" "$environment_file"
record_command environment_sync_target \
    grep -Fxq "SYNC_TARGET=$node_b_fqdn" "$environment_file"
record_command peer_hosts_ipv4_exact \
    grep -Fxq "$node_b_ipv4 $node_b_fqdn" /etc/hosts
record_command peer_hosts_ipv6_exact \
    grep -Fxq "$node_b_ipv6 $node_b_fqdn" /etc/hosts
record_command peer_nss_ipv4 peer_nss_ipv4_matches
record_command peer_nss_ipv6 peer_nss_ipv6_matches
record_command private_key_regular test -f "$private_key"
record_command private_key_not_symlink test ! -L "$private_key"
record_command known_hosts_regular test -f "$known_hosts"
record_command lsyncd_inactive \
    test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive

before_state="$work_dir/state-before"
before_state_error="$work_dir/state-before.err"
before_state_status=0
relevant_state >"$before_state" 2>"$before_state_error" ||
    before_state_status=$?
record_command before_state_status test "$before_state_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_state_error"
if [[ "$before_state_status" -eq 0 ]]; then
    before_state_sha256=$(file_hash "$before_state")
else
    before_state_sha256=unavailable
fi
readonly before_state_sha256
printf 'action_17o_b_value_before_state_sha256=%s\n' "$before_state_sha256"

empty_dir="$work_dir/empty"
mkdir -m 0700 -- "$empty_dir"
rsync_output="$work_dir/rsync.out"
rsync_error="$work_dir/rsync.err"
rsync_status=not_run
rsync_attempted=false
: >"$rsync_output"
: >"$rsync_error"

if [[ "$checks_failed" -eq 0 ]]; then
    rsync_attempted=true
    rsync_status=0
    remote_shell="ssh -6 -F /dev/null -b $node_a_ipv6"
    remote_shell+=" -i $private_key -o BatchMode=yes"
    remote_shell+=" -o ClearAllForwardings=yes"
    remote_shell+=" -o GlobalKnownHostsFile=/dev/null"
    remote_shell+=" -o HostKeyAlias=$node_b_fqdn"
    remote_shell+=" -o IdentitiesOnly=yes"
    remote_shell+=" -o KbdInteractiveAuthentication=no"
    remote_shell+=" -o PasswordAuthentication=no"
    remote_shell+=" -o PreferredAuthentications=publickey"
    remote_shell+=" -o StrictHostKeyChecking=yes"
    remote_shell+=" -o UpdateHostKeys=no"
    remote_shell+=" -o UserKnownHostsFile=$known_hosts"
    rsync \
        --archive \
        --dry-run \
        --itemize-changes \
        --rsh="$remote_shell" \
        "$empty_dir/" \
        "caddy-sync@$node_b_fqdn:/node-a/" \
        >"$rsync_output" 2>"$rsync_error" || rsync_status=$?
fi

record_command rsync_attempted test "$rsync_attempted" = true
record_command rsync_dry_run_status test "$rsync_status" -eq 0
record_command rsync_dry_run_stderr_empty test ! -s "$rsync_error"

stdout_bytes=$(wc -c <"$rsync_output")
stdout_lines=$(awk 'END { print NR }' "$rsync_output")
stdout_sha256=$(file_hash "$rsync_output")
readonly stdout_bytes stdout_lines stdout_sha256
record_command stdout_bytes_match_action_17o_a \
    test "$stdout_bytes" -eq "$expected_stdout_bytes"
record_command stdout_lines_match_action_17o_a \
    test "$stdout_lines" -eq "$expected_stdout_lines"
record_command stdout_sha256_match_action_17o_a \
    test "$stdout_sha256" = "$expected_stdout_sha256"

line_1="$work_dir/line-1"
line_2="$work_dir/line-2"
sed -n '1p' "$rsync_output" >"$line_1"
sed -n '2p' "$rsync_output" >"$line_2"

classify_refined_line "$line_1"
line_1_bytes=$refined_line_bytes
line_1_fields=$refined_line_fields
line_1_sha256=$refined_line_sha256
line_1_printable=$refined_line_printable
line_1_secret_free=$refined_line_secret_free
line_1_relative_scope=$refined_line_relative_scope
line_1_classification=$refined_line_classification
readonly line_1_bytes line_1_fields line_1_sha256
readonly line_1_printable line_1_secret_free line_1_relative_scope
readonly line_1_classification

record_command line_1_bytes_expected \
    test "$line_1_bytes" -eq "$expected_line_1_bytes"
record_command line_1_fields_expected \
    test "$line_1_fields" -eq "$expected_line_1_fields"
record_command line_1_sha256_expected \
    test "$line_1_sha256" = "$expected_line_1_sha256"
record_command line_1_printable test "$line_1_printable" = true
record_command line_1_secret_free test "$line_1_secret_free" = true
record_command line_1_relative_scope test "$line_1_relative_scope" = true
record_command line_1_created_expected_relative_directory \
    test "$line_1_classification" = created_expected_relative_directory

classify_refined_line "$line_2"
line_2_bytes=$refined_line_bytes
line_2_fields=$refined_line_fields
line_2_sha256=$refined_line_sha256
line_2_printable=$refined_line_printable
line_2_secret_free=$refined_line_secret_free
line_2_relative_scope=$refined_line_relative_scope
line_2_classification=$refined_line_classification
readonly line_2_bytes line_2_fields line_2_sha256
readonly line_2_printable line_2_secret_free line_2_relative_scope
readonly line_2_classification

record_command line_2_bytes_expected \
    test "$line_2_bytes" -eq "$expected_line_2_bytes"
record_command line_2_fields_expected \
    test "$line_2_fields" -eq "$expected_line_2_fields"
record_command line_2_sha256_expected \
    test "$line_2_sha256" = "$expected_line_2_sha256"
record_command line_2_printable test "$line_2_printable" = true
record_command line_2_secret_free test "$line_2_secret_free" = true
record_command line_2_relative_scope test "$line_2_relative_scope" = true
record_command line_2_itemized_current_directory \
    test "$line_2_classification" = itemized_current_directory
record_command exact_two_line_sequence \
    test "$line_1_classification:$line_2_classification" = \
    created_expected_relative_directory:itemized_current_directory

printf 'action_17o_b_value_rsync_attempted=%s\n' "$rsync_attempted"
printf 'action_17o_b_value_rsync_status=%s\n' "$rsync_status"
printf 'action_17o_b_value_stdout_bytes=%s\n' "$stdout_bytes"
printf 'action_17o_b_value_stdout_lines=%s\n' "$stdout_lines"
printf 'action_17o_b_value_stdout_sha256=%s\n' "$stdout_sha256"
printf 'action_17o_b_value_line_1_bytes=%s\n' "$line_1_bytes"
printf 'action_17o_b_value_line_1_fields=%s\n' "$line_1_fields"
printf 'action_17o_b_value_line_1_sha256=%s\n' "$line_1_sha256"
printf 'action_17o_b_value_line_1_classification=%s\n' \
    "$line_1_classification"
printf 'action_17o_b_value_line_2_bytes=%s\n' "$line_2_bytes"
printf 'action_17o_b_value_line_2_fields=%s\n' "$line_2_fields"
printf 'action_17o_b_value_line_2_sha256=%s\n' "$line_2_sha256"
printf 'action_17o_b_value_line_2_classification=%s\n' \
    "$line_2_classification"
printf 'action_17o_b_value_sequence_classification=%s\n' \
    "$line_1_classification:$line_2_classification"
printf 'action_17o_b_raw_stdout_emitted=false\n'

after_state="$work_dir/state-after"
after_state_error="$work_dir/state-after.err"
after_state_status=0
relevant_state >"$after_state" 2>"$after_state_error" ||
    after_state_status=$?
record_command after_state_status test "$after_state_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_state_error"
if [[ "$after_state_status" -eq 0 ]]; then
    after_state_sha256=$(file_hash "$after_state")
else
    after_state_sha256=unavailable
fi
readonly after_state_sha256
printf 'action_17o_b_value_after_state_sha256=%s\n' "$after_state_sha256"
record_command node_a_state_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"
record_command synchronization_service_still_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive

printf 'action_17o_b_checks_total=%s\n' "$checks_total"
printf 'action_17o_b_checks_passed=%s\n' "$checks_passed"
printf 'action_17o_b_checks_failed=%s\n' "$checks_failed"
printf 'action_17o_b_first_failure=%s\n' "$first_failure"
printf 'action_17o_b_release_payload_transferred=false\n'
printf 'action_17o_b_synchronization_executed=false\n'
printf 'action_17o_b_service_mutations=false\n'
printf 'action_17o_b_persistent_mutations=false\n'

if [[ "$checks_failed" -eq 0 ]]; then
    printf 'action_17o_b_node_a_collection_complete=true\n'
    exit 0
fi

printf 'action_17o_b_node_a_collection_complete=false\n'
exit 1
