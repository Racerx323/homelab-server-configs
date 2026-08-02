#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly manifest="$caddy_root/manifests/synchronization-protocol-v2.yaml"
readonly publisher="$caddy_root/scripts/publish-release-v2.sh"
readonly receiver="$caddy_root/scripts/caddy-sync-release-receiver-v2"
readonly finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly reconciler="$caddy_root/scripts/reconcile-release-v2.sh"
readonly lsyncd_template="$caddy_root/templates/lsyncd-caddy-receiver-finalized-v2.lua.in"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

for artifact in \
    "$publisher" \
    "$receiver" \
    "$finalizer" \
    "$reconciler"; do
    [[ -f "$artifact" ]]
    [[ ! -L "$artifact" ]]
    bash -n "$artifact"
    shellcheck "$artifact"
done

for data_artifact in \
    "$manifest" \
    "$lsyncd_template" \
    "$authorization_template"; do
    [[ -f "$data_artifact" ]]
    [[ ! -L "$data_artifact" ]]
done

"$receiver" --self-test >/dev/null
"$finalizer" --self-test >/dev/null
"$collision_checker" \
    "$publisher" \
    "$receiver" \
    "$finalizer" \
    "$reconciler" \
    "$0" >/dev/null

grep -Fq 'transmitted_completion_marker: false' "$manifest"
grep -Fq 'locally_created_marker: .complete' "$manifest"
grep -Fq 'conflict_action: quarantine' "$manifest"
grep -Fq 'forced_command_source_role: peer-role' "$manifest"
grep -Fxq \
    'from="@PEER_IPV4@,@PEER_IPV6@",restrict,command="/usr/local/libexec/caddy-sync-release-receiver-v2 --source-role @PEER_ROLE@"' \
    "$authorization_template"
grep -Fq 'targetdir = "/"' "$lsyncd_template"
grep -Fq '"--exclude=.complete"' "$lsyncd_template"
grep -Fq '"--exclude=.complete.pending"' "$lsyncd_template"
grep -Fq '"--no-perms"' "$lsyncd_template"
grep -Fq 'delete = false' "$lsyncd_template"
# These are intentional literal shell-source assertions.
# shellcheck disable=SC2016
grep -Fq '/usr/bin/rrsync -wo -no-del "$receiver_root"' "$receiver"
# shellcheck disable=SC2016
grep -Fq '"$finalizer" --source-role "$source_role"' "$receiver"
# shellcheck disable=SC2016
grep -Fq ': >"$staging_dir/.finalize-request"' "$publisher"
# shellcheck disable=SC2016
grep -Fq 'mv -- "$staging_dir" "$release_dir"' "$publisher"
grep -Fq '! -path ./.complete' "$publisher"
# shellcheck disable=SC2016
grep -Fq 'mv -T -- "$release_path/$pending_name"' "$finalizer"
# shellcheck disable=SC2016
grep -Fq '"$release_path/$complete_name"' "$finalizer"
# shellcheck disable=SC2016
grep -Fq 'manifest_paths_safe "$release_path/manifest.sha256"' "$finalizer"
# shellcheck disable=SC2016
grep -Fq 'manifest_file_set_matches "$release_path"' "$finalizer"
grep -Fq '! -path '\''*/.*'\''' "$reconciler"
# shellcheck disable=SC2016
grep -Fq 'manifest_file_set_matches "$candidate"' "$reconciler"
# shellcheck disable=SC2016
grep -Fq 'mv -- "$candidate" "$quarantine_path"' "$reconciler"

if grep -Eq \
    'rsync.*[.]complete|cp.*[.]complete|scp.*[.]complete' \
    "$publisher" "$receiver" "$finalizer" "$reconciler" "$lsyncd_template"; then
    printf 'Protocol v2 contains completion-marker transport behavior.\n' >&2
    exit 1
fi

if grep -Eq -- '--delete([=[:space:]]|$)' \
    "$publisher" "$receiver" "$finalizer" "$reconciler" "$lsyncd_template"; then
    printf 'Protocol v2 contains a remote-delete request.\n' >&2
    exit 1
fi

negative_dir=$(mktemp -d /tmp/caddy-receiver-v2-negative.XXXXXX)
trap 'rm -rf -- "$negative_dir"' EXIT
negative_status=0
SSH_ORIGINAL_COMMAND=caddy-sync-finalize \
    "$receiver" --source-role node-a \
    >"$negative_dir/out" 2>"$negative_dir/err" ||
    negative_status=$?
[[ "$negative_status" -eq 126 ]]
[[ ! -s "$negative_dir/out" ]]
grep -Fxq 'Only the rsync server protocol is permitted.' "$negative_dir/err"

delete_status=0
SSH_ORIGINAL_COMMAND='rsync --server --delete -logDtpre.iLsfxCIvu . /' \
    "$receiver" --source-role node-a \
    >"$negative_dir/delete-out" 2>"$negative_dir/delete-err" ||
    delete_status=$?
[[ "$delete_status" -eq 126 ]]
[[ ! -s "$negative_dir/delete-out" ]]
grep -Fxq 'Remote deletion is not permitted.' "$negative_dir/delete-err"

printf 'receiver_finalization_protocol_v2_regression_complete=true\n'
