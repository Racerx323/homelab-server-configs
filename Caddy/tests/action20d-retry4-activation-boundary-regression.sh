#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry4-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh

check_regression() {
    local retry4_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry4_regression_check_%s=true\n' "$retry4_regression_label"
        return 0
    fi
    printf 'action_20d_retry4_regression_check_%s=false\n' \
        "$retry4_regression_label" >&2
    return 1
}

test_root=$(mktemp -d /tmp/caddy-action20d-retry4-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT

make_gate() {
    local generated_gate_path=$1
    local generated_gate_label=$2

    # Dollar-prefixed expressions are literal fixture source.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -Eeuo pipefail'
        printf 'readonly fixture_label=%q\n' "$generated_gate_label"
        printf '%s\n' 'printf "%s\n" "$fixture_label" >>"$ACTION20D_RETRY4_ORDER_LOG"'
        printf '%s\n' 'printf "fixture_%s_stdout=true\n" "$fixture_label"'
        printf '%s\n' 'printf "fixture_%s_stderr=true\n" "$fixture_label" >&2'
        printf '%s\n' 'if [[ "${ACTION20D_RETRY4_FAIL_GATE:-none}" = "$fixture_label" ]]; then'
        printf '%s\n' '    if [[ "$fixture_label" = activation ]]; then'
        printf '%s\n' '        printf "fixture_activation_rollback_complete=true\n" >&2'
        printf '%s\n' '    fi'
        printf '%s\n' '    exit 23'
        printf '%s\n' 'fi'
    } >"$generated_gate_path"
    chmod 0644 "$generated_gate_path"
}

make_gate "$test_root/suite" suite
make_gate "$test_root/readiness" readiness
make_gate "$test_root/activation" activation
/bin/bash "$collision" "$test_root/suite" "$test_root/readiness" \
    "$test_root/activation" >/dev/null
/bin/bash "$collision" "$outer" "$0" >/dev/null

: >"$test_root/success.order"
ACTION20D_RETRY4_ORDER_LOG=$test_root/success.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/suite" "$test_root/readiness" "$test_root/activation" \
    >"$test_root/success.stdout" 2>"$test_root/success.stderr"
check_regression success_stderr_empty test ! -s "$test_root/success.stderr"
check_regression success_order test \
    "$(paste -sd, "$test_root/success.order")" = suite,readiness,activation
for success_label in \
    action_20d_retry4_complete_suite_accepted=true \
    action_20d_retry4_readiness_accepted=true \
    action_20d_retry4_activation_accepted=true \
    action_20d_retry4_boundary_cleanup_complete=true \
    action_20d_retry4_boundary_accepted=true \
    action_20d_retry4_complete_suite_stderr_classification=bounded_safe \
    action_20d_retry4_readiness_stderr_classification=bounded_safe \
    action_20d_retry4_activation_stderr_classification=bounded_safe; do
    check_regression "success_${success_label%%=*}" \
        grep -Fxq "$success_label" "$test_root/success.stdout"
done
check_regression success_stream_emitted \
    grep -Fq fixture_activation_stderr=true "$test_root/success.stdout"
printf 'action_20d_retry4_regression_success_order_and_evidence=true\n'

run_failure_case() {
    local failed_gate_label=$1
    local expected_order=$2
    local failure_stdout=$test_root/$failed_gate_label-failure.stdout
    local failure_stderr=$test_root/$failed_gate_label-failure.stderr
    local failure_order=$test_root/$failed_gate_label-failure.order
    local failure_status=0

    : >"$failure_order"
    ACTION20D_RETRY4_ORDER_LOG=$failure_order \
        ACTION20D_RETRY4_FAIL_GATE=$failed_gate_label \
        /bin/bash "$outer" --production-path-test \
        "$test_root/suite" "$test_root/readiness" "$test_root/activation" \
        >"$failure_stdout" 2>"$failure_stderr" || failure_status=$?
    check_regression "${failed_gate_label}_failure_status" \
        test "$failure_status" -eq 23
    check_regression "${failed_gate_label}_failure_order" \
        test "$(paste -sd, "$failure_order")" = "$expected_order"
    check_regression "${failed_gate_label}_failure_not_accepted" \
        grep -Fxq action_20d_retry4_boundary_accepted=false "$failure_stdout"
    if [[ "$failed_gate_label" = suite ]]; then
        check_regression suite_failure_readiness_blocked \
            grep -Fxq action_20d_retry4_readiness_invoked=false "$failure_stdout"
        check_regression suite_failure_activation_blocked \
            grep -Fxq action_20d_retry4_activation_invoked=false "$failure_stdout"
    elif [[ "$failed_gate_label" = readiness ]]; then
        check_regression readiness_failure_activation_blocked \
            grep -Fxq action_20d_retry4_activation_invoked=false "$failure_stdout"
    else
        check_regression activation_failure_rollback_visible \
            grep -Fq fixture_activation_rollback_complete=true "$failure_stdout"
    fi
}

run_failure_case suite suite
run_failure_case readiness suite,readiness
run_failure_case activation suite,readiness,activation
printf 'action_20d_retry4_regression_failure_ordering_and_rollback=true\n'

# The dollar-prefixed text is literal outer source.
# shellcheck disable=SC2016
check_regression readable_gates_use_bash \
    grep -Fq '/bin/bash "$boundary_gate_command"' "$outer"
check_regression correction_hash_gate_present \
    grep -Fq 'correction_boundary_hash' "$outer"
check_regression correction_wiring_gate_present \
    grep -Fq 'correction_wiring' "$outer"
printf 'action_20d_retry4_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_retry4_regression_complete=true\n'
