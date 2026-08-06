#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly candidate=$caddy_root/scripts/check-caddy-instrumented-action20d-retry10-d.sh
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-action20d-retry10-d.sh
readonly old_helper=$caddy_root/scripts/check-caddy-action20b.sh
readonly candidate_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly old_helper_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20d_d_regression_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20d_d_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20d_d_regression_label" >&2
    return 1
}
helper_contract_exact() {
    local action20d_d_service_line
    local action20d_d_validation_line
    local action20d_d_endpoint_line

    action20d_d_service_line=$(grep -nF 'health_run_stage service systemctl is-active --quiet caddy' \
        "$candidate" | cut -d: -f1) || return 1
    action20d_d_validation_line=$(grep -nF 'health_run_stage validation caddy validate' \
        "$candidate" | cut -d: -f1) || return 1
    action20d_d_endpoint_line=$(grep -nF 'health_run_stage endpoint curl' \
        "$candidate" | cut -d: -f1) || return 1
    [[ "$action20d_d_service_line" -lt "$action20d_d_validation_line" ]] || return 1
    [[ "$action20d_d_validation_line" -lt "$action20d_d_endpoint_line" ]] || return 1
    [[ "$(grep -Fc 'source /etc/default/caddy-ha' "$candidate")" -eq 1 ]] || return 1
    [[ "$(grep -Fc 'https://localhost' "$candidate")" -eq 1 ]] || return 1
    [[ "$(grep -Ec '(^|[[:space:]])timeout([[:space:]]|$)' "$candidate" || true)" -eq 0 ]] || return 1
    grep -Fq "trap 'health_on_signal TERM 143' TERM" "$candidate" || return 1
    grep -Fq "trap 'health_on_signal INT 130' INT" "$candidate" || return 1
    grep -Fq 'event=terminated' "$candidate" || return 1
    grep -Fq 'classification=unsafe_suppressed' "$candidate" || return 1
    grep -Fq 'classification=bounded_safe' "$candidate" || return 1
}
installer_scope_exact() {
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop|enable|disable)' \
        "$installer" "$runner" || return 1
    ! grep -Eq 'ip[[:space:]].*(address|addr)[[:space:]]+(add|delete|del|replace)' \
        "$installer" "$runner" || return 1
    grep -Fq 'sleep 7' "$installer" || return 1
    grep -Fq 'helper_invoked_by_transaction=false' "$installer" || return 1
    grep -Fq 'keepalived_reloaded=false' "$installer" || return 1
    grep -Fq 'persistent_mutation_scope=health_helper,rollback_backup' "$installer" || return 1
}
run_helper_case() {
    local action20d_d_mode=$1
    local action20d_d_expected_status=$2
    local action20d_d_expected_event=$3
    local action20d_d_status=0

    /bin/bash "$candidate" --regression "$action20d_d_mode" \
        >"$fixture_root/helper-$action20d_d_mode.stdout" \
        2>"$fixture_root/helper-$action20d_d_mode.stderr" || action20d_d_status=$?
    [[ "$action20d_d_status" -eq "$action20d_d_expected_status" ]] || return 1
    [[ ! -s "$fixture_root/helper-$action20d_d_mode.stderr" ]] || return 1
    grep -Fq "$action20d_d_expected_event" \
        "$fixture_root/helper-$action20d_d_mode.stdout" || return 1
    ! grep -Eqi 'PRIVATE KEY|DOPPLER_TOKEN|Authorization:' \
        "$fixture_root/helper-$action20d_d_mode.stdout" || return 1
}
create_fake_ssh() {
    local action20d_d_fake_path=$1

    cat >"$action20d_d_fake_path" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >/dev/null
mode=${CADDY_ACTION20D_RETRY10_D_FIXTURE_MODE:-success}
first=true
while IFS= read -r label; do
    if [[ "$mode" == missing && "$first" == true ]]; then
        first=false
        continue
    fi
    first=false
    printf 'action_20d_retry10_d_check_%s=true\n' "$label"
done < <(/bin/bash "$CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER" --expected-checks)
if [[ "$mode" == duplicate ]]; then
    printf 'action_20d_retry10_d_check_identity_root=true\n'
elif [[ "$mode" == false ]]; then
    printf 'action_20d_retry10_d_check_identity_root=false\n'
fi
printf '%s\n' \
    'action_20d_retry10_d_preflight_complete=true' \
    'action_20d_retry10_d_mutation_started=true' \
    'action_20d_retry10_d_backup_path=/var/backups/caddy-ha/action20d-retry10-d-node-a-health-instrumentation.ABC123' \
    'action_20d_retry10_d_helper_invoked_by_transaction=false' \
    'action_20d_retry10_d_keepalived_reloaded=false' \
    'action_20d_retry10_d_service_mutations=false' \
    'action_20d_retry10_d_vrrp_mutations=false' \
    'action_20d_retry10_d_vip_mutations=false' \
    'action_20d_retry10_d_persistent_mutation_scope=health_helper,rollback_backup' \
    'action_20d_retry10_d_install_complete=true'
FAKE_SSH
    chmod 0755 "$action20d_d_fake_path"
}
run_intercepted_runner() {
    local action20d_d_mode=$1
    local action20d_d_expected_status=$2
    local action20d_d_status=0

    CADDY_ACTION20D_RETRY10_D_SSH_BINARY="$fixture_root/fake-ssh" \
        CADDY_ACTION20D_RETRY10_D_FIXTURE_MODE="$action20d_d_mode" \
        CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER="$installer" \
        /bin/bash "$runner" >"$fixture_root/runner-$action20d_d_mode.stdout" \
        2>"$fixture_root/runner-$action20d_d_mode.stderr" || action20d_d_status=$?
    [[ "$action20d_d_status" -eq "$action20d_d_expected_status" ]] || return 1
    [[ ! -s "$fixture_root/runner-$action20d_d_mode.stderr" ]] || return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
create_fake_ssh "$fixture_root/fake-ssh"

check candidate_hash test "$(file_hash "$candidate")" = "$candidate_sha256"
check old_helper_hash test "$(file_hash "$old_helper")" = "$old_helper_sha256"
check candidate_self_test /bin/bash "$candidate" --self-test
check installer_self_test /bin/bash "$installer" --self-test
check runner_self_test /bin/bash "$runner" --self-test
check helper_contract helper_contract_exact
check installer_scope installer_scope_exact
check assertion_inventory_unique test \
    "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq \
    "$(/bin/bash "$installer" --expected-checks | LC_ALL=C sort -u | wc -l)"
check helper_failure_observable run_helper_case failure 1 'event=stage'
check helper_slow_observable run_helper_case slow 0 'event=stage'
check helper_term_observable run_helper_case term 143 'event=terminated'
check production_success run_intercepted_runner success 0
check production_missing_rejected run_intercepted_runner missing 1
check production_duplicate_rejected run_intercepted_runner duplicate 1
check production_false_rejected run_intercepted_runner false 1
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
