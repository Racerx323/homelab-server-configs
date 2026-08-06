#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly candidate=$caddy_root/scripts/check-caddy-vrrp-action20h.sh
readonly installer=$caddy_root/scripts/install-node-a-caddy-health-helper-action20h.sh
readonly stager=$caddy_root/scripts/stage-node-a-caddy-health-helper-action20h.sh
readonly runner=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h.sh

fixture_root=$(mktemp -d /tmp/caddy-action20h-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20h_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_regression_label" >&2
    return 1
}
source_contract() {
    grep -Fq 'health_run_stage service systemctl is-active --quiet caddy' "$candidate" || return 1
    grep -Fq 'health_run_stage endpoint curl' "$candidate" || return 1
    [[ "$(grep -Fc 'caddy validate' "$candidate" || true)" -eq 0 ]] || return 1
    awk 'index($0, "--max-time 3") { count++ } END { exit(count == 1 ? 0 : 1) }' \
        "$candidate" || return 1
}
transaction_contract() {
    local action20h_validation_line
    local action20h_mutation_line
    local action20h_observation_line

    grep -Fq 'expected_old_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810' "$installer" || return 1
    grep -Fq 'expected_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3' "$installer" || return 1
    grep -Fq 'setpriv --reuid "$action20h_script_uid" --regid "$action20h_tls_gid"' "$installer" || return 1
    grep -Fq 'caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' "$installer" || return 1
    grep -Fq "grep -Fc 'already running, expect idle - skipping run'" "$installer" || return 1
    grep -Fq "grep -Ec 'Script .check_caddy. now returning (1|143)'" "$installer" || return 1
    grep -Fq "sed -n '1p' /run/caddy-ha/vrrp-state" "$installer" || return 1
    grep -Fq -- '--after-cursor "$journal_cursor"' "$installer" || return 1
    ! grep -Eq 'systemctl[[:space:]]+(reload|restart|start|stop)[[:space:]]+keepalived' "$installer" || return 1
    action20h_validation_line=$(grep -nF -m1 'record_check full_caddy_validation_exact_context' "$installer" | cut -d: -f1) || return 1
    action20h_mutation_line=$(grep -nF 'mutation_started=true' "$installer" | tail -n 1 | cut -d: -f1) || return 1
    action20h_observation_line=$(grep -nF 'validate_poststate' "$installer" | tail -n 1 | cut -d: -f1) || return 1
    [[ "$action20h_validation_line" -lt "$action20h_mutation_line" ]] || return 1
    [[ "$action20h_mutation_line" -lt "$action20h_observation_line" ]] || return 1
}
create_fake_ssh() {
    local action20h_fake_ssh=$1

    cat >"$action20h_fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"$CADDY_ACTION20H_CAPTURE"
while IFS= read -r label; do
    [[ "${CADDY_ACTION20H_FAKE_MODE:-success}" = missing_label && "$label" = vrrp_master_after ]] && continue
    printf 'action_20h_check_%s=true\n' "$label"
done < <(/bin/bash "$CADDY_ACTION20H_TEST_INSTALLER" --expected-checks)
printf '%s\n' \
    'action_20h_preflight_complete=true' \
    'action_20h_mutation_started=true' \
    'action_20h_backup_path=/var/backups/caddy-ha/action20h-node-a-health-helper.ABC123' \
    'action_20h_helper_invoked_by_transaction=false' \
    'action_20h_keepalived_reloaded=false' \
    'action_20h_service_mutations=false' \
    'action_20h_vrrp_mutations=false' \
    'action_20h_vip_mutations=false' \
    'action_20h_persistent_mutation_scope=health_helper,rollback_backup' \
    'action_20h_install_complete=true'
FAKE_SSH
    chmod 0755 "$action20h_fake_ssh"
}
captured_remote=$fixture_root/remote.sh
readonly captured_remote
fake_ssh=$fixture_root/fake-ssh
readonly fake_ssh
create_fake_ssh "$fake_ssh"
export CADDY_ACTION20H_CAPTURE=$captured_remote
export CADDY_ACTION20H_TEST_INSTALLER=$installer
export CADDY_ACTION20H_SSH_BINARY=$fake_ssh

check candidate_contract source_contract
check transaction_contract transaction_contract
check candidate_self_test /bin/bash "$candidate" --self-test
check installer_self_test /bin/bash "$installer" --self-test
check stager_self_test /bin/bash -n "$stager"
check runner_self_test /bin/bash "$runner" --self-test
check intercepted_success /bin/bash "$runner"
check remote_captured test -s "$captured_remote"
check direct_run_candidate_stage grep -Fq \
    'candidate_stage=$(mktemp -d /run/caddy-action20h-candidate.XXXXXX)' \
    "$captured_remote"
check protected_payload_stage grep -Fq \
    'payload_stage=$(mktemp -d /run/caddy-action20h-payload.XXXXXX)' \
    "$captured_remote"
check exact_stager_boundary grep -Fq -- \
    '--adopt "$payload_stage/payload/check-caddy-vrrp-action20h.sh" "$candidate_stage" root caddy-tls /run root root' \
    "$captured_remote"
check node_b_absent test "$(grep -Ec '10\.1\.0\.54|pihole00|node-b' "$captured_remote" || true)" -eq 0
check missing_label_rejected env CADDY_ACTION20H_FAKE_MODE=missing_label \
    /bin/bash -c '! /bin/bash "$1" >/dev/null 2>&1' _ "$runner"
printf '%s_network_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
