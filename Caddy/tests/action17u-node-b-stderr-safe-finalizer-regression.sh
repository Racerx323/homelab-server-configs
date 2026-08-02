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
readonly candidate="$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly installer="$caddy_root/scripts/install-node-b-stderr-safe-finalizer-action17u.sh"
readonly runner="$caddy_root/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh"
readonly original_finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly action17t_renderer="$caddy_root/scripts/render-node-b-stdout-safe-finalizer-action17t.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly original_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly live_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly candidate_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly historical_action17s_retry_sha256=269c48158969f3767b13ffa92aaef1559bcb0c25c64bb19fdb93e70f56713bd0
readonly historical_action17s_b_runner_sha256=eaba182394c78179f2001833fc14647eec91deae90e2b96896584b6f16f1a4f6
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

report_regression_error() {
    local error_line=$1
    local error_status=$2
    printf 'action_17u_regression_failure_line=%s\n' "$error_line" >&2
    printf 'action_17u_regression_failure_status=%s\n' "$error_status" >&2
}
trap 'report_regression_error "$LINENO" "$?"' ERR

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

write_success_fixture() {
    local fixture_path=$1
    local fixture_label fixture_count

    fixture_count=$("$installer" --expected-checks | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17u_assertion_%s=true\n' "$fixture_label"
        done < <("$installer" --expected-checks)
        printf '%s\n' \
            "action_17u_assertion_count=$fixture_count" \
            action_17u_failed_assertion_count=0 \
            action_17u_first_failure=none \
            action_17u_preflight_complete=true \
            action_17u_mutation_started=true \
            action_17u_value_install_stdout_bytes=0 \
            action_17u_value_install_stdout_lines=0 \
            "action_17u_value_install_stdout_sha256=$empty_sha256" \
            action_17u_value_install_stdout_classification=empty \
            action_17u_install_stdout_raw_emitted=false \
            action_17u_value_install_stderr_bytes=0 \
            action_17u_value_install_stderr_lines=0 \
            "action_17u_value_install_stderr_sha256=$empty_sha256" \
            action_17u_value_install_stderr_classification=empty \
            action_17u_install_stderr_raw_emitted=false \
            "action_17u_value_old_finalizer_sha256=$live_finalizer_sha256" \
            "action_17u_value_new_finalizer_sha256=$candidate_sha256" \
            action_17u_value_revision=action17p-node-a-to-node-b-bootstrap \
            action_17u_value_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.ABC123 \
            action_17u_finalizer_invoked=false \
            action_17u_release_mutated=false \
            action_17u_marker_mutated=false \
            action_17u_lsyncd_reconciliation_activation=false \
            action_17u_service_mutations=false \
            action_17u_persistent_mutation_scope=stderr_safe_finalizer,rollback_backup \
            action_17u_node_b_stderr_safe_finalizer_install_complete=true
    } >"$fixture_path"
}

write_rollback_fixture() {
    local fixture_path=$1
    local fixture_label

    {
        printf '%s\n' \
            action_17u_rollback_started=true \
            action_17u_value_rollback_install_stdout_bytes=0 \
            action_17u_value_rollback_install_stdout_lines=0 \
            "action_17u_value_rollback_install_stdout_sha256=$empty_sha256" \
            action_17u_value_rollback_install_stdout_classification=empty \
            action_17u_rollback_install_stdout_raw_emitted=false \
            action_17u_value_rollback_install_stderr_bytes=0 \
            action_17u_value_rollback_install_stderr_lines=0 \
            "action_17u_value_rollback_install_stderr_sha256=$empty_sha256" \
            action_17u_value_rollback_install_stderr_classification=empty \
            action_17u_rollback_install_stderr_raw_emitted=false
        while IFS= read -r fixture_label; do
            printf 'action_17u_rollback_assertion_%s=true\n' "$fixture_label"
        done < <("$installer" --expected-rollback-checks)
        printf 'action_17u_rollback_complete=true\n'
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only inside the intercepted test process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17U_CAPTURED_BUNDLE"' \
        'printf "%s\n" "$*" >"$ACTION17U_SSH_ARGUMENTS"' \
        'cat "$ACTION17U_FIXTURE_OUTPUT"' \
        'cat "$ACTION17U_FIXTURE_ERROR" >&2' \
        'exit "$ACTION17U_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local case_runner=$4
    local case_status=$5
    local case_suffix=$6

    if ACTION17U_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
        ACTION17U_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION17U_FIXTURE_OUTPUT="$case_output" \
        ACTION17U_FIXTURE_ERROR="$case_error" \
        ACTION17U_STATUS="$case_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err"; then
        observed_status=0
    else
        observed_status=$?
    fi
}

run_finalizer_capture_regression() {
    local behavior_root=$1
    local extracted_library="$behavior_root/finalizer-library.sh"
    local fake_bin="$behavior_root/bin"
    local harness="$behavior_root/harness.sh"
    local validation_tmp="$behavior_root/tmp"

    install -d -m 0700 "$fake_bin" "$validation_tmp"
    sed -n '/^if \[\[ "${1:-}" == --self-test/q;p' "$candidate" |
        sed "s|^PATH=/usr/sbin:/usr/bin:/sbin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" \
            >"$extracted_library"
    # The environment variable is intentionally expanded by the harness.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'source "$ACTION17U_LIBRARY"' \
            'NODE_FQDN=pihole00.local.theama.co' \
            'NODE_IPV4=10.1.0.54' \
            'NODE_IPV6=fd36:5aa8:6971:1::54' \
            'export NODE_FQDN NODE_IPV4 NODE_IPV6' \
            'validate_caddy_configuration /tmp/release'
    } >"$harness"
    chmod 0755 "$harness"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "unexpected-success-stdout\n"' \
        'printf "expected-success-info\n" >&2' \
        'exit 0' >"$fake_bin/caddy"
    chmod 0755 "$fake_bin/caddy"
    ACTION17U_LIBRARY="$extracted_library" TMPDIR="$validation_tmp" "$harness" \
        >"$behavior_root/success.out" 2>"$behavior_root/success.err"
    [[ ! -s "$behavior_root/success.out" ]]
    [[ ! -s "$behavior_root/success.err" ]]

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "unexpected-failure-stdout\n"' \
        'printf "expected-validation-error\n" >&2' \
        'exit 42' >"$fake_bin/caddy"
    chmod 0755 "$fake_bin/caddy"
    failure_status=0
    ACTION17U_LIBRARY="$extracted_library" TMPDIR="$validation_tmp" "$harness" \
        >"$behavior_root/failure.out" 2>"$behavior_root/failure.err" ||
        failure_status=$?
    [[ "$failure_status" -eq 42 ]]
    [[ ! -s "$behavior_root/failure.out" ]]
    [[ "$(cat "$behavior_root/failure.err")" = expected-validation-error ]]
    [[ -z "$(find "$validation_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

run_real_caddy_regression() {
    local real_root=$1
    local extracted_library="$real_root/finalizer-library.sh"
    local harness="$real_root/harness.sh"
    local validation_tmp="$real_root/tmp"
    local valid_release="$real_root/valid-release"
    local invalid_release="$real_root/invalid-release"
    local invalid_status=0

    if ! command -v caddy >/dev/null 2>&1; then
        printf 'action_17u_real_caddy_behavior_validated=skipped\n'
        return 0
    fi

    install -d -m 0700 \
        "$validation_tmp" "$valid_release" "$invalid_release"
    sed -n '/^if \[\[ "${1:-}" == --self-test/q;p' "$candidate" \
        >"$extracted_library"
    # The environment variable is intentionally expanded by the harness.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'source "$ACTION17U_LIBRARY"' \
            'NODE_FQDN=pihole00.local.theama.co' \
            'NODE_IPV4=10.1.0.54' \
            'NODE_IPV6=fd36:5aa8:6971:1::54' \
            'export NODE_FQDN NODE_IPV4 NODE_IPV6' \
            'validate_caddy_configuration "$ACTION17U_RELEASE"'
    } >"$harness"
    chmod 0755 "$harness"
    printf '%s\n' \
        '{' \
        '    admin off' \
        '    auto_https off' \
        '}' \
        ':8088 {' \
        '    respond "ok"' \
        '}' >"$valid_release/Caddyfile"
    printf '%s\n' 'this is not valid caddy syntax {' >"$invalid_release/Caddyfile"

    ACTION17U_LIBRARY="$extracted_library" \
        ACTION17U_RELEASE="$valid_release" TMPDIR="$validation_tmp" \
        "$harness" >"$real_root/valid.out" 2>"$real_root/valid.err"
    [[ ! -s "$real_root/valid.out" && ! -s "$real_root/valid.err" ]]

    ACTION17U_LIBRARY="$extracted_library" \
        ACTION17U_RELEASE="$invalid_release" TMPDIR="$validation_tmp" \
        "$harness" >"$real_root/invalid.out" 2>"$real_root/invalid.err" ||
        invalid_status=$?
    [[ "$invalid_status" -ne 0 ]]
    [[ ! -s "$real_root/invalid.out" ]]
    [[ -s "$real_root/invalid.err" ]]
    [[ -z "$(find "$validation_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ]]
    printf 'action_17u_real_caddy_behavior_validated=true\n'
}

run_production_runner_regression() {
    local runner_regression_root=$1
    local fake_bin="$runner_regression_root/bin"
    local case_runner="$runner_regression_root/Caddy/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh"
    local empty_error="$runner_regression_root/empty.err"
    local valid_output="$runner_regression_root/valid.fixture"
    local rollback_error="$runner_regression_root/rollback.err.fixture"
    local rollback_output="$runner_regression_root/rollback.out.fixture"

    install -d -m 0700 "$fake_bin" "$runner_regression_root/Caddy/scripts" "$runner_regression_root/Caddy/tests"
    cp -- "$candidate" "$installer" "$runner" "$runner_regression_root/Caddy/scripts/"
    cp -- "$collision_checker" "$runner_regression_root/Caddy/tests/"
    chmod 0755 "$runner_regression_root/Caddy/scripts/"* "$runner_regression_root/Caddy/tests/"*
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" "$case_runner"
    write_fake_ssh "$fake_bin/ssh"
    : >"$empty_error"
    write_success_fixture "$valid_output"

    run_case "$empty_error" "$valid_output" "$runner_regression_root" "$case_runner" 0 valid
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17u_runner_acceptance=true "$runner_regression_root/valid.out"
    grep -Fxq action_17u_remote_stdout_safe_content_begin=true "$runner_regression_root/valid.out"
    grep -Fxq action_17u_remote_stdout_safe_content_end=true "$runner_regression_root/valid.out"
    grep -Fxq action_17u_remote_stdout_content_secured=emitted "$runner_regression_root/valid.out"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$runner_regression_root/valid.arguments"
    awk '/<<.*ACTION17U_ARCHIVE/ { capture = 1; next } capture && /^ACTION17U_ARCHIVE$/ { exit } capture { print }' \
        "$runner_regression_root/valid.bundle" | base64 -d \
        >"$runner_regression_root/valid.payload.tar"
    tar -tf "$runner_regression_root/valid.payload.tar" \
        >"$runner_regression_root/valid.payload.list"
    grep -Fxq finalize-incoming-release-v2.sh \
        "$runner_regression_root/valid.payload.list"

    printf 'action_17u_finalizer_invoked=true\n' >>"$valid_output"
    run_case "$empty_error" "$valid_output" "$runner_regression_root" "$case_runner" 0 contradiction
    [[ "$observed_status" -eq 97 ]]

    printf '%s\n' action_17u_preflight_complete=true action_17u_mutation_started=true >"$rollback_output"
    write_rollback_fixture "$rollback_error"
    run_case "$rollback_error" "$rollback_output" "$runner_regression_root" "$case_runner" 1 rollback
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17u_runner_acceptance=false "$runner_regression_root/rollback.out"

    sed -i '/rollback_complete=true/d' "$rollback_error"
    run_case "$rollback_error" "$rollback_output" "$runner_regression_root" "$case_runner" 1 incomplete
    [[ "$observed_status" -eq 97 ]]

    printf 'CADDY_TLS_PRIVATE_KEY_PEM=redacted-test-value\n' >"$runner_regression_root/unsafe.err.fixture"
    run_case "$runner_regression_root/unsafe.err.fixture" "$valid_output" \
        "$runner_regression_root" "$case_runner" 1 unsafe
    [[ "$observed_status" -eq 97 ]]
    protected_path=$(sed -n 's/^action_17u_remote_stderr_protected_path=//p' \
        "$runner_regression_root/unsafe.err" | tail -n 1)
    [[ "$protected_path" =~ ^/tmp/caddy-action17u-runner\.[A-Za-z0-9]+/remote.err$ ]]
    [[ "$(stat -c '%a' "$protected_path")" = 600 ]]
    rm -rf -- "${protected_path%/remote.err}"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$candidate_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17u_regression_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$original_finalizer")" = "$original_finalizer_sha256" ]]
[[ "$(file_hash "$candidate")" = "$candidate_sha256" ]]
[[ "$(file_hash "$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s-retry.sh")" = "$historical_action17s_retry_sha256" ]]
[[ "$(file_hash "$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh")" = "$historical_action17s_b_runner_sha256" ]]

regression_root=$(mktemp -d /tmp/caddy-action17u-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly action17t_candidate="$regression_root/action17t-finalizer"
"$action17t_renderer" --input "$original_finalizer" --output "$action17t_candidate" >/dev/null
[[ "$(file_hash "$action17t_candidate")" = "$live_finalizer_sha256" ]]

bash -n "$candidate" "$installer" "$runner" "$0"
shellcheck "$candidate" "$installer" "$runner" "$0"
"$collision_checker" "$candidate" "$installer" "$runner" "$0" >/dev/null
"$candidate" --self-test >/dev/null
"$installer" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$candidate" "$installer" "$runner"; then
    printf 'Action 17u contains a service mutation.\n' >&2
    exit 1
fi
grep -Fq 'finalizer_invoked=false' "$installer"
grep -Fq 'release_mutated=false' "$installer"
grep -Fq 'marker_mutated=false' "$installer"
grep -Fq 'content_secured=protected_retention' "$runner"

run_finalizer_capture_regression "$regression_root/behavior"
run_real_caddy_regression "$regression_root/real-caddy"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    printf 'action_17u_production_runner_behavior_validated=skipped_host_authoritative\n'
else
    run_production_runner_regression "$regression_root/runner"
    printf 'action_17u_production_runner_behavior_validated=workstation\n'
fi

printf 'action_17u_success_stderr_suppressed=true\n'
printf 'action_17u_failure_stderr_replayed=true\n'
printf 'action_17u_false_negative_valid_success_accepted=true\n'
printf 'action_17u_false_negative_complete_rollback_preserved=true\n'
printf 'action_17u_false_positive_contradiction_rejected=true\n'
printf 'action_17u_false_positive_incomplete_rollback_rejected=true\n'
printf 'action_17u_false_positive_unsafe_output_retained=true\n'
printf 'action_17u_production_path_network_contact=false\n'
printf 'action_17u_node_b_stderr_safe_finalizer_regression_complete=true\n'
