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
readonly live_hosts=/etc/hosts
readonly backup_dir=/var/backups/caddy-ha/action17n-retry-node-a-dns-nss
readonly prior_backup_dir=/var/backups/caddy-ha/action17n-node-a-dns-nss
readonly local_zone_transaction=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action17n-retry.new
readonly hosts_transaction=/etc/.hosts.action17n-retry.new
readonly accepted_primary_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly accepted_local_zone_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly candidate_local_zone_sha256=c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4
readonly prior_driver_sha256=7b24de1f46fd9fc04a0aec2819e3c0c7f728cef265720c4a1df3c93389c81990
readonly peer_ipv4=10.1.0.54
readonly peer_ipv6=fd36:5aa8:6971:1::54
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly peer_fqdn=pihole00.local.theama.co
readonly node_a_fqdn=pihole0.local.theama.co
readonly marker_begin='# BEGIN CADDY HA SYNC PEER'
readonly marker_end='# END CADDY HA SYNC PEER'
readonly readiness_timeout_seconds=20

mutation_started=false
transaction_complete=false
backup_started=false
pre_unbound_pid=
pre_unbound_restarts=
pre_ftl_pid=
pre_ftl_restarts=
pre_hosts_meta=
pre_prior_backup_manifest_hash=
current_boundary=initialization
probe_status_value=
probe_answer_value=
probe_safe_value=
readiness_failure_count=0

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

pass_check() {
    local check_label=$1

    printf 'action_17n_retry_check_%s=true\n' "$check_label"
}

fail_check() {
    local check_label=$1
    local observed_value=${2:-unavailable}

    printf 'action_17n_retry_check_%s=false\n' "$check_label" >&2
    printf 'action_17n_retry_failed_check=%s\n' "$check_label" >&2
    printf 'action_17n_retry_failed_observed=%s\n' "$observed_value" >&2
    return 1
}

assert_equal() {
    local equality_label=$1
    local observed_value=$2
    local expected_value=$3

    if [[ "$observed_value" == "$expected_value" ]]; then
        pass_check "$equality_label"
    else
        fail_check "$equality_label" "$observed_value"
    fi
}

assert_file_shape() {
    local shape_label=$1
    local shape_path=$2

    assert_equal "${shape_label}_regular" \
        "$(if [[ -f "$shape_path" ]]; then printf true; else printf false; fi)" \
        true
    assert_equal "${shape_label}_not_symlink" \
        "$(if [[ ! -L "$shape_path" ]]; then printf true; else printf false; fi)" \
        true
}

assert_path_absent() {
    local absence_label=$1
    local absence_path=$2

    assert_equal "${absence_label}_entry_absent" \
        "$(if [[ ! -e "$absence_path" ]]; then printf true; else printf false; fi)" \
        true
    assert_equal "${absence_label}_symlink_absent" \
        "$(if [[ ! -L "$absence_path" ]]; then printf true; else printf false; fi)" \
        true
}

run_check() {
    local operation_label=$1

    shift
    if "$@"; then
        pass_check "$operation_label"
    else
        fail_check "$operation_label"
    fi
}

set_boundary() {
    current_boundary=$1
    printf 'action_17n_retry_boundary=%s\n' "$current_boundary"
}

service_pid() {
    systemctl show --property=MainPID --value "$1"
}

service_restarts() {
    systemctl show --property=NRestarts --value "$1"
}

validate_candidate_records() {
    local candidate_record_label
    local candidate_record_text
    local -a candidate_record_labels=(
        pihole_vip_aaaa
        node_a_aaaa
        node_b_aaaa
        pihole_vip_ptr6
        node_a_ptr6
        node_b_ptr6
    )
    local -a candidate_record_texts=(
        '    local-data: "pihole.local.theama.co. IN AAAA fd36:5aa8:6971:1::55"'
        '    local-data: "pihole0.local.theama.co. IN AAAA fd36:5aa8:6971:1::53"'
        '    local-data: "pihole00.local.theama.co. IN AAAA fd36:5aa8:6971:1::54"'
        '    local-data-ptr: "fd36:5aa8:6971:1::55 pihole.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::53 pihole0.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::54 pihole00.local.theama.co."'
    )
    local candidate_record_index

    for candidate_record_index in "${!candidate_record_labels[@]}"; do
        candidate_record_label=${candidate_record_labels[$candidate_record_index]}
        candidate_record_text=${candidate_record_texts[$candidate_record_index]}
        assert_equal "candidate_${candidate_record_label}_exact_once" \
            "$(grep -Fxc "$candidate_record_text" "$candidate_local_zone" || true)" 1
        assert_equal "live_${candidate_record_label}_absent" \
            "$(grep -Fxc "$candidate_record_text" "$live_local_zone" || true)" 0
    done
    assert_equal candidate_homeassistant_a_absent \
        "$(grep -Fc 'homeassistant.local.theama.co. IN A ' \
            "$candidate_local_zone" || true)" 0
    assert_equal candidate_homeassistant_ptr_absent \
        "$(grep -Fc 'homeassistant.local.theama.co."' \
            "$candidate_local_zone" || true)" 0
    assert_equal candidate_caddy_records_absent \
        "$(grep -Ec 'proxy[.]local[.]theama[.]co|pihole-admin[.]local[.]theama[.]co|::56|10[.]1[.]0[.]56' \
            "$candidate_local_zone" || true)" 0
}

validate_shadow_parser() {
    local shadow_parser_path=$1

    {
        printf 'include-toplevel: "%s"\n' "$live_primary"
        printf 'include-toplevel: "%s"\n' "$candidate_local_zone"
    } >"$shadow_parser_path"
    unbound-checkconf "$shadow_parser_path" >/dev/null
}

capture_dns_probe() {
    local capture_server=$1
    local capture_port=$2
    local capture_name=$3
    local capture_type=$4
    local capture_output
    local capture_status
    local capture_canonical

    set +e
    if [[ "$capture_type" == PTR ]]; then
        capture_output=$(
            timeout 2 dig +time=1 +tries=1 +short \
                -p "$capture_port" "@$capture_server" -x "$capture_name" 2>/dev/null
        )
        capture_status=$?
    else
        capture_output=$(
            timeout 2 dig +time=1 +tries=1 +short \
                -p "$capture_port" "@$capture_server" \
                "$capture_name" "$capture_type" 2>/dev/null
        )
        capture_status=$?
    fi
    set -e

    capture_canonical=$(
        printf '%s\n' "$capture_output" |
            sed '/^$/d' |
            sort -u |
            awk 'BEGIN { first = 1 }
                {
                    if (!first) {
                        printf ","
                    }
                    printf "%s", $0
                    first = 0
                }'
    )
    if [[ -z "$capture_canonical" ]]; then
        capture_canonical=none
    fi

    probe_status_value=$capture_status
    if [[ ${#capture_canonical} -le 512 &&
        "$capture_canonical" =~ ^[A-Za-z0-9:.,_-]+$ ]]; then
        probe_safe_value=true
        probe_answer_value=$capture_canonical
    else
        probe_safe_value=false
        probe_answer_value="unsafe_sha256_$(printf '%s' "$capture_canonical" |
            sha256sum | awk '{ print $1 }')"
    fi
}

record_readiness_equal() {
    local readiness_label=$1
    local readiness_observed=$2
    local readiness_expected=$3

    if [[ "$readiness_observed" == "$readiness_expected" ]]; then
        pass_check "$readiness_label"
    else
        printf 'action_17n_retry_check_%s=false\n' "$readiness_label" >&2
        printf 'action_17n_retry_failed_check=%s\n' "$readiness_label" >&2
        printf 'action_17n_retry_failed_observed=%s\n' \
            "$readiness_observed" >&2
        readiness_failure_count=$((readiness_failure_count + 1))
    fi
}

validate_readiness_results() {
    local readiness_key
    local -n validation_status=$1
    local -n validation_answer=$2
    local -n validation_safe=$3
    local -n validation_expected=$4
    local -n validation_iteration=$5
    local -n validation_keys=$6

    readiness_failure_count=0
    for readiness_key in "${validation_keys[@]}"; do
        record_readiness_equal \
            "readiness_${readiness_key}_command_status" \
            "${validation_status[$readiness_key]}" 0
        record_readiness_equal \
            "readiness_${readiness_key}_answer_safe" \
            "${validation_safe[$readiness_key]}" true
        record_readiness_equal \
            "readiness_${readiness_key}_answer_exact" \
            "${validation_answer[$readiness_key]}" \
            "${validation_expected[$readiness_key]}"
        printf 'action_17n_retry_value_readiness_%s_answer=%s\n' \
            "$readiness_key" "${validation_answer[$readiness_key]}"
        printf 'action_17n_retry_value_readiness_%s_iteration=%s\n' \
            "$readiness_key" "${validation_iteration[$readiness_key]}"
    done
    [[ "$readiness_failure_count" -eq 0 ]]
}

rollback_record_status() {
    local rollback_label=$1
    local rollback_observed=$2

    printf 'action_17n_retry_rollback_check_%s_status=%s\n' \
        "$rollback_label" "$rollback_observed" >&2
    if [[ "$rollback_observed" -ne 0 ]]; then
        rollback_failed=true
    fi
}

rollback_record_equal() {
    local rollback_label=$1
    local rollback_observed=$2
    local rollback_expected=$3

    if [[ "$rollback_observed" == "$rollback_expected" ]]; then
        printf 'action_17n_retry_rollback_check_%s=true\n' \
            "$rollback_label" >&2
    else
        printf 'action_17n_retry_rollback_check_%s=false\n' \
            "$rollback_label" >&2
        rollback_failed=true
    fi
}

rollback() {
    local original_status=$?
    local rollback_status=0

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_status"
    fi

    set +e
    rollback_failed=false
    printf 'action_17n_retry_rollback_started=true\n' >&2
    if [[ "$mutation_started" == true ]]; then
        install -o root -g root -m 0644 \
            "$backup_dir/pihole-local-zone.conf.before" "$live_local_zone"
        rollback_status=$?
        rollback_record_status local_zone_restore "$rollback_status"

        cp -a -- "$backup_dir/hosts.before" "$live_hosts"
        rollback_status=$?
        rollback_record_status hosts_restore "$rollback_status"

        unbound-control reload >/dev/null 2>&1
        rollback_status=$?
        rollback_record_status unbound_reload "$rollback_status"
    elif [[ "$backup_started" == true ]]; then
        rm -rf -- "$backup_dir"
        rollback_status=$?
        rollback_record_status unused_backup_cleanup "$rollback_status"
    fi

    rm -f -- "$local_zone_transaction"
    rollback_status=$?
    rollback_record_status local_zone_transaction_cleanup "$rollback_status"
    rm -f -- "$hosts_transaction"
    rollback_status=$?
    rollback_record_status hosts_transaction_cleanup "$rollback_status"

    if [[ "$mutation_started" == true ]]; then
        rollback_record_equal local_zone_hash \
            "$(file_hash "$live_local_zone" 2>/dev/null)" \
            "$accepted_local_zone_sha256"
        rollback_record_equal hosts_metadata \
            "$(stat -c '%U:%G:%a' "$live_hosts" 2>/dev/null)" \
            "$pre_hosts_meta"
        rollback_record_equal unbound_pid \
            "$(service_pid unbound.service)" "$pre_unbound_pid"
        rollback_record_equal unbound_restarts \
            "$(service_restarts unbound.service)" "$pre_unbound_restarts"
        rollback_record_equal pihole_ftl_pid \
            "$(service_pid pihole-FTL.service)" "$pre_ftl_pid"
        rollback_record_equal pihole_ftl_restarts \
            "$(service_restarts pihole-FTL.service)" "$pre_ftl_restarts"
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'action_17n_retry_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 125
    fi
    printf 'action_17n_retry_rollback_complete=true\n' >&2
    exit "$original_status"
}

unhandled_error() {
    local error_status=$?
    local error_line=$1
    local error_command=$2

    printf 'action_17n_retry_unhandled_error=true\n' >&2
    printf 'action_17n_retry_unhandled_status=%s\n' "$error_status" >&2
    printf 'action_17n_retry_unhandled_boundary=%s\n' "$current_boundary" >&2
    printf 'action_17n_retry_unhandled_line=%s\n' "$error_line" >&2
    printf 'action_17n_retry_unhandled_command_sha256=%s\n' \
        "$(printf '%s' "$error_command" | sha256sum | awk '{ print $1 }')" >&2
    return "$error_status"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$expected_hostname" == j1-svpihole0 ]]
    [[ "$candidate_local_zone_sha256" == c70f709789223f91835f0f21c397f577d1e2bb24005a5defbf46055fb411dbb4 ]]
    [[ "$backup_dir" != "$prior_backup_dir" ]]
    printf 'action_17n_retry_driver_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" != --candidate || $# -ne 2 ]]; then
    printf 'Usage: %s --candidate /run/caddy-action17n-retry.*/pihole-local-zone.conf\n' \
        "${0##*/}" >&2
    exit 2
fi

candidate_local_zone=$2
readonly candidate_local_zone
candidate_parent=$(dirname -- "$candidate_local_zone")
readonly candidate_parent
parser_root="$candidate_parent/unbound-action17n-retry.conf"
readonly parser_root
prior_driver_artifact="$candidate_parent/apply-node-a-dns-nss-correction-action17n.sh"
readonly prior_driver_artifact

trap 'unhandled_error "$LINENO" "$BASH_COMMAND"' ERR
trap rollback EXIT

printf 'action_17n_retry_remote_reached=true\n'
set_boundary required_command_preflight
for required_command in \
    awk chmod chown cp dig dirname getent grep hostname id install mktemp mv \
    rm runuser sed sha256sum sleep sort stat systemctl timeout \
    unbound-checkconf unbound-control wc; do
    if command -v "$required_command" >/dev/null; then
        pass_check "command_${required_command//-/_}_available"
    else
        fail_check "command_${required_command//-/_}_available" missing
    fi
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
assert_file_shape live_hosts "$live_hosts"
assert_file_shape candidate "$candidate_local_zone"
assert_file_shape prior_driver_artifact "$prior_driver_artifact"
assert_equal prior_driver_artifact_hash \
    "$(file_hash "$prior_driver_artifact")" "$prior_driver_sha256"
assert_equal candidate_parent_pattern \
    "$(if [[ "$candidate_parent" =~ ^/run/caddy-action17n-retry\.[A-Za-z0-9]+$ ]]; then
        printf valid
    else
        printf invalid
    fi)" valid
assert_equal candidate_metadata \
    "$(stat -c '%U:%G:%a' "$candidate_local_zone")" root:root:600
assert_equal candidate_hash "$(file_hash "$candidate_local_zone")" \
    "$candidate_local_zone_sha256"
assert_file_shape prior_backup_manifest "$prior_backup_dir/manifest"
assert_equal prior_backup_manifest_action \
    "$(awk -F= '$1 == "action" { print $2 }' "$prior_backup_dir/manifest")" 17m
assert_equal prior_backup_manifest_metadata \
    "$(stat -c '%U:%G:%a' "$prior_backup_dir/manifest")" root:root:600
assert_path_absent retry_backup "$backup_dir"
assert_path_absent local_zone_transaction "$local_zone_transaction"
assert_path_absent hosts_transaction "$hosts_transaction"
assert_equal hosts_marker_begin_absent \
    "$(grep -Fxc "$marker_begin" "$live_hosts" || true)" 0
assert_equal hosts_marker_end_absent \
    "$(grep -Fxc "$marker_end" "$live_hosts" || true)" 0
assert_equal peer_fqdn_hosts_absent \
    "$(awk -v name="$peer_fqdn" '
        /^[[:space:]]*#/ { next }
        {
            for (field = 2; field <= NF; field++) {
                if ($field == name) {
                    found++
                }
            }
        }
        END { print found + 0 }
    ' "$live_hosts")" 0
run_check unbound_active systemctl is-active --quiet unbound.service
run_check pihole_ftl_active systemctl is-active --quiet pihole-FTL.service

set_boundary candidate_record_preflight
validate_candidate_records
set_boundary candidate_parser_preflight
run_check candidate_parser validate_shadow_parser "$parser_root"
run_check parser_root_cleanup rm -f -- "$parser_root"

set_boundary service_continuity_capture
pre_unbound_pid=$(service_pid unbound.service)
pre_unbound_restarts=$(service_restarts unbound.service)
pre_ftl_pid=$(service_pid pihole-FTL.service)
pre_ftl_restarts=$(service_restarts pihole-FTL.service)
pre_hosts_meta=$(stat -c '%U:%G:%a' "$live_hosts")
pre_prior_backup_manifest_hash=$(file_hash "$prior_backup_dir/manifest")

set_boundary rollback_backup_creation
backup_started=true
run_check backup_directory_create \
    install -d -o root -g root -m 0700 "$backup_dir"
run_check backup_local_zone_create \
    install -o root -g root -m 0600 \
    "$live_local_zone" "$backup_dir/pihole-local-zone.conf.before"
run_check backup_hosts_create cp -a -- "$live_hosts" "$backup_dir/hosts.before"
{
    printf 'action=17n\n'
    printf 'node=%s\n' "$expected_hostname"
    printf 'local_zone_before_sha256=%s\n' "$accepted_local_zone_sha256"
    printf 'local_zone_after_sha256=%s\n' "$candidate_local_zone_sha256"
    printf 'hosts_before_sha256=%s\n' "$(file_hash "$live_hosts")"
} >"$backup_dir/manifest"
run_check backup_manifest_chmod chmod 0600 "$backup_dir/manifest"
assert_equal backup_manifest_action \
    "$(awk -F= '$1 == "action" { print $2 }' "$backup_dir/manifest")" 17n
assert_equal backup_manifest_entry_count \
    "$(wc -l <"$backup_dir/manifest")" 5
set_boundary transaction_file_preparation
run_check transaction_local_zone_create \
    install -o root -g root -m 0644 \
    "$candidate_local_zone" "$local_zone_transaction"
run_check transaction_hosts_copy cp -a -- "$live_hosts" "$hosts_transaction"
{
    printf '\n%s\n' "$marker_begin"
    printf '%s %s\n' "$peer_ipv4" "$peer_fqdn"
    printf '%s %s\n' "$peer_ipv6" "$peer_fqdn"
    printf '%s\n' "$marker_end"
} >>"$hosts_transaction"
run_check transaction_hosts_chown chown root:root "$hosts_transaction"
run_check transaction_hosts_chmod \
    chmod "$(stat -c %a "$live_hosts")" "$hosts_transaction"
assert_equal transaction_local_zone_hash \
    "$(file_hash "$local_zone_transaction")" "$candidate_local_zone_sha256"
assert_equal transaction_hosts_peer_ipv4_exact \
    "$(grep -Fxc "$peer_ipv4 $peer_fqdn" "$hosts_transaction")" 1
assert_equal transaction_hosts_peer_ipv6_exact \
    "$(grep -Fxc "$peer_ipv6 $peer_fqdn" "$hosts_transaction")" 1

set_boundary atomic_live_file_switch
mutation_started=true
run_check local_zone_file_switch mv -f -- \
    "$local_zone_transaction" "$live_local_zone"
run_check hosts_file_switch mv -f -- "$hosts_transaction" "$live_hosts"

set_boundary unbound_reload
run_check unbound_reload unbound-control reload

# DNS_READINESS_BLOCK_BEGIN
set_boundary independently_labeled_dns_readiness
readonly -a readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)
declare -A readiness_server=(
    [direct_unbound_peer_aaaa]=127.0.0.1
    [direct_unbound_node_a_aaaa]=127.0.0.1
    [direct_unbound_peer_ptr6]=127.0.0.1
    [local_pihole_peer_aaaa]=127.0.0.1
    [local_pihole_node_a_aaaa]=127.0.0.1
    [local_pihole_peer_ptr6]=127.0.0.1
)
declare -A readiness_port=(
    [direct_unbound_peer_aaaa]=5335
    [direct_unbound_node_a_aaaa]=5335
    [direct_unbound_peer_ptr6]=5335
    [local_pihole_peer_aaaa]=53
    [local_pihole_node_a_aaaa]=53
    [local_pihole_peer_ptr6]=53
)
declare -A readiness_name=(
    [direct_unbound_peer_aaaa]="$peer_fqdn"
    [direct_unbound_node_a_aaaa]="$node_a_fqdn"
    [direct_unbound_peer_ptr6]="$peer_ipv6"
    [local_pihole_peer_aaaa]="$peer_fqdn"
    [local_pihole_node_a_aaaa]="$node_a_fqdn"
    [local_pihole_peer_ptr6]="$peer_ipv6"
)
declare -A readiness_type=(
    [direct_unbound_peer_aaaa]=AAAA
    [direct_unbound_node_a_aaaa]=AAAA
    [direct_unbound_peer_ptr6]=PTR
    [local_pihole_peer_aaaa]=AAAA
    [local_pihole_node_a_aaaa]=AAAA
    [local_pihole_peer_ptr6]=PTR
)
declare -A readiness_expected=(
    [direct_unbound_peer_aaaa]="$peer_ipv6"
    [direct_unbound_node_a_aaaa]="$node_a_ipv6"
    [direct_unbound_peer_ptr6]="${peer_fqdn}."
    [local_pihole_peer_aaaa]="$peer_ipv6"
    [local_pihole_node_a_aaaa]="$node_a_ipv6"
    [local_pihole_peer_ptr6]="${peer_fqdn}."
)
# ShellCheck cannot follow these arrays through the nameref validation helper.
# shellcheck disable=SC2034
declare -A readiness_status=()
# shellcheck disable=SC2034
declare -A readiness_answer=()
# shellcheck disable=SC2034
declare -A readiness_safe=()
# shellcheck disable=SC2034
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
        if ((SECONDS >= readiness_deadline)); then
            break
        fi
        if [[ "${readiness_ready[$readiness_key]}" == true ]]; then
            continue
        fi
        capture_dns_probe \
            "${readiness_server[$readiness_key]}" \
            "${readiness_port[$readiness_key]}" \
            "${readiness_name[$readiness_key]}" \
            "${readiness_type[$readiness_key]}"
        # ShellCheck cannot follow these values through the nameref helper.
        # shellcheck disable=SC2034
        readiness_status[$readiness_key]=$probe_status_value
        # shellcheck disable=SC2034
        readiness_answer[$readiness_key]=$probe_answer_value
        # shellcheck disable=SC2034
        readiness_safe[$readiness_key]=$probe_safe_value
        if [[ "$probe_status_value" -eq 0 &&
            "$probe_safe_value" == true &&
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
    if [[ "$readiness_all_ready" == true ]]; then
        break
    fi
    if ((SECONDS >= readiness_deadline)); then
        break
    fi
    sleep 1
done

validate_readiness_results \
    readiness_status readiness_answer readiness_safe readiness_expected \
    readiness_iteration readiness_keys
# DNS_READINESS_BLOCK_END

set_boundary nss_peer_resolution
assert_equal root_peer_ipv4 \
    "$(getent ahostsv4 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal root_peer_ipv6 \
    "$(getent ahostsv6 "$peer_fqdn" | awk 'NR == 1 { print $1 }')" "$peer_ipv6"
assert_equal caddy_sync_peer_ipv4 \
    "$(runuser -u caddy-sync -- getent ahostsv4 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv4"
assert_equal caddy_sync_peer_ipv6 \
    "$(runuser -u caddy-sync -- getent ahostsv6 "$peer_fqdn" |
        awk 'NR == 1 { print $1 }')" "$peer_ipv6"

set_boundary service_continuity_validation
assert_equal unbound_pid_preserved "$(service_pid unbound.service)" \
    "$pre_unbound_pid"
assert_equal unbound_restarts_preserved \
    "$(service_restarts unbound.service)" "$pre_unbound_restarts"
assert_equal pihole_ftl_pid_preserved "$(service_pid pihole-FTL.service)" \
    "$pre_ftl_pid"
assert_equal pihole_ftl_restarts_preserved \
    "$(service_restarts pihole-FTL.service)" "$pre_ftl_restarts"

set_boundary final_file_validation
assert_equal final_local_zone_hash "$(file_hash "$live_local_zone")" \
    "$candidate_local_zone_sha256"
assert_equal final_hosts_metadata "$(stat -c '%U:%G:%a' "$live_hosts")" \
    "$pre_hosts_meta"
assert_path_absent final_local_zone_transaction "$local_zone_transaction"
assert_path_absent final_hosts_transaction "$hosts_transaction"
assert_file_shape final_prior_backup_manifest "$prior_backup_dir/manifest"
assert_equal final_prior_backup_manifest_hash \
    "$(file_hash "$prior_backup_dir/manifest")" \
    "$pre_prior_backup_manifest_hash"

set_boundary acceptance
transaction_complete=true
printf 'action_17n_retry_backup_dir=%s\n' "$backup_dir"
printf 'action_17n_retry_manifest_action=17n\n'
printf 'action_17n_retry_local_zone_sha256=%s\n' \
    "$candidate_local_zone_sha256"
printf 'action_17n_retry_dns_configuration_mutation=true\n'
printf 'action_17n_retry_nss_configuration_mutation=true\n'
printf 'action_17n_retry_resolv_conf_mutation=false\n'
printf 'action_17n_retry_peer_connections=false\n'
printf 'action_17n_retry_synchronization_executed=false\n'
printf 'action_17n_retry_service_restart=false\n'
printf 'action_17n_retry_acceptance=true\n'
