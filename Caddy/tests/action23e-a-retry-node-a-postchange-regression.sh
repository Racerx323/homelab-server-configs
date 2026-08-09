#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23e_a_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-node-a-pihole-ptr-postchange-action23e-a-retry.sh
readonly outer=$caddy_root/scripts/run-node-a-pihole-ptr-postchange-action23e-a-retry-outer.sh
fixture_root=$(mktemp -d /tmp/caddy-action23ear-regression.XXXXXX)
readonly fixture_root
readonly fake_ssh=$fixture_root/ssh

cleanup() {
    local action23ear_regression_status=$?

    rm -rf -- "$fixture_root"
    exit "$action23ear_regression_status"
}
trap cleanup EXIT
record_check() {
    local action23ear_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23ear_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23ear_regression_label" >&2
    return 1
}
command_fails() {
    ! "$@"
}
run_case() {
    local action23ear_regression_mode=$1
    local action23ear_regression_expected_status=$2
    local action23ear_regression_expect_acceptance=$3
    local action23ear_regression_case_root
    local action23ear_regression_stdout
    local action23ear_regression_stderr
    local action23ear_regression_status=0

    action23ear_regression_case_root=$(mktemp -d "$fixture_root/case.XXXXXX")
    action23ear_regression_stdout=$action23ear_regression_case_root/stdout
    action23ear_regression_stderr=$action23ear_regression_case_root/stderr
    if CADDY_ACTION23EAR_TEST_MODE=1 \
        CADDY_ACTION23EAR_SSH_BINARY="$fake_ssh" \
        ACTION23EAR_FIXTURE_MODE="$action23ear_regression_mode" \
        ACTION23EAR_FIXTURE_INSPECTOR="$inspector" \
        ACTION23EAR_FIXTURE_LOG="$action23ear_regression_case_root/ssh.log" \
        /bin/bash "$outer" --test-transport \
        >"$action23ear_regression_stdout" 2>"$action23ear_regression_stderr"; then
        action23ear_regression_status=0
    else
        action23ear_regression_status=$?
    fi
    [[ "$action23ear_regression_status" -eq "$action23ear_regression_expected_status" ]] || return 1
    grep -Fqx 'fixture_target_exact=true' "$action23ear_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_root_cwd_exact=true' "$action23ear_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_inspector_exact=true' "$action23ear_regression_case_root/ssh.log" || return 1
    if [[ "$action23ear_regression_expect_acceptance" == true ]]; then
        grep -Fqx 'action_23e_a_retry_outer_acceptance=true' "$action23ear_regression_stdout" || return 1
        grep -Fqx 'action_23e_a_retry_outer_node_a_contacted=false' "$action23ear_regression_stdout" || return 1
        grep -Fqx 'action_23e_a_retry_outer_node_b_contacted=false' "$action23ear_regression_stdout" || return 1
        grep -Fqx 'action_23e_a_retry_outer_action_23b_rerun=false' "$action23ear_regression_stdout" || return 1
        grep -Fqx 'action_23e_a_retry_outer_action_23e_rerun=false' "$action23ear_regression_stdout" || return 1
        grep -Fqx 'action_23e_a_retry_outer_action_23e_a_rerun=false' "$action23ear_regression_stdout" || return 1
        [[ ! -s "$action23ear_regression_stderr" ]] || return 1
    else
        ! grep -Fqx 'action_23e_a_retry_outer_acceptance=true' "$action23ear_regression_stdout" || return 1
    fi
}
run_validation_case() {
    local action23ear_validation_mode=$1
    local action23ear_validation_expected_status=$2
    local action23ear_validation_root
    local action23ear_validation_contract
    local action23ear_validation_changed
    local action23ear_validation_producer_stderr
    local action23ear_validation_stdout
    local action23ear_validation_stderr
    local action23ear_validation_producer_status=0
    local action23ear_validation_status=0

    action23ear_validation_root=$(mktemp -d "$fixture_root/validation.XXXXXX") || return 1
    action23ear_validation_contract=$action23ear_validation_root/contract.stdout
    action23ear_validation_changed=$action23ear_validation_root/changed.stdout
    action23ear_validation_producer_stderr=$action23ear_validation_root/producer.stderr
    action23ear_validation_stdout=$action23ear_validation_root/validator.stdout
    action23ear_validation_stderr=$action23ear_validation_root/validator.stderr
    : >"$action23ear_validation_producer_stderr"
    /bin/bash "$inspector" --contract-transcript >"$action23ear_validation_contract" || return 1
    case "$action23ear_validation_mode" in
        missing_metadata)
            sed '/^action_23e_a_retry_value_ftl_stat=/d' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        altered_metadata)
            sed 's/mode_octal=664/mode_octal=/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        false_check)
            sed 's/^action_23e_a_retry_check_ftl_regular=true$/action_23e_a_retry_check_ftl_regular=false/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        duplicate_check)
            {
                cat "$action23ear_validation_contract"
                printf 'action_23e_a_retry_check_ftl_regular=true\n'
            } >"$action23ear_validation_changed" || return 1
            ;;
        changed_state)
            sed 's/^action_23e_a_retry_value_after_state_sha256=a\{64\}$/action_23e_a_retry_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        invalid_ftl_hash)
            sed 's/^action_23e_a_retry_value_ftl_sha256=.*/action_23e_a_retry_value_ftl_sha256=not-a-sha256/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        wrong_domain_hash)
            sed 's/^action_23e_a_retry_value_domain_sha256=.*/action_23e_a_retry_value_domain_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        wrong_custom_cname_hash)
            sed 's/^action_23e_a_retry_value_custom_cname_sha256=.*/action_23e_a_retry_value_custom_cname_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        action23b_rerun_true)
            sed 's/^action_23e_a_retry_action_23b_rerun=false$/action_23e_a_retry_action_23b_rerun=true/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        action23e_rerun_true)
            sed 's/^action_23e_a_retry_action_23e_rerun=false$/action_23e_a_retry_action_23e_rerun=true/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        action23ea_rerun_true)
            sed 's/^action_23e_a_retry_action_23e_a_rerun=false$/action_23e_a_retry_action_23e_a_rerun=true/' "$action23ear_validation_contract" >"$action23ear_validation_changed" || return 1
            ;;
        stderr)
            cp "$action23ear_validation_contract" "$action23ear_validation_changed" || return 1
            printf 'bounded fixture stderr\n' >"$action23ear_validation_producer_stderr"
            ;;
        nonzero)
            cp "$action23ear_validation_contract" "$action23ear_validation_changed" || return 1
            action23ear_validation_producer_status=23
            ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION23EAR_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action23ear_validation_changed" "$action23ear_validation_producer_stderr" \
        "$action23ear_validation_producer_status" \
        >"$action23ear_validation_stdout" 2>"$action23ear_validation_stderr"; then
        action23ear_validation_status=0
    else
        action23ear_validation_status=$?
    fi
    [[ "$action23ear_validation_status" -eq "$action23ear_validation_expected_status" ]] || return 1
    ! grep -Fqx 'action_23e_a_retry_outer_test_validation_complete=true' "$action23ear_validation_stdout" || return 1
}

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly fixture_mode=${ACTION23EAR_FIXTURE_MODE:?}
readonly fixture_inspector=${ACTION23EAR_FIXTURE_INSPECTOR:?}
readonly fixture_log=${ACTION23EAR_FIXTURE_LOG:?}
received_inspector=$(mktemp /tmp/caddy-action23ear-received.XXXXXX)
readonly received_inspector
contract=$(mktemp /tmp/caddy-action23ear-contract.XXXXXX)
readonly contract
trap 'rm -f -- "$received_inspector" "$contract"' EXIT
cat >"$received_inspector"
printf 'fixture_target_exact=%s\n' \
    "$(if [[ " $* " == *' pi@10.1.0.53 '* &&
        " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_root_cwd_exact=%s\n' \
    "$(if [[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_inspector_exact=%s\n' \
    "$(if [[ "$(sha256sum "$received_inspector" | awk '{ print $1 }')" == \
        "$(sha256sum "$fixture_inspector" | awk '{ print $1 }')" ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
/bin/bash "$fixture_inspector" --contract-transcript >"$contract"
case "$fixture_mode" in
    success) cat "$contract" ;;
    missing_metadata) sed '/^action_23e_a_retry_value_ftl_stat=/d' "$contract" ;;
    altered_metadata) sed 's/mode_octal=664/mode_octal=/' "$contract" ;;
    false_check) sed 's/^action_23e_a_retry_check_ftl_regular=true$/action_23e_a_retry_check_ftl_regular=false/' "$contract" ;;
    duplicate_check) cat "$contract"; printf 'action_23e_a_retry_check_ftl_regular=true\n' ;;
    changed_state) sed 's/^action_23e_a_retry_value_after_state_sha256=a\{64\}$/action_23e_a_retry_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$contract" ;;
    invalid_ftl_hash) sed 's/^action_23e_a_retry_value_ftl_sha256=.*/action_23e_a_retry_value_ftl_sha256=not-a-sha256/' "$contract" ;;
    wrong_domain_hash) sed 's/^action_23e_a_retry_value_domain_sha256=.*/action_23e_a_retry_value_domain_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$contract" ;;
    wrong_custom_cname_hash) sed 's/^action_23e_a_retry_value_custom_cname_sha256=.*/action_23e_a_retry_value_custom_cname_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$contract" ;;
    action23b_rerun_true) sed 's/^action_23e_a_retry_action_23b_rerun=false$/action_23e_a_retry_action_23b_rerun=true/' "$contract" ;;
    action23e_rerun_true) sed 's/^action_23e_a_retry_action_23e_rerun=false$/action_23e_a_retry_action_23e_rerun=true/' "$contract" ;;
    action23ea_rerun_true) sed 's/^action_23e_a_retry_action_23e_a_rerun=false$/action_23e_a_retry_action_23e_a_rerun=true/' "$contract" ;;
    stderr) cat "$contract"; printf 'bounded fixture stderr\n' >&2 ;;
    nonzero) cat "$contract"; exit 23 ;;
    *) exit 98 ;;
esac
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check inspector_syntax /bin/bash -n "$inspector"
record_check outer_syntax /bin/bash -n "$outer"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check direct_policy_accepts_canonical_vip /bin/bash "$inspector" \
    --ptr-policy-test direct pihole.local.theama.co.
record_check direct_policy_rejects_node_a command_fails /bin/bash "$inspector" \
    --ptr-policy-test direct j1-svpihole0.local.theama.co.
record_check direct_policy_rejects_node_b command_fails /bin/bash "$inspector" \
    --ptr-policy-test direct j1-svpihole00.local.theama.co.
record_check direct_policy_rejects_generic command_fails /bin/bash "$inspector" \
    --ptr-policy-test direct pi.hole.
record_check local_policy_accepts_node_a /bin/bash "$inspector" \
    --ptr-policy-test local j1-svpihole0.local.theama.co.
record_check local_policy_rejects_canonical_vip command_fails /bin/bash "$inspector" \
    --ptr-policy-test local pihole.local.theama.co.
record_check local_policy_rejects_node_b command_fails /bin/bash "$inspector" \
    --ptr-policy-test local j1-svpihole00.local.theama.co.
record_check local_policy_rejects_generic command_fails /bin/bash "$inspector" \
    --ptr-policy-test local pi.hole.
record_check direct_ipv4_uses_policy grep -Fqx \
    'query_and_emit direct_pihole_ptr4 127.0.0.1 5335 10.1.0.55 PTR policy:direct || exit 1' "$inspector"
record_check direct_ipv6_uses_policy grep -Fqx \
    'query_and_emit direct_pihole_ptr6 127.0.0.1 5335 fd36:5aa8:6971:1::55 PTR policy:direct || exit 1' "$inspector"
record_check local_ipv4_uses_policy grep -Fqx \
    'query_and_emit local_pihole_ptr4 127.0.0.1 53 10.1.0.55 PTR policy:local || exit 1' "$inspector"
record_check local_ipv6_uses_policy grep -Fqx \
    'query_and_emit local_pihole_ptr6 127.0.0.1 53 fd36:5aa8:6971:1::55 PTR policy:local || exit 1' "$inspector"
record_check action23b_driver_invocation_absent test \
    "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b-outer' "$inspector" || true)" -eq 0
record_check action23b_outer_invocation_absent test \
    "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b-outer' "$outer" || true)" -eq 0
record_check action23e_driver_invocation_absent test \
    "$(grep -Ec 'apply-node-a-pihole-ptr-policy-action23e|run-node-a-pihole-ptr-policy-action23e-outer' "$inspector" || true)" -eq 0
record_check action23e_outer_invocation_absent test \
    "$(grep -Ec 'apply-node-a-pihole-ptr-policy-action23e|run-node-a-pihole-ptr-policy-action23e-outer' "$outer" || true)" -eq 0
record_check pihole_restart_absent test "$(grep -Ec 'pihole[[:space:]]+restartdns' "$inspector" || true)" -eq 0
record_check success_case run_case success 0 true
record_check missing_metadata_rejected run_validation_case missing_metadata 97
record_check altered_metadata_rejected run_validation_case altered_metadata 97
record_check false_check_rejected run_validation_case false_check 97
record_check duplicate_check_rejected run_validation_case duplicate_check 97
record_check changed_state_rejected run_validation_case changed_state 97
record_check invalid_ftl_hash_rejected run_validation_case invalid_ftl_hash 97
record_check wrong_domain_hash_rejected run_validation_case wrong_domain_hash 97
record_check wrong_custom_cname_hash_rejected run_validation_case wrong_custom_cname_hash 97
record_check action23b_rerun_true_rejected run_validation_case action23b_rerun_true 97
record_check action23e_rerun_true_rejected run_validation_case action23e_rerun_true 97
record_check action23ea_rerun_true_rejected run_validation_case action23ea_rerun_true 97
record_check stderr_rejected run_validation_case stderr 97
record_check nonzero_rejected run_validation_case nonzero 23

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_action_23e_a_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
