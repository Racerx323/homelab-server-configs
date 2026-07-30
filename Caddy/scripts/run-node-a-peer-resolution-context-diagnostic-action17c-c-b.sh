#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly diagnostic_sha256=908eecb096ba3349fa8f7e77221906a600d0c4efe6d1bca7df160543cb0e7a8d
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly -a context_labels=(administrative root caddy_sync)
readonly -a context_identities=(pi root caddy-sync)
readonly -a databases=(ahostsv4 ahostsv6)

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly diagnostic="$script_dir/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"

verify_artifact_content() {
    local path=$1
    local expected_hash=$2

    [[ -f "$path" && ! -L "$path" ]]
    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected_hash" ]]
    bash -n "$path"
}

verify_artifact() {
    local path=$1
    local expected_hash=$2

    verify_artifact_content "$path" "$expected_hash"
    [[ "$(stat -c '%U:%G:%a' "$path")" == aaron:aaron:755 ]]
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

validate_boolean() {
    local prefix=$1
    local transcript=$2
    local value

    value=$(value_for "$prefix" "$transcript") || return 1
    [[ "$value" == true || "$value" == false ]]
}

validate_state_record() {
    local label=$1
    local transcript=$2
    local status state_hash stderr_hash

    status=$(value_for "${label}_state_status" "$transcript") || return 1
    state_hash=$(value_for "${label}_state_sha256" "$transcript") || return 1
    stderr_hash=$(value_for "${label}_state_stderr_sha256" "$transcript") ||
        return 1
    [[ "$status" == 0 ]]
    [[ "$state_hash" =~ ^[0-9a-f]{64}$ ]]
    [[ "$stderr_hash" =~ ^[0-9a-f]{64}$ ]]
}

validate_lookup() {
    local label=$1
    local database=$2
    local transcript=$3
    local status class present line_count

    status=$(value_for "${label}_${database}_status" "$transcript") ||
        return 1
    class=$(value_for "${label}_${database}_class" "$transcript") ||
        return 1
    present=$(
        value_for "${label}_${database}_expected_address_present" "$transcript"
    ) || return 1
    line_count=$(
        value_for "${label}_${database}_output_line_count" "$transcript"
    ) || return 1

    [[ "$status" =~ ^[0-9]{1,3}$ ]]
    [[ "$class" =~ ^(resolved_expected|resolved_unexpected|not_found|timed_out|permission_denied|command_failed)$ ]]
    [[ "$present" == true || "$present" == false ]]
    [[ "$line_count" =~ ^[0-9]{1,3}$ ]]
    validate_boolean "${label}_${database}_output_truncated" "$transcript" ||
        return 1
    [[ "$(value_for "${label}_${database}_address_set_b64" "$transcript")" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
    [[ "$(value_for "${label}_${database}_stdout_sha256" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    [[ "$(value_for "${label}_${database}_stderr_sha256" "$transcript")" =~ ^[0-9a-f]{64}$ ]]

    case "$class" in
        resolved_expected)
            [[ "$status" -eq 0 && "$present" == true ]]
            ;;
        resolved_unexpected)
            [[ "$status" -eq 0 && "$present" == false ]]
            ;;
        not_found)
            [[ "$status" -eq 2 && "$present" == false ]]
            ;;
        timed_out)
            [[ "$status" -eq 124 && "$present" == false ]]
            ;;
        permission_denied | command_failed)
            [[ "$status" -ne 0 ]]
            ;;
    esac
}

validate_transcript() {
    local transcript=$1
    local marker label database index
    local nameserver_count observed_nameserver_count

    for marker in \
        prestate_root_identity=true \
        prestate_working_directory=true \
        prestate_hostname=true \
        prestate_architecture=true \
        prestate_context_users_present=true \
        prestate_environment_values=true \
        prestate_resolver_files_readable=true \
        action_17c_c_b_prestate_collection_complete=true \
        action_17c_c_b_resolver_provenance_complete=true \
        action_17c_c_b_context_collection_complete=true \
        node_a_resolver_state_unchanged=true \
        peer_ssh_invoked=false \
        rsync_invoked=false \
        release_payload_transferred=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_b_node_a_cleanup_complete=true \
        action_17c_c_b_node_a_diagnostic_complete=true; do
        require_one "$marker" "$transcript" || return 1
    done

    validate_state_record before "$transcript" || return 1
    validate_state_record after "$transcript" || return 1
    validate_boolean resolv_conf_is_symlink "$transcript" || return 1
    for prefix in \
        resolv_conf_link_target_b64 \
        resolv_conf_canonical_target_b64 \
        nsswitch_hosts_line_b64; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[A-Za-z0-9+/]*={0,2}$ ]]
    done
    for prefix in \
        resolv_conf_sha256 \
        nsswitch_conf_sha256 \
        hosts_file_sha256; do
        [[ "$(value_for "$prefix" "$transcript")" =~ ^[0-9a-f]{64}$ ]]
    done
    validate_boolean hosts_file_peer_ipv4_present "$transcript" || return 1
    validate_boolean hosts_file_peer_ipv6_present "$transcript" || return 1

    nameserver_count=$(value_for resolver_nameserver_count "$transcript") ||
        return 1
    [[ "$nameserver_count" =~ ^[0-9]{1,2}$ ]]
    observed_nameserver_count=$(
        grep -Ec '^resolver_nameserver=' "$transcript" || true
    )
    [[ "$observed_nameserver_count" -eq "$nameserver_count" ]]
    if [[ "$observed_nameserver_count" -gt 0 ]]; then
        if grep -Evq \
            '^resolver_nameserver=[0-9A-Fa-f:.%]+$' \
            < <(grep -E '^resolver_nameserver=' "$transcript"); then
            return 1
        fi
    fi

    for index in "${!context_labels[@]}"; do
        label=${context_labels[$index]}
        require_one \
            "${label}_identity=${context_identities[$index]}" \
            "$transcript" || return 1
        for database in "${databases[@]}"; do
            validate_lookup "$label" "$database" "$transcript" || return 1
        done
    done
}

derive_conclusion() {
    local transcript=$1
    local admin_v4 root_v4 sync_v4 admin_v6 root_v6 sync_v6

    admin_v4=$(value_for administrative_ahostsv4_class "$transcript")
    root_v4=$(value_for root_ahostsv4_class "$transcript")
    sync_v4=$(value_for caddy_sync_ahostsv4_class "$transcript")
    admin_v6=$(value_for administrative_ahostsv6_class "$transcript")
    root_v6=$(value_for root_ahostsv6_class "$transcript")
    sync_v6=$(value_for caddy_sync_ahostsv6_class "$transcript")

    if [[ "$admin_v4" == resolved_expected &&
        "$root_v4" == resolved_expected &&
        "$sync_v4" == resolved_expected &&
        "$admin_v6" == resolved_expected &&
        "$root_v6" == resolved_expected &&
        "$sync_v6" == resolved_expected ]]; then
        printf 'all_contexts_resolve_expected_dual_stack\n'
    elif [[ "$admin_v4" == "$root_v4" &&
        "$admin_v6" == "$root_v6" ]] &&
        [[ "$sync_v4" != "$admin_v4" || "$sync_v6" != "$admin_v6" ]]; then
        printf 'caddy_sync_context_differs\n'
    elif [[ "$admin_v4" == "$root_v4" &&
        "$root_v4" == "$sync_v4" &&
        "$admin_v6" == "$root_v6" &&
        "$root_v6" == "$sync_v6" ]]; then
        printf 'all_contexts_match_non_success\n'
    else
        printf 'resolution_contexts_differ\n'
    fi
}

validate_secret_free() {
    ! grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$@"
}

write_lookup_fixture() {
    local label=$1
    local database=$2
    local class=$3
    local destination=$4
    local status present line_count
    local empty_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

    case "$class" in
        resolved_expected)
            status=0
            present=true
            line_count=3
            ;;
        not_found)
            status=2
            present=false
            line_count=0
            ;;
        *)
            printf 'Unsupported fixture class: %s\n' "$class" >&2
            exit 1
            ;;
    esac
    printf '%s\n' \
        "${label}_${database}_status=$status" \
        "${label}_${database}_class=$class" \
        "${label}_${database}_expected_address_present=$present" \
        "${label}_${database}_output_line_count=$line_count" \
        "${label}_${database}_output_truncated=false" \
        "${label}_${database}_address_set_b64=MTAuMS4wLjU0" \
        "${label}_${database}_stdout_sha256=$empty_hash" \
        "${label}_${database}_stderr_sha256=$empty_hash" >>"$destination"
}

write_fixture() {
    local destination=$1
    local label database index class
    local empty_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

    printf '%s\n' \
        prestate_root_identity=true \
        prestate_working_directory=true \
        prestate_hostname=true \
        prestate_architecture=true \
        prestate_context_users_present=true \
        prestate_environment_values=true \
        prestate_resolver_files_readable=true \
        before_state_status=0 \
        before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        "before_state_stderr_sha256=$empty_hash" \
        action_17c_c_b_prestate_collection_complete=true \
        resolv_conf_is_symlink=true \
        resolv_conf_link_target_b64=Li4vcnVuL3Jlc29sdi5jb25m \
        resolv_conf_canonical_target_b64=L3J1bi9yZXNvbHYuY29uZg== \
        resolv_conf_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
        nsswitch_conf_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
        hosts_file_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
        nsswitch_hosts_line_b64=aG9zdHM6IGZpbGVzIGRucw== \
        resolver_nameserver_count=1 \
        resolver_nameserver=127.0.0.1 \
        hosts_file_peer_ipv4_present=false \
        hosts_file_peer_ipv6_present=false \
        action_17c_c_b_resolver_provenance_complete=true >"$destination"

    for index in "${!context_labels[@]}"; do
        label=${context_labels[$index]}
        printf '%s_identity=%s\n' \
            "$label" "${context_identities[$index]}" >>"$destination"
        for database in "${databases[@]}"; do
            class=resolved_expected
            if [[ "$label" == caddy_sync ]]; then
                class=not_found
            fi
            write_lookup_fixture "$label" "$database" "$class" "$destination"
        done
    done
    printf '%s\n' \
        action_17c_c_b_context_collection_complete=true \
        after_state_status=0 \
        after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        "after_state_stderr_sha256=$empty_hash" \
        node_a_resolver_state_unchanged=true \
        peer_ssh_invoked=false \
        rsync_invoked=false \
        release_payload_transferred=false \
        service_mutations=false \
        persistent_mutations=false \
        action_17c_c_b_node_a_cleanup_complete=true \
        action_17c_c_b_node_a_diagnostic_complete=true >>"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$diagnostic_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_a_target" == pi@10.1.0.53 ]]
    verify_artifact_content "$diagnostic" "$diagnostic_sha256"
    "$diagnostic" --self-test >/dev/null
    printf 'action_17c_c_b_diagnostic_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    test_dir=$(mktemp -d /tmp/caddy-action17c-c-b-contract.XXXXXX)
    trap 'rm -rf -- "$test_dir"' EXIT
    write_fixture "$test_dir/success"
    validate_transcript "$test_dir/success"
    [[ "$(derive_conclusion "$test_dir/success")" == caddy_sync_context_differs ]]
    validate_secret_free "$test_dir/success"
    cp -- "$test_dir/success" "$test_dir/duplicate"
    printf 'root_ahostsv6_status=0\n' >>"$test_dir/duplicate"
    if validate_transcript "$test_dir/duplicate"; then
        printf 'Duplicate lookup record was accepted.\n' >&2
        exit 1
    fi
    sed \
        's/caddy_sync_ahostsv6_status=2/caddy_sync_ahostsv6_status=0/' \
        "$test_dir/success" >"$test_dir/inconsistent"
    if validate_transcript "$test_dir/inconsistent"; then
        printf 'Inconsistent lookup classification was accepted.\n' >&2
        exit 1
    fi
    printf 'action_17c_c_b_diagnostic_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_artifact "$diagnostic" "$diagnostic_sha256"
work_dir=$(mktemp -d /tmp/caddy-action17c-c-b-runner.XXXXXX)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

ssh_status=0
ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o "HostKeyAlias=$node_a_host_alias" \
    -o StrictHostKeyChecking=yes \
    "$node_a_target" \
    "sudo -n /bin/bash -c 'cd / && exec /bin/bash -s --'" \
    <"$diagnostic" >"$work_dir/node-a.out" 2>"$work_dir/node-a.err" ||
    ssh_status=$?

cat "$work_dir/node-a.out"
cat "$work_dir/node-a.err" >&2
printf 'node_a_administrative_ssh_status=%s\n' "$ssh_status"

if [[ "$ssh_status" -ne 0 ||
    -s "$work_dir/node-a.err" ]] ||
    ! validate_transcript "$work_dir/node-a.out" ||
    ! validate_secret_free "$work_dir/node-a.out" "$work_dir/node-a.err"; then
    printf 'Action 17c-c-b diagnostic evidence is incomplete.\n' >&2
    exit 97
fi

printf 'action_17c_c_b_diagnostic_conclusion=%s\n' \
    "$(derive_conclusion "$work_dir/node-a.out")"
printf 'action_17c_c_b_diagnostic_accepted=true\n'

cleanup
trap - EXIT
[[ ! -e "$work_dir" && ! -L "$work_dir" ]]
printf 'action_17c_c_b_local_cleanup_complete=true\n'
