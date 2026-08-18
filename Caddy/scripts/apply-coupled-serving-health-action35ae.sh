#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_35_ae
readonly node_a_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly serving_revision=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca
readonly serving_parent=$node_a_revision
readonly serving_payload_manifest_sha256=${ACTION35AE_SERVING_PAYLOAD_MANIFEST_SHA256:-ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962}
readonly retained_name=action17p-node-a-to-node-b-bootstrap
readonly retained_release_manifest_sha256=${ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256:-81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3}
readonly retained_payload_manifest_sha256=${ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256:-f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8}
readonly legacy_lighttpd_helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly legacy_lighttpd_helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly incoming_root=${ACTION35AE_INCOMING_ROOT:-/var/lib/caddy-sync/incoming}
readonly outgoing_root=${ACTION35AE_OUTGOING_ROOT:-/var/lib/caddy-sync/outbound}
readonly quarantine_root=${ACTION35AE_QUARANTINE_ROOT:-/var/lib/caddy-sync/quarantine}
readonly releases_root=${ACTION35AE_RELEASES_ROOT:-/etc/caddy/releases}
readonly node_environment=${ACTION35AE_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly runuser_command=${ACTION35AE_RUNUSER_COMMAND:-/usr/sbin/runuser}
readonly finalizer_command=${ACTION35AE_FINALIZER_COMMAND:-/usr/local/libexec/finalize-incoming-release-v2.sh}
readonly sync_user=${ACTION35AE_SYNC_USER:-caddy-sync}
readonly sync_group=${ACTION35AE_SYNC_GROUP:-caddy-sync}
readonly systemctl_command=${ACTION35AE_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly journalctl_command=${ACTION35AE_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
readonly unbound_checkconf_command=${ACTION35AE_UNBOUND_CHECKCONF_COMMAND:-/usr/sbin/unbound-checkconf}
readonly systemd_tmpfiles_command=${ACTION35AE_SYSTEMD_TMPFILES_COMMAND:-/usr/bin/systemd-tmpfiles}
readonly sleep_command=${ACTION35AE_SLEEP_COMMAND:-/usr/bin/sleep}
readonly busctl_command=${ACTION35AE_BUSCTL_COMMAND:-/usr/bin/busctl}
readonly ip_command=${ACTION35AE_IP_COMMAND:-/usr/sbin/ip}
readonly date_command=${ACTION35AE_DATE_COMMAND:-/usr/bin/date}
readonly daemon_required_transitions=${ACTION35AE_DAEMON_REQUIRED_TRANSITIONS:-5}
readonly daemon_observation_attempts=${ACTION35AE_DAEMON_OBSERVATION_ATTEMPTS:-30}
readonly daemon_observation_delay=${ACTION35AE_DAEMON_OBSERVATION_DELAY:-1}
readonly ownership_attempts=${ACTION35AE_OWNERSHIP_ATTEMPTS:-24}
readonly ownership_stable_samples=${ACTION35AE_OWNERSHIP_STABLE_SAMPLES:-3}
readonly ownership_sample_delay=${ACTION35AE_OWNERSHIP_SAMPLE_DELAY:-2}
readonly target_root=${ACTION35AE_TARGET_ROOT:-}

if [[ -n "${ACTION35AE_INCOMING_ROOT:-}${ACTION35AE_OUTGOING_ROOT:-}${ACTION35AE_QUARANTINE_ROOT:-}${ACTION35AE_RELEASES_ROOT:-}${ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256:-}${ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256:-}${ACTION35AE_QUARANTINE_INVENTORY_MANIFEST:-}${ACTION35AE_NODE_A_QUARANTINE_CONTRACT:-}${ACTION35AE_SERVING_PAYLOAD_MANIFEST_SHA256:-}${ACTION35AE_FINALIZER_COMMAND:-}${ACTION35AE_SYNC_USER:-}${ACTION35AE_SYNC_GROUP:-}${ACTION35AE_SYSTEMD_TMPFILES_COMMAND:-}${ACTION35AE_SLEEP_COMMAND:-}${ACTION35AE_BUSCTL_COMMAND:-}${ACTION35AE_IP_COMMAND:-}${ACTION35AE_DATE_COMMAND:-}${ACTION35AE_DAEMON_REQUIRED_TRANSITIONS:-}${ACTION35AE_DAEMON_OBSERVATION_ATTEMPTS:-}${ACTION35AE_DAEMON_OBSERVATION_DELAY:-}${ACTION35AE_OWNERSHIP_ATTEMPTS:-}${ACTION35AE_OWNERSHIP_STABLE_SAMPLES:-}${ACTION35AE_OWNERSHIP_SAMPLE_DELAY:-}" &&
    "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
    exit 64
fi

usage() {
    printf 'Usage: %s --production-path-test | MODE node-a|node-b PAYLOAD_ROOT EVIDENCE_ROOT\n' "${0##*/}" >&2
}

safe_root() {
    local action35ae_root=$1

    [[ "$action35ae_root" == /tmp/caddy-action35ae-* &&
        -d "$action35ae_root" && ! -L "$action35ae_root" ]]
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

effective_path() {
    local action35ae_logical_path=$1

    [[ "$action35ae_logical_path" = /* ]]
    printf '%s%s\n' "$target_root" "$action35ae_logical_path"
}

capture_command() {
    local action35ae_label=$1
    shift
    local action35ae_stdout=$evidence_root/$action35ae_label.stdout
    local action35ae_stderr=$evidence_root/$action35ae_label.stderr
    local action35ae_status=$evidence_root/$action35ae_label.status
    local action35ae_rc=0

    : >"$action35ae_stdout"
    : >"$action35ae_stderr"
    if "$@" >"$action35ae_stdout" 2>"$action35ae_stderr"; then
        action35ae_rc=0
    else
        action35ae_rc=$?
    fi
    printf '%s\n' "$action35ae_rc" >"$action35ae_status"
    chmod 0600 "$action35ae_stdout" "$action35ae_stderr" "$action35ae_status"
    [[ "$(stat -c '%s' "$action35ae_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35ae_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35ae_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35ae_stderr" >/dev/null
    return "$action35ae_rc"
}

capture_stdin_command() {
    local action35ae_label=$1
    local action35ae_input=$2
    shift 2
    local action35ae_stdout=$evidence_root/$action35ae_label.stdout
    local action35ae_stderr=$evidence_root/$action35ae_label.stderr
    local action35ae_status=$evidence_root/$action35ae_label.status
    local action35ae_rc=0

    regular_file "$action35ae_input"
    : >"$action35ae_stdout"
    : >"$action35ae_stderr"
    if "$@" <"$action35ae_input" >"$action35ae_stdout" 2>"$action35ae_stderr"; then
        action35ae_rc=0
    else
        action35ae_rc=$?
    fi
    printf '%s\n' "$action35ae_rc" >"$action35ae_status"
    chmod 0600 "$action35ae_stdout" "$action35ae_stderr" "$action35ae_status"
    [[ "$(stat -c '%s' "$action35ae_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$action35ae_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$action35ae_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$action35ae_stderr" >/dev/null
    return "$action35ae_rc"
}

require() {
    local action35ae_label=$1
    shift

    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action35ae_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action35ae_label" >&2
    return 1
}

require_equal() {
    local action35ae_label=$1
    local action35ae_expected=$2
    local action35ae_observed=$3

    [[ "$action35ae_label" =~ ^[a-z0-9_]+$ ]]
    [[ "$action35ae_expected" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    [[ "$action35ae_observed" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    printf '%s_expected_%s=%s\n' "$prefix" "$action35ae_label" "$action35ae_expected"
    printf '%s_observed_%s=%s\n' "$prefix" "$action35ae_label" "$action35ae_observed"
    require "$action35ae_label" test "$action35ae_observed" = "$action35ae_expected"
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
    local action35ae_label=$1
    local action35ae_root=$2
    local action35ae_expected=$3
    local action35ae_observed

    require "${action35ae_label}_root_regular" test -d "$action35ae_root" || return 1
    require "${action35ae_label}_root_not_symlink" test ! -L "$action35ae_root" || return 1
    if ! action35ae_observed=$(find "$action35ae_root" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | LC_ALL=C sort); then
        printf '%s_check_%s_inventory_read=false\n' "$prefix" "$action35ae_label"
        return 1
    fi
    require_equal "${action35ae_label}_inventory" "$action35ae_expected" "$action35ae_observed"
}

require_empty_or_absent_directory() {
    local action35ae_label=$1
    local action35ae_root=$2

    if [[ ! -e "$action35ae_root" && ! -L "$action35ae_root" ]]; then
        require_equal "${action35ae_label}_state" absent absent
        return 0
    fi
    require_exact_directory_inventory "$action35ae_label" "$action35ae_root" ''
}

quarantine_names() {
    printf '%s\n' \
        node-a-action17p-node-a-to-node-b-bootstrap \
        node-a-action33k-20260813T000701Z-2499021-node-a-reboot-normalized \
        node_b-outbound-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29-action30c \
        node_b-outbound-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4-action30c
}

node_a_quarantine_contract() {
    if [[ -n "${ACTION35AE_NODE_A_QUARANTINE_CONTRACT:-}" ]]; then
        [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]
        regular_file "$ACTION35AE_NODE_A_QUARANTINE_CONTRACT"
        cat "$ACTION35AE_NODE_A_QUARANTINE_CONTRACT"
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
    local action35ae_inventory_root=$1
    local action35ae_label=$2
    local action35ae_expected_metadata=caddy-sync:caddy-sync
    local action35ae_expected_names action35ae_observed_names
    local action35ae_name action35ae_name_label action35ae_revision action35ae_source
    local action35ae_release_hash action35ae_payload_hash action35ae_candidate
    local action35ae_allowed action35ae_observed action35ae_marker action35ae_path

    require "${action35ae_label}_root_regular" test -d "$action35ae_inventory_root" || return 1
    require "${action35ae_label}_root_not_symlink" test ! -L "$action35ae_inventory_root" || return 1
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35ae_expected_metadata=$(id -un):$(id -gn)
    fi
    require_equal "${action35ae_label}_root_metadata" \
        "$action35ae_expected_metadata:750" "$(stat -c '%U:%G:%a' "$action35ae_inventory_root")"
    action35ae_expected_names=$(mktemp /tmp/caddy-action35ae-node-a-expected.XXXXXX)
    action35ae_observed_names=$(mktemp /tmp/caddy-action35ae-node-a-observed.XXXXXX)
    node_a_quarantine_contract | awk -F '\t' '{ print $1 }' | LC_ALL=C sort \
        >"$action35ae_expected_names"
    find "$action35ae_inventory_root" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort >"$action35ae_observed_names"
    require "${action35ae_label}_top_level_exact" cmp -s \
        "$action35ae_expected_names" "$action35ae_observed_names" || {
        rm -f -- "$action35ae_expected_names" "$action35ae_observed_names"
        return 1
    }
    rm -f -- "$action35ae_expected_names" "$action35ae_observed_names"

    while IFS=$'\t' read -r action35ae_name action35ae_revision action35ae_source \
        action35ae_release_hash action35ae_payload_hash; do
        [[ "$action35ae_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
        action35ae_name_label=${action35ae_name,,}
        action35ae_name_label=${action35ae_name_label//[^a-z0-9_]/_}
        action35ae_candidate=$action35ae_inventory_root/$action35ae_name
        require "${action35ae_label}_${action35ae_name_label}_regular" \
            test -d "$action35ae_candidate" || return 1
        require "${action35ae_label}_${action35ae_name_label}_not_symlink" \
            test ! -L "$action35ae_candidate" || return 1
        require_equal "${action35ae_label}_${action35ae_name_label}_metadata" \
            "$action35ae_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35ae_candidate")"
        require "${action35ae_label}_${action35ae_name_label}_unsafe_types_absent" \
            test -z "$(find "$action35ae_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
        require "${action35ae_label}_${action35ae_name_label}_hardlinks_absent" \
            test -z "$(find "$action35ae_candidate" -type f -links +1 -print -quit)"
        while IFS= read -r -d '' action35ae_path; do
            if [[ -d "$action35ae_path" ]]; then
                require_equal "${action35ae_label}_${action35ae_name_label}_directory_metadata" \
                    "$action35ae_expected_metadata:550" "$(stat -c '%U:%G:%a' "$action35ae_path")" || return 1
            else
                require_equal "${action35ae_label}_${action35ae_name_label}_file_metadata" \
                    "$action35ae_expected_metadata:440" "$(stat -c '%U:%G:%a' "$action35ae_path")" || return 1
            fi
        done < <(find "$action35ae_candidate" -mindepth 1 -print0)
        require_equal "${action35ae_label}_${action35ae_name_label}_release_identity" \
            "$action35ae_release_hash" \
            "$(sha256sum "$action35ae_candidate/release-manifest.json" | awk '{ print $1 }')"
        require_equal "${action35ae_label}_${action35ae_name_label}_payload_identity" \
            "$action35ae_payload_hash" \
            "$(sha256sum "$action35ae_candidate/manifest.sha256" | awk '{ print $1 }')"
        require_equal "${action35ae_label}_${action35ae_name_label}_revision" \
            "$action35ae_revision" \
            "$(jq -r '.revision // empty' "$action35ae_candidate/release-manifest.json")"
        require_equal "${action35ae_label}_${action35ae_name_label}_source" \
            "$action35ae_source" \
            "$(jq -r '.source_node // empty' "$action35ae_candidate/release-manifest.json")"
        # The awk program must not expand shell positional parameters.
        # shellcheck disable=SC2016
        require "${action35ae_label}_${action35ae_name_label}_manifest_paths_safe" \
            awk 'length($0) < 68 { exit 1 } { p = substr($0, 67); sub(/^  /, "", p); if (p == "" || p ~ /^\// || p == ".." || p ~ /^\.\.\// || p ~ /\/\.\.\// || p ~ /\/\.\.$/) exit 1 }' \
            "$action35ae_candidate/manifest.sha256"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35ae_label}_${action35ae_name_label}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35ae_candidate"
        action35ae_allowed=$(mktemp /tmp/caddy-action35ae-node-a-allowed.XXXXXX)
        action35ae_observed=$(mktemp /tmp/caddy-action35ae-node-a-files.XXXXXX)
        for action35ae_marker in .finalize-request .complete; do
            if [[ -e "$action35ae_candidate/$action35ae_marker" ]]; then
                require "${action35ae_label}_${action35ae_name_label}_${action35ae_marker#.}_empty" \
                    test ! -s "$action35ae_candidate/$action35ae_marker" || return 1
            fi
        done
        {
            printf '%s\n' ./manifest.sha256 ./release-manifest.json
            awk '{ print substr($0, 67) }' "$action35ae_candidate/manifest.sha256"
            for action35ae_marker in .finalize-request .complete; do
                if [[ -e "$action35ae_candidate/$action35ae_marker" ]]; then
                    printf './%s\n' "$action35ae_marker"
                fi
            done
        } | LC_ALL=C sort -u >"$action35ae_allowed"
        require "${action35ae_label}_${action35ae_name_label}_complete_pending_absent" \
            path_absent "$action35ae_candidate/.complete.pending"
        (
            cd "$action35ae_candidate"
            find . -type f -print | LC_ALL=C sort -u
        ) >"$action35ae_observed"
        require "${action35ae_label}_${action35ae_name_label}_file_inventory_exact" \
            cmp -s "$action35ae_allowed" "$action35ae_observed" || {
            rm -f -- "$action35ae_allowed" "$action35ae_observed"
            return 1
        }
        rm -f -- "$action35ae_allowed" "$action35ae_observed"
    done < <(node_a_quarantine_contract)

    action35ae_path=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35ae_label}_current_reference_absent" test \
        "${action35ae_path#"$action35ae_inventory_root"/}" = "$action35ae_path"
    action35ae_path=''
    while IFS= read -r -d '' action35ae_marker; do
        action35ae_path=$(readlink -f "$action35ae_marker" || :)
        [[ "${action35ae_path#"$action35ae_inventory_root"/}" = "$action35ae_path" ]] || break
        action35ae_path=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35ae_label}_state_references_absent" test -z "$action35ae_path"
}

validate_quarantine_inventory() {
    local action35ae_inventory_root=$1
    local action35ae_label=$2
    local action35ae_manifest=${ACTION35AE_QUARANTINE_INVENTORY_MANIFEST:-$payload_root/manifests/action35ae-node-b-quarantine.tsv}
    local action35ae_expected_metadata=caddy-sync:caddy-sync:750
    local action35ae_observed_file action35ae_expected_file
    local action35ae_path action35ae_relative action35ae_encoded action35ae_type
    local action35ae_metadata action35ae_hash action35ae_reference
    local action35ae_name

    require "${action35ae_label}_root_regular" test -d "$action35ae_inventory_root" || return 1
    require "${action35ae_label}_root_not_symlink" test ! -L "$action35ae_inventory_root" || return 1
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35ae_expected_metadata=$(id -un):$(id -gn):750
    fi
    require_equal "${action35ae_label}_root_metadata" "$action35ae_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35ae_inventory_root")"
    require "${action35ae_label}_manifest_regular" regular_file "$action35ae_manifest"
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
        require_equal "${action35ae_label}_manifest_identity" \
            2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
            "$(sha256sum "$action35ae_manifest" | awk '{ print $1 }')"
    fi
    action35ae_expected_file=$(mktemp /tmp/caddy-action35ae-quarantine-expected.XXXXXX)
    action35ae_observed_file=$(mktemp /tmp/caddy-action35ae-quarantine-observed.XXXXXX)
    awk -F '\t' 'NR > 1 { print }' "$action35ae_manifest" | LC_ALL=C sort \
        >"$action35ae_expected_file"
    while IFS= read -r -d '' action35ae_path; do
        action35ae_relative=${action35ae_path#"$action35ae_inventory_root"/}
        [[ -n "$action35ae_relative" && "$action35ae_relative" != /* &&
            "$action35ae_relative" != .. && "$action35ae_relative" != ../* &&
            "$action35ae_relative" != */../* && "$action35ae_relative" != */.. ]]
        action35ae_encoded=$(printf '%s' "$action35ae_relative" | base64 -w 0)
        if [[ -d "$action35ae_path" && ! -L "$action35ae_path" ]]; then
            action35ae_type=directory
            action35ae_hash=-
        elif [[ -f "$action35ae_path" && ! -L "$action35ae_path" ]]; then
            if [[ -s "$action35ae_path" ]]; then
                action35ae_type='regular file'
            else
                action35ae_type='regular empty file'
            fi
            action35ae_hash=$(sha256sum "$action35ae_path" | awk '{ print $1 }')
        else
            printf '%s_check_%s_unsafe_type=false\n' "$prefix" "$action35ae_label"
            rm -f -- "$action35ae_expected_file" "$action35ae_observed_file"
            return 1
        fi
        action35ae_metadata=$(stat -c '%U:%G:%a' "$action35ae_path")
        printf '%s\t%s\t%s\t%s\n' "$action35ae_encoded" "$action35ae_type" \
            "$action35ae_metadata" "$action35ae_hash" >>"$action35ae_observed_file"
    done < <(find "$action35ae_inventory_root" -mindepth 1 -print0)
    LC_ALL=C sort -o "$action35ae_observed_file" "$action35ae_observed_file"
    require "${action35ae_label}_exact" cmp -s \
        "$action35ae_expected_file" "$action35ae_observed_file" || {
        rm -f -- "$action35ae_expected_file" "$action35ae_observed_file"
        return 1
    }
    rm -f -- "$action35ae_expected_file" "$action35ae_observed_file"
    while IFS= read -r action35ae_name; do
        require "${action35ae_label}_${action35ae_name//[-]/_}_release_manifest_json" \
            jq -e \
            'type == "object" and
             (.revision | type == "string" and length > 0) and
             (.parent_revision | type == "string" and length > 0) and
             (.source_node | type == "string" and (. == "node-a" or . == "node-b")) and
             (.created_at | type == "string" and length > 0)' \
            "$action35ae_inventory_root/$action35ae_name/release-manifest.json"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${action35ae_label}_${action35ae_name//[-]/_}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$action35ae_inventory_root/$action35ae_name"
    done < <(quarantine_names)
    action35ae_reference=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${action35ae_label}_current_reference_absent" test \
        "${action35ae_reference#"$action35ae_inventory_root"/}" = "$action35ae_reference"
    action35ae_reference=''
    while IFS= read -r -d '' action35ae_path; do
        action35ae_reference=$(readlink -f "$action35ae_path" || :)
        [[ "${action35ae_reference#"$action35ae_inventory_root"/}" = "$action35ae_reference" ]] || break
        action35ae_reference=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${action35ae_label}_state_references_absent" test -z "$action35ae_reference"
}

validate_retained_node_b_entry() {
    local action35ae_candidate=$incoming_root/node-a/$retained_name
    local action35ae_allowed
    local action35ae_expected_metadata=caddy-sync:caddy-sync:500
    local action35ae_observed

    [[ "$node_role" = node-b ]]
    require retained_inventory_exact require_exact_directory_inventory \
        retained_incoming_node_a "$incoming_root/node-a" "$retained_name"
    require retained_candidate_regular test -d "$action35ae_candidate"
    require retained_candidate_not_symlink test ! -L "$action35ae_candidate"
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35ae_expected_metadata=$(id -un):$(id -gn):500
    fi
    require_equal retained_candidate_metadata "$action35ae_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35ae_candidate")"
    require retained_release_manifest_regular regular_file \
        "$action35ae_candidate/release-manifest.json"
    require retained_payload_manifest_regular regular_file \
        "$action35ae_candidate/manifest.sha256"
    require_equal retained_release_manifest_identity \
        "$retained_release_manifest_sha256" \
        "$(sha256sum "$action35ae_candidate/release-manifest.json" | awk '{ print $1 }')"
    require_equal retained_payload_manifest_identity \
        "$retained_payload_manifest_sha256" \
        "$(sha256sum "$action35ae_candidate/manifest.sha256" | awk '{ print $1 }')"
    require_equal retained_revision "$retained_name" \
        "$(jq -r '.revision // empty' "$action35ae_candidate/release-manifest.json")"
    require_equal retained_source node-a \
        "$(jq -r '.source_node // empty' "$action35ae_candidate/release-manifest.json")"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require retained_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35ae_candidate"
    require retained_unsafe_types_absent test -z \
        "$(find "$action35ae_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
    require retained_finalize_request_absent path_absent \
        "$action35ae_candidate/.finalize-request"
    require retained_complete_absent path_absent "$action35ae_candidate/.complete"
    require retained_complete_pending_absent path_absent \
        "$action35ae_candidate/.complete.pending"
    action35ae_allowed=$(mktemp /tmp/caddy-action35ae-retained-allowed.XXXXXX)
    action35ae_observed=$(mktemp /tmp/caddy-action35ae-retained-observed.XXXXXX)
    {
        printf '%s\n' manifest.sha256 release-manifest.json
        awk '{ print $2 }' "$action35ae_candidate/manifest.sha256"
    } | sed 's#^\./##' | LC_ALL=C sort -u >"$action35ae_allowed"
    find "$action35ae_candidate" -mindepth 1 -type f -printf '%P\n' |
        LC_ALL=C sort -u >"$action35ae_observed"
    require retained_file_inventory_exact cmp -s "$action35ae_allowed" "$action35ae_observed"
    rm -f -- "$action35ae_allowed" "$action35ae_observed"
}

disposition_retained_node_b_entry() {
    local action35ae_candidate=$incoming_root/node-a/$retained_name
    local action35ae_backup=$evidence_root/retained-incoming
    local action35ae_quarantine_backup=$evidence_root/quarantine-disposition
    local action35ae_status=0

    [[ "$node_role" = node-b ]]
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    require retained_backup_absent test ! -e "$action35ae_backup"
    require quarantine_backup_absent test ! -e "$action35ae_quarantine_backup"
    require_equal quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35ae_status=125
    if [[ "$action35ae_status" -eq 0 ]]; then
        if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            chmod 0700 "$action35ae_candidate"
        fi
        mv -- "$action35ae_candidate" "$action35ae_backup" || action35ae_status=$?
    fi
    if [[ "$action35ae_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35ae_quarantine_backup" || action35ae_status=$?
    fi
    if [[ "$action35ae_status" -eq 0 ]]; then
        if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35ae_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35ae_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35ae_status=125
    [[ "$action35ae_status" -eq 0 ]] || return "$action35ae_status"
    require retained_candidate_dispositioned test ! -e "$action35ae_candidate"
    require incoming_node_a_inventory_empty require_exact_directory_inventory \
        incoming_node_a_after_disposition "$incoming_root/node-a" ''
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine_after_disposition "$quarantine_root" ''
}

restore_retained_node_b_entry() {
    local action35ae_candidate=$incoming_root/node-a/$retained_name
    local action35ae_backup=$evidence_root/retained-incoming
    local action35ae_quarantine_backup=$evidence_root/quarantine-disposition
    local action35ae_status=0

    [[ "$node_role" = node-b ]]
    if [[ -n "$target_root" && ! -d "$action35ae_backup" ]]; then
        return 0
    fi
    if [[ -d "$action35ae_backup" && ! -L "$action35ae_backup" ]]; then
        require retained_restore_target_absent test ! -e "$action35ae_candidate"
        "$systemctl_command" stop caddy-sync-reconcile.path || action35ae_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35ae_status=125
        if [[ "$action35ae_status" -eq 0 ]]; then
            mv -- "$action35ae_backup" "$action35ae_candidate" || action35ae_status=$?
            if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
                chmod 0500 "$action35ae_candidate"
            fi
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35ae_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35ae_status=125
    fi
    if [[ -d "$action35ae_quarantine_backup" && ! -L "$action35ae_quarantine_backup" ]]; then
        validate_quarantine_inventory "$action35ae_quarantine_backup" quarantine_restore_source
        if [[ -e "$quarantine_root" || -L "$quarantine_root" ]]; then
            require quarantine_restore_target_empty require_exact_directory_inventory \
                quarantine_restore_target "$quarantine_root" ''
        else
            require quarantine_restore_target_absent path_absent "$quarantine_root"
        fi
        "$systemctl_command" stop caddy-sync-reconcile.path || action35ae_status=125
        "$systemctl_command" stop caddy-lsyncd.service || action35ae_status=125
        if [[ "$action35ae_status" -eq 0 ]]; then
            if [[ -d "$quarantine_root" ]]; then
                rmdir "$quarantine_root" || action35ae_status=$?
            fi
        fi
        if [[ "$action35ae_status" -eq 0 ]]; then
            mv -- "$action35ae_quarantine_backup" "$quarantine_root" || action35ae_status=$?
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || action35ae_status=125
        "$systemctl_command" start caddy-lsyncd.service || action35ae_status=125
    fi
    [[ "$action35ae_status" -eq 0 ]] || return "$action35ae_status"
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_restored
}

disposition_node_a_quarantine() {
    local action35ae_backup=$evidence_root/node-a-quarantine-disposition
    local action35ae_status=0

    [[ "$node_role" = node-a ]]
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_baseline
    require node_a_quarantine_backup_absent test ! -e "$action35ae_backup"
    require_equal node_a_quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35ae_status=125
    if [[ "$action35ae_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$action35ae_backup" || action35ae_status=$?
    fi
    if [[ "$action35ae_status" -eq 0 ]]; then
        if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || action35ae_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || action35ae_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35ae_status=125
    [[ "$action35ae_status" -eq 0 ]] || return "$action35ae_status"
    require node_a_quarantine_inventory_empty require_exact_directory_inventory \
        node_a_quarantine_after_disposition "$quarantine_root" ''
}

restore_node_a_quarantine() {
    local action35ae_backup=$evidence_root/node-a-quarantine-disposition
    local action35ae_status=0

    [[ "$node_role" = node-a ]]
    if [[ ! -e "$action35ae_backup" && ! -L "$action35ae_backup" ]]; then
        return 0
    fi
    require node_a_quarantine_restore_source_regular test -d "$action35ae_backup"
    require node_a_quarantine_restore_source_not_symlink test ! -L "$action35ae_backup"
    validate_node_a_quarantine_inventory "$action35ae_backup" node_a_quarantine_restore_source
    require node_a_quarantine_restore_target_empty require_exact_directory_inventory \
        node_a_quarantine_restore_target "$quarantine_root" ''
    "$systemctl_command" stop caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" stop caddy-lsyncd.service || action35ae_status=125
    if [[ "$action35ae_status" -eq 0 ]]; then
        rmdir "$quarantine_root" || action35ae_status=$?
    fi
    if [[ "$action35ae_status" -eq 0 ]]; then
        mv -- "$action35ae_backup" "$quarantine_root" || action35ae_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35ae_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35ae_status=125
    [[ "$action35ae_status" -eq 0 ]] || return "$action35ae_status"
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_restored
}

validate_outbound_candidate() {
    local action35ae_candidate=$outgoing_root/$serving_revision
    local action35ae_manifest_hash

    require outbound_candidate_regular test -d "$action35ae_candidate"
    require outbound_candidate_not_symlink test ! -L "$action35ae_candidate"
    require outbound_candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$action35ae_candidate")" = "$sync_user:$sync_group:550"
    require outbound_revision test \
        "$(jq -r '.revision // empty' "$action35ae_candidate/release-manifest.json")" = "$serving_revision"
    require outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$action35ae_candidate/release-manifest.json")" = "$serving_parent"
    require outbound_source test \
        "$(jq -r '.source_node // empty' "$action35ae_candidate/release-manifest.json")" = node-a
    action35ae_manifest_hash=$(sha256sum "$action35ae_candidate/manifest.sha256" | awk '{ print $1 }')
    require outbound_payload_manifest_hash test \
        "$action35ae_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require outbound_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35ae_candidate"
    require outbound_finalize_marker_regular test -f "$action35ae_candidate/.finalize-request"
    require outbound_finalize_marker_empty test ! -s "$action35ae_candidate/.finalize-request"
    require outbound_symlinks_absent test -z \
        "$(find "$action35ae_candidate" -type l -print -quit)"
}

validate_installed_release() {
    local action35ae_release=$releases_root/$serving_revision
    local action35ae_manifest_hash

    require installed_release_regular test -d "$action35ae_release"
    require installed_release_not_symlink test ! -L "$action35ae_release"
    require installed_release_metadata test \
        "$(stat -c '%U:%G:%a' "$action35ae_release")" = root:caddy-tls:550
    require installed_release_revision test \
        "$(jq -r '.revision // empty' "$action35ae_release/release-manifest.json")" = "$serving_revision"
    require installed_release_parent test \
        "$(jq -r '.parent_revision // empty' "$action35ae_release/release-manifest.json")" = "$serving_parent"
    require installed_release_source test \
        "$(jq -r '.source_node // empty' "$action35ae_release/release-manifest.json")" = node-a
    action35ae_manifest_hash=$(sha256sum "$action35ae_release/manifest.sha256" | awk '{ print $1 }')
    require installed_payload_manifest_hash test \
        "$action35ae_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require installed_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action35ae_release"
}

validate_inventory() {
    local action35ae_inventory=$payload_root/manifests/production-artifacts.tsv
    local action35ae_key action35ae_repository action35ae_source action35ae_target
    local action35ae_inventory_node action35ae_source_hash action35ae_deployed_hash
    local action35ae_accepted action35ae_lifecycle action35ae_observed

    regular_file "$action35ae_inventory"
    while IFS=$'\t' read -r action35ae_key action35ae_repository action35ae_source \
        action35ae_target action35ae_inventory_node action35ae_source_hash \
        action35ae_deployed_hash action35ae_accepted action35ae_lifecycle; do
        [[ "$action35ae_key" = '# key' ]] && continue
        [[ "$action35ae_inventory_node" = "$node_role" ||
            "$action35ae_inventory_node" = both ]] || continue
        [[ -n "$action35ae_accepted" && "$action35ae_lifecycle" = production-current ]]
        require "artifact_${action35ae_key}_regular" regular_file "$action35ae_target"
        action35ae_observed=$(sha256sum "$action35ae_target" | awk '{ print $1 }')
        require_equal "artifact_${action35ae_key}_identity" \
            "$action35ae_deployed_hash" "$action35ae_observed"
    done <"$action35ae_inventory"
}

validate_legacy_lighttpd_helper() {
    local action35ae_path
    local action35ae_expected_metadata=root:root:755

    action35ae_path=$(effective_path "$legacy_lighttpd_helper")
    if [[ "$node_role" = node-a ]]; then
        require_equal legacy_lighttpd_helper_state absent \
            "$(if path_absent "$action35ae_path"; then printf absent; else printf present; fi)"
        return
    fi
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35ae_expected_metadata=$(id -un):$(id -gn):755
    fi
    require legacy_lighttpd_helper_regular regular_file "$action35ae_path"
    require_equal legacy_lighttpd_helper_metadata "$action35ae_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$action35ae_path")"
    require_equal legacy_lighttpd_helper_identity "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35ae_path" | awk '{ print $1 }')"
}

remove_legacy_lighttpd_helper() {
    local action35ae_path

    [[ "$node_role" = node-b ]]
    validate_legacy_lighttpd_helper
    action35ae_path=$(effective_path "$legacy_lighttpd_helper")
    backup_target "$legacy_lighttpd_helper"
    rm -f -- "$action35ae_path"
    require legacy_lighttpd_helper_removed path_absent "$action35ae_path"
}

restore_legacy_lighttpd_helper() {
    [[ "$node_role" = node-b ]]
    restore_target "$legacy_lighttpd_helper"
    validate_legacy_lighttpd_helper
}

validate_services() {
    local action35ae_unit

    for action35ae_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35ae_unit//[.@-]/_}_active" \
            "$systemctl_command" is-active --quiet "$action35ae_unit"
    done
    for action35ae_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${action35ae_unit//[.@-]/_}_enabled" \
            "$systemctl_command" is-enabled --quiet "$action35ae_unit"
    done
    require caddy_api_masked test "$($systemctl_command is-enabled caddy-api.service)" = masked
    require distribution_lsyncd_masked test "$($systemctl_command is-enabled lsyncd.service)" = masked
}

validate_split_baseline() {
    local action35ae_expected_revision

    action35ae_expected_revision=$(expected_release)
    require_equal current_release_expected "$action35ae_expected_revision" "$(current_revision)"
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
    local action35ae_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35ae_repository action35ae_source action35ae_target action35ae_mode
    local action35ae_expected_hash action35ae_lifecycle action35ae_file action35ae_observed

    require payload_root safe_root "$payload_root"
    require payload_manifest regular_file "$action35ae_manifest"
    require quarantine_inventory_manifest regular_file \
        "$payload_root/manifests/action35ae-node-b-quarantine.tsv"
    require_equal quarantine_inventory_manifest_identity \
        2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
        "$(sha256sum "$payload_root/manifests/action35ae-node-b-quarantine.tsv" | awk '{ print $1 }')"
    while IFS=$'\t' read -r action35ae_repository action35ae_source action35ae_target \
        action35ae_mode action35ae_expected_hash action35ae_lifecycle; do
        [[ "$action35ae_repository" = '# repository' ]] && continue
        action35ae_file=$payload_root/repositories/$action35ae_repository/$action35ae_source
        require "payload_${action35ae_expected_hash}_regular" regular_file "$action35ae_file"
        action35ae_observed=$(sha256sum "$action35ae_file" | awk '{ print $1 }')
        require "payload_${action35ae_expected_hash}_identity" test \
            "$action35ae_observed" = "$action35ae_expected_hash"
    done <"$action35ae_manifest"
}

validate_installed_candidate_inventory() {
    local action35ae_manifest=$payload_root/manifests/serving-health-production.tsv
    local action35ae_repository action35ae_source action35ae_target action35ae_mode
    local action35ae_expected_hash action35ae_lifecycle action35ae_observed

    while IFS=$'\t' read -r action35ae_repository action35ae_source action35ae_target \
        action35ae_mode action35ae_expected_hash action35ae_lifecycle; do
        [[ "$action35ae_repository" = '# repository' ]] && continue
        [[ "$action35ae_lifecycle" = production-candidate ]]
        case "$action35ae_target" in
            /etc/caddy/releases/REVISION/*) continue ;;
        esac
        if [[ "$action35ae_source" = Keepalived/configs/keepalived-pihole0.conf &&
            "$node_role" != node-a ]]; then
            continue
        fi
        if [[ "$action35ae_source" = Keepalived/configs/keepalived-pihole00.conf &&
            "$node_role" != node-b ]]; then
            continue
        fi
        require "candidate_${action35ae_expected_hash}_regular" regular_file "$action35ae_target"
        require "candidate_${action35ae_expected_hash}_mode" test \
            "$(stat -c '%a' "$action35ae_target")" = "${action35ae_mode#0}"
        require "candidate_${action35ae_expected_hash}_owner" test \
            "$(stat -c '%U:%G' "$action35ae_target")" = root:root
        action35ae_observed=$(sha256sum "$action35ae_target" | awk '{ print $1 }')
        require "candidate_${action35ae_expected_hash}_identity" test \
            "$action35ae_observed" = "$action35ae_expected_hash"
    done <"$action35ae_manifest"
}

candidate_file() {
    local action35ae_repository=$1
    local action35ae_source=$2
    printf '%s/repositories/%s/%s\n' "$payload_root" "$action35ae_repository" "$action35ae_source"
}

backup_path() {
    local action35ae_target=$1
    printf '%s/backups/%s\n' "$evidence_root" "${action35ae_target#/}"
}

backup_target() {
    local action35ae_target=$1
    local action35ae_backup
    local action35ae_effective_target

    action35ae_backup=$(backup_path "$action35ae_target")
    action35ae_effective_target=$(effective_path "$action35ae_target")
    install -d -m 0700 "$(dirname -- "$action35ae_backup")"
    if [[ -e "$action35ae_effective_target" || -L "$action35ae_effective_target" ]]; then
        cp -a -- "$action35ae_effective_target" "$action35ae_backup"
        printf 'present\n' >"$action35ae_backup.state"
    else
        printf 'absent\n' >"$action35ae_backup.state"
    fi
}

install_target() {
    local action35ae_source=$1
    local action35ae_target=$2
    local action35ae_mode=$3
    local action35ae_owner=$4
    local action35ae_group=$5
    local action35ae_effective_target

    action35ae_effective_target=$(effective_path "$action35ae_target")
    if [[ "${ACTION35AE_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        action35ae_owner=$(id -un)
        action35ae_group=$(id -gn)
    fi

    backup_target "$action35ae_target"
    install -d -m 0755 "$(dirname -- "$action35ae_effective_target")"
    install -o "$action35ae_owner" -g "$action35ae_group" -m "$action35ae_mode" \
        "$action35ae_source" "$action35ae_effective_target"
}

restore_target() {
    local action35ae_target=$1
    local action35ae_backup
    local action35ae_state
    local action35ae_effective_target

    action35ae_backup=$(backup_path "$action35ae_target")
    action35ae_effective_target=$(effective_path "$action35ae_target")
    [[ -f "$action35ae_backup.state" && ! -L "$action35ae_backup.state" ]] || return 0
    action35ae_state=$(<"$action35ae_backup.state")
    case "$action35ae_state" in
        present)
            rm -f -- "$action35ae_effective_target"
            cp -a -- "$action35ae_backup" "$action35ae_effective_target"
            ;;
        absent) rm -f -- "$action35ae_effective_target" ;;
        *) return 1 ;;
    esac
}

install_serving_artifacts() {
    local action35ae_keepalived_source

    "$systemctl_command" stop keepalived.service
    if "$systemctl_command" is-active --quiet keepalived.service; then
        require keepalived_stopped_before_helper_replacement false
    fi
    require keepalived_stopped_before_helper_replacement true

    if [[ "$node_role" = node-a ]]; then
        action35ae_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35ae_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
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
    install_target "$(candidate_file homelab-dns "$action35ae_keepalived_source")" \
        /etc/keepalived/keepalived.conf 0644 root root
    if [[ -n "$target_root" ]]; then
        "$unbound_checkconf_command" \
            "$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)"
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf
    fi
    "$systemctl_command" daemon-reload
    "$systemd_tmpfiles_command" --create \
        "$(effective_path /etc/tmpfiles.d/caddy-ha.conf)"
    "$systemctl_command" enable --now caddy-pihole-web-health.timer
    "$systemctl_command" reload unbound.service
    prepare_daemon_status_boundary
    capture_keepalived_activation_cursor
    "$systemctl_command" start keepalived.service
    daemon_serving_health_acceptance
}

status_record_identity() {
    local action35ae_status_path=$1

    if path_absent "$action35ae_status_path"; then
        printf 'absent\n'
        return 0
    fi
    regular_file "$action35ae_status_path"
    printf '%s:%s\n' \
        "$(stat -c '%d:%i:%U:%G:%a:%s:%Y' "$action35ae_status_path")" \
        "$(sha256sum "$action35ae_status_path" | awk '{ print $1 }')"
}

validate_daemon_status_record() {
    local action35ae_name=$1
    local action35ae_status_path=$2
    local action35ae_application=$3
    local action35ae_owner=$4
    local action35ae_group=$5
    local action35ae_observed_epoch action35ae_result action35ae_failure_class
    local action35ae_check

    regular_file "$action35ae_status_path"
    [[ "$(stat -c '%s' "$action35ae_status_path")" -le 4096 ]]
    iconv -f UTF-8 -t UTF-8 "$action35ae_status_path" >/dev/null
    if LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' \
        "$action35ae_status_path"; then
        return 1
    fi
    [[ "$(wc -l <"$action35ae_status_path")" -eq 9 ]]
    grep -Fxq 'schema=caddy-serving-health-status/v1' "$action35ae_status_path"
    grep -Fxq "application=$action35ae_application" "$action35ae_status_path"
    action35ae_result=$(awk -F= '$1 == "result" { print $2 }' \
        "$action35ae_status_path")
    action35ae_check=$(awk -F= '$1 == "check" { print $2 }' \
        "$action35ae_status_path")
    action35ae_failure_class=$(awk -F= '$1 == "failure_class" { print $2 }' \
        "$action35ae_status_path")
    [[ "$action35ae_result" =~ ^(healthy|failed)$ ]]
    [[ "$action35ae_check" =~ ^[A-Za-z0-9._-]+$ ]]
    [[ "$action35ae_failure_class" =~ ^[A-Za-z0-9._-]+$ ]]
    action35ae_observed_epoch=$(awk -F= \
        '$1 == "observed_epoch" { print $2 }' "$action35ae_status_path")
    [[ "$action35ae_observed_epoch" =~ ^[0-9]+$ ]]
    if [[ -z "$target_root" ]]; then
        [[ "$(stat -c '%U:%G:%a' "$action35ae_status_path")" = "$action35ae_owner:$action35ae_group:644" ]]
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$action35ae_name" \
        "$action35ae_observed_epoch" "$action35ae_result" \
        "$action35ae_check" "$action35ae_failure_class" \
        "$(status_record_identity "$action35ae_status_path")" \
        "$(sha256sum "$action35ae_status_path" | awk '{ print $1 }')"
}

prepare_daemon_status_boundary() {
    local action35ae_name action35ae_status_path action35ae_application
    local action35ae_owner action35ae_group

    : >"$evidence_root/keepalived-status-boundary.tsv"
    for action35ae_name in dns proxy; do
        if [[ "$action35ae_name" = dns ]]; then
            action35ae_status_path=$(effective_path /run/caddy-serving-health/dns/status)
            action35ae_application=DNS
            action35ae_owner=pi
            action35ae_group=pi
        else
            action35ae_status_path=$(effective_path /run/caddy-serving-health/proxy/status)
            action35ae_application=Proxy
            action35ae_owner=keepalived_script
            action35ae_group=caddy-tls
        fi
        if path_absent "$action35ae_status_path"; then
            printf '%s\tabsent\n' "$action35ae_name" \
                >>"$evidence_root/keepalived-status-boundary.tsv"
        else
            validate_daemon_status_record "$action35ae_name" "$action35ae_status_path" \
                "$action35ae_application" "$action35ae_owner" "$action35ae_group" \
                >>"$evidence_root/keepalived-status-boundary.tsv"
            grep -Fxq 'result=healthy' "$action35ae_status_path"
            grep -Fxq 'failure_class=none' "$action35ae_status_path"
            cp -a -- "$action35ae_status_path" \
                "$evidence_root/pre-activation-$action35ae_name.status-record"
            chmod 0600 "$evidence_root/pre-activation-$action35ae_name.status-record"
            rm -f -- "$action35ae_status_path"
        fi
    done
    chmod 0600 "$evidence_root/keepalived-status-boundary.tsv"
}

capture_keepalived_activation_cursor() {
    local action35ae_cursor

    capture_command keepalived_activation_cursor_raw "$journalctl_command" \
        --quiet --no-pager -n 0 --show-cursor
    action35ae_cursor=$(sed -n 's/^-- cursor: //p' \
        "$evidence_root/keepalived_activation_cursor_raw.stdout")
    require keepalived_activation_cursor_exact test -n "$action35ae_cursor"
    printf '%s\n' "$action35ae_cursor" >"$evidence_root/keepalived-activation.cursor"
    chmod 0600 "$evidence_root/keepalived-activation.cursor"
}

daemon_serving_health_acceptance() {
    local action35ae_dns_status action35ae_proxy_status
    local action35ae_dns_identity=absent action35ae_proxy_identity=absent
    local action35ae_current_identity action35ae_attempt action35ae_cursor
    local action35ae_dns_count=0 action35ae_proxy_count=0 action35ae_invalid=0

    [[ "$daemon_required_transitions" =~ ^([5-9]|[1-9][0-9]+)$ ]]
    [[ "$daemon_observation_attempts" =~ ^([1-9][0-9]|[2-9][0-9]+)$ ]]
    [[ "$daemon_observation_delay" =~ ^[1-9][0-9]*$ ]]
    action35ae_dns_status=$(effective_path /run/caddy-serving-health/dns/status)
    action35ae_proxy_status=$(effective_path /run/caddy-serving-health/proxy/status)
    printf 'helper\tobserved_epoch\tresult\tcheck\tfailure_class\tidentity\tsha256\n' \
        >"$evidence_root/keepalived-daemon-status-transitions.tsv"
    chmod 0600 "$evidence_root/keepalived-daemon-status-transitions.tsv"

    for ((action35ae_attempt = 1; action35ae_attempt <= daemon_observation_attempts; action35ae_attempt++)); do
        if regular_file "$action35ae_dns_status"; then
            action35ae_current_identity=$(status_record_identity "$action35ae_dns_status")
            if [[ "$action35ae_current_identity" != "$action35ae_dns_identity" ]]; then
                if ! validate_daemon_status_record dns "$action35ae_dns_status" DNS pi pi \
                    >>"$evidence_root/keepalived-daemon-status-transitions.tsv"; then
                    cp -a -- "$action35ae_dns_status" \
                        "$evidence_root/rejected-keepalived-dns-$action35ae_attempt.status-record"
                    chmod 0600 \
                        "$evidence_root/rejected-keepalived-dns-$action35ae_attempt.status-record"
                    action35ae_invalid=1
                elif ! grep -Fxq 'result=healthy' "$action35ae_dns_status" ||
                    ! grep -Fxq 'failure_class=none' "$action35ae_dns_status"; then
                    cp -a -- "$action35ae_dns_status" \
                        "$evidence_root/failed-keepalived-dns-$action35ae_attempt.status-record"
                    chmod 0600 \
                        "$evidence_root/failed-keepalived-dns-$action35ae_attempt.status-record"
                    action35ae_invalid=1
                else
                    action35ae_dns_count=$((action35ae_dns_count + 1))
                fi
                action35ae_dns_identity=$action35ae_current_identity
            fi
        fi
        if regular_file "$action35ae_proxy_status"; then
            action35ae_current_identity=$(status_record_identity "$action35ae_proxy_status")
            if [[ "$action35ae_current_identity" != "$action35ae_proxy_identity" ]]; then
                if ! validate_daemon_status_record proxy "$action35ae_proxy_status" Proxy \
                    keepalived_script caddy-tls \
                    >>"$evidence_root/keepalived-daemon-status-transitions.tsv"; then
                    cp -a -- "$action35ae_proxy_status" \
                        "$evidence_root/rejected-keepalived-proxy-$action35ae_attempt.status-record"
                    chmod 0600 \
                        "$evidence_root/rejected-keepalived-proxy-$action35ae_attempt.status-record"
                    action35ae_invalid=1
                elif ! grep -Fxq 'result=healthy' "$action35ae_proxy_status" ||
                    ! grep -Fxq 'failure_class=none' "$action35ae_proxy_status"; then
                    cp -a -- "$action35ae_proxy_status" \
                        "$evidence_root/failed-keepalived-proxy-$action35ae_attempt.status-record"
                    chmod 0600 \
                        "$evidence_root/failed-keepalived-proxy-$action35ae_attempt.status-record"
                    action35ae_invalid=1
                else
                    action35ae_proxy_count=$((action35ae_proxy_count + 1))
                fi
                action35ae_proxy_identity=$action35ae_current_identity
            fi
        fi
        if [[ "$action35ae_dns_count" -ge "$daemon_required_transitions" &&
            "$action35ae_proxy_count" -ge "$daemon_required_transitions" ]]; then
            break
        fi
        "$sleep_command" "$daemon_observation_delay"
    done

    action35ae_cursor=$(<"$evidence_root/keepalived-activation.cursor")
    capture_command keepalived_daemon_journal "$journalctl_command" --no-pager \
        -o short-iso-precise --after-cursor "$action35ae_cursor" \
        -u keepalived.service
    require keepalived_daemon_journal_vrrp grep -Fq Keepalived_vrrp \
        "$evidence_root/keepalived_daemon_journal.stdout"
    require keepalived_daemon_journal_activation grep -Eq \
        'Starting|Started|Reloading|Reload complete' \
        "$evidence_root/keepalived_daemon_journal.stdout"
    require keepalived_daemon_status_records_valid test "$action35ae_invalid" -eq 0
    require keepalived_daemon_dns_transition_count test \
        "$action35ae_dns_count" -ge "$daemon_required_transitions"
    require keepalived_daemon_proxy_transition_count test \
        "$action35ae_proxy_count" -ge "$daemon_required_transitions"
    if grep -Eiq \
        'returning [1-9]|VRRP_Script\([^)]*\) failed|Entering FAULT|entering FAULT|timed out|terminated by signal' \
        "$evidence_root/keepalived_daemon_journal.stdout"; then
        require keepalived_daemon_journal_no_failure false
    fi
    require keepalived_daemon_journal_no_failure true
    require keepalived_daemon_active "$systemctl_command" is-active --quiet keepalived.service
}

parser_and_identity_checks() {
    local action35ae_keepalived_source
    local action35ae_preflight_dns_status=$evidence_root/preflight-dns/status
    local action35ae_preflight_proxy_status=$evidence_root/preflight-proxy/status

    if [[ "$node_role" = node-a ]]; then
        action35ae_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        action35ae_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    capture_command unbound_local_zone_parser "$unbound_checkconf_command" \
        "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)"
    install -d -m 0700 "${action35ae_preflight_dns_status%/*}" \
        "${action35ae_preflight_proxy_status%/*}"
    capture_stdin_command dns_identity \
        "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        "$runuser_command" -u pi -- env \
        DNS_CHECK_STATUS_FILE="$action35ae_preflight_dns_status" \
        DNS_CHECK_DIG_COMMAND="${ACTION35AE_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        DNS_CHECK_SYSTEMCTL_COMMAND="${ACTION35AE_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
    capture_stdin_command caddy_identity \
        "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        "$runuser_command" -u keepalived_script -g caddy-tls -- env \
        CADDY_SERVING_HEALTH_STATUS_FILE="$action35ae_preflight_proxy_status" \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$node_environment" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="${ACTION35AE_CURL_COMMAND:-/usr/bin/curl}" \
        CADDY_SERVING_HEALTH_SS_COMMAND="${ACTION35AE_SS_COMMAND:-/usr/bin/ss}" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="${ACTION35AE_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
}

promote_local_candidate() {
    local action35ae_source=$outgoing_root/$serving_revision
    local action35ae_destination=$incoming_root/node-a/$serving_revision

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    require local_incoming_absent test ! -e "$action35ae_destination"
    local action35ae_promotion_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$action35ae_source" "$action35ae_destination" &&
        chown -R "$sync_user:$sync_group" "$action35ae_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require local_candidate_selected test "$(current_revision)" = "$serving_revision"; then
        :
    else
        action35ae_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || action35ae_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || action35ae_promotion_status=125
    return "$action35ae_promotion_status"
}

accept_installed_node() {
    local action35ae_keepalived_hash action35ae_dns_hash action35ae_caddy_hash
    local action35ae_service_hash action35ae_timer_hash action35ae_local_zone_hash
    local action35ae_enqueue_hash action35ae_sync_notifier_hash
    local action35ae_keepalived_notifier_hash action35ae_tmpfiles_hash

    action35ae_keepalived_hash=$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')
    action35ae_dns_hash=$(sha256sum /etc/scripts/check-dns.sh | awk '{ print $1 }')
    action35ae_caddy_hash=$(sha256sum /usr/local/libexec/check-caddy.sh | awk '{ print $1 }')
    action35ae_service_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.service | awk '{ print $1 }')
    action35ae_timer_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.timer | awk '{ print $1 }')
    action35ae_local_zone_hash=$(sha256sum /etc/unbound/unbound.conf.d/pihole-local-zone.conf | awk '{ print $1 }')
    action35ae_enqueue_hash=$(sha256sum /usr/local/libexec/caddy-apprise-enqueue | awk '{ print $1 }')
    action35ae_sync_notifier_hash=$(sha256sum /usr/local/libexec/lsyncd-sync-failure-notify.sh | awk '{ print $1 }')
    action35ae_keepalived_notifier_hash=$(sha256sum /usr/local/bin/keepalived-notify.sh | awk '{ print $1 }')
    action35ae_tmpfiles_hash=$(sha256sum /etc/tmpfiles.d/caddy-ha.conf | awk '{ print $1 }')
    if [[ "$node_role" = node-a ]]; then
        require keepalived_candidate_hash test "$action35ae_keepalived_hash" = \
            de67123685edb21cdfaee95eb0497d9ab527c546cf730a5f51506bc293eab92a
    else
        require keepalived_candidate_hash test "$action35ae_keepalived_hash" = \
            cb4749c6f9e1a247dc481809652470e5b35c5ea3992e87945bada9292f5cbd66
    fi
    require dns_candidate_hash test "$action35ae_dns_hash" = \
        8b33b542f9834ad136c4f82f935f51e006109e0776589064fcbe7b64df3fd117
    require caddy_candidate_hash test "$action35ae_caddy_hash" = \
        c786c27890ed66964b9e9d38d9a84cb5d9f3111670fbb325bdfe0c99da7eb27b
    require web_service_hash test "$action35ae_service_hash" = \
        a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0
    require web_timer_hash test "$action35ae_timer_hash" = \
        f214b69fecaeb322dbaba61f683f9cf35970596784adcd707e25278f0ace1505
    require unbound_local_zone_hash test "$action35ae_local_zone_hash" = \
        f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d
    require enqueue_candidate_hash test "$action35ae_enqueue_hash" = \
        5101792e178ede8f6ae4cae23f9d22d57bd4c453c3578dc164175a57fe4dc56f
    require sync_notifier_candidate_hash test "$action35ae_sync_notifier_hash" = \
        278e0ff1695feca3806f24cf74c6e4007723e0b8ddbb086aaf1e121d7e9c183c
    require keepalived_notifier_candidate_hash test "$action35ae_keepalived_notifier_hash" = \
        60b758b3dd73f092bfb9bb46eb33148a7d1ecc1a913b6c83c6301dc0a905e22d
    require tmpfiles_candidate_hash test "$action35ae_tmpfiles_hash" = \
        4313578a3914ae15cecb69f920a0acc59444753eacc1960c6e95bd49acad67b9
    require serving_health_root_metadata test \
        "$(stat -c '%U:%G:%a' /run/caddy-serving-health)" = root:root:755
    require dns_status_metadata test \
        "$(stat -c '%U:%G:%a' /run/caddy-serving-health/dns/status)" = pi:pi:644
    require proxy_status_metadata test \
        "$(stat -c '%U:%G:%a' /run/caddy-serving-health/proxy/status)" = \
        keepalived_script:caddy-tls:644
    require dns_status_schema grep -Fxq \
        'schema=caddy-serving-health-status/v1' \
        /run/caddy-serving-health/dns/status
    require dns_status_application grep -Fxq 'application=DNS' \
        /run/caddy-serving-health/dns/status
    require dns_status_healthy grep -Fxq 'result=healthy' \
        /run/caddy-serving-health/dns/status
    require proxy_status_schema grep -Fxq \
        'schema=caddy-serving-health-status/v1' \
        /run/caddy-serving-health/proxy/status
    require proxy_status_application grep -Fxq 'application=Proxy' \
        /run/caddy-serving-health/proxy/status
    require proxy_status_component grep -Fxq 'component=Caddy' \
        /run/caddy-serving-health/proxy/status
    require proxy_status_healthy grep -Fxq 'result=healthy' \
        /run/caddy-serving-health/proxy/status
    require web_timer_enabled "$systemctl_command" is-enabled --quiet caddy-pihole-web-health.timer
    require web_timer_active "$systemctl_command" is-active --quiet caddy-pihole-web-health.timer
    require web_worker_static test \
        "$($systemctl_command is-enabled caddy-pihole-web-health.service)" = static
    require selected_release test "$(current_revision)" = "$serving_revision"
    validate_installed_candidate_inventory
    validate_services
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
    local action35ae_target
    local action35ae_release_source
    local action35ae_restore_failed=0

    "$systemctl_command" stop keepalived.service || action35ae_restore_failed=1

    if [[ "$node_role" = node-b ]]; then
        restore_retained_node_b_entry || action35ae_restore_failed=1
        restore_target "$legacy_lighttpd_helper" || action35ae_restore_failed=1
    else
        restore_node_a_quarantine || action35ae_restore_failed=1
    fi

    for action35ae_target in \
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
        restore_target "$action35ae_target" || action35ae_restore_failed=1
    done
    "$systemctl_command" disable --now caddy-pihole-web-health.timer \
        >/dev/null 2>&1 || :
    for action35ae_target in \
        /run/caddy-serving-health/dns/status \
        /run/caddy-serving-health/proxy/status \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV4 \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV6; do
        action35ae_target=$(effective_path "$action35ae_target")
        if [[ -e "$action35ae_target" || -L "$action35ae_target" ]]; then
            if [[ "$action35ae_target" = */keepalived/* ]]; then
                if [[ -f "$action35ae_target" && ! -L "$action35ae_target" &&
                    "$(stat -c '%U:%G:%a' "$action35ae_target")" = root:root:644 &&
                    "$(wc -l <"$action35ae_target")" -eq 1 ]] &&
                    grep -Eq '^[A-Z_]{1,32}$' "$action35ae_target"; then
                    rm -f -- "$action35ae_target" || action35ae_restore_failed=1
                else
                    action35ae_restore_failed=1
                fi
            elif [[ -f "$action35ae_target" && ! -L "$action35ae_target" &&
                "$(stat -c '%a' "$action35ae_target")" = 644 ]] &&
                grep -Fxq 'schema=caddy-serving-health-status/v1' "$action35ae_target"; then
                rm -f -- "$action35ae_target" || action35ae_restore_failed=1
            else
                action35ae_restore_failed=1
            fi
        fi
    done
    rmdir "$(effective_path /run/caddy-serving-health/dns)" \
        "$(effective_path /run/caddy-serving-health/proxy)" \
        "$(effective_path /run/caddy-serving-health/keepalived)" \
        "$(effective_path /run/caddy-serving-health)" 2>/dev/null || {
        [[ ! -d "$(effective_path /run/caddy-serving-health)" ]] ||
            action35ae_restore_failed=1
    }
    "$systemctl_command" daemon-reload || action35ae_restore_failed=1
    if [[ -n "$target_root" ]]; then
        action35ae_target=$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)
        if [[ -f "$action35ae_target" && ! -L "$action35ae_target" ]]; then
            "$unbound_checkconf_command" "$action35ae_target" || action35ae_restore_failed=1
        fi
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf || action35ae_restore_failed=1
    fi
    "$systemctl_command" reload unbound.service || action35ae_restore_failed=1
    "$systemctl_command" start keepalived.service || action35ae_restore_failed=1
    if [[ -z "$target_root" && "$node_role" = node-a &&
        "$(current_revision)" = "$serving_revision" ]]; then
        ln -sfn "$releases_root/$node_a_revision" /etc/caddy/current.rollback
        mv -Tf /etc/caddy/current.rollback /etc/caddy/current
        "$systemctl_command" reload caddy.service || action35ae_restore_failed=1
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$releases_root/$serving_revision" ]]; then
        action35ae_release_source=$outgoing_root/$serving_revision
        if [[ -d "$evidence_root/consumed-outbound" ]]; then
            action35ae_release_source=$evidence_root/consumed-outbound
        fi
        if [[ -d "$action35ae_release_source" ]] &&
            diff -qr --exclude=.complete "$action35ae_release_source" \
                "$releases_root/$serving_revision" >/dev/null; then
            rm -rf -- "${releases_root:?}/${serving_revision:?}"
        else
            action35ae_restore_failed=1
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$evidence_root/consumed-outbound" &&
        ! -e "$outgoing_root/$serving_revision" ]]; then
        mv -- "$evidence_root/consumed-outbound" \
            "$outgoing_root/$serving_revision" || action35ae_restore_failed=1
    fi
    if [[ -z "$target_root" ]]; then
        capture_command journal_rollback "$journalctl_command" --no-pager -o short-iso-precise \
            --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
            -t keepalived-notify -t caddy-ha-health || :
    fi
    [[ "$action35ae_restore_failed" -eq 0 ]]
}

consume_outbound() {
    local action35ae_source=$outgoing_root/$serving_revision
    local action35ae_destination=$evidence_root/consumed-outbound

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    validate_installed_release
    require consumed_backup_absent test ! -e "$action35ae_destination"
    # The child Bash expands its positional parameters.
    # shellcheck disable=SC2016
    require installed_and_outbound_equal \
        /bin/bash -c 'diff -qr --exclude=.complete "$1" "$2" >/dev/null' \
        _ "$action35ae_source" "$releases_root/$serving_revision"
    local action35ae_consume_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$action35ae_source" "$action35ae_destination" || action35ae_consume_status=$?
    "$systemctl_command" start caddy-lsyncd.service || action35ae_consume_status=125
    [[ "$action35ae_consume_status" -eq 0 ]] || return "$action35ae_consume_status"
    require outbound_consumed test ! -e "$action35ae_source"
}

produce_bounded_evidence() {
    capture_command payload_identity sha256sum \
        "$payload_root/manifests/serving-health-production.tsv"
}

ownership_sample() {
    local action35ae_ipv4_state action35ae_ipv6_state action35ae_addresses
    local action35ae_expected_state action35ae_expected_vips
    local action35ae_vip_count action35ae_attempt action35ae_stable=0
    local action35ae_sample_valid

    action35ae_expected_state=Backup
    action35ae_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        action35ae_expected_state=Master
        action35ae_expected_vips=4
    fi
    : >"$evidence_root/ownership-samples.tsv"
    chmod 0600 "$evidence_root/ownership-samples.tsv"
    for ((action35ae_attempt = 1; action35ae_attempt <= ownership_attempts; action35ae_attempt++)); do
        action35ae_ipv4_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        action35ae_ipv6_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        action35ae_addresses=$("$ip_command" -o address show dev eth0)
        action35ae_vip_count=0
        grep -Fq ' 10.1.0.55/22 ' <<<"$action35ae_addresses" && action35ae_vip_count=$((action35ae_vip_count + 1))
        grep -Fq ' 10.1.0.56/22 ' <<<"$action35ae_addresses" && action35ae_vip_count=$((action35ae_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$action35ae_addresses" && action35ae_vip_count=$((action35ae_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$action35ae_addresses" && action35ae_vip_count=$((action35ae_vip_count + 1))
        printf '%s\t%s\t%s\t%s\t%s\n' "$action35ae_attempt" \
            "$($date_command -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
            "$action35ae_ipv4_state" "$action35ae_ipv6_state" "$action35ae_vip_count" \
            >>"$evidence_root/ownership-samples.tsv"

        action35ae_sample_valid=false
        if [[ "$action35ae_ipv4_state" = "$action35ae_ipv6_state" ]]; then
            case "$action35ae_ipv4_state:$action35ae_vip_count" in
                "$action35ae_expected_state:$action35ae_expected_vips")
                    action35ae_sample_valid=true
                    action35ae_stable=$((action35ae_stable + 1))
                    ;;
                Fault:0 | Backup:0)
                    action35ae_stable=0
                    ;;
                *)
                    require ownership_incorrect_state false
                    ;;
            esac
        else
            require ownership_split_family false
        fi
        if [[ "$action35ae_sample_valid" = true &&
            "$action35ae_stable" -ge "$ownership_stable_samples" ]]; then
            printf 'ipv4=%s\nipv6=%s\nshared_vips=%s\nstable_samples=%s\n' \
                "$action35ae_ipv4_state" "$action35ae_ipv6_state" \
                "$action35ae_vip_count" "$action35ae_stable"
            require ownership_ipv4 test "$action35ae_ipv4_state" = "$action35ae_expected_state"
            require ownership_ipv6 test "$action35ae_ipv6_state" = "$action35ae_expected_state"
            require ownership_vips test "$action35ae_vip_count" -eq "$action35ae_expected_vips"
            require ownership_stable test "$action35ae_stable" -ge "$ownership_stable_samples"
            return 0
        fi
        "$sleep_command" "$ownership_sample_delay"
    done
    require ownership_convergence false
}

capture_journal_cursor() {
    local action35ae_cursor

    capture_command journal_cursor_raw "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    action35ae_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal_cursor_raw.stdout")
    require journal_cursor_exact test -n "$action35ae_cursor"
    printf '%s\n' "$action35ae_cursor" >"$evidence_root/journal.cursor"
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
    local action35ae_sampler=$evidence_root/availability-sampler.sh

    require sampler_pid_absent test ! -e "$evidence_root/availability.pid"
    cat >"$action35ae_sampler" <<'SAMPLER'
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
    chmod 0700 "$action35ae_sampler"
    : >"$evidence_root/availability.tsv"
    chmod 0600 "$evidence_root/availability.tsv"
    nohup /bin/bash "$action35ae_sampler" "$node_role" "$evidence_root" \
        >"$evidence_root/availability.stdout" \
        2>"$evidence_root/availability.stderr" &
    printf '%s\n' "$!" >"$evidence_root/availability.pid"
    chmod 0600 "$evidence_root/availability.pid"
}

stop_sampler() {
    local action35ae_pid action35ae_wait

    regular_file "$evidence_root/availability.pid"
    action35ae_pid=$(<"$evidence_root/availability.pid")
    [[ "$action35ae_pid" =~ ^[1-9][0-9]*$ ]]
    : >"$evidence_root/availability.stop"
    for ((action35ae_wait = 0; action35ae_wait < 10; action35ae_wait++)); do
        kill -0 "$action35ae_pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$action35ae_pid" 2>/dev/null; then
        kill "$action35ae_pid"
        wait "$action35ae_pid" 2>/dev/null || :
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
    local action35ae_scenario=$1
    local action35ae_expectation=$2
    local action35ae_status=$3
    local action35ae_expected=$4
    local action35ae_observed=$5
    local action35ae_raw=$6
    local action35ae_decision=$7
    local action35ae_raw_hash

    action35ae_raw_hash=$(sha256sum "$action35ae_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action35ae_scenario" "$action35ae_expectation" "$action35ae_status" \
        "$action35ae_expected" "$action35ae_observed" "$action35ae_raw_hash" \
        >"$action35ae_decision"
    chmod 0600 "$action35ae_raw" "$action35ae_decision"
}

production_path_test_node_a_quarantine() {
    local action35ae_test_root=$1
    local action35ae_repo_root=$2
    local action35ae_state_root=$3
    local action35ae_payload=$4
    local action35ae_evidence=$5
    local action35ae_test_target=$6
    local action35ae_systemctl=$7
    local action35ae_contract=$action35ae_test_root/node-a-quarantine-contract.tsv
    local action35ae_candidate action35ae_name action35ae_revision action35ae_source
    local action35ae_release_hash action35ae_payload_hash action35ae_raw action35ae_decision
    local action35ae_status action35ae_saved action35ae_first

    chmod -R u+rwX -- "$action35ae_state_root/quarantine"
    rm -rf -- "$action35ae_state_root/quarantine"
    install -d -m 0750 "$action35ae_state_root/quarantine"
    : >"$action35ae_contract"
    while IFS=$'\t' read -r action35ae_name action35ae_revision action35ae_source; do
        action35ae_candidate=$action35ae_state_root/quarantine/$action35ae_name
        install -d -m 0750 "$action35ae_candidate"
        printf 'payload for %s\n' "$action35ae_revision" >"$action35ae_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"%s","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35ae_revision" "$action35ae_source" \
            >"$action35ae_candidate/release-manifest.json"
        (
            cd "$action35ae_candidate"
            find . -type f \
                ! -path ./manifest.sha256 \
                ! -path ./.finalize-request \
                ! -path ./.complete \
                ! -path ./.complete.pending \
                -print0 |
                LC_ALL=C sort -z |
                xargs -0 sha256sum
        ) >"$action35ae_candidate/manifest.sha256"
        : >"$action35ae_candidate/.finalize-request"
        if [[ "$action35ae_source" = node-b ]]; then
            : >"$action35ae_candidate/.complete"
        fi
        chmod 0440 "$action35ae_candidate"/* "$action35ae_candidate"/.[!.]*
        chmod 0550 "$action35ae_candidate"
        action35ae_release_hash=$(sha256sum "$action35ae_candidate/release-manifest.json" | awk '{ print $1 }')
        action35ae_payload_hash=$(sha256sum "$action35ae_candidate/manifest.sha256" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$action35ae_name" "$action35ae_revision" \
            "$action35ae_source" "$action35ae_release_hash" "$action35ae_payload_hash" \
            >>"$action35ae_contract"
    done <<'CONTRACT'
node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	node-b
node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	node-b
node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d	20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63	node-a
node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d	action17p-node-a-to-node-b-bootstrap	node-a
CONTRACT
    chmod 0600 "$action35ae_contract"

    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-baseline.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-baseline.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    write_decision node-a-quarantine-baseline accept 0 exact-four exact-four \
        "$action35ae_raw" "$action35ae_decision"

    install -d -m 0550 "$action35ae_state_root/quarantine/unexpected"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-extra-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-extra-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-a-quarantine-extra-rejection reject "$action35ae_status" \
        exact-four extra-entry "$action35ae_raw" "$action35ae_decision"
    rmdir "$action35ae_state_root/quarantine/unexpected"

    action35ae_first=$(awk -F '\t' 'NR == 1 { print $1 }' "$action35ae_contract")
    action35ae_candidate=$action35ae_state_root/quarantine/$action35ae_first
    chmod 0750 "$action35ae_candidate"
    chmod 0640 "$action35ae_candidate/Caddyfile"
    printf 'changed\n' >>"$action35ae_candidate/Caddyfile"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-changed-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-changed-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-a-quarantine-changed-rejection reject "$action35ae_status" \
        manifest-valid changed-payload "$action35ae_raw" "$action35ae_decision"
    sed -i '$d' "$action35ae_candidate/Caddyfile"
    chmod 0440 "$action35ae_candidate/Caddyfile"
    chmod 0550 "$action35ae_candidate"

    action35ae_saved=$action35ae_test_root/node-a-release-manifest.saved
    install -m 0600 "$action35ae_candidate/release-manifest.json" "$action35ae_saved"
    chmod 0750 "$action35ae_candidate"
    chmod 0640 "$action35ae_candidate/release-manifest.json"
    printf '{\n' >"$action35ae_candidate/release-manifest.json"
    chmod 0440 "$action35ae_candidate/release-manifest.json"
    chmod 0550 "$action35ae_candidate"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-malformed-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-malformed-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-a-quarantine-malformed-rejection reject "$action35ae_status" \
        exact-release-manifest malformed "$action35ae_raw" "$action35ae_decision"
    chmod 0750 "$action35ae_candidate"
    install -m 0440 "$action35ae_saved" "$action35ae_candidate/release-manifest.json"

    mv "$action35ae_candidate/Caddyfile" "$action35ae_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35ae_candidate/Caddyfile"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-symlink-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-symlink-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-a-quarantine-symlink-rejection reject "$action35ae_status" \
        regular-file symlink "$action35ae_raw" "$action35ae_decision"
    rm "$action35ae_candidate/Caddyfile"
    mv "$action35ae_candidate/Caddyfile.saved" "$action35ae_candidate/Caddyfile"
    chmod 0550 "$action35ae_candidate"

    rm "$action35ae_test_target/etc/caddy/current"
    ln -s "$action35ae_candidate" "$action35ae_test_target/etc/caddy/current"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-reference-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-reference-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-a-quarantine-reference-rejection reject "$action35ae_status" \
        unreferenced active-reference "$action35ae_raw" "$action35ae_decision"
    rm "$action35ae_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35ae_test_target/etc/caddy/current"

    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-disposition.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-disposition.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-disposition node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    write_decision node-a-quarantine-disposition accept 0 empty empty \
        "$action35ae_raw" "$action35ae_decision"
    action35ae_raw=$action35ae_test_root/raw/node-a-quarantine-rollback.txt
    action35ae_decision=$action35ae_test_root/decisions/node-a-quarantine-rollback.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_NODE_A_QUARANTINE_CONTRACT=$action35ae_contract \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        node-a-quarantine-rollback node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    write_decision node-a-quarantine-rollback accept 0 exact-four exact-four \
        "$action35ae_raw" "$action35ae_decision"
}

production_path_test() {
    local action35ae_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local action35ae_repo_root action35ae_inventory action35ae_key action35ae_repository
    local action35ae_source action35ae_target action35ae_inventory_node action35ae_source_hash
    local action35ae_deployed_hash action35ae_accepted action35ae_lifecycle action35ae_source_path
    local action35ae_observed action35ae_raw action35ae_decision action35ae_status
    local action35ae_state_root action35ae_payload action35ae_evidence action35ae_candidate
    local action35ae_release_hash action35ae_payload_hash action35ae_systemctl
    local action35ae_marker action35ae_marker_label action35ae_quarantine_manifest
    local action35ae_quarantine_name action35ae_quarantine_candidate
    local action35ae_test_target action35ae_saved_hash action35ae_missing_candidate
    local action35ae_saved_manifest
    local action35ae_promotion_root action35ae_promotion_payload
    local action35ae_promotion_evidence action35ae_promotion_target
    local action35ae_promotion_candidate action35ae_promotion_manifest_hash
    local action35ae_runuser action35ae_finalizer action35ae_dig action35ae_curl
    local action35ae_ss action35ae_unbound_checkconf action35ae_current_before
    local action35ae_current_after action35ae_phase_root action35ae_phase_status_file
    local action35ae_phase_helper action35ae_phase_observed

    action35ae_write_quarantine_manifest() {
        local action35ae_fixture_root=$1
        local action35ae_fixture_manifest=$2
        local action35ae_fixture_path action35ae_fixture_relative
        local action35ae_fixture_encoded action35ae_fixture_type
        local action35ae_fixture_metadata action35ae_fixture_hash

        printf '# path-b64\ttype\tmetadata\tsha256\n' >"$action35ae_fixture_manifest"
        while IFS= read -r -d '' action35ae_fixture_path; do
            action35ae_fixture_relative=${action35ae_fixture_path#"$action35ae_fixture_root"/}
            action35ae_fixture_encoded=$(printf '%s' "$action35ae_fixture_relative" | base64 -w 0)
            if [[ -d "$action35ae_fixture_path" && ! -L "$action35ae_fixture_path" ]]; then
                action35ae_fixture_type=directory
                action35ae_fixture_hash=-
            elif [[ -f "$action35ae_fixture_path" && ! -L "$action35ae_fixture_path" ]]; then
                if [[ -s "$action35ae_fixture_path" ]]; then
                    action35ae_fixture_type='regular file'
                else
                    action35ae_fixture_type='regular empty file'
                fi
                action35ae_fixture_hash=$(sha256sum "$action35ae_fixture_path" | awk '{ print $1 }')
            else
                return 1
            fi
            action35ae_fixture_metadata=$(stat -c '%U:%G:%a' "$action35ae_fixture_path")
            printf '%s\t%s\t%s\t%s\n' "$action35ae_fixture_encoded" \
                "$action35ae_fixture_type" "$action35ae_fixture_metadata" \
                "$action35ae_fixture_hash" >>"$action35ae_fixture_manifest"
        done < <(find "$action35ae_fixture_root" -mindepth 1 -print0 | LC_ALL=C sort -z)
    }

    [[ "$action35ae_test_root" = /tmp/* && -d "$action35ae_test_root" && ! -L "$action35ae_test_root" ]]
    chmod 0700 "$action35ae_test_root"
    install -d -m 0700 "$action35ae_test_root/raw" "$action35ae_test_root/decisions"
    if [[ -n "${ACTION35AE_TEST_REPOSITORY_ROOT:-}" ]]; then
        action35ae_repo_root=$ACTION35AE_TEST_REPOSITORY_ROOT
    else
        action35ae_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    fi
    action35ae_inventory=$action35ae_repo_root/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r action35ae_key action35ae_repository action35ae_source \
        action35ae_target action35ae_inventory_node action35ae_source_hash \
        action35ae_deployed_hash action35ae_accepted action35ae_lifecycle; do
        [[ "$action35ae_key" = '# key' ]] && continue
        action35ae_raw=$action35ae_test_root/raw/inventory-$action35ae_key.txt
        action35ae_decision=$action35ae_test_root/decisions/inventory-$action35ae_key.tsv
        if [[ "$action35ae_repository" = runtime-generated ]]; then
            printf '%s\t%s\t%s\n' "$action35ae_key" "$action35ae_target" \
                "$action35ae_deployed_hash" >"$action35ae_raw"
            action35ae_observed=$(awk -F '\t' '{ print $3 }' "$action35ae_raw")
            require_equal "production_inventory_${action35ae_key}" \
                "$action35ae_deployed_hash" "$action35ae_observed"
            write_decision "inventory-$action35ae_key" accept 0 \
                "$action35ae_deployed_hash" "$action35ae_observed" \
                "$action35ae_raw" "$action35ae_decision"
            continue
        fi
        action35ae_source_path=${action35ae_repo_root%/homelab-server-configs}/$action35ae_repository/$action35ae_source
        sha256sum "$action35ae_source_path" >"$action35ae_raw"
        action35ae_observed=$(awk '{ print $1 }' "$action35ae_raw")
        require_equal "production_inventory_${action35ae_key}" \
            "$action35ae_source_hash" "$action35ae_observed"
        write_decision "inventory-$action35ae_key" accept 0 \
            "$action35ae_source_hash" "$action35ae_observed" \
            "$action35ae_raw" "$action35ae_decision"
    done <"$action35ae_inventory"

    action35ae_state_root=$action35ae_test_root/state
    action35ae_payload=$(mktemp -d /tmp/caddy-action35ae-production-payload.XXXXXX)
    action35ae_evidence=$(mktemp -d /tmp/caddy-action35ae-production-evidence.XXXXXX)
    action35ae_candidate=$action35ae_state_root/incoming/node-a/$retained_name
    action35ae_systemctl=$action35ae_test_root/systemctl
    install -d -m 0700 "$action35ae_candidate" \
        "$action35ae_state_root/outgoing" \
        "$action35ae_state_root/releases" "$action35ae_payload/manifests" \
        "$action35ae_evidence"
    install -d -m 0750 "$action35ae_state_root/quarantine"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$action35ae_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$action35ae_repo_root/Caddy/manifests/action35ae-node-b-quarantine.tsv" \
        "$action35ae_payload/manifests/action35ae-node-b-quarantine.tsv"
    printf 'payload\n' >"$action35ae_candidate/Caddyfile"
    printf '%s  Caddyfile\n' "$(sha256sum "$action35ae_candidate/Caddyfile" | awk '{ print $1 }')" \
        >"$action35ae_candidate/manifest.sha256"
    printf '{"revision":"%s","source_node":"node-a"}\n' "$retained_name" \
        >"$action35ae_candidate/release-manifest.json"
    chmod 0500 "$action35ae_candidate"
    while IFS= read -r action35ae_quarantine_name; do
        action35ae_quarantine_candidate=$action35ae_state_root/quarantine/$action35ae_quarantine_name
        install -d -m 0750 "$action35ae_quarantine_candidate"
        printf 'payload for %s\n' "$action35ae_quarantine_name" \
            >"$action35ae_quarantine_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$action35ae_quarantine_name" \
            >"$action35ae_quarantine_candidate/release-manifest.json"
        {
            printf '%s  Caddyfile\n' \
                "$(sha256sum "$action35ae_quarantine_candidate/Caddyfile" | awk '{ print $1 }')"
            printf '%s  release-manifest.json\n' \
                "$(sha256sum "$action35ae_quarantine_candidate/release-manifest.json" | awk '{ print $1 }')"
        } >"$action35ae_quarantine_candidate/manifest.sha256"
        chmod 0440 "$action35ae_quarantine_candidate/"*
        case "$action35ae_quarantine_name" in
            node-a-action17p-* | node-a-action33k-*)
                : >"$action35ae_quarantine_candidate/.complete"
                : >"$action35ae_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35ae_quarantine_candidate/.complete" \
                    "$action35ae_quarantine_candidate/.finalize-request"
                ;;
            *)
                : >"$action35ae_quarantine_candidate/.finalize-request"
                chmod 0440 "$action35ae_quarantine_candidate/.finalize-request"
                ;;
        esac
        chmod 0550 "$action35ae_quarantine_candidate"
    done < <(quarantine_names)
    action35ae_quarantine_manifest=$action35ae_test_root/quarantine-inventory.tsv
    action35ae_write_quarantine_manifest "$action35ae_state_root/quarantine" \
        "$action35ae_quarantine_manifest"
    action35ae_test_target=$action35ae_test_root/target
    install -d -m 0700 "$action35ae_test_target/etc/caddy/releases/current-test"
    ln -s releases/current-test "$action35ae_test_target/etc/caddy/current"
    install -d -m 0755 "$action35ae_test_target/usr/local/libexec"
    install -m 0755 "$action35ae_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35ae_test_target$legacy_lighttpd_helper"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-node-b-baseline.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-node-b-baseline.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    write_decision legacy-helper-node-b-baseline accept 0 exact-legacy exact-legacy \
        "$action35ae_raw" "$action35ae_decision"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-removal.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-removal.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-remove node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    path_absent "$action35ae_test_target$legacy_lighttpd_helper"
    write_decision legacy-helper-removal accept 0 absent absent \
        "$action35ae_raw" "$action35ae_decision"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-rollback.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-rollback.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-rollback node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    require_equal production_test_legacy_helper_restored "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$action35ae_test_target$legacy_lighttpd_helper" | awk '{ print $1 }')"
    write_decision legacy-helper-rollback accept 0 exact-legacy exact-legacy \
        "$action35ae_raw" "$action35ae_decision"
    rm -f -- "$action35ae_test_target$legacy_lighttpd_helper"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-node-a-baseline.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-node-a-baseline.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw"
    write_decision legacy-helper-node-a-baseline accept 0 absent absent \
        "$action35ae_raw" "$action35ae_decision"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-node-b-absent-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-node-b-absent-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision legacy-helper-node-b-absent-rejection reject "$action35ae_status" \
        exact-legacy absent "$action35ae_raw" "$action35ae_decision"
    install -m 0755 "$action35ae_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$action35ae_test_target$legacy_lighttpd_helper"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-node-a-present-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-node-a-present-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-check node-a "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision legacy-helper-node-a-present-rejection reject "$action35ae_status" \
        absent present "$action35ae_raw" "$action35ae_decision"
    rm -f -- "$action35ae_test_target$legacy_lighttpd_helper"
    ln -s /dev/null "$action35ae_test_target$legacy_lighttpd_helper"
    action35ae_raw=$action35ae_test_root/raw/legacy-helper-node-b-symlink-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/legacy-helper-node-b-symlink-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        legacy-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision legacy-helper-node-b-symlink-rejection reject "$action35ae_status" \
        regular-file symlink "$action35ae_raw" "$action35ae_decision"
    rm -f -- "$action35ae_test_target$legacy_lighttpd_helper"
    action35ae_release_hash=$(sha256sum "$action35ae_candidate/release-manifest.json" | awk '{ print $1 }')
    action35ae_payload_hash=$(sha256sum "$action35ae_candidate/manifest.sha256" | awk '{ print $1 }')
    cat >"$action35ae_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35AE_SYSTEMCTL_CALLS:?}"
SYSTEMCTL
    chmod 0700 "$action35ae_systemctl"
    : >"$action35ae_test_root/systemctl.calls"
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256=$action35ae_release_hash \
        ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35ae_payload_hash \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        retained-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_test_root/retained-check.stdout"
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_test_root/quarantine-check.stdout"
    install -d -m 0550 "$action35ae_state_root/quarantine/unexpected"
    action35ae_raw=$action35ae_test_root/raw/quarantine-extra-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-extra-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-extra-rejection reject "$action35ae_status" \
        exact-four-entries extra-entry "$action35ae_raw" "$action35ae_decision"
    rmdir "$action35ae_state_root/quarantine/unexpected"
    action35ae_quarantine_candidate=$action35ae_state_root/quarantine/$(quarantine_names | sed -n '1p')
    action35ae_saved_hash=$(sha256sum "$action35ae_quarantine_candidate/Caddyfile" | awk '{ print $1 }')
    chmod 0750 "$action35ae_quarantine_candidate"
    chmod 0640 "$action35ae_quarantine_candidate/Caddyfile"
    printf 'changed\n' >>"$action35ae_quarantine_candidate/Caddyfile"
    action35ae_raw=$action35ae_test_root/raw/quarantine-changed-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-changed-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-changed-rejection reject "$action35ae_status" \
        exact-captured-hash changed-hash "$action35ae_raw" "$action35ae_decision"
    sed -i '$d' "$action35ae_quarantine_candidate/Caddyfile"
    chmod 0440 "$action35ae_quarantine_candidate/Caddyfile"
    [[ "$(sha256sum "$action35ae_quarantine_candidate/Caddyfile" | awk '{ print $1 }')" = "$action35ae_saved_hash" ]]
    mv "$action35ae_quarantine_candidate/Caddyfile" \
        "$action35ae_quarantine_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$action35ae_quarantine_candidate/Caddyfile"
    action35ae_raw=$action35ae_test_root/raw/quarantine-symlink-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-symlink-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-symlink-rejection reject "$action35ae_status" \
        regular-file symlink "$action35ae_raw" "$action35ae_decision"
    rm "$action35ae_quarantine_candidate/Caddyfile"
    mv "$action35ae_quarantine_candidate/Caddyfile.saved" \
        "$action35ae_quarantine_candidate/Caddyfile"
    chmod 0550 "$action35ae_quarantine_candidate"
    action35ae_missing_candidate=$action35ae_test_root/missing-quarantine-candidate
    chmod 0750 "$action35ae_quarantine_candidate"
    mv "$action35ae_quarantine_candidate" "$action35ae_missing_candidate"
    action35ae_raw=$action35ae_test_root/raw/quarantine-missing-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-missing-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-missing-rejection reject "$action35ae_status" \
        exact-four-entries missing-entry "$action35ae_raw" "$action35ae_decision"
    mv "$action35ae_missing_candidate" "$action35ae_quarantine_candidate"
    chmod 0550 "$action35ae_quarantine_candidate"
    action35ae_saved_manifest=$action35ae_test_root/release-manifest.saved
    install -m 0600 "$action35ae_quarantine_candidate/release-manifest.json" \
        "$action35ae_saved_manifest"
    chmod 0750 "$action35ae_quarantine_candidate"
    chmod 0640 "$action35ae_quarantine_candidate/release-manifest.json"
    printf '{\n' >"$action35ae_quarantine_candidate/release-manifest.json"
    action35ae_write_quarantine_manifest "$action35ae_state_root/quarantine" \
        "$action35ae_quarantine_manifest"
    action35ae_raw=$action35ae_test_root/raw/quarantine-malformed-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-malformed-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-malformed-rejection reject "$action35ae_status" \
        valid-release-json malformed-json "$action35ae_raw" "$action35ae_decision"
    install -m 0440 "$action35ae_saved_manifest" \
        "$action35ae_quarantine_candidate/release-manifest.json"
    chmod 0550 "$action35ae_quarantine_candidate"
    action35ae_write_quarantine_manifest "$action35ae_state_root/quarantine" \
        "$action35ae_quarantine_manifest"
    rm "$action35ae_test_target/etc/caddy/current"
    ln -s "$action35ae_quarantine_candidate" \
        "$action35ae_test_target/etc/caddy/current"
    action35ae_raw=$action35ae_test_root/raw/quarantine-reference-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/quarantine-reference-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        quarantine-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        return 1
    else
        action35ae_status=$?
    fi
    write_decision quarantine-reference-rejection reject "$action35ae_status" \
        unreferenced active-reference "$action35ae_raw" "$action35ae_decision"
    rm "$action35ae_test_target/etc/caddy/current"
    ln -s releases/current-test "$action35ae_test_target/etc/caddy/current"
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256=$action35ae_release_hash \
        ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35ae_payload_hash \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        retained-disposition node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_test_root/retained-disposition.stdout"
    [[ ! -e "$action35ae_candidate" && -d "$action35ae_evidence/retained-incoming" ]]
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256=$action35ae_release_hash \
        ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35ae_payload_hash \
        ACTION35AE_QUARANTINE_INVENTORY_MANIFEST=$action35ae_quarantine_manifest \
        ACTION35AE_TARGET_ROOT=$action35ae_test_target \
        ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        retained-rollback node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_test_root/retained-rollback.stdout"
    [[ -d "$action35ae_candidate" && ! -e "$action35ae_evidence/retained-incoming" ]]

    action35ae_raw=$action35ae_test_root/raw/transaction-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/transaction-rejection.tsv
    install -d -m 0700 "$action35ae_state_root/incoming/node-a/unexpected"
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
        ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
        ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
        ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
        ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256=$action35ae_release_hash \
        ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35ae_payload_hash \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        retained-check node-b "$action35ae_payload" "$action35ae_evidence" \
        >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision transaction-rejection reject "$action35ae_status" exact-retained-only \
        unexpected-sibling "$action35ae_raw" "$action35ae_decision"
    rmdir "$action35ae_state_root/incoming/node-a/unexpected"

    for action35ae_marker in .finalize-request .complete.pending .complete; do
        action35ae_marker_label=${action35ae_marker#.}
        action35ae_marker_label=${action35ae_marker_label//./-}
        chmod 0700 "$action35ae_candidate"
        : >"$action35ae_candidate/$action35ae_marker"
        chmod 0500 "$action35ae_candidate"
        action35ae_raw=$action35ae_test_root/raw/transaction-marker-$action35ae_marker_label-rejection.txt
        action35ae_decision=$action35ae_test_root/decisions/transaction-marker-$action35ae_marker_label-rejection.tsv
        if ACTION35AE_PRODUCTION_PATH_TEST=1 \
            ACTION35AE_INCOMING_ROOT=$action35ae_state_root/incoming \
            ACTION35AE_OUTGOING_ROOT=$action35ae_state_root/outgoing \
            ACTION35AE_QUARANTINE_ROOT=$action35ae_state_root/quarantine \
            ACTION35AE_RELEASES_ROOT=$action35ae_state_root/releases \
            ACTION35AE_RETAINED_RELEASE_MANIFEST_SHA256=$action35ae_release_hash \
            ACTION35AE_RETAINED_PAYLOAD_MANIFEST_SHA256=$action35ae_payload_hash \
            /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
            retained-check node-b "$action35ae_payload" "$action35ae_evidence" \
            >"$action35ae_raw" 2>&1; then
            action35ae_status=0
        else
            action35ae_status=$?
        fi
        write_decision "transaction-marker-$action35ae_marker_label-rejection" reject \
            "$action35ae_status" absent present "$action35ae_raw" "$action35ae_decision"
        chmod 0700 "$action35ae_candidate"
        rm -f -- "$action35ae_candidate/$action35ae_marker"
        chmod 0500 "$action35ae_candidate"
    done

    action35ae_raw=$action35ae_test_root/raw/transaction-acceptance.txt
    action35ae_decision=$action35ae_test_root/decisions/transaction-acceptance.tsv
    {
        cat "$action35ae_test_root/retained-check.stdout"
        cat "$action35ae_test_root/quarantine-check.stdout"
        cat "$action35ae_test_root/retained-disposition.stdout"
        cat "$action35ae_test_root/retained-rollback.stdout"
        cat "$action35ae_test_root/systemctl.calls"
        find "$action35ae_state_root/incoming/node-a" -mindepth 1 -maxdepth 1 \
            -printf '%f\t%y\t%u:%g:%m\n' | LC_ALL=C sort
    } >"$action35ae_raw"
    write_decision transaction-acceptance reach 0 retained-restored \
        retained-restored "$action35ae_raw" "$action35ae_decision"
    production_path_test_node_a_quarantine "$action35ae_test_root" \
        "$action35ae_repo_root" "$action35ae_state_root" "$action35ae_payload" \
        "$action35ae_evidence" "$action35ae_test_target" "$action35ae_systemctl"

    action35ae_promotion_root=$action35ae_test_root/promotion
    action35ae_promotion_payload=$(mktemp -d /tmp/caddy-action35ae-promotion-payload.XXXXXX)
    action35ae_promotion_evidence=$(mktemp -d /tmp/caddy-action35ae-promotion-evidence.XXXXXX)
    action35ae_promotion_target=$action35ae_promotion_root/target
    action35ae_promotion_candidate=$action35ae_promotion_root/outgoing/$serving_revision
    install -d -m 0700 "$action35ae_promotion_root/incoming" \
        "$action35ae_promotion_root/releases" "$action35ae_promotion_candidate" \
        "$action35ae_promotion_target/etc/caddy/releases/$node_a_revision" \
        "$action35ae_promotion_target/etc/default" \
        "$action35ae_promotion_payload/manifests" \
        "$action35ae_promotion_payload/repositories"
    printf '{"revision":"%s"}\n' "$node_a_revision" \
        >"$action35ae_promotion_target/etc/caddy/releases/$node_a_revision/release-manifest.json"
    ln -s "releases/$node_a_revision" "$action35ae_promotion_target/etc/caddy/current"
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$action35ae_promotion_target/etc/default/caddy-ha"
    install -m 0600 "$action35ae_repo_root/Caddy/manifests/serving-health-production.tsv" \
        "$action35ae_promotion_payload/manifests/serving-health-production.tsv"
    install -m 0600 "$action35ae_repo_root/Caddy/manifests/action35ae-node-b-quarantine.tsv" \
        "$action35ae_promotion_payload/manifests/action35ae-node-b-quarantine.tsv"
    while IFS=$'\t' read -r action35ae_repository action35ae_source _; do
        [[ "$action35ae_repository" = '# repository' ]] && continue
        action35ae_source_path=${action35ae_repo_root%/homelab-server-configs}/$action35ae_repository/$action35ae_source
        action35ae_target=$action35ae_promotion_payload/repositories/$action35ae_repository/$action35ae_source
        install -d -m 0700 "${action35ae_target%/*}"
        install -m 0600 "$action35ae_source_path" "$action35ae_target"
    done <"$action35ae_repo_root/Caddy/manifests/serving-health-production.tsv"
    printf 'respond /healthz 204\n' >"$action35ae_promotion_candidate/Caddyfile"
    printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
        "$serving_revision" "$serving_parent" \
        >"$action35ae_promotion_candidate/release-manifest.json"
    (
        cd "$action35ae_promotion_candidate"
        find . -type f ! -path ./manifest.sha256 -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action35ae_promotion_candidate/manifest.sha256"
    : >"$action35ae_promotion_candidate/.finalize-request"
    chmod 0440 "$action35ae_promotion_candidate/"*
    chmod 0550 "$action35ae_promotion_candidate"
    action35ae_promotion_manifest_hash=$(sha256sum \
        "$action35ae_promotion_candidate/manifest.sha256" | awk '{ print $1 }')

    action35ae_runuser=$action35ae_promotion_root/runuser
    action35ae_finalizer=$action35ae_promotion_root/finalizer
    action35ae_dig=$action35ae_promotion_root/dig
    action35ae_curl=$action35ae_promotion_root/curl
    action35ae_ss=$action35ae_promotion_root/ss
    action35ae_unbound_checkconf=$action35ae_promotion_root/unbound-checkconf
    cat >"$action35ae_runuser" <<'RUNUSER'
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
    >>"${ACTION35AE_TEST_RUNUSER_CALLS:?}"
exec "$@"
RUNUSER
    cat >"$action35ae_finalizer" <<'FINALIZER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source-role && "$2" = node-a ]]
candidate=${ACTION35AE_INCOMING_ROOT:?}/node-a/${ACTION35AE_TEST_SERVING_REVISION:?}
[[ -d "$candidate" && -f "$candidate/.finalize-request" ]]
printf '%s\n' "$*" >>"${ACTION35AE_TEST_FINALIZER_CALLS:?}"
chmod 0750 "$candidate"
: >"$candidate/.complete"
chmod 0440 "$candidate/.complete"
chmod 0550 "$candidate"
FINALIZER
    cat >"$action35ae_systemctl" <<'SYSTEMCTL_PROMOTION'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${ACTION35AE_SYSTEMCTL_CALLS:?}"
if [[ "$1" = start && "$2" = caddy-sync-reconcile.service ]]; then
    candidate=${ACTION35AE_INCOMING_ROOT:?}/node-a/${ACTION35AE_TEST_SERVING_REVISION:?}
    release=${ACTION35AE_RELEASES_ROOT:?}/${ACTION35AE_TEST_SERVING_REVISION:?}
    [[ -f "$candidate/.complete" ]]
    cp -a -- "$candidate" "$release"
    chmod 0750 "$release"
    rm -f -- "$release/.complete" "$release/.finalize-request"
    chmod 0550 "$release"
    rm -f -- "${ACTION35AE_TARGET_ROOT:?}/etc/caddy/current"
    ln -s "$release" "$ACTION35AE_TARGET_ROOT/etc/caddy/current"
fi
case "$1" in
    is-active) [[ "$2" = --quiet ]] ;;
    start | stop) [[ $# -eq 2 ]] ;;
    *) : ;;
esac
SYSTEMCTL_PROMOTION
    cat >"$action35ae_dig" <<'DIG'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$action35ae_curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
curl_family=ipv4
[[ " $* " = *' --ipv4 '* ]] || curl_family=ipv6
case "${ACTION35AE_TEST_CURL_MODE:-healthy}" in
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
revision=$(jq -r '.revision // empty' "${ACTION35AE_TARGET_ROOT:?}/etc/caddy/current/release-manifest.json")
if [[ "$revision" = "${ACTION35AE_TEST_SERVING_REVISION:?}" ]]; then
    printf '204\n'
else
    printf '404\n'
    exit 22
fi
CURL
    cat >"$action35ae_ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n'
SS
    cat >"$action35ae_unbound_checkconf" <<'UNBOUND'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]]
grep -Fq 'local-zone: "local.theama.co." static' "$1"
UNBOUND
    chmod 0700 "$action35ae_runuser" "$action35ae_finalizer" "$action35ae_systemctl" \
        "$action35ae_dig" "$action35ae_curl" "$action35ae_ss" "$action35ae_unbound_checkconf"
    : >"$action35ae_test_root/runuser.calls"
    : >"$action35ae_test_root/finalizer.calls"
    : >"$action35ae_test_root/systemctl.calls"
    action35ae_current_before=$(jq -r '.revision' \
        "$action35ae_promotion_target/etc/caddy/current/release-manifest.json")
    action35ae_raw=$action35ae_test_root/raw/post-promotion-sequence.txt
    action35ae_decision=$action35ae_test_root/decisions/post-promotion-sequence.tsv
    {
        printf 'current_before=%s\n' "$action35ae_current_before"
        ACTION35AE_PRODUCTION_PATH_TEST=1 \
            ACTION35AE_INCOMING_ROOT=$action35ae_promotion_root/incoming \
            ACTION35AE_OUTGOING_ROOT=$action35ae_promotion_root/outgoing \
            ACTION35AE_QUARANTINE_ROOT=$action35ae_promotion_root/quarantine \
            ACTION35AE_RELEASES_ROOT=$action35ae_promotion_root/releases \
            ACTION35AE_TARGET_ROOT=$action35ae_promotion_target \
            ACTION35AE_SERVING_PAYLOAD_MANIFEST_SHA256=$action35ae_promotion_manifest_hash \
            ACTION35AE_FINALIZER_COMMAND=$action35ae_finalizer \
            ACTION35AE_RUNUSER_COMMAND=$action35ae_runuser \
            ACTION35AE_SYNC_USER=$(id -un) ACTION35AE_SYNC_GROUP=$(id -gn) \
            ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
            ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
            ACTION35AE_TEST_RUNUSER_CALLS=$action35ae_test_root/runuser.calls \
            ACTION35AE_TEST_FINALIZER_CALLS=$action35ae_test_root/finalizer.calls \
            ACTION35AE_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
            promote node-a "$action35ae_promotion_payload" "$action35ae_promotion_evidence"
        action35ae_current_after=$(jq -r '.revision' \
            "$action35ae_promotion_target/etc/caddy/current/release-manifest.json")
        printf 'current_after=%s\n' "$action35ae_current_after"
        cat "$action35ae_test_root/runuser.calls" "$action35ae_test_root/finalizer.calls" \
            "$action35ae_test_root/systemctl.calls"
        ACTION35AE_PRODUCTION_PATH_TEST=1 \
            ACTION35AE_TARGET_ROOT=$action35ae_promotion_target \
            ACTION35AE_ENVIRONMENT_FILE=$action35ae_promotion_target/etc/default/caddy-ha \
            ACTION35AE_RUNUSER_COMMAND=$action35ae_runuser \
            ACTION35AE_SYSTEMCTL_COMMAND=$action35ae_systemctl \
            ACTION35AE_DNS_DIG_COMMAND=$action35ae_dig \
            ACTION35AE_CURL_COMMAND=$action35ae_curl \
            ACTION35AE_SS_COMMAND=$action35ae_ss \
            ACTION35AE_UNBOUND_CHECKCONF_COMMAND=$action35ae_unbound_checkconf \
            ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
            ACTION35AE_TEST_RUNUSER_CALLS=$action35ae_test_root/runuser.calls \
            ACTION35AE_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
            candidate-check node-a "$action35ae_promotion_payload" "$action35ae_promotion_evidence"
        cat "$action35ae_promotion_evidence/caddy_identity.stdout" \
            "$action35ae_promotion_evidence/caddy_identity.status"
    } >"$action35ae_raw" 2>&1
    action35ae_current_after=$(jq -r '.revision' \
        "$action35ae_promotion_target/etc/caddy/current/release-manifest.json")
    require_equal production_test_current_before "$node_a_revision" "$action35ae_current_before"
    require_equal production_test_current_after "$serving_revision" "$action35ae_current_after"
    write_decision post-promotion-sequence accept 0 "$serving_revision" \
        "$action35ae_current_after" "$action35ae_raw" "$action35ae_decision"

    action35ae_phase_root=$action35ae_test_root/helper-phase
    install -d -m 0700 "$action35ae_phase_root"
    action35ae_phase_helper=$action35ae_promotion_payload/repositories/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    action35ae_phase_status_file=$action35ae_phase_root/proxy.status
    action35ae_raw=$action35ae_test_root/raw/helper-phase-caddy-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/helper-phase-caddy-rejection.tsv
    if ACTION35AE_TARGET_ROOT=$action35ae_promotion_target \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        ACTION35AE_TEST_SERVING_REVISION=$serving_revision \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$action35ae_promotion_target/etc/default/caddy-ha \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$action35ae_curl \
        CADDY_SERVING_HEALTH_SS_COMMAND=/usr/bin/false \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        CADDY_SERVING_HEALTH_STATUS_FILE=$action35ae_phase_status_file \
        /bin/bash "$action35ae_phase_helper" \
        >"$action35ae_phase_root/proxy.stdout" \
        2>"$action35ae_phase_root/proxy.stderr"; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    cat "$action35ae_phase_root/proxy.stdout" \
        "$action35ae_phase_root/proxy.stderr" "$action35ae_phase_status_file" \
        >"$action35ae_raw"
    grep -Fxq 'check=listener-tcp-capture' "$action35ae_phase_status_file"
    grep -Fxq 'failure_class=phase-operation-failed' "$action35ae_phase_status_file"
    action35ae_phase_observed=$(awk -F= '$1 == "check" { print $2 }' \
        "$action35ae_phase_status_file")
    write_decision helper-phase-caddy-rejection reject "$action35ae_status" \
        listener-tcp-capture "$action35ae_phase_observed" \
        "$action35ae_raw" "$action35ae_decision"

    for action35ae_probe_family in ipv4 ipv6; do
        for action35ae_probe_case in missing-status malformed-status \
            missing-output malformed-output signal timeout curl http; do
            case "$action35ae_probe_case" in
                missing-status | missing-output)
                    action35ae_probe_expected=probe-result-missing
                    ;;
                malformed-status | malformed-output)
                    action35ae_probe_expected=probe-result-malformed
                    ;;
                signal) action35ae_probe_expected=signal ;;
                timeout) action35ae_probe_expected=timeout ;;
                curl) action35ae_probe_expected=connection-refusal ;;
                http) action35ae_probe_expected=unexpected-http-status ;;
            esac
            action35ae_probe_scenario=probe-result-$action35ae_probe_family-$action35ae_probe_case-rejection
            action35ae_raw=$action35ae_test_root/raw/$action35ae_probe_scenario.txt
            action35ae_decision=$action35ae_test_root/decisions/$action35ae_probe_scenario.tsv
            rm -f -- "$action35ae_phase_status_file"
            if ACTION35AE_TARGET_ROOT=$action35ae_promotion_target \
                ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
                ACTION35AE_TEST_SERVING_REVISION=$serving_revision \
                ACTION35AE_TEST_CURL_MODE=$action35ae_probe_family-$action35ae_probe_case \
                CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$action35ae_promotion_target/etc/default/caddy-ha \
                CADDY_SERVING_HEALTH_CURL_COMMAND=$action35ae_curl \
                CADDY_SERVING_HEALTH_SS_COMMAND=$action35ae_ss \
                CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$action35ae_systemctl \
                CADDY_SERVING_HEALTH_STATUS_FILE=$action35ae_phase_status_file \
                /bin/bash "$action35ae_phase_helper" \
                >"$action35ae_phase_root/$action35ae_probe_scenario.stdout" \
                2>"$action35ae_phase_root/$action35ae_probe_scenario.stderr"; then
                action35ae_status=0
            else
                action35ae_status=$?
            fi
            cat "$action35ae_phase_root/$action35ae_probe_scenario.stdout" \
                "$action35ae_phase_root/$action35ae_probe_scenario.stderr" \
                "$action35ae_phase_status_file" >"$action35ae_raw"
            action35ae_phase_observed=$(awk -F= \
                '$1 == "failure_class" { print $2 }' "$action35ae_phase_status_file")
            write_decision "$action35ae_probe_scenario" reject "$action35ae_status" \
                "$action35ae_probe_expected" "$action35ae_phase_observed" \
                "$action35ae_raw" "$action35ae_decision"
        done
    done

    action35ae_phase_helper=$action35ae_promotion_payload/repositories/homelab-dns/Keepalived/scripts/dns-check.sh
    action35ae_phase_status_file=$action35ae_phase_root/dns.status
    action35ae_raw=$action35ae_test_root/raw/helper-phase-dns-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/helper-phase-dns-rejection.tsv
    if DNS_CHECK_DIG_COMMAND=$action35ae_dig \
        DNS_CHECK_SYSTEMCTL_COMMAND=$action35ae_systemctl \
        DNS_CHECK_STATUS_FILE=$action35ae_phase_status_file \
        ACTION35AE_SYSTEMCTL_CALLS=$action35ae_test_root/systemctl.calls \
        /bin/bash "$action35ae_phase_helper" >/dev/full \
        2>"$action35ae_phase_root/dns.stderr"; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    cat "$action35ae_phase_root/dns.stderr" "$action35ae_phase_status_file" \
        >"$action35ae_raw"
    grep -Fxq 'check=probe-evidence-output' "$action35ae_phase_status_file"
    grep -Fxq 'failure_class=phase-operation-failed' "$action35ae_phase_status_file"
    action35ae_phase_observed=$(awk -F= '$1 == "check" { print $2 }' \
        "$action35ae_phase_status_file")
    write_decision helper-phase-dns-rejection reject "$action35ae_status" \
        probe-evidence-output "$action35ae_phase_observed" \
        "$action35ae_raw" "$action35ae_decision"

    action35ae_busctl=$action35ae_test_root/busctl
    action35ae_ip=$action35ae_test_root/ip
    action35ae_date=$action35ae_test_root/date
    action35ae_sleep=$action35ae_test_root/sleep
    cat >"$action35ae_busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
counter_file=${ACTION35AE_TEST_OWNERSHIP_COUNTER:?}
sequence_file=${ACTION35AE_TEST_OWNERSHIP_SEQUENCE:?}
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
    cat >"$action35ae_ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
counter=$(<"${ACTION35AE_TEST_OWNERSHIP_COUNTER:?}")
state=$(sed -n "${counter}p" "${ACTION35AE_TEST_OWNERSHIP_SEQUENCE:?}")
printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
if [[ "$state" = Master ]]; then
    printf '2: eth0    inet 10.1.0.55/22 scope global secondary eth0\n'
    printf '2: eth0    inet 10.1.0.56/22 scope global secondary eth0\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global\n'
fi
IP
    cat >"$action35ae_date" <<'DATE'
#!/usr/bin/env bash
printf '2026-08-17T00:00:00.000000000Z\n'
DATE
    cat >"$action35ae_sleep" <<'SLEEP'
#!/usr/bin/env bash
[[ "$1" =~ ^[0-9]+$ ]]
SLEEP
    chmod 0700 "$action35ae_busctl" "$action35ae_ip" "$action35ae_date" \
        "$action35ae_sleep"
    printf '0\n' >"$action35ae_test_root/ownership.counter"
    printf 'Fault\nBackup\nBackup\nBackup\n' \
        >"$action35ae_test_root/ownership.sequence"
    action35ae_raw=$action35ae_test_root/raw/bounded-node-b-convergence.txt
    action35ae_decision=$action35ae_test_root/decisions/bounded-node-b-convergence.tsv
    ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_BUSCTL_COMMAND=$action35ae_busctl \
        ACTION35AE_IP_COMMAND=$action35ae_ip \
        ACTION35AE_DATE_COMMAND=$action35ae_date \
        ACTION35AE_SLEEP_COMMAND=$action35ae_sleep \
        ACTION35AE_OWNERSHIP_ATTEMPTS=4 \
        ACTION35AE_OWNERSHIP_STABLE_SAMPLES=3 \
        ACTION35AE_OWNERSHIP_SAMPLE_DELAY=0 \
        ACTION35AE_TEST_OWNERSHIP_COUNTER=$action35ae_test_root/ownership.counter \
        ACTION35AE_TEST_OWNERSHIP_SEQUENCE=$action35ae_test_root/ownership.sequence \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        ownership node-b "$action35ae_promotion_payload" \
        "$action35ae_promotion_evidence" >"$action35ae_raw"
    write_decision bounded-node-b-convergence accept 0 \
        stable-backup-after-fault stable-backup-after-fault \
        "$action35ae_raw" "$action35ae_decision"

    printf '0\n' >"$action35ae_test_root/ownership.counter"
    printf 'Master\n' >"$action35ae_test_root/ownership.sequence"
    action35ae_raw=$action35ae_test_root/raw/node-b-master-rejection.txt
    action35ae_decision=$action35ae_test_root/decisions/node-b-master-rejection.tsv
    if ACTION35AE_PRODUCTION_PATH_TEST=1 \
        ACTION35AE_BUSCTL_COMMAND=$action35ae_busctl \
        ACTION35AE_IP_COMMAND=$action35ae_ip \
        ACTION35AE_DATE_COMMAND=$action35ae_date \
        ACTION35AE_SLEEP_COMMAND=$action35ae_sleep \
        ACTION35AE_OWNERSHIP_ATTEMPTS=1 \
        ACTION35AE_OWNERSHIP_STABLE_SAMPLES=1 \
        ACTION35AE_OWNERSHIP_SAMPLE_DELAY=0 \
        ACTION35AE_TEST_OWNERSHIP_COUNTER=$action35ae_test_root/ownership.counter \
        ACTION35AE_TEST_OWNERSHIP_SEQUENCE=$action35ae_test_root/ownership.sequence \
        /bin/bash "$action35ae_repo_root/Caddy/scripts/apply-coupled-serving-health-action35ae.sh" \
        ownership node-b "$action35ae_promotion_payload" \
        "$action35ae_promotion_evidence" >"$action35ae_raw" 2>&1; then
        action35ae_status=0
    else
        action35ae_status=$?
    fi
    write_decision node-b-master-rejection reject "$action35ae_status" \
        backup-zero-vips master-four-vips "$action35ae_raw" "$action35ae_decision"
    rm -rf -- "$action35ae_promotion_payload" "$action35ae_promotion_evidence"
    rm -rf -- "$action35ae_payload" "$action35ae_evidence"
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
