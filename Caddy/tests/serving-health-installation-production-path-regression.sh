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
[[ "$successor_status" = defined && "$successor_action" = 35ae ]]
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

grep -Fq 'action_35_ae_production_path_test_complete=true' "$root/transaction.stdout"
grep -Fq 'action_35_ae_expected_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_ae_observed_production_inventory_node_a_dns_health_helper=' \
    "$root/transaction.stdout"
grep -Fq 'action_35_ae_outer_production_path_test_complete=true' "$root/outer.stdout"
grep -Fq 'action_35_ae_outer_check_keepalived_parser_not_invoked=true' "$root/outer.stdout"
grep -Fq 'cd / && sudo -n /bin/bash -s --' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35ae-test-[A-Za-z0-9]+-node-a' "$root/outer/raw/outer-preflight.txt"
grep -Eq '/tmp/caddy-action35ae-test-[A-Za-z0-9]+-node-b' "$root/outer/raw/outer-preflight.txt"
grep -Fxq 'pi:default' "$root/outer/raw/outer-preflight.txt"
grep -Fxq 'keepalived_script:caddy-tls' "$root/outer/raw/outer-preflight.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-a-success.txt"
grep -Fq 'payload_identity.stdout' "$root/outer/raw/evidence-readback-node-b-success.txt"
node_b_install_line=$(grep -n ' install node-b ' "$root/outer/raw/outer-preflight.txt" |
    head -n 1 | cut -d: -f1)
node_a_promote_line=$(grep -n ' --production-path-test' "$root/outer/raw/outer-preflight.txt" |
    head -n 1 | cut -d: -f1)
node_a_install_line=$(grep -n ' install node-a ' "$root/outer/raw/outer-preflight.txt" |
    head -n 1 | cut -d: -f1)
node_a_rollback_line=$(grep -n ' rollback node-a ' "$root/outer/raw/outer-preflight.txt" |
    head -n 1 | cut -d: -f1)
node_b_rollback_line=$(grep -n ' rollback node-b ' "$root/outer/raw/outer-preflight.txt" |
    head -n 1 | cut -d: -f1)
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
[[ "$(find "$root/outer/decisions" -type f | wc -l)" -eq 12 ]]
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
grep -Fq 'action_35_ae_check_local_candidate_selected=true' \
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
grep -Fq 'action_35_ae_check_node_a_quarantine_top_level_exact=true' \
    "$root/transaction/raw/node-a-quarantine-baseline.txt"
grep -Fq 'action_35_ae_check_node_a_quarantine_after_disposition_inventory=true' \
    "$root/transaction/raw/node-a-quarantine-disposition.txt"
grep -Fq 'action_35_ae_check_node_a_quarantine_restored_top_level_exact=true' \
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
grep -Fq 'keepalived-daemon-status-transitions.tsv' \
    "$root/outer/raw/evidence-readback-node-b-success.txt"
grep -Fq 'keepalived_daemon_journal.stdout' \
    "$root/outer/raw/evidence-readback-node-b-success.txt"
if grep -Fq 'reload keepalived.service' "$root/outer/raw/outer-preflight.txt"; then
    exit 1
fi
test -s "$root/outer/decisions/keepalived-daemon-owned-acceptance.tsv"
snapshot_ordering=$root/outer/raw/keepalived-daemon-owned-acceptance.txt
keepalived_stop_line=$(grep -n '^systemctl stop keepalived.service$' \
    "$snapshot_ordering" | cut -d: -f1)
tmpfiles_line=$(grep -n '^tmpfiles --create ' "$snapshot_ordering" | cut -d: -f1)
keepalived_start_line=$(grep -n '^systemctl start keepalived.service$' \
    "$snapshot_ordering" | cut -d: -f1)
dns_first_line=$(grep -n '^runuser pi:default$' "$snapshot_ordering" | head -n 1 | cut -d: -f1)
proxy_first_line=$(grep -n '^runuser keepalived_script:caddy-tls$' \
    "$snapshot_ordering" | head -n 1 | cut -d: -f1)
[[ "$keepalived_stop_line" -lt "$tmpfiles_line" &&
    "$tmpfiles_line" -lt "$keepalived_start_line" &&
    "$keepalived_start_line" -lt "$dns_first_line" &&
    "$keepalived_start_line" -lt "$proxy_first_line" ]]
[[ "$(grep -c '^runuser pi:default$' "$snapshot_ordering")" -eq 5 ]]
[[ "$(grep -c '^runuser keepalived_script:caddy-tls$' "$snapshot_ordering")" -eq 5 ]]
for rejection in dns-intermittent caddy-intermittent stale journal-failure timeout signal; do
    test -s "$root/outer/decisions/daemon-$rejection-rejection.tsv"
    grep -Fq $'\treject\t' "$root/outer/decisions/daemon-$rejection-rejection.tsv"
done
grep -Fq 'application=DNS' "$root/outer/raw/daemon-dns-intermittent-rejection.txt"
grep -Fq 'result=failed' "$root/outer/raw/daemon-dns-intermittent-rejection.txt"
grep -Fq 'failure_class=probe-failed' \
    "$root/outer/raw/daemon-dns-intermittent-rejection.txt"
grep -Fq 'application=Proxy' "$root/outer/raw/daemon-caddy-intermittent-rejection.txt"
grep -Fq 'result=failed' "$root/outer/raw/daemon-caddy-intermittent-rejection.txt"
grep -Fq 'failure_class=connection-refusal' \
    "$root/outer/raw/daemon-caddy-intermittent-rejection.txt"
for helper in caddy dns; do
    test -s "$root/transaction/decisions/helper-phase-$helper-rejection.tsv"
    grep -Fq $'\treject\t' \
        "$root/transaction/decisions/helper-phase-$helper-rejection.tsv"
    grep -Fq 'failure_class=phase-operation-failed' \
        "$root/transaction/raw/helper-phase-$helper-rejection.txt"
done
grep -Fq 'check=listener-tcp-capture' \
    "$root/transaction/raw/helper-phase-caddy-rejection.txt"
grep -Fq 'check=probe-evidence-output' \
    "$root/transaction/raw/helper-phase-dns-rejection.txt"
for probe_family in ipv4 ipv6; do
    for probe_case in missing-status malformed-status missing-output \
        malformed-output signal timeout curl http; do
        case "$probe_case" in
            missing-status | missing-output) probe_expected=probe-result-missing ;;
            malformed-status | malformed-output) probe_expected=probe-result-malformed ;;
            signal) probe_expected=signal ;;
            timeout) probe_expected=timeout ;;
            curl) probe_expected=connection-refusal ;;
            http) probe_expected=unexpected-http-status ;;
        esac
        probe_scenario=probe-result-$probe_family-$probe_case-rejection
        test -s "$root/transaction/decisions/$probe_scenario.tsv"
        test -s "$root/transaction/raw/$probe_scenario.txt"
        grep -Fq $'\treject\t' "$root/transaction/decisions/$probe_scenario.tsv"
        grep -Fq $'\t'"$probe_expected"$'\t'"$probe_expected"$'\t' \
            "$root/transaction/decisions/$probe_scenario.tsv"
        grep -Fq "failure_class=$probe_expected" \
            "$root/transaction/raw/$probe_scenario.txt"
    done
done
grep -Fq 'action_35_ae_check_keepalived_daemon_status_records_valid=false' \
    "$root/outer/raw/daemon-dns-intermittent-rejection.txt"
grep -Fq 'action_35_ae_check_keepalived_daemon_status_records_valid=false' \
    "$root/outer/raw/daemon-caddy-intermittent-rejection.txt"
grep -Fq 'action_35_ae_check_keepalived_daemon_dns_transition_count=true' \
    "$root/outer/raw/daemon-journal-failure-rejection.txt"
grep -Fq 'action_35_ae_check_keepalived_daemon_proxy_transition_count=true' \
    "$root/outer/raw/daemon-journal-failure-rejection.txt"
grep -Fq 'action_35_ae_check_keepalived_daemon_journal_no_failure=false' \
    "$root/outer/raw/daemon-journal-failure-rejection.txt"
if sed -n '/^daemon_serving_health_acceptance()/,/^}/p' "$transaction" |
    grep -Eq 'action35ae_invalid=1[^}]*break'; then
    exit 1
fi
if sed -n '/^install_serving_artifacts()/,/^}/p' "$transaction" |
    grep -Eq 'runuser|scheduled_serving_health_acceptance|scheduled_invocation'; then
    exit 1
fi

printf '%s_complete=true\n' "$prefix"
