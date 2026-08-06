#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20f_a_focused
readonly inspector_sha256=25c9c45f8b56252500982735c5b5a395b887a4c00c662399c2ea127fe46985d9
readonly runner_sha256=cd0712ef35a583f34f6f711af0a9ad8c9ea2d44323b874d5b324ae7aa2230811
readonly regression_sha256=37e557f720d39d4f5e0ded1868d2ce4783e6c44b9bf6f73de907de9273925a67
readonly outer_sha256=a4defbeab49958ecaadf1c2e34c259a847ecf0cc5b9a86d359da2c210d8b68c9

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-health-group-postinstall-action20f-a.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-group-postinstall-action20f-a.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-group-postinstall-action20f-a-outer.sh
readonly regression=$test_directory/action20f-a-node-a-caddy-health-group-postinstall-regression.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh
readonly transcript=$test_directory/transcript-contract-ratchet-policy-regression.sh
readonly output_evidence=$test_directory/transaction-output-evidence-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_gate() {
    local action20fa_focused_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$action20fa_focused_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action20fa_focused_label" >&2
    return 1
}
exact_source() {
    local action20fa_expected_hash=$1
    local action20fa_source_path=$2

    [[ -f "$action20fa_source_path" && ! -L "$action20fa_source_path" &&
        -x "$action20fa_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20fa_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20fa_source_path")" = "$action20fa_expected_hash" ]] || return 1
}
forbidden_live_path_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|(^|[;&|[:space:]])ip[[:space:]]+(address|addr)[[:space:]]+(add|replace|delete|del)|(^|[;&|[:space:]])(mv|rsync|scp|sftp)[[:space:]]' \
        "$inspector" "$runner" "$outer"
}

require_gate inspector_exact exact_source "$inspector_sha256" "$inspector"
require_gate runner_exact exact_source "$runner_sha256" "$runner"
require_gate regression_exact exact_source "$regression_sha256" "$regression"
require_gate outer_exact exact_source "$outer_sha256" "$outer"
require_gate syntax /bin/bash -n "$inspector" "$runner" "$regression" "$outer"
require_gate shellcheck shellcheck "$inspector" "$runner" "$regression" "$outer"
require_gate canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$inspector" "$runner" "$regression" "$outer"
require_gate collision_policy /bin/bash "$collision" \
    "$inspector" "$runner" "$regression" "$outer"
require_gate conditional_policy /bin/bash "$conditional"
require_gate transcript_policy /bin/bash "$transcript"
require_gate output_evidence_policy /bin/bash "$output_evidence"
require_gate inspector_self_test /bin/bash "$inspector" --self-test
require_gate runner_self_test /bin/bash "$runner" --self-test
require_gate runner_contract_test /bin/bash "$runner" --contract-test
require_gate regression_self_test /bin/bash "$regression" --self-test
require_gate regression_production_path /bin/bash "$regression"
require_gate outer_self_test /bin/bash "$outer" --self-test
require_gate exact_assertion_count test \
    "$(/bin/bash "$inspector" --expected-assertions | wc -l)" -eq 171
require_gate exact_assertion_labels_unique test \
    "$(/bin/bash "$inspector" --expected-assertions | LC_ALL=C sort -u | wc -l)" -eq 171
require_gate forbidden_live_path_absent forbidden_live_path_absent
printf '%s_complete_suite_invoked=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_validation_complete=true\n' "$prefix"
