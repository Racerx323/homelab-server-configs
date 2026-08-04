#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_regression
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly installer_sha256=142eac9d91eb30c3ce2103cc98ef1d9dddd288fedb632398c589bade6c252db6
readonly runner_sha256=f45bde838b783b1ef6ff99f276ac1dab3df28a2f96eeea5dac14817ec1d71518

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly installer="$caddy_root/scripts/install-node-b-keepalived-fragment-action19a.sh"
readonly runner="$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions-v2.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

write_success_transcript() {
    local transcript_path=$1
    local fixture_index

    for fixture_index in $(seq 1 90); do
        printf 'action_19a_check_fixture_%03d=true\n' "$fixture_index"
    done >"$transcript_path"
    # The generated interceptor evaluates these variables when invoked.
    # shellcheck disable=SC2016
    printf '%s\n' \
        'action_19a_preflight_complete=true' \
        'action_19a_mutation_started=true' \
        'action_19a_fragment_installed=true' \
        'action_19a_main_configuration_mutated=false' \
        'action_19a_keepalived_reloaded=false' \
        'action_19a_keepalived_restarted=false' \
        'action_19a_vrrp_transition_requested=false' \
        'action_19a_vip_mutations=false' \
        'action_19a_service_mutations=false' \
        'action_19a_backup_path=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.FIXTURE' \
        'action_19a_persistent_mutation_scope=fragment,rollback_backup' \
        'action_19a_install_complete=true' >>"$transcript_path"
}

run_intercepted_case() {
    local case_directory=$1
    local expected_status=$2
    local transcript_path=$3
    local fake_ssh=$case_directory/fake-ssh
    local observed_status=0
    local output_path=$case_directory/runner.stdout
    local error_path=$case_directory/runner.stderr

    # The generated interceptor evaluates these variables when invoked.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        ': >"${ACTION19A_SSH_STDIN_CAPTURE:?}"' \
        'cat >"$ACTION19A_SSH_STDIN_CAPTURE"' \
        'printf "%s\\n" "$*" >"${ACTION19A_SSH_ARGS_CAPTURE:?}"' \
        'cat "${ACTION19A_SSH_TRANSCRIPT:?}"' >"$fake_ssh"
    chmod 0700 "$fake_ssh"
    : >"$output_path"
    : >"$error_path"
    chmod 0600 "$output_path" "$error_path"

    (
        cd "$repository_root"
        CADDY_ACTION19A_INTERCEPTED_TEST=1 \
            CADDY_ACTION19A_SSH_BINARY="$fake_ssh" \
            ACTION19A_SSH_TRANSCRIPT="$transcript_path" \
            ACTION19A_SSH_STDIN_CAPTURE="$case_directory/ssh.stdin" \
            ACTION19A_SSH_ARGS_CAPTURE="$case_directory/ssh.args" \
            "$runner"
    ) >"$output_path" 2>"$error_path" || observed_status=$?
    if [[ "$observed_status" -ne "$expected_status" ]]; then
        printf 'intercepted_case_expected_status=%s\n' "$expected_status" >&2
        printf 'intercepted_case_observed_status=%s\n' "$observed_status" >&2
        printf 'intercepted_case_stdout_begin\n' >&2
        cat "$output_path" >&2
        printf 'intercepted_case_stdout_end\n' >&2
        printf 'intercepted_case_stderr_begin\n' >&2
        cat "$error_path" >&2
        printf 'intercepted_case_stderr_end\n' >&2
        return 1
    fi
    [[ -s "$case_directory/ssh.stdin" ]] || return 1
    grep -Fq -- '-T -o BatchMode=yes' "$case_directory/ssh.args" || return 1
    grep -Fq 'pi@10.1.0.54 cd / && sudo -n /bin/bash -s' \
        "$case_directory/ssh.args" || return 1
    grep -Fq 'install-node-b-keepalived-fragment-action19a.sh' \
        "$case_directory/ssh.stdin" || return 1
    grep -Fq 'action_19a_remote_stdout_begin' "$output_path" || return 1
    grep -Fq 'action_19a_remote_stdout_end' "$output_path" || return 1
}

require_gate installer_hash_exact \
    test "$(file_hash "$installer")" = "$installer_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate fragment_hash_pin_exact grep -Fq \
    "expected_fragment_sha256=$expected_fragment_sha256" "$installer"
require_gate sources_syntax bash -n "$installer" "$runner"
require_gate sources_shellcheck shellcheck "$installer" "$runner"
require_gate collision_policy_clean "$collision_checker" "$installer" "$runner"
require_gate installer_self_test "$installer" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate target_exact grep -Fq 'fragment=/etc/keepalived/conf.d/caddy-ha.conf' \
    "$installer"
require_gate main_config_not_installed grep -Fq \
    'main_configuration_mutated=false' "$installer"
require_gate keepalived_reload_prohibited grep -Fq \
    'keepalived_reloaded=false' "$installer"
require_gate keepalived_restart_prohibited grep -Fq \
    'keepalived_restarted=false' "$installer"
require_gate vrrp_transition_prohibited grep -Fq \
    'vrrp_transition_requested=false' "$installer"
require_gate vip_mutation_prohibited grep -Fq 'vip_mutations=false' "$installer"
require_gate service_mutation_prohibited grep -Fq \
    'service_mutations=false' "$installer"
# Child shells and literal source checks intentionally defer expansion.
# shellcheck disable=SC2016
require_gate no_systemctl_mutation \
    bash -c '! grep -Eq "systemctl[[:space:]]+(reload|restart|start|stop|enable|disable|mask|unmask)" "$1"' \
    _ "$installer"
# shellcheck disable=SC2016
require_gate no_ip_mutation \
    bash -c '! grep -Eq "(^|[[:space:]])ip[[:space:]].*address[[:space:]]+(add|del|replace)([[:space:]]|$)" "$1"' \
    _ "$installer"
# shellcheck disable=SC2016
require_gate exact_fragment_only_install test \
    "$(grep -Ec 'mv -- \"\$install_stage\" \"\$fragment\"' "$installer")" -eq 1
# shellcheck disable=SC2016
require_gate parser_uses_sanitized_candidate grep -Fq \
    'sanitized_fragment=$parser_directory/caddy-ha.conf' "$installer"
require_gate parser_replaces_health_command grep -Fq \
    's#script "/usr/local/libexec/check-caddy.sh"#script "/bin/true"#' \
    "$installer"
# shellcheck disable=SC2016
require_gate rollback_removes_fragment grep -Fq 'rm -f -- "$fragment"' "$installer"
require_gate rollback_restores_tree_hash grep -Fq \
    'expected_keepalived_tree_sha256' "$installer"

work_directory=$(mktemp -d /tmp/caddy-action19a-regression.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT

success_directory=$work_directory/success
mkdir -m 0700 "$success_directory"
success_transcript=$success_directory/transcript
write_success_transcript "$success_transcript"
run_intercepted_case "$success_directory" 0 "$success_transcript"
printf '%s_false_negative_valid_production_path_accepted=true\n' "$prefix"

false_directory=$work_directory/false
mkdir -m 0700 "$false_directory"
false_transcript=$false_directory/transcript
write_success_transcript "$false_transcript"
printf 'action_19a_check_live_fragment_hash_exact=false\n' >>"$false_transcript"
run_intercepted_case "$false_directory" 1 "$false_transcript"
printf '%s_false_positive_failed_assertion_rejected=true\n' "$prefix"

duplicate_directory=$work_directory/duplicate
mkdir -m 0700 "$duplicate_directory"
duplicate_transcript=$duplicate_directory/transcript
write_success_transcript "$duplicate_transcript"
printf 'action_19a_check_fixture_001=true\n' >>"$duplicate_transcript"
run_intercepted_case "$duplicate_directory" 1 "$duplicate_transcript"
printf '%s_false_positive_duplicate_assertion_rejected=true\n' "$prefix"

printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
