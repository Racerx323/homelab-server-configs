#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly base_inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly base_runner_sha256=d0f6cc13e4de61dd9105ee4db3afd8f4caead3485d119b6c1e59e488219c4801
readonly base_regression_sha256=2faab580c7d201d83333961d41b1278e36377757fe6222106c89f7dcb08e502e
readonly node_a_keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly rendered_inspector_name=inspect-node-a-keepalived-prerequisite-action19c-a.sh
readonly rendered_runner_name=run-node-a-keepalived-prerequisite-action19c-a.sh
readonly rendered_regression_name=action19c-a-node-a-keepalived-prerequisite-regression.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly base_inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly base_runner="$script_directory/run-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly base_regression="$caddy_root/tests/action19a-a-node-b-keepalived-helper-prerequisite-regression.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_regression")" = "$base_regression_sha256" ]] ||
        return 1
}

render_inspector() {
    local output_path=$1

    awk -v keepalived_hash="$node_a_keepalived_tree_sha256" '
        function transform(v) {
            gsub(/node-b-keepalived-helper-prerequisite-action19a-a/,
                "node-a-keepalived-prerequisite-action19c-a", v)
            gsub(/action_19a_a/, "action_19c_a", v)
            gsub(/action19a-a/, "action19c-a", v)
            gsub(/action19a/, "action19c", v)
            gsub(/caddy-action19c-a/, "caddy-action19c-a", v)
            gsub(/hostname_node_b/, "hostname_node_a", v)
            gsub(/j1-svpihole00/, "j1-svpihole0", v)
            gsub(/10\.1\.0\.54/, "10.1.0.53", v)
            gsub(/fd36:5aa8:6971:1::54/, "fd36:5aa8:6971:1::53", v)
            gsub(/68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f/,
                keepalived_hash, v)
            gsub(/action15-health-follow-redirects/,
                "action16ar-retry-node-a-default-deny", v)
            gsub(/health_state_absent/, "health_state_supported", v)
            return v
        }
        {
            line = transform($0)
            if (line == "record_command health_state_supported test \"$health_state\" = absent") {
                line = "record_command health_state_supported state_supported \"$health_state\""
            }
            print line
        }
    ' "$base_inspector" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local inspector_hash=$1
    local output_path=$2

    awk -v inspector_hash="$inspector_hash" '
        function transform(v) {
            gsub(/node-b-keepalived-helper-prerequisite-action19a-a/,
                "node-a-keepalived-prerequisite-action19c-a", v)
            gsub(/inspect-node-b-keepalived-helper-prerequisite-action19a-a/,
                "inspect-node-a-keepalived-prerequisite-action19c-a", v)
            gsub(/action_19a_a/, "action_19c_a", v)
            gsub(/action19a-a/, "action19c-a", v)
            gsub(/action19a/, "action19c", v)
            gsub(/ACTION19AA/, "ACTION19CA", v)
            gsub(/CADDY_ACTION19AA/, "CADDY_ACTION19CA", v)
            gsub(/pi@10\.1\.0\.54/, "pi@10.1.0.53", v)
            gsub(/pihole00\.local\.theama\.co/,
                "pihole0.local.theama.co", v)
            gsub(/health_state_absent/, "health_state_supported", v)
            return v
        }
        {
            line = transform($0)
            if (line ~ /^readonly repository_root=/ ||
                line ~ /^readonly source_context_policy=/) {
                next
            } else if (line ~ /^readonly inspector_sha256=/) {
                line = "readonly inspector_sha256=" inspector_hash
            }
            print line
        }
    ' "$base_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_regression() {
    local inspector_hash=$1
    local output_path=$3
    local runner_hash=$2

    awk -v inspector_hash="$inspector_hash" -v runner_hash="$runner_hash" '
        function transform(v) {
            gsub(/action19a-a-node-b-keepalived-helper-prerequisite-regression/,
                "action19c-a-node-a-keepalived-prerequisite-regression", v)
            gsub(/inspect-node-b-keepalived-helper-prerequisite-action19a-a/,
                "inspect-node-a-keepalived-prerequisite-action19c-a", v)
            gsub(/run-node-b-keepalived-helper-prerequisite-action19a-a/,
                "run-node-a-keepalived-prerequisite-action19c-a", v)
            gsub(/action_19a_a/, "action_19c_a", v)
            gsub(/action19a-a/, "action19c-a", v)
            gsub(/action19a/, "action19c", v)
            gsub(/ACTION19AA/, "ACTION19CA", v)
            gsub(/CADDY_ACTION19AA/, "CADDY_ACTION19CA", v)
            gsub(/pi@10\.1\.0\.54/, "pi@10.1.0.53", v)
            gsub(/pihole00\.local\.theama\.co/,
                "pihole0.local.theama.co", v)
            gsub(/health_state_absent/, "health_state_supported", v)
            return v
        }
        {
            line = transform($0)
            if (line ~ /^readonly repository_root=/ ||
                line ~ /^readonly source_context_policy=/) {
                next
            } else if (line ~ /^readonly inspector_sha256=/) {
                line = "readonly inspector_sha256=" inspector_hash
            } else if (line ~ /^readonly runner_sha256=/) {
                line = "readonly runner_sha256=" runner_hash
            } else if (line == "require_gate runner_source_context \"$source_context_policy\" --runner \"$runner\"") {
                line = "require_gate rendered_runner_executable test -x \"$runner\""
            } else if (line == "        cd \"$repository_root\"") {
                print "        if [[ \"${CADDY_VALIDATION_CONTAINER:-}\" = 1 ]]; then"
                print "            cd /workspace/homelab-server-configs"
                print "        else"
                print "            cd /home/aaron/code/homelab-server-configs"
                print "        fi"
                next
            } else if (line == "printf \047%s_false_negative_valid_evidence_accepted=true\\n\047 \"$prefix\"") {
                print "sed \\"
                print "    -e \047s/action_19c_a_value_health_state=absent/action_19c_a_value_health_state=exact/\047 \\"
                print "    -e \047s/action_19c_a_value_health_observed_sha256=absent/action_19c_a_value_health_observed_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414/\047 \\"
                print "    -e \047s/action_19c_a_value_notification_state=absent/action_19c_a_value_notification_state=exact/\047 \\"
                print "    -e \047s/action_19c_a_value_notification_observed_sha256=absent/action_19c_a_value_notification_observed_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8/\047 \\"
                print "    \"$regression_root/valid.fixture\" >\"$regression_root/exact-helpers.fixture\""
                print "exact_helpers_status=$(run_case \"$regression_root/exact-helpers.fixture\" exact-helpers \\"
                print "    \"$regression_root\" 0)"
                print "require_gate exact_helpers_status_zero test \"$exact_helpers_status\" -eq 0"
                print "require_gate exact_helpers_accepted grep -Fxq \\"
                print "    action_19c_a_runner_acceptance=accepted \\"
                print "    \"$regression_root/exact-helpers.stdout\""
            }
            print line
        }
    ' "$base_regression" >"$output_path"
    chmod 0755 "$output_path"
}

render_all() {
    local output_directory=$1
    local inspector="$output_directory/Caddy/scripts/$rendered_inspector_name"
    local regression="$output_directory/Caddy/tests/$rendered_regression_name"
    local runner="$output_directory/Caddy/scripts/$rendered_runner_name"
    local inspector_hash
    local runner_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    install -d -m 0700 "$output_directory/Caddy/scripts" \
        "$output_directory/Caddy/tests"
    install -m 0755 "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$output_directory/Caddy/tests/check-shell-readonly-local-collisions-v2.sh"
    render_inspector "$inspector"
    inspector_hash=$(file_hash "$inspector")
    render_runner "$inspector_hash" "$runner"
    runner_hash=$(file_hash "$runner")
    render_regression "$inspector_hash" "$runner_hash" "$regression"
}

self_test() {
    verify_sources
    self_test_root=$(mktemp -d /tmp/caddy-action19c-a-derive.XXXXXX)
    readonly self_test_root
    cleanup_self_test() { rm -rf -- "$self_test_root"; }
    trap cleanup_self_test EXIT
    render_all "$self_test_root"
    bash -n \
        "$self_test_root/Caddy/scripts/$rendered_inspector_name" \
        "$self_test_root/Caddy/scripts/$rendered_runner_name" \
        "$self_test_root/Caddy/tests/$rendered_regression_name"
    "$self_test_root/Caddy/scripts/$rendered_inspector_name" \
        --self-test >/dev/null
    "$self_test_root/Caddy/scripts/$rendered_runner_name" \
        --self-test >/dev/null
    "$self_test_root/Caddy/scripts/$rendered_runner_name" \
        --contract-test >/dev/null
    grep -Fq 'record_command health_state_supported state_supported' \
        "$self_test_root/Caddy/scripts/$rendered_inspector_name"
    grep -Fq 'record_command notification_state_supported state_supported' \
        "$self_test_root/Caddy/scripts/$rendered_inspector_name"
    if grep -Eq 'j1-svpihole00|10\.1\.0\.54|::54|pihole00\.' \
        "$self_test_root/Caddy/scripts/$rendered_inspector_name" \
        "$self_test_root/Caddy/scripts/$rendered_runner_name" \
        "$self_test_root/Caddy/tests/$rendered_regression_name"; then
        return 1
    fi
    printf 'action_19c_a_derivation_self_test_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        self_test
        ;;
    --output-directory)
        [[ $# -eq 2 ]]
        verify_sources
        render_all "$2"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
