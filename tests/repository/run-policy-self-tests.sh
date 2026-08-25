#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory

/bin/bash "$test_directory/multifile-grep-count-policy.sh" --self-test
/bin/bash "$test_directory/portable-awk-policy.sh" --self-test
/bin/bash "$test_directory/remote-streamed-bash-policy.sh" --self-test

printf 'repository_shell_policy_self_tests_complete=true\n'
