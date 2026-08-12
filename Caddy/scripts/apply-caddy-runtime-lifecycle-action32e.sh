#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2034,SC2154,SC2317

set -Eeuo pipefail
set +x
umask 077

readonly successor_prefix=action_32e_remote
readonly successor_base_relative=./Caddy/scripts/apply-caddy-runtime-lifecycle-action32.sh
readonly successor_base_sha256=0505afa283c500f965ac578b3a65535eaa483fac67c00d734ed227db5c94f53a
successor_incoming_root=/var/lib/caddy-sync/incoming
successor_current_link=/etc/caddy/current
successor_releases_root=/etc/caddy/releases
successor_quarantine_root=/var/lib/caddy-sync/quarantine
successor_caddy_binary=/usr/bin/caddy
successor_environment_file=/etc/default/caddy-ha
successor_stage=
successor_definitions=
successor_expected_candidate=
successor_persisted_base=
successor_candidate_slot=

successor_file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

successor_cleanup() {
    if [[ -n "$successor_stage" && -d "$successor_stage" ]]; then
        rm -rf -- "$successor_stage"
    fi
    if [[ -n "${stage_directory:-}" && -d "$stage_directory" ]]; then
        rm -rf -- "$stage_directory"
    fi
}

successor_production_paths() {
    [[ "$successor_incoming_root" = /var/lib/caddy-sync/incoming &&
        "$successor_current_link" = /etc/caddy/current &&
        "$successor_releases_root" = /etc/caddy/releases &&
        "$successor_quarantine_root" = /var/lib/caddy-sync/quarantine &&
        "$successor_caddy_binary" = /usr/bin/caddy &&
        "$successor_environment_file" = /etc/default/caddy-ha ]]
}

successor_prepare_base() {
    local action32e_archive=$1
    local action32e_archive_sha256=$2
    local action32e_base

    [[ -f "$action32e_archive" && ! -L "$action32e_archive" ]] || return 1
    [[ "$action32e_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$(successor_file_hash "$action32e_archive")" = "$action32e_archive_sha256" ]] || return 1
    successor_stage=$(mktemp -d /run/caddy-runtime-action32e.XXXXXX 2>/dev/null ||
        mktemp -d /tmp/caddy-runtime-action32e.XXXXXX) || return 1
    chmod 0700 "$successor_stage" || return 1
    tar -xf "$action32e_archive" -C "$successor_stage" "$successor_base_relative" || return 1
    action32e_base=$successor_stage/${successor_base_relative#./}
    [[ -f "$action32e_base" && ! -L "$action32e_base" ]] || return 1
    [[ "$(successor_file_hash "$action32e_base")" = "$successor_base_sha256" ]] || return 1
    successor_definitions=$successor_stage/action32-definitions.sh
    sed -e '/^mode=${1:-}/,$d' \
        -e 's|^readonly manifest_relative=.*|readonly manifest_relative=Caddy/manifests/caddy-runtime-lifecycle-action32e.tsv|' \
        -e 's|^readonly manifest_sha256=.*|readonly manifest_sha256=94d70aa3b5a113ccd64e1f51009c2fe1bb36102e600eb19824cc78ae0f844196|' \
        "$action32e_base" >"$successor_definitions" || return 1
    chmod 0600 "$successor_definitions" || return 1
    source "$successor_definitions"
    install_successor_overrides
}

successor_persist_base() {
    local action32e_role=$1
    local action32e_base=$successor_stage/${successor_base_relative#./}

    successor_persisted_base=/tmp/caddy-action32e-base-$action32e_role.sh
    install -o root -g root -m 0600 "$action32e_base" "$successor_persisted_base" || return 1
    [[ "$(successor_file_hash "$successor_persisted_base")" = "$successor_base_sha256" ]]
}

successor_source_persisted_base() {
    local action32e_role=$1

    successor_persisted_base=/tmp/caddy-action32e-base-$action32e_role.sh
    [[ -f "$successor_persisted_base" && ! -L "$successor_persisted_base" ]] || return 1
    [[ "$(successor_file_hash "$successor_persisted_base")" = "$successor_base_sha256" ]] || return 1
    successor_stage=$(mktemp -d /run/caddy-runtime-action32e.XXXXXX 2>/dev/null ||
        mktemp -d /tmp/caddy-runtime-action32e.XXXXXX) || return 1
    successor_definitions=$successor_stage/action32-definitions.sh
    sed -e '/^mode=${1:-}/,$d' \
        -e 's|^readonly manifest_relative=.*|readonly manifest_relative=Caddy/manifests/caddy-runtime-lifecycle-action32e.tsv|' \
        -e 's|^readonly manifest_sha256=.*|readonly manifest_sha256=94d70aa3b5a113ccd64e1f51009c2fe1bb36102e600eb19824cc78ae0f844196|' \
        "$successor_persisted_base" >"$successor_definitions" || return 1
    chmod 0600 "$successor_definitions" || return 1
    source "$successor_definitions"
    install_successor_overrides
}

install_successor_overrides() {
    eval "$(declare -f install_candidates | sed \
        '1s/^install_candidates/successor_base_install_candidates/')"

    capture_semantic_state() {
        run_captured current_release readlink -f /etc/caddy/current || return 1
        before_release=$(cat "$capture_directory/current_release.stdout") || return 1
        [[ "$before_release" == /etc/caddy/releases/* && -d "$before_release" && ! -L "$before_release" ]] || return 1
        run_captured outbound_inventory safe_direct_inventory /var/lib/caddy-sync/outbound || return 1
        run_captured incoming_inventory safe_direct_inventory /var/lib/caddy-sync/incoming || return 1
        run_captured quarantine_inventory safe_direct_inventory /var/lib/caddy-sync/quarantine || return 1
        before_outbound=$(file_hash "$capture_directory/outbound_inventory.stdout") || return 1
        before_incoming=$(file_hash "$capture_directory/incoming_inventory.stdout") || return 1
        before_quarantine=$(file_hash "$capture_directory/quarantine_inventory.stdout") || return 1
        if [[ "$role" = node-b ]]; then
            check node_b_outbound_empty test ! -s "$capture_directory/outbound_inventory.stdout" || return 1
        else
            check node_a_outbound_present test -s "$capture_directory/outbound_inventory.stdout" || return 1
        fi
    }

    install_candidates() {
        run_captured frozen_candidate_semantics inspect_finalized_candidate || return 1
        if [[ "$role" = node-b ]]; then
            check node_b_deterministic_candidate_disposition \
                test -n "$successor_expected_candidate" || return 1
        else
            check node_a_no_finalized_candidate \
                test -z "$successor_expected_candidate" || return 1
        fi
        successor_base_install_candidates
    }

    no_finalized_candidate() {
        local action32e_override_attempt

        for action32e_override_attempt in $(seq 0 30); do
            if ! incoming_has_finalized_candidate; then
                printf 'finalized_candidate_drain_attempt=%s\n' "$action32e_override_attempt"
                printf 'finalized_candidate_drained_by_corrected_reconciler=true\n'
                return 0
            fi
            sleep 1
        done
        return 1
    }
}

manifest_paths_safe() {
    local action32e_manifest=$1

    awk '
        length($0) == 0 { bad = 1; next }
        {
            hash = substr($0, 1, 64)
            separator = substr($0, 65, 2)
            path = substr($0, 67)
            if (length(hash) != 64 ||
                hash !~ /^[0-9a-f]+$/ ||
                separator != "  " ||
                path !~ /^[.][/][^[:cntrl:]]+$/ ||
                path ~ /(^|[/])[.][.]([/]|$)/ ||
                path ~ /[/][/]/ ||
                path ~ /[/][.]([/]|$)/ ||
                path ~ /[/]$/) {
                bad = 1
            }
        }
        END { exit bad ? 1 : 0 }
    ' "$action32e_manifest"
}

manifest_file_set_matches() {
    local action32e_candidate=$1
    local action32e_expected
    local action32e_observed
    local action32e_status=0

    action32e_expected=$(mktemp /tmp/caddy-action32e-expected.XXXXXX) || return 1
    action32e_observed=$(mktemp /tmp/caddy-action32e-observed.XXXXXX) || {
        rm -f -- "$action32e_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action32e_candidate/manifest.sha256" |
        LC_ALL=C sort -u >"$action32e_expected"
    (
        cd "$action32e_candidate"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print |
            LC_ALL=C sort
    ) >"$action32e_observed"
    cmp -s "$action32e_expected" "$action32e_observed" || action32e_status=$?
    rm -f -- "$action32e_expected" "$action32e_observed"
    return "$action32e_status"
}

release_payload_matches() {
    local action32e_left=$1
    local action32e_right=$2

    candidate_check payload_candidate_directory test -d "$action32e_left" || return 1
    candidate_check payload_candidate_not_symlink test ! -L "$action32e_left" || return 1
    candidate_check payload_current_directory test -d "$action32e_right" || return 1
    candidate_check payload_current_not_symlink test ! -L "$action32e_right" || return 1
    candidate_check payload_candidate_release_manifest_regular \
        test -f "$action32e_left/release-manifest.json" || return 1
    candidate_check payload_candidate_release_manifest_not_symlink \
        test ! -L "$action32e_left/release-manifest.json" || return 1
    candidate_check payload_current_release_manifest_regular \
        test -f "$action32e_right/release-manifest.json" || return 1
    candidate_check payload_current_release_manifest_not_symlink \
        test ! -L "$action32e_right/release-manifest.json" || return 1
    candidate_check payload_candidate_hash_manifest_regular \
        test -f "$action32e_left/manifest.sha256" || return 1
    candidate_check payload_candidate_hash_manifest_not_symlink \
        test ! -L "$action32e_left/manifest.sha256" || return 1
    candidate_check payload_current_hash_manifest_regular \
        test -f "$action32e_right/manifest.sha256" || return 1
    candidate_check payload_current_hash_manifest_not_symlink \
        test ! -L "$action32e_right/manifest.sha256" || return 1
    candidate_check payload_candidate_request_marker_regular \
        test -f "$action32e_left/.finalize-request" || return 1
    candidate_check payload_candidate_request_marker_not_symlink \
        test ! -L "$action32e_left/.finalize-request" || return 1
    candidate_check payload_current_request_marker_regular \
        test -f "$action32e_right/.finalize-request" || return 1
    candidate_check payload_current_request_marker_not_symlink \
        test ! -L "$action32e_right/.finalize-request" || return 1
    candidate_check payload_candidate_completion_marker_regular \
        test -f "$action32e_left/.complete" || return 1
    candidate_check payload_candidate_completion_marker_not_symlink \
        test ! -L "$action32e_left/.complete" || return 1
    candidate_check payload_current_completion_marker_regular \
        test -f "$action32e_right/.complete" || return 1
    candidate_check payload_current_completion_marker_not_symlink \
        test ! -L "$action32e_right/.complete" || return 1
    candidate_check payload_candidate_pending_absent \
        test ! -e "$action32e_left/.complete.pending" || return 1
    candidate_check payload_current_pending_absent \
        test ! -e "$action32e_right/.complete.pending" || return 1
    candidate_check payload_candidate_types_safe test -z \
        "$(find "$action32e_left" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    candidate_check payload_current_types_safe test -z \
        "$(find "$action32e_right" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    candidate_check payload_candidate_hardlinks_absent test -z \
        "$(find "$action32e_left" -type f -links +1 -print -quit)" || return 1
    candidate_check payload_current_hardlinks_absent test -z \
        "$(find "$action32e_right" -type f -links +1 -print -quit)" || return 1
    candidate_check payload_candidate_manifest_paths_safe \
        manifest_paths_safe "$action32e_left/manifest.sha256" || return 1
    candidate_check payload_current_manifest_paths_safe \
        manifest_paths_safe "$action32e_right/manifest.sha256" || return 1
    candidate_check payload_candidate_file_set_exact \
        manifest_file_set_matches "$action32e_left" || return 1
    candidate_check payload_current_file_set_exact \
        manifest_file_set_matches "$action32e_right" || return 1
    candidate_check payload_candidate_hashes_valid bash -c \
        'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action32e_left" || return 1
    candidate_check payload_current_hashes_valid bash -c \
        'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action32e_right" || return 1
    candidate_check payload_release_manifests_equal cmp -s \
        "$action32e_left/release-manifest.json" \
        "$action32e_right/release-manifest.json" || return 1
    candidate_check payload_hash_manifests_equal cmp -s \
        "$action32e_left/manifest.sha256" "$action32e_right/manifest.sha256"
}

list_finalized_candidates() {
    [[ -d "$successor_incoming_root" && ! -L "$successor_incoming_root" ]] || return 1
    find "$successor_incoming_root" \
        -mindepth 2 -maxdepth 2 -type d \
        ! -path '*/.*' \
        -exec test -f '{}/.finalize-request' ';' \
        -exec test -f '{}/.complete' ';' \
        ! -exec test -e '{}/.complete.pending' ';' \
        -print 2>/dev/null | LC_ALL=C sort
}

candidate_check() {
    local action32e_candidate_label=$1

    shift
    if [[ -n "$successor_candidate_slot" ]]; then
        check "candidate_${successor_candidate_slot}_$action32e_candidate_label" "$@"
    else
        check "candidate_$action32e_candidate_label" "$@"
    fi
}

environment_value() {
    local action32e_environment_key=$1

    awk -F= -v wanted="$action32e_environment_key" '
        $1 == wanted { value = substr($0, length(wanted) + 2); count++ }
        END { if (count != 1 || value == "") exit 1; print value }
    ' "$successor_environment_file"
}

environment_contract_exact() {
    awk -F= '
        NF != 2 { exit 1 }
        $1 == "NODE_FQDN" && $2 ~ /^[A-Za-z0-9.-]+$/ { fqdn++ ; next }
        $1 == "NODE_IPV4" && $2 ~ /^[0-9.]+$/ { ipv4++ ; next }
        $1 == "NODE_IPV6" && $2 ~ /^[0-9A-Fa-f:]+$/ { ipv6++ ; next }
        { exit 1 }
        END { exit !(NR == 3 && fqdn == 1 && ipv4 == 1 && ipv6 == 1) }
    ' "$successor_environment_file"
}

candidate_runtime_ready() {
    local action32e_candidate=$1
    local action32e_node_fqdn
    local action32e_node_ipv4
    local action32e_node_ipv6
    local action32e_nested_controls
    local action32e_bad_directories
    local action32e_bad_files

    candidate_check request_marker_regular test -f "$action32e_candidate/.finalize-request" || return 1
    candidate_check request_marker_not_symlink test ! -L "$action32e_candidate/.finalize-request" || return 1
    candidate_check request_marker_empty test ! -s "$action32e_candidate/.finalize-request" || return 1
    candidate_check completion_marker_regular test -f "$action32e_candidate/.complete" || return 1
    candidate_check completion_marker_not_symlink test ! -L "$action32e_candidate/.complete" || return 1
    candidate_check completion_marker_empty test ! -s "$action32e_candidate/.complete" || return 1
    action32e_nested_controls=$(find "$action32e_candidate" -mindepth 2 \
        \( -name .finalize-request -o -name .complete \
        -o -name manifest.sha256 \) -print -quit) || return 1
    printf 'observed_candidate_nested_control=%s\n' "${action32e_nested_controls:-none}"
    candidate_check nested_control_files_absent test -z "$action32e_nested_controls" || return 1
    action32e_bad_directories=$(find "$action32e_candidate" -type d ! -perm 0550 -print -quit) || return 1
    printf 'observed_candidate_bad_directory_mode_path=%s\n' "${action32e_bad_directories:-none}"
    candidate_check directories_locked test -z "$action32e_bad_directories" || return 1
    action32e_bad_files=$(find "$action32e_candidate" -type f ! -perm 0440 -print -quit) || return 1
    printf 'observed_candidate_bad_file_mode_path=%s\n' "${action32e_bad_files:-none}"
    candidate_check files_locked test -z "$action32e_bad_files" || return 1
    candidate_check environment_regular test -f "$successor_environment_file" || return 1
    candidate_check environment_not_symlink test ! -L "$successor_environment_file" || return 1
    printf 'observed_environment_sha256=%s\n' "$(successor_file_hash "$successor_environment_file")"
    candidate_check caddy_binary_regular test -f "$successor_caddy_binary" || return 1
    candidate_check caddy_binary_not_symlink test ! -L "$successor_caddy_binary" || return 1
    candidate_check caddy_binary_executable test -x "$successor_caddy_binary" || return 1
    candidate_check environment_contract_exact environment_contract_exact || return 1
    action32e_node_fqdn=$(environment_value NODE_FQDN) || {
        candidate_check environment_node_fqdn_read false || true
        return 1
    }
    candidate_check environment_node_fqdn_read true || return 1
    action32e_node_ipv4=$(environment_value NODE_IPV4) || {
        candidate_check environment_node_ipv4_read false || true
        return 1
    }
    candidate_check environment_node_ipv4_read true || return 1
    action32e_node_ipv6=$(environment_value NODE_IPV6) || {
        candidate_check environment_node_ipv6_read false || true
        return 1
    }
    candidate_check environment_node_ipv6_read true || return 1
    printf 'observed_environment_node_fqdn=%s\n' "$action32e_node_fqdn"
    printf 'observed_environment_node_ipv4=%s\n' "$action32e_node_ipv4"
    printf 'observed_environment_node_ipv6=%s\n' "$action32e_node_ipv6"
    if run_captured "candidate_${successor_candidate_slot}_caddy_validation" env \
        CADDY_CONFIG_ROOT="$action32e_candidate" \
        NODE_FQDN="$action32e_node_fqdn" \
        NODE_IPV4="$action32e_node_ipv4" \
        NODE_IPV6="$action32e_node_ipv6" \
        "$successor_caddy_binary" validate \
        --config "$action32e_candidate/Caddyfile" --adapter caddyfile; then
        candidate_check caddy_validation_success true || return 1
    else
        candidate_check caddy_validation_success false || true
        return 1
    fi
}

incoming_shape_safe() {
    local action32e_entry_name
    local action32e_entry_path
    local action32e_entry_type
    local action32e_entry_index=0
    local action32e_source_role
    local action32e_expected_top_inventory
    local action32e_top_inventory
    local action32e_source_inventory

    action32e_top_inventory=$(successor_safe_direct_inventory "$successor_incoming_root") || {
        candidate_check incoming_top_inventory_query false || true
        return 1
    }
    printf 'observed_candidate_incoming_top_inventory_sha256=%s\n' \
        "$(printf '%s' "$action32e_top_inventory" | sha256sum | awk '{ print $1 }')"
    candidate_check incoming_top_inventory_query true || return 1
    if [[ "$role" = node-b ]]; then
        action32e_source_role=node-a
    else
        action32e_source_role=node-b
    fi
    action32e_expected_top_inventory=$(printf '.reconcile-trigger\tf\n%s\td' \
        "$action32e_source_role")
    candidate_check incoming_top_inventory_exact test \
        "$action32e_top_inventory" = "$action32e_expected_top_inventory" || return 1
    action32e_source_inventory=$(successor_safe_direct_inventory \
        "$successor_incoming_root/$action32e_source_role") || {
        candidate_check incoming_source_inventory_query false || true
        return 1
    }
    printf 'observed_candidate_source_inventory=%s\n' "$action32e_source_inventory"
    candidate_check incoming_source_inventory_query true || return 1
    while IFS=$'\t' read -r action32e_entry_name action32e_entry_type; do
        [[ -n "$action32e_entry_name" ]] || continue
        action32e_entry_index=$((action32e_entry_index + 1))
        action32e_entry_path=$successor_incoming_root/$action32e_source_role/$action32e_entry_name
        printf 'observed_source_entry_%s_name=%s\n' \
            "$action32e_entry_index" "$action32e_entry_name"
        printf 'observed_source_entry_%s_type=%s\n' \
            "$action32e_entry_index" "$action32e_entry_type"
        candidate_check "source_entry_${action32e_entry_index}_name_safe" \
            bash -c '[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]' \
            _ "$action32e_entry_name" || return 1
        candidate_check "source_entry_${action32e_entry_index}_directory" \
            test "$action32e_entry_type" = d || return 1
        candidate_check "source_entry_${action32e_entry_index}_not_symlink" \
            test ! -L "$action32e_entry_path" || return 1
        if [[ -f "$action32e_entry_path/.finalize-request" &&
            -f "$action32e_entry_path/.complete" &&
            ! -e "$action32e_entry_path/.complete.pending" ]]; then
            printf 'observed_source_entry_%s_class=finalized_candidate\n' \
                "$action32e_entry_index"
        else
            printf 'observed_source_entry_%s_class=retained_non_finalized\n' \
                "$action32e_entry_index"
        fi
    done <<<"$action32e_source_inventory"
    printf 'observed_source_entry_count=%s\n' "$action32e_entry_index"
}

successor_safe_direct_inventory() {
    local action32e_root=$1

    [[ -d "$action32e_root" && ! -L "$action32e_root" ]] || return 1
    find "$action32e_root" -mindepth 1 -maxdepth 1 -printf '%f\t%y\n' |
        LC_ALL=C sort
}

find_unique_quarantine_payload_match() {
    local action32e_candidate=$1
    local action32e_match=
    local action32e_match_count=0
    local action32e_quarantine_candidate

    while IFS= read -r -d '' action32e_quarantine_candidate; do
        [[ -d "$action32e_quarantine_candidate" &&
            ! -L "$action32e_quarantine_candidate" ]] || continue
        if release_payload_matches "$action32e_candidate" \
            "$action32e_quarantine_candidate" >/dev/null 2>&1; then
            action32e_match=$action32e_quarantine_candidate
            action32e_match_count=$((action32e_match_count + 1))
        fi
    done < <(find "$successor_quarantine_root" -mindepth 1 -maxdepth 1 \
        -type d -print0)
    [[ "$action32e_match_count" -eq 1 ]] || return 1
    printf '%s\n' "$action32e_match"
}

inspect_finalized_candidate() {
    local action32e_current
    local action32e_active_revision
    local action32e_revision
    local action32e_parent
    local action32e_source
    local action32e_candidate
    local action32e_disposition
    local action32e_quarantine
    local action32e_candidate_list
    local action32e_active_replay_count=0
    local action32e_quarantine_replay_count=0
    local action32e_index=0
    local -a action32e_candidates=()

    action32e_candidate_list=$(mktemp /tmp/caddy-action32e-candidates.XXXXXX) || return 1
    if list_finalized_candidates >"$action32e_candidate_list"; then
        candidate_check finalized_query_success true || return 1
    else
        candidate_check finalized_query_success false || true
        rm -f -- "$action32e_candidate_list"
        return 1
    fi
    mapfile -t action32e_candidates <"$action32e_candidate_list"
    rm -f -- "$action32e_candidate_list"
    printf 'observed_finalized_candidate_count=%s\n' "${#action32e_candidates[@]}"
    successor_candidate_slot=
    incoming_shape_safe || return 1
    if [[ "$role" = node-a ]]; then
        candidate_check node_a_finalized_count_zero test "${#action32e_candidates[@]}" -eq 0 || return 1
        printf 'finalized_candidate_count=0\n'
        successor_expected_candidate=
        return 0
    fi
    candidate_check node_b_finalized_count_nonzero test "${#action32e_candidates[@]}" -gt 0 || return 1
    candidate_check node_b_finalized_count_bounded test "${#action32e_candidates[@]}" -le 32 || return 1
    action32e_current=$(readlink -f "$successor_current_link") || {
        candidate_check current_release_resolved false || true
        return 1
    }
    printf 'observed_candidate_current_release=%s\n' "$action32e_current"
    candidate_check current_release_resolved true || return 1
    candidate_check current_release_under_root test \
        "${action32e_current%/*}" = "$successor_releases_root" || return 1
    candidate_check current_revision_shape bash -c \
        '[[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]' _ "${action32e_current##*/}" || return 1
    action32e_active_revision=${action32e_current##*/}
    for action32e_candidate in "${action32e_candidates[@]}"; do
        action32e_index=$((action32e_index + 1))
        successor_candidate_slot=$action32e_index
        printf 'observed_candidate_%s_path=%s\n' "$action32e_index" "$action32e_candidate"
        candidate_check path_under_node_a test \
            "${action32e_candidate%/*}" = "$successor_incoming_root/node-a" || return 1
        candidate_check path_revision_shape bash -c \
            '[[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]' _ "${action32e_candidate##*/}" || return 1
        action32e_revision=$(jq -er '.revision | strings' "$action32e_candidate/release-manifest.json") || {
            candidate_check manifest_revision_read false || true
            return 1
        }
        candidate_check manifest_revision_read true || return 1
        action32e_parent=$(jq -er '.parent_revision // "" | strings' "$action32e_candidate/release-manifest.json") || {
            candidate_check manifest_parent_read false || true
            return 1
        }
        candidate_check manifest_parent_read true || return 1
        action32e_source=$(jq -er '.source_node | strings' "$action32e_candidate/release-manifest.json") || {
            candidate_check manifest_source_read false || true
            return 1
        }
        candidate_check manifest_source_read true || return 1
        printf 'observed_candidate_%s_revision=%s\n' "$action32e_index" "$action32e_revision"
        printf 'observed_candidate_%s_parent=%s\n' "$action32e_index" "${action32e_parent:-none}"
        printf 'observed_candidate_%s_source=%s\n' "$action32e_index" "$action32e_source"
        printf 'observed_candidate_%s_release_manifest_sha256=%s\n' "$action32e_index" \
            "$(successor_file_hash "$action32e_candidate/release-manifest.json")"
        printf 'observed_candidate_%s_payload_manifest_sha256=%s\n' "$action32e_index" \
            "$(successor_file_hash "$action32e_candidate/manifest.sha256")"
        candidate_check manifest_revision_shape bash -c \
            '[[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]' _ "$action32e_revision" || return 1
        candidate_check manifest_parent_shape bash -c \
            '[[ -z "$1" || "$1" =~ ^[A-Za-z0-9._-]+$ ]]' _ "$action32e_parent" || return 1
        candidate_check manifest_source_node_a test "$action32e_source" = node-a || return 1
        candidate_check path_matches_revision test \
            "${action32e_candidate##*/}" = "$action32e_revision" || return 1
        candidate_runtime_ready "$action32e_candidate" || return 1

        action32e_disposition=reject
        if [[ "$action32e_revision" = "$action32e_active_revision" ]]; then
            release_payload_matches "$action32e_candidate" "$action32e_current" || return 1
            candidate_check payload_exact_active true || return 1
            action32e_disposition=consume_exact_active_replay
            action32e_active_replay_count=$((action32e_active_replay_count + 1))
        elif [[ "$action32e_parent" != "$action32e_active_revision" ]]; then
            action32e_quarantine=$(find_unique_quarantine_payload_match \
                "$action32e_candidate") || {
                candidate_check unique_quarantine_payload_match false || true
                return 1
            }
            candidate_check unique_quarantine_payload_match true || return 1
            printf 'observed_candidate_%s_quarantine_path=%s\n' \
                "$action32e_index" "$action32e_quarantine"
            candidate_check quarantine_directory test -d "$action32e_quarantine" || return 1
            candidate_check quarantine_not_symlink test ! -L "$action32e_quarantine" || return 1
            release_payload_matches "$action32e_candidate" "$action32e_quarantine" || return 1
            candidate_check payload_exact_quarantine true || return 1
            action32e_disposition=discard_exact_quarantine_replay
            action32e_quarantine_replay_count=$((action32e_quarantine_replay_count + 1))
        fi
        printf 'observed_candidate_%s_disposition=%s\n' \
            "$action32e_index" "$action32e_disposition"
        candidate_check disposition_allowed test "$action32e_disposition" != reject || return 1
    done
    successor_candidate_slot=
    candidate_check active_replay_count_one test "$action32e_active_replay_count" -eq 1 || return 1
    candidate_check all_nonactive_candidates_quarantine_replays test \
        "$action32e_quarantine_replay_count" -eq "$((${#action32e_candidates[@]} - 1))" || return 1
    successor_expected_candidate=semantic-deterministic-drain
    printf 'finalized_candidate_count=%s\n' "${#action32e_candidates[@]}"
    printf 'finalized_candidate_active_replay_count=1\n'
    printf 'finalized_candidate_quarantine_replay_count=%s\n' \
        "$action32e_quarantine_replay_count"
    printf 'finalized_candidate_disposition=consume-active-then-discard-exact-quarantine-replays\n'
}

capture_semantic_state() {
    run_captured current_release readlink -f /etc/caddy/current || return 1
    before_release=$(cat "$capture_directory/current_release.stdout") || return 1
    [[ "$before_release" == /etc/caddy/releases/* && -d "$before_release" && ! -L "$before_release" ]] || return 1
    run_captured outbound_inventory safe_direct_inventory /var/lib/caddy-sync/outbound || return 1
    run_captured incoming_inventory safe_direct_inventory /var/lib/caddy-sync/incoming || return 1
    run_captured quarantine_inventory safe_direct_inventory /var/lib/caddy-sync/quarantine || return 1
    before_outbound=$(file_hash "$capture_directory/outbound_inventory.stdout") || return 1
    before_incoming=$(file_hash "$capture_directory/incoming_inventory.stdout") || return 1
    before_quarantine=$(file_hash "$capture_directory/quarantine_inventory.stdout") || return 1
    if [[ "$role" = node-b ]]; then
        check node_b_outbound_empty test ! -s "$capture_directory/outbound_inventory.stdout" || return 1
    else
        check node_a_outbound_present test -s "$capture_directory/outbound_inventory.stdout" || return 1
    fi
}

no_finalized_candidate() {
    local action32e_attempt

    for action32e_attempt in $(seq 0 30); do
        if ! incoming_has_finalized_candidate; then
            printf 'finalized_candidate_drain_attempt=%s\n' "$action32e_attempt"
            printf 'finalized_candidate_drained_by_corrected_reconciler=true\n'
            return 0
        fi
        sleep 1
    done
    return 1
}

finalized_candidate_absent() {
    local -a action32e_candidates=()

    [[ -d "$successor_incoming_root" && ! -L "$successor_incoming_root" ]] || return 1
    mapfile -t action32e_candidates < <(list_finalized_candidates)
    ((${#action32e_candidates[@]} == 0))
}

successor_configure() {
    local action32e_role=$1

    configure_role "$action32e_role" || return 1
    backup_directory=$backup_root/action32e-$role-runtime-lifecycle
    capture_directory=/tmp/caddy-action32e/$node_token
}

successor_validate() {
    local action32e_archive=$1
    local action32e_archive_sha256=$2

    successor_prepare_base "$action32e_archive" "$action32e_archive_sha256" || return 1
    successor_configure "$3" || return 1
    archive_path=$action32e_archive
    capture_directory=$(mktemp -d /tmp/caddy-action32e-validation.XXXXXX) || return 1
    validate_payload "$archive_path" "$action32e_archive_sha256" || return 1
    printf '%s_%s_validate_payload_complete=true\n' "$successor_prefix" "$node_token"
}

successor_apply() {
    local action32e_archive=$1
    local action32e_archive_sha256=$2
    local action32e_role=$3

    successor_prepare_base "$action32e_archive" "$action32e_archive_sha256" || return 1
    successor_configure "$action32e_role" || return 1
    successor_persist_base "$action32e_role" || return 1
    archive_path=$action32e_archive
    trap successor_rollback_on_error EXIT INT TERM
    apply "$action32e_archive_sha256"
    trap - EXIT INT TERM
    successor_cleanup
    printf '%s_%s_apply_complete=true\n' "$successor_prefix" "$node_token"
}

successor_rollback_on_error() {
    local action32e_status=$?

    trap - EXIT INT TERM
    successor_cleanup
    [[ -z "$stage_directory" || ! -d "$stage_directory" ]] || rm -rf -- "$stage_directory"
    if [[ -n "$archive_path" && "$archive_path" == /tmp/caddy-action32e-payload-*.tar ]]; then
        rm -f -- "$archive_path"
    fi
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action32e_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$successor_prefix" "$node_token" >&2
    if restore_backup; then
        printf '%s_%s_rollback_complete=true\n' "$successor_prefix" "$node_token" >&2
        exit "$action32e_status"
    fi
    printf '%s_%s_manual_intervention_required=true\n' "$successor_prefix" "$node_token" >&2
    exit 125
}

successor_rollback() {
    local action32e_role=$1

    successor_source_persisted_base "$action32e_role" || return 1
    successor_configure "$action32e_role" || return 1
    rollback || return 1
    rm -f -- "$successor_persisted_base"
    printf '%s_%s_rollback_complete=true\n' "$successor_prefix" "$node_token"
}

successor_verify() {
    local action32e_role=$1

    successor_source_persisted_base "$action32e_role" || return 1
    successor_configure "$action32e_role" || return 1
    verify_current || return 1
    check no_finalized_candidate_current finalized_candidate_absent || return 1
    rm -f -- "$successor_persisted_base"
    printf '%s_%s_verify_current_complete=true\n' "$successor_prefix" "$node_token"
}

mode=${1:-}
case "$mode" in
    --validate-payload)
        [[ $# -eq 4 ]] || exit 64
        successor_production_paths || exit 64
        trap successor_cleanup EXIT INT TERM
        successor_validate "$3" "$4" "$2"
        ;;
    --apply)
        [[ $# -eq 4 && $3 == /tmp/caddy-action32e-payload-*.tar ]] || exit 64
        successor_production_paths || exit 64
        trap successor_cleanup EXIT INT TERM
        successor_apply "$3" "$4" "$2"
        ;;
    --rollback)
        [[ $# -eq 2 ]] || exit 64
        successor_production_paths || exit 64
        trap successor_cleanup EXIT INT TERM
        successor_rollback "$2"
        ;;
    --verify-current)
        [[ $# -eq 2 ]] || exit 64
        successor_production_paths || exit 64
        trap successor_cleanup EXIT INT TERM
        successor_verify "$2"
        ;;
    *) exit 64 ;;
esac
