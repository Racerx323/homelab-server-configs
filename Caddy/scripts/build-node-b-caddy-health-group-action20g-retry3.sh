#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry3_builder
readonly source_builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly source_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly source_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec
readonly expected_uid=992
readonly expected_primary_gid=988

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-b-caddy-health-group-action20g.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_retry3_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_retry3_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_retry3_builder_label" >&2
    return 1
}
identity_fixture_accepts() {
    local action20g_retry3_fixture_uid=$1
    local action20g_retry3_fixture_gid=$2

    [[ "$action20g_retry3_fixture_uid" -eq "$expected_uid" ]] || return 1
    [[ "$action20g_retry3_fixture_gid" -eq "$expected_primary_gid" ]]
}
build() (
    local action20g_retry3_output_root=$1
    local action20g_retry3_source_root
    local action20g_retry3_source_installer
    local action20g_retry3_source_runner
    local action20g_retry3_installer
    local action20g_retry3_runner
    local action20g_retry3_installer_hash

    action20g_retry3_source_root=$(mktemp -d /tmp/caddy-action20g-retry3-source.XXXXXX)
    trap 'rm -rf -- "$action20g_retry3_source_root"' EXIT
    install -d -m 0700 "$action20g_retry3_output_root"
    /bin/bash "$source_builder" --output "$action20g_retry3_source_root" >/dev/null
    action20g_retry3_source_installer=$action20g_retry3_source_root/install-node-b-caddy-health-group-action20g.sh
    action20g_retry3_source_runner=$action20g_retry3_source_root/run-node-b-caddy-health-group-correction-action20g.sh
    action20g_retry3_installer=$action20g_retry3_output_root/install-node-b-caddy-health-group-action20g.sh
    action20g_retry3_runner=$action20g_retry3_output_root/run-node-b-caddy-health-group-correction-action20g.sh

    record_check source_installer_hash test \
        "$(file_hash "$action20g_retry3_source_installer")" = "$source_installer_sha256"
    record_check source_runner_hash test \
        "$(file_hash "$action20g_retry3_source_runner")" = "$source_runner_sha256"
    record_check source_uid_once test \
        "$(grep -Fxc '    record_check script_user_uid_exact test "$action20g_script_uid" -eq 992 || return 1' "$action20g_retry3_source_installer" || true)" -eq 1
    record_check source_gid_once test \
        "$(grep -Fxc '    record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989 || return 1' "$action20g_retry3_source_installer" || true)" -eq 1

    sed 's/record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989/record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 988/' \
        "$action20g_retry3_source_installer" >"$action20g_retry3_installer"
    chmod 0755 "$action20g_retry3_installer"
    action20g_retry3_installer_hash=$(file_hash "$action20g_retry3_installer")
    sed "s/$source_installer_sha256/$action20g_retry3_installer_hash/" \
        "$action20g_retry3_source_runner" >"$action20g_retry3_runner"
    chmod 0755 "$action20g_retry3_runner"

    record_check installer_syntax /bin/bash -n "$action20g_retry3_installer"
    record_check runner_syntax /bin/bash -n "$action20g_retry3_runner"
    record_check corrected_gid_once test \
        "$(grep -Fxc '    record_check script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 988 || return 1' "$action20g_retry3_installer" || true)" -eq 1
    record_check old_gid_absent test \
        "$(grep -Fc 'script_user_primary_gid_exact test "$(id -g keepalived_script)" -eq 989' "$action20g_retry3_installer" || true)" -eq 0
    record_check runner_installer_pin grep -Fqx \
        "readonly installer_sha256=$action20g_retry3_installer_hash" "$action20g_retry3_runner"
    record_check fixture_node_b_accepts identity_fixture_accepts 992 988
    if identity_fixture_accepts 992 989; then
        printf '%s_check_fixture_old_gid_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_check_fixture_old_gid_rejected=true\n' "$prefix"
    if identity_fixture_accepts 993 988; then
        printf '%s_check_fixture_wrong_uid_rejected=false\n' "$prefix" >&2
        return 1
    fi
    printf '%s_check_fixture_wrong_uid_rejected=true\n' "$prefix"
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20g_retry3_installer_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20g_retry3_runner")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        record_check source_builder_hash test "$(file_hash "$source_builder")" = "$source_builder_sha256"
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20g_retry3_test_root=$(mktemp -d /tmp/caddy-action20g-retry3-builder.XXXXXX)
        readonly action20g_retry3_test_root
        trap 'rm -rf -- "$action20g_retry3_test_root"' EXIT
        record_check source_builder_hash test "$(file_hash "$source_builder")" = "$source_builder_sha256"
        build "$action20g_retry3_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
