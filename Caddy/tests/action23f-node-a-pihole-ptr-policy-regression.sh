#!/usr/bin/env bash

# shellcheck disable=SC2016
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23f_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly driver=$caddy_root/scripts/apply-node-a-pihole-ptr-policy-action23f.sh
readonly outer=$caddy_root/scripts/run-node-a-pihole-ptr-policy-action23f-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh
fixture_root=$(mktemp -d /tmp/caddy-action23f-regression.XXXXXX)
readonly fixture_root
readonly fake_ssh=$fixture_root/ssh

cleanup() {
    local action23f_regression_status=$?

    rm -rf -- "$fixture_root"
    exit "$action23f_regression_status"
}
trap cleanup EXIT

record_check() {
    local action23f_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23f_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23f_regression_label" >&2
    return 1
}
run_transport_case() {
    local action23f_regression_mode=$1
    local action23f_regression_expected_status=$2
    local action23f_regression_expected_acceptance=$3
    local action23f_regression_case_root
    local action23f_regression_stdout
    local action23f_regression_stderr
    local action23f_regression_status=0

    action23f_regression_case_root=$(mktemp -d "$fixture_root/case.XXXXXX")
    action23f_regression_stdout=$action23f_regression_case_root/stdout
    action23f_regression_stderr=$action23f_regression_case_root/stderr
    if CADDY_ACTION23F_TEST_MODE=1 \
        CADDY_ACTION23F_SSH_BINARY="$fake_ssh" \
        ACTION23F_FIXTURE_MODE="$action23f_regression_mode" \
        ACTION23F_FIXTURE_DRIVER="$driver" \
        ACTION23F_FIXTURE_LOG="$action23f_regression_case_root/ssh.log" \
        /bin/bash "$outer" --test-transport \
        >"$action23f_regression_stdout" 2>"$action23f_regression_stderr"; then
        action23f_regression_status=0
    else
        action23f_regression_status=$?
    fi
    if [[ "$action23f_regression_status" -ne "$action23f_regression_expected_status" ]]; then
        printf '%s_transport_case=%s\n' "$prefix" "$action23f_regression_mode" >&2
        printf '%s_transport_observed_status=%s\n' "$prefix" "$action23f_regression_status" >&2
        printf '%s_transport_expected_status=%s\n' "$prefix" "$action23f_regression_expected_status" >&2
        printf '%s_transport_stdout_begin\n' "$prefix" >&2
        sed -n '1,240p' "$action23f_regression_stdout" >&2
        printf '%s_transport_stdout_end\n' "$prefix" >&2
        printf '%s_transport_stderr_begin\n' "$prefix" >&2
        sed -n '1,240p' "$action23f_regression_stderr" >&2
        printf '%s_transport_stderr_end\n' "$prefix" >&2
        return 1
    fi
    grep -Fqx 'fixture_target_exact=true' "$action23f_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_root_cwd_exact=true' "$action23f_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_driver_exact=true' "$action23f_regression_case_root/ssh.log" || return 1
    if [[ "$action23f_regression_expected_acceptance" == true ]]; then
        grep -Fqx 'action_23f_outer_acceptance=true' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_node_a_contacted=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_node_b_contacted=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23b_rerun=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23d_rerun=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23e_rerun=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23e_a_rerun=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23e_a_retry_rerun=false' "$action23f_regression_stdout" || return 1
        grep -Fqx 'action_23f_outer_action_23e_a_retry2_rerun=false' "$action23f_regression_stdout" || return 1
        [[ ! -s "$action23f_regression_stderr" ]] || return 1
    else
        ! grep -Fqx 'action_23f_outer_acceptance=true' "$action23f_regression_stdout" || return 1
    fi
}

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly fixture_mode=${ACTION23F_FIXTURE_MODE:?}
readonly fixture_driver=${ACTION23F_FIXTURE_DRIVER:?}
readonly fixture_log=${ACTION23F_FIXTURE_LOG:?}
received_driver=$(mktemp /tmp/caddy-action23f-received.XXXXXX)
readonly received_driver
trap 'rm -f -- "$received_driver"' EXIT
cat >"$received_driver"
printf 'fixture_target_exact=%s\n' \
    "$(if [[ " $* " == *' pi@10.1.0.53 '* &&
        " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_root_cwd_exact=%s\n' \
    "$(if [[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_driver_exact=%s\n' \
    "$(if [[ "$(sha256sum "$received_driver" | awk '{ print $1 }')" == \
        "$(sha256sum "$fixture_driver" | awk '{ print $1 }')" ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
contract=$(mktemp /tmp/caddy-action23f-contract.XXXXXX)
readonly contract
trap 'rm -f -- "$received_driver" "$contract"' EXIT
/bin/bash "$fixture_driver" --contract-transcript >"$contract"
case "$fixture_mode" in
    success) cat "$contract" ;;
    missing_label) sed '/^action_23f_check_uid_root=true$/d' "$contract" ;;
    duplicate_label) cat "$contract"; printf 'action_23f_check_uid_root=true\n' ;;
    false_label) sed 's/^action_23f_check_uid_root=true$/action_23f_check_uid_root=false/' "$contract" ;;
    altered_domain) sed 's/^action_23f_value_domain_policy=local[.]theama[.]co$/action_23f_value_domain_policy=local.thema.co/' "$contract" ;;
    stale_ptr_policy) sed 's/^action_23f_value_new_ptr_policy=NONE$/action_23f_value_new_ptr_policy=HOSTNAMEFQDN/' "$contract" ;;
    stderr) cat "$contract"; printf 'bounded fixture stderr\n' >&2 ;;
    nonzero) cat "$contract"; exit 23 ;;
    *) exit 98 ;;
esac
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check outer_syntax /bin/bash -n "$outer"
record_check driver_syntax /bin/bash -n "$driver"
record_check collision_policy /bin/bash "$collision_policy" "$0" "$outer" "$driver"
record_check driver_self_test /bin/bash "$driver" --self-test
record_check exact_old_policy grep -Fq 'readonly old_ptr_line=PIHOLE_PTR=HOSTNAMEFQDN' "$driver"
record_check exact_new_policy grep -Fq 'readonly new_ptr_line=PIHOLE_PTR=NONE' "$driver"
record_check exact_domain grep -Fq 'readonly domain_line=domain=local.theama.co' "$driver"
record_check typo_rejected grep -Fq 'readonly misspelled_domain_line=domain=local.thema.co' "$driver"
record_check domain_read_only grep -Fq 'domain_configuration_mutation=false' "$driver"
record_check domain_hash_guard grep -Fq 'record_check domain_hash_unchanged' "$driver"
record_check observed_metadata_contract grep -Fq 'pihole:root:664' "$driver"
record_check candidate_metadata_contract grep -Fq 'install -o pihole -g root -m 0664 "$candidate"' "$driver"
record_check accepted_ftl_hash grep -Fq 'readonly accepted_ftl_sha256=c96c3591fabd3cbae4c0b32c695e34a2923a5b52b38e935cda3f2bf24fce1d7b' "$driver"
record_check accepted_domain_hash grep -Fq 'readonly accepted_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96' "$driver"
record_check dynamic_ftl_hash_capture grep -Fq 'before_ftl_sha256=$(file_hash "$live_ftl")' "$driver"
record_check dynamic_domain_hash_capture grep -Fq 'before_domain_sha256=$(file_hash "$live_domain")' "$driver"
record_check exact_delta_reconstruction grep -Fq 'record_check candidate_exact_delta validate_candidate_delta' "$driver"
record_check action23b_invocation_absent test "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b' "$driver" || true)" -eq 0
record_check action23d_invocation_absent test "$(grep -Ec 'apply-node-b-pihole-ptr-policy-action23d|run-node-b-pihole-ptr-policy-action23d' "$driver" || true)" -eq 0
record_check outer_action23b_invocation_absent test "$(grep -Ec 'apply-node-a-unbound-a-records-action23b|run-node-a-unbound-a-records-action23b' "$outer" || true)" -eq 0
record_check outer_action23d_invocation_absent test "$(grep -Ec 'apply-node-b-pihole-ptr-policy-action23d|run-node-b-pihole-ptr-policy-action23d' "$outer" || true)" -eq 0
record_check ftl_test_labeled grep -Fq 'record_check ftl_candidate_test validate_ftl_configuration' "$driver"
record_check pihole_restart_labeled grep -Fq 'record_check pihole_restartdns timeout 15' "$driver"
record_check node_b_target_absent test "$(grep -Fxc 'readonly expected_target=pi@10.1.0.54' "$outer" || true)" -eq 0
record_check success_transport run_transport_case success 0 true
record_check missing_label_rejected run_transport_case missing_label 97 false
record_check duplicate_label_rejected run_transport_case duplicate_label 97 false
record_check false_label_rejected run_transport_case false_label 97 false
record_check altered_domain_rejected run_transport_case altered_domain 97 false
record_check stale_ptr_policy_rejected run_transport_case stale_ptr_policy 97 false
record_check stderr_rejected run_transport_case stderr 97 false
record_check nonzero_rejected run_transport_case nonzero 23 false

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23d_rerun=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_action_23e_a_rerun=false\n' "$prefix"
printf '%s_action_23e_a_retry_rerun=false\n' "$prefix"
printf '%s_action_23e_a_retry2_rerun=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
