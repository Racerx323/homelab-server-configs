#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b-retry.sh"
readonly runner="$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b-retry.sh"
readonly historical_inspector="$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b.sh"
readonly historical_regression="$script_dir/action17n-b-node-a-pihole-response-path-regression.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"
readonly historical_inspector_sha256=533278646571fe5aecea3428d7045ea50557d291fcb2e2fa62e752c403336415
readonly historical_runner_sha256=5e1bf0e8bdcf37c683d45979f5ccdd3ae24f20e7e3b555de71805c3fe29983dd
readonly historical_regression_sha256=522dde7b6aab03526da319ac1b69a0750b105bb87e3d880addf8e6e937a1ecb1

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

run_gate() {
    local gate_label=$1
    shift

    if "$@" >/dev/null; then
        printf 'action_17n_b_retry_regression_assertion_%s=true\n' \
            "$gate_label"
    else
        printf 'action_17n_b_retry_regression_assertion_%s=false\n' \
            "$gate_label" >&2
        return 1
    fi
}

absolute_cli_production_regression() (
    local regression_root fake_cli output

    regression_root=$(mktemp -d /tmp/caddy-action17n-b-retry-regression.XXXXXX)
    trap 'rm -rf -- "$regression_root"' EXIT
    fake_cli="$regression_root/pihole-outside-locked-path"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "Pi-hole version is v5.18.3"' \
        'printf "%s\n" "FTL version is v5.25.2"' >"$fake_cli"
    chmod 0755 "$fake_cli"

    [[ ":$PATH:" != *":$regression_root:"* ]]
    output=$("$inspector" --absolute-cli-test "$fake_cli")
    [[ "$output" == action_17n_b_retry_absolute_cli_test_complete=true ]]
)

run_regression() {
    local required_text

    run_gate bash_syntax bash -n "$inspector" "$runner"
    run_gate historical_inspector_immutable test \
        "$(file_hash "$historical_inspector")" = \
        "$historical_inspector_sha256"
    run_gate historical_runner_immutable test \
        "$(file_hash "$historical_runner")" = "$historical_runner_sha256"
    run_gate historical_regression_immutable test \
        "$(file_hash "$historical_regression")" = \
        "$historical_regression_sha256"
    run_gate inspector_self_test "$inspector" --self-test
    run_gate absolute_cli_production_path absolute_cli_production_regression
    run_gate runner_self_test "$runner" --self-test
    run_gate runner_source_context \
        "$source_context_policy" --runner "$runner"
    run_gate readonly_local_collision \
        "$collision_checker" "$inspector" "$runner"

    # shellcheck disable=SC2016
    for required_text in \
        'readonly pihole_cli=/usr/local/bin/pihole' \
        'run_pihole_version "$pihole_cli"' \
        'record_assertion pihole_cli_absolute_executable true' \
        'pihole_restartdns_interface_present' \
        'pihole_cache_reset_performed=false' \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
        'pi@10.1.0.53'; do
        grep -Fq "$required_text" "$inspector" "$runner"
    done

    if grep -Eq '(^|[^/[:alnum:]_-])pihole[[:space:]]+-v' "$inspector"; then
        printf 'Action 17n-b retry contains a bare pihole invocation.\n' >&2
        return 1
    fi
    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mktemp|mv|rm|rmdir|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17n-b retry inspector contains a filesystem mutation.\n' \
            >&2
        return 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|/usr/local/bin/pihole[[:space:]]+restartdns' \
        "$inspector"; then
        printf 'Action 17n-b retry contains a service/cache mutation.\n' >&2
        return 1
    fi
    printf 'action_17n_b_retry_absolute_pihole_path_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
