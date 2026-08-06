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
readonly outer=$caddy_root/scripts/run-node-a-caddy-vrrp-activation-action20d-retry9-outer.sh
readonly health_baseline_outer=$caddy_root/scripts/run-node-a-caddy-health-group-postinstall-action20f-a-outer.sh
readonly readiness_probe=$caddy_root/scripts/inspect-dual-node-caddy-readiness-action20d-retry9.sh
readonly readiness_runner=$caddy_root/scripts/run-dual-node-caddy-readiness-action20d-retry9.sh
readonly collision=$script_directory/check-shell-readonly-local-collisions-v2.sh
readonly reload_check_pattern='^[[:space:]]*reload_check_config([[:space:]]|$)'
readonly literal_dollar='$'

check_regression() {
    local retry9_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry9_regression_check_%s=true\n' "$retry9_regression_label"
        return 0
    fi
    printf 'action_20d_retry9_regression_check_%s=false\n' \
        "$retry9_regression_label" >&2
    return 1
}

test_root=$(mktemp -d /tmp/caddy-action20d-retry9-regression.XXXXXX)
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
        printf '%s\n' 'printf "%s\n" "$fixture_label" >>"$ACTION20D_RETRY9_ORDER_LOG"'
        printf '%s\n' 'printf "fixture_%s_stdout=true\n" "$fixture_label"'
        printf '%s\n' 'printf "fixture_%s_stderr=true\n" "$fixture_label" >&2'
        printf '%s\n' 'if [[ "${ACTION20D_RETRY9_FAIL_GATE:-none}" = "$fixture_label" ]]; then'
        printf '%s\n' '    if [[ "$fixture_label" = activation ]]; then'
        printf '%s\n' '        printf "fixture_activation_rollback_complete=true\n" >&2'
        printf '%s\n' '    fi'
        printf '%s\n' '    exit 23'
        printf '%s\n' 'fi'
    } >"$generated_gate_path"
    chmod 0644 "$generated_gate_path"
}

make_gate "$test_root/readiness" readiness
make_gate "$test_root/activation" activation
/bin/bash "$collision" "$test_root/readiness" "$test_root/activation" >/dev/null
/bin/bash "$collision" "$outer" "$0" >/dev/null
check_regression health_baseline_outer_immutable test \
    "$(sha256sum "$health_baseline_outer" | awk '{ print $1 }')" = \
    a4defbeab49958ecaadf1c2e34c259a847ecf0cc5b9a86d359da2c210d8b68c9
check_regression readiness_node_a_fragment_current \
    grep -Fq 'expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39' \
    "$readiness_probe"
check_regression readiness_node_b_fragment_preserved \
    grep -Fq 'expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d' \
    "$readiness_probe"
check_regression readiness_runner_pins_probe \
    grep -Fq 'readonly probe_sha256=0acc886c5317179571fdc0947e69f19fa57f3aa34f031ab5788727cdfee4750e' \
    "$readiness_runner"

: >"$test_root/success.order"
ACTION20D_RETRY9_ORDER_LOG=$test_root/success.order \
    /bin/bash "$outer" --production-path-test \
    "$test_root/readiness" "$test_root/activation" \
    >"$test_root/success.stdout" 2>"$test_root/success.stderr"
check_regression success_stderr_empty test ! -s "$test_root/success.stderr"
check_regression success_order test \
    "$(paste -sd, "$test_root/success.order")" = readiness,activation
for success_label in \
    action_20d_retry9_readiness_accepted=true \
    action_20d_retry9_activation_accepted=true \
    action_20d_retry9_boundary_cleanup_complete=true \
    action_20d_retry9_boundary_accepted=true \
    action_20d_retry9_readiness_stderr_classification=bounded_safe \
    action_20d_retry9_activation_stderr_classification=bounded_safe; do
    check_regression "success_${success_label%%=*}" \
        grep -Fxq "$success_label" "$test_root/success.stdout"
done
check_regression success_stream_emitted \
    grep -Fq fixture_activation_stderr=true "$test_root/success.stdout"
printf 'action_20d_retry9_regression_success_order_and_evidence=true\n'

run_failure_case() {
    local failed_gate_label=$1
    local expected_order=$2
    local failure_stdout=$test_root/$failed_gate_label-failure.stdout
    local failure_stderr=$test_root/$failed_gate_label-failure.stderr
    local failure_order=$test_root/$failed_gate_label-failure.order
    local failure_status=0

    : >"$failure_order"
    ACTION20D_RETRY9_ORDER_LOG=$failure_order \
        ACTION20D_RETRY9_FAIL_GATE=$failed_gate_label \
        /bin/bash "$outer" --production-path-test \
        "$test_root/readiness" "$test_root/activation" \
        >"$failure_stdout" 2>"$failure_stderr" || failure_status=$?
    check_regression "${failed_gate_label}_failure_status" \
        test "$failure_status" -eq 23
    check_regression "${failed_gate_label}_failure_order" \
        test "$(paste -sd, "$failure_order")" = "$expected_order"
    check_regression "${failed_gate_label}_failure_not_accepted" \
        grep -Fxq action_20d_retry9_boundary_accepted=false "$failure_stdout"
    if [[ "$failed_gate_label" = readiness ]]; then
        check_regression readiness_failure_activation_blocked \
            grep -Fxq action_20d_retry9_activation_invoked=false "$failure_stdout"
    else
        check_regression activation_failure_rollback_visible \
            grep -Fq fixture_activation_rollback_complete=true "$failure_stdout"
    fi
}

run_failure_case readiness readiness
run_failure_case activation readiness,activation
printf 'action_20d_retry9_regression_failure_ordering_and_rollback=true\n'

# The dollar-prefixed text is literal outer source.
# shellcheck disable=SC2016
check_regression readable_gates_use_bash \
    grep -Fq '/bin/bash "$boundary_gate_command"' "$outer"
check_regression complete_suite_dependency_absent \
    test "$(grep -Ec 'complete_suite|tests/run\.sh|tests/integration\.sh|correction_boundary' "$outer")" -eq 0
# The dollar-prefixed text is literal outer source.
# shellcheck disable=SC2016
check_regression readiness_precedes_activation \
    grep -Fq 'run_boundary "$readiness_outer" "$activation_outer"' "$outer"
readonly transaction=$caddy_root/scripts/activate-node-a-caddy-vrrp-action20d-retry9.sh
check_regression node_a_fragment_hash_uses_action20f_a_baseline \
    grep -Fq 'expected_fragment_sha256=6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39' \
    "$transaction"
check_regression node_a_health_user_group_uses_action20f_a_baseline \
    grep -Fq "expected_health_user_line='    user keepalived_script caddy-tls'" \
    "$transaction"
check_regression node_a_production_candidate_hash_updated \
    grep -Fq 'expected_production_candidate_sha256=49ab7ef6d2b7c988f192b79e64175ac57f309c0fd639132e34858eda400cc460' \
    "$transaction"
check_regression sanitized_health_user_group_neutralized \
    grep -Fq "user keepalived_script caddy-tls[[:space:]]*\$/    user root/" \
    "$transaction"
check_regression config_test_command_absent \
    test "$(grep -Ec '^[[:space:]]*keepalived .*--config-test|^[[:space:]]*keepalived --config-test' "$transaction" || true)" -eq 0

assert_single_file_reload_check() {
    local inspected_assertion_label=$1
    local expected_path_expression=$2
    local inspected_assertion_block

    inspected_assertion_block=$(sed -n \
        "/^record_check ${inspected_assertion_label} /,+2p" "$transaction") || return 1
    [[ "$(printf '%s\n' "$inspected_assertion_block" | wc -l)" -eq 3 ]] || return 1
    [[ "$(printf '%s\n' "$inspected_assertion_block" | grep -Foc \
        "$expected_path_expression")" -eq 1 ]] || return 1
    [[ "$(printf '%s\n' "$inspected_assertion_block" | grep -Eoc \
        "\\${literal_dollar}(main_configuration|fragment|candidate_configuration|production_configuration)")" -eq 1 ]] || return 1
    return 0
}

check_regression reload_check_config_combined_label_absent \
    test "$(grep -Fc 'record_check reload_check_config_absent' "$transaction" || true)" -eq 0
check_regression reload_check_config_main_single_file \
    assert_single_file_reload_check reload_check_config_main_absent \
    "${literal_dollar}main_configuration"
check_regression reload_check_config_fragment_single_file \
    assert_single_file_reload_check reload_check_config_fragment_absent \
    "${literal_dollar}fragment"
check_regression reload_check_config_sanitized_candidate_single_file \
    assert_single_file_reload_check reload_check_config_sanitized_candidate_absent \
    "${literal_dollar}candidate_configuration"
check_regression reload_check_config_production_candidate_single_file \
    assert_single_file_reload_check reload_check_config_production_candidate_absent \
    "${literal_dollar}production_configuration"

for grep_fixture_number in 1 2 3 4; do
    : >"$test_root/grep-fixture-$grep_fixture_number.conf"
done

multifile_grep_status=0
LC_ALL=C grep -Eic "$reload_check_pattern" \
    "$test_root/grep-fixture-1.conf" \
    "$test_root/grep-fixture-2.conf" \
    "$test_root/grep-fixture-3.conf" \
    "$test_root/grep-fixture-4.conf" \
    >"$test_root/multifile-grep.stdout" \
    2>"$test_root/multifile-grep.stderr" || multifile_grep_status=$?
check_regression gnu_multifile_no_match_status test "$multifile_grep_status" -eq 1
check_regression gnu_multifile_stderr_empty test ! -s "$test_root/multifile-grep.stderr"
check_regression gnu_multifile_output_four_lines test \
    "$(wc -l <"$test_root/multifile-grep.stdout")" -eq 4
for grep_fixture_number in 1 2 3 4; do
    check_regression "gnu_multifile_fixture_${grep_fixture_number}_filename_prefix" \
        grep -Fxq "$test_root/grep-fixture-$grep_fixture_number.conf:0" \
        "$test_root/multifile-grep.stdout"
done

multifile_numeric_status=0
LC_ALL=C test "$(<"$test_root/multifile-grep.stdout")" -eq 0 \
    2>"$test_root/multifile-numeric.stderr" || multifile_numeric_status=$?
check_regression gnu_multifile_output_not_numeric test "$multifile_numeric_status" -eq 2
check_regression gnu_multifile_numeric_error_bounded test \
    "$(wc -c <"$test_root/multifile-numeric.stderr")" -le 1024
check_regression gnu_multifile_numeric_error_visible grep -Fq \
    'integer expression expected' "$test_root/multifile-numeric.stderr"

for grep_fixture_number in 1 2 3 4; do
    single_file_count=$(grep -Eic "$reload_check_pattern" \
        "$test_root/grep-fixture-$grep_fixture_number.conf" || true)
    check_regression "single_file_fixture_${grep_fixture_number}_scalar_zero" \
        test "$single_file_count" = 0
done

printf '%s\n' 'reload_check_config yes' >"$test_root/grep-fixture-1.conf"
for grep_fixture_number in 1 2 3 4; do
    single_file_count=$(grep -Eic "$reload_check_pattern" \
        "$test_root/grep-fixture-$grep_fixture_number.conf" || true)
    expected_single_file_count=0
    if [[ "$grep_fixture_number" -eq 1 ]]; then
        expected_single_file_count=1
    fi
    check_regression "single_file_fixture_${grep_fixture_number}_match_count" \
        test "$single_file_count" = "$expected_single_file_count"
done
check_regression bounded_reload_journal_required \
    grep -Fq 'record_captured_check reload_journal_captured' "$transaction"
backup_emit_line=$(grep -n -m1 "printf '%s_backup_path=%s" "$transaction" | cut -d: -f1)
mutation_line=$(grep -n -m1 '^mutation_started=true$' "$transaction" | cut -d: -f1)
install_line=$(grep -n -m1 'install -o root -g root -m 0644.*main_configuration' \
    "$transaction" | cut -d: -f1)
check_regression backup_path_emitted_once test \
    "$(grep -Fc "printf '%s_backup_path=%s" "$transaction")" -eq 1
check_regression backup_path_emitted_before_mutation test \
    "$backup_emit_line" -lt "$mutation_line"
check_regression backup_path_emitted_before_install test \
    "$backup_emit_line" -lt "$install_line"
check_regression rollback_restart_fallback_required \
    grep -Fq 'systemctl restart keepalived.service' "$transaction"
check_regression rollback_keepalived_continuity_required \
    grep -Fq 'rollback_check keepalived_active' "$transaction"
check_regression rollback_caddy_continuity_required \
    grep -Fq 'rollback_check caddy_active' "$transaction"
check_regression rollback_lighttpd_continuity_required \
    grep -Fq 'rollback_check lighttpd_active' "$transaction"
check_regression rollback_ipv4_dns_continuity_required \
    grep -Fq 'rollback_check dns_ipv4_continuity' "$transaction"
check_regression rollback_ipv6_dns_continuity_required \
    grep -Fq 'rollback_check dns_ipv6_continuity' "$transaction"
check_regression rollback_health_continuity_required \
    grep -Fq 'run_captured rollback_health' "$transaction"
node_b_status=0
/bin/bash "$transaction" --activate node-b >/dev/null 2>&1 || node_b_status=$?
check_regression node_b_rejected_before_preflight test "$node_b_status" -eq 64
printf 'action_20d_retry9_regression_false_positive_and_false_negative_controls=true\n'
printf 'action_20d_retry9_regression_complete=true\n'
