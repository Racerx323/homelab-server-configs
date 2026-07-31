#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17o_a
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly private_key="$ssh_dir/id_ed25519"
readonly known_hosts="$ssh_dir/known_hosts"
readonly environment_file=/etc/default/caddy-ha
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_ipv4=10.1.0.54
readonly node_b_ipv6=fd36:5aa8:6971:1::54
readonly node_b_fqdn=pihole00.local.theama.co
readonly maximum_stdout_bytes=4096
readonly maximum_stdout_lines=20

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

# ACTION17O_A_CLASSIFIER_BEGIN
classify_rsync_stdout() {
    local classification_path=$1
    local classification_nonempty_lines
    local classification_current_directory_lines
    local classification_itemized_lines

    classified_stdout_bytes=$(wc -c <"$classification_path")
    classified_stdout_lines=$(awk 'END { print NR }' "$classification_path")
    classified_stdout_sha256=$(
        sha256sum "$classification_path" | awk '{ print $1 }'
    )
    classified_stdout_printable=true
    if ! od -An -tu1 -v "$classification_path" |
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
        classified_stdout_printable=false
    fi
    classified_stdout_secret_free=true
    if grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|DOPPLER_TOKEN|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=' \
        "$classification_path"; then
        classified_stdout_secret_free=false
    fi
    classified_stdout_path_scope_safe=true
    if grep -Eq \
        '(^|[[:space:]])/|(^|[[:space:]])\.\./|/(etc|var|home|root|run|proc|sys)/' \
        "$classification_path"; then
        classified_stdout_path_scope_safe=false
    fi
    classified_stdout_bounded=true
    if [[ "$classified_stdout_bytes" -gt 4096 ||
        "$classified_stdout_lines" -gt 20 ]]; then
        classified_stdout_bounded=false
    fi

    classification_nonempty_lines=$(
        awk 'NF { count++ } END { print count + 0 }' "$classification_path"
    )
    classification_current_directory_lines=$(
        awk '
            NF {
                if (NF == 2 && length($1) == 11 && $2 == "./") {
                    count++
                }
            }
            END { print count + 0 }
        ' "$classification_path"
    )
    classification_itemized_lines=$(
        awk '
            NF {
                separator = index($0, " ")
                if (separator == 12 && length(substr($0, 1, separator - 1)) == 11) {
                    count++
                }
            }
            END { print count + 0 }
        ' "$classification_path"
    )

    if [[ "$classified_stdout_printable" != true ||
        "$classified_stdout_secret_free" != true ||
        "$classified_stdout_path_scope_safe" != true ||
        "$classified_stdout_bounded" != true ]]; then
        classified_stdout_classification=unsafe
    elif [[ "$classified_stdout_bytes" -eq 0 ]]; then
        classified_stdout_classification=empty
    elif [[ "$classification_nonempty_lines" -eq "$classification_current_directory_lines" ]]; then
        classified_stdout_classification=itemized_current_directory_only
    elif [[ "$classification_nonempty_lines" -eq "$classification_itemized_lines" ]]; then
        classified_stdout_classification=itemized_relative_paths
    else
        classified_stdout_classification=bounded_safe_other
    fi
}
# ACTION17O_A_CLASSIFIER_END

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$node_b_ipv4" == 10.1.0.54 ]]
    [[ "$node_b_ipv6" == fd36:5aa8:6971:1::54 ]]
    [[ "$node_b_fqdn" == pihole00.local.theama.co ]]
    [[ "$maximum_stdout_bytes" -eq 4096 ]]
    [[ "$maximum_stdout_lines" -eq 20 ]]
    printf 'action_17o_a_node_a_diagnostic_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --classifier-test && $# -eq 1 ]]; then
    (
        classifier_dir=$(mktemp -d /tmp/caddy-action17o-a-classifier.XXXXXX)
        trap 'rm -rf -- "$classifier_dir"' EXIT
        : >"$classifier_dir/empty"
        classify_rsync_stdout "$classifier_dir/empty"
        if [[ "$classified_stdout_classification" != empty ]]; then
            exit 1
        fi
        printf '.d..t...... ./\n' >"$classifier_dir/itemized"
        classify_rsync_stdout "$classifier_dir/itemized"
        if [[ "$classified_stdout_classification" != itemized_current_directory_only ]]; then
            exit 1
        fi
        printf '/etc/passwd\n' >"$classifier_dir/unsafe"
        classify_rsync_stdout "$classifier_dir/unsafe"
        if [[ "$classified_stdout_classification" != unsafe ]]; then
            exit 1
        fi
    )
    printf 'action_17o_a_node_a_classifier_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--classifier-test]\n' "${0##*/}" >&2
    exit 2
fi

work_dir=$(mktemp -d /tmp/caddy-action17o-a-node-a.XXXXXX)
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
printf 'action_17o_a_value_before_state_sha256=%s\n' "$before_state_sha256"

empty_dir="$work_dir/empty"
mkdir -m 0700 -- "$empty_dir"
rsync_output="$work_dir/rsync.out"
rsync_error="$work_dir/rsync.err"
rsync_status=not_run
rsync_attempted=false

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
    record_command rsync_dry_run_status test "$rsync_status" -eq 0
    record_command rsync_dry_run_stderr_empty test ! -s "$rsync_error"
    classify_rsync_stdout "$rsync_output"
    record_command stdout_printable \
        test "$classified_stdout_printable" = true
    record_command stdout_secret_free \
        test "$classified_stdout_secret_free" = true
    record_command stdout_path_scope_safe \
        test "$classified_stdout_path_scope_safe" = true
    record_command stdout_bounded \
        test "$classified_stdout_bounded" = true
    record_command stdout_classification_safe \
        test "$classified_stdout_classification" != unsafe
else
    : >"$rsync_output"
    : >"$rsync_error"
    classify_rsync_stdout "$rsync_output"
fi

printf 'action_17o_a_value_rsync_attempted=%s\n' "$rsync_attempted"
printf 'action_17o_a_value_rsync_status=%s\n' "$rsync_status"
printf 'action_17o_a_value_stdout_bytes=%s\n' "$classified_stdout_bytes"
printf 'action_17o_a_value_stdout_lines=%s\n' "$classified_stdout_lines"
printf 'action_17o_a_value_stdout_sha256=%s\n' \
    "$classified_stdout_sha256"
printf 'action_17o_a_value_stdout_classification=%s\n' \
    "$classified_stdout_classification"
printf 'action_17o_a_raw_stdout_emitted=false\n'

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
printf 'action_17o_a_value_after_state_sha256=%s\n' "$after_state_sha256"
record_command node_a_state_unchanged \
    test "$after_state_sha256" = "$before_state_sha256"
record_command synchronization_service_inactive \
    test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
    inactive

printf 'action_17o_a_checks_total=%s\n' "$checks_total"
printf 'action_17o_a_checks_passed=%s\n' "$checks_passed"
printf 'action_17o_a_checks_failed=%s\n' "$checks_failed"
printf 'action_17o_a_first_failure=%s\n' "$first_failure"
printf 'action_17o_a_release_payload_transferred=false\n'
printf 'action_17o_a_synchronization_executed=false\n'
printf 'action_17o_a_service_mutations=false\n'
printf 'action_17o_a_persistent_mutations=false\n'

if [[ "$checks_failed" -eq 0 ]]; then
    printf 'action_17o_a_node_a_collection_complete=true\n'
    exit 0
fi

printf 'action_17o_a_node_a_collection_complete=false\n'
exit 1
