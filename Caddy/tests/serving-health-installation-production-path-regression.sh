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
readonly transaction=$repository_root/Caddy/scripts/apply-coupled-serving-health-action35q.sh
readonly outer=$repository_root/Caddy/scripts/run-coupled-serving-health-action35q-outer.sh
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

grep -Fq 'action_35_q_production_path_test_complete=true' "$root/transaction.stdout"
grep -Fq 'action_35_q_expected_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_q_observed_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_q_outer_production_path_test_complete=true' "$root/outer.stdout"
grep -Fq 'cd / && sudo -n /bin/bash -s --' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35q-test-[A-Za-z0-9]+-node-a' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35q-test-[A-Za-z0-9]+-node-b' "$root/outer/raw/outer-preflight.txt"
grep -Fxq pi "$root/outer/raw/outer-preflight.txt"
grep -Fxq keepalived_script "$root/outer/raw/outer-preflight.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-a-success.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-b-success.txt"
node_b_install_line=$(grep -n ' install node-b ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_a_install_line=$(grep -n ' install node-a ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_a_rollback_line=$(grep -n ' rollback node-a ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
node_b_rollback_line=$(grep -n ' rollback node-b ' "$root/outer/raw/outer-preflight.txt" | cut -d: -f1)
[[ "$node_b_install_line" -lt "$node_a_install_line" ]]
[[ "$node_a_install_line" -lt "$node_a_rollback_line" ]]
[[ "$node_a_rollback_line" -lt "$node_b_rollback_line" ]]
grep -Fxq pi "$root/outer/raw/evidence-readback-node-a-success.txt" ||
    grep -Fq 'dns_identity.stdout' "$root/outer/raw/evidence-readback-node-a-success.txt"
[[ "$(find "$root/transaction/decisions" -type f | wc -l)" -gt 60 ]]
[[ "$(find "$root/outer/decisions" -type f | wc -l)" -eq 5 ]]
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

printf '%s_complete=true\n' "$prefix"
