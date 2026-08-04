#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19c_a_definition_regression
readonly derivation_sha256=30132cf21f3b5768f1f11548e5321d512104bfda8825751402e65b716ae212de
readonly outer_sha256=70b1427eca2207ff584eedee7ce65fff661defb13d6ee6c45e52accb1cafbbca
readonly inspector_sha256=57e3bf9d9ae61b4e2b6017118481f492bd29c5784e74710a367b620230e0bea9
readonly runner_sha256=25b08fae82ac5f682f0e1f3a6dabd170864ff3d8ecc604ab9a18cc7c42c65484
readonly regression_sha256=8f4e5a7db1a542ab2236be3e137d2ebe5ae589713b073251f8f95612c493b0e2

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-keepalived-prerequisite-action19c-a.sh"
readonly outer="$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

static_read_only_policy() {
    local policy_inspector_path=$1
    local policy_runner_path=$2

    # conditional-validator-explicit-failures-begin
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$policy_inspector_path" "$policy_runner_path"; then
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)|ip[[:space:]].*address[[:space:]]+(add|del|replace)' \
        "$policy_inspector_path" "$policy_runner_path"; then
        return 1
    fi
    grep -Fq "printf '%s_helper_execution=false" "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    grep -Fq "printf '%s_filesystem_mutations=false" \
        "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    grep -Fq "printf '%s_service_mutations=false" "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    grep -Fq "printf '%s_vrrp_mutations=false" "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    grep -Fq "printf '%s_vip_mutations=false" "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    grep -Fq "printf '%s_persistent_mutations=false" \
        "$policy_inspector_path" ||
        return 1 # conditional-validator-requires-return
    # conditional-validator-explicit-failures-end
    return 0
}

require_gate derivation_hash_exact test "$(file_hash "$derivation")" = \
    "$derivation_sha256"
require_gate self_collision_policy "$collision_checker" "${BASH_SOURCE[0]}"
require_gate outer_hash_exact test "$(file_hash "$outer")" = "$outer_sha256"
require_gate source_syntax bash -n "$derivation" "$outer"
require_gate source_shellcheck shellcheck "$derivation" "$outer"
require_gate source_collision_policy "$collision_checker" "$derivation" "$outer"
require_gate derivation_self_test "$derivation" --self-test
require_gate outer_self_test "$outer" --self-test
require_gate outer_contract_test "$outer" --contract-test

regression_root=$(mktemp -d /tmp/caddy-action19c-a-definition.XXXXXX)
readonly regression_root
# shellcheck disable=SC2317
cleanup() { rm -rf -- "$regression_root"; }
trap cleanup EXIT

# Literal negative-fixture source.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly collision_probe=global' \
    'probe() {' \
    '    local collision_probe=local' \
    '    : "$collision_probe"' \
    '}' >"$regression_root/collision.fixture"
if "$collision_checker" "$regression_root/collision.fixture" >/dev/null 2>&1; then
    printf '%s_dynamic_scope_collision_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_dynamic_scope_collision_rejected=true\n' "$prefix"

printf '%s\n' \
    'systemctl restart prohibited.service' \
    "printf '%s_helper_execution=false" \
    "printf '%s_filesystem_mutations=false" \
    "printf '%s_service_mutations=false" \
    "printf '%s_vrrp_mutations=false" \
    "printf '%s_vip_mutations=false" \
    "printf '%s_persistent_mutations=false" \
    >"$regression_root/early-invalid.fixture"
: >"$regression_root/empty-runner.fixture"
if static_read_only_policy "$regression_root/early-invalid.fixture" \
    "$regression_root/empty-runner.fixture"; then
    printf '%s_early_invalid_later_valid_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_early_invalid_later_valid_rejected=true\n' "$prefix"

grep -v '^systemctl restart prohibited\.service$' \
    "$regression_root/early-invalid.fixture" \
    >"$regression_root/valid-policy.fixture"
require_gate valid_policy_fixture_accepted static_read_only_policy \
    "$regression_root/valid-policy.fixture" \
    "$regression_root/empty-runner.fixture"

"$derivation" --output-directory "$regression_root"
readonly inspector="$regression_root/Caddy/scripts/inspect-node-a-keepalived-prerequisite-action19c-a.sh"
readonly runner="$regression_root/Caddy/scripts/run-node-a-keepalived-prerequisite-action19c-a.sh"
readonly regression="$regression_root/Caddy/tests/action19c-a-node-a-keepalived-prerequisite-regression.sh"

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate regression_hash_exact test "$(file_hash "$regression")" = \
    "$regression_sha256"
require_gate rendered_syntax bash -n "$inspector" "$runner" "$regression"
require_gate rendered_shellcheck shellcheck "$inspector" "$runner" \
    "$regression"
require_gate rendered_collision_policy "$collision_checker" "$inspector" \
    "$runner" "$regression"
require_gate node_a_hostname grep -Fq 'j1-svpihole0' "$inspector"
require_gate node_a_ipv4 grep -Fq '10.1.0.53/22' "$inspector"
require_gate node_a_ipv6 grep -Fq 'fd36:5aa8:6971:1::53/64' "$inspector"
require_gate node_a_target grep -Fq 'pi@10.1.0.53' "$runner"
require_gate node_a_alias grep -Fq 'pihole0.local.theama.co' "$runner"
require_gate node_a_release grep -Fq \
    '/etc/caddy/releases/action16ar-retry-node-a-default-deny' "$inspector"
require_gate node_a_keepalived_tree grep -Fq \
    'dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66' \
    "$inspector"
require_gate health_supported grep -Fq \
    'record_command health_state_supported state_supported' "$inspector"
require_gate notification_supported grep -Fq \
    'record_command notification_state_supported state_supported' "$inspector"
# Literal production-source assertion.
# shellcheck disable=SC2016
require_gate fragment_absence_required grep -Fq \
    'record_command fragment_absent test ! -e "$fragment"' "$inspector"
require_gate node_b_identity_absent bash -c \
    '! grep -Eq "j1-svpihole00|10\\.1\\.0\\.54|::54|pihole00\\." "$@"' \
    _ "$inspector" "$runner" "$regression"
require_gate exact_assertion_inventory test \
    "$("$inspector" --expected-assertions | wc -l)" -eq 61
require_gate static_read_only_policy static_read_only_policy "$inspector" \
    "$runner"
require_gate production_regression "$regression"
require_gate no_arbitrary_minimum bash -c \
    '! grep -Eq "\\[\\[ \\\"\\\$[A-Za-z_]*(check|assertion)[A-Za-z_]*\\\" -g[et] [0-9]+" "$@"' \
    _ "$inspector" "$runner" "$regression"

printf '%s_false_negative_supported_helper_states_accepted=true\n' "$prefix"
printf '%s_false_positive_unexpected_helper_state_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_state_drift_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
