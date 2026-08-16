#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_action34j_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-durable-apprise-action34j.sh
readonly outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34j-outer.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34j.tsv
readonly predecessor_upload=$caddy_root/scripts/apply-durable-apprise-action34i.sh
readonly predecessor_outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34i-outer.sh
readonly predecessor_transaction=$caddy_root/scripts/apply-durable-apprise-action34h.sh
readonly predecessor_regression=$test_directory/durable-apprise-action34i-regression.sh
readonly predecessor_action_manifest=$caddy_root/manifests/durable-apprise-action34i.yaml
readonly expected_predecessor_upload_sha256=34d43af6e72bcb40826eb8510cfe0a2d11369f8b7ec94529772e47217505675f
readonly expected_predecessor_outer_sha256=194730c4a2a3ad512a9e9636961bd87dfec0e07e90f3e83258ed727a9765cf83
readonly expected_predecessor_transaction_sha256=a909614f5d806e9c0da1d283090e5c8aa332ba9bf00a558707439899c5dac55c
readonly expected_predecessor_regression_sha256=d9c06d97ded16bbab221c527964df5ac771ae36a2499ed12905b832d18bce825
readonly expected_predecessor_action_manifest_sha256=602035f23d1f69216b76144c0a08069b54c1a5d5d448b9f275a7e9c4e297a13f

fixture_root=$(mktemp -d /tmp/caddy-action34j-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

check() {
    local action34j_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action34j_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action34j_regression_label" >&2
    return 1
}

candidate_sources_match() {
    local source_path installed_path mode baseline candidate source
    # conditional-validator-explicit-failures-begin
    while IFS=$'\t' read -r source_path installed_path mode baseline candidate; do
        [[ -n "$source_path" && "$source_path" != \#* ]] || continue
        : "$installed_path" "$mode" "$baseline"
        case "$source_path" in
            Caddy/*) source=${caddy_root%/Caddy}/$source_path ;;
            homelab-dns/*) source=${caddy_root%/Caddy}/../$source_path ;;
            *) return 1 ;;
        esac
        [[ -f "$source" && ! -L "$source" ]] || return 1
        [[ "$(file_hash "$source")" = "$candidate" ]] || return 1
    done <"$artifact_manifest"
    # conditional-validator-explicit-failures-end
}

ownership_rewrite_contract() {
    # conditional-validator-explicit-failures-begin
    # shellcheck disable=SC2016
    grep -Fq 'force_record_eligible_at "$action34h_record" "$action34h_now"' "$transaction" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'chown "$action34j_uid:$action34j_gid" "$action34j_temporary"' "$transaction" || return 1
    # shellcheck disable=SC2016
    grep -Fq '"$action34j_uid:$action34j_gid:600"' "$transaction" || return 1
    grep -Fq 'forced_eligibility_owner_' "$transaction" || return 1
    # shellcheck disable=SC2016
    ! grep -Fq 'action34h_temporary=$(mktemp "$queue_root/pending/.action34h.XXXXXX")' "$transaction" || return 1
    # conditional-validator-explicit-failures-end
}

actual_rewrite_path() {
    local record=$fixture_root/record.json
    local invalid=$fixture_root/invalid.json
    local now=1700000100
    local uid gid
    uid=$(id -u)
    gid=$(id -g)
    jq -n '{retry:{attempt:1,next_attempt_epoch:1700000000}}' >"$record"
    chmod 0600 "$record"
    /bin/bash -c '
        source "$1" --library-test node-a none none 1700000000-1
        force_record_eligible_at "$2" "$3" "$4" "$5"
    ' bash "$transaction" "$record" "$now" "$uid" "$gid"
    [[ -f "$record" && ! -L "$record" ]]
    [[ "$(stat -c '%u:%g:%a' "$record")" = "$uid:$gid:600" ]]
    [[ "$(jq -r '.retry.attempt' "$record")" -eq 1 ]]
    [[ "$(jq -r '.retry.next_attempt_epoch' "$record")" -eq "$now" ]]

    printf 'not-json\n' >"$invalid"
    chmod 0600 "$invalid"
    if /bin/bash -c '
        source "$1" --library-test node-a none none 1700000000-1
        force_record_eligible_at "$2" "$3" "$4" "$5"
    ' bash "$transaction" "$invalid" "$now" "$uid" "$gid"; then
        return 1
    fi
    [[ "$(cat "$invalid")" = not-json ]]
}

outer_contract() {
    # conditional-validator-explicit-failures-begin
    grep -Fq 'apply-durable-apprise-action34j.sh' "$outer" || return 1
    grep -Fq 'apply-durable-apprise-action34i.sh' "$outer" || return 1
    grep -Fq 'durable-apprise-action34j.tsv' "$outer" || return 1
    grep -Fq 'durable-apprise-action34h.tsv' "$outer" || return 1
    grep -Fq '/tmp/caddy-ssh-evidence/action34j' "$outer" || return 1
    ! grep -Fq 'run-dual-node-durable-apprise-action34i-outer.sh' "$outer" || return 1
    # conditional-validator-explicit-failures-end
}

check predecessor_upload_immutable test "$(file_hash "$predecessor_upload")" = "$expected_predecessor_upload_sha256"
check predecessor_outer_immutable test "$(file_hash "$predecessor_outer")" = "$expected_predecessor_outer_sha256"
check predecessor_transaction_immutable test "$(file_hash "$predecessor_transaction")" = "$expected_predecessor_transaction_sha256"
check predecessor_regression_immutable test "$(file_hash "$predecessor_regression")" = "$expected_predecessor_regression_sha256"
check predecessor_action_manifest_immutable test "$(file_hash "$predecessor_action_manifest")" = "$expected_predecessor_action_manifest_sha256"
check candidate_sources_match candidate_sources_match
check ownership_rewrite_contract ownership_rewrite_contract
check actual_rewrite_path actual_rewrite_path
check outer_contract outer_contract
check upload_boundary_regression /bin/bash "$predecessor_regression"
printf '%s_complete=true\n' "$prefix"
