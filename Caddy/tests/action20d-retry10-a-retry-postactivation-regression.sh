#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_a_retry_regression
readonly builder_sha256=b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3
readonly corrected_probe_sha256=aa86451cea27a257ff9b14ca10e774a6189e4859df3fcf9bb1449f889bff54e2
readonly corrected_runner_sha256=5c7d5b9c3732371b6b3e0b5422b7e1772f723887103f168d827fe1c95cac50a8
readonly historical_probe_sha256=564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84
readonly historical_runner_sha256=f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978
readonly accepted_provenance_outer_sha256=1d65abce9e15efaa2052b954dcf1a9029c1d75deb687f2cd33d51d22b675e0fa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh
readonly historical_probe=$caddy_root/scripts/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly historical_runner=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly accepted_provenance_outer=$caddy_root/scripts/run-node-b-caddy-environment-provenance-action20d-retry10-b-outer.sh

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
    local fixture_count
    local fixture_dns
    local fixture_state
    local fixture_label
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
            printf 'action_20d_retry10_a_retry_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$corrected_probe" --expected-assertions)
        printf '%s\n' \
            "action_20d_retry10_a_retry_probe_value_node_role=$fixture_role" \
            "action_20d_retry10_a_retry_probe_value_expected_vrrp_state=$fixture_state" \
            "action_20d_retry10_a_retry_probe_value_caddy_ipv4_count=$fixture_count" \
            "action_20d_retry10_a_retry_probe_value_caddy_ipv6_count=$fixture_count" \
            "action_20d_retry10_a_retry_probe_value_dns_ipv4_count=$fixture_dns" \
            "action_20d_retry10_a_retry_probe_value_dns_ipv6_count=$fixture_dns" \
            "action_20d_retry10_a_retry_probe_value_before_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_a_retry_probe_value_after_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_a_retry_probe_assertion_count=$(/bin/bash "$corrected_probe" --expected-assertions | wc -l)" \
            action_20d_retry10_a_retry_probe_failed_assertion_count=0 \
            action_20d_retry10_a_retry_probe_first_failure=none \
            action_20d_retry10_a_retry_probe_health_helper_invoked=true \
            action_20d_retry10_a_retry_probe_notification_helper_invoked=false \
            action_20d_retry10_a_retry_probe_filesystem_mutations=false \
            action_20d_retry10_a_retry_probe_service_mutations=false \
            action_20d_retry10_a_retry_probe_keepalived_mutations=false \
            action_20d_retry10_a_retry_probe_vrrp_mutations=false \
            action_20d_retry10_a_retry_probe_vip_mutations=false \
            action_20d_retry10_a_retry_probe_network_mutations=false \
            action_20d_retry10_a_retry_probe_persistent_mutations=false \
            action_20d_retry10_a_retry_probe_remote_cleanup_complete=true \
            action_20d_retry10_a_retry_probe_remote_complete=true
    } >"$fixture_path"
}
run_intercepted() {
    local run_name=$1
    local expected_status=$2
    local run_stdout=$regression_root/$run_name.stdout
    local run_stderr=$regression_root/$run_name.stderr
    local observed_status=0

    : >"$regression_root/order"
    : >"$regression_root/node-a.stdin"
    : >"$regression_root/node-b.stdin"
    CADDY_ACTION20D_RETRY10_A_SSH_BINARY=$regression_root/fake-ssh \
        CADDY_TEST_ORDER=$regression_root/order \
        CADDY_TEST_NODE_A_FIXTURE=$regression_root/node-a.fixture \
        CADDY_TEST_NODE_B_FIXTURE=$regression_root/node-b.fixture \
        CADDY_TEST_NODE_A_STDIN=$regression_root/node-a.stdin \
        CADDY_TEST_NODE_B_STDIN=$regression_root/node-b.stdin \
        /bin/bash "$corrected_runner" >"$run_stdout" 2>"$run_stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    if [[ "$expected_status" -eq 0 ]]; then
        [[ ! -s "$run_stderr" ]] || return 1
        grep -Fqx 'action_20d_retry10_a_retry_acceptance_complete=true' "$run_stdout" || return 1
        [[ "$(tr '\n' ' ' <"$regression_root/order")" = 'node-b node-a ' ]] || return 1
        cmp -s "$corrected_probe" "$regression_root/node-a.stdin" || return 1
        cmp -s "$corrected_probe" "$regression_root/node-b.stdin" || return 1
    fi
}
probe_delta_exact() {
    local normalized_probe=$regression_root/probe.normalized

    awk -v node_a_hash=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8 '
        $0 == "readonly prefix=action_20d_retry10_a_retry_probe" {
            print "readonly prefix=action_20d_retry10_a_probe"
            next
        }
        $0 == "case \"${2:-}\" in" {
            getline
            getline
            getline
            getline
            print "readonly environment_sha256=" node_a_hash
            next
        }
        { print }
    ' "$corrected_probe" >"$normalized_probe"
    cmp -s "$historical_probe" "$normalized_probe"
}
runner_delta_exact() {
    local normalized_runner=$regression_root/runner.normalized

    sed \
        -e 's/action_20d_retry10_a_retry/action_20d_retry10_a/g' \
        -e "s/readonly probe_sha256=$corrected_probe_sha256/readonly probe_sha256=$historical_probe_sha256/" \
        "$corrected_runner" >"$normalized_runner"
    cmp -s "$historical_runner" "$normalized_runner"
}

regression_root=$(mktemp -d /tmp/caddy-action20d-retry10-a-retry-regression.XXXXXX)
readonly regression_root
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT
readonly candidate_root=$regression_root/candidate
install -d -m 0700 "$candidate_root"
/bin/bash "$builder" --output "$candidate_root" >"$regression_root/builder.stdout"
readonly corrected_probe=$candidate_root/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly corrected_runner=$candidate_root/run-dual-node-caddy-postactivation-action20d-retry10-a.sh

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
record_check historical_probe_immutable test \
    "$(file_hash "$historical_probe")" = "$historical_probe_sha256"
record_check historical_runner_immutable test \
    "$(file_hash "$historical_runner")" = "$historical_runner_sha256"
record_check accepted_provenance_outer_immutable test \
    "$(file_hash "$accepted_provenance_outer")" = "$accepted_provenance_outer_sha256"
record_check corrected_probe_hash_exact test \
    "$(file_hash "$corrected_probe")" = "$corrected_probe_sha256"
record_check corrected_runner_hash_exact test \
    "$(file_hash "$corrected_runner")" = "$corrected_runner_sha256"
record_check probe_delta_exact probe_delta_exact
record_check runner_delta_exact runner_delta_exact
record_check corrected_probe_node_a_hash_exact grep -Fqx \
    '    node-a) readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8 ;;' \
    "$corrected_probe"
record_check corrected_probe_node_b_hash_exact grep -Fqx \
    '    node-b) readonly environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113 ;;' \
    "$corrected_probe"

write_fixture node-b "$regression_root/node-b.fixture"
write_fixture node-a "$regression_root/node-a.fixture"
record_check valid_production_path_accepted run_intercepted valid 0

cp "$regression_root/node-a.fixture" "$regression_root/node-a.valid"
sed -i '/retry_probe_assertion_main_hash_exact=true/d' "$regression_root/node-a.fixture"
record_check missing_assertion_rejected run_intercepted missing 1
cp "$regression_root/node-a.valid" "$regression_root/node-a.fixture"
printf 'action_20d_retry10_a_retry_probe_assertion_main_hash_exact=true\n' \
    >>"$regression_root/node-a.fixture"
record_check duplicate_assertion_rejected run_intercepted duplicate 1
cp "$regression_root/node-a.valid" "$regression_root/node-a.fixture"
sed -i 's/retry_probe_assertion_main_hash_exact=true/retry_probe_assertion_main_hash_exact=false/' \
    "$regression_root/node-a.fixture"
record_check false_assertion_rejected run_intercepted false 1
cp "$regression_root/node-a.valid" "$regression_root/node-a.fixture"
sed -i 's/retry_probe_value_caddy_ipv4_count=1/retry_probe_value_caddy_ipv4_count=0/' \
    "$regression_root/node-a.fixture"
record_check wrong_owner_rejected run_intercepted wrong-owner 1

record_check builder_output_complete grep -Fqx \
    'action_20d_retry10_a_retry_builder_complete=true' "$regression_root/builder.stdout"
record_check builder_historical_sources_unchanged grep -Fqx \
    'action_20d_retry10_a_retry_builder_historical_sources_unchanged=true' \
    "$regression_root/builder.stdout"

printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
