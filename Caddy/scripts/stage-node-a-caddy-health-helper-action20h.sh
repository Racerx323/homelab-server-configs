#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly candidate_name=check-caddy-vrrp-action20h.sh

validate_candidate_stage() {
    local stage_path=$1
    local expected_owner=$2
    local expected_group=$3
    local expected_parent=$4

    [[ "$(dirname -- "$stage_path")" = "$expected_parent" ]] || return 1
    [[ -d "$stage_path" && ! -L "$stage_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path")" = "$expected_owner:$expected_group:710" ]] || return 1
    [[ -f "$stage_path/$candidate_name" && ! -L "$stage_path/$candidate_name" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path/$candidate_name")" = "$expected_owner:$expected_group:750" ]] || return 1
    [[ "$(find "$stage_path" -mindepth 1 -maxdepth 1 -printf '.\n' | wc -l)" -eq 1 ]] || return 1
}
adopt_candidate_stage() {
    local source_path=$1
    local stage_path=$2
    local expected_owner=$3
    local expected_group=$4
    local expected_parent=$5
    local initial_owner=$6
    local initial_group=$7

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(dirname -- "$stage_path")" = "$expected_parent" ]] || return 1
    [[ -d "$stage_path" && ! -L "$stage_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$stage_path")" = "$initial_owner:$initial_group:700" ]] || return 1
    [[ "$(find "$stage_path" -mindepth 1 -maxdepth 1 -print -quit)" = "" ]] || return 1
    install -d -o "$expected_owner" -g "$expected_group" -m 0710 "$stage_path" || return 1
    install -o "$expected_owner" -g "$expected_group" -m 0750 \
        "$source_path" "$stage_path/$candidate_name" || return 1
    validate_candidate_stage "$stage_path" "$expected_owner" "$expected_group" \
        "$expected_parent"
}

case "${1:-}" in
    --adopt)
        [[ $# -eq 8 ]] || exit 64
        adopt_candidate_stage "$2" "$3" "$4" "$5" "$6" "$7" "$8"
        ;;
    --validate)
        [[ $# -eq 5 ]] || exit 64
        validate_candidate_stage "$2" "$3" "$4" "$5"
        ;;
    *)
        printf 'Usage: %s --adopt SOURCE STAGE OWNER GROUP PARENT INITIAL_OWNER INITIAL_GROUP | --validate STAGE OWNER GROUP PARENT\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
