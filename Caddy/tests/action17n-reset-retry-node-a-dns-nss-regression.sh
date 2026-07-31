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
readonly driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly runner="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-reset-retry.sh"
readonly historical_driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-retry.sh"
readonly historical_runner="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh"
readonly historical_regression="$script_dir/action17n-retry-node-a-dns-nss-correction-regression.sh"
readonly historical_driver_sha256=0d56be5b31f141d7b6ab4d92164450d66675dbd9fe05f12a0903644915a91620
readonly historical_runner_sha256=0b05f20f33babb1a8acca8f8ad095ffc0dd0c88dfbd1dfcfe81e67972b6eeb23
readonly historical_regression_sha256=9869fd512b1eb7a5656c5416c1d6cfc5098b15529dfb22d6dfbde8e959d81847
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_dir/run-source-test-in-context.sh"
readonly -a readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)
readonly -a reset_checks=(
    pihole_restartdns
    pihole_ftl_active_after_reset
    pihole_ftl_pid_after_reset_nonzero
    pihole_ftl_pid_changed_after_reset
    pihole_ftl_restarts_after_reset_numeric
    pihole_ftl_active_at_acceptance
    pihole_ftl_pid_stable_after_reset
    pihole_ftl_restarts_stable_after_reset
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

extract_function() {
    local extraction_name=$1
    local extraction_source=$2

    sed -n "/^${extraction_name}()/,/^}/p" "$extraction_source"
}

line_number() {
    local line_pattern=$1
    local line_source=$2

    grep -n -m 1 -F "$line_pattern" "$line_source" | cut -d: -f1
}

rollback_line_number() {
    local line_pattern=$1
    local line_source=$2

    awk -v pattern="$line_pattern" '
        /^rollback\(\)/ { inside = 1 }
        inside && index($0, pattern) { print NR; exit }
        inside && /^}/ { exit }
    ' "$line_source"
}

write_success_transcript() {
    local fixture_path=$1
    local fixture_key

    {
        printf '%s\n' \
            action_17n_reset_retry_acceptance=true \
            action_17n_reset_retry_manifest_action=17n-reset-retry \
            action_17n_reset_retry_resolv_conf_mutation=false \
            action_17n_reset_retry_peer_connections=false \
            action_17n_reset_retry_synchronization_executed=false \
            action_17n_reset_retry_pihole_cache_reset=true \
            action_17n_reset_retry_service_restart=true
        for fixture_key in "${reset_checks[@]}"; do
            printf 'action_17n_reset_retry_check_%s=true\n' "$fixture_key"
        done
        for fixture_key in "${readiness_keys[@]}"; do
            printf 'action_17n_reset_retry_check_readiness_%s_command_status=true\n' \
                "$fixture_key"
            printf 'action_17n_reset_retry_check_readiness_%s_answer_safe=true\n' \
                "$fixture_key"
            printf 'action_17n_reset_retry_check_readiness_%s_answer_exact=true\n' \
                "$fixture_key"
            printf 'action_17n_reset_retry_value_readiness_%s_answer=fd36:5aa8:6971:1::54\n' \
                "$fixture_key"
            printf 'action_17n_reset_retry_value_readiness_%s_iteration=1\n' \
                "$fixture_key"
        done
    } >"$fixture_path"
}

absolute_reset_function_regression() (
    local regression_root fake_cli function_fixture success_log
    local failure_status

    regression_root=$(mktemp -d /tmp/caddy-action17n-reset-regression.XXXXXX)
    trap 'rm -rf -- "$regression_root"' EXIT
    fake_cli="$regression_root/pihole-outside-path"
    success_log="$regression_root/arguments"
    function_fixture="$regression_root/function"
    extract_function perform_pihole_reset "$driver" >"$function_fixture"

    # The literal variables belong to the generated fake CLI.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "$*" >"$PIHOLE_RESET_TEST_LOG"' \
        'exit "${PIHOLE_RESET_TEST_STATUS:-0}"' >"$fake_cli"
    chmod 0755 "$fake_cli"

    PIHOLE_RESET_TEST_LOG="$success_log" \
        bash -s "$fake_cli" "$function_fixture" <<'EOF'
set -euo pipefail
PATH=/usr/bin:/bin
export PATH
pihole_cli=$1
pihole_reset_timeout_seconds=2
source "$2"
perform_pihole_reset
EOF
    grep -Fqx restartdns "$success_log"

    set +e
    PIHOLE_RESET_TEST_LOG="$success_log" PIHOLE_RESET_TEST_STATUS=9 \
        bash -s "$fake_cli" "$function_fixture" <<'EOF'
set -euo pipefail
PATH=/usr/bin:/bin
export PATH
pihole_cli=$1
pihole_reset_timeout_seconds=2
source "$2"
perform_pihole_reset
EOF
    failure_status=$?
    set -e
    [[ "$failure_status" -eq 9 ]]
)

runner_transcript_regression() (
    local regression_root function_fixture success_fixture duplicate_fixture

    regression_root=$(mktemp -d /tmp/caddy-action17n-runner-regression.XXXXXX)
    trap 'rm -rf -- "$regression_root"' EXIT
    function_fixture="$regression_root/function"
    success_fixture="$regression_root/success"
    duplicate_fixture="$regression_root/duplicate"
    extract_function validate_success_transcript "$runner" >"$function_fixture"
    write_success_transcript "$success_fixture"

    bash -s "$success_fixture" "$function_fixture" <<'EOF'
set -euo pipefail
readiness_keys=(
    direct_unbound_peer_aaaa direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6 local_pihole_peer_aaaa
    local_pihole_node_a_aaaa local_pihole_peer_ptr6
)
source "$2"
validate_success_transcript "$1"
EOF

    cp -- "$success_fixture" "$duplicate_fixture"
    printf '%s\n' \
        action_17n_reset_retry_check_pihole_restartdns=true \
        >>"$duplicate_fixture"
    if bash -s "$duplicate_fixture" "$function_fixture" <<'EOF'; then
set -euo pipefail
readiness_keys=(
    direct_unbound_peer_aaaa direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6 local_pihole_peer_aaaa
    local_pihole_node_a_aaaa local_pihole_peer_ptr6
)
source "$2"
validate_success_transcript "$1"
EOF
        printf 'Runner accepted a duplicate reset assertion.\n' >&2
        return 1
    fi
)

run_regression() {
    local main_reload_line main_reset_line readiness_line
    local rollback_restore_line rollback_reload_line rollback_reset_line

    bash -n "$driver" "$runner"
    [[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
    [[ "$(file_hash "$historical_runner")" == "$historical_runner_sha256" ]]
    [[ "$(file_hash "$historical_regression")" == "$historical_regression_sha256" ]]
    "$driver" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$source_context_policy" --runner "$runner" >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$driver" "$runner" >/dev/null

    grep -Fq 'readonly pihole_cli=/usr/local/bin/pihole' "$driver"
    grep -Fq 'readonly pihole_reset_timeout_seconds=30' "$driver"
    grep -Fq 'timeout --signal=TERM --kill-after=5s' "$driver"
    grep -Fq 'run_check pihole_restartdns perform_pihole_reset' "$driver"
    grep -Fq 'rollback_record_status pihole_restartdns' "$driver"
    grep -Fq 'action_17n_reset_retry_pihole_cache_reset=true' "$driver"
    grep -Fq 'action_17n_reset_retry_service_restart=true' "$driver"
    grep -Fq "printf 'action=17n-reset-retry" "$driver"
    [[ "$(grep -Fxc '        perform_pihole_reset >/dev/null 2>&1' \
        "$driver")" -eq 1 ]]

    main_reload_line=$(line_number 'set_boundary unbound_reload' "$driver")
    main_reset_line=$(line_number 'set_boundary pihole_cache_reset' "$driver")
    readiness_line=$(line_number '# DNS_READINESS_BLOCK_BEGIN' "$driver")
    [[ "$main_reload_line" -lt "$main_reset_line" ]]
    [[ "$main_reset_line" -lt "$readiness_line" ]]

    # The literal variables are matched against the driver source.
    # shellcheck disable=SC2016
    rollback_restore_line=$(
        rollback_line_number \
            '"$backup_dir/pihole-local-zone.conf.before" "$live_local_zone"' \
            "$driver"
    )
    rollback_reload_line=$(
        rollback_line_number 'unbound-control reload' "$driver"
    )
    rollback_reset_line=$(
        rollback_line_number 'perform_pihole_reset >/dev/null' "$driver"
    )
    [[ "$rollback_restore_line" -lt "$rollback_reload_line" ]]
    [[ "$rollback_reload_line" -lt "$rollback_reset_line" ]]

    if grep -Fq '/etc/resolv.conf' "$driver" "$runner"; then
        printf 'Reset retry reads or mutates /etc/resolv.conf.\n' >&2
        return 1
    fi
    if grep -Eq 'systemctl[[:space:]]+(restart|start|stop)' "$driver"; then
        printf 'Reset retry bypasses the validated Pi-hole CLI.\n' >&2
        return 1
    fi
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$driver" "$runner"; then
        printf 'Reset retry contains a synchronization command.\n' >&2
        return 1
    fi

    absolute_reset_function_regression
    runner_transcript_regression
    printf 'action_17n_reset_retry_regression_complete=true\n'
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
