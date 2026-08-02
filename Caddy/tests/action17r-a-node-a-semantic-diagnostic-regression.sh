#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly node_a_inspector="$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly baseline_runner="$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r.sh"
readonly diagnostic_runner="$caddy_root/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly node_a_inspector_sha256=e181f2e38f98f9df39bfb4992b4e4f91a786e738566c385becbe722709b931f1
readonly node_b_inspector_sha256=f9abd9952612f7855821c0d09a1de01c64fa540c1782aa24512cd035e7a1cdaf
readonly baseline_runner_sha256=ce8b1ba0641c2a03b9aa593c94ddecd1c27ff3ef73e094820d4bb0dc8b8ec71b
readonly diagnostic_runner_sha256=a8830d8ffb9f1ff9cf671ba7c2f942e5b5799531d503e44ef293f4df3baff3e5
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

report_regression_failure() {
    local failure_status=$?
    local failure_line=${BASH_LINENO[0]}

    printf 'action_17r_a_regression_failure_line=%s\n' "$failure_line" >&2
    printf 'action_17r_a_regression_failure_status=%s\n' "$failure_status" >&2
    exit "$failure_status"
}
trap report_regression_failure ERR

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

extract_source_labels() {
    local source_path=$1

    awk '
        /record_command\(\)/ { next }
        /^[[:space:]]*record_command [a-z0-9_]+/ {
            line = $0
            sub(/^[[:space:]]*record_command /, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            next
        }
        /^[[:space:]]*record_command[[:space:]]*\\$/ {
            getline
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
        }
    ' "$source_path"
}

write_fixture() {
    local fixture_source=$1
    local fixture_prefix=$2
    local fixture_role=$3
    local fixture_path=$4
    local fixture_label

    {
        while IFS= read -r fixture_label; do
            printf '%s_assertion_%s=true\n' "$fixture_prefix" "$fixture_label"
        done < <(extract_source_labels "$fixture_source")
        printf '%s\n' \
            "${fixture_prefix}_value_payload_sha256=$expected_payload_sha256" \
            "${fixture_prefix}_value_manifest_sha256=$expected_manifest_sha256" \
            "${fixture_prefix}_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111" \
            "${fixture_prefix}_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111"
        if [[ "$fixture_role" = node-a ]]; then
            printf '%s_value_source_state=legacy_complete_requires_v2_finalize_request\n' \
                "$fixture_prefix"
        else
            printf '%s\n' \
                "${fixture_prefix}_value_receiver_state=installed_policy_ready" \
                "${fixture_prefix}_value_release_state=payload_ready_awaiting_finalize_request"
        fi
        printf '%s\n' \
            "${fixture_prefix}_assertion_count=$(extract_source_labels "$fixture_source" | wc -l)" \
            "${fixture_prefix}_failed_assertion_count=0" \
            "${fixture_prefix}_first_failure=none" \
            "${fixture_prefix}_peer_connection_executed=false" \
            "${fixture_prefix}_restricted_command_executed=false" \
            "${fixture_prefix}_release_transfer_executed=false" \
            "${fixture_prefix}_marker_mutation=false" \
            "${fixture_prefix}_helper_invocation=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_persistent_mutations=false" \
            "${fixture_prefix}_remote_complete=true"
    } >"$fixture_path"
}

make_node_a_mismatch() {
    local source_fixture=$1
    local destination_fixture=$2

    sed \
        -e 's/action_17r_node_a_assertion_ipv6_bind_address_exact=true/action_17r_node_a_assertion_ipv6_bind_address_exact=false/' \
        -e 's/action_17r_node_a_failed_assertion_count=0/action_17r_node_a_failed_assertion_count=1/' \
        -e 's/action_17r_node_a_first_failure=none/action_17r_node_a_first_failure=ipv6_bind_address_exact/' \
        "$source_fixture" >"$destination_fixture"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'call_count=0' \
        'if [[ -f "$ACTION17RA_CALL_COUNT" ]]; then call_count=$(<"$ACTION17RA_CALL_COUNT"); fi' \
        'call_count=$((call_count + 1))' \
        'printf "%s\n" "$call_count" >"$ACTION17RA_CALL_COUNT"' \
        'printf "%s\n" "$*" >"$ACTION17RA_CAPTURE_DIR/call-$call_count.args"' \
        'cat >"$ACTION17RA_CAPTURE_DIR/call-$call_count.inspector"' \
        'case "$call_count" in' \
        '  1) cat "$ACTION17RA_NODE_B_BEFORE_FIXTURE"; exit 0 ;;' \
        '  2) cat "$ACTION17RA_NODE_A_BASELINE_FIXTURE"; exit "$ACTION17RA_NODE_A_BASELINE_STATUS" ;;' \
        '  3) cat "$ACTION17RA_NODE_B_AFTER_FIXTURE"; exit 0 ;;' \
        '  4) cat "$ACTION17RA_NODE_A_DETAIL_FIXTURE"; exit "$ACTION17RA_NODE_A_DETAIL_STATUS" ;;' \
        '  *) exit 98 ;;' \
        'esac' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_root=$1
    local case_runner=$2
    local case_suffix=$3
    local detail_fixture=$4
    local detail_status=$5
    local node_b_after_fixture=$6
    local baseline_fixture=$7
    local baseline_status=$8

    printf '0\n' >"$case_root/call-count"
    rm -rf -- "$case_root/captured"
    install -d -m 0700 "$case_root/captured"
    observed_status=0
    ACTION17RA_CALL_COUNT="$case_root/call-count" \
        ACTION17RA_CAPTURE_DIR="$case_root/captured" \
        ACTION17RA_NODE_B_BEFORE_FIXTURE="$case_root/node-b.fixture" \
        ACTION17RA_NODE_A_BASELINE_FIXTURE="$baseline_fixture" \
        ACTION17RA_NODE_A_BASELINE_STATUS="$baseline_status" \
        ACTION17RA_NODE_B_AFTER_FIXTURE="$node_b_after_fixture" \
        ACTION17RA_NODE_A_DETAIL_FIXTURE="$detail_fixture" \
        ACTION17RA_NODE_A_DETAIL_STATUS="$detail_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err" || observed_status=$?
}

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner
    local copied_baseline
    local copied_baseline_hash
    local duplicate_fixture
    local unsafe_fixture
    local drift_fixture

    case_root=$(mktemp -d /tmp/caddy-action17r-a-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 "$case_bin" "$case_root/captured" \
        "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$node_a_inspector" "$node_b_inspector" "$baseline_runner" \
        "$diagnostic_runner" "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    case_runner="$case_root/Caddy/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh"
    copied_baseline="$case_root/Caddy/scripts/run-dual-node-protocol-v2-readiness-action17r.sh"
    write_fake_ssh "$case_bin/ssh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" \
        "$copied_baseline" "$case_runner"
    copied_baseline_hash=$(file_hash "$copied_baseline")
    sed -i \
        "s|^readonly baseline_runner_sha256=.*$|readonly baseline_runner_sha256=$copied_baseline_hash|" \
        "$case_runner"
    chmod 0755 "$case_runner" "$case_root/Caddy/scripts/"*.sh \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"

    write_fixture "$node_b_inspector" action_17r_node_b node-b \
        "$case_root/node-b.fixture"
    write_fixture "$node_a_inspector" action_17r_node_a node-a \
        "$case_root/node-a-valid.fixture"
    make_node_a_mismatch "$case_root/node-a-valid.fixture" \
        "$case_root/node-a-mismatch.fixture"

    run_case "$case_root" "$case_runner" valid_mismatch \
        "$case_root/node-a-mismatch.fixture" 1 "$case_root/node-b.fixture" \
        "$case_root/node-a-mismatch.fixture" 1
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/valid_mismatch.err" ]]
    [[ "$(<"$case_root/call-count")" -eq 4 ]]
    grep -Fxq action_17r_a_runner_acceptance=true \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_a_diagnostic_conclusion=node_a_semantic_mismatch_identified \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_a_node_a_first_failure=ipv6_bind_address_exact \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_node_a_assertion_ipv6_bind_address_exact=false \
        "$case_root/valid_mismatch.out"
    [[ "$(grep -Ec '^action_17r_node_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$case_root/valid_mismatch.out")" -eq 52 ]]
    grep -Fxq action_17r_runner_assertion_node_b_before_remote_assertions_passed=true \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_runner_assertion_node_b_after_remote_assertions_passed=true \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_runner_assertion_payload_hashes_cross_node_exact=true \
        "$case_root/valid_mismatch.out"
    grep -Fxq action_17r_runner_assertion_node_b_bab_state_unchanged=true \
        "$case_root/valid_mismatch.out"
    cmp -s "$node_a_inspector" "$case_root/captured/call-4.inspector"
    grep -Fq 'pi@10.1.0.53' "$case_root/captured/call-4.args"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' \
        "$case_root/captured/call-4.args"

    run_case "$case_root" "$case_runner" valid_ready \
        "$case_root/node-a-valid.fixture" 0 "$case_root/node-b.fixture" \
        "$case_root/node-a-valid.fixture" 0
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/valid_ready.err" ]]
    grep -Fxq action_17r_a_runner_acceptance=true \
        "$case_root/valid_ready.out"
    grep -Fxq action_17r_a_diagnostic_conclusion=node_a_ready \
        "$case_root/valid_ready.out"
    [[ "$(grep -Ec '^action_17r_node_a_assertion_[a-z0-9_]+=(true|false)$' \
        "$case_root/valid_ready.out")" -eq 52 ]]

    run_case "$case_root" "$case_runner" false_negative \
        "$case_root/node-a-valid.fixture" 0 "$case_root/node-b.fixture" \
        "$case_root/node-a-mismatch.fixture" 1
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_a_runner_assertion_node_a_status_matches_baseline=false \
        "$case_root/false_negative.out"
    grep -Fxq action_17r_a_runner_acceptance=false \
        "$case_root/false_negative.out"

    duplicate_fixture="$case_root/node-a-duplicate.fixture"
    cp -- "$case_root/node-a-mismatch.fixture" "$duplicate_fixture"
    grep -F 'action_17r_node_a_assertion_ipv6_bind_address_exact=false' \
        "$case_root/node-a-mismatch.fixture" >>"$duplicate_fixture"
    run_case "$case_root" "$case_runner" false_positive \
        "$duplicate_fixture" 1 "$case_root/node-b.fixture" \
        "$case_root/node-a-mismatch.fixture" 1
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_a_runner_assertion_node_a_assertion_labels_unique=false \
        "$case_root/false_positive.out"
    grep -Fxq action_17r_a_runner_acceptance=false \
        "$case_root/false_positive.out"

    unsafe_fixture="$case_root/node-a-unsafe.fixture"
    cp -- "$case_root/node-a-mismatch.fixture" "$unsafe_fixture"
    printf 'PRIVATE_KEY=must-not-be-emitted\n' >>"$unsafe_fixture"
    run_case "$case_root" "$case_runner" unsafe \
        "$unsafe_fixture" 1 "$case_root/node-b.fixture" \
        "$case_root/node-a-mismatch.fixture" 1
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_a_runner_assertion_node_a_secret_free=false \
        "$case_root/unsafe.out"
    if grep -Fq must-not-be-emitted \
        "$case_root/unsafe.out" "$case_root/unsafe.err"; then
        printf 'Unsafe fixture content escaped transcript suppression.\n' >&2
        return 1
    fi

    drift_fixture="$case_root/node-b-drift.fixture"
    sed \
        -e 's/action_17r_node_b_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111/action_17r_node_b_value_before_state_sha256=2222222222222222222222222222222222222222222222222222222222222222/' \
        -e 's/action_17r_node_b_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111/action_17r_node_b_value_after_state_sha256=2222222222222222222222222222222222222222222222222222222222222222/' \
        "$case_root/node-b.fixture" >"$drift_fixture"
    run_case "$case_root" "$case_runner" node_b_drift \
        "$case_root/node-a-mismatch.fixture" 1 "$drift_fixture" \
        "$case_root/node-a-mismatch.fixture" 1
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_a_runner_assertion_baseline_node_b_bab_state_unchanged=false \
        "$case_root/node_b_drift.out"
    grep -Fxq action_17r_a_runner_acceptance=false \
        "$case_root/node_b_drift.out"
}

[[ "$(file_hash "$node_a_inspector")" = "$node_a_inspector_sha256" ]]
[[ "$(file_hash "$node_b_inspector")" = "$node_b_inspector_sha256" ]]
[[ "$(file_hash "$baseline_runner")" = "$baseline_runner_sha256" ]]
[[ "$(file_hash "$diagnostic_runner")" = "$diagnostic_runner_sha256" ]]
bash -n "$diagnostic_runner"
shellcheck "$diagnostic_runner"
"$collision_checker" "$diagnostic_runner" "$0" >/dev/null
"$diagnostic_runner" --self-test >/dev/null
"$diagnostic_runner" --source-test >/dev/null
"$diagnostic_runner" --contract-test >/dev/null
"$source_context_policy" --runner "$diagnostic_runner" >/dev/null
run_production_path_regression

printf 'action_17r_a_node_a_semantic_diagnostic_regression_complete=true\n'
