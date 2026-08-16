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

successor_regression_rejected() {
    ! CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
        /bin/bash "$successor_regression_policy" --check >/dev/null 2>&1
}

successor_regression_authorization_rejected() {
    ! CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
        /bin/bash "$successor_regression_policy" --authorization-ready >/dev/null 2>&1
}

successor_regression_write_registry() {
    local successor_regression_state_hash
    local successor_regression_regression=${1:-Caddy/tests/durable-apprise-deployment-regression.sh}

    successor_regression_state_hash=$(sha256sum "$successor_regression_root/Caddy/manifests/current-live-state.tsv" | awk '{ print $1 }')
    printf '%s\n' \
        $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
        "1"$'\t'"defined"$'\t'"999z"$'\t'"Caddy/manifests/deployable-successor-fixture.yaml"$'\t'"Caddy/scripts/apply-durable-apprise-current.sh"$'\t'"Caddy/scripts/run-dual-node-durable-apprise-current-outer.sh"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$successor_regression_state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"$successor_regression_regression" \
        >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
}

/bin/bash "$successor_regression_policy" --check >/dev/null
successor_regression_check current_none_contract true || exit 1
successor_regression_check current_none_authorization_rejected \
    successor_regression_authorization_rejected || exit 1

install -d -m 0700 \
    "$successor_regression_root/Caddy/manifests" \
    "$successor_regression_root/Caddy/scripts" \
    "$successor_regression_root/Caddy/tests"
printf 'accepted-live fixture\n' >"$successor_regression_root/Caddy/manifests/accepted-live-artifacts.tsv"
printf 'runtime fixture\n' >"$successor_regression_root/Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv"
successor_regression_accepted_hash=$(sha256sum "$successor_regression_root/Caddy/manifests/accepted-live-artifacts.tsv" | awk '{ print $1 }')
successor_regression_runtime_hash=$(sha256sum "$successor_regression_root/Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv" | awk '{ print $1 }')
printf '%s\n' \
    $'schema_version\tscope\tkey\tvalue\tevidence' \
    "1"$'\t'"cluster"$'\t'"accepted-live-artifacts-sha256"$'\t'"$successor_regression_accepted_hash"$'\t'"fixture" \
    "1"$'\t'"cluster"$'\t'"runtime-baseline-sha256"$'\t'"$successor_regression_runtime_hash"$'\t'"fixture" \
    $'1\tnode-a\townership\tipv4-master,ipv6-master,shared-vips=4\tfixture' \
    $'1\tnode-a\tservices\tcaddy=active,lsyncd=active,reconcile-path=active,keepalived=active\tfixture' \
    $'1\tnode-a\trelease\taction32g-exact\tfixture' \
    $'1\tnode-a\tdurable-apprise-installation\tabsent\tfixture' \
    $'1\tnode-a\tapprise-queue\tabsent\tfixture' \
    $'1\tnode-b\townership\tipv4-backup,ipv6-backup,shared-vips=0\tfixture' \
    $'1\tnode-b\tservices\tcaddy=active,lsyncd=active,reconcile-path=active,keepalived=active\tfixture' \
    $'1\tnode-b\trelease\taction32g-exact\tfixture' \
    $'1\tnode-b\tdurable-apprise-installation\tabsent\tfixture' \
    $'1\tnode-b\tapprise-queue\tabsent\tfixture' \
    >"$successor_regression_root/Caddy/manifests/current-live-state.tsv"

printf '%s\n' \
    $'scenario\tphase\tentrypoint\texpectation\tmarker' \
    $'node-b-queue-absent\tpre-mutation\ttransaction\taccept\tproduction_path_node_b_queue_absent' \
    $'node-b-exact-two-records\tpre-mutation\ttransaction\taccept\tproduction_path_node_b_exact_two_records' \
    $'node-b-one-record\tpre-mutation\ttransaction\treject\tproduction_path_node_b_one_record_rejected' \
    $'node-b-extra-record\tpre-mutation\ttransaction\treject\tproduction_path_node_b_extra_record_rejected' \
    $'node-b-unsafe-metadata\tpre-mutation\ttransaction\treject\tproduction_path_node_b_unsafe_metadata_rejected' \
    $'node-b-symlink\tpre-mutation\ttransaction\treject\tproduction_path_node_b_symlink_rejected' \
    $'node-b-malformed-record\tpre-mutation\ttransaction\treject\tproduction_path_node_b_malformed_record_rejected' \
    $'node-a-queue-absent\tpre-mutation\ttransaction\taccept\tproduction_path_node_a_queue_absent' \
    $'outer-production-entrypoint\tpre-mutation\touter\treach\tproduction_path_outer_dispatch_entry' \
    $'payload-construction\tpre-mutation\touter\treach\tproduction_path_outer_payload_constructed' \
    $'remote-path-generation\tpre-mutation\touter\treach\tproduction_path_outer_remote_path_generated' \
    $'upload-prepare\tpre-mutation\touter\treach\tproduction_path_outer_upload_prepare' \
    $'upload-accept\tpre-mutation\touter\treach\tproduction_path_outer_upload_accept' \
    $'upload-disposition\tpre-mutation\touter\treach\tproduction_path_outer_upload_disposition' \
    $'remote-command-construction\tpre-mutation\touter\treach\tproduction_path_outer_remote_command_constructed' \
    $'transaction-dispatch\tpre-mutation\touter\treach\tproduction_path_outer_transaction_dispatched' \
    $'stdin-transaction-dispatch\tpre-mutation\touter\treach\tproduction_path_outer_stdin_transaction_dispatched' \
    $'payload-validation\taccepted-path\ttransaction\treach\tproduction_path_payload_validation_reached' \
    $'mutation-boundary\taccepted-path\ttransaction\treach\tproduction_path_mutation_boundary_reached' \
    $'production-entrypoint\taccepted-path\ttransaction\treach\tproduction_path_dispatch_entry' \
    >"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
printf '%s\n' 'schema_version: 1' 'action: 999z' 'status: definition-only' \
    >"$successor_regression_root/Caddy/manifests/deployable-successor-fixture.yaml"
printf '%s\n' \
    $'# path\tlifecycle\tdeployable\tauthority' \
    $'Caddy/manifests/deployable-successor-fixture.yaml\tdefined-unexecuted\tno\tCaddy/docs/caddy_plan-v1.1.md' \
    >"$successor_regression_root/Caddy/manifests/manifest-lifecycle.tsv"

successor_regression_transaction=$successor_regression_root/Caddy/scripts/apply-durable-apprise-current.sh
# The generated fixture must retain child-shell parameter expansion literally.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    '[[ "${1:-}" = --production-path-test ]] || exit 64' \
    'printf "%s=true\n" production_path_dispatch_entry production_path_node_b_queue_absent production_path_node_b_exact_two_records production_path_node_b_one_record_rejected production_path_node_b_extra_record_rejected production_path_node_b_unsafe_metadata_rejected production_path_node_b_symlink_rejected production_path_node_b_malformed_record_rejected production_path_node_a_queue_absent production_path_payload_validation_reached production_path_mutation_boundary_reached' \
    >"$successor_regression_transaction"
chmod 0755 "$successor_regression_transaction"
cp "$successor_regression_transaction" "$successor_regression_transaction.good"

successor_regression_test=$successor_regression_root/Caddy/tests/durable-apprise-deployment-regression.sh
# The generated fixture must retain child-shell path expansion literally.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'root=${0%/Caddy/tests/*}' \
    'registry=$root/Caddy/manifests/deployable-successor.tsv' \
    'IFS=$'"'"'\t'"'"' read -r _ _ _ _ relative _ _ _ _ _ < <(sed -n '"'"'2p'"'"' "$registry")' \
    'transaction=$root/$relative' \
    '/bin/bash "$transaction" --production-path-test >/dev/null' \
    >"$successor_regression_test"
chmod 0755 "$successor_regression_test"

successor_regression_outer=$successor_regression_root/Caddy/scripts/run-dual-node-durable-apprise-current-outer.sh
# The fixture separates its offline production path from its policy-bearing live path.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'if [[ "${1:-}" = --production-path-test ]]; then' \
    '    evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?}' \
    '    printf "%064d\n" 0 >"$evidence/payload.sha256"' \
    '    printf "%s\n" /tmp/caddy-successor-fixture/payload.tar >"$evidence/remote-path"' \
    '    printf "prepare\\t0\\naccept\\t0\\ndisposition\\t0\\n" >"$evidence/upload-events.tsv"' \
    '    printf "%s\n" "/bin/bash /tmp/caddy-successor-fixture/payload.tar --apply" >"$evidence/remote-command.argv"' \
    '    printf "0\n" >"$evidence/transaction.status"' \
    '    printf "0\n" >"$evidence/mutation-count"' \
    '    chmod 0600 "$evidence"/*' \
    '    printf "%s=true\n" production_path_outer_dispatch_entry production_path_outer_payload_constructed production_path_outer_remote_path_generated production_path_outer_upload_prepare production_path_outer_upload_accept production_path_outer_upload_disposition production_path_outer_remote_command_constructed production_path_outer_transaction_dispatched production_path_outer_stdin_transaction_dispatched' \
    '    exit 0' \
    'fi' \
    '/bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready' \
    '/bin/bash Caddy/tests/durable-apprise-deployment-regression.sh' \
    >"$successor_regression_outer"
chmod 0755 "$successor_regression_outer"

successor_regression_write_registry
CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
    CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
    /bin/bash "$successor_regression_policy" --check >/dev/null
successor_regression_check complete_defined_contract true || exit 1
CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
    CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$successor_regression_root \
    /bin/bash "$successor_regression_policy" --authorization-ready >/dev/null
successor_regression_check defined_authorization_ready true || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor.tsv" \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.good"
sed 's/[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.good" \
    >"$successor_regression_root/Caddy/manifests/deployable-successor.tsv"
successor_regression_check stale_state_rejected successor_regression_rejected || exit 1
cp "$successor_regression_root/Caddy/manifests/deployable-successor.tsv.good" \
    "$successor_regression_root/Caddy/manifests/deployable-successor.tsv"

cp "$successor_regression_test" \
    "$successor_regression_root/Caddy/tests/durable-apprise-action999z-regression.sh"
chmod 0755 "$successor_regression_root/Caddy/tests/durable-apprise-action999z-regression.sh"
successor_regression_write_registry Caddy/tests/durable-apprise-action999z-regression.sh
successor_regression_check action_named_current_regression_rejected successor_regression_rejected || exit 1
successor_regression_write_registry

cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.good"
sed '/node-b-one-record/d' \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.good" \
    >"$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
successor_regression_check incomplete_matrix_rejected successor_regression_rejected || exit 1
cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.good" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"

sed '/production_path_node_b_one_record_rejected/d' "$successor_regression_transaction" \
    >"$successor_regression_transaction.incomplete"
mv "$successor_regression_transaction.incomplete" "$successor_regression_transaction"
chmod 0755 "$successor_regression_transaction"
successor_regression_check generated_path_missing_marker_rejected successor_regression_rejected || exit 1

cp "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv.good" \
    "$successor_regression_root/Caddy/manifests/deployable-successor-coverage.tsv"
cp "$successor_regression_transaction.good" "$successor_regression_transaction"
chmod 0755 "$successor_regression_transaction"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$successor_regression_outer"
chmod 0755 "$successor_regression_outer"
successor_regression_check outer_production_path_missing_rejected successor_regression_rejected || exit 1

printf '%s_complete=true\n' "$successor_regression_prefix"
