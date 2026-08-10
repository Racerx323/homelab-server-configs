#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_b_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly outer=$caddy_root/scripts/run-dual-node-caddy-failover-post-action28j-b-outer.sh
readonly state_inspector=$caddy_root/scripts/inspect-dual-node-caddy-failover-action28j.sh
readonly route_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-a-route.sh
readonly residue_inspector=$caddy_root/scripts/inspect-caddy-failover-action28j-a-residue.sh
readonly state_inspector_sha256=3f4e4ca1c55677f22e997d7cda3a105f2bbc662870885f3df1e343b5049de735
readonly route_inspector_sha256=33c1ba24aedc557d7c6e09bf9ecac2221b77b569759ebc60247ee7084f414068
readonly residue_inspector_sha256=c7ea3f9bc127dc8636bd860aadcf80c15961e84d08910f874615073427a90c5b

work_root=$(mktemp -d /tmp/caddy-action28j-b-regression.XXXXXX)
readonly work_root
cleanup() {
    local action28j_b_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28j_b_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
record_check() {
    local action28j_b_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_b_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_b_regression_label" >&2
    return 1
}
command_fails() { ! "$@" >/dev/null 2>&1; }
run_outer() {
    local action28j_b_regression_case=$1
    local action28j_b_regression_stdout=$2
    local action28j_b_regression_stderr=$3
    local action28j_b_regression_log=$4
    local action28j_b_regression_evidence_root=$work_root/evidence-$action28j_b_regression_case

    : >"$action28j_b_regression_log"
    mkdir -m 0700 -- "$action28j_b_regression_evidence_root"
    ACTION28J_B_FAKE_CASE=$action28j_b_regression_case \
        ACTION28J_B_CALL_LOG=$action28j_b_regression_log \
        ACTION28J_B_STATE_INSPECTOR=$state_inspector \
        ACTION28J_B_ROUTE_INSPECTOR=$route_inspector \
        ACTION28J_B_RESIDUE_INSPECTOR=$residue_inspector \
        CADDY_ACTION28J_B_TEST_MODE=1 \
        CADDY_ACTION28J_B_EVIDENCE_ROOT=$action28j_b_regression_evidence_root \
        CADDY_ACTION28J_B_SSH_PROGRAM=$fake_ssh \
        /bin/bash "$outer" >"$action28j_b_regression_stdout" \
        2>"$action28j_b_regression_stderr"
}
validate_durable_evidence() {
    local action28j_b_regression_case=$1
    local action28j_b_regression_wrapper_stdout=$2
    local action28j_b_regression_expected_status=$3
    local action28j_b_regression_evidence_directory
    local action28j_b_regression_expected_metadata

    action28j_b_regression_evidence_directory=$(sed -n \
        's/^action_28j_b_outer_durable_evidence_directory=//p' \
        "$action28j_b_regression_wrapper_stdout") || return 1
    [[ -n "$action28j_b_regression_evidence_directory" ]] || return 1
    [[ "$action28j_b_regression_evidence_directory" == "$work_root/evidence-$action28j_b_regression_case"/run.* ]] || return 1
    [[ -d "$action28j_b_regression_evidence_directory" &&
        ! -L "$action28j_b_regression_evidence_directory" ]] || return 1
    action28j_b_regression_expected_metadata="$(id -u):$(id -g):700"
    [[ "$(stat -c '%u:%g:%a' "$action28j_b_regression_evidence_directory")" = "$action28j_b_regression_expected_metadata" ]] || return 1
    for action28j_b_regression_evidence_file in stdout stderr exit-status metadata; do
        [[ -f "$action28j_b_regression_evidence_directory/$action28j_b_regression_evidence_file" &&
            ! -L "$action28j_b_regression_evidence_directory/$action28j_b_regression_evidence_file" ]] || return 1
        [[ "$(stat -c '%a' "$action28j_b_regression_evidence_directory/$action28j_b_regression_evidence_file")" = 600 ]] || return 1
    done
    [[ "$(<"$action28j_b_regression_evidence_directory/exit-status")" = "$action28j_b_regression_expected_status" ]] || return 1
    grep -Fqx "action_status=$action28j_b_regression_expected_status" \
        "$action28j_b_regression_evidence_directory/metadata" || return 1
    grep -Fqx "stdout_sha256=$(file_hash "$action28j_b_regression_evidence_directory/stdout")" \
        "$action28j_b_regression_evidence_directory/metadata" || return 1
    grep -Fqx "stderr_sha256=$(file_hash "$action28j_b_regression_evidence_directory/stderr")" \
        "$action28j_b_regression_evidence_directory/metadata" || return 1
    grep -Fqx 'stdout_classification=bounded_safe' \
        "$action28j_b_regression_evidence_directory/metadata" || return 1
    grep -Fqx 'stderr_classification=bounded_safe' \
        "$action28j_b_regression_evidence_directory/metadata" || return 1
    grep -Fqx action_28j_b_outer_durable_evidence_secured_before_cleanup=true \
        "$action28j_b_regression_wrapper_stdout"
}

fake_ssh=$work_root/ssh
readonly fake_ssh
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${ACTION28J_B_CALL_LOG:?}"
: "${ACTION28J_B_STATE_INSPECTOR:?}"
: "${ACTION28J_B_ROUTE_INSPECTOR:?}"
: "${ACTION28J_B_RESIDUE_INSPECTOR:?}"
printf '%s\n' "$*" >>"$ACTION28J_B_CALL_LOG"
call_index=$(wc -l <"$ACTION28J_B_CALL_LOG")
cat >/dev/null
emit_checks() {
    local producer=$1
    local record_prefix=$2
    local skip_first=${3:-false}
    local label
    local skipped=false

    while IFS= read -r label; do
        if [[ "$skip_first" = true && "$skipped" = false ]]; then
            skipped=true
            continue
        fi
        printf '%s_check_%s=true\n' "$record_prefix" "$label"
    done < <(/bin/bash "$producer" --expected-checks)
    printf '%s_check_count=%s\n' "$record_prefix" "$(/bin/bash "$producer" --expected-checks | wc -l)"
    printf '%s_failed_check_count=0\n' "$record_prefix"
    printf '%s_first_failure=none\n' "$record_prefix"
    printf '%s_acceptance=true\n' "$record_prefix"
}
case "$call_index" in
    1)
        skip_first=false
        [[ "${ACTION28J_B_FAKE_CASE:-valid}" != missing_check ]] || skip_first=true
        emit_checks "$ACTION28J_B_STATE_INSPECTOR" action_28j_node_a_failed "$skip_first"
        printf '%s\n' \
            action_28j_node_a_failed_value_vrrp_state=FAULT \
            action_28j_node_a_failed_value_caddy_ipv4_count=0 \
            action_28j_node_a_failed_value_caddy_ipv6_count=0 \
            action_28j_node_a_failed_value_dns_ipv4_count=1 \
            action_28j_node_a_failed_value_dns_ipv6_count=1
        ;;
    2 | 5)
        emit_checks "$ACTION28J_B_ROUTE_INSPECTOR" action_28j_a_route
        if [[ "${ACTION28J_B_FAKE_CASE:-valid}" = wrong_route && "$call_index" -eq 2 ]]; then
            printf '%s\n' \
                action_28j_a_route_value_a_answer=10.1.0.54 \
                action_28j_a_route_value_aaaa_answer=fd36:5aa8:6971:1::54 \
                action_28j_a_route_value_cname_answer=pihole00.local.theama.co. \
                action_28j_a_route_value_https_ipv4_url=https://pihole00.local.theama.co/admin/login.php \
                action_28j_a_route_value_https_ipv6_url=https://pihole00.local.theama.co/admin/login.php
        else
            printf '%s\n' \
                action_28j_a_route_value_a_answer=10.1.0.56 \
                action_28j_a_route_value_aaaa_answer=fd36:5aa8:6971:1::56 \
                action_28j_a_route_value_cname_answer=empty \
                action_28j_a_route_value_https_ipv4_url=https://pihole-admin.local.theama.co/admin/login.php \
                action_28j_a_route_value_https_ipv6_url=https://pihole-admin.local.theama.co/admin/login.php
        fi
        ;;
    3)
        emit_checks "$ACTION28J_B_RESIDUE_INSPECTOR" action_28j_a_residue
        if [[ "${ACTION28J_B_FAKE_CASE:-valid}" = residue_present ]]; then
            printf 'action_28j_a_residue_value_transaction_residue_count=1\n'
        else
            printf 'action_28j_a_residue_value_transaction_residue_count=0\n'
        fi
        ;;
    4)
        emit_checks "$ACTION28J_B_STATE_INSPECTOR" action_28j_node_b_failed
        if [[ "${ACTION28J_B_FAKE_CASE:-valid}" = wrong_node_b_state ]]; then
            printf 'action_28j_node_b_failed_value_vrrp_state=BACKUP\n'
        else
            printf 'action_28j_node_b_failed_value_vrrp_state=MASTER\n'
        fi
        printf '%s\n' \
            action_28j_node_b_failed_value_caddy_ipv4_count=1 \
            action_28j_node_b_failed_value_caddy_ipv6_count=1 \
            action_28j_node_b_failed_value_dns_ipv4_count=0 \
            action_28j_node_b_failed_value_dns_ipv6_count=0
        ;;
    6)
        emit_checks "$ACTION28J_B_RESIDUE_INSPECTOR" action_28j_a_residue
        printf 'action_28j_a_residue_value_transaction_residue_count=0\n'
        ;;
    *) exit 64 ;;
esac
FAKE_SSH
chmod 0755 "$fake_ssh"

record_check state_inspector_immutable test \
    "$(file_hash "$state_inspector")" = "$state_inspector_sha256"
record_check route_inspector_immutable test \
    "$(file_hash "$route_inspector")" = "$route_inspector_sha256"
record_check residue_inspector_immutable test \
    "$(file_hash "$residue_inspector")" = "$residue_inspector_sha256"
record_check residue_inspector_self_test /bin/bash "$residue_inspector" --self-test
record_check route_inspector_self_test /bin/bash "$route_inspector" --self-test
record_check outer_self_test /bin/bash "$outer" --self-test

valid_stdout=$work_root/valid.stdout
valid_stderr=$work_root/valid.stderr
valid_log=$work_root/valid.log
record_check production_success run_outer valid "$valid_stdout" "$valid_stderr" "$valid_log"
record_check production_stderr_empty test ! -s "$valid_stderr"
record_check production_acceptance grep -Fqx action_28j_b_outer_acceptance=true "$valid_stdout"
record_check production_durable_evidence validate_durable_evidence valid "$valid_stdout" 0
record_check production_raw_acceptance grep -Fqx action_28j_b_outer_acceptance=true \
    "$work_root/evidence-valid"/run.*/stdout
record_check production_stdout_content_emitted grep -Fq \
    'action_28j_b_outer_durable_stdout_content=action_28j_b_outer_acceptance=true' \
    "$valid_stdout"
record_check production_stderr_content_emitted grep -Fqx \
    action_28j_b_outer_durable_stderr_content=empty "$valid_stdout"
record_check production_six_remote_calls test "$(wc -l <"$valid_log")" -eq 6
record_check production_node_a_state_first sed -n '1{/pi@10[.]1[.]0[.]53.*--node node-a --phase failed/p;}' "$valid_log"
record_check production_node_b_residue_last sed -n '6{/pi@10[.]1[.]0[.]54.* node-b$/p;}' "$valid_log"
record_check production_remote_cwd test \
    "$(grep -Fc 'cd / && sudo -n /bin/bash -s --' "$valid_log")" -eq 6
record_check production_transient_cleanup test -z \
    "$(find /tmp -maxdepth 1 -type d -name 'caddy-action28j-b-post.*' -print -quit)"

record_check wrong_node_b_state_rejected command_fails run_outer wrong_node_b_state \
    "$work_root/wrong-state.stdout" "$work_root/wrong-state.stderr" "$work_root/wrong-state.log"
record_check wrong_node_b_state_evidence validate_durable_evidence wrong_node_b_state \
    "$work_root/wrong-state.stdout" 1
record_check residue_present_rejected command_fails run_outer residue_present \
    "$work_root/residue.stdout" "$work_root/residue.stderr" "$work_root/residue.log"
record_check wrong_route_rejected command_fails run_outer wrong_route \
    "$work_root/wrong-route.stdout" "$work_root/wrong-route.stderr" "$work_root/wrong-route.log"
record_check missing_check_rejected command_fails run_outer missing_check \
    "$work_root/missing.stdout" "$work_root/missing.stderr" "$work_root/missing.log"

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
