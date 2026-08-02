#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n.sh"
readonly historical_driver_sha256=7b24de1f46fd9fc04a0aec2819e3c0c7f728cef265720c4a1df3c93389c81990
readonly driver="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-retry.sh"
readonly runner="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"
readonly -a readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

extract_function() {
    local extraction_name=$1
    local extraction_source=$2

    sed -n "/^${extraction_name}()/,/^}/p" "$extraction_source"
}

write_success_transcript() {
    local fixture_path=$1
    local fixture_key

    {
        printf 'action_17n_retry_acceptance=true\n'
        printf 'action_17n_retry_manifest_action=17n\n'
        printf 'action_17n_retry_resolv_conf_mutation=false\n'
        printf 'action_17n_retry_peer_connections=false\n'
        printf 'action_17n_retry_synchronization_executed=false\n'
        printf 'action_17n_retry_service_restart=false\n'
        for fixture_key in "${readiness_keys[@]}"; do
            printf 'action_17n_retry_check_readiness_%s_command_status=true\n' \
                "$fixture_key"
            printf 'action_17n_retry_check_readiness_%s_answer_safe=true\n' \
                "$fixture_key"
            printf 'action_17n_retry_check_readiness_%s_answer_exact=true\n' \
                "$fixture_key"
            printf 'action_17n_retry_value_readiness_%s_answer=fd36:5aa8:6971:1::54\n' \
                "$fixture_key"
            printf 'action_17n_retry_value_readiness_%s_iteration=1\n' \
                "$fixture_key"
        done
    } >"$fixture_path"
}

run_readiness_function_regression() {
    local function_fixture=$1
    local transcript_fixture=$2
    local function_status

    {
        extract_function record_readiness_equal "$driver"
        extract_function validate_readiness_results "$driver"
    } >"$function_fixture"

    set +e
    bash -s >"$transcript_fixture" 2>&1 <<EOF
set -euo pipefail
readiness_failure_count=0
pass_check() {
    printf 'action_17n_retry_check_%s=true\n' "\$1"
}
$(<"$function_fixture")
keys=(one two three four five six)
declare -A statuses answers safeties expected iterations
for key in "\${keys[@]}"; do
    statuses[\$key]=0
    answers[\$key]=expected
    safeties[\$key]=true
    expected[\$key]=expected
    iterations[\$key]=1
done
statuses[one]=9
answers[one]=unexpected
safeties[one]=false
validate_readiness_results \
    statuses answers safeties expected iterations keys
EOF
    function_status=$?
    set -e

    [[ "$function_status" -eq 1 ]]
    [[ "$(grep -Ec '^action_17n_retry_check_readiness_[a-z0-9_]+=(true|false)$' \
        "$transcript_fixture")" -eq 18 ]]
    [[ "$(grep -Ec '^action_17n_retry_check_readiness_[a-z0-9_]+=false$' \
        "$transcript_fixture")" -eq 3 ]]
    grep -Fqx \
        'action_17n_retry_check_readiness_one_command_status=false' \
        "$transcript_fixture"
    grep -Fqx \
        'action_17n_retry_check_readiness_one_answer_safe=false' \
        "$transcript_fixture"
    grep -Fqx \
        'action_17n_retry_check_readiness_one_answer_exact=false' \
        "$transcript_fixture"
    grep -Fqx \
        'action_17n_retry_check_readiness_six_answer_exact=true' \
        "$transcript_fixture"
}

run_runner_transcript_regression() {
    local function_fixture=$1
    local transcript_fixture=$2
    local duplicate_fixture=$3

    extract_function validate_success_transcript "$runner" >"$function_fixture"
    write_success_transcript "$transcript_fixture"
    bash -s "$transcript_fixture" <<EOF
set -euo pipefail
readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)
$(<"$function_fixture")
validate_success_transcript "\$1"
EOF

    cp -- "$transcript_fixture" "$duplicate_fixture"
    printf '%s\n' \
        'action_17n_retry_check_readiness_direct_unbound_peer_aaaa_command_status=true' \
        >>"$duplicate_fixture"
    if bash -s "$duplicate_fixture" <<EOF; then
set -euo pipefail
readiness_keys=(
    direct_unbound_peer_aaaa
    direct_unbound_node_a_aaaa
    direct_unbound_peer_ptr6
    local_pihole_peer_aaaa
    local_pihole_node_a_aaaa
    local_pihole_peer_ptr6
)
$(<"$function_fixture")
validate_success_transcript "\$1"
EOF
        printf 'Runner accepted a duplicate readiness assertion.\n' >&2
        exit 1
    fi
}

run_regression() {
    local regression_key
    local test_dir

    bash -n "$historical_driver" "$driver" "$runner"
    [[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
    "$driver" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --source-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$collision_checker" "$driver" "$runner" >/dev/null

    [[ "$(grep -Fxc "    printf 'action=17n\\n'" "$driver")" -eq 1 ]]
    [[ "$(grep -Fxc "    printf 'action=17m\\n'" "$driver" || true)" -eq 0 ]]
    [[ "$(grep -Fxc "    printf 'action=17m\\n'" \
        "$historical_driver")" -eq 1 ]]
    grep -Fq \
        'readonly backup_dir=/var/backups/caddy-ha/action17n-retry-node-a-dns-nss' \
        "$driver"
    grep -Fq \
        'readonly prior_backup_dir=/var/backups/caddy-ha/action17n-node-a-dns-nss' \
        "$driver"
    grep -Fq \
        'readonly local_zone_transaction=/etc/unbound/unbound.conf.d/.pihole-local-zone.conf.action17n-retry.new' \
        "$driver"
    grep -Fq \
        'readonly hosts_transaction=/etc/.hosts.action17n-retry.new' "$driver"
    grep -Fq 'prior_backup_manifest_action' "$driver"
    grep -Fq 'final_prior_backup_manifest_hash' "$driver"
    grep -Fq '# DNS_READINESS_BLOCK_BEGIN' "$driver"
    grep -Fq '# DNS_READINESS_BLOCK_END' "$driver"
    grep -Fq 'readonly readiness_timeout_seconds=20' "$driver"
    grep -Fq \
        "readiness_deadline=\$((SECONDS + readiness_timeout_seconds))" "$driver"
    [[ "$(grep -Fxc \
        "            timeout 2 dig +time=1 +tries=1 +short \\" \
        "$driver")" -eq 2 ]]

    for regression_key in "${readiness_keys[@]}"; do
        grep -Fq "$regression_key" "$driver"
        grep -Fq \
            "\"readiness_\${readiness_key}_command_status\"" "$driver"
        grep -Fq \
            "\"readiness_\${readiness_key}_answer_safe\"" "$driver"
        grep -Fq \
            "\"readiness_\${readiness_key}_answer_exact\"" "$driver"
    done
    if grep -Fq 'bounded_dns_readiness' "$driver"; then
        printf 'Corrected retry contains the aggregate readiness gate.\n' >&2
        exit 1
    fi
    if grep -Fq '/etc/resolv.conf' "$driver" "$runner"; then
        printf 'Corrected retry reads or mutates /etc/resolv.conf.\n' >&2
        exit 1
    fi
    if grep -Eq 'systemctl[[:space:]]+(restart|start|stop)' "$driver"; then
        printf 'Corrected retry restarts a service.\n' >&2
        exit 1
    fi
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$driver" "$runner"; then
        printf 'Corrected retry contains a synchronization command.\n' >&2
        exit 1
    fi

    test_dir=$(mktemp -d)
    trap 'rm -rf -- "$test_dir"' RETURN
    run_readiness_function_regression \
        "$test_dir/readiness-functions.sh" "$test_dir/readiness-transcript"
    run_runner_transcript_regression \
        "$test_dir/runner-function.sh" \
        "$test_dir/success-transcript" \
        "$test_dir/duplicate-transcript"

    printf 'action_17n_retry_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
