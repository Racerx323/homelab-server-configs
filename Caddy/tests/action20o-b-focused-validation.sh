#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20o_b_focused_validation
readonly inspector_sha256=9e99fda15f3d730916dca95ef91b96864233c22fde9b8dfa7312b1ce220f7a11
readonly outer_sha256=5ad88ca05ab3450914d444ae27a83cbb891e5aadbadaa24939f1e2947c97a1ff
readonly regression_sha256=b88a264ca3643f075991d4ecf030e399354992aee934398a05ab4eb4bd46efe4

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-keepalived-dbus-postactivation-action20o-b.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-postactivation-action20o-b-outer.sh
readonly regression=$test_directory/action20o-b-node-b-postactivation-regression.sh
readonly focused=$test_directory/action20o-b-focused-validation.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20ob_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20ob_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20ob_focused_label" >&2
    return 1
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
for action20ob_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action20ob_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action20ob_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
record_check regression /bin/bash "$regression"

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_health_helpers_invoked=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
