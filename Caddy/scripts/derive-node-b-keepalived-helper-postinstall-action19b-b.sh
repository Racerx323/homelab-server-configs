#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly base_inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly base_runner_sha256=d0f6cc13e4de61dd9105ee4db3afd8f4caead3485d119b6c1e59e488219c4801
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_backup_manifest_sha256=1ea24e88eeab706fe64a4005ddadaf6bda3de1236838f05f82cf630f3f298adc
readonly expected_backup_path=/var/backups/caddy-ha/action19b-retry-node-b-keepalived-helpers.98dYgc
readonly rendered_inspector_name=inspect-node-b-keepalived-helper-postinstall-action19b-b.sh
readonly rendered_runner_name=run-node-b-keepalived-helper-postinstall-action19b-b.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_inspector="$script_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly base_runner="$script_directory/run-node-b-keepalived-helper-prerequisite-action19a-a.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_inspector" && ! -L "$base_inspector" ]] || return 1
    [[ -f "$base_runner" && ! -L "$base_runner" ]] || return 1
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] || return 1
}

transform_inspector() {
    awk \
        -v health_sha="$expected_health_sha256" \
        -v notification_sha="$expected_notification_sha256" \
        -v backup_sha="$expected_backup_manifest_sha256" \
        -v backup_path="$expected_backup_path" '
        function transform(v) {
            gsub(/action_19a_a/, "action_19b_b", v)
            gsub(/caddy-action19a-a-inspector/, "caddy-action19b-b-inspector", v)
            return v
        }
        {
            line = transform($0)
        }
        line == "readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects" {
            print line
            print "readonly expected_backup_path=" backup_path
            print "readonly expected_backup_manifest_sha256=" backup_sha
            constants_added++
            next
        }
        line == "    health_state_absent" {
            print "    health_state_exact"
            health_label_changed++
            next
        }
        line == "    notification_state_supported" {
            print "    notification_state_exact"
            notification_label_changed++
            next
        }
        line == "    notification_not_symlink" {
            print line
            print "    health_metadata_exact"
            print "    health_hash_exact"
            print "    health_syntax"
            print "    health_default_file_regular"
            print "    health_caddy_command_available"
            print "    health_curl_command_available"
            print "    notification_metadata_exact"
            print "    notification_hash_exact"
            print "    notification_syntax"
            print "    notification_jq_command_available"
            print "    notification_logger_command_available"
            print "    notification_endpoint_exact"
            print "    action19b_retry_backup_count_one"
            print "    backup_directory_regular"
            print "    backup_directory_not_symlink"
            print "    backup_directory_metadata_exact"
            print "    backup_manifest_regular"
            print "    backup_manifest_not_symlink"
            print "    backup_manifest_metadata_exact"
            print "    backup_manifest_hash_exact"
            print "    backup_manifest_content_exact"
            print "    action19b_retry_run_stage_count_zero"
            print "    action19b_retry_tmp_stage_count_zero"
            print "    health_install_stage_absent"
            print "    notification_install_stage_absent"
            labels_added++
            next
        }
        line ~ /^        "[$]main_configuration" "[$]keepalived_root" "[$]rollback_root"/ {
            print "        \"$main_configuration\" \"$keepalived_root\" \"$rollback_root\" " sprintf("%c", 92)
            print "        \"$expected_backup_path\" \"$expected_backup_path/manifest\" " sprintf("%c", 92)
            snapshot_paths_changed++
            next
        }
        line == "record_command health_state_absent test \"$health_state\" = absent" {
            print "record_command health_state_exact test \"$health_state\" = exact"
            health_check_changed++
            next
        }
        line == "record_command notification_state_supported state_supported \"$notification_state\"" {
            print "record_command notification_state_exact test \"$notification_state\" = exact"
            notification_check_changed++
            next
        }
        line == "record_command notification_not_symlink test ! -L \"$notification_script\"" {
            print line
            print "record_command health_metadata_exact test \"$(stat -c \047%U:%G:%a\047 \"$health_script\" 2>/dev/null || true)\" = root:root:755"
            print "record_command health_hash_exact test \"$(file_hash \"$health_script\" 2>/dev/null || true)\" = \"$expected_health_sha256\""
            print "record_command health_syntax bash -n \"$health_script\""
            print "record_command health_default_file_regular test -f /etc/default/caddy-ha"
            print "record_command health_caddy_command_available command -v caddy"
            print "record_command health_curl_command_available command -v curl"
            print "record_command notification_metadata_exact test \"$(stat -c \047%U:%G:%a\047 \"$notification_script\" 2>/dev/null || true)\" = root:root:755"
            print "record_command notification_hash_exact test \"$(file_hash \"$notification_script\" 2>/dev/null || true)\" = \"$expected_notification_sha256\""
            print "record_command notification_syntax bash -n \"$notification_script\""
            print "record_command notification_jq_command_available command -v jq"
            print "record_command notification_logger_command_available command -v logger"
            print "record_command notification_endpoint_exact grep -Fq \"readonly apprise_endpoint=\047http://10.1.3.83:8000/notify/apprise\047\" \"$notification_script\""
            print ""
            print "action19b_retry_backup_count=$(find \"$rollback_root\" -mindepth 1 -maxdepth 1 -type d -name \047action19b-retry-node-b-keepalived-helpers.*\047 -printf \047.\047 2>/dev/null | wc -c)"
            print "readonly action19b_retry_backup_count"
            print "action19b_retry_run_stage_count=$(find /run -mindepth 1 -maxdepth 1 -type d -name \047caddy-action19b-retry-stage.*\047 -printf \047.\047 2>/dev/null | wc -c)"
            print "readonly action19b_retry_run_stage_count"
            print "action19b_retry_tmp_stage_count=$(find /tmp -mindepth 1 -maxdepth 1 -type d -name \047caddy-action19b-retry-*\047 ! -path \"$work_directory\" -printf \047.\047 2>/dev/null | wc -c)"
            print "readonly action19b_retry_tmp_stage_count"
            print "record_command action19b_retry_backup_count_one test \"$action19b_retry_backup_count\" -eq 1"
            print "record_command backup_directory_regular test -d \"$expected_backup_path\""
            print "record_command backup_directory_not_symlink test ! -L \"$expected_backup_path\""
            print "record_command backup_directory_metadata_exact test \"$(stat -c \047%U:%G:%a\047 \"$expected_backup_path\" 2>/dev/null || true)\" = root:root:700"
            print "record_command backup_manifest_regular test -f \"$expected_backup_path/manifest\""
            print "record_command backup_manifest_not_symlink test ! -L \"$expected_backup_path/manifest\""
            print "record_command backup_manifest_metadata_exact test \"$(stat -c \047%U:%G:%a\047 \"$expected_backup_path/manifest\" 2>/dev/null || true)\" = root:root:600"
            print "record_command backup_manifest_hash_exact test \"$(file_hash \"$expected_backup_path/manifest\" 2>/dev/null || true)\" = \"$expected_backup_manifest_sha256\""
            print "record_command backup_manifest_content_exact test \"$(<\"$expected_backup_path/manifest\")\" = \"$(printf \047%s\\n\047 \047action=action19b-retry\047 \047health_pre_state=absent\047 \047notification_pre_state=absent\047 \"health_candidate_sha256=$expected_health_sha256\" \"notification_candidate_sha256=$expected_notification_sha256\")\""
            print "record_command action19b_retry_run_stage_count_zero test \"$action19b_retry_run_stage_count\" -eq 0"
            print "record_command action19b_retry_tmp_stage_count_zero test \"$action19b_retry_tmp_stage_count\" -eq 0"
            print "record_command health_install_stage_absent test -z \"$(find /usr/local/libexec -mindepth 1 -maxdepth 1 -name \047.check-caddy.action19b-retry.*\047 -print -quit 2>/dev/null)\""
            print "record_command notification_install_stage_absent test -z \"$(find /usr/local/libexec -mindepth 1 -maxdepth 1 -name \047.lsyncd-ha-failover-notify.action19b-retry.*\047 -print -quit 2>/dev/null)\""
            checks_added++
            next
        }
        line == "    [[ \"${#expected_assertions[@]}\" -eq 61 ]]" {
            print "    [[ \"${#expected_assertions[@]}\" -eq 86 ]]"
            self_count_changed++
            next
        }
        line == "    [[ \"$(printf \047%s\\n\047 \"${expected_assertions[@]}\" | sort -u | wc -l)\" -eq 61 ]]" {
            print "    [[ \"$(printf \047%s\\n\047 \"${expected_assertions[@]}\" | sort -u | wc -l)\" -eq 86 ]]"
            self_unique_changed++
            next
        }
        line ~ /^        "[$]expected_sync_health_sha256"; do/ {
            print "        \"$expected_sync_health_sha256\" \"$expected_backup_manifest_sha256\"; do"
            self_hash_added++
            next
        }
        line ~ /^printf .*_value_action19a_backup_count=/ {
            print "printf \047%s_value_action19b_retry_backup_path=%s\\n\047 \"$prefix\" \"$expected_backup_path\""
            print "printf \047%s_value_action19b_retry_backup_manifest_sha256=%s\\n\047 \"$prefix\" \"$expected_backup_manifest_sha256\""
            print "printf \047%s_value_action19b_retry_backup_count=%s\\n\047 \"$prefix\" \"$action19b_retry_backup_count\""
            print "printf \047%s_value_action19b_retry_run_stage_count=%s\\n\047 \"$prefix\" \"$action19b_retry_run_stage_count\""
            print "printf \047%s_value_action19b_retry_tmp_stage_count=%s\\n\047 \"$prefix\" \"$action19b_retry_tmp_stage_count\""
            print line
            values_added++
            next
        }
        {
            print line
        }
        END {
            if (constants_added != 1 || health_label_changed != 1 ||
                notification_label_changed != 1 || labels_added != 1 ||
                snapshot_paths_changed != 1 || health_check_changed != 1 ||
                notification_check_changed != 1 || checks_added != 1 ||
                self_count_changed != 1 || self_unique_changed != 1 ||
                self_hash_added != 1 || values_added != 1) {
                printf "action_19b_b_transform_inspector_counts=%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\\n",
                    constants_added, health_label_changed,
                    notification_label_changed, labels_added,
                    snapshot_paths_changed, health_check_changed,
                    notification_check_changed, checks_added,
                    self_count_changed, self_unique_changed, self_hash_added,
                    values_added > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_inspector"
}

transform_runner() {
    local inspector_hash=$1

    awk \
        -v inspector_hash="$inspector_hash" \
        -v health_sha="$expected_health_sha256" \
        -v notification_sha="$expected_notification_sha256" \
        -v backup_sha="$expected_backup_manifest_sha256" \
        -v backup_path="$expected_backup_path" '
        function transform(v) {
            gsub(/action_19a_a/, "action_19b_b", v)
            gsub(/ACTION19AA/, "ACTION19BB", v)
            gsub(/caddy-action19a-a/, "caddy-action19b-b", v)
            gsub(/keepalived-helper-prerequisite-action19a-a/, "keepalived-helper-postinstall-action19b-b", v)
            return v
        }
        {
            line = transform($0)
        }
        line ~ /^readonly inspector_sha256=/ {
            print "readonly inspector_sha256=" inspector_hash
            inspector_hash_changed++
            next
        }
        line == "readonly expected_assertion_count=61" {
            print "readonly expected_assertion_count=86"
            assertion_count_changed++
            next
        }
        line == "readonly maximum_stream_bytes=1048576" {
            print "readonly expected_health_sha256=" health_sha
            print "readonly expected_notification_sha256=" notification_sha
            print "readonly expected_backup_path=" backup_path
            print "readonly expected_backup_manifest_sha256=" backup_sha
            print line
            constants_added++
            next
        }
        line == "    is_helper_state \"$health_state\" || return 1" {
            print line
            print "    [[ \"$health_state\" = exact ]] || return 1"
            health_state_validation_added++
            next
        }
        line == "    is_observed_helper_hash \"$health_hash\" || return 1" {
            print line
            print "    [[ \"$health_hash\" = \"$expected_health_sha256\" ]] || return 1"
            health_hash_validation_added++
            next
        }
        line == "    is_helper_state \"$notification_state\" || return 1" {
            print line
            print "    [[ \"$notification_state\" = exact ]] || return 1"
            notification_state_validation_added++
            next
        }
        line == "    is_observed_helper_hash \"$notification_hash\" || return 1" {
            print line
            print "    [[ \"$notification_hash\" = \"$expected_notification_sha256\" ]] || return 1"
            notification_hash_validation_added++
            next
        }
        line ~ /^        action19a_backup_count action19a_run_stage_count/ {
            print "        action19b_retry_backup_count action19b_retry_run_stage_count " sprintf("%c", 92)
            print "        action19b_retry_tmp_stage_count " sprintf("%c", 92)
            print line
            numeric_values_added++
            next
        }
        line ~ /^    for value_key in before_state_sha256 after_state_sha256/ {
            print line
            print "    require_one \"${prefix}_value_action19b_retry_backup_path=$expected_backup_path\" \"$output_path\" || return 1"
            print "    require_one \"${prefix}_value_action19b_retry_backup_manifest_sha256=$expected_backup_manifest_sha256\" \"$output_path\" || return 1"
            required_values_added++
            next
        }
        line == "            \"${prefix}_value_health_state=absent\" \\" {
            print "            \"${prefix}_value_health_state=exact\" " sprintf("%c", 92)
            fixture_health_state_changed++
            next
        }
        line == "            \"${prefix}_value_health_observed_sha256=absent\" \\" {
            print "            \"${prefix}_value_health_observed_sha256=$expected_health_sha256\" " sprintf("%c", 92)
            fixture_health_hash_changed++
            next
        }
        line == "            \"${prefix}_value_notification_state=absent\" \\" {
            print "            \"${prefix}_value_notification_state=exact\" " sprintf("%c", 92)
            fixture_notification_state_changed++
            next
        }
        line == "            \"${prefix}_value_notification_observed_sha256=absent\" \\" {
            print "            \"${prefix}_value_notification_observed_sha256=$expected_notification_sha256\" " sprintf("%c", 92)
            print "            \"${prefix}_value_action19b_retry_backup_path=$expected_backup_path\" " sprintf("%c", 92)
            print "            \"${prefix}_value_action19b_retry_backup_manifest_sha256=$expected_backup_manifest_sha256\" " sprintf("%c", 92)
            print "            \"${prefix}_value_action19b_retry_backup_count=1\" " sprintf("%c", 92)
            print "            \"${prefix}_value_action19b_retry_run_stage_count=0\" " sprintf("%c", 92)
            print "            \"${prefix}_value_action19b_retry_tmp_stage_count=0\" " sprintf("%c", 92)
            fixture_notification_hash_changed++
            next
        }
        {
            print line
        }
        END {
            if (inspector_hash_changed != 1 || assertion_count_changed != 1 ||
                constants_added != 1 || health_state_validation_added != 1 ||
                health_hash_validation_added != 1 ||
                notification_state_validation_added != 1 ||
                notification_hash_validation_added != 1 ||
                numeric_values_added != 1 || required_values_added != 1 ||
                fixture_health_state_changed != 1 ||
                fixture_health_hash_changed != 1 ||
                fixture_notification_state_changed != 1 ||
                fixture_notification_hash_changed != 1) {
                printf "action_19b_b_transform_runner_counts=%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\\n",
                    inspector_hash_changed, assertion_count_changed,
                    constants_added, health_state_validation_added,
                    health_hash_validation_added,
                    notification_state_validation_added,
                    notification_hash_validation_added, numeric_values_added,
                    required_values_added, fixture_health_state_changed,
                    fixture_health_hash_changed,
                    fixture_notification_state_changed,
                    fixture_notification_hash_changed > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_runner"
}

render_pair() {
    local output_directory=$1
    local inspector_path="$output_directory/$rendered_inspector_name"
    local runner_path="$output_directory/$rendered_runner_name"
    local inspector_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    transform_inspector >"$inspector_path"
    chmod 0755 "$inspector_path"
    inspector_hash=$(file_hash "$inspector_path")
    transform_runner "$inspector_hash" >"$runner_path"
    chmod 0755 "$runner_path"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        test_root=$(mktemp -d /tmp/caddy-action19b-b-derive.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        render_pair "$test_root"
        bash -n "$test_root/$rendered_inspector_name" \
            "$test_root/$rendered_runner_name"
        "$test_root/$rendered_inspector_name" --self-test >/dev/null
        printf 'action_19b_b_derivation_self_test_complete=true\n'
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
