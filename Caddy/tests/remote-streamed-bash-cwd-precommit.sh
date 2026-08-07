#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=remote_streamed_bash_cwd_precommit
readonly historical_action20m_path=Caddy/scripts/run-node-b-keepalived-dbus-main-action20m-outer.sh
readonly historical_action20m_sha256=e5888f78ed8195e9a368df002c71a99a4f602de9de780c9dc7578b3803eaeeb2
readonly historical_action20ma_path=Caddy/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-outer.sh
readonly historical_action20ma_sha256=cc6d8179dbb85bb4411043854ad8dde17c6f212fbcc397eb9a748e56525d47fe

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly policy=$script_directory/remote-streamed-bash-cwd-policy.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
is_historical_exception() {
    local cwd_precommit_source=$1
    local cwd_precommit_relative=$cwd_precommit_source

    cwd_precommit_relative=${cwd_precommit_relative#/home/aaron/code/homelab-server-configs/}
    cwd_precommit_relative=${cwd_precommit_relative#/workspace/homelab-server-configs/}
    case "$cwd_precommit_relative" in
        "$historical_action20m_path")
            [[ "$(file_hash "$cwd_precommit_source")" = "$historical_action20m_sha256" ]]
            ;;
        "$historical_action20ma_path")
            [[ "$(file_hash "$cwd_precommit_source")" = "$historical_action20ma_sha256" ]]
            ;;
        *) return 1 ;;
    esac
}

declare -a checked_paths=()
exception_count=0
for cwd_precommit_source in "$@"; do
    if is_historical_exception "$cwd_precommit_source"; then
        exception_count=$((exception_count + 1))
        continue
    fi
    checked_paths+=("$cwd_precommit_source")
done
printf '%s_hash_pinned_exception_count=%s\n' "$prefix" "$exception_count"
if [[ "${#checked_paths[@]}" -gt 0 ]]; then
    /bin/bash "$policy" --check "${checked_paths[@]}"
fi
printf '%s_checked_file_count=%s\n' "$prefix" "${#checked_paths[@]}"
printf '%s_complete=true\n' "$prefix"
