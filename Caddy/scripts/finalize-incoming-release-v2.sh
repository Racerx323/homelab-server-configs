#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly incoming_root=/var/lib/caddy-sync/incoming
readonly request_name=.finalize-request
readonly pending_name=.complete.pending
readonly complete_name=.complete
readonly reconcile_trigger="$incoming_root/.reconcile-trigger"

usage() {
    printf 'Usage: %s --source-role node-a|node-b\n' "${0##*/}" >&2
}

log_event() {
    logger -t caddy-sync-finalize -- "$1" || :
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        return 0
    fi
    printf 'caddy_sync_finalize_v2_check_%s=false\n' "$check_label" >&2
    return 1
}
signal_reconciliation() {
    local finalizer_trigger_path=$1
    local finalizer_trigger_metadata=$2

    if [[ -e "$finalizer_trigger_path" || -L "$finalizer_trigger_path" ]]; then
        require_check reconcile_trigger_regular test -f "$finalizer_trigger_path" || return 1
        require_check reconcile_trigger_not_symlink test ! -L "$finalizer_trigger_path" || return 1
    else
        install -m 0640 /dev/null "$finalizer_trigger_path" || return 1
    fi
    touch -- "$finalizer_trigger_path" || return 1
    require_check reconcile_trigger_metadata test \
        "$(stat -c '%U:%G:%a' "$finalizer_trigger_path")" = \
        "$finalizer_trigger_metadata"
}

set_receiver_identity() {
    local release_source_role=$1

    case "$release_source_role" in
        node-a)
            NODE_FQDN=pihole00.local.theama.co
            NODE_IPV4=10.1.0.54
            NODE_IPV6=fd36:5aa8:6971:1::54
            ;;
        node-b)
            NODE_FQDN=pihole0.local.theama.co
            NODE_IPV4=10.1.0.53
            NODE_IPV6=fd36:5aa8:6971:1::53
            ;;
        *)
            return 1
            ;;
    esac
    export NODE_FQDN NODE_IPV4 NODE_IPV6
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
    local release_path=$1
    local expected_list
    local observed_list

    expected_list=$(mktemp "${TMPDIR:-/tmp}/caddy-finalize-expected.XXXXXX")
    observed_list=$(mktemp "${TMPDIR:-/tmp}/caddy-finalize-observed.XXXXXX")
    awk '{ print substr($0, 67) }' "$release_path/manifest.sha256" |
        LC_ALL=C sort -u >"$expected_list"
    (
        cd "$release_path"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path "./$request_name" \
            ! -path "./$pending_name" \
            ! -path "./$complete_name" \
            -print |
            LC_ALL=C sort
    ) >"$observed_list"
    local comparison_status=0
    cmp -s "$expected_list" "$observed_list" || comparison_status=$?
    rm -f -- "$expected_list" "$observed_list"
    return "$comparison_status"
}

key_pair_matches() {
    local release_path=$1
    local certificate_public_key
    local private_public_key

    certificate_public_key=$(
        openssl x509 -in "$release_path/tls/fullchain.pem" -pubkey -noout |
            openssl pkey -pubin -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    private_public_key=$(
        openssl pkey -in "$release_path/tls/privkey.pem" -pubout \
            -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    [[ "$certificate_public_key" == "$private_public_key" ]]
}

validate_release() {
    local release_path=$1
    local release_source_role=$2
    local release_revision=$3

    require_check release_directory_regular test -d "$release_path"
    require_check release_directory_not_symlink test ! -L "$release_path"
    require_check request_marker_regular test -f "$release_path/$request_name"
    require_check request_marker_not_symlink \
        test ! -L "$release_path/$request_name"
    require_check request_marker_empty test ! -s "$release_path/$request_name"
    require_check release_manifest_regular \
        test -f "$release_path/release-manifest.json"
    require_check release_manifest_not_symlink \
        test ! -L "$release_path/release-manifest.json"
    require_check hash_manifest_regular \
        test -f "$release_path/manifest.sha256"
    require_check hash_manifest_not_symlink \
        test ! -L "$release_path/manifest.sha256"
    require_check release_symlinks_absent \
        test -z "$(find "$release_path" -type l -print -quit)"
    require_check release_special_files_absent \
        test -z "$(find "$release_path" ! -type d ! -type f -print -quit)"
    require_check release_hardlinks_absent \
        test -z "$(find "$release_path" -type f -links +1 -print -quit)"
    require_check nested_control_files_absent \
        test -z "$(find "$release_path" -mindepth 2 \
            \( -name "$request_name" -o -name "$pending_name" \
            -o -name "$complete_name" -o -name manifest.sha256 \) \
            -print -quit)"
    require_check manifest_revision_exact \
        test "$(jq -r '.revision // empty' \
            "$release_path/release-manifest.json")" = "$release_revision"
    require_check manifest_source_role_exact \
        test "$(jq -r '.source_node // empty' \
            "$release_path/release-manifest.json")" = "$release_source_role"
    require_check manifest_schema jq -e '
        (.revision | type == "string" and length > 0) and
        (.parent_revision | type == "string") and
        (.source_node == "node-a" or .source_node == "node-b") and
        (.created_at | type == "string" and length > 0)
    ' "$release_path/release-manifest.json" >/dev/null
    require_check manifest_paths_safe \
        manifest_paths_safe "$release_path/manifest.sha256"
    require_check manifest_file_set_exact \
        manifest_file_set_matches "$release_path"
    # The positional parameter is intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    require_check manifest_hashes_valid \
        bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$release_path"
    require_check certificate_parse \
        openssl x509 -in "$release_path/tls/fullchain.pem" -noout
    require_check private_key_parse \
        openssl pkey -in "$release_path/tls/privkey.pem" -noout
    require_check certificate_private_key_match \
        key_pair_matches "$release_path"
    require_check receiver_identity_known \
        set_receiver_identity "$release_source_role"
    require_check caddy_configuration_valid \
        env CADDY_CONFIG_ROOT="$release_path" \
        NODE_FQDN="$NODE_FQDN" \
        NODE_IPV4="$NODE_IPV4" \
        NODE_IPV6="$NODE_IPV6" \
        caddy validate --config "$release_path/Caddyfile" \
        --adapter caddyfile
}

finalize_release() {
    local release_path=$1
    local release_source_role=$2
    local release_revision=$3

    if [[ -f "$release_path/$complete_name" &&
        ! -L "$release_path/$complete_name" &&
        ! -s "$release_path/$complete_name" &&
        ! -e "$release_path/$pending_name" ]]; then
        validate_release \
            "$release_path" "$release_source_role" "$release_revision"
        require_check idempotent_directory_modes_locked \
            test -z "$(find "$release_path" -type d \
                ! -perm 0550 -print -quit)"
        require_check idempotent_file_modes_locked \
            test -z "$(find "$release_path" -type f \
                ! -perm 0440 -print -quit)"
        return 0
    fi

    require_check completion_marker_absent_before \
        test ! -e "$release_path/$complete_name"
    validate_release "$release_path" "$release_source_role" "$release_revision"

    chmod 0750 "$release_path"
    if [[ -e "$release_path/$pending_name" ]]; then
        require_check pending_marker_regular \
            test -f "$release_path/$pending_name"
        require_check pending_marker_not_symlink \
            test ! -L "$release_path/$pending_name"
        require_check pending_marker_empty \
            test ! -s "$release_path/$pending_name"
    else
        : >"$release_path/$pending_name"
    fi
    chmod 0440 "$release_path/$pending_name"
    mv -T -- "$release_path/$pending_name" "$release_path/$complete_name"
    find "$release_path" -type d -exec chmod 0550 {} +
    find "$release_path" -type f -exec chmod 0440 {} +

    validate_release "$release_path" "$release_source_role" "$release_revision"
    require_check completion_marker_regular \
        test -f "$release_path/$complete_name"
    require_check completion_marker_not_symlink \
        test ! -L "$release_path/$complete_name"
    require_check completion_marker_empty \
        test ! -s "$release_path/$complete_name"
    require_check pending_marker_absent \
        test ! -e "$release_path/$pending_name"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    manifest_paths_safe <(
        printf '%064d  ./Caddyfile\n' 0
    )
    if manifest_paths_safe <(
        printf '%064d  ../../etc/shadow\n' 0
    ); then
        exit 1
    fi
    printf 'caddy_sync_finalize_v2_self_test_complete=true\n'
    exit 0
fi
if [[ "${1:-}" == --reconciliation-trigger-self-test && $# -eq 1 ]]; then
    trigger_fixture=$(mktemp -d /tmp/caddy-finalizer-trigger.XXXXXX)
    readonly trigger_fixture
    trap 'rm -rf -- "$trigger_fixture"' EXIT INT TERM
    trigger_path=$trigger_fixture/.reconcile-trigger
    expected_metadata="$(id -un):$(id -gn):640"
    signal_reconciliation "$trigger_path" "$expected_metadata"
    signal_reconciliation "$trigger_path" "$expected_metadata"
    rm -f -- "$trigger_path"
    ln -s /dev/null "$trigger_path"
    if signal_reconciliation "$trigger_path" "$expected_metadata" \
        >/dev/null 2>&1; then
        exit 1
    fi
    printf 'caddy_sync_finalize_v2_reconciliation_trigger_created=true\n'
    printf 'caddy_sync_finalize_v2_reconciliation_trigger_reused=true\n'
    printf 'caddy_sync_finalize_v2_reconciliation_trigger_symlink_rejected=true\n'
    printf 'caddy_sync_finalize_v2_reconciliation_trigger_self_test_complete=true\n'
    exit 0
fi

if [[ $# -ne 2 || "$1" != --source-role ||
    ! "$2" =~ ^node-[ab]$ ]]; then
    usage
    exit 2
fi

readonly source_role=$2
readonly source_root="$incoming_root/$source_role"

require_check identity_caddy_sync test "$(id -un)" = caddy-sync
require_check source_root_regular_directory test -d "$source_root"
require_check source_root_not_symlink test ! -L "$source_root"

finalized_count=0
while IFS= read -r -d '' release_path; do
    revision=${release_path##*/}
    if [[ "$revision" == .* || ! "$revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        log_event "rejected unsafe release directory under $source_role"
        exit 1
    fi
    finalize_release "$release_path" "$source_role" "$revision"
    finalized_count=$((finalized_count + 1))
    log_event "validated and finalized release $revision from $source_role"
done < <(
    find "$source_root" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        ! -name '.*' \
        -exec test -f '{}/.finalize-request' ';' \
        -print0 |
        LC_ALL=C sort -z
)

log_event "receiver finalization scan completed for $source_role with $finalized_count release(s)"
if ((finalized_count > 0)); then
    signal_reconciliation "$reconcile_trigger" caddy-sync:caddy-sync:640
    log_event "signaled reconciliation after finalizing $finalized_count release(s) from $source_role"
fi
