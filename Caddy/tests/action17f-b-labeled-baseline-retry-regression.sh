#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly tracer="$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-retry.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

work_dir=$(mktemp -d)
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

bash -n "$tracer" "$collision_checker"
"$tracer" --self-test >/dev/null
"$collision_checker" "$tracer" >/dev/null

literal_labels=$(
    sed -n -E \
        's/^[[:space:]]*current_assertion=([a-zA-Z0-9_]+)$/\1/p' \
        "$tracer" |
        grep -Fvx not_started
)
literal_label_count=$(printf '%s\n' "$literal_labels" | wc -l)
literal_unique_count=$(printf '%s\n' "$literal_labels" | sort -u | wc -l)
[[ "$literal_label_count" -eq 25 ]]
[[ "$literal_unique_count" -eq "$literal_label_count" ]]

# shellcheck disable=SC2016
grep -Fq 'current_assertion="primary_stage_entry_${entry_index}"' "$tracer"
# shellcheck disable=SC2016
grep -Fq 'current_assertion="primary_${file_labels[$entry_index]}_regular"' \
    "$tracer"
# shellcheck disable=SC2016
grep -Fq 'current_assertion="primary_${file_labels[$entry_index]}_metadata"' \
    "$tracer"
[[ "$(grep -Ec '^[[:space:]]*mark_passed$' "$tracer")" -eq 28 ]]
grep -Fq 'exact_assertion_%s=false' "$tracer"
grep -Fq 'action_17f_b_retry_exact_baseline_status=' "$tracer"
grep -Fq 'remote_paths_created=false' "$tracer"
grep -Fq 'dns_queries_performed=false' "$tracer"
grep -Fq 'dns_configuration_mutations=false' "$tracer"
grep -Fq 'service_mutations=false' "$tracer"
grep -Fq 'persistent_mutations=false' "$tracer"

if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|mkdir|mktemp)([[:space:]]|$)' \
    "$tracer"; then
    printf 'Corrected Action 17f-b tracer contains a remote write.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$tracer"; then
    printf 'Corrected Action 17f-b tracer contains a service mutation.\n' >&2
    exit 1
fi

clean_fixture="$work_dir/clean.sh"
collision_fixture="$work_dir/collision.sh"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly evidence_path=/tmp/evidence' \
    'validate() {' \
    '    local transcript_path=$1' \
    '    printf "%s\n" "$transcript_path"' \
    '}' >"$clean_fixture"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly transcript=/tmp/evidence' \
    'validate() {' \
    '    local transcript=$1' \
    '    printf "%s\n" "$transcript"' \
    '}' >"$collision_fixture"
"$collision_checker" "$clean_fixture" >/dev/null
if "$collision_checker" "$collision_fixture" >/dev/null 2>&1; then
    printf 'Readonly/local collision policy accepted a collision fixture.\n' >&2
    exit 1
fi

printf 'action_17f_b_labeled_baseline_retry_regression_complete=true\n'
