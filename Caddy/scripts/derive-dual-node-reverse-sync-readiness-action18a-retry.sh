#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18a_retry
readonly historical_inspector_sha256=209eadc6ff077e829c0b5fc2f3c867728b9ad279372e663cb9f6eebf09a45673
readonly historical_runner_sha256=6979f14c06c51a5f7eee5708cc5b58946aebbc065e2ab46c326946e2e661d832
readonly historical_regression_sha256=fd75ae21a34f1d1fcea0c0a4350795f896560ede6caf0de22d13dcb737ba5fc8
readonly corrected_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly rendered_inspector_name=inspect-reverse-sync-readiness-action18a-retry.sh
readonly rendered_runner_name=run-dual-node-reverse-sync-readiness-action18a-retry.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly historical_inspector="$script_directory/inspect-reverse-sync-readiness-action18a.sh"
readonly historical_runner="$script_directory/run-dual-node-reverse-sync-readiness-action18a.sh"
readonly historical_regression="$caddy_root/tests/action18a-dual-node-reverse-sync-readiness-regression.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_historical_sources() {
    local source_path
    local source_hash
    local expected_hash

    while IFS='|' read -r source_path source_hash expected_hash; do
        [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
        [[ "$source_hash" == "$expected_hash" ]] || return 1
    done <<EOF
$historical_inspector|$(file_hash "$historical_inspector")|$historical_inspector_sha256
$historical_runner|$(file_hash "$historical_runner")|$historical_runner_sha256
$historical_regression|$(file_hash "$historical_regression")|$historical_regression_sha256
EOF
}

render_inspector() {
    local output_path=$1

    awk -v finalizer_hash="$corrected_finalizer_sha256" '
        function emit_observed_helpers() {
            print ""
            print "hash_or_absent() {"
            print "    local hash_path=$1"
            print ""
            print "    if [[ -f \"$hash_path\" && ! -L \"$hash_path\" ]]; then"
            print "        file_hash \"$hash_path\""
            print "    else"
            print "        printf '\''absent\\n'\''"
            print "    fi"
            print "}"
            print ""
            print "# Invoked indirectly through record_command."
            print "# shellcheck disable=SC2317"
            print "hash_value_valid() {"
            print "    local observed_value=$1"
            print ""
            print "    [[ \"$observed_value\" == absent || \"$observed_value\" =~ ^[0-9a-f]{64}$ ]]"
            print "}"
        }
        function emit_observed_values() {
            print "observed_payload_sha256=absent"
            print "if [[ -d \"$release\" && ! -L \"$release\" ]]; then"
            print "    observed_payload_sha256=$(payload_digest \"$release\")"
            print "fi"
            print "readonly observed_payload_sha256"
            print "observed_manifest_sha256=$(hash_or_absent \"$release/manifest.sha256\")"
            print "readonly observed_manifest_sha256"
            print "observed_receiver_v2_sha256=$(hash_or_absent \"$receiver_v2\")"
            print "readonly observed_receiver_v2_sha256"
            print "observed_finalizer_v2_sha256=$(hash_or_absent \"$finalizer_v2\")"
            print "readonly observed_finalizer_v2_sha256"
            print "record_command observed_payload_sha256_format hash_value_valid \"$observed_payload_sha256\""
            print "record_command observed_manifest_sha256_format hash_value_valid \"$observed_manifest_sha256\""
            print "record_command observed_receiver_v2_sha256_format hash_value_valid \"$observed_receiver_v2_sha256\""
            print "record_command observed_finalizer_v2_sha256_format hash_value_valid \"$observed_finalizer_v2_sha256\""
        }
        BEGIN {
            inserted_helpers = 0
            inserted_observed = 0
        }
        {
            line = $0
            gsub(/action_18a/, "action_18a_retry", line)
            if (line ~ /^readonly finalizer_v2_sha256=/) {
                line = "readonly finalizer_v2_sha256=" finalizer_hash
            }
            if (line ~ /^work_directory=.*caddy-action18a-inspector/) {
                gsub(/caddy-action18a-inspector/, "caddy-action18a-retry-inspector", line)
            }
            if (line == "        find . -type f ! -name .complete -print0 |") {
                print "        find . -type f ! -name .complete \\"
                print "            ! -name .complete.pending ! -name .finalize-request -print0 |"
                next
            }
            if (!inserted_helpers && line == "}") {
                print line
                emit_observed_helpers()
                inserted_helpers = 1
                next
            }
            if (!inserted_observed && line == "record_command identity_root test \"$(id -u)\" -eq 0") {
                emit_observed_values()
                print ""
                inserted_observed = 1
            }
            gsub(/\$\(payload_digest "\$release"\)/, "$observed_payload_sha256", line)
            gsub(/\$\(file_hash "\$release\/manifest.sha256"\)/, "$observed_manifest_sha256", line)
            gsub(/\$\(file_hash "\$receiver_v2"\)/, "$observed_receiver_v2_sha256", line)
            gsub(/\$\(file_hash "\$finalizer_v2"\)/, "$observed_finalizer_v2_sha256", line)
            if (line == "printf '\''%s_value_revision=%s\\n'\'' \"$prefix\" \"$revision\"") {
                print "printf '\''%s_value_observed_payload_sha256=%s\\n'\'' \"$prefix\" \"$observed_payload_sha256\""
                print "printf '\''%s_value_observed_manifest_sha256=%s\\n'\'' \"$prefix\" \"$observed_manifest_sha256\""
                print "printf '\''%s_value_observed_receiver_v2_sha256=%s\\n'\'' \"$prefix\" \"$observed_receiver_v2_sha256\""
                print "printf '\''%s_value_observed_finalizer_v2_sha256=%s\\n'\'' \"$prefix\" \"$observed_finalizer_v2_sha256\""
            }
            print line
        }
        END {
            if (!inserted_helpers || !inserted_observed) {
                exit 91
            }
        }
    ' "$historical_inspector" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local output_path=$1
    local inspector_hash=$2

    awk -v rendered_hash="$inspector_hash" '
        {
            line = $0
            gsub(/action_18a/, "action_18a_retry", line)
            gsub(/inspect-reverse-sync-readiness-action18a\.sh/, "inspect-reverse-sync-readiness-action18a-retry.sh", line)
            if (line ~ /^readonly inspector_sha256=/) {
                line = "readonly inspector_sha256=" rendered_hash
            }
            if (line ~ /^work_directory=.*caddy-action18a-runner/) {
                gsub(/caddy-action18a-runner/, "caddy-action18a-retry-runner", line)
            }
            if (line == "    local count_value failed_value first_value") {
                line = "    local count_value failed_value first_value observed_name observed_value"
            }
            if (line ~ /^        before_state_sha256 after_state_sha256 assertion_count/) {
                print "        observed_payload_sha256 observed_manifest_sha256 \\"
                print "        observed_receiver_v2_sha256 observed_finalizer_v2_sha256 \\"
            }
            if (line == "            \"${fixture_prefix}_value_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e\" \\") {
                print line
                print "            \"${fixture_prefix}_value_observed_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e\" \\"
                print "            \"${fixture_prefix}_value_observed_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8\" \\"
                print "            \"${fixture_prefix}_value_observed_receiver_v2_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e\" \\"
                print "            \"${fixture_prefix}_value_observed_finalizer_v2_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d\" \\"
                next
            }
            if (line == "        done") {
                print "            cp \"$contract_directory/success\" \"$contract_directory/malformed-observed\""
                print "            sed -i '\''s/value_observed_payload_sha256=[0-9a-f]\\{64\\}/value_observed_payload_sha256=invalid/'\'' \"$contract_directory/malformed-observed\""
                print "            if validate_transcript \"$contract_role\" \"$contract_directory/malformed-observed\" \\"
                print "                \"$contract_directory/error\" 0; then"
                print "                exit 1"
                print "            elif [[ $? -ne 97 ]]; then"
                print "                exit 1"
                print "            fi"
            }
            if (line == "    [[ \"$count_value\" =~ ^[1-9][0-9]*$ && \"$failed_value\" =~ ^[0-9]+$ ]] || return 97") {
                print "    for observed_name in observed_payload_sha256 observed_manifest_sha256 \\"
                print "        observed_receiver_v2_sha256 observed_finalizer_v2_sha256; do"
                print "        observed_value=$(sed -n \"s/^${validation_prefix}_value_${observed_name}=//p\" \"$transcript_path\")"
                print "        [[ \"$observed_value\" == absent || \"$observed_value\" =~ ^[0-9a-f]{64}$ ]] || return 97"
                print "    done"
            }
            if (line == "for ancestry_field in revision parent_revision payload_sha256 manifest_sha256; do") {
                line = "for ancestry_field in revision parent_revision observed_payload_sha256 observed_manifest_sha256; do"
            }
            print line
        }
    ' "$historical_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local rendered_inspector="$output_directory/$rendered_inspector_name"
    local rendered_runner="$output_directory/$rendered_runner_name"
    local rendered_inspector_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    render_inspector "$rendered_inspector"
    rendered_inspector_hash=$(file_hash "$rendered_inspector")
    render_runner "$rendered_runner" "$rendered_inspector_hash"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_historical_sources
        test_directory=$(mktemp -d /tmp/caddy-action18a-retry-derive.XXXXXX)
        readonly test_directory
        trap 'rm -rf -- "$test_directory"' EXIT
        render_pair "$test_directory"
        bash -n "$test_directory/$rendered_inspector_name" \
            "$test_directory/$rendered_runner_name"
        "$test_directory/$rendered_inspector_name" --self-test >/dev/null
        "$test_directory/$rendered_runner_name" --self-test >/dev/null
        "$test_directory/$rendered_runner_name" --contract-test >/dev/null
        printf '%s_derivation_self_test_complete=true\n' "$action_prefix"
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_historical_sources
        render_pair "$2"
        printf '%s_render_complete=true\n' "$action_prefix"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac
