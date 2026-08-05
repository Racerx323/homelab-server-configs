#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_b_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/diagnose-node-a-caddy-vrrp-candidate-action20d-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-vrrp-candidate-diagnostic-action20d-b.sh"
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
    local exact_kind=$2
    local minimal_kind=$3
    local assertion_label
    local expected_count
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local candidate_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local exact_status
    local exact_classification
    local exact_duration
    local minimal_status
    local minimal_classification
    local minimal_duration

    case "$exact_kind" in
        valid)
            exact_status=0
            exact_classification=config_valid
            exact_duration=80
            ;;
        timeout)
            exact_status=124
            exact_classification=timeout_term
            exact_duration=15015
            ;;
        error)
            exact_status=2
            exact_classification=config_error_or_command_failure
            exact_duration=90
            ;;
        *) return 1 ;;
    esac
    case "$minimal_kind" in
        valid)
            minimal_status=0
            minimal_classification=config_valid
            minimal_duration=70
            ;;
        timeout)
            minimal_status=124
            minimal_classification=timeout_term
            minimal_duration=15011
            ;;
        error)
            minimal_status=2
            minimal_classification=config_error_or_command_failure
            minimal_duration=75
            ;;
        *) return 1 ;;
    esac
    expected_count=$(/bin/bash "$inspector" --expected-assertions | wc -l)
    : >"$fixture_path"
    while IFS= read -r assertion_label; do
        printf 'action_20d_b_assertion_%s=true\n' "$assertion_label" >>"$fixture_path"
    done < <(/bin/bash "$inspector" --expected-assertions)
    printf '%s\n' \
        "action_20d_b_value_before_state_sha256=$state_hash" \
        "action_20d_b_value_after_state_sha256=$state_hash" \
        "action_20d_b_value_candidate_sha256=$candidate_hash" \
        "action_20d_b_value_exact_status=$exact_status" \
        "action_20d_b_value_exact_classification=$exact_classification" \
        "action_20d_b_value_exact_duration_ms=$exact_duration" \
        "action_20d_b_value_minimal_status=$minimal_status" \
        "action_20d_b_value_minimal_classification=$minimal_classification" \
        "action_20d_b_value_minimal_duration_ms=$minimal_duration" \
        "action_20d_b_assertion_count=$expected_count" \
        action_20d_b_failed_assertion_count=0 \
        action_20d_b_first_failure=none \
        action_20d_b_candidate_validation_invoked=true \
        action_20d_b_candidate_installed=false \
        action_20d_b_node_b_contacted=false \
        action_20d_b_transient_filesystem_activity=true \
        action_20d_b_persistent_filesystem_mutations=false \
        action_20d_b_service_mutations=false \
        action_20d_b_keepalived_service_mutations=false \
        action_20d_b_vrrp_mutations=false \
        action_20d_b_vip_mutations=false \
        action_20d_b_remote_complete=true >>"$fixture_path"
}
run_case() {
    local case_root=$1
    local exact_kind=$2
    local minimal_kind=$3
    local corruption_kind=$4
    local expected_status=$5
    local observed_status=0
    local duplicate_line
    local evidence_path

    install -d -m 0700 "$case_root"
    write_fixture "$case_root/transcript" "$exact_kind" "$minimal_kind"
    case "$corruption_kind" in
        none) ;;
        missing)
            sed '/^action_20d_b_assertion_main_hash_exact=/d' "$case_root/transcript" >"$case_root/new"
            mv "$case_root/new" "$case_root/transcript"
            ;;
        duplicate)
            duplicate_line=$(grep -m1 '^action_20d_b_assertion_' "$case_root/transcript")
            printf '%s\n' "$duplicate_line" >>"$case_root/transcript"
            ;;
        unknown)
            sed -i 's/value_exact_classification=[a-z_]*/value_exact_classification=unknown/' "$case_root/transcript"
            ;;
        drift)
            sed -i 's/value_after_state_sha256=aaaaaaaa/value_after_state_sha256=cccccccc/' "$case_root/transcript"
            ;;
        *) return 1 ;;
    esac
    cat >"$case_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"${ACTION20DB_STDIN_CAPTURE:?}"
printf '%s\n' "$*" >"${ACTION20DB_SSH_ARGS_CAPTURE:?}"
cat "${ACTION20DB_TRANSCRIPT:?}"
FAKE_SSH
    chmod 0700 "$case_root/fake-ssh"
    (
        cd "$repository_root"
        CADDY_ACTION20DB_INTERCEPTED_TEST=1 \
            CADDY_ACTION20DB_SSH_BINARY="$case_root/fake-ssh" \
            ACTION20DB_STDIN_CAPTURE="$case_root/stdin" \
            ACTION20DB_SSH_ARGS_CAPTURE="$case_root/ssh.args" \
            ACTION20DB_TRANSCRIPT="$case_root/transcript" \
            /bin/bash "$runner"
    ) >"$case_root/stdout" 2>"$case_root/stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    if [[ "$expected_status" -eq 97 ]]; then
        [[ "$(wc -l <"$case_root/stderr")" -eq 1 ]] || return 1
        evidence_path=$(sed -n 's/^action_20d_b_protected_evidence=//p' "$case_root/stderr")
        [[ "$evidence_path" == /tmp/caddy-action20d-b-runner.* ]] || return 1
        rm -rf -- "$evidence_path"
    else
        [[ ! -s "$case_root/stderr" ]] || return 1
    fi
    [[ -s "$case_root/stdin" ]] || return 1
    grep -Fqx -- '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole0.local.theama.co pi@10.1.0.53 cd / && sudo -n /bin/bash -s --' "$case_root/ssh.args"
}
bounded_probe_policy() {
    # This checks literal source text; expansion would weaken the policy.
    # shellcheck disable=SC2016
    grep -Fq -- '--kill-after="${probe_kill_after_seconds}s" "${probe_timeout_seconds}s"' "$inspector" &&
        grep -Fq 'run_probe exact exact' "$inspector" &&
        grep -Fq 'run_probe minimal minimal' "$inspector"
}
no_persistent_mutation_policy() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|(^|[;&|[:space:]])(install|cp|mv|chmod|chown)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector" "$runner"
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
require_gate bounded_probe_policy bounded_probe_policy
require_gate no_persistent_mutation_policy no_persistent_mutation_policy
require_gate node_b_path_absent node_b_path_absent

regression_root=$(mktemp -d /tmp/caddy-action20d-b-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
require_gate both_valid_accepted run_case "$regression_root/both-valid" valid valid none 0
require_gate exact_timeout_minimal_valid_accepted run_case "$regression_root/exact-timeout" timeout valid none 0
require_gate exact_valid_minimal_timeout_accepted run_case "$regression_root/minimal-timeout" valid timeout none 0
require_gate both_config_error_accepted run_case "$regression_root/both-error" error error none 0
require_gate missing_label_rejected run_case "$regression_root/missing" valid valid missing 97
require_gate duplicate_label_rejected run_case "$regression_root/duplicate" valid valid duplicate 97
require_gate unknown_classification_rejected run_case "$regression_root/unknown" valid valid unknown 97
require_gate state_drift_rejected run_case "$regression_root/drift" valid valid drift 97
printf '%s_false_negative_timeout_observation_accepted=true\n' "$prefix"
printf '%s_false_negative_config_error_observation_accepted=true\n' "$prefix"
printf '%s_false_positive_missing_label_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_label_rejected=true\n' "$prefix"
printf '%s_false_positive_unknown_classification_rejected=true\n' "$prefix"
printf '%s_false_positive_state_drift_rejected=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
