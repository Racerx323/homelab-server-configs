#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry2_regression
readonly previous_outer_sha256=b22d7f7332215f4b0021759bb56cf4b6bb3cb8cdec4386b3330530a53786702b

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-retry2-outer.sh
readonly previous_outer=$caddy_root/scripts/run-node-b-caddy-health-group-correction-action20g-retry-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_retry2_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_retry2_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_retry2_regression_label" >&2
    return 1
}
write_fake_successor() {
    local action20g_retry2_fake_path=$1

    # Dollar-prefixed expressions are literal fake-successor source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '[[ "${CADDY_ACTION20G_SOURCE_ROOT:?}" = "${ACTION20G_RETRY2_EXPECTED_SOURCE_ROOT:?}" ]]' \
        'printf "action_20g_retry2_fake_source_root_exact=true\n"' \
        >"$action20g_retry2_fake_path"
    chmod 0755 "$action20g_retry2_fake_path"
}
production_boundary_accepted() {
    local action20g_retry2_output=$regression_root/production.stdout
    local action20g_retry2_error=$regression_root/production.stderr

    ACTION20G_RETRY2_EXPECTED_SOURCE_ROOT="$caddy_root" \
        /bin/bash "$outer" --production-path-test "$fake_successor" "$capture_root" \
        >"$action20g_retry2_output" 2>"$action20g_retry2_error" || return 1
    [[ ! -s "$action20g_retry2_error" ]] || return 1
    grep -Fqx 'action_20g_retry2_fake_source_root_exact=true' "$action20g_retry2_output" || return 1
    grep -Fqx 'action_20g_retry2_outer_successor_status=0' "$action20g_retry2_output" || return 1
    grep -Fqx 'action_20g_retry2_outer_production_path_test_complete=true' \
        "$action20g_retry2_output"
}
missing_environment_rejected() {
    local action20g_retry2_status=0

    env -u CADDY_ACTION20G_SOURCE_ROOT \
        "ACTION20G_RETRY2_EXPECTED_SOURCE_ROOT=$caddy_root" \
        /bin/bash "$fake_successor" >/dev/null 2>&1 || action20g_retry2_status=$?
    [[ "$action20g_retry2_status" -ne 0 ]]
}
wrong_environment_rejected() {
    local action20g_retry2_status=0

    env CADDY_ACTION20G_SOURCE_ROOT=/invalid \
        "ACTION20G_RETRY2_EXPECTED_SOURCE_ROOT=$caddy_root" \
        /bin/bash "$fake_successor" >/dev/null 2>&1 || action20g_retry2_status=$?
    [[ "$action20g_retry2_status" -ne 0 ]]
}

regression_root=$(mktemp -d /tmp/caddy-action20g-retry2-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly capture_root=$regression_root/capture
readonly fake_successor=$regression_root/fake-successor.sh
install -d -m 0700 "$capture_root"
write_fake_successor "$fake_successor"

record_check previous_outer_immutable test "$(file_hash "$previous_outer")" = "$previous_outer_sha256"
# Dollar-prefixed expressions in the next three assertions are literal outer source.
# shellcheck disable=SC2016
record_check source_root_export_once test \
    "$(grep -Fxc 'export CADDY_ACTION20G_SOURCE_ROOT=$caddy_root' "$outer" || true)" -eq 1
# shellcheck disable=SC2016
record_check boundary_env_assignment_once test \
    "$(grep -Fc '/usr/bin/env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" /bin/bash "$action20g_retry2_runner"' "$outer" || true)" -eq 1
# shellcheck disable=SC2016
record_check production_call_once test \
    "$(grep -Fxc 'run_successor_capture "$previous_outer" "$work_root"' "$outer" || true)" -eq 1
record_check production_boundary_accepted production_boundary_accepted
record_check missing_environment_rejected missing_environment_rejected
record_check wrong_environment_rejected wrong_environment_rejected
record_check no_ssh_invocation test \
    "$(grep -Ec '(^|[[:space:]])ssh([[:space:]]|$)' "$fake_successor" || true)" -eq 0
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
