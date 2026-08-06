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
readonly outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh

report_unexpected_failure() {
    local failure_status=$?
    local failure_line=${BASH_LINENO[0]:-unknown}

    printf 'action_20d_retry2_regression_unexpected_failure_line=%s\n' \
        "$failure_line" >&2
    printf 'action_20d_retry2_regression_unexpected_failure_status=%s\n' \
        "$failure_status" >&2
    return "$failure_status"
}
trap report_unexpected_failure ERR

test_root=$(mktemp -d /tmp/caddy-action20d-retry2-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT

make_gate() {
    local generated_gate_path=$1
    local generated_gate_name=$2

    # Dollar-prefixed values are literal generated fixture source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'printf '\''%s\n'\'' "${0##*/}" >>"$ACTION20D_RETRY2_ORDER_LOG"' \
        'printf '\''fixture_%s_stdout=true\n'\'' "${0##*/}"' \
        'printf '\''fixture_%s_stderr=true\n'\'' "${0##*/}" >&2' \
        'exit "${ACTION20D_RETRY2_FAIL_STATUS:-0}"' \
        >"$generated_gate_path"
    chmod 0644 "$generated_gate_path"
    printf '%s=%s\n' "$generated_gate_name" "$generated_gate_path" >/dev/null
}

make_gate "$test_root/suite" suite
make_gate "$test_root/readiness" readiness
make_gate "$test_root/activation" activation
/bin/bash "$collision" "$test_root/suite" "$test_root/readiness" \
    "$test_root/activation" >/dev/null

# The dollar-prefixed name is literal fixture source.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly collision_name=value' \
    'collision() {' \
    '    local collision_name=other' \
    '    printf '\''%s\n'\'' "$collision_name"' \
    '}' >"$test_root/collision-fixture.sh"
if /bin/bash "$collision" "$test_root/collision-fixture.sh" \
    >"$test_root/collision.stdout" 2>"$test_root/collision.stderr"; then
    printf 'Action 20d retry2 collision fixture was incorrectly accepted.\n' >&2
    exit 1
fi
grep -Fq 'readonly_local_collision=' "$test_root/collision.stderr"
printf 'action_20d_retry2_regression_collision_rejected=true\n'

/bin/bash "$collision" "$outer" "$0" >/dev/null

: >"$test_root/success.order"
ACTION20D_RETRY2_ORDER_LOG=$test_root/success.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/suite" "$test_root/readiness" "$test_root/activation" \
    >"$test_root/success.stdout" 2>"$test_root/success.stderr"
grep -Fxq 'suite' "$test_root/success.order"
grep -Fxq 'readiness' "$test_root/success.order"
grep -Fxq 'activation' "$test_root/success.order"
[[ "$(paste -sd, "$test_root/success.order")" = suite,readiness,activation ]]
grep -Fxq 'action_20d_retry2_complete_suite_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_readiness_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_activation_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_boundary_cleanup_complete=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_boundary_accepted=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_complete_suite_stderr_classification=bounded_safe' "$test_root/success.stdout"
grep -Fq 'fixture_suite_stderr=true' "$test_root/success.stdout"
[[ ! -s "$test_root/success.stderr" ]]
printf 'action_20d_retry2_regression_success_order_and_evidence=true\n'

: >"$test_root/suite-failure.order"
suite_failure_status=0
ACTION20D_RETRY2_ORDER_LOG=$test_root/suite-failure.order \
    ACTION20D_RETRY2_FAIL_STATUS=23 \
    /bin/bash "$outer" --production-path-test \
    "$test_root/suite" "$test_root/readiness" "$test_root/activation" \
    >"$test_root/suite-failure.stdout" 2>"$test_root/suite-failure.stderr" ||
    suite_failure_status=$?
printf 'action_20d_retry2_regression_suite_failure_observed_status=%s\n' \
    "$suite_failure_status"
printf 'action_20d_retry2_regression_suite_failure_stdout_begin\n'
cat "$test_root/suite-failure.stdout"
printf 'action_20d_retry2_regression_suite_failure_stdout_end\n'
printf 'action_20d_retry2_regression_suite_failure_stderr_begin\n'
cat "$test_root/suite-failure.stderr"
printf 'action_20d_retry2_regression_suite_failure_stderr_end\n'
[[ "$suite_failure_status" -eq 23 ]]
[[ "$(paste -sd, "$test_root/suite-failure.order")" = suite ]]
grep -Fxq 'action_20d_retry2_readiness_invoked=false' "$test_root/suite-failure.stdout"
grep -Fxq 'action_20d_retry2_activation_invoked=false' "$test_root/suite-failure.stdout"
grep -Fxq 'action_20d_retry2_boundary_accepted=false' "$test_root/suite-failure.stdout"
printf 'action_20d_retry2_regression_suite_failure_stops_before_nodes=true\n'

cat >"$test_root/readiness-failure" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${0##*/}" >>"$ACTION20D_RETRY2_ORDER_LOG"
printf 'fixture_readiness_failure=true\n'
exit 24
EOF
chmod 0644 "$test_root/readiness-failure"
/bin/bash "$collision" "$test_root/readiness-failure" >/dev/null
: >"$test_root/readiness-failure.order"
readiness_failure_status=0
ACTION20D_RETRY2_ORDER_LOG=$test_root/readiness-failure.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/suite" "$test_root/readiness-failure" "$test_root/activation" \
    >"$test_root/readiness-failure.stdout" 2>"$test_root/readiness-failure.stderr" ||
    readiness_failure_status=$?
printf 'action_20d_retry2_regression_readiness_failure_observed_status=%s\n' \
    "$readiness_failure_status"
[[ "$readiness_failure_status" -eq 24 ]]
[[ "$(paste -sd, "$test_root/readiness-failure.order")" = suite,readiness-failure ]]
grep -Fxq 'action_20d_retry2_activation_invoked=false' "$test_root/readiness-failure.stdout"
grep -Fxq 'action_20d_retry2_boundary_accepted=false' "$test_root/readiness-failure.stdout"
printf 'action_20d_retry2_regression_readiness_failure_blocks_activation=true\n'

cat >"$test_root/activation-failure" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${0##*/}" >>"$ACTION20D_RETRY2_ORDER_LOG"
printf 'fixture_activation_rollback_complete=true\n' >&2
exit 25
EOF
chmod 0644 "$test_root/activation-failure"
/bin/bash "$collision" "$test_root/activation-failure" >/dev/null
: >"$test_root/activation-failure.order"
activation_failure_status=0
ACTION20D_RETRY2_ORDER_LOG=$test_root/activation-failure.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/suite" "$test_root/readiness" "$test_root/activation-failure" \
    >"$test_root/activation-failure.stdout" 2>"$test_root/activation-failure.stderr" ||
    activation_failure_status=$?
printf 'action_20d_retry2_regression_activation_failure_observed_status=%s\n' \
    "$activation_failure_status"
[[ "$activation_failure_status" -eq 25 ]]
[[ "$(paste -sd, "$test_root/activation-failure.order")" = suite,readiness,activation-failure ]]
grep -Fq 'fixture_activation_rollback_complete=true' "$test_root/activation-failure.stdout"
grep -Fxq 'action_20d_retry2_boundary_accepted=false' "$test_root/activation-failure.stdout"
if grep -Fq 'action_20d_retry2_boundary_accepted=true' "$test_root/activation-failure.stdout"; then
    printf 'Action 20d retry2 accepted a failed activation.\n' >&2
    exit 1
fi
printf 'action_20d_retry2_regression_activation_failure_not_accepted=true\n'

# The dollar-prefixed name is literal outer source.
# shellcheck disable=SC2016
grep -Fq '/bin/bash "$boundary_gate_command"' "$outer"
printf 'action_20d_retry2_regression_readable_nonexecutable_gates_use_bash=true\n'
printf 'action_20d_retry2_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_retry2_regression_complete=true\n'
