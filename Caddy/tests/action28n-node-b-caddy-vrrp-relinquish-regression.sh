#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28n_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/relinquish-node-b-caddy-vrrp-action28n.sh
readonly outer=$caddy_root/scripts/run-node-b-caddy-vrrp-relinquish-action28n-outer.sh
readonly retired_fixture=$test_directory/fixtures/action28n-node-b-retired-main.conf
work_root=$(mktemp -d /tmp/caddy-action28n-regression.XXXXXX)
readonly work_root

cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
check() {
    local action28n_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28n_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28n_regression_label" >&2
    return 1
}
make_node_a_fixture() {
    local action28n_regression_output=$1
    local action28n_regression_label

    : >"$action28n_regression_output"
    while IFS= read -r action28n_regression_label; do
        printf 'action_28m_b_check_%s=true\n' "$action28n_regression_label" >>"$action28n_regression_output"
    done < <("$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh" --expected-checks)
    printf '%s\n' \
        'action_28m_b_first_failure=none' \
        'action_28m_b_node_b_contacted=false' \
        'action_28m_b_mutation=false' \
        'action_28m_b_acceptance=true' >>"$action28n_regression_output"
}
make_transaction_fixture() {
    local action28n_regression_output=$1
    local action28n_regression_mode=${2:-success}
    local action28n_regression_label

    : >"$action28n_regression_output"
    while IFS= read -r action28n_regression_label; do
        if [[ "$action28n_regression_mode" = false_check && "$action28n_regression_label" = caddy_ipv6_absent_after ]]; then
            printf 'action_28n_check_%s=false\n' "$action28n_regression_label" >>"$action28n_regression_output"
        else
            printf 'action_28n_check_%s=true\n' "$action28n_regression_label" >>"$action28n_regression_output"
        fi
    done < <("$transaction" --expected-checks)
    printf '%s\n' \
        'action_28n_value_first_failure=none' \
        'action_28n_rollback_invoked=false' \
        'action_28n_keepalived_reload_count=1' \
        'action_28n_node_a_ssh_contacted=false' \
        'action_28n_acceptance=true' >>"$action28n_regression_output"
}
make_mock_ssh() {
    local action28n_regression_mock=$1

    cat >"$action28n_regression_mock" <<'MOCK'
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
payload=$(mktemp /tmp/caddy-action28n-mock-payload.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
if [[ "$target" = pi@10.1.0.53 && "$command" = 'cd / && sudo -n /bin/bash -s --' ]]; then
    cat "${ACTION28N_NODE_A_FIXTURE:?}"
elif [[ "$target" = pi@10.1.0.54 && "$command" = 'cd / && sudo -n /bin/bash -s -- --execute' ]]; then
    grep -Fq 'readonly prefix=action_28n' "$payload"
    cat "${ACTION28N_NODE_B_FIXTURE:?}"
elif [[ "$target" = pi@10.1.0.54 && "$command" = 'cd / && sudo -n /bin/bash -s -- --rollback' ]]; then
    cat "${ACTION28N_ROLLBACK_FIXTURE:?}"
else
    printf 'unexpected transport: target=%s command=%s\n' "$target" "$command" >&2
    exit 96
fi
MOCK
    chmod 0755 "$action28n_regression_mock"
}
run_outer_case() {
    local action28n_regression_case=$1
    local action28n_regression_transaction_fixture=$2
    local action28n_regression_expected_status=$3
    local action28n_regression_case_root=$work_root/$action28n_regression_case
    local action28n_regression_status=0

    mkdir -m 0700 "$action28n_regression_case_root"
    CADDY_ACTION28N_TEST_MODE=1 \
        CADDY_ACTION28N_SSH_BIN=$mock_ssh \
        ACTION28N_NODE_A_FIXTURE=$node_a_fixture \
        ACTION28N_NODE_B_FIXTURE=$action28n_regression_transaction_fixture \
        ACTION28N_ROLLBACK_FIXTURE=$rollback_fixture \
        /bin/bash "$outer" >"$action28n_regression_case_root/stdout" \
        2>"$action28n_regression_case_root/stderr" || action28n_regression_status=$?
    if [[ "$action28n_regression_status" -ne "$action28n_regression_expected_status" ]]; then
        printf '%s_case_%s_observed_status=%s\n' "$prefix" "$action28n_regression_case" \
            "$action28n_regression_status" >&2
        cat "$action28n_regression_case_root/stdout" >&2
        cat "$action28n_regression_case_root/stderr" >&2
        return 1
    fi
}

check retired_fixture_hash test "$(sha256sum "$retired_fixture" | awk '{ print $1 }')" = \
    9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
baseline_fixture=$work_root/baseline.conf
{
    cat "$retired_fixture"
    printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n'
} >"$baseline_fixture"
check baseline_fixture_hash test "$(sha256sum "$baseline_fixture" | awk '{ print $1 }')" = \
    5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
check production_candidate_boundary "$transaction" --candidate-test "$baseline_fixture" "$retired_fixture"
wrong_boundary=$work_root/wrong-boundary.conf
head -n -1 "$baseline_fixture" >"$wrong_boundary"
if "$transaction" --candidate-test "$baseline_fixture" "$wrong_boundary" >/dev/null 2>&1; then
    printf '%s_check_wrong_boundary_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_wrong_boundary_rejected=true\n' "$prefix"
coupled_fixture=$work_root/coupled.conf
cp -- "$retired_fixture" "$coupled_fixture"
sed -i '/10.1.0.55\/22 dev eth0/a\        10.1.0.56/22 dev eth0' "$coupled_fixture"
if "$transaction" --candidate-test "$baseline_fixture" "$coupled_fixture" >/dev/null 2>&1; then
    printf '%s_check_coupled_candidate_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_coupled_candidate_rejected=true\n' "$prefix"

node_a_fixture=$work_root/node-a.fixture
node_b_fixture=$work_root/node-b.fixture
false_fixture=$work_root/node-b-false.fixture
rollback_fixture=$work_root/rollback.fixture
mock_ssh=$work_root/ssh
make_node_a_fixture "$node_a_fixture"
make_transaction_fixture "$node_b_fixture"
make_transaction_fixture "$false_fixture" false_check
: >"$rollback_fixture"
make_mock_ssh "$mock_ssh"
if run_outer_case success "$node_b_fixture" 0; then
    printf '%s_check_production_transport_success=true\n' "$prefix"
else
    printf '%s_check_production_transport_success=false\n' "$prefix" >&2
    exit 1
fi
if run_outer_case false-label "$false_fixture" 1; then
    printf '%s_check_false_production_label_rejected=true\n' "$prefix"
else
    printf '%s_check_false_production_label_rejected=false\n' "$prefix" >&2
    exit 1
fi
check execute_command_exact grep -Fq \
    "'cd / && sudo -n /bin/bash -s -- --execute'" "$outer"
check malformed_execute_command_absent test \
    "$(grep -Fxc "'cd / && sudo -n /bin/bash -s/ -- --execute'" "$outer" || true)" -eq 0
printf '%s_complete=true\n' "$prefix"
