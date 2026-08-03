#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly base_derivation_sha256=4e90f157b81110384d50d00fc0d0377a9733787260c056555d0b3c359379a51c
readonly historical_inspector_sha256=38df35f89dc5732320e84ef9ec90ff8b0d5d1cee72d342b025c743c74a0d4210
readonly historical_runner_sha256=facbaeda449522296cb90febf8fc0cbe4472129a35f960f9415e5aa5fb248ea2
readonly base_inspector_sha256=d579c51913ab6fc664550f8f966ed49fac50fd37c6c22890a1d04097018806c5
readonly base_runner_sha256=07e07a07c84a1d7b80792ff8f86bf420d4f323b51baf88fab424c49d93efc644
readonly corrected_inspector_sha256=216ee51b429048b0304e76d0b75402f4306470d012f170debb1352951efd5910
readonly corrected_runner_sha256=cb85c0c63faba81db701f6d02be092df3150dd38a3b926bc785c0b067f54ebad

derivation_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly derivation_directory
readonly base_derivation="$derivation_directory/derive-node-b-action17u-postrepair-acceptance-action17u-c.sh"
readonly historical_inspector="$derivation_directory/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly historical_runner="$derivation_directory/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly collision_checker="$derivation_directory/../tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local verification_path=$1
    local verification_hash=$2

    [[ -f "$verification_path" && ! -L "$verification_path" ]] || return 1
    [[ "$(file_hash "$verification_path")" == "$verification_hash" ]] || return 1
}

render_base_inspector() {
    local output_path=$1

    verify_file "$base_derivation" "$base_derivation_sha256" || return 1
    verify_file "$historical_inspector" "$historical_inspector_sha256" || return 1
    "$base_derivation" --render-inspector "$historical_inspector" >"$output_path"
    [[ "$(file_hash "$output_path")" == "$base_inspector_sha256" ]] || return 1
}

render_base_runner() {
    local output_path=$1

    verify_file "$base_derivation" "$base_derivation_sha256" || return 1
    verify_file "$historical_runner" "$historical_runner_sha256" || return 1
    "$base_derivation" --render-runner "$historical_runner" >"$output_path"
    [[ "$(file_hash "$output_path")" == "$base_runner_sha256" ]] || return 1
}

transform_inspector() {
    local base_source=$1

    awk '
        {
            line = $0
            gsub(/action_17u_c/, "action_17v", line)
            gsub(/caddy-action17u-c/, "caddy-action17v", line)
            gsub(/postrepair/, "postmigration", line)
        }
        line ~ /^readonly expected_manifest_sha256=/ {
            print line
            print "readonly marker_backup_directory=/var/backups/caddy-ha/action17s-retry2-node-b-marker-migration.K3K5zO"
            print "readonly marker_backup_snapshot=\"$marker_backup_directory/release.before\""
            print "readonly marker_backup_hash_record=\"$marker_backup_directory/release.before.sha256\""
            print "readonly expected_marker_before_snapshot_sha256=3df6a1b8ff8adf6e8ce30762b86bc9e25b2fc072ba4458fdc889e631892796a4"
            constants_added++
            next
        }
        line ~ /[$]prior_backup_directory.*[$]prior_backup_manifest.*\/etc\/caddy\/current; do/ {
            print "        \"$prior_backup_directory\" \"$prior_backup_manifest\" " "\\"
            print "        \"$marker_backup_directory\" \"$marker_backup_snapshot\" " "\\"
            print "        \"$marker_backup_hash_record\" /etc/caddy/current; do"
            snapshot_paths_changed++
            next
        }
        line ~ /[$]prior_backup_manifest.*[$]release\/manifest[.]sha256.*; do/ {
            print "        \"$prior_backup_manifest\" \"$release/manifest.sha256\" " "\\"
            print "        \"$marker_backup_snapshot\" \"$marker_backup_hash_record\"; do"
            snapshot_hashes_changed++
            next
        }
        line ~ /release_directory release_not_symlink release_metadata request_absent/ {
            print "        release_directory release_not_symlink release_metadata request_regular " "\\"
            marker_labels_changed++
            next
        }
        line ~ /request_not_symlink pending_absent pending_not_symlink complete_absent/ {
            print "        request_not_symlink request_empty request_metadata pending_absent " "\\"
            print "        pending_not_symlink complete_regular complete_not_symlink complete_empty " "\\"
            marker_labels_changed++
            next
        }
        line ~ /complete_not_symlink release_directories_locked/ {
            sub(/complete_not_symlink /, "complete_metadata ", line)
            marker_labels_changed++
        }
        line ~ /lsyncd_configuration_not_symlink transaction_stage_count_zero repair_stage_count_zero/ {
            print "        lsyncd_configuration_not_symlink transaction_stage_count_zero " "\\"
            print "        repair_stage_count_zero marker_backup_count_one " "\\"
            print "        marker_backup_directory marker_backup_not_symlink marker_backup_metadata " "\\"
            print "        marker_backup_snapshot_regular marker_backup_snapshot_not_symlink " "\\"
            print "        marker_backup_snapshot_metadata marker_backup_snapshot_hash_exact " "\\"
            print "        marker_backup_hash_record_regular marker_backup_hash_record_not_symlink " "\\"
            print "        marker_backup_hash_record_metadata marker_backup_hash_record_content_exact " "\\"
            print "        marker_transaction_stage_count_zero " "\\"
            backup_labels_added++
            next
        }
        line == "        [[ \"$(expected_check_labels | wc -l)\" -eq 72 ]] || exit 1" {
            sub(/72/, "89", line)
            counts_changed++
        }
        line == "        [[ \"$(expected_check_labels | sort -u | wc -l)\" -eq 72 ]] || exit 1" {
            sub(/72/, "89", line)
            counts_changed++
        }
        line ~ /^record_command request_absent / {
            print "record_command request_regular test -f \"$release/.finalize-request\""
            print "record_command request_not_symlink test ! -L \"$release/.finalize-request\""
            print "record_command request_empty test ! -s \"$release/.finalize-request\""
            print "record_command request_metadata test \"$(stat -c \047%U:%G:%a\047 \"$release/.finalize-request\" 2>/dev/null || true)\" = caddy-sync:caddy-sync:440"
            request_checks_changed++
            next
        }
        line ~ /^record_command request_not_symlink / { next }
        line ~ /^record_command complete_absent / {
            print "record_command complete_regular test -f \"$release/.complete\""
            print "record_command complete_not_symlink test ! -L \"$release/.complete\""
            print "record_command complete_empty test ! -s \"$release/.complete\""
            print "record_command complete_metadata test \"$(stat -c \047%U:%G:%a\047 \"$release/.complete\" 2>/dev/null || true)\" = caddy-sync:caddy-sync:440"
            complete_checks_changed++
            next
        }
        line ~ /^record_command complete_not_symlink / { next }
        {
            print line
        }
        line ~ /^record_command prior_backup_manifest_hash_exact / {
            print "record_command marker_backup_count_one test \"$(find \"$rollback_root\" -mindepth 1 -maxdepth 1 -type d -name \047action17s-retry2-node-b-marker-migration.*\047 -print 2>/dev/null | wc -l)\" -eq 1"
            print "record_command marker_backup_directory test -d \"$marker_backup_directory\""
            print "record_command marker_backup_not_symlink test ! -L \"$marker_backup_directory\""
            print "record_command marker_backup_metadata test \"$(stat -c \047%U:%G:%a\047 \"$marker_backup_directory\" 2>/dev/null || true)\" = root:root:700"
            print "record_command marker_backup_snapshot_regular test -f \"$marker_backup_snapshot\""
            print "record_command marker_backup_snapshot_not_symlink test ! -L \"$marker_backup_snapshot\""
            print "record_command marker_backup_snapshot_metadata test \"$(stat -c \047%U:%G:%a\047 \"$marker_backup_snapshot\" 2>/dev/null || true)\" = root:root:600"
            print "record_command marker_backup_snapshot_hash_exact test \"$(file_hash \"$marker_backup_snapshot\" 2>/dev/null || true)\" = \"$expected_marker_before_snapshot_sha256\""
            print "record_command marker_backup_hash_record_regular test -f \"$marker_backup_hash_record\""
            print "record_command marker_backup_hash_record_not_symlink test ! -L \"$marker_backup_hash_record\""
            print "record_command marker_backup_hash_record_metadata test \"$(stat -c \047%U:%G:%a\047 \"$marker_backup_hash_record\" 2>/dev/null || true)\" = root:root:600"
            print "record_command marker_backup_hash_record_content_exact test \"$(tr -d \047\\n\047 <\"$marker_backup_hash_record\" 2>/dev/null || true)\" = \"$expected_marker_before_snapshot_sha256\""
            backup_checks_added++
        }
        line ~ /^record_command repair_stage_count_zero / {
            print "record_command marker_transaction_stage_count_zero test \"$(find /run -mindepth 1 -maxdepth 1 -type d -name \047caddy-action17s-retry2-node-b.*\047 -print 2>/dev/null | wc -l)\" -eq 0"
            stage_check_added++
        }
        line == "        done" {
            print "        is_sha256 \"$expected_marker_before_snapshot_sha256\" || exit 1"
            self_hash_added++
        }
        line ~ /printf .*_value_manifest_sha256/ {
            print "printf \047%s_value_marker_backup_path=%s\\n\047 \"$prefix\" \"$marker_backup_directory\""
            print "printf \047%s_value_marker_before_snapshot_sha256=%s\\n\047 \"$prefix\" \"$expected_marker_before_snapshot_sha256\""
            values_added++
        }
        END {
            if (constants_added != 1 || snapshot_paths_changed != 1 ||
                snapshot_hashes_changed != 1 || marker_labels_changed != 3 ||
                backup_labels_added != 1 || counts_changed != 2 ||
                request_checks_changed != 1 || complete_checks_changed != 1 ||
                backup_checks_added != 1 || stage_check_added != 1 ||
                self_hash_added != 1 || values_added != 1) {
                exit 42
            }
        }
    ' "$base_source"
}

transform_runner() {
    local base_source=$1

    awk -v inspector_hash="$corrected_inspector_sha256" '
        {
            line = $0
            gsub(/action_17u_c/, "action_17v", line)
            gsub(/caddy-action17u-c/, "caddy-action17v", line)
            gsub(/postrepair/, "postmigration", line)
        }
        line ~ /^readonly inspector_sha256=/ {
            line = "readonly inspector_sha256=" inspector_hash
            inspector_hash_changed++
        }
        line ~ /^readonly inspector=/ {
            line = "readonly inspector=\"$script_directory/inspect-node-b-postmigration-acceptance-action17v.sh\""
            inspector_path_changed++
        }
        line ~ /^readonly expected_manifest_sha256=/ {
            print line
            print "readonly expected_marker_backup_path=/var/backups/caddy-ha/action17s-retry2-node-b-marker-migration.K3K5zO"
            print "readonly expected_marker_before_snapshot_sha256=3df6a1b8ff8adf6e8ce30762b86bc9e25b2fc072ba4458fdc889e631892796a4"
            constants_added++
            next
        }
        line == "    [[ \"$expected_count\" -eq 72 ]] || return 1" {
            sub(/72/, "89", line)
            count_changed++
        }
        {
            print line
        }
        line ~ /require_one .*_value_manifest_sha256=/ {
            print "    require_one \"action_17v_value_marker_backup_path=$expected_marker_backup_path\" \"$transcript\" || return 1"
            print "    require_one \"action_17v_value_marker_before_snapshot_sha256=$expected_marker_before_snapshot_sha256\" \"$transcript\" || return 1"
            validation_values_added++
        }
        line ~ /^            "action_17v_value_manifest_sha256=[$]expected_manifest_sha256"/ {
            print "            \"action_17v_value_marker_backup_path=$expected_marker_backup_path\" " "\\"
            print "            \"action_17v_value_marker_before_snapshot_sha256=$expected_marker_before_snapshot_sha256\" " "\\"
            fixture_values_added++
        }
        END {
            if (inspector_hash_changed != 1 || inspector_path_changed != 1 ||
                constants_added != 1 || count_changed != 1 ||
                validation_values_added != 1 || fixture_values_added != 1) {
                exit 42
            }
        }
    ' "$base_source"
}

render_inspector() {
    local inspector_output

    inspector_output=$(mktemp /tmp/caddy-action17v-base-inspector.XXXXXX)
    trap 'rm -f -- "$inspector_output"' RETURN
    render_base_inspector "$inspector_output"
    transform_inspector "$inspector_output"
    rm -f -- "$inspector_output"
    trap - RETURN
}

render_runner() {
    local runner_output

    runner_output=$(mktemp /tmp/caddy-action17v-base-runner.XXXXXX)
    trap 'rm -f -- "$runner_output"' RETURN
    render_base_runner "$runner_output"
    transform_runner "$runner_output"
    rm -f -- "$runner_output"
    trap - RETURN
}

self_test() {
    local self_root self_scripts self_tests rendered_inspector rendered_runner

    self_root=$(mktemp -d /tmp/caddy-action17v-derivation.XXXXXX)
    trap '[[ -z ${self_root:-} ]] || rm -rf -- "$self_root"' EXIT
    self_scripts="$self_root/Caddy/scripts"
    self_tests="$self_root/Caddy/tests"
    rendered_inspector="$self_scripts/inspect-node-b-postmigration-acceptance-action17v.sh"
    rendered_runner="$self_scripts/run-node-b-postmigration-acceptance-action17v.sh"
    install -d -m 0700 "$self_scripts" "$self_tests"
    install -m 0755 -- "$collision_checker" "$self_tests/${collision_checker##*/}"
    render_inspector >"$rendered_inspector"
    render_runner >"$rendered_runner"
    chmod 0755 "$rendered_inspector" "$rendered_runner"
    [[ "$(file_hash "$rendered_inspector")" == "$corrected_inspector_sha256" ]]
    [[ "$(file_hash "$rendered_runner")" == "$corrected_runner_sha256" ]]
    bash -n "$rendered_inspector" "$rendered_runner"
    "$rendered_inspector" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
    rm -rf -- "$self_root"
    self_root=
    trap - EXIT
    printf 'action_17v_derivation_self_test_complete=true\n'
}

case "${1:-}" in
    --render-inspector)
        [[ $# -eq 1 ]] || exit 64
        render_inspector
        ;;
    --render-runner)
        [[ $# -eq 1 ]] || exit 64
        render_runner
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *)
        printf 'Usage: %s --render-inspector | --render-runner | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
