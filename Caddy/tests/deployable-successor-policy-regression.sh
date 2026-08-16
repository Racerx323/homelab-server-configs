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
trap 'rm -rf -- "$successor_regression_root"' EXIT INT TERM

successor_regression_check() {
    local successor_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$successor_regression_prefix" "$successor_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$successor_regression_prefix" "$successor_regression_label" >&2
    return 1
}

successor_regression_policy_accepts_check() {
    CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
        /bin/bash "$successor_regression_policy" --check >/dev/null 2>&1
}

successor_regression_policy_rejects_check() {
    ! successor_regression_policy_accepts_check
}

successor_regression_policy_rejects_authorization() {
    ! CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
        /bin/bash "$successor_regression_policy" --authorization-ready >/dev/null 2>&1
}

successor_regression_restore_none_registry() {
    local successor_regression_state_hash

    successor_regression_state_hash=$(sha256sum \
        "$successor_regression_root/Caddy/manifests/current-live-state.tsv" |
        awk '{ print $1 }') || return 1
    printf '%s\n' \
        $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
        "1"$'\t'"none"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$successor_regression_state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"-" \
        >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
}

/bin/bash "$successor_regression_policy" --check >/dev/null
successor_regression_check current_none_contract true || exit 1
if /bin/bash "$successor_regression_policy" --authorization-ready >/dev/null 2>&1; then
    printf '%s_check_current_none_authorization_rejected=false\n' \
        "$successor_regression_prefix" >&2
    exit 1
fi
printf '%s_check_current_none_authorization_rejected=true\n' "$successor_regression_prefix"

install -d -m 0700 "$successor_regression_root/Caddy/manifests"
install -m 0600 \
    "$successor_regression_repository_root/Caddy/manifests/accepted-live-artifacts.tsv" \
    "$successor_regression_repository_root/Caddy/manifests/current-live-state.tsv" \
    "$successor_regression_repository_root/Caddy/manifests/runtime-production.tsv" \
    "$successor_regression_root/Caddy/manifests/"
printf '%s\n' $'scenario\tphase\tentrypoint\texpectation\tmarker' \
    >"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_restore_none_registry

successor_regression_check isolated_none_contract \
    successor_regression_policy_accepts_check || exit 1
successor_regression_check isolated_none_authorization_rejected \
    successor_regression_policy_rejects_authorization || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor.tsv" \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.accepted"
sed 's/[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.accepted" \
    >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
successor_regression_check stale_state_rejected \
    successor_regression_policy_rejects_check || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.accepted" \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
printf '%s\n' \
    $'unexpected\tpre-mutation\touter\treach\tunexpected_marker' \
    >>"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_check none_with_coverage_rejected \
    successor_regression_policy_rejects_check || exit 1

printf '%s\n' $'scenario\tphase\tentrypoint\texpectation\tmarker' \
    >"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
printf '%s\n' \
    $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
    $'1\tdefined\t35a\t-\t-\t-\tCaddy/manifests/current-live-state.tsv\t0000000000000000000000000000000000000000000000000000000000000000\tCaddy/manifests/deployable-successor-coverage.tsv\t-' \
    >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
successor_regression_check incomplete_defined_successor_rejected \
    successor_regression_policy_rejects_check || exit 1

successor_regression_restore_none_registry
printf '%s\n' 'unexpected-third-row' \
    >>"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
successor_regression_check extra_registry_row_rejected \
    successor_regression_policy_rejects_check || exit 1

printf '%s_complete=true\n' "$successor_regression_prefix"
