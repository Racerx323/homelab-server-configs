#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-caddy-runtime-lifecycle-action32a.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-runtime-lifecycle-action32a-outer.sh
readonly consumed=$caddy_root/scripts/apply-caddy-runtime-lifecycle-action32.sh
fixture_root=
definitions=

cleanup() {
    if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
        chmod -R u+rwX "$fixture_root"
        rm -rf -- "$fixture_root"
    fi
}
trap cleanup EXIT INT TERM

require_literal() {
    local action32a_regression_literal=$1
    local action32a_regression_file=$2

    grep -Fq -- "$action32a_regression_literal" "$action32a_regression_file"
}

line_number() {
    local action32a_regression_literal=$1
    local action32a_regression_file=$2

    awk -v wanted="$action32a_regression_literal" \
        'index($0, wanted) { print NR; found++ } END { if (found != 1) exit 1 }' \
        "$action32a_regression_file"
}

make_release() {
    local action32a_regression_path=$1
    local action32a_regression_revision=$2

    install -d -m 0700 "$action32a_regression_path"
    printf ':80 { respond "fixture" }\n' >"$action32a_regression_path/Caddyfile"
    printf '{"parent_revision":"parent","revision":"%s","source_node":"node-a"}\n' \
        "$action32a_regression_revision" >"$action32a_regression_path/release-manifest.json"
    (
        cd "$action32a_regression_path"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    : >"$action32a_regression_path/.finalize-request"
    : >"$action32a_regression_path/.complete"
    find "$action32a_regression_path" -type d -exec chmod 0550 {} +
    find "$action32a_regression_path" -type f -exec chmod 0440 {} +
}

fixture_root=$(mktemp -d /tmp/caddy-action32a-regression.XXXXXX)
chmod 0700 "$fixture_root"
definitions=$fixture_root/transaction-definitions.sh
sed '/^mode=${1:-}/,$d' "$transaction" >"$definitions"
# shellcheck disable=SC1090
source "$definitions"

successor_incoming_root=$fixture_root/incoming
successor_current_link=$fixture_root/current
successor_releases_root=$fixture_root/releases
successor_caddy_binary=/bin/true
install -d -m 0700 "$successor_incoming_root/node-a" "$fixture_root/releases"
: >"$successor_incoming_root/.reconcile-trigger"
make_release "$fixture_root/releases/revision-current" revision-current
ln -s "$fixture_root/releases/revision-current" "$successor_current_link"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"

role=node-b
inspect_finalized_candidate >"$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_count=1' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_revision=revision-current' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_source=node-a' "$fixture_root/exact.stdout"
grep -Fxq 'finalized_candidate_exact_active_replay=true' "$fixture_root/exact.stdout"

chmod u+w "$successor_incoming_root/node-a/revision-current/Caddyfile"
printf 'drift\n' >>"$successor_incoming_root/node-a/revision-current/Caddyfile"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32a_regression_divergent_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"
chmod 0644 "$successor_incoming_root/node-a/revision-current/Caddyfile"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32a_regression_overpermissive_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-current"
cp -a "$fixture_root/releases/revision-current" \
    "$successor_incoming_root/node-a/revision-extra"
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32a_regression_multiple_candidates_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-extra"
rm -rf -- "$successor_incoming_root/node-a/revision-extra"

role=node-a
if inspect_finalized_candidate >/dev/null 2>&1; then
    printf 'action32a_regression_node_a_candidate_accepted=false\n' >&2
    exit 1
fi
chmod -R u+rwX "$successor_incoming_root/node-a/revision-current"
rm -rf -- "$successor_incoming_root/node-a/revision-current"
inspect_finalized_candidate >"$fixture_root/node-a-empty.stdout"
grep -Fxq 'finalized_candidate_count=0' "$fixture_root/node-a-empty.stdout"

require_literal 'release_payload_matches "$action32a_candidate" "$action32a_current"' "$transaction"
require_literal '"$successor_caddy_binary" validate --config "$action32a_candidate/Caddyfile"' "$transaction"
require_literal 'run_captured finalized_candidate_semantics inspect_finalized_candidate' "$transaction"
require_literal 'finalized_candidate_drained_by_corrected_reconciler=true' "$transaction"
require_literal 'successor_persist_base "$action32a_role"' "$transaction"
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
    printf 'action32a_regression_transaction_direct_candidate_deletion=true\n' >&2
    exit 1
fi

printf 'action32a_regression_exact_replay_accepted=true\n'
printf 'action32a_regression_divergence_rejected=true\n'
printf 'action32a_regression_overpermissive_candidate_rejected=true\n'
printf 'action32a_regression_multiple_candidates_rejected=true\n'
printf 'action32a_regression_node_a_candidate_rejected=true\n'
printf 'action32a_regression_corrected_reconciler_precedes_drain=true\n'
printf 'action32a_regression_actual_payload_path_covered=true\n'
printf 'action32a_regression_complete=true\n'
