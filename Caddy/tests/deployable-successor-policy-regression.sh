#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=deployable_successor_policy_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly policy=$test_directory/deployable-successor-policy.sh
root=$(mktemp -d /tmp/caddy-successor-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT INT TERM

check() {
    local label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$label" >&2
    return 1
}

run_fixture() {
    CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$root \
        /bin/bash "$policy" --check >/dev/null 2>&1
}

fixture_rejected() {
    ! run_fixture
}

install -d -m 0700 "$root/Caddy/manifests" "$root/Caddy/scripts"
install -m 0600 \
    "$repository_root/Caddy/manifests/accepted-live-artifacts.tsv" \
    "$repository_root/Caddy/manifests/current-live-state.tsv" \
    "$repository_root/Caddy/manifests/production-artifacts.tsv" \
    "$repository_root/Caddy/manifests/runtime-production.tsv" \
    "$root/Caddy/manifests/"
install -m 0600 "$repository_root/Caddy/manifests/serving-health-operation.yaml" \
    "$root/Caddy/manifests/serving-health-operation.yaml"
install -m 0700 \
    "$repository_root/Caddy/scripts/apply-serving-health-deployment.sh" \
    "$repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh" \
    "$root/Caddy/scripts/"
printf '%s\n' \
    $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' \
    >"$root/Caddy/manifests/deployable-successor-coverage.tsv"
state_hash=$(sha256sum "$root/Caddy/manifests/current-live-state.tsv" | awk '{ print $1 }')
readonly state_hash
printf '%s\n' \
    $'schema_version\tstatus\taction\toperation_spec\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
    "2"$'\t'"none"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"-" \
    >"$root/Caddy/manifests/deployable-successor.tsv"

check clean_registry_accepts run_fixture || exit 1

sed -i 's/^action: none$/action: stale/' \
    "$root/Caddy/manifests/serving-health-operation.yaml"
check inactive_operation_rejected fixture_rejected || exit 1
install -m 0600 "$repository_root/Caddy/manifests/serving-health-operation.yaml" \
    "$root/Caddy/manifests/serving-health-operation.yaml"

sed -i 's/^readonly operation_sha256=/readonly operation_sha256=0/' \
    "$root/Caddy/scripts/run-serving-health-deployment-outer.sh"
check inactive_operation_pin_rejected fixture_rejected || exit 1
install -m 0700 "$repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh" \
    "$root/Caddy/scripts/run-serving-health-deployment-outer.sh"

sed -i '2s/^2/1/' "$root/Caddy/manifests/deployable-successor.tsv"
check obsolete_schema_rejected fixture_rejected || exit 1
sed -i '2s/^1/2/' "$root/Caddy/manifests/deployable-successor.tsv"

sed -i '2s/\tnone\t-\t-/\tdefined\t35ag\tCaddy\/manifests\/action35ag.yaml/' \
    "$root/Caddy/manifests/deployable-successor.tsv"
check action_numbered_spec_rejected fixture_rejected || exit 1

check neutral_transaction_required \
    grep -Fq 'Caddy/scripts/apply-serving-health-deployment.sh' "$policy" || exit 1
check neutral_outer_required \
    grep -Fq 'Caddy/scripts/run-serving-health-deployment-outer.sh' "$policy" || exit 1
check operation_hash_required grep -Fq 'readonly operation_sha256=' "$policy" || exit 1
check state_equivalence_contract_required \
    grep -Fq 'protocol-namespace-state-equivalence' "$policy" || exit 1
check protected_empty_state_required \
    grep -Fq 'protected-empty-directory' "$policy" || exit 1
check proportional_coverage \
    grep -Fq 'Extra bounded evidence is allowed' "$policy" || exit 1
forbidden_generator=successor_regression_write_entrypoint
check fabricated_entrypoint_absent \
    test -z "$(grep -F "$forbidden_generator()" "$0" || :)" || exit 1
check neutral_real_entrypoint_policy \
    grep -Fq 'successor_policy_neutral_entrypoints_are_real' "$policy" || exit 1
check fabricated_availability_policy \
    grep -Fq 'availability\.tsv' "$policy" || exit 1
check fabricated_journal_policy \
    grep -Fq 'exercise_.*_journal\.stdout' "$policy" || exit 1
# shellcheck disable=SC2016
check mode_dispatch_policy \
    grep -Fq 'case "$mode" in' "$policy" || exit 1

printf '%s_complete=true\n' "$prefix"
