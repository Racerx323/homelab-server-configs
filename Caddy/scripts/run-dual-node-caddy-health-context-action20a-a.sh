#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_a
readonly probe_sha256=68d7812760c0c663b74c4bb54ed71ec79f9ae9d102dc40511e222b6aca01aac2
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly probe="$script_directory/inspect-dual-node-caddy-health-context-action20a-a.sh"
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
        node_a_baseline_failure_reproduced node_b_baseline_failure_reproduced \
        node_a_transient_context_validates node_b_transient_context_validates \
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
    local before_hash
    local after_hash
    local baseline_status
    local transient_status

    validation_root=$(mktemp -d /tmp/caddy-action20aa-contract.XXXXXX) ||
        return 1
    # conditional-validator-explicit-failures-begin
    /bin/bash "$probe" --expected-assertions | LC_ALL=C sort \
        >"$validation_root/expected" || {
        rm -rf -- "$validation_root"
        return 1
    }
    sed -n 's/^action_20a_a_probe_assertion_\([a-z0-9_]*\)=true$/\1/p' \
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
            "action_20a_a_probe_assertion_${expected_label}=true" \
            "$transcript_path")" -ne 1 ]]; then
            rm -rf -- "$validation_root"
            return 1
        fi
    done <"$validation_root/expected"
    ! grep -Eq '^action_20a_a_probe_assertion_[a-z0-9_]+=false$' \
        "$transcript_path" || {
        rm -rf -- "$validation_root"
        return 1
    }
    grep -Fqx 'action_20a_a_probe_assertion_count=62' "$transcript_path" || {
        rm -rf -- "$validation_root"
        return 1
    }
    grep -Fqx 'action_20a_a_probe_failed_assertion_count=0' \
        "$transcript_path" || {
        rm -rf -- "$validation_root"
        return 1
    }
    grep -Fqx 'action_20a_a_probe_first_failure=none' "$transcript_path" || {
        rm -rf -- "$validation_root"
        return 1
    }
    grep -Fqx "action_20a_a_probe_value_node_role=$expected_role" \
        "$transcript_path" || {
        rm -rf -- "$validation_root"
        return 1
    }
    baseline_status=$(sed -n \
        's/^action_20a_a_probe_value_baseline_status=//p' "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    if [[ ! "$baseline_status" =~ ^[0-9]+$ || "$baseline_status" -eq 0 ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    transient_status=$(sed -n \
        's/^action_20a_a_probe_value_transient_validate_status=//p' \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    if [[ "$transient_status" != 0 ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    before_hash=$(sed -n \
        's/^action_20a_a_probe_value_before_state_sha256=//p' \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    after_hash=$(sed -n \
        's/^action_20a_a_probe_value_after_state_sha256=//p' \
        "$transcript_path") || {
        rm -rf -- "$validation_root"
        return 1
    }
    if [[ ! "$before_hash" =~ ^[0-9a-f]{64}$ ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    if [[ "$before_hash" != "$after_hash" ]]; then
        rm -rf -- "$validation_root"
        return 1
    fi
    for expected_record in \
        action_20a_a_probe_installed_health_helper_invoked=false \
        action_20a_a_probe_transient_filesystem_activity=true \
        action_20a_a_probe_service_mutations=false \
        action_20a_a_probe_vrrp_mutations=false \
        action_20a_a_probe_vip_mutations=false \
        action_20a_a_probe_persistent_mutations=false \
        action_20a_a_probe_remote_cleanup_complete=true \
        action_20a_a_probe_remote_complete=true; do
        grep -Fqx "$expected_record" "$transcript_path" || {
            rm -rf -- "$validation_root"
            return 1
        }
    done
    for expected_stream in baseline_stdout baseline_stderr transient_stdout \
        transient_stderr; do
        grep -Eq \
            "^action_20a_a_probe_value_${expected_stream}_bytes=[0-9]+$" \
            "$transcript_path" || {
            rm -rf -- "$validation_root"
            return 1
        }
        grep -Eq \
            "^action_20a_a_probe_value_${expected_stream}_lines=[0-9]+$" \
            "$transcript_path" || {
            rm -rf -- "$validation_root"
            return 1
        }
        grep -Eq \
            "^action_20a_a_probe_value_${expected_stream}_sha256=[0-9a-f]{64}$" \
            "$transcript_path" || {
            rm -rf -- "$validation_root"
            return 1
        }
        grep -Fqx \
            "action_20a_a_probe_value_${expected_stream}_classification=bounded_safe" \
            "$transcript_path" || {
            rm -rf -- "$validation_root"
            return 1
        }
    done
    # conditional-validator-explicit-failures-end
    rm -rf -- "$validation_root"
}
write_contract_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_label
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    {
        while IFS= read -r fixture_label; do
            printf 'action_20a_a_probe_assertion_%s=true\n' "$fixture_label"
        done < <(/bin/bash "$probe" --expected-assertions)
        printf '%s\n' \
            "action_20a_a_probe_value_node_role=$fixture_role" \
            'action_20a_a_probe_value_baseline_status=1' \
            'action_20a_a_probe_value_transient_validate_status=0' \
            'action_20a_a_probe_value_transient_local_pki_file_count=2' \
            "action_20a_a_probe_value_before_state_sha256=$fixture_hash" \
            "action_20a_a_probe_value_after_state_sha256=$fixture_hash"
        for fixture_stream in baseline_stdout baseline_stderr transient_stdout \
            transient_stderr; do
            printf '%s\n' \
                "action_20a_a_probe_value_${fixture_stream}_bytes=0" \
                "action_20a_a_probe_value_${fixture_stream}_lines=0" \
                "action_20a_a_probe_value_${fixture_stream}_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" \
                "action_20a_a_probe_value_${fixture_stream}_classification=bounded_safe" \
                "action_20a_a_probe_${fixture_stream}_content_secured=empty"
        done
        printf '%s\n' \
            'action_20a_a_probe_assertion_count=62' \
            'action_20a_a_probe_failed_assertion_count=0' \
            'action_20a_a_probe_first_failure=none' \
            'action_20a_a_probe_installed_health_helper_invoked=false' \
            'action_20a_a_probe_transient_filesystem_activity=true' \
            'action_20a_a_probe_service_mutations=false' \
            'action_20a_a_probe_vrrp_mutations=false' \
            'action_20a_a_probe_vip_mutations=false' \
            'action_20a_a_probe_persistent_mutations=false' \
            'action_20a_a_probe_remote_cleanup_complete=true' \
            'action_20a_a_probe_remote_complete=true'
    } >"$fixture_path"
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
        test_root=$(mktemp -d /tmp/caddy-action20aa-runner-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        write_contract_fixture "$test_root/valid" node-a
        validate_probe_transcript "$test_root/valid" node-a
        cp -- "$test_root/valid" "$test_root/invalid"
        sed -i \
            's/action_20a_a_probe_assertion_caddy_active=true/action_20a_a_probe_assertion_caddy_active=false/' \
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
if [[ "${CADDY_ACTION20AA_INTERCEPTED_TEST:-}" = 1 ]]; then
    ssh_binary=${CADDY_ACTION20AA_SSH_BINARY:?}
else
    [[ -z "${CADDY_ACTION20AA_SSH_BINARY:-}" ]]
    ssh_binary=$default_ssh_binary
fi
readonly ssh_binary

work_directory=$(mktemp -d /tmp/caddy-action20aa-runner.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

run_probe() {
    local probed_role=$1
    local probed_address=$2
    local probed_alias=$3
    local probed_stdout=$4
    local probed_stderr=$5

    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$probed_alias" \
        "pi@$probed_address" \
        "cd / && sudo -n env -u CADDY_ACTION20AA_PRODUCTION_REGRESSION -u CADDY_ACTION20AA_FIXTURE_ROOT /bin/bash -s -- --node $probed_role" \
        <"$probe" >"$probed_stdout" 2>"$probed_stderr"
}

readonly node_a_stdout=$work_directory/node-a.stdout
readonly node_a_stderr=$work_directory/node-a.stderr
readonly node_b_stdout=$work_directory/node-b.stdout
readonly node_b_stderr=$work_directory/node-b.stderr
for runner_capture in "$node_a_stdout" "$node_a_stderr" "$node_b_stdout" \
    "$node_b_stderr"; do
    : >"$runner_capture"
    chmod 0600 "$runner_capture"
done
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

node_a_baseline_status=$(sed -n \
    's/^action_20a_a_probe_value_baseline_status=//p' "$node_a_stdout")
readonly node_a_baseline_status
node_b_baseline_status=$(sed -n \
    's/^action_20a_a_probe_value_baseline_status=//p' "$node_b_stdout")
readonly node_b_baseline_status
node_a_transient_status=$(sed -n \
    's/^action_20a_a_probe_value_transient_validate_status=//p' "$node_a_stdout")
readonly node_a_transient_status
node_b_transient_status=$(sed -n \
    's/^action_20a_a_probe_value_transient_validate_status=//p' "$node_b_stdout")
readonly node_b_transient_status

run_assertion node_a_remote_status_zero test "$node_a_status" -eq 0
run_assertion node_b_remote_status_zero test "$node_b_status" -eq 0
run_assertion node_a_probe_contract_valid test "$node_a_contract_status" -eq 0
run_assertion node_b_probe_contract_valid test "$node_b_contract_status" -eq 0
run_assertion node_a_role_exact grep -Fqx \
    'action_20a_a_probe_value_node_role=node-a' "$node_a_stdout"
run_assertion node_b_role_exact grep -Fqx \
    'action_20a_a_probe_value_node_role=node-b' "$node_b_stdout"
run_assertion node_a_baseline_failure_reproduced test \
    "${node_a_baseline_status:-0}" -ne 0
run_assertion node_b_baseline_failure_reproduced test \
    "${node_b_baseline_status:-0}" -ne 0
run_assertion node_a_transient_context_validates test \
    "${node_a_transient_status:-1}" -eq 0
run_assertion node_b_transient_context_validates test \
    "${node_b_transient_status:-1}" -eq 0
run_assertion node_a_state_unchanged grep -Fqx \
    'action_20a_a_probe_assertion_state_unchanged=true' "$node_a_stdout"
run_assertion node_b_state_unchanged grep -Fqx \
    'action_20a_a_probe_assertion_state_unchanged=true' "$node_b_stdout"

printf '%s_value_node_a_remote_status=%s\n' "$prefix" "$node_a_status"
printf '%s_value_node_b_remote_status=%s\n' "$prefix" "$node_b_status"
printf '%s_value_node_a_contract_status=%s\n' "$prefix" "$node_a_contract_status"
printf '%s_value_node_b_contract_status=%s\n' "$prefix" "$node_b_contract_status"
emit_stream node_a_stdout "$node_a_stdout" "$node_a_streams_safe"
emit_stream node_a_stderr "$node_a_stderr" "$node_a_streams_safe"
emit_stream node_b_stdout "$node_b_stdout" "$node_b_streams_safe"
emit_stream node_b_stderr "$node_b_stderr" "$node_b_streams_safe"
printf '%s_assertion_count=12\n' "$prefix"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_contact=read_only\n' "$prefix"
printf '%s_installed_health_helper_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_runner_cleanup_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
