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
    root=$(mktemp -d /tmp/caddy-serving-health-state-contract.XXXXXX)
    trap 'chmod -R u+rwX -- "$root" 2>/dev/null || true; rm -rf -- "$root"' EXIT
    trap 'printf "regression_failure_line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
    install -d -m 0700 "$root/transaction"
    CADDY_NOTIFICATION_STATE_CONTRACT_ONLY=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/transaction \
        /bin/bash "$repository_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        --production-path-test >"$root/transaction.stdout"
    for decision in notification-state-only notification-state-lock \
        notification-state-unexpected notification-state-pending \
        notification-state-symlink notification-state-malformed \
        notification-state-state-mode notification-state-root-mode \
        notification-state-missing; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    awk -F '\t' '$2 == "reject" && $3 != 0 { rejected++ }
        END { exit(rejected == 7 ? 0 : 1) }' \
        "$root/transaction/decisions/notification-state-"{unexpected,pending,symlink,malformed,state-mode,root-mode,missing}.tsv
    grep -Fq 'notification_state_contract_production_path_test_complete=true' \
        "$root/transaction.stdout"
    install -d -m 0700 "$root/controlled-transaction" "$root/controlled-outer"
    CADDY_CONTROLLED_EXERCISE_CONTRACT_ONLY=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/controlled-transaction \
        /bin/bash "$repository_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        --production-path-test >"$root/controlled-transaction.stdout"
    CADDY_CONTROLLED_EXERCISE_CONTRACT_ONLY=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/controlled-outer \
        /bin/bash "$repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh" \
        --production-path-test >"$root/controlled-outer.stdout"
    grep -Fq 'controlled_failure_exercise_production_path_test_complete=true' \
        "$root/controlled-transaction.stdout"
    grep -Fq 'controlled_failure_exercise_production_path_test_complete=true' \
        "$root/controlled-outer.stdout"
    grep -Fq 'VRRP_Script(check-caddy) failed' \
        "$root/controlled-transaction/raw/exercise-journal-bounded.txt"
    test -s "$root/controlled-transaction/decisions/exercise-sampler-sigterm-lifecycle.tsv"
    test -s "$root/controlled-outer/decisions/outer-causal-continuity-classification.tsv"
    grep -Eq $'\t(handoff-overlap|settled-owner-serving-failure|family-degraded|unclassified-insufficient-evidence)$' \
        "$root/controlled-outer/raw/outer-causal-continuity-classification.txt"
    for corruption in missing duplicate malformed reordered oversized incomplete symlinked; do
        test -s "$root/controlled-outer/decisions/outer-continuity-$corruption.tsv"
        awk -F '\t' 'NR == 2 && $2 == "reject" && $3 != 0 { found=1 }
            END { exit(found ? 0 : 1) }' \
            "$root/controlled-outer/decisions/outer-continuity-$corruption.tsv"
    done
    grep -Fq $'node-a\texercise-service\tnode-a-caddy:stop' \
        "$root/controlled-outer/raw/outer-full-scenario-sequence.txt"
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
for entrypoint_root in transaction outer; do
    for decision in notification-state-only notification-state-lock \
        notification-state-unexpected notification-state-pending \
        notification-state-symlink notification-state-malformed \
        notification-state-state-mode notification-state-root-mode \
        notification-state-missing; do
        test -s "$root/$entrypoint_root/decisions/$decision.tsv"
        test -s "$root/$entrypoint_root/raw/$decision.txt"
    done
done
if [[ "$operation_scope" = external-notification-attribution-read-only ]]; then
    for decision in endpoint-only secret-bearing-evidence-rejection \
        exact-legacy-title-search second-caller-attribution scheduled-job-attribution \
        retained-replay-attribution multiple-candidate-ambiguity no-evidence-unattributed \
        bounded-journal-selection zero-production-mutation; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    for decision in outer-preflight exact-remote-cleanup evidence-readback-success \
        evidence-readback-failure zero-production-mutation-outer; do
        test -s "$root/outer/decisions/$decision.tsv"
        test -s "$root/outer/raw/$decision.txt"
    done
    awk -F '\t' '$1 == "multiple-candidate-ambiguity" && $2 == "reject" && $3 != 0 { found++ }
        END { exit(found == 1 ? 0 : 1) }' \
        "$root/transaction/decisions/multiple-candidate-ambiguity.tsv"
    awk -F '\t' '$1 == "secret-bearing-evidence-rejection" && $2 == "reject" && $3 != 0 { found++ }
        END { exit(found == 1 ? 0 : 1) }' \
        "$root/transaction/decisions/secret-bearing-evidence-rejection.tsv"
    grep -Fq 'external_attribution_production_path_test_complete=true' \
        "$root/transaction.stdout"
    grep -Fq 'external_attribution_production_path_test_complete=true' \
        "$root/outer.stdout"
    grep -Fxq 'remote_program_absent=true' "$root/outer/raw/exact-remote-cleanup.txt"
    grep -Fxq 'remote_evidence_preserved=true' "$root/outer/raw/exact-remote-cleanup.txt"
    grep -Fq 'caddy-notification-attribution-' "$root/outer/raw/outer-preflight.txt"
    if grep -Eq '(systemctl|curl[[:space:]].*(-X|--request)[[:space:]]*POST)' \
        "$root/outer/raw/outer-preflight.txt"; then
        exit 1
    fi
    printf '%s_complete=true\n' "$prefix"
    exit 0
elif [[ "$operation_scope" = controlled-serving-failure-exercise ]]; then
    for decision in exercise-role-rejection exercise-service-control \
        exercise-ownership-convergence exercise-journal-bounded \
        exercise-sampler-sigterm-lifecycle \
        exercise-reverse-restoration; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    for decision in outer-preflight outer-real-preflight outer-stale-preflight \
        outer-full-scenario-sequence outer-restored-failure-non125 \
        outer-acceptance-failure-non125 outer-causal-continuity-classification \
        outer-readback-cleanup; do
        test -s "$root/outer/decisions/$decision.tsv"
        test -s "$root/outer/raw/$decision.txt"
    done
    grep -Fq 'controlled_failure_exercise_production_path_test_complete=true' \
        "$root/transaction.stdout"
    grep -Fq 'controlled_failure_exercise_production_path_test_complete=true' \
        "$root/outer.stdout"
    for scenario in node-a-caddy node-a-lighttpd node-a-pihole-ftl \
        node-a-unbound node-a-keepalived node-b-caddy \
        node-b-lighttpd node-b-pihole-ftl node-b-unbound; do
        grep -Fq "$scenario" "$root/outer/raw/outer-full-scenario-sequence.txt"
    done
    for corruption in missing duplicate malformed reordered oversized incomplete symlinked; do
        test -s "$root/outer/decisions/outer-continuity-$corruption.tsv"
    done
    grep -Fq $'node-a\texercise-service\tnode-a-caddy:stop' \
        "$root/outer/raw/outer-full-scenario-sequence.txt"
    grep -Fq $'node-a\texercise-journal\tnode-a-caddy' \
        "$root/outer/raw/outer-full-scenario-sequence.txt"
    grep -Fq 'VRRP_Script(check-caddy) failed' \
        "$root/transaction/raw/exercise-journal-bounded.txt"
    grep -Fq 'VRRP_Script(check-caddy) succeeded' \
        "$root/transaction/raw/exercise-journal-bounded.txt"
    grep -Fxq 'node_a_payload=absent' "$root/outer/raw/outer-readback-cleanup.txt"
    grep -Fxq 'node_b_payload=absent' "$root/outer/raw/outer-readback-cleanup.txt"
    printf '%s_complete=true\n' "$prefix"
    exit 0
elif [[ "$operation_scope" = notification-standardization-only ]]; then
    for decision in notification-preflight notification-install notification-accept \
        notification-rollback notification-candidate-tamper; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    awk -F '\t' '$1 == "notification-candidate-tamper" && $2 == "reject" && $3 != 0 { found++ }
        END { exit(found == 1 ? 0 : 1) }' \
        "$root/transaction/decisions/notification-candidate-tamper.tsv"
    grep -Fq 'notification_standardization_production_path_test_complete=true' \
        "$root/transaction.stdout"
    grep -Fq $'node-b\tcd / && sudo -n /bin/bash -s -- notification-install' \
        "$root/outer/raw/outer-standby-first.txt"
    grep -Fq $'node-a\tcd / && sudo -n /bin/bash -s -- notification-install' \
        "$root/outer/raw/outer-standby-first.txt"
    grep -Fq 'file=mutation.tsv' "$root/outer/raw/outer-evidence-readback.txt"
    [[ "$(wc -l <"$root/transaction/busctl.calls")" -eq 2 ]]
    [[ "$(wc -l <"$root/transaction/ip.calls")" -eq 1 ]]
    grep -Fq '/org/keepalived/Vrrp1/Instance/eth0/100/IPv4' \
        "$root/outer/raw/outer-preflight.txt"
    grep -Fq '/org/keepalived/Vrrp1/Instance/eth0/101/IPv6' \
        "$root/outer/raw/outer-preflight.txt"
    grep -Fq $'node-a\t-o address show dev eth0' \
        "$root/outer/raw/outer-preflight.txt"
    grep -Fq $'node-b\t-o address show dev eth0' \
        "$root/outer/raw/outer-preflight.txt"
    printf '%s_complete=true\n' "$prefix"
    exit 0
elif [[ "$operation_scope" = pihole-web-health-unit-only ]]; then
    for decision in web-unit-service-identity web-unit-preflight web-unit-install web-unit-accept \
        web-unit-rollback web-unit-candidate-tamper; do
        test -s "$root/transaction/decisions/$decision.tsv"
        test -s "$root/transaction/raw/$decision.txt"
    done
    awk -F '\t' '$1 == "web-unit-candidate-tamper" && $2 == "reject" && $3 != 0 { found++ }
        END { exit(found == 1 ? 0 : 1) }' \
        "$root/transaction/decisions/web-unit-candidate-tamper.tsv"
    grep -Fxq 'start caddy-pihole-web-health.service' "$root/transaction/systemctl.calls"
    grep -Fq 'web_unit_timer_healthy_event=true' "$root/transaction/raw/web-unit-accept.txt"
    grep -Fq 'web_unit_timer_successful_completion=true' "$root/transaction/raw/web-unit-accept.txt"
    grep -Fq 'web_unit_timer_result=true' "$root/transaction/raw/web-unit-accept.txt"
    grep -Fq 'web_unit_timer_status=true' "$root/transaction/raw/web-unit-accept.txt"
    awk '/--show-cursor/ { count++ } END { exit(count == 2 ? 0 : 1) }' \
        "$root/transaction/journalctl.calls"
    grep -Fq 'web_unit_timer_failures_absent=true' "$root/transaction/raw/web-unit-accept.txt"
    if [[ "$EUID" -eq 0 ]]; then
        grep -Fxq 'without_caddy_tls_readable=false' "$root/transaction/raw/web-unit-service-identity.txt"
        grep -Fxq 'with_caddy_tls_readable=true' "$root/transaction/raw/web-unit-service-identity.txt"
        grep -Fxq 'pi_primary_queue_writable=true' "$root/transaction/raw/web-unit-service-identity.txt"
        grep -Fxq 'kernel_dac_execution=true' "$root/transaction/raw/web-unit-service-identity.txt"
    else
        grep -Fxq 'kernel_dac_execution=requires-root-debian-batch' \
            "$root/transaction/raw/web-unit-service-identity.txt"
    fi
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
    grep -Fq 'file=web_unit_failure_journal.stdout' \
        "$root/outer/raw/outer-reverse-rollback.txt"
    grep -Fxq 'ReadWritePaths=/var/lib/caddy-apprise-queue' \
        "$repository_root/Caddy/systemd/caddy-pihole-web-health.service"
    if grep -Fq '/run/caddy-apprise' \
        "$repository_root/Caddy/systemd/caddy-pihole-web-health.service"; then
        exit 1
    fi
    grep -Fxq 'SupplementaryGroups=caddy-tls' \
        "$repository_root/Caddy/systemd/caddy-pihole-web-health.service"
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
