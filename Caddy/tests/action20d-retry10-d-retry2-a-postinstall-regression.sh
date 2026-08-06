#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_a_regression
readonly probe_prefix=action_20d_retry10_d_retry2_a
readonly expected_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly expected_backup_path=/var/backups/caddy-ha/action20d-retry10-d-retry2-node-a-health-instrumentation.18d7kI
readonly expected_inspector_sha256=2904f0e0d6cfbe87d4f041998c7bad294215f93522b37995c93fa57a4b3c18ff

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20d_retry2_a_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20d_retry2_a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20d_retry2_a_regression_label" >&2
    return 1
}
emit_capture() {
    local action20d_retry2_a_regression_capture_label=$1

    if [[ "$action20d_retry2_a_regression_capture_label" == *_stderr ]]; then
        printf '%s_capture_%s_bytes=0\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_capture_label"
        printf '%s_capture_%s_lines=0\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_capture_label"
        printf '%s_capture_%s_sha256=%s\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_capture_label" \
            e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        printf '%s_capture_%s_classification=bounded_safe\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_capture_label"
        printf '%s_capture_%s_content_secured=empty\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_capture_label"
        return 0
    fi
    printf '%s_capture_%s_bytes=56\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label"
    printf '%s_capture_%s_lines=1\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label"
    printf '%s_capture_%s_sha256=%s\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label" \
        c54624ec3637e76415fbda315ad2aa937433939ee97203051de705d40bf84f2c
    printf '%s_capture_%s_classification=bounded_safe\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label"
    printf '%s_capture_%s_begin\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label"
    printf '%s_capture_%s_content=caddy_ha_health_instrumentation_self_test_complete=true\n' \
        "$probe_prefix" "$action20d_retry2_a_regression_capture_label"
    printf '%s_capture_%s_end\n' "$probe_prefix" \
        "$action20d_retry2_a_regression_capture_label"
}
write_valid_transcript() {
    local action20d_retry2_a_regression_output_path=$1
    local action20d_retry2_a_regression_expected_count
    local action20d_retry2_a_regression_label
    local action20d_retry2_a_regression_snapshot_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    action20d_retry2_a_regression_expected_count=$(/bin/bash "$inspector" \
        --expected-assertions | wc -l)
    {
        emit_capture root_self_test_stdout
        emit_capture root_self_test_stderr
        emit_capture exact_context_self_test_stdout
        emit_capture exact_context_self_test_stderr
        while IFS= read -r action20d_retry2_a_regression_label; do
            printf '%s_assertion_%s=true\n' "$probe_prefix" \
                "$action20d_retry2_a_regression_label"
        done < <(/bin/bash "$inspector" --expected-assertions)
        printf '%s_value_expected_assertion_count=%s\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_expected_count"
        printf '%s_value_health_sha256=%s\n' "$probe_prefix" \
            "$expected_health_sha256"
        printf '%s_value_backup_path=%s\n' "$probe_prefix" "$expected_backup_path"
        printf '%s_value_before_snapshot_sha256=%s\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_snapshot_hash"
        printf '%s_value_after_snapshot_sha256=%s\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_snapshot_hash"
        printf '%s_assertion_count=%s\n' "$probe_prefix" \
            "$action20d_retry2_a_regression_expected_count"
        printf '%s_failed_assertion_count=0\n' "$probe_prefix"
        printf '%s_first_failure=none\n' "$probe_prefix"
        printf '%s_full_health_helper_invoked=false\n' "$probe_prefix"
        printf '%s_notification_helper_invoked=false\n' "$probe_prefix"
        printf '%s_filesystem_mutations=false\n' "$probe_prefix"
        printf '%s_service_mutations=false\n' "$probe_prefix"
        printf '%s_keepalived_mutations=false\n' "$probe_prefix"
        printf '%s_vrrp_mutations=false\n' "$probe_prefix"
        printf '%s_vip_mutations=false\n' "$probe_prefix"
        printf '%s_network_mutations=false\n' "$probe_prefix"
        printf '%s_persistent_mutations=false\n' "$probe_prefix"
        printf '%s_remote_cleanup_complete=true\n' "$probe_prefix"
        printf '%s_remote_complete=true\n' "$probe_prefix"
    } >"$action20d_retry2_a_regression_output_path"
}
expect_rejected() {
    local action20d_retry2_a_regression_fixture=$1
    local action20d_retry2_a_regression_error=$2
    local action20d_retry2_a_regression_status=${3:-0}

    ! /bin/bash "$runner" --validate-transcript \
        "$action20d_retry2_a_regression_fixture" \
        "$action20d_retry2_a_regression_error" \
        "$action20d_retry2_a_regression_status" >/dev/null 2>&1
}

work_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-a-regression.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly valid=$work_root/valid.stdout
readonly empty_error=$work_root/empty.stderr
readonly invalid_error=$work_root/invalid.stderr
: >"$empty_error"
printf 'unexpected error\n' >"$invalid_error"
write_valid_transcript "$valid"

record_check source_hash test "$(file_hash "$inspector")" = \
    "$expected_inspector_sha256"
record_check valid_transcript /bin/bash "$runner" --validate-transcript \
    "$valid" "$empty_error" 0

false_fixture=$work_root/false.stdout
sed "0,/^${probe_prefix}_assertion_health_hash_exact=true$/s//${probe_prefix}_assertion_health_hash_exact=false/" \
    "$valid" >"$false_fixture"
record_check false_assertion_rejected expect_rejected "$false_fixture" "$empty_error"

missing_fixture=$work_root/missing.stdout
grep -Fvx "${probe_prefix}_assertion_health_hash_exact=true" \
    "$valid" >"$missing_fixture"
record_check missing_assertion_rejected expect_rejected "$missing_fixture" "$empty_error"

duplicate_fixture=$work_root/duplicate.stdout
cp "$valid" "$duplicate_fixture"
printf '%s_assertion_health_hash_exact=true\n' "$probe_prefix" >>"$duplicate_fixture"
record_check duplicate_assertion_rejected expect_rejected "$duplicate_fixture" "$empty_error"

capture_fixture=$work_root/capture.stdout
sed '0,/c54624ec3637e76415fbda315ad2aa937433939ee97203051de705d40bf84f2c/s//bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' \
    "$valid" >"$capture_fixture"
record_check altered_capture_rejected expect_rejected "$capture_fixture" "$empty_error"

snapshot_fixture=$work_root/snapshot.stdout
sed "s/^${probe_prefix}_value_after_snapshot_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$/${probe_prefix}_value_after_snapshot_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" \
    "$valid" >"$snapshot_fixture"
record_check changed_snapshot_rejected expect_rejected "$snapshot_fixture" "$empty_error"
record_check nonzero_status_rejected expect_rejected "$valid" "$empty_error" 1
record_check stderr_rejected expect_rejected "$valid" "$invalid_error"

readonly fake_ssh=$work_root/fake-ssh
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

[[ " $* " == *' -T '* ]]
[[ " $* " == *' pi@10.1.0.53 '* ]]
[[ "${*: -1}" = 'cd / && sudo /bin/bash -s -- --inspect' ]]
capture=$(mktemp /tmp/caddy-action20d-retry10-d-retry2-a-fake-ssh.XXXXXX)
trap 'rm -f -- "$capture"' EXIT
cat >"$capture"
[[ "$(sha256sum "$capture" | awk '{ print $1 }')" = \
    "$CADDY_ACTION20D_RETRY2_A_EXPECTED_INSPECTOR_SHA256" ]]
cat "$CADDY_ACTION20D_RETRY2_A_FIXTURE_TRANSCRIPT"
FAKE_SSH
chmod 0755 "$fake_ssh"
readonly production_stdout=$work_root/production.stdout
readonly production_stderr=$work_root/production.stderr
production_status=0
CADDY_ACTION20D_RETRY2_A_SSH_BINARY=$fake_ssh \
    CADDY_ACTION20D_RETRY2_A_EXPECTED_INSPECTOR_SHA256=$expected_inspector_sha256 \
    CADDY_ACTION20D_RETRY2_A_FIXTURE_TRANSCRIPT=$valid \
    /bin/bash "$runner" >"$production_stdout" 2>"$production_stderr" ||
    production_status=$?
readonly production_status
printf '%s_production_stdout_bytes=%s\n' "$prefix" "$(wc -c <"$production_stdout")"
printf '%s_production_stdout_sha256=%s\n' "$prefix" "$(file_hash "$production_stdout")"
printf '%s_production_stderr_bytes=%s\n' "$prefix" "$(wc -c <"$production_stderr")"
printf '%s_production_stderr_sha256=%s\n' "$prefix" "$(file_hash "$production_stderr")"
if [[ "$production_status" -ne 0 ]]; then
    printf '%s_production_stdout_begin\n' "$prefix"
    sed "s/^/${prefix}_production_stdout_content=/" "$production_stdout"
    printf '%s_production_stdout_end\n' "$prefix"
    printf '%s_production_stderr_begin\n' "$prefix"
    sed "s/^/${prefix}_production_stderr_content=/" "$production_stderr"
    printf '%s_production_stderr_end\n' "$prefix"
fi
record_check production_runner_status test "$production_status" -eq 0
record_check production_runner_stderr_empty test ! -s "$production_stderr"
record_check production_runner_remote_status grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_remote_status=0' "$production_stdout"
record_check production_runner_node_a_contact grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_node_a_contacted=true' "$production_stdout"
record_check production_runner_node_b_absent grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_node_b_contacted=false' "$production_stdout"
record_check production_runner_no_full_helper grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_full_health_helper_invoked=false' \
    "$production_stdout"
record_check production_runner_no_mutation grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_persistent_mutations=false' \
    "$production_stdout"
record_check production_runner_complete grep -Fxq \
    'action_20d_retry10_d_retry2_a_runner_cleanup_complete=true' "$production_stdout"

printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
