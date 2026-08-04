#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_a_retry
readonly base_derivation_sha256=f128432030f4fce0be7d2ab71a24fd70f9a966cbd14113b7b5cde02ccabb4f89
readonly base_inspector_sha256=ca6eac99ab383bc02cfb8e9f8468532011324a5d9dcd1b893ca5ac624600ccc5
readonly base_runner_sha256=83f01bb634a17c9b9d283aaf7d304055a79f623cf5bf6fed38a2fb2f5cf9e2fa
readonly transcribed_tree_sha256=dad64e4ac7fdbaab2dbdc4bf88feab59d4b6f99ee51ac562e67f968967072f66
readonly expected_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly rendered_inspector_name=inspect-node-a-keepalived-helper-postinstall-action19d-a-retry.sh
readonly rendered_runner_name=run-node-a-keepalived-helper-postinstall-action19d-a-retry.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_derivation="$script_directory/derive-node-a-keepalived-helper-postinstall-action19d-a.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_derivation" && ! -L "$base_derivation" ]] || return 1
    [[ "$(file_hash "$base_derivation")" = "$base_derivation_sha256" ]] ||
        return 1
}

transform_common() {
    sed \
        -e 's/action_19d_a/action_19d_a_retry/g' \
        -e 's/action19d-a/action19d-a-retry/g' \
        -e 's/ACTION19DA/ACTION19DARETRY/g' \
        -e 's/CADDY_ACTION19DA/CADDY_ACTION19DARETRY/g' \
        -e "s/$transcribed_tree_sha256/$expected_tree_sha256/g" \
        "$1"
}

transform_inspector() {
    local source_path=$1
    local output_path=$2
    local transformed_path

    transformed_path=$(mktemp /tmp/caddy-action19d-a-retry-inspector.XXXXXX) ||
        return 1
    transform_common "$source_path" >"$transformed_path"
    awk '
        $0 == "record_command keepalived_tree_hash_exact test \\" {
            print "observed_keepalived_tree_sha256=$(tree_hash \"$keepalived_root\" 2>/dev/null || true)"
            print "readonly observed_keepalived_tree_sha256"
            print "record_command keepalived_tree_hash_exact test \\"
            print "    \"$observed_keepalived_tree_sha256\" = \\"
            print "    \"$expected_keepalived_tree_sha256\""
            getline
            getline
            next
        }
        $0 == "printf \x27%s_value_health_state=%s\\n\x27 \"$prefix\" \"$health_state\"" {
            print "printf \x27%s_value_keepalived_tree_expected_sha256=%s\\n\x27 \"$prefix\" \\"
            print "    \"$expected_keepalived_tree_sha256\""
            print "printf \x27%s_value_keepalived_tree_observed_sha256=%s\\n\x27 \"$prefix\" \\"
            print "    \"$observed_keepalived_tree_sha256\""
        }
        { print }
    ' "$transformed_path" >"$output_path"
    rm -f -- "$transformed_path"
    chmod 0755 "$output_path"
}

transform_runner() {
    local source_path=$1
    local inspector_hash=$2
    local output_path=$3
    local transformed_path

    transformed_path=$(mktemp /tmp/caddy-action19d-a-retry-runner.XXXXXX) ||
        return 1
    transform_common "$source_path" |
        sed \
            -e "s/$base_inspector_sha256/$inspector_hash/g" \
            -e 's#inspect-node-a-keepalived-helper-postinstall-action19d-a\.sh#inspect-node-a-keepalived-helper-postinstall-action19d-a-retry.sh#g' \
            >"$transformed_path"
    awk -v expected_hash="$expected_tree_sha256" '
        $0 == "readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8" {
            print
            print "readonly expected_keepalived_tree_sha256=" expected_hash
            next
        }
        $0 == "    health_state=$(value_for \"${prefix}_value_health_state\" \"$output_path\") ||" {
            print "    contract_keepalived_tree_hash=$(value_for \\"
            print "        \"${prefix}_value_keepalived_tree_observed_sha256\" \\"
            print "        \"$output_path\") || return 1"
            print "    is_sha256 \"$contract_keepalived_tree_hash\" || return 1"
            print "    [[ \"$contract_keepalived_tree_hash\" = \\"
            print "        \"$expected_keepalived_tree_sha256\" ]] || return 1"
            print "    require_one \\"
            print "        \"${prefix}_value_keepalived_tree_expected_sha256=$expected_keepalived_tree_sha256\" \\"
            print "        \"$output_path\" || return 1"
        }
        $0 == "            \"${prefix}_value_health_state=exact\" \\" {
            print "            \"${prefix}_value_keepalived_tree_expected_sha256=$expected_keepalived_tree_sha256\" \\"
            print "            \"${prefix}_value_keepalived_tree_observed_sha256=$expected_keepalived_tree_sha256\" \\"
        }
        $0 == "        printf \x27%s_runner_contract_test_complete=true\\n\x27 \"$prefix\"" {
            print "        sed \\"
            print "            \"s/${prefix}_value_keepalived_tree_observed_sha256=$expected_keepalived_tree_sha256/${prefix}_value_keepalived_tree_observed_sha256=0000000000000000000000000000000000000000000000000000000000000000/\" \\"
            print "            \"$contract_directory/output\" >\"$contract_directory/tree-mismatch\""
            print "        if evaluate_contract \"$contract_directory/error\" \\"
            print "            \"$contract_directory/tree-mismatch\" 0; then"
            print "            exit 1"
            print "        fi"
            print "        printf \x27%s_runner_contract_tree_mismatch_rejected=true\\n\x27 \"$prefix\""
        }
        $0 == "    local health_hash" {
            print "    local contract_keepalived_tree_hash"
        }
        { print }
    ' "$transformed_path" >"$output_path"
    rm -f -- "$transformed_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local base_root
    local base_inspector
    local base_runner
    local rendered_inspector
    local rendered_runner
    local rendered_inspector_sha256

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    base_root=$(mktemp -d /tmp/caddy-action19d-a-retry-base.XXXXXX) ||
        return 1
    /bin/bash "$base_derivation" --output-directory "$base_root" || {
        rm -rf -- "$base_root"
        return 1
    }
    base_inspector=$base_root/inspect-node-a-keepalived-helper-postinstall-action19d-a.sh
    base_runner=$base_root/run-node-a-keepalived-helper-postinstall-action19d-a.sh
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] || {
        rm -rf -- "$base_root"
        return 1
    }
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] || {
        rm -rf -- "$base_root"
        return 1
    }
    rendered_inspector=$output_directory/$rendered_inspector_name
    rendered_runner=$output_directory/$rendered_runner_name
    transform_inspector "$base_inspector" "$rendered_inspector"
    rendered_inspector_sha256=$(file_hash "$rendered_inspector")
    transform_runner "$base_runner" "$rendered_inspector_sha256" \
        "$rendered_runner"
    rm -rf -- "$base_root"

    grep -Fq "readonly expected_keepalived_tree_sha256=$expected_tree_sha256" \
        "$rendered_inspector" "$rendered_runner" || return 1
    ! grep -Fq "$transcribed_tree_sha256" "$rendered_inspector" \
        "$rendered_runner" || return 1
    grep -Fq "\${prefix}_value_keepalived_tree_observed_sha256" \
        "$rendered_inspector" "$rendered_runner" || return 1
}

self_test() {
    local self_test_root

    verify_sources || return 1
    self_test_root=$(mktemp -d /tmp/caddy-action19d-a-retry-derive.XXXXXX) ||
        return 1
    render_pair "$self_test_root" || {
        rm -rf -- "$self_test_root"
        return 1
    }
    bash -n "$self_test_root/$rendered_inspector_name" \
        "$self_test_root/$rendered_runner_name" || {
        rm -rf -- "$self_test_root"
        return 1
    }
    /bin/bash "$self_test_root/$rendered_inspector_name" --self-test \
        >/dev/null || {
        rm -rf -- "$self_test_root"
        return 1
    }
    rm -rf -- "$self_test_root"
    printf '%s_derivation_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
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
