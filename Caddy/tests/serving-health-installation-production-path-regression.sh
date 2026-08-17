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
readonly transaction=$repository_root/Caddy/scripts/apply-coupled-serving-health-action35i.sh
readonly outer=$repository_root/Caddy/scripts/run-coupled-serving-health-action35i-outer.sh
root=$(mktemp -d /tmp/caddy-serving-health-installation-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT
install -d -m 0700 "$root/transaction" "$root/outer"

CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/transaction \
    /bin/bash "$transaction" --production-path-test >"$root/transaction.stdout"
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/outer \
    /bin/bash "$outer" --production-path-test >"$root/outer.stdout"

grep -Fq 'action_35_i_production_path_test_complete=true' "$root/transaction.stdout"
grep -Fq 'action_35_i_outer_production_path_test_complete=true' "$root/outer.stdout"
grep -Fq 'cd / && sudo -n /bin/bash -s --' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35i-test-[A-Za-z0-9]+-node-a' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35i-test-[A-Za-z0-9]+-node-b' "$root/outer/raw/outer-preflight.txt"
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

printf '%s_complete=true\n' "$prefix"
