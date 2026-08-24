#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=serving_health_deployment
readonly node_a_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly serving_revision=20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca
readonly serving_parent=$node_a_revision
readonly serving_payload_manifest_sha256=${CADDY_SERVING_HEALTH_SERVING_PAYLOAD_MANIFEST_SHA256:-ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962}
readonly retained_name=action17p-node-a-to-node-b-bootstrap
readonly retained_release_manifest_sha256=${CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256:-81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3}
readonly retained_payload_manifest_sha256=${CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256:-f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8}
readonly legacy_lighttpd_helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly legacy_lighttpd_helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly incoming_root=${CADDY_SERVING_HEALTH_INCOMING_ROOT:-/var/lib/caddy-sync/incoming}
readonly outgoing_root=${CADDY_SERVING_HEALTH_OUTGOING_ROOT:-/var/lib/caddy-sync/outbound}
readonly quarantine_root=${CADDY_SERVING_HEALTH_QUARANTINE_ROOT:-/var/lib/caddy-sync/quarantine}
readonly releases_root=${CADDY_SERVING_HEALTH_RELEASES_ROOT:-/etc/caddy/releases}
readonly node_environment=${CADDY_SERVING_HEALTH_ENVIRONMENT_FILE:-/etc/default/caddy-ha}
readonly runuser_command=${CADDY_SERVING_HEALTH_RUNUSER_COMMAND:-/usr/sbin/runuser}
readonly finalizer_command=${CADDY_SERVING_HEALTH_FINALIZER_COMMAND:-/usr/local/libexec/finalize-incoming-release-v2.sh}
readonly publisher_command=${CADDY_SERVING_HEALTH_PUBLISHER_COMMAND:-/usr/local/libexec/publish-release-v2.sh}
readonly sync_user=${CADDY_SERVING_HEALTH_SYNC_USER:-caddy-sync}
readonly sync_group=${CADDY_SERVING_HEALTH_SYNC_GROUP:-caddy-sync}
readonly systemctl_command=${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}
readonly journalctl_command=${CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
readonly unbound_checkconf_command=${CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND:-/usr/sbin/unbound-checkconf}
readonly systemd_tmpfiles_command=${CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND:-/usr/bin/systemd-tmpfiles}
readonly sleep_command=${CADDY_SERVING_HEALTH_SLEEP_COMMAND:-/usr/bin/sleep}
readonly busctl_command=${CADDY_SERVING_HEALTH_BUSCTL_COMMAND:-/usr/bin/busctl}
readonly ip_command=${CADDY_SERVING_HEALTH_IP_COMMAND:-/usr/sbin/ip}
readonly date_command=${CADDY_SERVING_HEALTH_DATE_COMMAND:-/usr/bin/date}
readonly daemon_observation_attempts=${CADDY_SERVING_HEALTH_DAEMON_OBSERVATION_ATTEMPTS:-30}
readonly daemon_observation_delay=${CADDY_SERVING_HEALTH_DAEMON_OBSERVATION_DELAY:-1}
readonly ownership_attempts=${CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS:-24}
readonly ownership_stable_samples=${CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES:-3}
readonly ownership_sample_delay=${CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY:-2}
readonly target_root=${CADDY_SERVING_HEALTH_TARGET_ROOT:-}
readonly web_health_unit=/etc/systemd/system/caddy-pihole-web-health.service
readonly web_health_unit_deployed_sha256=d773cf7b88429b819a7919dbdf5e939654616c84be538ca1ebfd3d7e3ed9c3fc
readonly web_health_unit_candidate_sha256=d773cf7b88429b819a7919dbdf5e939654616c84be538ca1ebfd3d7e3ed9c3fc
readonly web_health_timer=caddy-pihole-web-health.timer
readonly web_health_service=caddy-pihole-web-health.service
readonly web_health_observation_attempts=${CADDY_SERVING_HEALTH_WEB_OBSERVATION_ATTEMPTS:-45}
readonly web_health_observation_delay=${CADDY_SERVING_HEALTH_WEB_OBSERVATION_DELAY:-1}
readonly notification_enqueue_deployed_sha256=5abad15885a9d35405f060e956828dfcca6406f447273259155b0daf23b851bf
readonly notification_enqueue_candidate_sha256=5abad15885a9d35405f060e956828dfcca6406f447273259155b0daf23b851bf
readonly notification_worker_deployed_sha256=0fbf8133e0f4ea16098c58cea424f1d4cdf475f991ec245dc3e7e5fa332fcddc
readonly notification_worker_candidate_sha256=0fbf8133e0f4ea16098c58cea424f1d4cdf475f991ec245dc3e7e5fa332fcddc
readonly notification_notifier_deployed_sha256=81d3ebb308e9b326282f60a0887376c4eb50af9cd7ac29180c5278b14abfcdc9
readonly notification_notifier_candidate_sha256=81d3ebb308e9b326282f60a0887376c4eb50af9cd7ac29180c5278b14abfcdc9
readonly notification_tmpfiles_deployed_sha256=0a6fa67671acb390e8faff5a22c44eb673767351e65d72035917470c31f550f3
readonly notification_tmpfiles_candidate_sha256=0a6fa67671acb390e8faff5a22c44eb673767351e65d72035917470c31f550f3
readonly notification_dns_deployed_sha256=39e13951657bc02e054c6387a4647fea031177f92c0bda86f55e8970f6005f98
readonly notification_dns_candidate_sha256=39e13951657bc02e054c6387a4647fea031177f92c0bda86f55e8970f6005f98
readonly notification_caddy_deployed_sha256=6b95393d5a07c1dc8086a14fb33ccfe435af9435b13f766847e13846456e410d
readonly notification_caddy_candidate_sha256=6b95393d5a07c1dc8086a14fb33ccfe435af9435b13f766847e13846456e410d

if [[ -n "${CADDY_SERVING_HEALTH_INCOMING_ROOT:-}${CADDY_SERVING_HEALTH_OUTGOING_ROOT:-}${CADDY_SERVING_HEALTH_QUARANTINE_ROOT:-}${CADDY_SERVING_HEALTH_RELEASES_ROOT:-}${CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256:-}${CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256:-}${CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST:-}${CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT:-}${CADDY_SERVING_HEALTH_SERVING_PAYLOAD_MANIFEST_SHA256:-}${CADDY_SERVING_HEALTH_FINALIZER_COMMAND:-}${CADDY_SERVING_HEALTH_PUBLISHER_COMMAND:-}${CADDY_SERVING_HEALTH_SYNC_USER:-}${CADDY_SERVING_HEALTH_SYNC_GROUP:-}${CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND:-}${CADDY_SERVING_HEALTH_SLEEP_COMMAND:-}${CADDY_SERVING_HEALTH_BUSCTL_COMMAND:-}${CADDY_SERVING_HEALTH_IP_COMMAND:-}${CADDY_SERVING_HEALTH_DATE_COMMAND:-}${CADDY_SERVING_HEALTH_DAEMON_OBSERVATION_ATTEMPTS:-}${CADDY_SERVING_HEALTH_DAEMON_OBSERVATION_DELAY:-}${CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS:-}${CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES:-}${CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY:-}${CADDY_SERVING_HEALTH_WEB_OBSERVATION_ATTEMPTS:-}${CADDY_SERVING_HEALTH_WEB_OBSERVATION_DELAY:-}${CADDY_SERVING_HEALTH_SAMPLER_MAX_CYCLES:-}${CADDY_SERVING_HEALTH_SAMPLER_DELAY:-}" &&
    "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
    exit 64
fi

usage() {
    printf 'Usage: %s --production-path-test | MODE node-a|node-b|external-apprise PAYLOAD_ROOT EVIDENCE_ROOT\n' "${0##*/}" >&2
}

safe_root() {
    local serving_health_root=$1

    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 &&
        -n "${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}" &&
        "$serving_health_root" = "$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT"/* ]]; then
        [[ "$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT" = /tmp/* &&
            -d "$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT" &&
            ! -L "$CADDY_PRODUCTION_PATH_EVIDENCE_ROOT" &&
            -d "$serving_health_root" && ! -L "$serving_health_root" ]]
        return
    fi

    [[ "$serving_health_root" == /tmp/caddy-serving-health-* &&
        -d "$serving_health_root" && ! -L "$serving_health_root" ]]
}

regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

release_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

sha256_value() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

path_absent() {
    [[ ! -e "$1" && ! -L "$1" ]]
}

effective_path() {
    local serving_health_logical_path=$1

    [[ "$serving_health_logical_path" = /* ]]
    printf '%s%s\n' "$target_root" "$serving_health_logical_path"
}

capture_command() {
    local serving_health_label=$1
    shift
    local serving_health_stdout=$evidence_root/$serving_health_label.stdout
    local serving_health_stderr=$evidence_root/$serving_health_label.stderr
    local serving_health_status=$evidence_root/$serving_health_label.status
    local serving_health_rc=0

    : >"$serving_health_stdout"
    : >"$serving_health_stderr"
    if "$@" >"$serving_health_stdout" 2>"$serving_health_stderr"; then
        serving_health_rc=0
    else
        serving_health_rc=$?
    fi
    printf '%s\n' "$serving_health_rc" >"$serving_health_status"
    chmod 0600 "$serving_health_stdout" "$serving_health_stderr" "$serving_health_status"
    [[ "$(stat -c '%s' "$serving_health_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$serving_health_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$serving_health_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$serving_health_stderr" >/dev/null
    return "$serving_health_rc"
}

capture_stdin_command() {
    local serving_health_label=$1
    local serving_health_input=$2
    shift 2
    local serving_health_stdout=$evidence_root/$serving_health_label.stdout
    local serving_health_stderr=$evidence_root/$serving_health_label.stderr
    local serving_health_status=$evidence_root/$serving_health_label.status
    local serving_health_rc=0

    regular_file "$serving_health_input"
    : >"$serving_health_stdout"
    : >"$serving_health_stderr"
    if "$@" <"$serving_health_input" >"$serving_health_stdout" 2>"$serving_health_stderr"; then
        serving_health_rc=0
    else
        serving_health_rc=$?
    fi
    printf '%s\n' "$serving_health_rc" >"$serving_health_status"
    chmod 0600 "$serving_health_stdout" "$serving_health_stderr" "$serving_health_status"
    [[ "$(stat -c '%s' "$serving_health_stdout")" -le 1048576 ]]
    [[ "$(stat -c '%s' "$serving_health_stderr")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$serving_health_stdout" >/dev/null
    iconv -f UTF-8 -t UTF-8 "$serving_health_stderr" >/dev/null
    return "$serving_health_rc"
}

require() {
    local serving_health_label=$1
    shift

    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$serving_health_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$serving_health_label" >&2
    return 1
}

require_equal() {
    local serving_health_label=$1
    local serving_health_expected=$2
    local serving_health_observed=$3

    [[ "$serving_health_label" =~ ^[a-z0-9_]+$ ]]
    [[ "$serving_health_expected" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    [[ "$serving_health_observed" =~ ^[A-Za-z0-9._:/,@+-]*$ ]]
    printf '%s_expected_%s=%s\n' "$prefix" "$serving_health_label" "$serving_health_expected"
    printf '%s_observed_%s=%s\n' "$prefix" "$serving_health_label" "$serving_health_observed"
    require "$serving_health_label" test "$serving_health_observed" = "$serving_health_expected"
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
    local serving_health_revision_file=$evidence_root/target-revision

    regular_file "$serving_health_revision_file"
    local serving_health_revision
    serving_health_revision=$(<"$serving_health_revision_file")
    [[ "$serving_health_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    printf '%s\n' "$serving_health_revision"
}

accepted_revision() {
    if regular_file "$evidence_root/target-revision"; then
        target_revision
    else
        printf '%s\n' "$serving_revision"
    fi
}

require_exact_directory_inventory() {
    local serving_health_label=$1
    local serving_health_root=$2
    local serving_health_expected=$3
    local serving_health_observed

    require "${serving_health_label}_root_regular" test -d "$serving_health_root" || return 1
    require "${serving_health_label}_root_not_symlink" test ! -L "$serving_health_root" || return 1
    if ! serving_health_observed=$(find "$serving_health_root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort); then
        printf '%s_check_%s_inventory_read=false\n' "$prefix" "$serving_health_label"
        return 1
    fi
    require_equal "${serving_health_label}_inventory" "$serving_health_expected" "$serving_health_observed"
}

require_empty_or_absent_directory() {
    local serving_health_label=$1
    local serving_health_root=$2

    if [[ ! -e "$serving_health_root" && ! -L "$serving_health_root" ]]; then
        require_equal "${serving_health_label}_state" absent absent
        return 0
    fi
    require_exact_directory_inventory "$serving_health_label" "$serving_health_root" ''
}

require_empty_or_absent_sync_directory() {
    local serving_health_label=$1
    local serving_health_root=$2
    local serving_health_expected_metadata=caddy-sync:caddy-sync:750

    if [[ ! -e "$serving_health_root" && ! -L "$serving_health_root" ]]; then
        require_equal "${serving_health_label}_state" absent absent
        return 0
    fi
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=${CADDY_SERVING_HEALTH_TEST_EXPECTED_SYNC_METADATA:-$(id -un):$(id -gn):750}
    fi
    require_exact_directory_inventory "$serving_health_label" "$serving_health_root" '' || return 1
    require_equal "${serving_health_label}_metadata" "$serving_health_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$serving_health_root")"
}

quarantine_names() {
    printf '%s\n' \
        node-a-action17p-node-a-to-node-b-bootstrap \
        node-a-action33k-20260813T000701Z-2499021-node-a-reboot-normalized \
        node_b-outbound-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29-action30c \
        node_b-outbound-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4-action30c
}

node_a_quarantine_contract() {
    if [[ -n "${CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT:-}" ]]; then
        [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]
        regular_file "$CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT"
        cat "$CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT"
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
    local serving_health_inventory_root=$1
    local serving_health_label=$2
    local serving_health_expected_metadata=caddy-sync:caddy-sync
    local serving_health_expected_names serving_health_observed_names
    local serving_health_name serving_health_name_label serving_health_revision serving_health_source
    local serving_health_release_hash serving_health_payload_hash serving_health_candidate
    local serving_health_allowed serving_health_observed serving_health_marker serving_health_path

    require "${serving_health_label}_root_regular" test -d "$serving_health_inventory_root" || return 1
    require "${serving_health_label}_root_not_symlink" test ! -L "$serving_health_inventory_root" || return 1
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=$(id -un):$(id -gn)
    fi
    require_equal "${serving_health_label}_root_metadata" \
        "$serving_health_expected_metadata:750" "$(stat -c '%U:%G:%a' "$serving_health_inventory_root")"
    serving_health_expected_names=$(mktemp /tmp/caddy-serving-health-node-a-expected.XXXXXX)
    serving_health_observed_names=$(mktemp /tmp/caddy-serving-health-node-a-observed.XXXXXX)
    node_a_quarantine_contract | awk -F '\t' '{ print $1 }' | LC_ALL=C sort \
        >"$serving_health_expected_names"
    find "$serving_health_inventory_root" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        LC_ALL=C sort >"$serving_health_observed_names"
    require "${serving_health_label}_top_level_exact" cmp -s \
        "$serving_health_expected_names" "$serving_health_observed_names" || {
        rm -f -- "$serving_health_expected_names" "$serving_health_observed_names"
        return 1
    }
    rm -f -- "$serving_health_expected_names" "$serving_health_observed_names"

    while IFS=$'\t' read -r serving_health_name serving_health_revision serving_health_source \
        serving_health_release_hash serving_health_payload_hash; do
        [[ "$serving_health_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
        serving_health_name_label=${serving_health_name,,}
        serving_health_name_label=${serving_health_name_label//[^a-z0-9_]/_}
        serving_health_candidate=$serving_health_inventory_root/$serving_health_name
        require "${serving_health_label}_${serving_health_name_label}_regular" \
            test -d "$serving_health_candidate" || return 1
        require "${serving_health_label}_${serving_health_name_label}_not_symlink" \
            test ! -L "$serving_health_candidate" || return 1
        require_equal "${serving_health_label}_${serving_health_name_label}_metadata" \
            "$serving_health_expected_metadata:550" "$(stat -c '%U:%G:%a' "$serving_health_candidate")"
        require "${serving_health_label}_${serving_health_name_label}_unsafe_types_absent" \
            test -z "$(find "$serving_health_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
        require "${serving_health_label}_${serving_health_name_label}_hardlinks_absent" \
            test -z "$(find "$serving_health_candidate" -type f -links +1 -print -quit)"
        while IFS= read -r -d '' serving_health_path; do
            if [[ -d "$serving_health_path" ]]; then
                require_equal "${serving_health_label}_${serving_health_name_label}_directory_metadata" \
                    "$serving_health_expected_metadata:550" "$(stat -c '%U:%G:%a' "$serving_health_path")" || return 1
            else
                require_equal "${serving_health_label}_${serving_health_name_label}_file_metadata" \
                    "$serving_health_expected_metadata:440" "$(stat -c '%U:%G:%a' "$serving_health_path")" || return 1
            fi
        done < <(find "$serving_health_candidate" -mindepth 1 -print0)
        require_equal "${serving_health_label}_${serving_health_name_label}_release_identity" \
            "$serving_health_release_hash" \
            "$(sha256sum "$serving_health_candidate/release-manifest.json" | awk '{ print $1 }')"
        require_equal "${serving_health_label}_${serving_health_name_label}_payload_identity" \
            "$serving_health_payload_hash" \
            "$(sha256sum "$serving_health_candidate/manifest.sha256" | awk '{ print $1 }')"
        require_equal "${serving_health_label}_${serving_health_name_label}_revision" \
            "$serving_health_revision" \
            "$(jq -r '.revision // empty' "$serving_health_candidate/release-manifest.json")"
        require_equal "${serving_health_label}_${serving_health_name_label}_source" \
            "$serving_health_source" \
            "$(jq -r '.source_node // empty' "$serving_health_candidate/release-manifest.json")"
        # The awk program must not expand shell positional parameters.
        # shellcheck disable=SC2016
        require "${serving_health_label}_${serving_health_name_label}_manifest_paths_safe" \
            awk 'length($0) < 68 { exit 1 } { p = substr($0, 67); sub(/^  /, "", p); if (p == "" || p ~ /^\// || p == ".." || p ~ /^\.\.\// || p ~ /\/\.\.\// || p ~ /\/\.\.$/) exit 1 }' \
            "$serving_health_candidate/manifest.sha256"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${serving_health_label}_${serving_health_name_label}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$serving_health_candidate"
        serving_health_allowed=$(mktemp /tmp/caddy-serving-health-node-a-allowed.XXXXXX)
        serving_health_observed=$(mktemp /tmp/caddy-serving-health-node-a-files.XXXXXX)
        for serving_health_marker in .finalize-request .complete; do
            if [[ -e "$serving_health_candidate/$serving_health_marker" ]]; then
                require "${serving_health_label}_${serving_health_name_label}_${serving_health_marker#.}_empty" \
                    test ! -s "$serving_health_candidate/$serving_health_marker" || return 1
            fi
        done
        {
            printf '%s\n' ./manifest.sha256 ./release-manifest.json
            awk '{ print substr($0, 67) }' "$serving_health_candidate/manifest.sha256"
            for serving_health_marker in .finalize-request .complete; do
                if [[ -e "$serving_health_candidate/$serving_health_marker" ]]; then
                    printf './%s\n' "$serving_health_marker"
                fi
            done
        } | LC_ALL=C sort -u >"$serving_health_allowed"
        require "${serving_health_label}_${serving_health_name_label}_complete_pending_absent" \
            path_absent "$serving_health_candidate/.complete.pending"
        (
            cd "$serving_health_candidate"
            find . -type f -print | LC_ALL=C sort -u
        ) >"$serving_health_observed"
        require "${serving_health_label}_${serving_health_name_label}_file_inventory_exact" \
            cmp -s "$serving_health_allowed" "$serving_health_observed" || {
            rm -f -- "$serving_health_allowed" "$serving_health_observed"
            return 1
        }
        rm -f -- "$serving_health_allowed" "$serving_health_observed"
    done < <(node_a_quarantine_contract)

    serving_health_path=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${serving_health_label}_current_reference_absent" test \
        "${serving_health_path#"$serving_health_inventory_root"/}" = "$serving_health_path"
    serving_health_path=''
    while IFS= read -r -d '' serving_health_marker; do
        serving_health_path=$(readlink -f "$serving_health_marker" || :)
        [[ "${serving_health_path#"$serving_health_inventory_root"/}" = "$serving_health_path" ]] || break
        serving_health_path=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${serving_health_label}_state_references_absent" test -z "$serving_health_path"
}

validate_quarantine_inventory() {
    local serving_health_inventory_root=$1
    local serving_health_label=$2
    local serving_health_manifest=${CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST:-$payload_root/manifests/serving-health-quarantine-baseline.tsv}
    local serving_health_expected_metadata=caddy-sync:caddy-sync:750
    local serving_health_observed_file serving_health_expected_file
    local serving_health_path serving_health_relative serving_health_encoded serving_health_type
    local serving_health_metadata serving_health_hash serving_health_reference
    local serving_health_name

    require "${serving_health_label}_root_regular" test -d "$serving_health_inventory_root" || return 1
    require "${serving_health_label}_root_not_symlink" test ! -L "$serving_health_inventory_root" || return 1
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=$(id -un):$(id -gn):750
    fi
    require_equal "${serving_health_label}_root_metadata" "$serving_health_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$serving_health_inventory_root")"
    require "${serving_health_label}_manifest_regular" regular_file "$serving_health_manifest"
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
        require_equal "${serving_health_label}_manifest_identity" \
            2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
            "$(sha256sum "$serving_health_manifest" | awk '{ print $1 }')"
    fi
    serving_health_expected_file=$(mktemp /tmp/caddy-serving-health-quarantine-expected.XXXXXX)
    serving_health_observed_file=$(mktemp /tmp/caddy-serving-health-quarantine-observed.XXXXXX)
    awk -F '\t' 'NR > 1 { print }' "$serving_health_manifest" | LC_ALL=C sort \
        >"$serving_health_expected_file"
    while IFS= read -r -d '' serving_health_path; do
        serving_health_relative=${serving_health_path#"$serving_health_inventory_root"/}
        [[ -n "$serving_health_relative" && "$serving_health_relative" != /* &&
            "$serving_health_relative" != .. && "$serving_health_relative" != ../* &&
            "$serving_health_relative" != */../* && "$serving_health_relative" != */.. ]]
        serving_health_encoded=$(printf '%s' "$serving_health_relative" | base64 -w 0)
        if [[ -d "$serving_health_path" && ! -L "$serving_health_path" ]]; then
            serving_health_type=directory
            serving_health_hash=-
        elif [[ -f "$serving_health_path" && ! -L "$serving_health_path" ]]; then
            if [[ -s "$serving_health_path" ]]; then
                serving_health_type='regular file'
            else
                serving_health_type='regular empty file'
            fi
            serving_health_hash=$(sha256sum "$serving_health_path" | awk '{ print $1 }')
        else
            printf '%s_check_%s_unsafe_type=false\n' "$prefix" "$serving_health_label"
            rm -f -- "$serving_health_expected_file" "$serving_health_observed_file"
            return 1
        fi
        serving_health_metadata=$(stat -c '%U:%G:%a' "$serving_health_path")
        printf '%s\t%s\t%s\t%s\n' "$serving_health_encoded" "$serving_health_type" \
            "$serving_health_metadata" "$serving_health_hash" >>"$serving_health_observed_file"
    done < <(find "$serving_health_inventory_root" -mindepth 1 -print0)
    LC_ALL=C sort -o "$serving_health_observed_file" "$serving_health_observed_file"
    require "${serving_health_label}_exact" cmp -s \
        "$serving_health_expected_file" "$serving_health_observed_file" || {
        rm -f -- "$serving_health_expected_file" "$serving_health_observed_file"
        return 1
    }
    rm -f -- "$serving_health_expected_file" "$serving_health_observed_file"
    while IFS= read -r serving_health_name; do
        require "${serving_health_label}_${serving_health_name//[-]/_}_release_manifest_json" \
            jq -e \
            'type == "object" and
             (.revision | type == "string" and length > 0) and
             (.parent_revision | type == "string" and length > 0) and
             (.source_node | type == "string" and (. == "node-a" or . == "node-b")) and
             (.created_at | type == "string" and length > 0)' \
            "$serving_health_inventory_root/$serving_health_name/release-manifest.json"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        require "${serving_health_label}_${serving_health_name//[-]/_}_manifest_valid" \
            /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
            _ "$serving_health_inventory_root/$serving_health_name"
    done < <(quarantine_names)
    serving_health_reference=$(readlink -f "$(effective_path /etc/caddy/current)" || :)
    require "${serving_health_label}_current_reference_absent" test \
        "${serving_health_reference#"$serving_health_inventory_root"/}" = "$serving_health_reference"
    serving_health_reference=''
    while IFS= read -r -d '' serving_health_path; do
        serving_health_reference=$(readlink -f "$serving_health_path" || :)
        [[ "${serving_health_reference#"$serving_health_inventory_root"/}" = "$serving_health_reference" ]] || break
        serving_health_reference=''
    done < <(find "$incoming_root" "$outgoing_root" -type l -print0)
    require "${serving_health_label}_state_references_absent" test -z "$serving_health_reference"
}

validate_retained_node_b_entry() {
    local serving_health_candidate=$incoming_root/node-a/$retained_name
    local serving_health_allowed
    local serving_health_expected_metadata=caddy-sync:caddy-sync:500
    local serving_health_observed

    [[ "$node_role" = node-b ]]
    require retained_inventory_exact require_exact_directory_inventory \
        retained_incoming_node_a "$incoming_root/node-a" "$retained_name"
    require retained_candidate_regular test -d "$serving_health_candidate"
    require retained_candidate_not_symlink test ! -L "$serving_health_candidate"
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=$(id -un):$(id -gn):500
    fi
    require_equal retained_candidate_metadata "$serving_health_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$serving_health_candidate")"
    require retained_release_manifest_regular regular_file \
        "$serving_health_candidate/release-manifest.json"
    require retained_payload_manifest_regular regular_file \
        "$serving_health_candidate/manifest.sha256"
    require_equal retained_release_manifest_identity \
        "$retained_release_manifest_sha256" \
        "$(sha256sum "$serving_health_candidate/release-manifest.json" | awk '{ print $1 }')"
    require_equal retained_payload_manifest_identity \
        "$retained_payload_manifest_sha256" \
        "$(sha256sum "$serving_health_candidate/manifest.sha256" | awk '{ print $1 }')"
    require_equal retained_revision "$retained_name" \
        "$(jq -r '.revision // empty' "$serving_health_candidate/release-manifest.json")"
    require_equal retained_source node-a \
        "$(jq -r '.source_node // empty' "$serving_health_candidate/release-manifest.json")"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require retained_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$serving_health_candidate"
    require retained_unsafe_types_absent test -z \
        "$(find "$serving_health_candidate" \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit)"
    require retained_finalize_request_absent path_absent \
        "$serving_health_candidate/.finalize-request"
    require retained_complete_absent path_absent "$serving_health_candidate/.complete"
    require retained_complete_pending_absent path_absent \
        "$serving_health_candidate/.complete.pending"
    serving_health_allowed=$(mktemp /tmp/caddy-serving-health-retained-allowed.XXXXXX)
    serving_health_observed=$(mktemp /tmp/caddy-serving-health-retained-observed.XXXXXX)
    {
        printf '%s\n' manifest.sha256 release-manifest.json
        awk '{ print $2 }' "$serving_health_candidate/manifest.sha256"
    } | sed 's#^\./##' | LC_ALL=C sort -u >"$serving_health_allowed"
    find "$serving_health_candidate" -mindepth 1 -type f -printf '%P\n' |
        LC_ALL=C sort -u >"$serving_health_observed"
    require retained_file_inventory_exact cmp -s "$serving_health_allowed" "$serving_health_observed"
    rm -f -- "$serving_health_allowed" "$serving_health_observed"
}

disposition_retained_node_b_entry() {
    local serving_health_candidate=$incoming_root/node-a/$retained_name
    local serving_health_backup=$evidence_root/retained-incoming
    local serving_health_quarantine_backup=$evidence_root/quarantine-disposition
    local serving_health_status=0

    [[ "$node_role" = node-b ]]
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    require retained_backup_absent test ! -e "$serving_health_backup"
    require quarantine_backup_absent test ! -e "$serving_health_quarantine_backup"
    require_equal quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" stop caddy-lsyncd.service || serving_health_status=125
    if [[ "$serving_health_status" -eq 0 ]]; then
        if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            chmod 0700 "$serving_health_candidate"
        fi
        mv -- "$serving_health_candidate" "$serving_health_backup" || serving_health_status=$?
    fi
    if [[ "$serving_health_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$serving_health_quarantine_backup" || serving_health_status=$?
    fi
    if [[ "$serving_health_status" -eq 0 ]]; then
        if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || serving_health_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || serving_health_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" start caddy-lsyncd.service || serving_health_status=125
    [[ "$serving_health_status" -eq 0 ]] || return "$serving_health_status"
    require retained_candidate_dispositioned test ! -e "$serving_health_candidate"
    require incoming_node_a_inventory_empty require_exact_directory_inventory \
        incoming_node_a_after_disposition "$incoming_root/node-a" ''
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine_after_disposition "$quarantine_root" ''
}

restore_retained_node_b_entry() {
    local serving_health_candidate=$incoming_root/node-a/$retained_name
    local serving_health_backup=$evidence_root/retained-incoming
    local serving_health_quarantine_backup=$evidence_root/quarantine-disposition
    local serving_health_status=0

    [[ "$node_role" = node-b ]]
    if [[ -n "$target_root" && ! -d "$serving_health_backup" ]]; then
        return 0
    fi
    if [[ -d "$serving_health_backup" && ! -L "$serving_health_backup" ]]; then
        require retained_restore_target_absent test ! -e "$serving_health_candidate"
        "$systemctl_command" stop caddy-sync-reconcile.path || serving_health_status=125
        "$systemctl_command" stop caddy-lsyncd.service || serving_health_status=125
        if [[ "$serving_health_status" -eq 0 ]]; then
            mv -- "$serving_health_backup" "$serving_health_candidate" || serving_health_status=$?
            if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
                chmod 0500 "$serving_health_candidate"
            fi
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || serving_health_status=125
        "$systemctl_command" start caddy-lsyncd.service || serving_health_status=125
    fi
    if [[ -d "$serving_health_quarantine_backup" && ! -L "$serving_health_quarantine_backup" ]]; then
        validate_quarantine_inventory "$serving_health_quarantine_backup" quarantine_restore_source
        if [[ -e "$quarantine_root" || -L "$quarantine_root" ]]; then
            require quarantine_restore_target_empty require_exact_directory_inventory \
                quarantine_restore_target "$quarantine_root" ''
        else
            require quarantine_restore_target_absent path_absent "$quarantine_root"
        fi
        "$systemctl_command" stop caddy-sync-reconcile.path || serving_health_status=125
        "$systemctl_command" stop caddy-lsyncd.service || serving_health_status=125
        if [[ "$serving_health_status" -eq 0 ]]; then
            if [[ -d "$quarantine_root" ]]; then
                rmdir "$quarantine_root" || serving_health_status=$?
            fi
        fi
        if [[ "$serving_health_status" -eq 0 ]]; then
            mv -- "$serving_health_quarantine_backup" "$quarantine_root" || serving_health_status=$?
        fi
        "$systemctl_command" start caddy-sync-reconcile.path || serving_health_status=125
        "$systemctl_command" start caddy-lsyncd.service || serving_health_status=125
    fi
    [[ "$serving_health_status" -eq 0 ]] || return "$serving_health_status"
    validate_retained_node_b_entry
    validate_quarantine_inventory "$quarantine_root" quarantine_restored
}

disposition_node_a_quarantine() {
    local serving_health_backup=$evidence_root/node-a-quarantine-disposition
    local serving_health_status=0

    [[ "$node_role" = node-a ]]
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_baseline
    require node_a_quarantine_backup_absent test ! -e "$serving_health_backup"
    require_equal node_a_quarantine_same_filesystem \
        "$(stat -c '%d' "$quarantine_root")" "$(stat -c '%d' "$evidence_root")"
    "$systemctl_command" stop caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" stop caddy-lsyncd.service || serving_health_status=125
    if [[ "$serving_health_status" -eq 0 ]]; then
        mv -- "$quarantine_root" "$serving_health_backup" || serving_health_status=$?
    fi
    if [[ "$serving_health_status" -eq 0 ]]; then
        if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
            install -d -m 0750 "$quarantine_root" || serving_health_status=$?
        else
            install -d -o caddy-sync -g caddy-sync -m 0750 "$quarantine_root" || serving_health_status=$?
        fi
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" start caddy-lsyncd.service || serving_health_status=125
    [[ "$serving_health_status" -eq 0 ]] || return "$serving_health_status"
    require node_a_quarantine_inventory_empty require_exact_directory_inventory \
        node_a_quarantine_after_disposition "$quarantine_root" ''
}

restore_node_a_quarantine() {
    local serving_health_backup=$evidence_root/node-a-quarantine-disposition
    local serving_health_status=0

    [[ "$node_role" = node-a ]]
    if [[ ! -e "$serving_health_backup" && ! -L "$serving_health_backup" ]]; then
        return 0
    fi
    require node_a_quarantine_restore_source_regular test -d "$serving_health_backup"
    require node_a_quarantine_restore_source_not_symlink test ! -L "$serving_health_backup"
    validate_node_a_quarantine_inventory "$serving_health_backup" node_a_quarantine_restore_source
    require node_a_quarantine_restore_target_empty require_exact_directory_inventory \
        node_a_quarantine_restore_target "$quarantine_root" ''
    "$systemctl_command" stop caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" stop caddy-lsyncd.service || serving_health_status=125
    if [[ "$serving_health_status" -eq 0 ]]; then
        rmdir "$quarantine_root" || serving_health_status=$?
    fi
    if [[ "$serving_health_status" -eq 0 ]]; then
        mv -- "$serving_health_backup" "$quarantine_root" || serving_health_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || serving_health_status=125
    "$systemctl_command" start caddy-lsyncd.service || serving_health_status=125
    [[ "$serving_health_status" -eq 0 ]] || return "$serving_health_status"
    validate_node_a_quarantine_inventory "$quarantine_root" node_a_quarantine_restored
}

validate_outbound_candidate() {
    local serving_health_candidate=$outgoing_root/$serving_revision
    local serving_health_manifest_hash

    require outbound_candidate_regular test -d "$serving_health_candidate"
    require outbound_candidate_not_symlink test ! -L "$serving_health_candidate"
    require outbound_candidate_metadata test \
        "$(stat -c '%U:%G:%a' "$serving_health_candidate")" = "$sync_user:$sync_group:550"
    require outbound_revision test \
        "$(jq -r '.revision // empty' "$serving_health_candidate/release-manifest.json")" = "$serving_revision"
    require outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$serving_health_candidate/release-manifest.json")" = "$serving_parent"
    require outbound_source test \
        "$(jq -r '.source_node // empty' "$serving_health_candidate/release-manifest.json")" = node-a
    serving_health_manifest_hash=$(sha256sum "$serving_health_candidate/manifest.sha256" | awk '{ print $1 }')
    require outbound_payload_manifest_hash test \
        "$serving_health_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require outbound_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$serving_health_candidate"
    require outbound_finalize_marker_regular test -f "$serving_health_candidate/.finalize-request"
    require outbound_finalize_marker_empty test ! -s "$serving_health_candidate/.finalize-request"
    require outbound_symlinks_absent test -z \
        "$(find "$serving_health_candidate" -type l -print -quit)"
}

validate_installed_release() {
    local serving_health_release=$releases_root/$serving_revision
    local serving_health_manifest_hash
    local serving_health_expected_metadata=root:caddy-tls:550

    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=$(id -un):$(id -gn):550
    fi

    require installed_release_regular test -d "$serving_health_release"
    require installed_release_not_symlink test ! -L "$serving_health_release"
    require installed_release_metadata test \
        "$(stat -c '%U:%G:%a' "$serving_health_release")" = "$serving_health_expected_metadata"
    require installed_release_revision test \
        "$(jq -r '.revision // empty' "$serving_health_release/release-manifest.json")" = "$serving_revision"
    require installed_release_parent test \
        "$(jq -r '.parent_revision // empty' "$serving_health_release/release-manifest.json")" = "$serving_parent"
    require installed_release_source test \
        "$(jq -r '.source_node // empty' "$serving_health_release/release-manifest.json")" = node-a
    serving_health_manifest_hash=$(sha256sum "$serving_health_release/manifest.sha256" | awk '{ print $1 }')
    require installed_payload_manifest_hash test \
        "$serving_health_manifest_hash" = "$serving_payload_manifest_sha256"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require installed_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$serving_health_release"
}

validate_current_live_release() {
    local serving_health_state=$payload_root/manifests/current-live-state.tsv
    local serving_health_contract serving_health_release serving_health_manifest_hash
    local serving_health_current_manifest_hash serving_health_current_revision
    local serving_health_current_parent serving_health_current_source

    regular_file "$serving_health_state"
    serving_health_contract=$(awk -F '\t' -v role="$node_role" \
        '$2 == role && $3 == "release" { print $4 }' "$serving_health_state")
    require_equal current_live_release_rows 1 \
        "$(awk -F '\t' -v role="$node_role" '$2 == role && $3 == "release" { count++ } END { print count + 0 }' "$serving_health_state")"
    serving_health_current_revision=$(sed -n 's/.*revision=\([^,]*\).*/\1/p' \
        <<<"$serving_health_contract")
    serving_health_current_parent=$(sed -n 's/.*parent=\([^,]*\).*/\1/p' \
        <<<"$serving_health_contract")
    serving_health_current_source=$(sed -n 's/.*source=\([^,]*\).*/\1/p' \
        <<<"$serving_health_contract")
    serving_health_current_manifest_hash=$(sed -n \
        's/.*payload-manifest-sha256=\([^,]*\).*/\1/p' <<<"$serving_health_contract")
    require current_live_revision_format release_identifier \
        "$serving_health_current_revision"
    require current_live_parent_format release_identifier \
        "$serving_health_current_parent"
    require_equal current_live_source node-a "$serving_health_current_source"
    require current_live_manifest_hash_format sha256_value \
        "$serving_health_current_manifest_hash"
    serving_health_release=$releases_root/$serving_health_current_revision
    require current_live_release_regular test -d "$serving_health_release"
    require current_live_release_not_symlink test ! -L "$serving_health_release"
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        require_equal current_live_release_mode 550 \
            "$(stat -c '%a' "$serving_health_release")"
    else
        require_equal current_live_release_metadata root:caddy-tls:550 \
            "$(stat -c '%U:%G:%a' "$serving_health_release")"
    fi
    require_equal current_live_release_revision "$serving_health_current_revision" \
        "$(jq -r '.revision // empty' "$serving_health_release/release-manifest.json")"
    require_equal current_live_release_parent "$serving_health_current_parent" \
        "$(jq -r '.parent_revision // empty' "$serving_health_release/release-manifest.json")"
    require_equal current_live_release_source "$serving_health_current_source" \
        "$(jq -r '.source_node // empty' "$serving_health_release/release-manifest.json")"
    serving_health_manifest_hash=$(sha256sum "$serving_health_release/manifest.sha256" | awk '{ print $1 }')
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        printf '%s_expected_current_live_payload_manifest=%s\n' \
            "$prefix" "$serving_health_current_manifest_hash"
        printf '%s_observed_current_live_payload_manifest=%s\n' \
            "$prefix" "$serving_health_manifest_hash"
        require current_live_fixture_payload_manifest_format sha256_value \
            "$serving_health_manifest_hash"
    else
        require_equal current_live_payload_manifest "$serving_health_current_manifest_hash" \
            "$serving_health_manifest_hash"
    fi
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require current_live_manifest_valid \
        /bin/bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$serving_health_release"
    require_equal current_live_selected_revision "$serving_health_current_revision" \
        "$(current_revision)"
}

validate_inventory() {
    local serving_health_inventory=$payload_root/manifests/production-artifacts.tsv
    local serving_health_key serving_health_repository serving_health_source serving_health_target
    local serving_health_inventory_node serving_health_source_hash serving_health_deployed_hash
    local serving_health_accepted serving_health_lifecycle serving_health_observed

    regular_file "$serving_health_inventory"
    while IFS=$'\t' read -r serving_health_key serving_health_repository serving_health_source \
        serving_health_target serving_health_inventory_node serving_health_source_hash \
        serving_health_deployed_hash serving_health_accepted serving_health_lifecycle; do
        [[ "$serving_health_key" = '# key' ]] && continue
        [[ "$serving_health_inventory_node" = "$node_role" ||
            "$serving_health_inventory_node" = both ]] || continue
        [[ -n "$serving_health_accepted" && "$serving_health_lifecycle" = production-current ]]
        serving_health_target=$(effective_path "$serving_health_target")
        require "artifact_${serving_health_key}_regular" regular_file "$serving_health_target"
        serving_health_observed=$(sha256sum "$serving_health_target" | awk '{ print $1 }')
        if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 &&
            "$serving_health_repository" = runtime-generated ]]; then
            printf '%s_expected_artifact_%s_identity=%s\n' \
                "$prefix" "$serving_health_key" "$serving_health_deployed_hash"
            printf '%s_observed_artifact_%s_identity=%s\n' \
                "$prefix" "$serving_health_key" "$serving_health_observed"
            require "artifact_${serving_health_key}_fixture_identity_format" \
                sha256_value "$serving_health_observed"
        else
            require_equal "artifact_${serving_health_key}_identity" \
                "$serving_health_deployed_hash" "$serving_health_observed"
        fi
    done <"$serving_health_inventory"
}

validate_legacy_lighttpd_helper() {
    local serving_health_path
    local serving_health_expected_metadata=root:root:755

    serving_health_path=$(effective_path "$legacy_lighttpd_helper")
    if [[ "$node_role" = node-a ]]; then
        require_equal legacy_lighttpd_helper_state absent \
            "$(if path_absent "$serving_health_path"; then printf absent; else printf present; fi)"
        return
    fi
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_expected_metadata=$(id -un):$(id -gn):755
    fi
    require legacy_lighttpd_helper_regular regular_file "$serving_health_path"
    require_equal legacy_lighttpd_helper_metadata "$serving_health_expected_metadata" \
        "$(stat -c '%U:%G:%a' "$serving_health_path")"
    require_equal legacy_lighttpd_helper_identity "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$serving_health_path" | awk '{ print $1 }')"
}

remove_legacy_lighttpd_helper() {
    local serving_health_path

    [[ "$node_role" = node-b ]]
    validate_legacy_lighttpd_helper
    serving_health_path=$(effective_path "$legacy_lighttpd_helper")
    backup_target "$legacy_lighttpd_helper"
    rm -f -- "$serving_health_path"
    require legacy_lighttpd_helper_removed path_absent "$serving_health_path"
}

restore_legacy_lighttpd_helper() {
    [[ "$node_role" = node-b ]]
    restore_target "$legacy_lighttpd_helper"
    validate_legacy_lighttpd_helper
}

validate_services() {
    local serving_health_unit

    for serving_health_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${serving_health_unit//[.@-]/_}_active" \
            "$systemctl_command" is-active --quiet "$serving_health_unit"
    done
    for serving_health_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.path caddy-cert-expiry.timer \
        caddy-sync-health.timer caddy-apprise-worker.path \
        caddy-apprise-worker.timer keepalived.service; do
        require "${serving_health_unit//[.@-]/_}_enabled" \
            "$systemctl_command" is-enabled --quiet "$serving_health_unit"
    done
    require caddy_api_masked test "$($systemctl_command is-enabled caddy-api.service)" = masked
    require distribution_lsyncd_masked test "$($systemctl_command is-enabled lsyncd.service)" = masked
}

validate_split_baseline() {
    local serving_health_expected_revision

    serving_health_expected_revision=$(expected_release)
    require_equal current_release_expected "$serving_health_expected_revision" "$(current_revision)"
    validate_inventory
    validate_legacy_lighttpd_helper
    validate_services
    if [[ "$node_role" = node-b ]]; then
        validate_retained_node_b_entry
        require incoming_node_b_absent path_absent "$incoming_root/node-b"
        validate_quarantine_inventory "$quarantine_root" quarantine_baseline
    else
        require incoming_node_a_empty require_empty_or_absent_sync_directory \
            incoming_node_a "$incoming_root/node-a"
        require incoming_node_b_empty require_empty_or_absent_sync_directory \
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
    local serving_health_manifest=$payload_root/manifests/serving-health-production.tsv
    local serving_health_repository serving_health_source serving_health_target serving_health_mode
    local serving_health_expected_hash serving_health_lifecycle serving_health_file serving_health_observed

    require payload_root safe_root "$payload_root"
    require payload_manifest regular_file "$serving_health_manifest"
    require quarantine_inventory_manifest regular_file \
        "$payload_root/manifests/serving-health-quarantine-baseline.tsv"
    require_equal quarantine_inventory_manifest_identity \
        2989c2bc4cef06864cf2e5c2abc30114fac0830841e52a1bd8d5983ed26a2083 \
        "$(sha256sum "$payload_root/manifests/serving-health-quarantine-baseline.tsv" | awk '{ print $1 }')"
    while IFS=$'\t' read -r serving_health_repository serving_health_source serving_health_target \
        serving_health_mode serving_health_expected_hash serving_health_lifecycle; do
        [[ "$serving_health_repository" = '# repository' ]] && continue
        serving_health_file=$payload_root/repositories/$serving_health_repository/$serving_health_source
        require "payload_${serving_health_expected_hash}_regular" regular_file "$serving_health_file"
        serving_health_observed=$(sha256sum "$serving_health_file" | awk '{ print $1 }')
        require "payload_${serving_health_expected_hash}_identity" test \
            "$serving_health_observed" = "$serving_health_expected_hash"
    done <"$serving_health_manifest"
}

validate_installed_candidate_inventory() {
    local serving_health_manifest=$payload_root/manifests/serving-health-production.tsv
    local serving_health_repository serving_health_source serving_health_target serving_health_mode
    local serving_health_expected_hash serving_health_lifecycle serving_health_observed

    while IFS=$'\t' read -r serving_health_repository serving_health_source serving_health_target \
        serving_health_mode serving_health_expected_hash serving_health_lifecycle; do
        [[ "$serving_health_repository" = '# repository' ]] && continue
        [[ "$serving_health_lifecycle" = production-candidate ]]
        case "$serving_health_target" in
            /etc/caddy/releases/REVISION/*) continue ;;
        esac
        if [[ "$serving_health_source" = Keepalived/configs/keepalived-pihole0.conf &&
            "$node_role" != node-a ]]; then
            continue
        fi
        if [[ "$serving_health_source" = Keepalived/configs/keepalived-pihole00.conf &&
            "$node_role" != node-b ]]; then
            continue
        fi
        require "candidate_${serving_health_expected_hash}_regular" regular_file "$serving_health_target"
        require "candidate_${serving_health_expected_hash}_mode" test \
            "$(stat -c '%a' "$serving_health_target")" = "${serving_health_mode#0}"
        require "candidate_${serving_health_expected_hash}_owner" test \
            "$(stat -c '%U:%G' "$serving_health_target")" = root:root
        serving_health_observed=$(sha256sum "$serving_health_target" | awk '{ print $1 }')
        require "candidate_${serving_health_expected_hash}_identity" test \
            "$serving_health_observed" = "$serving_health_expected_hash"
    done <"$serving_health_manifest"
}

validate_web_health_queue_permissions() {
    local serving_health_queue_root
    local serving_health_queue_directory
    local serving_health_queue_label

    serving_health_queue_root=$(effective_path /var/lib/caddy-apprise-queue)
    require web_queue_root_regular test -d "$serving_health_queue_root"
    require web_queue_root_not_symlink test ! -L "$serving_health_queue_root"
    if [[ -z "$target_root" ]]; then
        require_equal web_queue_root_metadata pi:pi:700 \
            "$(stat -c '%U:%G:%a' "$serving_health_queue_root")"
    else
        require_equal web_queue_root_mode 700 "$(stat -c '%a' "$serving_health_queue_root")"
    fi
    for serving_health_queue_directory in pending inflight dead-letter delivered; do
        serving_health_queue_label=${serving_health_queue_directory//-/_}
        require "web_queue_${serving_health_queue_label}_regular" \
            test -d "$serving_health_queue_root/$serving_health_queue_directory"
        require "web_queue_${serving_health_queue_label}_not_symlink" \
            test ! -L "$serving_health_queue_root/$serving_health_queue_directory"
        if [[ -z "$target_root" ]]; then
            require_equal "web_queue_${serving_health_queue_label}_metadata" \
                pi:pi:700 "$(stat -c '%U:%G:%a' \
                    "$serving_health_queue_root/$serving_health_queue_directory")"
        else
            require_equal "web_queue_${serving_health_queue_label}_mode" 700 \
                "$(stat -c '%a' "$serving_health_queue_root/$serving_health_queue_directory")"
        fi
    done
}

web_health_unit_preflight() {
    local serving_health_installed
    local serving_health_service_name

    serving_health_installed=$(effective_path "$web_health_unit")
    require web_unit_regular regular_file "$serving_health_installed"
    if [[ -z "$target_root" ]]; then
        require_equal web_unit_metadata root:root:644 \
            "$(stat -c '%U:%G:%a' "$serving_health_installed")"
    else
        require_equal web_unit_test_mode 644 "$(stat -c '%a' "$serving_health_installed")"
    fi
    require_equal web_unit_deployed_identity "$web_health_unit_deployed_sha256" \
        "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')"
    require web_unit_broken_runtime_dependency \
        grep -Fq 'ReadWritePaths=/var/lib/caddy-apprise-queue /run/caddy-apprise' \
        "$serving_health_installed"
    require web_timer_enabled "$systemctl_command" is-enabled --quiet "$web_health_timer"
    require web_timer_active "$systemctl_command" is-active --quiet "$web_health_timer"
    require web_service_static test "$($systemctl_command is-enabled "$web_health_service")" = static
    for serving_health_service_name in caddy.service lighttpd.service pihole-FTL.service \
        unbound.service keepalived.service caddy-lsyncd.service; do
        require "baseline_${serving_health_service_name//[^a-zA-Z0-9]/_}_active" \
            "$systemctl_command" is-active --quiet "$serving_health_service_name"
    done
    validate_web_health_queue_permissions
    capture_journal_cursor
    capture_command web_unit_preflight_state "$systemctl_command" show "$web_health_service" \
        -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus \
        -p FragmentPath -p ReadWritePaths
}

install_web_health_unit() {
    local serving_health_candidate

    serving_health_candidate=$(candidate_file homelab-server-configs \
        Caddy/systemd/caddy-pihole-web-health.service)
    require web_unit_candidate_regular regular_file "$serving_health_candidate"
    require_equal web_unit_candidate_identity "$web_health_unit_candidate_sha256" \
        "$(sha256sum "$serving_health_candidate" | awk '{ print $1 }')"
    require web_unit_candidate_queue_only \
        grep -Fxq 'ReadWritePaths=/var/lib/caddy-apprise-queue' "$serving_health_candidate"
    require web_unit_candidate_worker_runtime_absent \
        test "$(grep -Fc '/run/caddy-apprise' "$serving_health_candidate")" -eq 0
    require web_unit_candidate_supplementary_group \
        grep -Fxq 'SupplementaryGroups=caddy-tls' "$serving_health_candidate"
    install_target "$serving_health_candidate" "$web_health_unit" 0644 root root
    "$systemctl_command" daemon-reload
    printf 'web-health-unit\n' >"$evidence_root/mutation"
    chmod 0600 "$evidence_root/mutation"
}

accept_web_health_unit() {
    local serving_health_installed
    local serving_health_attempt
    local serving_health_service_name
    local serving_health_healthy_count=0
    local serving_health_finish_count=0
    local serving_health_start_status=0

    serving_health_installed=$(effective_path "$web_health_unit")
    require_equal web_unit_installed_identity "$web_health_unit_candidate_sha256" \
        "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')"
    require_equal web_unit_installed_mode 644 "$(stat -c '%a' "$serving_health_installed")"
    if [[ -z "$target_root" ]]; then
        require_equal web_unit_installed_owner root:root \
            "$(stat -c '%U:%G' "$serving_health_installed")"
    fi
    if capture_command web_unit_direct_start "$systemctl_command" start "$web_health_service"; then
        serving_health_start_status=0
    else
        serving_health_start_status=$?
        capture_command web_unit_failure_journal "$journalctl_command" --quiet --no-pager \
            -o cat --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u "$web_health_service" || :
        return "$serving_health_start_status"
    fi
    capture_command web_unit_direct_state "$systemctl_command" show "$web_health_service" \
        -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus \
        -p SupplementaryGroups
    require web_unit_direct_result grep -Fxq 'Result=success' \
        "$evidence_root/web_unit_direct_state.stdout"
    require web_unit_direct_status grep -Fxq 'ExecMainStatus=0' \
        "$evidence_root/web_unit_direct_state.stdout"
    require web_unit_direct_supplementary_group grep -Fxq \
        'SupplementaryGroups=caddy-tls' "$evidence_root/web_unit_direct_state.stdout"

    capture_journal_cursor

    for ((serving_health_attempt = 1;  \
    serving_health_attempt <= web_health_observation_attempts;  \
    serving_health_attempt++)); do
        capture_command web_unit_timer_journal "$journalctl_command" --quiet --no-pager \
            -o cat --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u "$web_health_service"
        serving_health_healthy_count=$(grep -Fc \
            'pihole_web_health event=healthy' \
            "$evidence_root/web_unit_timer_journal.stdout" || :)
        serving_health_finish_count=$(grep -Ec \
            'Finished caddy-pihole-web-health.service|Deactivated successfully' \
            "$evidence_root/web_unit_timer_journal.stdout" || :)
        if [[ "$serving_health_healthy_count" -ge 1 && "$serving_health_finish_count" -ge 1 ]]; then
            break
        fi
        "$sleep_command" "$web_health_observation_delay"
    done
    require web_unit_timer_healthy_event test "$serving_health_healthy_count" -ge 1
    require web_unit_timer_successful_completion test "$serving_health_finish_count" -ge 1
    capture_command web_unit_timer_state "$systemctl_command" show "$web_health_service" \
        -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus
    require web_unit_timer_result grep -Fxq 'Result=success' \
        "$evidence_root/web_unit_timer_state.stdout"
    require web_unit_timer_status grep -Fxq 'ExecMainStatus=0' \
        "$evidence_root/web_unit_timer_state.stdout"
    require web_unit_timer_failures_absent test \
        "$(grep -Ec 'Failed to start|status=226/NAMESPACE|Failed at step NAMESPACE' \
            "$evidence_root/web_unit_timer_journal.stdout" || :)" -eq 0
    require web_timer_enabled "$systemctl_command" is-enabled --quiet "$web_health_timer"
    require web_timer_active "$systemctl_command" is-active --quiet "$web_health_timer"
    for serving_health_service_name in caddy.service lighttpd.service pihole-FTL.service \
        unbound.service keepalived.service caddy-lsyncd.service; do
        require "accepted_${serving_health_service_name//[^a-zA-Z0-9]/_}_active" \
            "$systemctl_command" is-active --quiet "$serving_health_service_name"
    done
    validate_web_health_queue_permissions
}

rollback_web_health_unit() {
    if [[ -f "$(backup_path "$web_health_unit").state" ]]; then
        restore_target "$web_health_unit"
    fi
    "$systemctl_command" daemon-reload
    require_equal web_unit_rollback_identity "$web_health_unit_deployed_sha256" \
        "$(sha256sum "$(effective_path "$web_health_unit")" | awk '{ print $1 }')"
    validate_web_health_queue_permissions
}

notification_artifact_rows() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        homelab-server-configs Caddy/scripts/caddy-apprise-enqueue.sh /usr/local/libexec/caddy-apprise-enqueue 0755 "$notification_enqueue_deployed_sha256" "$notification_enqueue_candidate_sha256" \
        homelab-server-configs Caddy/scripts/caddy-apprise-delivery-worker.sh /usr/local/libexec/caddy-apprise-delivery-worker 0755 "$notification_worker_deployed_sha256" "$notification_worker_candidate_sha256" \
        homelab-dns Keepalived/scripts/keepalived-notify.sh /usr/local/bin/keepalived-notify.sh 0755 "$notification_notifier_deployed_sha256" "$notification_notifier_candidate_sha256" \
        homelab-server-configs Caddy/configs/tmpfiles.d/caddy-ha.conf /etc/tmpfiles.d/caddy-ha.conf 0644 "$notification_tmpfiles_deployed_sha256" "$notification_tmpfiles_candidate_sha256" \
        homelab-dns Keepalived/scripts/dns-check.sh /etc/scripts/check-dns.sh 0755 "$notification_dns_deployed_sha256" "$notification_dns_candidate_sha256" \
        homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh /usr/local/libexec/check-caddy.sh 0755 "$notification_caddy_deployed_sha256" "$notification_caddy_candidate_sha256"
}

notification_capture_bootstrap_state() {
    local notification_ipv4_state notification_ipv6_state notification_addresses notification_vip
    local notification_vip_count=0 notification_expected_state notification_expected_vips

    notification_ipv4_state=$(
        "$busctl_command" get-property org.keepalived.Vrrp1 \
            /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
            org.keepalived.Vrrp1.Instance State |
            sed -n 's/.*"\([^"]*\)".*/\1/p'
    )
    notification_ipv6_state=$(
        "$busctl_command" get-property org.keepalived.Vrrp1 \
            /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
            org.keepalived.Vrrp1.Instance State |
            sed -n 's/.*"\([^"]*\)".*/\1/p'
    )
    notification_addresses=$("$ip_command" -o address show dev eth0)
    for notification_vip in 10.1.0.55/22 10.1.0.56/22 \
        fd36:5aa8:6971:1::55/128 fd36:5aa8:6971:1::56/128; do
        if grep -Fq " $notification_vip " <<<"$notification_addresses"; then
            notification_vip_count=$((notification_vip_count + 1))
        fi
    done
    notification_expected_state=Backup
    notification_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        notification_expected_state=Master
        notification_expected_vips=4
    fi
    require_equal notification_bootstrap_ipv4 "$notification_expected_state" \
        "$notification_ipv4_state"
    require_equal notification_bootstrap_ipv6 "$notification_expected_state" \
        "$notification_ipv6_state"
    require_equal notification_bootstrap_vips "$notification_expected_vips" \
        "$notification_vip_count"
    printf '%s\n' "${notification_expected_state^^}" \
        >"$evidence_root/notification-bootstrap-state"
    chmod 0600 "$evidence_root/notification-bootstrap-state"
}

validate_notification_state_contract() {
    local notification_state_parent=$1
    local notification_state_root=$2
    local notification_expected_state=$3
    local notification_parent_owner=$4
    local notification_parent_group=$5
    local notification_state_owner=$6
    local notification_state_group=$7
    local notification_state_evidence=$8
    local notification_state_file=$notification_state_root/PIHOLE_DUALSTACK.state
    local notification_lock_file=$notification_state_root/PIHOLE_DUALSTACK.lock
    local notification_inventory notification_inventory_state

    require notification_state_parent_directory test -d "$notification_state_parent" || return 1
    require notification_state_parent_not_symlink test ! -L "$notification_state_parent" || return 1
    require_equal notification_state_parent_metadata \
        "$notification_parent_owner:$notification_parent_group:755" \
        "$(stat -c '%U:%G:%a' "$notification_state_parent")" || return 1
    require notification_state_root_directory test -d "$notification_state_root" || return 1
    require notification_state_root_not_symlink test ! -L "$notification_state_root" || return 1
    require_equal notification_state_root_metadata \
        "$notification_state_owner:$notification_state_group:700" \
        "$(stat -c '%U:%G:%a' "$notification_state_root")" || return 1
    notification_inventory=$(find "$notification_state_root" -mindepth 1 -maxdepth 1 \
        -printf '%f\n' | LC_ALL=C sort) || return 1
    notification_inventory_state=unsafe
    case "$notification_inventory" in
        PIHOLE_DUALSTACK.state) notification_inventory_state=state ;;
        $'PIHOLE_DUALSTACK.lock\nPIHOLE_DUALSTACK.state')
            notification_inventory_state=state-lock
            ;;
    esac
    printf '%s_expected_notification_state_inventory=state-or-state-lock\n' "$prefix"
    printf '%s_observed_notification_state_inventory=%s\n' \
        "$prefix" "$notification_inventory_state"
    require notification_state_inventory test "$notification_inventory_state" != unsafe || return 1
    require notification_state_file_regular regular_file "$notification_state_file" || return 1
    require_equal notification_state_file_metadata \
        "$notification_state_owner:$notification_state_group:600" \
        "$(stat -c '%U:%G:%a' "$notification_state_file")" || return 1
    require_equal notification_state_file_lines 1 "$(wc -l <"$notification_state_file")" || return 1
    require_equal notification_state_file_value "$notification_expected_state" \
        "$(<"$notification_state_file")" || return 1
    if [[ -e "$notification_lock_file" || -L "$notification_lock_file" ]]; then
        require notification_lock_file_regular regular_file "$notification_lock_file" || return 1
        require_equal notification_lock_file_metadata \
            "$notification_state_owner:$notification_state_group:600:0" \
            "$(stat -c '%U:%G:%a:%s' "$notification_lock_file")" || return 1
    fi
    install -m 0600 "$notification_state_file" \
        "$notification_state_evidence/notification-state.baseline"
    printf '%s\n' "$notification_inventory" \
        >"$notification_state_evidence/notification-state-inventory.baseline"
    chmod 0600 "$notification_state_evidence/notification-state-inventory.baseline"
}

notification_preflight() {
    local notification_repository notification_source notification_target notification_mode
    local notification_deployed_hash notification_candidate_hash notification_installed
    local notification_candidate notification_parent_owner notification_parent_group
    local notification_state_owner notification_state_group

    while IFS=$'\t' read -r notification_repository notification_source notification_target \
        notification_mode notification_deployed_hash notification_candidate_hash; do
        notification_installed=$(effective_path "$notification_target")
        notification_candidate=$(candidate_file "$notification_repository" "$notification_source")
        require "notification_${notification_target//[^a-zA-Z0-9]/_}_installed_regular" \
            regular_file "$notification_installed"
        require_equal "notification_${notification_target//[^a-zA-Z0-9]/_}_baseline" \
            "$notification_deployed_hash" "$(sha256sum "$notification_installed" | awk '{ print $1 }')"
        require_equal "notification_${notification_target//[^a-zA-Z0-9]/_}_mode" \
            "${notification_mode#0}" "$(stat -c '%a' "$notification_installed")"
        require "notification_${notification_target//[^a-zA-Z0-9]/_}_candidate_regular" \
            regular_file "$notification_candidate"
        require_equal "notification_${notification_target//[^a-zA-Z0-9]/_}_candidate" \
            "$notification_candidate_hash" "$(sha256sum "$notification_candidate" | awk '{ print $1 }')"
    done < <(notification_artifact_rows)
    for notification_service in caddy.service pihole-FTL.service unbound.service keepalived.service; do
        require "notification_${notification_service//[^a-zA-Z0-9]/_}_active" \
            "$systemctl_command" is-active --quiet "$notification_service"
    done
    notification_capture_bootstrap_state
    validate_web_health_queue_permissions
    notification_parent_owner=root
    notification_parent_group=root
    notification_state_owner=pi
    notification_state_group=pi
    if [[ -n "$target_root" ]]; then
        notification_parent_owner=$(id -un)
        notification_parent_group=$(id -gn)
        notification_state_owner=$(id -un)
        notification_state_group=$(id -gn)
    fi
    validate_notification_state_contract \
        "$(effective_path /var/lib/caddy-serving-health)" \
        "$(effective_path /var/lib/caddy-serving-health/keepalived-notify)" \
        "$(<"$evidence_root/notification-bootstrap-state")" \
        "$notification_parent_owner" "$notification_parent_group" \
        "$notification_state_owner" "$notification_state_group" "$evidence_root"
}

install_notification_standardization() {
    local notification_repository notification_source notification_target notification_mode
    local notification_deployed_hash notification_candidate_hash notification_state_root
    local notification_initial_state notification_state_owner notification_state_group

    while IFS=$'\t' read -r notification_repository notification_source notification_target \
        notification_mode notification_deployed_hash notification_candidate_hash; do
        install_target "$(candidate_file "$notification_repository" "$notification_source")" \
            "$notification_target" "$notification_mode" root root
    done < <(notification_artifact_rows)
    "$systemd_tmpfiles_command" --create "$(effective_path /etc/tmpfiles.d/caddy-ha.conf)"
    notification_state_root=$(effective_path /var/lib/caddy-serving-health/keepalived-notify)
    require notification_state_root_created test -d "$notification_state_root"
    require notification_state_root_created_not_symlink test ! -L "$notification_state_root"
    notification_initial_state=$(<"$evidence_root/notification-bootstrap-state")
    notification_state_owner=pi
    notification_state_group=pi
    if [[ -n "$target_root" ]]; then
        notification_state_owner=$(id -un)
        notification_state_group=$(id -gn)
    fi
    install -o "$notification_state_owner" -g "$notification_state_group" -m 0600 \
        /dev/null "$notification_state_root/PIHOLE_DUALSTACK.state"
    printf '%s\n' "$notification_initial_state" >"$notification_state_root/PIHOLE_DUALSTACK.state"
    printf 'component\tmutation\nnotification\tstandardization\n' \
        >"$evidence_root/mutation.tsv"
    chmod 0600 "$evidence_root/mutation.tsv"
}

accept_notification_standardization() {
    local notification_repository notification_source notification_target notification_mode
    local notification_deployed_hash notification_candidate_hash notification_installed
    local notification_expected_state

    while IFS=$'\t' read -r notification_repository notification_source notification_target \
        notification_mode notification_deployed_hash notification_candidate_hash; do
        notification_installed=$(effective_path "$notification_target")
        require_equal "notification_${notification_target//[^a-zA-Z0-9]/_}_accepted" \
            "$notification_candidate_hash" "$(sha256sum "$notification_installed" | awk '{ print $1 }')"
    done < <(notification_artifact_rows)
    notification_expected_state=BACKUP
    [[ "$node_role" = node-b ]] || notification_expected_state=MASTER
    require_equal notification_bootstrap_state "$notification_expected_state" \
        "$(<"$(effective_path /var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state)")"
    if [[ -z "$target_root" ]]; then
        capture_command notification_caddy_installed_form "$runuser_command" \
            -u keepalived_script -g caddy-tls -- /usr/local/libexec/check-caddy.sh
        capture_command notification_dns_installed_form "$runuser_command" \
            -u pi -- /etc/scripts/check-dns.sh
    fi
    for notification_service in caddy.service pihole-FTL.service unbound.service keepalived.service; do
        require "notification_accepted_${notification_service//[^a-zA-Z0-9]/_}_active" \
            "$systemctl_command" is-active --quiet "$notification_service"
    done
    validate_web_health_queue_permissions
}

rollback_notification_standardization() {
    local notification_repository notification_source notification_target notification_mode
    local notification_deployed_hash notification_candidate_hash notification_state_root
    local notification_parent_owner notification_parent_group
    local notification_state_owner notification_state_group

    while IFS=$'\t' read -r notification_repository notification_source notification_target \
        notification_mode notification_deployed_hash notification_candidate_hash; do
        restore_target "$notification_target"
        require_equal "notification_${notification_target//[^a-zA-Z0-9]/_}_rollback" \
            "$notification_deployed_hash" \
            "$(sha256sum "$(effective_path "$notification_target")" | awk '{ print $1 }')"
    done < <(notification_artifact_rows)
    notification_state_root=$(effective_path /var/lib/caddy-serving-health/keepalived-notify)
    notification_parent_owner=root
    notification_parent_group=root
    notification_state_owner=pi
    notification_state_group=pi
    if [[ -n "$target_root" ]]; then
        notification_parent_owner=$(id -un)
        notification_parent_group=$(id -gn)
        notification_state_owner=$(id -un)
        notification_state_group=$(id -gn)
    fi
    install -o "$notification_state_owner" -g "$notification_state_group" -m 0600 \
        "$evidence_root/notification-state.baseline" \
        "$notification_state_root/PIHOLE_DUALSTACK.state"
    validate_notification_state_contract \
        "$(effective_path /var/lib/caddy-serving-health)" "$notification_state_root" \
        "$(<"$evidence_root/notification-bootstrap-state")" \
        "$notification_parent_owner" "$notification_parent_group" \
        "$notification_state_owner" "$notification_state_group" "$evidence_root"
}

candidate_file() {
    local serving_health_repository=$1
    local serving_health_source=$2
    printf '%s/repositories/%s/%s\n' "$payload_root" "$serving_health_repository" "$serving_health_source"
}

backup_path() {
    local serving_health_target=$1
    printf '%s/backups/%s\n' "$evidence_root" "${serving_health_target#/}"
}

backup_target() {
    local serving_health_target=$1
    local serving_health_backup
    local serving_health_effective_target

    serving_health_backup=$(backup_path "$serving_health_target")
    serving_health_effective_target=$(effective_path "$serving_health_target")
    install -d -m 0700 "$(dirname -- "$serving_health_backup")"
    if [[ -e "$serving_health_effective_target" || -L "$serving_health_effective_target" ]]; then
        cp -a -- "$serving_health_effective_target" "$serving_health_backup"
        printf 'present\n' >"$serving_health_backup.state"
    else
        printf 'absent\n' >"$serving_health_backup.state"
    fi
}

install_target() {
    local serving_health_source=$1
    local serving_health_target=$2
    local serving_health_mode=$3
    local serving_health_owner=$4
    local serving_health_group=$5
    local serving_health_effective_target

    serving_health_effective_target=$(effective_path "$serving_health_target")
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        serving_health_owner=$(id -un)
        serving_health_group=$(id -gn)
    fi

    backup_target "$serving_health_target"
    install -d -m 0755 "$(dirname -- "$serving_health_effective_target")"
    install -o "$serving_health_owner" -g "$serving_health_group" -m "$serving_health_mode" \
        "$serving_health_source" "$serving_health_effective_target"
}

restore_target() {
    local serving_health_target=$1
    local serving_health_backup
    local serving_health_state
    local serving_health_effective_target

    serving_health_backup=$(backup_path "$serving_health_target")
    serving_health_effective_target=$(effective_path "$serving_health_target")
    [[ -f "$serving_health_backup.state" && ! -L "$serving_health_backup.state" ]] || return 0
    serving_health_state=$(<"$serving_health_backup.state")
    case "$serving_health_state" in
        present)
            rm -f -- "$serving_health_effective_target"
            cp -a -- "$serving_health_backup" "$serving_health_effective_target"
            ;;
        absent) rm -f -- "$serving_health_effective_target" ;;
        *) return 1 ;;
    esac
}

install_serving_artifacts() {
    local serving_health_keepalived_source

    "$systemctl_command" stop keepalived.service
    if "$systemctl_command" is-active --quiet keepalived.service; then
        require keepalived_stopped_before_helper_replacement false
    fi
    require keepalived_stopped_before_helper_replacement true

    if [[ "$node_role" = node-a ]]; then
        serving_health_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        serving_health_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
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
    install_target "$(candidate_file homelab-dns "$serving_health_keepalived_source")" \
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
    local serving_health_name serving_health_directory serving_health_status_path
    local serving_health_backup serving_health_expected_metadata serving_health_observed_metadata

    : >"$evidence_root/obsolete-status-disposition.tsv"
    for serving_health_name in dns proxy; do
        serving_health_directory=$(effective_path "/run/caddy-serving-health/$serving_health_name")
        serving_health_backup=$evidence_root/obsolete-status-$serving_health_name
        require "obsolete_status_${serving_health_name}_backup_absent" \
            path_absent "$serving_health_backup"
        if path_absent "$serving_health_directory"; then
            printf '%s\tabsent\n' "$serving_health_name" \
                >>"$evidence_root/obsolete-status-disposition.tsv"
            continue
        fi
        require "obsolete_status_${serving_health_name}_regular_directory" \
            test -d "$serving_health_directory"
        require "obsolete_status_${serving_health_name}_not_symlink" \
            test ! -L "$serving_health_directory"
        require_exact_directory_inventory "obsolete_status_${serving_health_name}" \
            "$serving_health_directory" status
        serving_health_status_path=$serving_health_directory/status
        require "obsolete_status_${serving_health_name}_record_regular" \
            regular_file "$serving_health_status_path"
        require "obsolete_status_${serving_health_name}_record_bounded" \
            test "$(stat -c '%s' "$serving_health_status_path")" -le 4096
        require "obsolete_status_${serving_health_name}_record_schema" \
            grep -Fxq 'schema=caddy-serving-health-status/v1' "$serving_health_status_path"
        serving_health_expected_metadata=pi:pi:755
        [[ "$serving_health_name" = dns ]] ||
            serving_health_expected_metadata=keepalived_script:keepalived_script:755
        if [[ -z "$target_root" ]]; then
            serving_health_observed_metadata=$(stat -c '%U:%G:%a' "$serving_health_directory")
            require_equal "obsolete_status_${serving_health_name}_metadata" \
                "$serving_health_expected_metadata" "$serving_health_observed_metadata"
        fi
        require_equal "obsolete_status_${serving_health_name}_same_filesystem" \
            "$(stat -c '%d' "$serving_health_directory")" "$(stat -c '%d' "$evidence_root")"
        mv -- "$serving_health_directory" "$serving_health_backup"
        printf '%s\tdispositioned\t%s\n' "$serving_health_name" \
            "$(sha256sum "$serving_health_backup/status" | awk '{ print $1 }')" \
            >>"$evidence_root/obsolete-status-disposition.tsv"
    done
    chmod 0600 "$evidence_root/obsolete-status-disposition.tsv"
}

restore_obsolete_status_directories() {
    local serving_health_name serving_health_directory serving_health_backup

    for serving_health_name in dns proxy; do
        serving_health_directory=$(effective_path "/run/caddy-serving-health/$serving_health_name")
        serving_health_backup=$evidence_root/obsolete-status-$serving_health_name
        if [[ -d "$serving_health_backup" && ! -L "$serving_health_backup" ]]; then
            require "obsolete_status_${serving_health_name}_restore_target_absent" \
                path_absent "$serving_health_directory"
            mv -- "$serving_health_backup" "$serving_health_directory"
        fi
    done
}

capture_keepalived_activation_cursor() {
    local serving_health_cursor

    capture_command keepalived_activation_cursor_raw "$journalctl_command" \
        --quiet --no-pager -n 0 --show-cursor
    serving_health_cursor=$(sed -n 's/^-- cursor: //p' \
        "$evidence_root/keepalived_activation_cursor_raw.stdout")
    require keepalived_activation_cursor_exact test -n "$serving_health_cursor"
    printf '%s\n' "$serving_health_cursor" >"$evidence_root/keepalived-activation.cursor"
    chmod 0600 "$evidence_root/keepalived-activation.cursor"
}

daemon_serving_health_acceptance() {
    local serving_health_attempt serving_health_cursor

    [[ "$daemon_observation_attempts" =~ ^([1-9][0-9]|[2-9][0-9]+)$ ]]
    [[ "$daemon_observation_delay" =~ ^[1-9][0-9]*$ ]]
    for ((serving_health_attempt = 1; serving_health_attempt <= daemon_observation_attempts; serving_health_attempt++)); do
        "$sleep_command" "$daemon_observation_delay"
    done

    serving_health_cursor=$(<"$evidence_root/keepalived-activation.cursor")
    capture_command keepalived_daemon_journal "$journalctl_command" --no-pager \
        -o short-iso-precise --after-cursor "$serving_health_cursor" \
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
    local serving_health_keepalived_source

    if [[ "$node_role" = node-a ]]; then
        serving_health_keepalived_source=Keepalived/configs/keepalived-pihole0.conf
    else
        serving_health_keepalived_source=Keepalived/configs/keepalived-pihole00.conf
    fi
    capture_command unbound_local_zone_parser "$unbound_checkconf_command" \
        "$(candidate_file homelab-dns Unbound/configs/pihole-local-zone.conf)"
    capture_stdin_command dns_identity \
        "$(candidate_file homelab-dns Keepalived/scripts/dns-check.sh)" \
        "$runuser_command" -u pi -- env \
        DNS_CHECK_DIG_COMMAND="${CADDY_SERVING_HEALTH_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        DNS_CHECK_SYSTEMCTL_COMMAND="${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
    capture_stdin_command caddy_identity \
        "$(candidate_file homelab-server-configs Caddy/scripts/check-caddy-serving-health.sh)" \
        "$runuser_command" -u keepalived_script -g caddy-tls -- env \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$node_environment" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="${CADDY_SERVING_HEALTH_CURL_COMMAND:-/usr/bin/curl}" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="${CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND:-/usr/bin/systemctl}" \
        /bin/bash -s
}

promote_local_candidate() {
    local serving_health_source=$outgoing_root/$serving_revision
    local serving_health_destination=$incoming_root/node-a/$serving_revision

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    require local_incoming_absent test ! -e "$serving_health_destination"
    local serving_health_promotion_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$serving_health_source" "$serving_health_destination" &&
        chown -R "$sync_user:$sync_group" "$serving_health_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require local_candidate_selected test "$(current_revision)" = "$serving_revision"; then
        :
    else
        serving_health_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || serving_health_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || serving_health_promotion_status=125
    return "$serving_health_promotion_status"
}

publish_current_release() {
    local serving_health_source=$evidence_root/new-release-source
    local serving_health_before=$evidence_root/outbound-before-publish
    local serving_health_after=$evidence_root/outbound-after-publish
    local serving_health_revision

    [[ "$node_role" = node-a ]]
    require_equal publish_parent_release "$serving_revision" "$(current_revision)"
    require outbound_empty_before_publish require_exact_directory_inventory \
        outbound_before_publish "$outgoing_root" ''
    require new_release_source_absent path_absent "$serving_health_source"
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
        LC_ALL=C sort >"$serving_health_before"
    install -d -m 0700 "$serving_health_source"
    cp -a -- "$(effective_path /etc/caddy/current)/." "$serving_health_source/"
    find "$serving_health_source" -type d -exec chmod u+rwx {} +
    find "$serving_health_source" -type f -exec chmod u+rw {} +
    rm -f -- "$serving_health_source/.complete" \
        "$serving_health_source/.complete.pending" \
        "$serving_health_source/.finalize-request" \
        "$serving_health_source/manifest.sha256" \
        "$serving_health_source/release-manifest.json"
    require publish_source_conf_directory test -d "$serving_health_source/conf.d"
    install -m 0640 \
        "$(candidate_file homelab-server-configs Caddy/configs/caddy/conf.d/10-pihole-admin.caddy)" \
        "$serving_health_source/conf.d/10-pihole-admin.caddy"
    capture_command publish_release "$publisher_command" --source "$serving_health_source" \
        --node-role node-a
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
        LC_ALL=C sort >"$serving_health_after"
    serving_health_revision=$(comm -13 "$serving_health_before" "$serving_health_after")
    require target_revision_single test "$(wc -l <<<"$serving_health_revision")" -eq 1
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require target_revision_shape /bin/bash -c \
        '[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]' _ "$serving_health_revision"
    require target_revision_reported grep -Fxq \
        "Published protocol-v2 release $serving_health_revision for receiver validation." \
        "$evidence_root/publish_release.stdout"
    printf '%s\n' "$serving_health_revision" >"$evidence_root/target-revision"
    chmod 0600 "$evidence_root/target-revision"
    require target_candidate_parent test \
        "$(jq -r '.parent_revision // empty' "$outgoing_root/$serving_health_revision/release-manifest.json")" = \
        "$serving_revision"
    require target_candidate_source test \
        "$(jq -r '.source_node // empty' "$outgoing_root/$serving_health_revision/release-manifest.json")" = \
        node-a
    require target_candidate_caddy_payload test \
        "$(sha256sum "$outgoing_root/$serving_health_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
    rm -rf -- "$serving_health_source"
    printf 'Published protocol-v2 release %s for receiver validation.\n' \
        "$serving_health_revision"
}

record_target_revision() {
    local serving_health_revision=${target_revision_argument:-}

    [[ "$serving_health_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    require target_revision_absent path_absent "$evidence_root/target-revision"
    printf '%s\n' "$serving_health_revision" >"$evidence_root/target-revision"
    chmod 0600 "$evidence_root/target-revision"
}

wait_for_target_release() {
    local serving_health_revision serving_health_attempt

    [[ "$node_role" = node-b ]]
    serving_health_revision=$(target_revision)
    for ((serving_health_attempt = 1; serving_health_attempt <= 60; serving_health_attempt++)); do
        if [[ "$(current_revision)" = "$serving_health_revision" ]]; then
            break
        fi
        "$sleep_command" 1
    done
    require_equal target_release_selected "$serving_health_revision" "$(current_revision)"
    require target_release_regular test -d "$releases_root/$serving_health_revision"
    require target_release_not_symlink test ! -L "$releases_root/$serving_health_revision"
    require target_release_caddy_payload test \
        "$(sha256sum "$releases_root/$serving_health_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
}

promote_target_candidate() {
    local serving_health_revision serving_health_source serving_health_destination
    local serving_health_promotion_status=0

    [[ "$node_role" = node-a ]]
    serving_health_revision=$(target_revision)
    serving_health_source=$outgoing_root/$serving_health_revision
    serving_health_destination=$incoming_root/node-a/$serving_health_revision
    require target_outbound_regular test -d "$serving_health_source"
    require target_outbound_not_symlink test ! -L "$serving_health_source"
    require target_outbound_revision test \
        "$(jq -r '.revision // empty' "$serving_health_source/release-manifest.json")" = \
        "$serving_health_revision"
    require target_outbound_parent test \
        "$(jq -r '.parent_revision // empty' "$serving_health_source/release-manifest.json")" = \
        "$serving_revision"
    # The child Bash expands its positional parameter.
    # shellcheck disable=SC2016
    require target_outbound_manifest_valid /bin/bash -c \
        'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$serving_health_source"
    require target_local_incoming_absent path_absent "$serving_health_destination"
    "$systemctl_command" stop caddy-lsyncd.service
    "$systemctl_command" stop caddy-sync-reconcile.path
    if install -d -o "$sync_user" -g "$sync_group" -m 0750 "$incoming_root/node-a" &&
        cp -a -- "$serving_health_source" "$serving_health_destination" &&
        chown -R "$sync_user:$sync_group" "$serving_health_destination" &&
        "$runuser_command" -u caddy-sync -- /bin/bash \
            "$finalizer_command" --source-role node-a &&
        "$systemctl_command" start caddy-sync-reconcile.service &&
        require_equal target_local_selected "$serving_health_revision" "$(current_revision)"; then
        :
    else
        serving_health_promotion_status=$?
    fi
    "$systemctl_command" start caddy-sync-reconcile.path || serving_health_promotion_status=125
    "$systemctl_command" start caddy-lsyncd.service || serving_health_promotion_status=125
    return "$serving_health_promotion_status"
}

accept_installed_node() {
    local serving_health_keepalived_hash serving_health_dns_hash serving_health_caddy_hash
    local serving_health_service_hash serving_health_timer_hash serving_health_local_zone_hash
    local serving_health_enqueue_hash serving_health_sync_notifier_hash
    local serving_health_keepalived_notifier_hash serving_health_tmpfiles_hash

    serving_health_keepalived_hash=$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')
    serving_health_dns_hash=$(sha256sum /etc/scripts/check-dns.sh | awk '{ print $1 }')
    serving_health_caddy_hash=$(sha256sum /usr/local/libexec/check-caddy.sh | awk '{ print $1 }')
    serving_health_service_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.service | awk '{ print $1 }')
    serving_health_timer_hash=$(sha256sum /etc/systemd/system/caddy-pihole-web-health.timer | awk '{ print $1 }')
    serving_health_local_zone_hash=$(sha256sum /etc/unbound/unbound.conf.d/pihole-local-zone.conf | awk '{ print $1 }')
    serving_health_enqueue_hash=$(sha256sum /usr/local/libexec/caddy-apprise-enqueue | awk '{ print $1 }')
    serving_health_sync_notifier_hash=$(sha256sum /usr/local/libexec/lsyncd-sync-failure-notify.sh | awk '{ print $1 }')
    serving_health_keepalived_notifier_hash=$(sha256sum /usr/local/bin/keepalived-notify.sh | awk '{ print $1 }')
    serving_health_tmpfiles_hash=$(sha256sum /etc/tmpfiles.d/caddy-ha.conf | awk '{ print $1 }')
    if [[ "$node_role" = node-a ]]; then
        require keepalived_candidate_hash test "$serving_health_keepalived_hash" = \
            de67123685edb21cdfaee95eb0497d9ab527c546cf730a5f51506bc293eab92a
    else
        require keepalived_candidate_hash test "$serving_health_keepalived_hash" = \
            cb4749c6f9e1a247dc481809652470e5b35c5ea3992e87945bada9292f5cbd66
    fi
    require dns_candidate_hash test "$serving_health_dns_hash" = \
        10bbabead80305d57e8be420d521ff28883e5dbdbb81d4d4e680c05cd6848279
    require caddy_candidate_hash test "$serving_health_caddy_hash" = \
        60c2c196e75a17452d16174b08f9ba20d63699b2931a7ccf69779e55b96ddc32
    require web_service_hash test "$serving_health_service_hash" = \
        a1afee302fa521c9d4ba2eb6d7085e98f261ec5fdd464c156dd11aa1f1cfa3f0
    require web_timer_hash test "$serving_health_timer_hash" = \
        f214b69fecaeb322dbaba61f683f9cf35970596784adcd707e25278f0ace1505
    require unbound_local_zone_hash test "$serving_health_local_zone_hash" = \
        f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d
    require enqueue_candidate_hash test "$serving_health_enqueue_hash" = \
        5101792e178ede8f6ae4cae23f9d22d57bd4c453c3578dc164175a57fe4dc56f
    require sync_notifier_candidate_hash test "$serving_health_sync_notifier_hash" = \
        278e0ff1695feca3806f24cf74c6e4007723e0b8ddbb086aaf1e121d7e9c183c
    require keepalived_notifier_candidate_hash test "$serving_health_keepalived_notifier_hash" = \
        ffaf6d7e09b808dd71848ca481da01e144c715a305858d2922accedaecb5aabf
    require tmpfiles_candidate_hash test "$serving_health_tmpfiles_hash" = \
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
    local serving_health_revision

    serving_health_revision=$(target_revision)
    require selected_release test "$(current_revision)" = "$serving_health_revision"
    validate_installed_candidate_inventory
    validate_services
    require legacy_lighttpd_helper_absent path_absent \
        "$(effective_path "$legacy_lighttpd_helper")"
    if [[ "$node_role" = node-a ]]; then
        require incoming_node_a_empty require_empty_or_absent_sync_directory \
            incoming_node_a "$incoming_root/node-a"
        require incoming_node_b_empty require_empty_or_absent_sync_directory \
            incoming_node_b "$incoming_root/node-b"
    else
        require incoming_node_a_empty require_empty_or_absent_sync_directory \
            incoming_node_a "$incoming_root/node-a"
        require incoming_node_b_absent path_absent "$incoming_root/node-b"
    fi
    require quarantine_inventory_empty require_exact_directory_inventory \
        quarantine "$quarantine_root" ''
    require outbound_inventory_empty require_exact_directory_inventory outbound "$outgoing_root" ''
    require final_target_release_regular test -d "$releases_root/$serving_health_revision"
    require final_target_release_not_symlink test ! -L "$releases_root/$serving_health_revision"
    require final_target_caddy_payload test \
        "$(sha256sum "$releases_root/$serving_health_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
        8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8
}

rollback_node() {
    local serving_health_target
    local serving_health_release_source
    local serving_health_new_revision=
    local serving_health_restore_failed=0

    "$systemctl_command" stop keepalived.service || serving_health_restore_failed=1

    if [[ "$node_role" = node-b ]]; then
        restore_retained_node_b_entry || serving_health_restore_failed=1
        restore_target "$legacy_lighttpd_helper" || serving_health_restore_failed=1
    else
        restore_node_a_quarantine || serving_health_restore_failed=1
    fi

    for serving_health_target in \
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
        restore_target "$serving_health_target" || serving_health_restore_failed=1
    done
    "$systemctl_command" disable --now caddy-pihole-web-health.timer \
        >/dev/null 2>&1 || :
    for serving_health_target in \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV4 \
        /run/caddy-serving-health/keepalived/PIHOLE_IPV6; do
        serving_health_target=$(effective_path "$serving_health_target")
        if [[ -e "$serving_health_target" || -L "$serving_health_target" ]]; then
            if [[ "$serving_health_target" = */keepalived/* ]]; then
                if [[ -f "$serving_health_target" && ! -L "$serving_health_target" &&
                    "$(stat -c '%U:%G:%a' "$serving_health_target")" = root:root:644 &&
                    "$(wc -l <"$serving_health_target")" -eq 1 ]] &&
                    grep -Eq '^[A-Z_]{1,32}$' "$serving_health_target"; then
                    rm -f -- "$serving_health_target" || serving_health_restore_failed=1
                else
                    serving_health_restore_failed=1
                fi
            else
                serving_health_restore_failed=1
            fi
        fi
    done
    rmdir "$(effective_path /run/caddy-serving-health/keepalived)" \
        "$(effective_path /run/caddy-serving-health)" 2>/dev/null || {
        [[ ! -d "$(effective_path /run/caddy-serving-health)" ]] ||
            serving_health_restore_failed=1
    }
    restore_obsolete_status_directories || serving_health_restore_failed=1
    "$systemctl_command" daemon-reload || serving_health_restore_failed=1
    if [[ -n "$target_root" ]]; then
        serving_health_target=$(effective_path /etc/unbound/unbound.conf.d/pihole-local-zone.conf)
        if [[ -f "$serving_health_target" && ! -L "$serving_health_target" ]]; then
            "$unbound_checkconf_command" "$serving_health_target" || serving_health_restore_failed=1
        fi
    else
        "$unbound_checkconf_command" /etc/unbound/unbound.conf || serving_health_restore_failed=1
    fi
    "$systemctl_command" reload unbound.service || serving_health_restore_failed=1
    if regular_file "$evidence_root/target-revision"; then
        serving_health_new_revision=$(target_revision) || serving_health_restore_failed=1
    fi
    if [[ -z "$target_root" ]]; then
        local serving_health_original_revision=$serving_revision
        [[ "$node_role" = node-b ]] || serving_health_original_revision=$node_a_revision
        if [[ "$(current_revision)" != "$serving_health_original_revision" ]]; then
            require rollback_original_release_regular test \
                -d "$releases_root/$serving_health_original_revision" || serving_health_restore_failed=1
            if [[ "$serving_health_restore_failed" -eq 0 ]]; then
                ln -sfn "$releases_root/$serving_health_original_revision" /etc/caddy/current.rollback
                mv -Tf /etc/caddy/current.rollback /etc/caddy/current
                "$systemctl_command" reload caddy.service || serving_health_restore_failed=1
            fi
        fi
    fi
    if [[ -z "$target_root" && -n "$serving_health_new_revision" &&
        -d "$releases_root/$serving_health_new_revision" ]]; then
        require rollback_target_release_not_active test \
            "$(current_revision)" != "$serving_health_new_revision" || serving_health_restore_failed=1
        require rollback_target_revision_exact test \
            "$(jq -r '.revision // empty' "$releases_root/$serving_health_new_revision/release-manifest.json")" = \
            "$serving_health_new_revision" || serving_health_restore_failed=1
        require rollback_target_parent_exact test \
            "$(jq -r '.parent_revision // empty' "$releases_root/$serving_health_new_revision/release-manifest.json")" = \
            "$serving_revision" || serving_health_restore_failed=1
        require rollback_target_payload_exact test \
            "$(sha256sum "$releases_root/$serving_health_new_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = \
            8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8 ||
            serving_health_restore_failed=1
        if [[ "$serving_health_restore_failed" -eq 0 ]]; then
            rm -rf -- "${releases_root:?}/${serving_health_new_revision:?}"
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$releases_root/$serving_revision" ]]; then
        serving_health_release_source=$outgoing_root/$serving_revision
        if [[ -d "$evidence_root/consumed-outbound" ]]; then
            serving_health_release_source=$evidence_root/consumed-outbound
        fi
        if [[ -d "$serving_health_release_source" ]] &&
            diff -qr --exclude=.complete "$serving_health_release_source" \
                "$releases_root/$serving_revision" >/dev/null; then
            rm -rf -- "${releases_root:?}/${serving_revision:?}"
        else
            serving_health_restore_failed=1
        fi
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -d "$evidence_root/consumed-outbound" &&
        ! -e "$outgoing_root/$serving_revision" ]]; then
        mv -- "$evidence_root/consumed-outbound" \
            "$outgoing_root/$serving_revision" || serving_health_restore_failed=1
    fi
    if [[ -z "$target_root" && "$node_role" = node-a &&
        -n "$serving_health_new_revision" &&
        -d "$outgoing_root/$serving_health_new_revision" ]]; then
        require rollback_target_outbound_revision test \
            "$(jq -r '.revision // empty' "$outgoing_root/$serving_health_new_revision/release-manifest.json")" = \
            "$serving_health_new_revision" || serving_health_restore_failed=1
        require rollback_target_outbound_parent test \
            "$(jq -r '.parent_revision // empty' "$outgoing_root/$serving_health_new_revision/release-manifest.json")" = \
            "$serving_revision" || serving_health_restore_failed=1
        if [[ "$serving_health_restore_failed" -eq 0 ]]; then
            rm -rf -- "${outgoing_root:?}/${serving_health_new_revision:?}"
        fi
    fi
    "$systemctl_command" start keepalived.service || serving_health_restore_failed=1
    if [[ -z "$target_root" ]]; then
        capture_command journal_rollback "$journalctl_command" --no-pager -o short-iso-precise \
            --after-cursor "$(<"$evidence_root/journal.cursor")" \
            -u keepalived.service -u caddy.service -u caddy-lsyncd.service \
            -u caddy-sync-reconcile.service -u caddy-pihole-web-health.service \
            -t keepalived-notify -t caddy-ha-health || :
    fi
    [[ "$serving_health_restore_failed" -eq 0 ]]
}

consume_outbound() {
    local serving_health_source=$outgoing_root/$serving_revision
    local serving_health_destination=$evidence_root/consumed-outbound

    [[ "$node_role" = node-a ]]
    validate_outbound_candidate
    validate_installed_release
    require consumed_backup_absent test ! -e "$serving_health_destination"
    # The child Bash expands its positional parameters.
    # shellcheck disable=SC2016
    require installed_and_outbound_equal \
        /bin/bash -c 'diff -qr --exclude=.complete "$1" "$2" >/dev/null' \
        _ "$serving_health_source" "$releases_root/$serving_revision"
    local serving_health_consume_status=0

    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$serving_health_source" "$serving_health_destination" || serving_health_consume_status=$?
    "$systemctl_command" start caddy-lsyncd.service || serving_health_consume_status=125
    [[ "$serving_health_consume_status" -eq 0 ]] || return "$serving_health_consume_status"
    require outbound_consumed test ! -e "$serving_health_source"
}

consume_target_outbound() {
    local serving_health_revision serving_health_source serving_health_destination

    [[ "$node_role" = node-a ]]
    serving_health_revision=$(target_revision)
    serving_health_source=$outgoing_root/$serving_health_revision
    serving_health_destination=$evidence_root/consumed-target-outbound
    require target_selected_before_consume test "$(current_revision)" = "$serving_health_revision"
    require target_outbound_before_consume test -d "$serving_health_source"
    require target_consumed_backup_absent path_absent "$serving_health_destination"
    "$systemctl_command" stop caddy-lsyncd.service
    mv -- "$serving_health_source" "$serving_health_destination"
    "$systemctl_command" start caddy-lsyncd.service || return 125
    require target_outbound_consumed path_absent "$serving_health_source"
}

produce_bounded_evidence() {
    capture_command payload_identity sha256sum \
        "$payload_root/manifests/serving-health-production.tsv"
}

ownership_sample() {
    local serving_health_ipv4_state serving_health_ipv6_state serving_health_addresses
    local serving_health_expected_state serving_health_expected_vips
    local serving_health_vip_count serving_health_attempt serving_health_stable=0
    local serving_health_sample_valid

    serving_health_expected_state=Backup
    serving_health_expected_vips=0
    if [[ "$node_role" = node-a ]]; then
        serving_health_expected_state=Master
        serving_health_expected_vips=4
    fi
    : >"$evidence_root/ownership-samples.tsv"
    chmod 0600 "$evidence_root/ownership-samples.tsv"
    for ((serving_health_attempt = 1; serving_health_attempt <= ownership_attempts; serving_health_attempt++)); do
        serving_health_ipv4_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        serving_health_ipv6_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        serving_health_addresses=$("$ip_command" -o address show dev eth0)
        serving_health_vip_count=0
        grep -Fq ' 10.1.0.55/22 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' 10.1.0.56/22 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        printf '%s\t%s\t%s\t%s\t%s\n' "$serving_health_attempt" \
            "$($date_command -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
            "$serving_health_ipv4_state" "$serving_health_ipv6_state" "$serving_health_vip_count" \
            >>"$evidence_root/ownership-samples.tsv"

        serving_health_sample_valid=false
        if [[ "$serving_health_ipv4_state" = "$serving_health_ipv6_state" ]]; then
            case "$serving_health_ipv4_state:$serving_health_vip_count" in
                "$serving_health_expected_state:$serving_health_expected_vips")
                    serving_health_sample_valid=true
                    serving_health_stable=$((serving_health_stable + 1))
                    ;;
                Fault:0 | Backup:0)
                    serving_health_stable=0
                    ;;
                *)
                    require ownership_incorrect_state false
                    ;;
            esac
        else
            require ownership_split_family false
        fi
        if [[ "$serving_health_sample_valid" = true &&
            "$serving_health_stable" -ge "$ownership_stable_samples" ]]; then
            printf 'ipv4=%s\nipv6=%s\nshared_vips=%s\nstable_samples=%s\n' \
                "$serving_health_ipv4_state" "$serving_health_ipv6_state" \
                "$serving_health_vip_count" "$serving_health_stable"
            require ownership_ipv4 test "$serving_health_ipv4_state" = "$serving_health_expected_state"
            require ownership_ipv6 test "$serving_health_ipv6_state" = "$serving_health_expected_state"
            require ownership_vips test "$serving_health_vip_count" -eq "$serving_health_expected_vips"
            require ownership_stable test "$serving_health_stable" -ge "$ownership_stable_samples"
            return 0
        fi
        "$sleep_command" "$ownership_sample_delay"
    done
    require ownership_convergence false
}

capture_journal_cursor() {
    local serving_health_cursor

    capture_command journal_cursor_raw "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    serving_health_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal_cursor_raw.stdout")
    require journal_cursor_exact test -n "$serving_health_cursor"
    printf '%s\n' "$serving_health_cursor" >"$evidence_root/journal.cursor"
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
    local serving_health_sampler=$evidence_root/availability-sampler.sh
    local serving_health_observer=$evidence_root/vip-address-observer.sh

    require sampler_pid_absent test ! -e "$evidence_root/availability.pid"
    require observer_pid_absent test ! -e "$evidence_root/vip-address-monitor.pid"
    printf 'baseline\n' >"$evidence_root/availability.scenario"
    chmod 0600 "$evidence_root/availability.scenario"
    cat >"$serving_health_sampler" <<'SAMPLER'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
readonly role=$1 root=$2 dig_command=$3 curl_command=$4 date_command=$5 sleep_command=$6
readonly busctl_command=$7 ip_command=$8
readonly max_cycles=$9 sampler_delay=${10}
[[ "$max_cycles" =~ ^[1-9][0-9]*$ && "$sampler_delay" =~ ^(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]
case "$role" in
    node-a) fqdn=pihole0.local.theama.co; ipv4=10.1.0.53; ipv6=fd36:5aa8:6971:1::53 ;;
    node-b) fqdn=pihole00.local.theama.co; ipv4=10.1.0.54; ipv6=fd36:5aa8:6971:1::54 ;;
    *) exit 64 ;;
esac
readonly fqdn ipv4 ipv6
readonly records=$root/availability.tsv scenario_file=$root/availability.scenario
readonly work=$root/availability-work
install -d -m 0700 "$work"
cleanup() { rm -f -- "$work"/* 2>/dev/null || :; rmdir -- "$work" 2>/dev/null || :; }
trap 'exit 143' TERM INT HUP
trap cleanup EXIT

stderr_class() {
    local status=$1 file=$2
    if [[ "$status" -eq 0 && ! -s "$file" ]]; then printf none
    elif grep -Eqi 'timed out|timeout' "$file"; then printf timeout
    elif grep -Eqi 'connection refused|failed to connect' "$file"; then printf connection-refused
    elif grep -Eqi 'connection reset|send failure' "$file"; then printf connection-reset
    elif grep -Eqi 'no route|network is unreachable' "$file"; then printf routing-failure
    elif grep -Eqi 'certificate|tls' "$file"; then printf tls-verification
    elif grep -Eqi 'host name|hostname' "$file"; then printf hostname-mismatch
    elif [[ "$status" -ne 0 ]]; then printf 'command-exit-%s' "$status"
    else printf bounded-stderr; fi
}

ownership() {
    local state4 state6 addresses count=0
    state4=$("$busctl_command" get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
        org.keepalived.Vrrp1.Instance State 2>/dev/null |
        sed -n 's/.*"\([^"]*\)".*/\1/p') || state4=unavailable
    state6=$("$busctl_command" get-property org.keepalived.Vrrp1 \
        /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
        org.keepalived.Vrrp1.Instance State 2>/dev/null |
        sed -n 's/.*"\([^"]*\)".*/\1/p') || state6=unavailable
    addresses=$("$ip_command" -o address show dev eth0 2>/dev/null) || addresses=
    grep -Fq ' 10.1.0.55/22 ' <<<"$addresses" && count=$((count + 1))
    grep -Fq ' 10.1.0.56/22 ' <<<"$addresses" && count=$((count + 1))
    grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$addresses" && count=$((count + 1))
    grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$addresses" && count=$((count + 1))
    printf '%s\t%s\t%s' "${state4:-unavailable}" "${state6:-unavailable}" "$count"
}

safe_record() {
    local file=$1
    [[ "$(stat -c '%s' "$file")" -le 4096 ]]
    iconv -f UTF-8 -t UTF-8 "$file" >/dev/null
    ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$file"
}

record_dns() {
    local attempt=$1 family=$2 endpoint=$3 expected=$4 type=$5
    local stdout=$work/$sequence-dns-$family-$attempt.stdout
    local stderr=$work/$sequence-dns-$family-$attempt.stderr
    local start end status=0 answer result=failure class ownership_fields scenario
    start=$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)
    if "$dig_command" "@$endpoint" -p 53 pihole.local.theama.co "$type" \
        +short +time=1 +tries=1 >"$stdout" 2>"$stderr"; then status=0; else status=$?; fi
    end=$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)
    safe_record "$stdout"; safe_record "$stderr"
    answer=$(tr -d '\r\n' <"$stdout")
    [[ "$answer" != *$'\t'* && ${#answer} -le 256 ]]
    class=$(stderr_class "$status" "$stderr")
    [[ "$status" -eq 0 && "$answer" = "$expected" ]] && result=success
    [[ "$status" -ne 0 || "$answer" = "$expected" ]] || class=dns-answer-mismatch
    ownership_fields=$(ownership); scenario=$(<"$scenario_file")
    printf '%s\t%s\t%s\tdns\t%s\t%s\t53\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\t-\t-\t%s\n' \
        "$role" "$scenario" "$sequence" "$family" "$endpoint" "$attempt" "$start" "$end" \
        "$status" "$result" "$answer" "$class" "$ownership_fields" >>"$records"
    rm -f -- "$stdout" "$stderr"
    [[ "$result" = success ]]
}

record_curl() {
    local attempt=$1 probe=$2 family=$3 endpoint=$4 address=$5 path=$6 expected=$7 redirects=$8
    local stdout=$work/$sequence-$probe-$family-$attempt.stdout
    local stderr=$work/$sequence-$probe-$family-$attempt.stderr
    local start end status=0 result=failure class scenario ownership_fields
    local http connect tls first total remote local_ip value
    start=$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)
    if "$curl_command" "--ipv$family" --silent --show-error --fail --location --max-time 2 \
        --max-redirs "$redirects" \
        --resolve "$endpoint:443:$address" "https://$endpoint$path" --output /dev/null \
        --write-out $'%{http_code}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}\t%{time_total}\t%{remote_ip}\t%{local_ip}' \
        >"$stdout" 2>"$stderr"; then status=0; else status=$?; fi
    end=$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)
    safe_record "$stdout"; safe_record "$stderr"
    IFS=$'\t' read -r http connect tls first total remote local_ip <"$stdout" || :
    for value in "${http:--}" "${connect:--}" "${tls:--}" "${first:--}" \
        "${total:--}" "${remote:--}" "${local_ip:--}"; do
        [[ "$value" != *$'\t'* && "$value" != *$'\n'* && ${#value} -le 256 ]]
    done
    class=$(stderr_class "$status" "$stderr")
    if [[ "$status" -eq 0 && "$http" = "$expected" ]]; then result=success
    elif [[ "$status" -eq 0 ]]; then class=http-status; fi
    ownership_fields=$(ownership); scenario=$(<"$scenario_file")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t443\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$role" "$scenario" "$sequence" "$probe" "$family" "$endpoint" "$attempt" \
        "$start" "$end" "$status" "$result" "${http:--}" "$class" "${connect:--}" \
        "${tls:--}" "${first:--}" "${total:--}" "${remote:--}" "${local_ip:--}" \
        "$ownership_fields" >>"$records"
    rm -f -- "$stdout" "$stderr"
    [[ "$result" = success ]]
}

retry_dns() { record_dns primary "$@" || { record_dns retry "$@" || :; return 1; }; }
retry_curl() { record_curl primary "$@" || { record_curl retry "$@" || :; return 1; }; }

sequence=0
while [[ ! -e "$root/availability.stop" && "$sequence" -lt "$max_cycles" ]]; do
    sequence=$((sequence + 1))
    for family in 4 6; do
        if [[ "$family" = 4 ]]; then
            server=10.1.0.55; address=$ipv4; shared_address=10.1.0.56
            type=A; expected=10.1.0.55
        else
            server=fd36:5aa8:6971:1::55; address="[$ipv6]"
            shared_address='[fd36:5aa8:6971:1::56]'; type=AAAA
            expected=fd36:5aa8:6971:1::55
        fi
        retry_dns "$family" "$server" "$expected" "$type" || :
        retry_curl proxy_https "$family" proxy.local.theama.co "$shared_address" / 204 0 || :
        retry_curl node_ui "$family" "$fqdn" "$address" /admin/login.php 200 2 || :
        retry_curl shared_ui "$family" pihole-admin.local.theama.co "$shared_address" \
            /admin/login.php 200 2 || :
    done
    "$sleep_command" "$sampler_delay"
done
SAMPLER
    cat >"$serving_health_observer" <<'OBSERVER'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
readonly root=$1 ip_command=$2 date_command=$3
monitor_pid=
terminate() {
    if [[ -n "$monitor_pid" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
        kill -TERM "$monitor_pid" 2>/dev/null || :
        for _ in 1 2 3 4 5; do
            kill -0 "$monitor_pid" 2>/dev/null || break
            /usr/bin/sleep 0.1
        done
        kill -KILL "$monitor_pid" 2>/dev/null || :
        wait "$monitor_pid" 2>/dev/null || :
    fi
    printf 'observer-end\t%s\tstatus=143\n' \
        "$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
        >>"$root/vip-address-monitor.tsv"
    exit 143
}
trap terminate TERM INT HUP
printf 'observer-start\t%s\tuid=%s\tgid=%s\n' \
    "$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)" "$(id -u)" "$(id -g)" \
    >>"$root/vip-address-monitor.tsv"
coproc VIP_MONITOR {
    exec "$ip_command" -o monitor address dev eth0 2>"$root/vip-address-monitor.stderr"
}
monitor_pid=$VIP_MONITOR_PID
while IFS= read -r line <&"${VIP_MONITOR[0]}"; do
    [[ ${#line} -le 2048 && "$line" != *$'\t'* && "$line" != *$'\r'* ]]
    printf 'address-event\t%s\t%s\n' \
        "$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)" "$line" \
        >>"$root/vip-address-monitor.tsv"
done
if wait "$monitor_pid"; then monitor_status=0; else monitor_status=$?; fi
printf 'observer-end\t%s\tstatus=%s\n' \
    "$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)" "$monitor_status" \
    >>"$root/vip-address-monitor.tsv"
exit "$monitor_status"
OBSERVER
    chmod 0700 "$serving_health_sampler" "$serving_health_observer"
    printf '%s\n' $'role\tscenario\tsequence\tprobe\tfamily\tendpoint\tport\tattempt\tstart\tend\texit_status\tresult\tvalue\tstderr_class\tconnect\ttls\tfirst_byte\ttotal\tremote\tlocal\tstate4\tstate6\tvip_count' \
        >"$evidence_root/availability.tsv"
    : >"$evidence_root/vip-address-monitor.tsv"
    : >"$evidence_root/vip-address-monitor.stderr"
    chmod 0600 "$evidence_root/availability.tsv" "$evidence_root/vip-address-monitor.tsv" \
        "$evidence_root/vip-address-monitor.stderr"
    nohup /bin/bash "$serving_health_observer" "$evidence_root" "$ip_command" "$date_command" \
        >"$evidence_root/vip-address-monitor.stdout" \
        2>>"$evidence_root/vip-address-monitor.stderr" &
    printf '%s\n' "$!" >"$evidence_root/vip-address-monitor.pid"
    chmod 0600 "$evidence_root/vip-address-monitor.pid"
    nohup /bin/bash "$serving_health_sampler" "$node_role" "$evidence_root" \
        "${CADDY_SERVING_HEALTH_DNS_DIG_COMMAND:-/usr/bin/dig}" \
        "${CADDY_SERVING_HEALTH_CURL_COMMAND:-/usr/bin/curl}" \
        "$date_command" "$sleep_command" "$busctl_command" "$ip_command" \
        "${CADDY_SERVING_HEALTH_SAMPLER_MAX_CYCLES:-900}" \
        "${CADDY_SERVING_HEALTH_SAMPLER_DELAY:-1}" \
        >"$evidence_root/availability.stdout" 2>"$evidence_root/availability.stderr" &
    printf '%s\n' "$!" >"$evidence_root/availability.pid"
    chmod 0600 "$evidence_root/availability.pid"
}

set_sampler_scenario() {
    [[ "$target_revision_argument" =~ ^(baseline|final|node-[ab]-(caddy|lighttpd|pihole-ftl|unbound|keepalived))$ ]]
    regular_file "$evidence_root/availability.scenario"
    printf '%s\n' "$target_revision_argument" >"$evidence_root/availability.scenario.next"
    chmod 0600 "$evidence_root/availability.scenario.next"
    mv -T -- "$evidence_root/availability.scenario.next" "$evidence_root/availability.scenario"
}

stop_sampler() {
    local serving_health_pid serving_health_observer_pid serving_health_wait

    serving_health_terminate_pid() {
        local serving_health_target_pid=$1
        local serving_health_target_wait

        kill -TERM "$serving_health_target_pid" 2>/dev/null || :
        for ((serving_health_target_wait = 0; serving_health_target_wait < 20; serving_health_target_wait++)); do
            kill -0 "$serving_health_target_pid" 2>/dev/null || return 0
            /usr/bin/sleep 0.1
        done
        kill -KILL "$serving_health_target_pid" 2>/dev/null || :
        for ((serving_health_target_wait = 0; serving_health_target_wait < 20; serving_health_target_wait++)); do
            kill -0 "$serving_health_target_pid" 2>/dev/null || return 0
            /usr/bin/sleep 0.1
        done
        return 1
    }

    regular_file "$evidence_root/availability.pid"
    serving_health_pid=$(<"$evidence_root/availability.pid")
    [[ "$serving_health_pid" =~ ^[1-9][0-9]*$ ]]
    : >"$evidence_root/availability.stop"
    for ((serving_health_wait = 0; serving_health_wait < 10; serving_health_wait++)); do
        kill -0 "$serving_health_pid" 2>/dev/null || break
        "$sleep_command" 1
    done
    if kill -0 "$serving_health_pid" 2>/dev/null; then
        serving_health_terminate_pid "$serving_health_pid"
    fi
    regular_file "$evidence_root/vip-address-monitor.pid"
    serving_health_observer_pid=$(<"$evidence_root/vip-address-monitor.pid")
    [[ "$serving_health_observer_pid" =~ ^[1-9][0-9]*$ ]]
    serving_health_terminate_pid "$serving_health_observer_pid"
    # shellcheck disable=SC2016
    require availability_schema awk -F '\t' '
        NR == 1 { next }
        NF != 23 { exit 1 }
        $1 !~ /^node-[ab]$/ || $2 !~ /^(baseline|final|node-[ab]-(caddy|lighttpd|pihole-ftl|unbound|keepalived))$/ ||
        $3 !~ /^[1-9][0-9]*$/ || $4 !~ /^(dns|proxy_https|node_ui|shared_ui)$/ ||
        $5 !~ /^[46]$/ || $7 !~ /^(53|443)$/ || $8 !~ /^(primary|retry)$/ ||
        $11 !~ /^[0-9]+$/ || $12 !~ /^(success|failure)$/ || $23 !~ /^[0-4]$/ { exit 1 }
        END { if (NR < 9) exit 1 }
    ' "$evidence_root/availability.tsv"
    # The workstation owns the cross-node decision because only it has both
    # samplers and both address monitors. The node-local boundary proves that
    # every failed primary produced the required bounded retry record.
    # shellcheck disable=SC2016
    require availability_failed_primary_retry_complete awk -F '\t' '
        NR == 1 { next }
        {
            key=$1 FS $2 FS $3 FS $4 FS $5
            if ($8 == "primary" && $12 == "failure") failed[key]=1
            if ($8 == "retry") retried[key]=1
        }
        END {
            for (key in failed) if (!retried[key]) exit 1
        }
    ' "$evidence_root/availability.tsv"
    # shellcheck disable=SC2016
    require availability_unique awk -F '\t' '
        NR == 1 { next }
        { key=$1 FS $2 FS $3 FS $4 FS $5 FS $8; if (seen[key]++) exit 1 }
    ' "$evidence_root/availability.tsv"
    require availability_monitor_nonempty test -s "$evidence_root/vip-address-monitor.tsv"
    require availability_monitor_bounded test \
        "$(stat -c '%s' "$evidence_root/vip-address-monitor.tsv")" -le 1048576
    require availability_monitor_utf8 iconv -f UTF-8 -t UTF-8 \
        "$evidence_root/vip-address-monitor.tsv" -o /dev/null
    # shellcheck disable=SC2016
    require availability_monitor_complete awk -F '\t' '
        NR == 1 { if ($1 != "observer-start" || NF != 4) exit 1; next }
        $1 == "address-event" && NF == 3 { next }
        $1 == "observer-end" && NF == 3 && $3 ~ /^status=(0|143)$/ { ended++ ; next }
        { exit 1 }
        END { exit(ended == 1 ? 0 : 1) }
    ' "$evidence_root/vip-address-monitor.tsv"
    require availability_no_work_residue test ! -e "$evidence_root/availability-work"
}

controlled_exercise_recover_stopped_service() {
    local serving_health_service=$1
    local serving_health_marker=$2
    local serving_health_watchdog=$evidence_root/exercise-${serving_health_marker##*/exercise-}
    local serving_health_pid

    serving_health_watchdog=${serving_health_watchdog%.mutation.tsv}.watchdog.tsv
    if regular_file "$serving_health_watchdog"; then
        serving_health_pid=$(<"$serving_health_watchdog")
        if [[ "$serving_health_pid" =~ ^[1-9][0-9]*$ ]]; then
            kill "$serving_health_pid" 2>/dev/null || :
            wait "$serving_health_pid" 2>/dev/null || :
        fi
        rm -f -- "$serving_health_watchdog"
    fi
    if "$systemctl_command" start "$serving_health_service" &&
        "$systemctl_command" is-active --quiet "$serving_health_service"; then
        rm -f -- "$serving_health_marker"
        return 0
    fi
    return 125
}

controlled_exercise_service() {
    local serving_health_scenario serving_health_operation serving_health_expected_role
    local serving_health_service serving_health_marker serving_health_state

    IFS=: read -r serving_health_scenario serving_health_operation <<<"$target_revision_argument"
    case "$serving_health_scenario" in
        node-a-caddy)
            serving_health_expected_role=node-a
            serving_health_service=caddy.service
            ;;
        node-a-lighttpd)
            serving_health_expected_role=node-a
            serving_health_service=lighttpd.service
            ;;
        node-a-pihole-ftl)
            serving_health_expected_role=node-a
            serving_health_service=pihole-FTL.service
            ;;
        node-a-unbound)
            serving_health_expected_role=node-a
            serving_health_service=unbound.service
            ;;
        node-a-keepalived)
            serving_health_expected_role=node-a
            serving_health_service=keepalived.service
            ;;
        node-b-caddy)
            serving_health_expected_role=node-b
            serving_health_service=caddy.service
            ;;
        node-b-lighttpd)
            serving_health_expected_role=node-b
            serving_health_service=lighttpd.service
            ;;
        node-b-pihole-ftl)
            serving_health_expected_role=node-b
            serving_health_service=pihole-FTL.service
            ;;
        node-b-unbound)
            serving_health_expected_role=node-b
            serving_health_service=unbound.service
            ;;
        *) return 64 ;;
    esac
    [[ "$node_role" = "$serving_health_expected_role" ]]
    serving_health_marker=$evidence_root/exercise-$serving_health_scenario.mutation.tsv
    case "$serving_health_operation" in
        stop)
            require exercise_marker_absent path_absent "$serving_health_marker"
            require exercise_service_initially_active "$systemctl_command" is-active --quiet \
                "$serving_health_service"
            printf 'scenario\tservice\tinitial_state\n%s\t%s\tactive\n' \
                "$serving_health_scenario" "$serving_health_service" >"$serving_health_marker"
            chmod 0600 "$serving_health_marker"
            if ! capture_command "exercise_${serving_health_scenario}_stop" \
                "$systemctl_command" stop "$serving_health_service"; then
                controlled_exercise_recover_stopped_service "$serving_health_service" \
                    "$serving_health_marker" || return 125
                return 1
            fi
            if ! serving_health_state=$(
                "$systemctl_command" show --property=ActiveState --value \
                    "$serving_health_service"
            ); then
                controlled_exercise_recover_stopped_service "$serving_health_service" \
                    "$serving_health_marker" || return 125
                return 1
            fi
            case "$serving_health_state" in
                inactive | failed)
                    printf '%s_check_exercise_service_stopped=true\n' "$prefix"
                    ;;
                *)
                    printf '%s_check_exercise_service_stopped=false\n' "$prefix" >&2
                    controlled_exercise_recover_stopped_service "$serving_health_service" \
                        "$serving_health_marker" || return 125
                    return 1
                    ;;
            esac
            if [[ -z "$target_root" && "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" != 1 ]]; then
                # The child Bash expands its positional parameters.
                # shellcheck disable=SC2016
                nohup /bin/bash -c '
                    child=
                    trap '\''[[ -z "$child" ]] || kill "$child" 2>/dev/null || :; exit 0'\'' TERM INT
                    sleep 120 &
                    child=$!
                    wait "$child" || exit 0
                    if [[ -f "$1" && ! -L "$1" ]]; then
                        "$2" start "$3"
                    fi
                ' _ "$serving_health_marker" "$systemctl_command" "$serving_health_service" \
                    >"$evidence_root/exercise-$serving_health_scenario-watchdog.stdout" \
                    2>"$evidence_root/exercise-$serving_health_scenario-watchdog.stderr" &
                serving_health_state=$!
                if ! {
                    printf '%s\n' "$serving_health_state" \
                        >"$evidence_root/exercise-$serving_health_scenario.watchdog.tsv" &&
                        chmod 0600 "$evidence_root/exercise-$serving_health_scenario.watchdog.tsv" &&
                        kill -0 "$serving_health_state"
                }; then
                    controlled_exercise_recover_stopped_service "$serving_health_service" \
                        "$serving_health_marker" || return 125
                    return 1
                fi
            fi
            ;;
        start | restore)
            require exercise_marker_regular regular_file "$serving_health_marker"
            require_equal exercise_marker_scenario "$serving_health_scenario" \
                "$(awk -F '\t' 'NR == 2 { print $1 }' "$serving_health_marker")"
            require_equal exercise_marker_service "$serving_health_service" \
                "$(awk -F '\t' 'NR == 2 { print $2 }' "$serving_health_marker")"
            if ! capture_command "exercise_${serving_health_scenario}_start" \
                "$systemctl_command" start "$serving_health_service"; then
                return 125
            fi
            require exercise_service_restored "$systemctl_command" is-active --quiet \
                "$serving_health_service" || return 125
            rm -f -- "$serving_health_marker"
            if regular_file "$evidence_root/exercise-$serving_health_scenario.watchdog.tsv"; then
                serving_health_state=$(<"$evidence_root/exercise-$serving_health_scenario.watchdog.tsv")
                [[ "$serving_health_state" =~ ^[1-9][0-9]*$ ]]
                kill "$serving_health_state" 2>/dev/null || :
                wait "$serving_health_state" 2>/dev/null || :
                rm -f -- "$evidence_root/exercise-$serving_health_scenario.watchdog.tsv"
            fi
            ;;
        *) return 64 ;;
    esac
}

controlled_exercise_ownership() {
    local serving_health_ipv4_state serving_health_ipv6_state serving_health_addresses
    local serving_health_expected_state serving_health_expected_vips serving_health_vip_count
    local serving_health_attempt serving_health_stable=0

    case "$target_revision_argument" in
        master4)
            serving_health_expected_state=Master
            serving_health_expected_vips=4
            ;;
        backup0)
            serving_health_expected_state=Backup
            serving_health_expected_vips=0
            ;;
        fault0)
            serving_health_expected_state=Fault
            serving_health_expected_vips=0
            ;;
        *) return 64 ;;
    esac
    : >"$evidence_root/exercise-ownership-samples.tsv"
    chmod 0600 "$evidence_root/exercise-ownership-samples.tsv"
    for ((serving_health_attempt = 1; serving_health_attempt <= ownership_attempts; serving_health_attempt++)); do
        serving_health_ipv4_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/100/IPv4 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        serving_health_ipv6_state=$(
            "$busctl_command" get-property org.keepalived.Vrrp1 \
                /org/keepalived/Vrrp1/Instance/eth0/101/IPv6 \
                org.keepalived.Vrrp1.Instance State |
                sed -n 's/.*"\([^"]*\)".*/\1/p'
        )
        serving_health_addresses=$("$ip_command" -o address show dev eth0)
        serving_health_vip_count=0
        grep -Fq ' 10.1.0.55/22 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' 10.1.0.56/22 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::55/128 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        grep -Fq ' fd36:5aa8:6971:1::56/128 ' <<<"$serving_health_addresses" && serving_health_vip_count=$((serving_health_vip_count + 1))
        printf '%s\t%s\t%s\t%s\t%s\n' "$serving_health_attempt" \
            "$("$date_command" -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
            "$serving_health_ipv4_state" "$serving_health_ipv6_state" \
            "$serving_health_vip_count" >>"$evidence_root/exercise-ownership-samples.tsv"
        if [[ "$serving_health_ipv4_state" = "$serving_health_expected_state" &&
            "$serving_health_ipv6_state" = "$serving_health_expected_state" &&
            "$serving_health_vip_count" -eq "$serving_health_expected_vips" ]]; then
            serving_health_stable=$((serving_health_stable + 1))
            if [[ "$serving_health_stable" -ge "$ownership_stable_samples" ]]; then
                return 0
            fi
        else
            serving_health_stable=0
        fi
        "$sleep_command" "$ownership_sample_delay"
    done
    require exercise_ownership_convergence false
}

controlled_exercise_cursor() {
    local serving_health_scenario=$target_revision_argument
    local serving_health_cursor

    [[ "$serving_health_scenario" =~ ^node-[ab]-(caddy|lighttpd|pihole-ftl|unbound|keepalived)$ ]]
    capture_command "exercise_${serving_health_scenario}_cursor" \
        "$journalctl_command" --quiet --no-pager -n 0 --show-cursor
    serving_health_cursor=$(sed -n 's/^-- cursor: //p' \
        "$evidence_root/exercise_${serving_health_scenario}_cursor.stdout")
    require exercise_cursor_exact test -n "$serving_health_cursor"
    printf '%s\n' "$serving_health_cursor" \
        >"$evidence_root/exercise-$serving_health_scenario.cursor.tsv"
    chmod 0600 "$evidence_root/exercise-$serving_health_scenario.cursor.tsv"
}

controlled_exercise_journal() {
    local serving_health_scenario=$target_revision_argument
    local serving_health_cursor_file=$evidence_root/exercise-$target_revision_argument.cursor.tsv
    local serving_health_journal_label=exercise_${target_revision_argument}_journal
    local serving_health_daemon_label=${serving_health_journal_label}_daemon
    local serving_health_notification_label=${serving_health_journal_label}_notification
    local serving_health_attempt serving_health_ready=false

    regular_file "$serving_health_cursor_file"
    for ((serving_health_attempt = 1; serving_health_attempt <= 45; serving_health_attempt++)); do
        capture_command "$serving_health_daemon_label" "$journalctl_command" --no-pager \
            -o short-iso-precise --after-cursor "$(<"$serving_health_cursor_file")" \
            -u keepalived.service -u caddy.service -u pihole-FTL.service \
            -u unbound.service -u lighttpd.service -u caddy-pihole-web-health.service
        capture_command "$serving_health_notification_label" "$journalctl_command" --no-pager \
            -o short-iso-precise --after-cursor "$(<"$serving_health_cursor_file")" \
            -t keepalived-notify -t caddy-ha-health -t caddy-apprise-queue
        cat "$evidence_root/$serving_health_daemon_label.stdout" \
            "$evidence_root/$serving_health_notification_label.stdout" \
            >"$evidence_root/$serving_health_journal_label.stdout"
        chmod 0600 "$evidence_root/$serving_health_journal_label.stdout"
        case "$serving_health_scenario" in
            *-lighttpd)
                grep -Eq 'pihole_web_health event=(failure-retained|enqueue-failure-pending)' \
                    "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Fq 'pihole_web_health event=recovery-enqueued' \
                        "$evidence_root/$serving_health_daemon_label.stdout" &&
                    [[ "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=failure' \
                        "$evidence_root/$serving_health_notification_label.stdout")" -eq 1 ]] &&
                    [[ "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=success' \
                        "$evidence_root/$serving_health_notification_label.stdout")" -eq 1 ]] &&
                    serving_health_ready=true
                ;;
            *-caddy)
                grep -Fq 'VRRP_Script(check-caddy) failed' \
                    "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Fq 'VRRP_Script(check-caddy) succeeded' \
                        "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Eq 'event=enqueued .*source=keepalived ' \
                        "$evidence_root/$serving_health_notification_label.stdout" &&
                    serving_health_ready=true
                ;;
            *-pihole-ftl | *-unbound)
                grep -Fq 'VRRP_Script(check-dns) failed' \
                    "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Fq 'VRRP_Script(check-dns) succeeded' \
                        "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Eq 'event=enqueued .*source=keepalived ' \
                        "$evidence_root/$serving_health_notification_label.stdout" &&
                    serving_health_ready=true
                ;;
            *-keepalived)
                grep -Fq 'Started keepalived.service' \
                    "$evidence_root/$serving_health_daemon_label.stdout" &&
                    grep -Eq 'event=enqueued .*source=keepalived ' \
                        "$evidence_root/$serving_health_notification_label.stdout" &&
                    serving_health_ready=true
                ;;
        esac
        [[ "$serving_health_ready" = true ]] && break
        "$sleep_command" 1
    done
    require exercise_journal_nonempty test -s "$evidence_root/$serving_health_journal_label.stdout"
    require exercise_journal_complete test "$serving_health_ready" = true
    require exercise_legacy_title_absent test -z \
        "$(grep -F '[Failover Alert] Pi-hole DNS Cluster' \
            "$evidence_root/$serving_health_journal_label.stdout" || :)"
    case "$serving_health_scenario" in
        *-lighttpd)
            require exercise_lighttpd_failure_state grep -Eq \
                'pihole_web_health event=(failure-retained|enqueue-failure-pending)' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_lighttpd_recovery_event grep -Fq \
                'pihole_web_health event=recovery-enqueued' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require_equal exercise_lighttpd_failure_notification_count 1 \
                "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=failure' \
                    "$evidence_root/$serving_health_journal_label.stdout")"
            require_equal exercise_lighttpd_recovery_notification_count 1 \
                "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=success' \
                    "$evidence_root/$serving_health_journal_label.stdout")"
            ;;
        *-caddy)
            require exercise_caddy_failure grep -Fq 'VRRP_Script(check-caddy) failed' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_caddy_recovery grep -Fq 'VRRP_Script(check-caddy) succeeded' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_caddy_structured_notification grep -Eq \
                'event=enqueued .*source=keepalived ' \
                "$evidence_root/$serving_health_journal_label.stdout"
            ;;
        *-pihole-ftl | *-unbound)
            require exercise_dns_failure grep -Fq 'VRRP_Script(check-dns) failed' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_dns_recovery grep -Fq 'VRRP_Script(check-dns) succeeded' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_dns_structured_notification grep -Eq \
                'event=enqueued .*source=keepalived ' \
                "$evidence_root/$serving_health_journal_label.stdout"
            ;;
        *-keepalived)
            require exercise_keepalived_restart grep -Fq 'Started keepalived.service' \
                "$evidence_root/$serving_health_journal_label.stdout"
            require exercise_keepalived_structured_notification grep -Eq \
                'event=enqueued .*source=keepalived ' \
                "$evidence_root/$serving_health_journal_label.stdout"
            ;;
    esac
}

controlled_exercise_observe() {
    local serving_health_scenario=$target_revision_argument
    local serving_health_cursor_file=$evidence_root/exercise-$target_revision_argument.cursor.tsv
    local serving_health_observation_label=exercise_${target_revision_argument}_outage
    local serving_health_attempt serving_health_observed=false

    [[ "$serving_health_scenario" = node-a-lighttpd || "$serving_health_scenario" = node-b-lighttpd ]]
    regular_file "$serving_health_cursor_file"
    for ((serving_health_attempt = 1; serving_health_attempt <= 45; serving_health_attempt++)); do
        capture_command "$serving_health_observation_label" "$journalctl_command" --no-pager \
            -o short-iso-precise --after-cursor "$(<"$serving_health_cursor_file")" \
            -u caddy-pihole-web-health.service
        if grep -Eq 'pihole_web_health event=(failure-retained|enqueue-failure-pending)' \
            "$evidence_root/$serving_health_observation_label.stdout"; then
            serving_health_observed=true
            break
        fi
        "$sleep_command" 1
    done
    require exercise_lighttpd_outage_observed test "$serving_health_observed" = true
}

controlled_exercise_final_residue() {
    local serving_health_service

    require exercise_mutation_residue_absent test -z \
        "$(find "$evidence_root" -maxdepth 1 -type f -name 'exercise-*.mutation.tsv' -print -quit)"
    require exercise_watchdog_residue_absent test -z \
        "$(find "$evidence_root" -maxdepth 1 -type f -name 'exercise-*.watchdog.tsv' -print -quit)"
    for serving_health_service in caddy.service lighttpd.service pihole-FTL.service \
        unbound.service keepalived.service; do
        require "exercise_${serving_health_service//[^a-zA-Z0-9]/_}_active" \
            "$systemctl_command" is-active --quiet "$serving_health_service"
    done
}

write_decision() {
    local serving_health_scenario=$1
    local serving_health_expectation=$2
    local serving_health_status=$3
    local serving_health_expected=$4
    local serving_health_observed=$5
    local serving_health_raw=$6
    local serving_health_decision=$7
    local serving_health_raw_hash

    serving_health_raw_hash=$(sha256sum "$serving_health_raw" | awk '{ print $1 }')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$serving_health_scenario" "$serving_health_expectation" "$serving_health_status" \
        "$serving_health_expected" "$serving_health_observed" "$serving_health_raw_hash" \
        >"$serving_health_decision"
    chmod 0600 "$serving_health_raw" "$serving_health_decision"
}

external_attribution_redact() {
    sed -E \
        -e 's#([A-Za-z][A-Za-z0-9+.-]*://)[^[:space:]]+#\1[REDACTED]#g' \
        -e 's#([Aa]uthorization:)[[:space:]]*[^[:space:]]+#\1 [REDACTED]#g' \
        -e 's#((token|password|api[_-]?key|webhook)[=:])[[:graph:]]+#\1[REDACTED]#Ig'
}

external_attribution_safe_file() {
    local attribution_path=$1
    local attribution_expected_owner=root:root

    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        attribution_expected_owner=$(id -un):$(id -gn)
    fi

    regular_file "$attribution_path"
    [[ "$(stat -c '%U:%G' "$attribution_path")" = "$attribution_expected_owner" ]]
    [[ "$(stat -c '%a' "$attribution_path")" = 600 ]]
    [[ "$(stat -c '%s' "$attribution_path")" -le 1048576 ]]
    iconv -f UTF-8 -t UTF-8 "$attribution_path" >/dev/null
    if LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$attribution_path"; then
        return 1
    fi
    if grep -Eiq \
        '([A-Za-z][A-Za-z0-9+.-]*://[^[]|authorization:[[:space:]]*[^[]|((token|password|api[_-]?key|webhook)[=:])[^[])' \
        "$attribution_path"; then
        return 1
    fi
}

external_attribution_capture() {
    local attribution_title='[Failover Alert] Pi-hole DNS Cluster'
    local attribution_roots attribution_root attribution_candidate attribution_relative
    local attribution_matches=$evidence_root/source-matches.tsv
    local attribution_journal_raw=$evidence_root/.journal.raw
    local attribution_journal=$evidence_root/request-observations.tsv
    local attribution_result=$evidence_root/attribution.tsv
    local attribution_class=unattributed attribution_candidate_count=0
    local attribution_class_count=0 attribution_observed_class
    local attribution_file_count
    local attribution_expected_owner=root:root
    local attribution_journalctl=${CADDY_ATTRIBUTION_JOURNALCTL_COMMAND:-/usr/bin/journalctl}
    local attribution_podman=${CADDY_ATTRIBUTION_PODMAN_COMMAND:-/usr/bin/podman}

    safe_root "$evidence_root"
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        attribution_expected_owner=$(id -un):$(id -gn)
    fi
    [[ "$(stat -c '%U:%G' "$evidence_root")" = "$attribution_expected_owner" ]]
    [[ "$(stat -c '%a' "$evidence_root")" = 700 ]]
    if [[ "${CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        attribution_roots=${CADDY_ATTRIBUTION_SCAN_ROOTS:?missing test scan roots}
    else
        attribution_roots='/etc/systemd/system:/etc/cron.d:/etc/cron.daily:/etc/cron.hourly:/etc/cron.weekly:/etc/cron.monthly:/usr/local/bin:/usr/local/libexec:/opt:/home/pi:/var/lib/caddy-apprise-queue'
    fi
    printf 'classification\tsource\n' >"$attribution_matches"
    IFS=: read -r -a attribution_root_list <<<"$attribution_roots"
    for attribution_root in "${attribution_root_list[@]}"; do
        [[ "$attribution_root" = /* && "$attribution_root" != *$'\n'* ]]
        [[ ! -L "$attribution_root" ]] || return 66
        [[ -e "$attribution_root" ]] || continue
        attribution_file_count=$(find "$attribution_root" -xdev -type f \
            -size -1048577c -printf . 2>/dev/null | wc -c)
        [[ "$attribution_file_count" -le 5000 ]] || return 67
        while IFS= read -r -d '' attribution_candidate; do
            [[ -f "$attribution_candidate" && ! -L "$attribution_candidate" ]]
            [[ "$(stat -c '%s' "$attribution_candidate")" -le 1048576 ]] || continue
            if LC_ALL=C grep -IlF -- "$attribution_title" "$attribution_candidate" >/dev/null; then
                attribution_relative=$attribution_candidate
                [[ "$attribution_relative" != *$'\t'* && "$attribution_relative" != *$'\n'* ]]
                case "$attribution_relative" in
                    */cron.*/* | */systemd/system/*.timer) attribution_observed_class=scheduled-job ;;
                    */caddy-apprise-queue/* | */receipt*/* | */delivered/*) attribution_observed_class=retained-replay ;;
                    */usr/local/bin/* | */usr/local/libexec/* | */opt/* | */home/pi/*) attribution_observed_class=second-api-caller ;;
                    *) attribution_observed_class=external-producer ;;
                esac
                printf '%s\t%s\n' "$attribution_observed_class" "$attribution_relative" \
                    >>"$attribution_matches"
                attribution_candidate_count=$((attribution_candidate_count + 1))
            fi
        done < <(find "$attribution_root" -xdev -type f -size -1048577c -print0 2>/dev/null)
    done
    : >"$attribution_journal_raw"
    if [[ -x "$attribution_journalctl" ]]; then
        "$attribution_journalctl" --since '-14 days' --no-pager -n 2000 \
            -o short-iso-precise -u apprise-api.service >"$attribution_journal_raw" 2>/dev/null || :
    fi
    if [[ -x "$attribution_podman" ]]; then
        "$attribution_podman" logs --since 336h --tail 2000 apprise-api \
            >>"$attribution_journal_raw" 2>/dev/null || :
    fi
    [[ "$(stat -c '%s' "$attribution_journal_raw")" -le 1048576 ]] || return 67
    {
        printf 'timestamp\tsource-address\thttp-path\tstatus\tuser-agent\tprocess\tdestination-count\tlegacy-title\n'
        grep -F -- "$attribution_title" "$attribution_journal_raw" | external_attribution_redact || :
    } >"$attribution_journal"
    chmod 0600 "$attribution_matches" "$attribution_journal"
    rm -f -- "$attribution_journal_raw"
    external_attribution_safe_file "$attribution_matches" || return 68
    external_attribution_safe_file "$attribution_journal" || return 68
    attribution_class_count=$(awk -F '\t' 'NR > 1 { seen[$1] = 1 } END { for (item in seen) count++; print count + 0 }' "$attribution_matches")
    if [[ "$attribution_class_count" -gt 1 || "$attribution_candidate_count" -gt 1 ]]; then
        attribution_class=ambiguous
    elif [[ "$attribution_candidate_count" -eq 1 ]]; then
        attribution_class=$(awk -F '\t' 'NR == 2 { print $1 }' "$attribution_matches")
    fi
    printf 'config-id\tconfig-model\tattribution\tcandidates\n%s\t%s\t%s\t%s\n' \
        apprise endpoint-list-only "$attribution_class" "$attribution_candidate_count" \
        >"$attribution_result"
    chmod 0600 "$attribution_result"
    external_attribution_safe_file "$attribution_result" || return 68
    printf '%s_external_attribution=%s\n' "$prefix" "$attribution_class"
    [[ "$attribution_class" != ambiguous ]] || return 69
}

production_path_test_node_a_quarantine() {
    local serving_health_test_root=$1
    local serving_health_repo_root=$2
    local serving_health_state_root=$3
    local serving_health_payload=$4
    local serving_health_evidence=$5
    local serving_health_test_target=$6
    local serving_health_systemctl=$7
    local serving_health_contract=$serving_health_test_root/node-a-quarantine-contract.tsv
    local serving_health_candidate serving_health_name serving_health_revision serving_health_source
    local serving_health_release_hash serving_health_payload_hash serving_health_raw serving_health_decision
    local serving_health_status serving_health_saved serving_health_first

    chmod -R u+rwX -- "$serving_health_state_root/quarantine"
    rm -rf -- "$serving_health_state_root/quarantine"
    install -d -m 0750 "$serving_health_state_root/quarantine"
    : >"$serving_health_contract"
    while IFS=$'\t' read -r serving_health_name serving_health_revision serving_health_source; do
        serving_health_candidate=$serving_health_state_root/quarantine/$serving_health_name
        install -d -m 0750 "$serving_health_candidate"
        printf 'payload for %s\n' "$serving_health_revision" >"$serving_health_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"%s","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$serving_health_revision" "$serving_health_source" \
            >"$serving_health_candidate/release-manifest.json"
        (
            cd "$serving_health_candidate"
            find . -type f \
                ! -path ./manifest.sha256 \
                ! -path ./.finalize-request \
                ! -path ./.complete \
                ! -path ./.complete.pending \
                -print0 |
                LC_ALL=C sort -z |
                xargs -0 sha256sum
        ) >"$serving_health_candidate/manifest.sha256"
        : >"$serving_health_candidate/.finalize-request"
        if [[ "$serving_health_source" = node-b ]]; then
            : >"$serving_health_candidate/.complete"
        fi
        chmod 0440 "$serving_health_candidate"/* "$serving_health_candidate"/.[!.]*
        chmod 0550 "$serving_health_candidate"
        serving_health_release_hash=$(sha256sum "$serving_health_candidate/release-manifest.json" | awk '{ print $1 }')
        serving_health_payload_hash=$(sha256sum "$serving_health_candidate/manifest.sha256" | awk '{ print $1 }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$serving_health_name" "$serving_health_revision" \
            "$serving_health_source" "$serving_health_release_hash" "$serving_health_payload_hash" \
            >>"$serving_health_contract"
    done <<'CONTRACT'
node-b-20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29	node-b
node-b-20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4	node-b
node_a-outbound-20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63-action30d	20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63	node-a
node_a-outbound-action17p-node-a-to-node-b-bootstrap-action30d	action17p-node-a-to-node-b-bootstrap	node-a
CONTRACT
    chmod 0600 "$serving_health_contract"

    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-baseline.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-baseline.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    write_decision node-a-quarantine-baseline accept 0 exact-four exact-four \
        "$serving_health_raw" "$serving_health_decision"

    install -d -m 0550 "$serving_health_state_root/quarantine/unexpected"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-extra-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-extra-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-a-quarantine-extra-rejection reject "$serving_health_status" \
        exact-four extra-entry "$serving_health_raw" "$serving_health_decision"
    rmdir "$serving_health_state_root/quarantine/unexpected"

    serving_health_first=$(awk -F '\t' 'NR == 1 { print $1 }' "$serving_health_contract")
    serving_health_candidate=$serving_health_state_root/quarantine/$serving_health_first
    chmod 0750 "$serving_health_candidate"
    chmod 0640 "$serving_health_candidate/Caddyfile"
    printf 'changed\n' >>"$serving_health_candidate/Caddyfile"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-changed-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-changed-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-a-quarantine-changed-rejection reject "$serving_health_status" \
        manifest-valid changed-payload "$serving_health_raw" "$serving_health_decision"
    sed -i '$d' "$serving_health_candidate/Caddyfile"
    chmod 0440 "$serving_health_candidate/Caddyfile"
    chmod 0550 "$serving_health_candidate"

    serving_health_saved=$serving_health_test_root/node-a-release-manifest.saved
    install -m 0600 "$serving_health_candidate/release-manifest.json" "$serving_health_saved"
    chmod 0750 "$serving_health_candidate"
    chmod 0640 "$serving_health_candidate/release-manifest.json"
    printf '{\n' >"$serving_health_candidate/release-manifest.json"
    chmod 0440 "$serving_health_candidate/release-manifest.json"
    chmod 0550 "$serving_health_candidate"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-malformed-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-malformed-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-a-quarantine-malformed-rejection reject "$serving_health_status" \
        exact-release-manifest malformed "$serving_health_raw" "$serving_health_decision"
    chmod 0750 "$serving_health_candidate"
    install -m 0440 "$serving_health_saved" "$serving_health_candidate/release-manifest.json"

    mv "$serving_health_candidate/Caddyfile" "$serving_health_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$serving_health_candidate/Caddyfile"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-symlink-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-symlink-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-a-quarantine-symlink-rejection reject "$serving_health_status" \
        regular-file symlink "$serving_health_raw" "$serving_health_decision"
    rm "$serving_health_candidate/Caddyfile"
    mv "$serving_health_candidate/Caddyfile.saved" "$serving_health_candidate/Caddyfile"
    chmod 0550 "$serving_health_candidate"

    rm "$serving_health_test_target/etc/caddy/current"
    ln -s "$serving_health_candidate" "$serving_health_test_target/etc/caddy/current"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-reference-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-reference-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-a-quarantine-reference-rejection reject "$serving_health_status" \
        unreferenced active-reference "$serving_health_raw" "$serving_health_decision"
    rm "$serving_health_test_target/etc/caddy/current"
    ln -s releases/current-test "$serving_health_test_target/etc/caddy/current"

    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-disposition.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-disposition.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-disposition node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    write_decision node-a-quarantine-disposition accept 0 empty empty \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_raw=$serving_health_test_root/raw/node-a-quarantine-rollback.txt
    serving_health_decision=$serving_health_test_root/decisions/node-a-quarantine-rollback.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_NODE_A_QUARANTINE_CONTRACT=$serving_health_contract \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        node-a-quarantine-rollback node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    write_decision node-a-quarantine-rollback accept 0 exact-four exact-four \
        "$serving_health_raw" "$serving_health_decision"
}

production_path_test_namespace_case() {
    local serving_health_test_root=$1
    local serving_health_case=$2
    local serving_health_expectation=$3
    local serving_health_namespace=$4
    local serving_health_expected_metadata=${5:-}
    local serving_health_raw=$serving_health_test_root/raw/protocol-namespace-$serving_health_case.txt
    local serving_health_decision=$serving_health_test_root/decisions/protocol-namespace-$serving_health_case.tsv
    local serving_health_status=0

    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_TEST_EXPECTED_SYNC_METADATA=$serving_health_expected_metadata \
        require_empty_or_absent_sync_directory protocol_namespace "$serving_health_namespace" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    if [[ "$serving_health_expectation" = accept ]]; then
        [[ "$serving_health_status" -eq 0 ]]
    else
        [[ "$serving_health_status" -ne 0 ]]
    fi
    write_decision "protocol-namespace-$serving_health_case" "$serving_health_expectation" \
        "$serving_health_status" "$serving_health_expectation" "$serving_health_status" \
        "$serving_health_raw" "$serving_health_decision"
}

web_health_unit_production_path_test() {
    local serving_health_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local serving_health_repo_root=$1
    local serving_health_payload=$serving_health_test_root/payload
    local serving_health_evidence=$serving_health_test_root/evidence
    local serving_health_target=$serving_health_test_root/target
    local serving_health_bin=$serving_health_test_root/bin
    local serving_health_systemctl=$serving_health_bin/systemctl
    local serving_health_journalctl=$serving_health_bin/journalctl
    local serving_health_sleep=$serving_health_bin/sleep
    local serving_health_candidate
    local serving_health_installed
    local serving_health_raw
    local serving_health_decision
    local serving_health_status
    local serving_health_scenario
    local serving_health_identity_root
    local serving_health_identity_status=0

    [[ "$serving_health_test_root" = /tmp/* && -d "$serving_health_test_root" &&
        ! -L "$serving_health_test_root" ]]
    chmod 0700 "$serving_health_test_root"
    install -d -m 0700 "$serving_health_test_root/raw" \
        "$serving_health_test_root/decisions" "$serving_health_payload/manifests" \
        "$serving_health_payload/repositories/homelab-server-configs/Caddy/systemd" \
        "$serving_health_evidence" "$serving_health_bin"
    install -d -m 0755 "$serving_health_target/etc/systemd/system"
    install -d -m 0700 "$serving_health_target/var/lib/caddy-apprise-queue"
    for serving_health_queue_directory in pending inflight dead-letter delivered; do
        install -d -m 0700 \
            "$serving_health_target/var/lib/caddy-apprise-queue/$serving_health_queue_directory"
    done

    serving_health_candidate=$serving_health_payload/repositories/homelab-server-configs/Caddy/systemd/caddy-pihole-web-health.service
    install -m 0600 \
        "$serving_health_repo_root/Caddy/systemd/caddy-pihole-web-health.service" \
        "$serving_health_candidate"
    {
        sed -n '1p' "$serving_health_repo_root/Caddy/manifests/serving-health-production.tsv"
        awk -F '\t' '$2 == "Caddy/systemd/caddy-pihole-web-health.service" { print }' \
            "$serving_health_repo_root/Caddy/manifests/serving-health-production.tsv"
    } >"$serving_health_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$serving_health_repo_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$serving_health_payload/manifests/serving-health-quarantine-baseline.tsv"

    serving_health_installed=$serving_health_target$web_health_unit
    sed -e '/^SupplementaryGroups=caddy-tls$/d' \
        -e 's|^ReadWritePaths=/var/lib/caddy-apprise-queue$|ReadWritePaths=/var/lib/caddy-apprise-queue /run/caddy-apprise|' \
        "$serving_health_candidate" >"$serving_health_installed"
    chmod 0644 "$serving_health_installed"
    [[ "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')" = "$web_health_unit_deployed_sha256" ]]

    cat >"$serving_health_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$CADDY_WEB_HEALTH_TEST_ROOT/systemctl.calls"
case "$1" in
    is-enabled)
        if [[ "${2:-}" = --quiet ]]; then
            [[ "${3:-}" = caddy-pihole-web-health.timer ]]
            exit
        fi
        [[ "${2:-}" = caddy-pihole-web-health.service ]]
        printf 'static\n'
        ;;
    is-active) exit 0 ;;
    daemon-reload) exit 0 ;;
    start)
        [[ "${2:-}" = caddy-pihole-web-health.service ]]
        printf '%s\n' \
            'pihole_web_health event=healthy' \
            'Finished caddy-pihole-web-health.service - direct invocation' \
            >>"$CADDY_WEB_HEALTH_TEST_ROOT/service.journal"
        ;;
    show)
        printf '%s\n' 'LoadState=loaded' 'ActiveState=inactive' 'SubState=dead' \
            'Result=success' 'ExecMainStatus=0' \
            'FragmentPath=/etc/systemd/system/caddy-pihole-web-health.service' \
            'ReadWritePaths=/var/lib/caddy-apprise-queue' \
            'SupplementaryGroups=caddy-tls'
        ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$serving_health_journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$CADDY_WEB_HEALTH_TEST_ROOT/journalctl.calls"
if [[ " $* " = *' --show-cursor '* ]]; then
    cursor_count=0
    if [[ -f "$CADDY_WEB_HEALTH_TEST_ROOT/cursor-count" ]]; then
        cursor_count=$(<"$CADDY_WEB_HEALTH_TEST_ROOT/cursor-count")
    fi
    ((cursor_count += 1))
    printf '%s\n' "$cursor_count" >"$CADDY_WEB_HEALTH_TEST_ROOT/cursor-count"
    printf '%s\n' "-- cursor: s=web-health-test-cursor-$cursor_count"
    exit
fi
if [[ ! -e "$CADDY_WEB_HEALTH_TEST_ROOT/timer-observed" ]]; then
    printf '%s\n' \
        'pihole_web_health event=healthy' \
        'Finished caddy-pihole-web-health.service - timer invocation' \
        >"$CADDY_WEB_HEALTH_TEST_ROOT/timer.journal"
    : >"$CADDY_WEB_HEALTH_TEST_ROOT/timer-observed"
fi
cat "$CADDY_WEB_HEALTH_TEST_ROOT/timer.journal"
JOURNALCTL
    cat >"$serving_health_sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
SLEEP
    chmod 0700 "$serving_health_systemctl" "$serving_health_journalctl" \
        "$serving_health_sleep"
    : >"$serving_health_test_root/systemctl.calls"
    : >"$serving_health_test_root/journalctl.calls"
    : >"$serving_health_test_root/service.journal"
    export CADDY_WEB_HEALTH_TEST_ROOT=$serving_health_test_root

    serving_health_raw=$serving_health_test_root/raw/web-unit-service-identity.txt
    serving_health_decision=$serving_health_test_root/decisions/web-unit-service-identity.tsv
    if [[ "$EUID" -eq 0 ]]; then
        serving_health_identity_root=$(mktemp -d /tmp/caddy-web-health-identity.XXXXXX)
        chown 62000:62000 "$serving_health_identity_root"
        install -m 0640 /dev/null "$serving_health_identity_root/caddy-ha"
        install -d -m 0700 "$serving_health_identity_root/queue"
        chown 0:62001 "$serving_health_identity_root/caddy-ha"
        chown 62000:62000 "$serving_health_identity_root/queue"
        if /usr/bin/setpriv --reuid 62000 --regid 62000 --clear-groups -- \
            test -r "$serving_health_identity_root/caddy-ha"; then
            serving_health_identity_status=1
        fi
        # The child Bash expands its positional parameters.
        # shellcheck disable=SC2016
        if ! /usr/bin/setpriv --reuid 62000 --regid 62000 --groups 62001 -- \
            /bin/bash -c 'test -r "$1" && : >"$2/write-test"' _ \
            "$serving_health_identity_root/caddy-ha" \
            "$serving_health_identity_root/queue"; then
            serving_health_identity_status=1
        fi
        if [[ "$serving_health_identity_status" -eq 0 ]]; then
            printf '%s\n' \
                'without_caddy_tls_readable=false' \
                'with_caddy_tls_readable=true' \
                'pi_primary_queue_writable=true' \
                'kernel_dac_execution=true' >"$serving_health_raw"
        fi
        chmod -R u+rwX -- "$serving_health_identity_root"
        rm -rf -- "$serving_health_identity_root"
        [[ "$serving_health_identity_status" -eq 0 ]]
    else
        grep -Fxq 'User=pi' "$serving_health_candidate"
        grep -Fxq 'Group=pi' "$serving_health_candidate"
        grep -Fxq 'SupplementaryGroups=caddy-tls' "$serving_health_candidate"
        printf '%s\n' \
            'kernel_dac_execution=requires-root-debian-batch' \
            'unit_identity_contract=true' >"$serving_health_raw"
    fi
    write_decision web-unit-service-identity accept 0 identity-access identity-access \
        "$serving_health_raw" "$serving_health_decision"

    for serving_health_scenario in preflight install accept rollback; do
        serving_health_raw=$serving_health_test_root/raw/web-unit-$serving_health_scenario.txt
        serving_health_decision=$serving_health_test_root/decisions/web-unit-$serving_health_scenario.tsv
        if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_target \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
            CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$serving_health_journalctl \
            CADDY_SERVING_HEALTH_SLEEP_COMMAND=$serving_health_sleep \
            CADDY_SERVING_HEALTH_WEB_OBSERVATION_ATTEMPTS=2 \
            CADDY_SERVING_HEALTH_WEB_OBSERVATION_DELAY=0 \
            /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            "web-unit-$serving_health_scenario" node-b "$serving_health_payload" \
            "$serving_health_evidence" >"$serving_health_raw" 2>&1; then
            serving_health_status=0
        else
            serving_health_status=$?
        fi
        write_decision "web-unit-$serving_health_scenario" accept \
            "$serving_health_status" success \
            "$([[ "$serving_health_status" -eq 0 ]] && printf success || printf failure)" \
            "$serving_health_raw" "$serving_health_decision"
        [[ "$serving_health_status" -eq 0 ]]
    done
    [[ "$(sha256sum "$serving_health_installed" | awk '{ print $1 }')" = "$web_health_unit_deployed_sha256" ]]
    grep -Fxq 'start caddy-pihole-web-health.service' \
        "$serving_health_test_root/systemctl.calls"
    grep -Fq 'timer invocation' "$serving_health_test_root/timer.journal"

    printf '# changed\n' >>"$serving_health_candidate"
    serving_health_raw=$serving_health_test_root/raw/web-unit-candidate-tamper.txt
    serving_health_decision=$serving_health_test_root/decisions/web-unit-candidate-tamper.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        web-unit-install node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision web-unit-candidate-tamper reject "$serving_health_status" \
        "$web_health_unit_candidate_sha256" changed "$serving_health_raw" \
        "$serving_health_decision"
    [[ "$serving_health_status" -ne 0 ]]

    printf '%s_web_unit_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

notification_standardization_production_path_test() {
    local notification_repo_root=$1
    local notification_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local notification_payload notification_evidence notification_target
    local notification_systemctl notification_tmpfiles notification_busctl notification_ip
    local notification_raw notification_decision
    local notification_status notification_repository notification_source notification_installed
    local notification_mode notification_baseline_hash notification_candidate_hash

    notification_payload=$notification_test_root/payload
    notification_evidence=$notification_test_root/transaction-evidence
    notification_target=$(mktemp -d /tmp/caddy-notification-production-target.XXXXXX)
    install -d -m 0700 "$notification_payload/manifests" "$notification_evidence" \
        "$notification_target/var/lib/caddy-apprise-queue"/{pending,inflight,dead-letter,delivered}
    chmod 0700 "$notification_target/var/lib/caddy-apprise-queue" \
        "$notification_target/var/lib/caddy-apprise-queue"/*
    install -m 0600 "$notification_repo_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$notification_payload/manifests/serving-health-quarantine-baseline.tsv"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$notification_payload/manifests/serving-health-production.tsv"
    while IFS=$'\t' read -r notification_repository notification_source notification_installed \
        notification_mode notification_baseline_hash notification_candidate_hash; do
        install -d -m 0700 \
            "$notification_payload/repositories/$notification_repository/$(dirname "$notification_source")" \
            "$notification_target/$(dirname "$notification_installed")"
        if [[ "$notification_repository" = homelab-server-configs ]]; then
            install -m 0600 "$notification_repo_root/$notification_source" \
                "$notification_payload/repositories/$notification_repository/$notification_source"
            git -C "$notification_repo_root" show \
                "eb1e4471f87af7c80662d4e8aabb577e848bd03c:$notification_source" \
                >"$notification_target$notification_installed"
        else
            install -m 0600 "$notification_repo_root/../homelab-dns/$notification_source" \
                "$notification_payload/repositories/$notification_repository/$notification_source"
            git -C "$notification_repo_root/../homelab-dns" show \
                "ab9965fd:$notification_source" >"$notification_target$notification_installed"
        fi
        chmod "$notification_mode" "$notification_target$notification_installed"
        require_equal "notification_test_baseline_${notification_installed//[^a-zA-Z0-9]/_}" \
            "$notification_baseline_hash" \
            "$(sha256sum "$notification_target$notification_installed" | awk '{ print $1 }')"
        awk -F '\t' -v source="$notification_source" '$2 == source { print }' \
            "$notification_repo_root/Caddy/manifests/serving-health-production.tsv" \
            >>"$notification_payload/manifests/serving-health-production.tsv"
    done < <(notification_artifact_rows)

    notification_systemctl=$notification_test_root/notification-systemctl
    notification_tmpfiles=$notification_test_root/notification-tmpfiles
    notification_busctl=$notification_test_root/notification-busctl
    notification_ip=$notification_test_root/notification-ip
    cat >"$notification_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CADDY_NOTIFICATION_TEST_ROOT:?}/systemctl.calls"
[[ "$1" = is-active && "$2" = --quiet ]]
SYSTEMCTL
    cat >"$notification_tmpfiles" <<'TMPFILES'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_NOTIFICATION_TEST_ROOT:?}/tmpfiles.calls"
install -d -m 0755 "$CADDY_SERVING_HEALTH_TARGET_ROOT/var/lib/caddy-serving-health"
install -d -m 0700 "$CADDY_SERVING_HEALTH_TARGET_ROOT/var/lib/caddy-serving-health/keepalived-notify"
TMPFILES
    cat >"$notification_busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_NOTIFICATION_TEST_ROOT:?}/busctl.calls"
printf 's "Backup"\n'
BUSCTL
    cat >"$notification_ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_NOTIFICATION_TEST_ROOT:?}/ip.calls"
printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
IP
    chmod 0700 "$notification_systemctl" "$notification_tmpfiles" \
        "$notification_busctl" "$notification_ip"
    : >"$notification_test_root/systemctl.calls"
    : >"$notification_test_root/tmpfiles.calls"
    : >"$notification_test_root/busctl.calls"
    : >"$notification_test_root/ip.calls"
    export CADDY_NOTIFICATION_TEST_ROOT=$notification_test_root
    install -d -m 0755 "$notification_target/var/lib/caddy-serving-health"
    install -d -m 0700 \
        "$notification_target/var/lib/caddy-serving-health/keepalived-notify"
    printf 'BACKUP\n' \
        >"$notification_target/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"
    chmod 0600 \
        "$notification_target/var/lib/caddy-serving-health/keepalived-notify/PIHOLE_DUALSTACK.state"

    for notification_scenario in preflight install accept rollback; do
        notification_raw=$notification_test_root/raw/notification-$notification_scenario.txt
        notification_decision=$notification_test_root/decisions/notification-$notification_scenario.tsv
        if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_TARGET_ROOT=$notification_target \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$notification_systemctl \
            CADDY_SERVING_HEALTH_SYSTEMD_TMPFILES_COMMAND=$notification_tmpfiles \
            CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$notification_busctl \
            CADDY_SERVING_HEALTH_IP_COMMAND=$notification_ip \
            /bin/bash "$notification_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            "notification-$notification_scenario" node-b "$notification_payload" \
            "$notification_evidence" >"$notification_raw" 2>&1; then
            notification_status=0
        else
            notification_status=$?
        fi
        write_decision "notification-$notification_scenario" accept "$notification_status" success \
            "$([[ "$notification_status" -eq 0 ]] && printf success || printf failure)" \
            "$notification_raw" "$notification_decision"
        [[ "$notification_status" -eq 0 ]]
    done
    if grep -Eq '(^| )(restart|reload|stop|start) (caddy|pihole-FTL|unbound|keepalived)\.service$' \
        "$notification_test_root/systemctl.calls"; then
        return 1
    fi
    notification_raw=$notification_test_root/raw/notification-candidate-tamper.txt
    notification_decision=$notification_test_root/decisions/notification-candidate-tamper.tsv
    printf '# tamper\n' >>"$notification_payload/repositories/homelab-server-configs/Caddy/scripts/caddy-apprise-enqueue.sh"
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$notification_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$notification_systemctl \
        CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$notification_busctl \
        CADDY_SERVING_HEALTH_IP_COMMAND=$notification_ip \
        /bin/bash "$notification_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        notification-preflight node-b "$notification_payload" "$notification_evidence" \
        >"$notification_raw" 2>&1; then
        notification_status=0
    else
        notification_status=$?
    fi
    write_decision notification-candidate-tamper reject "$notification_status" exact changed \
        "$notification_raw" "$notification_decision"
    [[ "$notification_status" -ne 0 ]]
    chmod -R u+rwX -- "$notification_payload" "$notification_evidence" "$notification_target"
    rm -rf -- "$notification_payload" "$notification_evidence" "$notification_target"
    printf '%s_notification_standardization_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

external_attribution_production_path_test() {
    local attribution_test_root=$1
    local attribution_script=$2
    local attribution_fake_journal=$attribution_test_root/fake-journalctl
    local attribution_fake_podman=$attribution_test_root/fake-podman
    local attribution_fixture attribution_case_evidence
    local attribution_raw attribution_decision attribution_status attribution_expected
    local attribution_observed attribution_before attribution_after

    cat >"$attribution_fake_journal" <<'JOURNAL'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -n "${CADDY_ATTRIBUTION_TEST_JOURNAL:-}" ]]; then
    cat -- "$CADDY_ATTRIBUTION_TEST_JOURNAL"
fi
JOURNAL
    cat >"$attribution_fake_podman" <<'PODMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
PODMAN
    chmod 0700 "$attribution_fake_journal" "$attribution_fake_podman"

    external_attribution_test_case() {
        local attribution_case=$1
        local attribution_kind=$2
        local attribution_expectation=$3
        local attribution_journal_file=

        attribution_fixture=$attribution_test_root/fixtures/$attribution_case
        attribution_case_evidence=$attribution_test_root/cases/$attribution_case
        install -d -m 0700 "$attribution_fixture" "$attribution_case_evidence"
        case "$attribution_kind" in
            none) : ;;
            caller)
                install -d -m 0700 "$attribution_fixture/usr/local/bin"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/usr/local/bin/legacy-caller.sh"
                ;;
            scheduled)
                install -d -m 0700 "$attribution_fixture/etc/cron.d"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/etc/cron.d/legacy-notify"
                ;;
            replay)
                install -d -m 0700 "$attribution_fixture/var/lib/caddy-apprise-queue/delivered"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/var/lib/caddy-apprise-queue/delivered/legacy-record"
                ;;
            ambiguous)
                install -d -m 0700 "$attribution_fixture/usr/local/bin" \
                    "$attribution_fixture/etc/cron.d"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/usr/local/bin/legacy-caller.sh"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/etc/cron.d/legacy-notify"
                ;;
            secret)
                install -d -m 0700 "$attribution_fixture/usr/local/bin"
                printf '%s\n' '[Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_fixture/usr/local/bin/token=unsafe"
                ;;
            journal)
                install -d -m 0700 "$attribution_test_root/journals"
                attribution_journal_file=$attribution_test_root/journals/$attribution_case.txt
                printf '%s\n' \
                    '2026-08-23T12:00:00Z 10.1.3.10 POST /notify/apprise 200 legacy-agent apprise-api destinations=3 [Failover Alert] Pi-hole DNS Cluster' \
                    >"$attribution_journal_file"
                ;;
            *) return 64 ;;
        esac
        find "$attribution_fixture" -type f -exec chmod 0600 {} +
        if [[ -n "$attribution_journal_file" ]]; then
            chmod 0600 "$attribution_journal_file"
        fi
        attribution_before=$(find "$attribution_fixture" -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum | sha256sum | awk '{ print $1 }')
        if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$attribution_test_root \
            CADDY_ATTRIBUTION_SCAN_ROOTS=$attribution_fixture \
            CADDY_ATTRIBUTION_JOURNALCTL_COMMAND=$attribution_fake_journal \
            CADDY_ATTRIBUTION_PODMAN_COMMAND=$attribution_fake_podman \
            CADDY_ATTRIBUTION_TEST_JOURNAL=$attribution_journal_file \
            /bin/bash "$attribution_script" external-attribution-capture external-apprise \
            "$attribution_case_evidence" "$attribution_case_evidence" \
            >"$attribution_case_evidence/invocation.stdout" \
            2>"$attribution_case_evidence/invocation.stderr"; then
            attribution_status=0
        else
            attribution_status=$?
        fi
        chmod 0600 "$attribution_case_evidence/invocation.stdout" \
            "$attribution_case_evidence/invocation.stderr"
        attribution_after=$(find "$attribution_fixture" -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum | sha256sum | awk '{ print $1 }')
        [[ "$attribution_before" = "$attribution_after" ]]
        attribution_raw=$attribution_test_root/raw/$attribution_case.txt
        attribution_decision=$attribution_test_root/decisions/$attribution_case.tsv
        {
            printf 'fixture_before=%s\nfixture_after=%s\nexit_status=%s\n' \
                "$attribution_before" "$attribution_after" "$attribution_status"
            find "$attribution_case_evidence" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort
            if [[ -f "$attribution_case_evidence/attribution.tsv" ]]; then
                cat "$attribution_case_evidence/attribution.tsv"
                attribution_observed=$(awk -F '\t' 'NR == 2 { print $3 }' \
                    "$attribution_case_evidence/attribution.tsv")
            else
                attribution_observed=rejected
            fi
        } >"$attribution_raw"
        attribution_expected=$attribution_expectation
        write_decision "$attribution_case" \
            "$([[ "$attribution_expectation" = rejected ]] && printf reject || printf accept)" \
            "$attribution_status" "$attribution_expected" "$attribution_observed" \
            "$attribution_raw" "$attribution_decision"
        if [[ "$attribution_expectation" = rejected ]]; then
            [[ "$attribution_status" -ne 0 ]]
        else
            [[ "$attribution_status" -eq 0 && "$attribution_observed" = "$attribution_expectation" ]]
        fi
    }

    external_attribution_test_case endpoint-only none unattributed
    external_attribution_test_case no-evidence-unattributed none unattributed
    external_attribution_test_case exact-legacy-title-search caller second-api-caller
    external_attribution_test_case second-caller-attribution caller second-api-caller
    external_attribution_test_case scheduled-job-attribution scheduled scheduled-job
    external_attribution_test_case retained-replay-attribution replay retained-replay
    external_attribution_test_case multiple-candidate-ambiguity ambiguous rejected
    external_attribution_test_case secret-bearing-evidence-rejection secret rejected
    external_attribution_test_case bounded-journal-selection journal unattributed
    attribution_raw=$attribution_test_root/raw/zero-production-mutation.txt
    attribution_decision=$attribution_test_root/decisions/zero-production-mutation.tsv
    printf 'all_fixture_hashes_stable=true\n' >"$attribution_raw"
    write_decision zero-production-mutation accept 0 true true \
        "$attribution_raw" "$attribution_decision"
    printf '%s_external_attribution_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

controlled_failure_exercise_production_path_test() {
    local exercise_test_root=$1
    local exercise_repo_root=$2
    local exercise_payload=$exercise_test_root/payload
    local exercise_evidence=$exercise_test_root/exercise-evidence
    local exercise_systemctl=$exercise_test_root/systemctl
    local exercise_journalctl=$exercise_test_root/journalctl
    local exercise_busctl=$exercise_test_root/busctl
    local exercise_ip=$exercise_test_root/ip
    local exercise_sleep=$exercise_test_root/sleep
    local exercise_date=$exercise_test_root/date
    local exercise_dig=$exercise_test_root/dig
    local exercise_curl=$exercise_test_root/curl
    local exercise_script=$exercise_repo_root/Caddy/scripts/apply-serving-health-deployment.sh
    local exercise_scenario exercise_role exercise_status exercise_raw exercise_decision
    local -a exercise_scenarios=(
        node-a-caddy node-a-lighttpd node-a-pihole-ftl node-a-unbound node-a-keepalived
        node-b-caddy node-b-lighttpd node-b-pihole-ftl node-b-unbound
    )

    install -d -m 0700 "$exercise_payload/manifests" "$exercise_evidence"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$exercise_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$exercise_repo_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$exercise_payload/manifests/serving-health-quarantine-baseline.tsv"
    cat >"$exercise_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
service=${*: -1}
state_file=$CADDY_EXERCISE_TEST_ROOT/state-${service//[^a-zA-Z0-9]/_}
printf '%s\n' "$*" >>"$CADDY_EXERCISE_TEST_ROOT/systemctl.calls"
[[ -e "$state_file" ]] || printf 'active\n' >"$state_file"
case "$1" in
    is-active) [[ "$(<"$state_file")" = active ]] ;;
    stop)
        if [[ "${CADDY_EXERCISE_FAIL_STOP:-0}" = 1 ]]; then
            exit 1
        fi
        printf '%s\n' "${CADDY_EXERCISE_STOP_STATE:-inactive}" >"$state_file"
        case "$service" in
            caddy.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-caddy) failed (exited with status 1)' \
                    'event=enqueued event_id=caddy-failure source=keepalived severity=failure' \
                    >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                ;;
            pihole-FTL.service | unbound.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-dns) failed (exited with status 1)' \
                    'event=enqueued event_id=dns-failure source=keepalived severity=failure' \
                    >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                ;;
            lighttpd.service)
                if [[ "${CADDY_EXERCISE_PENDING_ENQUEUE:-0}" = 1 ]]; then
                    printf '%s\n' \
                        'pihole_web_health event=enqueue-failure-pending' \
                        >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                    : >"$CADDY_EXERCISE_TEST_ROOT/lighttpd-enqueue-pending"
                else
                    printf '%s\n' \
                        'pihole_web_health event=failure-retained' \
                        'event=enqueued event_id=web-failure source=pihole-web severity=failure' \
                        >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                fi
                ;;
        esac
        ;;
    start)
        if [[ "${CADDY_EXERCISE_FAIL_START:-0}" = 1 ]]; then
            exit 1
        fi
        printf 'active\n' >"$state_file"
        case "$service" in
            caddy.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-caddy) succeeded' \
                    'event=enqueued event_id=caddy-recovery source=keepalived severity=success' \
                    >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                ;;
            pihole-FTL.service | unbound.service)
                printf '%s\n' \
                    'Keepalived_vrrp: VRRP_Script(check-dns) succeeded' \
                    'event=enqueued event_id=dns-recovery source=keepalived severity=success' \
                    >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                ;;
            lighttpd.service)
                if [[ -e "$CADDY_EXERCISE_TEST_ROOT/lighttpd-enqueue-pending" ]]; then
                    rm -f -- "$CADDY_EXERCISE_TEST_ROOT/lighttpd-enqueue-pending"
                    printf '%s\n' \
                        'pihole_web_health event=recovered-before-enqueue' \
                        'event=enqueued event_id=web-failure source=pihole-web severity=failure' \
                        'pihole_web_health event=recovery-enqueued' \
                        'event=enqueued event_id=web-recovery source=pihole-web severity=success' \
                        >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                else
                    printf '%s\n' \
                        'pihole_web_health event=recovery-enqueued' \
                        'event=enqueued event_id=web-recovery source=pihole-web severity=success' \
                        >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                fi
                ;;
            keepalived.service)
                printf '%s\n' \
                    'systemd: Started keepalived.service' \
                    'event=enqueued event_id=keepalived-recovery source=keepalived severity=success' \
                    >>"$CADDY_EXERCISE_TEST_ROOT/journal.log"
                ;;
        esac
        ;;
    show)
        [[ "${CADDY_EXERCISE_FAIL_SHOW:-0}" != 1 ]] || exit 1
        cat "$state_file"
        ;;
    *) exit 64 ;;
esac
SYSTEMCTL
    cat >"$exercise_journalctl" <<'JOURNALCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
arguments=$*
printf '%s\n' "$*" >>"$CADDY_EXERCISE_TEST_ROOT/journalctl.calls"
if [[ " $* " = *' --show-cursor '* ]]; then
    lines=0
    [[ ! -f "$CADDY_EXERCISE_TEST_ROOT/journal.log" ]] || \
        lines=$(wc -l <"$CADDY_EXERCISE_TEST_ROOT/journal.log")
    printf '%s\n' "-- cursor: s=$lines"
elif [[ -f "$CADDY_EXERCISE_TEST_ROOT/journal.log" ]]; then
    cursor=0
    while [[ $# -gt 0 ]]; do
        if [[ "$1" = --after-cursor ]]; then
            cursor=${2#s=}
            break
        fi
        shift
    done
    if [[ " $arguments " = *' -t '* ]]; then
        tail -n "+$((cursor + 1))" "$CADDY_EXERCISE_TEST_ROOT/journal.log" |
            grep -E 'event=enqueued|keepalived-notify' || :
    else
        tail -n "+$((cursor + 1))" "$CADDY_EXERCISE_TEST_ROOT/journal.log" |
            grep -Ev '^event=enqueued' || :
    fi
fi
JOURNALCTL
    cat >"$exercise_busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 's "%s"\n' "${CADDY_EXERCISE_STATE:?}"
BUSCTL
    cat >"$exercise_ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " = *' monitor address '* ]]; then
    trap '' TERM
    while :; do /usr/bin/sleep 1; done
fi
if [[ "${CADDY_EXERCISE_VIPS:-0}" = 4 ]]; then
    printf '%s\n' \
        '1: eth0    inet 10.1.0.55/22 scope global eth0' \
        '1: eth0    inet 10.1.0.56/22 scope global eth0' \
        '1: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global' \
        '1: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global'
fi
IP
    cat >"$exercise_sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail
:
SLEEP
    cat >"$exercise_date" <<'DATE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '2026-08-23T12:00:00.000000000Z'
DATE
    cat >"$exercise_dig" <<'DIG'
#!/usr/bin/env bash
set -Eeuo pipefail
case " $* " in
    *' AAAA '*) printf '%s\n' 'fd36:5aa8:6971:1::55' ;;
    *) printf '%s\n' '10.1.0.55' ;;
esac
DIG
    cat >"$exercise_curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
case " $* " in
    *' https://proxy.local.theama.co/ '*) status=204 ;;
    *) status=200 ;;
esac
printf '%s\t0.001\t0.002\t0.003\t0.004\t10.1.0.56\t10.1.0.53' "$status"
CURL
    chmod 0700 "$exercise_systemctl" "$exercise_journalctl" "$exercise_busctl" \
        "$exercise_ip" "$exercise_sleep" "$exercise_date" "$exercise_dig" "$exercise_curl"
    : >"$exercise_test_root/systemctl.calls"
    : >"$exercise_test_root/journalctl.calls"
    : >"$exercise_test_root/journal.log"

    for exercise_scenario in "${exercise_scenarios[@]}"; do
        exercise_role=${exercise_scenario%%-*}-${exercise_scenario#*-}
        case "$exercise_scenario" in node-a-*) exercise_role=node-a ;; *) exercise_role=node-b ;; esac
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
            CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
            /bin/bash "$exercise_script" exercise-service "$exercise_role" \
            "$exercise_payload" "$exercise_evidence" "$exercise_scenario:stop"
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
            CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
            /bin/bash "$exercise_script" exercise-service "$exercise_role" \
            "$exercise_payload" "$exercise_evidence" "$exercise_scenario:start"
    done
    printf 'active\n' >"$exercise_test_root/state-lighttpd_service"
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_STOP_STATE=failed \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:stop
    [[ "$(<"$exercise_test_root/state-lighttpd_service")" = failed ]]
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:start
    [[ "$(<"$exercise_test_root/state-lighttpd_service")" = active ]]
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_STOP_STATE=active \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:stop \
        >"$exercise_test_root/unexpected-active.stdout" \
        2>"$exercise_test_root/unexpected-active.stderr"; then
        return 1
    fi
    [[ "$(<"$exercise_test_root/state-lighttpd_service")" = active ]]
    path_absent "$exercise_evidence/exercise-node-a-lighttpd.mutation.tsv"
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_FAIL_SHOW=1 \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:stop \
        >"$exercise_test_root/status-read-failure.stdout" \
        2>"$exercise_test_root/status-read-failure.stderr"; then
        return 1
    fi
    [[ "$(<"$exercise_test_root/state-lighttpd_service")" = active ]]
    path_absent "$exercise_evidence/exercise-node-a-lighttpd.mutation.tsv"
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_STOP_STATE=active CADDY_EXERCISE_FAIL_START=1 \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:stop \
        >"$exercise_test_root/recovery-failure.stdout" \
        2>"$exercise_test_root/recovery-failure.stderr"; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    [[ "$exercise_status" -eq 125 ]]
    regular_file "$exercise_evidence/exercise-node-a-lighttpd.mutation.tsv"
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-a \
        "$exercise_payload" "$exercise_evidence" node-a-lighttpd:restore
    path_absent "$exercise_evidence/exercise-node-a-lighttpd.mutation.tsv"
    exercise_raw=$exercise_test_root/raw/exercise-service-control.txt
    exercise_decision=$exercise_test_root/decisions/exercise-service-control.tsv
    {
        printf '%s\n' \
            'inactive_stop_accepted=true' \
            'failed_stop_accepted=true' \
            'unexpected_active_recovered=true' \
            'status_read_failure_recovered=true' \
            'unproven_recovery_status=125' \
            'final_residue=absent'
        cat "$exercise_test_root/systemctl.calls"
    } >"$exercise_raw"
    write_decision exercise-service-control accept 0 all-scenarios-restored \
        all-scenarios-restored "$exercise_raw" "$exercise_decision"

    exercise_raw=$exercise_test_root/raw/exercise-role-rejection.txt
    exercise_decision=$exercise_test_root/decisions/exercise-role-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-b "$exercise_payload" \
        "$exercise_evidence" node-a-caddy:stop >"$exercise_raw" 2>&1; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    write_decision exercise-role-rejection reject "$exercise_status" node-a node-b \
        "$exercise_raw" "$exercise_decision"

    for exercise_scenario in Master:4 Backup:0 Fault:0; do
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
            CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$exercise_busctl \
            CADDY_SERVING_HEALTH_IP_COMMAND=$exercise_ip \
            CADDY_SERVING_HEALTH_DATE_COMMAND=$exercise_date \
            CADDY_SERVING_HEALTH_SLEEP_COMMAND=$exercise_sleep \
            CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS=1 \
            CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES=1 \
            CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY=0 \
            CADDY_EXERCISE_STATE=${exercise_scenario%:*} \
            CADDY_EXERCISE_VIPS=${exercise_scenario#*:} \
            /bin/bash "$exercise_script" exercise-ownership node-a "$exercise_payload" \
            "$exercise_evidence" "$(tr '[:upper:]' '[:lower:]' <<<"${exercise_scenario%:*}")${exercise_scenario#*:}"
    done
    exercise_raw=$exercise_test_root/raw/exercise-ownership-convergence.txt
    exercise_decision=$exercise_test_root/decisions/exercise-ownership-convergence.tsv
    cp -- "$exercise_evidence/exercise-ownership-samples.tsv" "$exercise_raw"
    write_decision exercise-ownership-convergence accept 0 master-backup-fault \
        master-backup-fault "$exercise_raw" "$exercise_decision"

    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$exercise_journalctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-cursor node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy:stop
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy:start
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$exercise_journalctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-journal node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy
    exercise_raw=$exercise_test_root/raw/exercise-journal-bounded.txt
    exercise_decision=$exercise_test_root/decisions/exercise-journal-bounded.tsv
    cp -- "$exercise_evidence/exercise_node-a-caddy_journal.stdout" "$exercise_raw"
    write_decision exercise-journal-bounded accept 0 cursor-bounded cursor-bounded \
        "$exercise_raw" "$exercise_decision"

    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$exercise_journalctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-cursor node-a "$exercise_payload" \
        "$exercise_evidence" node-a-lighttpd
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_PENDING_ENQUEUE=1 \
        /bin/bash "$exercise_script" exercise-service node-a "$exercise_payload" \
        "$exercise_evidence" node-a-lighttpd:stop
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$exercise_journalctl \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND=$exercise_sleep \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-observe node-a "$exercise_payload" \
        "$exercise_evidence" node-a-lighttpd
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-service node-a "$exercise_payload" \
        "$exercise_evidence" node-a-lighttpd:start
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=$exercise_journalctl \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND=$exercise_sleep \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" exercise-journal node-a "$exercise_payload" \
        "$exercise_evidence" node-a-lighttpd
    exercise_raw=$exercise_test_root/raw/exercise-lighttpd-pending-enqueue.txt
    exercise_decision=$exercise_test_root/decisions/exercise-lighttpd-pending-enqueue.tsv
    cp -- "$exercise_evidence/exercise_node-a-lighttpd_journal.stdout" "$exercise_raw"
    grep -Fq 'pihole_web_health event=enqueue-failure-pending' "$exercise_raw"
    grep -Fq 'pihole_web_health event=recovered-before-enqueue' "$exercise_raw"
    [[ "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=failure' \
        "$exercise_raw")" -eq 1 ]]
    [[ "$(grep -Ec 'event=enqueued .*source=pihole-web .*severity=success' \
        "$exercise_raw")" -eq 1 ]]
    write_decision exercise-lighttpd-pending-enqueue accept 0 \
        pending-eventual-failure-and-recovery-delivery \
        pending-eventual-failure-and-recovery-delivery "$exercise_raw" "$exercise_decision"

    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$exercise_busctl \
        CADDY_SERVING_HEALTH_IP_COMMAND=$exercise_ip \
        CADDY_SERVING_HEALTH_DATE_COMMAND=$exercise_date \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND=$exercise_sleep \
        CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$exercise_dig \
        CADDY_SERVING_HEALTH_CURL_COMMAND=$exercise_curl \
        CADDY_SERVING_HEALTH_SAMPLER_MAX_CYCLES=4 \
        CADDY_SERVING_HEALTH_SAMPLER_DELAY=0 \
        CADDY_EXERCISE_STATE=Master CADDY_EXERCISE_VIPS=4 \
        /bin/bash "$exercise_script" sampler-start node-a "$exercise_payload" \
        "$exercise_evidence" shared-only
    /usr/bin/sleep 0.1
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" sampler-scenario node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        /bin/bash "$exercise_script" sampler-stop node-a "$exercise_payload" \
        "$exercise_evidence" shared-only
    exercise_raw=$exercise_test_root/raw/exercise-sampler-sigterm-lifecycle.txt
    exercise_decision=$exercise_test_root/decisions/exercise-sampler-sigterm-lifecycle.tsv
    {
        printf 'sampler_pid_alive=%s\n' \
            "$(kill -0 "$(<"$exercise_evidence/availability.pid")" 2>/dev/null && printf yes || printf no)"
        printf 'observer_pid_alive=%s\n' \
            "$(kill -0 "$(<"$exercise_evidence/vip-address-monitor.pid")" 2>/dev/null && printf yes || printf no)"
        printf 'work_residue=%s\n' \
            "$([[ -e "$exercise_evidence/availability-work" ]] && printf present || printf absent)"
    } >"$exercise_raw"
    grep -Fxq sampler_pid_alive=no "$exercise_raw"
    grep -Fxq observer_pid_alive=no "$exercise_raw"
    grep -Fxq work_residue=absent "$exercise_raw"
    write_decision exercise-sampler-sigterm-lifecycle accept 0 terminated-cleanly \
        terminated-cleanly "$exercise_raw" "$exercise_decision"

    exercise_raw=$exercise_test_root/raw/exercise-reverse-restoration.txt
    exercise_decision=$exercise_test_root/decisions/exercise-reverse-restoration.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$exercise_test_root \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$exercise_systemctl \
        CADDY_EXERCISE_TEST_ROOT=$exercise_test_root \
        CADDY_EXERCISE_FAIL_STOP=1 \
        /bin/bash "$exercise_script" exercise-service node-a "$exercise_payload" \
        "$exercise_evidence" node-a-caddy:stop >"$exercise_raw" 2>&1; then
        exercise_status=0
    else
        exercise_status=$?
    fi
    write_decision exercise-reverse-restoration reject "$exercise_status" stop-success \
        stop-failed-service-active "$exercise_raw" "$exercise_decision"
    grep -Fxq active "$exercise_test_root/state-caddy_service"
    printf '%s_controlled_failure_exercise_production_path_test_complete=true\n' "$prefix"
    printf '%s_production_path_test_complete=true\n' "$prefix"
}

notification_state_contract_production_path_test() {
    local notification_test_root=$1
    local notification_fixture=$notification_test_root/notification-state-contract
    local notification_parent=$notification_fixture/var/lib/caddy-serving-health
    local notification_root=$notification_parent/keepalived-notify
    local notification_state=$notification_root/PIHOLE_DUALSTACK.state
    local notification_lock=$notification_root/PIHOLE_DUALSTACK.lock
    local notification_evidence=$notification_fixture/evidence
    local notification_owner notification_group notification_raw notification_decision
    local notification_status notification_scenario

    notification_owner=$(id -un)
    notification_group=$(id -gn)
    install -d -m 0755 "$notification_parent"
    install -d -m 0700 "$notification_root"
    install -d -m 0700 "$notification_evidence"
    printf 'BACKUP\n' >"$notification_state"
    chmod 0600 "$notification_state"

    notification_raw=$notification_test_root/raw/notification-state-only.txt
    notification_decision=$notification_test_root/decisions/notification-state-only.tsv
    validate_notification_state_contract "$notification_parent" "$notification_root" BACKUP \
        "$notification_owner" "$notification_group" "$notification_owner" \
        "$notification_group" "$notification_evidence" \
        >"$notification_raw" 2>&1
    write_decision notification-state-only accept 0 state state \
        "$notification_raw" "$notification_decision"

    : >"$notification_lock"
    chmod 0600 "$notification_lock"
    notification_raw=$notification_test_root/raw/notification-state-lock.txt
    notification_decision=$notification_test_root/decisions/notification-state-lock.tsv
    validate_notification_state_contract "$notification_parent" "$notification_root" BACKUP \
        "$notification_owner" "$notification_group" "$notification_owner" \
        "$notification_group" "$notification_evidence" \
        >"$notification_raw" 2>&1
    write_decision notification-state-lock accept 0 state-lock state-lock \
        "$notification_raw" "$notification_decision"
    rm -f -- "$notification_lock"

    for notification_scenario in unexpected pending symlink malformed state-mode root-mode missing; do
        case "$notification_scenario" in
            unexpected) : >"$notification_root/unexpected" ;;
            pending)
                printf 'BACKUP\tFAULT\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t2026-08-23T12:00:00Z\n' \
                    >"$notification_root/PIHOLE_DUALSTACK.pending"
                chmod 0600 "$notification_root/PIHOLE_DUALSTACK.pending"
                ;;
            symlink)
                mv -- "$notification_state" "$notification_fixture/state.saved"
                ln -s -- "$notification_fixture/state.saved" "$notification_state"
                ;;
            malformed) printf 'not-valid\n' >"$notification_state" ;;
            state-mode) chmod 0644 "$notification_state" ;;
            root-mode) chmod 0755 "$notification_root" ;;
            missing) mv -- "$notification_state" "$notification_fixture/state.saved" ;;
        esac
        notification_raw=$notification_test_root/raw/notification-state-$notification_scenario.txt
        notification_decision=$notification_test_root/decisions/notification-state-$notification_scenario.tsv
        if validate_notification_state_contract "$notification_parent" "$notification_root" BACKUP \
            "$notification_owner" "$notification_group" "$notification_owner" \
            "$notification_group" "$notification_evidence" \
            >"$notification_raw" 2>&1; then
            notification_status=0
        else
            notification_status=$?
        fi
        write_decision "notification-state-$notification_scenario" reject \
            "$notification_status" safe "$notification_scenario" \
            "$notification_raw" "$notification_decision"
        [[ "$notification_status" -ne 0 ]]
        case "$notification_scenario" in
            unexpected) rm -f -- "$notification_root/unexpected" ;;
            pending) rm -f -- "$notification_root/PIHOLE_DUALSTACK.pending" ;;
            symlink)
                rm -f -- "$notification_state"
                mv -- "$notification_fixture/state.saved" "$notification_state"
                ;;
            malformed) printf 'BACKUP\n' >"$notification_state" ;;
            state-mode) chmod 0600 "$notification_state" ;;
            root-mode) chmod 0700 "$notification_root" ;;
            missing) mv -- "$notification_fixture/state.saved" "$notification_state" ;;
        esac
    done
    chmod -R u+rwX -- "$notification_fixture"
    rm -rf -- "$notification_fixture"
    printf '%s_notification_state_contract_production_path_test_complete=true\n' "$prefix"
}

production_path_test() {
    local serving_health_test_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?missing evidence root}
    local serving_health_repo_root serving_health_inventory serving_health_key serving_health_repository
    local serving_health_source serving_health_target serving_health_inventory_node serving_health_source_hash
    local serving_health_deployed_hash serving_health_accepted serving_health_lifecycle serving_health_source_path
    local serving_health_observed serving_health_raw serving_health_decision serving_health_status
    local serving_health_state_root serving_health_payload serving_health_evidence serving_health_candidate
    local serving_health_release_hash serving_health_payload_hash serving_health_systemctl
    local serving_health_marker serving_health_marker_label serving_health_quarantine_manifest
    local serving_health_quarantine_name serving_health_quarantine_candidate
    local serving_health_test_target serving_health_saved_hash serving_health_missing_candidate
    local serving_health_saved_manifest
    local serving_health_promotion_root serving_health_promotion_payload
    local serving_health_promotion_evidence serving_health_promotion_target
    local serving_health_promotion_candidate serving_health_promotion_manifest_hash
    local serving_health_runuser serving_health_finalizer serving_health_dig serving_health_curl
    local serving_health_ss serving_health_unbound_checkconf serving_health_publisher
    local serving_health_current_before serving_health_target_test_revision
    local serving_health_current_after serving_health_phase_helper
    local serving_health_namespace_root serving_health_namespace_target

    serving_health_write_quarantine_manifest() {
        local serving_health_fixture_root=$1
        local serving_health_fixture_manifest=$2
        local serving_health_fixture_path serving_health_fixture_relative
        local serving_health_fixture_encoded serving_health_fixture_type
        local serving_health_fixture_metadata serving_health_fixture_hash

        printf '# path-b64\ttype\tmetadata\tsha256\n' >"$serving_health_fixture_manifest"
        while IFS= read -r -d '' serving_health_fixture_path; do
            serving_health_fixture_relative=${serving_health_fixture_path#"$serving_health_fixture_root"/}
            serving_health_fixture_encoded=$(printf '%s' "$serving_health_fixture_relative" | base64 -w 0)
            if [[ -d "$serving_health_fixture_path" && ! -L "$serving_health_fixture_path" ]]; then
                serving_health_fixture_type=directory
                serving_health_fixture_hash=-
            elif [[ -f "$serving_health_fixture_path" && ! -L "$serving_health_fixture_path" ]]; then
                if [[ -s "$serving_health_fixture_path" ]]; then
                    serving_health_fixture_type='regular file'
                else
                    serving_health_fixture_type='regular empty file'
                fi
                serving_health_fixture_hash=$(sha256sum "$serving_health_fixture_path" | awk '{ print $1 }')
            else
                return 1
            fi
            serving_health_fixture_metadata=$(stat -c '%U:%G:%a' "$serving_health_fixture_path")
            printf '%s\t%s\t%s\t%s\n' "$serving_health_fixture_encoded" \
                "$serving_health_fixture_type" "$serving_health_fixture_metadata" \
                "$serving_health_fixture_hash" >>"$serving_health_fixture_manifest"
        done < <(find "$serving_health_fixture_root" -mindepth 1 -print0 | LC_ALL=C sort -z)
    }

    [[ "$serving_health_test_root" = /tmp/* && -d "$serving_health_test_root" && ! -L "$serving_health_test_root" ]]
    chmod 0700 "$serving_health_test_root"
    install -d -m 0700 "$serving_health_test_root/raw" "$serving_health_test_root/decisions"
    if [[ -n "${CADDY_SERVING_HEALTH_TEST_REPOSITORY_ROOT:-}" ]]; then
        serving_health_repo_root=$CADDY_SERVING_HEALTH_TEST_REPOSITORY_ROOT
    else
        serving_health_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    fi
    notification_state_contract_production_path_test "$serving_health_test_root"
    if [[ "${CADDY_NOTIFICATION_STATE_CONTRACT_ONLY:-0}" = 1 ]]; then
        printf '%s_production_path_test_complete=true\n' "$prefix"
        return
    fi
    if [[ "${CADDY_CONTROLLED_EXERCISE_CONTRACT_ONLY:-0}" = 1 ]]; then
        controlled_failure_exercise_production_path_test "$serving_health_test_root" \
            "$serving_health_repo_root"
        return
    fi
    if grep -Fxq 'scope: pihole-web-health-unit-only' \
        "$serving_health_repo_root/Caddy/manifests/serving-health-operation.yaml"; then
        web_health_unit_production_path_test "$serving_health_repo_root"
        return
    fi
    if grep -Fxq 'scope: notification-standardization-only' \
        "$serving_health_repo_root/Caddy/manifests/serving-health-operation.yaml"; then
        notification_standardization_production_path_test "$serving_health_repo_root"
        return
    fi
    if grep -Fxq 'scope: external-notification-attribution-read-only' \
        "$serving_health_repo_root/Caddy/manifests/serving-health-operation.yaml"; then
        external_attribution_production_path_test "$serving_health_test_root" \
            "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh"
        return
    fi
    if grep -Fxq 'scope: controlled-serving-failure-exercise' \
        "$serving_health_repo_root/Caddy/manifests/serving-health-operation.yaml"; then
        controlled_failure_exercise_production_path_test "$serving_health_test_root" \
            "$serving_health_repo_root"
        return
    fi
    serving_health_inventory=$serving_health_repo_root/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r serving_health_key serving_health_repository serving_health_source \
        serving_health_target serving_health_inventory_node serving_health_source_hash \
        serving_health_deployed_hash serving_health_accepted serving_health_lifecycle; do
        [[ "$serving_health_key" = '# key' ]] && continue
        serving_health_raw=$serving_health_test_root/raw/inventory-$serving_health_key.txt
        serving_health_decision=$serving_health_test_root/decisions/inventory-$serving_health_key.tsv
        if [[ "$serving_health_repository" = runtime-generated ]]; then
            printf '%s\t%s\t%s\n' "$serving_health_key" "$serving_health_target" \
                "$serving_health_deployed_hash" >"$serving_health_raw"
            serving_health_observed=$(awk -F '\t' '{ print $3 }' "$serving_health_raw")
            require_equal "production_inventory_${serving_health_key}" \
                "$serving_health_deployed_hash" "$serving_health_observed"
            write_decision "inventory-$serving_health_key" accept 0 \
                "$serving_health_deployed_hash" "$serving_health_observed" \
                "$serving_health_raw" "$serving_health_decision"
            continue
        fi
        serving_health_source_path=${serving_health_repo_root%/homelab-server-configs}/$serving_health_repository/$serving_health_source
        sha256sum "$serving_health_source_path" >"$serving_health_raw"
        serving_health_observed=$(awk '{ print $1 }' "$serving_health_raw")
        require_equal "production_inventory_${serving_health_key}" \
            "$serving_health_source_hash" "$serving_health_observed"
        write_decision "inventory-$serving_health_key" accept 0 \
            "$serving_health_source_hash" "$serving_health_observed" \
            "$serving_health_raw" "$serving_health_decision"
    done <"$serving_health_inventory"

    serving_health_state_root=$serving_health_test_root/state
    serving_health_namespace_root=$serving_health_test_root/protocol-namespace
    serving_health_namespace_target=$serving_health_test_root/protocol-namespace-target
    production_path_test_namespace_case "$serving_health_test_root" absent accept \
        "$serving_health_namespace_root"
    install -d -m 0750 "$serving_health_namespace_root"
    production_path_test_namespace_case "$serving_health_test_root" empty-protected accept \
        "$serving_health_namespace_root"
    printf 'unexpected\n' >"$serving_health_namespace_root/unexpected"
    production_path_test_namespace_case "$serving_health_test_root" non-empty reject \
        "$serving_health_namespace_root"
    rm -f -- "$serving_health_namespace_root/unexpected"
    chmod 0770 "$serving_health_namespace_root"
    production_path_test_namespace_case "$serving_health_test_root" unsafe-mode reject \
        "$serving_health_namespace_root"
    chmod 0750 "$serving_health_namespace_root"
    production_path_test_namespace_case "$serving_health_test_root" unsafe-owner reject \
        "$serving_health_namespace_root" different-owner:different-group:750
    rmdir "$serving_health_namespace_root"
    install -d -m 0750 "$serving_health_namespace_target"
    ln -s "$serving_health_namespace_target" "$serving_health_namespace_root"
    production_path_test_namespace_case "$serving_health_test_root" symlink reject \
        "$serving_health_namespace_root"
    rm -f -- "$serving_health_namespace_root"
    rmdir "$serving_health_namespace_target"
    printf 'not-a-directory\n' >"$serving_health_namespace_root"
    production_path_test_namespace_case "$serving_health_test_root" malformed reject \
        "$serving_health_namespace_root"
    rm -f -- "$serving_health_namespace_root"
    serving_health_raw=$serving_health_test_root/raw/protocol-namespace-state-equivalence.txt
    serving_health_decision=$serving_health_test_root/decisions/protocol-namespace-state-equivalence.tsv
    cat "$serving_health_test_root"/raw/protocol-namespace-{absent,empty-protected,non-empty,unsafe-mode,unsafe-owner,symlink,malformed}.txt \
        >"$serving_health_raw"
    write_decision protocol-namespace-state-equivalence accept 0 \
        'accept:absent,empty-protected;reject:non-empty,unsafe-mode,unsafe-owner,symlink,malformed' \
        'accept:absent,empty-protected;reject:non-empty,unsafe-mode,unsafe-owner,symlink,malformed' \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_payload=$(mktemp -d /tmp/caddy-serving-health-production-payload.XXXXXX)
    serving_health_evidence=$(mktemp -d /tmp/caddy-serving-health-production-evidence.XXXXXX)
    serving_health_candidate=$serving_health_state_root/incoming/node-a/$retained_name
    serving_health_systemctl=$serving_health_test_root/systemctl
    install -d -m 0700 "$serving_health_candidate" \
        "$serving_health_state_root/outgoing" \
        "$serving_health_state_root/releases" "$serving_health_payload/manifests" \
        "$serving_health_evidence"
    install -d -m 0750 "$serving_health_state_root/quarantine"
    printf '# repository\tsource-path\tinstalled-path\tmode\tcandidate-sha256\tlifecycle\n' \
        >"$serving_health_payload/manifests/serving-health-production.tsv"
    install -m 0600 \
        "$serving_health_repo_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$serving_health_payload/manifests/serving-health-quarantine-baseline.tsv"
    printf 'payload\n' >"$serving_health_candidate/Caddyfile"
    printf '%s  Caddyfile\n' "$(sha256sum "$serving_health_candidate/Caddyfile" | awk '{ print $1 }')" \
        >"$serving_health_candidate/manifest.sha256"
    printf '{"revision":"%s","source_node":"node-a"}\n' "$retained_name" \
        >"$serving_health_candidate/release-manifest.json"
    chmod 0500 "$serving_health_candidate"
    while IFS= read -r serving_health_quarantine_name; do
        serving_health_quarantine_candidate=$serving_health_state_root/quarantine/$serving_health_quarantine_name
        install -d -m 0750 "$serving_health_quarantine_candidate"
        printf 'payload for %s\n' "$serving_health_quarantine_name" \
            >"$serving_health_quarantine_candidate/Caddyfile"
        printf '{"revision":"%s","parent_revision":"fixture-parent","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
            "$serving_health_quarantine_name" \
            >"$serving_health_quarantine_candidate/release-manifest.json"
        {
            printf '%s  Caddyfile\n' \
                "$(sha256sum "$serving_health_quarantine_candidate/Caddyfile" | awk '{ print $1 }')"
            printf '%s  release-manifest.json\n' \
                "$(sha256sum "$serving_health_quarantine_candidate/release-manifest.json" | awk '{ print $1 }')"
        } >"$serving_health_quarantine_candidate/manifest.sha256"
        chmod 0440 "$serving_health_quarantine_candidate/"*
        case "$serving_health_quarantine_name" in
            node-a-action17p-* | node-a-action33k-*)
                : >"$serving_health_quarantine_candidate/.complete"
                : >"$serving_health_quarantine_candidate/.finalize-request"
                chmod 0440 "$serving_health_quarantine_candidate/.complete" \
                    "$serving_health_quarantine_candidate/.finalize-request"
                ;;
            *)
                : >"$serving_health_quarantine_candidate/.finalize-request"
                chmod 0440 "$serving_health_quarantine_candidate/.finalize-request"
                ;;
        esac
        chmod 0550 "$serving_health_quarantine_candidate"
    done < <(quarantine_names)
    serving_health_quarantine_manifest=$serving_health_test_root/quarantine-inventory.tsv
    serving_health_write_quarantine_manifest "$serving_health_state_root/quarantine" \
        "$serving_health_quarantine_manifest"
    serving_health_test_target=$serving_health_test_root/target
    install -d -m 0700 "$serving_health_test_target/etc/caddy/releases/current-test"
    ln -s releases/current-test "$serving_health_test_target/etc/caddy/current"
    install -d -m 0755 "$serving_health_test_target/usr/local/libexec"
    install -m 0755 "$serving_health_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$serving_health_test_target$legacy_lighttpd_helper"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-node-b-baseline.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-node-b-baseline.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    write_decision legacy-helper-node-b-baseline accept 0 exact-legacy exact-legacy \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-removal.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-removal.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-remove node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    path_absent "$serving_health_test_target$legacy_lighttpd_helper"
    write_decision legacy-helper-removal accept 0 absent absent \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-rollback.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-rollback.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-rollback node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    require_equal production_test_legacy_helper_restored "$legacy_lighttpd_helper_sha256" \
        "$(sha256sum "$serving_health_test_target$legacy_lighttpd_helper" | awk '{ print $1 }')"
    write_decision legacy-helper-rollback accept 0 exact-legacy exact-legacy \
        "$serving_health_raw" "$serving_health_decision"
    rm -f -- "$serving_health_test_target$legacy_lighttpd_helper"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-node-a-baseline.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-node-a-baseline.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw"
    write_decision legacy-helper-node-a-baseline accept 0 absent absent \
        "$serving_health_raw" "$serving_health_decision"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-node-b-absent-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-node-b-absent-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision legacy-helper-node-b-absent-rejection reject "$serving_health_status" \
        exact-legacy absent "$serving_health_raw" "$serving_health_decision"
    install -m 0755 "$serving_health_repo_root/Caddy/scripts/prepare-lighttpd-config.sh" \
        "$serving_health_test_target$legacy_lighttpd_helper"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-node-a-present-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-node-a-present-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-check node-a "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision legacy-helper-node-a-present-rejection reject "$serving_health_status" \
        absent present "$serving_health_raw" "$serving_health_decision"
    rm -f -- "$serving_health_test_target$legacy_lighttpd_helper"
    ln -s /dev/null "$serving_health_test_target$legacy_lighttpd_helper"
    serving_health_raw=$serving_health_test_root/raw/legacy-helper-node-b-symlink-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/legacy-helper-node-b-symlink-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        legacy-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision legacy-helper-node-b-symlink-rejection reject "$serving_health_status" \
        regular-file symlink "$serving_health_raw" "$serving_health_decision"
    rm -f -- "$serving_health_test_target$legacy_lighttpd_helper"
    serving_health_release_hash=$(sha256sum "$serving_health_candidate/release-manifest.json" | awk '{ print $1 }')
    serving_health_payload_hash=$(sha256sum "$serving_health_candidate/manifest.sha256" | awk '{ print $1 }')
    cat >"$serving_health_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS:?}"
SYSTEMCTL
    chmod 0700 "$serving_health_systemctl"
    : >"$serving_health_test_root/systemctl.calls"
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$serving_health_release_hash \
        CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$serving_health_payload_hash \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        retained-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_test_root/retained-check.stdout"
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_test_root/quarantine-check.stdout"
    install -d -m 0550 "$serving_health_state_root/quarantine/unexpected"
    serving_health_raw=$serving_health_test_root/raw/quarantine-extra-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-extra-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-extra-rejection reject "$serving_health_status" \
        exact-four-entries extra-entry "$serving_health_raw" "$serving_health_decision"
    rmdir "$serving_health_state_root/quarantine/unexpected"
    serving_health_quarantine_candidate=$serving_health_state_root/quarantine/$(quarantine_names | sed -n '1p')
    serving_health_saved_hash=$(sha256sum "$serving_health_quarantine_candidate/Caddyfile" | awk '{ print $1 }')
    chmod 0750 "$serving_health_quarantine_candidate"
    chmod 0640 "$serving_health_quarantine_candidate/Caddyfile"
    printf 'changed\n' >>"$serving_health_quarantine_candidate/Caddyfile"
    serving_health_raw=$serving_health_test_root/raw/quarantine-changed-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-changed-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-changed-rejection reject "$serving_health_status" \
        exact-captured-hash changed-hash "$serving_health_raw" "$serving_health_decision"
    sed -i '$d' "$serving_health_quarantine_candidate/Caddyfile"
    chmod 0440 "$serving_health_quarantine_candidate/Caddyfile"
    [[ "$(sha256sum "$serving_health_quarantine_candidate/Caddyfile" | awk '{ print $1 }')" = "$serving_health_saved_hash" ]]
    mv "$serving_health_quarantine_candidate/Caddyfile" \
        "$serving_health_quarantine_candidate/Caddyfile.saved"
    ln -s Caddyfile.saved "$serving_health_quarantine_candidate/Caddyfile"
    serving_health_raw=$serving_health_test_root/raw/quarantine-symlink-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-symlink-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-symlink-rejection reject "$serving_health_status" \
        regular-file symlink "$serving_health_raw" "$serving_health_decision"
    rm "$serving_health_quarantine_candidate/Caddyfile"
    mv "$serving_health_quarantine_candidate/Caddyfile.saved" \
        "$serving_health_quarantine_candidate/Caddyfile"
    chmod 0550 "$serving_health_quarantine_candidate"
    serving_health_missing_candidate=$serving_health_test_root/missing-quarantine-candidate
    chmod 0750 "$serving_health_quarantine_candidate"
    mv "$serving_health_quarantine_candidate" "$serving_health_missing_candidate"
    serving_health_raw=$serving_health_test_root/raw/quarantine-missing-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-missing-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-missing-rejection reject "$serving_health_status" \
        exact-four-entries missing-entry "$serving_health_raw" "$serving_health_decision"
    mv "$serving_health_missing_candidate" "$serving_health_quarantine_candidate"
    chmod 0550 "$serving_health_quarantine_candidate"
    serving_health_saved_manifest=$serving_health_test_root/release-manifest.saved
    install -m 0600 "$serving_health_quarantine_candidate/release-manifest.json" \
        "$serving_health_saved_manifest"
    chmod 0750 "$serving_health_quarantine_candidate"
    chmod 0640 "$serving_health_quarantine_candidate/release-manifest.json"
    printf '{\n' >"$serving_health_quarantine_candidate/release-manifest.json"
    serving_health_write_quarantine_manifest "$serving_health_state_root/quarantine" \
        "$serving_health_quarantine_manifest"
    serving_health_raw=$serving_health_test_root/raw/quarantine-malformed-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-malformed-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-malformed-rejection reject "$serving_health_status" \
        valid-release-json malformed-json "$serving_health_raw" "$serving_health_decision"
    install -m 0440 "$serving_health_saved_manifest" \
        "$serving_health_quarantine_candidate/release-manifest.json"
    chmod 0550 "$serving_health_quarantine_candidate"
    serving_health_write_quarantine_manifest "$serving_health_state_root/quarantine" \
        "$serving_health_quarantine_manifest"
    rm "$serving_health_test_target/etc/caddy/current"
    ln -s "$serving_health_quarantine_candidate" \
        "$serving_health_test_target/etc/caddy/current"
    serving_health_raw=$serving_health_test_root/raw/quarantine-reference-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/quarantine-reference-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        quarantine-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        return 1
    else
        serving_health_status=$?
    fi
    write_decision quarantine-reference-rejection reject "$serving_health_status" \
        unreferenced active-reference "$serving_health_raw" "$serving_health_decision"
    rm "$serving_health_test_target/etc/caddy/current"
    ln -s releases/current-test "$serving_health_test_target/etc/caddy/current"
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$serving_health_release_hash \
        CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$serving_health_payload_hash \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        retained-disposition node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_test_root/retained-disposition.stdout"
    [[ ! -e "$serving_health_candidate" && -d "$serving_health_evidence/retained-incoming" ]]
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$serving_health_release_hash \
        CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$serving_health_payload_hash \
        CADDY_SERVING_HEALTH_QUARANTINE_INVENTORY_MANIFEST=$serving_health_quarantine_manifest \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_test_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        retained-rollback node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_test_root/retained-rollback.stdout"
    [[ -d "$serving_health_candidate" && ! -e "$serving_health_evidence/retained-incoming" ]]

    serving_health_raw=$serving_health_test_root/raw/transaction-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/transaction-rejection.tsv
    install -d -m 0700 "$serving_health_state_root/incoming/node-a/unexpected"
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
        CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$serving_health_release_hash \
        CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$serving_health_payload_hash \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        retained-check node-b "$serving_health_payload" "$serving_health_evidence" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision transaction-rejection reject "$serving_health_status" exact-retained-only \
        unexpected-sibling "$serving_health_raw" "$serving_health_decision"
    rmdir "$serving_health_state_root/incoming/node-a/unexpected"

    for serving_health_marker in .finalize-request .complete.pending .complete; do
        serving_health_marker_label=${serving_health_marker#.}
        serving_health_marker_label=${serving_health_marker_label//./-}
        chmod 0700 "$serving_health_candidate"
        : >"$serving_health_candidate/$serving_health_marker"
        chmod 0500 "$serving_health_candidate"
        serving_health_raw=$serving_health_test_root/raw/transaction-marker-$serving_health_marker_label-rejection.txt
        serving_health_decision=$serving_health_test_root/decisions/transaction-marker-$serving_health_marker_label-rejection.tsv
        if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_state_root/incoming \
            CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_state_root/outgoing \
            CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_state_root/quarantine \
            CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_state_root/releases \
            CADDY_SERVING_HEALTH_RETAINED_RELEASE_MANIFEST_SHA256=$serving_health_release_hash \
            CADDY_SERVING_HEALTH_RETAINED_PAYLOAD_MANIFEST_SHA256=$serving_health_payload_hash \
            /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            retained-check node-b "$serving_health_payload" "$serving_health_evidence" \
            >"$serving_health_raw" 2>&1; then
            serving_health_status=0
        else
            serving_health_status=$?
        fi
        write_decision "transaction-marker-$serving_health_marker_label-rejection" reject \
            "$serving_health_status" absent present "$serving_health_raw" "$serving_health_decision"
        chmod 0700 "$serving_health_candidate"
        rm -f -- "$serving_health_candidate/$serving_health_marker"
        chmod 0500 "$serving_health_candidate"
    done

    serving_health_raw=$serving_health_test_root/raw/transaction-acceptance.txt
    serving_health_decision=$serving_health_test_root/decisions/transaction-acceptance.tsv
    {
        cat "$serving_health_test_root/retained-check.stdout"
        cat "$serving_health_test_root/quarantine-check.stdout"
        cat "$serving_health_test_root/retained-disposition.stdout"
        cat "$serving_health_test_root/retained-rollback.stdout"
        cat "$serving_health_test_root/systemctl.calls"
        find "$serving_health_state_root/incoming/node-a" -mindepth 1 -maxdepth 1 \
            -printf '%f\t%y\t%u:%g:%m\n' | LC_ALL=C sort
    } >"$serving_health_raw"
    write_decision transaction-acceptance reach 0 retained-restored \
        retained-restored "$serving_health_raw" "$serving_health_decision"
    production_path_test_node_a_quarantine "$serving_health_test_root" \
        "$serving_health_repo_root" "$serving_health_state_root" "$serving_health_payload" \
        "$serving_health_evidence" "$serving_health_test_target" "$serving_health_systemctl"

    serving_health_promotion_root=$(mktemp -d /tmp/caddy-serving-health-promotion-state.XXXXXX)
    serving_health_promotion_payload=$(mktemp -d /tmp/caddy-serving-health-promotion-payload.XXXXXX)
    serving_health_promotion_evidence=$serving_health_promotion_root/evidence
    install -d -m 0700 "$serving_health_promotion_evidence"
    serving_health_promotion_target=$serving_health_promotion_root/target
    serving_health_promotion_candidate=$serving_health_promotion_root/outgoing/$serving_revision
    install -d -m 0700 "$serving_health_promotion_root/incoming" \
        "$serving_health_promotion_root/releases" "$serving_health_promotion_candidate" \
        "$serving_health_promotion_target/etc/caddy/releases/$node_a_revision" \
        "$serving_health_promotion_target/etc/default" \
        "$serving_health_promotion_payload/manifests" \
        "$serving_health_promotion_payload/repositories"
    printf '{"revision":"%s"}\n' "$node_a_revision" \
        >"$serving_health_promotion_target/etc/caddy/releases/$node_a_revision/release-manifest.json"
    ln -s "releases/$node_a_revision" "$serving_health_promotion_target/etc/caddy/current"
    printf 'NODE_FQDN=pihole0.local.theama.co\nNODE_IPV4=10.1.0.53\nNODE_IPV6=fd36:5aa8:6971:1::53\n' \
        >"$serving_health_promotion_target/etc/default/caddy-ha"
    install -m 0600 "$serving_health_repo_root/Caddy/manifests/serving-health-production.tsv" \
        "$serving_health_promotion_payload/manifests/serving-health-production.tsv"
    install -m 0600 "$serving_health_repo_root/Caddy/manifests/serving-health-quarantine-baseline.tsv" \
        "$serving_health_promotion_payload/manifests/serving-health-quarantine-baseline.tsv"
    while IFS=$'\t' read -r serving_health_repository serving_health_source _; do
        [[ "$serving_health_repository" = '# repository' ]] && continue
        serving_health_source_path=${serving_health_repo_root%/homelab-server-configs}/$serving_health_repository/$serving_health_source
        serving_health_target=$serving_health_promotion_payload/repositories/$serving_health_repository/$serving_health_source
        install -d -m 0700 "${serving_health_target%/*}"
        install -m 0600 "$serving_health_source_path" "$serving_health_target"
    done <"$serving_health_repo_root/Caddy/manifests/serving-health-production.tsv"
    install -d -m 0750 "$serving_health_promotion_candidate/conf.d"
    printf 'respond /healthz 204\n' >"$serving_health_promotion_candidate/Caddyfile"
    printf 'respond /admin/* 200\n' \
        >"$serving_health_promotion_candidate/conf.d/10-pihole-admin.caddy"
    printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-17T00:00:00Z"}\n' \
        "$serving_revision" "$serving_parent" \
        >"$serving_health_promotion_candidate/release-manifest.json"
    (
        cd "$serving_health_promotion_candidate"
        find . -type f ! -path ./manifest.sha256 -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$serving_health_promotion_candidate/manifest.sha256"
    : >"$serving_health_promotion_candidate/.finalize-request"
    find "$serving_health_promotion_candidate" -type d -exec chmod 0550 {} +
    find "$serving_health_promotion_candidate" -type f -exec chmod 0440 {} +
    serving_health_promotion_manifest_hash=$(sha256sum \
        "$serving_health_promotion_candidate/manifest.sha256" | awk '{ print $1 }')

    serving_health_runuser=$serving_health_promotion_root/runuser
    serving_health_finalizer=$serving_health_promotion_root/finalizer
    serving_health_dig=$serving_health_promotion_root/dig
    serving_health_curl=$serving_health_promotion_root/curl
    serving_health_ss=$serving_health_promotion_root/ss
    serving_health_unbound_checkconf=$serving_health_promotion_root/unbound-checkconf
    serving_health_publisher=$serving_health_promotion_root/publisher
    cat >"$serving_health_runuser" <<'RUNUSER'
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
    >>"${CADDY_SERVING_HEALTH_TEST_RUNUSER_CALLS:?}"
exec "$@"
RUNUSER
    cat >"$serving_health_finalizer" <<'FINALIZER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source-role && "$2" = node-a ]]
candidate=${CADDY_SERVING_HEALTH_INCOMING_ROOT:?}/node-a/${CADDY_SERVING_HEALTH_TEST_SERVING_REVISION:?}
[[ -d "$candidate" && -f "$candidate/.finalize-request" ]]
printf '%s\n' "$*" >>"${CADDY_SERVING_HEALTH_TEST_FINALIZER_CALLS:?}"
chmod 0750 "$candidate"
: >"$candidate/.complete"
chmod 0440 "$candidate/.complete"
chmod 0550 "$candidate"
FINALIZER
    cat >"$serving_health_publisher" <<'PUBLISHER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" = --source && -d "$2" && "$3" = --node-role && "$4" = node-a ]]
source_root=$2
revision=serving_health-production-path-target
candidate=${CADDY_SERVING_HEALTH_OUTGOING_ROOT:?}/$revision
[[ ! -e "$candidate" ]]
cp -a -- "$source_root" "$candidate"
printf '{"revision":"%s","parent_revision":"%s","source_node":"node-a","created_at":"2026-08-18T00:00:00Z"}\n' \
    "$revision" "${CADDY_SERVING_HEALTH_TEST_SERVING_REVISION:?}" \
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
    cat >"$serving_health_systemctl" <<'SYSTEMCTL_PROMOTION'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS:?}"
if [[ "$1" = start && "$2" = caddy-sync-reconcile.service ]]; then
    candidate=${CADDY_SERVING_HEALTH_INCOMING_ROOT:?}/node-a/${CADDY_SERVING_HEALTH_TEST_SERVING_REVISION:?}
    release=${CADDY_SERVING_HEALTH_RELEASES_ROOT:?}/${CADDY_SERVING_HEALTH_TEST_SERVING_REVISION:?}
    [[ -f "$candidate/.complete" ]]
    cp -a -- "$candidate" "$release"
    chmod 0750 "$release"
    chmod 0550 "$release"
    rm -f -- "${CADDY_SERVING_HEALTH_TARGET_ROOT:?}/etc/caddy/current"
    ln -s "$release" "$CADDY_SERVING_HEALTH_TARGET_ROOT/etc/caddy/current"
fi
case "$1" in
    is-active) [[ "$2" = --quiet ]] ;;
    start | stop) [[ $# -eq 2 ]] ;;
    *) : ;;
esac
SYSTEMCTL_PROMOTION
    cat >"$serving_health_dig" <<'DIG'
#!/usr/bin/env bash
case " $* " in
    *' A '*) printf '10.1.0.55\n' ;;
    *' AAAA '*) printf 'fd36:5aa8:6971:1::55\n' ;;
    *) exit 64 ;;
esac
DIG
    cat >"$serving_health_curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
curl_family=ipv4
[[ " $* " = *' --ipv4 '* ]] || curl_family=ipv6
case "${CADDY_SERVING_HEALTH_TEST_CURL_MODE:-healthy}" in
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
revision=$(jq -r '.revision // empty' "${CADDY_SERVING_HEALTH_TARGET_ROOT:?}/etc/caddy/current/release-manifest.json")
if [[ "$revision" = "${CADDY_SERVING_HEALTH_TEST_SERVING_REVISION:?}" ]]; then
    printf '204\n'
else
    printf '404\n'
    exit 22
fi
CURL
    cat >"$serving_health_ss" <<'SS'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 10.1.0.53:443 0.0.0.0:*\n'
printf 'LISTEN 0 4096 [fd36:5aa8:6971:1::53]:443 [::]:*\n'
SS
    cat >"$serving_health_unbound_checkconf" <<'UNBOUND'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]]
grep -Fq 'local-zone: "local.theama.co." static' "$1"
UNBOUND
    chmod 0700 "$serving_health_runuser" "$serving_health_finalizer" "$serving_health_publisher" \
        "$serving_health_systemctl" \
        "$serving_health_dig" "$serving_health_curl" "$serving_health_ss" "$serving_health_unbound_checkconf"
    : >"$serving_health_test_root/runuser.calls"
    : >"$serving_health_test_root/finalizer.calls"
    : >"$serving_health_test_root/systemctl.calls"
    serving_health_current_before=$(jq -r '.revision' \
        "$serving_health_promotion_target/etc/caddy/current/release-manifest.json")
    serving_health_raw=$serving_health_test_root/raw/post-promotion-sequence.txt
    serving_health_decision=$serving_health_test_root/decisions/post-promotion-sequence.tsv
    {
        printf 'current_before=%s\n' "$serving_health_current_before"
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_promotion_root/incoming \
            CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_promotion_root/outgoing \
            CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_promotion_root/quarantine \
            CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_promotion_root/releases \
            CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_promotion_target \
            CADDY_SERVING_HEALTH_SERVING_PAYLOAD_MANIFEST_SHA256=$serving_health_promotion_manifest_hash \
            CADDY_SERVING_HEALTH_FINALIZER_COMMAND=$serving_health_finalizer \
            CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$serving_health_runuser \
            CADDY_SERVING_HEALTH_SYNC_USER=$(id -un) CADDY_SERVING_HEALTH_SYNC_GROUP=$(id -gn) \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
            CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
            CADDY_SERVING_HEALTH_TEST_RUNUSER_CALLS=$serving_health_test_root/runuser.calls \
            CADDY_SERVING_HEALTH_TEST_FINALIZER_CALLS=$serving_health_test_root/finalizer.calls \
            CADDY_SERVING_HEALTH_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            promote node-a "$serving_health_promotion_payload" "$serving_health_promotion_evidence"
        serving_health_current_after=$(jq -r '.revision' \
            "$serving_health_promotion_target/etc/caddy/current/release-manifest.json")
        printf 'current_after=%s\n' "$serving_health_current_after"
        cat "$serving_health_test_root/runuser.calls" "$serving_health_test_root/finalizer.calls" \
            "$serving_health_test_root/systemctl.calls"
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_promotion_target \
            CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$serving_health_promotion_target/etc/default/caddy-ha \
            CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$serving_health_runuser \
            CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
            CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=$serving_health_dig \
            CADDY_SERVING_HEALTH_CURL_COMMAND=$serving_health_curl \
            CADDY_SERVING_HEALTH_SS_COMMAND=$serving_health_ss \
            CADDY_SERVING_HEALTH_UNBOUND_CHECKCONF_COMMAND=$serving_health_unbound_checkconf \
            CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
            CADDY_SERVING_HEALTH_TEST_RUNUSER_CALLS=$serving_health_test_root/runuser.calls \
            CADDY_SERVING_HEALTH_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            candidate-check node-a "$serving_health_promotion_payload" "$serving_health_promotion_evidence"
        cat "$serving_health_promotion_evidence/caddy_identity.stdout" \
            "$serving_health_promotion_evidence/caddy_identity.status"
    } >"$serving_health_raw" 2>&1
    serving_health_current_after=$(jq -r '.revision' \
        "$serving_health_promotion_target/etc/caddy/current/release-manifest.json")
    require_equal production_test_current_before "$node_a_revision" "$serving_health_current_before"
    require_equal production_test_current_after "$serving_revision" "$serving_health_current_after"
    write_decision post-promotion-sequence accept 0 "$serving_revision" \
        "$serving_health_current_after" "$serving_health_raw" "$serving_health_decision"

    serving_health_raw=$serving_health_test_root/raw/protocol-v2-target-publication.txt
    serving_health_decision=$serving_health_test_root/decisions/protocol-v2-target-publication.tsv
    install -d -m 0755 "$serving_health_promotion_root/target-outgoing"
    {
        CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
            CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_promotion_root/incoming \
            CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_promotion_root/target-outgoing \
            CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_promotion_root/quarantine \
            CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_promotion_root/releases \
            CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_promotion_target \
            CADDY_SERVING_HEALTH_PUBLISHER_COMMAND=$serving_health_publisher \
            CADDY_SERVING_HEALTH_TEST_SERVING_REVISION=$serving_revision \
            /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
            publish node-a "$serving_health_promotion_payload" "$serving_health_promotion_evidence"
    } >"$serving_health_raw" 2>&1
    serving_health_target_test_revision=$(<"$serving_health_promotion_evidence/target-revision")
    [[ "$serving_health_target_test_revision" = serving_health-production-path-target ]]
    [[ "$(jq -r '.parent_revision' \
        "$serving_health_promotion_root/target-outgoing/$serving_health_target_test_revision/release-manifest.json")" = "$serving_revision" ]]
    [[ "$(sha256sum \
        "$serving_health_promotion_root/target-outgoing/$serving_health_target_test_revision/conf.d/10-pihole-admin.caddy" | awk '{ print $1 }')" = 8e1b07f254c8dee21b9671de02993484c87b1838189341f605acb6581f7f49d8 ]]
    write_decision protocol-v2-target-publication accept 0 \
        serving_health-production-path-target "$serving_health_target_test_revision" \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_raw=$serving_health_test_root/raw/protocol-v2-target-promotion.txt
    serving_health_decision=$serving_health_test_root/decisions/protocol-v2-target-promotion.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_INCOMING_ROOT=$serving_health_promotion_root/incoming \
        CADDY_SERVING_HEALTH_OUTGOING_ROOT=$serving_health_promotion_root/target-outgoing \
        CADDY_SERVING_HEALTH_QUARANTINE_ROOT=$serving_health_promotion_root/quarantine \
        CADDY_SERVING_HEALTH_RELEASES_ROOT=$serving_health_promotion_root/releases \
        CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_promotion_target \
        CADDY_SERVING_HEALTH_FINALIZER_COMMAND=$serving_health_finalizer \
        CADDY_SERVING_HEALTH_RUNUSER_COMMAND=$serving_health_runuser \
        CADDY_SERVING_HEALTH_SYNC_USER=$(id -un) CADDY_SERVING_HEALTH_SYNC_GROUP=$(id -gn) \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        CADDY_SERVING_HEALTH_TEST_RUNUSER_CALLS=$serving_health_test_root/runuser.calls \
        CADDY_SERVING_HEALTH_TEST_FINALIZER_CALLS=$serving_health_test_root/finalizer.calls \
        CADDY_SERVING_HEALTH_TEST_SERVING_REVISION=$serving_health_target_test_revision \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        promote-target node-a "$serving_health_promotion_payload" \
        "$serving_health_promotion_evidence" >"$serving_health_raw" 2>&1
    serving_health_current_after=$(jq -r '.revision' \
        "$serving_health_promotion_target/etc/caddy/current/release-manifest.json")
    write_decision protocol-v2-target-promotion accept 0 \
        "$serving_health_target_test_revision" "$serving_health_current_after" \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_phase_helper=$serving_health_promotion_payload/repositories/homelab-server-configs/Caddy/scripts/check-caddy-serving-health.sh
    serving_health_raw=$serving_health_test_root/raw/minimal-caddy-failure.txt
    serving_health_decision=$serving_health_test_root/decisions/minimal-caddy-failure.tsv
    if CADDY_SERVING_HEALTH_TARGET_ROOT=$serving_health_promotion_target \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        CADDY_SERVING_HEALTH_TEST_SERVING_REVISION=$serving_revision \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE=$serving_health_promotion_target/etc/default/caddy-ha \
        CADDY_SERVING_HEALTH_CURL_COMMAND=/usr/bin/false \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        /bin/bash "$serving_health_phase_helper" \
        >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    printf 'exit_status=%s\n' "$serving_health_status" >>"$serving_health_raw"
    write_decision minimal-caddy-failure reject "$serving_health_status" \
        zero nonzero \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_phase_helper=$serving_health_promotion_payload/repositories/homelab-dns/Keepalived/scripts/dns-check.sh
    serving_health_raw=$serving_health_test_root/raw/minimal-dns-failure.txt
    serving_health_decision=$serving_health_test_root/decisions/minimal-dns-failure.tsv
    if DNS_CHECK_DIG_COMMAND=/usr/bin/false \
        DNS_CHECK_SYSTEMCTL_COMMAND=$serving_health_systemctl \
        CADDY_SERVING_HEALTH_SYSTEMCTL_CALLS=$serving_health_test_root/systemctl.calls \
        /bin/bash "$serving_health_phase_helper" >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    printf 'exit_status=%s\n' "$serving_health_status" >>"$serving_health_raw"
    write_decision minimal-dns-failure reject "$serving_health_status" \
        zero nonzero \
        "$serving_health_raw" "$serving_health_decision"

    serving_health_busctl=$serving_health_test_root/busctl
    serving_health_ip=$serving_health_test_root/ip
    serving_health_date=$serving_health_test_root/date
    serving_health_sleep=$serving_health_test_root/sleep
    cat >"$serving_health_busctl" <<'BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
counter_file=${CADDY_SERVING_HEALTH_TEST_OWNERSHIP_COUNTER:?}
sequence_file=${CADDY_SERVING_HEALTH_TEST_OWNERSHIP_SEQUENCE:?}
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
    cat >"$serving_health_ip" <<'IP'
#!/usr/bin/env bash
set -Eeuo pipefail
counter=$(<"${CADDY_SERVING_HEALTH_TEST_OWNERSHIP_COUNTER:?}")
state=$(sed -n "${counter}p" "${CADDY_SERVING_HEALTH_TEST_OWNERSHIP_SEQUENCE:?}")
printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
if [[ "$state" = Master ]]; then
    printf '2: eth0    inet 10.1.0.55/22 scope global secondary eth0\n'
    printf '2: eth0    inet 10.1.0.56/22 scope global secondary eth0\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::55/128 scope global\n'
    printf '2: eth0    inet6 fd36:5aa8:6971:1::56/128 scope global\n'
fi
IP
    cat >"$serving_health_date" <<'DATE'
#!/usr/bin/env bash
printf '2026-08-17T00:00:00.000000000Z\n'
DATE
    cat >"$serving_health_sleep" <<'SLEEP'
#!/usr/bin/env bash
[[ "$1" =~ ^[0-9]+$ ]]
SLEEP
    chmod 0700 "$serving_health_busctl" "$serving_health_ip" "$serving_health_date" \
        "$serving_health_sleep"
    printf '0\n' >"$serving_health_test_root/ownership.counter"
    printf 'Fault\nBackup\nBackup\nBackup\n' \
        >"$serving_health_test_root/ownership.sequence"
    serving_health_raw=$serving_health_test_root/raw/bounded-node-b-convergence.txt
    serving_health_decision=$serving_health_test_root/decisions/bounded-node-b-convergence.tsv
    CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$serving_health_busctl \
        CADDY_SERVING_HEALTH_IP_COMMAND=$serving_health_ip \
        CADDY_SERVING_HEALTH_DATE_COMMAND=$serving_health_date \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND=$serving_health_sleep \
        CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS=4 \
        CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES=3 \
        CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY=0 \
        CADDY_SERVING_HEALTH_TEST_OWNERSHIP_COUNTER=$serving_health_test_root/ownership.counter \
        CADDY_SERVING_HEALTH_TEST_OWNERSHIP_SEQUENCE=$serving_health_test_root/ownership.sequence \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        ownership node-b "$serving_health_promotion_payload" \
        "$serving_health_promotion_evidence" >"$serving_health_raw"
    write_decision bounded-node-b-convergence accept 0 \
        stable-backup-after-fault stable-backup-after-fault \
        "$serving_health_raw" "$serving_health_decision"

    printf '0\n' >"$serving_health_test_root/ownership.counter"
    printf 'Master\n' >"$serving_health_test_root/ownership.sequence"
    serving_health_raw=$serving_health_test_root/raw/node-b-master-rejection.txt
    serving_health_decision=$serving_health_test_root/decisions/node-b-master-rejection.tsv
    if CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST=1 \
        CADDY_SERVING_HEALTH_BUSCTL_COMMAND=$serving_health_busctl \
        CADDY_SERVING_HEALTH_IP_COMMAND=$serving_health_ip \
        CADDY_SERVING_HEALTH_DATE_COMMAND=$serving_health_date \
        CADDY_SERVING_HEALTH_SLEEP_COMMAND=$serving_health_sleep \
        CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS=1 \
        CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES=1 \
        CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY=0 \
        CADDY_SERVING_HEALTH_TEST_OWNERSHIP_COUNTER=$serving_health_test_root/ownership.counter \
        CADDY_SERVING_HEALTH_TEST_OWNERSHIP_SEQUENCE=$serving_health_test_root/ownership.sequence \
        /bin/bash "$serving_health_repo_root/Caddy/scripts/apply-serving-health-deployment.sh" \
        ownership node-b "$serving_health_promotion_payload" \
        "$serving_health_promotion_evidence" >"$serving_health_raw" 2>&1; then
        serving_health_status=0
    else
        serving_health_status=$?
    fi
    write_decision node-b-master-rejection reject "$serving_health_status" \
        backup-zero-vips master-four-vips "$serving_health_raw" "$serving_health_decision"
    chmod -R u+rwX -- "$serving_health_promotion_payload" "$serving_health_promotion_root"
    rm -rf -- "$serving_health_promotion_payload" "$serving_health_promotion_root"
    rm -rf -- "$serving_health_payload" "$serving_health_evidence"
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
readonly requested_mode=$1
if [[ "$requested_mode" = external-attribution-capture ]]; then
    mode=preflight
else
    mode=$requested_mode
fi
readonly mode
readonly node_role=$2
readonly payload_root=$3
readonly evidence_root=$4
readonly target_revision_argument=${5:-}
[[ "$mode" =~ ^(preflight|candidate-check|quarantine-check|node-a-quarantine-check|node-a-quarantine-disposition|node-a-quarantine-rollback|retained-check|retained-disposition|retained-rollback|legacy-check|legacy-remove|legacy-rollback|install|promote|publish|record-target|wait-target|promote-target|accept|rollback|ownership|journal-cursor|journal-capture|sampler-start|sampler-scenario|sampler-stop|consume|consume-target|final-residue|evidence-probe|web-unit-preflight|web-unit-install|web-unit-accept|web-unit-rollback|notification-preflight|notification-install|notification-accept|notification-rollback|exercise-preflight|exercise-service|exercise-ownership|exercise-cursor|exercise-observe|exercise-journal|exercise-final-residue)$ ]]
[[ "$node_role" =~ ^(node-[ab]|external-apprise)$ ]]
safe_root "$payload_root"
safe_root "$evidence_root"
if [[ "$requested_mode" = external-attribution-capture ]]; then
    [[ "$node_role" = external-apprise && "$payload_root" = "$evidence_root" ]]
    external_attribution_capture
    exit
fi
[[ "$node_role" =~ ^node-[ab]$ ]]
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
    sampler-scenario) set_sampler_scenario ;;
    sampler-stop) stop_sampler ;;
    consume) consume_outbound ;;
    consume-target) consume_target_outbound ;;
    final-residue) validate_final_residue ;;
    evidence-probe) produce_bounded_evidence ;;
    web-unit-preflight) web_health_unit_preflight ;;
    web-unit-install) install_web_health_unit ;;
    web-unit-accept) accept_web_health_unit ;;
    web-unit-rollback) rollback_web_health_unit ;;
    notification-preflight) notification_preflight ;;
    notification-install) install_notification_standardization ;;
    notification-accept) accept_notification_standardization ;;
    notification-rollback) rollback_notification_standardization ;;
    exercise-preflight)
        validate_inventory
        validate_current_live_release
        validate_services
        notification_preflight
        controlled_exercise_final_residue
        ;;
    exercise-service) controlled_exercise_service ;;
    exercise-ownership) controlled_exercise_ownership ;;
    exercise-cursor) controlled_exercise_cursor ;;
    exercise-observe) controlled_exercise_observe ;;
    exercise-journal) controlled_exercise_journal ;;
    exercise-final-residue) controlled_exercise_final_residue ;;
esac
