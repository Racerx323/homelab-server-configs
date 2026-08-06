#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20d_d_retry2_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry2_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry2_regression_label" >&2
    return 1
}
stage_rejects_candidate_mode() {
    local action20d_d_retry2_rejected_mode=$1

    chmod "$action20d_d_retry2_rejected_mode" "$candidate_stage/$candidate_name"
    ! /bin/bash "$stager" --validate "$candidate_stage" "$final_owner" \
        "$final_group" "$run_root" >/dev/null 2>&1
}
create_fake_ssh() {
    local action20d_d_retry2_fake_ssh=$1

    cat >"$action20d_d_retry2_fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"$CADDY_ACTION20D_RETRY10_D_CAPTURE"
while IFS= read -r label; do
    printf 'action_20d_retry10_d_retry2_check_%s=true\n' "$label"
done < <(/bin/bash "$CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER" --expected-checks)
printf '%s\n' \
    'action_20d_retry10_d_retry2_preflight_complete=true' \
    'action_20d_retry10_d_retry2_mutation_started=true' \
    'action_20d_retry10_d_retry2_backup_path=/var/backups/caddy-ha/action20d-retry10-d-retry2-node-a-health-instrumentation.ABC123' \
    'action_20d_retry10_d_retry2_helper_invoked_by_transaction=false' \
    'action_20d_retry10_d_retry2_keepalived_reloaded=false' \
    'action_20d_retry10_d_retry2_service_mutations=false' \
    'action_20d_retry10_d_retry2_vrrp_mutations=false' \
    'action_20d_retry10_d_retry2_vip_mutations=false' \
    'action_20d_retry10_d_retry2_persistent_mutation_scope=health_helper,rollback_backup' \
    'action_20d_retry10_d_retry2_install_complete=true'
FAKE_SSH
    chmod 0755 "$action20d_d_retry2_fake_ssh"
}
line_number() {
    local action20d_d_retry2_pattern=$1

    grep -nF -m1 -- "$action20d_d_retry2_pattern" "$captured_remote" | cut -d: -f1
}
production_bundle_exact() {
    local action20d_d_retry2_payload_line
    local action20d_d_retry2_empty_candidate_line
    local action20d_d_retry2_trap_line
    local action20d_d_retry2_candidate_line
    local action20d_d_retry2_adopt_line
    local action20d_d_retry2_install_line

    action20d_d_retry2_payload_line=$(line_number \
        'payload_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-payload.XXXXXX)') || return 1
    action20d_d_retry2_empty_candidate_line=$(line_number 'candidate_stage=') || return 1
    action20d_d_retry2_trap_line=$(line_number 'trap cleanup_payload_stage EXIT') || return 1
    action20d_d_retry2_candidate_line=$(line_number \
        'candidate_stage=$(mktemp -d /run/caddy-action20d-retry10-d-retry2-candidate.XXXXXX)') || return 1
    action20d_d_retry2_adopt_line=$(line_number \
        '--adopt "$payload_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$candidate_stage" root caddy-tls /run root root') || return 1
    action20d_d_retry2_install_line=$(line_number '--stage "$candidate_stage"') || return 1
    [[ "$action20d_d_retry2_payload_line" -lt "$action20d_d_retry2_empty_candidate_line" ]] || return 1
    [[ "$action20d_d_retry2_empty_candidate_line" -lt "$action20d_d_retry2_trap_line" ]] || return 1
    [[ "$action20d_d_retry2_trap_line" -lt "$action20d_d_retry2_candidate_line" ]] || return 1
    [[ "$action20d_d_retry2_candidate_line" -lt "$action20d_d_retry2_adopt_line" ]] || return 1
    [[ "$action20d_d_retry2_adopt_line" -lt "$action20d_d_retry2_install_line" ]] || return 1
    grep -Fq 'chown -R root:root "$payload_stage/payload"' "$captured_remote" || return 1
    grep -Fq 'chmod 0700 "$payload_stage/payload" "$payload_stage/payload"/*' \
        "$captured_remote" || return 1
    grep -Fq '[[ -z "$candidate_stage" ]] || rm -rf -- "$candidate_stage"' \
        "$captured_remote" || return 1
    [[ "$(grep -Fc -- '--adopt ' "$captured_remote")" -eq 1 ]] || return 1
    [[ "$(grep -Fc -- '--stage ' "$captured_remote")" -eq 1 ]] || return 1
}
prepare_runtime_identity() {
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        [[ "$(id -u)" -eq 0 ]] || return 1
        if getent group caddy-tls >/dev/null; then
            [[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]] || return 1
        else
            ! getent group 991 >/dev/null || return 1
            groupadd --gid 991 caddy-tls || return 1
        fi
        if getent passwd keepalived_script >/dev/null; then
            [[ "$(id -u keepalived_script)" -eq 993 ]] || return 1
        else
            ! getent passwd 993 >/dev/null || return 1
            useradd --system --uid 993 --gid 991 --no-create-home \
                --shell /usr/sbin/nologin keepalived_script || return 1
        fi
        runtime_uid=$(id -u keepalived_script) || return 1
        runtime_gid=$(getent group caddy-tls | cut -d: -f3) || return 1
        final_owner=root
        final_group=caddy-tls
        initial_owner=root
        initial_group=root
        exact_context=true
    else
        runtime_uid=$(id -u) || return 1
        runtime_gid=$(id -g) || return 1
        final_owner=$(id -un) || return 1
        final_group=$(id -gn) || return 1
        initial_owner=$final_owner
        initial_group=$final_group
        exact_context=false
    fi
    readonly runtime_uid runtime_gid final_owner final_group initial_owner initial_group exact_context
}
runtime_can_read_and_execute_candidate() {
    if [[ "$exact_context" = true ]]; then
        setpriv --reuid "$runtime_uid" --regid "$runtime_gid" --clear-groups -- \
            test -r "$candidate_stage/$candidate_name" || return 1
        setpriv --reuid "$runtime_uid" --regid "$runtime_gid" --clear-groups -- \
            /bin/bash "$candidate_stage/$candidate_name" --self-test >/dev/null || return 1
        return 0
    fi
    test -r "$candidate_stage/$candidate_name" || return 1
    /bin/bash "$candidate_stage/$candidate_name" --self-test >/dev/null || return 1
}
exact_context_contract() {
    [[ "$exact_context" = true ]] || return 1
    [[ "$(id -u keepalived_script)" -eq 993 ]] || return 1
    [[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$run_root")" = root:root:755 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$payload_stage")" = root:root:700 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$candidate_stage")" = root:caddy-tls:710 ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$candidate_stage/$candidate_name")" = root:caddy-tls:750 ]] || return 1
    runtime_can_read_and_execute_candidate || return 1
    ! setpriv --reuid "$runtime_uid" --regid "$runtime_gid" --clear-groups -- \
        test -r "$payload_source" || return 1
}
root_only_ancestor_rejected() {
    local action20d_d_retry2_blocked_root=$run_root/blocked-parent
    local action20d_d_retry2_blocked_stage=$action20d_d_retry2_blocked_root/candidate

    install -d -o root -g root -m 0700 "$action20d_d_retry2_blocked_root"
    install -d -o root -g caddy-tls -m 0710 "$action20d_d_retry2_blocked_stage"
    install -o root -g caddy-tls -m 0750 "$source_candidate" \
        "$action20d_d_retry2_blocked_stage/$candidate_name"
    ! setpriv --reuid "$runtime_uid" --regid "$runtime_gid" --clear-groups -- \
        test -r "$action20d_d_retry2_blocked_stage/$candidate_name"
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-regression.XXXXXX)
readonly fixture_root
payload_stage=
candidate_stage=
cleanup() {
    [[ -z "$candidate_stage" ]] || rm -rf -- "$candidate_stage"
    [[ -z "$payload_stage" ]] || rm -rf -- "$payload_stage"
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT
readonly generated_root=$fixture_root/generated
/bin/bash "$builder" --output "$generated_root" >/dev/null
readonly candidate_name=check-caddy-instrumented-action20d-retry10-d.sh
readonly source_candidate=$generated_root/$candidate_name
readonly installer=$generated_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
readonly runner=$generated_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
readonly stager=$generated_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry2.sh
prepare_runtime_identity
if [[ "$exact_context" = true ]]; then
    run_root=/run
else
    run_root=$fixture_root/run
    install -d -m 0755 "$run_root"
fi
readonly run_root
payload_stage=$(mktemp -d "$run_root/caddy-action20d-retry10-d-retry2-payload.XXXXXX")
readonly payload_stage
candidate_stage=$(mktemp -d "$run_root/caddy-action20d-retry10-d-retry2-candidate.XXXXXX")
readonly candidate_stage
install -d -o "$initial_owner" -g "$initial_group" -m 0700 "$payload_stage/payload"
payload_source=$payload_stage/payload/$candidate_name
readonly payload_source
install -o "$initial_owner" -g "$initial_group" -m 0700 "$source_candidate" "$payload_source"

check stager_adopt /bin/bash "$stager" --adopt "$payload_source" "$candidate_stage" \
    "$final_owner" "$final_group" "$run_root" "$initial_owner" "$initial_group"
check direct_parent test "$(dirname -- "$candidate_stage")" = "$run_root"
check candidate_mode test "$(stat -c '%a' "$candidate_stage/$candidate_name")" = 750
check candidate_hash test "$(file_hash "$candidate_stage/$candidate_name")" = \
    "$(file_hash "$source_candidate")"
check complete_path_runtime_context runtime_can_read_and_execute_candidate

check unreadable_0700_rejected stage_rejects_candidate_mode 0700
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0755_rejected stage_rejects_candidate_mode 0755
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0760_rejected stage_rejects_candidate_mode 0760
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0770_rejected stage_rejects_candidate_mode 0770
chmod 0750 "$candidate_stage/$candidate_name"
check exact_stage_recovered /bin/bash "$stager" --validate "$candidate_stage" \
    "$final_owner" "$final_group" "$run_root"

if [[ "$exact_context" = true ]]; then
    check exact_named_cleared_group_context exact_context_contract
    check root_only_ancestor_rejected root_only_ancestor_rejected
    printf '%s_exact_context_executed=true\n' "$prefix"
else
    printf '%s_exact_context_deferred_to_canonical_container=true\n' "$prefix"
fi

readonly captured_remote=$fixture_root/remote.sh
readonly runner_stdout=$fixture_root/runner.stdout
readonly runner_stderr=$fixture_root/runner.stderr
readonly fake_ssh=$fixture_root/fake-ssh
create_fake_ssh "$fake_ssh"
runner_status=0
CADDY_ACTION20D_RETRY10_D_SSH_BINARY=$fake_ssh \
    CADDY_ACTION20D_RETRY10_D_CAPTURE=$captured_remote \
    CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER=$installer \
    /bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
printf '%s_runner_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$runner_stdout")"
printf '%s_runner_stdout_sha256=%s\n' "$prefix" "$(file_hash "$runner_stdout")"
printf '%s_runner_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$runner_stderr")"
printf '%s_runner_stderr_sha256=%s\n' "$prefix" "$(file_hash "$runner_stderr")"
if [[ -s "$runner_stderr" ]]; then
    printf '%s_runner_stderr_begin\n' "$prefix"
    cat "$runner_stderr"
    printf '%s_runner_stderr_end\n' "$prefix"
fi
check intercepted_runner_status test "$runner_status" -eq 0
check intercepted_runner_stderr_empty test ! -s "$runner_stderr"
check intercepted_runner_complete grep -Fq \
    'action_20d_retry10_d_retry2_runner_cleanup_complete=true' "$runner_stdout"
check production_bundle_contract production_bundle_exact
check no_node_b_reference test \
    "$(grep -Ec '10\.1\.0\.54|pihole00|node-b' "$captured_remote" || true)" -eq 0

printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
