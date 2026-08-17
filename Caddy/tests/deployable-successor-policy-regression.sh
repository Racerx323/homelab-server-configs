#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly successor_regression_prefix=deployable_successor_policy_regression
successor_regression_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly successor_regression_test_directory
readonly successor_regression_repository_root=${successor_regression_test_directory%/Caddy/tests}
readonly successor_regression_policy=$successor_regression_test_directory/deployable-successor-policy.sh
successor_regression_root=$(mktemp -d /tmp/caddy-successor-regression.XXXXXX)
readonly successor_regression_root
successor_regression_fixture_mode=normal
trap 'rm -rf -- "$successor_regression_root"' EXIT INT TERM

successor_regression_check() {
    local successor_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$successor_regression_prefix" "$successor_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$successor_regression_prefix" \
        "$successor_regression_label" >&2
    return 1
}

successor_regression_policy_accepts() {
    SUCCESSOR_POLICY_FIXTURE_MODE=$successor_regression_fixture_mode \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
        /bin/bash "$successor_regression_policy" --authorization-ready >/dev/null 2>&1
}

successor_regression_policy_rejects() {
    ! successor_regression_policy_accepts
}

successor_regression_write_registry() {
    local successor_regression_status=$1
    local successor_regression_state_hash

    successor_regression_state_hash=$(sha256sum \
        "$successor_regression_root/Caddy/manifests/current-live-state.tsv" |
        awk '{ print $1 }') || return 1
    if [[ "$successor_regression_status" = none ]]; then
        printf '%s\n' \
            $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
            "1"$'\t'"none"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$successor_regression_state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"-" \
            >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
        return
    fi
    printf '%s\n' \
        $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
        "1"$'\t'"defined"$'\t'"99z"$'\t'"Caddy/manifests/action99z.yaml"$'\t'"Caddy/scripts/apply-action99z.sh"$'\t'"Caddy/scripts/run-action99z-outer.sh"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$successor_regression_state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"Caddy/tests/current-successor-regression.sh" \
        >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
}

successor_regression_write_coverage() {
    local successor_regression_key

    printf '%s\n' \
        $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' \
        $'outer-preflight\tpre-mutation\touter\treach\tdecisions/outer-preflight.tsv\traw/outer-preflight.txt' \
        $'transaction-rejection\tpre-mutation\ttransaction\treject\tdecisions/transaction-rejection.tsv\traw/transaction-rejection.txt' \
        $'transaction-acceptance\taccepted-path\ttransaction\treach\tdecisions/transaction-acceptance.tsv\traw/transaction-acceptance.txt' \
        $'evidence-readback-node-a-success\taccepted-path\touter\taccept\tdecisions/evidence-readback-node-a-success.tsv\traw/evidence-readback-node-a-success.txt' \
        $'evidence-readback-node-a-failure\tpre-mutation\touter\treject\tdecisions/evidence-readback-node-a-failure.tsv\traw/evidence-readback-node-a-failure.txt' \
        $'evidence-readback-node-b-success\taccepted-path\touter\taccept\tdecisions/evidence-readback-node-b-success.tsv\traw/evidence-readback-node-b-success.txt' \
        $'evidence-readback-node-b-failure\tpre-mutation\touter\treject\tdecisions/evidence-readback-node-b-failure.tsv\traw/evidence-readback-node-b-failure.txt' \
        >"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
    while IFS=$'\t' read -r successor_regression_key _; do
        if [[ "$successor_regression_key" = '# key' ]]; then
            continue
        fi
        printf 'inventory-%s\tpre-mutation\ttransaction\taccept\tdecisions/inventory-%s.tsv\traw/inventory-%s.txt\n' \
            "$successor_regression_key" "$successor_regression_key" \
            "$successor_regression_key"
    done <"$successor_regression_root/Caddy/manifests/production-artifacts.tsv" \
        >>"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
}

successor_regression_write_entrypoint() {
    local successor_regression_path=$1
    local successor_regression_entrypoint=$2

    # The single-quoted fields are the generated entrypoint, not expressions
    # for this regression process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'umask 077' \
        '[[ "${1:-}" = --production-path-test && $# -eq 1 ]] || exit 64' \
        'readonly evidence_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?}' \
        "readonly entrypoint=$successor_regression_entrypoint" \
        'readonly repository_root='"$successor_regression_root" \
        'readonly coverage=$repository_root/Caddy/manifests/deployable-successor-coverage.tsv' \
        'readonly fixture_mode=${SUCCESSOR_POLICY_FIXTURE_MODE:-normal}' \
        'if [[ "$fixture_mode" = marker-only ]]; then' \
        '    awk -F '\''\t'\'' -v entrypoint="$entrypoint" '\''NR > 1 && $3 == entrypoint { print $1 "=true" }'\'' "$coverage"' \
        '    exit 0' \
        'fi' \
        'install -d -m 0700 "$evidence_root/decisions" "$evidence_root/raw"' \
        'while IFS=$'\''\t'\'' read -r scenario _ row_entrypoint expectation decision_relative raw_relative; do' \
        '    [[ "$scenario" != scenario && "$row_entrypoint" = "$entrypoint" ]] || continue' \
        '    status=0' \
        '    [[ "$expectation" != reject ]] || status=1' \
        '    raw=$evidence_root/$raw_relative' \
        '    decision=$evidence_root/$decision_relative' \
        '    printf '\''entrypoint=%s\nscenario=%s\nstatus=%s\n'\'' "$entrypoint" "$scenario" "$status" >"$raw"' \
        '    raw_hash=$(sha256sum "$raw" | awk '\''{ print $1 }'\'')' \
        '    printf '\''scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\tstatus:%s\tstatus:%s\t%s\n'\'' "$scenario" "$expectation" "$status" "$status" "$status" "$raw_hash" >"$decision"' \
        'done <"$coverage"' \
        'if [[ "$fixture_mode" = corrupt-raw ]]; then' \
        '    first_raw=$(find "$evidence_root/raw" -mindepth 1 -maxdepth 1 -type f -print -quit)' \
        '    printf '\''corruption\n'\'' >>"$first_raw"' \
        'fi' \
        >"$successor_regression_path"
    chmod 0755 "$successor_regression_path"
}

/bin/bash "$successor_regression_policy" --check >/dev/null
successor_regression_check current_none_contract true || exit 1
successor_regression_check current_none_authorization_rejected \
    successor_regression_policy_rejects || exit 1

install -d -m 0700 "$successor_regression_root/Caddy/manifests" \
    "$successor_regression_root/Caddy/scripts" "$successor_regression_root/Caddy/tests"
install -m 0600 \
    "$successor_regression_repository_root/Caddy/manifests/accepted-live-artifacts.tsv" \
    "$successor_regression_repository_root/Caddy/manifests/current-live-state.tsv" \
    "$successor_regression_repository_root/Caddy/manifests/production-artifacts.tsv" \
    "$successor_regression_repository_root/Caddy/manifests/runtime-production.tsv" \
    "$successor_regression_root/Caddy/manifests/"

successor_regression_write_coverage
successor_regression_write_entrypoint \
    "$successor_regression_root/Caddy/scripts/apply-action99z.sh" transaction
transaction_hash=$(sha256sum \
    "$successor_regression_root/Caddy/scripts/apply-action99z.sh" | awk '{ print $1 }')
readonly transaction_hash
successor_regression_write_entrypoint \
    "$successor_regression_root/Caddy/scripts/run-action99z-outer.sh" outer
sed -i "3ireadonly transaction_sha256=$transaction_hash" \
    "$successor_regression_root/Caddy/scripts/run-action99z-outer.sh"
printf 'transaction_sha256: %s\n' "$transaction_hash" \
    >"$successor_regression_root/Caddy/manifests/action99z.yaml"
printf '%s\n' \
    $'path\tlifecycle\tdeployable\tauthority' \
    $'Caddy/manifests/action99z.yaml\tdefined-unexecuted\tyes\tfixture' \
    >"$successor_regression_root/Caddy/manifests/manifest-lifecycle.tsv"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
    '[[ $# -eq 0 ]]' >"$successor_regression_root/Caddy/tests/current-successor-regression.sh"
chmod 0755 "$successor_regression_root/Caddy/tests/current-successor-regression.sh"
successor_regression_write_registry defined

successor_regression_check complete_causal_evidence_accepts \
    successor_regression_policy_accepts || exit 1

successor_regression_fixture_mode=marker-only
successor_regression_check marker_only_rejected successor_regression_policy_rejects || exit 1

successor_regression_fixture_mode=corrupt-raw
successor_regression_check noncausal_hash_rejected successor_regression_policy_rejects || exit 1
successor_regression_fixture_mode=normal

cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.complete"
sed -i '/^inventory-node_a_health_helper\t/d' \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_check incomplete_inventory_rejected \
    successor_regression_policy_rejects || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.complete" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
sed -i '/^evidence-readback-node-b-failure\t/d' \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_check incomplete_readback_rejected \
    successor_regression_policy_rejects || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.complete" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_write_registry none
successor_regression_check none_with_coverage_rejected \
    successor_regression_policy_rejects || exit 1

printf '%s_complete=true\n' "$successor_regression_prefix"
