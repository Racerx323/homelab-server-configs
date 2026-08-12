#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034,SC2154,SC2317

set -Eeuo pipefail
set +x
umask 077

readonly successor_prefix=action_32a_remote
readonly successor_base_relative=./Caddy/scripts/apply-caddy-runtime-lifecycle-action32.sh
readonly successor_base_sha256=0505afa283c500f965ac578b3a65535eaa483fac67c00d734ed227db5c94f53a
successor_incoming_root=/var/lib/caddy-sync/incoming
successor_current_link=/etc/caddy/current
successor_releases_root=/etc/caddy/releases
successor_caddy_binary=/usr/bin/caddy
successor_stage=
successor_definitions=
successor_expected_candidate=
successor_persisted_base=

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
        "$successor_caddy_binary" = /usr/bin/caddy ]]
}

successor_prepare_base() {
    local action32a_archive=$1
    local action32a_archive_sha256=$2
    local action32a_base

    [[ -f "$action32a_archive" && ! -L "$action32a_archive" ]] || return 1
    [[ "$action32a_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$(successor_file_hash "$action32a_archive")" = "$action32a_archive_sha256" ]] || return 1
    successor_stage=$(mktemp -d /run/caddy-runtime-action32a.XXXXXX 2>/dev/null ||
        mktemp -d /tmp/caddy-runtime-action32a.XXXXXX) || return 1
    chmod 0700 "$successor_stage" || return 1
    tar -xf "$action32a_archive" -C "$successor_stage" "$successor_base_relative" || return 1
    action32a_base=$successor_stage/${successor_base_relative#./}
    [[ -f "$action32a_base" && ! -L "$action32a_base" ]] || return 1
    [[ "$(successor_file_hash "$action32a_base")" = "$successor_base_sha256" ]] || return 1
    successor_definitions=$successor_stage/action32-definitions.sh
    sed '/^mode=${1:-}/,$d' "$action32a_base" >"$successor_definitions" || return 1
    chmod 0600 "$successor_definitions" || return 1
    source "$successor_definitions"
}

successor_persist_base() {
    local action32a_role=$1
    local action32a_base=$successor_stage/${successor_base_relative#./}

    successor_persisted_base=/tmp/caddy-action32a-base-$action32a_role.sh
    install -o root -g root -m 0600 "$action32a_base" "$successor_persisted_base" || return 1
    [[ "$(successor_file_hash "$successor_persisted_base")" = "$successor_base_sha256" ]]
}

successor_source_persisted_base() {
    local action32a_role=$1

    successor_persisted_base=/tmp/caddy-action32a-base-$action32a_role.sh
    [[ -f "$successor_persisted_base" && ! -L "$successor_persisted_base" ]] || return 1
    [[ "$(successor_file_hash "$successor_persisted_base")" = "$successor_base_sha256" ]] || return 1
    successor_stage=$(mktemp -d /run/caddy-runtime-action32a.XXXXXX 2>/dev/null ||
        mktemp -d /tmp/caddy-runtime-action32a.XXXXXX) || return 1
    successor_definitions=$successor_stage/action32-definitions.sh
    sed '/^mode=${1:-}/,$d' "$successor_persisted_base" >"$successor_definitions" || return 1
    chmod 0600 "$successor_definitions" || return 1
    source "$successor_definitions"
}

manifest_paths_safe() {
    local action32a_manifest=$1

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
    ' "$action32a_manifest"
}

manifest_file_set_matches() {
    local action32a_candidate=$1
    local action32a_expected
    local action32a_observed
    local action32a_status=0

    action32a_expected=$(mktemp /tmp/caddy-action32a-expected.XXXXXX) || return 1
    action32a_observed=$(mktemp /tmp/caddy-action32a-observed.XXXXXX) || {
        rm -f -- "$action32a_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action32a_candidate/manifest.sha256" |
        LC_ALL=C sort -u >"$action32a_expected"
    (
        cd "$action32a_candidate"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print |
            LC_ALL=C sort
    ) >"$action32a_observed"
    cmp -s "$action32a_expected" "$action32a_observed" || action32a_status=$?
    rm -f -- "$action32a_expected" "$action32a_observed"
    return "$action32a_status"
}

release_payload_matches() {
    local action32a_left=$1
    local action32a_right=$2

    [[ -d "$action32a_left" && ! -L "$action32a_left" ]] || return 1
    [[ -d "$action32a_right" && ! -L "$action32a_right" ]] || return 1
    [[ -f "$action32a_left/release-manifest.json" && ! -L "$action32a_left/release-manifest.json" ]] || return 1
    [[ -f "$action32a_right/release-manifest.json" && ! -L "$action32a_right/release-manifest.json" ]] || return 1
    [[ -f "$action32a_left/manifest.sha256" && ! -L "$action32a_left/manifest.sha256" ]] || return 1
    [[ -f "$action32a_right/manifest.sha256" && ! -L "$action32a_right/manifest.sha256" ]] || return 1
    [[ -f "$action32a_left/.finalize-request" && ! -L "$action32a_left/.finalize-request" ]] || return 1
    [[ -f "$action32a_right/.finalize-request" && ! -L "$action32a_right/.finalize-request" ]] || return 1
    [[ -f "$action32a_left/.complete" && ! -L "$action32a_left/.complete" ]] || return 1
    [[ -f "$action32a_right/.complete" && ! -L "$action32a_right/.complete" ]] || return 1
    [[ ! -e "$action32a_left/.complete.pending" && ! -e "$action32a_right/.complete.pending" ]] || return 1
    test -z "$(find "$action32a_left" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    test -z "$(find "$action32a_right" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    test -z "$(find "$action32a_left" -type f -links +1 -print -quit)" || return 1
    test -z "$(find "$action32a_right" -type f -links +1 -print -quit)" || return 1
    manifest_paths_safe "$action32a_left/manifest.sha256" || return 1
    manifest_paths_safe "$action32a_right/manifest.sha256" || return 1
    manifest_file_set_matches "$action32a_left" || return 1
    manifest_file_set_matches "$action32a_right" || return 1
    (cd "$action32a_left" && sha256sum --strict --check manifest.sha256 >/dev/null) || return 1
    (cd "$action32a_right" && sha256sum --strict --check manifest.sha256 >/dev/null) || return 1
    cmp -s "$action32a_left/release-manifest.json" "$action32a_right/release-manifest.json" || return 1
    cmp -s "$action32a_left/manifest.sha256" "$action32a_right/manifest.sha256" || return 1
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

candidate_runtime_ready() {
    local action32a_candidate=$1

    [[ -f "$action32a_candidate/.finalize-request" &&
        ! -L "$action32a_candidate/.finalize-request" &&
        ! -s "$action32a_candidate/.finalize-request" ]] || return 1
    [[ -f "$action32a_candidate/.complete" &&
        ! -L "$action32a_candidate/.complete" &&
        ! -s "$action32a_candidate/.complete" ]] || return 1
    test -z "$(find "$action32a_candidate" -mindepth 2 \
        \( -name .finalize-request -o -name .complete \
        -o -name manifest.sha256 \) -print -quit)" || return 1
    test -z "$(find "$action32a_candidate" -type d ! -perm 0550 -print -quit)" || return 1
    test -z "$(find "$action32a_candidate" -type f ! -perm 0440 -print -quit)" || return 1
    env CADDY_CONFIG_ROOT="$action32a_candidate" \
        "$successor_caddy_binary" validate --config "$action32a_candidate/Caddyfile" \
        --adapter caddyfile >/dev/null || return 1
}

node_b_incoming_shape_exact() {
    local action32a_candidate=$1
    local action32a_top_inventory
    local action32a_source_inventory

    action32a_top_inventory=$(successor_safe_direct_inventory "$successor_incoming_root") || return 1
    [[ "$action32a_top_inventory" = $'.reconcile-trigger\tf\nnode-a\td' ]] || return 1
    action32a_source_inventory=$(successor_safe_direct_inventory "$successor_incoming_root/node-a") || return 1
    [[ "$action32a_source_inventory" = "${action32a_candidate##*/}"$'\td' ]]
}

successor_safe_direct_inventory() {
    local action32a_root=$1

    [[ -d "$action32a_root" && ! -L "$action32a_root" ]] || return 1
    find "$action32a_root" -mindepth 1 -maxdepth 1 -printf '%f\t%y\n' |
        LC_ALL=C sort
}

inspect_finalized_candidate() {
    local action32a_current
    local action32a_active_revision
    local action32a_revision
    local action32a_parent
    local action32a_source
    local action32a_candidate
    local -a action32a_candidates=()

    mapfile -t action32a_candidates < <(list_finalized_candidates)
    if [[ "$role" = node-a ]]; then
        ((${#action32a_candidates[@]} == 0)) || return 1
        printf 'finalized_candidate_count=0\n'
        successor_expected_candidate=
        return 0
    fi
    ((${#action32a_candidates[@]} == 1)) || return 1
    action32a_candidate=${action32a_candidates[0]}
    [[ "$action32a_candidate" == "$successor_incoming_root"/node-a/* ]] || return 1
    [[ "${action32a_candidate##*/}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    action32a_current=$(readlink -f "$successor_current_link") || return 1
    [[ "$action32a_current" == "$successor_releases_root"/* ]] || return 1
    [[ "${action32a_current##*/}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    action32a_active_revision=${action32a_current##*/}
    action32a_revision=$(jq -er '.revision | strings' "$action32a_candidate/release-manifest.json") || return 1
    action32a_parent=$(jq -er '.parent_revision // "" | strings' "$action32a_candidate/release-manifest.json") || return 1
    action32a_source=$(jq -er '.source_node | strings' "$action32a_candidate/release-manifest.json") || return 1
    [[ "$action32a_revision" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ -z "$action32a_parent" || "$action32a_parent" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ "$action32a_source" = node-a ]] || return 1
    [[ "$action32a_revision" = "$action32a_active_revision" ]] || return 1
    [[ "${action32a_candidate##*/}" = "$action32a_revision" ]] || return 1
    node_b_incoming_shape_exact "$action32a_candidate" || return 1
    release_payload_matches "$action32a_candidate" "$action32a_current" || return 1
    candidate_runtime_ready "$action32a_candidate" || return 1
    successor_expected_candidate=$action32a_candidate
    printf 'finalized_candidate_count=1\n'
    printf 'finalized_candidate_path=%s\n' "$action32a_candidate"
    printf 'finalized_candidate_revision=%s\n' "$action32a_revision"
    printf 'finalized_candidate_parent=%s\n' "${action32a_parent:-none}"
    printf 'finalized_candidate_source=%s\n' "$action32a_source"
    printf 'finalized_candidate_release_manifest_sha256=%s\n' \
        "$(successor_file_hash "$action32a_candidate/release-manifest.json")"
    printf 'finalized_candidate_payload_manifest_sha256=%s\n' \
        "$(successor_file_hash "$action32a_candidate/manifest.sha256")"
    printf 'finalized_candidate_file_count=%s\n' \
        "$(find "$action32a_candidate" -type f -printf '.' | wc -c)"
    printf 'finalized_candidate_exact_active_replay=true\n'
}

capture_semantic_state() {
    run_captured current_release readlink -f /etc/caddy/current || return 1
    before_release=$(cat "$capture_directory/current_release.stdout") || return 1
    [[ "$before_release" == /etc/caddy/releases/* && -d "$before_release" && ! -L "$before_release" ]] || return 1
    run_captured outbound_inventory safe_direct_inventory /var/lib/caddy-sync/outbound || return 1
    run_captured incoming_inventory safe_direct_inventory /var/lib/caddy-sync/incoming || return 1
    run_captured quarantine_inventory safe_direct_inventory /var/lib/caddy-sync/quarantine || return 1
    run_captured finalized_candidate_semantics inspect_finalized_candidate || return 1
    before_outbound=$(file_hash "$capture_directory/outbound_inventory.stdout") || return 1
    before_incoming=$(file_hash "$capture_directory/incoming_inventory.stdout") || return 1
    before_quarantine=$(file_hash "$capture_directory/quarantine_inventory.stdout") || return 1
    if [[ "$role" = node-b ]]; then
        check node_b_outbound_empty test ! -s "$capture_directory/outbound_inventory.stdout" || return 1
        check node_b_exact_replay_candidate test -n "$successor_expected_candidate" || return 1
    else
        check node_a_outbound_present test -s "$capture_directory/outbound_inventory.stdout" || return 1
        check node_a_no_finalized_candidate test -z "$successor_expected_candidate" || return 1
    fi
}

no_finalized_candidate() {
    local action32a_attempt

    for action32a_attempt in $(seq 0 30); do
        if ! incoming_has_finalized_candidate; then
            printf 'finalized_candidate_drain_attempt=%s\n' "$action32a_attempt"
            printf 'finalized_candidate_drained_by_corrected_reconciler=true\n'
            return 0
        fi
        sleep 1
    done
    return 1
}

finalized_candidate_absent() {
    local -a action32a_candidates=()

    [[ -d "$successor_incoming_root" && ! -L "$successor_incoming_root" ]] || return 1
    mapfile -t action32a_candidates < <(list_finalized_candidates)
    ((${#action32a_candidates[@]} == 0))
}

successor_configure() {
    local action32a_role=$1

    configure_role "$action32a_role" || return 1
    backup_directory=$backup_root/action32a-$role-runtime-lifecycle
    capture_directory=/tmp/caddy-action32a/$node_token
}

successor_validate() {
    local action32a_archive=$1
    local action32a_archive_sha256=$2

    successor_prepare_base "$action32a_archive" "$action32a_archive_sha256" || return 1
    successor_configure "$3" || return 1
    archive_path=$action32a_archive
    capture_directory=$(mktemp -d /tmp/caddy-action32a-validation.XXXXXX) || return 1
    validate_payload "$archive_path" "$action32a_archive_sha256" || return 1
    printf '%s_%s_validate_payload_complete=true\n' "$successor_prefix" "$node_token"
}

successor_apply() {
    local action32a_archive=$1
    local action32a_archive_sha256=$2
    local action32a_role=$3

    successor_prepare_base "$action32a_archive" "$action32a_archive_sha256" || return 1
    successor_configure "$action32a_role" || return 1
    successor_persist_base "$action32a_role" || return 1
    archive_path=$action32a_archive
    trap successor_rollback_on_error EXIT INT TERM
    apply "$action32a_archive_sha256"
    trap - EXIT INT TERM
    successor_cleanup
    printf '%s_%s_apply_complete=true\n' "$successor_prefix" "$node_token"
}

successor_rollback_on_error() {
    local action32a_status=$?

    trap - EXIT INT TERM
    successor_cleanup
    [[ -z "$stage_directory" || ! -d "$stage_directory" ]] || rm -rf -- "$stage_directory"
    if [[ -n "$archive_path" && "$archive_path" == /tmp/caddy-action32a-payload-*.tar ]]; then
        rm -f -- "$archive_path"
    fi
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action32a_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$successor_prefix" "$node_token" >&2
    if restore_backup; then
        printf '%s_%s_rollback_complete=true\n' "$successor_prefix" "$node_token" >&2
        exit "$action32a_status"
    fi
    printf '%s_%s_manual_intervention_required=true\n' "$successor_prefix" "$node_token" >&2
    exit 125
}

successor_rollback() {
    local action32a_role=$1

    successor_source_persisted_base "$action32a_role" || return 1
    successor_configure "$action32a_role" || return 1
    rollback || return 1
    rm -f -- "$successor_persisted_base"
    printf '%s_%s_rollback_complete=true\n' "$successor_prefix" "$node_token"
}

successor_verify() {
    local action32a_role=$1

    successor_source_persisted_base "$action32a_role" || return 1
    successor_configure "$action32a_role" || return 1
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
        [[ $# -eq 4 && $3 == /tmp/caddy-action32a-payload-*.tar ]] || exit 64
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
