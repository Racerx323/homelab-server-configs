#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_regression
readonly expected_builder_sha256=1c64a013da42f07ce2add60d66159f4d7f591b6db91a30bfb2aaa49c427ff421
readonly expected_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly expected_stager_sha256=9596a34fb816d8e15068741875ab5ee4435d3a006fcf4812bb601ff2f6d4d295
readonly expected_installer_sha256=e4c3284a4c75ff40935c0d57b533e298e9f18fb3fece5e0626eff9f6e5784025
readonly expected_runner_sha256=326e30073aaee39ea0516195ba06eb0622f58d0f726e5b0ceb53000b17f8b04e

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-caddy-health-helper-action20i.sh

fixture_root=$(mktemp -d /tmp/caddy-action20i-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT INT TERM

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20i_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20i_regression_label" >&2
    return 1
}
create_fake_ssh() {
    local action20i_fake_ssh_path=$1

    cat >"$action20i_fake_ssh_path" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"$CADDY_ACTION20I_CAPTURE"
mapfile -t labels < <(/bin/bash "$CADDY_ACTION20I_TEST_INSTALLER" --expected-checks)
case "${CADDY_ACTION20I_FIXTURE_MODE:?}" in
    success | missing | duplicate)
        if [[ "$CADDY_ACTION20I_FIXTURE_MODE" = missing ]]; then
            unset 'labels[0]'
        fi
        for label in "${labels[@]}"; do
            printf 'action_20i_check_%s=true\n' "$label"
        done
        if [[ "$CADDY_ACTION20I_FIXTURE_MODE" = duplicate ]]; then
            printf 'action_20i_check_%s=true\n' "${labels[1]}"
        fi
        printf '%s\n' \
            'action_20i_preflight_complete=true' \
            'action_20i_mutation_started=true' \
            'action_20i_backup_path=/var/backups/caddy-ha/action20i-node-b-health-helper.ABC123' \
            'action_20i_helper_invoked_by_transaction=true' \
            'action_20i_keepalived_reloaded=false' \
            'action_20i_service_mutations=false' \
            'action_20i_vrrp_mutations=false' \
            'action_20i_vip_mutations=false' \
            'action_20i_persistent_mutation_scope=health_helper,rollback_backup' \
            'action_20i_install_complete=true'
        ;;
    rollback)
        printf '%s\n' 'action_20i_mutation_started=true'
        printf '%s\n' \
            'action_20i_rollback_started=true' \
            'action_20i_rollback_complete=true' >&2
        exit 1
        ;;
    *) exit 64 ;;
esac
FAKE_SSH
    chmod 0755 "$action20i_fake_ssh_path"
}
run_fixture() {
    local action20i_fixture_mode=$1
    local action20i_expected_status=$2
    local action20i_fixture_status=0
    local action20i_fixture_stdout=$fixture_root/$action20i_fixture_mode.stdout
    local action20i_fixture_stderr=$fixture_root/$action20i_fixture_mode.stderr

    CADDY_ACTION20I_CAPTURE=$fixture_root/$action20i_fixture_mode.remote \
        CADDY_ACTION20I_TEST_INSTALLER=$installer \
        CADDY_ACTION20I_FIXTURE_MODE=$action20i_fixture_mode \
        CADDY_ACTION20I_SSH_BINARY=$fake_ssh \
        /bin/bash "$runner" >"$action20i_fixture_stdout" \
        2>"$action20i_fixture_stderr" || action20i_fixture_status=$?
    if [[ "$action20i_fixture_status" -ne "$action20i_expected_status" ]]; then
        printf 'fixture=%s observed_status=%s expected_status=%s\n' \
            "$action20i_fixture_mode" "$action20i_fixture_status" \
            "$action20i_expected_status" >&2
        sed -n '1,240p' "$action20i_fixture_stdout" >&2
        sed -n '1,240p' "$action20i_fixture_stderr" >&2
        return 1
    fi
    [[ -s "$fixture_root/$action20i_fixture_mode.remote" ]] || return 1
    grep -Fqx 'cd /' "$fixture_root/$action20i_fixture_mode.remote" || return 1
}

readonly output_root=$fixture_root/output
record_check builder_hash test "$(file_hash "$builder")" = "$expected_builder_sha256"
/bin/bash "$builder" --output "$output_root" >"$fixture_root/builder.stdout"
readonly candidate=$output_root/check-caddy-vrrp-action20i.sh
readonly stager=$output_root/stage-node-b-caddy-health-helper-action20i.sh
readonly installer=$output_root/install-node-b-caddy-health-helper-action20i.sh
readonly runner=$output_root/run-node-b-caddy-health-helper-action20i.sh
record_check candidate_hash test "$(file_hash "$candidate")" = "$expected_candidate_sha256"
record_check stager_hash test "$(file_hash "$stager")" = "$expected_stager_sha256"
record_check installer_hash test "$(file_hash "$installer")" = "$expected_installer_sha256"
record_check runner_hash test "$(file_hash "$runner")" = "$expected_runner_sha256"
record_check installer_expected_labels_unique /bin/bash -c \
    'test "$($1 --expected-checks | wc -l)" -eq "$($1 --expected-checks | LC_ALL=C sort -u | wc -l)"' \
    _ "$installer"
record_check candidate_service_check grep -Fq \
    'systemctl is-active --quiet caddy' "$candidate"
record_check candidate_endpoint_check grep -Fq \
    'https://localhost' "$candidate"
record_check candidate_runtime_validation_absent test \
    "$(grep -Fc 'caddy validate' "$candidate" || true)" -eq 0
record_check installer_full_validation_present grep -Fq \
    'full_caddy_validation_exact_context' "$installer"
record_check installer_fragment_inactive grep -Fq \
    'main_excludes_fragment' "$installer"
record_check installer_zero_caddy_vips grep -Fq \
    'caddy_ipv4_still_absent' "$installer"
record_check installer_no_keepalived_reload test \
    "$(grep -Ec 'systemctl[[:space:]]+(reload|restart)[[:space:]]+keepalived' "$installer" || true)" -eq 0
record_check runner_node_b_target grep -Fqx \
    'readonly expected_target=pi@10.1.0.54' "$runner"
record_check runner_node_b_alias grep -Fqx \
    'readonly expected_host_alias=pihole00.local.theama.co' "$runner"
record_check runner_node_a_target_absent test \
    "$(grep -Fc '10.1.0.53' "$runner" || true)" -eq 0

readonly fake_ssh=$fixture_root/fake-ssh
create_fake_ssh "$fake_ssh"
record_check production_success run_fixture success 0
record_check missing_label_rejected run_fixture missing 1
record_check duplicate_label_rejected run_fixture duplicate 1
record_check rollback_accepted run_fixture rollback 1
record_check transmitted_node_b_installer grep -Fq \
    'install-node-b-caddy-health-helper-action20i.sh' "$fixture_root/success.remote"
record_check transmitted_direct_run_stage grep -Fq \
    'candidate_stage=$(mktemp -d /run/caddy-action20i-candidate.XXXXXX)' \
    "$fixture_root/success.remote"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
