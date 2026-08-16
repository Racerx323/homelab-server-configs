#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_34i_upload
readonly mode=${1:-}
readonly role=${2:-}
readonly upload_path=${3:-}
readonly expected_sha256=${4:-}
readonly expected_size=${5:-}
readonly run_token=${6:-}

if [[ "$mode" = --library-test ]]; then
    temporary_root=${CADDY_ACTION34I_TEST_TMP:?}
    runtime_root=${CADDY_ACTION34I_TEST_RUN:?}
    upload_owner=$(id -un)
    upload_group=$(id -gn)
    control_owner=$upload_owner
    control_group=$upload_group
else
    temporary_root=/tmp
    runtime_root=/run/caddy-action34i-upload
    upload_owner=pi
    upload_group=pi
    control_owner=root
    control_group=root
fi
readonly temporary_root runtime_root upload_owner upload_group control_owner control_group
readonly evidence_root=$temporary_root/caddy-action34i/$run_token-$role
readonly marker=$runtime_root/$run_token-$role.prepared
readonly known_action34h_payload_sha256=524a1083b78a7d4862cd03d8e0affecc4e9de3cce7ae51bcab0cb6691755a5fb
readonly known_action34h_payload_size=40960

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

gate() {
    local action34i_upload_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_%s=true\n' "$prefix" "${role//-/_}" "$action34i_upload_label"
        return 0
    fi
    printf '%s_%s_%s=false\n' "$prefix" "${role//-/_}" "$action34i_upload_label" >&2
    return 1
}

validate_common() {
    # conditional-validator-explicit-failures-begin
    [[ "$role" = node-a || "$role" = node-b ]] || return 1
    [[ "$run_token" =~ ^[0-9]{10,20}-[0-9]+$ ]] || return 1
    [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$expected_size" =~ ^[1-9][0-9]{0,8}$ ]] || return 1
    [[ "$upload_path" = "$temporary_root/caddy-action34h-payload-$role-$run_token.tar" ]] || return 1
    [[ "$upload_path" != *$'\n'* && "$upload_path" != *$'\r'* ]] || return 1
    # conditional-validator-explicit-failures-end
}

prepare_roots() {
    install -d -o "$control_owner" -g "$control_group" -m 0700 "$temporary_root/caddy-action34i" || return 1
    install -d -o "$control_owner" -g "$control_group" -m 0700 "$evidence_root" || return 1
    install -d -o "$control_owner" -g "$control_group" -m 0700 "$runtime_root" || return 1
}

write_marker() {
    local action34i_upload_temporary
    action34i_upload_temporary=$(mktemp "$runtime_root/.prepared.XXXXXX") || return 1
    printf '%s\t%s\t%s\n' "$upload_path" "$expected_sha256" "$expected_size" \
        >"$action34i_upload_temporary" || return 1
    chown "$control_owner:$control_group" "$action34i_upload_temporary" || return 1
    chmod 0600 "$action34i_upload_temporary" || return 1
    mv -T -- "$action34i_upload_temporary" "$marker" || return 1
}

marker_is_exact() {
    local action34i_upload_expected
    action34i_upload_expected=$(printf '%s\t%s\t%s' "$upload_path" "$expected_sha256" "$expected_size") || return 1
    # conditional-validator-explicit-failures-begin
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' -- "$marker")" = "$control_owner:$control_group:600" ]] || return 1
    [[ "$(cat -- "$marker")" = "$action34i_upload_expected" ]] || return 1
    # conditional-validator-explicit-failures-end
}

inventory_upload() {
    local action34i_upload_label=$1
    local action34i_upload_path=$2
    local action34i_upload_metadata action34i_upload_size action34i_upload_hash
    # conditional-validator-explicit-failures-begin
    [[ -f "$action34i_upload_path" && ! -L "$action34i_upload_path" ]] || return 1
    action34i_upload_metadata=$(stat -c '%U:%G:%a' -- "$action34i_upload_path") || return 1
    [[ "$action34i_upload_metadata" = "$upload_owner:$upload_group:600" ]] || return 1
    action34i_upload_size=$(stat -c '%s' -- "$action34i_upload_path") || return 1
    [[ "$action34i_upload_size" =~ ^[0-9]+$ ]] || return 1
    [[ "$action34i_upload_size" -le "$expected_size" ]] || return 1
    action34i_upload_hash=$(file_hash "$action34i_upload_path") || return 1
    [[ "$action34i_upload_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\t%s\t%s\t%s\n' "$action34i_upload_path" "$action34i_upload_metadata" \
        "$action34i_upload_size" "$action34i_upload_hash" \
        >"$evidence_root/$action34i_upload_label.tsv" || return 1
    chmod 0600 "$evidence_root/$action34i_upload_label.tsv" || return 1
    printf '%s_%s_%s_path=%s\n' "$prefix" "${role//-/_}" "$action34i_upload_label" "$action34i_upload_path"
    printf '%s_%s_%s_size=%s\n' "$prefix" "${role//-/_}" "$action34i_upload_label" "$action34i_upload_size"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "${role//-/_}" "$action34i_upload_label" "$action34i_upload_hash"
    # conditional-validator-explicit-failures-end
}

prepare_upload() {
    validate_common || return 1
    prepare_roots || return 1
    gate upload_path_absent test ! -e "$upload_path" || return 1
    gate upload_path_not_symlink test ! -L "$upload_path" || return 1
    gate marker_absent test ! -e "$marker" || return 1
    gate marker_not_symlink test ! -L "$marker" || return 1
    write_marker || return 1
    gate marker_exact marker_is_exact || return 1
    printf '%s_%s_prepare_complete=true\n' "$prefix" "${role//-/_}"
}

dispose_upload() {
    validate_common || return 1
    prepare_roots || return 1
    gate marker_exact marker_is_exact || return 1
    if [[ -e "$upload_path" || -L "$upload_path" ]]; then
        inventory_upload attempted-upload "$upload_path" || return 1
        rm -f -- "$upload_path" || return 1
        gate attempted_upload_removed test ! -e "$upload_path" || return 1
    else
        printf '%s_%s_attempted_upload_state=absent\n' "$prefix" "${role//-/_}"
    fi
    rm -f -- "$marker" || return 1
    gate marker_removed test ! -e "$marker" || return 1
    printf '%s_%s_disposition_complete=true\n' "$prefix" "${role//-/_}"
}

accept_upload() {
    validate_common || return 1
    prepare_roots || return 1
    gate marker_exact marker_is_exact || return 1
    inventory_upload accepted-upload "$upload_path" || return 1
    gate upload_size_exact test "$(stat -c '%s' -- "$upload_path")" -eq "$expected_size" || return 1
    gate upload_hash_exact test "$(file_hash "$upload_path")" = "$expected_sha256" || return 1
    rm -f -- "$marker" || return 1
    gate marker_removed test ! -e "$marker" || return 1
    printf '%s_%s_accept_complete=true\n' "$prefix" "${role//-/_}"
}

dispose_action34h_node_b_residue() {
    local action34i_upload_candidate
    local -a action34i_upload_matches=()
    [[ "$role" = node-b ]] || return 1
    [[ "$expected_sha256" = "$known_action34h_payload_sha256" ]] || return 1
    [[ "$expected_size" -eq "$known_action34h_payload_size" ]] || return 1
    prepare_roots || return 1
    while IFS= read -r -d '' action34i_upload_candidate; do
        action34i_upload_matches+=("$action34i_upload_candidate")
    done < <(find "$temporary_root" -maxdepth 1 -type f \
        -name 'caddy-action34h-payload-node-b-*.tar' -print0)
    printf '%s_node_b_action34h_residue_count=%s\n' "$prefix" "${#action34i_upload_matches[@]}"
    gate action34h_residue_count_bounded test "${#action34i_upload_matches[@]}" -le 1 || return 1
    if [[ "${#action34i_upload_matches[@]}" -eq 1 ]]; then
        action34i_upload_candidate=${action34i_upload_matches[0]}
        [[ "$action34i_upload_candidate" =~ ^$temporary_root/caddy-action34h-payload-node-b-[0-9]{10,20}-[0-9]+\.tar$ ]] || return 1
        inventory_upload action34h-residue "$action34i_upload_candidate" || return 1
        rm -f -- "$action34i_upload_candidate" || return 1
        gate action34h_residue_removed test ! -e "$action34i_upload_candidate" || return 1
    fi
    printf '%s_node_b_action34h_residue_disposition_complete=true\n' "$prefix"
}

if [[ "$mode" = --library-test ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

case "$mode" in
    --prepare-upload) prepare_upload ;;
    --dispose-upload) dispose_upload ;;
    --accept-upload) accept_upload ;;
    --dispose-action34h-node-b-residue) dispose_action34h_node_b_residue ;;
    *) exit 64 ;;
esac
