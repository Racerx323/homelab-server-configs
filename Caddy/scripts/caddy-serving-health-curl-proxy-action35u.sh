#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly evidence_root=${ACTION35U_CURL_EVIDENCE_ROOT:?missing ACTION35U_CURL_EVIDENCE_ROOT}
readonly real_curl=${ACTION35U_REAL_CURL:-/usr/bin/curl}
[[ "$evidence_root" = /tmp/caddy-action35u-evidence-* && -d "$evidence_root" && ! -L "$evidence_root" ]]
[[ -x "$real_curl" && ! -L "$real_curl" ]]
family=ipv4
for argument in "$@"; do
    [[ "$argument" = --ipv6 ]] && family=ipv6
done
readonly family

printf '%q ' "$real_curl" "$@" >"$evidence_root/helper-$family-curl-arguments.txt"
printf '\n' >>"$evidence_root/helper-$family-curl-arguments.txt"
: >"$evidence_root/helper-$family-curl.stdout"
: >"$evidence_root/helper-$family-curl.stderr"
status=0
if "$real_curl" "$@" >"$evidence_root/helper-$family-curl.stdout" \
    2>"$evidence_root/helper-$family-curl.stderr"; then
    status=0
else
    status=$?
fi
printf '%s\n' "$status" >"$evidence_root/helper-$family-curl.status"
exit "$status"
