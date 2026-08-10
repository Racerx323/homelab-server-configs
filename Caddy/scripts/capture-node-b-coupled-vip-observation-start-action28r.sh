#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
if [[ "${CADDY_ACTION28R_TEST_MODE:-}" = 1 ]]; then
    PATH=${CADDY_ACTION28R_TEST_PATH:-/usr/bin:/bin}
else
    PATH=/usr/bin:/bin
fi
export PATH
readonly PATH
readonly prefix=action_28r_observation_start

check() {
    local action28r_observation_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28r_observation_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28r_observation_label"
    return 1
}
require_check() {
    local action28r_observation_required_label=$1

    shift
    check "$action28r_observation_required_label" "$@" || {
        first_failure=$action28r_observation_required_label
        return 1
    }
}
expected_checks() {
    printf '%s\n' identity_root working_directory_root hostname_exact \
        journal_cursor_status_zero journal_cursor_present journal_cursor_safe epoch_present
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]]
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(expected_checks | wc -l)" -eq "$(expected_checks | LC_ALL=C sort -u | wc -l)" ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') ;;
    *) exit 64 ;;
esac

first_failure=none
require_check identity_root test "$(id -u)" -eq 0
require_check working_directory_root test "$(pwd -P)" = /
require_check hostname_exact test "$(hostname)" = j1-svpihole00
journal_cursor_status=0
journal_cursor=$(journalctl --sync --quiet 2>/dev/null &&
    journalctl -n 0 --show-cursor --no-pager 2>/dev/null |
    sed -n 's/^-- cursor: //p') || journal_cursor_status=$?
require_check journal_cursor_status_zero test "$journal_cursor_status" -eq 0
require_check journal_cursor_present test -n "$journal_cursor"
require_check journal_cursor_safe test -z "${journal_cursor//[A-Za-z0-9:;=._-]/}"
observation_epoch_ms=$(date +%s%3N)
require_check epoch_present test -n "$observation_epoch_ms"
printf '%s_value_journal_cursor=%s\n' "$prefix" "$journal_cursor"
printf '%s_value_epoch_ms=%s\n' "$prefix" "$observation_epoch_ms"
printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_mutation=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
