#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly node_a_inspector="$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r-c.sh"
readonly node_b_inspector="$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly runner="$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly node_a_inspector_sha256=ce7463c63883fc5973226d94332522326e88cc942d1d28f9ac9644e30803aa40
readonly node_b_inspector_sha256=f9abd9952612f7855821c0d09a1de01c64fa540c1782aa24512cd035e7a1cdaf
readonly runner_sha256=db59dcf4b0a52034639305e46bd6dc62f18ea3f4621013cfa53e6b0919ad2a5e
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly historical_node_a="$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r.sh"
readonly historical_node_b="$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh"
readonly historical_runner="$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r.sh"
readonly historical_regression="$script_directory/action17r-dual-node-protocol-v2-readiness-regression.sh"
readonly historical_action17r_a_runner="$caddy_root/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh"
readonly historical_action17r_a_regression="$script_directory/action17r-a-node-a-semantic-diagnostic-regression.sh"
readonly historical_action17r_b_inspector="$caddy_root/scripts/diagnose-node-a-ssh-g-stderr-action17r-b.sh"
readonly historical_action17r_b_runner="$caddy_root/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh"
readonly historical_action17r_b_regression="$script_directory/action17r-b-node-a-ssh-g-stderr-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_historical_immutability() {
    [[ "$(file_hash "$historical_node_a")" = e181f2e38f98f9df39bfb4992b4e4f91a786e738566c385becbe722709b931f1 ]]
    [[ "$(file_hash "$historical_node_b")" = f9abd9952612f7855821c0d09a1de01c64fa540c1782aa24512cd035e7a1cdaf ]]
    [[ "$(file_hash "$historical_runner")" = ce8b1ba0641c2a03b9aa593c94ddecd1c27ff3ef73e094820d4bb0dc8b8ec71b ]]
    [[ "$(file_hash "$historical_regression")" = fdd4d9c5ca8cefa39328475c5e165a24adc11cc45ad223a5e3fe517289c98ae9 ]]
    [[ "$(file_hash "$historical_action17r_a_runner")" = a8830d8ffb9f1ff9cf671ba7c2f942e5b5799531d503e44ef293f4df3baff3e5 ]]
    [[ "$(file_hash "$historical_action17r_a_regression")" = 32c390d484edf399c266a58fa1533d1e01f88a3b4593307c4a39c7d00388cf85 ]]
    [[ "$(file_hash "$historical_action17r_b_inspector")" = d892f6e06fee2edfbdcdc5a5d559bafb5234a675b0a2d42d8eb23fd77e85bf96 ]]
    [[ "$(file_hash "$historical_action17r_b_runner")" = 42073901bd8f4faf92f84c24c9e1e84d8ee26607aab7ef42eec0cf911f91cd83 ]]
    [[ "$(file_hash "$historical_action17r_b_regression")" = 061dc3007d298074679f948c74a9f46e1ac954bba1a1d44e6fb5bed34eb8f4c2 ]]
}

run_real_ssh_g_t_regression() {
    local regression_root
    local address_family
    local bind_address
    local expected_family
    local probe_status

    regression_root=$(mktemp -d /tmp/caddy-action17r-c-ssh-g-t.XXXXXX)
    trap 'rm -rf -- "$regression_root"' RETURN
    for address_family in 4 6; do
        bind_address=127.0.0.1
        expected_family=inet
        if [[ "$address_family" = 6 ]]; then
            bind_address=::1
            expected_family=inet6
        fi
        probe_status=0
        ssh -G -T -F /dev/null "-$address_family" -b "$bind_address" \
            -o BatchMode=yes -o ClearAllForwardings=yes \
            -o HostKeyAlias=example.invalid -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile=/dev/null \
            caddy-sync@example.invalid \
            >"$regression_root/ipv$address_family.options" \
            2>"$regression_root/ipv$address_family.error" || probe_status=$?
        [[ "$probe_status" -eq 0 ]]
        [[ ! -s "$regression_root/ipv$address_family.error" ]]
        awk -v expected="$expected_family" \
            '$1 == "addressfamily" && $2 == expected { found = 1 }
             END { exit found ? 0 : 1 }' \
            "$regression_root/ipv$address_family.options"
        awk -v expected="$bind_address" \
            '$1 == "bindaddress" && $2 == expected { found = 1 }
             END { exit found ? 0 : 1 }' \
            "$regression_root/ipv$address_family.options"
        grep -Fxq 'requesttty false' \
            "$regression_root/ipv$address_family.options"
    done
    trap - RETURN
    rm -rf -- "$regression_root"
    printf 'action_17r_c_real_ssh_g_t_stderr_suppression=true\n'
}

extract_source_labels() {
    local source_path=$1

    awk '
        /record_command\(\)/ { next }
        /^[[:space:]]*record_command [a-z0-9_]+/ {
            line = $0
            sub(/^[[:space:]]*record_command /, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            next
        }
        /^[[:space:]]*record_command[[:space:]]*\\$/ {
            getline
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
        }
    ' "$source_path"
}

write_fixture() {
    local fixture_source=$1
    local fixture_prefix=$2
    local fixture_role=$3
    local fixture_path=$4
    local fixture_label

    {
        while IFS= read -r fixture_label; do
            printf '%s_assertion_%s=true\n' "$fixture_prefix" "$fixture_label"
        done < <(extract_source_labels "$fixture_source")
        printf '%s\n' \
            "${fixture_prefix}_value_payload_sha256=$expected_payload_sha256" \
            "${fixture_prefix}_value_manifest_sha256=$expected_manifest_sha256" \
            "${fixture_prefix}_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111" \
            "${fixture_prefix}_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111"
        if [[ "$fixture_role" = node-a ]]; then
            printf '%s_value_source_state=legacy_complete_requires_v2_finalize_request\n' \
                "$fixture_prefix"
        else
            printf '%s\n' \
                "${fixture_prefix}_value_receiver_state=installed_policy_ready" \
                "${fixture_prefix}_value_release_state=payload_ready_awaiting_finalize_request"
        fi
        printf '%s\n' \
            "${fixture_prefix}_assertion_count=$(extract_source_labels "$fixture_source" | wc -l)" \
            "${fixture_prefix}_failed_assertion_count=0" \
            "${fixture_prefix}_first_failure=none" \
            "${fixture_prefix}_peer_connection_executed=false" \
            "${fixture_prefix}_restricted_command_executed=false" \
            "${fixture_prefix}_release_transfer_executed=false" \
            "${fixture_prefix}_marker_mutation=false" \
            "${fixture_prefix}_helper_invocation=false" \
            "${fixture_prefix}_service_mutations=false" \
            "${fixture_prefix}_persistent_mutations=false" \
            "${fixture_prefix}_remote_complete=true"
    } >"$fixture_path"
}

assert_static_policy() {
    local inspected_source

    for inspected_source in "$node_a_inspector" "$node_b_inspector" "$runner"; do
        if grep -Eq \
            'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
            "$inspected_source"; then
            printf 'Action 17r-c contains a service mutation.\n' >&2
            return 1
        fi
        if grep -Eq '^[[:space:]]*(/usr/bin/)?(rsync|scp|sftp)[[:space:]]' \
            "$inspected_source"; then
            printf 'Action 17r-c contains a transfer command.\n' >&2
            return 1
        fi
    done
    if grep -Eq 'ACTION17RC_(FIXTURE|STATUS|CAPTURE|CALL)' "$runner"; then
        printf 'Production Action 17r-c runner contains a fixture bypass.\n' >&2
        return 1
    fi
    if grep -Fq 'IdentitiesOnly=yes' "$runner"; then
        printf 'Action 17r-c administrative SSH disables agent identity selection.\n' >&2
        return 1
    fi
    grep -Fq 'ssh -G -T -F /dev/null -4' "$node_a_inspector"
    grep -Fq 'ssh -G -T -F /dev/null -6' "$node_a_inspector"
    [[ "$(grep -Fc 'ssh -G -T -F /dev/null' "$node_a_inspector")" -eq 2 ]]
    if grep -Eq 'ssh -G -F /dev/null -(4|6)' "$node_a_inspector"; then
        printf 'Action 17r-c retains an unsuppressed ssh -G probe.\n' >&2
        return 1
    fi
    grep -Fq 'receiver_command_allowed' "$node_b_inspector"
    grep -Fq 'boundary_rejects_delete' "$node_b_inspector"
    grep -Fq 'boundary_accepts_rsync_server' "$node_b_inspector"
    # These assertions intentionally match literal production shell source.
    # shellcheck disable=SC2016
    grep -Fq 'run_remote_inspection "$node_b_target"' "$runner"
    # shellcheck disable=SC2016
    grep -Fq 'run_remote_inspection "$node_a_target"' "$runner"
    grep -Fq 'node_b_bab_state_unchanged' "$runner"
    grep -Fq 'action_17r_c_helper_invocation=false' "$runner"
    grep -Fq \
        'action_17r_c_finalization_readiness=legacy_release_requires_transactional_marker_migration' \
        "$runner"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'call_count=0' \
        'if [[ -f "$ACTION17RC_CALL_COUNT" ]]; then call_count=$(<"$ACTION17RC_CALL_COUNT"); fi' \
        'call_count=$((call_count + 1))' \
        'printf "%s\n" "$call_count" >"$ACTION17RC_CALL_COUNT"' \
        'printf "%s\n" "$*" >"$ACTION17RC_CAPTURE_DIR/call-$call_count.args"' \
        'cat >"$ACTION17RC_CAPTURE_DIR/call-$call_count.inspector"' \
        'case "$call_count" in' \
        '  1) cat "$ACTION17RC_NODE_B_BEFORE_FIXTURE"; exit "${ACTION17RC_NODE_B_BEFORE_STATUS:-0}" ;;' \
        '  2) cat "$ACTION17RC_NODE_A_FIXTURE"; exit "${ACTION17RC_NODE_A_STATUS:-0}" ;;' \
        '  3) cat "$ACTION17RC_NODE_B_AFTER_FIXTURE"; exit "${ACTION17RC_NODE_B_AFTER_STATUS:-0}" ;;' \
        '  *) exit 98 ;;' \
        'esac' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_root=$1
    local case_runner=$2

    : >"$case_root/call-count"
    printf '0\n' >"$case_root/call-count"
    set +e
    ACTION17RC_CALL_COUNT="$case_root/call-count" \
        ACTION17RC_CAPTURE_DIR="$case_root/captured" \
        ACTION17RC_NODE_B_BEFORE_FIXTURE="$case_root/node-b-before.fixture" \
        ACTION17RC_NODE_A_FIXTURE="$case_root/node-a.fixture" \
        ACTION17RC_NODE_B_AFTER_FIXTURE="$case_root/node-b-after.fixture" \
        ACTION17RC_NODE_B_BEFORE_STATUS="${case_node_b_before_status:-0}" \
        ACTION17RC_NODE_A_STATUS="${case_node_a_status:-0}" \
        ACTION17RC_NODE_B_AFTER_STATUS="${case_node_b_after_status:-0}" \
        "$case_runner" >"$case_root/output" 2>"$case_root/error"
    observed_status=$?
    set -e
}

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner

    case_root=$(mktemp -d /tmp/caddy-action17r-c-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 "$case_bin" "$case_root/captured" \
        "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$node_a_inspector" "$node_b_inspector" "$runner" \
        "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    case_runner="$case_root/Caddy/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh"
    write_fake_ssh "$case_bin/ssh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
    chmod 0755 "$case_runner" "$case_root/Caddy/scripts/"*.sh \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"
    write_fixture "$node_b_inspector" action_17r_node_b node-b \
        "$case_root/node-b-before.fixture"
    cp -- "$case_root/node-b-before.fixture" "$case_root/node-b-after.fixture"
    write_fixture "$node_a_inspector" action_17r_c_node_a node-a \
        "$case_root/node-a.fixture"

    case_node_b_before_status=0
    case_node_a_status=0
    case_node_b_after_status=0
    run_case "$case_root" "$case_runner"
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/error" ]]
    grep -Fxq action_17r_c_runner_acceptance=true "$case_root/output"
    grep -Fxq action_17r_c_workstation_cleanup_complete=true "$case_root/output"
    [[ "$(<"$case_root/call-count")" -eq 3 ]]
    cmp -s "$node_b_inspector" "$case_root/captured/call-1.inspector"
    cmp -s "$node_a_inspector" "$case_root/captured/call-2.inspector"
    cmp -s "$node_b_inspector" "$case_root/captured/call-3.inspector"
    grep -Fq 'pi@10.1.0.54' "$case_root/captured/call-1.args"
    grep -Fq 'pi@10.1.0.53' "$case_root/captured/call-2.args"
    grep -Fq 'pi@10.1.0.54' "$case_root/captured/call-3.args"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' \
        "$case_root/captured/call-1.args"

    rm -rf -- "$case_root/captured"
    install -d -m 0700 "$case_root/captured"
    sed -i \
        -e 's/action_17r_c_node_a_assertion_ipv4_bind_address_exact=true/action_17r_c_node_a_assertion_ipv4_bind_address_exact=false/' \
        -e 's/action_17r_c_node_a_failed_assertion_count=0/action_17r_c_node_a_failed_assertion_count=1/' \
        -e 's/action_17r_c_node_a_first_failure=none/action_17r_c_node_a_first_failure=ipv4_bind_address_exact/' \
        "$case_root/node-a.fixture"
    case_node_a_status=1
    run_case "$case_root" "$case_runner"
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17r_c_runner_acceptance=false "$case_root/output"

    rm -rf -- "$case_root/captured"
    install -d -m 0700 "$case_root/captured"
    sed -i \
        's/action_17r_node_b_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111/action_17r_node_b_value_before_state_sha256=2222222222222222222222222222222222222222222222222222222222222222/' \
        "$case_root/node-b-after.fixture"
    case_node_a_status=1
    run_case "$case_root" "$case_runner"
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17r_c_runner_acceptance=false "$case_root/output"
}

[[ "$(file_hash "$node_a_inspector")" = "$node_a_inspector_sha256" ]]
[[ "$(file_hash "$node_b_inspector")" = "$node_b_inspector_sha256" ]]
[[ "$(file_hash "$runner")" = "$runner_sha256" ]]
[[ "$(extract_source_labels "$node_a_inspector" | wc -l)" -eq 52 ]]
[[ "$(extract_source_labels "$node_b_inspector" | wc -l)" -eq 60 ]]
bash -n "$node_a_inspector" "$node_b_inspector" "$runner"
shellcheck "$node_a_inspector" "$node_b_inspector" "$runner"
"$collision_checker" "$node_a_inspector" "$node_b_inspector" "$runner" "$0" \
    >/dev/null
"$node_a_inspector" --self-test >/dev/null
"$node_b_inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --source-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
assert_historical_immutability
assert_static_policy
run_real_ssh_g_t_regression
run_production_path_regression

printf 'action_17r_c_dual_node_protocol_v2_readiness_regression_complete=true\n'
