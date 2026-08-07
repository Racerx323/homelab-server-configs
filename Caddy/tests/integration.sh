#!/usr/bin/env bash
set -euo pipefail

readonly workspace=/workspace
readonly caddy_root="$workspace/homelab-server-configs/Caddy"
readonly munin_root="$workspace/homelab-monitoring-observability/Munin"
readonly deployment_fixture="$caddy_root/tests/fixtures/deployment.yaml"
export CADDY_VALIDATION_CONTAINER=1

cd "$workspace/homelab-server-configs"

"$caddy_root/tests/executable-wrapper-policy-regression.sh" >/dev/null
"$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --self-test
"$caddy_root/tests/unbound-validation-runtime-regression.sh" \
    --production-test >/dev/null
"$caddy_root/tests/source-test-context-policy-regression.sh" \
    --production-test >/dev/null
"$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
"$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" >/dev/null
command -v git >/dev/null

work_dir=$(mktemp -d /tmp/caddy-integration.XXXXXX)
trap 'rm -rf -- "$work_dir"' EXIT

if ! ip link show eth0 >/dev/null 2>&1; then
    ip link add eth0 type dummy
fi
ip link set eth0 up
ip address replace 10.1.0.53/22 dev eth0
ip address replace 10.1.0.56/22 dev eth0
ip -6 address replace fd36:5aa8:6971:1::53/128 dev eth0
ip -6 address replace fd36:5aa8:6971:1::56/128 dev eth0

"$caddy_root/tests/generate-test-certificate.sh" "$work_dir/input"

export CADDY_TLS_CERT_PEM
export CADDY_TLS_CA_BUNDLE_PEM
export CADDY_TLS_PRIVATE_KEY_PEM
CADDY_TLS_CERT_PEM=$(<"$work_dir/input/input.cert")
CADDY_TLS_CA_BUNDLE_PEM=$(<"$work_dir/input/input.ca-bundle")
CADDY_TLS_PRIVATE_KEY_PEM=$(<"$work_dir/input/input.key")

prepare_output=$(
    "$caddy_root/scripts/prepare-certificate.sh" \
        --output "$work_dir/prepared"
)
if grep -Fq -- '-----BEGIN' <<<"$prepare_output"; then
    printf 'Certificate preparation leaked PEM material to standard output.\n' >&2
    exit 1
fi
[[ "$(awk '$0 == "-----BEGIN CERTIFICATE-----" { count++ }
    END { print count + 0 }' "$work_dir/prepared/intermediates.pem")" -eq 1 ]]
[[ "$(awk '$0 == "-----BEGIN CERTIFICATE-----" { count++ }
    END { print count + 0 }' "$work_dir/prepared/fullchain.pem")" -eq 2 ]]

incomplete_manifest="$work_dir/deployment-incomplete.yaml"
sed 's/^interface: eth0$/interface: pending_node_preflight/' \
    "$deployment_fixture" >"$incomplete_manifest"
grep -Fxq 'interface: pending_node_preflight' "$incomplete_manifest"
if "$caddy_root/scripts/render-node-config.sh" \
    --node node-a \
    --manifest "$incomplete_manifest" \
    --output "$work_dir/incomplete-render" >/dev/null 2>&1; then
    printf 'Renderer accepted an unresolved deployment manifest.\n' >&2
    exit 1
fi
if "$caddy_root/scripts/render-node-config.sh" \
    --node unknown \
    --manifest "$deployment_fixture" \
    --output "$work_dir/unknown-render" >/dev/null 2>&1; then
    printf 'Renderer accepted an unknown node role.\n' >&2
    exit 1
fi

for node_role in node-a node-b; do
    render_dir="$work_dir/render-$node_role"
    "$caddy_root/scripts/render-node-config.sh" \
        --node "$node_role" \
        --manifest "$deployment_fixture" \
        --output "$render_dir"
    grep -Fxq "NODE_ROLE=$node_role" "$render_dir/caddy-ha.env"
    "$caddy_root/scripts/render-source-bound-sync-config-action17c-c.sh" \
        --node "$node_role" \
        --manifest "$deployment_fixture" \
        --output "$work_dir/source-bound-$node_role" >/dev/null
done
source_bound_test_source="$work_dir/source-bound-empty"
install -d -m 0750 "$source_bound_test_source"
sed -i \
    "s|/var/lib/caddy-sync/outbound/|$source_bound_test_source/|" \
    "$work_dir/source-bound-node-a/caddy.lua"
sed -i \
    -e '/^    rsync = {$/a\        binary = "/bin/true",' \
    -e '/^    ssh = {$/a\        binary = "/bin/true",' \
    "$work_dir/source-bound-node-a/caddy.lua"
grep -Fxq '            BindAddress = "fd36:5aa8:6971:1::53",' \
    "$work_dir/source-bound-node-a/caddy.lua"
grep -Fxq '            HostKeyAlias = "pihole00.local.theama.co",' \
    "$work_dir/source-bound-node-a/caddy.lua"
grep -Fxq '            BindAddress = "fd36:5aa8:6971:1::54",' \
    "$work_dir/source-bound-node-b/caddy.lua"
grep -Fxq '            HostKeyAlias = "pihole0.local.theama.co",' \
    "$work_dir/source-bound-node-b/caddy.lua"

"$caddy_root/scripts/install-caddy-ha.sh" \
    --node node-a \
    --manifest "$deployment_fixture" \
    --certificate-dir "$work_dir/prepared" \
    --component all >/tmp/install-first.json

[[ "$(getent passwd caddy-sync | cut -d: -f7)" == /bin/sh ]]
[[ "$(passwd --status caddy-sync | awk '{print $2}')" == L ]]
"$caddy_root/tests/action17c-c-working-directory-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-source-bound-transport-action17c-c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-source-bound-transport-diagnostic-action17c-c-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-c-a-source-bound-diagnostic-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-peer-resolution-contexts-action17c-c-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-c-b-peer-resolution-context-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/correct-peer-resolution-readonly-shadow-action17c-c-b-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-peer-resolution-context-diagnostic-action17c-c-b-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-c-b-second-resolver-snapshot-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/diagnose-dns-path-authority-action17c-c-c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c.sh" \
    --contract-test >/dev/null
[[ -f "$caddy_root/tests/action17c-c-c-dns-path-authority-regression.sh" ]]
"$caddy_root/scripts/inspect-dns-continuity-action17c-c-c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-continuity-action17c-c-c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-continuity-action17c-c-c-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-c-c-a-dns-continuity-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/correct-dns-path-work-dir-action17c-c-c-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17c-c-c-first-query-production-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-path-authority-diagnostic-action17c-c-c-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-b-two-file-unbound-preflight-action17d.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17d-node-b-two-file-unbound-preflight-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-two-file-unbound-preflight-action17d.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-two-file-unbound-preflight-action17d.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/stage-node-b-unbound-primary-action17e.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17e-node-b-unbound-primary-stage-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/diagnose-node-b-unbound-primary-prewrite-action17e-a.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17e-a-node-b-unbound-prewrite-diagnostic-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-prewrite-diagnostic-action17e-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-prewrite-diagnostic-action17e-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/correct-node-b-unbound-primary-working-directory-action17e-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17e-working-directory-production-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-primary-stage-action17e-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh" \
    --self-test >/dev/null
[[ -f "$caddy_root/tests/action17f-node-b-unbound-local-zone-stage-regression.sh" ]]
"$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/diagnose-node-b-unbound-local-zone-prewrite-action17f-a.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-a-node-b-unbound-prewrite-diagnostic-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-local-zone-prewrite-diagnostic-action17f-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-local-zone-prewrite-diagnostic-action17f-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/instrument-node-b-unbound-local-zone-action17f-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-instrumented-retry-regression.sh" \
    --production-test >/dev/null
[[ -f "$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-retry.sh" ]]
"$caddy_root/scripts/diagnose-node-b-unbound-action17f-transition.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-b-transition-diagnostic-regression.sh" \
    >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-transition-diagnostic.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-transition-diagnostic.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/check-shell-readonly-local-collisions.sh" >/dev/null
"$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-b-labeled-baseline-retry-regression.sh" \
    >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-labeled-baseline-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-labeled-baseline-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-second-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-b-second-retry-production-failure-regression.sh" \
    >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-baseline-second-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-action17f-baseline-second-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-normalized-live-state-boundary-regression.sh" \
    --production-test >/dev/null
[[ -f "$caddy_root/scripts/run-node-b-unbound-local-zone-stage-action17f-normalized-retry.sh" ]]
"$caddy_root/scripts/inspect-node-b-unbound-local-zone-stage-action17f-c.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17f-c-retained-stage-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-local-zone-stage-verification-action17f-c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-local-zone-stage-verification-action17f-c.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/activate-node-b-unbound-two-file-action17g.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17g-node-b-unbound-two-file-activation-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-two-file-activation-action17g.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-two-file-activation-action17g.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-b-unbound-post-activation-action17g-a.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17g-a-node-b-unbound-post-activation-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-post-activation-action17g-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-unbound-post-activation-action17g-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-a-two-file-unbound-preflight-action17h.sh" \
    --self-test >/dev/null
[[ -f "$caddy_root/tests/action17h-node-a-two-file-unbound-preflight-regression.sh" ]]
"$caddy_root/scripts/run-node-a-two-file-unbound-preflight-action17h.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-a-unbound-semantic-diff-action17h-a.sh" \
    --self-test >/dev/null
[[ -f "$caddy_root/tests/action17h-a-node-a-semantic-diff-regression.sh" ]]
"$caddy_root/scripts/run-node-a-unbound-semantic-diff-action17h-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/stage-node-a-unbound-primary-action17i.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17i-node-a-unbound-primary-stage-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-primary-stage-action17i.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-primary-stage-action17i.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/stage-node-a-unbound-local-zone-action17j.sh" \
    --self-test >/dev/null
[[ -f "$caddy_root/tests/action17j-node-a-unbound-local-zone-stage-regression.sh" ]]
"$caddy_root/scripts/run-node-a-unbound-local-zone-stage-action17j.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-a-unbound-dual-stage-action17j-a.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17j-a-node-a-dual-stage-acceptance-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-dual-stage-acceptance-action17j-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-dual-stage-acceptance-action17j-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/activate-node-a-unbound-two-file-action17k.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17k-node-a-unbound-two-file-activation-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-two-file-activation-action17k.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-two-file-activation-action17k.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-a-unbound-post-activation-action17k-a.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17k-a-node-a-unbound-post-activation-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-post-activation-action17k-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-unbound-post-activation-action17k-a.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-dual-node-dns-sync-readiness-action17l.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17l-dual-node-dns-sync-readiness-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-dual-node-dns-sync-readiness-action17l.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/apply-node-b-dns-nss-correction-action17m.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-dns-nss-correction-action17m.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-dns-nss-correction-action17m.sh" \
    --source-test >/dev/null
"$caddy_root/scripts/run-node-b-dns-nss-correction-action17m.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17m-node-b-dns-nss-correction-regression.sh" \
    --production-test >/dev/null
"$caddy_root/tests/action17m-unbound-source-advance-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-node-b-dns-nss-post-correction-action17m-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-dns-nss-post-correction-action17m-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-dns-nss-post-correction-action17m-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17m-a-node-b-dns-nss-post-correction-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-dns-vip-response-path-action17m-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-vip-response-path-diagnostic-action17m-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-dns-vip-response-path-diagnostic-action17m-b.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17m-b-dns-vip-response-path-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n.sh" \
    --source-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17n-node-a-dns-nss-correction-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-node-a-dns-nss-post-rollback-action17n-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-post-rollback-action17n-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-post-rollback-action17n-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17n-a-node-a-post-rollback-readiness-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh" \
    --source-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17n-retry-node-a-dns-nss-correction-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17n-b-node-a-pihole-response-path-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-node-a-pihole-response-path-action17n-b-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-pihole-response-path-action17n-b-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17n-b-retry-absolute-pihole-path-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/apply-node-a-dns-nss-correction-action17n-reset-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-reset-retry.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-dns-nss-correction-action17n-reset-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17n-reset-retry-node-a-dns-nss-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/inspect-node-a-source-bound-restricted-transport-action17o.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-b-source-bound-restricted-transport-action17o.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-to-node-b-source-bound-restricted-transport-action17o.sh" \
    >/dev/null
"$caddy_root/tests/action17o-source-bound-restricted-transport-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-rsync-dry-run-output-action17o-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-rsync-dry-run-output-action17o-a.sh" \
    --classifier-test >/dev/null
"$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-rsync-dry-run-output-diagnostic-action17o-a.sh" \
    >/dev/null
"$caddy_root/tests/action17o-a-rsync-output-classification-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/refine-node-a-rsync-output-classification-action17o-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/refine-node-a-rsync-output-classification-action17o-b.sh" \
    --classifier-test >/dev/null
"$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-rsync-classification-refinement-action17o-b.sh" \
    >/dev/null
"$caddy_root/tests/action17o-b-classification-refinement-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-source-bound-transport-acceptance-action17o-c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-source-bound-transport-acceptance-action17o-c.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-node-a-to-node-b-source-bound-transport-acceptance-action17o-c.sh" \
    >/dev/null
"$caddy_root/tests/action17o-c-source-bound-transport-acceptance-regression.sh" \
    --production-test >/dev/null
"$caddy_root/scripts/inspect-release-transfer-failure-action17p-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh" \
    >/dev/null
"$caddy_root/tests/action17p-a-release-transfer-failure-regression.sh" \
    --production-test >/dev/null
"$caddy_root/tests/labeled-dns-readiness-policy-regression.sh" \
    --production-test >/dev/null
[[ "$(stat -c '%U:%G:%a' /var/log/unbound)" == unbound:unbound:750 ]]
printf 'include-toplevel: "%s"\ninclude-toplevel: "%s"\n' \
    "$workspace/homelab-dns/Unbound/configs/pihole0.conf" \
    "$workspace/homelab-dns/Unbound/configs/pihole0-local-zone.conf" |
    unbound-checkconf /dev/stdin >/dev/null
grep -Fq 'targetdir = "/node-a/"' /etc/lsyncd/caddy.lua
grep -Fq \
    'exec /usr/bin/rrsync -wo -no-del /var/lib/caddy-sync/incoming' \
    /usr/local/libexec/caddy-sync-rsync-receiver
/usr/local/libexec/setup-sync-ssh.sh >/dev/null
derived_sync_public=$(
    runuser -u caddy-sync -- \
        ssh-keygen -y -f /var/lib/caddy-sync/.ssh/id_ed25519 |
        awk '{print $1, $2}'
)
recorded_sync_public=$(
    awk '{print $1, $2}' /var/lib/caddy-sync/.ssh/id_ed25519.pub
)
[[ "$derived_sync_public" == "$recorded_sync_public" ]]

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

caddy fmt /etc/caddy/current/Caddyfile >"$work_dir/Caddyfile.formatted"
if ! cmp --silent \
    /etc/caddy/current/Caddyfile "$work_dir/Caddyfile.formatted"; then
    diff -u /etc/caddy/current/Caddyfile "$work_dir/Caddyfile.formatted" >&2
    printf 'Caddyfile is not canonically formatted.\n' >&2
    exit 1
fi
adapted_caddy_json=$(
    caddy adapt \
        --config /etc/caddy/current/Caddyfile \
        --adapter caddyfile
)
jq -e '.apps.http.servers | type == "object"' \
    <<<"$adapted_caddy_json" >/dev/null
static_response_summary=$(
    jq -c '.apps.http.servers' <<<"$adapted_caddy_json" |
        "$caddy_root/scripts/extend-node-a-lighttpd-routing-action16aq-a-retry.sh" \
            --summarize-servers
)
jq -e -s '
    length >= 2
    and any(.[];
        (.listen | index(":443")) != null
        and (.hosts | length) == 0
        and (.status_code_present | type == "boolean")
        and (.effective_status_code | type == "number")
        and (.body_length | type == "number")
        and (.body_is_421 | type == "boolean")
    )
' <<<"$static_response_summary" >/dev/null
server_selection_summary=$(
    jq -c '.apps.http.servers' <<<"$adapted_caddy_json" |
        "$caddy_root/scripts/diagnose-node-a-caddy-server-selection-action16aq-b.sh" \
            --summarize-servers
)
jq -e -s '
    any(.[];
        .exact_target == true
        and (.hosts | index("pihole0.local.theama.co")) != null
    )
    and any(.[];
        .wildcard_target == true
        and .hostless_static_421 == true
    )
' <<<"$server_selection_summary" >/dev/null
jq -e '
    def hostless_421:
        any(
            .routes[]?;
            ([.match[]?.host[]?] | length) == 0
            and any(
                .handle[]? | .. | objects;
                .handler? == "static_response"
                and (.status_code // 200) == 421
            )
        );
    def has_hosts($wanted):
        ([.routes[]?.match[]?.host[]?] | unique | sort) as $actual
        | all($wanted[]; $actual | index(.) != null);
    def server($first; $second):
        [
            .[]
            | select(
                ((.listen // []) | sort)
                == ([$first, $second] | sort)
            )
        ];

    .apps.http.servers as $servers
    | ($servers | server(
        "10.1.0.53:443";
        "[fd36:5aa8:6971:1::53]:443"
    )) as $physical
    | ($servers | server(
        "10.1.0.56:443";
        "[fd36:5aa8:6971:1::56]:443"
    )) as $vip
    | ($servers | server("127.0.0.1:443"; "[::1]:443")) as $loopback
    | ([
        $servers[]
        | select((.listen // []) == [":443"])
    ]) as $wildcard_https
    | ([
        $servers[]
        | select((.listen // []) == [":80"])
    ]) as $wildcard_http
    | ($servers | length) == 5
    and ($physical | length) == 1
    and ($vip | length) == 1
    and ($loopback | length) == 1
    and ($wildcard_https | length) == 1
    and ($wildcard_http | length) == 1
    and ($physical[0] | has_hosts(["pihole0.local.theama.co"]))
    and ($vip[0] | has_hosts([
        "pihole-admin.local.theama.co",
        "proxy.local.theama.co"
    ]))
    and ($loopback[0] | has_hosts(["localhost"]))
    and ($physical[0] | hostless_421)
    and ($vip[0] | hostless_421)
    and ($loopback[0] | hostless_421)
    and ($wildcard_https[0] | hostless_421)
    and ($wildcard_http[0] | hostless_421)
' <<<"$adapted_caddy_json" >/dev/null
[[ "$(
    printf '%s' '200%7C10.1.0.53%7C2%7C0%7C0' |
        "$caddy_root/scripts/correct-node-a-caddy-server-selection-action16aq-b-retry.sh" \
            --decode-probe-code
)" == 200 ]]
caddy adapt \
    --config /etc/caddy/current/Caddyfile \
    --adapter caddyfile >/dev/null
caddy validate \
    --config /etc/caddy/current/Caddyfile \
    --adapter caddyfile >/dev/null

"$caddy_root/tests/action16ar-reload-regression.sh"

action16ar_b_dir="$work_dir/action16ar-b"
install -d "$action16ar_b_dir"
"$caddy_root/scripts/derive-node-a-post-correction-acceptance-action16ar-b.sh" \
    --render-inspector \
    "$caddy_root/scripts/diagnose-node-a-action16ar-recovery-action16ar-a.sh" \
    >"$action16ar_b_dir/diagnose-node-a-post-correction-acceptance-action16ar-b.sh"
action16ar_b_inspector_hash=$(
    sha256sum \
        "$action16ar_b_dir/diagnose-node-a-post-correction-acceptance-action16ar-b.sh" |
        awk '{ print $1 }'
)
[[ "$action16ar_b_inspector_hash" == 71c31f7e04beed53edc58bda0ac72b5079c15231f29639548aab9971710aed0f ]]
"$caddy_root/scripts/derive-node-a-post-correction-acceptance-action16ar-b.sh" \
    --render-runner \
    "$caddy_root/scripts/run-node-a-action16ar-recovery-diagnostic-action16ar-a.sh" \
    "$action16ar_b_inspector_hash" \
    >"$action16ar_b_dir/run-node-a-post-correction-inner-action16ar-b.sh"
[[ "$(sha256sum \
    "$action16ar_b_dir/run-node-a-post-correction-inner-action16ar-b.sh" |
    awk '{ print $1 }')" == 8af27b5c54eda5a6a9f47692ea0072eda9312016e5a5545d3ac521d7d13fcf5d ]]
bash -n \
    "$action16ar_b_dir/diagnose-node-a-post-correction-acceptance-action16ar-b.sh" \
    "$action16ar_b_dir/run-node-a-post-correction-inner-action16ar-b.sh"
bash \
    "$action16ar_b_dir/diagnose-node-a-post-correction-acceptance-action16ar-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/correct-node-a-post-correction-acceptance-action16ar-b-retry.sh" \
    --render \
    "$caddy_root/scripts/run-node-a-post-correction-acceptance-action16ar-b.sh" \
    >"$action16ar_b_dir/run-node-a-post-correction-acceptance-action16ar-b-retry.sh"
[[ "$(sha256sum \
    "$action16ar_b_dir/run-node-a-post-correction-acceptance-action16ar-b-retry.sh" |
    awk '{ print $1 }')" == 00ab68767fef384ff0dca13c67d0c0970755d9e8c81861cc5d1c1f57fe49d25e ]]
bash -n \
    "$action16ar_b_dir/run-node-a-post-correction-acceptance-action16ar-b-retry.sh"
bash \
    "$action16ar_b_dir/run-node-a-post-correction-acceptance-action16ar-b-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action16ar-b-production-transcript-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/inspect-sync-readiness-before-action17.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-sync-readiness-before-action17.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/correct-sync-readiness-before-action17-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17a-node-b-release-regression.sh" \
    --self-test >/dev/null
bash -n "$caddy_root/scripts/run-sync-readiness-before-action17-retry.sh"
"$caddy_root/scripts/authorize-node-a-sync-key-on-node-b-action17b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-b-authorize-node-a-sync-key-action17b.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17b-node-b-authorization-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/inspect-node-b-restricted-transport-state-action17c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/validate-node-a-to-node-b-restricted-transport-action17c.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-restricted-transport-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/correct-restricted-transport-action17c-retry.sh" \
    --self-test >/dev/null
"$caddy_root/tests/action17c-streamed-stdin-continuity-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-restricted-transport-action17c-retry.sh" \
    --contract-test >/dev/null
"$caddy_root/scripts/inspect-node-b-ipv6-restricted-transport-action17c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-to-node-b-ipv6-restricted-transport-action17c-a.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-to-node-b-ipv6-restricted-transport-diagnostic-action17c-a.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-a-ipv6-diagnostic-regression.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/diagnose-node-a-ipv6-source-selection-action17c-b.sh" \
    --self-test >/dev/null
"$caddy_root/scripts/run-node-a-ipv6-source-selection-diagnostic-action17c-b.sh" \
    --contract-test >/dev/null
"$caddy_root/tests/action17c-b-ipv6-source-selection-regression.sh" \
    --self-test >/dev/null

(
    caddy_pid=
    # Invoked indirectly by the EXIT trap.
    # shellcheck disable=SC2317
    cleanup_caddy_runtime_test() {
        if [[ -n "$caddy_pid" ]] &&
            kill -0 "$caddy_pid" >/dev/null 2>&1; then
            kill -TERM "$caddy_pid"
            wait "$caddy_pid" || true
        fi
    }
    trap cleanup_caddy_runtime_test EXIT

    caddy run \
        --config /etc/caddy/current/Caddyfile \
        --adapter caddyfile \
        >"$work_dir/caddy-runtime.log" 2>&1 &
    caddy_pid=$!
    caddy_ready=false
    for ((attempt = 0; attempt < 80; attempt++)); do
        if ! kill -0 "$caddy_pid" >/dev/null 2>&1; then
            wait "$caddy_pid" || true
            caddy_pid=
            cat "$work_dir/caddy-runtime.log" >&2
            printf 'Corrected Caddy exited before becoming ready.\n' >&2
            exit 1
        fi
        if [[ "$(
            curl --noproxy '*' --insecure --silent --show-error \
                --connect-timeout 1 --max-time 2 \
                --output /dev/null --write-out '%{http_code}' \
                https://localhost/ 2>/dev/null || true
        )" == 204 ]]; then
            caddy_ready=true
            break
        fi
        sleep 0.1
    done
    if [[ "$caddy_ready" != true ]]; then
        cat "$work_dir/caddy-runtime.log" >&2
        printf 'Corrected Caddy did not become ready.\n' >&2
        exit 1
    fi

    for address in \
        10.1.0.53 '[fd36:5aa8:6971:1::53]' \
        10.1.0.56 '[fd36:5aa8:6971:1::56]' \
        127.0.0.1 '[::1]'; do
        [[ "$(
            curl --noproxy '*' --insecure --silent --show-error \
                --connect-timeout 1 --max-time 2 \
                --resolve "unexpected.local.theama.co:443:$address" \
                --output /dev/null --write-out '%{http_code}' \
                https://unexpected.local.theama.co/ 2>/dev/null
        )" == 421 ]]
    done
    [[ "$(
        curl --noproxy '*' --insecure --silent --show-error \
            --connect-timeout 1 --max-time 2 \
            --resolve proxy.local.theama.co:443:10.1.0.56 \
            --output /dev/null --write-out '%{http_code}' \
            https://proxy.local.theama.co/ 2>/dev/null
    )" == 204 ]]
)

set -a
# shellcheck disable=SC1091
source "$work_dir/render-node-b/caddy-ha.env"
set +a
caddy validate \
    --config /etc/caddy/current/Caddyfile \
    --adapter caddyfile >/dev/null

validate_keepalived() {
    local source_config=$1
    local label=$2
    local validation_config="$work_dir/keepalived-$label.conf"
    local wrapper_config="$work_dir/keepalived-wrapper-$label.conf"

    # Keepalived 2.2.7's config-test mode executes notification and non-root
    # vrrp_script setup, then exits via SIGTERM in a container without an init
    # system. Use inert commands for parsing and assert production directives.
    sed \
        -e '/^[[:space:]]*notify "/d' \
        -e 's/user keepalived_script/user root/' \
        -e 's#script "/usr/local/libexec/check-caddy.sh"#script "/bin/true"#' \
        "$source_config" >"$validation_config"
    sed \
        "s#/etc/keepalived/conf.d/caddy-ha.conf#$validation_config#" \
        "$caddy_root/tests/fixtures/keepalived-wrapper.conf" \
        >"$wrapper_config"
    keepalived \
        --dont-fork \
        --config-test="$work_dir/keepalived-$label.log" \
        -f "$wrapper_config" >/dev/null
    grep -Fq 'user keepalived_script' "$source_config"
    grep -Fq \
        'notify "/usr/local/libexec/lsyncd-ha-failover-notify.sh"' \
        "$source_config"
}

validate_keepalived /etc/keepalived/conf.d/caddy-ha.conf node-a
validate_keepalived \
    "$work_dir/render-node-b/keepalived-caddy-ha.conf" node-b

# shellcheck disable=SC2016
printf '%s\n' \
    'server.modules += ( "mod_openssl" )' \
    '$SERVER["socket"] == ":443" {' \
    '    ssl.engine = "enable"' \
    '}' >/etc/lighttpd/conf-enabled/external.conf
printf '%s\n' \
    'server.modules += ( "mod_accesslog" )' \
    'accesslog.filename = "/var/log/lighttpd/access.log"' \
    >/etc/lighttpd/conf-enabled/accesslog.conf
# shellcheck disable=SC2016
printf '%s\n' \
    '$HTTP["url"] =~ "^/admin/" {' \
    '    accesslog.filename = "/var/log/lighttpd/access-admin.log"' \
    '}' >/etc/lighttpd/conf-enabled/accesslog-admin.conf
"$caddy_root/scripts/prepare-lighttpd-config.sh" \
    --source-root /etc/lighttpd \
    --output "$work_dir/lighttpd-staged" >/dev/null
[[ "$(stat -c '%a' "$work_dir/lighttpd-staged")" == 750 ]]
grep -Eq '^[[:space:]]*server\.bind[[:space:]]*=[[:space:]]*"127\.0\.0\.1"' \
    "$work_dir/lighttpd-staged/lighttpd.conf"
grep -Eq '^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*8080' \
    "$work_dir/lighttpd-staged/lighttpd.conf"
grep -Eq \
    '^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*=[[:space:]]*"enable"' \
    "$work_dir/lighttpd-staged/lighttpd.conf"
accesslog_syslog_count=$(
    grep -R -Eh \
        '^[[:space:]]*accesslog\.use-syslog[[:space:]]*=[[:space:]]*"enable"' \
        "$work_dir/lighttpd-staged/lighttpd.conf" \
        "$work_dir/lighttpd-staged/conf-enabled" |
        wc -l
)
[[ "$accesslog_syslog_count" -eq 2 ]]
if grep -R -qE \
    '^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=' \
    "$work_dir/lighttpd-staged/lighttpd.conf" \
    "$work_dir/lighttpd-staged/conf-enabled"; then
    printf 'Staged lighttpd retained a file-backed access-log target.\n' >&2
    exit 1
fi
grep -R -Eq '"mod_accesslog"' \
    "$work_dir/lighttpd-staged/lighttpd.conf" \
    "$work_dir/lighttpd-staged/conf-enabled"
if grep -R -qE '/dev/(stderr|stdout)' \
    "$work_dir/lighttpd-staged/lighttpd.conf" \
    "$work_dir/lighttpd-staged/conf-enabled"; then
    printf 'Staged lighttpd configuration retained a device-backed log target.\n' >&2
    exit 1
fi
[[ -f "$work_dir/lighttpd-staged/conf-disabled-by-caddy-ha/external.conf" ]]
[[ ! -e "$work_dir/lighttpd-staged/conf-enabled/external.conf" ]]

(
    lighttpd_pid=
    # Invoked indirectly by the EXIT trap.
    # shellcheck disable=SC2317
    cleanup_lighttpd_runtime_test() {
        if [[ -n "$lighttpd_pid" ]] &&
            kill -0 "$lighttpd_pid" >/dev/null 2>&1; then
            kill -TERM "$lighttpd_pid"
            wait "$lighttpd_pid" || true
        fi
    }
    trap cleanup_lighttpd_runtime_test EXIT

    lighttpd -D -f "$work_dir/lighttpd-staged/lighttpd.conf" \
        >"$work_dir/lighttpd-runtime.log" 2>&1 &
    lighttpd_pid=$!
    lighttpd_ready=false
    for ((attempt = 0; attempt < 50; attempt++)); do
        if ! kill -0 "$lighttpd_pid" >/dev/null 2>&1; then
            wait "$lighttpd_pid" || true
            lighttpd_pid=
            cat "$work_dir/lighttpd-runtime.log" >&2
            printf 'Staged lighttpd exited before becoming ready.\n' >&2
            exit 1
        fi
        if ss -H -lnt 'sport = :8080' |
            grep -Fq '127.0.0.1:8080'; then
            lighttpd_ready=true
            break
        fi
        sleep 0.1
    done
    if [[ "$lighttpd_ready" != true ]]; then
        cat "$work_dir/lighttpd-runtime.log" >&2
        printf 'Staged lighttpd did not bind 127.0.0.1:8080 in time.\n' >&2
        exit 1
    fi
    if grep -Fq 'unknown config-key' "$work_dir/lighttpd-runtime.log"; then
        cat "$work_dir/lighttpd-runtime.log" >&2
        printf 'Staged lighttpd ignored an unknown configuration key.\n' >&2
        exit 1
    fi
)

install -d -m 0750 /run/caddy-lsyncd
set +e
timeout 3s lsyncd -nodaemon -log scarce /etc/lsyncd/caddy.lua \
    >"$work_dir/lsyncd.log" 2>&1
set -e
if grep -Eq 'Error:|syntax error|Bad configuration option' \
    "$work_dir/lsyncd.log"; then
    cat "$work_dir/lsyncd.log" >&2
    exit 1
fi

source_bound_lsyncd_status=0
timeout 3s lsyncd -nodaemon -log scarce \
    "$work_dir/source-bound-node-a/caddy.lua" \
    >"$work_dir/source-bound-lsyncd.log" 2>&1 ||
    source_bound_lsyncd_status=$?
[[ "$source_bound_lsyncd_status" -eq 0 ||
    "$source_bound_lsyncd_status" -eq 124 ]]
if grep -Eqi 'error|unknown|invalid|syntax' \
    "$work_dir/source-bound-lsyncd.log"; then
    cat "$work_dir/source-bound-lsyncd.log" >&2
    exit 1
fi

sed \
    -e 's/@NODE_ROLE@/node-a/g' \
    -e 's/@NODE_IPV6@/fd36:5aa8:6971:1::53/g' \
    -e 's/@PEER_FQDN@/pihole00.local.theama.co/g' \
    -e "s|/var/lib/caddy-sync/outbound/|$source_bound_test_source/|" \
    "$caddy_root/templates/lsyncd-caddy-receiver-finalized-v2.lua.in" \
    >"$work_dir/receiver-finalized-v2.lua"
sed -i \
    -e '/^    rsync = {$/a\        binary = "/bin/true",' \
    -e '/^    ssh = {$/a\        binary = "/bin/true",' \
    "$work_dir/receiver-finalized-v2.lua"
receiver_finalized_lsyncd_status=0
timeout 3s lsyncd -nodaemon -log scarce \
    "$work_dir/receiver-finalized-v2.lua" \
    >"$work_dir/receiver-finalized-lsyncd.log" 2>&1 ||
    receiver_finalized_lsyncd_status=$?
[[ "$receiver_finalized_lsyncd_status" -eq 0 ||
    "$receiver_finalized_lsyncd_status" -eq 124 ]]
if grep -Eqi 'error|unknown|invalid|syntax' \
    "$work_dir/receiver-finalized-lsyncd.log"; then
    cat "$work_dir/receiver-finalized-lsyncd.log" >&2
    exit 1
fi

systemd-analyze verify \
    "$caddy_root"/systemd/*.service \
    "$caddy_root"/systemd/*.path \
    "$caddy_root"/systemd/*.timer

for plugin in caddy_health caddy_requests caddy_tls lsyncd_caddy; do
    "$munin_root/scripts/$plugin" config >/dev/null
    "$munin_root/scripts/$plugin" >/dev/null 2>&1
done

"$caddy_root/scripts/install-caddy-ha.sh" \
    --node node-a \
    --manifest "$deployment_fixture" \
    --certificate-dir "$work_dir/prepared" \
    --component all >"$work_dir/install-second.json"

if [[ "$(jq -r '.changes' "$work_dir/install-second.json")" != 0 ]]; then
    printf 'Expected no changes on second install.\n' >&2
    cat "$work_dir/install-second.json" >&2
    exit 1
fi

active_before=$(readlink /etc/caddy/current)
install -d /var/lib/caddy-sync/incoming/node-a/zz-incomplete
"$caddy_root/scripts/reconcile-release.sh"
[[ "$(readlink /etc/caddy/current)" == "$active_before" ]]
rm -rf /var/lib/caddy-sync/incoming/node-a/zz-incomplete

install -m 0755 \
    "$caddy_root/scripts/finalize-incoming-release-v2.sh" \
    /usr/local/libexec/finalize-incoming-release-v2.sh

publisher_output=$(
    "$caddy_root/scripts/publish-release-v2.sh" \
        --source /etc/caddy/releases/bootstrap \
        --node-role node-a
)
published_revision=${publisher_output#Published protocol-v2 release }
published_revision=${published_revision% for receiver validation.}
[[ "$published_revision" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f-]{36}$ ]]
published_path="/var/lib/caddy-sync/outbound/$published_revision"
[[ -d "$published_path" && ! -L "$published_path" ]]
[[ -f "$published_path/.finalize-request" ]]
[[ ! -s "$published_path/.finalize-request" ]]
[[ ! -e "$published_path/.complete" ]]
[[ ! -e "$published_path/.complete.pending" ]]
[[ -z "$(find "$published_path" -type d ! -perm 0550 -print -quit)" ]]
[[ -z "$(find "$published_path" -type f ! -perm 0440 -print -quit)" ]]
(
    cd "$published_path"
    sha256sum --strict --check manifest.sha256 >/dev/null
)
rm -rf -- "$published_path"

create_v2_receiver_fixture() {
    local fixture_revision=$1
    local fixture_path="/var/lib/caddy-sync/incoming/node-a/$fixture_revision"

    install -d -o caddy-sync -g caddy-sync -m 0750 "$fixture_path"
    cp -a /etc/caddy/current/. "$fixture_path/"
    rm -f -- \
        "$fixture_path/.complete" \
        "$fixture_path/.complete.pending" \
        "$fixture_path/.finalize-request" \
        "$fixture_path/manifest.sha256"
    jq -n \
        --arg revision "$fixture_revision" \
        --arg parent_revision bootstrap \
        --arg source_node node-a \
        --arg created_at 2026-07-30T00:00:00Z \
        '{
            revision: $revision,
            parent_revision: $parent_revision,
            source_node: $source_node,
            created_at: $created_at
        }' >"$fixture_path/release-manifest.json"
    (
        cd "$fixture_path"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print0 |
            LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$fixture_path/manifest.sha256"
    : >"$fixture_path/.finalize-request"
    chown -R caddy-sync:caddy-sync "$fixture_path"
    find "$fixture_path" -type d -exec chmod 0700 {} +
    find "$fixture_path" -type f -exec chmod 0600 {} +
}

create_v2_receiver_fixture aa-v2-valid
runuser -u caddy-sync -- \
    /usr/local/libexec/finalize-incoming-release-v2.sh \
    --source-role node-a
[[ -f /var/lib/caddy-sync/incoming/node-a/aa-v2-valid/.complete ]]
[[ ! -s /var/lib/caddy-sync/incoming/node-a/aa-v2-valid/.complete ]]
[[ ! -e /var/lib/caddy-sync/incoming/node-a/aa-v2-valid/.complete.pending ]]
[[ -z "$(find /var/lib/caddy-sync/incoming/node-a/aa-v2-valid \
    -type d ! -perm 0550 -print -quit)" ]]
[[ -z "$(find /var/lib/caddy-sync/incoming/node-a/aa-v2-valid \
    -type f ! -perm 0440 -print -quit)" ]]
runuser -u caddy-sync -- \
    /usr/local/libexec/finalize-incoming-release-v2.sh \
    --source-role node-a

create_v2_receiver_fixture ab-v2-extra
printf 'unmanifested\n' \
    >/var/lib/caddy-sync/incoming/node-a/ab-v2-extra/unmanifested.txt
chown caddy-sync:caddy-sync \
    /var/lib/caddy-sync/incoming/node-a/ab-v2-extra/unmanifested.txt
chmod 0600 \
    /var/lib/caddy-sync/incoming/node-a/ab-v2-extra/unmanifested.txt
if runuser -u caddy-sync -- \
    /usr/local/libexec/finalize-incoming-release-v2.sh \
    --source-role node-a >/dev/null 2>&1; then
    printf 'Receiver finalizer accepted unmanifested payload.\n' >&2
    exit 1
fi
[[ ! -e /var/lib/caddy-sync/incoming/node-a/ab-v2-extra/.complete ]]

rm -rf -- \
    /var/lib/caddy-sync/incoming/node-a/aa-v2-valid \
    /var/lib/caddy-sync/incoming/node-a/ab-v2-extra

jq -n \
    --arg revision active-test \
    '{revision: $revision, parent_revision: ""}' \
    >/etc/caddy/current/release-manifest.json

create_candidate_release() {
    local revision=$1
    local parent_revision=$2
    local candidate="/var/lib/caddy-sync/incoming/node-a/$revision"

    install -d "$candidate"
    cp -a /etc/caddy/current/. "$candidate/"
    rm -f "$candidate/manifest.sha256" "$candidate/.complete"
    jq -n \
        --arg revision "$revision" \
        --arg parent_revision "$parent_revision" \
        --arg source_node node-a \
        '{
            revision: $revision,
            parent_revision: $parent_revision,
            source_node: $source_node
        }' >"$candidate/release-manifest.json"
    (
        cd "$candidate"
        find . -type f \
            ! -name manifest.sha256 \
            ! -name .complete \
            -print0 |
            sort -z |
            xargs -0 sha256sum
    ) >"$candidate/manifest.sha256"
    touch "$candidate/.complete"
}

install -d "$work_dir/bin"
printf '#!/bin/sh\nexit 0\n' >"$work_dir/bin/systemctl"
chmod 0755 "$work_dir/bin/systemctl"

create_candidate_release valid-next active-test
PATH="$work_dir/bin:$PATH" "$caddy_root/scripts/reconcile-release.sh"
[[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/valid-next ]]

create_candidate_release zz-conflict wrong-parent
if PATH="$work_dir/bin:$PATH" \
    "$caddy_root/scripts/reconcile-release.sh" >/dev/null 2>&1; then
    printf 'Divergent release was not rejected.\n' >&2
    exit 1
fi
[[ -d /var/lib/caddy-sync/quarantine/zz-conflict ]]
[[ ! -e /var/lib/caddy-sync/incoming/node-a/zz-conflict ]]

test_root="$work_dir/root"
install -d "$test_root/etc/default"
printf 'preexisting-caddy-ha\n' >"$test_root/etc/default/caddy-ha"
"$caddy_root/scripts/install-caddy-ha.sh" \
    --node node-b \
    --manifest "$deployment_fixture" \
    --root "$test_root" \
    --certificate-dir "$work_dir/prepared" \
    --component all >/dev/null
backup_file=$(
    find "$test_root/var/backups/caddy-ha" \
        -path '*/etc/default/caddy-ha' -type f -print -quit
)
grep -Fxq preexisting-caddy-ha "$backup_file"
"$caddy_root/scripts/validate-caddy-ha.sh" \
    --node node-b \
    --root "$test_root"
"$caddy_root/scripts/uninstall-caddy-ha.sh" \
    --node node-b \
    --root "$test_root" >/dev/null
if "$caddy_root/scripts/validate-caddy-ha.sh" \
    --node node-b \
    --root "$test_root" >/dev/null 2>&1; then
    printf 'Validation unexpectedly passed after uninstall simulation.\n' >&2
    exit 1
fi

active_v2_parent=$(
    jq -r '.revision // empty' /etc/caddy/current/release-manifest.json
)
create_v2_receiver_fixture zz-v2-reconcile
jq --arg parent_revision "$active_v2_parent" \
    '.parent_revision = $parent_revision' \
    /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile/release-manifest.json \
    >"$work_dir/v2-reconcile-manifest.json"
mv -- "$work_dir/v2-reconcile-manifest.json" \
    /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile/release-manifest.json
(
    cd /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile
    find . -type f \
        ! -path ./manifest.sha256 \
        ! -path ./.finalize-request \
        ! -path ./.complete \
        ! -path ./.complete.pending \
        -print0 |
        LC_ALL=C sort -z |
        xargs -0 sha256sum
) >/var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile/manifest.sha256
chown -R caddy-sync:caddy-sync \
    /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile
find /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile \
    -type d -exec chmod 0700 {} +
find /var/lib/caddy-sync/incoming/node-a/zz-v2-reconcile \
    -type f -exec chmod 0600 {} +
runuser -u caddy-sync -- \
    /usr/local/libexec/finalize-incoming-release-v2.sh \
    --source-role node-a
mv -- /usr/bin/systemctl "$work_dir/systemctl.real"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>/tmp/caddy-v2-systemctl.log' \
    'exit 0' \
    >/usr/bin/systemctl
chmod 0755 /usr/bin/systemctl
"$caddy_root/scripts/reconcile-release-v2.sh"
grep -Fxq 'reload caddy.service' /tmp/caddy-v2-systemctl.log
rm -f -- /usr/bin/systemctl /tmp/caddy-v2-systemctl.log
mv -- "$work_dir/systemctl.real" /usr/bin/systemctl
[[ "$(readlink /etc/caddy/current)" == /etc/caddy/releases/zz-v2-reconcile ]]

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
"$caddy_root/tests/action17t-node-b-stdout-safe-finalizer-regression.sh" \
    --self-test
printf 'action_17t_historical_container_projection_validated=true\n'
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
# These immutable, already executed artifacts deliberately hash-pin their
# workstation source ownership and create a self-test tree beside that source.
# The complete host suite above is authoritative; the read-only container
# projection must not make the repository writable merely to repeat it.
printf 'action_17s_retry2_container_projection=skipped_host_authoritative\n'
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
"$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh" \
    --contract-test
"$caddy_root/tests/action18a-dual-node-reverse-sync-readiness-regression.sh"
"$caddy_root/scripts/derive-dual-node-reverse-sync-readiness-action18a-retry.sh" \
    --self-test
"$caddy_root/tests/run-source-test-in-context.sh" \
    --runner "$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a-retry-outer.sh"
printf 'action_18a_retry_outer_container_projection=skipped_host_authoritative\n'
"$caddy_root/tests/action18a-retry-dual-node-reverse-sync-readiness-regression.sh"
for historical_action_18b_runner in \
    "$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-outer.sh" \
    "$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a.sh" \
    "$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a-retry-outer.sh" \
    "$caddy_root/scripts/run-node-a-action18-prerequisite-action18b-retry-outer.sh"; do
    "$caddy_root/tests/run-source-test-in-context.sh" \
        --runner "$historical_action_18b_runner"
done
printf 'historical_action_18b_container_projection=skipped_host_authoritative\n'
"$caddy_root/scripts/derive-node-a-action18b-postinstall-acceptance-action18b-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b-outer.sh" \
    --self-test
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
"$caddy_root/scripts/run-node-b-protocol-v2-publisher-install-action18c-prerequisite-outer.sh" \
    --contract-test
"$caddy_root/tests/action18c-publisher-prerequisite-node-b-install-regression.sh"
"$caddy_root/scripts/derive-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh" \
    --self-test
"$caddy_root/tests/action18c-publisher-a-node-b-postinstall-acceptance-regression.sh"
"$caddy_root/scripts/run-node-b-publisher-postinstall-acceptance-action18c-publisher-a-outer.sh" \
    --self-test
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
"$caddy_root/scripts/run-node-b-keepalived-fragment-install-action19a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19a-node-b-keepalived-fragment-install-regression.sh"
"$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
    --contract-test
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
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-a-node-b-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-a-retry-node-b-postfailure-regression.sh"
"$caddy_root/scripts/derive-node-b-action19b-postfailure-action19b-a-retry2.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-action19b-postfailure-action19b-a-retry2-outer.sh" \
    --self-test
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
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-install-action19b-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19b-retry-node-b-keepalived-helper-install-regression.sh"
"$caddy_root/scripts/derive-node-b-keepalived-helper-postinstall-action19b-b.sh" \
    --self-test
"$caddy_root/scripts/run-node-b-keepalived-helper-postinstall-action19b-b-outer.sh" \
    --self-test
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
"$caddy_root/scripts/run-node-b-keepalived-fragment-postinstall-action19a-b-outer.sh" \
    --contract-test
"$caddy_root/tests/action19a-b-node-b-keepalived-fragment-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-prerequisite-action19c-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-prerequisite-action19c-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19c-a-node-a-keepalived-prerequisite-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-install-action19d.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-install-action19d-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-install-action19d-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-node-a-keepalived-helper-install-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-a-node-a-keepalived-helper-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-helper-postinstall-action19d-a-retry.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-helper-postinstall-action19d-a-retry-outer.sh" \
    --contract-test
"$caddy_root/tests/action19d-a-retry-node-a-keepalived-helper-postinstall-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-fragment-action19e.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-fragment-install-action19e-outer.sh" \
    --contract-test
"$caddy_root/tests/action19e-node-a-keepalived-fragment-definition-regression.sh"
"$caddy_root/scripts/derive-node-a-keepalived-fragment-postinstall-action19e-a.sh" \
    --self-test
"$caddy_root/scripts/run-node-a-keepalived-fragment-postinstall-action19e-a-outer.sh" \
    --self-test
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
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-dual-node-caddy-health-context-action20a-a-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-dual-node-caddy-postfailure-continuity-action20a-b-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-b-caddy-health-context-correction-action20b-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-b-caddy-health-postinstall-action20b-a-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-a-caddy-health-context-correction-action20c-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-a-caddy-health-postinstall-action20c-a-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-b-caddy-state-difference-action20a-retry-a-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-dual-node-caddy-vrrp-preactivation-action20a-retry2-outer.sh" \
    --source-test
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
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c.sh" \
    --contract-test
"$caddy_root/scripts/run-node-b-to-node-a-release-transfer-action18c-outer.sh" \
    --self-test
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
"$caddy_root/tests/action20e-focused-validation.sh"
"$caddy_root/tests/action20e-retry-focused-validation.sh"
"$caddy_root/tests/action20e-b-focused-validation.sh"
"$caddy_root/tests/action20e-retry2-focused-validation.sh"
"$caddy_root/tests/action20e-retry2-a-focused-validation.sh"

printf 'Container integration validation passed.\n'
