#!/usr/bin/env bash
set -euo pipefail

skip_container=false
if [[ "${1:-}" == --skip-container ]]; then
    skip_container=true
elif (($#)); then
    printf 'Usage: %s [--skip-container]\n' "${0##*/}" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_dir/.." && pwd)
server_repo=$(cd -- "$caddy_root/.." && pwd)
workspace=$(cd -- "$server_repo/.." && pwd)
monitoring_root="$workspace/homelab-monitoring-observability/Munin"

mapfile -d '' shell_files < <(
    find "$caddy_root/scripts" "$monitoring_root/scripts" -type f -print0
    find "$caddy_root/tests" -type f -name '*.sh' -print0
)

shellcheck "${shell_files[@]}"
"$script_dir/shfmt-canonical.sh" --check "${shell_files[@]}"
"$script_dir/shfmt-policy-regression.sh"
"$script_dir/executable-wrapper-policy-regression.sh"
"$script_dir/remote-streamed-bash-cwd-policy.sh" --self-test
"$script_dir/unbound-validation-runtime-regression.sh" --production-test
"$script_dir/source-test-context-policy-regression.sh" --production-test
"$script_dir/vscode-tracking-policy-regression.sh"
"$script_dir/conditional-validator-errexit-policy-regression.sh"
"$script_dir/check-shell-readonly-local-collisions-v2.sh" >/dev/null
"$caddy_root/scripts/validate-node-a-validation-dependency-convergence-action16x-retry.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-validation-dependencies-action16x-b.sh" \
    --self-test
"$caddy_root/scripts/validate-node-a-validation-dependency-convergence-action16x-retry2.sh" \
    --self-test
"$caddy_root/scripts/validate-node-a-validation-dependency-convergence-action16x-retry3.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-command-versions-action16x-c.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-ip-symlink-action16x-d.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-iproute2-ownership-action16x-e.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-iproute2-ownership-action16x-e-retry.sh" \
    --self-test
"$caddy_root/scripts/install-node-a-service-identities-action16y.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-sysctl-preflight-action16z.sh" \
    --self-test
"$caddy_root/scripts/install-node-a-sysctl-action16aa.sh" \
    --self-test
"$caddy_root/scripts/stage-node-a-lighttpd-action16ab.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-lighttpd-action16ab.sh" \
    --self-test
"$caddy_root/scripts/validate-workstation-certificate-stage-action16ac.sh" \
    --self-test
"$caddy_root/scripts/diagnose-workstation-certificate-stage-action16ac-a.sh" \
    --self-test
"$caddy_root/scripts/prepare-workstation-certificate-stage-action16ad.sh" \
    --self-test
"$caddy_root/scripts/stage-node-a-certificate-action16ae.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-certificate-transfer-action16ae.sh" \
    --self-test
"$caddy_root/scripts/stage-node-a-caddy-source-action16af.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-source-transfer-action16af.sh" \
    --self-test
"$caddy_root/scripts/validate-node-a-caddy-installer-dry-run-action16ag.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-installer-dry-run-action16ag.sh" \
    --self-test
"$caddy_root/scripts/install-node-a-caddy-configuration-action16ah.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-configuration-install-action16ah.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-sync-ssh-prestate-action16ai.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-b-sync-peer-material-action16ai.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-preflight-action16ai.sh" \
    --self-test
"$caddy_root/scripts/stage-node-a-sync-ssh-artifacts-action16aj.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-stage-action16aj.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-sync-stage-rollback-action16aj-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-stage-rollback-diagnostic-action16aj-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-stage-rollback-diagnostic-action16aj-a.sh" \
    --local-test
"$caddy_root/scripts/diagnose-node-a-sync-stage-transient-action16aj-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-stage-transient-diagnostic-action16aj-b.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-sync-continuity-action16aj-c.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-continuity-action16aj-c.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-sync-stage-transient-action16aj-d.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-stage-transient-diagnostic-action16aj-d.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-stage-transient-diagnostic-action16aj-d.sh" \
    --local-test
"$caddy_root/scripts/stage-node-a-sync-ssh-artifacts-action16aj-e.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-stage-action16aj-e.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-stage-action16aj-e.sh" \
    --local-test
"$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-install-action16ak.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-diagnostic-action16ak-a.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-retained-stage-metadata-action16ak-b.sh" \
    --self-test
"$caddy_root/scripts/repair-node-a-retained-stage-mode-action16ak-c.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-retained-stage-mode-repair-action16ak-c.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-retained-stage-mode-repair-action16ak-c.sh" \
    --local-test
"$caddy_root/scripts/inspect-node-a-post-repair-continuity-action16ak-d.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-post-repair-continuity-action16ak-d.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-sync-ssh-postinstall-action16ak-e.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-sync-ssh-postinstall-action16ak-e.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-systemd-preflight-action16al.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-preflight-action16al.sh" \
    --self-test
"$caddy_root/scripts/stage-node-a-systemd-artifacts-action16am.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-stage-action16am.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-stage-action16am.sh" \
    --local-test
"$caddy_root/scripts/inspect-node-a-systemd-stage-action16am-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-stage-inspection-action16am-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-stage-inspection-action16am-a.sh" \
    --contract-test
"$caddy_root/scripts/install-node-a-systemd-action16an.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-install-action16an.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-install-action16an.sh" \
    --contract-test
"$caddy_root/scripts/inspect-node-a-systemd-postinstall-action16an-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-postinstall-action16an-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-systemd-postinstall-action16an-a.sh" \
    --contract-test
yamllint --strict "$caddy_root/manifests"

while IFS= read -r -d '' json_file; do
    jq empty "$json_file"
done < <(find "$caddy_root" -type f -name '*.json' -print0)

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-host-tests.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

for node_role in node-a node-b; do
    "$caddy_root/scripts/render-node-config.sh" \
        --node "$node_role" \
        --manifest "$caddy_root/tests/fixtures/deployment.yaml" \
        --output "$work_dir/$node_role" >/dev/null
    "$caddy_root/scripts/install-caddy-ha.sh" \
        --node "$node_role" \
        --manifest "$caddy_root/tests/fixtures/deployment.yaml" \
        --root "$work_dir/root-$node_role" \
        --dry-run >"$work_dir/dry-run-$node_role.json"
    jq -e \
        --arg node "$node_role" \
        '.node == $node and .dry_run == true and .service_mutations == false' \
        "$work_dir/dry-run-$node_role.json" >/dev/null
done

"$caddy_root/tests/receiver-finalization-protocol-v2-regression.sh"
"$caddy_root/tests/action17q-umask-stable-boundary.sh"
"$caddy_root/scripts/inspect-node-b-protocol-v2-postinstall-action17q-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-postinstall-action17q-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-postinstall-action17q-b.sh" \
    --contract-test
"$caddy_root/tests/action17q-b-node-b-postinstall-regression.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r.sh" \
    --source-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r.sh" \
    --contract-test
"$caddy_root/tests/action17r-dual-node-protocol-v2-readiness-regression.sh"
"$caddy_root/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh" \
    --source-test
"$caddy_root/scripts/run-node-a-protocol-v2-semantic-diagnostic-action17r-a.sh" \
    --contract-test
"$caddy_root/tests/action17r-a-node-a-semantic-diagnostic-regression.sh"
"$caddy_root/scripts/diagnose-node-a-ssh-g-stderr-action17r-b.sh" \
    --self-test
"$caddy_root/scripts/diagnose-node-a-ssh-g-stderr-action17r-b.sh" \
    --contract-test
"$caddy_root/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh"
"$caddy_root/scripts/run-node-a-ssh-g-stderr-diagnostic-action17r-b.sh" \
    --contract-test
"$caddy_root/tests/action17r-b-node-a-ssh-g-stderr-regression.sh"
"$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r-c.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh" \
    --source-test
"$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh" \
    --contract-test
"$caddy_root/tests/action17r-c-dual-node-protocol-v2-readiness-regression.sh"
"$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s.sh"
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s.sh" \
    --contract-test
"$caddy_root/tests/action17s-node-b-marker-migration-regression.sh"
"$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry.sh"
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry.sh" \
    --contract-test
"$caddy_root/tests/action17s-retry-node-b-marker-migration-regression.sh"
"$caddy_root/scripts/inspect-node-b-action17s-rollback-output-action17s-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action17s-rollback-output-action17s-a.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17s-rollback-output-action17s-a.sh"
"$caddy_root/scripts/run-node-b-action17s-rollback-output-action17s-a.sh" \
    --contract-test
"$caddy_root/tests/transaction-output-evidence-policy-regression.sh"
"$caddy_root/tests/action17s-a-node-b-rollback-output-regression.sh"
"$caddy_root/scripts/inspect-node-b-action17s-retry-stderr-action17s-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh"
"$caddy_root/scripts/run-node-b-action17s-retry-stderr-action17s-b.sh" \
    --contract-test
"$caddy_root/tests/action17s-b-node-b-rollback-stderr-regression.sh"
"$caddy_root/scripts/render-node-b-stdout-safe-finalizer-action17t.sh" \
    --self-test
"$caddy_root/scripts/install-node-b-stdout-safe-finalizer-action17t.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh"
"$caddy_root/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh" \
    --contract-test
"$caddy_root/tests/action17t-node-b-stdout-safe-finalizer-regression.sh"
"$caddy_root/scripts/inspect-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh"
"$caddy_root/scripts/run-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh" \
    --contract-test
"$caddy_root/tests/action17t-a-node-b-postinstall-regression.sh"
"$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-action17u.sh" \
    --self-test
"$caddy_root/scripts/install-node-b-stderr-safe-finalizer-action17u.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh"
"$caddy_root/scripts/run-node-b-stderr-safe-finalizer-install-action17u.sh" \
    --contract-test
"$caddy_root/tests/action17u-node-b-stderr-safe-finalizer-regression.sh"
"$caddy_root/scripts/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
"$caddy_root/scripts/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh" \
    --contract-test
"$caddy_root/tests/action17u-a-node-b-postinstall-regression.sh"
"$caddy_root/scripts/repair-node-b-action17u-backup-manifest-action17u-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b.sh"
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b.sh" \
    --contract-test
"$caddy_root/tests/action17u-b-node-b-backup-manifest-repair-regression.sh"
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh"
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry.sh" \
    --contract-test
"$caddy_root/tests/action17u-b-retry-node-b-backup-manifest-repair-regression.sh"
"$caddy_root/scripts/correct-node-b-action17u-backup-manifest-hostname-action17u-b-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh"
"$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b-retry2.sh" \
    --contract-test
"$caddy_root/tests/action17u-b-retry2-node-b-backup-manifest-repair-regression.sh"
"$caddy_root/scripts/derive-node-b-action17u-postrepair-acceptance-action17u-c.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
"$caddy_root/scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh" \
    --contract-test
"$caddy_root/tests/action17u-c-node-b-postrepair-acceptance-regression.sh"
"$caddy_root/scripts/derive-node-b-retained-release-marker-migration-action17s-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry2-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry2-outer.sh"
"$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s-retry2-outer.sh" \
    --contract-test
"$caddy_root/tests/action17s-retry2-node-b-marker-migration-regression.sh"
"$caddy_root/scripts/derive-node-b-postmigration-acceptance-action17v.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-postmigration-acceptance-action17v-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-postmigration-acceptance-action17v-outer.sh"
"$caddy_root/scripts/run-node-b-postmigration-acceptance-action17v-outer.sh" \
    --contract-test
"$caddy_root/tests/action17v-node-b-postmigration-acceptance-regression.sh"
"$caddy_root/scripts/inspect-reverse-sync-readiness-action18a.sh" --self-test
"$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh"
"$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh" \
    --contract-test
"$caddy_root/tests/action18a-dual-node-reverse-sync-readiness-regression.sh"
"$caddy_root/scripts/derive-dual-node-reverse-sync-readiness-action18a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a-retry-outer.sh"
"$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action18a-retry-dual-node-reverse-sync-readiness-regression.sh"
"$caddy_root/scripts/derive-node-a-action18-prerequisite-action18b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-outer.sh"
"$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-outer.sh" \
    --contract-test
"$caddy_root/tests/action18b-node-a-prerequisite-regression.sh"
"$caddy_root/scripts/inspect-node-a-action18b-postfailure-action18b-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a.sh"
"$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a.sh" \
    --contract-test
"$caddy_root/tests/action18b-a-node-a-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-a-action18b-postfailure-action18b-a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a-retry-outer.sh"
"$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action18b-a-retry-node-a-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-a-action18-prerequisite-action18b-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-retry-outer.sh"
"$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action18b-retry-node-a-prerequisite-regression.sh"
"$caddy_root/scripts/derive-node-a-action18b-postinstall-acceptance-action18b-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b-outer.sh"
"$caddy_root/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b-outer.sh" \
    --contract-test
"$caddy_root/tests/action18b-b-node-a-postinstall-acceptance-regression.sh"
"$caddy_root/scripts/install-node-b-protocol-v2-publisher-action18c-prerequisite.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite-outer.sh"
"$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite-outer.sh" \
    --contract-test
"$caddy_root/tests/action18c-publisher-prerequisite-node-b-install-regression.sh"
"$caddy_root/scripts/derive-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh" \
    --self-test
"$caddy_root/tests/action18c-publisher-a-node-b-postinstall-acceptance-regression.sh"
"$caddy_root/scripts/run-node-b-publisher-postinstall-acceptance-action18c-publisher-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-publisher-postinstall-acceptance-action18c-publisher-a-outer.sh"
"$caddy_root/scripts/run-node-b-publisher-postinstall-acceptance-action18c-publisher-a-outer.sh" \
    --contract-test
"$caddy_root/scripts/inspect-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a.sh" \
    --contract-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-emergency-master-eligibility-action18c-vrrp-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action18c-vrrp-a-emergency-master-eligibility-regression.sh"
"$caddy_root/scripts/install-node-b-keepalived-fragment-action19a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19a-node-b-keepalived-fragment-install-regression.sh"
"$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19a-a-node-b-keepalived-helper-prerequisite-regression.sh"
"$caddy_root/scripts/install-node-b-keepalived-helpers-action19b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-node-b-keepalived-helper-install-regression.sh"
"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \
    --self-test \
    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a.sh" \
    --contract-test \
    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-outer.sh"
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-a-node-b-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh"
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-a-retry-node-b-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry2-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry2-outer.sh"
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry2-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-a-retry2-node-b-postfailure-regression.sh"
"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh" \
    --self-test \
    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
"$caddy_root/scripts/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh" \
    --contract-test \
    "$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
"$caddy_root/scripts/install-node-b-keepalived-helpers-action19b-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh"
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-retry-node-b-keepalived-helper-install-regression.sh"
"$caddy_root/scripts/derive-node-b-keepalived-helper-postinstall-action19b-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-postinstall-action19b-b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-helper-postinstall-action19b-b-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-helper-postinstall-action19b-b-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-b-node-b-keepalived-helper-postinstall-regression.sh"
"$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh"
"$caddy_root/scripts/inspect-node-b-keepalived-fragment-postinstall-action19a-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b-outer.sh"
"$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b-outer.sh" \
    --contract-test
"$caddy_root/tests/action19a-b-node-b-keepalived-fragment-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-prerequisite-action19c-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19c-a-node-a-keepalived-prerequisite-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-install-action19d.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-install-action19d-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-helper-install-action19d-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-helper-install-action19d-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-node-a-keepalived-helper-install-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-a-node-a-keepalived-helper-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-a-retry-node-a-keepalived-helper-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-fragment-action19e.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh" \
    --contract-test
"$caddy_root/tests/action19e-node-a-keepalived-fragment-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-fragment-postinstall-action19e-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh"
"$caddy_root/scripts/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19e-a-node-a-keepalived-fragment-postinstall-regression.sh"
"$caddy_root/scripts/inspect-dual-node-caddy-vrrp-preactivation-action20a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a.sh" \
    --contract-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-dual-node-caddy-vrrp-preactivation-regression.sh"
"$caddy_root/scripts/inspect-dual-node-caddy-health-context-action20a-a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a.sh" \
    --contract-test
"$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-a-dual-node-caddy-health-context-regression.sh"
"$caddy_root/scripts/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b.sh" \
    --contract-test
"$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-b-dual-node-postfailure-continuity-regression.sh"
"$caddy_root/scripts/install-node-b-caddy-health-context-action20b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" --self-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b-outer.sh" \
    --contract-test
"$caddy_root/tests/action20b-node-b-caddy-health-context-correction-regression.sh"
"$caddy_root/scripts/inspect-node-b-caddy-health-postinstall-action20b-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action20b-a-node-b-caddy-health-postinstall-regression.sh"
"$caddy_root/scripts/install-node-a-caddy-health-context-action20c.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh" \
    --contract-test
"$caddy_root/tests/action20c-node-a-caddy-health-context-correction-regression.sh"
"$caddy_root/scripts/inspect-node-a-caddy-health-postinstall-action20c-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action20c-a-node-a-caddy-health-postinstall-regression.sh"
"$caddy_root/scripts/inspect-dual-node-caddy-vrrp-preactivation-action20a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-retry-dual-node-caddy-vrrp-preactivation-regression.sh"
"$caddy_root/scripts/inspect-node-b-caddy-state-difference-action20a-retry-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh"
"$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-retry-a-node-b-state-difference-regression.sh"
"$caddy_root/scripts/inspect-dual-node-caddy-vrrp-preactivation-action20a-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2-outer.sh" \
    --contract-test
"$caddy_root/tests/action20a-retry2-dual-node-caddy-vrrp-preactivation-regression.sh"
"$caddy_root/scripts/activate-caddy-vrrp-node-action20d.sh" --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-outer.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-outer.sh" \
    --source-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-outer.sh" \
    --contract-test
"$caddy_root/tests/action20d-dual-node-caddy-vrrp-activation-regression.sh"
"$caddy_root/scripts/inspect-node-a-caddy-vrrp-postfailure-action20d-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-vrrp-postfailure-action20d-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-vrrp-postfailure-action20d-a.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-vrrp-postfailure-action20d-a-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-vrrp-postfailure-action20d-a-outer.sh" \
    --source-test
"$caddy_root/tests/action20d-a-node-a-caddy-vrrp-postfailure-regression.sh"
"$caddy_root/scripts/diagnose-node-a-caddy-vrrp-candidate-action20d-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-vrrp-candidate-diagnostic-action20d-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-caddy-vrrp-candidate-diagnostic-action20d-b.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-node-a-caddy-vrrp-candidate-diagnostic-action20d-b-outer.sh"
"$caddy_root/scripts/run-node-a-caddy-vrrp-candidate-diagnostic-action20d-b-outer.sh" \
    --source-test
"$caddy_root/tests/action20d-b-node-a-candidate-diagnostic-regression.sh"
"$caddy_root/scripts/activate-caddy-vrrp-node-action20d-retry.sh" --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-vrrp-activation-action20d-retry-outer.sh" \
    --source-test
"$caddy_root/tests/action20d-retry-dual-node-caddy-vrrp-activation-regression.sh"
"$caddy_root/scripts/inspect-caddy-notifier-context-action20d-c.sh" --self-test
"$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh" \
    --self-test
"$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c.sh" \
    --contract-test
"$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
    --runner "$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-outer.sh"
"$caddy_root/scripts/run-dual-node-caddy-notifier-context-action20d-c-outer.sh" \
    --source-test
"$caddy_root/tests/action20d-c-dual-node-notifier-context-regression.sh"
"$caddy_root/tests/action20d-c-retry-focused-validation.sh"
"$caddy_root/tests/action20d-retry3-a-retry-stale-suite-hash-boundary.sh"
"$caddy_root/tests/action20d-retry2-a-focused-validation.sh"
"$caddy_root/tests/action20d-retry2-b-focused-validation.sh"
"$caddy_root/tests/action20d-retry3-a-retry-focused-validation.sh"
"$caddy_root/tests/action20d-retry4-focused-validation.sh"
"$caddy_root/tests/run-focused-container.sh" --self-test
"$caddy_root/scripts/transfer-node-b-release-to-node-a-action18c.sh" \
    --self-test
"$caddy_root/scripts/inspect-node-a-incoming-release-action18c.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c.sh"
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c-outer.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c-outer.sh"
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c-outer.sh" \
    --contract-test
"$caddy_root/tests/action18c-node-b-to-node-a-release-transfer-regression.sh"
"$caddy_root/scripts/inspect-node-b-protocol-v2-postfailure-action17q-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-postfailure-action17q-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-protocol-v2-postfailure-action17q-a.sh" \
    --contract-test
"$caddy_root/tests/action17q-a-node-b-postfailure-regression.sh" \
    --self-test

grep -R -Fq 'protocols h1 h2 h3' "$caddy_root/configs/caddy"
grep -Fq 'skip_install_trust' "$caddy_root/configs/caddy/Caddyfile"
grep -Fq 'health_follow_redirects' \
    "$caddy_root/configs/caddy/conf.d/10-pihole-admin.caddy"
grep -Fq 'TimeoutStopSec=30s' \
    "$caddy_root/systemd/caddy.service.d/override.conf"
grep -R -Fq 'ports: [443]' "$caddy_root/manifests/deployment.yaml"
grep -R -Fq 'virtual_router_id 110' "$caddy_root/templates"
grep -R -Fq 'virtual_router_id 111' "$caddy_root/templates"
grep -Fq 'targetdir = "/@NODE_ROLE@/"' \
    "$caddy_root/templates/lsyncd-caddy.lua.in"
grep -Fq "caddy-sync@\$SYNC_TARGET:/\$NODE_ROLE/" \
    "$caddy_root/scripts/validate-sync-ssh.sh"
grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    "$caddy_root/scripts/caddy-sync-rsync-receiver"
grep -Fq \
    'from=\"10.1.0.54,fd36:5aa8:6971:1::54\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\"' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq \
    "\"\$validator\" >/dev/null" \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq 'expected_stage_inode=1670964' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq 'expected_stage_device=66306' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq \
    'package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq 'action_16ak_mutation_started=true' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"
grep -Fq 'Action 16ak lacks required rollback evidence.' \
    "$caddy_root/scripts/run-node-a-sync-ssh-install-action16ak.sh"
if grep -Fq -- '--connect' \
    "$caddy_root/scripts/install-node-a-sync-ssh-action16ak.sh"; then
    printf 'Action 16ak must not perform a peer connection.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh"; then
    printf 'Action 16ak-a inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh"; then
    printf 'Action 16ak-a inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Fq -- '--connect' \
    "$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh"; then
    printf 'Action 16ak-a must not perform a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'action_16ak_preflight_would_pass=' \
    "$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh"
grep -Fq 'installed_shape_valid=' \
    "$caddy_root/scripts/diagnose-node-a-sync-ssh-action16ak-a.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"; then
    printf 'Action 16ak-b inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"; then
    printf 'Action 16ak-b inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Fq -- '--connect' \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"; then
    printf 'Action 16ak-b must not perform a peer connection.\n' >&2
    exit 1
fi
grep -Fq "print_metadata retained_stage" \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"
grep -Fq "'%s_owner_numeric=%s\\n'" \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"
grep -Fq "'%s_mode_symbolic=%s\\n'" \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"
grep -Fq "print_acl retained_stage" \
    "$caddy_root/scripts/inspect-node-a-retained-stage-metadata-action16ak-b.sh"
stage_driver="$caddy_root/scripts/stage-node-a-sync-ssh-artifacts-action16aj-e.sh"
stage_extract_line=$(grep -nF 'require_stage_command stage_extract' \
    "$stage_driver" | cut -d: -f1)
stage_mode_line=$(grep -nF 'require_stage_command stage_root_post_extract_mode' \
    "$stage_driver" | cut -d: -f1)
stage_meta_line=$(grep -nF 'require_stage_equal stage_root_post_extract_meta' \
    "$stage_driver" | cut -d: -f1)
[[ "$stage_extract_line" -lt "$stage_mode_line" ]]
[[ "$stage_mode_line" -lt "$stage_meta_line" ]]
grep -Fq "\"\$(stat -c '%U:%G:%a' \"\$retained_stage\")\"" \
    "$stage_driver"
repair_driver="$caddy_root/scripts/repair-node-a-retained-stage-mode-action16ak-c.sh"
[[ "$(grep -Ec '(^|[[:space:]])chmod[[:space:]]' "$repair_driver")" -eq 2 ]]
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$repair_driver"; then
    printf 'Action 16ak-c must not mutate service state.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chown|tee|truncate)([[:space:]]|$)' \
    "$repair_driver"; then
    printf 'Action 16ak-c exceeds its metadata-only mutation boundary.\n' >&2
    exit 1
fi
if grep -Fq -- '--connect' "$repair_driver"; then
    printf 'Action 16ak-c must not perform a peer connection.\n' >&2
    exit 1
fi
grep -Fq "chmod 0750 \"/proc/self/fd/\$stage_fd\"" "$repair_driver"
grep -Fq "chmod 0700 \"/proc/self/fd/\$stage_fd\"" "$repair_driver"
grep -Fq 'action_16ak_c_mutation_started=true' "$repair_driver"
grep -Fq 'action_16ak_c_rollback_complete=' "$repair_driver"
grep -Fq 'Action 16ak-c lacks required rollback evidence.' \
    "$caddy_root/scripts/run-node-a-retained-stage-mode-repair-action16ak-c.sh"
continuity_inspector="$caddy_root/scripts/inspect-node-a-post-repair-continuity-action16ak-d.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$continuity_inspector"; then
    printf 'Action 16ak-d inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$continuity_inspector"; then
    printf 'Action 16ak-d inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Fq -- '--connect' "$continuity_inspector"; then
    printf 'Action 16ak-d must not perform a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'root:root:750' "$continuity_inspector"
grep -Fq 'expected_stage_inode=1670964' "$continuity_inspector"
grep -Fq 'expected_stage_device=66306' "$continuity_inspector"
grep -Fq \
    'package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c' \
    "$continuity_inspector"
grep -Fq 'record_equal protected_package_inventory' "$continuity_inspector"
grep -Fq 'action_16ak_d_continuity_valid=' "$continuity_inspector"
postinstall_inspector="$caddy_root/scripts/inspect-node-a-sync-ssh-postinstall-action16ak-e.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$postinstall_inspector"; then
    printf 'Action 16ak-e inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$postinstall_inspector"; then
    printf 'Action 16ak-e inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' \
    "$postinstall_inspector"; then
    printf 'Action 16ak-e must not perform a peer transfer.\n' >&2
    exit 1
fi
[[ "$(grep -Ec '^[[:space:]]*ssh[[:space:]]+-G([[:space:]]|$)' \
    "$postinstall_inspector")" -eq 1 ]]
# shellcheck disable=SC2016 # The regex intentionally matches literal variables.
helper_reference_pattern='^[[:space:]]*"\$(receiver|setup_helper|validator)"[[:space:]]*$'
if [[ "$(grep -Ec "$helper_reference_pattern" "$postinstall_inspector")" -ne 1 ]] ||
    ! grep -Fq 'record_command receiver_no_delete_contract' \
        "$postinstall_inspector"; then
    printf 'Action 16ak-e helper contract inspection is ambiguous.\n' >&2
    exit 1
fi
grep -Fq \
    "expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'" \
    "$postinstall_inspector"
grep -Fq 'peer_connections=false' "$postinstall_inspector"
grep -Fq 'installed_helper_execution=false' "$postinstall_inspector"
grep -Fq 'action_16ak_e_postinstall_valid=' "$postinstall_inspector"
systemd_preflight_inspector="$caddy_root/scripts/inspect-node-a-systemd-preflight-action16al.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$systemd_preflight_inspector"; then
    printf 'Action 16al inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$systemd_preflight_inspector"; then
    printf 'Action 16al inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$systemd_preflight_inspector"; then
    printf 'Action 16al must not perform a peer connection or transfer.\n' >&2
    exit 1
fi
# shellcheck disable=SC2016 # The regex intentionally matches literal variables.
helper_execution_pattern='^[[:space:]]*"\$(receiver|setup_helper|validator)"([[:space:]]|$)'
if grep -Eq "$helper_execution_pattern" "$systemd_preflight_inspector"; then
    printf 'Action 16al must not execute an installed helper.\n' >&2
    exit 1
fi
grep -Fq 'caddy-sync-failure@action16al-preflight.service' \
    "$systemd_preflight_inspector"
grep -Fq 'protected_caddy_api_socket_load' "$systemd_preflight_inspector"
grep -Fq 'UnitFileState' "$systemd_preflight_inspector"
grep -Fq 'expected_libexec_files' "$systemd_preflight_inspector"
grep -Fq 'preflight_mismatch_count=' "$systemd_preflight_inspector"
grep -Fq 'action_16al_preflight_valid=' "$systemd_preflight_inspector"
grep -Fq 'peer_connections=false' "$systemd_preflight_inspector"
grep -Fq 'installed_helper_execution=false' "$systemd_preflight_inspector"
grep -Fq 'service_mutations=false' "$systemd_preflight_inspector"
grep -Fq \
    'readonly inspector_sha256=1ce571c8f6bcb6c063930754dcfcfb4f58a069d982a71fc78ce93d2b98b6b472' \
    "$caddy_root/scripts/run-node-a-systemd-preflight-action16al.sh"
systemd_stage_driver="$caddy_root/scripts/stage-node-a-systemd-artifacts-action16am.sh"
systemd_stage_runner="$caddy_root/scripts/run-node-a-systemd-stage-action16am.sh"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$systemd_stage_driver"; then
    printf 'Action 16am must not mutate systemd or service state.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$systemd_stage_driver"; then
    printf 'Action 16am remote driver must not make a peer connection.\n' >&2
    exit 1
fi
# shellcheck disable=SC2016 # Match the literal remote-stage variable.
[[ "$(grep -Fc 'rm -rf -- "$stage"' "$systemd_stage_driver")" -eq 1 ]]
grep -Fq \
    'readonly stage=/var/tmp/caddy-systemd-node-a-action16am' \
    "$systemd_stage_driver"
grep -Fq \
    'readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15' \
    "$systemd_stage_driver"
grep -Fq \
    'a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df  systemd/caddy.service.d/override.conf' \
    "$systemd_stage_driver"
grep -Fq 'stage_file_count=16' "$systemd_stage_driver"
grep -Fq 'systemd_daemon_reload_performed=false' "$systemd_stage_driver"
grep -Fq 'service_mutations=false' "$systemd_stage_driver"
grep -Fq 'action_16am_systemd_stage_complete=true' \
    "$systemd_stage_driver"
grep -Fq \
    'readonly driver_sha256=86452d84350ff12cb97216991de7c608656c996db53d1a7202b1752fe75a9bab' \
    "$systemd_stage_runner"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' "$systemd_stage_runner"
grep -Fq 'pi@10.1.0.53' "$systemd_stage_runner"
grep -Fq 'Action 16am lacks required rollback evidence.' \
    "$systemd_stage_runner"
systemd_stage_inspector_16am_a="$caddy_root/scripts/inspect-node-a-systemd-stage-action16am-a.sh"
systemd_stage_runner_16am_a="$caddy_root/scripts/run-node-a-systemd-stage-inspection-action16am-a.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$systemd_stage_inspector_16am_a"; then
    printf 'Action 16am-a inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$systemd_stage_inspector_16am_a"; then
    printf 'Action 16am-a inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$systemd_stage_inspector_16am_a"; then
    printf 'Action 16am-a must not perform a peer connection or transfer.\n' >&2
    exit 1
fi
# shellcheck disable=SC2016 # The regex intentionally matches literal variables.
helper_execution_pattern='^[[:space:]]*"\$(receiver|setup_helper|validator)"([[:space:]]|$)'
if grep -Eq "$helper_execution_pattern" "$systemd_stage_inspector_16am_a"; then
    printf 'Action 16am-a must not execute an installed helper.\n' >&2
    exit 1
fi
grep -Fq \
    'readonly stage=/var/tmp/caddy-systemd-node-a-action16am' \
    "$systemd_stage_inspector_16am_a"
grep -Fq \
    'readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15' \
    "$systemd_stage_inspector_16am_a"
grep -Fq 'expected_checksums=(' "$systemd_stage_inspector_16am_a"
grep -Fq 'live_targets=(' "$systemd_stage_inspector_16am_a"
grep -Fq 'record_equal stage_file_count_valid ' \
    "$systemd_stage_inspector_16am_a"
grep -Fq 'record_equal stage_digest_valid ' \
    "$systemd_stage_inspector_16am_a"
grep -Fq "printf 'stage_file_count=%s" "$systemd_stage_inspector_16am_a"
grep -Fq "printf 'stage_digest=%s" "$systemd_stage_inspector_16am_a"
grep -Fq 'inspection_mismatch_count=' "$systemd_stage_inspector_16am_a"
grep -Fq 'peer_connections=false' "$systemd_stage_inspector_16am_a"
grep -Fq 'installed_helper_execution=false' "$systemd_stage_inspector_16am_a"
grep -Fq 'systemd_daemon_reload_performed=false' \
    "$systemd_stage_inspector_16am_a"
grep -Fq 'service_mutations=false' "$systemd_stage_inspector_16am_a"
grep -Fq 'action_16am_a_stage_and_protected_state_valid=' \
    "$systemd_stage_inspector_16am_a"
grep -Fq \
    'readonly inspector_sha256=5ec3f551701185b26dccd3fac84e5e6e6ea599e9e809bcdc8a28855ab1b4fa1d' \
    "$systemd_stage_runner_16am_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$systemd_stage_runner_16am_a"
grep -Fq 'pi@10.1.0.53' "$systemd_stage_runner_16am_a"
grep -Fq 'systemd_daemon_reload_performed=false' \
    "$systemd_stage_runner_16am_a"
grep -Fq 'service_mutations=false' "$systemd_stage_runner_16am_a"
grep -Fq "false_line_count=\$(grep -Ec '=false$'" \
    "$systemd_stage_runner_16am_a"
grep -Fq "expected_false_line_count=\$((mismatch_count + 4))" \
    "$systemd_stage_runner_16am_a"
grep -Fq 'stage_file_count_valid=true' "$systemd_stage_runner_16am_a"
grep -Fq 'stage_digest_valid=true' "$systemd_stage_runner_16am_a"
grep -Fq "duplicate=\$(printf" "$systemd_stage_runner_16am_a"
grep -Fq "malformed=\${success/stage_file_count=16/stage_file_count=invalid}" \
    "$systemd_stage_runner_16am_a"
grep -Fq 'missing_marker=' "$systemd_stage_runner_16am_a"
grep -Fq "inconsistent=\$(printf" "$systemd_stage_runner_16am_a"
grep -Fq "secret=\$(printf" "$systemd_stage_runner_16am_a"
grep -Fq 'action_16am_a_transcript_contract_test_complete=true' \
    "$systemd_stage_runner_16am_a"
if grep -Fq "'=false$|manual_intervention_required=true" \
    "$systemd_stage_runner_16am_a"; then
    printf 'Action 16am-a repeats the Action 16am broad false-marker defect.\n' >&2
    exit 1
fi
systemd_install_driver_16an="$caddy_root/scripts/install-node-a-systemd-action16an.sh"
systemd_install_runner_16an="$caddy_root/scripts/run-node-a-systemd-install-action16an.sh"
grep -Fq \
    'readonly stage=/var/tmp/caddy-systemd-node-a-action16am' \
    "$systemd_install_driver_16an"
grep -Fq \
    'readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15' \
    "$systemd_install_driver_16an"
grep -Fq 'systemctl daemon-reload' "$systemd_install_driver_16an"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
    "$systemd_install_driver_16an"; then
    printf 'Action 16an must not change unit enablement or service state.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$systemd_install_driver_16an"; then
    printf 'Action 16an remote driver must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'action_16an_rollback_complete=true' \
    "$systemd_install_driver_16an"
grep -Fq 'manual_intervention_required=true' \
    "$systemd_install_driver_16an"
grep -Fq 'custom_units_enabled=false' "$systemd_install_driver_16an"
grep -Fq 'custom_units_active=false' "$systemd_install_driver_16an"
grep -Fq 'peer_connections=false' "$systemd_install_driver_16an"
grep -Fq 'installed_helper_execution=false' "$systemd_install_driver_16an"
grep -Fq 'service_mutations=false' "$systemd_install_driver_16an"
grep -Fq 'action_16an_systemd_install_complete=true' \
    "$systemd_install_driver_16an"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$systemd_install_runner_16an"
grep -Fq 'pi@10.1.0.53' "$systemd_install_runner_16an"
grep -Fq 'Action 16an lacks required rollback evidence.' \
    "$systemd_install_runner_16an"
grep -Fq 'action_16an_contract_test_complete=true' \
    "$systemd_install_runner_16an"
systemd_postinstall_inspector_16an_a="$caddy_root/scripts/inspect-node-a-systemd-postinstall-action16an-a.sh"
systemd_postinstall_runner_16an_a="$caddy_root/scripts/run-node-a-systemd-postinstall-action16an-a.sh"
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$systemd_postinstall_inspector_16an_a"; then
    printf 'Action 16an-a inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$systemd_postinstall_inspector_16an_a"; then
    printf 'Action 16an-a inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$systemd_postinstall_inspector_16an_a"; then
    printf 'Action 16an-a inspector must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq \
    'readonly stage=/var/tmp/caddy-systemd-node-a-action16am' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq \
    'readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'acceptance_assertion_count=' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'acceptance_mismatch_count=' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'peer_connections=false' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'installed_helper_execution=false' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'systemd_daemon_reload_performed=false' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'service_mutations=false' \
    "$systemd_postinstall_inspector_16an_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$systemd_postinstall_runner_16an_a"
grep -Fq 'pi@10.1.0.53' "$systemd_postinstall_runner_16an_a"
grep -Fq 'action_16an_a_contract_test_complete=true' \
    "$systemd_postinstall_runner_16an_a"
cutover_preflight_inspector_16ao="$caddy_root/scripts/inspect-node-a-cutover-preflight-action16ao.sh"
cutover_preflight_runner_16ao="$caddy_root/scripts/run-node-a-cutover-preflight-action16ao.sh"
"$cutover_preflight_inspector_16ao" --self-test
"$cutover_preflight_runner_16ao" --self-test
"$cutover_preflight_runner_16ao" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$cutover_preflight_inspector_16ao"; then
    printf 'Action 16ao inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$cutover_preflight_inspector_16ao"; then
    printf 'Action 16ao inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$cutover_preflight_inspector_16ao"; then
    printf 'Action 16ao inspector must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'fd36:5aa8:6971:1::53/64' "$cutover_preflight_inspector_16ao"
grep -Fq 'readonly caddy_mask=/etc/systemd/system/caddy.service' \
    "$cutover_preflight_inspector_16ao"
grep -Fq 'readonly caddy_vendor_unit=/lib/systemd/system/caddy.service' \
    "$cutover_preflight_inspector_16ao"
grep -Fq \
    'readonly caddy_vendor_canonical=/usr/lib/systemd/system/caddy.service' \
    "$cutover_preflight_inspector_16ao"
grep -Fq \
    'readonly caddy_vendor_unit_sha256=6c271e030644bd36a0c8956885934f16c928f88202bc126f12cde519ef9693ff' \
    "$cutover_preflight_inspector_16ao"
grep -Fq 'install ok installed|caddy|2.11.4|arm64' \
    "$cutover_preflight_inspector_16ao"
grep -Fq 'caddy_vendor_unit_type' "$cutover_preflight_inspector_16ao"
grep -Fq 'tcp_80_dualstack_lighttpd' "$cutover_preflight_inspector_16ao"
grep -Fq 'candidate_native_parse' "$cutover_preflight_inspector_16ao"
grep -Fq 'certificate_key_match' "$cutover_preflight_inspector_16ao"
grep -Fq 'current_https_management' "$cutover_preflight_inspector_16ao"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$cutover_preflight_runner_16ao"
grep -Fq 'pi@10.1.0.53' "$cutover_preflight_runner_16ao"
cutover_diagnostic_16ao_a="$caddy_root/scripts/diagnose-node-a-cutover-preflight-action16ao-a.sh"
cutover_diagnostic_runner_16ao_a="$caddy_root/scripts/run-node-a-cutover-diagnostic-action16ao-a.sh"
"$cutover_diagnostic_16ao_a" --self-test
"$cutover_diagnostic_runner_16ao_a" --self-test
"$cutover_diagnostic_runner_16ao_a" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$cutover_diagnostic_16ao_a"; then
    printf 'Action 16ao-a diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$cutover_diagnostic_16ao_a"; then
    printf 'Action 16ao-a diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$cutover_diagnostic_16ao_a"; then
    printf 'Action 16ao-a diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'ip -o -6 address show' "$cutover_diagnostic_16ao_a"
grep -Fq 'caddy_type=' "$cutover_diagnostic_16ao_a"
grep -Fq 'type_directive_record=' "$cutover_diagnostic_16ao_a"
grep -Fq "ss -H -lntp 'sport = :80'" "$cutover_diagnostic_16ao_a"
grep -Fq 'tcp80_listener=' "$cutover_diagnostic_16ao_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$cutover_diagnostic_runner_16ao_a"
grep -Fq 'pi@10.1.0.53' "$cutover_diagnostic_runner_16ao_a"
vendor_unit_diagnostic_16ao_b="$caddy_root/scripts/diagnose-node-a-caddy-vendor-unit-action16ao-b.sh"
vendor_unit_diagnostic_runner_16ao_b="$caddy_root/scripts/run-node-a-caddy-vendor-unit-diagnostic-action16ao-b.sh"
"$vendor_unit_diagnostic_16ao_b" --self-test
"$vendor_unit_diagnostic_runner_16ao_b" --self-test
"$vendor_unit_diagnostic_runner_16ao_b" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$vendor_unit_diagnostic_16ao_b"; then
    printf 'Action 16ao-b diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)' \
    "$vendor_unit_diagnostic_16ao_b"; then
    printf 'Action 16ao-b diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$vendor_unit_diagnostic_16ao_b"; then
    printf 'Action 16ao-b diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'mask_path=/etc/systemd/system/caddy.service' \
    "$vendor_unit_diagnostic_16ao_b"
grep -Fq "readlink -f -- \"\$mask_path\"" "$vendor_unit_diagnostic_16ao_b"
grep -Fq 'dpkg-query -L caddy' "$vendor_unit_diagnostic_16ao_b"
grep -Fq "dpkg-query -S \"\$vendor_path\"" "$vendor_unit_diagnostic_16ao_b"
grep -Fq 'vendor_type_record=' "$vendor_unit_diagnostic_16ao_b"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$vendor_unit_diagnostic_runner_16ao_b"
grep -Fq 'pi@10.1.0.53' "$vendor_unit_diagnostic_runner_16ao_b"
node_a_cutover_16ap="$caddy_root/scripts/cutover-node-a-lighttpd-caddy-action16ap.sh"
node_a_cutover_runner_16ap="$caddy_root/scripts/run-node-a-lighttpd-caddy-cutover-action16ap.sh"
"$node_a_cutover_16ap" --self-test
"$node_a_cutover_runner_16ap" --self-test
"$node_a_cutover_runner_16ap" --contract-test
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_cutover_16ap"; then
    printf 'Action 16ap driver must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq \
    'readonly source_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab' \
    "$node_a_cutover_16ap"
grep -Fq \
    'readonly cutover_candidate=/etc/.lighttpd-caddy-action16ap' \
    "$node_a_cutover_16ap"
grep -Fq 'readonly lighttpd_ready_seconds=20' "$node_a_cutover_16ap"
grep -Fq 'readonly caddy_ready_seconds=35' "$node_a_cutover_16ap"
grep -Fq 'readonly stability_seconds=3' "$node_a_cutover_16ap"
grep -Fq 'wait_until_stable lighttpd_backend' "$node_a_cutover_16ap"
grep -Fq 'wait_until_stable caddy' "$node_a_cutover_16ap"
grep -Fq 'wait_until_stable original_lighttpd' "$node_a_cutover_16ap"
grep -Fq "for resolved_address in 10.1.0.53 '[fd36:5aa8:6971:1::53]'" \
    "$node_a_cutover_16ap"
grep -Fq 'action_16ap_rollback_complete=true' "$node_a_cutover_16ap"
grep -Fq 'action_16ap_rollback_incomplete=true' "$node_a_cutover_16ap"
grep -Fq 'manual_intervention_required=true' "$node_a_cutover_16ap"
grep -Fq 'systemctl unmask caddy.service' "$node_a_cutover_16ap"
grep -Fq 'systemctl start caddy.service' "$node_a_cutover_16ap"
grep -Fq 'systemctl mask caddy.service' "$node_a_cutover_16ap"
grep -Fq 'systemctl restart lighttpd.service' "$node_a_cutover_16ap"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_cutover_runner_16ap"
grep -Fq 'pi@10.1.0.53' "$node_a_cutover_runner_16ap"
grep -Fq 'action_16ap_contract_test_complete=true' \
    "$node_a_cutover_runner_16ap"
node_a_cutover_16ap_retry="$caddy_root/scripts/cutover-node-a-lighttpd-caddy-action16ap-retry.sh"
node_a_cutover_runner_16ap_retry="$caddy_root/scripts/run-node-a-lighttpd-caddy-cutover-action16ap-retry.sh"
"$node_a_cutover_16ap_retry" --self-test
"$node_a_cutover_runner_16ap_retry" --self-test
"$node_a_cutover_runner_16ap_retry" --contract-test
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_cutover_16ap_retry"; then
    printf 'Action 16ap retry driver must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'reset_caddy_if_failed before_start' \
    "$node_a_cutover_16ap_retry"
grep -Fq 'reset_caddy_if_failed during_rollback' \
    "$node_a_cutover_16ap_retry"
grep -Fq "if [[ \"\$active_state\" == failed ]]; then" \
    "$node_a_cutover_16ap_retry"
if [[ "$(grep -Fxc \
    '        systemctl reset-failed caddy.service' \
    "$node_a_cutover_16ap_retry")" -ne 1 ]]; then
    printf 'Action 16ap retry must contain one guarded Caddy reset.\n' >&2
    exit 1
fi
grep -Fq "caddy_active_state_supported \"\$active_state\"" \
    "$node_a_cutover_16ap_retry"
grep -Fq 'caddy_reset_before_start=(true|false)' \
    "$node_a_cutover_runner_16ap_retry"
grep -Fq 'action_16ap_retry_rollback_complete=true' \
    "$node_a_cutover_16ap_retry"
grep -Fq 'action_16ap_retry_rollback_incomplete=true' \
    "$node_a_cutover_16ap_retry"
grep -Fq 'manual_intervention_required=true' \
    "$node_a_cutover_16ap_retry"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_cutover_runner_16ap_retry"
grep -Fq 'pi@10.1.0.53' "$node_a_cutover_runner_16ap_retry"
grep -Fq 'action_16ap_retry_contract_test_complete=true' \
    "$node_a_cutover_runner_16ap_retry"
node_a_post_cutover_inspector_16aq="$caddy_root/scripts/inspect-node-a-post-cutover-action16aq.sh"
node_a_post_cutover_runner_16aq="$caddy_root/scripts/run-node-a-post-cutover-acceptance-action16aq.sh"
"$node_a_post_cutover_inspector_16aq" --self-test
"$node_a_post_cutover_runner_16aq" --self-test
"$node_a_post_cutover_runner_16aq" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_post_cutover_inspector_16aq"; then
    printf 'Action 16aq inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_post_cutover_inspector_16aq"; then
    printf 'Action 16aq inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_post_cutover_inspector_16aq"; then
    printf 'Action 16aq inspector must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq \
    'readonly live_lighttpd_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq \
    'readonly original_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'record_equal caddy_active' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'record_equal caddy_enabled' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'record_command tcp_80_caddy_only' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'record_command tcp_8080_lighttpd_only' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'management_ipv6_http2_code=' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'unknown_host_code=' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'served_leaf_sha256=' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'action_16aq_post_cutover_valid=' \
    "$node_a_post_cutover_inspector_16aq"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_post_cutover_runner_16aq"
grep -Fq 'pi@10.1.0.53' "$node_a_post_cutover_runner_16aq"
grep -Fq 'action_16aq_contract_test_complete=true' \
    "$node_a_post_cutover_runner_16aq"
node_a_lighttpd_routing_diagnostic_16aq_a="$caddy_root/scripts/diagnose-node-a-lighttpd-routing-action16aq-a.sh"
node_a_lighttpd_routing_runner_16aq_a="$caddy_root/scripts/run-node-a-lighttpd-routing-diagnostic-action16aq-a.sh"
"$node_a_lighttpd_routing_diagnostic_16aq_a" --self-test
"$node_a_lighttpd_routing_runner_16aq_a" --self-test
"$node_a_lighttpd_routing_runner_16aq_a" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"; then
    printf 'Action 16aq-a diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"; then
    printf 'Action 16aq-a diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"; then
    printf 'Action 16aq-a diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'lighttpd_directive_record_count=' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'lighttpd_effective_record_count=' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'lighttpd_enabled_record_count=' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'adapted_route_record_count=' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'runtime_route_record_count=' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq "curl --noproxy '*'" \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'run_probe known_sni_unknown_host' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'run_probe unknown_sni_known_host' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'probe_record_count=5' \
    "$node_a_lighttpd_routing_diagnostic_16aq_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_lighttpd_routing_runner_16aq_a"
grep -Fq 'pi@10.1.0.53' "$node_a_lighttpd_routing_runner_16aq_a"
grep -Fq 'action_16aq_a_contract_test_complete=true' \
    "$node_a_lighttpd_routing_runner_16aq_a"
node_a_lighttpd_routing_extension_16aq_a_retry="$caddy_root/scripts/extend-node-a-lighttpd-routing-action16aq-a-retry.sh"
node_a_lighttpd_routing_runner_16aq_a_retry="$caddy_root/scripts/run-node-a-lighttpd-routing-diagnostic-action16aq-a-retry.sh"
"$node_a_lighttpd_routing_extension_16aq_a_retry" --extension-self-test
"$node_a_lighttpd_routing_runner_16aq_a_retry" --self-test
"$node_a_lighttpd_routing_runner_16aq_a_retry" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"; then
    printf 'Action 16aq-a retry extension contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"; then
    printf 'Action 16aq-a retry extension contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"; then
    printf 'Action 16aq-a retry extension must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'status_code_present:' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq 'effective_status_code:' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq 'body_length:' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq 'body_is_421:' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq 'action_16aq_a_retry_static_response_extension_complete=true' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq -- '--summarize-servers' \
    "$node_a_lighttpd_routing_extension_16aq_a_retry"
grep -Fq '421%%7C10.1.0.53%%7C2%%7C0%%7C0%%7Ctext/plain' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
grep -Fq 'Literal-delimiter retry evidence was accepted.' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
# shellcheck disable=SC2016
grep -Fq 'cat "$diagnostic" "$extension" >"$remote_payload"' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
grep -Fq 'pi@10.1.0.53' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
grep -Fq 'action_16aq_a_retry_contract_test_complete=true' \
    "$node_a_lighttpd_routing_runner_16aq_a_retry"
node_a_server_selection_diagnostic_16aq_b="$caddy_root/scripts/diagnose-node-a-caddy-server-selection-action16aq-b.sh"
node_a_server_selection_runner_16aq_b="$caddy_root/scripts/run-node-a-caddy-server-selection-diagnostic-action16aq-b.sh"
"$node_a_server_selection_diagnostic_16aq_b" --self-test
"$node_a_server_selection_runner_16aq_b" --self-test
"$node_a_server_selection_runner_16aq_b" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_server_selection_diagnostic_16aq_b"; then
    printf 'Action 16aq-b diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_server_selection_diagnostic_16aq_b"; then
    printf 'Action 16aq-b diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_server_selection_diagnostic_16aq_b"; then
    printf 'Action 16aq-b diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq 'caddy_http_request_duration_seconds_count' \
    "$node_a_server_selection_diagnostic_16aq_b"
grep -Fq 'exact_listener_control_plus_unhandled_200' \
    "$node_a_server_selection_diagnostic_16aq_b"
grep -Fq 'runtime_metrics_counter_effect=true' \
    "$node_a_server_selection_diagnostic_16aq_b"
if grep -Fq '10000' "$node_a_server_selection_diagnostic_16aq_b"; then
    printf 'Action 16aq-b diagnostic must not access Webmin TCP 10000.\n' >&2
    exit 1
fi
grep -Fq -- '--summarize-servers' \
    "$node_a_server_selection_diagnostic_16aq_b"
grep -Fq \
    'readonly diagnostic_sha256=28ad0167c7e44242540cb5194fc308da8474f378dbc714a9f17931388e6321c3' \
    "$node_a_server_selection_runner_16aq_b"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_server_selection_runner_16aq_b"
grep -Fq 'pi@10.1.0.53' \
    "$node_a_server_selection_runner_16aq_b"
grep -Fq 'action_16aq_b_contract_test_complete=true' \
    "$node_a_server_selection_runner_16aq_b"
node_a_server_selection_correction_16aq_b_retry="$caddy_root/scripts/correct-node-a-caddy-server-selection-action16aq-b-retry.sh"
node_a_server_selection_runner_16aq_b_retry="$caddy_root/scripts/run-node-a-caddy-server-selection-diagnostic-action16aq-b-retry.sh"
"$node_a_server_selection_correction_16aq_b_retry" --extension-self-test
[[ "$(
    printf '%s' '200%7C10.1.0.53%7C2%7C0%7C0' |
        "$node_a_server_selection_correction_16aq_b_retry" \
            --decode-probe-code
)" == 200 ]]
"$node_a_server_selection_runner_16aq_b_retry" --self-test
"$node_a_server_selection_runner_16aq_b_retry" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_server_selection_correction_16aq_b_retry"; then
    printf 'Action 16aq-b retry correction contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_server_selection_correction_16aq_b_retry"; then
    printf 'Action 16aq-b retry correction contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_server_selection_correction_16aq_b_retry"; then
    printf 'Action 16aq-b retry correction must not make a peer connection.\n' \
        >&2
    exit 1
fi
grep -Fq '200%7C10.1.0.53%7C2%7C0%7C0' \
    "$node_a_server_selection_correction_16aq_b_retry"
grep -Fq 'corrected_unknown_http_code=' \
    "$node_a_server_selection_correction_16aq_b_retry"
grep -Fq 'corrected_server_selection_record=' \
    "$node_a_server_selection_correction_16aq_b_retry"
grep -Fq \
    'readonly diagnostic_sha256=28ad0167c7e44242540cb5194fc308da8474f378dbc714a9f17931388e6321c3' \
    "$node_a_server_selection_runner_16aq_b_retry"
grep -Fq \
    'readonly correction_sha256=5abef1aa638f054379a36c26cb47454299952fea3d6bb043b92a2585148e7b63' \
    "$node_a_server_selection_runner_16aq_b_retry"
# shellcheck disable=SC2016
grep -Fq 'cat "$diagnostic" "$correction" >"$remote_payload"' \
    "$node_a_server_selection_runner_16aq_b_retry"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_server_selection_runner_16aq_b_retry"
grep -Fq 'pi@10.1.0.53' \
    "$node_a_server_selection_runner_16aq_b_retry"
grep -Fq 'action_16aq_b_retry_contract_test_complete=true' \
    "$node_a_server_selection_runner_16aq_b_retry"
node_a_routing_correction_16ar="$caddy_root/scripts/apply-node-a-caddy-routing-correction-action16ar.sh"
node_a_routing_correction_runner_16ar="$caddy_root/scripts/run-node-a-caddy-routing-correction-action16ar.sh"
"$node_a_routing_correction_16ar" --self-test
"$node_a_routing_correction_runner_16ar" --self-test
"$node_a_routing_correction_runner_16ar" --contract-test
grep -Fq \
    'readonly correction_sha256=d3a31eabc6fd75784f5f3891d55dd80d3f024463d112d8dd68549c91bcde8ae7' \
    "$node_a_routing_correction_16ar"
grep -Fq \
    'readonly driver_sha256=a361d0f4e37bd84a440de9115c0a3148cf9511f3e80736ae93795d812b09278a' \
    "$node_a_routing_correction_runner_16ar"
grep -Fq \
    'readonly correction_sha256=d3a31eabc6fd75784f5f3891d55dd80d3f024463d112d8dd68549c91bcde8ae7' \
    "$node_a_routing_correction_runner_16ar"
grep -Fq 'systemctl reload caddy.service' \
    "$node_a_routing_correction_16ar"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_routing_correction_16ar"; then
    printf 'Action 16ar may reload Caddy but contains another service mutation.\n' >&2
    exit 1
fi
if grep -Eq '10[.]1[.]0[.]54|pihole00[.]local[.]theama[.]co|10000' \
    "$node_a_routing_correction_16ar"; then
    printf 'Action 16ar must not contact Node B or Webmin.\n' >&2
    exit 1
fi
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_routing_correction_runner_16ar"
grep -Fq 'pi@10.1.0.53' "$node_a_routing_correction_runner_16ar"
grep -Fq 'action_16ar_routing_correction_contract_test_complete=true' \
    "$node_a_routing_correction_runner_16ar"
node_a_recovery_diagnostic_16ar_a="$caddy_root/scripts/diagnose-node-a-action16ar-recovery-action16ar-a.sh"
node_a_recovery_runner_16ar_a="$caddy_root/scripts/run-node-a-action16ar-recovery-diagnostic-action16ar-a.sh"
"$node_a_recovery_diagnostic_16ar_a" --self-test
"$node_a_recovery_runner_16ar_a" --self-test
"$node_a_recovery_runner_16ar_a" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|ln)([[:space:]]|$)' \
    "$node_a_recovery_diagnostic_16ar_a"; then
    printf 'Action 16ar-a diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_recovery_diagnostic_16ar_a"; then
    printf 'Action 16ar-a diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_recovery_diagnostic_16ar_a"; then
    printf 'Action 16ar-a diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
if grep -Eq '10[.]1[.]0[.]54|pihole00[.]local[.]theama[.]co|10000' \
    "$node_a_recovery_diagnostic_16ar_a"; then
    printf 'Action 16ar-a must not inspect Node B or Webmin.\n' >&2
    exit 1
fi
grep -Fq '/etc/caddy/releases/action16ar-node-a-default-deny' \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq '/etc/caddy/releases/.action16ar-node-a-default-deny.staging' \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq '/etc/caddy/current.action16ar-new' \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq 'readonly caddy_admin=http://127.0.0.1:2019' \
    "$node_a_recovery_diagnostic_16ar_a"
# shellcheck disable=SC2016
grep -Fq '$caddy_admin/config/' \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq "journal_since='2026-07-29 16:20:00 UTC'" \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq 'filesystem_mutations=false' \
    "$node_a_recovery_diagnostic_16ar_a"
grep -Fq \
    'readonly inspector_sha256=c63146c3c2d7e3201bb5a90d3456333a3ccdcb4bf6a287721607e8f046ff28cb' \
    "$node_a_recovery_runner_16ar_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_recovery_runner_16ar_a"
grep -Fq 'pi@10.1.0.53' "$node_a_recovery_runner_16ar_a"
grep -Fq 'action_16ar_a_contract_test_complete=true' \
    "$node_a_recovery_runner_16ar_a"
node_a_routing_transformer_16ar_retry="$caddy_root/scripts/correct-node-a-caddy-routing-transaction-action16ar-retry.sh"
node_a_routing_runner_16ar_retry="$caddy_root/scripts/run-node-a-caddy-routing-correction-action16ar-retry.sh"
"$node_a_routing_transformer_16ar_retry" --self-test
"$node_a_routing_runner_16ar_retry" --self-test
"$node_a_routing_runner_16ar_retry" --contract-test
grep -Fq \
    'readonly historical_driver_sha256=a361d0f4e37bd84a440de9115c0a3148cf9511f3e80736ae93795d812b09278a' \
    "$node_a_routing_transformer_16ar_retry"
# shellcheck disable=SC2016
grep -Fq 'print "            print $1 \"|\" $2 \"|\" $5 \"|\" process"' \
    "$node_a_routing_transformer_16ar_retry"
grep -Fq 'gsub(/action16ar/, "action16ar-retry")' \
    "$node_a_routing_transformer_16ar_retry"
grep -Fq \
    'readonly transformer_sha256=d8c612cb6ea765d45ddb34878ab0dba31a30642d4c473340ce114f37264270e7' \
    "$node_a_routing_runner_16ar_retry"
grep -Fq \
    'readonly rendered_driver_sha256=b62222cc0edd941e7ea4ade533f494fe289b9ac741eb254b0c0b61cde8284a2f' \
    "$node_a_routing_runner_16ar_retry"
grep -Fq \
    'selected_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny' \
    "$node_a_routing_runner_16ar_retry"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_routing_runner_16ar_retry"
grep -Fq 'pi@10.1.0.53' "$node_a_routing_runner_16ar_retry"
grep -Fq 'action_16ar_retry_contract_test_complete=true' \
    "$node_a_routing_runner_16ar_retry"
grep -Fq 'raw_listener_candidate_equal=' \
    "$caddy_root/tests/action16ar-reload-regression.sh"
grep -Fq 'semantic_listener_candidate_equal=' \
    "$caddy_root/tests/action16ar-reload-regression.sh"
grep -Fq 'action_16ar_reload_regression_complete=true' \
    "$caddy_root/tests/action16ar-reload-regression.sh"
node_a_acceptance_deriver_16ar_b="$caddy_root/scripts/derive-node-a-post-correction-acceptance-action16ar-b.sh"
node_a_acceptance_runner_16ar_b="$caddy_root/scripts/run-node-a-post-correction-acceptance-action16ar-b.sh"
"$node_a_acceptance_deriver_16ar_b" --self-test
"$node_a_acceptance_runner_16ar_b" --self-test
"$node_a_acceptance_runner_16ar_b" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|ln)([[:space:]]|$)' \
    "$node_a_acceptance_deriver_16ar_b"; then
    printf 'Action 16ar-b rendered remote diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_acceptance_deriver_16ar_b"; then
    printf 'Action 16ar-b rendered remote diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '10[.]1[.]0[.]54|pihole00[.]local[.]theama[.]co|10000' \
    "$node_a_acceptance_deriver_16ar_b"; then
    printf 'Action 16ar-b rendered remote diagnostic must not inspect Node B or Webmin.\n' >&2
    exit 1
fi
grep -Fq \
    'readonly rendered_inspector_sha256=71c31f7e04beed53edc58bda0ac72b5079c15231f29639548aab9971710aed0f' \
    "$node_a_acceptance_runner_16ar_b"
grep -Fq \
    'readonly rendered_runner_sha256=8af27b5c54eda5a6a9f47692ea0072eda9312016e5a5545d3ac521d7d13fcf5d' \
    "$node_a_acceptance_runner_16ar_b"
grep -Fq \
    'readonly release_manifest_sha256=3e25f80cba754f7cbadfa08420889004cffc7781664bb624896efe5c4f5131dd' \
    "$node_a_acceptance_runner_16ar_b"
grep -Fq \
    'readonly content_manifest_sha256=272c1f17ad59d7050e61caa2da47fc8768d87777c0759cebdf513988ba837e70' \
    "$node_a_acceptance_runner_16ar_b"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_acceptance_runner_16ar_b"
grep -Fq 'pi@10.1.0.53' "$node_a_acceptance_runner_16ar_b"
grep -Fq 'action_16ar_b_acceptance_contract_test_complete=true' \
    "$node_a_acceptance_runner_16ar_b"
node_a_acceptance_correction_16ar_b_retry="$caddy_root/scripts/correct-node-a-post-correction-acceptance-action16ar-b-retry.sh"
node_a_acceptance_runner_16ar_b_retry="$caddy_root/scripts/run-node-a-post-correction-acceptance-action16ar-b-retry.sh"
node_a_acceptance_regression_16ar_b="$caddy_root/tests/action16ar-b-production-transcript-regression.sh"
"$node_a_acceptance_correction_16ar_b_retry" --self-test
"$node_a_acceptance_regression_16ar_b" --self-test
"$node_a_acceptance_runner_16ar_b_retry" --self-test
"$node_a_acceptance_runner_16ar_b_retry" --contract-test
grep -Fq \
    'readonly historical_runner_sha256=fe4e09369ee6699bceeb14453546ca6f22523219c5391a383b815f59293635fe' \
    "$node_a_acceptance_correction_16ar_b_retry"
grep -Fq \
    'readonly rendered_runner_sha256=00ab68767fef384ff0dca13c67d0c0970755d9e8c81861cc5d1c1f57fe49d25e' \
    "$node_a_acceptance_runner_16ar_b_retry"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_acceptance_runner_16ar_b_retry"
grep -Fq 'pi@10.1.0.53' "$node_a_acceptance_runner_16ar_b_retry"
grep -Fq 'action_16ar_b_production_transcript_regression_complete=true' \
    "$node_a_acceptance_regression_16ar_b"
sync_readiness_inspector_action17="$caddy_root/scripts/inspect-sync-readiness-before-action17.sh"
sync_readiness_runner_action17="$caddy_root/scripts/run-sync-readiness-before-action17.sh"
"$sync_readiness_inspector_action17" --self-test
"$sync_readiness_runner_action17" --self-test
"$sync_readiness_runner_action17" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|ln|mkdir)([[:space:]]|$)' \
    "$sync_readiness_inspector_action17"; then
    printf 'Action 17 readiness inspector contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$sync_readiness_inspector_action17"; then
    printf 'Action 17 readiness inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)|ssh[[:space:]]+-T' \
    "$sync_readiness_inspector_action17"; then
    printf 'Action 17 readiness inspector contains a peer command.\n' >&2
    exit 1
fi
grep -Fq 'readonly node_a_host_alias=pihole0.local.theama.co' \
    "$sync_readiness_runner_action17"
grep -Fq 'readonly node_b_host_alias=pihole00.local.theama.co' \
    "$sync_readiness_runner_action17"
grep -Fq 'pi@10.1.0.53' "$sync_readiness_runner_action17"
grep -Fq 'pi@10.1.0.54' "$sync_readiness_runner_action17"
grep -Fq 'action_17_sync_readiness_accepted=true' \
    "$sync_readiness_runner_action17"
sync_readiness_correction_action17a_retry="$caddy_root/scripts/correct-sync-readiness-before-action17-retry.sh"
sync_readiness_regression_action17a_retry="$caddy_root/tests/action17a-node-b-release-regression.sh"
sync_readiness_runner_action17a_retry="$caddy_root/scripts/run-sync-readiness-before-action17-retry.sh"
"$sync_readiness_correction_action17a_retry" --self-test
"$sync_readiness_regression_action17a_retry" --self-test
"$sync_readiness_runner_action17a_retry" --self-test
"$sync_readiness_runner_action17a_retry" --contract-test
grep -Fq \
    'readonly historical_inspector_sha256=1193632a867b4a86fd28f4b932b809926498b0b6a2e4751e8ee1f69c5da05ae8' \
    "$sync_readiness_correction_action17a_retry"
grep -Fq \
    'readonly rendered_inspector_sha256=87c910f1c7a5a01c21af8af0b840d339a793a91b9f430539760bfbe94a80b805' \
    "$sync_readiness_runner_action17a_retry"
grep -Fq \
    '/etc/caddy/releases/action15-health-follow-redirects' \
    "$sync_readiness_runner_action17a_retry"
grep -Fq 'action_17a_node_b_release_regression_complete=true' \
    "$sync_readiness_regression_action17a_retry"
node_b_authorization_driver_action17b="$caddy_root/scripts/authorize-node-a-sync-key-on-node-b-action17b.sh"
node_b_authorization_runner_action17b="$caddy_root/scripts/run-node-b-authorize-node-a-sync-key-action17b.sh"
node_b_authorization_regression_action17b="$caddy_root/tests/action17b-node-b-authorization-regression.sh"
"$node_b_authorization_driver_action17b" --self-test
"$node_b_authorization_runner_action17b" --self-test
"$node_b_authorization_runner_action17b" --contract-test
"$node_b_authorization_regression_action17b" --self-test
grep -Fq \
    'readonly driver_sha256=ebd126884ec1985b4561d5ac7fc16b54f93fb29e7d5de9fddbe4788925c27efe' \
    "$node_b_authorization_runner_action17b"
grep -Fq \
    'readonly expected_target=pi@10.1.0.54' \
    "$node_b_authorization_runner_action17b"
grep -Fq \
    'readonly expected_host_alias=pihole00.local.theama.co' \
    "$node_b_authorization_runner_action17b"
grep -Fq \
    'persistent_mutation_scope=authorized_keys_only' \
    "$node_b_authorization_driver_action17b"
grep -Fq \
    'action_17b_rollback_complete=true' \
    "$node_b_authorization_driver_action17b"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_b_authorization_driver_action17b"; then
    printf 'Action 17b driver contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)|ssh[[:space:]]+-T' \
    "$node_b_authorization_driver_action17b"; then
    printf 'Action 17b driver contains a synchronization or peer command.\n' >&2
    exit 1
fi
node_b_transport_inspector_action17c="$caddy_root/scripts/inspect-node-b-restricted-transport-state-action17c.sh"
node_a_transport_driver_action17c="$caddy_root/scripts/validate-node-a-to-node-b-restricted-transport-action17c.sh"
restricted_transport_runner_action17c="$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c.sh"
restricted_transport_regression_action17c="$caddy_root/tests/action17c-restricted-transport-regression.sh"
"$node_b_transport_inspector_action17c" --self-test
"$node_a_transport_driver_action17c" --self-test
"$restricted_transport_runner_action17c" --self-test
"$restricted_transport_runner_action17c" --contract-test
"$restricted_transport_regression_action17c" --self-test
grep -Fq \
    'readonly inspector_sha256=37e5390fb132c77002b468d9dfabfc579d5bb03f1da44f60802c448df3a35111' \
    "$restricted_transport_runner_action17c"
grep -Fq \
    'readonly driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0' \
    "$restricted_transport_runner_action17c"
grep -Fq 'readonly node_a_target=pi@10.1.0.53' \
    "$restricted_transport_runner_action17c"
grep -Fq 'readonly node_b_target=pi@10.1.0.54' \
    "$restricted_transport_runner_action17c"
grep -Fq 'release_payload_transferred=false' \
    "$node_a_transport_driver_action17c"
grep -Fq -- '--dry-run' "$node_a_transport_driver_action17c"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_b_transport_inspector_action17c" \
    "$node_a_transport_driver_action17c"; then
    printf 'Action 17c contains a service mutation.\n' >&2
    exit 1
fi
if grep -Fq -- '--delete' "$node_a_transport_driver_action17c"; then
    printf 'Action 17c driver contains a deletion request.\n' >&2
    exit 1
fi
restricted_transport_correction_action17c_retry="$caddy_root/scripts/correct-restricted-transport-action17c-retry.sh"
restricted_transport_stream_regression_action17c_retry="$caddy_root/tests/action17c-streamed-stdin-continuity-regression.sh"
restricted_transport_runner_action17c_retry="$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c-retry.sh"
"$restricted_transport_correction_action17c_retry" --self-test
"$restricted_transport_stream_regression_action17c_retry" --self-test
"$restricted_transport_runner_action17c_retry" --self-test
"$restricted_transport_runner_action17c_retry" --contract-test
grep -Fq \
    'readonly historical_driver_sha256=f3e775716ec0d3506b67088286545fb5998e2c587b56f18e5f20b27c314a15c0' \
    "$restricted_transport_correction_action17c_retry"
grep -Fq \
    'readonly historical_runner_sha256=d2b8672f7b3c336e4dfe9e1bf7f12b61290e8a993a8c92eef252b3a5b03f510b' \
    "$restricted_transport_correction_action17c_retry"
grep -Fq \
    'readonly rendered_driver_sha256=3259b979e64ccee667e2a81ac9683c21d140331c0d1f44d6c6e41bf88a7b31dd' \
    "$restricted_transport_correction_action17c_retry"
grep -Fq \
    'readonly rendered_runner_sha256=c88ab6f91f3adaeab6a7cd5ba7c2013d8d62bc7d393601a370c140f50e1eb795' \
    "$restricted_transport_correction_action17c_retry"
grep -Fq \
    'action_17c_streamed_stdin_continuity_regression_complete=true' \
    "$restricted_transport_stream_regression_action17c_retry"
grep -Fq \
    'readonly correction_sha256=693a75d7cfb1c308a1367111c5891e3eae3fac7dc1e4bfd8ea4a43604f2229b6' \
    "$restricted_transport_runner_action17c_retry"
grep -Fq \
    'action_17c_retry_accepted=true' \
    "$restricted_transport_runner_action17c_retry"
ipv6_transport_node_b_inspector_action17c_a="$caddy_root/scripts/inspect-node-b-ipv6-restricted-transport-action17c-a.sh"
ipv6_transport_node_a_diagnostic_action17c_a="$caddy_root/scripts/diagnose-node-a-to-node-b-ipv6-restricted-transport-action17c-a.sh"
ipv6_transport_runner_action17c_a="$caddy_root/scripts/run-node-a-to-node-b-ipv6-restricted-transport-diagnostic-action17c-a.sh"
ipv6_transport_regression_action17c_a="$caddy_root/tests/action17c-a-ipv6-diagnostic-regression.sh"
"$ipv6_transport_node_b_inspector_action17c_a" --self-test
"$ipv6_transport_node_a_diagnostic_action17c_a" --self-test
"$ipv6_transport_runner_action17c_a" --self-test
"$ipv6_transport_runner_action17c_a" --contract-test
"$ipv6_transport_regression_action17c_a" --self-test
grep -Fq 'ssh -6 -n -T -vv' \
    "$ipv6_transport_node_a_diagnostic_action17c_a"
grep -Fq 'rsync_invoked=false' \
    "$ipv6_transport_node_a_diagnostic_action17c_a"
grep -Fq 'action_17c_a_diagnostic_conclusion=' \
    "$ipv6_transport_runner_action17c_a"
ipv6_source_diagnostic_action17c_b="$caddy_root/scripts/diagnose-node-a-ipv6-source-selection-action17c-b.sh"
ipv6_source_runner_action17c_b="$caddy_root/scripts/run-node-a-ipv6-source-selection-diagnostic-action17c-b.sh"
ipv6_source_regression_action17c_b="$caddy_root/tests/action17c-b-ipv6-source-selection-regression.sh"
"$ipv6_source_diagnostic_action17c_b" --self-test
"$ipv6_source_runner_action17c_b" --self-test
"$ipv6_source_runner_action17c_b" --contract-test
"$ipv6_source_regression_action17c_b" --self-test
grep -Fq 'node_a_ipv6_selected_source=' \
    "$ipv6_source_diagnostic_action17c_b"
grep -Fq 'stable_source_binding_restores_authorization' \
    "$ipv6_source_runner_action17c_b"
source_binding_runner_action17c_c="$caddy_root/scripts/run-node-a-source-bound-transport-action17c-c.sh"
source_binding_regression_action17c_c="$caddy_root/tests/action17c-c-source-binding-regression.sh"
"$source_binding_runner_action17c_c" --self-test
"$source_binding_runner_action17c_c" --contract-test
"$source_binding_regression_action17c_c" --self-test
working_directory_regression_action17c_c="$caddy_root/tests/action17c-c-working-directory-regression.sh"
"$working_directory_regression_action17c_c" --self-test
source_bound_diagnostic_action17c_c_a="$caddy_root/scripts/diagnose-node-a-source-bound-transport-action17c-c-a.sh"
source_bound_diagnostic_runner_action17c_c_a="$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh"
source_bound_diagnostic_regression_action17c_c_a="$caddy_root/tests/action17c-c-a-source-bound-diagnostic-regression.sh"
"$source_bound_diagnostic_action17c_c_a" --self-test
"$source_bound_diagnostic_runner_action17c_c_a" --self-test
"$source_bound_diagnostic_runner_action17c_c_a" --contract-test
"$source_bound_diagnostic_regression_action17c_c_a" --self-test
peer_resolution_diagnostic_action17c_c_b="$caddy_root/scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh"
peer_resolution_runner_action17c_c_b="$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh"
peer_resolution_regression_action17c_c_b="$caddy_root/tests/action17c-c-b-peer-resolution-context-regression.sh"
"$peer_resolution_diagnostic_action17c_c_b" --self-test
"$peer_resolution_runner_action17c_c_b" --self-test
"$peer_resolution_runner_action17c_c_b" --contract-test
"$peer_resolution_regression_action17c_c_b" --self-test
peer_resolution_correction_action17c_c_b_retry="$caddy_root/scripts/correct-peer-resolution-readonly-shadow-action17c-c-b-retry.sh"
peer_resolution_runner_action17c_c_b_retry="$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry.sh"
peer_resolution_regression_action17c_c_b_retry="$caddy_root/tests/action17c-c-b-second-resolver-snapshot-regression.sh"
"$peer_resolution_correction_action17c_c_b_retry" --self-test
"$peer_resolution_runner_action17c_c_b_retry" --self-test
"$peer_resolution_runner_action17c_c_b_retry" --contract-test
"$peer_resolution_regression_action17c_c_b_retry" --self-test
dns_path_collector_action17c_c_c="$caddy_root/scripts/diagnose-dns-path-authority-action17c-c-c.sh"
dns_path_runner_action17c_c_c="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh"
dns_path_regression_action17c_c_c="$caddy_root/tests/action17c-c-c-dns-path-authority-regression.sh"
"$dns_path_collector_action17c_c_c" --self-test
"$dns_path_runner_action17c_c_c" --self-test
"$dns_path_runner_action17c_c_c" --contract-test
[[ -f "$dns_path_regression_action17c_c_c" ]]
dns_continuity_inspector_action17c_c_c_a="$caddy_root/scripts/inspect-dns-continuity-action17c-c-c-a.sh"
dns_continuity_runner_action17c_c_c_a="$caddy_root/scripts/run-dns-continuity-action17c-c-c-a.sh"
dns_continuity_regression_action17c_c_c_a="$caddy_root/tests/action17c-c-c-a-dns-continuity-regression.sh"
"$dns_continuity_inspector_action17c_c_c_a" --self-test
"$dns_continuity_runner_action17c_c_c_a" --self-test
"$dns_continuity_runner_action17c_c_c_a" --contract-test
"$dns_continuity_regression_action17c_c_c_a" --self-test
dns_path_correction_action17c_c_c_retry="$caddy_root/scripts/correct-dns-path-work-dir-action17c-c-c-retry.sh"
dns_path_runner_action17c_c_c_retry="$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry.sh"
dns_path_regression_action17c_c_c_retry="$caddy_root/tests/action17c-c-c-first-query-production-regression.sh"
"$dns_path_correction_action17c_c_c_retry" --self-test
"$dns_path_regression_action17c_c_c_retry" --production-test
"$dns_path_runner_action17c_c_c_retry" --self-test
"$dns_path_runner_action17c_c_c_retry" --contract-test
node_b_unbound_inspector_action17d="$caddy_root/scripts/inspect-node-b-two-file-unbound-preflight-action17d.sh"
node_b_unbound_regression_action17d="$caddy_root/tests/action17d-node-b-two-file-unbound-preflight-regression.sh"
node_b_unbound_runner_action17d="$caddy_root/scripts/run-node-b-two-file-unbound-preflight-action17d.sh"
"$node_b_unbound_inspector_action17d" --self-test
"$node_b_unbound_regression_action17d" --self-test
"$node_b_unbound_runner_action17d" --self-test
"$node_b_unbound_runner_action17d" --contract-test
node_b_unbound_primary_driver_action17e="$caddy_root/scripts/stage-node-b-unbound-primary-action17e.sh"
node_b_unbound_primary_regression_action17e="$caddy_root/tests/action17e-node-b-unbound-primary-stage-regression.sh"
node_b_unbound_primary_runner_action17e="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh"
"$node_b_unbound_primary_driver_action17e" --self-test
"$node_b_unbound_primary_regression_action17e" --self-test
"$node_b_unbound_primary_runner_action17e" --self-test
"$node_b_unbound_primary_runner_action17e" --source-test
"$node_b_unbound_primary_runner_action17e" --contract-test
node_b_unbound_prewrite_diagnostic_action17e_a="$caddy_root/scripts/diagnose-node-b-unbound-primary-prewrite-action17e-a.sh"
node_b_unbound_prewrite_regression_action17e_a="$caddy_root/tests/action17e-a-node-b-unbound-prewrite-diagnostic-regression.sh"
node_b_unbound_prewrite_runner_action17e_a="$caddy_root/scripts/run-node-b-unbound-primary-prewrite-diagnostic-action17e-a.sh"
"$node_b_unbound_prewrite_diagnostic_action17e_a" --self-test
"$node_b_unbound_prewrite_regression_action17e_a" --self-test
"$node_b_unbound_prewrite_runner_action17e_a" --self-test
"$node_b_unbound_prewrite_runner_action17e_a" --source-test
"$node_b_unbound_prewrite_runner_action17e_a" --contract-test
node_b_unbound_correction_action17e_retry="$caddy_root/scripts/correct-node-b-unbound-primary-working-directory-action17e-retry.sh"
node_b_unbound_regression_action17e_retry="$caddy_root/tests/action17e-working-directory-production-regression.sh"
node_b_unbound_runner_action17e_retry="$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e-retry.sh"
"$node_b_unbound_correction_action17e_retry" --self-test
"$node_b_unbound_regression_action17e_retry" --production-test
"$node_b_unbound_runner_action17e_retry" --self-test
"$node_b_unbound_runner_action17e_retry" --source-test
"$node_b_unbound_runner_action17e_retry" --contract-test
node_b_unbound_local_zone_driver_action17f="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"
node_b_unbound_local_zone_regression_action17f="$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh"
node_b_unbound_local_zone_runner_action17f="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f.sh"
"$node_b_unbound_local_zone_driver_action17f" --self-test
[[ -f "$node_b_unbound_local_zone_regression_action17f" ]]
"$node_b_unbound_local_zone_runner_action17f" --contract-test
node_b_unbound_prewrite_inspector_action17f_a="$caddy_root/scripts/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh"
node_b_unbound_prewrite_regression_action17f_a="$caddy_root/tests/action17f-a-node-b-unbound-prewrite-diagnostic-regression.sh"
node_b_unbound_prewrite_runner_action17f_a="$caddy_root/scripts/run-node-b-unbound-local-zone-prewrite-diagnostic-action17f-a.sh"
"$node_b_unbound_prewrite_inspector_action17f_a" --self-test
"$node_b_unbound_prewrite_regression_action17f_a" --production-test
"$node_b_unbound_prewrite_runner_action17f_a" --self-test
"$node_b_unbound_prewrite_runner_action17f_a" --source-test
"$node_b_unbound_prewrite_runner_action17f_a" --contract-test
node_b_unbound_instrumentation_action17f_retry="$caddy_root/scripts/instrument-node-b-unbound-local-zone-action17f-retry.sh"
node_b_unbound_regression_action17f_retry="$caddy_root/tests/action17f-instrumented-retry-regression.sh"
node_b_unbound_runner_action17f_retry="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-retry.sh"
"$node_b_unbound_instrumentation_action17f_retry" --self-test
"$node_b_unbound_regression_action17f_retry" --production-test
[[ -f "$node_b_unbound_runner_action17f_retry" ]]
node_b_unbound_transition_diagnostic_action17f_b="$caddy_root/scripts/diagnose-node-b-unbound-action17f-transition.sh"
node_b_unbound_transition_regression_action17f_b="$caddy_root/tests/action17f-b-transition-diagnostic-regression.sh"
node_b_unbound_transition_runner_action17f_b="$caddy_root/scripts/run-node-b-unbound-action17f-transition-diagnostic.sh"
"$node_b_unbound_transition_diagnostic_action17f_b" --self-test
"$node_b_unbound_transition_regression_action17f_b"
"$node_b_unbound_transition_runner_action17f_b" --self-test
"$node_b_unbound_transition_runner_action17f_b" --source-test
"$node_b_unbound_transition_runner_action17f_b" --contract-test
"$caddy_root/tests/check-shell-readonly-local-collisions.sh"
node_b_unbound_labeled_trace_action17f_b_retry="$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-retry.sh"
node_b_unbound_labeled_regression_action17f_b_retry="$caddy_root/tests/action17f-b-labeled-baseline-retry-regression.sh"
node_b_unbound_labeled_runner_action17f_b_retry="$caddy_root/scripts/run-node-b-unbound-action17f-labeled-baseline-retry.sh"
"$node_b_unbound_labeled_trace_action17f_b_retry" --self-test
"$node_b_unbound_labeled_regression_action17f_b_retry"
"$node_b_unbound_labeled_runner_action17f_b_retry" --self-test
"$node_b_unbound_labeled_runner_action17f_b_retry" --source-test
"$node_b_unbound_labeled_runner_action17f_b_retry" --contract-test
node_b_unbound_trace_action17f_b_second_retry="$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-second-retry.sh"
node_b_unbound_regression_action17f_b_second_retry="$caddy_root/tests/action17f-b-second-retry-production-failure-regression.sh"
node_b_unbound_runner_action17f_b_second_retry="$caddy_root/scripts/run-node-b-unbound-action17f-baseline-second-retry.sh"
"$node_b_unbound_trace_action17f_b_second_retry" --self-test
"$node_b_unbound_regression_action17f_b_second_retry"
"$node_b_unbound_runner_action17f_b_second_retry" --self-test
"$node_b_unbound_runner_action17f_b_second_retry" --source-test
"$node_b_unbound_runner_action17f_b_second_retry" --contract-test
node_b_unbound_correction_action17f_normalized_retry="$caddy_root/scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"
node_b_unbound_regression_action17f_normalized_retry="$caddy_root/tests/action17f-normalized-live-state-boundary-regression.sh"
node_b_unbound_runner_action17f_normalized_retry="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-normalized-retry.sh"
"$node_b_unbound_correction_action17f_normalized_retry" --self-test
"$node_b_unbound_regression_action17f_normalized_retry" --production-test
[[ -f "$node_b_unbound_runner_action17f_normalized_retry" ]]
node_b_unbound_stage_inspector_action17f_c="$caddy_root/scripts/inspect-node-b-unbound-local-zone-stage-action17f-c.sh"
node_b_unbound_stage_regression_action17f_c="$caddy_root/tests/action17f-c-retained-stage-regression.sh"
node_b_unbound_stage_runner_action17f_c="$caddy_root/scripts/run-node-b-unbound-local-zone-stage-verification-action17f-c.sh"
"$node_b_unbound_stage_inspector_action17f_c" --self-test
"$node_b_unbound_stage_regression_action17f_c" --self-test
"$node_b_unbound_stage_runner_action17f_c" --self-test
"$node_b_unbound_stage_runner_action17f_c" --source-test
"$node_b_unbound_stage_runner_action17f_c" --contract-test
node_b_unbound_activation_driver_action17g="$caddy_root/scripts/activate-node-b-unbound-two-file-action17g.sh"
node_b_unbound_activation_regression_action17g="$caddy_root/tests/action17g-node-b-unbound-two-file-activation-regression.sh"
node_b_unbound_activation_runner_action17g="$caddy_root/scripts/run-node-b-unbound-two-file-activation-action17g.sh"
"$node_b_unbound_activation_driver_action17g" --self-test
"$node_b_unbound_activation_regression_action17g" --production-test
"$node_b_unbound_activation_runner_action17g" --self-test
"$node_b_unbound_activation_runner_action17g" --source-test
"$node_b_unbound_activation_runner_action17g" --contract-test
node_b_unbound_post_activation_inspector_action17g_a="$caddy_root/scripts/inspect-node-b-unbound-post-activation-action17g-a.sh"
node_b_unbound_post_activation_regression_action17g_a="$caddy_root/tests/action17g-a-node-b-unbound-post-activation-regression.sh"
node_b_unbound_post_activation_runner_action17g_a="$caddy_root/scripts/run-node-b-unbound-post-activation-action17g-a.sh"
"$node_b_unbound_post_activation_inspector_action17g_a" --self-test
"$node_b_unbound_post_activation_regression_action17g_a" --production-test
"$node_b_unbound_post_activation_runner_action17g_a" --self-test
"$node_b_unbound_post_activation_runner_action17g_a" --source-test
"$node_b_unbound_post_activation_runner_action17g_a" --contract-test
node_a_unbound_preflight_inspector_action17h="$caddy_root/scripts/inspect-node-a-two-file-unbound-preflight-action17h.sh"
node_a_unbound_preflight_regression_action17h="$caddy_root/tests/action17h-node-a-two-file-unbound-preflight-regression.sh"
node_a_unbound_preflight_runner_action17h="$caddy_root/scripts/run-node-a-two-file-unbound-preflight-action17h.sh"
"$node_a_unbound_preflight_inspector_action17h" --self-test
[[ -f "$node_a_unbound_preflight_regression_action17h" ]]
"$node_a_unbound_preflight_runner_action17h" --contract-test
node_a_unbound_semantic_diff_diagnostic_action17h_a="$caddy_root/scripts/inspect-node-a-unbound-semantic-diff-action17h-a.sh"
node_a_unbound_semantic_diff_regression_action17h_a="$caddy_root/tests/action17h-a-node-a-semantic-diff-regression.sh"
node_a_unbound_semantic_diff_runner_action17h_a="$caddy_root/scripts/run-node-a-unbound-semantic-diff-action17h-a.sh"
"$node_a_unbound_semantic_diff_diagnostic_action17h_a" --self-test
[[ -f "$node_a_unbound_semantic_diff_regression_action17h_a" ]]
"$node_a_unbound_semantic_diff_runner_action17h_a" --contract-test
node_a_unbound_primary_driver_action17i="$caddy_root/scripts/stage-node-a-unbound-primary-action17i.sh"
node_a_unbound_primary_regression_action17i="$caddy_root/tests/action17i-node-a-unbound-primary-stage-regression.sh"
node_a_unbound_primary_runner_action17i="$caddy_root/scripts/run-node-a-unbound-primary-stage-action17i.sh"
"$node_a_unbound_primary_driver_action17i" --self-test
"$node_a_unbound_primary_regression_action17i" --self-test
"$node_a_unbound_primary_runner_action17i" --self-test
"$node_a_unbound_primary_runner_action17i" --source-test
"$node_a_unbound_primary_runner_action17i" --contract-test
node_a_unbound_local_zone_driver_action17j="$caddy_root/scripts/stage-node-a-unbound-local-zone-action17j.sh"
node_a_unbound_local_zone_regression_action17j="$caddy_root/tests/action17j-node-a-unbound-local-zone-stage-regression.sh"
node_a_unbound_local_zone_runner_action17j="$caddy_root/scripts/run-node-a-unbound-local-zone-stage-action17j.sh"
"$node_a_unbound_local_zone_driver_action17j" --self-test
[[ -f "$node_a_unbound_local_zone_regression_action17j" ]]
"$node_a_unbound_local_zone_runner_action17j" --contract-test
node_a_unbound_dual_stage_inspector_action17j_a="$caddy_root/scripts/inspect-node-a-unbound-dual-stage-action17j-a.sh"
node_a_unbound_dual_stage_regression_action17j_a="$caddy_root/tests/action17j-a-node-a-dual-stage-acceptance-regression.sh"
node_a_unbound_dual_stage_runner_action17j_a="$caddy_root/scripts/run-node-a-unbound-dual-stage-acceptance-action17j-a.sh"
"$node_a_unbound_dual_stage_inspector_action17j_a" --self-test
"$node_a_unbound_dual_stage_regression_action17j_a" --self-test
"$node_a_unbound_dual_stage_runner_action17j_a" --self-test
"$node_a_unbound_dual_stage_runner_action17j_a" --source-test
"$node_a_unbound_dual_stage_runner_action17j_a" --contract-test
node_a_unbound_activation_driver_action17k="$caddy_root/scripts/activate-node-a-unbound-two-file-action17k.sh"
node_a_unbound_activation_regression_action17k="$caddy_root/tests/action17k-node-a-unbound-two-file-activation-regression.sh"
node_a_unbound_activation_runner_action17k="$caddy_root/scripts/run-node-a-unbound-two-file-activation-action17k.sh"
"$node_a_unbound_activation_driver_action17k" --self-test
"$node_a_unbound_activation_regression_action17k" --production-test
"$node_a_unbound_activation_runner_action17k" --self-test
"$node_a_unbound_activation_runner_action17k" --source-test
"$node_a_unbound_activation_runner_action17k" --contract-test
node_a_unbound_post_activation_inspector_action17k_a="$caddy_root/scripts/inspect-node-a-unbound-post-activation-action17k-a.sh"
node_a_unbound_post_activation_regression_action17k_a="$caddy_root/tests/action17k-a-node-a-unbound-post-activation-regression.sh"
node_a_unbound_post_activation_runner_action17k_a="$caddy_root/scripts/run-node-a-unbound-post-activation-action17k-a.sh"
"$node_a_unbound_post_activation_inspector_action17k_a" --self-test
"$node_a_unbound_post_activation_regression_action17k_a" --production-test
"$node_a_unbound_post_activation_runner_action17k_a" --self-test
"$node_a_unbound_post_activation_runner_action17k_a" --source-test
"$node_a_unbound_post_activation_runner_action17k_a" --contract-test
dual_node_dns_sync_readiness_inspector_action17l="$caddy_root/scripts/inspect-dual-node-dns-sync-readiness-action17l.sh"
dual_node_dns_sync_readiness_regression_action17l="$caddy_root/tests/action17l-dual-node-dns-sync-readiness-regression.sh"
dual_node_dns_sync_readiness_runner_action17l="$caddy_root/scripts/run-dual-node-dns-sync-readiness-action17l.sh"
node_b_dns_nss_driver_action17m="$caddy_root/scripts/apply-node-b-dns-nss-correction-action17m.sh"
node_b_dns_nss_runner_action17m="$caddy_root/scripts/run-node-b-dns-nss-correction-action17m.sh"
node_b_dns_nss_regression_action17m="$caddy_root/tests/action17m-node-b-dns-nss-correction-regression.sh"
unbound_source_advance_regression_action17m="$caddy_root/tests/action17m-unbound-source-advance-regression.sh"
node_b_dns_nss_inspector_action17m_a="$caddy_root/scripts/inspect-node-b-dns-nss-post-correction-action17m-a.sh"
node_b_dns_nss_runner_action17m_a="$caddy_root/scripts/run-node-b-dns-nss-post-correction-action17m-a.sh"
node_b_dns_nss_regression_action17m_a="$caddy_root/tests/action17m-a-node-b-dns-nss-post-correction-regression.sh"
node_a_dns_nss_driver_action17n="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n.sh"
node_a_dns_nss_runner_action17n="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n.sh"
node_a_dns_nss_regression_action17n="$caddy_root/tests/action17n-node-a-dns-nss-correction-regression.sh"
node_a_post_rollback_inspector_action17n_a="$caddy_root/scripts/inspect-node-a-dns-nss-post-rollback-action17n-a.sh"
node_a_post_rollback_runner_action17n_a="$caddy_root/scripts/run-node-a-dns-nss-post-rollback-action17n-a.sh"
node_a_post_rollback_regression_action17n_a="$caddy_root/tests/action17n-a-node-a-post-rollback-readiness-regression.sh"
node_a_dns_nss_driver_action17n_retry="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-retry.sh"
node_a_dns_nss_runner_action17n_retry="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh"
node_a_dns_nss_regression_action17n_retry="$caddy_root/tests/action17n-retry-node-a-dns-nss-correction-regression.sh"
node_a_pihole_inspector_action17n_b="$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b.sh"
node_a_pihole_runner_action17n_b="$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b.sh"
node_a_pihole_regression_action17n_b="$caddy_root/tests/action17n-b-node-a-pihole-response-path-regression.sh"
node_a_pihole_inspector_action17n_b_retry="$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b-retry.sh"
node_a_pihole_runner_action17n_b_retry="$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b-retry.sh"
node_a_pihole_regression_action17n_b_retry="$caddy_root/tests/action17n-b-retry-absolute-pihole-path-regression.sh"
node_a_dns_nss_driver_action17n_reset_retry="$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-reset-retry.sh"
node_a_dns_nss_runner_action17n_reset_retry="$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-reset-retry.sh"
node_a_dns_nss_regression_action17n_reset_retry="$caddy_root/tests/action17n-reset-retry-node-a-dns-nss-regression.sh"
node_a_transport_inspector_action17o="$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh"
node_b_transport_inspector_action17o="$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh"
transport_runner_action17o="$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh"
transport_regression_action17o="$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh"
node_a_rsync_output_diagnostic_action17o_a="$caddy_root/scripts/diagnose-node-a-rsync-dry-run-output-action17o-a.sh"
node_a_rsync_output_runner_action17o_a="$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh"
node_a_rsync_output_regression_action17o_a="$caddy_root/tests/action17o-a-rsync-output-classification-regression.sh"
node_a_rsync_refinement_action17o_b="$caddy_root/scripts/refine-node-a-rsync-output-classification-action17o-b.sh"
node_a_rsync_refinement_runner_action17o_b="$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh"
node_a_rsync_refinement_regression_action17o_b="$caddy_root/tests/action17o-b-classification-refinement-regression.sh"
transport_acceptance_runner_action17o_c="$caddy_root/scripts/run-node-a-to-node-b-source-bound-transport-acceptance-action17o-c.sh"
transport_acceptance_regression_action17o_c="$caddy_root/tests/action17o-c-source-bound-transport-acceptance-regression.sh"
release_transfer_node_a_action17p="$caddy_root/scripts/transfer-node-a-release-to-node-b-action17p.sh"
release_transfer_node_b_action17p="$caddy_root/scripts/inspect-node-b-incoming-release-action17p.sh"
release_transfer_runner_action17p="$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action17p.sh"
release_transfer_regression_action17p="$caddy_root/tests/action17p-release-transfer-regression.sh"
release_failure_inspector_action17p_a="$caddy_root/scripts/inspect-release-transfer-failure-action17p-a.sh"
release_failure_runner_action17p_a="$caddy_root/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh"
release_failure_regression_action17p_a="$caddy_root/tests/action17p-a-release-transfer-failure-regression.sh"
labeled_dns_readiness_policy="$caddy_root/tests/labeled-dns-readiness-policy-regression.sh"
"$dual_node_dns_sync_readiness_inspector_action17l" --self-test
"$dual_node_dns_sync_readiness_regression_action17l" --production-test
"$dual_node_dns_sync_readiness_runner_action17l" --contract-test
"$node_b_dns_nss_driver_action17m" --self-test
"$node_b_dns_nss_runner_action17m" --self-test
"$node_b_dns_nss_runner_action17m" --source-test
"$node_b_dns_nss_runner_action17m" --contract-test
"$node_b_dns_nss_regression_action17m" --production-test
"$unbound_source_advance_regression_action17m" --production-test
"$node_b_dns_nss_inspector_action17m_a" --self-test
"$node_b_dns_nss_runner_action17m_a" --self-test
"$node_b_dns_nss_runner_action17m_a" --source-test
"$node_b_dns_nss_runner_action17m_a" --contract-test
"$node_b_dns_nss_regression_action17m_a" --production-test
"$node_a_dns_nss_driver_action17n" --self-test
"$node_a_dns_nss_runner_action17n" --self-test
"$node_a_dns_nss_runner_action17n" --source-test
"$node_a_dns_nss_runner_action17n" --contract-test
"$node_a_dns_nss_regression_action17n" --production-test
"$node_a_post_rollback_inspector_action17n_a" --self-test
"$node_a_post_rollback_runner_action17n_a" --self-test
"$node_a_post_rollback_runner_action17n_a" --source-test
"$node_a_post_rollback_runner_action17n_a" --contract-test
"$node_a_post_rollback_regression_action17n_a" --production-test
"$node_a_dns_nss_driver_action17n_retry" --self-test
"$node_a_dns_nss_runner_action17n_retry" --self-test
"$node_a_dns_nss_runner_action17n_retry" --source-test
"$node_a_dns_nss_runner_action17n_retry" --contract-test
"$node_a_dns_nss_regression_action17n_retry" --production-test
"$node_a_pihole_inspector_action17n_b" --self-test
"$node_a_pihole_runner_action17n_b" --self-test
"$node_a_pihole_runner_action17n_b" --source-test
"$node_a_pihole_regression_action17n_b" --production-test
"$node_a_pihole_inspector_action17n_b_retry" --self-test
"$node_a_pihole_runner_action17n_b_retry" --self-test
"$node_a_pihole_runner_action17n_b_retry" --source-test
"$node_a_pihole_regression_action17n_b_retry" --production-test
"$node_a_dns_nss_driver_action17n_reset_retry" --self-test
"$node_a_dns_nss_runner_action17n_reset_retry" --self-test
"$node_a_dns_nss_runner_action17n_reset_retry" --source-test
"$node_a_dns_nss_runner_action17n_reset_retry" --contract-test
"$node_a_dns_nss_regression_action17n_reset_retry" --production-test
"$node_a_transport_inspector_action17o" --self-test
"$node_a_transport_inspector_action17o" --contract-test
"$node_b_transport_inspector_action17o" --self-test
"$transport_runner_action17o" --self-test
"$transport_runner_action17o" --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$transport_runner_action17o"
"$transport_regression_action17o" --production-test
"$node_a_rsync_output_diagnostic_action17o_a" --self-test
"$node_a_rsync_output_diagnostic_action17o_a" --classifier-test
"$node_a_rsync_output_runner_action17o_a" --self-test
"$node_a_rsync_output_runner_action17o_a" --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$node_a_rsync_output_runner_action17o_a"
"$node_a_rsync_output_regression_action17o_a" --production-test
"$node_a_rsync_refinement_action17o_b" --self-test
"$node_a_rsync_refinement_action17o_b" --classifier-test
"$node_a_rsync_refinement_runner_action17o_b" --self-test
"$node_a_rsync_refinement_runner_action17o_b" --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$node_a_rsync_refinement_runner_action17o_b"
"$node_a_rsync_refinement_regression_action17o_b" --production-test
"$transport_acceptance_runner_action17o_c" --self-test
"$transport_acceptance_runner_action17o_c" --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$transport_acceptance_runner_action17o_c"
"$transport_acceptance_regression_action17o_c" --production-test
"$release_transfer_node_a_action17p" --self-test
"$release_transfer_node_b_action17p" --self-test
"$release_transfer_runner_action17p" --self-test
"$release_transfer_runner_action17p" --contract-test
"$release_transfer_regression_action17p"
"$release_failure_inspector_action17p_a" --self-test
"$release_failure_runner_action17p_a" --self-test
"$release_failure_runner_action17p_a" --contract-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$release_failure_runner_action17p_a"
"$release_failure_regression_action17p_a" --production-test
"$labeled_dns_readiness_policy" --production-test
dns_vip_response_inspector_action17m_b="$caddy_root/scripts/inspect-dns-vip-response-path-action17m-b.sh"
dns_vip_response_runner_action17m_b="$caddy_root/scripts/run-dns-vip-response-path-diagnostic-action17m-b.sh"
dns_vip_response_regression_action17m_b="$caddy_root/tests/action17m-b-dns-vip-response-path-regression.sh"
"$dns_vip_response_inspector_action17m_b" --self-test
"$dns_vip_response_runner_action17m_b" --self-test
"$dns_vip_response_runner_action17m_b" --source-test
"$dns_vip_response_runner_action17m_b" --contract-test
"$dns_vip_response_regression_action17m_b" --production-test
node_a_recovery_diagnostic_16ap_a="$caddy_root/scripts/diagnose-node-a-recovery-state-action16ap-a.sh"
node_a_recovery_runner_16ap_a="$caddy_root/scripts/run-node-a-recovery-diagnostic-action16ap-a.sh"
"$node_a_recovery_diagnostic_16ap_a" --self-test
"$node_a_recovery_runner_16ap_a" --self-test
"$node_a_recovery_runner_16ap_a" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$node_a_recovery_diagnostic_16ap_a"; then
    printf 'Action 16ap-a diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$node_a_recovery_diagnostic_16ap_a"; then
    printf 'Action 16ap-a diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$node_a_recovery_diagnostic_16ap_a"; then
    printf 'Action 16ap-a diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq '/etc/.lighttpd-pre-action16ap' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq '/etc/.lighttpd-caddy-action16ap.failed' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq '/var/tmp/caddy-ha-lighttpd-node-a-action16ab' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'service_record=' "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'path_record=' "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'lighttpd_record=' "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'listener_record=' "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'health_record=' "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'journalctl --no-pager --quiet -n 25' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'systemd_daemon_reload_performed=false' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'service_mutations=false' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'filesystem_mutations=false' \
    "$node_a_recovery_diagnostic_16ap_a"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$node_a_recovery_runner_16ap_a"
grep -Fq 'pi@10.1.0.53' "$node_a_recovery_runner_16ap_a"
grep -Fq 'action_16ap_a_contract_test_complete=true' \
    "$node_a_recovery_runner_16ap_a"
caddy_validation_diagnostic_16ap_b="$caddy_root/scripts/diagnose-caddy-validation-provenance-action16ap-b.sh"
caddy_validation_runner_16ap_b="$caddy_root/scripts/run-caddy-validation-provenance-action16ap-b.sh"
"$caddy_validation_diagnostic_16ap_b" --self-test
"$caddy_validation_runner_16ap_b" --self-test
"$caddy_validation_runner_16ap_b" --contract-test
if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$caddy_validation_diagnostic_16ap_b"; then
    printf 'Action 16ap-b diagnostic contains a write command.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$caddy_validation_diagnostic_16ap_b"; then
    printf 'Action 16ap-b diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$caddy_validation_diagnostic_16ap_b"; then
    printf 'Action 16ap-b diagnostic must not make a peer connection.\n' >&2
    exit 1
fi
grep -Fq -- '-u NODE_ROLE' "$caddy_validation_diagnostic_16ap_b"
grep -Fq "source \"\$environment_file\"" \
    "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'emit_validation bare' "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'emit_validation environment' \
    "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'EnvironmentFiles' "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'config_tree_sha256=' "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'filesystem_mutations=false' \
    "$caddy_validation_diagnostic_16ap_b"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' \
    "$caddy_validation_runner_16ap_b"
grep -Fq 'pi@10.1.0.53' "$caddy_validation_runner_16ap_b"
grep -Fq 'HostKeyAlias=pihole00.local.theama.co' \
    "$caddy_validation_runner_16ap_b"
grep -Fq 'pi@10.1.0.54' "$caddy_validation_runner_16ap_b"
grep -Fq 'action_16ap_b_contract_test_complete=true' \
    "$caddy_validation_runner_16ap_b"
grep -Fq -- '--shell /bin/sh' \
    "$caddy_root/scripts/install-caddy-ha.sh"
grep -Fq 'passwd --lock caddy-sync' \
    "$caddy_root/scripts/install-caddy-ha.sh"
grep -Fq 'scope: operator_workstation_only' \
    "$caddy_root/manifests/dependencies.yaml"
grep -Fq 'operator_workstation_required:' \
    "$caddy_root/manifests/dependencies.yaml"
[[ "$(grep -Ec '^[[:space:]]+- doppler$' \
    "$caddy_root/manifests/dependencies.yaml")" -eq 2 ]]
grep -Fq 'node-a)' "$caddy_root/scripts/create-node-rollback-backup.sh"
grep -Fq 'expected_hostname=j1-svpihole0' \
    "$caddy_root/scripts/create-node-rollback-backup.sh"
grep -Fq 'expected_ipv4=10.1.0.53' \
    "$caddy_root/scripts/create-node-rollback-backup.sh"
grep -Fq 'node-b)' "$caddy_root/scripts/create-node-rollback-backup.sh"
grep -Fq 'expected_hostname=j1-svpihole00' \
    "$caddy_root/scripts/create-node-rollback-backup.sh"
grep -Fq 'expected_ipv4=10.1.0.54' \
    "$caddy_root/scripts/create-node-rollback-backup.sh"
if "$caddy_root/scripts/create-node-rollback-backup.sh" \
    --node unknown >/dev/null 2>&1; then
    printf 'Rollback backup accepted an unknown node role.\n' >&2
    exit 1
fi

"$caddy_root/tests/action20e-focused-validation.sh"
"$caddy_root/tests/action20e-retry-focused-validation.sh"
"$caddy_root/tests/action20e-b-focused-validation.sh"
"$caddy_root/tests/action20e-retry2-focused-validation.sh"
"$caddy_root/tests/action20e-retry2-a-focused-validation.sh"

for plugin in caddy_health caddy_requests caddy_tls lsyncd_caddy; do
    "$monitoring_root/scripts/$plugin" config >/dev/null
    "$monitoring_root/scripts/$plugin" >/dev/null 2>&1
done

if [[ "$skip_container" == true ]]; then
    printf 'Host validation passed; Podman integration skipped.\n'
    exit 0
fi

podman build \
    --tag localhost/caddy-ha-validation:latest \
    --file "$script_dir/Containerfile" \
    "$script_dir"
podman run \
    --rm \
    --cap-add NET_ADMIN \
    --volume "$workspace:/workspace:ro" \
    localhost/caddy-ha-validation:latest \
    /workspace/homelab-server-configs/Caddy/tests/integration.sh

printf 'All Caddy HA repository validation passed.\n'
