#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2034

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction=$caddy_root/scripts/transact-caddy-ha-reliability-action33b.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-ha-reliability-action33b-outer.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33b.yaml
readonly production_publisher=$caddy_root/scripts/publish-release-v2.sh
readonly production_finalizer=$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh
readonly production_reconciler=$caddy_root/scripts/reconcile-release-v2.sh
fixture_root=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+w "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM

require_literal() { grep -Fq -- "$1" "$2"; }
reject_literal() { ! grep -Fq -- "$1" "$2"; }
for file in "$transaction" "$outer" "$manifest"; do [[ -f "$file" && ! -L "$file" ]]; done
/bin/bash -n "$transaction"
/bin/bash -n "$outer"
/bin/bash "$production_publisher" --help >/dev/null 2>&1
/bin/bash "$production_finalizer" --self-test >/dev/null
/bin/bash "$production_reconciler" --candidate-selection-self-test >/dev/null
CADDY_ACTION33B_SSH_BIN=/bin/false /bin/bash "$outer" --self-test >/tmp/action33b-self-test.stdout
grep -Fxq 'action_33b_outer_self_test_complete=true' /tmp/action33b-self-test.stdout
rm -f -- /tmp/action33b-self-test.stdout

require_literal 'cd / && sudo -n /bin/bash' "$outer"
require_literal '-s -- $mode $role $run_id $scenario $argument' "$outer"
require_literal 'capture_files "$action33b_outer_stdout" "$action33b_outer_stderr" "$action33b_outer_status_file"' "$outer"
require_literal 'wait_ssh_state a-down' "$outer"
require_literal 'wait_ssh_state b-down' "$outer"
require_literal 'wait_ssh_state a-up' "$outer"
require_literal 'wait_ssh_state b-up' "$outer"
require_literal 'cat /proc/sys/kernel/random/boot_id' "$transaction"
require_literal 'systemctl disable --now keepalived.service' "$transaction"
require_literal 'systemd-run --unit "caddy-action33b-reboot-$run_id-$scenario"' "$transaction"
require_literal 'systemd-run --unit "$action33b_remote_unit" --on-active=45s' "$transaction"
require_literal '--publish-emergency' "$outer"
require_literal '--reject-normal' "$outer"
require_literal 'sleep 12' "$outer"
require_literal 'action33b-$run_id-' "$outer"
require_literal 'inventory_tree "$quarantine_root"' "$transaction"
require_literal 'assert_outbound_role_policy "$role"' "$transaction"
reject_literal 'check outbound_empty' "$transaction"
reject_literal 'check node_a_outbound_present' "$transaction"
require_literal 'check node_a_outbound_entries_admissible test' "$transaction"
require_literal 'assert_replay_destination_absent "$action33b_remote_destination"' "$transaction"
replay_absence_line=$(grep -nF 'assert_replay_destination_absent "$action33b_remote_destination"' "$transaction" | cut -d: -f1)
replay_freeze_line=$(grep -nF 'run_captured replay_transport_freeze systemctl stop caddy-lsyncd.service' "$transaction" | cut -d: -f1)
[[ "$replay_absence_line" -lt "$replay_freeze_line" ]]
require_literal 'release-manifest.sha256' "$transaction"
require_literal 'original_release_path_restored' "$transaction"
require_literal 'original_release_manifest_restored' "$transaction"
require_literal 'publish_owned "$argument" false' "$transaction"
require_literal 'publish_owned "$argument" true' "$transaction"
require_literal 'assert_invalid_rejected "$argument"' "$transaction"
require_literal 'assert_replay_incomplete "$argument"' "$transaction"
require_literal 'assert_conflict "$argument"' "$transaction"
require_literal 'active_replay_consumed_once' "$transaction"
require_literal '--rolling-maintenance' "$outer"
require_literal 'rolling-b' "$outer"
require_literal 'rolling-a' "$outer"
require_literal 'exit 125' "$outer"
require_literal 'registry_uploaded_a=false' "$outer"
require_literal 'registry_uploaded_b=false' "$outer"
require_literal 'recovery-remove-registry-a' "$outer"
require_literal 'recovery-remove-registry-b' "$outer"
require_literal '--remove-registry final-acceptance' "$outer"
require_literal 'historical-complete-suite' "$manifest"
reject_literal 'Caddy/tests/run.sh' "$outer"

fixture_root=$(mktemp -d /tmp/action33b-regression.XXXXXX)
chmod 0700 "$fixture_root"
sed '/^if \[\[ "$mode" = --self-test/,$d' "$transaction" \
    >"$fixture_root/definitions.sh"
source "$fixture_root/definitions.sh"
run_id=fixture-run
scenario=node-a-controlled
role=node-a
node_token=node_a
evidence_directory=$fixture_root/evidence
install -d -m 0700 "$evidence_directory" "$fixture_root/bin"
cat >"$fixture_root/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${ACTION33_SYSTEMCTL_CAPTURE:?}"
SYSTEMCTL
chmod 0700 "$fixture_root/bin/systemctl"
render_controlled_recovery_script "$fixture_root/recovery.sh"
chmod 0700 "$fixture_root/recovery.sh"
/bin/bash -n "$fixture_root/recovery.sh"
env ACTION33_SYSTEMCTL_CAPTURE="$fixture_root/systemctl.capture" \
    PATH="$fixture_root/bin:/usr/bin:/bin" /bin/bash "$fixture_root/recovery.sh"
grep -Fxq true "$evidence_directory/control-recovery-pretransport"
grep -Fxq 'start ssh.service caddy.service caddy-lsyncd.service caddy-sync-reconcile.path caddy-sync-health.timer' \
    "$fixture_root/systemctl.capture"

fixture_releases=$fixture_root/releases
fixture_outbound=$fixture_root/outbound
fixture_empty_outbound=$fixture_root/empty-outbound
fixture_revision=fixture-current
fixture_current=$fixture_releases/$fixture_revision
install -d -m 0700 "$fixture_releases" "$fixture_outbound" \
    "$fixture_empty_outbound" "$fixture_current"
printf '%s\n' '{' \
    '  "revision": "fixture-current",' \
    '  "parent_revision": "fixture-parent",' \
    '  "source_node": "node-a",' \
    '  "created_at": "2026-08-12T00:00:00Z"' \
    '}' >"$fixture_current/release-manifest.json"
printf 'fixture payload\n' >"$fixture_current/Caddyfile"
(
    cd "$fixture_current"
    sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
)
: >"$fixture_current/.complete"
find "$fixture_current" -type f -exec chmod 0440 {} +
find "$fixture_current" -type d -exec chmod 0550 {} +
cp -a -- "$fixture_current" "$fixture_outbound/$fixture_revision"
chmod 0750 "$fixture_outbound/$fixture_revision"
rm -f -- "$fixture_outbound/$fixture_revision/.complete"
: >"$fixture_outbound/$fixture_revision/.finalize-request"
chmod 0440 "$fixture_outbound/$fixture_revision/.finalize-request"
chmod 0550 "$fixture_outbound/$fixture_revision"

role=node-a
node_token=node_a
assert_outbound_role_policy node-a "$fixture_empty_outbound" \
    "$fixture_releases" "$fixture_current" >"$fixture_root/node-a-empty.stdout"
grep -Fq 'outbound_entry_count=0' "$fixture_root/node-a-empty.stdout"
grep -Fq 'check_node_a_outbound_entries_admissible=true' \
    "$fixture_root/node-a-empty.stdout"
grep -Fq 'outbound_role_policy=accepted' "$fixture_root/node-a-empty.stdout"

assert_outbound_role_policy node-a "$fixture_outbound" "$fixture_releases" \
    "$fixture_current" >"$fixture_root/node-a-safe.stdout"
grep -Fq 'disposition=retain_exact_active_replay' \
    "$fixture_root/node-a-safe.stdout"
role=node-b
node_token=node_b
assert_outbound_role_policy node-b "$fixture_empty_outbound" \
    "$fixture_releases" "$fixture_current" >"$fixture_root/node-b-empty.stdout"
grep -Fq 'outbound_role_policy=accepted' "$fixture_root/node-b-empty.stdout"

replay_destination=$fixture_outbound/transaction-owned-replay
assert_replay_destination_absent "$replay_destination" \
    >"$fixture_root/replay-absent.stdout"
grep -Fq 'check_replay_outgoing_absent=true' \
    "$fixture_root/replay-absent.stdout"
install -d -m 0750 "$replay_destination"
printf 'current production collision sentinel\n' \
    >"$replay_destination/sentinel"
chmod 0440 "$replay_destination/sentinel"
chmod 0550 "$replay_destination"
replay_before=$(sha256sum "$replay_destination/sentinel" | awk '{ print $1 }')
if assert_replay_destination_absent "$replay_destination" \
    >"$fixture_root/replay-present.stdout" 2>"$fixture_root/replay-present.stderr"; then
    printf 'action33b regression accepted an existing replay destination\n' >&2
    exit 1
fi
grep -Fq 'check_replay_outgoing_absent=false' \
    "$fixture_root/replay-present.stderr"
replay_after=$(sha256sum "$replay_destination/sentinel" | awk '{ print $1 }')
[[ "$replay_before" = "$replay_after" ]]
chmod -R u+w "$replay_destination"
rm -rf -- "$replay_destination"

role=node-a
node_token=node_a
chmod 0640 "$fixture_outbound/$fixture_revision/Caddyfile"
printf 'unsafe drift\n' >>"$fixture_outbound/$fixture_revision/Caddyfile"
chmod 0440 "$fixture_outbound/$fixture_revision/Caddyfile"
if assert_outbound_role_policy node-a "$fixture_outbound" \
    "$fixture_releases" "$fixture_current" >/dev/null 2>&1; then
    printf 'action33b regression accepted payload drift\n' >&2
    exit 1
fi
chmod -R u+w "$fixture_outbound/${fixture_revision:?}"
rm -rf -- "$fixture_outbound/${fixture_revision:?}"
ln -s "$fixture_current" "$fixture_outbound/$fixture_revision"
if assert_outbound_role_policy node-a "$fixture_outbound" \
    "$fixture_releases" "$fixture_current" >/dev/null 2>&1; then
    printf 'action33b regression accepted an outbound symlink\n' >&2
    exit 1
fi

for required in invalid-a-to-b-payload-hash interrupted-a-to-b-finalize-request same-parent-conflict-retained node-a-controlled node-a-reboot node-b-controlled node-b-reboot; do
    require_literal "$required" "$manifest"
done
printf 'caddy_ha_reliability_action33b_regression_complete=true\n'
