#!/usr/bin/env bash
# shellcheck disable=SC1003,SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry2_builder
readonly source_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly source_stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly source_installer_sha256=33a834270f8c468e24a573b7ab42cb106d2d25f2624ef783031964771c93874f
readonly source_runner_sha256=e0ad03a83e75b4e7ec3e4c3beb23458d72c90d13ffc6f0e14a105b070abbd48c
readonly source_validation_line='        caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile \'
readonly replacement_validation_line='        /bin/bash -c '\''set -a; source /etc/default/caddy-ha; set +a; : "${NODE_ROLE:?}"; : "${NODE_FQDN:?}"; : "${NODE_IPV4:?}"; : "${NODE_IPV6:?}"; : "${CADDY_CONFIG_ROOT:?}"; exec caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile'\'' \'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_candidate=$script_directory/check-caddy-vrrp-action20h.sh
readonly source_stager=$script_directory/stage-node-a-caddy-health-helper-action20h.sh
readonly source_installer=$script_directory/install-node-a-caddy-health-helper-action20h-retry.sh
readonly source_runner=$script_directory/run-node-a-caddy-health-helper-action20h-retry.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20h_retry2_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry2_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry2_builder_label" >&2
    return 1
}
render_installer() {
    local action20h_retry2_output=$1
    local action20h_retry2_line
    local action20h_retry2_replacements=0

    : >"$action20h_retry2_output"
    while IFS= read -r action20h_retry2_line || [[ -n "$action20h_retry2_line" ]]; do
        if [[ "$action20h_retry2_line" = "$source_validation_line" ]]; then
            printf '%s\n' "$replacement_validation_line" >>"$action20h_retry2_output"
            action20h_retry2_replacements=$((action20h_retry2_replacements + 1))
        else
            printf '%s\n' "$action20h_retry2_line" >>"$action20h_retry2_output"
        fi
    done <"$source_installer"
    [[ "$action20h_retry2_replacements" -eq 1 ]]
}
build() {
    local action20h_retry2_output_root=$1
    local action20h_retry2_installer
    local action20h_retry2_runner
    local action20h_retry2_installer_hash

    install -d -m 0700 "$action20h_retry2_output_root"
    action20h_retry2_installer=$action20h_retry2_output_root/install-node-a-caddy-health-helper-action20h-retry2.sh
    action20h_retry2_runner=$action20h_retry2_output_root/run-node-a-caddy-health-helper-action20h-retry2.sh

    record_check source_candidate_hash test \
        "$(file_hash "$source_candidate")" = "$source_candidate_sha256" || return 1
    record_check source_stager_hash test \
        "$(file_hash "$source_stager")" = "$source_stager_sha256" || return 1
    record_check source_installer_hash test \
        "$(file_hash "$source_installer")" = "$source_installer_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$source_runner")" = "$source_runner_sha256" || return 1
    record_check source_validation_line_once test \
        "$(grep -Fxc "$source_validation_line" "$source_installer" || true)" -eq 1 || return 1
    install -m 0755 "$source_candidate" "$source_stager" "$action20h_retry2_output_root/"
    render_installer "$action20h_retry2_installer" || return 1
    chmod 0755 "$action20h_retry2_installer"
    action20h_retry2_installer_hash=$(file_hash "$action20h_retry2_installer") || return 1
    sed \
        -e "s/$source_installer_sha256/$action20h_retry2_installer_hash/g" \
        -e 's/install-node-a-caddy-health-helper-action20h-retry\.sh/install-node-a-caddy-health-helper-action20h-retry2.sh/g' \
        "$source_runner" >"$action20h_retry2_runner"
    chmod 0755 "$action20h_retry2_runner"

    record_check installer_syntax /bin/bash -n "$action20h_retry2_installer" || return 1
    record_check runner_syntax /bin/bash -n "$action20h_retry2_runner" || return 1
    record_check source_bare_validation_absent test \
        "$(grep -Fxc "$source_validation_line" "$action20h_retry2_installer" || true)" -eq 0 || return 1
    record_check environment_validation_once test \
        "$(grep -Fxc "$replacement_validation_line" "$action20h_retry2_installer" || true)" -eq 1 || return 1
    record_check environment_export_before_validation /bin/bash -c \
        'line=$(grep -nF "source /etc/default/caddy-ha" "$1" | cut -d: -f1); validation=$(grep -nF "exec caddy validate" "$1" | cut -d: -f1); [[ "$line" -eq "$validation" ]]' \
        _ "$action20h_retry2_installer" || return 1
    record_check required_node_variables_exact test \
        "$(grep -Eo '\$\{(NODE_ROLE|NODE_FQDN|NODE_IPV4|NODE_IPV6|CADDY_CONFIG_ROOT):\?\}' "$action20h_retry2_installer" | LC_ALL=C sort -u | wc -l)" -eq 5 || return 1
    record_check runner_installer_name grep -Fq \
        'install-node-a-caddy-health-helper-action20h-retry2.sh' "$action20h_retry2_runner" || return 1
    record_check runner_installer_hash grep -Fqx \
        "readonly installer_sha256=$action20h_retry2_installer_hash" "$action20h_retry2_runner" || return 1
    /bin/bash "$action20h_retry2_installer" --self-test >/dev/null || return 1
    /bin/bash "$action20h_retry2_runner" --self-test >/dev/null || return 1
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20h_retry2_installer_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20h_retry2_runner")"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20h_retry2_test_root=$(mktemp -d /tmp/caddy-action20h-retry2-builder.XXXXXX)
        readonly action20h_retry2_test_root
        trap 'rm -rf -- "$action20h_retry2_test_root"' EXIT
        build "$action20h_retry2_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
