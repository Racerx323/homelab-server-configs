#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly old_installer=$caddy_root/scripts/install-node-a-caddy-health-helper-action20h.sh
readonly new_installer=$caddy_root/scripts/install-node-a-caddy-health-helper-action20h-retry.sh
readonly old_runner=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h.sh
readonly new_runner=$caddy_root/scripts/run-node-a-caddy-health-helper-action20h-retry.sh
readonly old_installer_sha256=dd8b6c8fbbbc3360ce9aef2c460297d56e1753f62e2ec54a7544016c67c7b692
readonly new_installer_sha256=33a834270f8c468e24a573b7ab42cb106d2d25f2624ef783031964771c93874f
readonly old_runner_sha256=82a99e77530f1e53c923dde17e7ce26f646e80fa51e5af357d2068da5c291194
readonly new_runner_sha256=e0ad03a83e75b4e7ec3e4c3beb23458d72c90d13ffc6f0e14a105b070abbd48c

fixture_root=$(mktemp -d /tmp/caddy-action20h-retry-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20h_retry_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry_regression_label" >&2
    return 1
}
source_hashes_exact() {
    [[ "$(file_hash "$old_installer")" = "$old_installer_sha256" ]] || return 1
    [[ "$(file_hash "$new_installer")" = "$new_installer_sha256" ]] || return 1
    [[ "$(file_hash "$old_runner")" = "$old_runner_sha256" ]] || return 1
    [[ "$(file_hash "$new_runner")" = "$new_runner_sha256" ]] || return 1
}
installer_delta_exact() {
    sed 's/check-caddy-instrumented-action20h\.sh/check-caddy-vrrp-action20h.sh/g' \
        "$old_installer" >"$fixture_root/expected-installer"
    cmp -s "$fixture_root/expected-installer" "$new_installer" || return 1
    [[ "$(grep -Fc 'check-caddy-instrumented-action20h.sh' "$old_installer" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fc 'check-caddy-instrumented-action20h.sh' "$new_installer" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fc 'check-caddy-vrrp-action20h.sh' "$new_installer" || true)" -eq 2 ]] || return 1
}
runner_delta_exact() {
    sed \
        -e 's/install-node-a-caddy-health-helper-action20h\.sh/install-node-a-caddy-health-helper-action20h-retry.sh/g' \
        -e 's/dd8b6c8fbbbc3360ce9aef2c460297d56e1753f62e2ec54a7544016c67c7b692/33a834270f8c468e24a573b7ab42cb106d2d25f2624ef783031964771c93874f/g' \
        "$old_runner" >"$fixture_root/expected-runner"
    cmp -s "$fixture_root/expected-runner" "$new_runner"
}
create_fake_ssh() {
    local action20h_retry_fake_ssh=$1

    cat >"$action20h_retry_fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >"$CADDY_ACTION20H_CAPTURE"
while IFS= read -r label; do
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
    chmod 0755 "$action20h_retry_fake_ssh"
}

captured_remote=$fixture_root/remote.sh
readonly captured_remote
fake_ssh=$fixture_root/fake-ssh
readonly fake_ssh
create_fake_ssh "$fake_ssh"
export CADDY_ACTION20H_CAPTURE=$captured_remote
export CADDY_ACTION20H_TEST_INSTALLER=$new_installer
export CADDY_ACTION20H_SSH_BINARY=$fake_ssh

check source_hashes source_hashes_exact
check installer_delta installer_delta_exact
check runner_delta runner_delta_exact
check intercepted_retry /bin/bash "$new_runner"
check corrected_installer_transmitted grep -Fq \
    'install-node-a-caddy-health-helper-action20h-retry.sh' "$captured_remote"
check corrected_candidate_path_transmitted grep -Fq \
    'check-caddy-vrrp-action20h.sh' "$captured_remote"
check stale_candidate_path_absent test \
    "$(grep -Fc 'check-caddy-instrumented-action20h.sh' "$captured_remote" || true)" -eq 0
printf '%s_network_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
