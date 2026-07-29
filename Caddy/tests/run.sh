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
shfmt -d -i 4 -ci "${shell_files[@]}"
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
