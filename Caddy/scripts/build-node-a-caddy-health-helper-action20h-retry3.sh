#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry3_builder
readonly source_builder_sha256=272c45dff2975f3b6f0fbbcae39b5054fd25ec4302c73f2213d7cda44094787d
readonly source_installer_sha256=702f4ed558dccf213a0d24d1587118eabc3fe5da5c1d342a0c8ddac8a8d14dc2
readonly source_runner_sha256=aff13c6c73cce6ce5f6067f0b10b8c33e3a20b33e1358a3fe4e7f742602cdb3a
readonly unsupported_prerequisite='; : "${CADDY_CONFIG_ROOT:?}"'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-a-caddy-health-helper-action20h-retry2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20h_retry3_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry3_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry3_builder_label" >&2
    return 1
}
build() (
    local action20h_retry3_output_root=$1
    local action20h_retry3_source_root
    local action20h_retry3_source_installer
    local action20h_retry3_source_runner
    local action20h_retry3_installer
    local action20h_retry3_runner
    local action20h_retry3_installer_hash

    action20h_retry3_source_root=$(mktemp -d /tmp/caddy-action20h-retry3-source.XXXXXX)
    trap 'rm -rf -- "$action20h_retry3_source_root"' EXIT
    install -d -m 0700 "$action20h_retry3_output_root"
    /bin/bash "$source_builder" --output "$action20h_retry3_source_root" >/dev/null
    action20h_retry3_source_installer=$action20h_retry3_source_root/install-node-a-caddy-health-helper-action20h-retry2.sh
    action20h_retry3_source_runner=$action20h_retry3_source_root/run-node-a-caddy-health-helper-action20h-retry2.sh
    action20h_retry3_installer=$action20h_retry3_output_root/install-node-a-caddy-health-helper-action20h-retry3.sh
    action20h_retry3_runner=$action20h_retry3_output_root/run-node-a-caddy-health-helper-action20h-retry3.sh

    record_check source_installer_hash test \
        "$(file_hash "$action20h_retry3_source_installer")" = "$source_installer_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$action20h_retry3_source_runner")" = "$source_runner_sha256" || return 1
    record_check unsupported_prerequisite_once test \
        "$(grep -Fo "$unsupported_prerequisite" "$action20h_retry3_source_installer" | wc -l)" -eq 1 || return 1

    sed 's/; : "${CADDY_CONFIG_ROOT:?}"//' \
        "$action20h_retry3_source_installer" >"$action20h_retry3_installer"
    chmod 0755 "$action20h_retry3_installer"
    action20h_retry3_installer_hash=$(file_hash "$action20h_retry3_installer")
    sed \
        -e "s/$source_installer_sha256/$action20h_retry3_installer_hash/g" \
        -e 's/install-node-a-caddy-health-helper-action20h-retry2\.sh/install-node-a-caddy-health-helper-action20h-retry3.sh/g' \
        "$action20h_retry3_source_runner" >"$action20h_retry3_runner"
    chmod 0755 "$action20h_retry3_runner"
    install -m 0755 \
        "$action20h_retry3_source_root/check-caddy-vrrp-action20h.sh" \
        "$action20h_retry3_source_root/stage-node-a-caddy-health-helper-action20h.sh" \
        "$action20h_retry3_output_root/"

    record_check installer_syntax /bin/bash -n "$action20h_retry3_installer" || return 1
    record_check runner_syntax /bin/bash -n "$action20h_retry3_runner" || return 1
    record_check unsupported_prerequisite_absent test \
        "$(grep -Fc 'CADDY_CONFIG_ROOT:?' "$action20h_retry3_installer" || true)" -eq 0 || return 1
    record_check four_required_variables_exact test \
        "$(grep -Eo '\$\{(NODE_ROLE|NODE_FQDN|NODE_IPV4|NODE_IPV6):\?\}' "$action20h_retry3_installer" | LC_ALL=C sort -u | wc -l)" -eq 4 || return 1
    record_check caddy_config_default_preserved grep -Fq \
        'exec caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' \
        "$action20h_retry3_installer" || return 1
    record_check runner_installer_name grep -Fq \
        'install-node-a-caddy-health-helper-action20h-retry3.sh' "$action20h_retry3_runner" || return 1
    record_check runner_installer_hash grep -Fqx \
        "readonly installer_sha256=$action20h_retry3_installer_hash" "$action20h_retry3_runner" || return 1
    /bin/bash "$action20h_retry3_installer" --self-test >/dev/null || return 1
    /bin/bash "$action20h_retry3_runner" --self-test >/dev/null || return 1
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20h_retry3_installer_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20h_retry3_runner")"
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
        action20h_retry3_test_root=$(mktemp -d /tmp/caddy-action20h-retry3-builder.XXXXXX)
        readonly action20h_retry3_test_root
        trap 'rm -rf -- "$action20h_retry3_test_root"' EXIT
        record_check source_builder_hash test "$(file_hash "$source_builder")" = "$source_builder_sha256"
        build "$action20h_retry3_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
