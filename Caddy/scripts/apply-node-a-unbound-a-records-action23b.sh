#!/usr/bin/env bash

set -Eeu -o pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly expected_hostname=j1-svpihole0
readonly live_primary=/etc/unbound/unbound.conf.d/pihole.conf
readonly live_local_zone=/etc/unbound/unbound.conf.d/pihole-local-zone.conf
readonly accepted_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly accepted_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly candidate_local_zone_sha256=b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160
readonly backup_dir=/var/backups/caddy-ha/action23b-node-a-unbound-a-records
readonly transaction_file=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action23b.new
readonly pihole_cli=/usr/local/bin/pihole
readonly pihole_reset_timeout_seconds=30
readonly readiness_timeout_seconds=20
readonly caddy_ipv4=10.1.0.56
readonly node_b_ipv4=10.1.0.54
readonly pihole_ipv4=10.1.0.55
readonly pihole_ipv6=fd36:5aa8:6971:1::55
readonly pihole_fqdn=pihole.local.theama.co
readonly proxy_fqdn=proxy.local.theama.co
readonly admin_fqdn=pihole-admin.local.theama.co
readonly node_b_fqdn=pihole00.local.theama.co
readonly -a required_commands=(
    awk chmod cmp curl dig dirname grep hostname id install mktemp mv rm
    sed sha256sum sleep sort stat systemctl timeout unbound-checkconf
    unbound-control wc
)
readonly -a readiness_keys=(
    direct_proxy_a
    direct_admin_a
    local_proxy_a
    local_admin_a
    direct_pihole_a
    direct_pihole_aaaa
    direct_pihole_ptr4
    local_pihole_a
    local_pihole_aaaa
    local_pihole_ptr4
)

mutation_started=false
transaction_complete=false
backup_started=false
pre_unbound_pid=
pre_unbound_restarts=
pre_ftl_pid=
post_reset_ftl_pid=
post_reset_ftl_restarts=
current_boundary=initialization
probe_status_value=
probe_answer_value=
probe_safe_value=
readiness_failure_count=0
declare -A seen_checks=()

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

pass_check() {
    local action23b_pass_label=$1

    if [[ -n "${seen_checks[$action23b_pass_label]+set}" ]]; then
        printf 'action_23b_duplicate_check=%s\n' "$action23b_pass_label" >&2
        return 1
    fi
    seen_checks[$action23b_pass_label]=true
    printf 'action_23b_check_%s=true\n' "$action23b_pass_label"
}

fail_check() {
    local action23b_fail_label=$1
    local action23b_fail_observed=${2:-unavailable}

    printf 'action_23b_check_%s=false\n' "$action23b_fail_label" >&2
    printf 'action_23b_failed_check=%s\n' "$action23b_fail_label" >&2
    printf 'action_23b_failed_observed=%s\n' "$action23b_fail_observed" >&2
    return 1
}

assert_equal() {
    local action23b_equal_label=$1
    local action23b_equal_observed=$2
    local action23b_equal_expected=$3

    if [[ "$action23b_equal_observed" == "$action23b_equal_expected" ]]; then
        pass_check "$action23b_equal_label"
    else
        fail_check "$action23b_equal_label" "$action23b_equal_observed"
    fi
}

assert_file_shape() {
    local action23b_shape_label=$1
    local action23b_shape_path=$2
    local action23b_shape_regular
    local action23b_shape_not_symlink

    action23b_shape_regular=$(
        if [[ -f "$action23b_shape_path" ]]; then printf true; else printf false; fi
    )
    action23b_shape_not_symlink=$(
        if [[ ! -L "$action23b_shape_path" ]]; then printf true; else printf false; fi
    )

    # conditional-validator-explicit-failures-begin
    assert_equal "${action23b_shape_label}_regular" \
        "$action23b_shape_regular" true || return 1
    assert_equal "${action23b_shape_label}_not_symlink" \
        "$action23b_shape_not_symlink" true || return 1
    # conditional-validator-explicit-failures-end
}

assert_path_absent() {
    local action23b_absent_label=$1
    local action23b_absent_path=$2
    local action23b_entry_absent
    local action23b_symlink_absent

    action23b_entry_absent=$(
        if [[ ! -e "$action23b_absent_path" ]]; then printf true; else printf false; fi
    )
    action23b_symlink_absent=$(
        if [[ ! -L "$action23b_absent_path" ]]; then printf true; else printf false; fi
    )

    # conditional-validator-explicit-failures-begin
    assert_equal "${action23b_absent_label}_entry_absent" \
        "$action23b_entry_absent" true || return 1
    assert_equal "${action23b_absent_label}_symlink_absent" \
        "$action23b_symlink_absent" true || return 1
    # conditional-validator-explicit-failures-end
}

run_check() {
    local action23b_run_label=$1

    shift
    if "$@"; then
        pass_check "$action23b_run_label"
    else
        fail_check "$action23b_run_label"
    fi
}

set_boundary() {
    current_boundary=$1
    printf 'action_23b_boundary=%s\n' "$current_boundary"
}

service_pid() {
    systemctl show --property=MainPID --value "$1"
}

service_restarts() {
    systemctl show --property=NRestarts --value "$1"
}

perform_pihole_reset() {
    timeout --signal=TERM --kill-after=5s \
        "${pihole_reset_timeout_seconds}s" "$pihole_cli" restartdns
}

https_probe() {
    local action23b_https_name=$1
    local action23b_https_address=$2

    curl -kfsS -o /dev/null --connect-timeout 3 --max-time 5 \
        --resolve "${action23b_https_name}:443:${action23b_https_address}" \
        "https://${action23b_https_name}/"
}

validate_candidate_records() {
    local action23b_candidate=$1
    local action23b_live_records
    local action23b_candidate_records
    local action23b_existing_records_unchanged

    # conditional-validator-explicit-failures-begin
    assert_equal candidate_admin_a_exact_once \
        "$(grep -Fxc '    local-data: "pihole-admin.local.theama.co. IN A 10.1.0.56"' \
            "$action23b_candidate" || true)" 1 || return 1
    assert_equal candidate_proxy_a_exact_once \
        "$(grep -Fxc '    local-data: "proxy.local.theama.co. IN A 10.1.0.56"' \
            "$action23b_candidate" || true)" 1 || return 1
    assert_equal live_admin_a_absent \
        "$(grep -Fc 'pihole-admin.local.theama.co. IN A ' "$live_local_zone" || true)" 0 || return 1
    assert_equal live_proxy_a_absent \
        "$(grep -Fc 'proxy.local.theama.co. IN A ' "$live_local_zone" || true)" 0 || return 1
    assert_equal candidate_caddy_aaaa_absent \
        "$(grep -Ec '(pihole-admin|proxy)[.]local[.]theama[.]co[.].* IN AAAA ' \
            "$action23b_candidate" || true)" 0 || return 1
    assert_equal candidate_caddy_ptr_absent \
        "$(grep -Ec 'local-data-ptr: "(10[.]1[.]0[.]56|fd36:5aa8:6971:1::56) ' \
            "$action23b_candidate" || true)" 0 || return 1
    assert_equal candidate_caddy_srv_absent \
        "$(grep -Fc '_https._tcp.proxy.local.theama.co.' \
            "$action23b_candidate" || true)" 0 || return 1
    assert_equal candidate_homeassistant_absent \
        "$(grep -Fc 'homeassistant.local.theama.co' \
            "$action23b_candidate" || true)" 0 || return 1
    # conditional-validator-explicit-failures-end
    action23b_live_records=$(mktemp)
    action23b_candidate_records=$(mktemp)
    grep -E '^[[:space:]]+local-data(-ptr)?: ' "$live_local_zone" |
        LC_ALL=C sort >"$action23b_live_records" || return 1
    grep -E '^[[:space:]]+local-data(-ptr)?: ' "$action23b_candidate" |
        grep -Fv 'pihole-admin.local.theama.co. IN A 10.1.0.56' |
        grep -Fv 'proxy.local.theama.co. IN A 10.1.0.56' |
        LC_ALL=C sort >"$action23b_candidate_records" || return 1
    action23b_existing_records_unchanged=$(
        if cmp -s "$action23b_live_records" "$action23b_candidate_records"; then
            printf true
        else
            printf false
        fi
    )
    # conditional-validator-explicit-failures-begin
    assert_equal candidate_existing_records_unchanged \
        "$action23b_existing_records_unchanged" true || return 1
    rm -f -- "$action23b_live_records" || return 1
    rm -f -- "$action23b_candidate_records" || return 1
    # conditional-validator-explicit-failures-end
}

validate_shadow_parser() {
    local action23b_parser_root=$1
    local action23b_parser_candidate=$2

    {
        printf 'include-toplevel: "%s"\n' "$live_primary"
        printf 'include-toplevel: "%s"\n' "$action23b_parser_candidate"
    } >"$action23b_parser_root"
    unbound-checkconf "$action23b_parser_root" >/dev/null
}

run_dns_probe_command() (
    trap - ERR

    local action23b_probe_server=$1
    local action23b_probe_port=$2
    local action23b_probe_name=$3
    local action23b_probe_type=$4
    local action23b_probe_binary=${5:-dig}

    if [[ "$action23b_probe_type" == PTR ]]; then
        timeout 2 "$action23b_probe_binary" +time=1 +tries=1 +short \
            -p "$action23b_probe_port" "@$action23b_probe_server" \
            -x "$action23b_probe_name" 2>/dev/null
    else
        timeout 2 "$action23b_probe_binary" +time=1 +tries=1 +short \
            -p "$action23b_probe_port" "@$action23b_probe_server" \
            "$action23b_probe_name" "$action23b_probe_type" 2>/dev/null
    fi
)

capture_dns_probe() {
    local action23b_probe_server=$1
    local action23b_probe_port=$2
    local action23b_probe_name=$3
    local action23b_probe_type=$4
    local action23b_probe_binary=${5:-dig}
    local action23b_probe_output
    local action23b_probe_status
    local action23b_probe_canonical

    if action23b_probe_output=$(run_dns_probe_command \
        "$action23b_probe_server" "$action23b_probe_port" \
        "$action23b_probe_name" "$action23b_probe_type" \
        "$action23b_probe_binary"); then
        action23b_probe_status=0
    else
        action23b_probe_status=$?
    fi

    action23b_probe_canonical=$(printf '%s\n' "$action23b_probe_output" |
        sed '/^$/d' | LC_ALL=C sort -u |
        awk 'BEGIN { first = 1 }
            {
                if (!first) { printf "," }
                printf "%s", $0
                first = 0
            }')
    if [[ -z "$action23b_probe_canonical" ]]; then
        action23b_probe_canonical=none
    fi

    probe_status_value=$action23b_probe_status
    if [[ ${#action23b_probe_canonical} -le 512 &&
        "$action23b_probe_canonical" =~ ^[A-Za-z0-9:.,_-]+$ ]]; then
        probe_safe_value=true
        probe_answer_value=$action23b_probe_canonical
    else
        probe_safe_value=false
        probe_answer_value="unsafe_sha256_$(printf '%s' "$action23b_probe_canonical" |
            sha256sum | awk '{ print $1 }')"
    fi
}

readiness_probe_contract_test() {
    local action23b_probe_test_dir
    local action23b_probe_failure_binary
    local action23b_probe_success_binary
    local action23b_probe_trap_fired=false

    action23b_probe_test_dir=$(mktemp -d)
    action23b_probe_failure_binary="$action23b_probe_test_dir/dig-failure"
    action23b_probe_success_binary="$action23b_probe_test_dir/dig-success"
    trap 'rm -rf -- "$action23b_probe_test_dir"' RETURN
    printf '%s\n' '#!/bin/sh' 'exit 9' >"$action23b_probe_failure_binary"
    printf '%s\n' '#!/bin/sh' "printf '%s\\n' 10.1.0.56" \
        >"$action23b_probe_success_binary"
    chmod 0700 "$action23b_probe_failure_binary" "$action23b_probe_success_binary"

    trap 'action23b_probe_trap_fired=true' ERR
    capture_dns_probe 127.0.0.1 53 example.invalid A \
        "$action23b_probe_failure_binary"
    if [[ "$probe_status_value" != 9 ]]; then return 1; fi
    if [[ "$probe_answer_value" != none ]]; then return 1; fi
    if [[ "$probe_safe_value" != true ]]; then return 1; fi
    if [[ "$action23b_probe_trap_fired" != false ]]; then return 1; fi

    capture_dns_probe 127.0.0.1 53 example.invalid A \
        "$action23b_probe_success_binary"
    if [[ "$probe_status_value" != 0 ]]; then return 1; fi
    if [[ "$probe_answer_value" != 10.1.0.56 ]]; then return 1; fi
    if [[ "$probe_safe_value" != true ]]; then return 1; fi
    if [[ "$action23b_probe_trap_fired" != false ]]; then return 1; fi
    trap - ERR
    trap - RETURN
    rm -rf -- "$action23b_probe_test_dir"
    printf 'action_23b_readiness_probe_contract_test_complete=true\n'
}

record_readiness_equal() {
    local action23b_ready_label=$1
    local action23b_ready_observed=$2
    local action23b_ready_expected=$3

    if [[ "$action23b_ready_observed" == "$action23b_ready_expected" ]]; then
        pass_check "$action23b_ready_label"
    else
        printf 'action_23b_check_%s=false\n' "$action23b_ready_label" >&2
        printf 'action_23b_failed_check=%s\n' "$action23b_ready_label" >&2
        printf 'action_23b_failed_observed=%s\n' "$action23b_ready_observed" >&2
        readiness_failure_count=$((readiness_failure_count + 1))
    fi
}

validate_readiness_results() {
    local action23b_ready_key
    local -n action23b_status_map=$1
    local -n action23b_answer_map=$2
    local -n action23b_safe_map=$3
    local -n action23b_expected_map=$4
    local -n action23b_iteration_map=$5

    # conditional-validator-explicit-failures-begin
    readiness_failure_count=0
    for action23b_ready_key in "${readiness_keys[@]}"; do
        record_readiness_equal \
            "readiness_${action23b_ready_key}_command_status" \
            "${action23b_status_map[$action23b_ready_key]}" 0 || return 1
        record_readiness_equal \
            "readiness_${action23b_ready_key}_answer_safe" \
            "${action23b_safe_map[$action23b_ready_key]}" true || return 1
        record_readiness_equal \
            "readiness_${action23b_ready_key}_answer_exact" \
            "${action23b_answer_map[$action23b_ready_key]}" \
            "${action23b_expected_map[$action23b_ready_key]}" || return 1
        printf 'action_23b_value_readiness_%s_answer=%s\n' \
            "$action23b_ready_key" "${action23b_answer_map[$action23b_ready_key]}"
        printf 'action_23b_value_readiness_%s_iteration=%s\n' \
            "$action23b_ready_key" "${action23b_iteration_map[$action23b_ready_key]}"
    done
    [[ "$readiness_failure_count" -eq 0 ]] || return 1
    # conditional-validator-explicit-failures-end
}

emit_expected_labels() {
    local action23b_expected_command
    local action23b_expected_key

    for action23b_expected_command in "${required_commands[@]}"; do
        printf 'command_%s_available\n' "${action23b_expected_command//-/_}"
    done
    printf '%s\n' \
        uid_is_root working_directory_is_root hostname_matches \
        primary_regular primary_not_symlink primary_hash \
        live_local_zone_regular live_local_zone_not_symlink live_local_zone_hash \
        candidate_regular candidate_not_symlink candidate_parent_pattern \
        candidate_metadata candidate_hash backup_entry_absent backup_symlink_absent \
        transaction_entry_absent transaction_symlink_absent \
        unbound_active_before pihole_ftl_active_before \
        pihole_cli_regular pihole_cli_not_symlink pihole_cli_executable \
        candidate_admin_a_exact_once candidate_proxy_a_exact_once \
        live_admin_a_absent live_proxy_a_absent candidate_caddy_aaaa_absent \
        candidate_caddy_ptr_absent candidate_caddy_srv_absent \
        candidate_homeassistant_absent candidate_existing_records_unchanged \
        candidate_parser parser_root_cleanup backup_directory_create \
        backup_local_zone_create backup_manifest_chmod backup_manifest_action \
        backup_manifest_entry_count transaction_local_zone_create \
        transaction_local_zone_hash local_zone_file_switch unbound_reload \
        pihole_restartdns pihole_ftl_active_after_reset \
        pihole_ftl_pid_after_reset_nonzero pihole_ftl_pid_changed_after_reset \
        pihole_ftl_restarts_after_reset_numeric
    for action23b_expected_key in "${readiness_keys[@]}"; do
        printf 'readiness_%s_command_status\n' "$action23b_expected_key"
        printf 'readiness_%s_answer_safe\n' "$action23b_expected_key"
        printf 'readiness_%s_answer_exact\n' "$action23b_expected_key"
    done
    printf '%s\n' \
        node_b_management_https caddy_vip_https \
        unbound_active_after unbound_pid_preserved unbound_restarts_preserved \
        pihole_ftl_active_at_acceptance pihole_ftl_pid_stable_after_reset \
        pihole_ftl_restarts_stable_after_reset final_local_zone_hash \
        final_local_zone_metadata final_transaction_entry_absent \
        final_transaction_symlink_absent final_backup_manifest_regular \
        final_backup_manifest_not_symlink final_backup_manifest_hash_stable
}

emit_contract_transcript() {
    local action23b_contract_label
    local action23b_contract_count=0

    while IFS= read -r action23b_contract_label; do
        [[ -n "$action23b_contract_label" ]] || continue
        printf 'action_23b_check_%s=true\n' "$action23b_contract_label"
        action23b_contract_count=$((action23b_contract_count + 1))
    done < <(emit_expected_labels)
    printf 'action_23b_value_check_count=%s\n' "$action23b_contract_count"
    printf 'action_23b_backup_dir=%s\n' "$backup_dir"
    printf 'action_23b_manifest_action=23b\n'
    printf 'action_23b_record_family=A\n'
    printf 'action_23b_local_zone_sha256=%s\n' "$candidate_local_zone_sha256"
    printf 'action_23b_dns_configuration_mutation=true\n'
    printf 'action_23b_pihole_cache_reset=true\n'
    printf 'action_23b_unbound_reload=true\n'
    printf 'action_23b_peer_ssh=false\n'
    printf 'action_23b_synchronization_executed=false\n'
    printf 'action_23b_acceptance=true\n'
}

rollback_record_status() {
    local action23b_rollback_label=$1
    local action23b_rollback_status=$2

    printf 'action_23b_rollback_check_%s_status=%s\n' \
        "$action23b_rollback_label" "$action23b_rollback_status" >&2
    if [[ "$action23b_rollback_status" -ne 0 ]]; then
        rollback_failed=true
    fi
}

rollback_record_equal() {
    local action23b_rollback_equal_label=$1
    local action23b_rollback_observed=$2
    local action23b_rollback_expected=$3

    if [[ "$action23b_rollback_observed" == "$action23b_rollback_expected" ]]; then
        printf 'action_23b_rollback_check_%s=true\n' \
            "$action23b_rollback_equal_label" >&2
    else
        printf 'action_23b_rollback_check_%s=false\n' \
            "$action23b_rollback_equal_label" >&2
        rollback_failed=true
    fi
}

rollback() {
    local action23b_original_status=$?
    local action23b_rollback_status=0

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$action23b_original_status"
    fi

    set +e
    rollback_failed=false
    printf 'action_23b_rollback_started=true\n' >&2
    if [[ "$mutation_started" == true ]]; then
        install -o root -g root -m 0644 \
            "$backup_dir/pihole-local-zone.conf.before" "$live_local_zone"
        action23b_rollback_status=$?
        rollback_record_status local_zone_restore "$action23b_rollback_status"
        unbound-control reload >/dev/null 2>&1
        action23b_rollback_status=$?
        rollback_record_status unbound_reload "$action23b_rollback_status"
        perform_pihole_reset >/dev/null 2>&1
        action23b_rollback_status=$?
        rollback_record_status pihole_restartdns "$action23b_rollback_status"
        systemctl is-active --quiet unbound.service
        action23b_rollback_status=$?
        rollback_record_status unbound_active "$action23b_rollback_status"
        systemctl is-active --quiet pihole-FTL.service
        action23b_rollback_status=$?
        rollback_record_status pihole_ftl_active "$action23b_rollback_status"
    elif [[ "$backup_started" == true ]]; then
        rm -rf -- "$backup_dir"
        action23b_rollback_status=$?
        rollback_record_status unused_backup_cleanup "$action23b_rollback_status"
    fi
    rm -f -- "$transaction_file"
    action23b_rollback_status=$?
    rollback_record_status transaction_cleanup "$action23b_rollback_status"

    if [[ "$mutation_started" == true ]]; then
        rollback_record_equal local_zone_hash \
            "$(file_hash "$live_local_zone" 2>/dev/null)" \
            "$accepted_local_zone_sha256"
        rollback_record_equal unbound_pid \
            "$(service_pid unbound.service)" "$pre_unbound_pid"
        rollback_record_equal unbound_restarts \
            "$(service_restarts unbound.service)" "$pre_unbound_restarts"
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_23b_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_23b_rollback_complete=true\n' >&2
    exit "$action23b_original_status"
}

unhandled_error() {
    local action23b_error_status=$?
    local action23b_error_line=$1
    local action23b_error_command=$2

    printf 'action_23b_unhandled_error=true\n' >&2
    printf 'action_23b_unhandled_status=%s\n' "$action23b_error_status" >&2
    printf 'action_23b_unhandled_boundary=%s\n' "$current_boundary" >&2
    printf 'action_23b_unhandled_line=%s\n' "$action23b_error_line" >&2
    printf 'action_23b_unhandled_command_sha256=%s\n' \
        "$(printf '%s' "$action23b_error_command" | sha256sum | awk '{ print $1 }')" >&2
    return "$action23b_error_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$expected_hostname" == j1-svpihole0 ]]
        [[ "$accepted_local_zone_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]]
        [[ "$candidate_local_zone_sha256" == b0c6549c1ac5825de7c50e60e5c825cddb51f5d75056f0fd37c196d670886160 ]]
        [[ "$pihole_reset_timeout_seconds" -eq 30 ]]
        readiness_probe_contract_test
        printf 'action_23b_driver_self_test_complete=true\n'
        exit 0
        ;;
    --expected-labels)
        [[ $# -eq 1 ]]
        emit_expected_labels
        exit 0
        ;;
    --contract-transcript)
        [[ $# -eq 1 ]]
        emit_contract_transcript
        exit 0
        ;;
    --candidate)
        [[ $# -eq 2 ]]
        ;;
    *)
        printf 'Usage: %s --candidate /run/caddy-action23b.*/pihole-local-zone.conf\n' \
            "${0##*/}" >&2
        exit 2
        ;;
esac

candidate_local_zone=$2
readonly candidate_local_zone
candidate_parent=$(dirname -- "$candidate_local_zone")
readonly candidate_parent
parser_root="$candidate_parent/unbound-action23b.conf"
readonly parser_root

trap 'unhandled_error "$LINENO" "$BASH_COMMAND"' ERR
trap rollback EXIT

printf 'action_23b_remote_reached=true\n'
set_boundary required_command_preflight
for required_command in "${required_commands[@]}"; do
    run_check "command_${required_command//-/_}_available" \
        command -v "$required_command"
done

set_boundary identity_and_live_state_preflight
assert_equal uid_is_root "$(id -u)" 0
assert_equal working_directory_is_root "$PWD" /
assert_equal hostname_matches "$(hostname)" "$expected_hostname"
assert_file_shape primary "$live_primary"
assert_equal primary_hash "$(file_hash "$live_primary")" \
    "$accepted_primary_sha256"
assert_file_shape live_local_zone "$live_local_zone"
assert_equal live_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$accepted_local_zone_sha256"
assert_file_shape candidate "$candidate_local_zone"
assert_equal candidate_parent_pattern \
    "$(if [[ "$candidate_parent" =~ ^/run/caddy-action23b\.[A-Za-z0-9]+$ ]]; then
        printf valid
    else
        printf invalid
    fi)" valid
assert_equal candidate_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_local_zone")" root:root:600
assert_equal candidate_hash "$(file_hash "$candidate_local_zone")" \
    "$candidate_local_zone_sha256"
assert_path_absent backup "$backup_dir"
assert_path_absent transaction "$transaction_file"
run_check unbound_active_before systemctl is-active --quiet unbound.service
run_check pihole_ftl_active_before systemctl is-active --quiet pihole-FTL.service
assert_file_shape pihole_cli "$pihole_cli"
assert_equal pihole_cli_executable \
    "$(if [[ -x "$pihole_cli" ]]; then printf true; else printf false; fi)" true

set_boundary candidate_record_preflight
validate_candidate_records "$candidate_local_zone"
set_boundary candidate_parser_preflight
run_check candidate_parser validate_shadow_parser \
    "$parser_root" "$candidate_local_zone"
run_check parser_root_cleanup rm -f -- "$parser_root"

set_boundary service_continuity_capture
pre_unbound_pid=$(service_pid unbound.service)
pre_unbound_restarts=$(service_restarts unbound.service)
pre_ftl_pid=$(service_pid pihole-FTL.service)

set_boundary rollback_backup_creation
backup_started=true
run_check backup_directory_create \
    install -d -o root -g root -m 0700 "$backup_dir"
run_check backup_local_zone_create \
    install -o root -g root -m 0600 \
    "$live_local_zone" "$backup_dir/pihole-local-zone.conf.before"
{
    printf 'action=23b\n'
    printf 'node=%s\n' "$expected_hostname"
    printf 'record_family=A\n'
    printf 'local_zone_before_sha256=%s\n' "$accepted_local_zone_sha256"
    printf 'local_zone_after_sha256=%s\n' "$candidate_local_zone_sha256"
} >"$backup_dir/manifest"
run_check backup_manifest_chmod chmod 0600 "$backup_dir/manifest"
assert_equal backup_manifest_action \
    "$(awk -F= '$1 == "action" { print $2 }' "$backup_dir/manifest")" 23b
assert_equal backup_manifest_entry_count "$(wc -l <"$backup_dir/manifest")" 5
backup_manifest_hash=$(file_hash "$backup_dir/manifest")
readonly backup_manifest_hash

set_boundary transaction_file_preparation
run_check transaction_local_zone_create \
    install -o root -g root -m 0644 \
    "$candidate_local_zone" "$transaction_file"
assert_equal transaction_local_zone_hash \
    "$(file_hash "$transaction_file")" "$candidate_local_zone_sha256"

set_boundary atomic_live_file_switch
mutation_started=true
run_check local_zone_file_switch mv -f -- \
    "$transaction_file" "$live_local_zone"

set_boundary unbound_reload
run_check unbound_reload unbound-control reload

set_boundary pihole_cache_reset
run_check pihole_restartdns perform_pihole_reset
run_check pihole_ftl_active_after_reset \
    systemctl is-active --quiet pihole-FTL.service
post_reset_ftl_pid=$(service_pid pihole-FTL.service)
post_reset_ftl_restarts=$(service_restarts pihole-FTL.service)
assert_equal pihole_ftl_pid_after_reset_nonzero \
    "$(if [[ "$post_reset_ftl_pid" =~ ^[1-9][0-9]*$ ]]; then printf true; else printf false; fi)" \
    true
assert_equal pihole_ftl_pid_changed_after_reset \
    "$(if [[ "$post_reset_ftl_pid" != "$pre_ftl_pid" ]]; then printf true; else printf false; fi)" \
    true
assert_equal pihole_ftl_restarts_after_reset_numeric \
    "$(if [[ "$post_reset_ftl_restarts" =~ ^[0-9]+$ ]]; then printf true; else printf false; fi)" \
    true

# DNS_READINESS_BLOCK_BEGIN
set_boundary independently_labeled_dns_readiness
declare -A readiness_server=(
    [direct_proxy_a]=127.0.0.1 [direct_admin_a]=127.0.0.1
    [local_proxy_a]=127.0.0.1 [local_admin_a]=127.0.0.1
    [direct_pihole_a]=127.0.0.1 [direct_pihole_aaaa]=127.0.0.1
    [direct_pihole_ptr4]=127.0.0.1 [local_pihole_a]=127.0.0.1
    [local_pihole_aaaa]=127.0.0.1 [local_pihole_ptr4]=127.0.0.1
)
declare -A readiness_port=(
    [direct_proxy_a]=5335 [direct_admin_a]=5335
    [local_proxy_a]=53 [local_admin_a]=53
    [direct_pihole_a]=5335 [direct_pihole_aaaa]=5335
    [direct_pihole_ptr4]=5335 [local_pihole_a]=53
    [local_pihole_aaaa]=53 [local_pihole_ptr4]=53
)
declare -A readiness_name=(
    [direct_proxy_a]="$proxy_fqdn" [direct_admin_a]="$admin_fqdn"
    [local_proxy_a]="$proxy_fqdn" [local_admin_a]="$admin_fqdn"
    [direct_pihole_a]="$pihole_fqdn" [direct_pihole_aaaa]="$pihole_fqdn"
    [direct_pihole_ptr4]="$pihole_ipv4" [local_pihole_a]="$pihole_fqdn"
    [local_pihole_aaaa]="$pihole_fqdn" [local_pihole_ptr4]="$pihole_ipv4"
)
declare -A readiness_type=(
    [direct_proxy_a]=A [direct_admin_a]=A [local_proxy_a]=A [local_admin_a]=A
    [direct_pihole_a]=A [direct_pihole_aaaa]=AAAA [direct_pihole_ptr4]=PTR
    [local_pihole_a]=A [local_pihole_aaaa]=AAAA [local_pihole_ptr4]=PTR
)
declare -A readiness_expected=(
    [direct_proxy_a]="$caddy_ipv4" [direct_admin_a]="$caddy_ipv4"
    [local_proxy_a]="$caddy_ipv4" [local_admin_a]="$caddy_ipv4"
    [direct_pihole_a]="$pihole_ipv4" [direct_pihole_aaaa]="$pihole_ipv6"
    [direct_pihole_ptr4]="${pihole_fqdn}." [local_pihole_a]="$pihole_ipv4"
    [local_pihole_aaaa]="$pihole_ipv6" [local_pihole_ptr4]="${pihole_fqdn}."
)
declare -A readiness_status=()
declare -A readiness_answer=()
declare -A readiness_safe=()
declare -A readiness_iteration=()
declare -A readiness_ready=()
readiness_deadline=$((SECONDS + readiness_timeout_seconds))
readonly readiness_deadline

for readiness_key in "${readiness_keys[@]}"; do
    readiness_status[$readiness_key]=not_run
    readiness_answer[$readiness_key]=none
    readiness_safe[$readiness_key]=false
    readiness_iteration[$readiness_key]=none
    readiness_ready[$readiness_key]=false
done
for readiness_poll_iteration in {1..20}; do
    for readiness_key in "${readiness_keys[@]}"; do
        if ((SECONDS >= readiness_deadline)); then break; fi
        if [[ "${readiness_ready[$readiness_key]}" == true ]]; then continue; fi
        capture_dns_probe \
            "${readiness_server[$readiness_key]}" \
            "${readiness_port[$readiness_key]}" \
            "${readiness_name[$readiness_key]}" \
            "${readiness_type[$readiness_key]}"
        # ShellCheck cannot follow these arrays through the nameref validator.
        # shellcheck disable=SC2034
        readiness_status[$readiness_key]=$probe_status_value
        # shellcheck disable=SC2034
        readiness_answer[$readiness_key]=$probe_answer_value
        # shellcheck disable=SC2034
        readiness_safe[$readiness_key]=$probe_safe_value
        if [[ "$probe_status_value" -eq 0 && "$probe_safe_value" == true &&
            "$probe_answer_value" == "${readiness_expected[$readiness_key]}" ]]; then
            readiness_ready[$readiness_key]=true
            # shellcheck disable=SC2034
            readiness_iteration[$readiness_key]=$readiness_poll_iteration
        fi
    done
    readiness_all_ready=true
    for readiness_key in "${readiness_keys[@]}"; do
        if [[ "${readiness_ready[$readiness_key]}" != true ]]; then
            readiness_all_ready=false
        fi
    done
    if [[ "$readiness_all_ready" == true ]]; then break; fi
    if ((SECONDS >= readiness_deadline)); then break; fi
    sleep 1
done
validate_readiness_results readiness_status readiness_answer readiness_safe \
    readiness_expected readiness_iteration
# DNS_READINESS_BLOCK_END

set_boundary endpoint_continuity
run_check node_b_management_https https_probe "$node_b_fqdn" "$node_b_ipv4"
run_check caddy_vip_https https_probe "$admin_fqdn" "$caddy_ipv4"

set_boundary service_continuity_validation
run_check unbound_active_after systemctl is-active --quiet unbound.service
assert_equal unbound_pid_preserved "$(service_pid unbound.service)" \
    "$pre_unbound_pid"
assert_equal unbound_restarts_preserved \
    "$(service_restarts unbound.service)" "$pre_unbound_restarts"
run_check pihole_ftl_active_at_acceptance \
    systemctl is-active --quiet pihole-FTL.service
assert_equal pihole_ftl_pid_stable_after_reset \
    "$(service_pid pihole-FTL.service)" "$post_reset_ftl_pid"
assert_equal pihole_ftl_restarts_stable_after_reset \
    "$(service_restarts pihole-FTL.service)" "$post_reset_ftl_restarts"

set_boundary final_file_validation
assert_equal final_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$candidate_local_zone_sha256"
assert_equal final_local_zone_metadata \
    "$(stat -c '%U:%G:%a' "$live_local_zone")" root:root:644
assert_path_absent final_transaction "$transaction_file"
assert_file_shape final_backup_manifest "$backup_dir/manifest"
assert_equal final_backup_manifest_hash_stable \
    "$(file_hash "$backup_dir/manifest")" "$backup_manifest_hash"

set_boundary acceptance
transaction_complete=true
printf 'action_23b_value_check_count=%s\n' "${#seen_checks[@]}"
printf 'action_23b_backup_dir=%s\n' "$backup_dir"
printf 'action_23b_manifest_action=23b\n'
printf 'action_23b_record_family=A\n'
printf 'action_23b_local_zone_sha256=%s\n' "$candidate_local_zone_sha256"
printf 'action_23b_dns_configuration_mutation=true\n'
printf 'action_23b_pihole_cache_reset=true\n'
printf 'action_23b_unbound_reload=true\n'
printf 'action_23b_peer_ssh=false\n'
printf 'action_23b_synchronization_executed=false\n'
printf 'action_23b_acceptance=true\n'
