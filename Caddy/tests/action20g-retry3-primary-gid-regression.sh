#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry3_regression
readonly source_builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly source_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly source_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly source_builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g.sh
readonly retry_builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g-retry3.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_retry3_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_retry3_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_retry3_regression_label" >&2
    return 1
}
installer_delta_exact() {
    local action20g_retry3_normalized=$regression_root/installer.normalized

    sed 's/record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 988/record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989/' \
        "$retry_installer" >"$action20g_retry3_normalized"
    cmp -s "$source_installer" "$action20g_retry3_normalized"
}
runner_delta_exact() {
    local action20g_retry3_normalized=$regression_root/runner.normalized

    sed "s/$retry_installer_sha256/$source_installer_sha256/" \
        "$retry_runner" >"$action20g_retry3_normalized"
    cmp -s "$source_runner" "$action20g_retry3_normalized"
}
fixture_accepts() {
    local action20g_retry3_fixture_uid=$1
    local action20g_retry3_fixture_gid=$2
    local action20g_retry3_expected_uid
    local action20g_retry3_expected_gid

    action20g_retry3_expected_uid=$(sed -n \
        's/.*script_user_uid_exact test "$action20g_script_uid" -eq \([0-9][0-9]*\).*/\1/p' \
        "$retry_installer")
    action20g_retry3_expected_gid=$(sed -n \
        's/.*script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq \([0-9][0-9]*\).*/\1/p' \
        "$retry_installer")
    [[ "$action20g_retry3_fixture_uid" = "$action20g_retry3_expected_uid" ]] || return 1
    [[ "$action20g_retry3_fixture_gid" = "$action20g_retry3_expected_gid" ]]
}

regression_root=$(mktemp -d /tmp/caddy-action20g-retry3-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly source_root=$regression_root/source
readonly retry_root=$regression_root/retry
install -d -m 0700 "$source_root" "$retry_root"
/bin/bash "$source_builder" --output "$source_root" >/dev/null
/bin/bash "$retry_builder" --output "$retry_root" >/dev/null
readonly source_installer=$source_root/install-node-b-caddy-health-group-action20g.sh
readonly source_runner=$source_root/run-node-b-caddy-health-group-correction-action20g.sh
readonly retry_installer=$retry_root/install-node-b-caddy-health-group-action20g.sh
readonly retry_runner=$retry_root/run-node-b-caddy-health-group-correction-action20g.sh
retry_installer_sha256=$(file_hash "$retry_installer")
readonly retry_installer_sha256

record_check source_builder_immutable test "$(file_hash "$source_builder")" = "$source_builder_sha256"
record_check source_installer_immutable test "$(file_hash "$source_installer")" = "$source_installer_sha256"
record_check source_runner_immutable test "$(file_hash "$source_runner")" = "$source_runner_sha256"
record_check installer_delta_only_primary_gid installer_delta_exact
record_check runner_delta_only_installer_hash runner_delta_exact
record_check generated_uid_992_once test \
    "$(grep -Fxc '    record_check script_user_uid_exact test "$action20g_script_uid" -eq 992 || return 1' "$retry_installer" || true)" -eq 1
record_check generated_gid_988_once test \
    "$(grep -Fxc '    record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 988 || return 1' "$retry_installer" || true)" -eq 1
record_check node_b_fixture_accepted fixture_accepts 992 988
if fixture_accepts 992 989; then
    printf '%s_check_old_gid_fixture_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_old_gid_fixture_rejected=true\n' "$prefix"
if fixture_accepts 993 988; then
    printf '%s_check_wrong_uid_fixture_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_wrong_uid_fixture_rejected=true\n' "$prefix"
record_check runner_installer_hash_exact grep -Fqx \
    "readonly installer_sha256=$retry_installer_sha256" "$retry_runner"
record_check installer_self_test /bin/bash "$retry_installer" --self-test
record_check runner_self_test env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" \
    /bin/bash "$retry_runner" --self-test
record_check runner_contract_test env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" \
    /bin/bash "$retry_runner" --contract-test
printf '%s_pre_ssh_fixture_coverage=true\n' "$prefix"
printf '%s_network_contact=false\n' "$prefix"
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
