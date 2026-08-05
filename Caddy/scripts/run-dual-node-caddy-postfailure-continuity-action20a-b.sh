#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_b
readonly probe_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly probe="$script_directory/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly default_ssh_binary=/usr/bin/ssh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local inspected_stream_path=$1

    [[ "$(wc -c <"$inspected_stream_path")" -le "$maximum_stream_bytes" ]] ||
        return 1
    [[ "$(line_count "$inspected_stream_path")" -le "$maximum_stream_lines" ]] ||
        return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_stream_path" \
        >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_stream_path"
}
expected_assertions() {
    printf '%s\n' \
        node_a_remote_status_zero node_b_remote_status_zero \
        node_a_probe_contract_valid node_b_probe_contract_valid \
        node_a_role_exact node_b_role_exact \
        node_a_components_complete node_b_components_complete \
        node_a_state_unchanged node_b_state_unchanged
}
record_command() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}
emit_stream() {
    local emitted_name=$1
    local emitted_path=$2
    local emitted_safe=$3

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_name" \
        "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_name" \
        "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_name" \
        "$(file_hash "$emitted_path")"
    printf '%s_%s_classification=%s\n' "$prefix" "$emitted_name" \
        "$emitted_safe"
    if [[ "$emitted_safe" != bounded_safe ]]; then
        return 0
    fi
    if [[ ! -s "$emitted_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$emitted_name"
    cat "$emitted_path"
    printf '%s_%s_end\n' "$prefix" "$emitted_name"
}
validate_probe_transcript() {
    local transcript_path=$1
    local expected_role=$2
    local validation_root
    local expected_label
    local inspected_component
    local before_component_value
    local after_component_value
    local before_hash
    local after_hash

    validation_root=$(mktemp -d /tmp/caddy-action20ab-contract.XXXXXX) ||
        return 1
    # conditional-validator-explicit-failures-begin
    /bin/bash "$probe" --expected-assertions | LC_ALL=C sort \
        >"$validation_root/expected" || {
        rm -rf -- "$validation_root"
        return 1
    }
    sed -n 's/^action_20a_b_probe_assertion_\([a-z0-9_]*\)=true$/\1/p' \
        "$transcript_path" | LC_ALL=C sort >"$validation_root/observed" || {
        rm -rf -- "$validation_root"
        return 1
    }
    if ! cmp -s "$validation_root/expected" "$validation_root/observed"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    while IFS= read -r expected_label; do
        if [[ "$(grep -Fxc \
            "action_20a_b_probe_assertion_${expected_label}=true" \
            "$transcript_path")" -ne 1 ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done <"$validation_root/expected"
    if grep -Eq '^action_20a_b_probe_assertion_[a-z0-9_]+=false$' \
        "$transcript_path"; then
        rm -rf -- "$validation_root"
        return 1
    fi
    for required_record in \
        action_20a_b_probe_assertion_count=79 \
        action_20a_b_probe_failed_assertion_count=0 \
        action_20a_b_probe_first_failure=none \
        "action_20a_b_probe_value_node_role=$expected_role" \
        action_20a_b_probe_installed_health_helper_invoked=false \
        action_20a_b_probe_caddy_validation_invoked=false \
        action_20a_b_probe_transient_filesystem_activity=true \
        action_20a_b_probe_service_mutations=false \
        action_20a_b_probe_vrrp_mutations=false \
        action_20a_b_probe_vip_mutations=false \
        action_20a_b_probe_persistent_mutations=false \
        action_20a_b_probe_remote_cleanup_complete=true \
        action_20a_b_probe_remote_complete=true; do
        if [[ "$(grep -Fxc "$required_record" "$transcript_path")" -ne 1 ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done
    /bin/bash "$probe" --snapshot-components >"$validation_root/components" || {
        rm -rf -- "$validation_root"
        return 1
    }
    while IFS= read -r inspected_component; do
        if [[ "$(grep -Ec \
            "^action_20a_b_probe_value_before_${inspected_component}=.*$" \
            "$transcript_path")" -ne 1 ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
        if [[ "$(grep -Ec \
            "^action_20a_b_probe_value_after_${inspected_component}=.*$" \
            "$transcript_path")" -ne 1 ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
        before_component_value=$(sed -n \
            "s/^action_20a_b_probe_value_before_${inspected_component}=//p" \
            "$transcript_path")
        after_component_value=$(sed -n \
            "s/^action_20a_b_probe_value_after_${inspected_component}=//p" \
            "$transcript_path")
        if [[ "$before_component_value" != "$after_component_value" ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done <"$validation_root/components"
    before_hash=$(sed -n \
        's/^action_20a_b_probe_value_before_state_sha256=//p' \
        "$transcript_path")
    after_hash=$(sed -n \
        's/^action_20a_b_probe_value_after_state_sha256=//p' \
        "$transcript_path")
    if [[ ! "$before_hash" =~ ^[0-9a-f]{64}$ ||
        "$before_hash" != "$after_hash" ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    # conditional-validator-explicit-failures-end
    rm -rf -- "$validation_root"
}
write_contract_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_label
    local fixture_component
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_b_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        while IFS= read -r fixture_component; do
            printf 'action_20a_b_probe_value_before_%s=fixture-%s\n' \
                "$fixture_component" "$fixture_component"
            printf 'action_20a_b_probe_value_after_%s=fixture-%s\n' \
                "$fixture_component" "$fixture_component"
        done < <(/bin/bash "$probe" --snapshot-components)
        printf '%s\n' \
            "action_20a_b_probe_value_node_role=$fixture_role" \
            'action_20a_b_probe_value_dns_ipv4_vip_count=1' \
            'action_20a_b_probe_value_dns_ipv6_vip_count=1' \
            "action_20a_b_probe_value_before_state_sha256=$fixture_hash" \
            "action_20a_b_probe_value_after_state_sha256=$fixture_hash" \
            'action_20a_b_probe_assertion_count=79' \
            'action_20a_b_probe_failed_assertion_count=0' \
            'action_20a_b_probe_first_failure=none' \
            'action_20a_b_probe_installed_health_helper_invoked=false' \
            'action_20a_b_probe_caddy_validation_invoked=false' \
            'action_20a_b_probe_transient_filesystem_activity=true' \
            'action_20a_b_probe_service_mutations=false' \
            'action_20a_b_probe_vrrp_mutations=false' \
            'action_20a_b_probe_vip_mutations=false' \
            'action_20a_b_probe_persistent_mutations=false' \
            'action_20a_b_probe_remote_cleanup_complete=true' \
            'action_20a_b_probe_remote_complete=true'
    } >"$fixture_path"
}
component_record_count() {
    local counted_transcript_path=$1
    local counted_phase=$2
    local counted_component
    local matched_component_count=0

    while IFS= read -r counted_component; do
        if [[ "$(grep -Ec \
            "^action_20a_b_probe_value_${counted_phase}_${counted_component}=.*$" \
            "$counted_transcript_path")" -eq 1 ]]; then
            matched_component_count=$((matched_component_count + 1))
        fi
    done < <(/bin/bash "$probe" --snapshot-components)
    printf '%s\n' "$matched_component_count"
}
verify_sources() {
    [[ -f "$probe" && ! -L "$probe" && -x "$probe" ]] || return 1
    [[ "$(file_hash "$probe")" = "$probe_sha256" ]] || return 1
    bash -n "$probe" || return 1
    shellcheck "$probe" || return 1
    /bin/bash "$probe" --self-test >/dev/null || return 1
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        test_root=$(mktemp -d /tmp/caddy-action20ab-runner-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        write_contract_fixture "$test_root/valid" node-a
        validate_probe_transcript "$test_root/valid" node-a
        cp -- "$test_root/valid" "$test_root/invalid"
        sed -i \
            's/action_20a_b_probe_value_after_caddy_main_pid=fixture-caddy_main_pid/action_20a_b_probe_value_after_caddy_main_pid=changed/' \
            "$test_root/invalid"
        ! validate_probe_transcript "$test_root/invalid" node-a
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
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
case "$PWD" in
    /home/aaron/code/homelab-server-configs | /workspace/homelab-server-configs) ;;
    *) exit 1 ;;
esac
if [[ "${CADDY_ACTION20AB_INTERCEPTED_TEST:-}" = 1 ]]; then
    ssh_binary=${CADDY_ACTION20AB_SSH_BINARY:?}
else
    [[ -z "${CADDY_ACTION20AB_SSH_BINARY:-}" ]]
    ssh_binary=$default_ssh_binary
fi
readonly ssh_binary

work_directory=$(mktemp -d /tmp/caddy-action20ab-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly node_a_stdout=$work_directory/node-a.stdout
readonly node_a_stderr=$work_directory/node-a.stderr
readonly node_b_stdout=$work_directory/node-b.stdout
readonly node_b_stderr=$work_directory/node-b.stderr
for runner_capture in "$node_a_stdout" "$node_a_stderr" "$node_b_stdout" \
    "$node_b_stderr"; do
    : >"$runner_capture"
    chmod 0600 "$runner_capture"
done
run_probe() {
    local probed_role=$1
    local probed_address=$2
    local probed_alias=$3
    local probed_stdout=$4
    local probed_stderr=$5

    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$probed_alias" \
        "pi@$probed_address" \
        "cd / && sudo -n env -u CADDY_ACTION20AB_PRODUCTION_REGRESSION -u CADDY_ACTION20AB_FIXTURE_ROOT /bin/bash -s -- --node $probed_role" \
        <"$probe" >"$probed_stdout" 2>"$probed_stderr"
}

node_a_status=0
run_probe node-a 10.1.0.53 pihole0.local.theama.co "$node_a_stdout" \
    "$node_a_stderr" || node_a_status=$?
readonly node_a_status
node_b_status=0
run_probe node-b 10.1.0.54 pihole00.local.theama.co "$node_b_stdout" \
    "$node_b_stderr" || node_b_status=$?
readonly node_b_status
node_a_streams_safe=unsafe
if safe_stream "$node_a_stdout" && safe_stream "$node_a_stderr"; then
    node_a_streams_safe=bounded_safe
fi
readonly node_a_streams_safe
node_b_streams_safe=unsafe
if safe_stream "$node_b_stdout" && safe_stream "$node_b_stderr"; then
    node_b_streams_safe=bounded_safe
fi
readonly node_b_streams_safe
node_a_contract_status=0
validate_probe_transcript "$node_a_stdout" node-a || node_a_contract_status=$?
readonly node_a_contract_status
node_b_contract_status=0
validate_probe_transcript "$node_b_stdout" node-b || node_b_contract_status=$?
readonly node_b_contract_status

failed_count=0
first_failure=none
run_assertion() {
    local executed_assertion_label=$1

    shift
    if ! record_command "$executed_assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$executed_assertion_label
        fi
    fi
}
run_assertion node_a_remote_status_zero test "$node_a_status" -eq 0
run_assertion node_b_remote_status_zero test "$node_b_status" -eq 0
run_assertion node_a_probe_contract_valid test "$node_a_contract_status" -eq 0
run_assertion node_b_probe_contract_valid test "$node_b_contract_status" -eq 0
run_assertion node_a_role_exact grep -Fqx \
    'action_20a_b_probe_value_node_role=node-a' "$node_a_stdout"
run_assertion node_b_role_exact grep -Fqx \
    'action_20a_b_probe_value_node_role=node-b' "$node_b_stdout"
run_assertion node_a_components_complete test \
    "$(component_record_count "$node_a_stdout" before)" -eq 19
run_assertion node_b_components_complete test \
    "$(component_record_count "$node_b_stdout" before)" -eq 19
run_assertion node_a_state_unchanged grep -Fqx \
    'action_20a_b_probe_assertion_state_unchanged=true' "$node_a_stdout"
run_assertion node_b_state_unchanged grep -Fqx \
    'action_20a_b_probe_assertion_state_unchanged=true' "$node_b_stdout"

printf '%s_value_node_a_remote_status=%s\n' "$prefix" "$node_a_status"
printf '%s_value_node_b_remote_status=%s\n' "$prefix" "$node_b_status"
printf '%s_value_node_a_contract_status=%s\n' "$prefix" "$node_a_contract_status"
printf '%s_value_node_b_contract_status=%s\n' "$prefix" "$node_b_contract_status"
emit_stream node_a_stdout "$node_a_stdout" "$node_a_streams_safe"
emit_stream node_a_stderr "$node_a_stderr" "$node_a_streams_safe"
emit_stream node_b_stdout "$node_b_stdout" "$node_b_streams_safe"
emit_stream node_b_stderr "$node_b_stderr" "$node_b_streams_safe"
printf '%s_assertion_count=10\n' "$prefix"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_contact=read_only\n' "$prefix"
printf '%s_installed_health_helper_invoked=false\n' "$prefix"
printf '%s_caddy_validation_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
