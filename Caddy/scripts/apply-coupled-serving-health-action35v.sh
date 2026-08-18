#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_35_v
readonly node_a_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly serving_revision=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca
readonly serving_parent=$node_a_revision
readonly serving_payload_manifest_sha256=${ACTION35V_SERVING_PAYLOAD_MANIFEST_SHA256:-ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962}
readonly retained_name=action17p-node-a-to-node-b-bootstrap
readonly retained_release_manifest_sha256=${ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256:-81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3}
readonly retained_payload_manifest_sha256=${ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256:-f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8}
readonly legacy_lighttpd_helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly legacy_lighttpd_helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly incoming_root=${ACTION35V_INCOMING_ROOT:-/var/lib/caddy-sync/incoming}
readonly outgoing_root=${ACTION35V_OUTGOING_ROOT:-/var/lib/caddy-sync/outbound}
readonly quarantine_root=${ACTION35V_QUARANTINE_ROOT:-/var/lib/caddy-sync/quarantine}
readonly releases_root=${ACTION35V_RELEASES_ROOT:-/etc/caddy/releases}
readonly node_environment=${ACTION35V_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly runuser_command=${ACTION35V_RUNUSER_COMMAND:-/usr/sbin/runuser}
readonly finalizer_command=${ACTION35V_FINALIZER_COMMAND:-/usr/local/libexec/finalize-incoming-release-v2.sh}
readonly sync_user=${ACTION35V_SYNC_USER:-caddy-sync}
readonly sync_group=${ACTION35V_SYNC_GROUP:-caddy-sync}
readonly systemctl_command=${ACTION35V_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly journalctl_command=${ACTION35V_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
readonly unbound_checkconf_command=${ACTION35V_UNBOUND_CHECKCONF_COMMAND:-/usr/sbin/unbound-checkconf}
readonly target_root=${ACTION35V_TARGET_ROOT:-}

if [[ -n "${ACTION35V_INCOMING_ROOT:-}${ACTION35V_OUTGOING_ROOT:-}${ACTION35V_QUARANTINE_ROOT:-}${ACTION35V_RELEASES_ROOT:-}${ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256:-}${ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256:-}${ACTION35V_QUARANTINE_INVENTORY_MANIFEST:-}${ACTION35V_NODE_A_QUARANTINE_CONTRACT:-}${ACTION35V_SERVING_PAYLOAD_MANIFEST_SHA256:-}${ACTION35V_FINALIZER_COMMAND:-}${ACTION35V_SYNC_USER:-}${ACTION35V_SYNC_GROUP:-}" &&
    "${ACTION35V_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
    exit 64
fi

usage() {
    printf 'Usage: %s --production-path-test | MODE node-a|node-b PAYLOAD_ROOT EVIDENCE_ROOT\n' "${0##*/}" >&2
}

safe_root() {
    local action35v_root=$1

    [[ "$action35v_root" == /tmp/caddy-action35v-* &&
        -d "$action35v_root" && ! -L "$action35v_root" ]]
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

effective_path() {
    local action35v_logical_path=$1

    [[ "$action35v_logical_path" = /* ]]
    printf '%s%s\n' "$target_root" "$action35v_logical_path"
}

capture_command() {
    local action35v_label=$1
    shift
    local action35v_stdout=$evidence_root/$action35v_label.stdout
    local action35v_stderr=$evidence_root/$action35v_label.stderr
    local action35v_status=$evidence_root/$action35v_label.status
    local action35v_rc=0

    : >"$action35v_stdout"
    : >"$action35v_stderr"
    if "$@" >"$action35v_stdout" 2>"$action35v_stderr"; then
        action35v_rc=0
    else
        action35v_rc=$?
    fi
    printf '%s\n' "$action35v_rc" >"$action35v_status"
    chmod 0600 "$action35v_stdout" "$action35v_stderr" "$action35v_status"
    [[ "$(stat -c '%s' "$action35v_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35v_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35v_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35v_stderr" >/dev/null
    return "$action35v_rc"
}

capture_stdin_command() {
    local action35v_label=$1
    local action35v_input=$2
    shift 2
    local action35v_stdout=$evidence_root/$action35v_label.stdout
    local action35v_stderr=$evidence_root/$action35v_label.stderr
    local action35v_status=$evidence_root/$action35v_label.status
    local action35v_rc=0

    regular_file "$action35v_input"
    : >"$action35v_stdout"
    : >"$action35v_stderr"
    if "$@" <"$action35v_input" >"$action35v_stdout" 2>"$action35v_stderr"; then
        action35v_rc=0
    else
        action35v_rc=$?
    fi
    printf '%s\n' "$action35v_rc" >"$action35v_status"
    chmod 0600 "$action35v_stdout" "$action35v_stderr" "$action35v_status"
    [[ "$(stat -c '%s' "$action35v_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35v_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35v_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35v_stderr" >/dev/null
    return "$action35v_rc"
}

require() {
    local action35v_label=$1
    shift

    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action35v_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action35v_label" >&2
    return 1
}

require_equal() {
    local action35v_label=$1
    local action35v_expected=$2
    local action35v_observed=$3

    [[ "$action35v_label" =~ ^[a-z0-9_]+$ ]]
    [[ "$action35v_expected" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    [[ "$action35v_observed" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    printf '%s_expected_%s=%s\n' "$prefix" "$action35v_label" "$action35v_expected"
    printf '%s_observed_%s=%s\n' "$prefix" "$action35v_label" "$action35v_observed"
    require "$action35v_label" test "$action35v_observed" = "$action35v_expected"
}

expected_release() {
    if [[ "$node_role" = node-a ]]; then
        printf '%s\n' "$node_a_revision"
    else
        printf '%s\n' "$serving_revision"
    fi
}

current_revision() {
    jq -r '.revision // empty' "$(effective_path /etc/caddy/current/release-manifest.json)"
}

require_exact_directory_inventory() {
    local action35v_label=$1
    local action35v_root=$2
    local action35v_expected=$3
    local action35v_observed

    require "${action35v_label}_root_regular" test -d "$action35v_root" || return 1
    require "${action35v_label}_root_not_symlink" test ! -L "$action35v_root" || return 1
    if ! action35v_observed=$(find "$action35v_root" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | LC_ALL=C sort); then
        printf '%s_check_%s_inventory_read=false\n' "$prefix" "$action35v_label"
        return 1
    fi
    require_equal "${action35v_label}_inventory" "$action35v_expected" "$action35v_observed"
}

require_empty_or_absent_directory() {
    local action35v_label=$1
    local action35v_root=$2

    if [[ ! -e "$action35v_root" && ! -L "$action35v_root" ]]; then
        require_equal "${action35v_label}_state" absent absent
        return 0
    fi
    require_exact_directory_inventory "$action35v_label" "$action35v_root" ''
}

quarantine_names() {
    printf '%s\n' \
        node-a-action17p-node-a-to-node-b-bootstrap \
        node-a-action33k-20260813T000701Z-2499021-node-a-reboot-normalized \
        node_b-outbound-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29-action30c \
        node_b-outbound-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4-action30c
}

node_a_quarantine_contract() {
    if [[ -n "${ACTION35V_NODE_A_QUARANTINE_CONTRACT:-}" ]]; then
        [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]
        regular_file "$ACTION35V_NODE_A_QUARANTINE_CONTRACT"
        cat "$ACTION35V_NODE_A_QUARANTINE_CONTRACT"
        return
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' \
        node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29 \
        20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29 node-b \
        6bf16107a81bfe67bb273e97c1b52814b846e705b8d21ec3226c83cf07a3043f \
        e7e28a835b60d5d58b79968bcc1c041fe85eaed93f97abe176c8d7f8e865e81d
    printf '%s\t%s\t%s\t%s\t%s\n' \
        node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4 \
        20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4 node-b \
        77540139b7636f38f1ceac41d3048817d56eb2a31df1d8a8d392f185048304e6 \
        6f147b7030be5a3817e5910c560e291af1ac03ebe3e68d90e2a8a764106f6c5e
    printf '%s\t%s\t%s\t%s\t%s\n' \
        node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d \
        20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63 node-a \
        c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de \
        fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
    printf '%s\t%s\t%s\t%s\t%s\n' \
        node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d \
        action17p-node-a-to-node-b-bootstrap node-a \
        81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3 \
        f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
}

validate_node_a_quarantine_inventory() {
    local action35v_inventory_root=$1
    local action35v_label=$2
    local action35v_expected_metadata=caddy-sync:caddy-sync
    local action35v_expected_names action35v_observed_names
    local action35v_name action35v_name_label action35v_revision action35v_source
    local action35v_release_hash action35v_payload_hash action35v_candidate
    local action35v_allowed action35v_observed action35v_marker action35v_path

    require "${action35v_label}_root_regular" test -d "$action35v_inventory_root" || return 1
    require "${action35v_label}_root_not_symlink" test ! -L "$action35v_inventory_root" || return 1
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35v_expected_metadata=$(id -un):$(id -gn)
    fi
    require_equal "${action35v_label}_root_metadata" \
        "$action35v_expected_metadata:750" "$(stat -c '%U:%G:%a' "$action35v_inventory_root")"
    action35v_expected_names=$(mktemp /tmp/caddy-action35v-node-a-expected.XXXXXX)
    action35v_observed_names=$(mktemp /tmp/caddy-action35v-node-a-observed.XXXXXX)
    node_a_quarantine_contract | awk -F '\t' '{ print $1 }' | LC_ALL=C sort \
        >"$action35v_expected_names"
    find "$action35v_inventory_root" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort >"$action35v_observed_names"
    require "${action35v_label}_top_level_exact" cmp -s \
        "$action35v_expected_names" "$action35v_observed_names" || {
        rm -f -- "$action35v_expected_names" "$action35v_observed_names"
        return 1
    }
    rm -f -- "$action35v_expected_names" "$action35v_observed_names"

    while IFS=$'\t' read -r action35v_name action35v_revision action35v_source \
        action35v_release_hash action35v_payload_hash; do
        [[ "$action35v_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
        action35v_name_label=${action35v_name,,}
        action35v_name_label=${action35v_name_label//[^a-z0-9_]/_}
        action35v_candidate=$action35v_inventory_root/$action35v_name
        require "${action35v_label}_${action35v_name_label}_regular" \
            test -d "$action35v_candidate" || return 1
        require "${action35v_label}_${action35v_name_label}_not_symlink" \
            test ! -L "$action35v_candidate" || return 1
        require_equal "${action35v_label}_${action35v_name_label}_metadata" \
            "$action35v_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35v_candidate")"
        require "${action35v_label}_${action35v_name_label}_unsafe_types_absent" \
            test -z "$(find "$action35v_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
        require "${action35v_label}_${action35v_name_label}_hardlinks_absent" \
            test -z "$(find "$action35v_candidate" -type f -links +1 -print -quit)"
        while IFS= read -r -d '' action35v_path; do
            if [[ -d "$action35v_path" ]]; then
                require_equal "${action35v_label}_${action35v_name_label}_directory_metadata" \
                    "$action35v_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35v_path")" || return 1
            else
                require_equal "${action35v_label}_${action35v_name_label}_file_metadata" \
                    "$action35v_expected_metadata:440" "$(stat -c '%U:%G:%a' "$action35v_path")" || return 1
            fi
        done < <(find "$action35v_candidate" -mindepth 1 -print0)
        require_equal "${action35v_label}_${action35v_name_label}_release_identity" \
            "$action35v_release_hash" \
            "$(sha256sum "$action35v_candidate/release-manifest.json" | awk '{ print $1 }')"
        require_equal "${action35v_label}_${action35v_name_label}_payload_identity" \
            "$action35v_payload_hash" \
            "$(sha256sum "$action35v_candidate/manifest.sha256" | awk '{ print $1 }')"
        require_equal "${action35v_label}_${action35v_name_label}_revision" \
            "$action35v_revision" \
            "$(jq -r '.revision // empty' "$action35v_candidate/release-manifest.json")"
        require_equal "${action35v_label}_${action35v_name_label}_source" \
            "$action35v_source" \
            "$(jq -r '.source_node // empty' "$action35v_candidate/release-manifest.json")"
        # The awk program must not expand shell positional parameters.
        # shellcheck disable=SC2016
        require "${action35v_label}_${action35v_name_label}_manifest_paths_safe" \
            awk 'length($0) < 68 { exit 1 } { p = substr($0, 67); sub(/^  /, "", p); if (p == "" || p ~ /^\// || p == ".." || p ~ /^\.\.\// || p ~ /\/\.\.\// || p ~ /\/\.\.$/) exit 1 }' \
            "$action35v_candidate/manifest.sha256"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35v_label}_${action35v_name_label}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35v_candidate"
        action35v_allowed=$(mktemp /tmp/caddy-action35v-node-a-allowed.XXXXXX)
        action35v_observed=$(mktemp /tmp/caddy-action35v-node-a-files.XXXXXX)
        for action35v_marker in .finalize-request .complete; do
            if [[ -e "$action35v_candidate/$action35v_marker" ]]; then
                require "${action35v_label}_${action35v_name_label}_${action35v_marker#.}_empty" \
                    test ! -s "$action35v_candidate/$action35v_marker" || return 1
            fi
        done
        {
            printf '%s\n' ./manifest.sha256 ./release-manifest.json
            awk '{ print substr($0, 67) }' "$action35v_candidate/manifest.sha256"
            for action35v_marker in .finalize-request .complete; do
                if [[ -e "$action35v_candidate/$action35v_marker" ]]; then
                    printf './%s\n' "$action35v_marker"
                fi
            done
        } | LC_ALL=C sort -u >"$action35v_allowed"
        require "${action35v_label}_${action35v_name_label}_complete_pending_absent" \
            path_absent "$action35v_candidate/.complete.pending"
        (
            cd "$action35v_candidate"
            find . -type f -print | LC_ALL=C sort -u
        ) >"$action35v_observed"
        require "${action35v_label}_${action35v_name_label}_file_inventory_exact" \
            cmp -s "$action35v_allowed" "$action35v_observed" || {
            rm -f -- "$action35v_allowed" "$action35v_observed"
            return 1
        }
        rm -f -- "$action35v_allowed" "$action35v_observed"
    done < <(node_a_quarantine_contract)

    action35v_path=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35v_label}_current_reference_absent" test \
        "${action35v_path#"$action35v_inventory_root"/}" = "$action35v_path"
    action35v_path=''
    while IFS= read -r -d '' action35v_marker; do
        action35v_path=$(readlink -f "$action35v_marker" || :)
        [[ "${action35v_path#"$action35v_inventory_root"/}" = "$action35v_path" ]] || break
        action35v_path=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35v_label}_state_references_absent" test -z "$action35v_path"
}

validate_quarantine_inventory() {
    local action35v_inventory_root=$1
    local action35v_label=$2
    local action35v_manifest=${ACTION35V_QUARANTINE_INVENTORY_MANIFEST:-$payload_root/manifests/action35v-node-b-quarantine.tsv}
    local action35v_expected_metadata=caddy-sync:caddy-sync:750
    local action35v_observed_file action35v_expected_file
    local action35v_path action35v_relative action35v_encoded action35v_type
    local action35v_metadata action35v_hash action35v_reference
    local action35v_name

    require "${action35v_label}_root_regular" test -d "$action35v_inventory_root" || return 1
    require "${action35v_label}_root_not_symlink" test ! -L "$action35v_inventory_root" || return 1
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35v_expected_metadata=$(id -un):$(id -gn):750
    fi
    require_equal "${action35v_label}_root_metadata" "$action35v_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35v_inventory_root")"
    require "${action35v_label}_manifest_regular" regular_file "$action35v_manifest"
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
        require_equal "${action35v_label}_manifest_identity" \
            2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
            "$(sha256sum "$action35v_manifest" | awk '{ print $1 }')"
    fi
    action35v_expected_file=$(mktemp /tmp/caddy-action35v-quarantine-expected.XXXXXX)
    action35v_observed_file=$(mktemp /tmp/caddy-action35v-quarantine-observed.XXXXXX)
    awk -F '\t' 'NR > 1 { print }' "$action35v_manifest" | LC_ALL=C sort \
        >"$action35v_expected_file"
    while IFS= read -r -d '' action35v_path; do
        action35v_relative=${action35v_path#"$action35v_inventory_root"/}
        [[ -n "$action35v_relative" && "$action35v_relative" != /* &&
            "$action35v_relative" != .. && "$action35v_relative" != ../* &&
            "$action35v_relative" != */../* && "$action35v_relative" != */.. ]]
        action35v_encoded=$(printf '%s' "$action35v_relative" | base64 -w 0)
        if [[ -d "$action35v_path" && ! -L "$action35v_path" ]]; then
            action35v_type=directory
            action35v_hash=-
        elif [[ -f "$action35v_path" && ! -L "$action35v_path" ]]; then
            if [[ -s "$action35v_path" ]]; then
                action35v_type='regular file'
            else
                action35v_type='regular empty file'
            fi
            action35v_hash=$(sha256sum "$action35v_path" | awk '{ print $1 }')
        else
            printf '%s_check_%s_unsafe_type=false\n' "$prefix" "$action35v_label"
            rm -f -- "$action35v_expected_file" "$action35v_observed_file"
            return 1
        fi
        action35v_metadata=$(stat -c '%U:%G:%a' "$action35v_path")
        printf '%s\t%s\t%s\t%s\n' "$action35v_encoded" "$action35v_type" \
            "$action35v_metadata" "$action35v_hash" >>"$action35v_observed_file"
    done < <(find "$action35v_inventory_root" -mindepth 1 -print0)
    LC_ALL=C sort -o "$action35v_observed_file" "$action35v_observed_file"
    require "${action35v_label}_exact" cmp -s \
        "$action35v_expected_file" "$action35v_observed_file" || {
        rm -f -- "$action35v_expected_file" "$action35v_observed_file"
        return 1
    }
    rm -f -- "$action35v_expected_file" "$action35v_observed_file"
    while IFS= read -r action35v_name; do
        require "${action35v_label}_${action35v_name//[-]/_}_release_manifest_json" \
            jq -e \
            'type == "object" and
             (.revision | type == "string" and length > 0) and
             (.parent_revision | type == "string" and length > 0) and
             (.source_node | type == "string" and (. == "node-a" or . == "node-b")) and
             (.created_at | type == "string" and length > 0)' \
            "$action35v_inventory_root/$action35v_name/release-manifest.json"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35v_label}_${action35v_name//[-]/_}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35v_inventory_root/$action35v_name"
    done < <(quarantine_names)
    action35v_reference=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35v_label}_current_reference_absent" test \
        "${action35v_reference#"$action35v_inventory_root"/}" = "$action35v_reference"
    action35v_reference=''
    while IFS= read -r -d '' action35v_path; do
        action35v_reference=$(readlink -f "$action35v_path" || :)
        [[ "${action35v_reference#"$action35v_inventory_root"/}" = "$action35v_reference" ]] || break
        action35v_reference=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35v_label}_state_references_absent" test -z "$action35v_reference"
}

validate_retained_node_b_entry() {
    local action35v_candidate=$incoming_root/node-a/$retained_name
    local action35v_allowed
    local action35v_expected_metadata=caddy-sync:caddy-sync:500
    local action35v_observed

    [[ "$node_role" = node-b ]]
    require retained_inventory_exact require_exact_directory_inventory \
        retained_incoming_node_a "$incoming_root/node-a" "$retained_name"
    require retained_candidate_regular test -d "$action35v_candidate"
    require retained_candidate_not_symlink test ! -L "$action35v_candidate"
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35v_expected_metadata=$(id -un):$(id -gn):500
    fi
    require_equal retained_candidate_metadata "$action35v_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35v_candidate")"
    require retained_release_manifest_regular regular_file \
        "$action35v_candidate/release-manifest.json"
    require retained_payload_manifest_regular regular_file \
        "$action35v_candidate/manifest.sha256"
    require_equal retained_release_manifest_identity \
        "$retained_release_manifest_sha256" \
        "$(sha256sum "$action35v_candidate/release-manifest.json" | awk '{ print $1 }')"
    require_equal retained_payload_manifest_identity \
        "$retained_payload_manifest_sha256" \
        "$(sha256sum "$action35v_candidate/manifest.sha256" | awk '{ print $1 }')"
    require_equal retained_revision "$retained_name" \
        "$(jq -r '.revision // empty' "$action35v_candidate/release-manifest.json")"
    require_equal retained_source node-a \
        "$(jq -r '.source_node // empty' "$action35v_candidate/release-manifest.json")"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require retained_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35v_candidate"
    require retained_unsafe_types_absent test -z \
        "$(find "$action35v_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
    require retained_finalize_request_absent path_absent \
        "$action35v_candidate/.finalize-request"
    require retained_complete_absent path_absent "$action35v_candidate/.complete"
    require retained_complete_pending_absent path_absent \
        "$action35v_candidate/.complete.pending"
    action35v_allowed=$(mktemp /tmp/caddy-action35v-retained-allowed.XXXXXX)
    action35v_observed=$(mktemp /tmp/caddy-action35v-retained-observed.XXXXXX)
    {
        printf '%s\n' manifest.sha256 release-manifest.json
        awk '{ print $2 }' "$action35v_candidate/manifest.sha256"
    } | sed 's#^\./##' | LC_ALL=C sort -u >"$action35v_allowed"
    find "$action35v_candidate" -mindepth 1 -type f -printf '%P\n' |
        LC_ALL=C sort -u >"$action35v_observed"
    require retained_file_inventory_exact cmp -s "$action35v_allowed" "$action35v_observed"
    rm -f -- "$action35v_allowed" "$action35v_observed"
}

disposition_retained_node_b_entry() {
    local action35v_candidate=$incoming_root/node-a/$retained_name
    local action35v_backup=$evidence_root/retained-incoming
    local action35v_quarantine_backup=$evidence_root/quarantine-disposition
    local action35v_status=0

    [[ "$node_role" = node-b ]]
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    require retained_backup_absent test ! -e "$action35v_backup"
    require quarantine_backup_absent test ! -e "$action35v_quarantine_backup"
    require_equal quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35v_status=125
    if [[ "$action35v_status" -eq 0 ]]; then
        if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            chmod 0700 "$action35v_candidate"
        fi
        mv -- "$action35v_candidate" "$action35v_backup" || action35v_status=$?
    fi
    if [[ "$action35v_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35v_quarantine_backup" || action35v_status=$?
    fi
    if [[ "$action35v_status" -eq 0 ]]; then
        if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35v_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35v_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35v_status=125
    [[ "$action35v_status" -eq 0 ]] || return "$action35v_status"
    require retained_candidate_dispositioned test ! -e "$action35v_candidate"
    require incoming_node_a_inventory_empty require_exact_directory_inventory \
        incoming_node_a_after_disposition "$incoming_root/node-a" ''
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine_after_disposition "$quarantine_root" ''
}

restore_retained_node_b_entry() {
    local action35v_candidate=$incoming_root/node-a/$retained_name
    local action35v_backup=$evidence_root/retained-incoming
    local action35v_quarantine_backup=$evidence_root/quarantine-disposition
    local action35v_status=0

    [[ "$node_role" = node-b ]]
    if [[ -n "$target_root" && ! -d "$action35v_backup" ]]; then
        return 0
    fi
    if [[ -d "$action35v_backup" && ! -L "$action35v_backup" ]]; then
        require retained_restore_target_absent test ! -e "$action35v_candidate"
        "$systemctl_command" stop caddy-sync-reconcile.path || action35v_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35v_status=125
        if [[ "$action35v_status" -eq 0 ]]; then
            mv -- "$action35v_backup" "$action35v_candidate" || action35v_status=$?
            if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
                chmod 0500 "$action35v_candidate"
            fi
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35v_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35v_status=125
    fi
    if [[ -d "$action35v_quarantine_backup" && ! -L "$action35v_quarantine_backup" ]]; then
        validate_quarantine_inventory "$action35v_quarantine_backup" quarantine_restore_source
        if [[ -e "$quarantine_root" || -L "$quarantine_root" ]]; then
            require quarantine_restore_target_empty require_exact_directory_inventory \
                quarantine_restore_target "$quarantine_root" ''
        else
            require quarantine_restore_target_absent path_absent "$quarantine_root"
        fi
        "$systemctl_command" stop caddy-sync-reconcile.path || action35v_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35v_status=125
        if [[ "$action35v_status" -eq 0 ]]; then
            if [[ -d "$quarantine_root" ]]; then
                rmdir "$quarantine_root" || action35v_status=$?
            fi
        fi
        if [[ "$action35v_status" -eq 0 ]]; then
            mv -- "$action35v_quarantine_backup" "$quarantine_root" || action35v_status=$?
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35v_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35v_status=125
    fi
    [[ "$action35v_status" -eq 0 ]] || return "$action35v_status"
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_restored
}

disposition_node_a_quarantine() {
    local action35v_backup=$evidence_root/node-a-quarantine-disposition
    local action35v_status=0

    [[ "$node_role" = node-a ]]
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_baseline
    require node_a_quarantine_backup_absent test ! -e "$action35v_backup"
    require_equal node_a_quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35v_status=125
    if [[ "$action35v_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35v_backup" || action35v_status=$?
    fi
    if [[ "$action35v_status" -eq 0 ]]; then
        if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35v_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35v_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35v_status=125
    [[ "$action35v_status" -eq 0 ]] || return "$action35v_status"
    require node_a_quarantine_inventory_empty require_exact_directory_inventory \
        node_a_quarantine_after_disposition "$quarantine_root" ''
}

restore_node_a_quarantine() {
    local action35v_backup=$evidence_root/node-a-quarantine-disposition
    local action35v_status=0

    [[ "$node_role" = node-a ]]
    if [[ ! -e "$action35v_backup" && ! -L "$action35v_backup" ]]; then
        return 0
    fi
    require node_a_quarantine_restore_source_regular test -d "$action35v_backup"
    require node_a_quarantine_restore_source_not_symlink test ! -L "$action35v_backup"
    validate_node_a_quarantine_inventory "$action35v_backup" node_a_quarantine_restore_source
    require node_a_quarantine_restore_target_empty require_exact_directory_inventory \
        node_a_quarantine_restore_target "$quarantine_root" ''
    "$systemctl_command" stop caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35v_status=125
    if [[ "$action35v_status" -eq 0 ]]; then
        rmdir "$quarantine_root" || action35v_status=$?
    fi
    if [[ "$action35v_status" -eq 0 ]]; then
        mv -- "$action35v_backup" "$quarantine_root" || action35v_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35v_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35v_status=125
    [[ "$action35v_status" -eq 0 ]] || return "$action35v_status"
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_restored
}

validate_outbound_candidate() {
    local action35v_candidate=$outgoing_root/$serving_revision
    local action35v_manifest_hash

    require outbound_candidate_regular test -d "$action35v_candidate"
    require outbound_candidate_not_symlink test ! -L "$action35v_candidate"
    require outbound_candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action35v_candidate")" = "$sync_user:$sync_group:550"
    require outbound_revision test \
        "$(jq -r '.revision // empty' "$action35v_candidate/release-manifest.json")" = "$serving_revision"
    require outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$action35v_candidate/release-manifest.json")" = "$serving_parent"
    require outbound_source test \
        "$(jq -r '.source_node // empty' "$action35v_candidate/release-manifest.json")" = node-a
    action35v_manifest_hash=$(sha256sum "$action35v_candidate/manifest.sha256" | awk '{ print $1 }')
    require outbound_payload_manifest_hash test \
        "$action35v_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require outbound_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35v_candidate"
    require outbound_finalize_marker_regular test -f "$action35v_candidate/.finalize-request"
    require outbound_finalize_marker_empty test ! -s "$action35v_candidate/.finalize-request"
    require outbound_symlinks_absent test -z \
        "$(find "$action35v_candidate" -type l -print -quit)"
}

validate_installed_release() {
    local action35v_release=$releases_root/$serving_revision
    local action35v_manifest_hash

    require installed_release_regular test -d "$action35v_release"
    require installed_release_not_symlink test ! -L "$action35v_release"
    require installed_release_metadata test \
        "$(stat -c '%U:%G:%a' "$action35v_release")" = root:caddy-tls:550
    require installed_release_revision test \
        "$(jq -r '.revision // empty' "$action35v_release/release-manifest.json")" = "$serving_revision"
    require installed_release_parent test \
        "$(jq -r '.parent_revision // empty' "$action35v_release/release-manifest.json")" = "$serving_parent"
    require installed_release_source test \
        "$(jq -r '.source_node // empty' "$action35v_release/release-manifest.json")" = node-a
    action35v_manifest_hash=$(sha256sum "$action35v_release/manifest.sha256" | awk '{ print $1 }')
    require installed_payload_manifest_hash test \
        "$action35v_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require installed_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35v_release"
}

validate_inventory() {
    local action35v_inventory=$payload_root/manifests/production-artifacts.tsv
    local action35v_key action35v_repository action35v_source action35v_target
    local action35v_inventory_node action35v_source_hash action35v_deployed_hash
    local action35v_accepted action35v_lifecycle action35v_observed

    regular_file "$action35v_inventory"
    while IFS=$'\t' read -r action35v_key action35v_repository action35v_source \
        action35v_target action35v_inventory_node action35v_source_hash \
        action35v_deployed_hash action35v_accepted action35v_lifecycle; do
        [[ "$action35v_key" = '# key' ]] && continue
        [[ "$action35v_inventory_node" = "$node_role" ||
            "$action35v_inventory_node" = both ]] || continue
        [[ -n "$action35v_accepted" && "$action35v_lifecycle" = production-current ]]
        require "artifact_${action35v_key}_regular" regular_file "$action35v_target"
        action35v_observed=$(sha256sum "$action35v_target" | awk '{ print $1 }')
        require_equal "artifact_${action35v_key}_identity" \
            "$action35v_deployed_hash" "$action35v_observed"
    done <"$action35v_inventory"
}

validate_legacy_lighttpd_helper() {
    local action35v_path
    local action35v_expected_metadata=root:root:755

    action35v_path=$(effective_path "$legacy_lighttpd_helper")
    if [[ "$node_role" = node-a ]]; then
        require_equal legacy_lighttpd_helper_state absent \
            "$(if path_absent "$action35v_path"; then printf absent; else printf present; fi)"
        return
    fi
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35v_expected_metadata=$(id -un):$(id -gn):755
    fi
    require legacy_lighttpd_helper_regular regular_file "$action35v_path"
    require_equal legacy_lighttpd_helper_metadata "$action35v_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35v_path")"
    require_equal legacy_lighttpd_helper_identity "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35v_path" | awk '{ print $1 }')"
}

remove_legacy_lighttpd_helper() {
    local action35v_path

    [[ "$node_role" = node-b ]]
    validate_legacy_lighttpd_helper
    action35v_path=$(effective_path "$legacy_lighttpd_helper")
    backup_target "$legacy_lighttpd_helper"
    rm -f -- "$action35v_path"
    require legacy_lighttpd_helper_removed path_absent "$action35v_path"
}

restore_legacy_lighttpd_helper() {
    [[ "$node_role" = node-b ]]
    restore_target "$legacy_lighttpd_helper"
    validate_legacy_lighttpd_helper
}

validate_services() {
    local action35v_unit

    for action35v_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35v_unit//[.@-]/_}_active" \
            "$systemctl_command" is-active --quiet "$action35v_unit"
    done
    for action35v_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35v_unit//[.@-]/_}_enabled" \
            "$systemctl_command" is-enabled --quiet "$action35v_unit"
    done
    require caddy_api_masked test "$($systemctl_command is-enabled caddy-api.service)" = masked
    require distribution_lsyncd_masked test "$($systemctl_command is-enabled lsyncd.service)" = masked
}

validate_split_baseline() {
    local action35v_expected_revision

    action35v_expected_revision=$(expected_release)
    require_equal current_release_expected "$action35v_expected_revision" "$(current_revision)"
    validate_inventory
    validate_legacy_lighttpd_helper
    validate_services
    if [[ "$node_role" = node-b ]]; then
        validate_retained_node_b_entry
        require incoming_node_b_absent path_absent "$incoming_root/node-b"
        validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    else
        require incoming_node_a_absent path_absent "$incoming_root/node-a"
        require incoming_node_b_empty require_empty_or_absent_directory \
            incoming_node_b "$incoming_root/node-b"
        validate_node_a_quarantine_inventory "$quarantine_root" \
            node_a_quarantine_baseline
    fi
    if [[ "$node_role" = node-a ]]; then
        require outbound_inventory_exact require_exact_directory_inventory \
            outbound "$outgoing_root" "$serving_revision"
        validate_outbound_candidate
    else
        require outbound_inventory_empty require_exact_directory_inventory outbound "$outgoing_root" ''
        validate_installed_release
    fi
}

validate_payload() {
    local action35v_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35v_repository action35v_source action35v_target action35v_mode
    local action35v_expected_hash action35v_lifecycle action35v_file action35v_observed

    require payload_root safe_root "$payload_root"
    require payload_manifest regular_file "$action35v_manifest"
    require quarantine_inventory_manifest regular_file \
        "$payload_root/manifests/action35v-node-b-quarantine.tsv"
    require_equal quarantine_inventory_manifest_identity \
        2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
        "$(sha256sum "$payload_root/manifests/action35v-node-b-quarantine.tsv" | awk '{ print $1 }')"
    while IFS=$'\t' read -r action35v_repository action35v_source action35v_target \
        action35v_mode action35v_expected_hash action35v_lifecycle; do
        [[ "$action35v_repository" = '# repository' ]] && continue
        action35v_file=$payload_root/repositories/$action35v_repository/$action35v_source
        require "payload_${action35v_expected_hash}_regular" regular_file "$action35v_file"
        action35v_observed=$(sha256sum "$action35v_file" | awk '{ print $1 }')
        require "payload_${action35v_expected_hash}_identity" test \
            "$action35v_observed" = "$action35v_expected_hash"
    done <"$action35v_manifest"
}

validate_installed_candidate_inventory() {
    local action35v_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35v_repository action35v_source action35v_target action35v_mode
    local action35v_expected_hash action35v_lifecycle action35v_observed

    while IFS=$'\t' read -r action35v_repository action35v_source action35v_target \
        action35v_mode action35v_expected_hash action35v_lifecycle; do
        [[ "$action35v_repository" = '# repository' ]] && continue
        [[ "$action35v_lifecycle" = production-candidate ]]
        case "$action35v_target" in
            /etc/caddy/releases/REVISION/*) continue ;;
        esac
        if [[ "$action35v_source" = Keepalived/configs/keepalived-pihole0.conf &&
            "$node_role" != node-a ]]; then
            continue
        fi
        if [[ "$action35v_source" = Keepalived/configs/keepalived-pihole00.conf &&
            "$node_role" != node-b ]]; then
            continue
        fi
        require "candidate_${action35v_expected_hash}_regular" regular_file "$action35v_target"
        require "candidate_${action35v_expected_hash}_mode" test \
            "$(stat -c '%a' "$action35v_target")" = "${action35v_mode#0}"
        require "candidate_${action35v_expected_hash}_owner" test \
            "$(stat -c '%U:%G' "$action35v_target")" = root:root
        action35v_observed=$(sha256sum "$action35v_target" | awk '{ print $1 }')
        require "candidate_${action35v_expected_hash}_identity" test \
            "$action35v_observed" = "$action35v_expected_hash"
    done <"$action35v_manifest"
}

candidate_file() {
    local action35v_repository=$1
    local action35v_source=$2
    printf '%s/repositories/%s/%s\n' "$payload_root" "$action35v_repository" "$action35v_source"
}

backup_path() {
    local action35v_target=$1
    printf '%s/backups/%s\n' "$evidence_root" "${action35v_target#/}"
}

backup_target() {
    local action35v_target=$1
    local action35v_backup
    local action35v_effective_target

    action35v_backup=$(backup_path "$action35v_target")
    action35v_effective_target=$(effective_path "$action35v_target")
    install -d -m 0700 "$(dirname -- "$action35v_backup")"
    if [[ -e "$action35v_effective_target" || -L "$action35v_effective_target" ]]; then
        cp -a -- "$action35v_effective_target" "$action35v_backup"
        printf 'present\n' >"$action35v_backup.state"
    else
        printf 'absent\n' >"$action35v_backup.state"
    fi
}

install_target() {
    local action35v_source=$1
    local action35v_target=$2
    local action35v_mode=$3
    local action35v_owner=$4
    local action35v_group=$5
    local action35v_effective_target

    action35v_effective_target=$(effective_path "$action35v_target")
    if [[ "${ACTION35V_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35v_owner=$(id -un)
        action35v_group=$(id -gn)
    fi

    backup_target "$action35v_target"
    install -d -m 0755 "$(dirname -- "$action35v_effective_target")"
    install -o "$action35v_owner" -g "$action35v_group" -m "$action35v_mode" \
        "$action35v_source" "$action35v_effective_target"
}

restore_target() {
    local action35v_target=$1
    local action35v_backup
    local action35v_state
    local action35v_effective_target

    action35v_backup=$(backup_path "$action35v_target")
    action35v_effective_target=$(effective_path "$action35v_target")
    [[ -f "$action35v_backup.state" && ! -L "$action35v_backup.state" ]] || return 0
    action35v_state=$(<"$action35v_backup.state")
    case "$action35v_state" in
        present)
            rm -f -- "$action35v_effective_target"
            cp -a -- "$action35v_backup" "$action35v_effective_target"
            ;;
        absent) rm -f -- "$action35v_effective_target" ;;
        *) return 1 ;;
    esac
}

install_serving_artifacts() {
    local action35v_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        action35v_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35v_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
        remove_legacy_lighttpd_helper
    fi
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        /usr/local/libexec/check-caddy.sh 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/check-pihole-web-health.sh)" \
        /usr/local/libexec/check-pihole-web-health.sh 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/caddy-apprise-enqueue.sh)" \
        /usr/local/libexec/caddy-apprise-enqueue 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/caddy-apprise-delivery-worker.sh)" \
        /usr/local/libexec/caddy-apprise-delivery-worker 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.service)" \
        /etc/systemd/system/caddy-pihole-web-health.service 0644 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.timer)" \
        /etc/systemd/system/caddy-pihole-web-health.timer 0644 root root
    install_target "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        /etc/scripts/check-dns.sh 0755 root root
    install_target "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)" \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf 0644 root root
    install_target "$(candidate_file homelab-dns "$action35v_keepalived_source")" \
        /etc/keepalived/keepalived.conf 0644 root root
    if [[ -n "$target_root" ]]; then
        "$unbound_checkconf_command" \
            "$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)"
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf
    fi
    "$systemctl_command" daemon-reload
    "$systemctl_command" enable --now caddy-pihole-web-health.timer
    "$systemctl_command" reload unbound.service
    "$systemctl_command" reload keepalived.service
}

parser_and_identity_checks() {
    local action35v_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        action35v_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35v_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    capture_command unbound_local_zone_parser "$unbound_checkconf_command" \
        "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)"
    capture_stdin_command dns_identity \
        "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        "$runuser_command" -u pi -- env \
        DNS_CHECK_DIG_COMMAND="${ACTION35V_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        DNS_CHECK_SYSTEMCTL_COMMAND="${ACTION35V_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
    capture_stdin_command caddy_identity \
        "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        "$runuser_command" -u keepalived_script -- env \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$node_environment" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="${ACTION35V_CURL_COMMAND:-/usr/bin/curl}" \
        CADDY_SERVING_HEALTH_SS_COMMAND="${ACTION35V_SS_COMMAND:-/usr/bin/ss}" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="${ACTION35V_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
}

promote_local_candidate() {
    local action35v_source=$outgoing_root/$serving_revision
    local action35v_destination=$incoming_root/node-a/$serving_revision

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    require local_incoming_absent test ! -e "$action35v_destination"
    local action35v_promotion_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$action35v_source" "$action35v_destination" &&
        chown -R "$sync_user:$sync_group" "$action35v_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require local_candidate_selected test "$(current_revision)" = "$serving_revision"; then
        :
    else
        action35v_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35v_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35v_promotion_status=125
    return "$action35v_promotion_status"
}

accept_installed_node() {
    local action35v_keepalived_hash action35v_dns_hash action35v_caddy_hash
    local action35v_service_hash action35v_timer_hash action35v_local_zone_hash

    action35v_keepalived_hash=$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')
    action35v_dns_hash=$(sha256sum /etc/scripts/check-dns.sh | awk '{ print $1 }')
    action35v_caddy_hash=$(sha256sum /usr/local/libexec/check-caddy.sh | awk '{ print $1 }')
    action35v_service_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.service | awk '{ print $1 }')
    action35v_timer_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.timer | awk '{ print $1 }')
    action35v_local_zone_hash=$(sha256sum /etc/unbound/unbound.conf.d/pihole-local-zone.conf | awk '{ print $1 }')
    if [[ "$node_role" = node-a ]]; then
        require keepalived_candidate_hash test "$action35v_keepalived_hash" = \
            18560da8026928b3107da667bdea8762cea85d3a55946e979437e861ce8bd826
    else
        require keepalived_candidate_hash test "$action35v_keepalived_hash" = \
            dffb9c0076b553e085a3dd6223d004829ba3e15570e6985b88646ff037d5ea57
    fi
    require dns_candidate_hash test "$action35v_dns_hash" = \
        294afb4db26a3ccac454636efe091b872724e648c901b467142b31fae489e8aa
    require caddy_candidate_hash test "$action35v_caddy_hash" = \
        381c9b371621e1ddfae1eba3f557f8750fc0bbcc162415b038c8043aa1bac208
    require web_service_hash test "$action35v_service_hash" = \
        a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0
    require web_timer_hash test "$action35v_timer_hash" = \
        f214b69fecaeb322dbaba61f683f9cf35970596784adcd707e25278f0ace1505
    require unbound_local_zone_hash test "$action35v_local_zone_hash" = \
        f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d
    require web_timer_enabled "$systemctl_command" is-enabled --quiet caddy-pihole-web-health.timer
    require web_timer_active "$systemctl_command" is-active --quiet caddy-pihole-web-health.timer
    require web_worker_static test \
        "$($systemctl_command is-enabled caddy-pihole-web-health.service)" = static
    require selected_release test "$(current_revision)" = "$serving_revision"
    validate_installed_candidate_inventory
    validate_services
    parser_and_identity_checks
}

validate_final_residue() {
    require selected_release test "$(current_revision)" = "$serving_revision"
    validate_installed_candidate_inventory
    validate_services
    require legacy_lighttpd_helper_absent path_absent \
        "$(effective_path "$legacy_lighttpd_helper")"
    if [[ "$node_role" = node-a ]]; then
        require incoming_node_a_absent path_absent "$incoming_root/node-a"
        require incoming_node_b_empty require_empty_or_absent_directory \
            incoming_node_b "$incoming_root/node-b"
    else
        require incoming_node_a_empty require_empty_or_absent_directory \
            incoming_node_a "$incoming_root/node-a"
        require incoming_node_b_absent path_absent "$incoming_root/node-b"
    fi
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine "$quarantine_root" ''
    require outbound_inventory_empty require_exact_directory_inventory outbound "$outgoing_root" ''
    validate_installed_release
}

rollback_node() {
    local action35v_target
    local action35v_release_source
    local action35v_restore_failed=0

    if [[ "$node_role" = node-b ]]; then
        restore_retained_node_b_entry || action35v_restore_failed=1
        restore_target "$legacy_lighttpd_helper" || action35v_restore_failed=1
    else
        restore_node_a_quarantine || action35v_restore_failed=1
    fi

    for action35v_target in \
        /etc/keepalived/keepalived.conf \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf \
        /etc/scripts/check-dns.sh \
        /etc/systemd/system/caddy-pihole-web-health.timer \
        /etc/systemd/system/caddy-pihole-web-health.service \
        /usr/local/libexec/caddy-apprise-delivery-worker \
        /usr/local/libexec/caddy-apprise-enqueue \
        /usr/local/libexec/check-pihole-web-health.sh \
        /usr/local/libexec/check-caddy.sh; do
        restore_target "$action35v_target" || action35v_restore_failed=1
    done
    "$systemctl_command" disable --now caddy-pihole-web-health.timer \
        >/dev/null 2>&1 || :
    "$systemctl_command" daemon-reload || action35v_restore_failed=1
    if [[ -n "$target_root" ]]; then
        action35v_target=$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)
        if [[ -f "$action35v_target" && ! -L "$action35v_target" ]]; then
            "$unbound_checkconf_command" "$action35v_target" || action35v_restore_failed=1
        fi
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf || action35v_restore_failed=1
    fi
    "$systemctl_command" reload unbound.service || action35v_restore_failed=1
    "$systemctl_command" reload keepalived.service || action35v_restore_failed=1
    if [[ -z "$target_root" && "$node_role" = node-a &&
        "$(current_revision)" = "$serving_revision" ]]; then
        ln -sfn "$releases_root/$node_a_revision" /etc/caddy/current.rollback
        mv -Tf /etc/caddy/current.rollback /etc/caddy/current
        "$systemctl_command" reload caddy.service || action35v_restore_failed=1
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$releases_root/$serving_revision" ]]; then
        action35v_release_source=$outgoing_root/$serving_revision
        if [[ -d "$evidence_root/consumed-outbound" ]]; then
            action35v_release_source=$evidence_root/consumed-outbound
        fi
        if [[ -d "$action35v_release_source" ]] &&
            diff -qr --exclude=.complete "$action35v_release_source" \
                "$releases_root/$serving_revision" >/dev/null; then
            rm -rf -- "${releases_root:?}/${serving_revision:?}"
        else
            action35v_restore_failed=1
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$evidence_root/consumed-outbound" &&
        ! -e "$outgoing_root/$serving_revision" ]]; then
        mv -- "$evidence_root/consumed-outbound" \
            "$outgoing_root/$serving_revision" || action35v_restore_failed=1
    fi
    if [[ -z "$target_root" ]]; then
        capture_command journal_rollback "$journalctl_command" --no-pager -o short-iso-precise \
            --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
            -t keepalived-notify -t caddy-ha-health || :
    fi
    [[ "$action35v_restore_failed" -eq 0 ]]
}

consume_outbound() {
    local action35v_source=$outgoing_root/$serving_revision
    local action35v_destination=$evidence_root/consumed-outbound

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    validate_installed_release
    require consumed_backup_absent test ! -e "$action35v_destination"
    # The child Bash expands its positional parameters.
    # shellcheck disable=SC2016
    require installed_and_outbound_equal \
        /bin/bash -c 'diff -qr --exclude=.complete "$1" "$2" >/dev/null' \
        _ "$action35v_source" "$releases_root/$serving_revision"
    local action35v_consume_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$action35v_source" "$action35v_destination" || action35v_consume_status=$?
    "$systemctl_command" start caddy-lsyncd.service || action35v_consume_status=125
    [[ "$action35v_consume_status" -eq 0 ]] || return "$action35v_consume_status"
    require outbound_consumed test ! -e "$action35v_source"
}

produce_bounded_evidence() {
    capture_command payload_identity sha256sum \
        "$payload_root/manifests/serving-health-production.tsv"
}

ownership_sample() {
    local action35v_ipv4_state action35v_ipv6_state action35v_addresses
    local action35v_expected_state action35v_expected_vips
    local action35v_vip_count=0

    action35v_expected_state=Backup
    action35v_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        action35v_expected_state=Master
        action35v_expected_vips=4
    fi
    action35v_ipv4_state=$(busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
        org.keepalived.Vrrp1.Instance State | sed -n 's/.*"\([^"]*\)".*/\1/p')
    action35v_ipv6_state=$(busctl get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
        org.keepalived.Vrrp1.Instance State | sed -n 's/.*"\([^"]*\)".*/\1/p')
    action35v_addresses=$(ip -o address show dev eth0)
    grep -Fq ' 10.1.0.55/22 ' <<<"$action35v_addresses" && action35v_vip_count=$((action35v_vip_count + 1))
    grep -Fq ' 10.1.0.56/22 ' <<<"$action35v_addresses" && action35v_vip_count=$((action35v_vip_count + 1))
    grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$action35v_addresses" && action35v_vip_count=$((action35v_vip_count + 1))
    grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$action35v_addresses" && action35v_vip_count=$((action35v_vip_count + 1))
    printf 'ipv4=%s\nipv6=%s\nshared_vips=%s\n' \
        "$action35v_ipv4_state" "$action35v_ipv6_state" "$action35v_vip_count"
    require ownership_ipv4 test "$action35v_ipv4_state" = "$action35v_expected_state"
    require ownership_ipv6 test "$action35v_ipv6_state" = "$action35v_expected_state"
    require ownership_vips test "$action35v_vip_count" -eq "$action35v_expected_vips"
}

capture_journal_cursor() {
    local action35v_cursor

    capture_command journal_cursor_raw "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    action35v_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal_cursor_raw.stdout")
    require journal_cursor_exact test -n "$action35v_cursor"
    printf '%s\n' "$action35v_cursor" >"$evidence_root/journal.cursor"
    chmod 0600 "$evidence_root/journal.cursor"
}

capture_post_journal() {
    regular_file "$evidence_root/journal.cursor"
    capture_command journal_post "$journalctl_command" --no-pager -o short-iso-precise \
        --after-cursor "$(<"$evidence_root/journal.cursor")" \
        -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
        -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
        -t keepalived-notify -t caddy-ha-health
}

start_sampler() {
    local action35v_sampler=$evidence_root/availability-sampler.sh

    require sampler_pid_absent test ! -e "$evidence_root/availability.pid"
    cat >"$action35v_sampler" <<'SAMPLER'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/bin:/bin
readonly role=$1
readonly root=$2
case "$role" in
    node-a) fqdn=pihole0.local.theama.co; ipv4=10.1.0.53; ipv6=fd36:5aa8:6971:1::53 ;;
    node-b) fqdn=pihole00.local.theama.co; ipv4=10.1.0.54; ipv6=fd36:5aa8:6971:1::54 ;;
    *) exit 64 ;;
esac
sequence=0
while [[ ! -e "$root/availability.stop" && "$sequence" -lt 900 ]]; do
    sequence=$((sequence + 1))
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
    for family in 4 6; do
        dns_status=0
        https_status=0
        node_ui_status=0
        shared_ui_status=0
        if [[ "$family" = 4 ]]; then
            server=127.0.0.1
            address=$ipv4
            shared_address=10.1.0.56
            type=A
            expected=10.1.0.55
        else
            server=::1
            address="[$ipv6]"
            shared_address='[fd36:5aa8:6971:1::56]'
            type=AAAA
            expected=fd36:5aa8:6971:1::55
        fi
        answer=$(dig "@$server" -p 53 pihole.local.theama.co "$type" +short +time=1 +tries=1) || dns_status=$?
        [[ "$answer" = "$expected" ]] || dns_status=90
        status=$(curl "--ipv$family" --silent --show-error --fail --max-time 2 \
            --max-redirs 0 --output /dev/null --write-out '%{http_code}' \
            --resolve "$fqdn:443:$address" "https://$fqdn/healthz") || https_status=$?
        [[ "$status" = 204 ]] || https_status=91
        status=$(curl "--ipv$family" --silent --show-error --fail --location \
            --max-time 2 --max-redirs 2 --output /dev/null --write-out '%{http_code}' \
            --resolve "$fqdn:443:$address" "https://$fqdn/admin/login.php") || node_ui_status=$?
        [[ "$status" = 200 ]] || node_ui_status=92
        status=$(curl "--ipv$family" --silent --show-error --fail --location \
            --max-time 2 --max-redirs 2 --output /dev/null --write-out '%{http_code}' \
            --resolve "pihole-admin.local.theama.co:443:$shared_address" \
            'https://pihole-admin.local.theama.co/admin/login.php') || shared_ui_status=$?
        [[ "$status" = 200 ]] || shared_ui_status=93
        printf '%s\t%s\t%s\tdns=%s\thttps=%s\tnode_ui=%s\tshared_ui=%s\n' \
            "$sequence" "$timestamp" "$family" "$dns_status" "$https_status" \
            "$node_ui_status" "$shared_ui_status" \
            >>"$root/availability.tsv"
    done
    sleep 1
done
SAMPLER
    chmod 0700 "$action35v_sampler"
    : >"$evidence_root/availability.tsv"
    chmod 0600 "$evidence_root/availability.tsv"
    nohup /bin/bash "$action35v_sampler" "$node_role" "$evidence_root" \
        >"$evidence_root/availability.stdout" \
        2>"$evidence_root/availability.stderr" &
    printf '%s\n' "$!" >"$evidence_root/availability.pid"
    chmod 0600 "$evidence_root/availability.pid"
}

stop_sampler() {
    local action35v_pid action35v_wait

    regular_file "$evidence_root/availability.pid"
    action35v_pid=$(<"$evidence_root/availability.pid")
    [[ "$action35v_pid" =~ ^[1-9][0-9]*$ ]]
    : >"$evidence_root/availability.stop"
    for ((action35v_wait = 0; action35v_wait < 10; action35v_wait++)); do
        kill -0 "$action35v_pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$action35v_pid" 2>/dev/null; then
        kill "$action35v_pid"
        wait "$action35v_pid" 2>/dev/null || :
    fi
    require availability_minimum test "$(wc -l <"$evidence_root/availability.tsv")" -ge 4
    require availability_dns_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $4 != "dns=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_dns_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $4 != "dns=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_https_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $5 != "https=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_https_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $5 != "https=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_node_ui_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $6 != "node_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_node_ui_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $6 != "node_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_shared_ui_ipv4 test -z \
        "$(awk -F '\t' '$3 == 4 && $7 != "shared_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
    require availability_shared_ui_ipv6 test -z \
        "$(awk -F '\t' '$3 == 6 && $7 != "shared_ui=0" { print; exit }' "$evidence_root/availability.tsv")"
}

write_decision() {
    local action35v_scenario=$1
    local action35v_expectation=$2
    local action35v_status=$3
    local action35v_expected=$4
    local action35v_observed=$5
    local action35v_raw=$6
    local action35v_decision=$7
    local action35v_raw_hash

    action35v_raw_hash=$(sha256sum "$action35v_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35v_scenario" "$action35v_expectation" "$action35v_status" \
        "$action35v_expected" "$action35v_observed" "$action35v_raw_hash" \
        >"$action35v_decision"
    chmod 0600 "$action35v_raw" "$action35v_decision"
}

production_path_test_node_a_quarantine() {
    local action35v_test_root=$1
    local action35v_repo_root=$2
    local action35v_state_root=$3
    local action35v_payload=$4
    local action35v_evidence=$5
    local action35v_test_target=$6
    local action35v_systemctl=$7
    local action35v_contract=$action35v_test_root/node-a-quarantine-contract.tsv
    local action35v_candidate action35v_name action35v_revision action35v_source
    local action35v_release_hash action35v_payload_hash action35v_raw action35v_decision
    local action35v_status action35v_saved action35v_first

    chmod -R u+rwX -- "$action35v_state_root/quarantine"
    rm -rf -- "$action35v_state_root/quarantine"
    install -d -m 0750 "$action35v_state_root/quarantine"
    : >"$action35v_contract"
    while IFS=$'\t' read -r action35v_name action35v_revision action35v_source; do
        action35v_candidate=$action35v_state_root/quarantine/$action35v_name
        install -d -m 0750 "$action35v_candidate"
        printf 'payload for %s\n' "$action35v_revision" >"$action35v_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"%s","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35v_revision" "$action35v_source" \
            >"$action35v_candidate/release-manifest.json"
        (
            cd "$action35v_candidate"
            find . -type f \
                ! -path ./manifest.sha256 \
                ! -path ./.finalize-request \
                ! -path ./.complete \
                ! -path ./.complete.pending \
                -print0 |
                LC_ALL=C sort -z |
                xargs -0 sha256sum
        ) >"$action35v_candidate/manifest.sha256"
        : >"$action35v_candidate/.finalize-request"
        if [[ "$action35v_source" = node-b ]]; then
            : >"$action35v_candidate/.complete"
        fi
        chmod 0440 "$action35v_candidate"/* "$action35v_candidate"/.[!.]*
        chmod 0550 "$action35v_candidate"
        action35v_release_hash=$(sha256sum "$action35v_candidate/release-manifest.json" | awk '{ print $1 }')
        action35v_payload_hash=$(sha256sum "$action35v_candidate/manifest.sha256" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$action35v_name" "$action35v_revision" \
            "$action35v_source" "$action35v_release_hash" "$action35v_payload_hash" \
            >>"$action35v_contract"
    done <<'CONTRACT'
node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	node-b
node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	node-b
node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d	20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63	node-a
node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d	action17p-node-a-to-node-b-bootstrap	node-a
CONTRACT
    chmod 0600 "$action35v_contract"

    action35v_raw=$action35v_test_root/raw/node-a-quarantine-baseline.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-baseline.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    write_decision node-a-quarantine-baseline accept 0 exact-four exact-four \
        "$action35v_raw" "$action35v_decision"

    install -d -m 0550 "$action35v_state_root/quarantine/unexpected"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-extra-rejection.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-extra-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision node-a-quarantine-extra-rejection reject "$action35v_status" \
        exact-four extra-entry "$action35v_raw" "$action35v_decision"
    rmdir "$action35v_state_root/quarantine/unexpected"

    action35v_first=$(awk -F '\t' 'NR == 1 { print $1 }' "$action35v_contract")
    action35v_candidate=$action35v_state_root/quarantine/$action35v_first
    chmod 0750 "$action35v_candidate"
    chmod 0640 "$action35v_candidate/Caddyfile"
    printf 'changed\n' >>"$action35v_candidate/Caddyfile"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-changed-rejection.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-changed-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision node-a-quarantine-changed-rejection reject "$action35v_status" \
        manifest-valid changed-payload "$action35v_raw" "$action35v_decision"
    sed -i '$d' "$action35v_candidate/Caddyfile"
    chmod 0440 "$action35v_candidate/Caddyfile"
    chmod 0550 "$action35v_candidate"

    action35v_saved=$action35v_test_root/node-a-release-manifest.saved
    install -m 0600 "$action35v_candidate/release-manifest.json" "$action35v_saved"
    chmod 0750 "$action35v_candidate"
    chmod 0640 "$action35v_candidate/release-manifest.json"
    printf '{\n' >"$action35v_candidate/release-manifest.json"
    chmod 0440 "$action35v_candidate/release-manifest.json"
    chmod 0550 "$action35v_candidate"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-malformed-rejection.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-malformed-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision node-a-quarantine-malformed-rejection reject "$action35v_status" \
        exact-release-manifest malformed "$action35v_raw" "$action35v_decision"
    chmod 0750 "$action35v_candidate"
    install -m 0440 "$action35v_saved" "$action35v_candidate/release-manifest.json"

    mv "$action35v_candidate/Caddyfile" "$action35v_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35v_candidate/Caddyfile"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-symlink-rejection.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-symlink-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision node-a-quarantine-symlink-rejection reject "$action35v_status" \
        regular-file symlink "$action35v_raw" "$action35v_decision"
    rm "$action35v_candidate/Caddyfile"
    mv "$action35v_candidate/Caddyfile.saved" "$action35v_candidate/Caddyfile"
    chmod 0550 "$action35v_candidate"

    rm "$action35v_test_target/etc/caddy/current"
    ln -s "$action35v_candidate" "$action35v_test_target/etc/caddy/current"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-reference-rejection.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-reference-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision node-a-quarantine-reference-rejection reject "$action35v_status" \
        unreferenced active-reference "$action35v_raw" "$action35v_decision"
    rm "$action35v_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35v_test_target/etc/caddy/current"

    action35v_raw=$action35v_test_root/raw/node-a-quarantine-disposition.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-disposition.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
        ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-disposition node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    write_decision node-a-quarantine-disposition accept 0 empty empty \
        "$action35v_raw" "$action35v_decision"
    action35v_raw=$action35v_test_root/raw/node-a-quarantine-rollback.txt
    action35v_decision=$action35v_test_root/decisions/node-a-quarantine-rollback.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_NODE_A_QUARANTINE_CONTRACT=$action35v_contract \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
        ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        node-a-quarantine-rollback node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    write_decision node-a-quarantine-rollback accept 0 exact-four exact-four \
        "$action35v_raw" "$action35v_decision"
}

production_path_test() {
    local action35v_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35v_repo_root action35v_inventory action35v_key action35v_repository
    local action35v_source action35v_target action35v_inventory_node action35v_source_hash
    local action35v_deployed_hash action35v_accepted action35v_lifecycle action35v_source_path
    local action35v_observed action35v_raw action35v_decision action35v_status
    local action35v_state_root action35v_payload action35v_evidence action35v_candidate
    local action35v_release_hash action35v_payload_hash action35v_systemctl
    local action35v_marker action35v_marker_label action35v_quarantine_manifest
    local action35v_quarantine_name action35v_quarantine_candidate
    local action35v_test_target action35v_saved_hash action35v_missing_candidate
    local action35v_saved_manifest
    local action35v_promotion_root action35v_promotion_payload
    local action35v_promotion_evidence action35v_promotion_target
    local action35v_promotion_candidate action35v_promotion_manifest_hash
    local action35v_runuser action35v_finalizer action35v_dig action35v_curl
    local action35v_ss action35v_unbound_checkconf action35v_current_before
    local action35v_current_after

    action35v_write_quarantine_manifest() {
        local action35v_fixture_root=$1
        local action35v_fixture_manifest=$2
        local action35v_fixture_path action35v_fixture_relative
        local action35v_fixture_encoded action35v_fixture_type
        local action35v_fixture_metadata action35v_fixture_hash

        printf '# path-b64\ttype\tmetadata\tsha256\n' >"$action35v_fixture_manifest"
        while IFS= read -r -d '' action35v_fixture_path; do
            action35v_fixture_relative=${action35v_fixture_path#"$action35v_fixture_root"/}
            action35v_fixture_encoded=$(printf '%s' "$action35v_fixture_relative" | base64 -w 0)
            if [[ -d "$action35v_fixture_path" && ! -L "$action35v_fixture_path" ]]; then
                action35v_fixture_type=directory
                action35v_fixture_hash=-
            elif [[ -f "$action35v_fixture_path" && ! -L "$action35v_fixture_path" ]]; then
                if [[ -s "$action35v_fixture_path" ]]; then
                    action35v_fixture_type='regular file'
                else
                    action35v_fixture_type='regular empty file'
                fi
                action35v_fixture_hash=$(sha256sum "$action35v_fixture_path" | awk '{ print $1 }')
            else
                return 1
            fi
            action35v_fixture_metadata=$(stat -c '%U:%G:%a' "$action35v_fixture_path")
            printf '%s\t%s\t%s\t%s\n' "$action35v_fixture_encoded" \
                "$action35v_fixture_type" "$action35v_fixture_metadata" \
                "$action35v_fixture_hash" >>"$action35v_fixture_manifest"
        done < <(find "$action35v_fixture_root" -mindepth 1 -print0 | LC_ALL=C sort -z)
    }

    [[ "$action35v_test_root" = /tmp/* && -d "$action35v_test_root" && ! -L "$action35v_test_root" ]]
    chmod 0700 "$action35v_test_root"
    install -d -m 0700 "$action35v_test_root/raw" "$action35v_test_root/decisions"
    if [[ -n "${ACTION35V_TEST_REPOSITORY_ROOT:-}" ]]; then
        action35v_repo_root=$ACTION35V_TEST_REPOSITORY_ROOT
    else
        action35v_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    fi
    action35v_inventory=$action35v_repo_root/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r action35v_key action35v_repository action35v_source \
        action35v_target action35v_inventory_node action35v_source_hash \
        action35v_deployed_hash action35v_accepted action35v_lifecycle; do
        [[ "$action35v_key" = '# key' ]] && continue
        action35v_raw=$action35v_test_root/raw/inventory-$action35v_key.txt
        action35v_decision=$action35v_test_root/decisions/inventory-$action35v_key.tsv
        if [[ "$action35v_repository" = runtime-generated ]]; then
            printf '%s\t%s\t%s\n' "$action35v_key" "$action35v_target" \
                "$action35v_deployed_hash" >"$action35v_raw"
            action35v_observed=$(awk -F '\t' '{ print $3 }' "$action35v_raw")
            require_equal "production_inventory_${action35v_key}" \
                "$action35v_deployed_hash" "$action35v_observed"
            write_decision "inventory-$action35v_key" accept 0 \
                "$action35v_deployed_hash" "$action35v_observed" \
                "$action35v_raw" "$action35v_decision"
            continue
        fi
        action35v_source_path=${action35v_repo_root%/homelab-server-configs}/$action35v_repository/$action35v_source
        sha256sum "$action35v_source_path" >"$action35v_raw"
        action35v_observed=$(awk '{ print $1 }' "$action35v_raw")
        require_equal "production_inventory_${action35v_key}" \
            "$action35v_source_hash" "$action35v_observed"
        write_decision "inventory-$action35v_key" accept 0 \
            "$action35v_source_hash" "$action35v_observed" \
            "$action35v_raw" "$action35v_decision"
    done <"$action35v_inventory"

    action35v_state_root=$action35v_test_root/state
    action35v_payload=$(mktemp -d /tmp/caddy-action35v-production-payload.XXXXXX)
    action35v_evidence=$(mktemp -d /tmp/caddy-action35v-production-evidence.XXXXXX)
    action35v_candidate=$action35v_state_root/incoming/node-a/$retained_name
    action35v_systemctl=$action35v_test_root/systemctl
    install -d -m 0700 "$action35v_candidate" \
        "$action35v_state_root/outgoing" \
        "$action35v_state_root/releases" "$action35v_payload/manifests" \
        "$action35v_evidence"
    install -d -m 0750 "$action35v_state_root/quarantine"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$action35v_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$action35v_repo_root/Caddy/manifests/action35v-node-b-quarantine.tsv" \
        "$action35v_payload/manifests/action35v-node-b-quarantine.tsv"
    printf 'payload\n' >"$action35v_candidate/Caddyfile"
    printf '%s  Caddyfile\n' "$(sha256sum "$action35v_candidate/Caddyfile" | awk '{ print $1 }')" \
        >"$action35v_candidate/manifest.sha256"
    printf '{"revision":"%s","source_node":"node-a"}\n' "$retained_name" \
        >"$action35v_candidate/release-manifest.json"
    chmod 0500 "$action35v_candidate"
    while IFS= read -r action35v_quarantine_name; do
        action35v_quarantine_candidate=$action35v_state_root/quarantine/$action35v_quarantine_name
        install -d -m 0750 "$action35v_quarantine_candidate"
        printf 'payload for %s\n' "$action35v_quarantine_name" \
            >"$action35v_quarantine_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35v_quarantine_name" \
            >"$action35v_quarantine_candidate/release-manifest.json"
        {
            printf '%s  Caddyfile\n' \
                "$(sha256sum "$action35v_quarantine_candidate/Caddyfile" | awk '{ print $1 }')"
            printf '%s  release-manifest.json\n' \
                "$(sha256sum "$action35v_quarantine_candidate/release-manifest.json" | awk '{ print $1 }')"
        } >"$action35v_quarantine_candidate/manifest.sha256"
        chmod 0440 "$action35v_quarantine_candidate/"*
        case "$action35v_quarantine_name" in
            node-a-action17p-* | node-a-action33k-*)
                : >"$action35v_quarantine_candidate/.complete"
                : >"$action35v_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35v_quarantine_candidate/.complete" \
                    "$action35v_quarantine_candidate/.finalize-request"
                ;;
            *)
                : >"$action35v_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35v_quarantine_candidate/.finalize-request"
                ;;
        esac
        chmod 0550 "$action35v_quarantine_candidate"
    done < <(quarantine_names)
    action35v_quarantine_manifest=$action35v_test_root/quarantine-inventory.tsv
    action35v_write_quarantine_manifest "$action35v_state_root/quarantine" \
        "$action35v_quarantine_manifest"
    action35v_test_target=$action35v_test_root/target
    install -d -m 0700 "$action35v_test_target/etc/caddy/releases/current-test"
    ln -s releases/current-test "$action35v_test_target/etc/caddy/current"
    install -d -m 0755 "$action35v_test_target/usr/local/libexec"
    install -m 0755 "$action35v_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35v_test_target$legacy_lighttpd_helper"
    action35v_raw=$action35v_test_root/raw/legacy-helper-node-b-baseline.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-node-b-baseline.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    write_decision legacy-helper-node-b-baseline accept 0 exact-legacy exact-legacy \
        "$action35v_raw" "$action35v_decision"
    action35v_raw=$action35v_test_root/raw/legacy-helper-removal.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-removal.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-remove node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    path_absent "$action35v_test_target$legacy_lighttpd_helper"
    write_decision legacy-helper-removal accept 0 absent absent \
        "$action35v_raw" "$action35v_decision"
    action35v_raw=$action35v_test_root/raw/legacy-helper-rollback.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-rollback.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-rollback node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    require_equal production_test_legacy_helper_restored "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35v_test_target$legacy_lighttpd_helper" | awk '{ print $1 }')"
    write_decision legacy-helper-rollback accept 0 exact-legacy exact-legacy \
        "$action35v_raw" "$action35v_decision"
    rm -f -- "$action35v_test_target$legacy_lighttpd_helper"
    action35v_raw=$action35v_test_root/raw/legacy-helper-node-a-baseline.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-node-a-baseline.tsv
    ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw"
    write_decision legacy-helper-node-a-baseline accept 0 absent absent \
        "$action35v_raw" "$action35v_decision"
    action35v_raw=$action35v_test_root/raw/legacy-helper-node-b-absent-rejection.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-node-b-absent-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision legacy-helper-node-b-absent-rejection reject "$action35v_status" \
        exact-legacy absent "$action35v_raw" "$action35v_decision"
    install -m 0755 "$action35v_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35v_test_target$legacy_lighttpd_helper"
    action35v_raw=$action35v_test_root/raw/legacy-helper-node-a-present-rejection.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-node-a-present-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-check node-a "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision legacy-helper-node-a-present-rejection reject "$action35v_status" \
        absent present "$action35v_raw" "$action35v_decision"
    rm -f -- "$action35v_test_target$legacy_lighttpd_helper"
    ln -s /dev/null "$action35v_test_target$legacy_lighttpd_helper"
    action35v_raw=$action35v_test_root/raw/legacy-helper-node-b-symlink-rejection.txt
    action35v_decision=$action35v_test_root/decisions/legacy-helper-node-b-symlink-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        legacy-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision legacy-helper-node-b-symlink-rejection reject "$action35v_status" \
        regular-file symlink "$action35v_raw" "$action35v_decision"
    rm -f -- "$action35v_test_target$legacy_lighttpd_helper"
    action35v_release_hash=$(sha256sum "$action35v_candidate/release-manifest.json" | awk '{ print $1 }')
    action35v_payload_hash=$(sha256sum "$action35v_candidate/manifest.sha256" | awk '{ print $1 }')
    cat >"$action35v_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35V_SYSTEMCTL_CALLS:?}"
SYSTEMCTL
    chmod 0700 "$action35v_systemctl"
    : >"$action35v_test_root/systemctl.calls"
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256=$action35v_release_hash \
        ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35v_payload_hash \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
        ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        retained-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_test_root/retained-check.stdout"
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_test_root/quarantine-check.stdout"
    install -d -m 0550 "$action35v_state_root/quarantine/unexpected"
    action35v_raw=$action35v_test_root/raw/quarantine-extra-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-extra-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-extra-rejection reject "$action35v_status" \
        exact-four-entries extra-entry "$action35v_raw" "$action35v_decision"
    rmdir "$action35v_state_root/quarantine/unexpected"
    action35v_quarantine_candidate=$action35v_state_root/quarantine/$(quarantine_names | sed -n '1p')
    action35v_saved_hash=$(sha256sum "$action35v_quarantine_candidate/Caddyfile" | awk '{ print $1 }')
    chmod 0750 "$action35v_quarantine_candidate"
    chmod 0640 "$action35v_quarantine_candidate/Caddyfile"
    printf 'changed\n' >>"$action35v_quarantine_candidate/Caddyfile"
    action35v_raw=$action35v_test_root/raw/quarantine-changed-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-changed-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-changed-rejection reject "$action35v_status" \
        exact-captured-hash changed-hash "$action35v_raw" "$action35v_decision"
    sed -i '$d' "$action35v_quarantine_candidate/Caddyfile"
    chmod 0440 "$action35v_quarantine_candidate/Caddyfile"
    [[ "$(sha256sum "$action35v_quarantine_candidate/Caddyfile" | awk '{ print $1 }')" = "$action35v_saved_hash" ]]
    mv "$action35v_quarantine_candidate/Caddyfile" \
        "$action35v_quarantine_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35v_quarantine_candidate/Caddyfile"
    action35v_raw=$action35v_test_root/raw/quarantine-symlink-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-symlink-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-symlink-rejection reject "$action35v_status" \
        regular-file symlink "$action35v_raw" "$action35v_decision"
    rm "$action35v_quarantine_candidate/Caddyfile"
    mv "$action35v_quarantine_candidate/Caddyfile.saved" \
        "$action35v_quarantine_candidate/Caddyfile"
    chmod 0550 "$action35v_quarantine_candidate"
    action35v_missing_candidate=$action35v_test_root/missing-quarantine-candidate
    chmod 0750 "$action35v_quarantine_candidate"
    mv "$action35v_quarantine_candidate" "$action35v_missing_candidate"
    action35v_raw=$action35v_test_root/raw/quarantine-missing-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-missing-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-missing-rejection reject "$action35v_status" \
        exact-four-entries missing-entry "$action35v_raw" "$action35v_decision"
    mv "$action35v_missing_candidate" "$action35v_quarantine_candidate"
    chmod 0550 "$action35v_quarantine_candidate"
    action35v_saved_manifest=$action35v_test_root/release-manifest.saved
    install -m 0600 "$action35v_quarantine_candidate/release-manifest.json" \
        "$action35v_saved_manifest"
    chmod 0750 "$action35v_quarantine_candidate"
    chmod 0640 "$action35v_quarantine_candidate/release-manifest.json"
    printf '{\n' >"$action35v_quarantine_candidate/release-manifest.json"
    action35v_write_quarantine_manifest "$action35v_state_root/quarantine" \
        "$action35v_quarantine_manifest"
    action35v_raw=$action35v_test_root/raw/quarantine-malformed-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-malformed-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-malformed-rejection reject "$action35v_status" \
        valid-release-json malformed-json "$action35v_raw" "$action35v_decision"
    install -m 0440 "$action35v_saved_manifest" \
        "$action35v_quarantine_candidate/release-manifest.json"
    chmod 0550 "$action35v_quarantine_candidate"
    action35v_write_quarantine_manifest "$action35v_state_root/quarantine" \
        "$action35v_quarantine_manifest"
    rm "$action35v_test_target/etc/caddy/current"
    ln -s "$action35v_quarantine_candidate" \
        "$action35v_test_target/etc/caddy/current"
    action35v_raw=$action35v_test_root/raw/quarantine-reference-rejection.txt
    action35v_decision=$action35v_test_root/decisions/quarantine-reference-rejection.tsv
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        quarantine-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        return 1
    else
        action35v_status=$?
    fi
    write_decision quarantine-reference-rejection reject "$action35v_status" \
        unreferenced active-reference "$action35v_raw" "$action35v_decision"
    rm "$action35v_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35v_test_target/etc/caddy/current"
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256=$action35v_release_hash \
        ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35v_payload_hash \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
        ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        retained-disposition node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_test_root/retained-disposition.stdout"
    [[ ! -e "$action35v_candidate" && -d "$action35v_evidence/retained-incoming" ]]
    ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256=$action35v_release_hash \
        ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35v_payload_hash \
        ACTION35V_QUARANTINE_INVENTORY_MANIFEST=$action35v_quarantine_manifest \
        ACTION35V_TARGET_ROOT=$action35v_test_target \
        ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
        ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        retained-rollback node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_test_root/retained-rollback.stdout"
    [[ -d "$action35v_candidate" && ! -e "$action35v_evidence/retained-incoming" ]]

    action35v_raw=$action35v_test_root/raw/transaction-rejection.txt
    action35v_decision=$action35v_test_root/decisions/transaction-rejection.tsv
    install -d -m 0700 "$action35v_state_root/incoming/node-a/unexpected"
    if ACTION35V_PRODUCTION_PATH_TEST=1 \
        ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
        ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
        ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
        ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
        ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256=$action35v_release_hash \
        ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35v_payload_hash \
        /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
        retained-check node-b "$action35v_payload" "$action35v_evidence" \
        >"$action35v_raw" 2>&1; then
        action35v_status=0
    else
        action35v_status=$?
    fi
    write_decision transaction-rejection reject "$action35v_status" exact-retained-only \
        unexpected-sibling "$action35v_raw" "$action35v_decision"
    rmdir "$action35v_state_root/incoming/node-a/unexpected"

    for action35v_marker in .finalize-request .complete.pending .complete; do
        action35v_marker_label=${action35v_marker#.}
        action35v_marker_label=${action35v_marker_label//./-}
        chmod 0700 "$action35v_candidate"
        : >"$action35v_candidate/$action35v_marker"
        chmod 0500 "$action35v_candidate"
        action35v_raw=$action35v_test_root/raw/transaction-marker-$action35v_marker_label-rejection.txt
        action35v_decision=$action35v_test_root/decisions/transaction-marker-$action35v_marker_label-rejection.tsv
        if ACTION35V_PRODUCTION_PATH_TEST=1 \
            ACTION35V_INCOMING_ROOT=$action35v_state_root/incoming \
            ACTION35V_OUTGOING_ROOT=$action35v_state_root/outgoing \
            ACTION35V_QUARANTINE_ROOT=$action35v_state_root/quarantine \
            ACTION35V_RELEASES_ROOT=$action35v_state_root/releases \
            ACTION35V_RETAINED_RELEASE_MANIFEST_SHA256=$action35v_release_hash \
            ACTION35V_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35v_payload_hash \
            /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
            retained-check node-b "$action35v_payload" "$action35v_evidence" \
            >"$action35v_raw" 2>&1; then
            action35v_status=0
        else
            action35v_status=$?
        fi
        write_decision "transaction-marker-$action35v_marker_label-rejection" reject \
            "$action35v_status" absent present "$action35v_raw" "$action35v_decision"
        chmod 0700 "$action35v_candidate"
        rm -f -- "$action35v_candidate/$action35v_marker"
        chmod 0500 "$action35v_candidate"
    done

    action35v_raw=$action35v_test_root/raw/transaction-acceptance.txt
    action35v_decision=$action35v_test_root/decisions/transaction-acceptance.tsv
    {
        cat "$action35v_test_root/retained-check.stdout"
        cat "$action35v_test_root/quarantine-check.stdout"
        cat "$action35v_test_root/retained-disposition.stdout"
        cat "$action35v_test_root/retained-rollback.stdout"
        cat "$action35v_test_root/systemctl.calls"
        find "$action35v_state_root/incoming/node-a" -mindepth 1 -maxdepth 1 \
            -printf '%f\t%y\t%u:%g:%m\n' | LC_ALL=C sort
    } >"$action35v_raw"
    write_decision transaction-acceptance reach 0 retained-restored \
        retained-restored "$action35v_raw" "$action35v_decision"
    production_path_test_node_a_quarantine "$action35v_test_root" \
        "$action35v_repo_root" "$action35v_state_root" "$action35v_payload" \
        "$action35v_evidence" "$action35v_test_target" "$action35v_systemctl"

    action35v_promotion_root=$action35v_test_root/promotion
    action35v_promotion_payload=$(mktemp -d /tmp/caddy-action35v-promotion-payload.XXXXXX)
    action35v_promotion_evidence=$(mktemp -d /tmp/caddy-action35v-promotion-evidence.XXXXXX)
    action35v_promotion_target=$action35v_promotion_root/target
    action35v_promotion_candidate=$action35v_promotion_root/outgoing/$serving_revision
    install -d -m 0700 "$action35v_promotion_root/incoming" \
        "$action35v_promotion_root/releases" "$action35v_promotion_candidate" \
        "$action35v_promotion_target/etc/caddy/releases/$node_a_revision" \
        "$action35v_promotion_target/etc/default" \
        "$action35v_promotion_payload/manifests" \
        "$action35v_promotion_payload/repositories"
    printf '{"revision":"%s"}\n' "$node_a_revision" \
        >"$action35v_promotion_target/etc/caddy/releases/$node_a_revision/release-manifest.json"
    ln -s "releases/$node_a_revision" "$action35v_promotion_target/etc/caddy/current"
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$action35v_promotion_target/etc/default/caddy-ha"
    install -m 0600 "$action35v_repo_root/Caddy/manifests/serving-health-production.tsv" \
        "$action35v_promotion_payload/manifests/serving-health-production.tsv"
    install -m 0600 "$action35v_repo_root/Caddy/manifests/action35v-node-b-quarantine.tsv" \
        "$action35v_promotion_payload/manifests/action35v-node-b-quarantine.tsv"
    while IFS=$'\t' read -r action35v_repository action35v_source _; do
        [[ "$action35v_repository" = '# repository' ]] && continue
        action35v_source_path=${action35v_repo_root%/homelab-server-configs}/$action35v_repository/$action35v_source
        action35v_target=$action35v_promotion_payload/repositories/$action35v_repository/$action35v_source
        install -d -m 0700 "${action35v_target%/*}"
        install -m 0600 "$action35v_source_path" "$action35v_target"
    done <"$action35v_repo_root/Caddy/manifests/serving-health-production.tsv"
    printf 'respond /healthz 204\n' >"$action35v_promotion_candidate/Caddyfile"
    printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
        "$serving_revision" "$serving_parent" \
        >"$action35v_promotion_candidate/release-manifest.json"
    (
        cd "$action35v_promotion_candidate"
        find . -type f ! -path ./manifest.sha256 -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action35v_promotion_candidate/manifest.sha256"
    : >"$action35v_promotion_candidate/.finalize-request"
    chmod 0440 "$action35v_promotion_candidate/"*
    chmod 0550 "$action35v_promotion_candidate"
    action35v_promotion_manifest_hash=$(sha256sum \
        "$action35v_promotion_candidate/manifest.sha256" | awk '{ print $1 }')

    action35v_runuser=$action35v_promotion_root/runuser
    action35v_finalizer=$action35v_promotion_root/finalizer
    action35v_dig=$action35v_promotion_root/dig
    action35v_curl=$action35v_promotion_root/curl
    action35v_ss=$action35v_promotion_root/ss
    action35v_unbound_checkconf=$action35v_promotion_root/unbound-checkconf
    cat >"$action35v_runuser" <<'RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -u && "$3" = -- ]]
printf '%s\n' "$2" >>"${ACTION35V_TEST_RUNUSER_CALLS:?}"
shift 3
exec "$@"
RUNUSER
    cat >"$action35v_finalizer" <<'FINALIZER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source-role && "$2" = node-a ]]
candidate=${ACTION35V_INCOMING_ROOT:?}/node-a/${ACTION35V_TEST_SERVING_REVISION:?}
[[ -d "$candidate" && -f "$candidate/.finalize-request" ]]
printf '%s\n' "$*" >>"${ACTION35V_TEST_FINALIZER_CALLS:?}"
chmod 0750 "$candidate"
: >"$candidate/.complete"
chmod 0440 "$candidate/.complete"
chmod 0550 "$candidate"
FINALIZER
    cat >"$action35v_systemctl" <<'SYSTEMCTL_PROMOTION'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35V_SYSTEMCTL_CALLS:?}"
if [[ "$1" = start && "$2" = caddy-sync-reconcile.service ]]; then
    candidate=${ACTION35V_INCOMING_ROOT:?}/node-a/${ACTION35V_TEST_SERVING_REVISION:?}
    release=${ACTION35V_RELEASES_ROOT:?}/${ACTION35V_TEST_SERVING_REVISION:?}
    [[ -f "$candidate/.complete" ]]
    cp -a -- "$candidate" "$release"
    chmod 0750 "$release"
    rm -f -- "$release/.complete" "$release/.finalize-request"
    chmod 0550 "$release"
    rm -f -- "${ACTION35V_TARGET_ROOT:?}/etc/caddy/current"
    ln -s "$release" "$ACTION35V_TARGET_ROOT/etc/caddy/current"
fi
case "$1" in
    is-active) [[ "$2" = --quiet ]] ;;
    start | stop) [[ $# -eq 2 ]] ;;
    *) : ;;
esac
SYSTEMCTL_PROMOTION
    cat >"$action35v_dig" <<'DIG'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$action35v_curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
revision=$(jq -r '.revision // empty' "${ACTION35V_TARGET_ROOT:?}/etc/caddy/current/release-manifest.json")
if [[ "$revision" = "${ACTION35V_TEST_SERVING_REVISION:?}" ]]; then
    printf '204\n'
else
    printf '404\n'
    exit 22
fi
CURL
    cat >"$action35v_ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n'
SS
    cat >"$action35v_unbound_checkconf" <<'UNBOUND'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]]
grep -Fq 'local-zone: "local.theama.co." static' "$1"
UNBOUND
    chmod 0700 "$action35v_runuser" "$action35v_finalizer" "$action35v_systemctl" \
        "$action35v_dig" "$action35v_curl" "$action35v_ss" "$action35v_unbound_checkconf"
    : >"$action35v_test_root/runuser.calls"
    : >"$action35v_test_root/finalizer.calls"
    : >"$action35v_test_root/systemctl.calls"
    action35v_current_before=$(jq -r '.revision' \
        "$action35v_promotion_target/etc/caddy/current/release-manifest.json")
    action35v_raw=$action35v_test_root/raw/post-promotion-sequence.txt
    action35v_decision=$action35v_test_root/decisions/post-promotion-sequence.tsv
    {
        printf 'current_before=%s\n' "$action35v_current_before"
        ACTION35V_PRODUCTION_PATH_TEST=1 \
            ACTION35V_INCOMING_ROOT=$action35v_promotion_root/incoming \
            ACTION35V_OUTGOING_ROOT=$action35v_promotion_root/outgoing \
            ACTION35V_QUARANTINE_ROOT=$action35v_promotion_root/quarantine \
            ACTION35V_RELEASES_ROOT=$action35v_promotion_root/releases \
            ACTION35V_TARGET_ROOT=$action35v_promotion_target \
            ACTION35V_SERVING_PAYLOAD_MANIFEST_SHA256=$action35v_promotion_manifest_hash \
            ACTION35V_FINALIZER_COMMAND=$action35v_finalizer \
            ACTION35V_RUNUSER_COMMAND=$action35v_runuser \
            ACTION35V_SYNC_USER=$(id -un) ACTION35V_SYNC_GROUP=$(id -gn) \
            ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
            ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
            ACTION35V_TEST_RUNUSER_CALLS=$action35v_test_root/runuser.calls \
            ACTION35V_TEST_FINALIZER_CALLS=$action35v_test_root/finalizer.calls \
            ACTION35V_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
            promote node-a "$action35v_promotion_payload" "$action35v_promotion_evidence"
        action35v_current_after=$(jq -r '.revision' \
            "$action35v_promotion_target/etc/caddy/current/release-manifest.json")
        printf 'current_after=%s\n' "$action35v_current_after"
        cat "$action35v_test_root/runuser.calls" "$action35v_test_root/finalizer.calls" \
            "$action35v_test_root/systemctl.calls"
        ACTION35V_PRODUCTION_PATH_TEST=1 \
            ACTION35V_TARGET_ROOT=$action35v_promotion_target \
            ACTION35V_ENVIRONMENT_FILE=$action35v_promotion_target/etc/default/caddy-ha \
            ACTION35V_RUNUSER_COMMAND=$action35v_runuser \
            ACTION35V_SYSTEMCTL_COMMAND=$action35v_systemctl \
            ACTION35V_DNS_DIG_COMMAND=$action35v_dig \
            ACTION35V_CURL_COMMAND=$action35v_curl \
            ACTION35V_SS_COMMAND=$action35v_ss \
            ACTION35V_UNBOUND_CHECKCONF_COMMAND=$action35v_unbound_checkconf \
            ACTION35V_SYSTEMCTL_CALLS=$action35v_test_root/systemctl.calls \
            ACTION35V_TEST_RUNUSER_CALLS=$action35v_test_root/runuser.calls \
            ACTION35V_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35v_repo_root/Caddy/scripts/apply-coupled-serving-health-action35v.sh" \
            candidate-check node-a "$action35v_promotion_payload" "$action35v_promotion_evidence"
        cat "$action35v_promotion_evidence/caddy_identity.stdout" \
            "$action35v_promotion_evidence/caddy_identity.status"
    } >"$action35v_raw" 2>&1
    action35v_current_after=$(jq -r '.revision' \
        "$action35v_promotion_target/etc/caddy/current/release-manifest.json")
    require_equal production_test_current_before "$node_a_revision" "$action35v_current_before"
    require_equal production_test_current_after "$serving_revision" "$action35v_current_after"
    write_decision post-promotion-sequence accept 0 "$serving_revision" \
        "$action35v_current_after" "$action35v_raw" "$action35v_decision"
    rm -rf -- "$action35v_promotion_payload" "$action35v_promotion_evidence"
    rm -rf -- "$action35v_payload" "$action35v_evidence"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

if [[ "${1:-}" = --production-path-test ]]; then
    [[ $# -eq 1 ]]
    production_path_test
    exit 0
fi

[[ $# -eq 4 ]] || {
    usage
    exit 64
}
readonly mode=$1
readonly node_role=$2
readonly payload_root=$3
readonly evidence_root=$4
[[ "$mode" =~ ^(preflight|candidate-check|quarantine-check|node-a-quarantine-check|node-a-quarantine-disposition|node-a-quarantine-rollback|retained-check|retained-disposition|retained-rollback|legacy-check|legacy-remove|legacy-rollback|install|promote|accept|rollback|ownership|journal-cursor|journal-capture|sampler-start|sampler-stop|consume|final-residue|evidence-probe)$ ]]
[[ "$node_role" =~ ^node-[ab]$ ]]
safe_root "$payload_root"
safe_root "$evidence_root"
validate_payload

case "$mode" in
    preflight) validate_split_baseline ;;
    candidate-check) parser_and_identity_checks ;;
    quarantine-check) validate_quarantine_inventory "$quarantine_root" quarantine ;;
    node-a-quarantine-check) validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine ;;
    node-a-quarantine-disposition) disposition_node_a_quarantine ;;
    node-a-quarantine-rollback) restore_node_a_quarantine ;;
    retained-check) validate_retained_node_b_entry ;;
    retained-disposition) disposition_retained_node_b_entry ;;
    retained-rollback) restore_retained_node_b_entry ;;
    legacy-check) validate_legacy_lighttpd_helper ;;
    legacy-remove) remove_legacy_lighttpd_helper ;;
    legacy-rollback) restore_legacy_lighttpd_helper ;;
    install) install_serving_artifacts ;;
    promote) promote_local_candidate ;;
    accept) accept_installed_node ;;
    rollback) rollback_node ;;
    ownership) ownership_sample ;;
    journal-cursor) capture_journal_cursor ;;
    journal-capture) capture_post_journal ;;
    sampler-start) start_sampler ;;
    sampler-stop) stop_sampler ;;
    consume) consume_outbound ;;
    final-residue) validate_final_residue ;;
    evidence-probe) produce_bounded_evidence ;;
esac
