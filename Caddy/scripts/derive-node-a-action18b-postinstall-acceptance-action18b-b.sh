#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly base_inspector_sha256=ba1b49c0f01bf43c25b576d3740ea29f622a7644db016d7b9d6673897bd5f8b4
readonly base_runner_sha256=20822b4e02466727e57e6257aad03f13660cc9b1ec049146f482c42b6508eede
readonly action18b_outer_sha256=84f83568751c7bee11b3c507318f40d794e91ba6ce4769dbfd0d7c4ab34650cb
readonly rendered_inspector_name=inspect-node-a-action18b-postinstall-acceptance-action18b-b.sh
readonly rendered_runner_name=run-node-a-action18b-postinstall-acceptance-action18b-b.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_inspector="$script_directory/inspect-node-b-protocol-v2-postinstall-action17q-b.sh"
readonly base_runner="$script_directory/run-node-b-protocol-v2-postinstall-action17q-b.sh"
readonly action18b_outer="$script_directory/run-node-a-action18-prerequisite-action18b-retry-outer.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ "$(file_hash "$base_inspector")" == "$base_inspector_sha256" ]]
    [[ "$(file_hash "$base_runner")" == "$base_runner_sha256" ]]
    [[ "$(file_hash "$action18b_outer")" == "$action18b_outer_sha256" ]]
}

render_inspector() {
    local output_path=$1

    awk '
        function transform(v) {
            gsub(/node-b-protocol-v2-postinstall-action17q-b/,
                "node-a-action18b-postinstall-acceptance-action18b-b", v)
            gsub(/action_17q_b/, "action_18b_b", v)
            gsub(/action17q-retry-node-b-protocol-v2\.TEhT7k/,
                "action18b-retry-node-a-prerequisite.jWa83f", v)
            gsub(/action17q-retry-node-b-protocol-v2/,
                "action18b-retry-node-a-prerequisite", v)
            gsub(/action17q-node-b-protocol-v2/,
                "action18b-node-a-prerequisite", v)
            gsub(/action17q_retry/, "action18b_retry", v)
            gsub(/action17q/, "action18b", v)
            gsub(/incoming\/node-a/, "outbound", v)
            gsub(/action15-health-follow-redirects/,
                "action16ar-retry-node-a-default-deny", v)
            gsub(/hostname_node_b/, "hostname_node_a", v)
            gsub(/authorized_keys_node_a_fingerprint/,
                "authorized_keys_node_b_fingerprint", v)
            gsub(/j1-svpihole00/, "j1-svpihole0", v)
            gsub(/expected_node_a_fingerprint/,
                "expected_node_b_fingerprint", v)
            gsub(/SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC\/nb56VfAQpK4Y8V0/,
                "SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g", v)
            gsub(/a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c/,
                "15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d", v)
            gsub(/2d07f2dd0bdd1be96f5e6eb227cd23ddc407876925f01849ffa3333c50b553e1/,
                "6ef8d656053aba6508524aaebd3d215ef9036f8bb6fd1f56cd8b4a654649f968", v)
            gsub(/54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1/,
                "3df0ffaaf4d0f1007a9d7214eefc81f4f08df00ad840ea1d3f83e8b72b0e2331", v)
            gsub(/caddy-action17q-b/, "caddy-action18b-b", v)
            return v
        }
        BEGIN { skip_marker = 0; marker_done = 0; stage_skip = 0; stage_done = 0 }
        {
            raw = $0
            if (skip_marker) {
                if (raw == "    test ! -L \"$retained_release/.complete\"") {
                    skip_marker = 0
                    marker_done = 1
                }
                next
            }
            if (stage_skip) {
                if (raw == ")") { stage_skip = 0; stage_done = 1 }
                next
            }
            if (raw == "        find . -type f ! -name .complete -print0 |") {
                print "        find . -type f ! -name .complete \\"
                print "            ! -name .complete.pending ! -name .finalize-request -print0 |"
                next
            }
            if (raw == "record_command retained_complete_absent \\") {
                print "record_command retained_complete_regular test -f \"$retained_release/.complete\""
                print "record_command retained_complete_not_symlink test ! -L \"$retained_release/.complete\""
                print "record_command retained_complete_metadata \\"
                print "    test \"$(stat -c \047%U:%G:%a\047 \"$retained_release/.complete\" 2>/dev/null || true)\" = caddy-sync:caddy-sync:440"
                print "record_command retained_complete_empty test ! -s \"$retained_release/.complete\""
                print "record_command retained_complete_bytes_zero \\"
                print "    test \"$(stat -c \047%s\047 \"$retained_release/.complete\" 2>/dev/null || true)\" = 0"
                print "record_command retained_complete_lines_zero \\"
                print "    test \"$(awk \047END { print NR }\047 \"$retained_release/.complete\" 2>/dev/null || true)\" = 0"
                print "record_command retained_complete_sha256 \\"
                print "    test \"$(file_hash \"$retained_release/.complete\" 2>/dev/null || true)\" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                skip_marker = 1
                next
            }
            if (raw == "action17q_retry_stage_count=$(") {
                print "action18b_retry_stage_count=$("
                print "    find /run /tmp -mindepth 1 -maxdepth 1 \\"
                print "        \\( -name \047caddy-action18b-*\047 -o -name \047.caddy-sync-*-v2.*\047 \\) \\"
                print "        ! -path \"$work_directory\" -printf . 2>/dev/null | wc -c"
                print ")"
                stage_skip = 1
                next
            }
            line = transform(raw)
            if (line == "        \"$retained_release/manifest.sha256\" \\") {
                print line
                print "        \"$retained_release/.complete\" \\"
                next
            }
            print line
        }
        END { if (!marker_done || !stage_done || skip_marker || stage_skip) exit 91 }
    ' "$base_inspector" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local inspector_hash=$1
    local output_path=$2

    awk -v inspector_hash="$inspector_hash" '
        function transform(v) {
            gsub(/node-b-protocol-v2-postinstall-action17q-b/,
                "node-a-action18b-postinstall-acceptance-action18b-b", v)
            gsub(/action17q-retry-node-b-protocol-v2\.TEhT7k/,
                "action18b-retry-node-a-prerequisite.jWa83f", v)
            gsub(/action_17q_b/, "action_18b_b", v)
            gsub(/action17q-retry-node-b-protocol-v2/,
                "action18b-retry-node-a-prerequisite", v)
            gsub(/action17q_retry/, "action18b_retry", v)
            gsub(/action17q/, "action18b", v)
            gsub(/hostname_node_b/, "hostname_node_a", v)
            gsub(/pi@10\.1\.0\.54/, "pi@10.1.0.53", v)
            gsub(/pihole00\.local\.theama\.co/, "pihole0.local.theama.co", v)
            gsub(/authorized_keys_node_a_fingerprint/,
                "authorized_keys_node_b_fingerprint", v)
            gsub(/caddy-action17q-b/, "caddy-action18b-b", v)
            gsub(/Action 17q-b/, "Action 18b-b", v)
            return v
        }
        BEGIN { skip_marker = 0; marker_done = 0; verify_inspector = 0 }
        {
            raw = $0
            if (raw == "verify_inspector() {") {
                verify_inspector = 1
                print raw
                next
            }
            if (verify_inspector && raw == "}") {
                verify_inspector = 0
                print raw
                next
            }
            if (verify_inspector && raw != "") {
                print transform(raw) " || return 1"
                next
            }
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
            if (line ~ /^readonly inspector_sha256=/) {
                line = "readonly inspector_sha256=" inspector_hash
            }
            print line
        }
        END { if (!marker_done || skip_marker || verify_inspector) exit 91 }
    ' "$base_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local inspector="$output_directory/$rendered_inspector_name"
    local runner="$output_directory/$rendered_runner_name"
    local inspector_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]]
    render_inspector "$inspector"
    inspector_hash=$(file_hash "$inspector")
    render_runner "$inspector_hash" "$runner"
}

case "${1:-}" in
    --self-test)
        verify_sources
        test_root=$(mktemp -d /tmp/caddy-action18b-b-derive.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        render_pair "$test_root"
        bash -n "$test_root/$rendered_inspector_name" \
            "$test_root/$rendered_runner_name"
        "$test_root/$rendered_inspector_name" --self-test >/dev/null
        printf 'action_18b_b_derivation_self_test_complete=true\n'
        ;;
    --output-directory)
        [[ $# -eq 2 ]]
        verify_sources
        render_pair "$2"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac
