#!/usr/bin/env bash

set -u -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"
readonly legacy_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly primary_stage=/var/tmp/caddy-unbound-node-a-action17i-primary
readonly final_stage=/var/tmp/caddy-unbound-node-a-action17j-local-zone
readonly accepted_live_primary_sha256=dd5af7ccbbac11324921e1d447d753dbab33b633bc4cb1db248ee0574825d3ae
readonly accepted_state_sha256=7b00e0d91512674b446e3b783db77351f8686b867ccf8ccd02283aa7abba6b74
readonly staged_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly primary_manifest_sha256=af6d77bbdea6c7aada55f7fcf41a2406a1a6e90a04eca33a97ec4313c6e2ba7c
readonly primary_metadata_sha256=6a5e95a5cf7ed12b289b586c965a678f85966ad1c2692a5a272d14c47a3da1a9
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_root_include='include-toplevel: "/etc/unbound/unbound.conf.d/*.conf"'
readonly expected_preflight_assertion_count=64
readonly expected_total_assertion_count=90

assertion_count=0
failed_assertion_count=0
first_failure=none
transaction_stage=
final_stage_created_by_action=false
transaction_complete=false
before_state=

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

active_directives() {
    awk '
        /^[[:space:]]*(#|$)/ { next }
        {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/[[:space:]]+/, " ")
            print
        }
    ' "$@"
}

state_snapshot() {
    local snapshot_path

    for snapshot_path in "$live_root" "$live_primary" "$live_local_zone" \
        "$legacy_local_zone"; do
        if [[ -f "$snapshot_path" && ! -L "$snapshot_path" ]]; then
            printf 'file|%s|%s|%s\n' \
                "$snapshot_path" \
                "$(stat -c '%U:%G:%a:%s' "$snapshot_path")" \
                "$(file_hash "$snapshot_path")"
        elif [[ -L "$snapshot_path" ]]; then
            printf 'link|%s|%s\n' "$snapshot_path" \
                "$(readlink -- "$snapshot_path")"
        else
            printf 'absent|%s\n' "$snapshot_path"
        fi
    done
    systemctl show --property=ActiveState,SubState,UnitFileState \
        pihole-FTL.service unbound.service 2>/dev/null || true
}

state_hash() {
    local state_value

    state_value=$(state_snapshot)
    printf '%s' "$state_value" | sha256sum | awk '{ print $1 }'
}

record_assertion() {
    local assertion_label=$1
    local assertion_status=$2
    local observed_value=${3:-unavailable}

    ((assertion_count += 1))
    printf 'action_17j_assertion_%s=%s\n' \
        "$assertion_label" "$assertion_status"
    if [[ "$assertion_status" != true ]]; then
        ((failed_assertion_count += 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
        printf 'action_17j_observed_%s=%s\n' \
            "$assertion_label" "$observed_value"
    fi
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        record_assertion "$equality_label" true
    else
        record_assertion "$equality_label" false "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        record_assertion "$regular_label" true
    else
        record_assertion "$regular_label" false \
            "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_directory() {
    local directory_label=$1
    local directory_path=$2

    if [[ -d "$directory_path" && ! -L "$directory_path" ]]; then
        record_assertion "$directory_label" true
    else
        record_assertion "$directory_label" false \
            "$(stat -c %F "$directory_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        record_assertion "$absent_label" true
    else
        record_assertion "$absent_label" false \
            "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

emit_summary() {
    printf 'action_17j_assertion_count=%s\n' "$assertion_count"
    printf 'action_17j_failed_assertion_count=%s\n' "$failed_assertion_count"
    printf 'action_17j_first_failure=%s\n' "$first_failure"
}

rollback() {
    local original_status=$?
    local rollback_failed=false
    local rollback_service
    local rollback_status
    local rollback_state_hash

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    set +e
    printf 'action_17j_rollback_started=true\n' >&2
    rollback_status=0
    if [[ -n "$transaction_stage" &&
        (-e "$transaction_stage" || -L "$transaction_stage") ]]; then
        if [[ -d "$transaction_stage" && ! -L "$transaction_stage" ]]; then
            rm -rf -- "$transaction_stage" || rollback_status=$?
        else
            rollback_status=1
        fi
    fi
    printf 'action_17j_rollback_transaction_stage_remove_status=%s\n' \
        "$rollback_status" >&2
    [[ "$rollback_status" -eq 0 ]] || rollback_failed=true

    rollback_status=0
    if [[ "$final_stage_created_by_action" == true &&
        (-e "$final_stage" || -L "$final_stage") ]]; then
        if [[ -d "$final_stage" && ! -L "$final_stage" ]]; then
            rm -rf -- "$final_stage" || rollback_status=$?
        else
            rollback_status=1
        fi
    fi
    printf 'action_17j_rollback_final_stage_remove_status=%s\n' \
        "$rollback_status" >&2
    [[ "$rollback_status" -eq 0 ]] || rollback_failed=true

    if [[ ! -e "$final_stage" && ! -L "$final_stage" ]]; then
        printf 'action_17j_rollback_final_stage_absent=true\n' >&2
    else
        printf 'action_17j_rollback_final_stage_absent=false\n' >&2
        rollback_failed=true
    fi
    if [[ -d "$primary_stage" && ! -L "$primary_stage" &&
        "$(stat -c '%U:%G:%a' "$primary_stage" 2>/dev/null)" == root:root:700 &&
        "$(file_hash "$primary_stage/pihole.conf" 2>/dev/null)" == "$staged_primary_sha256" ]]; then
        printf 'action_17j_rollback_primary_stage_preserved=true\n' >&2
    else
        printf 'action_17j_rollback_primary_stage_preserved=false\n' >&2
        rollback_failed=true
    fi

    rollback_state_hash=$(state_hash)
    printf 'action_17j_rollback_state_sha256=%s\n' \
        "$rollback_state_hash" >&2
    [[ "$rollback_state_hash" == "$accepted_state_sha256" ]] ||
        rollback_failed=true
    unbound-checkconf "$live_root" >/dev/null 2>&1
    rollback_status=$?
    printf 'action_17j_rollback_live_parser_status=%s\n' \
        "$rollback_status" >&2
    [[ "$rollback_status" -eq 0 ]] || rollback_failed=true
    for rollback_service in unbound.service pihole-FTL.service; do
        rollback_status=0
        systemctl is-active --quiet "$rollback_service" || rollback_status=$?
        printf 'action_17j_rollback_%s_active_status=%s\n' \
            "${rollback_service//[.-]/_}" "$rollback_status" >&2
        [[ "$rollback_status" -eq 0 ]] || rollback_failed=true
    done

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17j_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17j_rollback_complete=true\n' >&2
    exit "$original_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_preflight_assertion_count" -eq 64 ]]
    [[ "$expected_total_assertion_count" -eq 90 ]]
    [[ "$primary_stage" == /var/tmp/caddy-unbound-node-a-action17i-primary ]]
    [[ "$final_stage" == /var/tmp/caddy-unbound-node-a-action17j-local-zone ]]
    printf 'action_17j_node_a_unbound_local_zone_stage_driver_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --source-stage || $# -ne 2 ]]; then
    printf 'Usage: %s --source-stage /run/caddy-action17j.*\n' \
        "${0##*/}" >&2
    exit 2
fi

source_stage=$2
readonly source_stage
candidate_local_zone="$source_stage/pihole-local-zone.conf"
readonly candidate_local_zone
candidate_shadow="$source_stage/candidate-unbound.conf"
readonly candidate_shadow

printf 'action_17j_remote_reached=true\n'
for required_command in \
    awk chmod chown find grep hostname id install mktemp mv readlink rm \
    sha256sum sort stat systemctl touch unbound-checkconf wc; do
    command_label=${required_command//-/_}
    if command -v "$required_command" >/dev/null; then
        record_assertion "command_${command_label}_available" true
    else
        record_assertion "command_${command_label}_available" false missing
    fi
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
if [[ "$source_stage" =~ ^/run/caddy-action17j\.[A-Za-z0-9]+$ &&
    -d "$source_stage" && ! -L "$source_stage" ]]; then
    record_assertion source_stage_directory true
else
    record_assertion source_stage_directory false "$source_stage"
fi
assert_equal source_stage_metadata \
    "$(stat -c '%U:%G:%a' "$source_stage" 2>/dev/null)" root:root:700
assert_regular_file candidate_local_zone_regular "$candidate_local_zone"
assert_equal candidate_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_local_zone" 2>/dev/null)" root:root:600
assert_equal candidate_local_zone_hash \
    "$(file_hash "$candidate_local_zone" 2>/dev/null)" \
    "$candidate_local_zone_sha256"

assert_regular_file live_root_regular "$live_root"
assert_equal root_active_directive_count \
    "$(active_directives "$live_root" | wc -l)" 1
assert_equal root_include_count \
    "$(active_directives "$live_root" |
        grep -Fxc "$expected_root_include" || true)" 1
assert_equal nonregular_conf_count \
    "$(find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        -name '*.conf' ! -type f -printf '.' | wc -c)" 0
assert_regular_file live_primary_regular "$live_primary"
assert_equal live_primary_hash \
    "$(file_hash "$live_primary" 2>/dev/null)" \
    "$accepted_live_primary_sha256"
assert_equal live_primary_metadata \
    "$(stat -c '%U:%G:%a:%s' "$live_primary" 2>/dev/null)" \
    root:root:644:33211
assert_absent live_local_zone_absent "$live_local_zone"
assert_absent legacy_local_zone_absent "$legacy_local_zone"
assert_equal unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

live_parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 || live_parser_status=$?
assert_equal live_parser_status "$live_parser_status" 0
before_state=$(state_snapshot)
before_state_sha256=$(
    printf '%s' "$before_state" | sha256sum | awk '{ print $1 }'
)
readonly before_state before_state_sha256
assert_equal before_state_hash \
    "$before_state_sha256" "$accepted_state_sha256"

assert_directory primary_stage_directory "$primary_stage"
assert_equal primary_stage_metadata \
    "$(stat -c '%U:%G:%a' "$primary_stage" 2>/dev/null)" root:root:700
assert_equal primary_stage_file_count \
    "$(find "$primary_stage" -mindepth 1 -maxdepth 1 -type f 2>/dev/null |
        wc -l)" 4
assert_equal primary_stage_candidate_hash \
    "$(file_hash "$primary_stage/pihole.conf" 2>/dev/null)" \
    "$staged_primary_sha256"
primary_manifest_status=0
(
    cd "$primary_stage" || exit 1
    sha256sum --check --status manifest.sha256
) || primary_manifest_status=$?
assert_equal primary_stage_manifest_status "$primary_manifest_status" 0
assert_regular_file primary_stage_completion_regular \
    "$primary_stage/.complete"
assert_equal primary_stage_completion_metadata \
    "$(stat -c '%U:%G:%a' "$primary_stage/.complete" 2>/dev/null)" \
    root:root:600
assert_equal primary_stage_manifest_metadata \
    "$(stat -c '%U:%G:%a' "$primary_stage/manifest.sha256" 2>/dev/null)" \
    root:root:600
assert_equal primary_stage_metadata_file_metadata \
    "$(stat -c '%U:%G:%a' "$primary_stage/stage.meta" 2>/dev/null)" \
    root:root:600
assert_equal primary_stage_metadata_file_hash \
    "$(file_hash "$primary_stage/stage.meta" 2>/dev/null)" \
    "$primary_metadata_sha256"
assert_equal primary_stage_manifest_file_hash \
    "$(file_hash "$primary_stage/manifest.sha256" 2>/dev/null)" \
    "$primary_manifest_sha256"
assert_absent local_zone_stage_absent "$final_stage"
assert_equal transaction_residue_count \
    "$(find /var/tmp -mindepth 1 -maxdepth 1 \
        -name '.caddy-unbound-node-a-action17j-local-zone.*' -print |
        wc -l)" 0

assert_equal candidate_server_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Fxc server: || true)" 1
assert_equal candidate_private_domain_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Fxc 'private-domain: "local.theama.co"' || true)" 1
assert_equal candidate_domain_insecure_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Fxc 'domain-insecure: "local.theama.co"' || true)" 1
assert_equal candidate_static_zone_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Fxc 'local-zone: "local.theama.co." static' || true)" 1
assert_equal candidate_local_data_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Ec '^local-data:' || true)" 23
assert_equal candidate_local_data_ptr_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Ec '^local-data-ptr:' || true)" 20
assert_equal candidate_absolute_ptr_target_count \
    "$(active_directives "$candidate_local_zone" |
        grep -Ec '^local-data-ptr: "[^ ]+ [^"]+\."$' || true)" 20

candidate_shadow_write_status=0
printf 'include-toplevel: "%s"\ninclude-toplevel: "%s"\n' \
    "$primary_stage/pihole.conf" "$candidate_local_zone" \
    >"$candidate_shadow" || candidate_shadow_write_status=$?
assert_equal candidate_shadow_write_status \
    "$candidate_shadow_write_status" 0
candidate_shadow_chmod_status=0
chmod 0600 "$candidate_shadow" || candidate_shadow_chmod_status=$?
assert_equal candidate_shadow_chmod_status \
    "$candidate_shadow_chmod_status" 0
candidate_parser_status=0
unbound-checkconf "$candidate_shadow" >/dev/null 2>&1 ||
    candidate_parser_status=$?
assert_equal candidate_parser_status "$candidate_parser_status" 0
candidate_shadow_remove_status=0
rm -f -- "$candidate_shadow" || candidate_shadow_remove_status=$?
assert_equal candidate_shadow_remove_status \
    "$candidate_shadow_remove_status" 0

if [[ "$assertion_count" -ne "$expected_preflight_assertion_count" ]]; then
    record_assertion internal_preflight_assertion_count false "$assertion_count"
fi
if [[ "$failed_assertion_count" -ne 0 ]]; then
    emit_summary
    printf 'action_17j_conclusion=preflight_failed_before_mutation\n'
    printf 'action_17j_remote_complete=true\n'
    exit 1
fi

printf 'action_17j_preflight_complete=true\n'
printf 'before_live_state_sha256=%s\n' "$before_state_sha256"
printf 'primary_stage_previously_accepted=true\n'
printf 'local_zone_stage_previously_absent=true\n'

trap rollback EXIT
transaction_stage_create_status=0
transaction_stage=$(
    mktemp -d /var/tmp/.caddy-unbound-node-a-action17j-local-zone.XXXXXX
) || transaction_stage_create_status=$?
assert_equal transaction_stage_create_status \
    "$transaction_stage_create_status" 0
if [[ "$transaction_stage" =~ ^/var/tmp/\.caddy-unbound-node-a-action17j-local-zone\.[A-Za-z0-9]+$ &&
    -d "$transaction_stage" && ! -L "$transaction_stage" ]]; then
    record_assertion transaction_stage_path true
else
    record_assertion transaction_stage_path false "$transaction_stage"
fi
assert_equal transaction_stage_metadata \
    "$(stat -c '%U:%G:%a' "$transaction_stage" 2>/dev/null)" root:root:700

if [[ "$failed_assertion_count" -ne 0 ]]; then
    emit_summary
    printf 'action_17j_conclusion=transaction_stage_creation_failed\n'
    printf 'action_17j_remote_complete=true\n'
    exit 1
fi

printf 'action_17j_mutation_started=true\n'

candidate_install_status=0
install -o root -g root -m 0600 "$candidate_local_zone" \
    "$transaction_stage/pihole-local-zone.conf" ||
    candidate_install_status=$?
assert_equal candidate_install_status "$candidate_install_status" 0
assert_equal staged_candidate_hash \
    "$(file_hash "$transaction_stage/pihole-local-zone.conf" 2>/dev/null)" \
    "$candidate_local_zone_sha256"

manifest_write_status=0
printf '%s  pihole-local-zone.conf\n' "$candidate_local_zone_sha256" \
    >"$transaction_stage/manifest.sha256" || manifest_write_status=$?
assert_equal manifest_write_status "$manifest_write_status" 0
metadata_write_status=0
printf '%s\n' \
    action=17j \
    node_role=node-a \
    artifact=pihole-local-zone.conf \
    source_sha256="$candidate_local_zone_sha256" \
    parent_action=17i \
    parent_sha256="$staged_primary_sha256" \
    live_activation=false \
    >"$transaction_stage/stage.meta" || metadata_write_status=$?
assert_equal metadata_write_status "$metadata_write_status" 0
completion_touch_status=0
touch "$transaction_stage/.complete" || completion_touch_status=$?
assert_equal completion_touch_status "$completion_touch_status" 0
stage_file_chmod_status=0
chown root:root \
    "$transaction_stage/manifest.sha256" \
    "$transaction_stage/stage.meta" \
    "$transaction_stage/.complete" &&
    chmod 0600 \
        "$transaction_stage/manifest.sha256" \
        "$transaction_stage/stage.meta" \
        "$transaction_stage/.complete" ||
    stage_file_chmod_status=$?
assert_equal stage_file_chmod_status "$stage_file_chmod_status" 0
stage_directory_chmod_status=0
chmod 0700 "$transaction_stage" || stage_directory_chmod_status=$?
assert_equal stage_directory_chmod_status "$stage_directory_chmod_status" 0
stage_move_status=0
if mv --no-clobber -T -- "$transaction_stage" "$final_stage"; then
    final_stage_created_by_action=true
else
    stage_move_status=$?
fi
assert_equal stage_move_status "$stage_move_status" 0

assert_directory final_stage_directory "$final_stage"
assert_equal final_stage_metadata \
    "$(stat -c '%U:%G:%a' "$final_stage" 2>/dev/null)" root:root:700
assert_equal final_stage_file_count \
    "$(find "$final_stage" -mindepth 1 -maxdepth 1 -type f |
        wc -l)" 4
assert_equal final_candidate_hash \
    "$(file_hash "$final_stage/pihole-local-zone.conf" 2>/dev/null)" \
    "$candidate_local_zone_sha256"
manifest_verify_status=0
(
    cd "$final_stage" || exit 1
    sha256sum --check --status manifest.sha256
) || manifest_verify_status=$?
assert_equal manifest_verify_status "$manifest_verify_status" 0
assert_regular_file completion_marker_regular "$final_stage/.complete"
assert_equal completion_marker_metadata \
    "$(stat -c '%U:%G:%a' "$final_stage/.complete" 2>/dev/null)" \
    root:root:600

assert_directory primary_stage_still_directory "$primary_stage"
assert_equal primary_stage_still_metadata \
    "$(stat -c '%U:%G:%a' "$primary_stage" 2>/dev/null)" root:root:700
assert_equal primary_candidate_still_hash \
    "$(file_hash "$primary_stage/pihole.conf" 2>/dev/null)" \
    "$staged_primary_sha256"
post_primary_manifest_status=0
(
    cd "$primary_stage" || exit 1
    sha256sum --check --status manifest.sha256
) || post_primary_manifest_status=$?
assert_equal primary_manifest_still_valid "$post_primary_manifest_status" 0

after_state=$(state_snapshot)
after_state_sha256=$(
    printf '%s' "$after_state" | sha256sum | awk '{ print $1 }'
)
readonly after_state after_state_sha256
assert_equal after_state_hash "$after_state_sha256" "$accepted_state_sha256"
post_live_parser_status=0
unbound-checkconf "$live_root" >/dev/null 2>&1 ||
    post_live_parser_status=$?
assert_equal post_live_parser_status "$post_live_parser_status" 0
assert_equal post_unbound_active \
    "$(systemctl is-active unbound.service 2>/dev/null)" active
assert_equal post_pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service 2>/dev/null)" active

if [[ "$assertion_count" -ne "$expected_total_assertion_count" ]]; then
    record_assertion internal_total_assertion_count false "$assertion_count"
fi
if [[ "$failed_assertion_count" -ne 0 ]]; then
    emit_summary
    printf 'action_17j_conclusion=transaction_failed_rollback_required\n'
    printf 'action_17j_remote_complete=true\n'
    exit 1
fi

transaction_complete=true
trap - EXIT
emit_summary
printf 'local_zone_candidate_sha256=%s\n' "$candidate_local_zone_sha256"
printf 'local_zone_stage_path=%s\n' "$final_stage"
printf 'local_zone_stage_owner_mode=root:root:700\n'
printf 'local_zone_file_owner_mode=root:root:600\n'
printf 'combined_candidate_parser_valid=true\n'
printf 'local_zone_ownership_boundary_valid=true\n'
printf 'local_zone_stage_complete=true\n'
printf 'primary_stage_preserved=true\n'
printf 'live_unbound_configuration_mutated=false\n'
printf 'dns_queries_performed=false\n'
printf 'service_mutations=false\n'
printf 'after_live_state_sha256=%s\n' "$after_state_sha256"
printf 'live_state_unchanged=true\n'
printf 'persistent_mutation_scope=local_zone_stage_only\n'
printf 'action_17j_conclusion=local_zone_stage_retained\n'
printf 'action_17j_remote_complete=true\n'
printf 'action_17j_node_a_unbound_local_zone_stage_complete=true\n'
