#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_a_regression
readonly builder_sha256=1b488289ee70698b20d05e2eec177b0c2af50b1d1e02e40c9f832d7f3c76a4e0
readonly generated_probe_sha256=6bd6184f1dc45742eba93845a7b6f3b9025c92a7897fc5078ccbfa9bdac27263
readonly generated_runner_sha256=bd1310ca45b5787c25cc902e7f62474c3b982d0d6fe6fbbf7cadfe570633ac66

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-dual-node-caddy-postactivation-action20j-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_a_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20j_a_regression_label" >&2
    return 1
}
write_fixture() {
    local action20j_a_fixture_role=$1
    local action20j_a_fixture_path=$2
    local action20j_a_fixture_caddy_count
    local action20j_a_fixture_dns_count
    local action20j_a_fixture_state
    local action20j_a_fixture_label
    local action20j_a_fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    if [[ "$action20j_a_fixture_role" = node-a ]]; then
        action20j_a_fixture_caddy_count=1
        action20j_a_fixture_dns_count=1
        action20j_a_fixture_state=MASTER
    else
        action20j_a_fixture_caddy_count=0
        action20j_a_fixture_dns_count=0
        action20j_a_fixture_state=BACKUP
    fi
    {
        while IFS= read -r action20j_a_fixture_label; do
            printf 'action_20j_a_probe_assertion_%s=true\n' "$action20j_a_fixture_label"
        done < <(/bin/bash "$generated_probe" --expected-assertions)
        printf '%s\n' \
            "action_20j_a_probe_value_node_role=$action20j_a_fixture_role" \
            "action_20j_a_probe_value_expected_vrrp_state=$action20j_a_fixture_state" \
            "action_20j_a_probe_value_caddy_ipv4_count=$action20j_a_fixture_caddy_count" \
            "action_20j_a_probe_value_caddy_ipv6_count=$action20j_a_fixture_caddy_count" \
            "action_20j_a_probe_value_dns_ipv4_count=$action20j_a_fixture_dns_count" \
            "action_20j_a_probe_value_dns_ipv6_count=$action20j_a_fixture_dns_count" \
            "action_20j_a_probe_value_before_snapshot_sha256=$action20j_a_fixture_hash" \
            "action_20j_a_probe_value_after_snapshot_sha256=$action20j_a_fixture_hash" \
            "action_20j_a_probe_assertion_count=$(/bin/bash "$generated_probe" --expected-assertions | wc -l)" \
            action_20j_a_probe_failed_assertion_count=0 \
            action_20j_a_probe_first_failure=none \
            action_20j_a_probe_health_helper_invoked=true \
            action_20j_a_probe_health_execution_context=999:998:clear-groups \
            "action_20j_a_probe_keepalived_journal_since=2026-08-06 17:38:00-05:00" \
            action_20j_a_probe_keepalived_journal_captured=true \
            action_20j_a_probe_notification_helper_invoked=false \
            action_20j_a_probe_filesystem_mutations=false \
            action_20j_a_probe_service_mutations=false \
            action_20j_a_probe_keepalived_mutations=false \
            action_20j_a_probe_vrrp_mutations=false \
            action_20j_a_probe_vip_mutations=false \
            action_20j_a_probe_network_mutations=false \
            action_20j_a_probe_persistent_mutations=false \
            action_20j_a_probe_remote_cleanup_complete=true \
            action_20j_a_probe_remote_complete=true
    } >"$action20j_a_fixture_path"
}
run_intercepted() {
    local action20j_a_run_name=$1
    local action20j_a_expected_status=$2
    local action20j_a_run_stdout=$regression_root/$action20j_a_run_name.stdout
    local action20j_a_run_stderr=$regression_root/$action20j_a_run_name.stderr
    local action20j_a_observed_status=0

    : >"$regression_root/order"
    : >"$regression_root/node-a.stdin"
    : >"$regression_root/node-b.stdin"
    CADDY_ACTION20J_A_SSH_BINARY=$regression_root/fake-ssh \
        CADDY_TEST_ORDER=$regression_root/order \
        CADDY_TEST_NODE_A_FIXTURE=$regression_root/node-a.fixture \
        CADDY_TEST_NODE_B_FIXTURE=$regression_root/node-b.fixture \
        CADDY_TEST_NODE_A_STDIN=$regression_root/node-a.stdin \
        CADDY_TEST_NODE_B_STDIN=$regression_root/node-b.stdin \
        /bin/bash "$generated_runner" >"$action20j_a_run_stdout" \
        2>"$action20j_a_run_stderr" || action20j_a_observed_status=$?
    [[ "$action20j_a_observed_status" -eq "$action20j_a_expected_status" ]] || return 1
    if [[ "$action20j_a_expected_status" -eq 0 ]]; then
        [[ ! -s "$action20j_a_run_stderr" ]] || return 1
        grep -Fqx 'action_20j_a_acceptance_complete=true' "$action20j_a_run_stdout" || return 1
        [[ "$(tr '\n' ' ' <"$regression_root/order")" = 'node-b node-a ' ]] || return 1
        cmp -s "$generated_probe" "$regression_root/node-a.stdin" || return 1
        cmp -s "$generated_probe" "$regression_root/node-b.stdin" || return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20j-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM
readonly generated_root=$regression_root/generated
install -d -m 0700 "$generated_root"
/bin/bash "$builder" --output "$generated_root" >"$regression_root/builder.stdout"
readonly generated_probe=$generated_root/inspect-dual-node-caddy-postactivation-action20j-a.sh
readonly generated_runner=$generated_root/run-dual-node-caddy-postactivation-action20j-a.sh

cat >"$regression_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
for argument in "$@"; do
    case "$argument" in
        pi@10.1.0.54)
            printf 'node-b\n' >>"$CADDY_TEST_ORDER"
            cat >"$CADDY_TEST_NODE_B_STDIN"
            cat "$CADDY_TEST_NODE_B_FIXTURE"
            exit 0
            ;;
        pi@10.1.0.53)
            printf 'node-a\n' >>"$CADDY_TEST_ORDER"
            cat >"$CADDY_TEST_NODE_A_STDIN"
            cat "$CADDY_TEST_NODE_A_FIXTURE"
            exit 0
            ;;
    esac
done
exit 64
FAKE_SSH
chmod 0700 "$regression_root/fake-ssh"

record_check builder_hash_exact test "$(file_hash "$builder")" = "$builder_sha256"
record_check generated_probe_hash_exact test \
    "$(file_hash "$generated_probe")" = "$generated_probe_sha256"
record_check generated_runner_hash_exact test \
    "$(file_hash "$generated_runner")" = "$generated_runner_sha256"
record_check generated_probe_assertion_count test \
    "$(/bin/bash "$generated_probe" --expected-assertions | wc -l)" -eq 58
record_check generated_probe_assertion_labels_unique test \
    "$(/bin/bash "$generated_probe" --expected-assertions | LC_ALL=C sort | uniq -d | wc -l)" -eq 0
record_check generated_probe_ttl_gate grep -Fq journal_no_ttl_hl_rejection \
    "$generated_probe"
# The dollar expressions are an intentional literal generated-source contract.
# shellcheck disable=SC2016
record_check generated_probe_exact_context grep -Fq \
    'setpriv --reuid "$script_uid" --regid "$tls_gid" --clear-groups' \
    "$generated_probe"

write_fixture node-b "$regression_root/node-b.fixture"
write_fixture node-a "$regression_root/node-a.fixture"
record_check valid_production_path_accepted run_intercepted valid 0

cp "$regression_root/node-b.fixture" "$regression_root/node-b.valid"
sed -i '/probe_assertion_journal_no_ttl_hl_rejection=true/d' \
    "$regression_root/node-b.fixture"
record_check missing_ttl_assertion_rejected run_intercepted missing-ttl 1
cp "$regression_root/node-b.valid" "$regression_root/node-b.fixture"
sed -i 's/probe_assertion_journal_no_ttl_hl_rejection=true/probe_assertion_journal_no_ttl_hl_rejection=false/' \
    "$regression_root/node-b.fixture"
record_check false_ttl_assertion_rejected run_intercepted false-ttl 1
cp "$regression_root/node-b.valid" "$regression_root/node-b.fixture"
printf 'action_20j_a_probe_assertion_journal_no_ttl_hl_rejection=true\n' \
    >>"$regression_root/node-b.fixture"
record_check duplicate_ttl_assertion_rejected run_intercepted duplicate-ttl 1
cp "$regression_root/node-b.valid" "$regression_root/node-b.fixture"
sed -i 's/probe_value_expected_vrrp_state=BACKUP/probe_value_expected_vrrp_state=MASTER/' \
    "$regression_root/node-b.fixture"
record_check node_b_master_rejected run_intercepted node-b-master 1
cp "$regression_root/node-b.valid" "$regression_root/node-b.fixture"

cp "$regression_root/node-a.fixture" "$regression_root/node-a.valid"
sed -i 's/probe_value_caddy_ipv6_count=1/probe_value_caddy_ipv6_count=0/' \
    "$regression_root/node-a.fixture"
record_check missing_ipv6_owner_rejected run_intercepted missing-ipv6-owner 1
cp "$regression_root/node-a.valid" "$regression_root/node-a.fixture"

record_check builder_complete grep -Fqx 'action_20j_a_builder_complete=true' \
    "$regression_root/builder.stdout"
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
