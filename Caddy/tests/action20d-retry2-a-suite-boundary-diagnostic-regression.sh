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
readonly outer=$caddy_root/scripts/run-action20d-retry2-suite-boundary-diagnostic-outer.sh
readonly executed_outer=$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry2-outer.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly executed_outer_sha256=6d89fa6fff1ad1bcdb3d627a877e2e34a01c1096f770a7342ad13adeb116b9e5

test_root=$(mktemp -d /tmp/caddy-action20d-retry2-a-regression.XXXXXX)
readonly test_root
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT

make_fixture() {
    local fixture_path=$1

    # Dollar-prefixed values are literal generated fixture source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'fixture_name=${0##*/}' \
        'fixture_mode=${1:-none}' \
        'printf '\''%s:%s\n'\'' "$fixture_name" "$fixture_mode" >>"$ACTION20D_RETRY2_A_ORDER_LOG"' \
        'printf '\''fixture_%s_%s_stdout=true\n'\'' "$fixture_name" "$fixture_mode"' \
        'printf '\''fixture_%s_%s_stderr=true\n'\'' "$fixture_name" "$fixture_mode" >&2' \
        'if [[ "${ACTION20D_RETRY2_A_FAIL_FIXTURE:-none}" = "$fixture_name" ]]; then' \
        '    exit 23' \
        'fi' \
        >"$fixture_path"
    chmod 0755 "$fixture_path"
}

make_fixture "$test_root/receiver"
make_fixture "$test_root/action17q"
make_fixture "$test_root/action17q-retry"
make_fixture "$test_root/inspector"
make_fixture "$test_root/runner"
make_fixture "$test_root/postinstall-regression"
/bin/bash "$collision" "$test_root/receiver" "$test_root/action17q" \
    "$test_root/action17q-retry" "$test_root/inspector" "$test_root/runner" \
    "$test_root/postinstall-regression" >/dev/null

[[ "$(sha256sum "$executed_outer" | awk '{ print $1 }')" = "$executed_outer_sha256" ]]
printf 'action_20d_retry2_a_regression_executed_outer_immutable=true\n'
/bin/bash "$collision" "$outer" "$0" >/dev/null

: >"$test_root/success.order"
ACTION20D_RETRY2_A_ORDER_LOG=$test_root/success.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/receiver" "$test_root/action17q" \
    "$test_root/action17q-retry" "$test_root/inspector" \
    "$test_root/runner" "$test_root/postinstall-regression" \
    >"$test_root/success.stdout" 2>"$test_root/success.stderr"
[[ ! -s "$test_root/success.stderr" ]]
[[ "$(paste -sd, "$test_root/success.order")" = receiver:none,action17q:--self-test,action17q-retry:--self-test,inspector:--self-test,runner:--self-test,runner:--contract-test,postinstall-regression:--self-test ]]
grep -Fxq 'action_20d_retry2_a_failure_count=0' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_classification=not_reproduced_in_narrow_sequence' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_context_unchanged=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_repository_state_unchanged=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_repository_mutations=false' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_podman_invoked=false' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_node_contact=false' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_activation_invoked=false' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_live_mutations=false' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_cleanup_complete=true' "$test_root/success.stdout"
grep -Fxq 'action_20d_retry2_a_diagnostic_complete=true' "$test_root/success.stdout"
printf 'action_20d_retry2_a_regression_valid_sequence_accepted=true\n'

: >"$test_root/failure.order"
ACTION20D_RETRY2_A_ORDER_LOG=$test_root/failure.order \
    ACTION20D_RETRY2_A_FAIL_FIXTURE=action17q \
    /bin/bash "$outer" --production-path-test \
    "$test_root/receiver" "$test_root/action17q" \
    "$test_root/action17q-retry" "$test_root/inspector" \
    "$test_root/runner" "$test_root/postinstall-regression" \
    >"$test_root/failure.stdout" 2>"$test_root/failure.stderr"
[[ ! -s "$test_root/failure.stderr" ]]
[[ "$(wc -l <"$test_root/failure.order")" -eq 7 ]]
grep -Fxq 'action_20d_retry2_a_action17q_original_status=23' "$test_root/failure.stdout"
grep -Fxq 'action_20d_retry2_a_action17q_b_regression_status=0' "$test_root/failure.stdout"
grep -Fxq 'action_20d_retry2_a_failure_count=1' "$test_root/failure.stdout"
grep -Fxq 'action_20d_retry2_a_classification=single_action17q_failure_reproduced' "$test_root/failure.stdout"
grep -Fxq 'action_20d_retry2_a_diagnostic_complete=true' "$test_root/failure.stdout"
printf 'action_20d_retry2_a_regression_failure_does_not_truncate_collection=true\n'

if grep -Eq '^[[:space:]]*(podman|ssh|scp|rsync)([[:space:]]|$)' "$outer"; then
    printf 'Diagnostic contains a prohibited external command.\n' >&2
    exit 1
fi
grep -Fq 'environment_name_hash' "$outer"
if grep -Fq 'env | LC_ALL=C sort' "$outer"; then
    printf 'Diagnostic exposes raw environment values.\n' >&2
    exit 1
fi
printf 'action_20d_retry2_a_regression_environment_values_not_emitted=true\n'
printf 'action_20d_retry2_a_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_retry2_a_regression_complete=true\n'
