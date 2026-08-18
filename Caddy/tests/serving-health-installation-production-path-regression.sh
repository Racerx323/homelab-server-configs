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
if [[ "$successor_status" = none ]]; then
    [[ "$successor_action" = - && "$transaction_relative" = - && "$outer_relative" = - ]]
    printf '%s_no_registered_successor=true\n' "$prefix"
    exit 0
fi
[[ "$successor_status" = defined ]]
readonly transaction=$repository_root/$transaction_relative
readonly outer=$repository_root/$outer_relative
operation_scope=$(sed -n 's/^scope: //p' \
    "$repository_root/Caddy/manifests/serving-health-operation.yaml")
readonly operation_scope
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

grep -Eq '_production_path_test_complete=true$' "$root/transaction.stdout"
grep -Eq '_production_path_test_complete=true$' "$root/outer.stdout"
if [[ "$operation_scope" = pihole-web-health-unit-only ]]; then
    for decision in web-unit-preflight web-unit-install web-unit-accept \
        web-unit-rollback web-unit-candidate-tamper; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    awk -F '\t' '$1 == "web-unit-candidate-tamper" && $2 == "reject" && $3 != 0 { found++ }
        END { exit(found == 1 ? 0 : 1) }' \
        "$root/transaction/decisions/web-unit-candidate-tamper.tsv"
    grep -Fxq 'start caddy-pihole-web-health.service' \
        "$root/transaction/systemctl.calls"
    grep -Fq 'web_unit_direct_and_timer_starts=true' \
        "$root/transaction/raw/web-unit-accept.txt"
    grep -Fq 'web_unit_timer_failures_absent=true' \
        "$root/transaction/raw/web-unit-accept.txt"
    for decision in outer-preflight outer-reverse-rollback outer-standby-first \
        outer-evidence-readback outer-zero-residue; do
        test -s "$root/outer/decisions/$decision.tsv"
        test -s "$root/outer/raw/$decision.txt"
    done
    grep -Fq $'node-b\tcd / && sudo -n /bin/bash -s -- web-unit-install' \
        "$root/outer/raw/outer-standby-first.txt"
    grep -Fq $'node-a\tcd / && sudo -n /bin/bash -s -- web-unit-install' \
        "$root/outer/raw/outer-standby-first.txt"
    grep -Fq 'node_a_payload_absent=true' "$root/outer/raw/outer-zero-residue.txt"
    grep -Fq 'node_b_payload_absent=true' "$root/outer/raw/outer-zero-residue.txt"
    grep -Fxq 'ReadWritePaths=/var/lib/caddy-apprise-queue' \
        "$repository_root/Caddy/systemd/caddy-pihole-web-health.service"
    if grep -Fq '/run/caddy-apprise' \
        "$repository_root/Caddy/systemd/caddy-pihole-web-health.service"; then
        exit 1
    fi
    if sed -n '/^run_web_health_unit_live()/,/^}/p' "$outer" |
        grep -Eq 'restart|reload.*(caddy|lighttpd|pihole-FTL|unbound|keepalived)'; then
        exit 1
    fi
    printf '%s_complete=true\n' "$prefix"
    exit 0
fi
grep -Fq '_check_keepalived_parser_not_invoked=true' "$root/outer.stdout"

for decision in \
    transaction-acceptance transaction-rejection \
    protocol-namespace-state-equivalence \
    post-promotion-sequence protocol-v2-target-publication \
    protocol-v2-target-promotion minimal-caddy-failure minimal-dns-failure \
    bounded-node-b-convergence node-b-master-rejection; do
    if [[ ! -s "$root/transaction/decisions/$decision.tsv" ||
        ! -s "$root/transaction/raw/$decision.txt" ]]; then
        printf 'missing_transaction_evidence=%s\n' "$decision" >&2
        exit 1
    fi
done
grep -Fq $'protocol-namespace-state-equivalence\taccept\t0\t' \
    "$root/transaction/decisions/protocol-namespace-state-equivalence.tsv"
for namespace_case in absent empty-protected; do
    grep -Fq "protocol-namespace-$namespace_case"$'\taccept\t0\t' \
        "$root/transaction/decisions/protocol-namespace-$namespace_case.tsv"
done
for namespace_case in non-empty unsafe-mode unsafe-owner symlink malformed; do
    awk -F '\t' -v scenario="protocol-namespace-$namespace_case" '
        $1 == scenario && $2 == "reject" && $3 != 0 { accepted = 1 }
        END { exit !accepted }
    ' "$root/transaction/decisions/protocol-namespace-$namespace_case.tsv"
done
grep -Fq 'protocol_namespace_state=absent' \
    "$root/transaction/raw/protocol-namespace-absent.txt"
grep -Fq 'protocol_namespace_metadata=true' \
    "$root/transaction/raw/protocol-namespace-empty-protected.txt"
grep -Fq $'protocol-v2-target-publication\taccept\t0\t' \
    "$root/transaction/decisions/protocol-v2-target-publication.tsv"
grep -Fq $'protocol-v2-target-promotion\taccept\t0\t' \
    "$root/transaction/decisions/protocol-v2-target-promotion.tsv"
grep -Fq 'target_candidate_parent=true' \
    "$root/transaction/raw/protocol-v2-target-publication.txt"
grep -Fq 'target_candidate_caddy_payload=true' \
    "$root/transaction/raw/protocol-v2-target-publication.txt"

for decision in \
    outer-preflight keepalived-daemon-owned-acceptance \
    daemon-journal-failure-rejection \
    evidence-readback-node-a-success evidence-readback-node-a-failure \
    evidence-readback-node-b-success evidence-readback-node-b-failure; do
    test -s "$root/outer/decisions/$decision.tsv"
    test -s "$root/outer/raw/$decision.txt"
done
grep -Fq 'cd / && sudo -n /bin/bash -s --' \
    "$root/outer/raw/outer-preflight.txt"
grep -Fxq 'runuser pi:default' \
    "$root/outer/raw/keepalived-daemon-owned-acceptance.txt"
grep -Fxq 'runuser keepalived_script:caddy-tls' \
    "$root/outer/raw/keepalived-daemon-owned-acceptance.txt"
[[ "$(grep -c '^runuser pi:default$' \
    "$root/outer/raw/keepalived-daemon-owned-acceptance.txt")" -eq 3 ]]
[[ "$(grep -c '^runuser keepalived_script:caddy-tls$' \
    "$root/outer/raw/keepalived-daemon-owned-acceptance.txt")" -eq 3 ]]
grep -Fq 'keepalived_daemon_journal_no_failure=false' \
    "$root/outer/raw/daemon-journal-failure-rejection.txt"

if grep -En 'STATUS_FILE|status-record|scheduled_invocation|/usr/bin/timeout' \
    "$transaction" "$outer"; then
    exit 1
fi
if sed -n '/^daemon_serving_health_acceptance()/,/^}/p' "$transaction" |
    grep -Eq 'runuser|check-dns\.sh|check-caddy\.sh'; then
    exit 1
fi
grep -Fq 'VRRP_Script\(check-dns\)' "$transaction"
grep -Fq 'VRRP_Script\(check-caddy\)' "$transaction"
grep -Fq 'publish-release-v2.sh' "$transaction"
grep -Fq '10-pihole-admin.caddy' "$transaction"

live_sequence=$root/live-sequence.txt
sed -n '/^run_live()/,/^}/p' "$outer" >"$live_sequence"
if grep -Fq 'node-a-record-target' "$live_sequence"; then
    printf 'redundant_node_a_record_target=true\n' >&2
    exit 1
fi
publish_line=$(grep -n 'node-a-publish' "$live_sequence" | head -n 1 | cut -d: -f1)
node_b_record_line=$(grep -n 'node-b-record-target' "$live_sequence" | head -n 1 | cut -d: -f1)
node_b_wait_line=$(grep -n 'node-b-wait-target' "$live_sequence" | head -n 1 | cut -d: -f1)
node_b_accept_line=$(grep -n 'node-b-target-accept' "$live_sequence" | head -n 1 | cut -d: -f1)
node_a_promote_line=$(grep -n 'node-a-promote-target' "$live_sequence" | head -n 1 | cut -d: -f1)
[[ "$publish_line" -lt "$node_b_record_line" &&
    "$node_b_record_line" -lt "$node_b_wait_line" &&
    "$node_b_wait_line" -lt "$node_b_accept_line" &&
    "$node_b_accept_line" -lt "$node_a_promote_line" ]]
grep -Fq 'serving-health-operation.yaml' "$outer"
if grep -Eq 'action[0-9]+.*(transaction|outer|regression)' \
    "$transaction" "$outer"; then
    exit 1
fi

printf '%s_complete=true\n' "$prefix"
