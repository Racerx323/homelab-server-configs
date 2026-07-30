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
readonly tracer="$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-second-retry.sh"
readonly historical_tracer="$caddy_root/scripts/trace-node-b-unbound-action17f-baseline-retry.sh"
readonly historical_tracer_sha256=1513aa2a559259965a1c6730e79dc3bfb953f4f5aca17590f4d39d71cc73de10

[[ "$(sha256sum "$historical_tracer" | awk '{ print $1 }')" == "$historical_tracer_sha256" ]]
grep -Fq 'set -Eeuo pipefail' "$tracer"
grep -Fq 'trap report_exact_failure ERR' "$tracer"
grep -Fq 'run_labeled_validation validate_baseline_labeled' "$tracer"
grep -Fq 'observed_live_state_sha256=%s' "$tracer"
grep -Fq 'expected_live_state_sha256=%s' "$tracer"

regression_dir=$(mktemp -d)
readonly regression_dir
cleanup() {
    rm -rf -- "$regression_dir"
}
trap cleanup EXIT

readonly transcript="$regression_dir/transcript"
failure_status=0
"$tracer" --failure-regression >"$transcript" 2>&1 ||
    failure_status=$?

[[ "$failure_status" -eq 1 ]]
[[ "$(grep -Ec '^exact_assertion_regression_function_internal_failure=false$' \
    "$transcript")" -eq 1 ]]
[[ "$(grep -Ec '^exact_assertion_regression_function_internal_failure_status=1$' \
    "$transcript")" -eq 1 ]]
[[ "$(grep -Ec '^action_17f_b_second_retry_failure_regression_status=1$' \
    "$transcript")" -eq 1 ]]
[[ "$(grep -Ec '^action_17f_b_second_retry_exact_baseline_complete=true$' \
    "$transcript")" -eq 0 ]]
[[ "$(grep -Ec '=true$' "$transcript")" -eq 0 ]]
if grep -Eq \
    'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|DOPPLER_TOKEN|AUDIT=' \
    "$transcript"; then
    exit 1
fi

printf 'action_17f_b_second_retry_production_failure_regression_complete=true\n'
