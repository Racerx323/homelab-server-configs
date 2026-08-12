#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-caddy-systemd-boot-persistence-action30e.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-systemd-boot-persistence-action30e-outer.sh
readonly regression=$caddy_root/tests/action30e-caddy-systemd-boot-persistence-regression.sh
readonly policy=$caddy_root/tests/systemd-boot-persistence-policy.sh
readonly health_worker=$caddy_root/scripts/validate-sync-health.sh
readonly lsyncd_unit=$caddy_root/systemd/caddy-lsyncd.service
readonly manifest=$caddy_root/manifests/caddy-systemd-boot-persistence-action30e.yaml
readonly prefix=action_30e_focused

check() {
    local action30e_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action30e_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action30e_focused_label" >&2
    return 1
}
manifest_valid() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest"
        return
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
}
run_checks() {
    local action30e_focused_entry

    # conditional-validator-explicit-failures-begin
    for action30e_focused_entry in "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}"; do
        check "$(basename "$action30e_focused_entry" | tr -c '[:alnum:]' _)_syntax" \
            /bin/bash -n "$action30e_focused_entry" || return 1
    done
    check regression /bin/bash "$regression" || return 1
    check policy /bin/bash "$policy" --check || return 1
    check shellcheck shellcheck "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}" || return 1
    check canonical /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}" || return 1
    check collision /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}" || return 1
    check conditional /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    check multifile /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}" || return 1
    check portable_awk /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$outer" "$regression" "$policy" "$health_worker" "${BASH_SOURCE[0]}" || return 1
    check remote_cwd /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "$outer" || return 1
    check ssh_evidence /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "$outer" || return 1
    check manifest manifest_valid || return 1
    check lsyncd_unit_regular test -f "$lsyncd_unit" || return 1
    check lsyncd_unit_success_exit_exact test \
        "$(grep -Fxc 'SuccessExitStatus=143' "$lsyncd_unit")" -eq 1 || return 1
    check outer_self_test env CADDY_ACTION30E_SKIP_REGRESSION=true \
        CADDY_ACTION30E_SKIP_REPEATED_POLICIES=true /bin/bash "$outer" --self-test || return 1
    # conditional-validator-explicit-failures-end
    printf '%s_complete=true\n' "$prefix"
}

run_checks
