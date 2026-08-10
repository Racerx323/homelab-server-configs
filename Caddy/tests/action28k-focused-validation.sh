#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28k_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly backend=$caddy_root/templates/pihole-admin-backend.Caddyfile.in
readonly frontend=$caddy_root/templates/pihole-admin-dns-owner.caddy.in
readonly service=$caddy_root/systemd/caddy-pihole-backend.service
readonly manifest=$caddy_root/manifests/pihole-admin-backend-action28k.yaml
readonly regression=$test_directory/action28k-protected-backend-architecture-regression.sh
readonly focused=$test_directory/action28k-focused-validation.sh
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

record_check() {
    local action28k_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28k_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28k_focused_label" >&2
    return 1
}

yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    grep -Fqx 'action: 28k' "$manifest" || return 1
    grep -Fqx 'status: architecture_defined_not_executable' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest" || return 1
    return 0
}

record_check syntax /bin/bash -n "$regression" "$focused"
record_check shellcheck shellcheck "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$regression" "$focused"
record_check yaml yaml_check
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$regression" "$focused"
record_check architecture_regression /bin/bash "$regression"
record_check plan_gate grep -Fq 'Action 28k' "$plan"
record_check backend_regular test -f "$backend"
record_check frontend_regular test -f "$frontend"
record_check service_regular test -f "$service"
record_check manifest_regular test -f "$manifest"

for action28k_focused_entrypoint in "$regression" "$focused"; do
    record_check "executable_$(basename "$action28k_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28k_focused_entrypoint"
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
