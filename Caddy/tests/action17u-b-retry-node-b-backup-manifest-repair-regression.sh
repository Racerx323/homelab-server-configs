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
readonly repair="$caddy_root/scripts/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly failed_runner="$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b.sh"
readonly retry_runner="$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh"
readonly failed_regression="$script_directory/action17u-b-node-b-backup-manifest-repair-regression.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"
readonly legacy_collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly repair_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly failed_runner_sha256=27d89ba02199b02924ee6c92067d77cb8ee1d818d7f3ea2e3bf05af2b373784d
readonly failed_regression_sha256=5c42c857937986d4afb4eb776f5fc712a20ac72ac0ba14804a6beb01a0568927
readonly old_manifest_sha256=8b7ee379963bec0932dece5b11dd602efba33fe5d76a6e281c4db0c93b60dfbf
readonly new_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b

observed_status=0

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_label
    local fixture_count=0

    : >"$fixture_path"
    while IFS= read -r fixture_label; do
        fixture_count=$((fixture_count + 1))
        printf 'action_17u_b_assertion_%s=true\n' "$fixture_label" >>"$fixture_path"
    done < <("$repair" --expected-checks)
    {
        printf 'action_17u_b_value_assertion_count=%s\n' "$fixture_count"
        printf 'action_17u_b_value_failed_assertion_count=0\n'
        printf 'action_17u_b_value_first_failure=none\n'
        printf 'action_17u_b_value_old_manifest_sha256=%s\n' "$old_manifest_sha256"
        printf 'action_17u_b_value_new_manifest_sha256=%s\n' "$new_manifest_sha256"
        printf 'action_17u_b_value_backup_directory=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC\n'
        printf 'action_17u_b_value_persistent_change=backup_manifest_action_only\n'
        printf 'action_17u_b_transaction_complete=true\n'
    } >>"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only inside the intercepted regression process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'umask 077' \
        'printf "%s\n" "$@" >"$ACTION17UB_ARGUMENTS"' \
        'cat >"$ACTION17UB_STDIN"' \
        'stdout_path=$(readlink -f /proc/$$/fd/1)' \
        'stderr_path=$(readlink -f /proc/$$/fd/2)' \
        '{' \
        '    printf "stdout_path=%s\n" "$stdout_path"' \
        '    printf "stdout_metadata=%s\n" "$(stat -Lc "%U:%G:%a" /proc/$$/fd/1)"' \
        '    printf "stderr_path=%s\n" "$stderr_path"' \
        '    printf "stderr_metadata=%s\n" "$(stat -Lc "%U:%G:%a" /proc/$$/fd/2)"' \
        '} >"$ACTION17UB_METADATA"' \
        'cat -- "$ACTION17UB_STDOUT"' \
        'cat -- "$ACTION17UB_STDERR" >&2' \
        'exit "$ACTION17UB_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

verify_indented_readonly_collision_policy() {
    local policy_test_root
    local collision_fixture
    local clean_fixture
    local collision_status=0

    policy_test_root=$(mktemp -d /tmp/caddy-action17u-b-collision-policy.XXXXXX)
    collision_fixture="$policy_test_root/collision.sh"
    clean_fixture="$policy_test_root/clean.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'collision_function() {' \
        '    local later_readonly=value' \
        '}' \
        'if true; then' \
        '    later_readonly=value' \
        '    readonly later_readonly' \
        'fi' >"$collision_fixture"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'clean_function() {' \
        '    local function_value=value' \
        '}' \
        'if true; then' \
        '    script_value=value' \
        '    readonly script_value' \
        'fi' >"$clean_fixture"
    "$collision_checker" "$collision_fixture" \
        >"$policy_test_root/collision.out" 2>"$policy_test_root/collision.err" ||
        collision_status=$?
    [[ "$collision_status" -eq 1 ]]
    grep -Fq 'collision.sh|later_readonly' "$policy_test_root/collision.err"
    "$collision_checker" "$clean_fixture" >/dev/null
    rm -rf -- "$policy_test_root"
    printf 'action_17u_b_retry_indented_readonly_collision_rejected=true\n'
}

run_case() {
    local case_name=$1
    local case_root=$2
    local case_runner=$3
    local case_status=$4
    local case_stdout=$5
    local case_stderr=$6

    observed_status=0
    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17UB_ARGUMENTS="$case_root/$case_name.arguments" \
            ACTION17UB_METADATA="$case_root/$case_name.metadata" \
            ACTION17UB_STATUS="$case_status" \
            ACTION17UB_STDERR="$case_stderr" \
            ACTION17UB_STDIN="$case_root/$case_name.stdin" \
            ACTION17UB_STDOUT="$case_stdout" \
            "$case_runner"
    ) >"$case_root/$case_name.out" 2>"$case_root/$case_name.err" ||
        observed_status=$?
}

run_intercepted_production_regression() {
    local production_case_root=$1
    local fake_bin="$production_case_root/bin"
    local retry_root="$production_case_root/retry"
    local retry_case_runner="$retry_root/Caddy/scripts/${retry_runner##*/}"
    local failed_root="$production_case_root/failed"
    local failed_case_runner="$failed_root/Caddy/scripts/${failed_runner##*/}"
    local valid_fixture="$production_case_root/valid.fixture"
    local empty_fixture="$production_case_root/empty.fixture"
    local unsafe_fixture="$production_case_root/unsafe.fixture"
    local stdout_path
    local stderr_path
    local retained_path
    local failed_leak_path

    install -d -m 0700 \
        "$fake_bin" \
        "$retry_root/Caddy/scripts" "$retry_root/Caddy/tests" \
        "$failed_root/Caddy/scripts" "$failed_root/Caddy/tests"
    cp -- "$repair" "$retry_runner" "$retry_root/Caddy/scripts/"
    cp -- "$collision_checker" "$retry_root/Caddy/tests/"
    cp -- "$repair" "$failed_runner" "$failed_root/Caddy/scripts/"
    cp -- "$legacy_collision_checker" "$failed_root/Caddy/tests/"
    chmod 0755 \
        "$retry_root/Caddy/scripts/"* "$retry_root/Caddy/tests/"* \
        "$failed_root/Caddy/scripts/"* "$failed_root/Caddy/tests/"*
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" \
        "$retry_case_runner" "$failed_case_runner"
    write_fake_ssh "$fake_bin/ssh"
    write_success_fixture "$valid_fixture"
    : >"$empty_fixture"
    printf 'CADDY_TLS_PRIVATE_KEY_PEM=regression-secret\n' >"$unsafe_fixture"

    run_case success "$production_case_root" "$retry_case_runner" \
        0 "$valid_fixture" "$empty_fixture"
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17u_b_capture_files_secure=true "$production_case_root/success.out"
    grep -Fxq stdout_metadata=aaron:aaron:600 "$production_case_root/success.metadata"
    grep -Fxq stderr_metadata=aaron:aaron:600 "$production_case_root/success.metadata"
    stdout_path=$(sed -n 's/^stdout_path=//p' "$production_case_root/success.metadata")
    stderr_path=$(sed -n 's/^stderr_path=//p' "$production_case_root/success.metadata")
    [[ "$stdout_path" =~ ^/tmp/caddy-action17u-b-retry-runner\.[A-Za-z0-9]+/remote\.stdout\.[A-Za-z0-9]+$ ]]
    [[ "$stderr_path" =~ ^/tmp/caddy-action17u-b-retry-runner\.[A-Za-z0-9]+/remote\.stderr\.[A-Za-z0-9]+$ ]]
    [[ ! -e "${stdout_path%/*}" ]]
    [[ "$(file_hash "$production_case_root/success.stdin")" == "$repair_sha256" ]]
    grep -Fxq 'cd / && sudo -n /bin/bash -s --' "$production_case_root/success.arguments"
    printf 'action_17u_b_retry_false_negative_success_cleanup=true\n'

    run_case ssh_failure "$production_case_root" "$retry_case_runner" \
        255 "$empty_fixture" "$empty_fixture"
    [[ "$observed_status" -eq 97 ]]
    stdout_path=$(sed -n 's/^stdout_path=//p' "$production_case_root/ssh_failure.metadata")
    [[ ! -e "${stdout_path%/*}" ]]
    printf 'action_17u_b_retry_false_negative_failure_cleanup=true\n'

    run_case unsafe "$production_case_root" "$retry_case_runner" \
        1 "$empty_fixture" "$unsafe_fixture"
    [[ "$observed_status" -eq 97 ]]
    retained_path=$(sed -n 's/^action_17u_b_value_protected_evidence_directory=//p' \
        "$production_case_root/unsafe.out")
    [[ "$retained_path" =~ ^/tmp/caddy-action17u-b-retry-runner\.[A-Za-z0-9]+$ ]]
    [[ "$(stat -c '%U:%G:%a' "$retained_path")" == aaron:aaron:700 ]]
    [[ "$(find "$retained_path" -mindepth 1 -maxdepth 1 -type f -name 'remote.stderr.*' -printf '%m\n')" == 600 ]]
    rm -rf -- "$retained_path"
    printf 'action_17u_b_retry_false_positive_unsafe_retention=true\n'

    run_case historical "$production_case_root" "$failed_case_runner" \
        0 "$valid_fixture" "$empty_fixture"
    [[ "$observed_status" -eq 1 ]]
    [[ ! -e "$production_case_root/historical.metadata" ]]
    grep -Fq "chmod: cannot access '/tmp/caddy-action17u-b-runner." \
        "$production_case_root/historical.err"
    failed_leak_path=$(sed -n \
        "s#^chmod: cannot access '\(/tmp/caddy-action17u-b-runner\.[^/]\+\)/remote\.stdout'.*#\1#p" \
        "$production_case_root/historical.err" | head -n 1)
    [[ "$failed_leak_path" =~ ^/tmp/caddy-action17u-b-runner\.[A-Za-z0-9]+$ ]]
    [[ -d "$failed_leak_path" ]]
    [[ -z "$(find "$failed_leak_path" -mindepth 1 -maxdepth 1 -print -quit)" ]]
    rm -rf -- "$failed_leak_path"
    printf 'action_17u_b_historical_missing_capture_failure_reproduced=true\n'

    printf 'action_17u_b_retry_production_path_network_contact=false\n'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$repair_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17u_b_retry_regression_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$repair")" == "$repair_sha256" ]]
[[ "$(file_hash "$failed_runner")" == "$failed_runner_sha256" ]]
[[ "$(file_hash "$failed_regression")" == "$failed_regression_sha256" ]]
[[ -f "$retry_runner" && ! -L "$retry_runner" ]]
[[ "$(stat -c '%a' "$retry_runner")" == 755 ]]
bash -n "$retry_runner" "$0"
shellcheck "$retry_runner" "$0"
"$collision_checker" "$retry_runner" "$0" >/dev/null
"$retry_runner" --self-test >/dev/null
"$retry_runner" --contract-test >/dev/null
verify_indented_readonly_collision_policy

trap_line=$(grep -nFx 'trap cleanup_runner_work_directory EXIT' "$retry_runner" | cut -d: -f1)
# shellcheck disable=SC2016
stdout_line=$(grep -nF 'remote_stdout=$(mktemp "$work_directory/remote.stdout.XXXXXX")' "$retry_runner" | cut -d: -f1)
# shellcheck disable=SC2016
stderr_line=$(grep -nF 'remote_stderr=$(mktemp "$work_directory/remote.stderr.XXXXXX")' "$retry_runner" | cut -d: -f1)
# shellcheck disable=SC1003
ssh_line=$(grep -nFx 'ssh \' "$retry_runner" | cut -d: -f1)
[[ "$trap_line" =~ ^[0-9]+$ && "$stdout_line" =~ ^[0-9]+$ ]]
[[ "$stderr_line" =~ ^[0-9]+$ && "$ssh_line" =~ ^[0-9]+$ ]]
[[ "$trap_line" -lt "$stdout_line" ]]
[[ "$stdout_line" -lt "$stderr_line" ]]
[[ "$stderr_line" -lt "$ssh_line" ]]
# shellcheck disable=SC2016
if grep -Fq 'chmod 0600 "$remote_stdout" "$remote_stderr"' "$retry_runner"; then
    printf 'Retry retained the historical missing-file chmod boundary.\n' >&2
    exit 1
fi
grep -Fq 'trap - EXIT' "$retry_runner"
# shellcheck disable=SC2016
grep -Fq 'exit "$cleanup_status"' "$retry_runner"

if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    printf 'action_17u_b_retry_container_projection_validated=true\n'
else
    regression_root=$(mktemp -d /tmp/caddy-action17u-b-retry-regression.XXXXXX)
    readonly regression_root
    trap 'rm -rf -- "$regression_root"' EXIT
    run_intercepted_production_regression "$regression_root"
fi

printf 'Action 17u-b retry backup-manifest repair regression passed.\n'
