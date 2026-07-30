#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly inspector_sha256=1193632a867b4a86fd28f4b932b809926498b0b6a2e4751e8ee1f69c5da05ae8
readonly node_a_host_alias=pihole0.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_b_host_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly inspector="$script_dir/inspect-sync-readiness-before-action17.sh"

verify_inspector() {
    [[ -f "$inspector" && ! -L "$inspector" ]]
    [[ "$(stat -c '%U:%G:%a' "$inspector")" == aaron:aaron:755 ]]
    [[ "$(sha256sum "$inspector" | awk '{ print $1 }')" == "$inspector_sha256" ]]
    bash -n "$inspector"
}

require_one_fixed() {
    local value=$1
    local transcript=$2

    [[ "$(grep -Fxc "$value" "$transcript")" -eq 1 ]]
}

require_one_regex() {
    local expression=$1
    local transcript=$2

    [[ "$(grep -Ec "$expression" "$transcript")" -eq 1 ]]
}

validate_transcript() {
    local node_role=$1
    local transcript=$2
    local error_file=$3
    local remote_status=$4
    local check_count true_count mismatch_count first_failure readiness_valid

    [[ "$remote_status" -eq 0 || "$remote_status" -eq 1 ]] || return 97
    [[ ! -s "$error_file" ]] || return 97
    if grep -Eq \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN' \
        "$transcript" "$error_file"; then
        return 97
    fi
    if LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$transcript" "$error_file" >/dev/null; then
        return 97
    fi

    for marker in \
        action_17_readiness_remote_reached=true \
        "readiness_node_role=$node_role" \
        action_17_readiness_inspection_complete=true \
        peer_connections=false \
        synchronization_commands_executed=false \
        installed_helper_execution=false \
        service_mutations=false \
        filesystem_mutations=false; do
        require_one_fixed "$marker" "$transcript" || return 97
    done
    for field in \
        package_lsyncd \
        package_rsync \
        package_openssh_client \
        package_openssh_server \
        expected_peer_role \
        expected_peer_ip \
        readiness_check_count \
        readiness_true_check_count \
        readiness_mismatch_count \
        readiness_first_failure; do
        [[ "$(grep -c "^${field}=" "$transcript")" -eq 1 ]] || return 97
    done
    require_one_regex '^package_lsyncd=[^[:space:]]+$' "$transcript" ||
        return 97
    require_one_regex '^package_rsync=[^[:space:]]+$' "$transcript" ||
        return 97
    require_one_regex '^package_openssh_client=[^[:space:]]+$' "$transcript" ||
        return 97
    require_one_regex '^package_openssh_server=[^[:space:]]+$' "$transcript" ||
        return 97
    require_one_regex '^readiness_check_count=[1-9][0-9]*$' "$transcript" ||
        return 97
    require_one_regex \
        '^readiness_true_check_count=[0-9]+$' "$transcript" || return 97
    require_one_regex '^readiness_mismatch_count=[0-9]+$' "$transcript" ||
        return 97
    require_one_regex \
        '^readiness_first_failure=(none|[a-z0-9_]+)$' "$transcript" ||
        return 97
    require_one_regex \
        "^action_17_${node_role//-/_}_readiness_valid=(true|false)$" \
        "$transcript" || return 97

    check_count=$(sed -n 's/^readiness_check_count=//p' "$transcript")
    true_count=$(
        sed -n 's/^readiness_true_check_count=//p' "$transcript"
    )
    mismatch_count=$(
        sed -n 's/^readiness_mismatch_count=//p' "$transcript"
    )
    first_failure=$(
        sed -n 's/^readiness_first_failure=//p' "$transcript"
    )
    readiness_valid=$(
        sed -n \
            "s/^action_17_${node_role//-/_}_readiness_valid=//p" \
            "$transcript"
    )
    [[ "$((true_count + mismatch_count))" -eq "$check_count" ]] ||
        return 97
    [[ "$(grep -c '^check_[a-zA-Z0-9_]*=true$' "$transcript")" -eq "$true_count" ]] || return 97
    [[ "$(grep -c '^check_[a-zA-Z0-9_]*=false$' "$transcript")" -eq "$mismatch_count" ]] || return 97

    if [[ "$mismatch_count" -eq 0 ]]; then
        [[ "$first_failure" == none &&
            "$readiness_valid" == true &&
            "$remote_status" -eq 0 ]] || return 97
        return 0
    fi
    [[ "$first_failure" != none &&
        "$readiness_valid" == false &&
        "$remote_status" -eq 1 ]] || return 97
    return 1
}

write_contract_transcript() {
    local node_role=$1
    local mismatch_count=$2
    local destination=$3
    local expected_peer_role expected_peer_ip valid first_failure

    if [[ "$node_role" == node-a ]]; then
        expected_peer_role=node-b
        expected_peer_ip=10.1.0.54
    else
        expected_peer_role=node-a
        expected_peer_ip=10.1.0.53
    fi
    if [[ "$mismatch_count" -eq 0 ]]; then
        valid=true
        first_failure=none
    else
        valid=false
        first_failure=authorized_keys_absent
    fi
    {
        printf '%s\n' \
            action_17_readiness_remote_reached=true \
            "readiness_node_role=$node_role" \
            check_identity=true \
            "check_authorized_keys_absent=$(
                [[ "$mismatch_count" -eq 0 ]] && printf true || printf false
            )" \
            package_lsyncd=2.2.3-1 \
            package_rsync=3.2.7-1+deb12u6 \
            package_openssh_client=1:9.2p1-2+deb12u10 \
            package_openssh_server=1:9.2p1-2+deb12u10 \
            "expected_peer_role=$expected_peer_role" \
            "expected_peer_ip=$expected_peer_ip" \
            readiness_check_count=2 \
            "readiness_true_check_count=$((2 - mismatch_count))" \
            "readiness_mismatch_count=$mismatch_count" \
            "readiness_first_failure=$first_failure" \
            peer_connections=false \
            synchronization_commands_executed=false \
            installed_helper_execution=false \
            service_mutations=false \
            filesystem_mutations=false \
            "action_17_${node_role//-/_}_readiness_valid=$valid" \
            action_17_readiness_inspection_complete=true
    } >"$destination"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$node_a_target" == pi@10.1.0.53 ]]
    [[ "$node_b_target" == pi@10.1.0.54 ]]
    verify_inspector
    "$inspector" --self-test >/dev/null
    printf 'action_17_readiness_runner_self_test_complete=true\n'
    exit 0
elif [[ "${1:-}" == --contract-test && $# -eq 1 ]]; then
    contract_dir=$(mktemp -d /tmp/caddy-action17-readiness-contract.XXXXXX)
    trap 'rm -rf -- "$contract_dir"' EXIT
    error_file=$contract_dir/error
    : >"$error_file"
    for node_role in node-a node-b; do
        success=$contract_dir/$node_role-success
        mismatch=$contract_dir/$node_role-mismatch
        write_contract_transcript "$node_role" 0 "$success"
        validate_transcript "$node_role" "$success" "$error_file" 0
        write_contract_transcript "$node_role" 1 "$mismatch"
        if validate_transcript "$node_role" "$mismatch" "$error_file" 1; then
            printf 'Readiness mismatch was accepted for %s.\n' \
                "$node_role" >&2
            exit 1
        elif [[ "$?" -ne 1 ]]; then
            printf 'Readiness mismatch contract was malformed for %s.\n' \
                "$node_role" >&2
            exit 1
        fi
        duplicate=$contract_dir/$node_role-duplicate
        cp -- "$success" "$duplicate"
        printf 'readiness_node_role=%s\n' "$node_role" >>"$duplicate"
        if validate_transcript \
            "$node_role" "$duplicate" "$error_file" 0; then
            printf 'Duplicate readiness record was accepted.\n' >&2
            exit 1
        fi
        secret=$contract_dir/$node_role-secret
        cp -- "$success" "$secret"
        printf '%s\n' '-----BEGIN PRIVATE KEY-----' >>"$secret"
        if validate_transcript "$node_role" "$secret" "$error_file" 0; then
            printf 'Secret-bearing readiness output was accepted.\n' >&2
            exit 1
        fi
    done
    printf 'action_17_readiness_runner_contract_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--contract-test]\n' "${0##*/}" >&2
    exit 2
fi

verify_inspector
work_dir=$(mktemp -d /tmp/caddy-action17-readiness.XXXXXX)
readonly work_dir

cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

finish() {
    local status=$1

    cleanup
    trap - EXIT
    if [[ -e "$work_dir" || -L "$work_dir" ]]; then
        printf 'action_17_readiness_local_cleanup_complete=false\n' >&2
        exit 97
    fi
    printf 'action_17_readiness_local_cleanup_complete=true\n'
    exit "$status"
}

overall_status=0
for node_role in node-a node-b; do
    if [[ "$node_role" == node-a ]]; then
        host_alias=$node_a_host_alias
        target=$node_a_target
    else
        host_alias=$node_b_host_alias
        target=$node_b_target
    fi
    output=$work_dir/$node_role.out
    error_file=$work_dir/$node_role.err
    remote_status=0
    ssh -T \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o "HostKeyAlias=$host_alias" \
        -o StrictHostKeyChecking=yes \
        "$target" \
        "sudo -n /bin/bash -s -- --node $node_role" \
        <"$inspector" >"$output" 2>"$error_file" || remote_status=$?

    cat "$output"
    cat "$error_file" >&2
    printf 'action_17_%s_ssh_exit_status=%s\n' \
        "${node_role//-/_}" "$remote_status"
    set +e
    validate_transcript "$node_role" "$output" "$error_file" "$remote_status"
    validation_status=$?
    set -e
    printf 'action_17_%s_validation_status=%s\n' \
        "${node_role//-/_}" "$validation_status"
    if [[ "$validation_status" -eq 97 ]]; then
        finish 97
    elif [[ "$validation_status" -eq 1 ]]; then
        overall_status=1
    fi
done

if [[ "$overall_status" -eq 0 ]]; then
    printf 'action_17_sync_readiness_accepted=true\n'
else
    printf 'action_17_sync_readiness_accepted=false\n'
fi
finish "$overall_status"
