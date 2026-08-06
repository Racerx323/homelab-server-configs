#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_outer_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-b-caddy-health-helper-action20i-outer.sh

fixture_root=$(mktemp -d /tmp/caddy-action20i-outer-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT INT TERM

record_check() {
    local action20i_outer_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_outer_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20i_outer_regression_label" >&2
    return 1
}
write_fixture() {
    local action20i_fixture_path=$1
    local action20i_fixture_marker=$2
    local action20i_fixture_status=$3

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        "printf '%s\\n' '$action20i_fixture_marker'" \
        "printf '%s\\n' '$action20i_fixture_marker' >>'${action20i_fixture_path}.invoked'" \
        "exit $action20i_fixture_status" >"$action20i_fixture_path"
    chmod 0644 "$action20i_fixture_path"
}
run_success_path() {
    /bin/bash "$outer" --production-path-test "$fixture_root/baseline-success" \
        "$fixture_root/transaction-success" >"$fixture_root/success.stdout" \
        2>"$fixture_root/success.stderr" || return 1
    [[ ! -s "$fixture_root/success.stderr" ]] || return 1
    [[ -s "$fixture_root/baseline-success.invoked" ]] || return 1
    [[ -s "$fixture_root/transaction-success.invoked" ]] || return 1
    grep -Fq 'action_20i_outer_baseline_accepted=true' "$fixture_root/success.stdout" || return 1
    grep -Fq 'action_20i_outer_transaction_status=0' "$fixture_root/success.stdout" || return 1
}
run_baseline_failure() {
    local action20i_failure_status=0

    /bin/bash "$outer" --production-path-test "$fixture_root/baseline-failure" \
        "$fixture_root/transaction-blocked" >"$fixture_root/failure.stdout" \
        2>"$fixture_root/failure.stderr" || action20i_failure_status=$?
    [[ "$action20i_failure_status" -eq 23 ]] || return 1
    [[ -s "$fixture_root/baseline-failure.invoked" ]] || return 1
    [[ ! -e "$fixture_root/transaction-blocked.invoked" ]] || return 1
    grep -Fq 'action_20i_outer_baseline_status=23' "$fixture_root/failure.stdout" || return 1
}

write_fixture "$fixture_root/baseline-success" baseline_fixture_complete=true 0
write_fixture "$fixture_root/transaction-success" transaction_fixture_complete=true 0
write_fixture "$fixture_root/baseline-failure" baseline_fixture_failed=true 23
write_fixture "$fixture_root/transaction-blocked" transaction_fixture_must_not_run=true 0
record_check outer_syntax /bin/bash -n "$outer"
record_check success_path run_success_path
record_check baseline_failure_blocks_transaction run_baseline_failure
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
