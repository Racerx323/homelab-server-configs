#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly base_derivation_sha256=46adf7d35a306ddb13e68087db9f5191140b78418f0f65a2182f3ebc848c7afd
readonly base_inspector_sha256=216ee51b429048b0304e76d0b75402f4306470d012f170debb1352951efd5910
readonly base_runner_sha256=cb85c0c63faba81db701f6d02be092df3150dd38a3b926bc785c0b067f54ebad
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
readonly publisher_backup_manifest_sha256=25104ecff8173a5eed58b339c19e0937e6623ffcd771b206260992df77238a99
readonly rendered_inspector_name=inspect-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh
readonly rendered_runner_name=run-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_derivation="$script_directory/derive-node-b-postmigration-acceptance-action17v.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_derivation" && ! -L "$base_derivation" ]] || return 1
    [[ "$(file_hash "$base_derivation")" = "$base_derivation_sha256" ]] ||
        return 1
}

render_base() {
    local kind=$1
    local output_path=$2
    local expected_hash=$3

    "$base_derivation" "--render-$kind" >"$output_path" || return 1
    [[ "$(file_hash "$output_path")" = "$expected_hash" ]] || return 1
}

transform_inspector() {
    local base_source=$1

    awk \
        -v publisher_sha="$publisher_sha256" \
        -v publisher_manifest_sha="$publisher_backup_manifest_sha256" '
        function transform(v) {
            gsub(/action_17v/, "action_18c_publisher_a", v)
            gsub(/caddy-action17v/, "caddy-action18c-publisher-a", v)
            gsub(/postmigration/, "publisher_postinstall", v)
            return v
        }
        {
            raw = $0
            line = transform(raw)
        }
        line ~ /^readonly expected_marker_before_snapshot_sha256=/ {
            print line
            print "readonly publisher=/usr/local/libexec/publish-release-v2.sh"
            print "readonly receiver_v2=/usr/local/libexec/caddy-sync-release-receiver-v2"
            print "readonly authorized_keys=/var/lib/caddy-sync/.ssh/authorized_keys"
            print "readonly publisher_backup_directory=/var/backups/caddy-ha/action18c-publisher-prerequisite.TtgS91"
            print "readonly publisher_backup_manifest=\"$publisher_backup_directory/manifest\""
            print "readonly expected_publisher_sha256=" publisher_sha
            print "readonly expected_receiver_v2_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e"
            print "readonly expected_authorized_keys_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1"
            print "readonly expected_node_a_fingerprint=\047SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0\047"
            print "readonly expected_publisher_backup_manifest_sha256=" publisher_manifest_sha
            constants_added++
            next
        }
        line == "is_sha256() { [[ \"$1\" =~ ^[0-9a-f]{64}$ ]]; }" {
            print line
            print "authorization_fingerprint() {"
            print "    awk \047{ print $(NF-2), $(NF-1), $NF }\047 \"$1\" |"
            print "        ssh-keygen -lf - -E sha256 | awk \047{ print $2 }\047"
            print "}"
            helper_added++
            next
        }
        line == "    local snapshot_path snapshot_unit" {
            print line
            print "    stat -c \047%n|%F|%U:%G:%a:%s:%i\047 \"$publisher\" \"$receiver_v2\" \"$authorized_keys\" \"$publisher_backup_directory\" \"$publisher_backup_manifest\" 2>/dev/null || :"
            print "    printf \047publisher_sha256=%s\\n\047 \"$(file_hash \"$publisher\" 2>/dev/null || true)\""
            print "    printf \047receiver_v2_sha256=%s\\n\047 \"$(file_hash \"$receiver_v2\" 2>/dev/null || true)\""
            print "    printf \047authorized_keys_sha256=%s\\n\047 \"$(file_hash \"$authorized_keys\" 2>/dev/null || true)\""
            print "    printf \047publisher_backup_manifest_sha256=%s\\n\047 \"$(file_hash \"$publisher_backup_manifest\" 2>/dev/null || true)\""
            snapshot_added++
            next
        }
        line ~ /^        marker_transaction_stage_count_zero/ {
            print line
            print "        publisher_regular publisher_not_symlink publisher_metadata publisher_hash_exact publisher_syntax publisher_emergency_gate publisher_master_gate receiver_v2_regular receiver_v2_not_symlink receiver_v2_metadata receiver_v2_hash_exact receiver_v2_syntax authorized_keys_regular authorized_keys_not_symlink authorized_keys_metadata authorized_keys_hash_exact authorized_keys_single_line authorized_keys_node_a_fingerprint publisher_backup_count_one publisher_backup_directory publisher_backup_not_symlink publisher_backup_metadata publisher_backup_manifest_regular publisher_backup_manifest_not_symlink publisher_backup_manifest_metadata publisher_backup_manifest_hash_exact publisher_backup_manifest_action_exact publisher_backup_manifest_prestate_absent publisher_backup_manifest_candidate_hash_exact publisher_transaction_stage_count_zero publisher_install_stage_absent \\"
            labels_added++
            next
        }
        line == "        [[ \"$(expected_check_labels | wc -l)\" -eq 89 ]] || exit 1" {
            sub(/89/, "120", line)
            counts_changed++
        }
        line == "        [[ \"$(expected_check_labels | sort -u | wc -l)\" -eq 89 ]] || exit 1" {
            sub(/89/, "120", line)
            counts_changed++
        }
        {
            print line
        }
        line ~ /^record_command marker_backup_hash_record_content_exact / {
            print ""
            print "record_command publisher_regular test -f \"$publisher\""
            print "record_command publisher_not_symlink test ! -L \"$publisher\""
            print "record_command publisher_metadata test \"$(stat -c \047%U:%G:%a\047 \"$publisher\" 2>/dev/null || true)\" = root:root:755"
            print "record_command publisher_hash_exact test \"$(file_hash \"$publisher\" 2>/dev/null || true)\" = \"$expected_publisher_sha256\""
            print "record_command publisher_syntax bash -n \"$publisher\""
            print "record_command publisher_emergency_gate grep -Fq \047Node B publishing requires --emergency.\047 \"$publisher\""
            print "record_command publisher_master_gate grep -Fq \047Node B may publish only while CADDY_DUALSTACK is MASTER.\047 \"$publisher\""
            print "record_command receiver_v2_regular test -f \"$receiver_v2\""
            print "record_command receiver_v2_not_symlink test ! -L \"$receiver_v2\""
            print "record_command receiver_v2_metadata test \"$(stat -c \047%U:%G:%a\047 \"$receiver_v2\" 2>/dev/null || true)\" = root:root:755"
            print "record_command receiver_v2_hash_exact test \"$(file_hash \"$receiver_v2\" 2>/dev/null || true)\" = \"$expected_receiver_v2_sha256\""
            print "record_command receiver_v2_syntax bash -n \"$receiver_v2\""
            print "record_command authorized_keys_regular test -f \"$authorized_keys\""
            print "record_command authorized_keys_not_symlink test ! -L \"$authorized_keys\""
            print "record_command authorized_keys_metadata test \"$(stat -c \047%U:%G:%a\047 \"$authorized_keys\" 2>/dev/null || true)\" = caddy-sync:caddy-sync:600"
            print "record_command authorized_keys_hash_exact test \"$(file_hash \"$authorized_keys\" 2>/dev/null || true)\" = \"$expected_authorized_keys_sha256\""
            print "record_command authorized_keys_single_line test \"$(wc -l <\"$authorized_keys\" 2>/dev/null || true)\" -eq 1"
            print "record_command authorized_keys_node_a_fingerprint test \"$(authorization_fingerprint \"$authorized_keys\" 2>/dev/null || true)\" = \"$expected_node_a_fingerprint\""
            print "record_command publisher_backup_count_one test \"$(find \"$rollback_root\" -mindepth 1 -maxdepth 1 -type d -name \047action18c-publisher-prerequisite.*\047 -print 2>/dev/null | wc -l)\" -eq 1"
            print "record_command publisher_backup_directory test -d \"$publisher_backup_directory\""
            print "record_command publisher_backup_not_symlink test ! -L \"$publisher_backup_directory\""
            print "record_command publisher_backup_metadata test \"$(stat -c \047%U:%G:%a\047 \"$publisher_backup_directory\" 2>/dev/null || true)\" = root:root:700"
            print "record_command publisher_backup_manifest_regular test -f \"$publisher_backup_manifest\""
            print "record_command publisher_backup_manifest_not_symlink test ! -L \"$publisher_backup_manifest\""
            print "record_command publisher_backup_manifest_metadata test \"$(stat -c \047%U:%G:%a\047 \"$publisher_backup_manifest\" 2>/dev/null || true)\" = root:root:600"
            print "record_command publisher_backup_manifest_hash_exact test \"$(file_hash \"$publisher_backup_manifest\" 2>/dev/null || true)\" = \"$expected_publisher_backup_manifest_sha256\""
            print "record_command publisher_backup_manifest_action_exact grep -Fxq action=action18c-publisher-prerequisite \"$publisher_backup_manifest\""
            print "record_command publisher_backup_manifest_prestate_absent grep -Fxq publisher_pre_state=absent \"$publisher_backup_manifest\""
            print "record_command publisher_backup_manifest_candidate_hash_exact grep -Fxq \"publisher_candidate_sha256=$expected_publisher_sha256\" \"$publisher_backup_manifest\""
            print "record_command publisher_transaction_stage_count_zero test \"$(find /run -mindepth 1 -maxdepth 1 -type d -name \047caddy-action18c-publisher-prerequisite-stage.*\047 -print 2>/dev/null | wc -l)\" -eq 0"
            print "record_command publisher_install_stage_absent test -z \"$(find /usr/local/libexec -mindepth 1 -maxdepth 1 -name \047.publish-release-v2.action18c.*\047 -print -quit 2>/dev/null)\""
            checks_added++
        }
        line ~ /is_sha256 "[$]expected_marker_before_snapshot_sha256"/ {
            print "        is_sha256 \"$expected_publisher_sha256\" || exit 1"
            print "        is_sha256 \"$expected_receiver_v2_sha256\" || exit 1"
            print "        is_sha256 \"$expected_authorized_keys_sha256\" || exit 1"
            print "        is_sha256 \"$expected_publisher_backup_manifest_sha256\" || exit 1"
            self_hashes_added++
        }
        line ~ /printf .*_value_marker_before_snapshot_sha256/ {
            print "printf \047%s_value_publisher_sha256=%s\\n\047 \"$prefix\" \"$expected_publisher_sha256\""
            print "printf \047%s_value_receiver_v2_sha256=%s\\n\047 \"$prefix\" \"$expected_receiver_v2_sha256\""
            print "printf \047%s_value_authorized_keys_sha256=%s\\n\047 \"$prefix\" \"$expected_authorized_keys_sha256\""
            print "printf \047%s_value_publisher_backup_path=%s\\n\047 \"$prefix\" \"$publisher_backup_directory\""
            print "printf \047%s_value_publisher_backup_manifest_sha256=%s\\n\047 \"$prefix\" \"$expected_publisher_backup_manifest_sha256\""
            values_added++
        }
        line ~ /printf .*_finalizer_invoked=false/ {
            print "printf \047%s_publisher_invoked=false\\n\047 \"$prefix\""
            print "printf \047%s_authorization_mutated=false\\n\047 \"$prefix\""
            markers_added++
        }
        END {
            if (constants_added != 1 || helper_added != 1 || snapshot_added != 1 ||
                labels_added != 1 || counts_changed != 2 || checks_added != 1 ||
                self_hashes_added != 1 || values_added != 1 || markers_added != 1) {
                printf "action_18c_publisher_a_transform_inspector_counts=%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
                    constants_added, helper_added, snapshot_added, labels_added,
                    counts_changed, checks_added, self_hashes_added, values_added,
                    markers_added > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_source"
}

transform_runner() {
    local base_source=$1
    local inspector_hash=$2

    awk \
        -v inspector_hash="$inspector_hash" \
        -v publisher_sha="$publisher_sha256" \
        -v publisher_manifest_sha="$publisher_backup_manifest_sha256" '
        function transform(v) {
            gsub(/action_17v/, "action_18c_publisher_a", v)
            gsub(/caddy-action17v/, "caddy-action18c-publisher-a", v)
            gsub(/postmigration/, "publisher_postinstall", v)
            return v
        }
        {
            line = transform($0)
        }
        line ~ /^readonly inspector_sha256=/ {
            line = "readonly inspector_sha256=" inspector_hash
            inspector_hash_changed++
        }
        line ~ /^readonly inspector=/ {
            line = "readonly inspector=\"$script_directory/inspect-node-b-publisher-postinstall-acceptance-action18c-publisher-a.sh\""
            inspector_path_changed++
        }
        line ~ /^readonly expected_marker_before_snapshot_sha256=/ {
            print line
            print "readonly expected_publisher_sha256=" publisher_sha
            print "readonly expected_receiver_v2_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e"
            print "readonly expected_authorized_keys_sha256=54eeda8ae3c94e878a38d76ccade91642ba9ab193b5f416ea1bf308a500a1bc1"
            print "readonly expected_publisher_backup_path=/var/backups/caddy-ha/action18c-publisher-prerequisite.TtgS91"
            print "readonly expected_publisher_backup_manifest_sha256=" publisher_manifest_sha
            constants_added++
            next
        }
        line == "    [[ \"$expected_count\" -eq 89 ]] || return 1" {
            sub(/89/, "120", line)
            count_changed++
        }
        line ~ /for marker in finalizer_invoked release_mutated marker_mutated service_mutations/ {
            sub(/finalizer_invoked /, "publisher_invoked authorization_mutated finalizer_invoked ", line)
            marker_validation_added++
        }
        line ~ /action_18c_publisher_a_finalizer_invoked=false action_18c_publisher_a_release_mutated=false/ {
            sub(/action_18c_publisher_a_finalizer_invoked=false /,
                "action_18c_publisher_a_publisher_invoked=false action_18c_publisher_a_authorization_mutated=false action_18c_publisher_a_finalizer_invoked=false ", line)
            fixture_markers_added++
        }
        {
            print line
        }
        line ~ /require_one .*_value_marker_before_snapshot_sha256=/ {
            print "    require_one \"action_18c_publisher_a_value_publisher_sha256=$expected_publisher_sha256\" \"$transcript\" || return 1"
            print "    require_one \"action_18c_publisher_a_value_receiver_v2_sha256=$expected_receiver_v2_sha256\" \"$transcript\" || return 1"
            print "    require_one \"action_18c_publisher_a_value_authorized_keys_sha256=$expected_authorized_keys_sha256\" \"$transcript\" || return 1"
            print "    require_one \"action_18c_publisher_a_value_publisher_backup_path=$expected_publisher_backup_path\" \"$transcript\" || return 1"
            print "    require_one \"action_18c_publisher_a_value_publisher_backup_manifest_sha256=$expected_publisher_backup_manifest_sha256\" \"$transcript\" || return 1"
            validation_values_added++
        }
        line ~ /^            "action_18c_publisher_a_value_marker_before_snapshot_sha256=/ {
            print "            \"action_18c_publisher_a_value_publisher_sha256=$expected_publisher_sha256\" \"action_18c_publisher_a_value_receiver_v2_sha256=$expected_receiver_v2_sha256\" \"action_18c_publisher_a_value_authorized_keys_sha256=$expected_authorized_keys_sha256\" \"action_18c_publisher_a_value_publisher_backup_path=$expected_publisher_backup_path\" \"action_18c_publisher_a_value_publisher_backup_manifest_sha256=$expected_publisher_backup_manifest_sha256\" \\"
            fixture_values_added++
        }
        END {
            if (inspector_hash_changed != 1 || inspector_path_changed != 1 ||
                constants_added != 1 ||
                count_changed != 1 || validation_values_added != 1 ||
                marker_validation_added != 1 || fixture_values_added != 1 ||
                fixture_markers_added != 1) {
                printf "action_18c_publisher_a_transform_runner_counts=%d,%d,%d,%d,%d,%d,%d,%d\n",
                    inspector_hash_changed, inspector_path_changed, constants_added,
                    validation_values_added, marker_validation_added,
                    fixture_values_added, fixture_markers_added > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_source"
}

render_pair() {
    local output_directory=$1
    local base_inspector
    local base_runner
    local rendered_inspector
    local rendered_runner
    local inspector_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    base_inspector=$(mktemp /tmp/caddy-action18c-publisher-a-base-inspector.XXXXXX)
    base_runner=$(mktemp /tmp/caddy-action18c-publisher-a-base-runner.XXXXXX)
    trap 'rm -f -- "$base_inspector" "$base_runner"' RETURN
    render_base inspector "$base_inspector" "$base_inspector_sha256"
    render_base runner "$base_runner" "$base_runner_sha256"
    rendered_inspector="$output_directory/$rendered_inspector_name"
    rendered_runner="$output_directory/$rendered_runner_name"
    transform_inspector "$base_inspector" >"$rendered_inspector"
    chmod 0755 "$rendered_inspector"
    inspector_hash=$(file_hash "$rendered_inspector")
    transform_runner "$base_runner" "$inspector_hash" >"$rendered_runner"
    chmod 0755 "$rendered_runner"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        test_root=$(mktemp -d /tmp/caddy-action18c-publisher-a-derive.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        render_pair "$test_root"
        bash -n "$test_root/$rendered_inspector_name" \
            "$test_root/$rendered_runner_name"
        "$test_root/$rendered_inspector_name" --self-test >/dev/null
        printf 'action_18c_publisher_a_derivation_self_test_complete=true\n'
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_sources
        render_pair "$2"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
