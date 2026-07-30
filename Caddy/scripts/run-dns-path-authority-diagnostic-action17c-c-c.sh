#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly collector_sha256=5ef814b847151550a6c1cfa935917cc13861152f50ece55bd49b9e8ea107c364
readonly regression_sha256=f5ef1077dc627c8e35248ce439f4c01e419d02b8e431412d66e762813755d825
readonly primary_source_sha256=cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8
readonly local_zone_source_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1
readonly dns_manifest_sha256=809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22
readonly node_a_target=pi@10.1.0.53
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_host_alias=pihole00.local.theama.co
readonly -a common_query_labels=(
    local_unbound_peer_a
    local_unbound_peer_aaaa
    local_unbound_peer_ptr
    local_unbound_caddy_a
    local_unbound_caddy_ptr
    local_pihole_peer_a
)
readonly -a node_a_query_labels=(
    configured_ipv4_peer_a
    dns_vip_ipv4_peer_a
    dns_vip_ipv6_peer_a
    dns_vip_ipv4_caddy_a
)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly collector="$script_dir/diagnose-dns-path-authority-action17c-c-c.sh"
readonly regression="$caddy_root/tests/action17c-c-c-dns-path-authority-regression.sh"
readonly primary_source="$workspace_root/homelab-dns/Unbound/configs/pihole0.conf"
readonly local_zone_source="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly dns_repo="$workspace_root/homelab-dns"
readonly dns_manifest="$caddy_root/manifests/dns-records.yaml"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file_content() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(file_hash "$path")" == "$expected_hash" ]]
}

verify_executable() {
    local path=$1
    local expected_hash=$2

    verify_file_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
    bash -n "$path"
}

verify_operator_source() {
    local path=$1
    local expected_hash=$2

    verify_file_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:644 ]]
}

verify_operator_sources() {
    verify_operator_source "$primary_source" "$primary_source_sha256"
    verify_operator_source "$local_zone_source" "$local_zone_source_sha256"
    verify_operator_source "$dns_manifest" "$dns_manifest_sha256"
    git -C "$dns_repo" check-ignore -q Unbound/configs/pihole0.conf
    git -C "$dns_repo" check-ignore -q \
        Unbound/configs/pihole0-local-zone.conf
    if git -C "$dns_repo" ls-files --error-unmatch \
        Unbound/configs/pihole0.conf >/dev/null 2>&1 ||
        git -C "$dns_repo" ls-files --error-unmatch \
            Unbound/configs/pihole0-local-zone.conf >/dev/null 2>&1; then
        printf 'Private Unbound operator sources unexpectedly became tracked.\n' \
            >&2
        return 1
    fi
    [[ "$(grep -Ec '^server:$' "$primary_source")" -eq 1 ]]
    grep -Fxq '    interface: 127.0.0.1' "$primary_source"
    grep -Fxq '    interface: ::1' "$primary_source"
    grep -Fxq '    port: 5335' "$primary_source"
    [[ "$(grep -Ec '^server:$' "$local_zone_source")" -eq 1 ]]
    grep -Fxq '    local-zone: "local.theama.co." static' \
        "$local_zone_source"
    grep -Fxq \
        '    local-data: "pihole00.local.theama.co. IN A 10.1.0.54"' \
        "$local_zone_source"
    grep -Fxq \
        '    local-data-ptr: "10.1.0.54 pihole00.local.theama.co."' \
        "$local_zone_source"
    if grep -Eq \
        '^[[:space:]]*local-data:[[:space:]]+"pihole00\.local\.theama\.co\.[^"]*[[:space:]]AAAA[[:space:]]' \
        "$local_zone_source"; then
        printf 'Operator local-zone source unexpectedly contains peer AAAA.\n' \
            >&2
        return 1
    fi
    if grep -Eq \
        '^[[:space:]]*local-data:[[:space:]]+"(proxy|pihole-admin)\.local\.theama\.co\.' \
        "$local_zone_source"; then
        printf 'Operator local-zone source unexpectedly contains Caddy names.\n' \
            >&2
        return 1
    fi
    grep -Fxq 'status: intended' "$dns_manifest"
    grep -Fxq 'apply_only_after: caddy_vrrp_activation_and_validation' \
        "$dns_manifest"
}

require_one() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

value_for() {
    local prefix=$1
    local transcript=$2
    local record

    [[ "$(grep -Ec "^${prefix}=" "$transcript")" -eq 1 ]] || return 1
    record=$(grep -E "^${prefix}=" "$transcript")
    printf '%s\n' "${record#*=}"
}

validate_boolean_or_unavailable() {
    local prefix=$1
    local transcript=$2
    local value

    value=$(value_for "$prefix" "$transcript") || return 1
    [[ "$value" == true || "$value" == false || "$value" == unavailable ]]
}

validate_query() {
    local label=$1
    local transcript=$2
    local value

    value=$(value_for "${label}_server" "$transcript") || return 1
    [[ "$value" =~ ^[0-9A-Fa-f:.]+$ ]]
    value=$(value_for "${label}_port" "$transcript") || return 1
    [[ "$value" =~ ^[0-9]{1,5}$ ]]
    value=$(value_for "${label}_qname" "$transcript") || return 1
    [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]]
    value=$(value_for "${label}_qtype" "$transcript") || return 1
    [[ "$value" =~ ^(A|AAAA|PTR)$ ]]
    value=$(value_for "${label}_command_status" "$transcript") || return 1
    [[ "$value" =~ ^[0-9]{1,3}$ ]]
    value=$(value_for "${label}_rcode" "$transcript") || return 1
    [[ "$value" =~ ^(NOERROR|NXDOMAIN|SERVFAIL|REFUSED|FORMERR|NOTIMP|unavailable)$ ]]
    value=$(value_for "${label}_answer_count" "$transcript") || return 1
    [[ "$value" =~ ^[0-9]{1,3}$ ]]
    value=$(value_for "${label}_expected_match" "$transcript") || return 1
    [[ "$value" == true || "$value" == false ]]
    value=$(value_for "${label}_class" "$transcript") || return 1
    [[ "$value" =~ ^(expected_present|expected_absent|expected_answer_missing|unexpected_answer|timed_out|command_failed|malformed_response)$ ]]
    [[ "$(value_for "${label}_flags_b64" "$transcript")" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
    [[ "$(value_for "${label}_answers_b64" "$transcript")" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
    [[ "$(value_for "${label}_response_sha256" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(value_for "${label}_stderr_sha256" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
}

validate_transcript() {
    local expected_role=$1
    local transcript=$2
    local marker label

    for marker in \
        action_17c_c_c_prestate_complete=true \
        action_17c_c_c_source_inspection_complete=true \
        action_17c_c_c_query_collection_complete=true \
        node_dns_state_unchanged=true \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_c_node_cleanup_complete=true \
        action_17c_c_c_node_diagnostic_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done
    require_one "node_role=$expected_role" "$transcript" || return 1
    if [[ "$expected_role" == node-a ]]; then
        require_one node_hostname=j1-svpihole0 "$transcript" || return 1
    else
        require_one node_hostname=j1-svpihole00 "$transcript" || return 1
    fi
    for prefix in before_state_status after_state_status; do
        [[ "$(value_for "$prefix" "$transcript")" == 0 ]]
    done
    for prefix in \
        before_state_sha256 \
        before_state_stderr_sha256 \
        after_state_sha256 \
        after_state_stderr_sha256; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    done
    [[ "$(value_for before_state_sha256 "$transcript")" == "$(value_for after_state_sha256 "$transcript")" ]]

    for prefix in primary_config_file_state local_zone_file_state; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^(regular|symlink|absent)$ ]]
    done
    for prefix in primary_config_file_sha256 local_zone_file_sha256; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^([0-9a-f]{64}|unavailable)$ ]]
    done
    for prefix in primary_config_file_metadata local_zone_file_metadata; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^([A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[0-7]{3,4}:[0-9]+|unavailable)$ ]]
    done
    for prefix in \
        live_primary_server_clause_present \
        live_primary_ipv4_loopback_present \
        live_primary_ipv6_loopback_present \
        live_primary_port_present \
        live_primary_contains_local_zone \
        live_static_zone_present \
        live_peer_a_present \
        live_peer_aaaa_absent \
        live_peer_ptr_present \
        live_caddy_names_absent \
        live_caddy_ipv4_ptr_absent \
        live_caddy_ipv6_ptr_absent; do
        validate_boolean_or_unavailable "$prefix" "$transcript" || return 1
    done
    for prefix in \
        configured_ipv4_resolver_present \
        configured_ipv6_resolver_present; do
        value_for "$prefix" "$transcript" |
            grep -Eq '^(true|false)$' || return 1
    done
    for label in "${common_query_labels[@]}"; do
        validate_query "$label" "$transcript" || return 1
    done
    if [[ "$expected_role" == node-a ]]; then
        for label in "${node_a_query_labels[@]}"; do
            validate_query "$label" "$transcript" || return 1
        done
    else
        for label in "${node_a_query_labels[@]}"; do
            if grep -Eq "^${label}_" "$transcript"; then
                return 1
            fi
        done
    fi
}

query_class() {
    local label=$1
    local transcript=$2

    value_for "${label}_class" "$transcript"
}

derive_two_file_conclusion() {
    local node_a=$1
    local node_b=$2

    if [[ "$(value_for local_zone_file_state "$node_a")" == absent &&
    "$(value_for local_zone_file_state "$node_b")" == absent &&
    "$(value_for live_primary_contains_local_zone "$node_a")" == true &&
    "$(value_for live_primary_contains_local_zone "$node_b")" == true ]]; then
        printf 'legacy_single_file_unbound_configuration\n'
        return
    fi

    if [[ "$(value_for primary_config_file_sha256 "$node_a")" == "$primary_source_sha256" &&
    "$(value_for primary_config_file_sha256 "$node_b")" == "$primary_source_sha256" &&
    "$(value_for local_zone_file_sha256 "$node_a")" == "$local_zone_source_sha256" &&
    "$(value_for local_zone_file_sha256 "$node_b")" == "$local_zone_source_sha256" ]]; then
        printf 'two_file_unbound_prerequisite_converged\n'
    else
        printf 'two_file_unbound_prerequisite_not_converged\n'
    fi
}

derive_path_conclusion() {
    local node_a=$1
    local node_b=$2
    local label
    local two_file_conclusion

    two_file_conclusion=$(derive_two_file_conclusion "$node_a" "$node_b")
    if [[ "$two_file_conclusion" != two_file_unbound_prerequisite_converged ]]; then
        printf '%s\n' "$two_file_conclusion"
        return
    fi
    for label in \
        local_unbound_peer_a \
        local_unbound_peer_ptr; do
        if [[ "$(query_class "$label" "$node_a")" != expected_present ||
        "$(query_class "$label" "$node_b")" != expected_present ]]; then
            printf 'unbound_authority_positive_control_failure\n'
            return
        fi
    done
    for label in \
        local_unbound_peer_aaaa \
        local_unbound_caddy_a \
        local_unbound_caddy_ptr; do
        if [[ "$(query_class "$label" "$node_a")" != expected_absent ||
        "$(query_class "$label" "$node_b")" != expected_absent ]]; then
            printf 'unbound_authority_expected_absence_mismatch\n'
            return
        fi
    done
    if [[ "$(query_class local_pihole_peer_a "$node_a")" != expected_present ||
    "$(query_class local_pihole_peer_a "$node_b")" != expected_present ]]; then
        printf 'local_pihole_forwarding_failure\n'
    elif [[ "$(query_class dns_vip_ipv4_peer_a "$node_a")" != expected_present ||
    "$(query_class dns_vip_ipv6_peer_a "$node_a")" != expected_present ]]; then
        printf 'dns_vip_path_failure\n'
    elif [[ "$(query_class configured_ipv4_peer_a "$node_a")" != expected_present ]]; then
        printf 'configured_ipv4_resolver_diverges\n'
    else
        printf 'ipv4_dns_path_positive_controls_pass\n'
    fi
}

derive_sync_dns_conclusion() {
    local node_a=$1
    local node_b=$2

    if [[ "$(value_for live_peer_aaaa_absent "$node_a")" == true &&
    "$(value_for live_peer_aaaa_absent "$node_b")" == true &&
    "$(query_class local_unbound_peer_aaaa "$node_a")" == expected_absent &&
    "$(query_class local_unbound_peer_aaaa "$node_b")" == expected_absent ]]; then
        printf 'peer_aaaa_not_deployed\n'
    else
        printf 'peer_aaaa_state_inconsistent\n'
    fi
}

derive_caddy_dns_conclusion() {
    local node_a=$1
    local node_b=$2

    if [[ "$(value_for live_caddy_names_absent "$node_a")" == true &&
    "$(value_for live_caddy_names_absent "$node_b")" == true &&
    "$(value_for live_caddy_ipv4_ptr_absent "$node_a")" == true &&
    "$(value_for live_caddy_ipv4_ptr_absent "$node_b")" == true &&
    "$(value_for live_caddy_ipv6_ptr_absent "$node_a")" == true &&
    "$(value_for live_caddy_ipv6_ptr_absent "$node_b")" == true &&
    "$(query_class local_unbound_caddy_a "$node_a")" == expected_absent &&
    "$(query_class local_unbound_caddy_a "$node_b")" == expected_absent &&
    "$(query_class local_unbound_caddy_ptr "$node_a")" == expected_absent &&
    "$(query_class local_unbound_caddy_ptr "$node_b")" == expected_absent ]]; then
        printf 'caddy_records_not_deployed\n'
    else
        printf 'caddy_record_state_inconsistent\n'
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_query_fixture() {
    local label=$1
    local class=$2
    local destination=$3
    local expected_match=true answer_count=1 rcode=NOERROR
    local empty_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

    if [[ "$class" == expected_absent ]]; then
        answer_count=0
        rcode=NXDOMAIN
    elif [[ "$class" == expected_answer_missing ]]; then
        answer_count=0
        expected_match=false
    fi
    printf '%s\n' \
        "${label}_server=127.0.0.1" \
        "${label}_port=53" \
        "${label}_qname=pihole00.local.theama.co" \
        "${label}_qtype=A" \
        "${label}_command_status=0" \
        "${label}_rcode=$rcode" \
        "${label}_flags_b64=cXIgYWE=" \
        "${label}_answer_count=$answer_count" \
        "${label}_answers_b64=MTAuMS4wLjU0" \
        "${label}_expected_match=$expected_match" \
        "${label}_class=$class" \
        "${label}_response_sha256=$empty_hash" \
        "${label}_stderr_sha256=$empty_hash" >>"$destination"
}

write_node_fixture() {
    local role=$1
    local destination=$2
    local hostname label class
    local state_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local empty_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

    hostname=j1-svpihole0
    [[ "$role" == node-a ]] || hostname=j1-svpihole00
    printf '%s\n' \
        action_17c_c_c_prestate_complete=true \
        "node_role=$role" \
        "node_hostname=$hostname" \
        before_state_status=0 \
        "before_state_sha256=$state_hash" \
        "before_state_stderr_sha256=$empty_hash" \
        primary_config_file_state=regular \
        "primary_config_file_sha256=$primary_source_sha256" \
        primary_config_file_metadata=root:root:644:1 \
        local_zone_file_state=regular \
        "local_zone_file_sha256=$local_zone_source_sha256" \
        local_zone_file_metadata=root:root:644:1 \
        live_primary_server_clause_present=true \
        live_primary_ipv4_loopback_present=true \
        live_primary_ipv6_loopback_present=true \
        live_primary_port_present=true \
        live_primary_contains_local_zone=false \
        live_static_zone_present=true \
        live_peer_a_present=true \
        live_peer_aaaa_absent=true \
        live_peer_ptr_present=true \
        live_caddy_names_absent=true \
        live_caddy_ipv4_ptr_absent=true \
        live_caddy_ipv6_ptr_absent=true \
        configured_ipv4_resolver_present=true \
        configured_ipv6_resolver_present=true \
        action_17c_c_c_source_inspection_complete=true >"$destination"
    for label in "${common_query_labels[@]}"; do
        class=expected_present
        case "$label" in
            local_unbound_peer_aaaa | local_unbound_caddy_a | local_unbound_caddy_ptr)
                class=expected_absent
                ;;
        esac
        write_query_fixture "$label" "$class" "$destination"
    done
    if [[ "$role" == node-a ]]; then
        for label in "${node_a_query_labels[@]}"; do
            class=expected_present
            [[ "$label" == dns_vip_ipv4_caddy_a ]] &&
                class=expected_absent
            write_query_fixture "$label" "$class" "$destination"
        done
    fi
    printf '%s\n' \
        action_17c_c_c_query_collection_complete=true \
        after_state_status=0 \
        "after_state_sha256=$state_hash" \
        "after_state_stderr_sha256=$empty_hash" \
        node_dns_state_unchanged=true \
        dns_configuration_mutations=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_c_node_cleanup_complete=true \
        action_17c_c_c_node_diagnostic_complete=true >>"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for value in \
        "$collector_sha256" \
        "$regression_sha256" \
        "$primary_source_sha256" \
        "$local_zone_source_sha256" \
        "$dns_manifest_sha256"; do
        [[ "$value" =~ ^[0-9a-f]{64}$ ]]
    done
    verify_file_content "$collector" "$collector_sha256"
    verify_file_content "$regression" "$regression_sha256"
    bash -n "$collector" "$regression"
    "$collector" --self-test >/dev/null
    printf 'action_17c_c_c_dns_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --source-test && $# -eq 1 ]]; then
    verify_operator_sources
    printf 'action_17c_c_c_dns_operator_source_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-c-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_node_fixture node-a "$test_dir/node-a"
    write_node_fixture node-b "$test_dir/node-b"
    validate_transcript node-a "$test_dir/node-a"
    validate_transcript node-b "$test_dir/node-b"
    [[ "$(derive_two_file_conclusion "$test_dir/node-a" "$test_dir/node-b")" == two_file_unbound_prerequisite_converged ]]
    [[ "$(derive_path_conclusion "$test_dir/node-a" "$test_dir/node-b")" == ipv4_dns_path_positive_controls_pass ]]
    [[ "$(derive_sync_dns_conclusion "$test_dir/node-a" "$test_dir/node-b")" == peer_aaaa_not_deployed ]]
    [[ "$(derive_caddy_dns_conclusion "$test_dir/node-a" "$test_dir/node-b")" == caddy_records_not_deployed ]]
    sed \
        -e 's/^local_zone_file_state=regular$/local_zone_file_state=absent/' \
        -e 's/^local_zone_file_sha256=.*$/local_zone_file_sha256=unavailable/' \
        -e 's/^local_zone_file_metadata=.*$/local_zone_file_metadata=unavailable/' \
        -e 's/^live_primary_contains_local_zone=false$/live_primary_contains_local_zone=true/' \
        "$test_dir/node-a" >"$test_dir/node-a-legacy"
    sed \
        -e 's/^local_zone_file_state=regular$/local_zone_file_state=absent/' \
        -e 's/^local_zone_file_sha256=.*$/local_zone_file_sha256=unavailable/' \
        -e 's/^local_zone_file_metadata=.*$/local_zone_file_metadata=unavailable/' \
        -e 's/^live_primary_contains_local_zone=false$/live_primary_contains_local_zone=true/' \
        "$test_dir/node-b" >"$test_dir/node-b-legacy"
    validate_transcript node-a "$test_dir/node-a-legacy"
    validate_transcript node-b "$test_dir/node-b-legacy"
    [[ "$(derive_two_file_conclusion \
        "$test_dir/node-a-legacy" "$test_dir/node-b-legacy")" == legacy_single_file_unbound_configuration ]]
    [[ "$(derive_path_conclusion \
        "$test_dir/node-a-legacy" "$test_dir/node-b-legacy")" == legacy_single_file_unbound_configuration ]]
    sed \
        's/configured_ipv4_peer_a_class=expected_present/configured_ipv4_peer_a_class=expected_answer_missing/' \
        "$test_dir/node-a" >"$test_dir/configured-divergence"
    validate_transcript node-a "$test_dir/configured-divergence"
    [[ "$(derive_path_conclusion \
        "$test_dir/configured-divergence" "$test_dir/node-b")" == configured_ipv4_resolver_diverges ]]
    sed \
        "s/primary_config_file_sha256=$primary_source_sha256/primary_config_file_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/" \
        "$test_dir/node-b" >"$test_dir/two-file-drift"
    validate_transcript node-b "$test_dir/two-file-drift"
    [[ "$(derive_two_file_conclusion \
        "$test_dir/node-a" "$test_dir/two-file-drift")" == two_file_unbound_prerequisite_not_converged ]]
    sed \
        -e 's/live_peer_aaaa_absent=true/live_peer_aaaa_absent=false/' \
        -e 's/local_unbound_peer_aaaa_class=expected_absent/local_unbound_peer_aaaa_class=unexpected_answer/' \
        "$test_dir/node-a" >"$test_dir/peer-aaaa-inconsistent"
    validate_transcript node-a "$test_dir/peer-aaaa-inconsistent"
    [[ "$(derive_sync_dns_conclusion \
        "$test_dir/peer-aaaa-inconsistent" "$test_dir/node-b")" == peer_aaaa_state_inconsistent ]]
    sed \
        -e 's/live_caddy_names_absent=true/live_caddy_names_absent=false/' \
        -e 's/local_unbound_caddy_a_class=expected_absent/local_unbound_caddy_a_class=unexpected_answer/' \
        "$test_dir/node-a" >"$test_dir/caddy-inconsistent"
    validate_transcript node-a "$test_dir/caddy-inconsistent"
    [[ "$(derive_caddy_dns_conclusion \
        "$test_dir/caddy-inconsistent" "$test_dir/node-b")" == caddy_record_state_inconsistent ]]
    cp -- "$test_dir/node-a" "$test_dir/duplicate"
    printf 'live_peer_a_present=true\n' >>"$test_dir/duplicate"
    if validate_transcript node-a "$test_dir/duplicate"; then
        printf 'Duplicate source assertion was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_c_dns_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
        "${0##*/}" >&2
    exit 2
fi

verify_executable "$collector" "$collector_sha256"
verify_executable "$regression" "$regression_sha256"
verify_operator_sources
work_dir=$(mktemp -d /tmp/caddy-action17c-c-c-runner.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

run_node() {
    local role=$1
    local target=$2
    local host_alias=$3
    local output=$4
    local error=$5
    local status=0

    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" \
        -o StrictHostKeyChecking=yes \
        "$target" \
        "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s -- --node $role'" \
        <"$collector" >"$output" 2>"$error" || status=$?
    printf '%s\n' "$status"
}

node_a_status=$(
    run_node node-a "$node_a_target" "$node_a_host_alias" \
        "$work_dir/node-a.out" "$work_dir/node-a.err"
)
node_b_status=$(
    run_node node-b "$node_b_target" "$node_b_host_alias" \
        "$work_dir/node-b.out" "$work_dir/node-b.err"
)
cat "$work_dir/node-a.out"
cat "$work_dir/node-b.out"
cat "$work_dir/node-a.err" >&2
cat "$work_dir/node-b.err" >&2
printf '%s\n' \
    "node_a_administrative_ssh_status=$node_a_status" \
    "node_b_administrative_ssh_status=$node_b_status" \
    "operator_primary_source_sha256=$primary_source_sha256" \
    "operator_local_zone_source_sha256=$local_zone_source_sha256" \
    operator_unbound_sources_git_state=ignored_by_repository_policy

if [[ "$node_a_status" -ne 0 || "$node_b_status" -ne 0 ]] ||
    [[ -s "$work_dir/node-a.err" || -s "$work_dir/node-b.err" ]] ||
    ! validate_transcript node-a "$work_dir/node-a.out" ||
    ! validate_transcript node-b "$work_dir/node-b.out" ||
    ! validate_secret_free \
        "$work_dir/node-a.out" "$work_dir/node-a.err" \
        "$work_dir/node-b.out" "$work_dir/node-b.err"; then
    printf 'Action 17c-c-c DNS diagnostic evidence is incomplete.\n' >&2
    exit 97
fi

printf '%s\n' \
    "action_17c_c_c_two_file_conclusion=$(derive_two_file_conclusion "$work_dir/node-a.out" "$work_dir/node-b.out")" \
    "action_17c_c_c_path_conclusion=$(derive_path_conclusion "$work_dir/node-a.out" "$work_dir/node-b.out")" \
    "action_17c_c_c_sync_dns_conclusion=$(derive_sync_dns_conclusion "$work_dir/node-a.out" "$work_dir/node-b.out")" \
    "action_17c_c_c_caddy_dns_conclusion=$(derive_caddy_dns_conclusion "$work_dir/node-a.out" "$work_dir/node-b.out")" \
    action_17c_c_c_dns_diagnostic_accepted=true

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_c_local_cleanup_complete=true\n'
