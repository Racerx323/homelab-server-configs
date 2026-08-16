#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly policy=$script_directory/remote-streamed-bash-cwd-policy.sh

[[ $# -gt 0 ]] || exit 64
/bin/bash "$policy" --check "$@"
printf 'remote_streamed_bash_cwd_precommit_checked_file_count=%s\n' "$#"
printf 'remote_streamed_bash_cwd_precommit_complete=true\n'
