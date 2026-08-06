#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry5_a_focused
readonly diagnostic_sha256=1f0cb96acc9f04325c943cb18b378b2a8d75cadfcaa5bb8673f2511053d27ce7
readonly outer_sha256=7169a2983ec7c2b95f8eaba3feca429c3d2b4696d4a6e0a9202aca1d20bc7afd
readonly regression_sha256=e94a5ca55006f63f6243ca03f0af6d55e62307ca146524dbfe9cd30ae84b77d1

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly diagnostic=$caddy_root/scripts/diagnose-node-a-keepalived-pidfile-isolation-action20d-retry5-a.sh
readonly outer=$caddy_root/scripts/run-node-a-keepalived-pidfile-isolation-action20d-retry5-a-outer.sh
readonly regression=$test_directory/action20d-retry5-a-pidfile-isolation-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly outer_policy=$test_directory/outer-local-gate-label-policy-regression.sh

record_gate() {
    local focused_gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$focused_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$focused_gate_label" >&2
    return 1
}
hash_exact() {
    local expected_focused_hash=$1
    local inspected_focused_file=$2

    [[ "$(sha256sum "$inspected_focused_file" | awk '{ print $1 }')" = "$expected_focused_hash" ]] || return 1
    return 0
}
complete_suite_dependency_absent() {
    ! grep -Eq 'tests/run\.sh|tests/integration\.sh|complete_suite' \
        "$diagnostic" "$outer" "$regression" || return 1
    return 0
}

record_gate diagnostic_hash_exact hash_exact "$diagnostic_sha256" "$diagnostic"
record_gate outer_hash_exact hash_exact "$outer_sha256" "$outer"
record_gate regression_hash_exact hash_exact "$regression_sha256" "$regression"
record_gate syntax /bin/bash -n "$diagnostic" "$outer" "$regression" "$0"
record_gate shellcheck shellcheck "$diagnostic" "$outer" "$regression" "$0"
record_gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$diagnostic" "$outer" "$regression" "$0"
record_gate collision_policy /bin/bash "$collision" \
    "$diagnostic" "$outer" "$regression" "$0"
record_gate complete_suite_bypassed complete_suite_dependency_absent
record_gate diagnostic_self_test /bin/bash "$diagnostic" --self-test
record_gate outer_local_gate_policy /bin/bash "$outer_policy" --runner "$outer"
record_gate production_path_regression /bin/bash "$regression"

printf '%s_complete_suite_invoked=false\n' "$prefix"
printf '%s_podman_invoked=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_keepalived_config_test_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_validation_complete=true\n' "$prefix"
