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
readonly transaction=$caddy_root/scripts/transact-caddy-ha-reliability-action33.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-ha-reliability-action33-outer.sh
readonly manifest=$caddy_root/manifests/caddy-ha-reliability-action33.yaml
readonly production_publisher=$caddy_root/scripts/publish-release-v2.sh
readonly production_finalizer=$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh
readonly production_reconciler=$caddy_root/scripts/reconcile-release-v2.sh
fixture_root=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
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
CADDY_ACTION33_SSH_BIN=/bin/false /bin/bash "$outer" --self-test >/tmp/action33-self-test.stdout
grep -Fxq 'action_33_outer_self_test_complete=true' /tmp/action33-self-test.stdout
rm -f -- /tmp/action33-self-test.stdout

require_literal 'cd / && sudo -n /bin/bash' "$outer"
require_literal '-s -- $mode $role $run_id $scenario $argument' "$outer"
require_literal 'capture_files "$action33_outer_stdout" "$action33_outer_stderr" "$action33_outer_status_file"' "$outer"
require_literal 'wait_ssh_state a-down' "$outer"
require_literal 'wait_ssh_state b-down' "$outer"
require_literal 'wait_ssh_state a-up' "$outer"
require_literal 'wait_ssh_state b-up' "$outer"
require_literal 'cat /proc/sys/kernel/random/boot_id' "$transaction"
require_literal 'systemctl disable --now keepalived.service' "$transaction"
require_literal 'systemd-run --unit "caddy-action33-reboot-$run_id-$scenario"' "$transaction"
require_literal 'systemd-run --unit "$action33_remote_unit" --on-active=45s' "$transaction"
require_literal '--publish-emergency' "$outer"
require_literal '--reject-normal' "$outer"
require_literal 'sleep 12' "$outer"
require_literal 'action33-$run_id-' "$outer"
require_literal 'inventory_tree "$quarantine_root"' "$transaction"
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

fixture_root=$(mktemp -d /tmp/action33-regression.XXXXXX)
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

for required in invalid-a-to-b-payload-hash interrupted-a-to-b-finalize-request same-parent-conflict-retained node-a-controlled node-a-reboot node-b-controlled node-b-reboot; do
    require_literal "$required" "$manifest"
done
printf 'caddy_ha_reliability_exercise_regression_complete=true\n'
