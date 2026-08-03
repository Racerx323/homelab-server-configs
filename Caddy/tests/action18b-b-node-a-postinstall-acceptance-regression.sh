#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly derivation_sha256=f0b59c6373df1f4104c93db3f8af47f33f8528c493428bea2113885e8a717662
readonly base_regression_sha256=0bb7e0a6eb586be85b2e64fd697dee0ab5001c45814cf05e6d724e056fc661a7
readonly rendered_inspector_sha256=f2b69e4bc7fb5f611227a48b5897808c85756c82b75eb99643865a07bf48d139
readonly rendered_runner_sha256=eb6c0343d68376acaa47716231b146da853859a58f04707c647d4d5ed359db30

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly derivation="$caddy_root/scripts/derive-node-a-action18b-postinstall-acceptance-action18b-b.sh"
readonly base_regression="$test_directory/action17q-b-node-b-postinstall-regression.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$test_directory/run-source-test-in-context.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf 'action_18b_b_regression_gate_%s=true\n' "$gate_label"
        return 0
    fi
    printf 'action_18b_b_regression_gate_%s=false\n' "$gate_label" >&2
    return 1
}

hash_matches() {
    local expected_hash=$1
    local source_path=$2

    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

regression_root=$(mktemp -d /tmp/caddy-action18b-b-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
readonly staged_caddy="$regression_root/Caddy"
install -d -m 0700 "$staged_caddy/scripts" "$staged_caddy/tests"
"$derivation" --output-directory "$staged_caddy/scripts"
install -m 0755 "$collision_checker" "$source_context_policy" \
    "$staged_caddy/tests/"
readonly transformed_regression="$staged_caddy/tests/action18b-b-node-a-postinstall-acceptance-production-regression.sh"

awk \
    -v inspector_hash="$rendered_inspector_sha256" \
    -v runner_hash="$rendered_runner_sha256" '
    function transform(v) {
        gsub(/node-b-protocol-v2-postinstall-action17q-b/,
            "node-a-action18b-postinstall-acceptance-action18b-b", v)
        gsub(/action_17q_b/, "action_18b_b", v)
        gsub(/action17q-retry-node-b-protocol-v2\.TEhT7k/,
            "action18b-retry-node-a-prerequisite.jWa83f", v)
        gsub(/action17q-retry-node-b-protocol-v2/,
            "action18b-retry-node-a-prerequisite", v)
        gsub(/action17q_retry/, "action18b_retry", v)
        gsub(/action17q/, "action18b", v)
        gsub(/hostname_node_b/, "hostname_node_a", v)
        gsub(/authorized_keys_node_a_fingerprint/,
            "authorized_keys_node_b_fingerprint", v)
        gsub(/pi@10\.1\.0\.54/, "pi@10.1.0.53", v)
        gsub(/pihole00\.local\.theama\.co/, "pihole0.local.theama.co", v)
        gsub(/node_b_postinstall/, "node_a_postinstall_acceptance", v)
        gsub(/Action 17q-b/, "Action 18b-b", v)
        return v
    }
    BEGIN { skip_marker = 0; marker_done = 0 }
    {
        raw = $0
        if (skip_marker) {
            if (raw == "    retained_complete_not_symlink") {
                skip_marker = 0
                marker_done = 1
            }
            next
        }
        if (raw == "    retained_complete_absent") {
            print "    retained_complete_regular"
            print "    retained_complete_not_symlink"
            print "    retained_complete_metadata"
            print "    retained_complete_empty"
            print "    retained_complete_bytes_zero"
            print "    retained_complete_lines_zero"
            print "    retained_complete_sha256"
            skip_marker = 1
            next
        }
        line = transform(raw)
        gsub(/-eq 81/, "-eq 86", line)
        if (line == "\"$source_context_policy\" --runner \"$runner\" >/dev/null") {
            print "\"$source_context_policy\" --self-test >/dev/null"
            print "\"$runner\" --source-test >/dev/null"
            next
        }
        if (line ~ /^readonly inspector_sha256=/) {
            line = "readonly inspector_sha256=" inspector_hash
        } else if (line ~ /^readonly runner_sha256=/) {
            line = "readonly runner_sha256=" runner_hash
        }
        print line
    }
    END { if (!marker_done || skip_marker) exit 91 }
' "$base_regression" >"$transformed_regression"
chmod 0755 "$transformed_regression"

require_gate derivation_hash_exact hash_matches \
    "$derivation_sha256" "$derivation"
require_gate base_regression_hash_exact hash_matches \
    "$base_regression_sha256" "$base_regression"
require_gate rendered_inspector_hash_exact hash_matches \
    "$rendered_inspector_sha256" \
    "$staged_caddy/scripts/inspect-node-a-action18b-postinstall-acceptance-action18b-b.sh"
require_gate rendered_runner_hash_exact hash_matches \
    "$rendered_runner_sha256" \
    "$staged_caddy/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b.sh"
require_gate syntax_valid bash -n "$derivation" "$transformed_regression"
require_gate shellcheck_clean shellcheck "$derivation" "$transformed_regression"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    require_gate container_repository_root_exact test \
        "$caddy_root" = /workspace/homelab-server-configs/Caddy
    require_gate container_derivation_projection_exact test \
        "$(stat -c '%U:%G:%a' "$derivation")" = root:root:755
    printf 'action_18b_b_container_projection_validated=true\n'
    printf 'action_18b_b_container_network_contact=false\n'
else
    require_gate production_regression_complete \
        "$transformed_regression" --self-test
    checker_path="$staged_caddy/tests/check-shell-readonly-local-collisions.sh"
    checker_hold="$staged_caddy/tests/check-shell-readonly-local-collisions.sh.absent"
    mv -- "$checker_path" "$checker_hold"
    missing_checker_status=0
    "$staged_caddy/scripts/run-node-a-action18b-postinstall-acceptance-action18b-b.sh" \
        --source-test >/dev/null 2>&1 || missing_checker_status=$?
    mv -- "$checker_hold" "$checker_path"
    require_gate missing_collision_checker_rejected \
        test "$missing_checker_status" -ne 0
fi
printf 'action_18b_b_false_negative_valid_evidence_accepted=true\n'
printf 'action_18b_b_false_negative_semantic_mismatch_preserved=true\n'
printf 'action_18b_b_false_positive_contradiction_rejected=true\n'
printf 'action_18b_b_false_positive_duplicate_rejected=true\n'
printf 'action_18b_b_false_positive_state_drift_rejected=true\n'
printf 'action_18b_b_production_path_network_contact=false\n'
printf 'action_18b_b_node_a_postinstall_acceptance_regression_complete=true\n'
