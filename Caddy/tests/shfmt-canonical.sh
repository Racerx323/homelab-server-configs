#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
workspace_root=$(cd -- "$repo_root/.." && pwd)
monitoring_root="$workspace_root/homelab-monitoring-observability/Munin"

if [[ $# -lt 2 ]]; then
    printf 'Usage: %s --check|--write FILE [FILE ...]\n' "${0##*/}" >&2
    exit 2
fi

mode=$1
shift
case "$mode" in
    --check)
        shfmt_mode=-d
        ;;
    --write)
        shfmt_mode=-w
        ;;
    *)
        printf 'Usage: %s --check|--write FILE [FILE ...]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

canonical_files=()
for requested_file in "$@"; do
    if [[ ! -f "$requested_file" || -L "$requested_file" ]]; then
        printf 'Refusing non-regular or symbolic-link target: %s\n' \
            "$requested_file" >&2
        exit 2
    fi
    canonical_file=$(realpath -e -- "$requested_file")
    case "$canonical_file" in
        "$repo_root"/* | "$monitoring_root"/*)
            canonical_files+=("$canonical_file")
            ;;
        *)
            printf 'Refusing target outside approved repository roots: %s\n' \
                "$canonical_file" >&2
            exit 2
            ;;
    esac
done

exec shfmt "$shfmt_mode" -i 4 -ci "${canonical_files[@]}"
