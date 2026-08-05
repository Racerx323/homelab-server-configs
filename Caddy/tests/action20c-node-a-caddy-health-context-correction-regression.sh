#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20c_regression
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly candidate="$caddy_root/scripts/check-caddy-action20b.sh"
readonly installer="$caddy_root/scripts/install-node-a-caddy-health-context-action20c.sh"
readonly runner="$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c.sh"
readonly baseline="$caddy_root/scripts/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh"
readonly host_suite="$caddy_root/tests/run.sh"
readonly integration_suite="$caddy_root/tests/integration.sh"
readonly candidate_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly installer_sha256=de17f05035c79e679166c8d20ae510cc9b570cc61d65d7fffe1bdb7a65ce56a1
readonly baseline_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
regression_line_count() { awk 'END { print NR }' "$1"; }
regression_stream_safe() {
    local regression_stream_path=$1

    # conditional-validator-explicit-failures-begin
    [[ "$(wc -c <"$regression_stream_path")" -le 1048576 ]] || return 1
    [[ "$(regression_line_count "$regression_stream_path")" -le 4096 ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$regression_stream_path" \
        >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$regression_stream_path" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
emit_regression_stream() {
    local regression_stream_name=$1
    local regression_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$regression_stream_name" \
        "$(wc -c <"$regression_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$regression_stream_name" \
        "$(regression_line_count "$regression_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$regression_stream_name" \
        "$(file_hash "$regression_stream_path")"
    if [[ ! -s "$regression_stream_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" \
            "$regression_stream_name"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$regression_stream_name"
    cat "$regression_stream_path"
    printf '%s_%s_end\n' "$prefix" "$regression_stream_name"
}
require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
forbidden_live_mutation_absent() {
    ! grep -Eq \
        'systemctl[[:space:]]+(reload|restart|enable|disable|start|stop)|(^|[;&|[:space:]])ip[[:space:]]+(address|addr)[[:space:]]+(add|replace|delete|del)|keepalived[[:space:]]+--' \
        "$candidate" "$installer" "$runner"
}
candidate_contract() {
    # Dollar-prefixed tokens are matched as literal source text.
    # shellcheck disable=SC2016
    grep -Fq 'source /etc/default/caddy-ha' "$candidate" &&
        grep -Fq 'mktemp -d /tmp/caddy-health.XXXXXX' "$candidate" &&
        grep -Fq 'HOME=$runtime_root/home' "$candidate" &&
        grep -Fq 'XDG_CONFIG_HOME=$runtime_root/config' "$candidate" &&
        grep -Fq 'XDG_DATA_HOME=$runtime_root/data' "$candidate" &&
        grep -Fq 'trap cleanup EXIT INT TERM' "$candidate" &&
        grep -Fq 'systemctl is-active --quiet caddy' "$candidate" &&
        grep -Fq 'https://localhost' "$candidate"
}
installer_contract() {
    grep -Fq 'keepalived_caddy_tls_group_exact' "$installer" &&
        grep -Fq 'active_fullchain_readable' "$installer" &&
        grep -Fq 'active_private_key_readable' "$installer" &&
        grep -Fq '.check-caddy.action20c-validate.XXXXXX' "$installer" &&
        grep -Fq 'root:caddy-tls:750' "$installer" &&
        grep -Fq 'candidate_execution_stage_metadata' "$installer" &&
        grep -Fq 'candidate_execution_success' "$installer" &&
        grep -Fq 'installed_helper_execution_success' "$installer" &&
        grep -Fq 'readonly active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' "$installer" &&
        grep -Fq 'readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5' "$installer" &&
        grep -Fq 'readonly expected_fragment_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS' "$installer" &&
        grep -Fq 'fragment_backup_tree_hash_unchanged' "$installer" &&
        grep -Fq -- '--node node-a' "$installer" &&
        grep -Fq 'action20c-node-a-health-context.XXXXXX' "$installer" &&
        grep -Fq 'persistent_mutation_scope=health_helper,rollback_backup' "$installer"
}
runner_contract() {
    grep -Fq 'readonly expected_target=pi@10.1.0.53' "$runner" &&
        grep -Fq 'readonly expected_host_alias=pihole0.local.theama.co' "$runner" &&
        grep -Fq 'IdentitiesOnly=no' "$runner" &&
        grep -Fq "sudo -n /bin/bash -s" "$runner" &&
        grep -Fq -- '--expected-checks' "$runner" &&
        grep -Fq 'diff -u' "$runner"
}
ssh() {
    local intercepted_mode=${ACTION20C_INTERCEPT_MODE:-valid}
    local emitted_label
    local first_label=true

    cat >/dev/null
    printf 'ssh\n' >>"$ACTION20C_INTERCEPT_COUNT"
    while IFS= read -r emitted_label; do
        if [[ "$intercepted_mode" == missing && "$first_label" == true ]]; then
            first_label=false
            continue
        fi
        first_label=false
        printf 'action_20c_check_%s=true\n' "$emitted_label"
    done < <(/bin/bash "$ACTION20C_TEST_INSTALLER" --expected-checks)
    if [[ "$intercepted_mode" == duplicate ]]; then
        printf 'action_20c_check_identity_root=true\n'
    elif [[ "$intercepted_mode" == false ]]; then
        printf 'action_20c_check_identity_root=false\n'
    fi
    printf '%s\n' \
        'action_20c_preflight_complete=true' \
        'action_20c_mutation_started=true' \
        'action_20c_helper_invoked_for_validation=true' \
        'action_20c_fragment_mutated=false' \
        'action_20c_keepalived_mutated=false' \
        'action_20c_service_mutations=false' \
        'action_20c_vrrp_mutated=false' \
        'action_20c_vip_mutated=false' \
        'action_20c_backup_path=/var/backups/caddy-ha/action20c-node-a-health-context.ABC123' \
        'action_20c_persistent_mutation_scope=health_helper,rollback_backup' \
        'action_20c_install_complete=true'
}
export -f ssh

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        require_gate candidate_hash_exact test "$(file_hash "$candidate")" = "$candidate_sha256"
        require_gate installer_hash_exact test "$(file_hash "$installer")" = "$installer_sha256"
        require_gate historical_baseline_immutable test "$(file_hash "$baseline")" = "$baseline_sha256"
        require_gate sources_syntax /bin/bash -n "$candidate" "$installer" "$runner"
        require_gate sources_shellcheck shellcheck "$candidate" "$installer" "$runner"
        require_gate candidate_contract candidate_contract
        require_gate installer_contract installer_contract
        require_gate runner_contract runner_contract
        require_gate exact_check_count test \
            "$(/bin/bash "$installer" --expected-check-count)" -eq 77
        require_gate exact_check_labels_unique test \
            "$(/bin/bash "$installer" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 77
        # The positional parameters are intentionally expanded by the child shell.
        # shellcheck disable=SC2016
        require_gate node_b_identity_absent /bin/bash -c \
            '! grep -Eq '\''10\.1\.0\.54|pihole00\.local\.theama\.co|j1-svpihole00|--node node-b'\'' "$1" "$2"' \
            _ "$installer" "$runner"
        require_gate forbidden_live_mutation_absent forbidden_live_mutation_absent
        require_gate host_suite_outer_signature grep -Fq \
            'run-node-a-caddy-health-context-correction-action20c-outer.sh' \
            "$host_suite"
        require_gate host_suite_regression_signature grep -Fq \
            'action20c-node-a-caddy-health-context-correction-regression.sh' \
            "$host_suite"
        require_gate integration_suite_outer_signature grep -Fq \
            'run-node-a-caddy-health-context-correction-action20c-outer.sh' \
            "$integration_suite"
        require_gate integration_suite_regression_signature grep -Fq \
            'action20c-node-a-caddy-health-context-correction-regression.sh' \
            "$integration_suite"
        require_gate installer_self_test /bin/bash "$installer" --self-test
        require_gate runner_self_test /bin/bash "$runner" --self-test
        require_gate runner_contract_test /bin/bash "$runner" --contract-test
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20c-regression.XXXXXX)
readonly work_directory
trap 'rm -rf -- "$work_directory"' EXIT
export ACTION20C_TEST_INSTALLER=$installer
export ACTION20C_INTERCEPT_COUNT=$work_directory/ssh.count
: >"$ACTION20C_INTERCEPT_COUNT"

valid_runner_status=0
ACTION20C_INTERCEPT_MODE=valid /bin/bash "$runner" \
    >"$work_directory/valid.stdout" 2>"$work_directory/valid.stderr" ||
    valid_runner_status=$?
readonly valid_runner_status
printf '%s_valid_runner_status=%s\n' "$prefix" "$valid_runner_status"
if [[ "$valid_runner_status" -ne 0 ]]; then
    printf '%s_valid_runner_status_zero=false\n' "$prefix" >&2
    if regression_stream_safe "$work_directory/valid.stdout" &&
        regression_stream_safe "$work_directory/valid.stderr"; then
        printf '%s_valid_runner_streams=bounded_safe\n' "$prefix"
        emit_regression_stream valid_runner_stdout "$work_directory/valid.stdout"
        emit_regression_stream valid_runner_stderr "$work_directory/valid.stderr"
    else
        printf '%s_valid_runner_streams=unsafe_retained\n' "$prefix" >&2
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    fi
    exit 1
fi
printf '%s_valid_runner_status_zero=true\n' "$prefix"
require_gate false_negative_valid_contract_accepted grep -Fxq \
    'action_20c_remote_status=0' "$work_directory/valid.stdout"
require_gate valid_stderr_empty test ! -s "$work_directory/valid.stderr"
require_gate intercepted_ssh_once test "$(wc -l <"$ACTION20C_INTERCEPT_COUNT")" -eq 1

for negative_mode in missing duplicate false; do
    if ACTION20C_INTERCEPT_MODE=$negative_mode /bin/bash "$runner" \
        >"$work_directory/$negative_mode.stdout" \
        2>"$work_directory/$negative_mode.stderr"; then
        printf '%s_false_positive_%s_rejected=false\n' "$prefix" "$negative_mode" >&2
        exit 1
    fi
    printf '%s_false_positive_%s_rejected=true\n' "$prefix" "$negative_mode"
done
require_gate production_path_network_contact_false test \
    "$(wc -l <"$ACTION20C_INTERCEPT_COUNT")" -eq 4
printf '%s_complete=true\n' "$prefix"
