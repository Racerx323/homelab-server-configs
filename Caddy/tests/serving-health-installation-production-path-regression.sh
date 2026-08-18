#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_installation_production_path_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly successor_registry=$repository_root/Caddy/manifests/deployable-successor.tsv
IFS=$'\t' read -r successor_status successor_action transaction_relative outer_relative < <(
    awk -F '\t' 'NR == 2 { print $2 "\t" $3 "\t" $5 "\t" $6 }' \
        "$successor_registry"
)
[[ "$successor_status" = defined && "$successor_action" = 35aa ]]
readonly transaction=$repository_root/$transaction_relative
readonly outer=$repository_root/$outer_relative
root=$(mktemp -d /tmp/caddy-serving-health-installation-regression.XXXXXX)
readonly root
cleanup() {
    chmod -R u+rwX -- "$root" 2>/dev/null || true
    rm -rf -- "$root"
}
trap cleanup EXIT
trap 'printf "regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
install -d -m 0700 "$root/transaction" "$root/outer"

CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/transaction \
    /bin/bash "$transaction" --production-path-test >"$root/transaction.stdout"
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/outer \
    /bin/bash "$outer" --production-path-test >"$root/outer.stdout"

grep -Fq 'action_35_aa_production_path_test_complete=true' "$root/transaction.stdout"
grep -Fq 'action_35_aa_expected_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_aa_observed_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_aa_outer_production_path_test_complete=true' "$root/outer.stdout"
grep -Fq 'action_35_aa_outer_check_keepalived_parser_not_invoked=true' "$root/outer.stdout"
grep -Fq 'cd / && sudo -n /bin/bash -s --' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35aa-test-[A-Za-z0-9]+-node-a' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35aa-test-[A-Za-z0-9]+-node-b' "$root/outer/raw/outer-preflight.txt"
grep -Fxq 'pi:default' "$root/outer/raw/outer-preflight.txt"
grep -Fxq 'keepalived_script:caddy-tls' "$root/outer/raw/outer-preflight.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-a-success.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-b-success.txt"
node_b_install_line=$(grep -n ' install node-b ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_a_promote_line=$(grep -n ' --production-path-test' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_a_install_line=$(grep -n ' install node-a ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_a_rollback_line=$(grep -n ' rollback node-a ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_b_rollback_line=$(grep -n ' rollback node-b ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
[[ "$node_b_install_line" -lt "$node_a_promote_line" ]]
[[ "$node_a_promote_line" -lt "$node_a_install_line" ]]
if grep -Fq 'node-a-candidate-check' "$root/outer/raw/outer-preflight.txt"; then
    exit 1
fi
[[ "$node_a_install_line" -lt "$node_a_rollback_line" ]]
[[ "$node_a_rollback_line" -lt "$node_b_rollback_line" ]]
grep -Fxq 'pi:default' "$root/outer/transaction-through-outer/runuser.calls"
grep -Fxq 'keepalived_script:caddy-tls' \
    "$root/outer/transaction-through-outer/runuser.calls"
[[ "$(find "$root/transaction/decisions" -type f | wc -l)" -gt 60 ]]
[[ "$(find "$root/outer/decisions" -type f | wc -l)" -eq 6 ]]
grep -Fq 'retained_candidate_dispositioned=true' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq 'retained_finalize_request_absent=true' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq 'retained_complete_absent=true' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq 'retained_complete_pending_absent=true' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq 'stop caddy-sync-reconcile.path' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq 'start caddy-lsyncd.service' "$root/transaction/raw/transaction-acceptance.txt"
grep -Fq -- '--production-path-test' "$root/outer/raw/outer-preflight.txt"
grep -Fq 'quarantine_baseline_exact=true' \
    "$root/outer/transaction-through-outer/raw/transaction-acceptance.txt"
grep -Fq 'quarantine_after_disposition_inventory=true' \
    "$root/outer/transaction-through-outer/raw/transaction-acceptance.txt"
grep -Fq 'quarantine_restored_exact=true' \
    "$root/outer/transaction-through-outer/raw/transaction-acceptance.txt"
grep -Fq 'current_before=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04' \
    "$root/outer/transaction-through-outer/raw/post-promotion-sequence.txt"
grep -Fq 'current_after=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca' \
    "$root/outer/transaction-through-outer/raw/post-promotion-sequence.txt"
grep -Fq 'action_35_aa_check_local_candidate_selected=true' \
    "$root/outer/transaction-through-outer/raw/post-promotion-sequence.txt"
grep -Fq 'caddy_serving_health_check_ipv4_https=true' \
    "$root/outer/transaction-through-outer/raw/post-promotion-sequence.txt"
grep -Fq 'caddy_serving_health_check_ipv6_https=true' \
    "$root/outer/transaction-through-outer/raw/post-promotion-sequence.txt"
grep -Fq 'stable_samples=3' \
    "$root/transaction/raw/bounded-node-b-convergence.txt"
test -s "$root/transaction/decisions/bounded-node-b-convergence.tsv"
test -s "$root/transaction/decisions/node-b-master-rejection.tsv"
grep -Fq 'https://proxy.local.theama.co/' "$transaction"
if sed -n '/^start_sampler()/,/^}/p' "$transaction" | grep -Fq '/healthz'; then
    exit 1
fi
grep -Fq 'retained_candidate_dispositioned=true' \
    "$root/outer/transaction-through-outer/raw/transaction-acceptance.txt"
grep -Fq 'legacy_lighttpd_helper_identity=true' \
    "$root/transaction/raw/legacy-helper-node-b-baseline.txt"
grep -Fq 'legacy_lighttpd_helper_removed=true' \
    "$root/transaction/raw/legacy-helper-removal.txt"
grep -Fq 'legacy_lighttpd_helper_identity=true' \
    "$root/transaction/raw/legacy-helper-rollback.txt"
grep -Fq 'legacy_lighttpd_helper_state=true' \
    "$root/transaction/raw/legacy-helper-node-a-baseline.txt"
for decision in \
    node-a-quarantine-baseline \
    node-a-quarantine-extra-rejection \
    node-a-quarantine-changed-rejection \
    node-a-quarantine-malformed-rejection \
    node-a-quarantine-symlink-rejection \
    node-a-quarantine-reference-rejection \
    node-a-quarantine-disposition \
    node-a-quarantine-rollback; do
    test -s "$root/transaction/decisions/$decision.tsv"
done
grep -Fq 'action_35_aa_check_node_a_quarantine_top_level_exact=true' \
    "$root/transaction/raw/node-a-quarantine-baseline.txt"
grep -Fq 'action_35_aa_check_node_a_quarantine_after_disposition_inventory=true' \
    "$root/transaction/raw/node-a-quarantine-disposition.txt"
grep -Fq 'action_35_aa_check_node_a_quarantine_restored_top_level_exact=true' \
    "$root/transaction/raw/node-a-quarantine-rollback.txt"
canonical_candidate=$root/transaction/state/quarantine/node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29
grep -Eq '^[0-9a-f]{64}  \./Caddyfile$' "$canonical_candidate/manifest.sha256"
grep -Eq '^[0-9a-f]{64}  \./release-manifest.json$' \
    "$canonical_candidate/manifest.sha256"
if grep -Eq '^[0-9a-f]{64}  Caddyfile$' "$canonical_candidate/manifest.sha256"; then
    exit 1
fi
grep -Fxq 'pi:default' "$root/outer/transaction-through-outer/runuser.calls"
grep -Fxq 'keepalived_script:caddy-tls' \
    "$root/outer/transaction-through-outer/runuser.calls"
grep -Fq 'scheduled-1-dns.tsv' \
    "$root/outer/raw/evidence-readback-node-b-success.txt"
grep -Fq 'scheduled-1-caddy.tsv' \
    "$root/outer/raw/evidence-readback-node-b-success.txt"
grep -Fq 'reload keepalived.service' "$root/outer/raw/outer-preflight.txt"
test -s \
    "$root/outer/decisions/scheduled-helper-acceptance-before-keepalived-reload.tsv"
snapshot_ordering=$root/outer/raw/scheduled-helper-acceptance-before-keepalived-reload.txt
tmpfiles_line=$(grep -n '^tmpfiles --create ' "$snapshot_ordering" | cut -d: -f1)
[[ "$(grep -c '^runuser pi:default$' "$snapshot_ordering")" -eq 5 ]]
[[ "$(grep -c '^runuser keepalived_script:caddy-tls$' "$snapshot_ordering")" -eq 5 ]]
dns_schedule_line=$(grep -n '^runuser pi:default$' "$snapshot_ordering" | head -n 1 | cut -d: -f1)
proxy_schedule_line=$(grep -n '^runuser keepalived_script:caddy-tls$' \
    "$snapshot_ordering" | head -n 1 | cut -d: -f1)
dns_schedule_last=$(grep -n '^runuser pi:default$' "$snapshot_ordering" | tail -n 1 | cut -d: -f1)
proxy_schedule_last=$(grep -n '^runuser keepalived_script:caddy-tls$' \
    "$snapshot_ordering" | tail -n 1 | cut -d: -f1)
keepalived_line=$(grep -n '^systemctl reload keepalived.service$' \
    "$snapshot_ordering" | cut -d: -f1)
[[ "$tmpfiles_line" -lt "$dns_schedule_line" &&
    "$tmpfiles_line" -lt "$proxy_schedule_line" &&
    "$dns_schedule_last" -lt "$keepalived_line" &&
    "$proxy_schedule_last" -lt "$keepalived_line" ]]

printf '%s_complete=true\n' "$prefix"
