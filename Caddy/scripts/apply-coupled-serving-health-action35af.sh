#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_35_af
readonly node_a_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly serving_revision=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca
readonly serving_parent=$node_a_revision
readonly serving_payload_manifest_sha256=${ACTION35AF_SERVING_PAYLOAD_MANIFEST_SHA256:-ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962}
readonly retained_name=action17p-node-a-to-node-b-bootstrap
readonly retained_release_manifest_sha256=${ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256:-81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3}
readonly retained_payload_manifest_sha256=${ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256:-f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8}
readonly legacy_lighttpd_helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly legacy_lighttpd_helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly incoming_root=${ACTION35AF_INCOMING_ROOT:-/var/lib/caddy-sync/incoming}
readonly outgoing_root=${ACTION35AF_OUTGOING_ROOT:-/var/lib/caddy-sync/outbound}
readonly quarantine_root=${ACTION35AF_QUARANTINE_ROOT:-/var/lib/caddy-sync/quarantine}
readonly releases_root=${ACTION35AF_RELEASES_ROOT:-/etc/caddy/releases}
readonly node_environment=${ACTION35AF_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly runuser_command=${ACTION35AF_RUNUSER_COMMAND:-/usr/sbin/runuser}
readonly finalizer_command=${ACTION35AF_FINALIZER_COMMAND:-/usr/local/libexec/finalize-incoming-release-v2.sh}
readonly publisher_command=${ACTION35AF_PUBLISHER_COMMAND:-/usr/local/libexec/publish-release-v2.sh}
readonly sync_user=${ACTION35AF_SYNC_USER:-caddy-sync}
readonly sync_group=${ACTION35AF_SYNC_GROUP:-caddy-sync}
readonly systemctl_command=${ACTION35AF_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly journalctl_command=${ACTION35AF_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
readonly unbound_checkconf_command=${ACTION35AF_UNBOUND_CHECKCONF_COMMAND:-/usr/sbin/unbound-checkconf}
readonly systemd_tmpfiles_command=${ACTION35AF_SYSTEMD_TMPFILES_COMMAND:-/usr/bin/systemd-tmpfiles}
readonly sleep_command=${ACTION35AF_SLEEP_COMMAND:-/usr/bin/sleep}
readonly busctl_command=${ACTION35AF_BUSCTL_COMMAND:-/usr/bin/busctl}
readonly ip_command=${ACTION35AF_IP_COMMAND:-/usr/sbin/ip}
readonly date_command=${ACTION35AF_DATE_COMMAND:-/usr/bin/date}
readonly daemon_observation_attempts=${ACTION35AF_DAEMON_OBSERVATION_ATTEMPTS:-30}
readonly daemon_observation_delay=${ACTION35AF_DAEMON_OBSERVATION_DELAY:-1}
readonly ownership_attempts=${ACTION35AF_OWNERSHIP_ATTEMPTS:-24}
readonly ownership_stable_samples=${ACTION35AF_OWNERSHIP_STABLE_SAMPLES:-3}
readonly ownership_sample_delay=${ACTION35AF_OWNERSHIP_SAMPLE_DELAY:-2}
readonly target_root=${ACTION35AF_TARGET_ROOT:-}

if [[ -n "${ACTION35AF_INCOMING_ROOT:-}${ACTION35AF_OUTGOING_ROOT:-}${ACTION35AF_QUARANTINE_ROOT:-}${ACTION35AF_RELEASES_ROOT:-}${ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256:-}${ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256:-}${ACTION35AF_QUARANTINE_INVENTORY_MANIFEST:-}${ACTION35AF_NODE_A_QUARANTINE_CONTRACT:-}${ACTION35AF_SERVING_PAYLOAD_MANIFEST_SHA256:-}${ACTION35AF_FINALIZER_COMMAND:-}${ACTION35AF_PUBLISHER_COMMAND:-}${ACTION35AF_SYNC_USER:-}${ACTION35AF_SYNC_GROUP:-}${ACTION35AF_SYSTEMD_TMPFILES_COMMAND:-}${ACTION35AF_SLEEP_COMMAND:-}${ACTION35AF_BUSCTL_COMMAND:-}${ACTION35AF_IP_COMMAND:-}${ACTION35AF_DATE_COMMAND:-}${ACTION35AF_DAEMON_OBSERVATION_ATTEMPTS:-}${ACTION35AF_DAEMON_OBSERVATION_DELAY:-}${ACTION35AF_OWNERSHIP_ATTEMPTS:-}${ACTION35AF_OWNERSHIP_STABLE_SAMPLES:-}${ACTION35AF_OWNERSHIP_SAMPLE_DELAY:-}" &&
    "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
    exit 64
fi

usage() {
    printf 'Usage: %s --production-path-test | MODE node-a|node-b PAYLOAD_ROOT EVIDENCE_ROOT\n' "${0##*/}" >&2
}

safe_root() {
    local action35af_root=$1

    [[ "$action35af_root" == /tmp/caddy-action35af-* &&
        -d "$action35af_root" && ! -L "$action35af_root" ]]
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

effective_path() {
    local action35af_logical_path=$1

    [[ "$action35af_logical_path" = /* ]]
    printf '%s%s\n' "$target_root" "$action35af_logical_path"
}

capture_command() {
    local action35af_label=$1
    shift
    local action35af_stdout=$evidence_root/$action35af_label.stdout
    local action35af_stderr=$evidence_root/$action35af_label.stderr
    local action35af_status=$evidence_root/$action35af_label.status
    local action35af_rc=0

    : >"$action35af_stdout"
    : >"$action35af_stderr"
    if "$@" >"$action35af_stdout" 2>"$action35af_stderr"; then
        action35af_rc=0
    else
        action35af_rc=$?
    fi
    printf '%s\n' "$action35af_rc" >"$action35af_status"
    chmod 0600 "$action35af_stdout" "$action35af_stderr" "$action35af_status"
    [[ "$(stat -c '%s' "$action35af_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35af_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35af_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35af_stderr" >/dev/null
    return "$action35af_rc"
}

capture_stdin_command() {
    local action35af_label=$1
    local action35af_input=$2
    shift 2
    local action35af_stdout=$evidence_root/$action35af_label.stdout
    local action35af_stderr=$evidence_root/$action35af_label.stderr
    local action35af_status=$evidence_root/$action35af_label.status
    local action35af_rc=0

    regular_file "$action35af_input"
    : >"$action35af_stdout"
    : >"$action35af_stderr"
    if "$@" <"$action35af_input" >"$action35af_stdout" 2>"$action35af_stderr"; then
        action35af_rc=0
    else
        action35af_rc=$?
    fi
    printf '%s\n' "$action35af_rc" >"$action35af_status"
    chmod 0600 "$action35af_stdout" "$action35af_stderr" "$action35af_status"
    [[ "$(stat -c '%s' "$action35af_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35af_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35af_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35af_stderr" >/dev/null
    return "$action35af_rc"
}

require() {
    local action35af_label=$1
    shift

    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action35af_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action35af_label" >&2
    return 1
}

require_equal() {
    local action35af_label=$1
    local action35af_expected=$2
    local action35af_observed=$3

    [[ "$action35af_label" =~ ^[a-z0-9_]+$ ]]
    [[ "$action35af_expected" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    [[ "$action35af_observed" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    printf '%s_expected_%s=%s\n' "$prefix" "$action35af_label" "$action35af_expected"
    printf '%s_observed_%s=%s\n' "$prefix" "$action35af_label" "$action35af_observed"
    require "$action35af_label" test "$action35af_observed" = "$action35af_expected"
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

target_revision() {
    local action35af_revision_file=$evidence_root/target-revision

    regular_file "$action35af_revision_file"
    local action35af_revision
    action35af_revision=$(<"$action35af_revision_file")
    [[ "$action35af_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    printf '%s\n' "$action35af_revision"
}

accepted_revision() {
    if regular_file "$evidence_root/target-revision"; then
        target_revision
    else
        printf '%s\n' "$serving_revision"
    fi
}

require_exact_directory_inventory() {
    local action35af_label=$1
    local action35af_root=$2
    local action35af_expected=$3
    local action35af_observed

    require "${action35af_label}_root_regular" test -d "$action35af_root" || return 1
    require "${action35af_label}_root_not_symlink" test ! -L "$action35af_root" || return 1
    if ! action35af_observed=$(find "$action35af_root" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | LC_ALL=C sort); then
        printf '%s_check_%s_inventory_read=false\n' "$prefix" "$action35af_label"
        return 1
    fi
    require_equal "${action35af_label}_inventory" "$action35af_expected" "$action35af_observed"
}

require_empty_or_absent_directory() {
    local action35af_label=$1
    local action35af_root=$2

    if [[ ! -e "$action35af_root" && ! -L "$action35af_root" ]]; then
        require_equal "${action35af_label}_state" absent absent
        return 0
    fi
    require_exact_directory_inventory "$action35af_label" "$action35af_root" ''
}

quarantine_names() {
    printf '%s\n' \
        node-a-action17p-node-a-to-node-b-bootstrap \
        node-a-action33k-20260813T000701Z-2499021-node-a-reboot-normalized \
        node_b-outbound-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29-action30c \
        node_b-outbound-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4-action30c
}

node_a_quarantine_contract() {
    if [[ -n "${ACTION35AF_NODE_A_QUARANTINE_CONTRACT:-}" ]]; then
        [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]
        regular_file "$ACTION35AF_NODE_A_QUARANTINE_CONTRACT"
        cat "$ACTION35AF_NODE_A_QUARANTINE_CONTRACT"
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
    local action35af_inventory_root=$1
    local action35af_label=$2
    local action35af_expected_metadata=caddy-sync:caddy-sync
    local action35af_expected_names action35af_observed_names
    local action35af_name action35af_name_label action35af_revision action35af_source
    local action35af_release_hash action35af_payload_hash action35af_candidate
    local action35af_allowed action35af_observed action35af_marker action35af_path

    require "${action35af_label}_root_regular" test -d "$action35af_inventory_root" || return 1
    require "${action35af_label}_root_not_symlink" test ! -L "$action35af_inventory_root" || return 1
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_expected_metadata=$(id -un):$(id -gn)
    fi
    require_equal "${action35af_label}_root_metadata" \
        "$action35af_expected_metadata:750" "$(stat -c '%U:%G:%a' "$action35af_inventory_root")"
    action35af_expected_names=$(mktemp /tmp/caddy-action35af-node-a-expected.XXXXXX)
    action35af_observed_names=$(mktemp /tmp/caddy-action35af-node-a-observed.XXXXXX)
    node_a_quarantine_contract | awk -F '\t' '{ print $1 }' | LC_ALL=C sort \
        >"$action35af_expected_names"
    find "$action35af_inventory_root" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort >"$action35af_observed_names"
    require "${action35af_label}_top_level_exact" cmp -s \
        "$action35af_expected_names" "$action35af_observed_names" || {
        rm -f -- "$action35af_expected_names" "$action35af_observed_names"
        return 1
    }
    rm -f -- "$action35af_expected_names" "$action35af_observed_names"

    while IFS=$'\t' read -r action35af_name action35af_revision action35af_source \
        action35af_release_hash action35af_payload_hash; do
        [[ "$action35af_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
        action35af_name_label=${action35af_name,,}
        action35af_name_label=${action35af_name_label//[^a-z0-9_]/_}
        action35af_candidate=$action35af_inventory_root/$action35af_name
        require "${action35af_label}_${action35af_name_label}_regular" \
            test -d "$action35af_candidate" || return 1
        require "${action35af_label}_${action35af_name_label}_not_symlink" \
            test ! -L "$action35af_candidate" || return 1
        require_equal "${action35af_label}_${action35af_name_label}_metadata" \
            "$action35af_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35af_candidate")"
        require "${action35af_label}_${action35af_name_label}_unsafe_types_absent" \
            test -z "$(find "$action35af_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
        require "${action35af_label}_${action35af_name_label}_hardlinks_absent" \
            test -z "$(find "$action35af_candidate" -type f -links +1 -print -quit)"
        while IFS= read -r -d '' action35af_path; do
            if [[ -d "$action35af_path" ]]; then
                require_equal "${action35af_label}_${action35af_name_label}_directory_metadata" \
                    "$action35af_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35af_path")" || return 1
            else
                require_equal "${action35af_label}_${action35af_name_label}_file_metadata" \
                    "$action35af_expected_metadata:440" "$(stat -c '%U:%G:%a' "$action35af_path")" || return 1
            fi
        done < <(find "$action35af_candidate" -mindepth 1 -print0)
        require_equal "${action35af_label}_${action35af_name_label}_release_identity" \
            "$action35af_release_hash" \
            "$(sha256sum "$action35af_candidate/release-manifest.json" | awk '{ print $1 }')"
        require_equal "${action35af_label}_${action35af_name_label}_payload_identity" \
            "$action35af_payload_hash" \
            "$(sha256sum "$action35af_candidate/manifest.sha256" | awk '{ print $1 }')"
        require_equal "${action35af_label}_${action35af_name_label}_revision" \
            "$action35af_revision" \
            "$(jq -r '.revision // empty' "$action35af_candidate/release-manifest.json")"
        require_equal "${action35af_label}_${action35af_name_label}_source" \
            "$action35af_source" \
            "$(jq -r '.source_node // empty' "$action35af_candidate/release-manifest.json")"
        # The awk program must not expand shell positional parameters.
        # shellcheck disable=SC2016
        require "${action35af_label}_${action35af_name_label}_manifest_paths_safe" \
            awk 'length($0) < 68 { exit 1 } { p = substr($0, 67); sub(/^  /, "", p); if (p == "" || p ~ /^\// || p == ".." || p ~ /^\.\.\// || p ~ /\/\.\.\// || p ~ /\/\.\.$/) exit 1 }' \
            "$action35af_candidate/manifest.sha256"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35af_label}_${action35af_name_label}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35af_candidate"
        action35af_allowed=$(mktemp /tmp/caddy-action35af-node-a-allowed.XXXXXX)
        action35af_observed=$(mktemp /tmp/caddy-action35af-node-a-files.XXXXXX)
        for action35af_marker in .finalize-request .complete; do
            if [[ -e "$action35af_candidate/$action35af_marker" ]]; then
                require "${action35af_label}_${action35af_name_label}_${action35af_marker#.}_empty" \
                    test ! -s "$action35af_candidate/$action35af_marker" || return 1
            fi
        done
        {
            printf '%s\n' ./manifest.sha256 ./release-manifest.json
            awk '{ print substr($0, 67) }' "$action35af_candidate/manifest.sha256"
            for action35af_marker in .finalize-request .complete; do
                if [[ -e "$action35af_candidate/$action35af_marker" ]]; then
                    printf './%s\n' "$action35af_marker"
                fi
            done
        } | LC_ALL=C sort -u >"$action35af_allowed"
        require "${action35af_label}_${action35af_name_label}_complete_pending_absent" \
            path_absent "$action35af_candidate/.complete.pending"
        (
            cd "$action35af_candidate"
            find . -type f -print | LC_ALL=C sort -u
        ) >"$action35af_observed"
        require "${action35af_label}_${action35af_name_label}_file_inventory_exact" \
            cmp -s "$action35af_allowed" "$action35af_observed" || {
            rm -f -- "$action35af_allowed" "$action35af_observed"
            return 1
        }
        rm -f -- "$action35af_allowed" "$action35af_observed"
    done < <(node_a_quarantine_contract)

    action35af_path=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35af_label}_current_reference_absent" test \
        "${action35af_path#"$action35af_inventory_root"/}" = "$action35af_path"
    action35af_path=''
    while IFS= read -r -d '' action35af_marker; do
        action35af_path=$(readlink -f "$action35af_marker" || :)
        [[ "${action35af_path#"$action35af_inventory_root"/}" = "$action35af_path" ]] || break
        action35af_path=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35af_label}_state_references_absent" test -z "$action35af_path"
}

validate_quarantine_inventory() {
    local action35af_inventory_root=$1
    local action35af_label=$2
    local action35af_manifest=${ACTION35AF_QUARANTINE_INVENTORY_MANIFEST:-$payload_root/manifests/action35af-node-b-quarantine.tsv}
    local action35af_expected_metadata=caddy-sync:caddy-sync:750
    local action35af_observed_file action35af_expected_file
    local action35af_path action35af_relative action35af_encoded action35af_type
    local action35af_metadata action35af_hash action35af_reference
    local action35af_name

    require "${action35af_label}_root_regular" test -d "$action35af_inventory_root" || return 1
    require "${action35af_label}_root_not_symlink" test ! -L "$action35af_inventory_root" || return 1
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_expected_metadata=$(id -un):$(id -gn):750
    fi
    require_equal "${action35af_label}_root_metadata" "$action35af_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35af_inventory_root")"
    require "${action35af_label}_manifest_regular" regular_file "$action35af_manifest"
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
        require_equal "${action35af_label}_manifest_identity" \
            2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
            "$(sha256sum "$action35af_manifest" | awk '{ print $1 }')"
    fi
    action35af_expected_file=$(mktemp /tmp/caddy-action35af-quarantine-expected.XXXXXX)
    action35af_observed_file=$(mktemp /tmp/caddy-action35af-quarantine-observed.XXXXXX)
    awk -F '\t' 'NR > 1 { print }' "$action35af_manifest" | LC_ALL=C sort \
        >"$action35af_expected_file"
    while IFS= read -r -d '' action35af_path; do
        action35af_relative=${action35af_path#"$action35af_inventory_root"/}
        [[ -n "$action35af_relative" && "$action35af_relative" != /* &&
            "$action35af_relative" != .. && "$action35af_relative" != ../* &&
            "$action35af_relative" != */../* && "$action35af_relative" != */.. ]]
        action35af_encoded=$(printf '%s' "$action35af_relative" | base64 -w 0)
        if [[ -d "$action35af_path" && ! -L "$action35af_path" ]]; then
            action35af_type=directory
            action35af_hash=-
        elif [[ -f "$action35af_path" && ! -L "$action35af_path" ]]; then
            if [[ -s "$action35af_path" ]]; then
                action35af_type='regular file'
            else
                action35af_type='regular empty file'
            fi
            action35af_hash=$(sha256sum "$action35af_path" | awk '{ print $1 }')
        else
            printf '%s_check_%s_unsafe_type=false\n' "$prefix" "$action35af_label"
            rm -f -- "$action35af_expected_file" "$action35af_observed_file"
            return 1
        fi
        action35af_metadata=$(stat -c '%U:%G:%a' "$action35af_path")
        printf '%s\t%s\t%s\t%s\n' "$action35af_encoded" "$action35af_type" \
            "$action35af_metadata" "$action35af_hash" >>"$action35af_observed_file"
    done < <(find "$action35af_inventory_root" -mindepth 1 -print0)
    LC_ALL=C sort -o "$action35af_observed_file" "$action35af_observed_file"
    require "${action35af_label}_exact" cmp -s \
        "$action35af_expected_file" "$action35af_observed_file" || {
        rm -f -- "$action35af_expected_file" "$action35af_observed_file"
        return 1
    }
    rm -f -- "$action35af_expected_file" "$action35af_observed_file"
    while IFS= read -r action35af_name; do
        require "${action35af_label}_${action35af_name//[-]/_}_release_manifest_json" \
            jq -e \
            'type == "object" and
             (.revision | type == "string" and length > 0) and
             (.parent_revision | type == "string" and length > 0) and
             (.source_node | type == "string" and (. == "node-a" or . == "node-b")) and
             (.created_at | type == "string" and length > 0)' \
            "$action35af_inventory_root/$action35af_name/release-manifest.json"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35af_label}_${action35af_name//[-]/_}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35af_inventory_root/$action35af_name"
    done < <(quarantine_names)
    action35af_reference=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35af_label}_current_reference_absent" test \
        "${action35af_reference#"$action35af_inventory_root"/}" = "$action35af_reference"
    action35af_reference=''
    while IFS= read -r -d '' action35af_path; do
        action35af_reference=$(readlink -f "$action35af_path" || :)
        [[ "${action35af_reference#"$action35af_inventory_root"/}" = "$action35af_reference" ]] || break
        action35af_reference=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35af_label}_state_references_absent" test -z "$action35af_reference"
}

validate_retained_node_b_entry() {
    local action35af_candidate=$incoming_root/node-a/$retained_name
    local action35af_allowed
    local action35af_expected_metadata=caddy-sync:caddy-sync:500
    local action35af_observed

    [[ "$node_role" = node-b ]]
    require retained_inventory_exact require_exact_directory_inventory \
        retained_incoming_node_a "$incoming_root/node-a" "$retained_name"
    require retained_candidate_regular test -d "$action35af_candidate"
    require retained_candidate_not_symlink test ! -L "$action35af_candidate"
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_expected_metadata=$(id -un):$(id -gn):500
    fi
    require_equal retained_candidate_metadata "$action35af_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35af_candidate")"
    require retained_release_manifest_regular regular_file \
        "$action35af_candidate/release-manifest.json"
    require retained_payload_manifest_regular regular_file \
        "$action35af_candidate/manifest.sha256"
    require_equal retained_release_manifest_identity \
        "$retained_release_manifest_sha256" \
        "$(sha256sum "$action35af_candidate/release-manifest.json" | awk '{ print $1 }')"
    require_equal retained_payload_manifest_identity \
        "$retained_payload_manifest_sha256" \
        "$(sha256sum "$action35af_candidate/manifest.sha256" | awk '{ print $1 }')"
    require_equal retained_revision "$retained_name" \
        "$(jq -r '.revision // empty' "$action35af_candidate/release-manifest.json")"
    require_equal retained_source node-a \
        "$(jq -r '.source_node // empty' "$action35af_candidate/release-manifest.json")"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require retained_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35af_candidate"
    require retained_unsafe_types_absent test -z \
        "$(find "$action35af_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
    require retained_finalize_request_absent path_absent \
        "$action35af_candidate/.finalize-request"
    require retained_complete_absent path_absent "$action35af_candidate/.complete"
    require retained_complete_pending_absent path_absent \
        "$action35af_candidate/.complete.pending"
    action35af_allowed=$(mktemp /tmp/caddy-action35af-retained-allowed.XXXXXX)
    action35af_observed=$(mktemp /tmp/caddy-action35af-retained-observed.XXXXXX)
    {
        printf '%s\n' manifest.sha256 release-manifest.json
        awk '{ print $2 }' "$action35af_candidate/manifest.sha256"
    } | sed 's#^\./##' | LC_ALL=C sort -u >"$action35af_allowed"
    find "$action35af_candidate" -mindepth 1 -type f -printf '%P\n' |
        LC_ALL=C sort -u >"$action35af_observed"
    require retained_file_inventory_exact cmp -s "$action35af_allowed" "$action35af_observed"
    rm -f -- "$action35af_allowed" "$action35af_observed"
}

disposition_retained_node_b_entry() {
    local action35af_candidate=$incoming_root/node-a/$retained_name
    local action35af_backup=$evidence_root/retained-incoming
    local action35af_quarantine_backup=$evidence_root/quarantine-disposition
    local action35af_status=0

    [[ "$node_role" = node-b ]]
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    require retained_backup_absent test ! -e "$action35af_backup"
    require quarantine_backup_absent test ! -e "$action35af_quarantine_backup"
    require_equal quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35af_status=125
    if [[ "$action35af_status" -eq 0 ]]; then
        if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            chmod 0700 "$action35af_candidate"
        fi
        mv -- "$action35af_candidate" "$action35af_backup" || action35af_status=$?
    fi
    if [[ "$action35af_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35af_quarantine_backup" || action35af_status=$?
    fi
    if [[ "$action35af_status" -eq 0 ]]; then
        if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35af_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35af_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35af_status=125
    [[ "$action35af_status" -eq 0 ]] || return "$action35af_status"
    require retained_candidate_dispositioned test ! -e "$action35af_candidate"
    require incoming_node_a_inventory_empty require_exact_directory_inventory \
        incoming_node_a_after_disposition "$incoming_root/node-a" ''
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine_after_disposition "$quarantine_root" ''
}

restore_retained_node_b_entry() {
    local action35af_candidate=$incoming_root/node-a/$retained_name
    local action35af_backup=$evidence_root/retained-incoming
    local action35af_quarantine_backup=$evidence_root/quarantine-disposition
    local action35af_status=0

    [[ "$node_role" = node-b ]]
    if [[ -n "$target_root" && ! -d "$action35af_backup" ]]; then
        return 0
    fi
    if [[ -d "$action35af_backup" && ! -L "$action35af_backup" ]]; then
        require retained_restore_target_absent test ! -e "$action35af_candidate"
        "$systemctl_command" stop caddy-sync-reconcile.path || action35af_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35af_status=125
        if [[ "$action35af_status" -eq 0 ]]; then
            mv -- "$action35af_backup" "$action35af_candidate" || action35af_status=$?
            if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
                chmod 0500 "$action35af_candidate"
            fi
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35af_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35af_status=125
    fi
    if [[ -d "$action35af_quarantine_backup" && ! -L "$action35af_quarantine_backup" ]]; then
        validate_quarantine_inventory "$action35af_quarantine_backup" quarantine_restore_source
        if [[ -e "$quarantine_root" || -L "$quarantine_root" ]]; then
            require quarantine_restore_target_empty require_exact_directory_inventory \
                quarantine_restore_target "$quarantine_root" ''
        else
            require quarantine_restore_target_absent path_absent "$quarantine_root"
        fi
        "$systemctl_command" stop caddy-sync-reconcile.path || action35af_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35af_status=125
        if [[ "$action35af_status" -eq 0 ]]; then
            if [[ -d "$quarantine_root" ]]; then
                rmdir "$quarantine_root" || action35af_status=$?
            fi
        fi
        if [[ "$action35af_status" -eq 0 ]]; then
            mv -- "$action35af_quarantine_backup" "$quarantine_root" || action35af_status=$?
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35af_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35af_status=125
    fi
    [[ "$action35af_status" -eq 0 ]] || return "$action35af_status"
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_restored
}

disposition_node_a_quarantine() {
    local action35af_backup=$evidence_root/node-a-quarantine-disposition
    local action35af_status=0

    [[ "$node_role" = node-a ]]
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_baseline
    require node_a_quarantine_backup_absent test ! -e "$action35af_backup"
    require_equal node_a_quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35af_status=125
    if [[ "$action35af_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35af_backup" || action35af_status=$?
    fi
    if [[ "$action35af_status" -eq 0 ]]; then
        if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35af_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35af_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35af_status=125
    [[ "$action35af_status" -eq 0 ]] || return "$action35af_status"
    require node_a_quarantine_inventory_empty require_exact_directory_inventory \
        node_a_quarantine_after_disposition "$quarantine_root" ''
}

restore_node_a_quarantine() {
    local action35af_backup=$evidence_root/node-a-quarantine-disposition
    local action35af_status=0

    [[ "$node_role" = node-a ]]
    if [[ ! -e "$action35af_backup" && ! -L "$action35af_backup" ]]; then
        return 0
    fi
    require node_a_quarantine_restore_source_regular test -d "$action35af_backup"
    require node_a_quarantine_restore_source_not_symlink test ! -L "$action35af_backup"
    validate_node_a_quarantine_inventory "$action35af_backup" node_a_quarantine_restore_source
    require node_a_quarantine_restore_target_empty require_exact_directory_inventory \
        node_a_quarantine_restore_target "$quarantine_root" ''
    "$systemctl_command" stop caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35af_status=125
    if [[ "$action35af_status" -eq 0 ]]; then
        rmdir "$quarantine_root" || action35af_status=$?
    fi
    if [[ "$action35af_status" -eq 0 ]]; then
        mv -- "$action35af_backup" "$quarantine_root" || action35af_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35af_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35af_status=125
    [[ "$action35af_status" -eq 0 ]] || return "$action35af_status"
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_restored
}

validate_outbound_candidate() {
    local action35af_candidate=$outgoing_root/$serving_revision
    local action35af_manifest_hash

    require outbound_candidate_regular test -d "$action35af_candidate"
    require outbound_candidate_not_symlink test ! -L "$action35af_candidate"
    require outbound_candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action35af_candidate")" = "$sync_user:$sync_group:550"
    require outbound_revision test \
        "$(jq -r '.revision // empty' "$action35af_candidate/release-manifest.json")" = "$serving_revision"
    require outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$action35af_candidate/release-manifest.json")" = "$serving_parent"
    require outbound_source test \
        "$(jq -r '.source_node // empty' "$action35af_candidate/release-manifest.json")" = node-a
    action35af_manifest_hash=$(sha256sum "$action35af_candidate/manifest.sha256" | awk '{ print $1 }')
    require outbound_payload_manifest_hash test \
        "$action35af_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require outbound_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35af_candidate"
    require outbound_finalize_marker_regular test -f "$action35af_candidate/.finalize-request"
    require outbound_finalize_marker_empty test ! -s "$action35af_candidate/.finalize-request"
    require outbound_symlinks_absent test -z \
        "$(find "$action35af_candidate" -type l -print -quit)"
}

validate_installed_release() {
    local action35af_release=$releases_root/$serving_revision
    local action35af_manifest_hash
    local action35af_expected_metadata=root:caddy-tls:550

    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_expected_metadata=$(id -un):$(id -gn):550
    fi

    require installed_release_regular test -d "$action35af_release"
    require installed_release_not_symlink test ! -L "$action35af_release"
    require installed_release_metadata test \
        "$(stat -c '%U:%G:%a' "$action35af_release")" = "$action35af_expected_metadata"
    require installed_release_revision test \
        "$(jq -r '.revision // empty' "$action35af_release/release-manifest.json")" = "$serving_revision"
    require installed_release_parent test \
        "$(jq -r '.parent_revision // empty' "$action35af_release/release-manifest.json")" = "$serving_parent"
    require installed_release_source test \
        "$(jq -r '.source_node // empty' "$action35af_release/release-manifest.json")" = node-a
    action35af_manifest_hash=$(sha256sum "$action35af_release/manifest.sha256" | awk '{ print $1 }')
    require installed_payload_manifest_hash test \
        "$action35af_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require installed_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35af_release"
}

validate_inventory() {
    local action35af_inventory=$payload_root/manifests/production-artifacts.tsv
    local action35af_key action35af_repository action35af_source action35af_target
    local action35af_inventory_node action35af_source_hash action35af_deployed_hash
    local action35af_accepted action35af_lifecycle action35af_observed

    regular_file "$action35af_inventory"
    while IFS=$'\t' read -r action35af_key action35af_repository action35af_source \
        action35af_target action35af_inventory_node action35af_source_hash \
        action35af_deployed_hash action35af_accepted action35af_lifecycle; do
        [[ "$action35af_key" = '# key' ]] && continue
        [[ "$action35af_inventory_node" = "$node_role" ||
            "$action35af_inventory_node" = both ]] || continue
        [[ -n "$action35af_accepted" && "$action35af_lifecycle" = production-current ]]
        require "artifact_${action35af_key}_regular" regular_file "$action35af_target"
        action35af_observed=$(sha256sum "$action35af_target" | awk '{ print $1 }')
        require_equal "artifact_${action35af_key}_identity" \
            "$action35af_deployed_hash" "$action35af_observed"
    done <"$action35af_inventory"
}

validate_legacy_lighttpd_helper() {
    local action35af_path
    local action35af_expected_metadata=root:root:755

    action35af_path=$(effective_path "$legacy_lighttpd_helper")
    if [[ "$node_role" = node-a ]]; then
        require_equal legacy_lighttpd_helper_state absent \
            "$(if path_absent "$action35af_path"; then printf absent; else printf present; fi)"
        return
    fi
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_expected_metadata=$(id -un):$(id -gn):755
    fi
    require legacy_lighttpd_helper_regular regular_file "$action35af_path"
    require_equal legacy_lighttpd_helper_metadata "$action35af_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35af_path")"
    require_equal legacy_lighttpd_helper_identity "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35af_path" | awk '{ print $1 }')"
}

remove_legacy_lighttpd_helper() {
    local action35af_path

    [[ "$node_role" = node-b ]]
    validate_legacy_lighttpd_helper
    action35af_path=$(effective_path "$legacy_lighttpd_helper")
    backup_target "$legacy_lighttpd_helper"
    rm -f -- "$action35af_path"
    require legacy_lighttpd_helper_removed path_absent "$action35af_path"
}

restore_legacy_lighttpd_helper() {
    [[ "$node_role" = node-b ]]
    restore_target "$legacy_lighttpd_helper"
    validate_legacy_lighttpd_helper
}

validate_services() {
    local action35af_unit

    for action35af_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35af_unit//[.@-]/_}_active" \
            "$systemctl_command" is-active --quiet "$action35af_unit"
    done
    for action35af_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35af_unit//[.@-]/_}_enabled" \
            "$systemctl_command" is-enabled --quiet "$action35af_unit"
    done
    require caddy_api_masked test "$($systemctl_command is-enabled caddy-api.service)" = masked
    require distribution_lsyncd_masked test "$($systemctl_command is-enabled lsyncd.service)" = masked
}

validate_split_baseline() {
    local action35af_expected_revision

    action35af_expected_revision=$(expected_release)
    require_equal current_release_expected "$action35af_expected_revision" "$(current_revision)"
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
    local action35af_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35af_repository action35af_source action35af_target action35af_mode
    local action35af_expected_hash action35af_lifecycle action35af_file action35af_observed

    require payload_root safe_root "$payload_root"
    require payload_manifest regular_file "$action35af_manifest"
    require quarantine_inventory_manifest regular_file \
        "$payload_root/manifests/action35af-node-b-quarantine.tsv"
    require_equal quarantine_inventory_manifest_identity \
        2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
        "$(sha256sum "$payload_root/manifests/action35af-node-b-quarantine.tsv" | awk '{ print $1 }')"
    while IFS=$'\t' read -r action35af_repository action35af_source action35af_target \
        action35af_mode action35af_expected_hash action35af_lifecycle; do
        [[ "$action35af_repository" = '# repository' ]] && continue
        action35af_file=$payload_root/repositories/$action35af_repository/$action35af_source
        require "payload_${action35af_expected_hash}_regular" regular_file "$action35af_file"
        action35af_observed=$(sha256sum "$action35af_file" | awk '{ print $1 }')
        require "payload_${action35af_expected_hash}_identity" test \
            "$action35af_observed" = "$action35af_expected_hash"
    done <"$action35af_manifest"
}

validate_installed_candidate_inventory() {
    local action35af_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35af_repository action35af_source action35af_target action35af_mode
    local action35af_expected_hash action35af_lifecycle action35af_observed

    while IFS=$'\t' read -r action35af_repository action35af_source action35af_target \
        action35af_mode action35af_expected_hash action35af_lifecycle; do
        [[ "$action35af_repository" = '# repository' ]] && continue
        [[ "$action35af_lifecycle" = production-candidate ]]
        case "$action35af_target" in
            /etc/caddy/releases/REVISION/*) continue ;;
        esac
        if [[ "$action35af_source" = Keepalived/configs/keepalived-pihole0.conf &&
            "$node_role" != node-a ]]; then
            continue
        fi
        if [[ "$action35af_source" = Keepalived/configs/keepalived-pihole00.conf &&
            "$node_role" != node-b ]]; then
            continue
        fi
        require "candidate_${action35af_expected_hash}_regular" regular_file "$action35af_target"
        require "candidate_${action35af_expected_hash}_mode" test \
            "$(stat -c '%a' "$action35af_target")" = "${action35af_mode#0}"
        require "candidate_${action35af_expected_hash}_owner" test \
            "$(stat -c '%U:%G' "$action35af_target")" = root:root
        action35af_observed=$(sha256sum "$action35af_target" | awk '{ print $1 }')
        require "candidate_${action35af_expected_hash}_identity" test \
            "$action35af_observed" = "$action35af_expected_hash"
    done <"$action35af_manifest"
}

candidate_file() {
    local action35af_repository=$1
    local action35af_source=$2
    printf '%s/repositories/%s/%s\n' "$payload_root" "$action35af_repository" "$action35af_source"
}

backup_path() {
    local action35af_target=$1
    printf '%s/backups/%s\n' "$evidence_root" "${action35af_target#/}"
}

backup_target() {
    local action35af_target=$1
    local action35af_backup
    local action35af_effective_target

    action35af_backup=$(backup_path "$action35af_target")
    action35af_effective_target=$(effective_path "$action35af_target")
    install -d -m 0700 "$(dirname -- "$action35af_backup")"
    if [[ -e "$action35af_effective_target" || -L "$action35af_effective_target" ]]; then
        cp -a -- "$action35af_effective_target" "$action35af_backup"
        printf 'present\n' >"$action35af_backup.state"
    else
        printf 'absent\n' >"$action35af_backup.state"
    fi
}

install_target() {
    local action35af_source=$1
    local action35af_target=$2
    local action35af_mode=$3
    local action35af_owner=$4
    local action35af_group=$5
    local action35af_effective_target

    action35af_effective_target=$(effective_path "$action35af_target")
    if [[ "${ACTION35AF_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35af_owner=$(id -un)
        action35af_group=$(id -gn)
    fi

    backup_target "$action35af_target"
    install -d -m 0755 "$(dirname -- "$action35af_effective_target")"
    install -o "$action35af_owner" -g "$action35af_group" -m "$action35af_mode" \
        "$action35af_source" "$action35af_effective_target"
}

restore_target() {
    local action35af_target=$1
    local action35af_backup
    local action35af_state
    local action35af_effective_target

    action35af_backup=$(backup_path "$action35af_target")
    action35af_effective_target=$(effective_path "$action35af_target")
    [[ -f "$action35af_backup.state" && ! -L "$action35af_backup.state" ]] || return 0
    action35af_state=$(<"$action35af_backup.state")
    case "$action35af_state" in
        present)
            rm -f -- "$action35af_effective_target"
            cp -a -- "$action35af_backup" "$action35af_effective_target"
            ;;
        absent) rm -f -- "$action35af_effective_target" ;;
        *) return 1 ;;
    esac
}

install_serving_artifacts() {
    local action35af_keepalived_source

    "$systemctl_command" stop keepalived.service
    if "$systemctl_command" is-active --quiet keepalived.service; then
        require keepalived_stopped_before_helper_replacement false
    fi
    require keepalived_stopped_before_helper_replacement true

    if [[ "$node_role" = node-a ]]; then
        action35af_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35af_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
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
    install_target "$(candidate_file homelab-server-configs Caddy/scripts/lsyncd-sync-failure-notify.sh)" \
        /usr/local/libexec/lsyncd-sync-failure-notify.sh 0755 root root
    install_target "$(candidate_file homelab-dns Keepalived/scripts/keepalived-notify.sh)" \
        /usr/local/bin/keepalived-notify.sh 0755 root root
    install_target "$(candidate_file homelab-server-configs Caddy/configs/tmpfiles.d/caddy-ha.conf)" \
        /etc/tmpfiles.d/caddy-ha.conf 0644 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.service)" \
        /etc/systemd/system/caddy-pihole-web-health.service 0644 root root
    install_target "$(candidate_file homelab-server-configs Caddy/systemd/caddy-pihole-web-health.timer)" \
        /etc/systemd/system/caddy-pihole-web-health.timer 0644 root root
    install_target "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        /etc/scripts/check-dns.sh 0755 root root
    install_target "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)" \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf 0644 root root
    install_target "$(candidate_file homelab-dns "$action35af_keepalived_source")" \
        /etc/keepalived/keepalived.conf 0644 root root
    if [[ -n "$target_root" ]]; then
        "$unbound_checkconf_command" \
            "$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)"
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf
    fi
    "$systemctl_command" daemon-reload
    disposition_obsolete_status_directories
    "$systemd_tmpfiles_command" --create \
        "$(effective_path /etc/tmpfiles.d/caddy-ha.conf)"
    "$systemctl_command" enable --now caddy-pihole-web-health.timer
    "$systemctl_command" reload unbound.service
    capture_keepalived_activation_cursor
    "$systemctl_command" start keepalived.service
    daemon_serving_health_acceptance
}

disposition_obsolete_status_directories() {
    local action35af_name action35af_directory action35af_status_path
    local action35af_backup action35af_expected_metadata action35af_observed_metadata

    : >"$evidence_root/obsolete-status-disposition.tsv"
    for action35af_name in dns proxy; do
        action35af_directory=$(effective_path "/run/caddy-serving-health/$action35af_name")
        action35af_backup=$evidence_root/obsolete-status-$action35af_name
        require "obsolete_status_${action35af_name}_backup_absent" \
            path_absent "$action35af_backup"
        if path_absent "$action35af_directory"; then
            printf '%s\tabsent\n' "$action35af_name" \
                >>"$evidence_root/obsolete-status-disposition.tsv"
            continue
        fi
        require "obsolete_status_${action35af_name}_regular_directory" \
            test -d "$action35af_directory"
        require "obsolete_status_${action35af_name}_not_symlink" \
            test ! -L "$action35af_directory"
        require_exact_directory_inventory "obsolete_status_${action35af_name}" \
            "$action35af_directory" status
        action35af_status_path=$action35af_directory/status
        require "obsolete_status_${action35af_name}_record_regular" \
            regular_file "$action35af_status_path"
        require "obsolete_status_${action35af_name}_record_bounded" \
            test "$(stat -c '%s' "$action35af_status_path")" -le 4096
        require "obsolete_status_${action35af_name}_record_schema" \
            grep -Fxq 'schema=caddy-serving-health-status/v1' "$action35af_status_path"
        action35af_expected_metadata=pi:pi:755
        [[ "$action35af_name" = dns ]] ||
            action35af_expected_metadata=keepalived_script:keepalived_script:755
        if [[ -z "$target_root" ]]; then
            action35af_observed_metadata=$(stat -c '%U:%G:%a' "$action35af_directory")
            require_equal "obsolete_status_${action35af_name}_metadata" \
                "$action35af_expected_metadata" "$action35af_observed_metadata"
        fi
        require_equal "obsolete_status_${action35af_name}_same_filesystem" \
            "$(stat -c '%d' "$action35af_directory")" "$(stat -c '%d' "$evidence_root")"
        mv -- "$action35af_directory" "$action35af_backup"
        printf '%s\tdispositioned\t%s\n' "$action35af_name" \
            "$(sha256sum "$action35af_backup/status" | awk '{ print $1 }')" \
            >>"$evidence_root/obsolete-status-disposition.tsv"
    done
    chmod 0600 "$evidence_root/obsolete-status-disposition.tsv"
}

restore_obsolete_status_directories() {
    local action35af_name action35af_directory action35af_backup

    for action35af_name in dns proxy; do
        action35af_directory=$(effective_path "/run/caddy-serving-health/$action35af_name")
        action35af_backup=$evidence_root/obsolete-status-$action35af_name
        if [[ -d "$action35af_backup" && ! -L "$action35af_backup" ]]; then
            require "obsolete_status_${action35af_name}_restore_target_absent" \
                path_absent "$action35af_directory"
            mv -- "$action35af_backup" "$action35af_directory"
        fi
    done
}

capture_keepalived_activation_cursor() {
    local action35af_cursor

    capture_command keepalived_activation_cursor_raw "$journalctl_command" \
        --quiet --no-pager -n 0 --show-cursor
    action35af_cursor=$(sed -n 's/^-- cursor: //p' \
        "$evidence_root/keepalived_activation_cursor_raw.stdout")
    require keepalived_activation_cursor_exact test -n "$action35af_cursor"
    printf '%s\n' "$action35af_cursor" >"$evidence_root/keepalived-activation.cursor"
    chmod 0600 "$evidence_root/keepalived-activation.cursor"
}

daemon_serving_health_acceptance() {
    local action35af_attempt action35af_cursor

    [[ "$daemon_observation_attempts" =~ ^([1-9][0-9]|[2-9][0-9]+)$ ]]
    [[ "$daemon_observation_delay" =~ ^[1-9][0-9]*$ ]]
    for ((action35af_attempt = 1; action35af_attempt <= daemon_observation_attempts; action35af_attempt++)); do
        "$sleep_command" "$daemon_observation_delay"
    done

    action35af_cursor=$(<"$evidence_root/keepalived-activation.cursor")
    capture_command keepalived_daemon_journal "$journalctl_command" --no-pager \
        -o short-iso-precise --after-cursor "$action35af_cursor" \
        -u keepalived.service
    require keepalived_daemon_journal_vrrp grep -Fq Keepalived_vrrp \
        "$evidence_root/keepalived_daemon_journal.stdout"
    require keepalived_daemon_journal_activation grep -Eq \
        'Starting|Started|Reloading|Reload complete' \
        "$evidence_root/keepalived_daemon_journal.stdout"
    require keepalived_daemon_dns_success grep -Eq \
        'VRRP_Script\(check-dns\) (considered successful|succeeded)' \
        "$evidence_root/keepalived_daemon_journal.stdout"
    require keepalived_daemon_proxy_success grep -Eq \
        'VRRP_Script\(check-caddy\) (considered successful|succeeded)' \
        "$evidence_root/keepalived_daemon_journal.stdout"
    if grep -Eiq \
        'returning [1-9]|VRRP_Script\([^)]*\) failed|timed out|terminated by signal' \
        "$evidence_root/keepalived_daemon_journal.stdout"; then
        require keepalived_daemon_journal_no_failure false
    fi
    require keepalived_daemon_journal_no_failure true
    require keepalived_daemon_active "$systemctl_command" is-active --quiet keepalived.service
}

parser_and_identity_checks() {
    local action35af_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        action35af_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35af_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    capture_command unbound_local_zone_parser "$unbound_checkconf_command" \
        "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)"
    capture_stdin_command dns_identity \
        "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        "$runuser_command" -u pi -- env \
        DNS_CHECK_DIG_COMMAND="${ACTION35AF_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        DNS_CHECK_SYSTEMCTL_COMMAND="${ACTION35AF_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
    capture_stdin_command caddy_identity \
        "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        "$runuser_command" -u keepalived_script -g caddy-tls -- env \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$node_environment" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="${ACTION35AF_CURL_COMMAND:-/usr/bin/curl}" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="${ACTION35AF_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
}

promote_local_candidate() {
    local action35af_source=$outgoing_root/$serving_revision
    local action35af_destination=$incoming_root/node-a/$serving_revision

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    require local_incoming_absent test ! -e "$action35af_destination"
    local action35af_promotion_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$action35af_source" "$action35af_destination" &&
        chown -R "$sync_user:$sync_group" "$action35af_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require local_candidate_selected test "$(current_revision)" = "$serving_revision"; then
        :
    else
        action35af_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35af_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35af_promotion_status=125
    return "$action35af_promotion_status"
}

publish_current_release() {
    local action35af_source=$evidence_root/new-release-source
    local action35af_before=$evidence_root/outbound-before-publish
    local action35af_after=$evidence_root/outbound-after-publish
    local action35af_revision

    [[ "$node_role" = node-a ]]
    require_equal publish_parent_release "$serving_revision" "$(current_revision)"
    require outbound_empty_before_publish require_exact_directory_inventory \
        outbound_before_publish "$outgoing_root" ''
    require new_release_source_absent path_absent "$action35af_source"
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
        LC_ALL=C sort >"$action35af_before"
    install -d -m 0700 "$action35af_source"
    cp -a -- "$(effective_path /etc/caddy/current)/." "$action35af_source/"
    find "$action35af_source" -type d -exec chmod u+rwx {} +
    find "$action35af_source" -type f -exec chmod u+rw {} +
    rm -f -- "$action35af_source/.complete" \
        "$action35af_source/.complete.pending" \
        "$action35af_source/.finalize-request" \
        "$action35af_source/manifest.sha256" \
        "$action35af_source/release-manifest.json"
    require publish_source_conf_directory test -d "$action35af_source/conf.d"
    install -m 0640 \
        "$(candidate_file homelab-server-configs Caddy/configs/caddy/conf.d/10-pihole-admin.caddy)" \
        "$action35af_source/conf.d/10-pihole-admin.caddy"
    capture_command publish_release "$publisher_command" --source "$action35af_source" \
        --node-role node-a
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
        LC_ALL=C sort >"$action35af_after"
    action35af_revision=$(comm -13 "$action35af_before" "$action35af_after")
    require target_revision_single test "$(wc -l <<<"$action35af_revision")" -eq 1
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require target_revision_shape /bin/bash -c \
        '[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]' _ "$action35af_revision"
    require target_revision_reported grep -Fxq \
        "Published protocol-v2 release $action35af_revision for receiver validation." \
        "$evidence_root/publish_release.stdout"
    printf '%s\n' "$action35af_revision" >"$evidence_root/target-revision"
    chmod 0600 "$evidence_root/target-revision"
    require target_candidate_parent test \
        "$(jq -r '.parent_revision // empty' "$outgoing_root/$action35af_revision/release-manifest.json")" = \
        "$serving_revision"
    require target_candidate_source test \
        "$(jq -r '.source_node // empty' "$outgoing_root/$action35af_revision/release-manifest.json")" = \
        node-a
    require target_candidate_caddy_payload test \
        "$(sha256sum "$outgoing_root/$action35af_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
    rm -rf -- "$action35af_source"
    printf 'Published protocol-v2 release %s for receiver validation.\n' \
        "$action35af_revision"
}

record_target_revision() {
    local action35af_revision=${target_revision_argument:-}

    [[ "$action35af_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    require target_revision_absent path_absent "$evidence_root/target-revision"
    printf '%s\n' "$action35af_revision" >"$evidence_root/target-revision"
    chmod 0600 "$evidence_root/target-revision"
}

wait_for_target_release() {
    local action35af_revision action35af_attempt

    [[ "$node_role" = node-b ]]
    action35af_revision=$(target_revision)
    for ((action35af_attempt = 1; action35af_attempt <= 60; action35af_attempt++)); do
        if [[ "$(current_revision)" = "$action35af_revision" ]]; then
            break
        fi
        "$sleep_command" 1
    done
    require_equal target_release_selected "$action35af_revision" "$(current_revision)"
    require target_release_regular test -d "$releases_root/$action35af_revision"
    require target_release_not_symlink test ! -L "$releases_root/$action35af_revision"
    require target_release_caddy_payload test \
        "$(sha256sum "$releases_root/$action35af_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
}

promote_target_candidate() {
    local action35af_revision action35af_source action35af_destination
    local action35af_promotion_status=0

    [[ "$node_role" = node-a ]]
    action35af_revision=$(target_revision)
    action35af_source=$outgoing_root/$action35af_revision
    action35af_destination=$incoming_root/node-a/$action35af_revision
    require target_outbound_regular test -d "$action35af_source"
    require target_outbound_not_symlink test ! -L "$action35af_source"
    require target_outbound_revision test \
        "$(jq -r '.revision // empty' "$action35af_source/release-manifest.json")" = \
        "$action35af_revision"
    require target_outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$action35af_source/release-manifest.json")" = \
        "$serving_revision"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require target_outbound_manifest_valid /bin/bash -c \
        'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35af_source"
    require target_local_incoming_absent path_absent "$action35af_destination"
    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$action35af_source" "$action35af_destination" &&
        chown -R "$sync_user:$sync_group" "$action35af_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require_equal target_local_selected "$action35af_revision" "$(current_revision)"; then
        :
    else
        action35af_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35af_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35af_promotion_status=125
    return "$action35af_promotion_status"
}

accept_installed_node() {
    local action35af_keepalived_hash action35af_dns_hash action35af_caddy_hash
    local action35af_service_hash action35af_timer_hash action35af_local_zone_hash
    local action35af_enqueue_hash action35af_sync_notifier_hash
    local action35af_keepalived_notifier_hash action35af_tmpfiles_hash

    action35af_keepalived_hash=$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')
    action35af_dns_hash=$(sha256sum /etc/scripts/check-dns.sh | awk '{ print $1 }')
    action35af_caddy_hash=$(sha256sum /usr/local/libexec/check-caddy.sh | awk '{ print $1 }')
    action35af_service_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.service | awk '{ print $1 }')
    action35af_timer_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.timer | awk '{ print $1 }')
    action35af_local_zone_hash=$(sha256sum /etc/unbound/unbound.conf.d/pihole-local-zone.conf | awk '{ print $1 }')
    action35af_enqueue_hash=$(sha256sum /usr/local/libexec/caddy-apprise-enqueue | awk '{ print $1 }')
    action35af_sync_notifier_hash=$(sha256sum /usr/local/libexec/lsyncd-sync-failure-notify.sh | awk '{ print $1 }')
    action35af_keepalived_notifier_hash=$(sha256sum /usr/local/bin/keepalived-notify.sh | awk '{ print $1 }')
    action35af_tmpfiles_hash=$(sha256sum /etc/tmpfiles.d/caddy-ha.conf | awk '{ print $1 }')
    if [[ "$node_role" = node-a ]]; then
        require keepalived_candidate_hash test "$action35af_keepalived_hash" = \
            de67123685edb21cdfaee95eb0497d9ab527c546cf730a5f51506bc293eab92a
    else
        require keepalived_candidate_hash test "$action35af_keepalived_hash" = \
            cb4749c6f9e1a247dc481809652470e5b35c5ea3992e87945bada9292f5cbd66
    fi
    require dns_candidate_hash test "$action35af_dns_hash" = \
        10bbabead80305d57e8be420d521ff28883e5dbdbb81d4d4e680c05cd6848279
    require caddy_candidate_hash test "$action35af_caddy_hash" = \
        60c2c196e75a17452d16174b08f9ba20d63699b2931a7ccf69779e55b96ddc32
    require web_service_hash test "$action35af_service_hash" = \
        a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0
    require web_timer_hash test "$action35af_timer_hash" = \
        f214b69fecaeb322dbaba61f683f9cf35970596784adcd707e25278f0ace1505
    require unbound_local_zone_hash test "$action35af_local_zone_hash" = \
        f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d
    require enqueue_candidate_hash test "$action35af_enqueue_hash" = \
        5101792e178ede8f6ae4cae23f9d22d57bd4c453c3578dc164175a57fe4dc56f
    require sync_notifier_candidate_hash test "$action35af_sync_notifier_hash" = \
        278e0ff1695feca3806f24cf74c6e4007723e0b8ddbb086aaf1e121d7e9c183c
    require keepalived_notifier_candidate_hash test "$action35af_keepalived_notifier_hash" = \
        ffaf6d7e09b808dd71848ca481da01e144c715a305858d2922accedaecb5aabf
    require tmpfiles_candidate_hash test "$action35af_tmpfiles_hash" = \
        21bc21a73056f7eb8abd549e9315c640522e32b28b4d0989ca43ba57a82da98b
    require serving_health_root_metadata test \
        "$(stat -c '%U:%G:%a' /run/caddy-serving-health)" = root:root:755
    require obsolete_dns_status_absent path_absent /run/caddy-serving-health/dns
    require obsolete_proxy_status_absent path_absent /run/caddy-serving-health/proxy
    require web_timer_enabled "$systemctl_command" is-enabled --quiet caddy-pihole-web-health.timer
    require web_timer_active "$systemctl_command" is-active --quiet caddy-pihole-web-health.timer
    require web_worker_static test \
        "$($systemctl_command is-enabled caddy-pihole-web-health.service)" = static
    require selected_release test "$(current_revision)" = "$(accepted_revision)"
    if regular_file "$evidence_root/target-revision"; then
        require active_caddy_payload test \
            "$(sha256sum "$(effective_path /etc/caddy/current/conf.d/10-pihole-admin.caddy)" | awk '{ print $1 }')" = \
            8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
    fi
    validate_installed_candidate_inventory
    validate_services
}

validate_final_residue() {
    local action35af_revision

    action35af_revision=$(target_revision)
    require selected_release test "$(current_revision)" = "$action35af_revision"
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
    require final_target_release_regular test -d "$releases_root/$action35af_revision"
    require final_target_release_not_symlink test ! -L "$releases_root/$action35af_revision"
    require final_target_caddy_payload test \
        "$(sha256sum "$releases_root/$action35af_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
}

rollback_node() {
    local action35af_target
    local action35af_release_source
    local action35af_new_revision=
    local action35af_restore_failed=0

    "$systemctl_command" stop keepalived.service || action35af_restore_failed=1

    if [[ "$node_role" = node-b ]]; then
        restore_retained_node_b_entry || action35af_restore_failed=1
        restore_target "$legacy_lighttpd_helper" || action35af_restore_failed=1
    else
        restore_node_a_quarantine || action35af_restore_failed=1
    fi

    for action35af_target in \
        /etc/keepalived/keepalived.conf \
        /etc/tmpfiles.d/caddy-ha.conf \
        /etc/unbound/unbound.conf.d/pihole-local-zone.conf \
        /etc/scripts/check-dns.sh \
        /etc/systemd/system/caddy-pihole-web-health.timer \
        /etc/systemd/system/caddy-pihole-web-health.service \
        /usr/local/libexec/caddy-apprise-delivery-worker \
        /usr/local/libexec/caddy-apprise-enqueue \
        /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        /usr/local/libexec/check-pihole-web-health.sh \
        /usr/local/libexec/check-caddy.sh \
        /usr/local/bin/keepalived-notify.sh; do
        restore_target "$action35af_target" || action35af_restore_failed=1
    done
    "$systemctl_command" disable --now caddy-pihole-web-health.timer \
        >/dev/null 2>&1 || :
    for action35af_target in \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV4 \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV6; do
        action35af_target=$(effective_path "$action35af_target")
        if [[ -e "$action35af_target" || -L "$action35af_target" ]]; then
            if [[ "$action35af_target" = */keepalived/* ]]; then
                if [[ -f "$action35af_target" && ! -L "$action35af_target" &&
                    "$(stat -c '%U:%G:%a' "$action35af_target")" = root:root:644 &&
                    "$(wc -l <"$action35af_target")" -eq 1 ]] &&
                    grep -Eq '^[A-Z_]{1,32}$' "$action35af_target"; then
                    rm -f -- "$action35af_target" || action35af_restore_failed=1
                else
                    action35af_restore_failed=1
                fi
            else
                action35af_restore_failed=1
            fi
        fi
    done
    rmdir "$(effective_path /run/caddy-serving-health/keepalived)" \
        "$(effective_path /run/caddy-serving-health)" 2>/dev/null || {
        [[ ! -d "$(effective_path /run/caddy-serving-health)" ]] ||
            action35af_restore_failed=1
    }
    restore_obsolete_status_directories || action35af_restore_failed=1
    "$systemctl_command" daemon-reload || action35af_restore_failed=1
    if [[ -n "$target_root" ]]; then
        action35af_target=$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)
        if [[ -f "$action35af_target" && ! -L "$action35af_target" ]]; then
            "$unbound_checkconf_command" "$action35af_target" || action35af_restore_failed=1
        fi
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf || action35af_restore_failed=1
    fi
    "$systemctl_command" reload unbound.service || action35af_restore_failed=1
    if regular_file "$evidence_root/target-revision"; then
        action35af_new_revision=$(target_revision) || action35af_restore_failed=1
    fi
    if [[ -z "$target_root" ]]; then
        local action35af_original_revision=$serving_revision
        [[ "$node_role" = node-b ]] || action35af_original_revision=$node_a_revision
        if [[ "$(current_revision)" != "$action35af_original_revision" ]]; then
            require rollback_original_release_regular test \
                -d "$releases_root/$action35af_original_revision" || action35af_restore_failed=1
            if [[ "$action35af_restore_failed" -eq 0 ]]; then
                ln -sfn "$releases_root/$action35af_original_revision" /etc/caddy/current.rollback
                mv -Tf /etc/caddy/current.rollback /etc/caddy/current
                "$systemctl_command" reload caddy.service || action35af_restore_failed=1
            fi
        fi
    fi
    if [[ -z "$target_root" && -n "$action35af_new_revision" &&
        -d "$releases_root/$action35af_new_revision" ]]; then
        require rollback_target_release_not_active test \
            "$(current_revision)" != "$action35af_new_revision" || action35af_restore_failed=1
        require rollback_target_revision_exact test \
            "$(jq -r '.revision // empty' "$releases_root/$action35af_new_revision/release-manifest.json")" = \
            "$action35af_new_revision" || action35af_restore_failed=1
        require rollback_target_parent_exact test \
            "$(jq -r '.parent_revision // empty' "$releases_root/$action35af_new_revision/release-manifest.json")" = \
            "$serving_revision" || action35af_restore_failed=1
        require rollback_target_payload_exact test \
            "$(sha256sum "$releases_root/$action35af_new_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
            8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8 ||
            action35af_restore_failed=1
        if [[ "$action35af_restore_failed" -eq 0 ]]; then
            rm -rf -- "${releases_root:?}/${action35af_new_revision:?}"
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$releases_root/$serving_revision" ]]; then
        action35af_release_source=$outgoing_root/$serving_revision
        if [[ -d "$evidence_root/consumed-outbound" ]]; then
            action35af_release_source=$evidence_root/consumed-outbound
        fi
        if [[ -d "$action35af_release_source" ]] &&
            diff -qr --exclude=.complete "$action35af_release_source" \
                "$releases_root/$serving_revision" >/dev/null; then
            rm -rf -- "${releases_root:?}/${serving_revision:?}"
        else
            action35af_restore_failed=1
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$evidence_root/consumed-outbound" &&
        ! -e "$outgoing_root/$serving_revision" ]]; then
        mv -- "$evidence_root/consumed-outbound" \
            "$outgoing_root/$serving_revision" || action35af_restore_failed=1
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -n "$action35af_new_revision" &&
        -d "$outgoing_root/$action35af_new_revision" ]]; then
        require rollback_target_outbound_revision test \
            "$(jq -r '.revision // empty' "$outgoing_root/$action35af_new_revision/release-manifest.json")" = \
            "$action35af_new_revision" || action35af_restore_failed=1
        require rollback_target_outbound_parent test \
            "$(jq -r '.parent_revision // empty' "$outgoing_root/$action35af_new_revision/release-manifest.json")" = \
            "$serving_revision" || action35af_restore_failed=1
        if [[ "$action35af_restore_failed" -eq 0 ]]; then
            rm -rf -- "${outgoing_root:?}/${action35af_new_revision:?}"
        fi
    fi
    "$systemctl_command" start keepalived.service || action35af_restore_failed=1
    if [[ -z "$target_root" ]]; then
        capture_command journal_rollback "$journalctl_command" --no-pager -o short-iso-precise \
            --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
            -t keepalived-notify -t caddy-ha-health || :
    fi
    [[ "$action35af_restore_failed" -eq 0 ]]
}

consume_outbound() {
    local action35af_source=$outgoing_root/$serving_revision
    local action35af_destination=$evidence_root/consumed-outbound

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    validate_installed_release
    require consumed_backup_absent test ! -e "$action35af_destination"
    # The child Bash expands its positional parameters.
    # shellcheck disable=SC2016
    require installed_and_outbound_equal \
        /bin/bash -c 'diff -qr --exclude=.complete "$1" "$2" >/dev/null' \
        _ "$action35af_source" "$releases_root/$serving_revision"
    local action35af_consume_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$action35af_source" "$action35af_destination" || action35af_consume_status=$?
    "$systemctl_command" start caddy-lsyncd.service || action35af_consume_status=125
    [[ "$action35af_consume_status" -eq 0 ]] || return "$action35af_consume_status"
    require outbound_consumed test ! -e "$action35af_source"
}

consume_target_outbound() {
    local action35af_revision action35af_source action35af_destination

    [[ "$node_role" = node-a ]]
    action35af_revision=$(target_revision)
    action35af_source=$outgoing_root/$action35af_revision
    action35af_destination=$evidence_root/consumed-target-outbound
    require target_selected_before_consume test "$(current_revision)" = "$action35af_revision"
    require target_outbound_before_consume test -d "$action35af_source"
    require target_consumed_backup_absent path_absent "$action35af_destination"
    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$action35af_source" "$action35af_destination"
    "$systemctl_command" start caddy-lsyncd.service || return 125
    require target_outbound_consumed path_absent "$action35af_source"
}

produce_bounded_evidence() {
    capture_command payload_identity sha256sum \
        "$payload_root/manifests/serving-health-production.tsv"
}

ownership_sample() {
    local action35af_ipv4_state action35af_ipv6_state action35af_addresses
    local action35af_expected_state action35af_expected_vips
    local action35af_vip_count action35af_attempt action35af_stable=0
    local action35af_sample_valid

    action35af_expected_state=Backup
    action35af_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        action35af_expected_state=Master
        action35af_expected_vips=4
    fi
    : >"$evidence_root/ownership-samples.tsv"
    chmod 0600 "$evidence_root/ownership-samples.tsv"
    for ((action35af_attempt = 1; action35af_attempt <= ownership_attempts; action35af_attempt++)); do
        action35af_ipv4_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        action35af_ipv6_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        action35af_addresses=$("$ip_command" -o address show dev eth0)
        action35af_vip_count=0
        grep -Fq ' 10.1.0.55/22 ' <<<"$action35af_addresses" && action35af_vip_count=$((action35af_vip_count + 1))
        grep -Fq ' 10.1.0.56/22 ' <<<"$action35af_addresses" && action35af_vip_count=$((action35af_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$action35af_addresses" && action35af_vip_count=$((action35af_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$action35af_addresses" && action35af_vip_count=$((action35af_vip_count + 1))
        printf '%s\t%s\t%s\t%s\t%s\n' "$action35af_attempt" \
            "$($date_command -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
            "$action35af_ipv4_state" "$action35af_ipv6_state" "$action35af_vip_count" \
            >>"$evidence_root/ownership-samples.tsv"

        action35af_sample_valid=false
        if [[ "$action35af_ipv4_state" = "$action35af_ipv6_state" ]]; then
            case "$action35af_ipv4_state:$action35af_vip_count" in
                "$action35af_expected_state:$action35af_expected_vips")
                    action35af_sample_valid=true
                    action35af_stable=$((action35af_stable + 1))
                    ;;
                Fault:0 | Backup:0)
                    action35af_stable=0
                    ;;
                *)
                    require ownership_incorrect_state false
                    ;;
            esac
        else
            require ownership_split_family false
        fi
        if [[ "$action35af_sample_valid" = true &&
            "$action35af_stable" -ge "$ownership_stable_samples" ]]; then
            printf 'ipv4=%s\nipv6=%s\nshared_vips=%s\nstable_samples=%s\n' \
                "$action35af_ipv4_state" "$action35af_ipv6_state" \
                "$action35af_vip_count" "$action35af_stable"
            require ownership_ipv4 test "$action35af_ipv4_state" = "$action35af_expected_state"
            require ownership_ipv6 test "$action35af_ipv6_state" = "$action35af_expected_state"
            require ownership_vips test "$action35af_vip_count" -eq "$action35af_expected_vips"
            require ownership_stable test "$action35af_stable" -ge "$ownership_stable_samples"
            return 0
        fi
        "$sleep_command" "$ownership_sample_delay"
    done
    require ownership_convergence false
}

capture_journal_cursor() {
    local action35af_cursor

    capture_command journal_cursor_raw "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    action35af_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal_cursor_raw.stdout")
    require journal_cursor_exact test -n "$action35af_cursor"
    printf '%s\n' "$action35af_cursor" >"$evidence_root/journal.cursor"
    chmod 0600 "$evidence_root/journal.cursor"
}

capture_post_journal() {
    regular_file "$evidence_root/journal.cursor"
    capture_command journal_keepalived_vrrp "$journalctl_command" --no-pager -o short-iso-precise \
        --after-cursor "$(<"$evidence_root/journal.cursor")" \
        -u keepalived.service
    capture_command journal_post "$journalctl_command" --no-pager -o short-iso-precise \
        --after-cursor "$(<"$evidence_root/journal.cursor")" \
        -u caddy.service -u caddy-lsyncd.service \
        -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
        -t keepalived-notify -t caddy-ha-health -t caddy-ha-notify \
        -t caddy-apprise-queue
}

start_sampler() {
    local action35af_sampler=$evidence_root/availability-sampler.sh

    require sampler_pid_absent test ! -e "$evidence_root/availability.pid"
    cat >"$action35af_sampler" <<'SAMPLER'
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
            --resolve "proxy.local.theama.co:443:$shared_address" \
            'https://proxy.local.theama.co/') || https_status=$?
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
    chmod 0700 "$action35af_sampler"
    : >"$evidence_root/availability.tsv"
    chmod 0600 "$evidence_root/availability.tsv"
    nohup /bin/bash "$action35af_sampler" "$node_role" "$evidence_root" \
        >"$evidence_root/availability.stdout" \
        2>"$evidence_root/availability.stderr" &
    printf '%s\n' "$!" >"$evidence_root/availability.pid"
    chmod 0600 "$evidence_root/availability.pid"
}

stop_sampler() {
    local action35af_pid action35af_wait

    regular_file "$evidence_root/availability.pid"
    action35af_pid=$(<"$evidence_root/availability.pid")
    [[ "$action35af_pid" =~ ^[1-9][0-9]*$ ]]
    : >"$evidence_root/availability.stop"
    for ((action35af_wait = 0; action35af_wait < 10; action35af_wait++)); do
        kill -0 "$action35af_pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$action35af_pid" 2>/dev/null; then
        kill "$action35af_pid"
        wait "$action35af_pid" 2>/dev/null || :
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
    local action35af_scenario=$1
    local action35af_expectation=$2
    local action35af_status=$3
    local action35af_expected=$4
    local action35af_observed=$5
    local action35af_raw=$6
    local action35af_decision=$7
    local action35af_raw_hash

    action35af_raw_hash=$(sha256sum "$action35af_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35af_scenario" "$action35af_expectation" "$action35af_status" \
        "$action35af_expected" "$action35af_observed" "$action35af_raw_hash" \
        >"$action35af_decision"
    chmod 0600 "$action35af_raw" "$action35af_decision"
}

production_path_test_node_a_quarantine() {
    local action35af_test_root=$1
    local action35af_repo_root=$2
    local action35af_state_root=$3
    local action35af_payload=$4
    local action35af_evidence=$5
    local action35af_test_target=$6
    local action35af_systemctl=$7
    local action35af_contract=$action35af_test_root/node-a-quarantine-contract.tsv
    local action35af_candidate action35af_name action35af_revision action35af_source
    local action35af_release_hash action35af_payload_hash action35af_raw action35af_decision
    local action35af_status action35af_saved action35af_first

    chmod -R u+rwX -- "$action35af_state_root/quarantine"
    rm -rf -- "$action35af_state_root/quarantine"
    install -d -m 0750 "$action35af_state_root/quarantine"
    : >"$action35af_contract"
    while IFS=$'\t' read -r action35af_name action35af_revision action35af_source; do
        action35af_candidate=$action35af_state_root/quarantine/$action35af_name
        install -d -m 0750 "$action35af_candidate"
        printf 'payload for %s\n' "$action35af_revision" >"$action35af_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"%s","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35af_revision" "$action35af_source" \
            >"$action35af_candidate/release-manifest.json"
        (
            cd "$action35af_candidate"
            find . -type f \
                ! -path ./manifest.sha256 \
                ! -path ./.finalize-request \
                ! -path ./.complete \
                ! -path ./.complete.pending \
                -print0 |
                LC_ALL=C sort -z |
                xargs -0 sha256sum
        ) >"$action35af_candidate/manifest.sha256"
        : >"$action35af_candidate/.finalize-request"
        if [[ "$action35af_source" = node-b ]]; then
            : >"$action35af_candidate/.complete"
        fi
        chmod 0440 "$action35af_candidate"/* "$action35af_candidate"/.[!.]*
        chmod 0550 "$action35af_candidate"
        action35af_release_hash=$(sha256sum "$action35af_candidate/release-manifest.json" | awk '{ print $1 }')
        action35af_payload_hash=$(sha256sum "$action35af_candidate/manifest.sha256" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$action35af_name" "$action35af_revision" \
            "$action35af_source" "$action35af_release_hash" "$action35af_payload_hash" \
            >>"$action35af_contract"
    done <<'CONTRACT'
node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	node-b
node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	node-b
node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d	20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63	node-a
node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d	action17p-node-a-to-node-b-bootstrap	node-a
CONTRACT
    chmod 0600 "$action35af_contract"

    action35af_raw=$action35af_test_root/raw/node-a-quarantine-baseline.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-baseline.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    write_decision node-a-quarantine-baseline accept 0 exact-four exact-four \
        "$action35af_raw" "$action35af_decision"

    install -d -m 0550 "$action35af_state_root/quarantine/unexpected"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-extra-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-extra-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-a-quarantine-extra-rejection reject "$action35af_status" \
        exact-four extra-entry "$action35af_raw" "$action35af_decision"
    rmdir "$action35af_state_root/quarantine/unexpected"

    action35af_first=$(awk -F '\t' 'NR == 1 { print $1 }' "$action35af_contract")
    action35af_candidate=$action35af_state_root/quarantine/$action35af_first
    chmod 0750 "$action35af_candidate"
    chmod 0640 "$action35af_candidate/Caddyfile"
    printf 'changed\n' >>"$action35af_candidate/Caddyfile"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-changed-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-changed-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-a-quarantine-changed-rejection reject "$action35af_status" \
        manifest-valid changed-payload "$action35af_raw" "$action35af_decision"
    sed -i '$d' "$action35af_candidate/Caddyfile"
    chmod 0440 "$action35af_candidate/Caddyfile"
    chmod 0550 "$action35af_candidate"

    action35af_saved=$action35af_test_root/node-a-release-manifest.saved
    install -m 0600 "$action35af_candidate/release-manifest.json" "$action35af_saved"
    chmod 0750 "$action35af_candidate"
    chmod 0640 "$action35af_candidate/release-manifest.json"
    printf '{\n' >"$action35af_candidate/release-manifest.json"
    chmod 0440 "$action35af_candidate/release-manifest.json"
    chmod 0550 "$action35af_candidate"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-malformed-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-malformed-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-a-quarantine-malformed-rejection reject "$action35af_status" \
        exact-release-manifest malformed "$action35af_raw" "$action35af_decision"
    chmod 0750 "$action35af_candidate"
    install -m 0440 "$action35af_saved" "$action35af_candidate/release-manifest.json"

    mv "$action35af_candidate/Caddyfile" "$action35af_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35af_candidate/Caddyfile"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-symlink-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-symlink-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-a-quarantine-symlink-rejection reject "$action35af_status" \
        regular-file symlink "$action35af_raw" "$action35af_decision"
    rm "$action35af_candidate/Caddyfile"
    mv "$action35af_candidate/Caddyfile.saved" "$action35af_candidate/Caddyfile"
    chmod 0550 "$action35af_candidate"

    rm "$action35af_test_target/etc/caddy/current"
    ln -s "$action35af_candidate" "$action35af_test_target/etc/caddy/current"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-reference-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-reference-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-a-quarantine-reference-rejection reject "$action35af_status" \
        unreferenced active-reference "$action35af_raw" "$action35af_decision"
    rm "$action35af_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35af_test_target/etc/caddy/current"

    action35af_raw=$action35af_test_root/raw/node-a-quarantine-disposition.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-disposition.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-disposition node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    write_decision node-a-quarantine-disposition accept 0 empty empty \
        "$action35af_raw" "$action35af_decision"
    action35af_raw=$action35af_test_root/raw/node-a-quarantine-rollback.txt
    action35af_decision=$action35af_test_root/decisions/node-a-quarantine-rollback.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_NODE_A_QUARANTINE_CONTRACT=$action35af_contract \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        node-a-quarantine-rollback node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    write_decision node-a-quarantine-rollback accept 0 exact-four exact-four \
        "$action35af_raw" "$action35af_decision"
}

production_path_test() {
    local action35af_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35af_repo_root action35af_inventory action35af_key action35af_repository
    local action35af_source action35af_target action35af_inventory_node action35af_source_hash
    local action35af_deployed_hash action35af_accepted action35af_lifecycle action35af_source_path
    local action35af_observed action35af_raw action35af_decision action35af_status
    local action35af_state_root action35af_payload action35af_evidence action35af_candidate
    local action35af_release_hash action35af_payload_hash action35af_systemctl
    local action35af_marker action35af_marker_label action35af_quarantine_manifest
    local action35af_quarantine_name action35af_quarantine_candidate
    local action35af_test_target action35af_saved_hash action35af_missing_candidate
    local action35af_saved_manifest
    local action35af_promotion_root action35af_promotion_payload
    local action35af_promotion_evidence action35af_promotion_target
    local action35af_promotion_candidate action35af_promotion_manifest_hash
    local action35af_runuser action35af_finalizer action35af_dig action35af_curl
    local action35af_ss action35af_unbound_checkconf action35af_publisher
    local action35af_current_before action35af_target_test_revision
    local action35af_current_after action35af_phase_helper

    action35af_write_quarantine_manifest() {
        local action35af_fixture_root=$1
        local action35af_fixture_manifest=$2
        local action35af_fixture_path action35af_fixture_relative
        local action35af_fixture_encoded action35af_fixture_type
        local action35af_fixture_metadata action35af_fixture_hash

        printf '# path-b64\ttype\tmetadata\tsha256\n' >"$action35af_fixture_manifest"
        while IFS= read -r -d '' action35af_fixture_path; do
            action35af_fixture_relative=${action35af_fixture_path#"$action35af_fixture_root"/}
            action35af_fixture_encoded=$(printf '%s' "$action35af_fixture_relative" | base64 -w 0)
            if [[ -d "$action35af_fixture_path" && ! -L "$action35af_fixture_path" ]]; then
                action35af_fixture_type=directory
                action35af_fixture_hash=-
            elif [[ -f "$action35af_fixture_path" && ! -L "$action35af_fixture_path" ]]; then
                if [[ -s "$action35af_fixture_path" ]]; then
                    action35af_fixture_type='regular file'
                else
                    action35af_fixture_type='regular empty file'
                fi
                action35af_fixture_hash=$(sha256sum "$action35af_fixture_path" | awk '{ print $1 }')
            else
                return 1
            fi
            action35af_fixture_metadata=$(stat -c '%U:%G:%a' "$action35af_fixture_path")
            printf '%s\t%s\t%s\t%s\n' "$action35af_fixture_encoded" \
                "$action35af_fixture_type" "$action35af_fixture_metadata" \
                "$action35af_fixture_hash" >>"$action35af_fixture_manifest"
        done < <(find "$action35af_fixture_root" -mindepth 1 -print0 | LC_ALL=C sort -z)
    }

    [[ "$action35af_test_root" = /tmp/* && -d "$action35af_test_root" && ! -L "$action35af_test_root" ]]
    chmod 0700 "$action35af_test_root"
    install -d -m 0700 "$action35af_test_root/raw" "$action35af_test_root/decisions"
    if [[ -n "${ACTION35AF_TEST_REPOSITORY_ROOT:-}" ]]; then
        action35af_repo_root=$ACTION35AF_TEST_REPOSITORY_ROOT
    else
        action35af_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    fi
    action35af_inventory=$action35af_repo_root/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r action35af_key action35af_repository action35af_source \
        action35af_target action35af_inventory_node action35af_source_hash \
        action35af_deployed_hash action35af_accepted action35af_lifecycle; do
        [[ "$action35af_key" = '# key' ]] && continue
        action35af_raw=$action35af_test_root/raw/inventory-$action35af_key.txt
        action35af_decision=$action35af_test_root/decisions/inventory-$action35af_key.tsv
        if [[ "$action35af_repository" = runtime-generated ]]; then
            printf '%s\t%s\t%s\n' "$action35af_key" "$action35af_target" \
                "$action35af_deployed_hash" >"$action35af_raw"
            action35af_observed=$(awk -F '\t' '{ print $3 }' "$action35af_raw")
            require_equal "production_inventory_${action35af_key}" \
                "$action35af_deployed_hash" "$action35af_observed"
            write_decision "inventory-$action35af_key" accept 0 \
                "$action35af_deployed_hash" "$action35af_observed" \
                "$action35af_raw" "$action35af_decision"
            continue
        fi
        action35af_source_path=${action35af_repo_root%/homelab-server-configs}/$action35af_repository/$action35af_source
        sha256sum "$action35af_source_path" >"$action35af_raw"
        action35af_observed=$(awk '{ print $1 }' "$action35af_raw")
        require_equal "production_inventory_${action35af_key}" \
            "$action35af_source_hash" "$action35af_observed"
        write_decision "inventory-$action35af_key" accept 0 \
            "$action35af_source_hash" "$action35af_observed" \
            "$action35af_raw" "$action35af_decision"
    done <"$action35af_inventory"

    action35af_state_root=$action35af_test_root/state
    action35af_payload=$(mktemp -d /tmp/caddy-action35af-production-payload.XXXXXX)
    action35af_evidence=$(mktemp -d /tmp/caddy-action35af-production-evidence.XXXXXX)
    action35af_candidate=$action35af_state_root/incoming/node-a/$retained_name
    action35af_systemctl=$action35af_test_root/systemctl
    install -d -m 0700 "$action35af_candidate" \
        "$action35af_state_root/outgoing" \
        "$action35af_state_root/releases" "$action35af_payload/manifests" \
        "$action35af_evidence"
    install -d -m 0750 "$action35af_state_root/quarantine"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$action35af_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$action35af_repo_root/Caddy/manifests/action35af-node-b-quarantine.tsv" \
        "$action35af_payload/manifests/action35af-node-b-quarantine.tsv"
    printf 'payload\n' >"$action35af_candidate/Caddyfile"
    printf '%s  Caddyfile\n' "$(sha256sum "$action35af_candidate/Caddyfile" | awk '{ print $1 }')" \
        >"$action35af_candidate/manifest.sha256"
    printf '{"revision":"%s","source_node":"node-a"}\n' "$retained_name" \
        >"$action35af_candidate/release-manifest.json"
    chmod 0500 "$action35af_candidate"
    while IFS= read -r action35af_quarantine_name; do
        action35af_quarantine_candidate=$action35af_state_root/quarantine/$action35af_quarantine_name
        install -d -m 0750 "$action35af_quarantine_candidate"
        printf 'payload for %s\n' "$action35af_quarantine_name" \
            >"$action35af_quarantine_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35af_quarantine_name" \
            >"$action35af_quarantine_candidate/release-manifest.json"
        {
            printf '%s  Caddyfile\n' \
                "$(sha256sum "$action35af_quarantine_candidate/Caddyfile" | awk '{ print $1 }')"
            printf '%s  release-manifest.json\n' \
                "$(sha256sum "$action35af_quarantine_candidate/release-manifest.json" | awk '{ print $1 }')"
        } >"$action35af_quarantine_candidate/manifest.sha256"
        chmod 0440 "$action35af_quarantine_candidate/"*
        case "$action35af_quarantine_name" in
            node-a-action17p-* | node-a-action33k-*)
                : >"$action35af_quarantine_candidate/.complete"
                : >"$action35af_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35af_quarantine_candidate/.complete" \
                    "$action35af_quarantine_candidate/.finalize-request"
                ;;
            *)
                : >"$action35af_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35af_quarantine_candidate/.finalize-request"
                ;;
        esac
        chmod 0550 "$action35af_quarantine_candidate"
    done < <(quarantine_names)
    action35af_quarantine_manifest=$action35af_test_root/quarantine-inventory.tsv
    action35af_write_quarantine_manifest "$action35af_state_root/quarantine" \
        "$action35af_quarantine_manifest"
    action35af_test_target=$action35af_test_root/target
    install -d -m 0700 "$action35af_test_target/etc/caddy/releases/current-test"
    ln -s releases/current-test "$action35af_test_target/etc/caddy/current"
    install -d -m 0755 "$action35af_test_target/usr/local/libexec"
    install -m 0755 "$action35af_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35af_test_target$legacy_lighttpd_helper"
    action35af_raw=$action35af_test_root/raw/legacy-helper-node-b-baseline.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-node-b-baseline.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    write_decision legacy-helper-node-b-baseline accept 0 exact-legacy exact-legacy \
        "$action35af_raw" "$action35af_decision"
    action35af_raw=$action35af_test_root/raw/legacy-helper-removal.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-removal.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-remove node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    path_absent "$action35af_test_target$legacy_lighttpd_helper"
    write_decision legacy-helper-removal accept 0 absent absent \
        "$action35af_raw" "$action35af_decision"
    action35af_raw=$action35af_test_root/raw/legacy-helper-rollback.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-rollback.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-rollback node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    require_equal production_test_legacy_helper_restored "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35af_test_target$legacy_lighttpd_helper" | awk '{ print $1 }')"
    write_decision legacy-helper-rollback accept 0 exact-legacy exact-legacy \
        "$action35af_raw" "$action35af_decision"
    rm -f -- "$action35af_test_target$legacy_lighttpd_helper"
    action35af_raw=$action35af_test_root/raw/legacy-helper-node-a-baseline.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-node-a-baseline.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw"
    write_decision legacy-helper-node-a-baseline accept 0 absent absent \
        "$action35af_raw" "$action35af_decision"
    action35af_raw=$action35af_test_root/raw/legacy-helper-node-b-absent-rejection.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-node-b-absent-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision legacy-helper-node-b-absent-rejection reject "$action35af_status" \
        exact-legacy absent "$action35af_raw" "$action35af_decision"
    install -m 0755 "$action35af_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35af_test_target$legacy_lighttpd_helper"
    action35af_raw=$action35af_test_root/raw/legacy-helper-node-a-present-rejection.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-node-a-present-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-check node-a "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision legacy-helper-node-a-present-rejection reject "$action35af_status" \
        absent present "$action35af_raw" "$action35af_decision"
    rm -f -- "$action35af_test_target$legacy_lighttpd_helper"
    ln -s /dev/null "$action35af_test_target$legacy_lighttpd_helper"
    action35af_raw=$action35af_test_root/raw/legacy-helper-node-b-symlink-rejection.txt
    action35af_decision=$action35af_test_root/decisions/legacy-helper-node-b-symlink-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        legacy-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision legacy-helper-node-b-symlink-rejection reject "$action35af_status" \
        regular-file symlink "$action35af_raw" "$action35af_decision"
    rm -f -- "$action35af_test_target$legacy_lighttpd_helper"
    action35af_release_hash=$(sha256sum "$action35af_candidate/release-manifest.json" | awk '{ print $1 }')
    action35af_payload_hash=$(sha256sum "$action35af_candidate/manifest.sha256" | awk '{ print $1 }')
    cat >"$action35af_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35AF_SYSTEMCTL_CALLS:?}"
SYSTEMCTL
    chmod 0700 "$action35af_systemctl"
    : >"$action35af_test_root/systemctl.calls"
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256=$action35af_release_hash \
        ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35af_payload_hash \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        retained-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_test_root/retained-check.stdout"
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_test_root/quarantine-check.stdout"
    install -d -m 0550 "$action35af_state_root/quarantine/unexpected"
    action35af_raw=$action35af_test_root/raw/quarantine-extra-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-extra-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-extra-rejection reject "$action35af_status" \
        exact-four-entries extra-entry "$action35af_raw" "$action35af_decision"
    rmdir "$action35af_state_root/quarantine/unexpected"
    action35af_quarantine_candidate=$action35af_state_root/quarantine/$(quarantine_names | sed -n '1p')
    action35af_saved_hash=$(sha256sum "$action35af_quarantine_candidate/Caddyfile" | awk '{ print $1 }')
    chmod 0750 "$action35af_quarantine_candidate"
    chmod 0640 "$action35af_quarantine_candidate/Caddyfile"
    printf 'changed\n' >>"$action35af_quarantine_candidate/Caddyfile"
    action35af_raw=$action35af_test_root/raw/quarantine-changed-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-changed-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-changed-rejection reject "$action35af_status" \
        exact-captured-hash changed-hash "$action35af_raw" "$action35af_decision"
    sed -i '$d' "$action35af_quarantine_candidate/Caddyfile"
    chmod 0440 "$action35af_quarantine_candidate/Caddyfile"
    [[ "$(sha256sum "$action35af_quarantine_candidate/Caddyfile" | awk '{ print $1 }')" = "$action35af_saved_hash" ]]
    mv "$action35af_quarantine_candidate/Caddyfile" \
        "$action35af_quarantine_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35af_quarantine_candidate/Caddyfile"
    action35af_raw=$action35af_test_root/raw/quarantine-symlink-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-symlink-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-symlink-rejection reject "$action35af_status" \
        regular-file symlink "$action35af_raw" "$action35af_decision"
    rm "$action35af_quarantine_candidate/Caddyfile"
    mv "$action35af_quarantine_candidate/Caddyfile.saved" \
        "$action35af_quarantine_candidate/Caddyfile"
    chmod 0550 "$action35af_quarantine_candidate"
    action35af_missing_candidate=$action35af_test_root/missing-quarantine-candidate
    chmod 0750 "$action35af_quarantine_candidate"
    mv "$action35af_quarantine_candidate" "$action35af_missing_candidate"
    action35af_raw=$action35af_test_root/raw/quarantine-missing-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-missing-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-missing-rejection reject "$action35af_status" \
        exact-four-entries missing-entry "$action35af_raw" "$action35af_decision"
    mv "$action35af_missing_candidate" "$action35af_quarantine_candidate"
    chmod 0550 "$action35af_quarantine_candidate"
    action35af_saved_manifest=$action35af_test_root/release-manifest.saved
    install -m 0600 "$action35af_quarantine_candidate/release-manifest.json" \
        "$action35af_saved_manifest"
    chmod 0750 "$action35af_quarantine_candidate"
    chmod 0640 "$action35af_quarantine_candidate/release-manifest.json"
    printf '{\n' >"$action35af_quarantine_candidate/release-manifest.json"
    action35af_write_quarantine_manifest "$action35af_state_root/quarantine" \
        "$action35af_quarantine_manifest"
    action35af_raw=$action35af_test_root/raw/quarantine-malformed-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-malformed-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-malformed-rejection reject "$action35af_status" \
        valid-release-json malformed-json "$action35af_raw" "$action35af_decision"
    install -m 0440 "$action35af_saved_manifest" \
        "$action35af_quarantine_candidate/release-manifest.json"
    chmod 0550 "$action35af_quarantine_candidate"
    action35af_write_quarantine_manifest "$action35af_state_root/quarantine" \
        "$action35af_quarantine_manifest"
    rm "$action35af_test_target/etc/caddy/current"
    ln -s "$action35af_quarantine_candidate" \
        "$action35af_test_target/etc/caddy/current"
    action35af_raw=$action35af_test_root/raw/quarantine-reference-rejection.txt
    action35af_decision=$action35af_test_root/decisions/quarantine-reference-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        quarantine-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        return 1
    else
        action35af_status=$?
    fi
    write_decision quarantine-reference-rejection reject "$action35af_status" \
        unreferenced active-reference "$action35af_raw" "$action35af_decision"
    rm "$action35af_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35af_test_target/etc/caddy/current"
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256=$action35af_release_hash \
        ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35af_payload_hash \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        retained-disposition node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_test_root/retained-disposition.stdout"
    [[ ! -e "$action35af_candidate" && -d "$action35af_evidence/retained-incoming" ]]
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256=$action35af_release_hash \
        ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35af_payload_hash \
        ACTION35AF_QUARANTINE_INVENTORY_MANIFEST=$action35af_quarantine_manifest \
        ACTION35AF_TARGET_ROOT=$action35af_test_target \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        retained-rollback node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_test_root/retained-rollback.stdout"
    [[ -d "$action35af_candidate" && ! -e "$action35af_evidence/retained-incoming" ]]

    action35af_raw=$action35af_test_root/raw/transaction-rejection.txt
    action35af_decision=$action35af_test_root/decisions/transaction-rejection.tsv
    install -d -m 0700 "$action35af_state_root/incoming/node-a/unexpected"
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
        ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256=$action35af_release_hash \
        ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35af_payload_hash \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        retained-check node-b "$action35af_payload" "$action35af_evidence" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision transaction-rejection reject "$action35af_status" exact-retained-only \
        unexpected-sibling "$action35af_raw" "$action35af_decision"
    rmdir "$action35af_state_root/incoming/node-a/unexpected"

    for action35af_marker in .finalize-request .complete.pending .complete; do
        action35af_marker_label=${action35af_marker#.}
        action35af_marker_label=${action35af_marker_label//./-}
        chmod 0700 "$action35af_candidate"
        : >"$action35af_candidate/$action35af_marker"
        chmod 0500 "$action35af_candidate"
        action35af_raw=$action35af_test_root/raw/transaction-marker-$action35af_marker_label-rejection.txt
        action35af_decision=$action35af_test_root/decisions/transaction-marker-$action35af_marker_label-rejection.tsv
        if ACTION35AF_PRODUCTION_PATH_TEST=1 \
            ACTION35AF_INCOMING_ROOT=$action35af_state_root/incoming \
            ACTION35AF_OUTGOING_ROOT=$action35af_state_root/outgoing \
            ACTION35AF_QUARANTINE_ROOT=$action35af_state_root/quarantine \
            ACTION35AF_RELEASES_ROOT=$action35af_state_root/releases \
            ACTION35AF_RETAINED_RELEASE_MANIFEST_SHA256=$action35af_release_hash \
            ACTION35AF_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35af_payload_hash \
            /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
            retained-check node-b "$action35af_payload" "$action35af_evidence" \
            >"$action35af_raw" 2>&1; then
            action35af_status=0
        else
            action35af_status=$?
        fi
        write_decision "transaction-marker-$action35af_marker_label-rejection" reject \
            "$action35af_status" absent present "$action35af_raw" "$action35af_decision"
        chmod 0700 "$action35af_candidate"
        rm -f -- "$action35af_candidate/$action35af_marker"
        chmod 0500 "$action35af_candidate"
    done

    action35af_raw=$action35af_test_root/raw/transaction-acceptance.txt
    action35af_decision=$action35af_test_root/decisions/transaction-acceptance.tsv
    {
        cat "$action35af_test_root/retained-check.stdout"
        cat "$action35af_test_root/quarantine-check.stdout"
        cat "$action35af_test_root/retained-disposition.stdout"
        cat "$action35af_test_root/retained-rollback.stdout"
        cat "$action35af_test_root/systemctl.calls"
        find "$action35af_state_root/incoming/node-a" -mindepth 1 -maxdepth 1 \
            -printf '%f\t%y\t%u:%g:%m\n' | LC_ALL=C sort
    } >"$action35af_raw"
    write_decision transaction-acceptance reach 0 retained-restored \
        retained-restored "$action35af_raw" "$action35af_decision"
    production_path_test_node_a_quarantine "$action35af_test_root" \
        "$action35af_repo_root" "$action35af_state_root" "$action35af_payload" \
        "$action35af_evidence" "$action35af_test_target" "$action35af_systemctl"

    action35af_promotion_root=$(mktemp -d /tmp/caddy-action35af-promotion-state.XXXXXX)
    action35af_promotion_payload=$(mktemp -d /tmp/caddy-action35af-promotion-payload.XXXXXX)
    action35af_promotion_evidence=$action35af_promotion_root/evidence
    install -d -m 0700 "$action35af_promotion_evidence"
    action35af_promotion_target=$action35af_promotion_root/target
    action35af_promotion_candidate=$action35af_promotion_root/outgoing/$serving_revision
    install -d -m 0700 "$action35af_promotion_root/incoming" \
        "$action35af_promotion_root/releases" "$action35af_promotion_candidate" \
        "$action35af_promotion_target/etc/caddy/releases/$node_a_revision" \
        "$action35af_promotion_target/etc/default" \
        "$action35af_promotion_payload/manifests" \
        "$action35af_promotion_payload/repositories"
    printf '{"revision":"%s"}\n' "$node_a_revision" \
        >"$action35af_promotion_target/etc/caddy/releases/$node_a_revision/release-manifest.json"
    ln -s "releases/$node_a_revision" "$action35af_promotion_target/etc/caddy/current"
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$action35af_promotion_target/etc/default/caddy-ha"
    install -m 0600 "$action35af_repo_root/Caddy/manifests/serving-health-production.tsv" \
        "$action35af_promotion_payload/manifests/serving-health-production.tsv"
    install -m 0600 "$action35af_repo_root/Caddy/manifests/action35af-node-b-quarantine.tsv" \
        "$action35af_promotion_payload/manifests/action35af-node-b-quarantine.tsv"
    while IFS=$'\t' read -r action35af_repository action35af_source _; do
        [[ "$action35af_repository" = '# repository' ]] && continue
        action35af_source_path=${action35af_repo_root%/homelab-server-configs}/$action35af_repository/$action35af_source
        action35af_target=$action35af_promotion_payload/repositories/$action35af_repository/$action35af_source
        install -d -m 0700 "${action35af_target%/*}"
        install -m 0600 "$action35af_source_path" "$action35af_target"
    done <"$action35af_repo_root/Caddy/manifests/serving-health-production.tsv"
    install -d -m 0750 "$action35af_promotion_candidate/conf.d"
    printf 'respond /healthz 204\n' >"$action35af_promotion_candidate/Caddyfile"
    printf 'respond /admin/* 200\n' \
        >"$action35af_promotion_candidate/conf.d/10-pihole-admin.caddy"
    printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
        "$serving_revision" "$serving_parent" \
        >"$action35af_promotion_candidate/release-manifest.json"
    (
        cd "$action35af_promotion_candidate"
        find . -type f ! -path ./manifest.sha256 -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action35af_promotion_candidate/manifest.sha256"
    : >"$action35af_promotion_candidate/.finalize-request"
    find "$action35af_promotion_candidate" -type d -exec chmod 0550 {} +
    find "$action35af_promotion_candidate" -type f -exec chmod 0440 {} +
    action35af_promotion_manifest_hash=$(sha256sum \
        "$action35af_promotion_candidate/manifest.sha256" | awk '{ print $1 }')

    action35af_runuser=$action35af_promotion_root/runuser
    action35af_finalizer=$action35af_promotion_root/finalizer
    action35af_dig=$action35af_promotion_root/dig
    action35af_curl=$action35af_promotion_root/curl
    action35af_ss=$action35af_promotion_root/ss
    action35af_unbound_checkconf=$action35af_promotion_root/unbound-checkconf
    action35af_publisher=$action35af_promotion_root/publisher
    cat >"$action35af_runuser" <<'RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = -u ]]
runuser_identity=$2
runuser_group=default
shift 2
if [[ "$1" = -g ]]; then
    runuser_group=$2
    shift 2
fi
[[ "$1" = -- ]]
shift
printf '%s:%s\n' "$runuser_identity" "$runuser_group" \
    >>"${ACTION35AF_TEST_RUNUSER_CALLS:?}"
exec "$@"
RUNUSER
    cat >"$action35af_finalizer" <<'FINALIZER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source-role && "$2" = node-a ]]
candidate=${ACTION35AF_INCOMING_ROOT:?}/node-a/${ACTION35AF_TEST_SERVING_REVISION:?}
[[ -d "$candidate" && -f "$candidate/.finalize-request" ]]
printf '%s\n' "$*" >>"${ACTION35AF_TEST_FINALIZER_CALLS:?}"
chmod 0750 "$candidate"
: >"$candidate/.complete"
chmod 0440 "$candidate/.complete"
chmod 0550 "$candidate"
FINALIZER
    cat >"$action35af_publisher" <<'PUBLISHER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source && -d "$2" && "$3" = --node-role && "$4" = node-a ]]
source_root=$2
revision=action35af-production-path-target
candidate=${ACTION35AF_OUTGOING_ROOT:?}/$revision
[[ ! -e "$candidate" ]]
cp -a -- "$source_root" "$candidate"
printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-18T00:00:00Z"}\n' \
    "$revision" "${ACTION35AF_TEST_SERVING_REVISION:?}" \
    >"$candidate/release-manifest.json"
(
    cd "$candidate"
    find . -type f ! -path ./manifest.sha256 -print0 | LC_ALL=C sort -z |
        xargs -0 sha256sum
) >"$candidate/manifest.sha256"
: >"$candidate/.finalize-request"
find "$candidate" -type d -exec chmod 0550 {} +
find "$candidate" -type f -exec chmod 0440 {} +
printf 'Published protocol-v2 release %s for receiver validation.\n' "$revision"
PUBLISHER
    cat >"$action35af_systemctl" <<'SYSTEMCTL_PROMOTION'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35AF_SYSTEMCTL_CALLS:?}"
if [[ "$1" = start && "$2" = caddy-sync-reconcile.service ]]; then
    candidate=${ACTION35AF_INCOMING_ROOT:?}/node-a/${ACTION35AF_TEST_SERVING_REVISION:?}
    release=${ACTION35AF_RELEASES_ROOT:?}/${ACTION35AF_TEST_SERVING_REVISION:?}
    [[ -f "$candidate/.complete" ]]
    cp -a -- "$candidate" "$release"
    chmod 0750 "$release"
    chmod 0550 "$release"
    rm -f -- "${ACTION35AF_TARGET_ROOT:?}/etc/caddy/current"
    ln -s "$release" "$ACTION35AF_TARGET_ROOT/etc/caddy/current"
fi
case "$1" in
    is-active) [[ "$2" = --quiet ]] ;;
    start | stop) [[ $# -eq 2 ]] ;;
    *) : ;;
esac
SYSTEMCTL_PROMOTION
    cat >"$action35af_dig" <<'DIG'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$action35af_curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
curl_family=ipv4
[[ " $* " = *' --ipv4 '* ]] || curl_family=ipv6
case "${ACTION35AF_TEST_CURL_MODE:-healthy}" in
    "$curl_family-missing-status")
        kill -KILL "$PPID"
        exit 137
        ;;
    "$curl_family-malformed-status")
        curl_output=$(readlink "/proc/$$/fd/1")
        printf 'invalid\n' >"${curl_output}.status"
        kill -KILL "$PPID"
        exit 137
        ;;
    "$curl_family-missing-output")
        curl_output=$(readlink "/proc/$$/fd/1")
        rm -f -- "$curl_output"
        printf '204\n'
        exit 0
        ;;
    "$curl_family-malformed-output")
        printf 'invalid\n'
        exit 0
        ;;
    "$curl_family-signal") exit 143 ;;
    "$curl_family-timeout") exit 28 ;;
    "$curl_family-curl") exit 7 ;;
    "$curl_family-http") printf '503\n'; exit 0 ;;
esac
revision=$(jq -r '.revision // empty' "${ACTION35AF_TARGET_ROOT:?}/etc/caddy/current/release-manifest.json")
if [[ "$revision" = "${ACTION35AF_TEST_SERVING_REVISION:?}" ]]; then
    printf '204\n'
else
    printf '404\n'
    exit 22
fi
CURL
    cat >"$action35af_ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n'
SS
    cat >"$action35af_unbound_checkconf" <<'UNBOUND'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]]
grep -Fq 'local-zone: "local.theama.co." static' "$1"
UNBOUND
    chmod 0700 "$action35af_runuser" "$action35af_finalizer" "$action35af_publisher" \
        "$action35af_systemctl" \
        "$action35af_dig" "$action35af_curl" "$action35af_ss" "$action35af_unbound_checkconf"
    : >"$action35af_test_root/runuser.calls"
    : >"$action35af_test_root/finalizer.calls"
    : >"$action35af_test_root/systemctl.calls"
    action35af_current_before=$(jq -r '.revision' \
        "$action35af_promotion_target/etc/caddy/current/release-manifest.json")
    action35af_raw=$action35af_test_root/raw/post-promotion-sequence.txt
    action35af_decision=$action35af_test_root/decisions/post-promotion-sequence.tsv
    {
        printf 'current_before=%s\n' "$action35af_current_before"
        ACTION35AF_PRODUCTION_PATH_TEST=1 \
            ACTION35AF_INCOMING_ROOT=$action35af_promotion_root/incoming \
            ACTION35AF_OUTGOING_ROOT=$action35af_promotion_root/outgoing \
            ACTION35AF_QUARANTINE_ROOT=$action35af_promotion_root/quarantine \
            ACTION35AF_RELEASES_ROOT=$action35af_promotion_root/releases \
            ACTION35AF_TARGET_ROOT=$action35af_promotion_target \
            ACTION35AF_SERVING_PAYLOAD_MANIFEST_SHA256=$action35af_promotion_manifest_hash \
            ACTION35AF_FINALIZER_COMMAND=$action35af_finalizer \
            ACTION35AF_RUNUSER_COMMAND=$action35af_runuser \
            ACTION35AF_SYNC_USER=$(id -un) ACTION35AF_SYNC_GROUP=$(id -gn) \
            ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
            ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
            ACTION35AF_TEST_RUNUSER_CALLS=$action35af_test_root/runuser.calls \
            ACTION35AF_TEST_FINALIZER_CALLS=$action35af_test_root/finalizer.calls \
            ACTION35AF_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
            promote node-a "$action35af_promotion_payload" "$action35af_promotion_evidence"
        action35af_current_after=$(jq -r '.revision' \
            "$action35af_promotion_target/etc/caddy/current/release-manifest.json")
        printf 'current_after=%s\n' "$action35af_current_after"
        cat "$action35af_test_root/runuser.calls" "$action35af_test_root/finalizer.calls" \
            "$action35af_test_root/systemctl.calls"
        ACTION35AF_PRODUCTION_PATH_TEST=1 \
            ACTION35AF_TARGET_ROOT=$action35af_promotion_target \
            ACTION35AF_ENVIRONMENT_FILE=$action35af_promotion_target/etc/default/caddy-ha \
            ACTION35AF_RUNUSER_COMMAND=$action35af_runuser \
            ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
            ACTION35AF_DNS_DIG_COMMAND=$action35af_dig \
            ACTION35AF_CURL_COMMAND=$action35af_curl \
            ACTION35AF_SS_COMMAND=$action35af_ss \
            ACTION35AF_UNBOUND_CHECKCONF_COMMAND=$action35af_unbound_checkconf \
            ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
            ACTION35AF_TEST_RUNUSER_CALLS=$action35af_test_root/runuser.calls \
            ACTION35AF_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
            candidate-check node-a "$action35af_promotion_payload" "$action35af_promotion_evidence"
        cat "$action35af_promotion_evidence/caddy_identity.stdout" \
            "$action35af_promotion_evidence/caddy_identity.status"
    } >"$action35af_raw" 2>&1
    action35af_current_after=$(jq -r '.revision' \
        "$action35af_promotion_target/etc/caddy/current/release-manifest.json")
    require_equal production_test_current_before "$node_a_revision" "$action35af_current_before"
    require_equal production_test_current_after "$serving_revision" "$action35af_current_after"
    write_decision post-promotion-sequence accept 0 "$serving_revision" \
        "$action35af_current_after" "$action35af_raw" "$action35af_decision"

    action35af_raw=$action35af_test_root/raw/protocol-v2-target-publication.txt
    action35af_decision=$action35af_test_root/decisions/protocol-v2-target-publication.tsv
    install -d -m 0755 "$action35af_promotion_root/target-outgoing"
    {
        ACTION35AF_PRODUCTION_PATH_TEST=1 \
            ACTION35AF_INCOMING_ROOT=$action35af_promotion_root/incoming \
            ACTION35AF_OUTGOING_ROOT=$action35af_promotion_root/target-outgoing \
            ACTION35AF_QUARANTINE_ROOT=$action35af_promotion_root/quarantine \
            ACTION35AF_RELEASES_ROOT=$action35af_promotion_root/releases \
            ACTION35AF_TARGET_ROOT=$action35af_promotion_target \
            ACTION35AF_PUBLISHER_COMMAND=$action35af_publisher \
            ACTION35AF_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
            publish node-a "$action35af_promotion_payload" "$action35af_promotion_evidence"
    } >"$action35af_raw" 2>&1
    action35af_target_test_revision=$(<"$action35af_promotion_evidence/target-revision")
    [[ "$action35af_target_test_revision" = action35af-production-path-target ]]
    [[ "$(jq -r '.parent_revision' \
        "$action35af_promotion_root/target-outgoing/$action35af_target_test_revision/release-manifest.json")" = "$serving_revision" ]]
    [[ "$(sha256sum \
        "$action35af_promotion_root/target-outgoing/$action35af_target_test_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = 8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8 ]]
    write_decision protocol-v2-target-publication accept 0 \
        action35af-production-path-target "$action35af_target_test_revision" \
        "$action35af_raw" "$action35af_decision"

    action35af_raw=$action35af_test_root/raw/protocol-v2-target-promotion.txt
    action35af_decision=$action35af_test_root/decisions/protocol-v2-target-promotion.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_INCOMING_ROOT=$action35af_promotion_root/incoming \
        ACTION35AF_OUTGOING_ROOT=$action35af_promotion_root/target-outgoing \
        ACTION35AF_QUARANTINE_ROOT=$action35af_promotion_root/quarantine \
        ACTION35AF_RELEASES_ROOT=$action35af_promotion_root/releases \
        ACTION35AF_TARGET_ROOT=$action35af_promotion_target \
        ACTION35AF_FINALIZER_COMMAND=$action35af_finalizer \
        ACTION35AF_RUNUSER_COMMAND=$action35af_runuser \
        ACTION35AF_SYNC_USER=$(id -un) ACTION35AF_SYNC_GROUP=$(id -gn) \
        ACTION35AF_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        ACTION35AF_TEST_RUNUSER_CALLS=$action35af_test_root/runuser.calls \
        ACTION35AF_TEST_FINALIZER_CALLS=$action35af_test_root/finalizer.calls \
        ACTION35AF_TEST_SERVING_REVISION=$action35af_target_test_revision \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        promote-target node-a "$action35af_promotion_payload" \
        "$action35af_promotion_evidence" >"$action35af_raw" 2>&1
    action35af_current_after=$(jq -r '.revision' \
        "$action35af_promotion_target/etc/caddy/current/release-manifest.json")
    write_decision protocol-v2-target-promotion accept 0 \
        "$action35af_target_test_revision" "$action35af_current_after" \
        "$action35af_raw" "$action35af_decision"

    action35af_phase_helper=$action35af_promotion_payload/repositories/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35af_raw=$action35af_test_root/raw/minimal-caddy-failure.txt
    action35af_decision=$action35af_test_root/decisions/minimal-caddy-failure.tsv
    if ACTION35AF_TARGET_ROOT=$action35af_promotion_target \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        ACTION35AF_TEST_SERVING_REVISION=$serving_revision \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$action35af_promotion_target/etc/default/caddy-ha \
        CADDY_SERVING_HEALTH_CURL_COMMAND=/usr/bin/false \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$action35af_systemctl \
        /bin/bash "$action35af_phase_helper" \
        >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    printf 'exit_status=%s\n' "$action35af_status" >>"$action35af_raw"
    write_decision minimal-caddy-failure reject "$action35af_status" \
        zero nonzero \
        "$action35af_raw" "$action35af_decision"

    action35af_phase_helper=$action35af_promotion_payload/repositories/homelab-dns/Keepalived/scripts/dns-check.sh
    action35af_raw=$action35af_test_root/raw/minimal-dns-failure.txt
    action35af_decision=$action35af_test_root/decisions/minimal-dns-failure.tsv
    if DNS_CHECK_DIG_COMMAND=/usr/bin/false \
        DNS_CHECK_SYSTEMCTL_COMMAND=$action35af_systemctl \
        ACTION35AF_SYSTEMCTL_CALLS=$action35af_test_root/systemctl.calls \
        /bin/bash "$action35af_phase_helper" >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    printf 'exit_status=%s\n' "$action35af_status" >>"$action35af_raw"
    write_decision minimal-dns-failure reject "$action35af_status" \
        zero nonzero \
        "$action35af_raw" "$action35af_decision"

    action35af_busctl=$action35af_test_root/busctl
    action35af_ip=$action35af_test_root/ip
    action35af_date=$action35af_test_root/date
    action35af_sleep=$action35af_test_root/sleep
    cat >"$action35af_busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
counter_file=${ACTION35AF_TEST_OWNERSHIP_COUNTER:?}
sequence_file=${ACTION35AF_TEST_OWNERSHIP_SEQUENCE:?}
counter=$(<"$counter_file")
[[ "$counter" =~ ^[0-9]+$ ]]
if [[ "$*" = *'/IPv4 '* ]]; then
    counter=$((counter + 1))
    printf '%s\n' "$counter" >"$counter_file"
fi
state=$(sed -n "${counter}p" "$sequence_file")
[[ "$state" =~ ^(Fault|Backup|Master)$ ]]
printf 's "%s"\n' "$state"
BUSCTL
    cat >"$action35af_ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
counter=$(<"${ACTION35AF_TEST_OWNERSHIP_COUNTER:?}")
state=$(sed -n "${counter}p" "${ACTION35AF_TEST_OWNERSHIP_SEQUENCE:?}")
printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
if [[ "$state" = Master ]]; then
    printf '2: eth0    inet 10.1.0.55/22 scope global secondary eth0\n'
    printf '2: eth0    inet 10.1.0.56/22 scope global secondary eth0\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global\n'
fi
IP
    cat >"$action35af_date" <<'DATE'
#!/usr/bin/env bash
printf '2026-08-17T00:00:00.000000000Z\n'
DATE
    cat >"$action35af_sleep" <<'SLEEP'
#!/usr/bin/env bash
[[ "$1" =~ ^[0-9]+$ ]]
SLEEP
    chmod 0700 "$action35af_busctl" "$action35af_ip" "$action35af_date" \
        "$action35af_sleep"
    printf '0\n' >"$action35af_test_root/ownership.counter"
    printf 'Fault\nBackup\nBackup\nBackup\n' \
        >"$action35af_test_root/ownership.sequence"
    action35af_raw=$action35af_test_root/raw/bounded-node-b-convergence.txt
    action35af_decision=$action35af_test_root/decisions/bounded-node-b-convergence.tsv
    ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_BUSCTL_COMMAND=$action35af_busctl \
        ACTION35AF_IP_COMMAND=$action35af_ip \
        ACTION35AF_DATE_COMMAND=$action35af_date \
        ACTION35AF_SLEEP_COMMAND=$action35af_sleep \
        ACTION35AF_OWNERSHIP_ATTEMPTS=4 \
        ACTION35AF_OWNERSHIP_STABLE_SAMPLES=3 \
        ACTION35AF_OWNERSHIP_SAMPLE_DELAY=0 \
        ACTION35AF_TEST_OWNERSHIP_COUNTER=$action35af_test_root/ownership.counter \
        ACTION35AF_TEST_OWNERSHIP_SEQUENCE=$action35af_test_root/ownership.sequence \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        ownership node-b "$action35af_promotion_payload" \
        "$action35af_promotion_evidence" >"$action35af_raw"
    write_decision bounded-node-b-convergence accept 0 \
        stable-backup-after-fault stable-backup-after-fault \
        "$action35af_raw" "$action35af_decision"

    printf '0\n' >"$action35af_test_root/ownership.counter"
    printf 'Master\n' >"$action35af_test_root/ownership.sequence"
    action35af_raw=$action35af_test_root/raw/node-b-master-rejection.txt
    action35af_decision=$action35af_test_root/decisions/node-b-master-rejection.tsv
    if ACTION35AF_PRODUCTION_PATH_TEST=1 \
        ACTION35AF_BUSCTL_COMMAND=$action35af_busctl \
        ACTION35AF_IP_COMMAND=$action35af_ip \
        ACTION35AF_DATE_COMMAND=$action35af_date \
        ACTION35AF_SLEEP_COMMAND=$action35af_sleep \
        ACTION35AF_OWNERSHIP_ATTEMPTS=1 \
        ACTION35AF_OWNERSHIP_STABLE_SAMPLES=1 \
        ACTION35AF_OWNERSHIP_SAMPLE_DELAY=0 \
        ACTION35AF_TEST_OWNERSHIP_COUNTER=$action35af_test_root/ownership.counter \
        ACTION35AF_TEST_OWNERSHIP_SEQUENCE=$action35af_test_root/ownership.sequence \
        /bin/bash "$action35af_repo_root/Caddy/scripts/apply-coupled-serving-health-action35af.sh" \
        ownership node-b "$action35af_promotion_payload" \
        "$action35af_promotion_evidence" >"$action35af_raw" 2>&1; then
        action35af_status=0
    else
        action35af_status=$?
    fi
    write_decision node-b-master-rejection reject "$action35af_status" \
        backup-zero-vips master-four-vips "$action35af_raw" "$action35af_decision"
    chmod -R u+rwX -- "$action35af_promotion_payload" "$action35af_promotion_root"
    rm -rf -- "$action35af_promotion_payload" "$action35af_promotion_root"
    rm -rf -- "$action35af_payload" "$action35af_evidence"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

if [[ "${1:-}" = --production-path-test ]]; then
    [[ $# -eq 1 ]]
    production_path_test
    exit 0
fi

[[ $# -eq 4 || $# -eq 5 ]] || {
    usage
    exit 64
}
readonly mode=$1
readonly node_role=$2
readonly payload_root=$3
readonly evidence_root=$4
readonly target_revision_argument=${5:-}
[[ "$mode" =~ ^(preflight|candidate-check|quarantine-check|node-a-quarantine-check|node-a-quarantine-disposition|node-a-quarantine-rollback|retained-check|retained-disposition|retained-rollback|legacy-check|legacy-remove|legacy-rollback|install|promote|publish|record-target|wait-target|promote-target|accept|rollback|ownership|journal-cursor|journal-capture|sampler-start|sampler-stop|consume|consume-target|final-residue|evidence-probe)$ ]]
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
    publish) publish_current_release ;;
    record-target) record_target_revision ;;
    wait-target) wait_for_target_release ;;
    promote-target) promote_target_candidate ;;
    accept) accept_installed_node ;;
    rollback) rollback_node ;;
    ownership) ownership_sample ;;
    journal-cursor) capture_journal_cursor ;;
    journal-capture) capture_post_journal ;;
    sampler-start) start_sampler ;;
    sampler-stop) stop_sampler ;;
    consume) consume_outbound ;;
    consume-target) consume_target_outbound ;;
    final-residue) validate_final_residue ;;
    evidence-probe) produce_bounded_evidence ;;
esac
