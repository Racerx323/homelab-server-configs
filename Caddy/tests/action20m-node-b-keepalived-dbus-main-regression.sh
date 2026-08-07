#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_regression
readonly expected_check_count=71

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly installer=$caddy_root/scripts/install-node-b-keepalived-dbus-main-action20m.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-main-action20m-outer.sh
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh

record_gate() {
    local action20m_regression_gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20m_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20m_regression_gate_label" >&2
    return 1
}
setup_fixture() {
    local action20m_regression_fixture_root=$1
    local action20m_regression_stage=$2
    local action20m_regression_source=$action20m_regression_stage/keepalived-pihole00.conf
    local action20m_regression_main=$action20m_regression_fixture_root/etc/keepalived/keepalived.conf

    install -d -m 0700 "$action20m_regression_stage" || return 1
    install -d -m 0755 \
        "$action20m_regression_fixture_root/etc/keepalived/conf.d" \
        "$action20m_regression_fixture_root/usr/local/libexec" \
        "$action20m_regression_fixture_root/run/caddy-ha" \
        "$action20m_regression_fixture_root/var/backups" || return 1
    printf '%s\n' \
        '# node-b fixture' \
        'global_defs {' \
        '    router_id j1-svpihole00' \
        '    script_user pi' \
        '    enable_script_security' \
        '    enable_dbus' \
        '    vrrp_check_unicast_src' \
        '    vrrp_version 3' \
        '}' \
        '' \
        'vrrp_instance PIHOLE_IPV4 {' \
        '    state BACKUP' \
        '}' >"$action20m_regression_source" || return 1
    chmod 0600 "$action20m_regression_source" || return 1
    sed '/^[[:space:]]*enable_dbus$/d' "$action20m_regression_source" \
        >"$action20m_regression_main" || return 1
    printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n' \
        >>"$action20m_regression_main" || return 1
    printf 'node-b-fragment\n' \
        >"$action20m_regression_fixture_root/etc/keepalived/conf.d/caddy-ha.conf" || return 1
    printf '#!/usr/bin/env bash\nexit 0\n' \
        >"$action20m_regression_fixture_root/usr/local/libexec/check-caddy.sh" || return 1
    printf 'BACKUP\n' >"$action20m_regression_fixture_root/run/caddy-ha/vrrp-state" || return 1
    chmod 0644 "$action20m_regression_main" \
        "$action20m_regression_fixture_root/etc/keepalived/conf.d/caddy-ha.conf" || return 1
    chmod 0755 "$action20m_regression_fixture_root/usr/local/libexec/check-caddy.sh" || return 1
}
export_test_context() {
    local action20m_regression_fixture_root=$1

    export ACTION20M_TEST_MODE=1
    export ACTION20M_TEST_ROOT=$action20m_regression_fixture_root
    export ACTION20M_TEST_HOSTNAME=j1-svpihole00
    export ACTION20M_TEST_ARCHITECTURE=arm64
    export ACTION20M_TEST_SERVICES_ACTIVE=true
    export ACTION20M_TEST_KEEPALIVED_PID=4242
    export ACTION20M_TEST_KEEPALIVED_RESTARTS=0
    export ACTION20M_BUNDLE_PARENT=/tmp
    export ACTION20M_BUNDLE_OWNER
    ACTION20M_BUNDLE_OWNER=$(id -un) || return 1
    export ACTION20M_BUNDLE_GROUP
    ACTION20M_BUNDLE_GROUP=$(id -gn) || return 1
}
run_installer() (
    local action20m_regression_fixture_root=$1
    local action20m_regression_stage=$2
    local action20m_regression_stdout=$3
    local action20m_regression_stderr=$4

    export_test_context "$action20m_regression_fixture_root" || return 1
    cd / || return 1
    /bin/bash "$installer" --stage "$action20m_regression_stage" \
        >"$action20m_regression_stdout" 2>"$action20m_regression_stderr"
)
validate_with_outer() {
    local action20m_regression_stdout=$1
    local action20m_regression_stderr=$2
    local action20m_regression_status=$3

    CADDY_ACTION20M_TEST_MODE=1 /bin/bash "$outer" --test-validate-success \
        "$action20m_regression_stdout" "$action20m_regression_stderr" \
        "$action20m_regression_status"
}
validate_real_producer() {
    local action20m_regression_stdout=$1
    local action20m_regression_stderr=$2
    local action20m_regression_validator_status=0

    validate_with_outer "$action20m_regression_stdout" "$action20m_regression_stderr" 0 ||
        action20m_regression_validator_status=$?
    if [[ "$action20m_regression_validator_status" -ne 0 ]]; then
        printf '%s_observed_producer_lines=%s\n' "$prefix" \
            "$(awk 'END { print NR }' "$action20m_regression_stdout")" >&2
        printf '%s_observed_producer_sha256=%s\n' "$prefix" \
            "$(sha256sum "$action20m_regression_stdout" | awk '{ print $1 }')" >&2
        printf '%s_observed_validator_status=%s\n' "$prefix" \
            "$action20m_regression_validator_status" >&2
        return "$action20m_regression_validator_status"
    fi
}
make_mock_ssh() {
    local action20m_regression_mock=$1

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'exec /bin/bash' >"$action20m_regression_mock" || return 1
    chmod 0755 "$action20m_regression_mock"
}
run_regression() (
    local action20m_regression_root
    local action20m_regression_success_root
    local action20m_regression_success_stage
    local action20m_regression_success_stdout
    local action20m_regression_success_stderr
    local action20m_regression_failure_root
    local action20m_regression_failure_stage
    local action20m_regression_failure_stdout
    local action20m_regression_failure_stderr
    local action20m_regression_failure_status=0
    local action20m_regression_original_main_hash
    local action20m_regression_mock_root
    local action20m_regression_mock_stage
    local action20m_regression_mock_ssh
    local action20m_regression_mock_stdout
    local action20m_regression_mock_stderr
    local action20m_regression_case
    local action20m_regression_case_status=0
    local action20m_regression_collision_fixture

    action20m_regression_root=$(mktemp -d /tmp/caddy-action20m-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$action20m_regression_root"' EXIT
    action20m_regression_success_root=$action20m_regression_root/success-root
    action20m_regression_success_stage=$action20m_regression_root/success-stage
    action20m_regression_success_stdout=$action20m_regression_root/success.stdout
    action20m_regression_success_stderr=$action20m_regression_root/success.stderr
    setup_fixture "$action20m_regression_success_root" "$action20m_regression_success_stage" || return 1
    run_installer "$action20m_regression_success_root" "$action20m_regression_success_stage" \
        "$action20m_regression_success_stdout" "$action20m_regression_success_stderr" || return 1
    record_gate success_stderr_empty test ! -s "$action20m_regression_success_stderr" || return 1
    record_gate success_check_count test \
        "$(grep -Ec '^action_20m_check_[a-z0-9_]+=true$' "$action20m_regression_success_stdout")" \
        -eq "$expected_check_count" || return 1
    record_gate real_producer_transcript_accepted validate_real_producer \
        "$action20m_regression_success_stdout" "$action20m_regression_success_stderr" || return 1
    record_gate installed_candidate_enable_dbus grep -Fqx '    enable_dbus' \
        "$action20m_regression_success_root/etc/keepalived/keepalived.conf" || return 1

    for action20m_regression_case in false missing duplicate reordered wrong_prefix; do
        cp -- "$action20m_regression_success_stdout" \
            "$action20m_regression_root/$action20m_regression_case.stdout" || return 1
    done
    sed -i '0,/=true$/s/=true$/=false/' "$action20m_regression_root/false.stdout" || return 1
    sed -i '1d' "$action20m_regression_root/missing.stdout" || return 1
    sed -n '1p' "$action20m_regression_success_stdout" \
        >>"$action20m_regression_root/duplicate.stdout" || return 1
    awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
        "$action20m_regression_success_stdout" >"$action20m_regression_root/reordered.tmp" || return 1
    mv "$action20m_regression_root/reordered.tmp" "$action20m_regression_root/reordered.stdout" || return 1
    sed -i '0,/^action_20m_check_/s//action_20x_check_/' \
        "$action20m_regression_root/wrong_prefix.stdout" || return 1
    for action20m_regression_case in false missing duplicate reordered wrong_prefix; do
        action20m_regression_case_status=0
        validate_with_outer "$action20m_regression_root/$action20m_regression_case.stdout" \
            "$action20m_regression_success_stderr" 0 >/dev/null 2>&1 ||
            action20m_regression_case_status=$?
        record_gate "${action20m_regression_case}_transcript_rejected" test \
            "$action20m_regression_case_status" -ne 0 || return 1
    done
    printf 'unexpected stderr\n' >"$action20m_regression_root/nonempty.stderr"
    action20m_regression_case_status=0
    validate_with_outer "$action20m_regression_success_stdout" \
        "$action20m_regression_root/nonempty.stderr" 0 >/dev/null 2>&1 ||
        action20m_regression_case_status=$?
    record_gate stderr_rejected test "$action20m_regression_case_status" -ne 0 || return 1
    action20m_regression_case_status=0
    validate_with_outer "$action20m_regression_success_stdout" \
        "$action20m_regression_success_stderr" 1 >/dev/null 2>&1 ||
        action20m_regression_case_status=$?
    record_gate nonzero_status_rejected test "$action20m_regression_case_status" -ne 0 || return 1

    action20m_regression_failure_root=$action20m_regression_root/failure-root
    action20m_regression_failure_stage=$action20m_regression_root/failure-stage
    action20m_regression_failure_stdout=$action20m_regression_root/failure.stdout
    action20m_regression_failure_stderr=$action20m_regression_root/failure.stderr
    setup_fixture "$action20m_regression_failure_root" "$action20m_regression_failure_stage" || return 1
    action20m_regression_original_main_hash=$(sha256sum \
        "$action20m_regression_failure_root/etc/keepalived/keepalived.conf" | awk '{ print $1 }') || return 1
    export_test_context "$action20m_regression_failure_root" || return 1
    action20m_regression_failure_status=0
    (
        cd / || exit 1
        ACTION20M_TEST_FAIL_AFTER_INSTALL=1 /bin/bash "$installer" \
            --stage "$action20m_regression_failure_stage"
    ) >"$action20m_regression_failure_stdout" 2>"$action20m_regression_failure_stderr" ||
        action20m_regression_failure_status=$?
    record_gate injected_failure_nonzero test "$action20m_regression_failure_status" -eq 1 || return 1
    record_gate rollback_started grep -Fqx action_20m_rollback_started=true \
        "$action20m_regression_failure_stderr" || return 1
    record_gate rollback_complete grep -Fqx action_20m_rollback_complete=true \
        "$action20m_regression_failure_stderr" || return 1
    record_gate rollback_main_restored test \
        "$(sha256sum "$action20m_regression_failure_root/etc/keepalived/keepalived.conf" | awk '{ print $1 }')" = \
        "$action20m_regression_original_main_hash" || return 1

    action20m_regression_mock_root=$action20m_regression_root/mock-root
    action20m_regression_mock_stage=$action20m_regression_root/mock-source
    action20m_regression_mock_ssh=$action20m_regression_root/mock-ssh
    action20m_regression_mock_stdout=$action20m_regression_root/mock.stdout
    action20m_regression_mock_stderr=$action20m_regression_root/mock.stderr
    setup_fixture "$action20m_regression_mock_root" "$action20m_regression_mock_stage" || return 1
    make_mock_ssh "$action20m_regression_mock_ssh" || return 1
    export_test_context "$action20m_regression_mock_root" || return 1
    CADDY_ACTION20M_TEST_MODE=1 \
        CADDY_ACTION20M_SSH_BINARY=$action20m_regression_mock_ssh \
        CADDY_ACTION20M_SOURCE_PATH=$action20m_regression_mock_stage/keepalived-pihole00.conf \
        /bin/bash "$outer" --test-transport \
        >"$action20m_regression_mock_stdout" 2>"$action20m_regression_mock_stderr" || return 1
    record_gate bundled_production_path_stderr_empty test ! -s "$action20m_regression_mock_stderr" || return 1
    record_gate bundled_production_path_complete grep -Fqx \
        action_20m_outer_complete=true "$action20m_regression_mock_stdout" || return 1

    action20m_regression_collision_fixture=$action20m_regression_root/collision.sh
    # The fixture intentionally contains a literal dynamic-scope collision.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'readonly action20m_collision=value' \
        'collision() {' \
        '    local action20m_collision=other' \
        '    printf '\''%s\n'\'' "$action20m_collision"' \
        '}' >"$action20m_regression_collision_fixture" || return 1
    action20m_regression_case_status=0
    /bin/bash "$collision_checker" "$action20m_regression_collision_fixture" \
        >/dev/null 2>&1 || action20m_regression_case_status=$?
    record_gate dynamic_scope_collision_rejected test "$action20m_regression_case_status" -eq 1 || return 1
    record_gate collision_policy_clean /bin/bash "$collision_checker" \
        "$installer" "$outer" "$0" || return 1
    printf '%s_false_negative_real_success_accepted=true\n' "$prefix"
    printf '%s_false_positive_invalid_transcripts_rejected=true\n' "$prefix"
    printf '%s_false_negative_rollback_restored=true\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_regression
