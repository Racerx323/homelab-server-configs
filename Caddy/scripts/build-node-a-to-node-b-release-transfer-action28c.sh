#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=25d62e26123ff2fc468db5cba92aeb9cd54befe69c51f9c48ba3586407182234
readonly historical_inspector_sha256=026766ca4085b5a696be3f0f14f9d74321f4d27b2aa33db1aced86689702f34a
readonly historical_runner_sha256=0e0399f47f9941d30ee86ffbdf48e10692a4e84593adae53599d30b2db53d495

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly historical_driver=$script_directory/transfer-node-a-release-to-node-b-action28.sh
readonly historical_inspector=$script_directory/inspect-node-b-incoming-release-action28.sh
readonly historical_runner=$script_directory/run-node-a-to-node-b-release-transfer-action28.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_historical() {
    local action28c_builder_expected_hash=$1
    local action28c_builder_source=$2

    [[ -f "$action28c_builder_source" && ! -L "$action28c_builder_source" ]] || return 1
    [[ "$(file_hash "$action28c_builder_source")" = "$action28c_builder_expected_hash" ]]
}
render_driver() {
    local action28c_builder_output=$1

    awk '
        {
            gsub(/25d62e26123ff2fc468db5cba92aeb9cd54befe69c51f9c48ba3586407182234/, "175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9")
            gsub(/026766ca4085b5a696be3f0f14f9d74321f4d27b2aa33db1aced86689702f34a/, "475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513")
            gsub(/action_28_node_a/, "action_28c_node_a")
            gsub(/caddy-action28-node-a/, "caddy-action28c-node-a")
            gsub(/record_command manifest_hashes_valid bash -c/, "record_command manifest_hashes_valid /bin/bash -c")
        }
        /^readonly outbound_root=/ {
            print
            print "readonly publisher_backup=/var/backups/caddy-ha/action28b-node-a-publisher"
            print "readonly retained_release=$outbound_root/action17p-node-a-to-node-b-bootstrap"
            print "readonly expected_outbound_root_metadata=994:990:750:4096:1785461698"
            print "readonly expected_retained_metadata=994:990:550:4096:1785461697"
            print "readonly expected_retained_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37"
            print "readonly expected_current_tree_sha256=b7f3dfba3b0dc2aa278f0d1e6dd02fc7d2be6ef0eb656f12f7bc7288df12ebd9"
            next
        }
        /^record_preflight\(\) \{/ {
            print "tree_digest() {"
            print "    local action28c_node_a_tree_root=$1"
            print ""
            print "    ("
            print "        cd \"$action28c_node_a_tree_root\" || exit"
            print "        find . -printf \047%P|%y|%U:%G:%m:%s\\n\047 | LC_ALL=C sort"
            print "        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum"
            print "    ) | sha256sum | awk \047{ print $1 }\047"
            print "}"
            print "backup_manifest_exact() {"
            print "    local action28c_node_a_expected"
            print ""
            print "    action28c_node_a_expected=$(printf \047%s\\n\047 \047action=28b\047 \047node=j1-svpihole0\047 \047publisher_pre_state=absent\047 \"publisher_candidate_sha256=$publisher_sha256\") || return 1"
            print "    [[ \"$(<\"$publisher_backup/manifest\")\" = \"$action28c_node_a_expected\" ]]"
            print "}"
            print ""
            print
            next
        }
        /^    record_command outbound_root_not_symlink/ {
            print
            print "    record_command action28b_backup_directory test -d \"$publisher_backup\""
            print "    record_command action28b_backup_not_symlink test ! -L \"$publisher_backup\""
            print "    record_command action28b_backup_metadata test \"$(stat -c \047%U:%G:%a\047 \"$publisher_backup\" 2>/dev/null || true)\" = root:root:700"
            print "    record_command action28b_manifest_regular test -f \"$publisher_backup/manifest\""
            print "    record_command action28b_manifest_not_symlink test ! -L \"$publisher_backup/manifest\""
            print "    record_command action28b_manifest_metadata test \"$(stat -c \047%U:%G:%a\047 \"$publisher_backup/manifest\" 2>/dev/null || true)\" = root:root:600"
            print "    record_command action28b_manifest_exact backup_manifest_exact"
            print "    record_command action28b_stage_residue_absent test -z \"$(find /usr/local/libexec -mindepth 1 -maxdepth 1 -name \047.publish-release-v2.action28b.*\047 -print -quit 2>/dev/null)\""
            print "    record_command outbound_root_metadata_exact test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$outbound_root\" 2>/dev/null || true)\" = \"$expected_outbound_root_metadata\""
            print "    record_command outbound_child_count_exact test \"$(find \"$outbound_root\" -mindepth 1 -maxdepth 1 -print | wc -l)\" -eq 1"
            print "    record_command retained_release_directory test -d \"$retained_release\""
            print "    record_command retained_release_not_symlink test ! -L \"$retained_release\""
            print "    record_command retained_release_metadata_exact test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$retained_release\" 2>/dev/null || true)\" = \"$expected_retained_metadata\""
            print "    record_command retained_release_tree_exact test \"$(tree_digest \"$retained_release\" 2>/dev/null || true)\" = \"$expected_retained_tree_sha256\""
            print "    record_command retained_finalize_request_absent test ! -e \"$retained_release/.finalize-request\""
            print "    record_command retained_complete_regular test -f \"$retained_release/.complete\""
            print "    record_command retained_complete_empty test ! -s \"$retained_release/.complete\""
            print "    record_command retained_complete_pending_absent test ! -e \"$retained_release/.complete.pending\""
            print "    record_command current_tree_exact test \"$(tree_digest \"$source_release\" 2>/dev/null || true)\" = \"$expected_current_tree_sha256\""
            next
        }
        /^    record_command rsync_status_zero/ {
            print
            print "        record_command publisher_hash_still_exact test \"$(file_hash \"$publisher\" 2>/dev/null || true)\" = \"$publisher_sha256\""
            print "        record_command action28b_manifest_still_exact backup_manifest_exact"
            print "        record_command retained_release_tree_still_exact test \"$(tree_digest \"$retained_release\" 2>/dev/null || true)\" = \"$expected_retained_tree_sha256\""
            print "        record_command current_tree_still_exact test \"$(tree_digest \"$source_release\" 2>/dev/null || true)\" = \"$expected_current_tree_sha256\""
            next
        }
        { print }
    ' "$historical_driver" >"$action28c_builder_output"
}
render_inspector() {
    local action28c_builder_output=$1

    sed -e 's/action_28_node_b/action_28c_node_b/g' \
        -e 's/record_command manifest_hashes_valid bash -c/record_command manifest_hashes_valid \/bin\/bash -c/' \
        "$historical_inspector" >"$action28c_builder_output"
}
render_runner() {
    local action28c_builder_output=$1

    awk '
        {
            gsub(/25d62e26123ff2fc468db5cba92aeb9cd54befe69c51f9c48ba3586407182234/, "175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9")
            gsub(/026766ca4085b5a696be3f0f14f9d74321f4d27b2aa33db1aced86689702f34a/, "475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513")
            gsub(/action_28_/, "action_28c_")
            gsub(/caddy-action28-runner/, "caddy-action28c-runner")
            gsub(/transfer-node-a-release-to-node-b-action28[.]sh/, "transfer-node-a-release-to-node-b-action28c.sh")
            gsub(/inspect-node-b-incoming-release-action28[.]sh/, "inspect-node-b-incoming-release-action28c.sh")
            gsub(/sudo -n bash -s/, "sudo -n /bin/bash -s/")
            if ($0 == "readonly prefix=action_28") {
                $0 = "readonly prefix=action_28c"
            }
            if ($0 == "readonly caddy_root=${script_directory%/scripts}") {
                $0 = "readonly caddy_root=${CADDY_ACTION28C_CADDY_ROOT:?}"
            }
            if ($0 == "[[ \"$PWD\" == /home/aaron/code/homelab-server-configs ]]") {
                $0 = "working_directory_approved"
            }
        }
        /^checks_total=0$/ {
            print "ssh_binary=${CADDY_ACTION28C_SSH_BINARY:-ssh}"
            print "readonly ssh_binary"
            print
        }
        /^    ssh -T / {
            sub(/^    ssh -T /, "    \"$ssh_binary\" -T ")
        }
        /^safe_stream\(\) \{/ {
            print "working_directory_approved() {"
            print "    case \"$PWD\" in"
            print "        /home/aaron/code/homelab-server-configs) return 0 ;;"
            print "        /workspace/homelab-server-configs)"
            print "            [[ \"${CADDY_VALIDATION_CONTAINER:-}\" = 1 ]] || return 1"
            print "            return 0"
            print "            ;;"
            print "        *) return 1 ;;"
            print "    esac"
            print "}"
            print ""
            print
            next
        }
        /^emit_stream node_b_pre_stderr / {
            print
            print "record_command node_b_preflight_stderr_empty test ! -s \"$work_directory/node-b-pre.err\""
            next
        }
        /^    emit_stream node_a_pre_stderr / {
            print
            print "    record_command node_a_preflight_stderr_empty test ! -s \"$work_directory/node-a-pre.err\""
            next
        }
        /^    emit_stream node_a_transfer_stderr / {
            print
            print "    record_command node_a_transfer_stderr_empty test ! -s \"$work_directory/node-a-transfer.err\""
            next
        }
        /^    emit_stream node_b_complete_stderr / {
            print
            print "    record_command node_b_complete_stderr_empty test ! -s \"$work_directory/node-b-complete.err\""
            next
        }
        { print }
    ' "$historical_runner" >"$action28c_builder_output"
}

[[ $# -eq 1 ]]
readonly output_directory=$1
[[ -d "$output_directory" && ! -L "$output_directory" ]]
require_historical "$historical_driver_sha256" "$historical_driver"
require_historical "$historical_inspector_sha256" "$historical_inspector"
require_historical "$historical_runner_sha256" "$historical_runner"

render_driver "$output_directory/transfer-node-a-release-to-node-b-action28c.sh"
render_inspector "$output_directory/inspect-node-b-incoming-release-action28c.sh"
render_runner "$output_directory/run-node-a-to-node-b-release-transfer-action28c.sh"
chmod 0755 \
    "$output_directory/transfer-node-a-release-to-node-b-action28c.sh" \
    "$output_directory/inspect-node-b-incoming-release-action28c.sh" \
    "$output_directory/run-node-a-to-node-b-release-transfer-action28c.sh"
