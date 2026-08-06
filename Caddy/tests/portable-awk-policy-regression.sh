#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=portable_awk_policy_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly policy=$test_directory/portable-awk-policy.sh
root=$(mktemp -d /tmp/caddy-portable-awk-policy.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT

cat >"$root/valid.sh" <<'VALID'
#!/usr/bin/env bash
awk '
    length($2) != 64 || $2 !~ /^[0-9a-f]+$/ { exit 1 }
' input
[[ "$value" =~ ^[0-9a-f]{64}$ ]]
VALID
/bin/bash "$policy" --check "$root/valid.sh" >/dev/null
printf '%s_portable_length_check_accepted=true\n' "$prefix"
printf '%s_non_awk_interval_accepted=true\n' "$prefix"

readonly invalid_interval='{64}'
printf '%s\n' '#!/usr/bin/env bash' \
    "awk '\$2 !~ /^[0-9a-f]${invalid_interval}\$/ { exit 1 }' input" \
    >"$root/invalid-inline.sh"
if /bin/bash "$policy" --check "$root/invalid-inline.sh" >/dev/null 2>"$root/inline.stderr"; then
    printf '%s_inline_interval_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_inline_interval_rejected=true\n' "$prefix"

printf '%s\n' '#!/usr/bin/env bash' "awk '" \
    "    \$2 !~ /^[0-9a-f]${invalid_interval}\$/ { exit 1 }" \
    "' input" >"$root/invalid-multiline.sh"
if /bin/bash "$policy" --check "$root/invalid-multiline.sh" >/dev/null 2>"$root/multiline.stderr"; then
    printf '%s_multiline_interval_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_multiline_interval_rejected=true\n' "$prefix"
printf '%s_false_positive_controls=true\n' "$prefix"
printf '%s_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
