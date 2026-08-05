#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a
readonly node_a_baseline_sha256=6669641d327ef31bebaf9ed0794c254760d7befafe9e0b4b92f14b2bad841f3d
readonly node_b_baseline_sha256=f5e2c80a917ddba313a942221e23b722c8c33c4982f7cb2f9e66e08bacf688f5
readonly probe_sha256=9b051e4c8b7c21e8f75bd9da71a7e04bc7d6582fd4eaa6a044f9ac2a4083f4d7
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly node_a_baseline="$script_directory/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh"
readonly node_b_baseline="$script_directory/run-node-b-keepalived-fragment-postinstall-action19a-b-outer.sh"
readonly probe="$script_directory/inspect-dual-node-caddy-vrrp-preactivation-action20a.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_one() {
    local exact_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$exact_line" "$transcript_path")" -eq 1 ]]
}
extract_one() {
    local key_name=$1
    local transcript_path=$2
    local extracted_value

    [[ "$(grep -c "^${key_name}=" "$transcript_path")" -eq 1 ]] || return 1
    extracted_value=$(sed -n "s/^${key_name}=//p" "$transcript_path") || return 1
    printf '%s\n' "$extracted_value"
}
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null ||
        return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$stream_path"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" \
        "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" \
        "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" \
        "$(file_hash "$stream_path")"
    if safe_stream "$stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
        if [[ -s "$stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$stream_label"
            cat "$stream_path"
            printf '%s_%s_end\n' "$prefix" "$stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
    return 97
}
expected_assertions() {
    printf '%s\n' \
        node_a_baseline_accepted node_b_baseline_accepted \
        node_a_probe_accepted node_b_probe_accepted node_a_health_ready \
        node_b_health_ready node_a_state_unchanged node_b_state_unchanged \
        dns_ipv4_single_owner dns_ipv6_single_owner \
        dns_dualstack_owner_coherent caddy_ipv4_absent_both \
        caddy_ipv6_absent_both priorities_exact vrids_exact \
        ipv4_peers_reciprocal ipv6_peers_reciprocal \
        main_inclusion_prerequisites notification_helpers_not_invoked
}
validate_baseline() {
    local baseline_role=$1
    local baseline_stdout=$2
    local baseline_stderr=$3
    local baseline_status=$4
    local baseline_prefix

    [[ "$baseline_status" -eq 0 ]] || return 1
    [[ ! -s "$baseline_stderr" ]] || return 1
    case "$baseline_role" in
        node-a) baseline_prefix=action_19e_a ;;
        node-b) baseline_prefix=action_19a_b ;;
        *) return 1 ;;
    esac
    require_one "${baseline_prefix}_assertion_count=114" "$baseline_stdout" ||
        return 1
    require_one "${baseline_prefix}_failed_assertion_count=0" "$baseline_stdout" ||
        return 1
    require_one "${baseline_prefix}_first_failure=none" "$baseline_stdout" ||
        return 1
    require_one "${baseline_prefix}_validation_status=0" "$baseline_stdout" ||
        return 1
    require_one "${baseline_prefix}_inner_status=0" "$baseline_stdout" || return 1
    require_one "${baseline_prefix}_outer_cleanup_complete=true" \
        "$baseline_stdout" || return 1
    for baseline_marker in helper_execution filesystem_mutations \
        service_mutations vrrp_mutations vip_mutations persistent_mutations; do
        require_one "${baseline_prefix}_${baseline_marker}=false" \
            "$baseline_stdout" || return 1
    done
}
validate_probe() {
    local probe_role=$1
    local probe_stdout=$2
    local probe_stderr=$3
    local probe_status=$4
    local expected_label
    local probe_expected_count

    [[ "$probe_status" -eq 0 ]] || return 1
    [[ ! -s "$probe_stderr" ]] || return 1
    probe_expected_count=$("$probe" --expected-assertions | wc -l) || return 1
    while IFS= read -r expected_label; do
        require_one "action_20a_probe_assertion_${expected_label}=true" \
            "$probe_stdout" || return 1
    done < <("$probe" --expected-assertions)
    [[ "$(grep -Ec '^action_20a_probe_assertion_[a-z0-9_]+=(true|false)$' \
        "$probe_stdout")" -eq "$probe_expected_count" ]] || return 1
    [[ "$(grep '^action_20a_probe_assertion_' "$probe_stdout" |
        cut -d= -f1 | LC_ALL=C sort | uniq -d | wc -l)" -eq 0 ]] || return 1
    require_one "action_20a_probe_assertion_count=$probe_expected_count" \
        "$probe_stdout" || return 1
    require_one 'action_20a_probe_failed_assertion_count=0' "$probe_stdout" ||
        return 1
    require_one 'action_20a_probe_first_failure=none' "$probe_stdout" || return 1
    require_one "action_20a_probe_value_node_role=$probe_role" \
        "$probe_stdout" || return 1
    require_one 'action_20a_probe_notification_helper_invoked=false' \
        "$probe_stdout" || return 1
    for probe_marker in filesystem_mutations service_mutations vrrp_mutations \
        vip_mutations persistent_mutations; do
        require_one "action_20a_probe_${probe_marker}=false" \
            "$probe_stdout" || return 1
    done
    require_one 'action_20a_probe_remote_complete=true' "$probe_stdout"
}
verify_sources() {
    [[ -f "$node_a_baseline" && ! -L "$node_a_baseline" ]] || return 1
    [[ -f "$node_b_baseline" && ! -L "$node_b_baseline" ]] || return 1
    [[ -f "$probe" && ! -L "$probe" ]] || return 1
    [[ "$(file_hash "$node_a_baseline")" = "$node_a_baseline_sha256" ]] ||
        return 1
    [[ "$(file_hash "$node_b_baseline")" = "$node_b_baseline_sha256" ]] ||
        return 1
    [[ "$(file_hash "$probe")" = "$probe_sha256" ]] || return 1
    bash -n "$node_a_baseline" "$node_b_baseline" "$probe" || return 1
    "$probe" --self-test >/dev/null || return 1
}
write_baseline_fixture() {
    local fixture_role=$1
    local fixture_path=$2
    local fixture_prefix

    case "$fixture_role" in
        node-a) fixture_prefix=action_19e_a ;;
        node-b) fixture_prefix=action_19a_b ;;
        *) return 1 ;;
    esac
    {
        printf '%s\n' \
            "${fixture_prefix}_assertion_count=114" \
            "${fixture_prefix}_failed_assertion_count=0" \
            "${fixture_prefix}_first_failure=none" \
            "${fixture_prefix}_helper_execution=false" \
            "${fixture_prefix}_filesystem_mutations=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_vrrp_mutations=false" \
            "${fixture_prefix}_vip_mutations=false" \
            "${fixture_prefix}_persistent_mutations=false" \
            "${fixture_prefix}_validation_status=0" \
            "${fixture_prefix}_inner_status=0" \
            "${fixture_prefix}_outer_cleanup_complete=true"
    } >"$fixture_path"
}
write_probe_fixture() {
    local fixture_role=$1
    local dns_count=$2
    local fixture_path=$3
    local fixture_label
    local fixture_priority fixture_ipv4_source fixture_ipv4_peer
    local fixture_ipv6_source fixture_ipv6_peer fixture_fragment
    local fixture_state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    if [[ "$fixture_role" = node-a ]]; then
        fixture_priority=140
        fixture_ipv4_source=10.1.0.53
        fixture_ipv4_peer=10.1.0.54
        fixture_ipv6_source=fd36:5aa8:6971:1::53
        fixture_ipv6_peer=fd36:5aa8:6971:1::54
        fixture_fragment=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
    else
        fixture_priority=100
        fixture_ipv4_source=10.1.0.54
        fixture_ipv4_peer=10.1.0.53
        fixture_ipv6_source=fd36:5aa8:6971:1::54
        fixture_ipv6_peer=fd36:5aa8:6971:1::53
        fixture_fragment=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
    fi
    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_probe_assertion_%s=true\n' "$fixture_label"
        done < <("$probe" --expected-assertions)
        printf '%s\n' \
            "action_20a_probe_value_node_role=$fixture_role" \
            "action_20a_probe_value_priority=$fixture_priority" \
            'action_20a_probe_value_ipv4_vrid=110' \
            'action_20a_probe_value_ipv6_vrid=111' \
            "action_20a_probe_value_ipv4_source=$fixture_ipv4_source" \
            "action_20a_probe_value_ipv4_peer=$fixture_ipv4_peer" \
            "action_20a_probe_value_ipv6_source=$fixture_ipv6_source" \
            "action_20a_probe_value_ipv6_peer=$fixture_ipv6_peer" \
            "action_20a_probe_value_dns_ipv4_vip_count=$dns_count" \
            "action_20a_probe_value_dns_ipv6_vip_count=$dns_count" \
            'action_20a_probe_value_caddy_ipv4_vip_count=0' \
            'action_20a_probe_value_caddy_ipv6_vip_count=0' \
            "action_20a_probe_value_main_sha256=$fixture_state" \
            "action_20a_probe_value_fragment_sha256=$fixture_fragment" \
            "action_20a_probe_value_before_state_sha256=$fixture_state" \
            "action_20a_probe_value_after_state_sha256=$fixture_state" \
            'action_20a_probe_value_health_status=0' \
            'action_20a_probe_value_health_stream_classification=true' \
            "action_20a_probe_assertion_count=$("$probe" --expected-assertions | wc -l)" \
            'action_20a_probe_failed_assertion_count=0' \
            'action_20a_probe_first_failure=none' \
            'action_20a_probe_notification_helper_invoked=false' \
            'action_20a_probe_filesystem_mutations=false' \
            'action_20a_probe_service_mutations=false' \
            'action_20a_probe_vrrp_mutations=false' \
            'action_20a_probe_vip_mutations=false' \
            'action_20a_probe_persistent_mutations=false' \
            'action_20a_probe_remote_complete=true'
    } >"$fixture_path"
}
run_contract_test() {
    local contract_root

    contract_root=$(mktemp -d /tmp/caddy-action20a-contract.XXXXXX) || return 1
    : >"$contract_root/empty"
    for contract_role in node-a node-b; do
        write_baseline_fixture "$contract_role" "$contract_root/baseline" || {
            rm -rf -- "$contract_root"
            return 1
        }
        validate_baseline "$contract_role" "$contract_root/baseline" \
            "$contract_root/empty" 0 || {
            rm -rf -- "$contract_root"
            return 1
        }
        write_probe_fixture "$contract_role" 0 "$contract_root/probe" || {
            rm -rf -- "$contract_root"
            return 1
        }
        validate_probe "$contract_role" "$contract_root/probe" \
            "$contract_root/empty" 0 || {
            rm -rf -- "$contract_root"
            return 1
        }
        printf 'action_20a_probe_assertion_identity_root=true\n' \
            >>"$contract_root/probe"
        if validate_probe "$contract_role" "$contract_root/probe" \
            "$contract_root/empty" 0; then
            rm -rf -- "$contract_root"
            return 1
        fi
    done
    rm -rf -- "$contract_root"
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_contract_test
        printf '%s_runner_contract_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--contract-test|--expected-assertions]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
if [[ "${CADDY_ACTION20A_INTERCEPTED_TEST:-}" = 1 ]]; then
    case "$PWD" in
        /home/aaron/code/homelab-server-configs | \
            /workspace/homelab-server-configs) ;;
        *) exit 1 ;;
    esac
else
    [[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
fi
work_directory=$(mktemp -d /tmp/caddy-action20a.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

if [[ "${CADDY_ACTION20A_INTERCEPTED_TEST:-}" = 1 ]]; then
    node_a_baseline_command=${CADDY_ACTION20A_NODE_A_BASELINE:?}
    node_b_baseline_command=${CADDY_ACTION20A_NODE_B_BASELINE:?}
    ssh_binary=${CADDY_ACTION20A_SSH_BINARY:?}
else
    node_a_baseline_command=$node_a_baseline
    node_b_baseline_command=$node_b_baseline
    ssh_binary=/usr/bin/ssh
fi
readonly node_a_baseline_command node_b_baseline_command ssh_binary

declare -A baseline_status probe_status
declare -A baseline_stdout baseline_stderr probe_stdout probe_stderr
for node_role in node-a node-b; do
    role_key=${node_role//-/_}
    baseline_stdout[$node_role]=$work_directory/$node_role.baseline.stdout
    baseline_stderr[$node_role]=$work_directory/$node_role.baseline.stderr
    probe_stdout[$node_role]=$work_directory/$node_role.probe.stdout
    probe_stderr[$node_role]=$work_directory/$node_role.probe.stderr
    : >"${baseline_stdout[$node_role]}"
    : >"${baseline_stderr[$node_role]}"
    : >"${probe_stdout[$node_role]}"
    : >"${probe_stderr[$node_role]}"
    chmod 0600 "${baseline_stdout[$node_role]}" \
        "${baseline_stderr[$node_role]}" "${probe_stdout[$node_role]}" \
        "${probe_stderr[$node_role]}"
    baseline_status[$node_role]=0
    if [[ "$node_role" = node-a ]]; then
        "$node_a_baseline_command" >"${baseline_stdout[$node_role]}" \
            2>"${baseline_stderr[$node_role]}" || baseline_status[$node_role]=$?
        host_alias=pihole0.local.theama.co
        target=pi@10.1.0.53
    else
        "$node_b_baseline_command" >"${baseline_stdout[$node_role]}" \
            2>"${baseline_stderr[$node_role]}" || baseline_status[$node_role]=$?
        host_alias=pihole00.local.theama.co
        target=pi@10.1.0.54
    fi
    emit_stream "${role_key}_baseline_stdout" \
        "${baseline_stdout[$node_role]}" || {
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
        exit 97
    }
    emit_stream "${role_key}_baseline_stderr" \
        "${baseline_stderr[$node_role]}" || {
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
        exit 97
    }
    probe_status[$node_role]=0
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$host_alias" \
        "$target" "cd / && sudo -n /bin/bash -s -- --node $node_role" \
        <"$probe" >"${probe_stdout[$node_role]}" \
        2>"${probe_stderr[$node_role]}" || probe_status[$node_role]=$?
    emit_stream "${role_key}_probe_stdout" "${probe_stdout[$node_role]}" || {
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
        exit 97
    }
    emit_stream "${role_key}_probe_stderr" "${probe_stderr[$node_role]}" || {
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
        exit 97
    }
done
printf '%s_phase_capture_complete=true\n' "$prefix"

failed_count=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    failed_count=$((failed_count + 1))
    if [[ "$first_failure" = none ]]; then first_failure=$assertion_label; fi
    return 0
}

readonly node_a_key=node-a
readonly node_b_key=node-b
node_a_baseline_validation=0
validate_baseline node-a "${baseline_stdout[$node_a_key]}" \
    "${baseline_stderr[$node_a_key]}" "${baseline_status[$node_a_key]}" ||
    node_a_baseline_validation=$?
readonly node_a_baseline_validation
printf '%s_phase_node_a_baseline_validation=%s\n' "$prefix" \
    "$node_a_baseline_validation"
node_b_baseline_validation=0
validate_baseline node-b "${baseline_stdout[$node_b_key]}" \
    "${baseline_stderr[$node_b_key]}" "${baseline_status[$node_b_key]}" ||
    node_b_baseline_validation=$?
readonly node_b_baseline_validation
printf '%s_phase_node_b_baseline_validation=%s\n' "$prefix" \
    "$node_b_baseline_validation"
node_a_probe_validation=0
validate_probe node-a "${probe_stdout[$node_a_key]}" \
    "${probe_stderr[$node_a_key]}" "${probe_status[$node_a_key]}" ||
    node_a_probe_validation=$?
readonly node_a_probe_validation
printf '%s_phase_node_a_probe_validation=%s\n' "$prefix" \
    "$node_a_probe_validation"
node_b_probe_validation=0
validate_probe node-b "${probe_stdout[$node_b_key]}" \
    "${probe_stderr[$node_b_key]}" "${probe_status[$node_b_key]}" ||
    node_b_probe_validation=$?
readonly node_b_probe_validation
printf '%s_phase_node_b_probe_validation=%s\n' "$prefix" \
    "$node_b_probe_validation"

run_assertion node_a_baseline_accepted test "$node_a_baseline_validation" -eq 0
run_assertion node_b_baseline_accepted test "$node_b_baseline_validation" -eq 0
run_assertion node_a_probe_accepted test "$node_a_probe_validation" -eq 0
run_assertion node_b_probe_accepted test "$node_b_probe_validation" -eq 0

node_a_probe_path=${probe_stdout[$node_a_key]}
node_b_probe_path=${probe_stdout[$node_b_key]}
readonly node_a_probe_path node_b_probe_path
node_a_health=$(extract_one action_20a_probe_value_health_status "$node_a_probe_path" || true)
node_b_health=$(extract_one action_20a_probe_value_health_status "$node_b_probe_path" || true)
node_a_before=$(extract_one action_20a_probe_value_before_state_sha256 "$node_a_probe_path" || true)
node_a_after=$(extract_one action_20a_probe_value_after_state_sha256 "$node_a_probe_path" || true)
node_b_before=$(extract_one action_20a_probe_value_before_state_sha256 "$node_b_probe_path" || true)
node_b_after=$(extract_one action_20a_probe_value_after_state_sha256 "$node_b_probe_path" || true)
node_a_dns4=$(extract_one action_20a_probe_value_dns_ipv4_vip_count "$node_a_probe_path" || true)
node_a_dns6=$(extract_one action_20a_probe_value_dns_ipv6_vip_count "$node_a_probe_path" || true)
node_b_dns4=$(extract_one action_20a_probe_value_dns_ipv4_vip_count "$node_b_probe_path" || true)
node_b_dns6=$(extract_one action_20a_probe_value_dns_ipv6_vip_count "$node_b_probe_path" || true)
node_a_caddy4=$(extract_one action_20a_probe_value_caddy_ipv4_vip_count "$node_a_probe_path" || true)
node_a_caddy6=$(extract_one action_20a_probe_value_caddy_ipv6_vip_count "$node_a_probe_path" || true)
node_b_caddy4=$(extract_one action_20a_probe_value_caddy_ipv4_vip_count "$node_b_probe_path" || true)
node_b_caddy6=$(extract_one action_20a_probe_value_caddy_ipv6_vip_count "$node_b_probe_path" || true)
readonly node_a_health node_b_health node_a_before node_a_after node_b_before node_b_after
readonly node_a_dns4 node_a_dns6 node_b_dns4 node_b_dns6
readonly node_a_caddy4 node_a_caddy6 node_b_caddy4 node_b_caddy6

run_assertion node_a_health_ready test "$node_a_health" = 0
run_assertion node_b_health_ready test "$node_b_health" = 0
run_assertion node_a_state_unchanged test -n "$node_a_before" -a \
    "$node_a_before" = "$node_a_after"
run_assertion node_b_state_unchanged test -n "$node_b_before" -a \
    "$node_b_before" = "$node_b_after"
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
run_assertion dns_ipv4_single_owner bash -c \
    '[[ "$1" =~ ^[01]$ && "$2" =~ ^[01]$ && $(($1 + $2)) -eq 1 ]]' \
    _ "$node_a_dns4" "$node_b_dns4"
# shellcheck disable=SC2016
run_assertion dns_ipv6_single_owner bash -c \
    '[[ "$1" =~ ^[01]$ && "$2" =~ ^[01]$ && $(($1 + $2)) -eq 1 ]]' \
    _ "$node_a_dns6" "$node_b_dns6"
run_assertion dns_dualstack_owner_coherent test "$node_a_dns4" = \
    "$node_a_dns6" -a "$node_b_dns4" = "$node_b_dns6"
run_assertion caddy_ipv4_absent_both test "$node_a_caddy4" = 0 -a \
    "$node_b_caddy4" = 0
run_assertion caddy_ipv6_absent_both test "$node_a_caddy6" = 0 -a \
    "$node_b_caddy6" = 0
node_a_priority=$(extract_one action_20a_probe_value_priority "$node_a_probe_path" || true)
node_b_priority=$(extract_one action_20a_probe_value_priority "$node_b_probe_path" || true)
readonly node_a_priority node_b_priority
run_assertion priorities_exact test "$node_a_priority" = 140 -a \
    "$node_b_priority" = 100
# shellcheck disable=SC2016
run_assertion vrids_exact bash -c \
    '[[ "$1" = 110 && "$2" = 111 && "$3" = 110 && "$4" = 111 ]]' \
    _ \
    "$(extract_one action_20a_probe_value_ipv4_vrid "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv6_vrid "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv4_vrid "$node_b_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv6_vrid "$node_b_probe_path" || true)"
# shellcheck disable=SC2016
run_assertion ipv4_peers_reciprocal bash -c \
    '[[ "$1" = "$4" && "$2" = "$3" ]]' _ \
    "$(extract_one action_20a_probe_value_ipv4_source "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv4_peer "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv4_source "$node_b_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv4_peer "$node_b_probe_path" || true)"
# shellcheck disable=SC2016
run_assertion ipv6_peers_reciprocal bash -c \
    '[[ "$1" = "$4" && "$2" = "$3" ]]' _ \
    "$(extract_one action_20a_probe_value_ipv6_source "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv6_peer "$node_a_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv6_source "$node_b_probe_path" || true)" \
    "$(extract_one action_20a_probe_value_ipv6_peer "$node_b_probe_path" || true)"
# shellcheck disable=SC2016
run_assertion main_inclusion_prerequisites bash -c \
    'for transcript in "$1" "$2"; do for label in main_configuration_excludes_fragment main_configuration_caddy_names_clear main_configuration_vrids_clear main_configuration_terminal_newline main_hash_matches_backup; do grep -Fqx "action_20a_probe_assertion_${label}=true" "$transcript" || exit 1; done; done' \
    _ "$node_a_probe_path" "$node_b_probe_path"
# shellcheck disable=SC2016
run_assertion notification_helpers_not_invoked bash -c \
    'grep -Fqx action_20a_probe_notification_helper_invoked=false "$1" && grep -Fqx action_20a_probe_notification_helper_invoked=false "$2"' \
    _ "$node_a_probe_path" "$node_b_probe_path"

overall_expected_count=$(expected_assertions | wc -l)
readonly overall_expected_count
printf '%s_value_expected_assertion_count=%s\n' "$prefix" "$overall_expected_count"
printf '%s_value_dns_ipv4_owner_node_a=%s\n' "$prefix" "$node_a_dns4"
printf '%s_value_dns_ipv4_owner_node_b=%s\n' "$prefix" "$node_b_dns4"
printf '%s_value_dns_ipv6_owner_node_a=%s\n' "$prefix" "$node_a_dns6"
printf '%s_value_dns_ipv6_owner_node_b=%s\n' "$prefix" "$node_b_dns6"
printf '%s_assertion_count=%s\n' "$prefix" "$overall_expected_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_health_helpers_invoked=true\n' "$prefix"
printf '%s_notification_helpers_invoked=false\n' "$prefix"
printf '%s_node_to_node_connections=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_activation=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then
    printf '%s_readiness=ready_for_separately_authorized_action20_activation_design\n' \
        "$prefix"
else
    printf '%s_readiness=prerequisites_required_before_action20_activation\n' \
        "$prefix"
fi
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_cleanup_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
