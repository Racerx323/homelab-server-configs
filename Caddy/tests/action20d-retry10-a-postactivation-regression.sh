#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly accepted_outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry10-outer.sh
readonly accepted_outer_sha256=0bf76de0c4f170b72338d7f7ec2627b7004361c0a59afeab7f410daa4747114c
readonly prefix=action_20d_retry10_a_regression

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}
write_fixture() {
    local fixture_role=$1
    local fixture_path=$2
    local fixture_count fixture_dns fixture_state fixture_label
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    if [[ "$fixture_role" = node-a ]]; then
        fixture_count=1
        fixture_dns=1
        fixture_state=MASTER
    else
        fixture_count=0
        fixture_dns=0
        fixture_state=inactive_fragment
    fi
    {
        while IFS= read -r fixture_label; do
            printf 'action_20d_retry10_a_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        printf '%s\n' \
            "action_20d_retry10_a_probe_value_node_role=$fixture_role" \
            "action_20d_retry10_a_probe_value_expected_vrrp_state=$fixture_state" \
            "action_20d_retry10_a_probe_value_caddy_ipv4_count=$fixture_count" \
            "action_20d_retry10_a_probe_value_caddy_ipv6_count=$fixture_count" \
            "action_20d_retry10_a_probe_value_dns_ipv4_count=$fixture_dns" \
            "action_20d_retry10_a_probe_value_dns_ipv6_count=$fixture_dns" \
            "action_20d_retry10_a_probe_value_before_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_a_probe_value_after_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_a_probe_assertion_count=$(/bin/bash "$probe" --expected-assertions | wc -l)" \
            'action_20d_retry10_a_probe_failed_assertion_count=0' \
            'action_20d_retry10_a_probe_first_failure=none' \
            'action_20d_retry10_a_probe_health_helper_invoked=true' \
            'action_20d_retry10_a_probe_notification_helper_invoked=false' \
            'action_20d_retry10_a_probe_filesystem_mutations=false' \
            'action_20d_retry10_a_probe_service_mutations=false' \
            'action_20d_retry10_a_probe_keepalived_mutations=false' \
            'action_20d_retry10_a_probe_vrrp_mutations=false' \
            'action_20d_retry10_a_probe_vip_mutations=false' \
            'action_20d_retry10_a_probe_network_mutations=false' \
            'action_20d_retry10_a_probe_persistent_mutations=false' \
            'action_20d_retry10_a_probe_remote_cleanup_complete=true' \
            'action_20d_retry10_a_probe_remote_complete=true'
    } >"$fixture_path"
}
run_intercepted() {
    local run_name=$1
    local run_stdout=$test_root/$run_name.stdout
    local run_stderr=$test_root/$run_name.stderr
    local run_status=0

    : >"$test_root/order"
    CADDY_ACTION20D_RETRY10_A_SSH_BINARY=$test_root/fake-ssh \
        /bin/bash "$runner" >"$run_stdout" 2>"$run_stderr" || run_status=$?
    printf '%s\n' "$run_status"
}

test_root=$(mktemp -d /tmp/caddy-action20d-retry10-a-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT
write_fixture node-b "$test_root/node-b.fixture"
write_fixture node-a "$test_root/node-a.fixture"
cat >"$test_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
for argument in "$@"; do
    case "$argument" in
        pi@10.1.0.54)
            printf 'node-b\n' >>"$CADDY_TEST_ORDER"
            cat "$CADDY_TEST_NODE_B_FIXTURE"
            exit 0
            ;;
        pi@10.1.0.53)
            printf 'node-a\n' >>"$CADDY_TEST_ORDER"
            cat "$CADDY_TEST_NODE_A_FIXTURE"
            exit 0
            ;;
    esac
done
exit 64
FAKE_SSH
chmod 0700 "$test_root/fake-ssh"
export CADDY_TEST_ORDER=$test_root/order
export CADDY_TEST_NODE_B_FIXTURE=$test_root/node-b.fixture
export CADDY_TEST_NODE_A_FIXTURE=$test_root/node-a.fixture

record_check accepted_outer_immutable test "$(file_hash "$accepted_outer")" = "$accepted_outer_sha256"
record_check probe_self_test /bin/bash "$probe" --self-test
record_check runner_self_test /bin/bash "$runner" --self-test
record_check runner_contract_test /bin/bash "$runner" --contract-test
record_check probe_labels_unique test \
    "$(/bin/bash "$probe" --expected-assertions | LC_ALL=C sort | uniq -d | wc -l)" -eq 0
record_check runner_labels_unique test \
    "$(/bin/bash "$runner" --expected-assertions | LC_ALL=C sort | uniq -d | wc -l)" -eq 0

valid_status=$(run_intercepted valid)
record_check valid_status_zero test "$valid_status" -eq 0
record_check valid_stderr_empty test ! -s "$test_root/valid.stderr"
record_check node_b_before_node_a test "$(tr '\n' ' ' <"$test_root/order")" = 'node-b node-a '
record_check valid_acceptance_complete test \
    "$(grep -Fxc 'action_20d_retry10_a_acceptance_complete=true' "$test_root/valid.stdout")" -eq 1
record_check valid_owner_counts test \
    "$(grep -Ec '^action_20d_retry10_a_value_ipv(4|6)_owner_count=1$' "$test_root/valid.stdout")" -eq 2

cp "$test_root/node-a.fixture" "$test_root/node-a.valid"
sed -i '/action_20d_retry10_a_probe_assertion_main_hash_exact=true/d' "$test_root/node-a.fixture"
missing_status=$(run_intercepted missing)
record_check missing_label_rejected test "$missing_status" -ne 0
cp "$test_root/node-a.valid" "$test_root/node-a.fixture"
printf 'action_20d_retry10_a_probe_assertion_main_hash_exact=true\n' >>"$test_root/node-a.fixture"
duplicate_status=$(run_intercepted duplicate)
record_check duplicate_label_rejected test "$duplicate_status" -ne 0
cp "$test_root/node-a.valid" "$test_root/node-a.fixture"
sed -i 's/action_20d_retry10_a_probe_assertion_main_hash_exact=true/action_20d_retry10_a_probe_assertion_main_hash_exact=false/' "$test_root/node-a.fixture"
false_status=$(run_intercepted false)
record_check false_label_rejected test "$false_status" -ne 0
cp "$test_root/node-a.valid" "$test_root/node-a.fixture"
printf 'action_20d_retry10_a_probe_assertion_unexpected=true\n' >>"$test_root/node-a.fixture"
extra_status=$(run_intercepted extra)
record_check extra_label_rejected test "$extra_status" -ne 0
cp "$test_root/node-a.valid" "$test_root/node-a.fixture"
sed -i 's/action_20d_retry10_a_probe_value_caddy_ipv4_count=1/action_20d_retry10_a_probe_value_caddy_ipv4_count=0/' "$test_root/node-a.fixture"
wrong_owner_status=$(run_intercepted wrong-owner)
record_check wrong_owner_rejected test "$wrong_owner_status" -ne 0

record_check probe_has_no_service_mutation test \
    "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable|mask|unmask)' "$probe" || true)" -eq 0
record_check probe_has_no_address_mutation test \
    "$(grep -Ec 'ip[[:space:]].*(address|addr)[[:space:]]+(add|del|replace)' "$probe" || true)" -eq 0
record_check runner_has_no_transfer test \
    "$(grep -Ec '(^|[[:space:]])(scp|rsync)([[:space:]]|$)' "$runner" || true)" -eq 0
record_check notification_not_invoked test \
    "$(grep -Ec '^[[:space:]]*\"?\$?notification_helper\"?[[:space:]]*$' "$probe" || true)" -eq 0
record_check exact_backup_path_pinned grep -Fq \
    '/var/backups/caddy-ha/action20d-retry10-node-a-caddy-vrrp.dTSW20' "$probe"

printf '%s_false_positive_and_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
