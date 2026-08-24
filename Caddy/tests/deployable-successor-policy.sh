#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly successor_policy_prefix=deployable_successor_policy
successor_policy_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly successor_policy_test_directory
successor_policy_default_root=${successor_policy_test_directory%/Caddy/tests}
readonly successor_policy_default_root

if [[ -n "${CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT:-}" ]]; then
    [[ "${CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE:-}" = 1 ]] || exit 64
    [[ "$CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT" = /tmp/* ]] || exit 64
    successor_policy_repository_root=$CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT
else
    successor_policy_repository_root=$successor_policy_default_root
fi
readonly successor_policy_repository_root
readonly successor_policy_registry=${CADDY_DEPLOYABLE_SUCCESSOR_REGISTRY:-$successor_policy_repository_root/Caddy/manifests/deployable-successor.tsv}

successor_policy_check() {
    local successor_policy_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$successor_policy_prefix" "$successor_policy_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$successor_policy_prefix" "$successor_policy_label" >&2
    return 1
}

successor_policy_regular_file() {
    local successor_policy_path=$1

    [[ -f "$successor_policy_path" && ! -L "$successor_policy_path" ]]
}

successor_policy_executable_file() {
    local successor_policy_relative=$1
    local successor_policy_path=$successor_policy_repository_root/$successor_policy_relative
    local successor_policy_index_mode

    successor_policy_regular_file "$successor_policy_path" || return 1
    [[ -x "$successor_policy_path" ]] || return 1
    if [[ "$successor_policy_repository_root" = "$successor_policy_default_root" ]]; then
        successor_policy_index_mode=$(git -C "$successor_policy_repository_root" \
            ls-files -s -- "$successor_policy_relative" | awk '{ print $1 }')
        if [[ -n "$successor_policy_index_mode" ]]; then
            [[ "$successor_policy_index_mode" = 100755 ]] || return 1
        fi
    fi
}

successor_policy_neutral_entrypoints_are_real() {
    local successor_policy_outer_path=$successor_policy_repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh

    successor_policy_regular_file "$successor_policy_outer_path" || return 1
    grep -Fq 'exec env' "$successor_policy_outer_path" || return 1
    grep -Fq 'CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=' \
        "$successor_policy_outer_path" || return 1
    # The policy intentionally searches for literal shell source, not expansion.
    # shellcheck disable=SC2016
    if grep -Eq '>[[:space:]]*"\$evidence/(availability\.tsv|exercise_.*_journal\.stdout|exercise-ownership-samples\.tsv)"' \
        "$successor_policy_outer_path"; then
        return 1
    fi
    # shellcheck disable=SC2016
    if grep -Fq 'case "$mode" in' "$successor_policy_outer_path"; then
        return 1
    fi
}

successor_policy_inactive_valid() {
    local successor_policy_operation=$successor_policy_repository_root/Caddy/manifests/serving-health-operation.yaml
    local successor_policy_transaction=$successor_policy_repository_root/Caddy/scripts/apply-serving-health-deployment.sh
    local successor_policy_outer=$successor_policy_repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh
    local successor_policy_operation_hash successor_policy_transaction_hash

    successor_policy_regular_file "$successor_policy_operation" || return 1
    successor_policy_executable_file Caddy/scripts/apply-serving-health-deployment.sh || return 1
    successor_policy_executable_file Caddy/scripts/run-serving-health-deployment-outer.sh || return 1
    grep -Fxq 'action: none' "$successor_policy_operation" || return 1
    grep -Fxq 'status: inactive' "$successor_policy_operation" || return 1
    grep -Fxq '  lifecycle: neutral-reusable' "$successor_policy_operation" || return 1
    grep -Fxq '  copy_per_action: prohibited' "$successor_policy_operation" || return 1
    grep -Fxq 'transaction: Caddy/scripts/apply-serving-health-deployment.sh' \
        "$successor_policy_operation" || return 1
    grep -Fxq 'outer_runner: Caddy/scripts/run-serving-health-deployment-outer.sh' \
        "$successor_policy_operation" || return 1
    grep -Fxq 'state_contract: Caddy/manifests/current-live-state.tsv' \
        "$successor_policy_operation" || return 1
    grep -Fxq 'production_contract: Caddy/manifests/serving-health-production.tsv' \
        "$successor_policy_operation" || return 1
    grep -Fxq 'live_execution: no-operation-defined' "$successor_policy_operation" || return 1
    ! grep -Eq '^(scope|quarantine_contract|baseline_contract):' \
        "$successor_policy_operation" || return 1
    successor_policy_transaction_hash=$(sha256sum "$successor_policy_transaction" | awk '{ print $1 }') || return 1
    successor_policy_operation_hash=$(sha256sum "$successor_policy_operation" | awk '{ print $1 }') || return 1
    grep -Fxq "transaction_sha256: $successor_policy_transaction_hash" \
        "$successor_policy_operation" || return 1
    grep -Fxq "readonly transaction_sha256=$successor_policy_transaction_hash" \
        "$successor_policy_outer" || return 1
    grep -Fxq "readonly operation_sha256=$successor_policy_operation_hash" \
        "$successor_policy_outer" || return 1
}

successor_policy_remove_probe_root() {
    local successor_policy_cleanup_root=$1

    [[ "$successor_policy_cleanup_root" = /tmp/caddy-successor-production-evidence.* ]]
    [[ -d "$successor_policy_cleanup_root" && ! -L "$successor_policy_cleanup_root" ]]
    chmod -R u+rwX -- "$successor_policy_cleanup_root"
    rm -rf -- "$successor_policy_cleanup_root"
}

successor_policy_state_valid() {
    local successor_policy_state=$1
    local successor_policy_accepted_hash successor_policy_runtime_hash

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_state" || return 1
    [[ "$(sed -n '1p' "$successor_policy_state")" = $'schema_version\tscope\tkey\tvalue\tevidence' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 5 || $1 != "1" { invalid = 1; exit }
        $2 !~ /^(cluster|node-a|node-b)$/ { invalid = 1; exit }
        $3 !~ /^[a-z0-9][a-z0-9-]*$/ || $4 == "" || $5 == "" { invalid = 1; exit }
        seen[$2 FS $3]++ { invalid = 1; exit }
        END { exit invalid || NR <= 1 }
    ' "$successor_policy_state" || return 1
    for successor_policy_required in \
        cluster:accepted-live-artifacts-sha256 cluster:runtime-production-sha256 \
        node-a:ownership node-a:services node-a:release \
        node-a:durable-apprise-installation node-a:apprise-queue \
        node-b:ownership node-b:services node-b:release \
        node-b:durable-apprise-installation node-b:apprise-queue; do
        awk -F '\t' -v required="$successor_policy_required" '
            NR > 1 && $2 ":" $3 == required { found++ }
            END { exit(found == 1 ? 0 : 1) }
        ' "$successor_policy_state" || return 1
    done
    successor_policy_accepted_hash=$(awk -F '\t' '$2 == "cluster" && $3 == "accepted-live-artifacts-sha256" { print $4 }' "$successor_policy_state") || return 1
    successor_policy_runtime_hash=$(awk -F '\t' '$2 == "cluster" && $3 == "runtime-production-sha256" { print $4 }' "$successor_policy_state") || return 1
    [[ "$successor_policy_accepted_hash" = "$(sha256sum "$successor_policy_repository_root/Caddy/manifests/accepted-live-artifacts.tsv" | awk '{ print $1 }')" ]] || return 1
    [[ "$successor_policy_runtime_hash" = "$(sha256sum "$successor_policy_repository_root/Caddy/manifests/runtime-production.tsv" | awk '{ print $1 }')" ]] || return 1
    # conditional-validator-explicit-failures-end
}

successor_policy_coverage_valid() {
    local successor_policy_coverage=$1
    local successor_policy_scope=$2
    local successor_policy_required_scenario
    local successor_policy_required_scenarios

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_coverage" || return 1
    [[ "$(sed -n '1p' "$successor_policy_coverage")" = $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 6 { invalid = 1; exit }
        $1 !~ /^[a-z0-9][a-z0-9_-]*$/ || $2 !~ /^(pre-mutation|accepted-path)$/ { invalid = 1; exit }
        $3 !~ /^(outer|transaction)$/ || $4 !~ /^(accept|reject|reach)$/ { invalid = 1; exit }
        $5 !~ /^decisions\/[a-z0-9][a-z0-9._-]*\.tsv$/ { invalid = 1; exit }
        $6 !~ /^raw\/[a-z0-9][a-z0-9._-]*\.(txt|tsv|json)$/ { invalid = 1; exit }
        seen_scenario[$1]++ || seen_decision[$5]++ || seen_raw[$6]++ { invalid = 1; exit }
        END { exit invalid || NR <= 1 }
    ' "$successor_policy_coverage" || return 1
    awk -F '\t' '
        NR == 1 { next }
        $2 == "pre-mutation" && $3 == "outer" && $4 == "reach" { outer_pre++ }
        $2 == "pre-mutation" && $3 == "transaction" && $4 == "reject" { tx_reject++ }
        $2 == "accepted-path" && $3 == "transaction" && ($4 == "accept" || $4 == "reach") { tx_accept++ }
        END { exit(outer_pre > 0 && tx_reject > 0 && tx_accept > 0 ? 0 : 1) }
    ' "$successor_policy_coverage" || return 1
    case "$successor_policy_scope" in
        pihole-web-health-unit-only)
            successor_policy_required_scenarios='outer-preflight web-unit-service-identity web-unit-candidate-tamper web-unit-accept outer-standby-first outer-reverse-rollback outer-evidence-readback outer-zero-residue'
            ;;
        notification-standardization-only)
            successor_policy_required_scenarios='outer-preflight notification-preflight notification-install notification-accept notification-candidate-tamper outer-standby-first outer-reverse-rollback outer-evidence-readback outer-zero-residue'
            ;;
        external-notification-attribution-read-only)
            successor_policy_required_scenarios='endpoint-only secret-bearing-evidence-rejection exact-legacy-title-search second-caller-attribution scheduled-job-attribution retained-replay-attribution multiple-candidate-ambiguity no-evidence-unattributed bounded-journal-selection zero-production-mutation outer-preflight exact-remote-cleanup evidence-readback-success evidence-readback-failure zero-production-mutation-outer'
            ;;
        controlled-serving-failure-exercise)
            successor_policy_required_scenarios='exercise-role-rejection exercise-service-control exercise-ownership-convergence exercise-journal-bounded exercise-lighttpd-pending-enqueue exercise-sampler-sigterm-lifecycle exercise-reverse-restoration outer-preflight outer-real-preflight outer-stale-preflight outer-full-scenario-sequence outer-restored-failure-non125 outer-acceptance-failure-non125 outer-causal-continuity-classification outer-bounded-convergence-retry outer-continuity-missing outer-continuity-duplicate outer-continuity-malformed outer-continuity-reordered outer-continuity-oversized outer-continuity-incomplete outer-continuity-symlinked outer-readback-cleanup'
            ;;
        *)
            successor_policy_required_scenarios='outer-preflight transaction-rejection transaction-acceptance protocol-v2-target-publication protocol-v2-target-promotion keepalived-daemon-owned-acceptance bounded-node-b-convergence node-a-quarantine-rollback protocol-namespace-state-equivalence'
            ;;
    esac
    for successor_policy_required_scenario in $successor_policy_required_scenarios; do
        awk -F '\t' -v scenario="$successor_policy_required_scenario" '
            NR > 1 && $1 == scenario { found++ }
            END { exit(found == 1 ? 0 : 1) }
        ' "$successor_policy_coverage" || return 1
    done
    # conditional-validator-explicit-failures-end
}

successor_policy_evidence_valid() {
    local successor_policy_evidence_root=$1
    local successor_policy_coverage=$2
    local successor_policy_entrypoint=$3
    local successor_policy_scenario successor_policy_expectation
    local successor_policy_decision_relative successor_policy_raw_relative
    local successor_policy_decision successor_policy_raw successor_policy_raw_hash
    local successor_policy_record_scenario successor_policy_record_expectation
    local successor_policy_status successor_policy_expected successor_policy_observed
    local successor_policy_record_raw_hash

    [[ -d "$successor_policy_evidence_root" && ! -L "$successor_policy_evidence_root" ]] || return 1
    [[ "$(stat -c '%a' "$successor_policy_evidence_root")" = 700 ]] || return 1
    [[ -d "$successor_policy_evidence_root/decisions" &&
        ! -L "$successor_policy_evidence_root/decisions" ]] || return 1
    [[ -d "$successor_policy_evidence_root/raw" &&
        ! -L "$successor_policy_evidence_root/raw" ]] || return 1
    [[ "$(stat -c '%a' "$successor_policy_evidence_root/decisions")" = 700 ]] || return 1
    [[ "$(stat -c '%a' "$successor_policy_evidence_root/raw")" = 700 ]] || return 1
    while IFS=$'\t' read -r successor_policy_scenario _ successor_policy_row_entrypoint \
        successor_policy_expectation successor_policy_decision_relative \
        successor_policy_raw_relative; do
        if [[ "$successor_policy_scenario" = scenario ||
            "$successor_policy_row_entrypoint" != "$successor_policy_entrypoint" ]]; then
            continue
        fi
        successor_policy_decision=$successor_policy_evidence_root/$successor_policy_decision_relative
        successor_policy_raw=$successor_policy_evidence_root/$successor_policy_raw_relative
        successor_policy_regular_file "$successor_policy_decision" || return 1
        successor_policy_regular_file "$successor_policy_raw" || return 1
        [[ "$(stat -c '%a' "$successor_policy_decision")" = 600 ]] || return 1
        [[ "$(stat -c '%a' "$successor_policy_raw")" = 600 ]] || return 1
        [[ "$(stat -c '%s' "$successor_policy_decision")" -le 4096 ]] || return 1
        [[ "$(stat -c '%s' "$successor_policy_raw")" -le 1048576 ]] || return 1
        iconv -f UTF-8 -t UTF-8 "$successor_policy_decision" >/dev/null || return 1
        iconv -f UTF-8 -t UTF-8 "$successor_policy_raw" >/dev/null || return 1
        ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' \
            "$successor_policy_decision" || return 1
        ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' \
            "$successor_policy_raw" || return 1
        [[ "$(sed -n '1p' "$successor_policy_decision")" = $'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256' ]] || return 1
        [[ "$(wc -l <"$successor_policy_decision")" -eq 2 ]] || return 1
        IFS=$'\t' read -r successor_policy_record_scenario \
            successor_policy_record_expectation successor_policy_status \
            successor_policy_expected successor_policy_observed \
            successor_policy_record_raw_hash < <(sed -n '2p' "$successor_policy_decision")
        [[ "$successor_policy_record_scenario" = "$successor_policy_scenario" ]] || return 1
        [[ "$successor_policy_record_expectation" = "$successor_policy_expectation" ]] || return 1
        [[ "$successor_policy_status" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] || return 1
        [[ -n "$successor_policy_expected" && -n "$successor_policy_observed" ]] || return 1
        [[ "$successor_policy_expected" != *$'\n'* && "$successor_policy_observed" != *$'\n'* ]] || return 1
        case "$successor_policy_expectation" in
            accept | reach)
                [[ "$successor_policy_status" -eq 0 ]] || return 1
                [[ "$successor_policy_expected" = "$successor_policy_observed" ]] || return 1
                ;;
            reject) [[ "$successor_policy_status" -ne 0 ]] || return 1 ;;
            *) return 1 ;;
        esac
        [[ "$successor_policy_record_raw_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
        successor_policy_raw_hash=$(sha256sum "$successor_policy_raw" | awk '{ print $1 }') || return 1
        [[ "$successor_policy_record_raw_hash" = "$successor_policy_raw_hash" ]] || return 1
    done <"$successor_policy_coverage"
    # Extra bounded evidence is allowed. The coverage registry names only the
    # causal decisions required for authorization.
}

successor_policy_defined_valid() {
    local successor_policy_action=$1
    local successor_policy_operation_spec=$2
    local successor_policy_transaction=$3
    local successor_policy_outer=$4
    local successor_policy_coverage=$5
    local successor_policy_regression=$6
    local successor_policy_transaction_output successor_policy_transaction_error
    local successor_policy_outer_output successor_policy_outer_error
    local successor_policy_probe_root successor_policy_transaction_evidence
    local successor_policy_outer_evidence
    local successor_policy_transaction_hash successor_policy_operation_hash
    local successor_policy_scope successor_policy_state_variant

    # conditional-validator-explicit-failures-begin
    [[ "$successor_policy_action" =~ ^[0-9]+[a-z0-9-]*$ ]] || return 1
    [[ "$successor_policy_operation_spec" = Caddy/manifests/serving-health-operation.yaml ]] || return 1
    [[ "$successor_policy_transaction" = Caddy/scripts/apply-serving-health-deployment.sh ]] || return 1
    [[ "$successor_policy_outer" = Caddy/scripts/run-serving-health-deployment-outer.sh ]] || return 1
    [[ "$successor_policy_coverage" =~ ^Caddy/manifests/[A-Za-z0-9._-]+\.tsv$ ]] || return 1
    [[ "$successor_policy_regression" =~ ^Caddy/tests/[A-Za-z0-9._-]+\.sh$ ]] || return 1
    [[ "${successor_policy_regression##*/}" != *action[0-9]* ]] || return 1
    successor_policy_regular_file "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
    successor_policy_executable_file "$successor_policy_transaction" || return 1
    successor_policy_executable_file "$successor_policy_outer" || return 1
    successor_policy_executable_file "$successor_policy_regression" || return 1
    successor_policy_transaction_hash=$(sha256sum \
        "$successor_policy_repository_root/$successor_policy_transaction" |
        awk '{ print $1 }') || return 1
    successor_policy_operation_hash=$(sha256sum \
        "$successor_policy_repository_root/$successor_policy_operation_spec" |
        awk '{ print $1 }') || return 1
    grep -Fxq "readonly transaction_sha256=$successor_policy_transaction_hash" \
        "$successor_policy_repository_root/$successor_policy_outer" || return 1
    grep -Fq "transaction_sha256: $successor_policy_transaction_hash" \
        "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
    grep -Fxq "readonly operation_sha256=$successor_policy_operation_hash" \
        "$successor_policy_repository_root/$successor_policy_outer" || return 1
    grep -Fxq "action: $successor_policy_action" \
        "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
    grep -Fxq 'status: defined-unexecuted' \
        "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
    successor_policy_scope=$(sed -n 's/^scope: //p' \
        "$successor_policy_repository_root/$successor_policy_operation_spec") || return 1
    case "$successor_policy_scope" in
        pihole-web-health-unit-only | notification-standardization-only | external-notification-attribution-read-only | controlled-serving-failure-exercise | full-serving-health) : ;;
        *) return 1 ;;
    esac
    case "$successor_policy_scope" in
        full-serving-health)
            grep -Fxq 'state_equivalence:' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '    - absent' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '    - protected-empty-directory' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            for successor_policy_state_variant in non-empty symlinked malformed \
                incorrect-owner incorrect-mode; do
                grep -Fxq "    - $successor_policy_state_variant" \
                    "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            done
            ;;
        pihole-web-health-unit-only)
            grep -Fxq 'SupplementaryGroups=caddy-tls' \
                "$successor_policy_repository_root/Caddy/systemd/caddy-pihole-web-health.service" || return 1
            grep -Fxq '  - service keeps User=pi and Group=pi with SupplementaryGroups=caddy-tls' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            ;;
        external-notification-attribution-read-only)
            grep -Fxq '  model: endpoint-list-only' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  credentials: prohibited-from-evidence' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  - no notification or test notification' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  - incomplete causal evidence reports unattributed' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            ;;
        controlled-serving-failure-exercise)
            grep -Fxq '  - changes no repository or node configuration artifact' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  - stops no service on both nodes simultaneously' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  - status 125 is reserved for recovery that cannot be proven after mutation' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  - synthetic production results or marker-only acceptance' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            ;;
        *)
            grep -Fxq '  - no Caddy, Pi-hole FTL, Unbound, lighttpd, or Keepalived restart or reload' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            grep -Fxq '  classification: external-producer-or-delivery-path' \
                "$successor_policy_repository_root/$successor_policy_operation_spec" || return 1
            ;;
    esac
    successor_policy_coverage_valid \
        "$successor_policy_repository_root/$successor_policy_coverage" \
        "$successor_policy_scope" || return 1
    awk -F '\t' -v path="$successor_policy_operation_spec" '
        $1 == path && $2 == "defined-unexecuted" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$successor_policy_repository_root/Caddy/manifests/manifest-lifecycle.tsv" || return 1
    grep -Fq -- '--production-path-test' "$successor_policy_repository_root/$successor_policy_transaction" || return 1
    grep -Fq -- '--production-path-test' "$successor_policy_repository_root/$successor_policy_outer" || return 1
    successor_policy_transaction_output=$(mktemp /tmp/caddy-successor-transaction-output.XXXXXX) || return 1
    successor_policy_transaction_error=$(mktemp /tmp/caddy-successor-transaction-error.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output"
        return 1
    }
    successor_policy_outer_output=$(mktemp /tmp/caddy-successor-outer-output.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error"
        return 1
    }
    successor_policy_outer_error=$(mktemp /tmp/caddy-successor-outer-error.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output"
        return 1
    }
    successor_policy_probe_root=$(mktemp -d /tmp/caddy-successor-production-evidence.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        return 1
    }
    successor_policy_transaction_evidence=$successor_policy_probe_root/transaction
    successor_policy_outer_evidence=$successor_policy_probe_root/outer
    install -d -m 0700 "$successor_policy_transaction_evidence" \
        "$successor_policy_outer_evidence" || return 1
    if ! CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$successor_policy_transaction_evidence \
        /bin/bash "$successor_policy_repository_root/$successor_policy_transaction" \
        --production-path-test >"$successor_policy_transaction_output" \
        2>"$successor_policy_transaction_error"; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    if [[ -s "$successor_policy_transaction_error" ]]; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    if ! CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$successor_policy_outer_evidence \
        /bin/bash "$successor_policy_repository_root/$successor_policy_outer" \
        --production-path-test >"$successor_policy_outer_output" \
        2>"$successor_policy_outer_error"; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    if [[ -s "$successor_policy_outer_error" ]]; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    if ! successor_policy_evidence_valid "$successor_policy_transaction_evidence" \
        "$successor_policy_repository_root/$successor_policy_coverage" transaction; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    if ! successor_policy_evidence_valid "$successor_policy_outer_evidence" \
        "$successor_policy_repository_root/$successor_policy_coverage" outer; then
        rm -f -- "$successor_policy_transaction_output" \
            "$successor_policy_transaction_error" "$successor_policy_outer_output" \
            "$successor_policy_outer_error"
        successor_policy_remove_probe_root "$successor_policy_probe_root"
        return 1
    fi
    rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
        "$successor_policy_outer_output" "$successor_policy_outer_error" || return 1
    successor_policy_remove_probe_root "$successor_policy_probe_root" || return 1
    /bin/bash "$successor_policy_repository_root/$successor_policy_regression" || return 1
    # conditional-validator-explicit-failures-end
}

successor_policy_registry_valid() {
    local successor_policy_require_defined=${1:-0}
    local successor_policy_schema successor_policy_status successor_policy_action
    local successor_policy_operation_spec successor_policy_transaction successor_policy_outer
    local successor_policy_state_relative successor_policy_state_hash successor_policy_coverage
    local successor_policy_regression successor_policy_state

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_registry" || return 1
    [[ "$(sed -n '1p' "$successor_policy_registry")" = $'schema_version\tstatus\taction\toperation_spec\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' ]] || return 1
    [[ "$(wc -l <"$successor_policy_registry")" -eq 2 ]] || return 1
    IFS=$'\t' read -r successor_policy_schema successor_policy_status successor_policy_action \
        successor_policy_operation_spec successor_policy_transaction successor_policy_outer \
        successor_policy_state_relative successor_policy_state_hash successor_policy_coverage \
        successor_policy_regression < <(sed -n '2p' "$successor_policy_registry")
    [[ "$successor_policy_schema" = 2 ]] || return 1
    [[ "$successor_policy_state_relative" = Caddy/manifests/current-live-state.tsv ]] || return 1
    [[ "$successor_policy_coverage" = Caddy/manifests/deployable-successor-coverage.tsv ]] || return 1
    [[ "$successor_policy_state_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    successor_policy_state=$successor_policy_repository_root/$successor_policy_state_relative
    successor_policy_state_valid "$successor_policy_state" || return 1
    successor_policy_regular_file "$successor_policy_repository_root/$successor_policy_coverage" || return 1
    [[ "$(sed -n '1p' "$successor_policy_repository_root/$successor_policy_coverage")" = $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' ]] || return 1
    [[ "$successor_policy_state_hash" = "$(sha256sum "$successor_policy_state" | awk '{ print $1 }')" ]] || return 1
    case "$successor_policy_status" in
        none)
            [[ "$successor_policy_require_defined" = 0 ]] || return 1
            [[ "$successor_policy_action" = - && "$successor_policy_operation_spec" = - ]] || return 1
            [[ "$successor_policy_transaction" = - && "$successor_policy_outer" = - ]] || return 1
            [[ "$successor_policy_regression" = - ]] || return 1
            [[ "$(wc -l <"$successor_policy_repository_root/$successor_policy_coverage")" -eq 1 ]] || return 1
            successor_policy_inactive_valid || return 1
            ;;
        defined)
            successor_policy_defined_valid "$successor_policy_action" \
                "$successor_policy_operation_spec" "$successor_policy_transaction" \
                "$successor_policy_outer" "$successor_policy_coverage" \
                "$successor_policy_regression" || return 1
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        if [[ "$successor_policy_repository_root" = "$successor_policy_default_root" ]]; then
            successor_policy_check neutral_entrypoints_real \
                successor_policy_neutral_entrypoints_are_real || exit 1
        fi
        successor_policy_check registry successor_policy_registry_valid 0 || exit 1
        printf '%s_complete=true\n' "$successor_policy_prefix"
        ;;
    --authorization-ready)
        [[ $# -eq 1 ]] || exit 64
        if [[ "$successor_policy_repository_root" = "$successor_policy_default_root" ]]; then
            successor_policy_check neutral_entrypoints_real \
                successor_policy_neutral_entrypoints_are_real || exit 1
        fi
        successor_policy_check authorization_ready successor_policy_registry_valid 1 || exit 1
        printf '%s_complete=true\n' "$successor_policy_prefix"
        ;;
    *)
        printf 'Usage: %s --check|--authorization-ready\n' "${0##*/}" >&2
        exit 64
        ;;
esac
