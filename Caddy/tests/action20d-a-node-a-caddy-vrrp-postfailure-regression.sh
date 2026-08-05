#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/inspect-node-a-caddy-vrrp-postfailure-action20d-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-vrrp-postfailure-action20d-a.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
write_fixture() {
    local fixture_path=$1
    local fixture_kind=$2
    local assertion_label
    local expected_count
    local failed_count=0
    local first_failure=none
    local assertion_value=true
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    expected_count=$(/bin/bash "$inspector" --expected-assertions | wc -l)
    : >"$fixture_path"
    while IFS= read -r assertion_label; do
        assertion_value=true
        if [[ "$fixture_kind" = semantic && "$assertion_label" = keepalived_process_args_main_config ]]; then
            assertion_value=false
            failed_count=1
            first_failure=$assertion_label
        fi
        printf 'action_20d_a_assertion_%s=%s\n' "$assertion_label" "$assertion_value" >>"$fixture_path"
    done < <(/bin/bash "$inspector" --expected-assertions)
    printf '%s\n' \
        "action_20d_a_value_before_state_sha256=$state_hash" \
        "action_20d_a_value_after_state_sha256=$state_hash" \
        "action_20d_a_assertion_count=$expected_count" \
        "action_20d_a_failed_assertion_count=$failed_count" \
        "action_20d_a_first_failure=$first_failure" \
        action_20d_a_candidate_validation_invoked=false \
        action_20d_a_node_b_contacted=false \
        action_20d_a_filesystem_mutations=false \
        action_20d_a_service_mutations=false \
        action_20d_a_keepalived_mutations=false \
        action_20d_a_vrrp_mutations=false \
        action_20d_a_vip_mutations=false \
        action_20d_a_persistent_mutations=false \
        action_20d_a_remote_complete=true >>"$fixture_path"
}
run_case() {
    local case_root=$1
    local fixture_kind=$2
    local corruption_kind=$3
    local expected_status=$4
    local evidence_path
    local observed_status=0
    local duplicate_line

    install -d -m 0700 "$case_root"
    write_fixture "$case_root/transcript" "$fixture_kind"
    case "$corruption_kind" in
        none) ;;
        missing)
            sed '/^action_20d_a_assertion_main_hash_exact=/d' "$case_root/transcript" >"$case_root/new"
            mv "$case_root/new" "$case_root/transcript"
            ;;
        duplicate)
            duplicate_line=$(grep -m1 '^action_20d_a_assertion_' "$case_root/transcript")
            printf '%s\n' "$duplicate_line" >>"$case_root/transcript"
            ;;
        state_drift)
            sed -i 's/action_20d_a_value_after_state_sha256=aaaaaaaa/action_20d_a_value_after_state_sha256=bbbbbbbb/' "$case_root/transcript"
            ;;
        *) return 1 ;;
    esac
    cat >"$case_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20DA_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION20DA_SSH_ARGS_CAPTURE:?}"
cat "${ACTION20DA_TRANSCRIPT:?}"
if grep -q '^action_20d_a_assertion_.*=false$' "${ACTION20DA_TRANSCRIPT:?}"; then
    exit 1
fi
FAKE_SSH
    chmod 0700 "$case_root/fake-ssh"
    (
        cd "$repository_root"
        CADDY_ACTION20DA_INTERCEPTED_TEST=1 \
            CADDY_ACTION20DA_SSH_BINARY="$case_root/fake-ssh" \
            ACTION20DA_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20DA_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            ACTION20DA_TRANSCRIPT="$case_root/transcript" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    if [[ "$expected_status" -eq 97 ]]; then
        [[ "$(wc -l <"$case_root/stderr")" -eq 1 ]] || return 1
        evidence_path=$(sed -n 's/^action_20d_a_protected_evidence=//p' "$case_root/stderr")
        [[ "$evidence_path" == /tmp/caddy-action20d-a-runner.* ]] || return 1
        rm -rf -- "$evidence_path"
    else
        [[ ! -s "$case_root/stderr" ]] || return 1
    fi
    [[ -s "$case_root/stdin" ]] || return 1
    grep -Fqx -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co pi@10.1.0.53 cd / && sudo -n /bin/bash -s --' "$case_root/ssh.args"
}
static_read_only_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector" "$runner"
}
candidate_validation_absent() {
    ! grep -Eq 'keepalived[[:space:]].*--config-test|keepalived[[:space:]].*-t([[:space:]]|$)' "$inspector" "$runner"
}
node_b_path_absent() {
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b|Node B' "$inspector" "$runner"
}

require_gate sources_syntax /bin/bash -n "$0" "$inspector" "$runner"
require_gate sources_shellcheck shellcheck "$0" "$inspector" "$runner"
require_gate collision_policy /bin/bash "$collision_checker" "$0" "$inspector" "$runner"
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate static_read_only_policy static_read_only_policy
require_gate candidate_validation_absent candidate_validation_absent
require_gate node_b_path_absent node_b_path_absent

regression_root=$(mktemp -d /tmp/caddy-action20d-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
require_gate valid_production_transcript_accepted run_case "$regression_root/valid" valid none 0
require_gate semantic_failure_preserved run_case "$regression_root/semantic" semantic none 1
require_gate missing_label_rejected run_case "$regression_root/missing" valid missing 97
require_gate duplicate_label_rejected run_case "$regression_root/duplicate" valid duplicate 97
require_gate state_drift_rejected run_case "$regression_root/drift" valid state_drift 97
printf '%s_false_negative_semantic_failure_preserved=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_false_positive_state_drift_rejected=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
