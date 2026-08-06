#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_retry2_environment_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-helper-action20h-retry2.sh
readonly builder_sha256=272c45dff2975f3b6f0fbbcae39b5054fd25ec4302c73f2213d7cda44094787d
readonly expected_installer_sha256=702f4ed558dccf213a0d24d1587118eabc3fe5da5c1d342a0c8ddac8a8d14dc2
readonly expected_runner_sha256=aff13c6c73cce6ce5f6067f0b10b8c33e3a20b33e1358a3fe4e7f742602cdb3a

fixture_root=$(mktemp -d /tmp/caddy-action20h-retry2-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20h_retry2_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_retry2_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_retry2_regression_label" >&2
    return 1
}
create_fake_caddy() {
    local action20h_retry2_fake_caddy=$1

    cat >"$action20h_retry2_fake_caddy" <<'FAKE_CADDY'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${NODE_ROLE:-}" = node-a ]]
[[ "${NODE_FQDN:-}" = pihole0.local.theama.co ]]
[[ "${NODE_IPV4:-}" = 10.1.0.53 ]]
[[ "${NODE_IPV6:-}" = fd36:5aa8:6971:1::53 ]]
[[ "${CADDY_CONFIG_ROOT:-}" = /etc/caddy/current ]]
[[ "$*" = 'validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' ]]
printf 'fixture_caddy_environment_complete=true\n'
FAKE_CADDY
    chmod 0755 "$action20h_retry2_fake_caddy"
}
create_fake_ssh() {
    local action20h_retry2_fake_ssh=$1

    cat >"$action20h_retry2_fake_ssh" <<'FAKE_SSH'
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
    chmod 0755 "$action20h_retry2_fake_ssh"
}
extract_validation_body() {
    local action20h_retry2_installer=$1
    local action20h_retry2_validation_line

    action20h_retry2_validation_line=$(grep -F \
        'source /etc/default/caddy-ha' "$action20h_retry2_installer") || return 1
    action20h_retry2_validation_line=${action20h_retry2_validation_line#*\'}
    action20h_retry2_validation_line=${action20h_retry2_validation_line%\' \\}
    printf '%s\n' "$action20h_retry2_validation_line"
}
run_populated_fixture() {
    local action20h_retry2_body=$1
    local action20h_retry2_fixture_body

    action20h_retry2_fixture_body=${action20h_retry2_body//\/etc\/default\/caddy-ha/$fixture_root/populated.env}
    env -i PATH="$fixture_root/bin:/usr/bin:/bin" \
        /bin/bash -c "$action20h_retry2_fixture_body" \
        >"$fixture_root/populated.stdout" 2>"$fixture_root/populated.stderr"
    [[ ! -s "$fixture_root/populated.stderr" ]] || return 1
    [[ "$(cat "$fixture_root/populated.stdout")" = fixture_caddy_environment_complete=true ]]
}
run_absent_fixture() {
    local action20h_retry2_body=$1
    local action20h_retry2_fixture_body
    local action20h_retry2_status=0

    action20h_retry2_fixture_body=${action20h_retry2_body//\/etc\/default\/caddy-ha/$fixture_root/absent.env}
    env -i PATH="$fixture_root/bin:/usr/bin:/bin" \
        /bin/bash -c "$action20h_retry2_fixture_body" \
        >"$fixture_root/absent.stdout" 2>"$fixture_root/absent.stderr" ||
        action20h_retry2_status=$?
    [[ "$action20h_retry2_status" -ne 0 ]] || return 1
    [[ ! -s "$fixture_root/absent.stdout" ]] || return 1
    grep -Fq 'NODE_ROLE' "$fixture_root/absent.stderr" || return 1
    ! grep -Fq fixture_caddy_environment_complete "$fixture_root/absent.stdout"
}

readonly output_root=$fixture_root/output
readonly fake_bin=$fixture_root/bin
install -d -m 0700 "$fake_bin"
create_fake_caddy "$fake_bin/caddy"
printf '%s\n' \
    'NODE_ROLE=node-a' \
    'NODE_FQDN=pihole0.local.theama.co' \
    'NODE_IPV4=10.1.0.53' \
    'NODE_IPV6=fd36:5aa8:6971:1::53' \
    'CADDY_CONFIG_ROOT=/etc/caddy/current' >"$fixture_root/populated.env"
: >"$fixture_root/absent.env"
chmod 0600 "$fixture_root/populated.env" "$fixture_root/absent.env"

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
/bin/bash "$builder" --output "$output_root" >"$fixture_root/builder.stdout"
readonly installer=$output_root/install-node-a-caddy-health-helper-action20h-retry2.sh
readonly runner=$output_root/run-node-a-caddy-health-helper-action20h-retry2.sh
record_check installer_hash test "$(file_hash "$installer")" = "$expected_installer_sha256"
record_check runner_hash test "$(file_hash "$runner")" = "$expected_runner_sha256"
validation_body=$(extract_validation_body "$installer")
readonly validation_body
record_check validation_body_single test \
    "$(grep -Fc 'source /etc/default/caddy-ha' "$installer" || true)" -eq 1
record_check populated_environment run_populated_fixture "$validation_body"
record_check absent_environment_rejected run_absent_fixture "$validation_body"

readonly captured_remote=$fixture_root/remote.sh
readonly fake_ssh=$fixture_root/fake-ssh
create_fake_ssh "$fake_ssh"
export CADDY_ACTION20H_CAPTURE=$captured_remote
export CADDY_ACTION20H_TEST_INSTALLER=$installer
export CADDY_ACTION20H_SSH_BINARY=$fake_ssh
record_check intercepted_production_runner /bin/bash "$runner"
record_check retry2_installer_transmitted grep -Fq \
    'install-node-a-caddy-health-helper-action20h-retry2.sh' "$captured_remote"
sed -n "/<<'ACTION20H_ARCHIVE'/,/^ACTION20H_ARCHIVE$/p" "$captured_remote" |
    sed '1d;$d' | base64 -d >"$fixture_root/transmitted.tar"
install -d -m 0700 "$fixture_root/transmitted"
tar --extract --file "$fixture_root/transmitted.tar" --directory "$fixture_root/transmitted"
record_check environment_source_transmitted grep -Fq \
    'source /etc/default/caddy-ha' \
    "$fixture_root/transmitted/install-node-a-caddy-health-helper-action20h-retry2.sh"
record_check prior_retry_installer_not_invoked test \
    "$(grep -Fc '/install-node-a-caddy-health-helper-action20h-retry.sh' "$captured_remote" || true)" -eq 0
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
