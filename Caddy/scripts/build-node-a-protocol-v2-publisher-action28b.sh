#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28b_builder
readonly base_driver_sha256=6e1580798f40e5d056018f52bc9346f0366326f21685810b906b60a66da2c8bd
readonly retained_name=action17p-node-a-to-node-b-bootstrap
readonly retained_root_metadata=994:990:750:4096:1785461698
readonly retained_child_metadata=994:990:550:4096:1785461697
readonly retained_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_driver=$script_directory/install-node-a-protocol-v2-publisher-action28a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
verify_source() {
    [[ -f "$base_driver" && ! -L "$base_driver" ]] || return 1
    [[ "$(file_hash "$base_driver")" == "$base_driver_sha256" ]]
}
render_driver() {
    local action28b_builder_output=$1

    awk \
        -v retained_name="$retained_name" \
        -v root_metadata="$retained_root_metadata" \
        -v child_metadata="$retained_child_metadata" \
        -v tree_sha256="$retained_tree_sha256" '
        function emit_constants() {
            print "retained_outbound_name=" retained_name
            print "retained_outbound_root_metadata=" root_metadata
            print "retained_outbound_child_metadata=" child_metadata
            print "retained_outbound_tree_sha256=" tree_sha256
        }
        function emit_pre_checks() {
            print "record_check outbound_root_metadata_exact test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$outbound_root\")\" = \"$retained_outbound_root_metadata\" || exit 1"
            print "record_check outbound_child_count_exact test \"$(find \"$outbound_root\" -mindepth 1 -maxdepth 1 -printf \047.\047 | wc -c)\" -eq 1 || exit 1"
            print "record_check retained_child_directory test -d \"$retained_outbound_path\" || exit 1"
            print "record_check retained_child_not_symlink test ! -L \"$retained_outbound_path\" || exit 1"
            print "record_check retained_child_metadata_exact test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$retained_outbound_path\")\" = \"$retained_outbound_child_metadata\" || exit 1"
            print "record_check retained_child_tree_hash_exact test \"$(tree_digest \"$retained_outbound_path\")\" = \"$retained_outbound_tree_sha256\" || exit 1"
            print "record_check retained_finalize_request_absent test ! -e \"$retained_outbound_path/.finalize-request\" || exit 1"
            print "record_check retained_finalize_request_not_symlink test ! -L \"$retained_outbound_path/.finalize-request\" || exit 1"
            print "record_check retained_complete_regular test -f \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_not_symlink test ! -L \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_empty test ! -s \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_pending_absent test ! -e \"$retained_outbound_path/.complete.pending\" || exit 1"
            print "record_check retained_complete_pending_not_symlink test ! -L \"$retained_outbound_path/.complete.pending\" || exit 1"
        }
        function emit_post_checks() {
            print "record_check outbound_root_metadata_unchanged test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$outbound_root\")\" = \"$retained_outbound_root_metadata\" || exit 1"
            print "record_check outbound_child_count_unchanged test \"$(find \"$outbound_root\" -mindepth 1 -maxdepth 1 -printf \047.\047 | wc -c)\" -eq 1 || exit 1"
            print "record_check retained_child_directory_after test -d \"$retained_outbound_path\" || exit 1"
            print "record_check retained_child_not_symlink_after test ! -L \"$retained_outbound_path\" || exit 1"
            print "record_check retained_child_metadata_unchanged test \"$(stat -c \047%u:%g:%a:%s:%Y\047 \"$retained_outbound_path\")\" = \"$retained_outbound_child_metadata\" || exit 1"
            print "record_check retained_child_tree_hash_unchanged test \"$(tree_digest \"$retained_outbound_path\")\" = \"$retained_outbound_tree_sha256\" || exit 1"
            print "record_check retained_finalize_request_absent_after test ! -e \"$retained_outbound_path/.finalize-request\" || exit 1"
            print "record_check retained_finalize_request_not_symlink_after test ! -L \"$retained_outbound_path/.finalize-request\" || exit 1"
            print "record_check retained_complete_regular_after test -f \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_not_symlink_after test ! -L \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_empty_after test ! -s \"$retained_outbound_path/.complete\" || exit 1"
            print "record_check retained_complete_pending_absent_after test ! -e \"$retained_outbound_path/.complete.pending\" || exit 1"
            print "record_check retained_complete_pending_not_symlink_after test ! -L \"$retained_outbound_path/.complete.pending\" || exit 1"
        }
        /^readonly empty_sha256=/ {
            print
            emit_constants()
            constants++
            next
        }
        /outbound_root_not_symlink outbound_root_empty sync_tree_before_hash_valid/ {
            sub(/outbound_root_empty/, "outbound_root_metadata_exact outbound_child_count_exact \\\n        retained_child_directory retained_child_not_symlink retained_child_metadata_exact \\\n        retained_child_tree_hash_exact retained_finalize_request_absent \\\n        retained_finalize_request_not_symlink retained_complete_regular \\\n        retained_complete_not_symlink retained_complete_empty \\\n        retained_complete_pending_absent retained_complete_pending_not_symlink")
            pre_labels++
        }
        /service_state_unchanged vrrp_master_after outbound_root_still_empty/ {
            sub(/outbound_root_still_empty/, "outbound_root_metadata_unchanged \\\n        outbound_child_count_unchanged retained_child_directory_after \\\n        retained_child_not_symlink_after retained_child_metadata_unchanged \\\n        retained_child_tree_hash_unchanged retained_finalize_request_absent_after \\\n        retained_finalize_request_not_symlink_after retained_complete_regular_after \\\n        retained_complete_not_symlink_after retained_complete_empty_after \\\n        retained_complete_pending_absent_after retained_complete_pending_not_symlink_after")
            post_labels++
        }
        /^record_check outbound_root_empty test -z/ {
            getline
            emit_pre_checks()
            pre_checks++
            next
        }
        /^record_check outbound_root_still_empty test -z/ {
            getline
            emit_post_checks()
            post_checks++
            next
        }
        /^readonly current_link outbound_root sync_root$/ {
            print
            print "retained_outbound_path=$outbound_root/$retained_outbound_name"
            print "readonly retained_outbound_path"
            retained_path++
            next
        }
        /^        test_mode=true$/ {
            print
            print "        retained_outbound_root_metadata=${CADDY_ACTION28B_TEST_ROOT_METADATA:?}"
            print "        retained_outbound_child_metadata=${CADDY_ACTION28B_TEST_CHILD_METADATA:?}"
            print "        retained_outbound_tree_sha256=${CADDY_ACTION28B_TEST_TREE_SHA256:?}"
            fixture_values++
            next
        }
        /^readonly test_mode root_prefix stage_directory expected_owner install_owner install_group$/ {
            print
            print "readonly retained_outbound_name retained_outbound_root_metadata"
            print "readonly retained_outbound_child_metadata retained_outbound_tree_sha256"
            retained_readonly++
            next
        }
        /'action=28a'/ {
            gsub(/action=28a/, "action=28b")
            action_manifest++
        }
        /^    printf .*value_publisher_pre_state=absent/ {
            print
            print "    printf \047%s_value_retained_outbound_name=%s\\n\047 \"$prefix\" \"$retained_outbound_name\""
            print "    printf \047%s_value_retained_outbound_tree_sha256=%s\\n\047 \"$prefix\" \"$retained_outbound_tree_sha256\""
            contract_values++
            next
        }
        /^printf .%s_value_publisher_pre_state=absent/ {
            print
            print "printf \047%s_value_retained_outbound_name=%s\\n\047 \"$prefix\" \"$retained_outbound_name\""
            print "printf \047%s_value_retained_outbound_tree_sha256=%s\\n\047 \"$prefix\" \"$retained_outbound_tree_sha256\""
            runtime_values++
            next
        }
        {
            gsub(/action_28a/, "action_28b")
            gsub(/action28a/, "action28b")
            gsub(/ACTION28A/, "ACTION28B")
            print
        }
        END {
            if (constants != 1 || pre_labels != 1 || post_labels != 1 ||
                pre_checks != 1 || post_checks != 1 || retained_path != 1 ||
                contract_values != 1 || runtime_values != 1 || fixture_values != 1 ||
                retained_readonly != 1 || action_manifest != 2) {
                printf "action_28b_transform_counts=%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
                    constants, pre_labels, post_labels, pre_checks, post_checks,
                    retained_path, contract_values, runtime_values, fixture_values,
                    retained_readonly, action_manifest > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_driver" >"$action28b_builder_output"
    chmod 0700 "$action28b_builder_output"
    /bin/bash -n "$action28b_builder_output"
}
self_test() {
    local action28b_builder_root
    local action28b_builder_rendered

    verify_source
    action28b_builder_root=$(mktemp -d /tmp/caddy-action28b-builder.XXXXXX)
    trap 'rm -rf -- "$action28b_builder_root"' RETURN
    action28b_builder_rendered=$action28b_builder_root/driver.sh
    render_driver "$action28b_builder_rendered"
    grep -Fq 'readonly prefix=action_28b' "$action28b_builder_rendered"
    grep -Fq 'record_check retained_child_tree_hash_exact' "$action28b_builder_rendered"
    grep -Fq 'record_check retained_child_tree_hash_unchanged' "$action28b_builder_rendered"
    if grep -Fq 'outbound_root_empty' "$action28b_builder_rendered"; then
        return 1
    fi
    if grep -Fq 'outbound_root_still_empty' "$action28b_builder_rendered"; then
        return 1
    fi
    printf '%s_rendered_sha256=%s\n' "$prefix" "$(file_hash "$action28b_builder_rendered")"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --render)
        [[ $# -eq 2 ]] || exit 64
        verify_source
        render_driver "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *) exit 64 ;;
esac
