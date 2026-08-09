#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_a_retry_focused_validation
readonly source_inspector_sha256=55bf9878744e75ff7f79cb93d565cd4c5bb3e500bc2a575c04333e94456ee2f8
readonly source_outer_sha256=e2450fc5d10115d7576d8ad39535688e5abf29c43f028b8b27de03e4d30730e3
readonly retry_outer_sha256=cd97f5e1ffc197598a2c95cec53ead857e624f806cdd5a165862f5826578f16d
readonly regression_sha256=63b5de59aee07c623064a20653643de2c92f1698852c8adbcc696c87f90de1fc
readonly rendered_inspector_sha256=a72b9ae988513de85bc0dc15bcdb777482e2d769e4458a6046fd4da90c678663
readonly rendered_core_sha256=bd1e83db6c7682385a5497df9a9aa20813016cb63a5fc86a400e103b6e00efb7

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly source_inspector=$caddy_root/scripts/inspect-dual-node-keepalived-post-action20p-a.sh
readonly source_outer=$caddy_root/scripts/run-dual-node-keepalived-post-action20p-a-outer.sh
readonly retry_outer=$caddy_root/scripts/run-dual-node-keepalived-post-action20p-a-retry-outer.sh
readonly regression=$test_directory/action20p-a-retry-dual-node-postactivation-regression.sh
readonly focused=$test_directory/action20p-a-retry-focused-validation.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20pa_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20pa_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20pa_retry_focused_label" >&2
    return 1
}

record_check source_inspector_immutable test "$(file_hash "$source_inspector")" = "$source_inspector_sha256"
record_check source_outer_immutable test "$(file_hash "$source_outer")" = "$source_outer_sha256"
record_check retry_outer_hash test "$(file_hash "$retry_outer")" = "$retry_outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
action20pa_retry_focused_rendered_hashes=$(/bin/bash "$retry_outer" --render-hashes)
readonly action20pa_retry_focused_rendered_hashes
record_check rendered_inspector_hash grep -Fqx \
    "rendered_inspector_sha256=$rendered_inspector_sha256" <<<"$action20pa_retry_focused_rendered_hashes"
record_check rendered_core_hash grep -Fqx \
    "rendered_core_sha256=$rendered_core_sha256" <<<"$action20pa_retry_focused_rendered_hashes"
record_check regression /bin/bash "$regression"
record_check syntax /bin/bash -n "$retry_outer" "$regression" "$focused"
record_check shellcheck shellcheck "$retry_outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$retry_outer" "$regression" "$focused"
record_check outer_gate_inventory_unique test \
    "$("$retry_outer" --expected-local-gates | wc -l)" -eq \
    "$("$retry_outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
for action20pa_retry_focused_entrypoint in "$retry_outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action20pa_retry_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action20pa_retry_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_keepalived_restart=false\n' "$prefix"
printf '%s_dbus_runtime_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_repository_policies_exercised_by_intercepted_outer=true\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
