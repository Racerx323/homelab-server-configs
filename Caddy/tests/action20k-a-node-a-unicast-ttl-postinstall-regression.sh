#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_a_regression
readonly inspector_sha256=d8bc0a25b003f5803c90624d3e2d2b4b2387cc78d161e93ce0b747a68fdda137
readonly outer_sha256=11fb1a00159e39cf7b7aec7923efafb7e1f398a208d8ad474686ca2449b312ef
readonly expected_check_count=61
readonly expected_backup=/var/backups/caddy-ha/action20k-node-a-unicast-ttl.5YRfcn
readonly expected_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly fixture_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector=$caddy_root/scripts/inspect-node-a-unicast-ttl-postinstall-action20k-a.sh
readonly outer=$caddy_root/scripts/run-node-a-unicast-ttl-postinstall-action20k-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_gate() {
    local action20ka_regression_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20ka_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20ka_regression_gate_label" >&2
    return 1
}
write_valid_transcript() {
    local action20ka_regression_output=$1
    local action20ka_regression_label

    {
        while IFS= read -r action20ka_regression_label; do
            printf 'action_20k_a_check_%s=true\n' "$action20ka_regression_label"
        done < <(/bin/bash "$inspector" --expected-checks)
        printf '%s\n' \
            "action_20k_a_value_expected_check_count=$expected_check_count" \
            "action_20k_a_value_backup_path=$expected_backup" \
            "action_20k_a_value_fragment_sha256=$expected_fragment_sha256" \
            "action_20k_a_value_before_state_sha256=$fixture_state_sha256" \
            "action_20k_a_value_after_state_sha256=$fixture_state_sha256" \
            "action_20k_a_check_count=$expected_check_count" \
            'action_20k_a_failed_check_count=0' \
            'action_20k_a_first_failure=none' \
            'action_20k_a_helper_execution=false' \
            'action_20k_a_filesystem_mutations=false' \
            'action_20k_a_service_mutations=false' \
            'action_20k_a_vrrp_mutations=false' \
            'action_20k_a_vip_mutations=false' \
            'action_20k_a_node_b_contacted=false' \
            'action_20k_a_remote_complete=true'
    } >"$action20ka_regression_output"
}
run_intercepted_case() {
    local action20ka_regression_case_root=$1
    local action20ka_regression_transcript=$2
    local action20ka_regression_remote_status=$3
    local action20ka_regression_expected_status=$4
    local action20ka_regression_stderr_content=${5:-}
    local action20ka_regression_fake_ssh=$action20ka_regression_case_root/fake-ssh
    local action20ka_regression_observed_status=0

    install -d -m 0700 "$action20ka_regression_case_root" || return 1
    # The generated fake transport expands these variables at runtime.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"${ACTION20KA_STDIN_CAPTURE:?}"' \
        'printf "%s\n" "$*" >"${ACTION20KA_ARGS_CAPTURE:?}"' \
        'cat "${ACTION20KA_TRANSCRIPT:?}"' \
        'if [[ -n "${ACTION20KA_STDERR_CONTENT:-}" ]]; then' \
        '    printf "%s\n" "$ACTION20KA_STDERR_CONTENT" >&2' \
        'fi' \
        'exit "${ACTION20KA_REMOTE_STATUS:?}"' >"$action20ka_regression_fake_ssh" || return 1
    chmod 0700 "$action20ka_regression_fake_ssh" || return 1
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20KA_TEST_MODE=1 \
            CADDY_ACTION20KA_SSH_BINARY="$action20ka_regression_fake_ssh" \
            ACTION20KA_STDIN_CAPTURE="$action20ka_regression_case_root/stdin" \
            ACTION20KA_ARGS_CAPTURE="$action20ka_regression_case_root/args" \
            ACTION20KA_TRANSCRIPT="$action20ka_regression_transcript" \
            ACTION20KA_STDERR_CONTENT="$action20ka_regression_stderr_content" \
            ACTION20KA_REMOTE_STATUS="$action20ka_regression_remote_status" \
            /bin/bash "$outer" --test-transport
    ) >"$action20ka_regression_case_root/stdout" \
        2>"$action20ka_regression_case_root/stderr" ||
        action20ka_regression_observed_status=$?
    [[ "$action20ka_regression_observed_status" -eq "$action20ka_regression_expected_status" ]] || return 1
    [[ "$(file_hash "$action20ka_regression_case_root/stdin")" = "$inspector_sha256" ]] || return 1
    grep -Fq -- '-T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes pi@10.1.0.53 cd / && sudo -n /bin/bash -s --' \
        "$action20ka_regression_case_root/args" || return 1
    ! grep -Fq '10.1.0.54' "$action20ka_regression_case_root/args" || return 1
}
production_label_alignment() {
    local action20ka_regression_root=$1

    /bin/bash "$inspector" --expected-checks >"$action20ka_regression_root/expected" || return 1
    awk '$1 == "record_check" { print $2 }' "$inspector" \
        >"$action20ka_regression_root/static" || return 1
    [[ "$(wc -l <"$action20ka_regression_root/expected")" -eq "$expected_check_count" ]] || return 1
    [[ "$(wc -l <"$action20ka_regression_root/static")" -eq "$expected_check_count" ]] || return 1
    diff -u "$action20ka_regression_root/expected" \
        "$action20ka_regression_root/static" >/dev/null
}
regression_root=$(mktemp -d /tmp/caddy-action20k-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly valid_transcript=$regression_root/valid.transcript
write_valid_transcript "$valid_transcript"

record_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
record_gate outer_hash_exact test "$(file_hash "$outer")" = "$outer_sha256"
record_gate syntax /bin/bash -n "$0" "$inspector" "$outer"
record_gate inspector_self_test /bin/bash "$inspector" --self-test
record_gate production_label_alignment production_label_alignment "$regression_root"
# The child Bash expands its positional parameter.
# shellcheck disable=SC2016
record_gate node_b_ssh_target_absent bash -c \
    '! grep -Fq "pi@10.1.0.54" "$1"' _ "$outer"
# shellcheck disable=SC2016
record_gate node_b_hostname_absent bash -c \
    '! grep -Fq "j1-svpihole00" "$1"' _ "$inspector"
# shellcheck disable=SC2016
record_gate service_and_vip_mutation_commands_absent bash -c \
    '! grep -Eq "systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)" "$1"' \
    _ "$inspector"
record_gate helper_execution_false_marker_present grep -Fq \
    "printf '%s_helper_execution=false" "$inspector"
record_gate filesystem_mutations_false_marker_present grep -Fq \
    "printf '%s_filesystem_mutations=false" "$inspector"
record_gate node_b_contacted_false_marker_present grep -Fq \
    "printf '%s_node_b_contacted=false" "$inspector"
record_gate valid_transcript_line_count test "$(wc -l <"$valid_transcript")" -eq 76
record_gate valid_production_path run_intercepted_case \
    "$regression_root/valid" "$valid_transcript" 0 0

cp -- "$valid_transcript" "$regression_root/false.transcript"
sed -i 's/action_20k_a_check_fragment_hash_exact=true/action_20k_a_check_fragment_hash_exact=false/' \
    "$regression_root/false.transcript"
record_gate false_assertion_rejected run_intercepted_case \
    "$regression_root/false" "$regression_root/false.transcript" 0 97

grep -Fv 'action_20k_a_check_fragment_hash_exact=true' "$valid_transcript" \
    >"$regression_root/missing.transcript"
record_gate missing_assertion_rejected run_intercepted_case \
    "$regression_root/missing" "$regression_root/missing.transcript" 0 97

cp -- "$valid_transcript" "$regression_root/duplicate.transcript"
printf '%s\n' 'action_20k_a_check_fragment_hash_exact=true' \
    >>"$regression_root/duplicate.transcript"
record_gate duplicate_assertion_rejected run_intercepted_case \
    "$regression_root/duplicate" "$regression_root/duplicate.transcript" 0 97

awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
    "$valid_transcript" >"$regression_root/reordered.transcript"
record_gate reordered_assertion_rejected run_intercepted_case \
    "$regression_root/reordered" "$regression_root/reordered.transcript" 0 97

sed "s/action_20k_a_value_after_state_sha256=$fixture_state_sha256/action_20k_a_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" \
    "$valid_transcript" >"$regression_root/changed-state.transcript"
record_gate changed_state_rejected run_intercepted_case \
    "$regression_root/changed-state" "$regression_root/changed-state.transcript" 0 97

record_gate stderr_rejected run_intercepted_case \
    "$regression_root/stderr" "$valid_transcript" 0 97 bounded-safe-error
record_gate nonzero_status_preserved run_intercepted_case \
    "$regression_root/status" "$valid_transcript" 7 7

printf '%s_false_negative_valid_production_transcript_accepted=true\n' "$prefix"
printf '%s_false_positive_false_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_reordered_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_changed_state_rejected=true\n' "$prefix"
printf '%s_false_positive_stderr_rejected=true\n' "$prefix"
printf '%s_false_negative_nonzero_status_preserved=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
