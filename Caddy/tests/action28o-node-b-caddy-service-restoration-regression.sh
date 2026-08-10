#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28o_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/restore-node-b-caddy-service-action28o.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-service-restoration-action28o-outer.sh
work_root=$(mktemp -d /tmp/caddy-action28o-regression.XXXXXX)
readonly work_root

cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
check() {
    local action28o_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28o_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28o_regression_label" >&2
    return 1
}
make_node_a_fixture() {
    local action28o_regression_output=$1
    local action28o_regression_label

    : >"$action28o_regression_output"
    while IFS= read -r action28o_regression_label; do
        printf 'action_28m_b_check_%s=true\n' "$action28o_regression_label" >>"$action28o_regression_output"
    done < <("$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh" --expected-checks)
    printf '%s\n' \
        'action_28m_b_first_failure=none' \
        'action_28m_b_node_b_contacted=false' \
        'action_28m_b_mutation=false' \
        'action_28m_b_acceptance=true' >>"$action28o_regression_output"
}
make_transaction_fixture() {
    local action28o_regression_output=$1
    local action28o_regression_mode=${2:-success}
    local action28o_regression_label

    : >"$action28o_regression_output"
    while IFS= read -r action28o_regression_label; do
        if [[ "$action28o_regression_mode" = missing && "$action28o_regression_label" = caddy_active_after_sample_3 ]]; then
            continue
        fi
        if [[ "$action28o_regression_mode" = false_check && "$action28o_regression_label" = caddy_active_after_sample_3 ]]; then
            printf 'action_28o_check_%s=false\n' "$action28o_regression_label" >>"$action28o_regression_output"
        else
            printf 'action_28o_check_%s=true\n' "$action28o_regression_label" >>"$action28o_regression_output"
        fi
        if [[ "$action28o_regression_mode" = duplicate && "$action28o_regression_label" = caddy_active_after_sample_3 ]]; then
            printf 'action_28o_check_%s=true\n' "$action28o_regression_label" >>"$action28o_regression_output"
        fi
    done < <("$transaction" --expected-checks)
    [[ "$action28o_regression_mode" != extra ]] || printf 'action_28o_check_unexpected=true\n' >>"$action28o_regression_output"
    printf '%s\n' \
        'action_28o_value_first_failure=none' \
        'action_28o_rollback_invoked=false' \
        'action_28o_caddy_start_count=1' \
        'action_28o_keepalived_reload_count=0' \
        'action_28o_node_a_ssh_contacted=false' \
        'action_28o_acceptance=true' >>"$action28o_regression_output"
}
make_rollback_fixture() {
    local action28o_regression_output=$1
    local action28o_regression_label

    : >"$action28o_regression_output"
    while IFS= read -r action28o_regression_label; do
        printf 'action_28o_rollback_check_%s=true\n' "$action28o_regression_label" >>"$action28o_regression_output"
    done < <("$transaction" --expected-rollback-checks)
    printf '%s\n' \
        'action_28o_rollback_first_failure=none' \
        'action_28o_rollback_acceptance=true' >>"$action28o_regression_output"
}
make_mock_ssh() {
    local action28o_regression_mock=$1

    cat >"$action28o_regression_mock" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
target=
command=
for argument in "$@"; do
    case "$argument" in
        pi@10.1.0.53 | pi@10.1.0.54) target=$argument ;;
        cd\ /*) command=$argument ;;
    esac
done
payload=$(mktemp /tmp/caddy-action28o-mock-payload.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
if [[ "$target" = pi@10.1.0.53 && "$command" = 'cd / && sudo -n /bin/bash -s --' ]]; then
    grep -Fq 'readonly prefix=action_28m_b' "$payload"
    cat "${ACTION28O_NODE_A_FIXTURE:?}"
elif [[ "$target" = pi@10.1.0.54 && "$command" = 'cd / && sudo -n /bin/bash -s -- --execute' ]]; then
    grep -Fq 'readonly prefix=action_28o' "$payload"
    /bin/bash "$payload" --expected-checks >/dev/null
    cat "${ACTION28O_NODE_B_FIXTURE:?}"
elif [[ "$target" = pi@10.1.0.54 && "$command" = 'cd / && sudo -n /bin/bash -s -- --rollback' ]]; then
    grep -Fq 'readonly prefix=action_28o' "$payload"
    cat "${ACTION28O_ROLLBACK_FIXTURE:?}"
else
    printf 'unexpected transport: target=%s command=%s\n' "$target" "$command" >&2
    exit 96
fi
MOCK
    chmod 0755 "$action28o_regression_mock"
}
run_outer_case() {
    local action28o_regression_case=$1
    local action28o_regression_transaction_fixture=$2
    local action28o_regression_expected_status=$3
    local action28o_regression_case_root=$work_root/$action28o_regression_case
    local action28o_regression_status=0

    mkdir -m 0700 "$action28o_regression_case_root"
    CADDY_ACTION28O_TEST_MODE=1 \
        CADDY_ACTION28O_SELF_TEST_MODE=1 \
        CADDY_ACTION28O_SSH_BIN=$mock_ssh \
        ACTION28O_NODE_A_FIXTURE=$node_a_fixture \
        ACTION28O_NODE_B_FIXTURE=$action28o_regression_transaction_fixture \
        ACTION28O_ROLLBACK_FIXTURE=$rollback_fixture \
        /bin/bash "$outer" >"$action28o_regression_case_root/stdout" \
        2>"$action28o_regression_case_root/stderr" || action28o_regression_status=$?
    if [[ "$action28o_regression_status" -ne "$action28o_regression_expected_status" ]]; then
        printf '%s_case_%s_observed_status=%s\n' "$prefix" "$action28o_regression_case" \
            "$action28o_regression_status" >&2
        cat "$action28o_regression_case_root/stdout" >&2
        cat "$action28o_regression_case_root/stderr" >&2
        return 1
    fi
}

node_a_fixture=$work_root/node-a.fixture
node_b_fixture=$work_root/node-b.fixture
missing_fixture=$work_root/node-b-missing.fixture
false_fixture=$work_root/node-b-false.fixture
duplicate_fixture=$work_root/node-b-duplicate.fixture
extra_fixture=$work_root/node-b-extra.fixture
rollback_fixture=$work_root/rollback.fixture
mock_ssh=$work_root/ssh
make_node_a_fixture "$node_a_fixture"
make_transaction_fixture "$node_b_fixture"
make_transaction_fixture "$missing_fixture" missing
make_transaction_fixture "$false_fixture" false_check
make_transaction_fixture "$duplicate_fixture" duplicate
make_transaction_fixture "$extra_fixture" extra
make_rollback_fixture "$rollback_fixture"
make_mock_ssh "$mock_ssh"

if run_outer_case success "$node_b_fixture" 0; then
    printf '%s_check_production_transport_success=true\n' "$prefix"
else
    printf '%s_check_production_transport_success=false\n' "$prefix" >&2
    exit 1
fi
for action28o_regression_negative_case in missing false-label duplicate extra; do
    case "$action28o_regression_negative_case" in
        missing) action28o_regression_negative_fixture=$missing_fixture ;;
        false-label) action28o_regression_negative_fixture=$false_fixture ;;
        duplicate) action28o_regression_negative_fixture=$duplicate_fixture ;;
        extra) action28o_regression_negative_fixture=$extra_fixture ;;
    esac
    if ! CADDY_ACTION28O_TEST_MODE=1 /bin/bash "$outer" --transaction-transcript-test \
        "$action28o_regression_negative_fixture" /dev/null 0 >/dev/null 2>&1; then
        printf '%s_check_%s_production_label_rejected=true\n' "$prefix" \
            "${action28o_regression_negative_case//-/_}"
    else
        printf '%s_check_%s_production_label_rejected=false\n' "$prefix" \
            "${action28o_regression_negative_case//-/_}" >&2
        exit 1
    fi
done
check execute_command_exact grep -Fq \
    "'cd / && sudo -n /bin/bash -s -- --execute'" "$outer"
check rollback_command_exact grep -Fq \
    "'cd / && sudo -n /bin/bash -s -- --rollback'" "$outer"
check malformed_execute_command_absent test \
    "$(grep -Fxc "'cd / && sudo -n /bin/bash -s/ -- --execute'" "$outer" || true)" -eq 0
check keepalived_reload_absent test \
    "$(grep -Fxc 'systemctl reload keepalived.service' "$transaction" || true)" -eq 0
check start_before_success_samples awk '
    /run_captured start systemctl start caddy[.]service/ { start = NR }
    /caddy_active_after_sample_/ { sample = NR }
    END { exit start > 0 && sample > start ? 0 : 1 }
' "$transaction"
check rollback_stops_caddy grep -Fq 'systemctl stop caddy.service' "$transaction"
check transaction_collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" "$transaction"
collision_fixture=$work_root/collision.sh
# The fixture intentionally contains a literal dynamic-scope collision.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly collision=value' \
    'bad() {' \
    '    local collision=other' \
    '    : "$collision"' \
    '}' >"$collision_fixture"
if /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$collision_fixture" >/dev/null 2>&1; then
    printf '%s_check_dynamic_scope_collision_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_dynamic_scope_collision_rejected=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
