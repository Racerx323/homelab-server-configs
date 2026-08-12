#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-caddy-runtime-lifecycle-action32d.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-lifecycle-action32d-outer.sh
readonly consumed=$caddy_root/scripts/apply-caddy-runtime-lifecycle-action32.sh
fixture_root=
definitions=
payload_root=
payload_archive=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+rwX "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM

require_literal() {
    local action32d_regression_literal=$1
    local action32d_regression_file=$2

    grep -Fq -- "$action32d_regression_literal" "$action32d_regression_file"
}

line_number() {
    local action32d_regression_literal=$1
    local action32d_regression_file=$2

    awk -v wanted="$action32d_regression_literal" \
        'index($0, wanted) { print NR; found++ } END { if (found != 1) exit 1 }' \
        "$action32d_regression_file"
}

make_release() {
    local action32d_regression_path=$1
    local action32d_regression_revision=$2
    local action32d_regression_parent=${3:-parent}

    install -d -m 0700 "$action32d_regression_path"
    printf ':80 { respond "fixture" }\n' >"$action32d_regression_path/Caddyfile"
    printf '{"parent_revision":"%s","revision":"%s","source_node":"node-a"}\n' \
        "$action32d_regression_parent" "$action32d_regression_revision" \
        >"$action32d_regression_path/release-manifest.json"
    (
        cd "$action32d_regression_path"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    : >"$action32d_regression_path/.finalize-request"
    : >"$action32d_regression_path/.complete"
    find "$action32d_regression_path" -type d -exec chmod 0550 {} +
    find "$action32d_regression_path" -type f -exec chmod 0440 {} +
}

fixture_root=$(mktemp -d /tmp/caddy-action32d-regression.XXXXXX)
chmod 0700 "$fixture_root"
definitions=$fixture_root/transaction-definitions.sh
sed '/^mode=${1:-}/,$d' "$transaction" >"$definitions"
# shellcheck disable=SC1090
source "$definitions"

payload_root=$fixture_root/payload
payload_archive=$fixture_root/payload.tar
install -d -m 0700 "$payload_root/Caddy/scripts"
install -m 0600 "$consumed" \
    "$payload_root/Caddy/scripts/apply-caddy-runtime-lifecycle-action32.sh"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --format=ustar -cf "$payload_archive" -C "$payload_root" .
successor_prepare_base "$payload_archive" \
    "$(sha256sum "$payload_archive" | awk '{ print $1 }')"
declare -f capture_semantic_state >"$fixture_root/capture-definition"
declare -f no_finalized_candidate >"$fixture_root/drain-definition"
grep -Fq 'finalized_candidate_semantics inspect_finalized_candidate' \
    "$fixture_root/capture-definition"
grep -Fq 'finalized_candidate_drained_by_corrected_reconciler=true' \
    "$fixture_root/drain-definition"
if grep -Fq 'check no_finalized_candidate no_finalized_candidate' \
    "$fixture_root/capture-definition"; then
    printf 'action32d_regression_base_overrode_successor=true\n' >&2
    exit 1
fi

successor_incoming_root=$fixture_root/incoming
successor_current_link=$fixture_root/current
successor_releases_root=$fixture_root/releases
successor_quarantine_root=$fixture_root/quarantine
successor_environment_file=$fixture_root/caddy-ha.env
successor_caddy_binary=$fixture_root/mock-caddy
capture_directory=$fixture_root/captures
node_token=node_b
install -d -m 0700 "$capture_directory"
printf 'NODE_FQDN=j1-svpihole00\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n' \
    >"$successor_environment_file"
cat >"$successor_caddy_binary" <<'MOCK_CADDY'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${CADDY_CONFIG_ROOT:-}" == */incoming/node-a/revision-* ]]
[[ "${NODE_FQDN:-}" = j1-svpihole00 ]]
[[ "${NODE_IPV4:-}" = 10.1.0.54 ]]
[[ "${NODE_IPV6:-}" = fd36:5aa8:6971:1::54 ]]
[[ "$*" = 'validate --config '*'/Caddyfile --adapter caddyfile' ]]
printf 'mock_caddy_environment_complete=true\n'
MOCK_CADDY
chmod 0700 "$successor_caddy_binary"
install -d -m 0700 "$successor_incoming_root/node-a" \
    "$fixture_root/releases" "$successor_quarantine_root"
: >"$successor_incoming_root/.reconcile-trigger"
make_release "$fixture_root/releases/revision-current" revision-current
ln -s "$fixture_root/releases/revision-current" "$successor_current_link"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"
make_release "$successor_incoming_root/node-a/revision-old" revision-old
cp -a "$successor_incoming_root/node-a/revision-old" \
    "$successor_quarantine_root/node-a-revision-old"

role=node-b
inspect_finalized_candidate >"$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_count=2' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_active_replay_count=1' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_quarantine_replay_count=1' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_disposition=consume-active-then-discard-quarantine-replay' \
    "$fixture_root/exact.stdout"
grep -Fxq 'observed_candidate_1_disposition=consume_exact_active_replay' \
    "$fixture_root/exact.stdout"
grep -Fxq 'observed_candidate_2_disposition=discard_exact_quarantine_replay' \
    "$fixture_root/exact.stdout"
grep -Fxq 'action_32_remote_node_b_check_candidate_1_environment_contract_exact=true' \
    "$fixture_root/exact.stdout"
grep -Fxq 'action_32_remote_node_b_check_candidate_2_environment_contract_exact=true' \
    "$fixture_root/exact.stdout"
grep -Fxq 'action_32_remote_node_b_check_candidate_1_caddy_validation_success=true' \
    "$fixture_root/exact.stdout"
grep -Fxq 'action_32_remote_node_b_check_candidate_2_caddy_validation_success=true' \
    "$fixture_root/exact.stdout"
grep -Fxq 'mock_caddy_environment_complete=true' \
    "$capture_directory/candidate_1_caddy_validation.stdout"
grep -Fxq 'mock_caddy_environment_complete=true' \
    "$capture_directory/candidate_2_caddy_validation.stdout"
grep -E '^action_32_remote_node_b_check_candidate_.*=true$' \
    "$fixture_root/exact.stdout" | LC_ALL=C sort >"$fixture_root/candidate-labels"
[[ "$(awk 'END { print NR }' "$fixture_root/candidate-labels")" -eq "$(sort -u "$fixture_root/candidate-labels" | awk 'END { print NR }')" ]]
if grep -Eq '^action_32_remote_node_b_check_candidate_.*=false$' \
    "$fixture_root/exact.stdout"; then
    exit 1
fi

sed -i '/^NODE_IPV6=/d' "$successor_environment_file"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_absent_node_environment_accepted=false\n' >&2
    exit 1
fi
printf 'NODE_IPV6=fd36:5aa8:6971:1::54\n' >>"$successor_environment_file"

chmod u+w "$successor_incoming_root/node-a/revision-current/Caddyfile"
printf 'drift\n' >>"$successor_incoming_root/node-a/revision-current/Caddyfile"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_divergent_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"
chmod 0644 "$successor_incoming_root/node-a/revision-current/Caddyfile"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_overpermissive_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-extra"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_multiple_candidates_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-extra"
rm -rf -- "$successor_incoming_root/node-a/revision-extra"

chmod u+w "$successor_incoming_root/node-a/revision-old/Caddyfile"
printf 'quarantine-drift\n' >>"$successor_incoming_root/node-a/revision-old/Caddyfile"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_quarantine_mismatch_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-old"
rm -rf -- "$successor_incoming_root/node-a/revision-old"
make_release "$successor_incoming_root/node-a/revision-child" \
    revision-child revision-current
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_deployable_child_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-child"
rm -rf -- "$successor_incoming_root/node-a/revision-child"
cp -a "$successor_quarantine_root/node-a-revision-old" \
    "$successor_incoming_root/node-a/revision-old"

role=node-a
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32d_regression_node_a_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
chmod -R u+rwX "$successor_incoming_root/node-a/revision-old"
rm -rf -- "$successor_incoming_root/node-a/revision-old"
inspect_finalized_candidate >"$fixture_root/node-a-empty.stdout"
grep -Fxq 'finalized_candidate_count=0' "$fixture_root/node-a-empty.stdout"

require_literal 'action32d_disposition=consume_exact_active_replay' "$transaction"
require_literal 'action32d_disposition=discard_exact_quarantine_replay' "$transaction"
require_literal 'candidate_check active_replay_count_one' "$transaction"
require_literal 'candidate_check quarantine_replay_count_one' "$transaction"
require_literal 'candidate_check payload_exact_active true' "$transaction"
require_literal 'candidate_check payload_candidate_hashes_valid bash -c' "$transaction"
require_literal 'candidate_check payload_release_manifests_equal cmp -s' "$transaction"
require_literal '"$successor_caddy_binary" validate' "$transaction"
require_literal '--config "$action32d_candidate/Caddyfile" --adapter caddyfile' "$transaction"
require_literal 'run_captured finalized_candidate_semantics inspect_finalized_candidate' "$transaction"
require_literal 'finalized_candidate_drained_by_corrected_reconciler=true' "$transaction"
require_literal 'successor_persist_base "$action32d_role"' "$transaction"
require_literal 'source "$successor_definitions"' "$transaction"
require_literal 'install_successor_overrides' "$transaction"
require_literal 'NODE_FQDN="$action32d_node_fqdn"' "$transaction"
require_literal 'NODE_IPV4="$action32d_node_ipv4"' "$transaction"
require_literal 'NODE_IPV6="$action32d_node_ipv6"' "$transaction"
require_literal 'run_captured "candidate_${successor_candidate_slot}_caddy_validation" env' "$transaction"
require_literal 'readonly consumed_transaction_sha256=' "$outer"
require_literal 'install -m 0600 "$consumed_transaction"' "$outer"
require_literal 'node_b_mutated=true' "$outer"
require_literal 'node_a_mutated=true' "$outer"
require_literal 'run_captured stop_reconcile_path systemctl stop caddy-sync-reconcile.path' "$consumed"
require_literal 'install_candidates || return 1' "$consumed"
require_literal 'run_captured start_reconcile_path systemctl start caddy-sync-reconcile.path' "$consumed"
require_literal 'check no_finalized_candidate_after no_finalized_candidate' "$consumed"
[[ "$(line_number 'install_candidates || return 1' "$consumed")" -lt "$(line_number 'run_captured start_reconcile_path systemctl start caddy-sync-reconcile.path' "$consumed")" ]]
[[ "$(line_number 'run_captured start_reconcile_path systemctl start caddy-sync-reconcile.path' "$consumed")" -lt "$(line_number 'check no_finalized_candidate_after no_finalized_candidate' "$consumed")" ]]
if grep -Fq 'rm -rf -- "$successor_expected_candidate"' "$transaction"; then
    printf 'action32d_regression_transaction_direct_candidate_deletion=true\n' >&2
    exit 1
fi

printf 'action32d_regression_exact_replay_accepted=true\n'
printf 'action32d_regression_divergence_rejected=true\n'
printf 'action32d_regression_overpermissive_candidate_rejected=true\n'
printf 'action32d_regression_multiple_candidates_rejected=true\n'
printf 'action32d_regression_quarantine_mismatch_rejected=true\n'
printf 'action32d_regression_deployable_child_rejected=true\n'
printf 'action32d_regression_node_a_candidate_rejected=true\n'
printf 'action32d_regression_corrected_reconciler_precedes_drain=true\n'
printf 'action32d_regression_actual_payload_path_covered=true\n'
printf 'action32d_regression_runtime_source_order_covered=true\n'
printf 'action32d_regression_exact_environment_propagated=true\n'
printf 'action32d_regression_absent_environment_rejected=true\n'
printf 'action32d_regression_candidate_label_inventory_exact=true\n'
printf 'action32d_regression_complete=true\n'
