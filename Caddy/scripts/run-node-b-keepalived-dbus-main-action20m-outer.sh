#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_outer
readonly expected_target=pi@10.1.0.54
readonly expected_host_alias=10.1.0.54
readonly installer_sha256=603b36c877831ba6cbef09c239e72ddf121e55cb2e5bd985ceaf6da477d78d13
readonly source_sha256=9aa36b630f304bab674e31af96d96a1dbafb330728b01e2d8216c8dbab2df148
readonly candidate_sha256=5480e6994994b65b0a498f42cb7943b5de86958416732a44983e341a93db1393
readonly regression_sha256=9611ebe5ff2142eb91f9ce7b1930b5552a20602ccfbbc7cf15cb826bd58a9eeb
readonly expected_check_count=71
readonly expected_success_line_count=103
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly repository_root=${caddy_root%/Caddy}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly installer=$script_directory/install-node-b-keepalived-dbus-main-action20m.sh
readonly source_configuration=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly regression=$caddy_root/tests/action20m-node-b-keepalived-dbus-main-regression.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
require_hash() {
    local action20m_outer_expected_hash=$1
    local action20m_outer_path=$2

    [[ -f "$action20m_outer_path" && ! -L "$action20m_outer_path" ]] || return 1
    [[ "$(file_hash "$action20m_outer_path")" = "$action20m_outer_expected_hash" ]]
}
run_gate() {
    local action20m_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20m_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20m_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory installer_regular installer_executable installer_hash \
        source_regular source_not_symlink source_hash candidate_hash_contract \
        regression_regular regression_executable regression_hash syntax shellcheck \
        canonical_format collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy accepted_live_hash_policy \
        installer_self_test regression
}
candidate_hash_contract() {
    {
        cat "$source_configuration"
        printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n'
    } | sha256sum | awk -v expected="$candidate_sha256" '$1 == expected { valid=1 }
        END { exit(valid == 1 ? 0 : 1) }'
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate installer_regular test -f "$installer" || return 1
    run_gate installer_executable test -x "$installer" || return 1
    run_gate installer_hash require_hash "$installer_sha256" "$installer" || return 1
    run_gate source_regular test -f "$source_configuration" || return 1
    run_gate source_not_symlink test ! -L "$source_configuration" || return 1
    run_gate source_hash require_hash "$source_sha256" "$source_configuration" || return 1
    run_gate candidate_hash_contract candidate_hash_contract || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate syntax /bin/bash -n "$installer" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$installer" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$installer" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash \
        "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    run_gate installer_self_test /bin/bash "$installer" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20m_outer_stream=$1

    [[ "$(wc -c <"$action20m_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20m_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20m_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20m_outer_stream"
}
emit_stream() {
    local action20m_outer_stream_label=$1
    local action20m_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20m_outer_stream_label" "$(wc -c <"$action20m_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20m_outer_stream_label" "$(line_count "$action20m_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20m_outer_stream_label" "$(file_hash "$action20m_outer_stream")"
    if safe_stream "$action20m_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20m_outer_stream_label"
        if [[ -s "$action20m_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20m_outer_stream_label"
            cat "$action20m_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action20m_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20m_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20m_outer_stream_label" >&2
    return 97
}
require_one() {
    local action20m_outer_line=$1
    local action20m_outer_transcript=$2

    [[ "$(grep -Fxc "$action20m_outer_line" "$action20m_outer_transcript" || true)" -eq 1 ]]
}
validate_assert() {
    local action20m_outer_assertion_label=$1

    shift
    if "$@"; then
        printf '%s_validation_%s=true\n' "$prefix" "$action20m_outer_assertion_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action20m_outer_assertion_label" >&2
    return 1
}
backup_path_exact() {
    local action20m_outer_stdout=$1
    local action20m_outer_backup_pattern='^action_20m_backup_path=/var/backups/caddy-ha/action20m-node-b-dbus-main\.[A-Za-z0-9]+$'

    if [[ "${CADDY_ACTION20M_TEST_MODE:-}" = 1 ]]; then
        action20m_outer_backup_pattern='^action_20m_backup_path=/.*/var/backups/caddy-ha/action20m-node-b-dbus-main\.[A-Za-z0-9]+$'
    fi
    [[ "$(grep -Ec "$action20m_outer_backup_pattern" "$action20m_outer_stdout")" -eq 1 ]]
}
generate_expected_checks() {
    local action20m_outer_expected=$1

    /bin/bash "$installer" --expected-checks >"$action20m_outer_expected"
}
validate_success() {
    local action20m_outer_stdout=$1
    local action20m_outer_stderr=$2
    local action20m_outer_status=$3
    local action20m_outer_expected=$4
    local action20m_outer_actual=$5
    local action20m_outer_actual_count

    # conditional-validator-explicit-failures-begin
    validate_assert status_zero test "$action20m_outer_status" -eq 0 || return 1
    validate_assert stderr_empty test ! -s "$action20m_outer_stderr" || return 1
    validate_assert transcript_line_count test \
        "$(line_count "$action20m_outer_stdout")" -eq "$expected_success_line_count" || return 1
    validate_assert expected_checks_generated generate_expected_checks \
        "$action20m_outer_expected" || return 1
    validate_assert expected_check_count test \
        "$(line_count "$action20m_outer_expected")" -eq "$expected_check_count" || return 1
    validate_assert no_false_checks test \
        "$(grep -Ec '^action_20m_check_[a-z0-9_]+=false$' "$action20m_outer_stdout" || true)" -eq 0 || return 1
    sed -n 's/^action_20m_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action20m_outer_stdout" >"$action20m_outer_actual" || return 1
    action20m_outer_actual_count=$(line_count "$action20m_outer_actual") || return 1
    validate_assert actual_check_count test "$action20m_outer_actual_count" -eq "$expected_check_count" || return 1
    validate_assert unique_check_count test \
        "$(LC_ALL=C sort -u "$action20m_outer_actual" | wc -l)" -eq "$expected_check_count" || return 1
    validate_assert ordered_check_contract diff -u "$action20m_outer_expected" "$action20m_outer_actual" || return 1
    validate_assert node_exact require_one 'action_20m_node=node-b' "$action20m_outer_stdout" || return 1
    validate_assert main_mutated require_one 'action_20m_main_configuration_mutated=true' "$action20m_outer_stdout" || return 1
    validate_assert backup_retained require_one 'action_20m_backup_retained=true' "$action20m_outer_stdout" || return 1
    validate_assert reload_false require_one 'action_20m_keepalived_reload=false' "$action20m_outer_stdout" || return 1
    validate_assert restart_false require_one 'action_20m_keepalived_restart=false' "$action20m_outer_stdout" || return 1
    validate_assert service_mutation_false require_one 'action_20m_service_mutation=false' "$action20m_outer_stdout" || return 1
    validate_assert vrrp_transition_false require_one 'action_20m_vrrp_transition=false' "$action20m_outer_stdout" || return 1
    validate_assert vip_mutation_false require_one 'action_20m_vip_mutation=false' "$action20m_outer_stdout" || return 1
    validate_assert producer_complete require_one 'action_20m_complete=true' "$action20m_outer_stdout" || return 1
    validate_assert backup_path_exact backup_path_exact "$action20m_outer_stdout" || return 1
    for action20m_outer_capture in install_candidate_stdout install_candidate_stderr rename_candidate_stdout rename_candidate_stderr; do
        validate_assert "${action20m_outer_capture}_bytes" require_one "action_20m_capture_${action20m_outer_capture}_bytes=0" "$action20m_outer_stdout" || return 1
        validate_assert "${action20m_outer_capture}_lines" require_one "action_20m_capture_${action20m_outer_capture}_lines=0" "$action20m_outer_stdout" || return 1
        validate_assert "${action20m_outer_capture}_sha256" require_one "action_20m_capture_${action20m_outer_capture}_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$action20m_outer_stdout" || return 1
        validate_assert "${action20m_outer_capture}_classification" require_one "action_20m_capture_${action20m_outer_capture}_classification=bounded_safe" "$action20m_outer_stdout" || return 1
        validate_assert "${action20m_outer_capture}_secured" require_one "action_20m_capture_${action20m_outer_capture}_content_secured=empty" "$action20m_outer_stdout" || return 1
    done
    validate_assert install_status require_one 'action_20m_capture_install_candidate_status=0' "$action20m_outer_stdout" || return 1
    validate_assert rename_status require_one 'action_20m_capture_rename_candidate_status=0' "$action20m_outer_stdout" || return 1
    validate_assert rollback_absent test \
        "$(grep -Fc 'action_20m_rollback_' "$action20m_outer_stdout" || true)" -eq 0 || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
validate_failure() {
    local action20m_outer_stdout=$1
    local action20m_outer_stderr=$2
    local action20m_outer_status=$3

    # conditional-validator-explicit-failures-begin
    [[ "$action20m_outer_status" -ne 0 ]] || return 1
    if grep -Fq 'action_20m_check_mutation_started=true' "$action20m_outer_stdout"; then
        require_one 'action_20m_rollback_started=true' "$action20m_outer_stderr" || return 1
        require_one 'action_20m_rollback_complete=true' "$action20m_outer_stderr" || return 1
    fi
    ! grep -Fq 'action_20m_rollback_complete=false' "$action20m_outer_stderr" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
write_remote_bundle() {
    local action20m_outer_archive=$1
    local action20m_outer_remote_script=$2

    # Variables in the quoted lines expand only on the remote node or test shell.
    # shellcheck disable=SC2016
    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -Eeuo pipefail' \
            'set +x' \
            'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' \
            'cd /' \
            'bundle_parent=${ACTION20M_BUNDLE_PARENT:-/run}' \
            'bundle_owner=${ACTION20M_BUNDLE_OWNER:-root}' \
            'bundle_group=${ACTION20M_BUNDLE_GROUP:-root}' \
            '[[ -d "$bundle_parent" && ! -L "$bundle_parent" ]]' \
            'bundle_stage=$(mktemp -d "$bundle_parent/caddy-action20m-bundle.XXXXXX")' \
            'cleanup_bundle_stage() { rm -rf -- "$bundle_stage"; }' \
            'trap cleanup_bundle_stage EXIT INT TERM' \
            'chown "$bundle_owner:$bundle_group" "$bundle_stage"' \
            'chmod 0700 "$bundle_stage"' \
            'install -d -o "$bundle_owner" -g "$bundle_group" -m 0700 "$bundle_stage/payload"' \
            'install -m 0600 /dev/null "$bundle_stage/payload.tar"' \
            'base64 -d >"$bundle_stage/payload.tar" <<'\''ACTION20M_ARCHIVE'\'''
        base64 "$action20m_outer_archive"
        printf '%s\n' \
            'ACTION20M_ARCHIVE' \
            'printf '\''%s\n'\'' install-node-b-keepalived-dbus-main-action20m.sh keepalived-pihole00.conf >"$bundle_stage/expected-members"' \
            'tar -tf "$bundle_stage/payload.tar" | LC_ALL=C sort >"$bundle_stage/actual-members"' \
            'diff -u "$bundle_stage/expected-members" "$bundle_stage/actual-members" >/dev/null' \
            'tar --extract --file "$bundle_stage/payload.tar" --directory "$bundle_stage/payload" --no-same-owner --no-same-permissions' \
            'chown "$bundle_owner:$bundle_group" "$bundle_stage/payload" "$bundle_stage/payload"/*' \
            'chmod 0700 "$bundle_stage/payload" "$bundle_stage/payload/install-node-b-keepalived-dbus-main-action20m.sh"' \
            'chmod 0600 "$bundle_stage/payload/keepalived-pihole00.conf"' \
            'cd /' \
            '/bin/bash "$bundle_stage/payload/install-node-b-keepalived-dbus-main-action20m.sh" --stage "$bundle_stage/payload"'
    } >"$action20m_outer_remote_script" || return 1
    chmod 0600 "$action20m_outer_remote_script" || return 1
    /bin/bash -n "$action20m_outer_remote_script"
}
run_transport() (
    local action20m_outer_ssh_binary=${CADDY_ACTION20M_SSH_BINARY:-ssh}
    local action20m_outer_selected_source=$source_configuration
    local action20m_outer_work_root
    local action20m_outer_bundle_files
    local action20m_outer_archive
    local action20m_outer_remote_script
    local action20m_outer_stdout
    local action20m_outer_stderr
    local action20m_outer_expected
    local action20m_outer_actual
    local action20m_outer_status=0
    local action20m_outer_stream_failure=false

    if [[ "$action20m_outer_ssh_binary" != ssh ]]; then
        [[ "${CADDY_ACTION20M_TEST_MODE:-}" = 1 && -x "$action20m_outer_ssh_binary" ]] || return 64
        [[ -n "${CADDY_ACTION20M_SOURCE_PATH:-}" ]] || return 64
        action20m_outer_selected_source=$CADDY_ACTION20M_SOURCE_PATH
    fi
    action20m_outer_work_root=$(mktemp -d /tmp/caddy-action20m-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20m_outer_work_root"' EXIT
    action20m_outer_bundle_files=$action20m_outer_work_root/bundle-files
    action20m_outer_archive=$action20m_outer_work_root/payload.tar
    action20m_outer_remote_script=$action20m_outer_work_root/remote.sh
    action20m_outer_stdout=$action20m_outer_work_root/remote.stdout
    action20m_outer_stderr=$action20m_outer_work_root/remote.stderr
    action20m_outer_expected=$action20m_outer_work_root/expected
    action20m_outer_actual=$action20m_outer_work_root/actual
    install -d -m 0700 "$action20m_outer_bundle_files" || return 1
    install -m 0700 "$installer" "$action20m_outer_bundle_files/install-node-b-keepalived-dbus-main-action20m.sh" || return 1
    install -m 0600 "$action20m_outer_selected_source" "$action20m_outer_bundle_files/keepalived-pihole00.conf" || return 1
    tar --create --file "$action20m_outer_archive" --directory "$action20m_outer_bundle_files" \
        install-node-b-keepalived-dbus-main-action20m.sh keepalived-pihole00.conf || return 1
    write_remote_bundle "$action20m_outer_archive" "$action20m_outer_remote_script" || return 1
    install -m 0600 /dev/null "$action20m_outer_stdout" || return 1
    install -m 0600 /dev/null "$action20m_outer_stderr" || return 1
    "$action20m_outer_ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes \
        -o IdentitiesOnly=no -o HostKeyAlias="$expected_host_alias" \
        "$expected_target" 'sudo -n /bin/bash -s' \
        <"$action20m_outer_remote_script" >"$action20m_outer_stdout" 2>"$action20m_outer_stderr" ||
        action20m_outer_status=$?
    emit_stream remote_stdout "$action20m_outer_stdout" || action20m_outer_stream_failure=true
    emit_stream remote_stderr "$action20m_outer_stderr" || action20m_outer_stream_failure=true
    printf '%s_remote_status=%s\n' "$prefix" "$action20m_outer_status"
    if [[ "$action20m_outer_stream_failure" = true ]]; then
        trap - EXIT
        printf '%s_protected_evidence=%s\n' "$prefix" "$action20m_outer_work_root" >&2
        return 97
    fi
    if [[ "$action20m_outer_status" -eq 0 ]]; then
        validate_success "$action20m_outer_stdout" "$action20m_outer_stderr" \
            "$action20m_outer_status" "$action20m_outer_expected" "$action20m_outer_actual" || return 97
    else
        validate_failure "$action20m_outer_stdout" "$action20m_outer_stderr" \
            "$action20m_outer_status" || return 97
        return "$action20m_outer_status"
    fi
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_main_configuration_mutated=true\n' "$prefix"
    printf '%s_backup_retained=true\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_transition=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates || exit $?
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION20M_TEST_MODE:-}" = 1 ]] || exit 64
        run_transport || exit $?
        ;;
    --test-validate-success)
        if [[ $# -ne 4 ]]; then
            printf '%s_test_validator_argument_count=false\n' "$prefix" >&2
            exit 64
        fi
        if [[ "${CADDY_ACTION20M_TEST_MODE:-}" != 1 ]]; then
            printf '%s_test_validator_mode=false\n' "$prefix" >&2
            exit 64
        fi
        action20m_outer_test_root=$(mktemp -d /tmp/caddy-action20m-validator.XXXXXX) || exit 1
        readonly action20m_outer_test_root
        trap 'rm -rf -- "$action20m_outer_test_root"' EXIT
        validate_success "$2" "$3" "$4" \
            "$action20m_outer_test_root/expected" "$action20m_outer_test_root/actual"
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates || exit $?
        run_transport || exit $?
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
