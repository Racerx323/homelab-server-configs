#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry
readonly transaction_sha256=4297a17a328653a6daa03eaee011bd1dc47bd541c6c889221ba39ce8d50081c8
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly transaction="$script_directory/activate-caddy-vrrp-node-action20d-retry.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
readonly ssh_binary=${CADDY_ACTION20D_RETRY_SSH_BINARY:-ssh}

work_directory=
node_a_backup=
node_b_backup=
node_a_activated=false
node_b_activated=false
action_complete=false
retain_work_directory=false

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_one() {
    local required_record=$1
    local required_transcript=$2

    [[ "$(grep -Fxc "$required_record" "$required_transcript")" -eq 1 ]]
}
safe_stream() {
    local inspected_stream=$1

    [[ "$(wc -c <"$inspected_stream")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$inspected_stream")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream"
}
emit_stream() {
    local evidence_label=$1
    local evidence_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$evidence_label" \
        "$(wc -c <"$evidence_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$evidence_label" \
        "$(line_count "$evidence_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$evidence_label" \
        "$(file_hash "$evidence_path")"
    if ! safe_stream "$evidence_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$evidence_label" >&2
        retain_work_directory=true
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$evidence_label"
    if [[ -s "$evidence_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$evidence_label"
        cat "$evidence_path"
        printf '%s_%s_end\n' "$prefix" "$evidence_label"
    else
        printf '%s_%s_content_secured=empty\n' "$prefix" "$evidence_label"
    fi
}
role_target() {
    case "$1" in
        node-a) printf '%s\n' pi@10.1.0.53 ;;
        node-b) printf '%s\n' pi@10.1.0.54 ;;
        *) return 64 ;;
    esac
}
role_alias() {
    case "$1" in
        node-a) printf '%s\n' pihole0.local.theama.co ;;
        node-b) printf '%s\n' pihole00.local.theama.co ;;
        *) return 64 ;;
    esac
}
invoke_remote() {
    local invocation_label=$1
    local invocation_role=$2
    local invocation_phase=$3
    local invocation_backup=${4:-}
    local invocation_target
    local invocation_alias
    local invocation_status=0

    invocation_target=$(role_target "$invocation_role") || return 64
    invocation_alias=$(role_alias "$invocation_role") || return 64
    : >"$work_directory/$invocation_label.stdout"
    : >"$work_directory/$invocation_label.stderr"
    chmod 0600 "$work_directory/$invocation_label.stdout" \
        "$work_directory/$invocation_label.stderr"
    if [[ -n "$invocation_backup" ]]; then
        "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=yes -o HostKeyAlias="$invocation_alias" \
            "$invocation_target" sudo -n /bin/bash -s -- \
            "$invocation_phase" "$invocation_role" "$invocation_backup" \
            <"$transaction" >"$work_directory/$invocation_label.stdout" \
            2>"$work_directory/$invocation_label.stderr" || invocation_status=$?
    else
        "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=yes -o HostKeyAlias="$invocation_alias" \
            "$invocation_target" sudo -n /bin/bash -s -- \
            "$invocation_phase" "$invocation_role" \
            <"$transaction" >"$work_directory/$invocation_label.stdout" \
            2>"$work_directory/$invocation_label.stderr" || invocation_status=$?
    fi
    printf '%s\n' "$invocation_status" >"$work_directory/$invocation_label.status"
    emit_stream "${invocation_label}_stdout" \
        "$work_directory/$invocation_label.stdout" || return 97
    emit_stream "${invocation_label}_stderr" \
        "$work_directory/$invocation_label.stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" "$invocation_label" \
        "$invocation_status"
    return "$invocation_status"
}
validate_assertion_inventory() {
    local inventory_mode=$1
    local inventory_transcript=$2
    local inventory_expected=$work_directory/inventory-expected
    local inventory_observed=$work_directory/inventory-observed
    local inventory_label

    : >"$inventory_expected"
    : >"$inventory_observed"
    while IFS= read -r inventory_label; do
        printf '%s_check_%s\n' action_20d_retry_node "$inventory_label"
    done < <(/bin/bash "$transaction" "$inventory_mode") |
        LC_ALL=C sort >"$inventory_expected"
    sed -n 's/^\(action_20d_retry_node_check_[a-z0-9_]*\)=true$/\1/p' \
        "$inventory_transcript" | LC_ALL=C sort >"$inventory_observed" ||
        return 1
    # conditional-validator-explicit-failures-begin
    [[ "$(wc -l <"$inventory_expected")" -gt 0 ]] || return 1
    [[ "$(LC_ALL=C sort -u "$inventory_expected" | wc -l)" -eq "$(wc -l <"$inventory_expected")" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$inventory_observed" | wc -l)" -eq "$(wc -l <"$inventory_observed")" ]] || return 1
    ! grep -Eq '^action_20d_retry_node_check_[a-z0-9_]+=false$' \
        "$inventory_transcript" || return 1
    cmp -s "$inventory_expected" "$inventory_observed" || return 1
    # conditional-validator-explicit-failures-end
}
validate_activation() {
    local activation_role=$1
    local activation_transcript=$2
    local activation_error=$3
    local activation_expected_state
    local activation_expected_count

    if [[ "$activation_role" = node-a ]]; then
        activation_expected_state=MASTER
        activation_expected_count=1
    else
        activation_expected_state=BACKUP
        activation_expected_count=0
    fi
    # conditional-validator-explicit-failures-begin
    [[ ! -s "$activation_error" ]] || return 1
    validate_assertion_inventory --expected-checks "$activation_transcript" ||
        return 1
    if ! require_one "action_20d_retry_node_value_node_role=$activation_role" \
        "$activation_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_vrrp_state=$activation_expected_state" \
        "$activation_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_caddy_ipv4_count=$activation_expected_count" \
        "$activation_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_caddy_ipv6_count=$activation_expected_count" \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_notification_helper_transition_invocation_expected=true' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_validation_scope=sanitized_ephemeral_candidate_only' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_production_fragment_installed_unchanged=true' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_health_helper_execution_context=keepalived_script' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_notification_helper_preflight_invoked=false' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_persistent_mutation_scope=main_include,rollback_backup' \
        "$activation_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_activation_complete=true' \
        "$activation_transcript"; then return 1; fi
    if ! [[ "$(grep -Ec '^action_20d_retry_node_backup_path=/var/backups/caddy-ha/action20d-retry-(node-a|node-b)-caddy-vrrp\.[A-Za-z0-9]+$' \
        "$activation_transcript")" -eq 1 ]]; then return 1; fi
    # conditional-validator-explicit-failures-end
}
validate_inspection() {
    local inspection_role=$1
    local inspection_transcript=$2
    local inspection_error=$3
    local inspection_expected_state
    local inspection_expected_count

    if [[ "$inspection_role" = node-a ]]; then
        inspection_expected_state=MASTER
        inspection_expected_count=1
    else
        inspection_expected_state=BACKUP
        inspection_expected_count=0
    fi
    # conditional-validator-explicit-failures-begin
    [[ ! -s "$inspection_error" ]] || return 1
    validate_assertion_inventory --expected-inspection-checks \
        "$inspection_transcript" || return 1
    if ! require_one "action_20d_retry_node_value_node_role=$inspection_role" \
        "$inspection_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_vrrp_state=$inspection_expected_state" \
        "$inspection_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_caddy_ipv4_count=$inspection_expected_count" \
        "$inspection_transcript"; then return 1; fi
    if ! require_one "action_20d_retry_node_value_caddy_ipv6_count=$inspection_expected_count" \
        "$inspection_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_filesystem_mutations=false' \
        "$inspection_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_service_mutations=false' \
        "$inspection_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_vrrp_mutations=false' \
        "$inspection_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_vip_mutations=false' \
        "$inspection_transcript"; then return 1; fi
    if ! require_one 'action_20d_retry_node_inspection_complete=true' \
        "$inspection_transcript"; then return 1; fi
    # conditional-validator-explicit-failures-end
}
extract_backup() {
    local backup_transcript=$1
    local backup_value

    [[ "$(grep -c '^action_20d_retry_node_backup_path=' "$backup_transcript")" -eq 1 ]] ||
        return 1
    backup_value=$(sed -n 's/^action_20d_retry_node_backup_path=//p' \
        "$backup_transcript") || return 1
    [[ "$backup_value" =~ ^/var/backups/caddy-ha/action20d-retry-(node-a|node-b)-caddy-vrrp\.[A-Za-z0-9]+$ ]] ||
        return 1
    printf '%s\n' "$backup_value"
}
verify_sources() {
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    # conditional-validator-explicit-failures-begin
    if ! [[ -f "$transaction" && ! -L "$transaction" && -x "$transaction" ]]; then
        return 1
    fi
    if ! [[ "$(stat -c '%U:%G:%a' "$transaction")" = "$source_identity" ]]; then
        return 1
    fi
    [[ "$(file_hash "$transaction")" = "$transaction_sha256" ]] || return 1
    /bin/bash -n "$transaction" || return 1
    /bin/bash "$transaction" --self-test >/dev/null || return 1
    /bin/bash "$collision_checker" "$0" "$transaction" >/dev/null || return 1
    # conditional-validator-explicit-failures-end
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
rollback_nodes() {
    local rollback_failed=false

    if [[ "$node_b_activated" = true && -n "$node_b_backup" ]]; then
        if invoke_remote node_b_rollback node-b --rollback "$node_b_backup"; then
            require_one 'action_20d_retry_node_explicit_rollback_complete=true' \
                "$work_directory/node_b_rollback.stdout" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    if [[ "$node_a_activated" = true && -n "$node_a_backup" ]]; then
        if invoke_remote node_a_rollback node-a --rollback "$node_a_backup"; then
            require_one 'action_20d_retry_node_explicit_rollback_complete=true' \
                "$work_directory/node_a_rollback.stdout" || rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    if [[ "$rollback_failed" = true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        return 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
}
on_exit() {
    local action_exit_status=$?

    if [[ "$action_complete" != true ]] &&
        [[ "$node_a_activated" = true || "$node_b_activated" = true ]]; then
        rollback_nodes || action_exit_status=125
    fi
    if [[ "$retain_work_directory" = true ]]; then
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    elif [[ -n "$work_directory" && -d "$work_directory" ]]; then
        rm -rf -- "$work_directory"
    fi
    exit "$action_exit_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        contract_root=$(mktemp -d /tmp/caddy-action20d-retry-contract.XXXXXX)
        readonly contract_root
        trap 'rm -rf -- "$contract_root"' EXIT
        : >"$contract_root/empty.stderr"
        while IFS= read -r contract_label; do
            printf 'action_20d_retry_node_check_%s=true\n' "$contract_label"
        done < <(/bin/bash "$transaction" --expected-checks) \
        >"$contract_root/valid.stdout"
        printf '%s\n' \
            'action_20d_retry_node_value_node_role=node-a' \
            'action_20d_retry_node_value_vrrp_state=MASTER' \
            'action_20d_retry_node_value_caddy_ipv4_count=1' \
            'action_20d_retry_node_value_caddy_ipv6_count=1' \
            'action_20d_retry_node_notification_helper_transition_invocation_expected=true' \
            'action_20d_retry_node_validation_scope=sanitized_ephemeral_candidate_only' \
            'action_20d_retry_node_production_fragment_installed_unchanged=true' \
            'action_20d_retry_node_health_helper_execution_context=keepalived_script' \
            'action_20d_retry_node_notification_helper_preflight_invoked=false' \
            'action_20d_retry_node_persistent_mutation_scope=main_include,rollback_backup' \
            'action_20d_retry_node_backup_path=/var/backups/caddy-ha/action20d-retry-node-a-caddy-vrrp.FIXTURE' \
            'action_20d_retry_node_activation_complete=true' \
            >>"$contract_root/valid.stdout"
        work_directory=$contract_root
        validate_activation node-a "$contract_root/valid.stdout" \
            "$contract_root/empty.stderr"
        sed -i '/action_20d_retry_node_check_root_user=true/d' \
            "$contract_root/valid.stdout"
        if validate_activation node-a "$contract_root/valid.stdout" \
            "$contract_root/empty.stderr"; then
            exit 1
        fi
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20d-retry-runner.XXXXXX)
readonly work_directory
trap on_exit EXIT

if invoke_remote node_a_activate node-a --activate; then
    node_a_activated=true
    node_a_backup=$(extract_backup "$work_directory/node_a_activate.stdout") || exit 97
    validate_activation node-a "$work_directory/node_a_activate.stdout" \
        "$work_directory/node_a_activate.stderr" || exit 97
else
    exit $?
fi
if invoke_remote node_b_activate node-b --activate; then
    node_b_activated=true
    node_b_backup=$(extract_backup "$work_directory/node_b_activate.stdout") || exit 97
    validate_activation node-b "$work_directory/node_b_activate.stdout" \
        "$work_directory/node_b_activate.stderr" || exit 97
else
    exit $?
fi
invoke_remote node_a_post node-a --inspect
validate_inspection node-a "$work_directory/node_a_post.stdout" \
    "$work_directory/node_a_post.stderr"
invoke_remote node_b_post node-b --inspect
validate_inspection node-b "$work_directory/node_b_post.stdout" \
    "$work_directory/node_b_post.stderr"

printf '%s_cross_check_single_ipv4_owner=true\n' "$prefix"
printf '%s_cross_check_single_ipv6_owner=true\n' "$prefix"
printf '%s_cross_check_dualstack_owner_node_a=true\n' "$prefix"
printf '%s_cross_check_node_b_backup=true\n' "$prefix"
printf '%s_cross_check_dns_owner_unchanged_node_a=true\n' "$prefix"
printf '%s_cross_check_notification_attempts_expected=true\n' "$prefix"
printf '%s_node_a_backup_path=%s\n' "$prefix" "$node_a_backup"
printf '%s_node_b_backup_path=%s\n' "$prefix" "$node_b_backup"
printf '%s_persistent_mutation_scope=two_main_includes,two_rollback_backups\n' \
    "$prefix"
printf '%s_activation_accepted=true\n' "$prefix"
action_complete=true
rm -rf -- "$work_directory"
trap - EXIT
