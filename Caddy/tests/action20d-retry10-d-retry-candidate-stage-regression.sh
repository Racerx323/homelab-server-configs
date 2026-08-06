#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20d_d_retry_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_d_retry_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20d_d_retry_regression_label" >&2
    return 1
}
stage_rejects_candidate_mode() {
    local action20d_d_retry_rejected_mode=$1

    chmod "$action20d_d_retry_rejected_mode" "$candidate_stage/$candidate_name"
    ! /bin/bash "$stager" --validate "$candidate_stage" "$fixture_owner" "$fixture_group" \
        >/dev/null 2>&1
}
stage_rejects_directory_mode() {
    local action20d_d_retry_rejected_mode=$1

    chmod "$action20d_d_retry_rejected_mode" "$candidate_stage"
    ! /bin/bash "$stager" --validate "$candidate_stage" "$fixture_owner" "$fixture_group" \
        >/dev/null 2>&1
}
stage_rejects_current() {
    ! /bin/bash "$stager" --validate "$candidate_stage" "$fixture_owner" "$fixture_group" \
        >/dev/null 2>&1
}
create_fake_ssh() {
    local action20d_d_retry_fake_ssh=$1

    cat >"$action20d_d_retry_fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"$CADDY_ACTION20D_RETRY10_D_CAPTURE"
while IFS= read -r label; do
    printf 'action_20d_retry10_d_retry_check_%s=true\n' "$label"
done < <(/bin/bash "$CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER" --expected-checks)
printf '%s\n' \
    'action_20d_retry10_d_retry_preflight_complete=true' \
    'action_20d_retry10_d_retry_mutation_started=true' \
    'action_20d_retry10_d_retry_backup_path=/var/backups/caddy-ha/action20d-retry10-d-retry-node-a-health-instrumentation.ABC123' \
    'action_20d_retry10_d_retry_helper_invoked_by_transaction=false' \
    'action_20d_retry10_d_retry_keepalived_reloaded=false' \
    'action_20d_retry10_d_retry_service_mutations=false' \
    'action_20d_retry10_d_retry_vrrp_mutations=false' \
    'action_20d_retry10_d_retry_vip_mutations=false' \
    'action_20d_retry10_d_retry_persistent_mutation_scope=health_helper,rollback_backup' \
    'action_20d_retry10_d_retry_install_complete=true'
FAKE_SSH
    chmod 0755 "$action20d_d_retry_fake_ssh"
}
production_bundle_exact() {
    grep -Fq 'chown -R root:root "$bundle_stage/payload"' "$captured_remote" || return 1
    grep -Fq 'chmod 0700 "$bundle_stage/payload" "$bundle_stage/payload"/*' \
        "$captured_remote" || return 1
    grep -Fq -- \
        '--apply "$bundle_stage/payload/check-caddy-instrumented-action20d-retry10-d.sh" "$bundle_stage/candidate" root caddy-tls' \
        "$captured_remote" || return 1
    grep -Fq -- '--stage "$bundle_stage/candidate"' "$captured_remote" || return 1
    [[ "$(grep -Fc -- '--apply ' "$captured_remote")" -eq 1 ]] || return 1
    [[ "$(grep -Fc -- '--stage ' "$captured_remote")" -eq 1 ]] || return 1
}

fixture_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
readonly generated_root=$fixture_root/generated
/bin/bash "$builder" --output "$generated_root" >/dev/null
readonly candidate_name=check-caddy-instrumented-action20d-retry10-d.sh
readonly source_candidate=$generated_root/$candidate_name
readonly installer=$generated_root/install-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
readonly runner=$generated_root/run-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
readonly stager=$generated_root/stage-node-a-caddy-health-instrumentation-action20d-retry10-d-retry.sh
readonly candidate_stage=$fixture_root/candidate
fixture_owner=$(id -un)
readonly fixture_owner
fixture_group=$(id -gn)
readonly fixture_group
readonly captured_remote=$fixture_root/remote.sh
readonly runner_stdout=$fixture_root/runner.stdout
readonly runner_stderr=$fixture_root/runner.stderr
readonly fake_ssh=$fixture_root/fake-ssh

check stager_apply /bin/bash "$stager" --apply "$source_candidate" "$candidate_stage" \
    "$fixture_owner" "$fixture_group"
check stage_directory_mode test "$(stat -c '%a' "$candidate_stage")" = 710
check stage_directory_owner test "$(stat -c '%U:%G' "$candidate_stage")" = \
    "$fixture_owner:$fixture_group"
check candidate_mode test "$(stat -c '%a' "$candidate_stage/$candidate_name")" = 750
check candidate_owner test "$(stat -c '%U:%G' "$candidate_stage/$candidate_name")" = \
    "$fixture_owner:$fixture_group"
check candidate_hash test "$(file_hash "$candidate_stage/$candidate_name")" = \
    "$(file_hash "$source_candidate")"
check exact_stage_accepted /bin/bash "$stager" --validate "$candidate_stage" \
    "$fixture_owner" "$fixture_group"

check unreadable_0700_rejected stage_rejects_candidate_mode 0700
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0755_rejected stage_rejects_candidate_mode 0755
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0760_rejected stage_rejects_candidate_mode 0760
chmod 0750 "$candidate_stage/$candidate_name"
check over_permissive_0770_rejected stage_rejects_candidate_mode 0770
chmod 0750 "$candidate_stage/$candidate_name"
check parent_unsearchable_0700_rejected stage_rejects_directory_mode 0700
chmod 0710 "$candidate_stage"

touch "$candidate_stage/unexpected"
check extra_payload_rejected stage_rejects_current
rm -f "$candidate_stage/unexpected"
ln -s "$candidate_name" "$candidate_stage/unexpected-link"
check symlink_payload_rejected stage_rejects_current
rm -f "$candidate_stage/unexpected-link"
check recovered_exact_stage /bin/bash "$stager" --validate "$candidate_stage" \
    "$fixture_owner" "$fixture_group"

create_fake_ssh "$fake_ssh"
CADDY_ACTION20D_RETRY10_D_SSH_BINARY=$fake_ssh \
    CADDY_ACTION20D_RETRY10_D_CAPTURE=$captured_remote \
    CADDY_ACTION20D_RETRY10_D_TEST_INSTALLER=$installer \
    /bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr"
check intercepted_runner_stderr_empty test ! -s "$runner_stderr"
check intercepted_runner_complete grep -Fq \
    'action_20d_retry10_d_retry_runner_cleanup_complete=true' "$runner_stdout"
check production_bundle_contract production_bundle_exact
check no_node_b_reference test \
    "$(grep -Ec '10\.1\.0\.54|pihole00|node-b' "$captured_remote" || true)" -eq 0

printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
