#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_b_regression
readonly probe_sha256=7c9f989f21c09de85810b6e7ffc8b7c77600ec0fffe90ba55ce94a18de7018fe
readonly runner_sha256=6cf8bdd0cfed2699fa3ccd7d9ca00d2673e3ce8b7636f9826b9a7701d4c9d85e
readonly accepted_failed_outer_sha256=e680404b76803d1c975af60d71f4d18865ab7a04dd6099e550dd1caf142dc44c
readonly expected_node_b_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly probe=$caddy_root/scripts/inspect-node-b-caddy-environment-provenance-action20d-retry10-b.sh
readonly runner=$caddy_root/scripts/run-node-b-caddy-environment-provenance-action20d-retry10-b.sh
readonly accepted_failed_outer=$caddy_root/scripts/run-dual-node-caddy-postactivation-action20d-retry10-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
multi_file_match_count() {
    local count_pattern=$1
    local count_path
    local count_total=0

    shift
    for count_path in "$@"; do
        count_total=$((count_total + $(grep -Ec "$count_pattern" "$count_path" || true)))
    done
    printf '%s\n' "$count_total"
}
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
    local fixture_path=$1
    local fixture_hash=$2
    local fixture_classification=$3
    local fixture_label
    local fixture_key
    local fixture_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20d_retry10_b_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        printf '%s\n' \
            "action_20d_retry10_b_probe_value_environment_sha256=$fixture_hash" \
            "action_20d_retry10_b_probe_value_expected_node_b_environment_sha256=$expected_node_b_environment_sha256" \
            action_20d_retry10_b_probe_value_rejected_node_a_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8 \
            "action_20d_retry10_b_probe_value_source_classification=$fixture_classification" \
            action_20d_retry10_b_probe_value_package_classification=locally_managed \
            action_20d_retry10_b_probe_value_environment_metadata=root:caddy-tls:640:256:1:1:1
        while IFS= read -r fixture_key; do
            printf 'action_20d_retry10_b_probe_value_line_%s_sha256=%s\n' \
                "${fixture_key,,}" "$fixture_sha"
        done < <(/bin/bash "$probe" --expected-keys)
        printf '%s\n' \
            "action_20d_retry10_b_probe_value_before_snapshot_sha256=$fixture_sha" \
            "action_20d_retry10_b_probe_value_after_snapshot_sha256=$fixture_sha" \
            "action_20d_retry10_b_probe_assertion_count=$(/bin/bash "$probe" --expected-assertions | wc -l)" \
            action_20d_retry10_b_probe_failed_assertion_count=0 \
            action_20d_retry10_b_probe_first_failure=none \
            action_20d_retry10_b_probe_environment_values_emitted=false \
            action_20d_retry10_b_probe_health_helper_invoked=false \
            action_20d_retry10_b_probe_notification_helper_invoked=false \
            action_20d_retry10_b_probe_node_a_contacted=false \
            action_20d_retry10_b_probe_filesystem_mutations=false \
            action_20d_retry10_b_probe_service_mutations=false \
            action_20d_retry10_b_probe_keepalived_mutations=false \
            action_20d_retry10_b_probe_vrrp_mutations=false \
            action_20d_retry10_b_probe_vip_mutations=false \
            action_20d_retry10_b_probe_network_mutations=false \
            action_20d_retry10_b_probe_persistent_mutations=false \
            action_20d_retry10_b_probe_remote_complete=true
    } >"$fixture_path"
}
run_case() {
    local case_name=$1
    local expected_status=$2
    local case_stdout=$regression_root/$case_name.stdout
    local case_stderr=$regression_root/$case_name.stderr
    local observed_status=0

    : >"$regression_root/ssh.args"
    : >"$regression_root/stdin"
    CADDY_ACTION20D_RETRY10_B_SSH_BINARY=$regression_root/fake-ssh \
        CADDY_TEST_TRANSCRIPT=$regression_root/transcript \
        CADDY_TEST_ARGS=$regression_root/ssh.args \
        CADDY_TEST_STDIN=$regression_root/stdin \
        /bin/bash "$runner" >"$case_stdout" 2>"$case_stderr" || observed_status=$?
    [[ "$observed_status" -eq "$expected_status" ]] || return 1
    if [[ "$expected_status" -eq 0 ]]; then
        [[ ! -s "$case_stderr" ]] || return 1
        grep -Fqx 'action_20d_retry10_b_diagnostic_complete=true' "$case_stdout" || return 1
        grep -Fqx -- \
            '-T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s' \
            "$regression_root/ssh.args" || return 1
        cmp -s "$probe" "$regression_root/stdin" || return 1
    fi
}

regression_root=$(mktemp -d /tmp/caddy-action20d-retry10-b-regression.XXXXXX)
readonly regression_root
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT
cat >"$regression_root/fake-ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${CADDY_TEST_ARGS:?}"
cat >"${CADDY_TEST_STDIN:?}"
cat "${CADDY_TEST_TRANSCRIPT:?}"
FAKE_SSH
chmod 0700 "$regression_root/fake-ssh"

record_check probe_hash_exact test "$(file_hash "$probe")" = "$probe_sha256"
record_check runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
record_check accepted_failed_outer_immutable test \
    "$(file_hash "$accepted_failed_outer")" = "$accepted_failed_outer_sha256"
record_check probe_self_test /bin/bash "$probe" --self-test
record_check runner_self_test /bin/bash "$runner" --self-test
record_check runner_contract_test /bin/bash "$runner" --contract-test

write_fixture "$regression_root/transcript" "$expected_node_b_environment_sha256" \
    rendered_node_b_candidate
record_check node_b_candidate_accepted run_case node-b 0

write_fixture "$regression_root/transcript" \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    unrecognized
record_check unrecognized_candidate_diagnosed run_case unrecognized 0

write_fixture "$regression_root/transcript" "$expected_node_b_environment_sha256" \
    rendered_node_b_candidate
sed -i '/probe_assertion_environment_regular=true/d' "$regression_root/transcript"
record_check missing_assertion_rejected run_case missing 1

write_fixture "$regression_root/transcript" "$expected_node_b_environment_sha256" \
    rendered_node_b_candidate
printf 'action_20d_retry10_b_probe_assertion_environment_regular=true\n' \
    >>"$regression_root/transcript"
record_check duplicate_assertion_rejected run_case duplicate 1

write_fixture "$regression_root/transcript" "$expected_node_b_environment_sha256" \
    rendered_node_b_candidate
sed -i 's/probe_assertion_environment_regular=true/probe_assertion_environment_regular=false/' \
    "$regression_root/transcript"
record_check false_assertion_rejected run_case false 1

write_fixture "$regression_root/transcript" "$expected_node_b_environment_sha256" \
    unrecognized
record_check inconsistent_classification_rejected run_case inconsistent 1

record_check no_node_a_ssh_target test \
    "$(multi_file_match_count \
        'pi@10\.1\.0\.53|HostKeyAlias=pihole0\.local\.theama\.co' \
        "$probe" "$runner")" -eq 0
record_check raw_environment_output_absent test \
    "$(grep -Ec 'cat[[:space:]]+["]?[$]environment_file["]?|printf.*[$]environment_line([[:space:]]|$)' \
        "$probe" || true)" -eq 0
record_check helper_invocation_absent test \
    "$(grep -Ec '^[[:space:]]*\"?\$?health_helper\"?[[:space:]]*$' "$probe" || true)" -eq 0
record_check notification_invocation_absent test \
    "$(multi_file_match_count 'lsyncd-ha-failover-notify\.sh[[:space:]]*$' \
        "$probe" "$runner")" -eq 0

printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
