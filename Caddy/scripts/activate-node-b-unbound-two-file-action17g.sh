#!/usr/bin/env bash

set -Eeu -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole00
readonly live_root=/etc/unbound/unbound.conf
readonly live_conf_dir=/etc/unbound/unbound.conf.d
readonly live_primary="$live_conf_dir/pihole.conf"
readonly live_local_zone="$live_conf_dir/pihole-local-zone.conf"
readonly legacy_local_zone="$live_conf_dir/pihole0-local-zone.conf"
readonly primary_stage=/var/tmp/caddy-unbound-node-b-action17e-primary
readonly local_zone_stage=/var/tmp/caddy-unbound-node-b-action17f-local-zone
readonly primary_stage_file="$primary_stage/pihole.conf"
readonly local_zone_stage_file="$local_zone_stage/pihole0-local-zone.conf"
readonly backup_dir=/var/backups/caddy-ha/action17g-node-b-unbound-two-file
readonly transaction_primary="$live_conf_dir/.pihole.conf.action17g.new"
readonly transaction_local_zone="$live_conf_dir/.pihole-local-zone.conf.action17g.new"
readonly rollback_primary="$live_conf_dir/.pihole.conf.action17g.before"
readonly accepted_root_sha256=8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8
readonly accepted_legacy_primary_sha256=017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7
readonly candidate_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly candidate_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly expected_primary_meta_sha256=14731d6ae7e968f4752117e53c972bb86ab22bb4da50f1615a5f780049219b56
readonly expected_local_zone_meta_sha256=7f365675e5f9996f2c53647dc4fe98f5e27c7d10ecfda765a7b0290444e26b7c

mutation_started=false
live_switch_started=false
reload_attempted=false
transaction_complete=false
pre_unbound_pid=
pre_unbound_restarts=
pre_ftl_pid=
pre_ftl_restarts=
protected_tree_before=

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

pass_step() {
    local passed_label=$1

    printf 'action_17g_check_%s=true\n' "$passed_label"
}

fail_step() {
    local failed_label=$1
    local observed_value=${2:-unavailable}

    printf 'action_17g_check_%s=false\n' "$failed_label" >&2
    printf 'action_17g_failed_step=%s\n' "$failed_label" >&2
    printf 'action_17g_failed_observed=%s\n' "$observed_value" >&2
    return 1
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        pass_step "$equality_label"
    else
        fail_step "$equality_label" "$observed_value"
    fi
}

assert_regular_file() {
    local regular_label=$1
    local regular_path=$2

    if [[ -f "$regular_path" && ! -L "$regular_path" ]]; then
        pass_step "$regular_label"
    else
        fail_step "$regular_label" "$(stat -c %F "$regular_path" 2>/dev/null || printf absent)"
    fi
}

assert_absent() {
    local absent_label=$1
    local absent_path=$2

    if [[ ! -e "$absent_path" && ! -L "$absent_path" ]]; then
        pass_step "$absent_label"
    else
        fail_step "$absent_label" "$(stat -c %F "$absent_path" 2>/dev/null || printf present)"
    fi
}

run_step() {
    local operation_label=$1

    shift
    if "$@"; then
        pass_step "$operation_label"
    else
        fail_step "$operation_label"
    fi
}

protected_tree_hash() {
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 \
        ! -name pihole.conf \
        ! -name pihole-local-zone.conf \
        ! -name pihole0-local-zone.conf \
        ! -name '.pihole.conf.action17g.new' \
        ! -name '.pihole-local-zone.conf.action17g.new' \
        ! -name '.pihole.conf.action17g.before' \
        -printf '%f|%y|%U:%G:%m:%s:%i\n' |
        LC_ALL=C sort
    find "$live_conf_dir" -mindepth 1 -maxdepth 1 -type f \
        ! -name pihole.conf \
        ! -name pihole-local-zone.conf \
        ! -name pihole0-local-zone.conf \
        ! -name '.pihole.conf.action17g.new' \
        ! -name '.pihole-local-zone.conf.action17g.new' \
        ! -name '.pihole.conf.action17g.before' \
        -print0 |
        LC_ALL=C sort -z |
        xargs -0 -r sha256sum
}

stage_meta_hash() {
    file_hash "$1/stage.meta"
}

validate_stage() {
    local stage_label=$1
    local stage_path=$2
    local stage_candidate_name=$3
    local stage_candidate_hash=$4
    local stage_meta_expected_hash=$5
    local stage_member stage_member_label
    local -a stage_entries=()

    if [[ -d "$stage_path" && ! -L "$stage_path" ]]; then
        pass_step "${stage_label}_directory"
    else
        fail_step "${stage_label}_directory"
    fi
    assert_equal "${stage_label}_directory_metadata" \
        "$(stat -c '%U:%G:%a' "$stage_path")" root:root:700
    mapfile -t stage_entries < <(
        find "$stage_path" -mindepth 1 -maxdepth 1 -printf '%f\n' |
            LC_ALL=C sort
    )
    assert_equal "${stage_label}_entry_count" "${#stage_entries[@]}" 4
    assert_equal "${stage_label}_entry_0" "${stage_entries[0]:-}" .complete
    assert_equal "${stage_label}_entry_1" "${stage_entries[1]:-}" manifest.sha256
    assert_equal "${stage_label}_entry_2" "${stage_entries[2]:-}" \
        "$stage_candidate_name"
    assert_equal "${stage_label}_entry_3" "${stage_entries[3]:-}" stage.meta

    for stage_member in \
        "$stage_path/.complete" \
        "$stage_path/manifest.sha256" \
        "$stage_path/$stage_candidate_name" \
        "$stage_path/stage.meta"; do
        stage_member_label=${stage_member##*/}
        stage_member_label=${stage_member_label#.}
        stage_member_label=${stage_member_label//./_}
        stage_member_label=${stage_member_label//-/_}
        assert_regular_file "${stage_label}_member_${stage_member_label}" \
            "$stage_member"
        assert_equal "${stage_label}_mode_${stage_member_label}" \
            "$(stat -c '%U:%G:%a' "$stage_member")" root:root:600
    done
    assert_equal "${stage_label}_completion_size" \
        "$(stat -c %s "$stage_path/.complete")" 0
    assert_equal "${stage_label}_candidate_hash" \
        "$(file_hash "$stage_path/$stage_candidate_name")" \
        "$stage_candidate_hash"
    assert_equal "${stage_label}_manifest_content" \
        "$(cat "$stage_path/manifest.sha256")" \
        "$stage_candidate_hash  $stage_candidate_name"
    if (
        cd "$stage_path"
        sha256sum --check --status manifest.sha256
    ); then
        pass_step "${stage_label}_manifest_check"
    else
        fail_step "${stage_label}_manifest_check"
    fi
    assert_equal "${stage_label}_meta_hash" \
        "$(stage_meta_hash "$stage_path")" "$stage_meta_expected_hash"
}

validate_direct_unbound() {
    local query_label=$1
    local query_server=$2
    local query_name=$3
    local query_type=$4
    local query_expected=$5
    local query_result

    query_result=$(
        dig +time=2 +tries=1 +short \
            "@$query_server" -p 5335 "$query_name" "$query_type" |
            sed 's/[.]$//' |
            LC_ALL=C sort
    )
    assert_equal "$query_label" "$query_result" "$query_expected"
}

validate_pihole_path() {
    local pihole_query_result

    pihole_query_result=$(
        dig +time=2 +tries=1 +short \
            @127.0.0.1 -p 53 pihole00.local.theama.co A |
            LC_ALL=C sort
    )
    assert_equal pihole_path_query "$pihole_query_result" 10.1.0.54
}

wait_for_readiness() {
    local readiness_iteration
    local readiness_addresses readiness_answer

    for ((readiness_iteration = 1; readiness_iteration <= 20; readiness_iteration += 1)); do
        readiness_addresses=$(
            ss -H -ltn 'sport = :5335' 2>/dev/null |
                awk '{ print $4 }' |
                LC_ALL=C sort
        ) || readiness_addresses=
        readiness_answer=$(
            dig +time=1 +tries=1 +short \
                @127.0.0.1 -p 5335 pihole00.local.theama.co A 2>/dev/null |
                LC_ALL=C sort
        ) || readiness_answer=
        if [[ "$(systemctl is-active unbound.service 2>/dev/null)" == active ]] &&
            [[ "$readiness_addresses" == *127.0.0.1:5335* ]] &&
            [[ "$readiness_addresses" == *"[::1]:5335"* ]] &&
            [[ "$readiness_answer" == 10.1.0.54 ]]; then
            printf 'action_17g_readiness_iterations=%s\n' \
                "$readiness_iteration"
            pass_step bounded_readiness
            return 0
        fi
        sleep 1
    done
    fail_step bounded_readiness timeout
}

reload_legacy_after_rollback() {
    local rollback_iteration
    local rollback_answer

    systemctl reload unbound.service >/dev/null 2>&1 || return 1
    for ((rollback_iteration = 1; rollback_iteration <= 20; rollback_iteration += 1)); do
        rollback_answer=$(
            dig +time=1 +tries=1 +short \
                @127.0.0.1 -p 5335 pihole00.local.theama.co A 2>/dev/null |
                LC_ALL=C sort
        ) || rollback_answer=
        if [[ "$(systemctl is-active unbound.service 2>/dev/null)" == active ]] &&
            [[ "$rollback_answer" == 10.1.0.54 ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    if [[ "$mutation_started" == false ]]; then
        printf 'action_17g_prewrite_failure_before_mutation=true\n' >&2
        exit "$original_status"
    fi

    set +e
    printf 'action_17g_rollback_started=true\n' >&2

    if [[ "$live_switch_started" == true ]]; then
        if [[ -e "$live_local_zone" || -L "$live_local_zone" ]]; then
            if [[ -f "$live_local_zone" && ! -L "$live_local_zone" ]]; then
                rm -f -- "$live_local_zone" || rollback_failed=true
            else
                rollback_failed=true
            fi
        fi
        if [[ -e "$live_primary" || -L "$live_primary" ]]; then
            if [[ -f "$live_primary" && ! -L "$live_primary" ]]; then
                rm -f -- "$live_primary" || rollback_failed=true
            else
                rollback_failed=true
            fi
        fi
        if [[ -f "$rollback_primary" && ! -L "$rollback_primary" ]]; then
            mv -- "$rollback_primary" "$live_primary" || rollback_failed=true
        elif [[ -f "$backup_dir/pihole.conf.before" &&
            ! -L "$backup_dir/pihole.conf.before" ]]; then
            install -o root -g root -m 0644 \
                "$backup_dir/pihole.conf.before" "$live_primary" ||
                rollback_failed=true
        else
            rollback_failed=true
        fi
    fi
    rm -f -- "$transaction_primary" "$transaction_local_zone" ||
        rollback_failed=true

    if [[ "$(file_hash "$live_primary" 2>/dev/null)" != "$accepted_legacy_primary_sha256" ]]; then
        rollback_failed=true
    fi
    if [[ -e "$live_local_zone" || -L "$live_local_zone" ||
        -e "$legacy_local_zone" || -L "$legacy_local_zone" ]]; then
        rollback_failed=true
    fi
    unbound-checkconf "$live_root" >/dev/null 2>&1 ||
        rollback_failed=true
    if [[ "$live_switch_started" == true || "$reload_attempted" == true ]]; then
        reload_legacy_after_rollback || rollback_failed=true
    fi
    if [[ "$(systemctl show unbound.service -p MainPID --value 2>/dev/null)" != "$pre_unbound_pid" ]]; then
        rollback_failed=true
    fi
    if [[ "$(systemctl show unbound.service -p NRestarts --value 2>/dev/null)" != "$pre_unbound_restarts" ]]; then
        rollback_failed=true
    fi
    if [[ "$(systemctl show pihole-FTL.service -p MainPID --value 2>/dev/null)" != "$pre_ftl_pid" ]]; then
        rollback_failed=true
    fi
    if [[ "$(systemctl show pihole-FTL.service -p NRestarts --value 2>/dev/null)" != "$pre_ftl_restarts" ]]; then
        rollback_failed=true
    fi
    if [[ "$(protected_tree_hash | sha256sum | awk '{ print $1 }')" != "$protected_tree_before" ]]; then
        rollback_failed=true
    fi

    if [[ -d "$backup_dir" && ! -L "$backup_dir" ]]; then
        rm -rf -- "$backup_dir" || rollback_failed=true
    else
        rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17g_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17g_rollback_complete=true\n' >&2
    exit "$original_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$live_primary" == /etc/unbound/unbound.conf.d/pihole.conf ]]
    [[ "$live_local_zone" == /etc/unbound/unbound.conf.d/pihole-local-zone.conf ]]
    [[ "$local_zone_stage_file" == */pihole0-local-zone.conf ]]
    [[ "$live_local_zone" != "$local_zone_stage_file" ]]
    printf 'action_17g_node_b_unbound_activation_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

trap rollback EXIT

for required_command in \
    awk cat dig find grep hostname id install mapfile mv rm sed sha256sum \
    sleep sort ss stat systemctl unbound-checkconf wc xargs; do
    command_label=${required_command//-/_}
    if command -v "$required_command" >/dev/null; then
        pass_step "command_${command_label}_available"
    else
        fail_step "command_${command_label}_available"
    fi
done

assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
assert_regular_file live_root_regular "$live_root"
assert_equal live_root_hash "$(file_hash "$live_root")" "$accepted_root_sha256"
assert_regular_file live_primary_regular "$live_primary"
assert_equal legacy_primary_hash \
    "$(file_hash "$live_primary")" "$accepted_legacy_primary_sha256"
assert_equal legacy_primary_metadata \
    "$(stat -c '%U:%G:%a:%s' "$live_primary")" root:root:644:34342
assert_absent corrected_local_zone_absent "$live_local_zone"
assert_absent legacy_local_zone_absent "$legacy_local_zone"
assert_absent backup_absent "$backup_dir"
assert_absent transaction_primary_absent "$transaction_primary"
assert_absent transaction_local_zone_absent "$transaction_local_zone"
assert_absent rollback_primary_absent "$rollback_primary"

validate_stage primary "$primary_stage" pihole.conf \
    "$candidate_primary_sha256" "$expected_primary_meta_sha256"
validate_stage local_zone "$local_zone_stage" pihole0-local-zone.conf \
    "$candidate_local_zone_sha256" "$expected_local_zone_meta_sha256"

if unbound-checkconf "$live_root" >/dev/null; then
    pass_step live_parser
else
    fail_step live_parser
fi
if printf 'include-toplevel: "%s"\ninclude-toplevel: "%s"\n' \
    "$primary_stage_file" "$local_zone_stage_file" |
    unbound-checkconf /dev/stdin >/dev/null; then
    pass_step staged_pair_parser
else
    fail_step staged_pair_parser
fi

assert_equal unbound_active \
    "$(systemctl is-active unbound.service)" active
assert_equal pihole_ftl_active \
    "$(systemctl is-active pihole-FTL.service)" active
pre_unbound_pid=$(systemctl show unbound.service -p MainPID --value)
pre_unbound_restarts=$(systemctl show unbound.service -p NRestarts --value)
pre_ftl_pid=$(systemctl show pihole-FTL.service -p MainPID --value)
pre_ftl_restarts=$(systemctl show pihole-FTL.service -p NRestarts --value)
protected_tree_before=$(
    protected_tree_hash |
        sha256sum |
        awk '{ print $1 }'
)
readonly pre_unbound_pid pre_unbound_restarts pre_ftl_pid pre_ftl_restarts
readonly protected_tree_before
assert_equal unbound_pid_numeric \
    "$([[ "$pre_unbound_pid" =~ ^[1-9][0-9]*$ ]] && printf true || printf false)" \
    true
assert_equal ftl_pid_numeric \
    "$([[ "$pre_ftl_pid" =~ ^[1-9][0-9]*$ ]] && printf true || printf false)" \
    true

printf 'action_17g_preflight_complete=true\n'
printf 'action_17g_live_primary_name=pihole.conf\n'
printf 'action_17g_live_local_zone_name=pihole-local-zone.conf\n'

run_step backup_directory_created \
    install -d -o root -g root -m 0700 "$backup_dir"
mutation_started=true
printf 'action_17g_mutation_started=true\n'
run_step backup_primary_installed \
    install -o root -g root -m 0600 \
    "$live_primary" "$backup_dir/pihole.conf.before"
if printf '%s  pihole.conf.before\n' "$accepted_legacy_primary_sha256" \
    >"$backup_dir/manifest.sha256"; then
    pass_step backup_manifest_written
else
    fail_step backup_manifest_written
fi
if printf '%s\n' \
    action=17g \
    node_role=node-b \
    live_primary_name=pihole.conf \
    live_local_zone_name=pihole-local-zone.conf \
    legacy_primary_sha256="$accepted_legacy_primary_sha256" \
    candidate_primary_sha256="$candidate_primary_sha256" \
    candidate_local_zone_sha256="$candidate_local_zone_sha256" \
    >"$backup_dir/action.meta"; then
    pass_step backup_metadata_written
else
    fail_step backup_metadata_written
fi
run_step backup_files_owned \
    chown root:root "$backup_dir/manifest.sha256" "$backup_dir/action.meta"
run_step backup_files_protected \
    chmod 0600 "$backup_dir/manifest.sha256" "$backup_dir/action.meta"
if (
    cd "$backup_dir"
    sha256sum --check --status manifest.sha256
); then
    pass_step protected_backup
else
    fail_step protected_backup
fi

run_step transaction_primary_installed \
    install -o root -g root -m 0644 \
    "$primary_stage_file" "$transaction_primary"
run_step transaction_local_zone_installed \
    install -o root -g root -m 0644 \
    "$local_zone_stage_file" "$transaction_local_zone"
assert_equal transaction_primary_hash \
    "$(file_hash "$transaction_primary")" "$candidate_primary_sha256"
assert_equal transaction_local_zone_hash \
    "$(file_hash "$transaction_local_zone")" "$candidate_local_zone_sha256"

run_step legacy_primary_moved_to_rollback \
    mv -- "$live_primary" "$rollback_primary"
live_switch_started=true
printf 'action_17g_live_switch_started=true\n'
run_step primary_activated mv -- "$transaction_primary" "$live_primary"
run_step local_zone_activated \
    mv -- "$transaction_local_zone" "$live_local_zone"
assert_equal active_primary_name "${live_primary##*/}" pihole.conf
assert_equal active_local_zone_name "${live_local_zone##*/}" pihole-local-zone.conf
assert_equal active_primary_hash \
    "$(file_hash "$live_primary")" "$candidate_primary_sha256"
assert_equal active_local_zone_hash \
    "$(file_hash "$live_local_zone")" "$candidate_local_zone_sha256"
assert_equal active_primary_metadata \
    "$(stat -c '%U:%G:%a' "$live_primary")" root:root:644
assert_equal active_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone")" root:root:644
assert_absent legacy_local_zone_after_switch "$legacy_local_zone"
if unbound-checkconf "$live_root" >/dev/null; then
    pass_step activated_parser
else
    fail_step activated_parser
fi

reload_attempted=true
printf 'action_17g_reload_attempted=true\n'
run_step unbound_reload systemctl reload unbound.service
printf 'action_17g_reload_status=0\n'
wait_for_readiness

assert_equal unbound_pid_preserved \
    "$(systemctl show unbound.service -p MainPID --value)" \
    "$pre_unbound_pid"
assert_equal unbound_restarts_preserved \
    "$(systemctl show unbound.service -p NRestarts --value)" \
    "$pre_unbound_restarts"
assert_equal ftl_pid_preserved \
    "$(systemctl show pihole-FTL.service -p MainPID --value)" \
    "$pre_ftl_pid"
assert_equal ftl_restarts_preserved \
    "$(systemctl show pihole-FTL.service -p NRestarts --value)" \
    "$pre_ftl_restarts"
assert_equal protected_tree_preserved \
    "$(protected_tree_hash | sha256sum | awk '{ print $1 }')" \
    "$protected_tree_before"

validate_direct_unbound direct_ipv4_node_a \
    127.0.0.1 pihole0.local.theama.co A 10.1.0.53
validate_direct_unbound direct_ipv4_node_b \
    127.0.0.1 pihole00.local.theama.co A 10.1.0.54
validate_direct_unbound direct_ipv6_node_b \
    ::1 pihole00.local.theama.co A 10.1.0.54
validate_direct_unbound direct_ptr_node_b \
    127.0.0.1 54.0.1.10.in-addr.arpa PTR pihole00.local.theama.co
validate_pihole_path

run_step rollback_copy_removed rm -f -- "$rollback_primary"
assert_absent rollback_primary_removed "$rollback_primary"
assert_absent transaction_primary_removed "$transaction_primary"
assert_absent transaction_local_zone_removed "$transaction_local_zone"

transaction_complete=true
trap - EXIT
printf 'action_17g_backup_path=%s\n' "$backup_dir"
printf 'action_17g_primary_sha256=%s\n' "$candidate_primary_sha256"
printf 'action_17g_local_zone_sha256=%s\n' "$candidate_local_zone_sha256"
printf 'action_17g_unbound_pid_preserved=true\n'
printf 'action_17g_ftl_pid_preserved=true\n'
printf 'action_17g_live_names_correct=true\n'
printf 'action_17g_legacy_live_name_absent=true\n'
printf 'action_17g_stages_preserved=true\n'
printf 'action_17g_dns_queries_performed=true\n'
printf 'action_17g_service_mutation=unbound_reload_only\n'
printf 'action_17g_persistent_mutation_scope=two_live_files_and_backup\n'
printf 'action_17g_node_b_unbound_activation_complete=true\n'
