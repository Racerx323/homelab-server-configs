#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly incoming_root=/var/lib/caddy-sync/incoming
readonly releases_root=/etc/caddy/releases
readonly quarantine_root=/var/lib/caddy-sync/quarantine
quarantine_replay_fixture_root=

cleanup_quarantine_replay_fixture() {
    if [[ -n "$quarantine_replay_fixture_root" &&
        -d "$quarantine_replay_fixture_root" ]]; then
        rm -rf -- "$quarantine_replay_fixture_root"
    fi
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        return 0
    fi
    printf 'caddy_sync_reconcile_v2_check_%s=false\n' "$check_label" >&2
    return 1
}

manifest_paths_safe() {
    local manifest_path=$1

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
    ' "$manifest_path"
}

manifest_file_set_matches() {
    local candidate_path=$1
    local expected_list
    local observed_list

    expected_list=$(mktemp "${TMPDIR:-/tmp}/caddy-reconcile-expected.XXXXXX")
    observed_list=$(mktemp "${TMPDIR:-/tmp}/caddy-reconcile-observed.XXXXXX")
    awk '{ print substr($0, 67) }' "$candidate_path/manifest.sha256" |
        LC_ALL=C sort -u >"$expected_list"
    (
        cd "$candidate_path"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending \
            -print |
            LC_ALL=C sort
    ) >"$observed_list"
    local comparison_status=0
    cmp -s "$expected_list" "$observed_list" || comparison_status=$?
    rm -f -- "$expected_list" "$observed_list"
    return "$comparison_status"
}

release_payload_matches() {
    local reconcile_left=$1
    local reconcile_right=$2

    # conditional-validator-explicit-failures-begin
    [[ -d "$reconcile_left" && ! -L "$reconcile_left" ]] || return 1
    [[ -d "$reconcile_right" && ! -L "$reconcile_right" ]] || return 1
    [[ -f "$reconcile_left/release-manifest.json" ]] || return 1
    [[ -f "$reconcile_right/release-manifest.json" ]] || return 1
    [[ -f "$reconcile_left/manifest.sha256" ]] || return 1
    [[ -f "$reconcile_right/manifest.sha256" ]] || return 1
    [[ -f "$reconcile_left/.finalize-request" && ! -L "$reconcile_left/.finalize-request" ]] || return 1
    [[ -f "$reconcile_right/.finalize-request" && ! -L "$reconcile_right/.finalize-request" ]] || return 1
    [[ -f "$reconcile_left/.complete" && ! -L "$reconcile_left/.complete" ]] || return 1
    [[ -f "$reconcile_right/.complete" && ! -L "$reconcile_right/.complete" ]] || return 1
    [[ ! -e "$reconcile_left/.complete.pending" ]] || return 1
    [[ ! -e "$reconcile_right/.complete.pending" ]] || return 1
    test -z "$(find "$reconcile_left" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    test -z "$(find "$reconcile_right" \( -type l -o ! -type d ! -type f \) -print -quit)" || return 1
    test -z "$(find "$reconcile_left" -type f -links +1 -print -quit)" || return 1
    test -z "$(find "$reconcile_right" -type f -links +1 -print -quit)" || return 1
    manifest_paths_safe "$reconcile_left/manifest.sha256" || return 1
    manifest_paths_safe "$reconcile_right/manifest.sha256" || return 1
    manifest_file_set_matches "$reconcile_left" || return 1
    manifest_file_set_matches "$reconcile_right" || return 1
    (cd "$reconcile_left" && sha256sum --strict --check manifest.sha256 >/dev/null) || return 1
    (cd "$reconcile_right" && sha256sum --strict --check manifest.sha256 >/dev/null) || return 1
    cmp -s "$reconcile_left/release-manifest.json" "$reconcile_right/release-manifest.json" || return 1
    cmp -s "$reconcile_left/manifest.sha256" "$reconcile_right/manifest.sha256" || return 1
    # conditional-validator-explicit-failures-end
}

discard_exact_quarantine_replay() {
    local replay_candidate=$1
    local replay_quarantine=$2
    local replay_revision=$3

    # conditional-validator-explicit-failures-begin
    require_check quarantine_destination_regular \
        test -d "$replay_quarantine" || return 1
    require_check quarantine_destination_not_symlink \
        test ! -L "$replay_quarantine" || return 1
    require_check quarantine_replay_payload_exact \
        release_payload_matches "$replay_candidate" "$replay_quarantine" || return 1
    # conditional-validator-explicit-failures-end
    rm -rf -- "$replay_candidate"
    printf 'Discarded exact replay of quarantined protocol-v2 release %s.\n' \
        "$replay_revision"
}

run_quarantine_replay_self_test() {
    local replay_fixture_candidate
    local replay_fixture_quarantine

    quarantine_replay_fixture_root=$(mktemp -d /tmp/caddy-reconcile-replay.XXXXXX)
    trap cleanup_quarantine_replay_fixture EXIT INT TERM
    replay_fixture_candidate=$quarantine_replay_fixture_root/incoming/node-a/fixture
    replay_fixture_quarantine=$quarantine_replay_fixture_root/quarantine/node-a-fixture
    mkdir -p "$replay_fixture_quarantine"
    printf 'fixture\n' >"$replay_fixture_quarantine/Caddyfile"
    printf '{"revision":"fixture","source_node":"node-a"}\n' \
        >"$replay_fixture_quarantine/release-manifest.json"
    (
        cd "$replay_fixture_quarantine"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
    : >"$replay_fixture_quarantine/.finalize-request"
    : >"$replay_fixture_quarantine/.complete"
    mkdir -p "$(dirname -- "$replay_fixture_candidate")"
    cp -a -- "$replay_fixture_quarantine" "$replay_fixture_candidate"
    discard_exact_quarantine_replay "$replay_fixture_candidate" \
        "$replay_fixture_quarantine" fixture
    [[ ! -e "$replay_fixture_candidate" ]] || return 1
    printf 'caddy_sync_reconcile_v2_self_test_exact_replay_discarded=true\n'
    cp -a -- "$replay_fixture_quarantine" "$replay_fixture_candidate"
    printf 'drift\n' >>"$replay_fixture_candidate/Caddyfile"
    if discard_exact_quarantine_replay "$replay_fixture_candidate" \
        "$replay_fixture_quarantine" fixture >/dev/null 2>&1; then
        return 1
    fi
    [[ -d "$replay_fixture_candidate" ]] || return 1
    printf 'caddy_sync_reconcile_v2_self_test_divergent_replay_rejected=true\n'
    printf 'caddy_sync_reconcile_v2_self_test_complete=true\n'
}

if [[ "${1:-}" = --quarantine-replay-self-test ]]; then
    run_quarantine_replay_self_test
    exit 0
fi

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

install -d -m 0750 "$releases_root" "$quarantine_root"

restore_previous_selection() {
    local reconcile_previous=$1

    ln -sfn "$reconcile_previous" /etc/caddy/current.rollback
    mv -Tf /etc/caddy/current.rollback /etc/caddy/current
    systemctl reload caddy.service
}

candidate=$(
    find "$incoming_root" \
        -mindepth 2 \
        -maxdepth 2 \
        -type d \
        ! -path '*/.*' \
        -exec test -f '{}/.finalize-request' ';' \
        -exec test -f '{}/.complete' ';' \
        ! -exec test -e '{}/.complete.pending' ';' \
        -print 2>/dev/null |
        LC_ALL=C sort |
        tail -n 1
)

if [[ -z "$candidate" ]]; then
    exit 0
fi

require_check candidate_not_symlink test ! -L "$candidate"
require_check request_marker_regular test -f "$candidate/.finalize-request"
require_check request_marker_not_symlink \
    test ! -L "$candidate/.finalize-request"
require_check request_marker_empty test ! -s "$candidate/.finalize-request"
require_check completion_marker_regular test -f "$candidate/.complete"
require_check completion_marker_not_symlink test ! -L "$candidate/.complete"
require_check completion_marker_empty test ! -s "$candidate/.complete"
require_check candidate_symlinks_absent \
    test -z "$(find "$candidate" -type l -print -quit)"
require_check candidate_special_files_absent \
    test -z "$(find "$candidate" ! -type d ! -type f -print -quit)"
require_check candidate_hardlinks_absent \
    test -z "$(find "$candidate" -type f -links +1 -print -quit)"
require_check nested_control_files_absent \
    test -z "$(find "$candidate" -mindepth 2 \
        \( -name .finalize-request -o -name .complete \
        -o -name manifest.sha256 \) -print -quit)"
require_check candidate_directories_locked \
    test -z "$(find "$candidate" -type d ! -perm 0550 -print -quit)"
require_check candidate_files_locked \
    test -z "$(find "$candidate" -type f ! -perm 0440 -print -quit)"

revision=$(jq -r '.revision // empty' "$candidate/release-manifest.json")
readonly revision
parent_revision=$(
    jq -r '.parent_revision // ""' "$candidate/release-manifest.json"
)
readonly parent_revision
source_node=$(jq -r '.source_node // empty' "$candidate/release-manifest.json")
readonly source_node

# The positional parameters are intentionally expanded by the child shell.
# shellcheck disable=SC2016
require_check revision_shape \
    bash -c '[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]' _ "$revision"
# shellcheck disable=SC2016
require_check source_role_shape \
    bash -c '[[ "$1" =~ ^node-[ab]$ ]]' _ "$source_node"
require_check candidate_path_exact \
    test "$candidate" = "$incoming_root/$source_node/$revision"
require_check manifest_paths_safe \
    manifest_paths_safe "$candidate/manifest.sha256"
require_check manifest_file_set_exact \
    manifest_file_set_matches "$candidate"
# The positional parameter is intentionally expanded by the child shell.
# shellcheck disable=SC2016
require_check manifest_hashes_valid \
    bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
    _ "$candidate"
require_check caddy_configuration_valid \
    env CADDY_CONFIG_ROOT="$candidate" \
    caddy validate --config "$candidate/Caddyfile" \
    --adapter caddyfile

active_revision=
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    active_revision=$(
        jq -r '.revision // ""' /etc/caddy/current/release-manifest.json
    )
fi
readonly active_revision

if [[ -n "$active_revision" && "$revision" = "$active_revision" ]]; then
    require_check active_destination_exact \
        test "$(readlink -f -- /etc/caddy/current)" = "$releases_root/$revision"
    require_check active_destination_payload_exact \
        release_payload_matches "$candidate" "$releases_root/$revision"
    printf 'Protocol-v2 release %s is already active.\n' "$revision"
    exit 0
fi

if [[ -n "$active_revision" && "$parent_revision" != "$active_revision" ]]; then
    quarantine_path="$quarantine_root/$source_node-$revision"
    readonly quarantine_path
    if [[ -e "$quarantine_path" || -L "$quarantine_path" ]]; then
        discard_exact_quarantine_replay "$candidate" "$quarantine_path" \
            "$revision"
        exit 0
    fi
    mv -- "$candidate" "$quarantine_path"
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "Quarantined divergent release $revision; expected parent $active_revision"
    exit 1
fi

destination="$releases_root/$revision"
readonly destination
destination_stage=
cleanup_destination_stage() {
    if [[ -n "$destination_stage" && -d "$destination_stage" ]]; then
        rm -rf -- "$destination_stage"
    fi
}
trap cleanup_destination_stage EXIT INT TERM
if [[ -e "$destination" || -L "$destination" ]]; then
    require_check destination_payload_exact \
        release_payload_matches "$candidate" "$destination"
else
    destination_stage=$(mktemp -d "$releases_root/.reconcile-$revision.XXXXXX")
    cp -a -- "$candidate/." "$destination_stage/"
    chown -R root:caddy-tls "$destination_stage"
    find "$destination_stage" -type d -exec chmod 0550 {} +
    find "$destination_stage" -type f -exec chmod 0440 {} +
    require_check staged_destination_payload_exact \
        release_payload_matches "$candidate" "$destination_stage"
    mv -- "$destination_stage" "$destination"
    destination_stage=
fi
require_check destination_regular_directory test -d "$destination"
require_check destination_not_symlink test ! -L "$destination"
chown -R root:caddy-tls "$destination"
find "$destination" -type d -exec chmod 0550 {} +
find "$destination" -type f -exec chmod 0440 {} +
require_check destination_directories_locked \
    test -z "$(find "$destination" -type d ! -perm 0550 -print -quit)"
require_check destination_files_locked \
    test -z "$(find "$destination" -type f ! -perm 0440 -print -quit)"
require_check destination_payload_exact_before_selection \
    release_payload_matches "$candidate" "$destination"
previous_destination=$(readlink -f -- /etc/caddy/current)
readonly previous_destination
require_check previous_destination_regular test -d "$previous_destination"
require_check previous_destination_not_symlink test ! -L "$previous_destination"
ln -sfn "$destination" /etc/caddy/current.new
mv -Tf /etc/caddy/current.new /etc/caddy/current
reload_status=0
systemctl reload caddy.service || reload_status=$?
if [[ "$reload_status" -ne 0 ]]; then
    restore_status=0
    restore_previous_selection "$previous_destination" || restore_status=$?
    if [[ "$restore_status" -ne 0 ]]; then
        printf 'Failed to restore the previous Caddy release after reload failure.\n' >&2
        exit 125
    fi
    printf 'Caddy reload rejected protocol-v2 release %s; previous release restored.\n' \
        "$revision" >&2
    exit "$reload_status"
fi
trap - EXIT INT TERM
printf 'Activated protocol-v2 release %s\n' "$revision"
