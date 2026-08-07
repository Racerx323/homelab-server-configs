#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_b_regression
readonly inspector_sha256=414f6ada4119863c9575dbec017af9d640434bd2ee4ba11a5875ce5945f61a0d
readonly outer_sha256=dbaa0d330d10868eab157f7528b0e23bee1449adc983a44f1785b3102f10aaa6
readonly expected_check_count=61
readonly expected_backup=/var/backups/caddy-ha/action20k-node-b-unicast-ttl.JcpMAl
readonly expected_fragment_sha256=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
readonly fixture_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector=$caddy_root/scripts/inspect-node-b-unicast-ttl-postinstall-action20k-b.sh
readonly outer=$caddy_root/scripts/run-node-b-unicast-ttl-postinstall-action20k-b-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_gate() {
    local action20kb_regression_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20kb_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20kb_regression_gate_label" >&2
    return 1
}
write_valid_transcript() {
    local action20kb_regression_output=$1
    local action20kb_regression_label

    {
        while IFS= read -r action20kb_regression_label; do
            printf 'action_20k_b_check_%s=true\n' "$action20kb_regression_label"
        done < <(/bin/bash "$inspector" --expected-checks)
        printf '%s\n' \
            "action_20k_b_value_expected_check_count=$expected_check_count" \
            "action_20k_b_value_backup_path=$expected_backup" \
            "action_20k_b_value_fragment_sha256=$expected_fragment_sha256" \
            "action_20k_b_value_before_state_sha256=$fixture_state_sha256" \
            "action_20k_b_value_after_state_sha256=$fixture_state_sha256" \
            "action_20k_b_check_count=$expected_check_count" \
            'action_20k_b_failed_check_count=0' \
            'action_20k_b_first_failure=none' \
            'action_20k_b_helper_execution=false' \
            'action_20k_b_filesystem_mutations=false' \
            'action_20k_b_service_mutations=false' \
            'action_20k_b_vrrp_mutations=false' \
            'action_20k_b_vip_mutations=false' \
            'action_20k_b_node_a_contacted=false' \
            'action_20k_b_remote_complete=true'
    } >"$action20kb_regression_output"
}
run_intercepted_case() {
    local action20kb_regression_case_root=$1
    local action20kb_regression_transcript=$2
    local action20kb_regression_remote_status=$3
    local action20kb_regression_expected_status=$4
    local action20kb_regression_stderr_content=${5:-}
    local action20kb_regression_fake_ssh=$action20kb_regression_case_root/fake-ssh
    local action20kb_regression_observed_status=0

    install -d -m 0700 "$action20kb_regression_case_root" || return 1
    # The generated fake transport expands these variables at runtime.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"${ACTION20KB_STDIN_CAPTURE:?}"' \
        'printf "%s\n" "$*" >"${ACTION20KB_ARGS_CAPTURE:?}"' \
        'cat "${ACTION20KB_TRANSCRIPT:?}"' \
        'if [[ -n "${ACTION20KB_STDERR_CONTENT:-}" ]]; then' \
        '    printf "%s\n" "$ACTION20KB_STDERR_CONTENT" >&2' \
        'fi' \
        'exit "${ACTION20KB_REMOTE_STATUS:?}"' >"$action20kb_regression_fake_ssh" || return 1
    chmod 0700 "$action20kb_regression_fake_ssh" || return 1
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20KB_TEST_MODE=1 \
            CADDY_ACTION20KB_SSH_BINARY="$action20kb_regression_fake_ssh" \
            ACTION20KB_STDIN_CAPTURE="$action20kb_regression_case_root/stdin" \
            ACTION20KB_ARGS_CAPTURE="$action20kb_regression_case_root/args" \
            ACTION20KB_TRANSCRIPT="$action20kb_regression_transcript" \
            ACTION20KB_STDERR_CONTENT="$action20kb_regression_stderr_content" \
            ACTION20KB_REMOTE_STATUS="$action20kb_regression_remote_status" \
            /bin/bash "$outer" --test-transport
    ) >"$action20kb_regression_case_root/stdout" \
        2>"$action20kb_regression_case_root/stderr" ||
        action20kb_regression_observed_status=$?
    [[ "$action20kb_regression_observed_status" -eq "$action20kb_regression_expected_status" ]] || return 1
    [[ "$(file_hash "$action20kb_regression_case_root/stdin")" = "$inspector_sha256" ]] || return 1
    grep -Fq -- '-T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes pi@10.1.0.54 cd / && sudo -n /bin/bash -s --' \
        "$action20kb_regression_case_root/args" || return 1
    ! grep -Fq '10.1.0.53' "$action20kb_regression_case_root/args" || return 1
}
production_label_alignment() {
    local action20kb_regression_root=$1

    /bin/bash "$inspector" --expected-checks >"$action20kb_regression_root/expected" || return 1
    awk '$1 == "record_check" { print $2 }' "$inspector" \
        >"$action20kb_regression_root/static" || return 1
    [[ "$(wc -l <"$action20kb_regression_root/expected")" -eq "$expected_check_count" ]] || return 1
    [[ "$(wc -l <"$action20kb_regression_root/static")" -eq "$expected_check_count" ]] || return 1
    diff -u "$action20kb_regression_root/expected" \
        "$action20kb_regression_root/static" >/dev/null
}
regression_root=$(mktemp -d /tmp/caddy-action20k-b-regression.XXXXXX)
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
record_gate node_a_ssh_target_absent bash -c \
    '! grep -Fq "pi@10.1.0.53" "$1"' _ "$outer"
# shellcheck disable=SC2016
record_gate node_a_hostname_absent bash -c \
    '! grep -Fxq "readonly expected_hostname=j1-svpihole0" "$1"' _ "$inspector"
# shellcheck disable=SC2016
record_gate service_and_vip_mutation_commands_absent bash -c \
    '! grep -Eq "systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)" "$1"' \
    _ "$inspector"
record_gate helper_execution_false_marker_present grep -Fq \
    "printf '%s_helper_execution=false" "$inspector"
record_gate filesystem_mutations_false_marker_present grep -Fq \
    "printf '%s_filesystem_mutations=false" "$inspector"
record_gate node_a_contacted_false_marker_present grep -Fq \
    "printf '%s_node_a_contacted=false" "$inspector"
record_gate valid_transcript_line_count test "$(wc -l <"$valid_transcript")" -eq 76
record_gate valid_production_path run_intercepted_case \
    "$regression_root/valid" "$valid_transcript" 0 0

cp -- "$valid_transcript" "$regression_root/false.transcript"
sed -i 's/action_20k_b_check_fragment_hash_exact=true/action_20k_b_check_fragment_hash_exact=false/' \
    "$regression_root/false.transcript"
record_gate false_assertion_rejected run_intercepted_case \
    "$regression_root/false" "$regression_root/false.transcript" 0 97

grep -Fv 'action_20k_b_check_fragment_hash_exact=true' "$valid_transcript" \
    >"$regression_root/missing.transcript"
record_gate missing_assertion_rejected run_intercepted_case \
    "$regression_root/missing" "$regression_root/missing.transcript" 0 97

cp -- "$valid_transcript" "$regression_root/duplicate.transcript"
printf '%s\n' 'action_20k_b_check_fragment_hash_exact=true' \
    >>"$regression_root/duplicate.transcript"
record_gate duplicate_assertion_rejected run_intercepted_case \
    "$regression_root/duplicate" "$regression_root/duplicate.transcript" 0 97

awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
    "$valid_transcript" >"$regression_root/reordered.transcript"
record_gate reordered_assertion_rejected run_intercepted_case \
    "$regression_root/reordered" "$regression_root/reordered.transcript" 0 97

sed "s/action_20k_b_value_after_state_sha256=$fixture_state_sha256/action_20k_b_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" \
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
