#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly diagnostic=$caddy_root/scripts/inspect-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-timing-action20d-retry10-c.sh
readonly diagnostic_sha256=6d71149eaecbb629be2064d2eeea31b7a6416276568e884633173978b0819034
readonly runner_sha256=d0ae53fe95b29f78c2a1997c3e80a94abf524e5686c2f012a677f2be0f35a751

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local timing_regression_label=$1

    shift
    if "$@"; then
        printf 'action_20d_retry10_c_regression_%s=true\n' "$timing_regression_label"
        return 0
    fi
    printf 'action_20d_retry10_c_regression_%s=false\n' "$timing_regression_label" >&2
    return 1
}
assertion_inventory_exact() {
    local timing_inventory_root=$1

    /bin/bash "$diagnostic" --expected-assertions >"$timing_inventory_root/labels"
    [[ "$(wc -l <"$timing_inventory_root/labels")" -ge 50 ]] || return 1
    [[ "$(wc -l <"$timing_inventory_root/labels")" -eq "$(LC_ALL=C sort -u "$timing_inventory_root/labels" | wc -l)" ]] || return 1
    ! grep -Ev '^[a-z0-9_]+$' "$timing_inventory_root/labels" | grep -q .
}
read_only_scope_exact() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable|mask|unmask)' \
        "$diagnostic" "$runner" || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$diagnostic" "$runner" || return 1
    ! grep -Eq '(install|cp|mv)[[:space:]].*(/etc/|/usr/local/|/var/backups/)' \
        "$diagnostic" "$runner" || return 1
    [[ "$(grep -Fc 'pi@10.1.0.53' "$runner")" -eq 1 ]] || return 1
    ! grep -Eq '10\.1\.0\.54|pihole00|node-b' "$diagnostic" "$runner" || return 1
}
complete_helper_execution_absent() {
    ! grep -Eq '(^|[[:space:]])(capture_command|run_probe|runuser|setpriv).*health_helper|/bin/bash.*health_helper' \
        "$diagnostic" || return 1
    grep -Fq "printf '%s_complete_helper_invoked=false" "$diagnostic" || return 1
}
component_timing_contract_exact() {
    local timing_component

    for timing_component in service_probe caddy_validate_probe curl_probe; do
        [[ "$(grep -Ec "^capture_command ${timing_component}([[:space:]]|$)" \
            "$diagnostic")" -eq 1 ]] || return 1
        [[ "$(grep -Ec "^run_assertion ${timing_component}_status_zero([[:space:]]|$)" \
            "$diagnostic")" -eq 1 ]] || return 1
        [[ "$(grep -Ec "^run_assertion ${timing_component}_elapsed_numeric([[:space:]]|$)" \
            "$diagnostic")" -eq 1 ]] || return 1
    done
}
journal_window_contract_exact() {
    local timing_journal_label

    for timing_journal_label in journal_keepalived_0732 journal_caddy_0732 \
        journal_keepalived_0736 journal_caddy_0736 \
        journal_keepalived_0841 journal_caddy_0841; do
        [[ "$(grep -Ec "^capture_command ${timing_journal_label}([[:space:]]|$)" \
            "$diagnostic")" -eq 1 ]] || return 1
    done
}
create_fake_ssh() {
    local timing_fake_path=$1

    # The generated fixture must expand these variables only when it executes.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'tmp=$(mktemp /tmp/caddy-action20d-retry10-c-fake.XXXXXX)' \
        'trap '\''rm -f -- "$tmp"'\'' EXIT' \
        'cat >"$tmp"' \
        'case "${CADDY_ACTION20D_RETRY10_C_FIXTURE_MODE:-success}" in' \
        '  success) CADDY_ACTION20D_RETRY10_C_REGRESSION=1 /bin/bash "$tmp" --fixture-success ;;' \
        '  missing) CADDY_ACTION20D_RETRY10_C_REGRESSION=1 /bin/bash "$tmp" --fixture-success | sed '\''/assertion_identity_root=/d'\'' ;;' \
        '  false) CADDY_ACTION20D_RETRY10_C_REGRESSION=1 /bin/bash "$tmp" --fixture-success | sed '\''s/assertion_identity_root=true/assertion_identity_root=false/'\'' ;;' \
        '  duplicate) CADDY_ACTION20D_RETRY10_C_REGRESSION=1 /bin/bash "$tmp" --fixture-success | sed '\''/assertion_identity_root=true/p'\'' ;;' \
        '  *) exit 64 ;;' \
        'esac' >"$timing_fake_path"
    chmod 0755 "$timing_fake_path"
}
run_intercepted_fixture() {
    local timing_fixture_mode=$1
    local timing_expected_status=$2
    local timing_fixture_status=0

    CADDY_ACTION20D_RETRY10_C_SSH_BINARY="$fixture_root/fake-ssh" \
        CADDY_ACTION20D_RETRY10_C_FIXTURE_MODE="$timing_fixture_mode" \
        /bin/bash "$runner" >"$fixture_root/$timing_fixture_mode.stdout" \
        2>"$fixture_root/$timing_fixture_mode.stderr" || timing_fixture_status=$?
    [[ "$timing_fixture_status" -eq "$timing_expected_status" ]] || return 1
    [[ ! -s "$fixture_root/$timing_fixture_mode.stderr" ]] || return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-c-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
create_fake_ssh "$fixture_root/fake-ssh"

check diagnostic_hash test "$(file_hash "$diagnostic")" = "$diagnostic_sha256"
check runner_hash test "$(file_hash "$runner")" = "$runner_sha256"
check diagnostic_self_test /bin/bash "$diagnostic" --self-test
check diagnostic_classification_test /bin/bash "$diagnostic" --classification-test
check runner_self_test /bin/bash "$runner" --self-test
check assertion_inventory assertion_inventory_exact "$fixture_root"
check read_only_scope read_only_scope_exact
check complete_helper_not_executed complete_helper_execution_absent
check component_timing_contract component_timing_contract_exact
check journal_window_contract journal_window_contract_exact
check production_success run_intercepted_fixture success 0
check production_missing_rejected run_intercepted_fixture missing 1
check production_false_rejected run_intercepted_fixture false 1
check production_duplicate_rejected run_intercepted_fixture duplicate 1
printf 'action_20d_retry10_c_regression_false_positive_controls=true\n'
printf 'action_20d_retry10_c_regression_false_negative_controls=true\n'
printf 'action_20d_retry10_c_regression_node_contact=false\n'
printf 'action_20d_retry10_c_regression_complete=true\n'
