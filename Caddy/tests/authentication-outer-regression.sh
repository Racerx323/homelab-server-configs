#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
[[ ${CADDY_VALIDATION_CONTAINER:-0} = 1 && -f /run/.containerenv && $(id -u) = 0 ]] || exit 64
auth_outer_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly auth_outer_test_directory
for auth_outer_scenario in preflight-ipv6 preflight-tls preflight-http preflight-service preflight-publication preflight-interrupt success login-failure shared-login-failure restore-failure interrupt-helper evidence-failure dns-failure activate-reply-failure reconcile-failure reordered-evidence; do
    AUTH_OUTER_SCENARIO=$auth_outer_scenario python3 "$auth_outer_test_directory/authentication-outer-regression.py"
done

python3 "$auth_outer_test_directory/authentication-deployment-policy.py" --evidence-check /evidence
