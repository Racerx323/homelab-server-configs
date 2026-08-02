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
readonly inspector="$caddy_root/scripts/diagnose-node-a-ssh-g-stderr-action17r-b.sh"
readonly runner="$caddy_root/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly inspector_sha256=d892f6e06fee2edfbdcdc5a5d559bafb5234a675b0a2d42d8eb23fd77e85bf96
readonly runner_sha256=42073901bd8f4faf92f84c24c9e1e84d8ee26607aab7ef42eec0cf911f91cd83
readonly notice='Pseudo-terminal will not be allocated because stdin is not a terminal.'

report_regression_failure() {
    local failure_status=$?
    local failure_line=${BASH_LINENO[0]}

    printf 'action_17r_b_regression_failure_line=%s\n' "$failure_line" >&2
    printf 'action_17r_b_regression_failure_status=%s\n' "$failure_status" >&2
    exit "$failure_status"
}
trap report_regression_failure ERR

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

line_count() {
    awk 'END { print NR + 0 }' "$1"
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

encoded_value() {
    local source_file=$1
    local encoded

    encoded=$(base64 -w 0 "$source_file")
    printf '%s\n' "${encoded:-empty}"
}

write_fixture() {
    local destination=$1
    local ipv4_file=$2
    local ipv4_class=$3
    local ipv6_file=$4
    local ipv6_class=$5
    local fixture_label
    local assertion_total

    assertion_total=$(extract_source_labels "$inspector" | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17r_b_node_a_assertion_%s=true\n' "$fixture_label"
        done < <(extract_source_labels "$inspector")
        printf '%s\n' \
            action_17r_b_node_a_value_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            action_17r_b_node_a_value_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            action_17r_b_node_a_value_ipv4_ssh_g_status=0 \
            "action_17r_b_node_a_value_ipv4_stderr_bytes=$(stat -c '%s' "$ipv4_file")" \
            "action_17r_b_node_a_value_ipv4_stderr_lines=$(line_count "$ipv4_file")" \
            "action_17r_b_node_a_value_ipv4_stderr_sha256=$(file_hash "$ipv4_file")" \
            "action_17r_b_node_a_value_ipv4_stderr_classification=$ipv4_class" \
            "action_17r_b_node_a_value_ipv4_stderr_base64=$(encoded_value "$ipv4_file")" \
            action_17r_b_node_a_value_ipv6_ssh_g_status=0 \
            "action_17r_b_node_a_value_ipv6_stderr_bytes=$(stat -c '%s' "$ipv6_file")" \
            "action_17r_b_node_a_value_ipv6_stderr_lines=$(line_count "$ipv6_file")" \
            "action_17r_b_node_a_value_ipv6_stderr_sha256=$(file_hash "$ipv6_file")" \
            "action_17r_b_node_a_value_ipv6_stderr_classification=$ipv6_class" \
            "action_17r_b_node_a_value_ipv6_stderr_base64=$(encoded_value "$ipv6_file")" \
            "action_17r_b_node_a_assertion_count=$assertion_total" \
            action_17r_b_node_a_failed_assertion_count=0 \
            action_17r_b_node_a_first_failure=none \
            action_17r_b_node_a_peer_connection_executed=false \
            action_17r_b_node_a_restricted_command_executed=false \
            action_17r_b_node_a_release_transfer_executed=false \
            action_17r_b_node_a_marker_mutation=false \
            action_17r_b_node_a_helper_invocation=false \
            action_17r_b_node_a_service_mutations=false \
            action_17r_b_node_a_persistent_mutations=false \
            action_17r_b_node_a_remote_complete=true
    } >"$destination"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'printf "%s\n" "$*" >"$ACTION17RB_CAPTURE_ARGS"' \
        'cat >"$ACTION17RB_CAPTURE_INSPECTOR"' \
        'if [[ -n "${ACTION17RB_REMOTE_ERROR:-}" ]]; then printf "%s\n" "$ACTION17RB_REMOTE_ERROR" >&2; fi' \
        'cat "$ACTION17RB_REMOTE_FIXTURE"' \
        'exit "$ACTION17RB_REMOTE_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_root=$1
    local case_runner=$2
    local case_name=$3
    local fixture_path=$4
    local remote_status=$5
    local remote_error=${6:-}

    observed_status=0
    ACTION17RB_CAPTURE_ARGS="$case_root/$case_name.args" \
        ACTION17RB_CAPTURE_INSPECTOR="$case_root/$case_name.inspector" \
        ACTION17RB_REMOTE_FIXTURE="$fixture_path" \
        ACTION17RB_REMOTE_STATUS="$remote_status" \
        ACTION17RB_REMOTE_ERROR="$remote_error" \
        "$case_runner" >"$case_root/$case_name.out" \
        2>"$case_root/$case_name.err" || observed_status=$?
}

run_production_path_regression() {
    local case_root
    local case_bin
    local case_runner
    local copied_inspector
    local copied_inspector_hash
    local mismatch_fixture
    local duplicate_fixture
    local secret_fixture

    case_root=$(mktemp -d /tmp/caddy-action17r-b-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 "$case_bin" "$case_root/Caddy/scripts" \
        "$case_root/Caddy/tests"
    cp -- "$inspector" "$runner" "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    case_runner="$case_root/Caddy/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh"
    copied_inspector="$case_root/Caddy/scripts/diagnose-node-a-ssh-g-stderr-action17r-b.sh"
    write_fake_ssh "$case_bin/ssh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
    sed -i '/^verify_workstation_metadata$/s/.*/true/' "$case_runner"
    copied_inspector_hash=$(file_hash "$copied_inspector")
    sed -i \
        "s|^readonly inspector_sha256=.*$|readonly inspector_sha256=$copied_inspector_hash|" \
        "$case_runner"
    chmod 0755 "$case_runner" "$copied_inspector" \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"

    : >"$case_root/empty"
    printf '%s\n' "$notice" >"$case_root/notice"
    printf 'safe diagnostic text\n' >"$case_root/safe-other"
    printf '%s\n' 'Authorization: Bearer regression-secret' >"$case_root/secret"
    write_fixture "$case_root/notice.fixture" \
        "$case_root/notice" pseudo_terminal_not_allocated \
        "$case_root/notice" pseudo_terminal_not_allocated
    write_fixture "$case_root/empty.fixture" \
        "$case_root/empty" empty "$case_root/empty" empty
    write_fixture "$case_root/mixed.fixture" \
        "$case_root/notice" pseudo_terminal_not_allocated \
        "$case_root/safe-other" safe_unclassified

    run_case "$case_root" "$case_runner" valid_notice \
        "$case_root/notice.fixture" 0
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/valid_notice.err" ]]
    grep -Fxq action_17r_b_runner_acceptance=true \
        "$case_root/valid_notice.out"
    grep -Fxq \
        action_17r_b_diagnostic_conclusion=pseudo_terminal_notice_confirmed_dual_stack \
        "$case_root/valid_notice.out"
    grep -Fxq action_17r_b_runner_assertion_ipv4_classification_matches_decoded=true \
        "$case_root/valid_notice.out"
    grep -Fxq action_17r_b_runner_assertion_ipv6_classification_matches_decoded=true \
        "$case_root/valid_notice.out"
    cmp -s "$inspector" "$case_root/valid_notice.inspector"
    grep -Fq 'pi@10.1.0.53' "$case_root/valid_notice.args"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$case_root/valid_notice.args"
    if grep -Fq 'IdentitiesOnly=yes' "$case_root/valid_notice.args"; then
        printf 'Administrative SSH unexpectedly used IdentitiesOnly.\n' >&2
        return 1
    fi

    run_case "$case_root" "$case_runner" false_negative_empty \
        "$case_root/empty.fixture" 0
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17r_b_diagnostic_conclusion=stderr_empty_dual_stack \
        "$case_root/false_negative_empty.out"
    grep -Fxq action_17r_b_runner_acceptance=true \
        "$case_root/false_negative_empty.out"

    run_case "$case_root" "$case_runner" false_negative_mixed \
        "$case_root/mixed.fixture" 0
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17r_b_diagnostic_conclusion=safe_stderr_classification_captured \
        "$case_root/false_negative_mixed.out"
    grep -Fxq action_17r_b_runner_acceptance=true \
        "$case_root/false_negative_mixed.out"

    mismatch_fixture="$case_root/mismatch.fixture"
    sed \
        's/action_17r_b_node_a_value_ipv6_stderr_classification=pseudo_terminal_not_allocated/action_17r_b_node_a_value_ipv6_stderr_classification=empty/' \
        "$case_root/notice.fixture" >"$mismatch_fixture"
    run_case "$case_root" "$case_runner" false_positive_classification \
        "$mismatch_fixture" 0
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_b_runner_assertion_ipv6_classification_matches_decoded=false \
        "$case_root/false_positive_classification.out"
    grep -Fxq action_17r_b_runner_acceptance=false \
        "$case_root/false_positive_classification.out"

    duplicate_fixture="$case_root/duplicate.fixture"
    cp -- "$case_root/notice.fixture" "$duplicate_fixture"
    printf 'action_17r_b_node_a_value_ipv4_stderr_bytes=1\n' >>"$duplicate_fixture"
    run_case "$case_root" "$case_runner" false_positive_duplicate \
        "$duplicate_fixture" 0
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_b_runner_assertion_ipv4_bytes_numeric=false \
        "$case_root/false_positive_duplicate.out"

    write_fixture "$case_root/secret-base.fixture" \
        "$case_root/notice" pseudo_terminal_not_allocated \
        "$case_root/notice" pseudo_terminal_not_allocated
    secret_fixture="$case_root/secret.fixture"
    sed \
        -e "s|^action_17r_b_node_a_value_ipv4_stderr_bytes=.*$|action_17r_b_node_a_value_ipv4_stderr_bytes=$(stat -c '%s' "$case_root/secret")|" \
        -e "s|^action_17r_b_node_a_value_ipv4_stderr_lines=.*$|action_17r_b_node_a_value_ipv4_stderr_lines=$(line_count "$case_root/secret")|" \
        -e "s|^action_17r_b_node_a_value_ipv4_stderr_sha256=.*$|action_17r_b_node_a_value_ipv4_stderr_sha256=$(file_hash "$case_root/secret")|" \
        -e "s|^action_17r_b_node_a_value_ipv4_stderr_base64=.*$|action_17r_b_node_a_value_ipv4_stderr_base64=$(encoded_value "$case_root/secret")|" \
        "$case_root/secret-base.fixture" >"$secret_fixture"
    run_case "$case_root" "$case_runner" false_positive_secret \
        "$secret_fixture" 0
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_b_runner_assertion_ipv4_decoded_secret_free=false \
        "$case_root/false_positive_secret.out"
    if grep -Fq 'regression-secret' \
        "$case_root/false_positive_secret.out" "$case_root/false_positive_secret.err"; then
        printf 'Decoded unsafe stderr reached runner output.\n' >&2
        return 1
    fi

    run_case "$case_root" "$case_runner" remote_stderr \
        "$case_root/notice.fixture" 0 'unexpected administrative stderr'
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_b_runner_assertion_remote_stderr_empty=false \
        "$case_root/remote_stderr.out"

    trap - RETURN
    rm -rf -- "$case_root"
}

[[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
[[ "$(file_hash "$runner")" = "$runner_sha256" ]]
bash -n "$inspector" "$runner"
shellcheck -x "$inspector" "$runner"
"$collision_checker" "$inspector" "$runner" >/dev/null
"$inspector" --self-test >/dev/null
"$inspector" --contract-test >/dev/null
"$runner" --self-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
"$runner" --contract-test >/dev/null
run_production_path_regression
printf 'action_17r_b_node_a_ssh_g_stderr_regression_complete=true\n'
