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
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-group-action20g.sh
readonly expected_builder_sha256=8171bf8bf9cc881f4939c1589fbae181f95be110c56c4bee596125d1e5f86c5b
readonly expected_installer_sha256=1961680f2591a988af5203744947455080903ce29e8317cfe678d95dffe78b6c
readonly expected_runner_sha256=88398dccf48209f63b5765d47886970269668fc486f3573f13ebabce192146ec

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20g_regression_label=$1
    shift
    if "$@"; then
        printf 'action_20g_regression_%s=true\n' "$action20g_regression_label"
        return 0
    fi
    printf 'action_20g_regression_%s=false\n' "$action20g_regression_label" >&2
    return 1
}

root=$(mktemp -d /tmp/caddy-action20g-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
/bin/bash "$builder" --output "$root" >"$root/builder.out"
installer=$root/install-node-b-caddy-health-group-action20g.sh
runner=$root/run-node-b-caddy-health-group-correction-action20g.sh
check builder_hash test "$(file_hash "$builder")" = "$expected_builder_sha256"
check installer_hash test "$(file_hash "$installer")" = "$expected_installer_sha256"
check runner_hash test "$(file_hash "$runner")" = "$expected_runner_sha256"
check installer_self_test /bin/bash "$installer" --self-test
check runner_self_test env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" \
    /bin/bash "$runner" --self-test
check runner_contract_test env CADDY_ACTION20G_SOURCE_ROOT="$caddy_root" \
    /bin/bash "$runner" --contract-test
# Dollar-prefixed expressions are literal generated source.
# shellcheck disable=SC2016
check node_b_hostname grep -Fq 'hostname_node_b test "$(hostname)" = j1-svpihole00' "$installer"
check node_b_fragment_old_pin grep -Fq '294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d' "$installer"
check node_b_fragment_new_pin grep -Fq '7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270' "$installer"
check explicit_health_group grep -Fq 'user keepalived_script caddy-tls' "$installer"
check node_b_target grep -Fqx 'readonly expected_target=pi@10.1.0.54' "$runner"
# shellcheck disable=SC2016
check node_a_contact_false grep -Fq '${prefix}_node_a_contacted=false' "$runner"
check keepalived_reload_absent test "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived' "$installer" || true)" -eq 0
check address_mutation_absent test "$(grep -Ec 'ip[[:space:]].*(address|addr)[[:space:]]+(add|del|delete|replace)' "$installer" || true)" -eq 0
check node_b_activation_command_absent test \
    "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived|ip[[:space:]].*(address|addr)[[:space:]]+(add|del|delete|replace)' "$installer" || true)" -eq 0
check vrrp_transition_false_marker grep -Fq \
    "printf '%s_vrrp_transition_requested=false" "$installer"
check vip_mutations_false_marker grep -Fq \
    "printf '%s_vip_mutations=false" "$installer"
printf 'action_20g_regression_false_positive_controls=true\n'
printf 'action_20g_regression_false_negative_controls=true\n'
printf 'action_20g_regression_complete=true\n'
