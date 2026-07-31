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

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        return 0
    fi
    printf 'caddy_sync_reconcile_v2_check_%s=false\n' "$check_label" >&2
    return 1
}

set -a
# shellcheck disable=SC1091
source /etc/default/caddy-ha
set +a

install -d -m 0750 "$releases_root" "$quarantine_root"

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
            -print |
            LC_ALL=C sort
    ) >"$observed_list"
    local comparison_status=0
    cmp -s "$expected_list" "$observed_list" || comparison_status=$?
    rm -f -- "$expected_list" "$observed_list"
    return "$comparison_status"
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

if [[ -n "$active_revision" && "$parent_revision" != "$active_revision" ]]; then
    quarantine_path="$quarantine_root/$source_node-$revision"
    readonly quarantine_path
    require_check quarantine_destination_absent \
        test ! -e "$quarantine_path"
    mv -- "$candidate" "$quarantine_path"
    /usr/local/libexec/lsyncd-sync-failure-notify.sh \
        "Quarantined divergent release $revision; expected parent $active_revision"
    exit 1
fi

destination="$releases_root/$revision"
readonly destination
if [[ ! -d "$destination" ]]; then
    cp -a -- "$candidate" "$destination"
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
ln -sfn "$destination" /etc/caddy/current.new
mv -Tf /etc/caddy/current.new /etc/caddy/current
systemctl reload caddy.service
printf 'Activated protocol-v2 release %s\n' "$revision"
