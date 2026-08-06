#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly config=$caddy_root/configs/tmpfiles.d/caddy-ha.conf
readonly installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry.sh
readonly inspector=$caddy_root/scripts/inspect-caddy-runtime-directories-action20e-retry-a.sh
readonly acceptance_runner=$caddy_root/scripts/run-dual-node-caddy-runtime-postinstall-action20e-retry-a.sh

verify_sources() {
    local source_path

    for source_path in "$config" "$installer" "$runner" "$inspector" "$acceptance_runner"; do
        [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    done
    [[ "$(stat -c '%a' "$config")" = 644 ]] || return 1
    for source_path in "$installer" "$runner" "$inspector" "$acceptance_runner"; do
        [[ -x "$source_path" ]] || return 1
    done
    /bin/bash -n "$installer" "$runner" "$inspector" "$acceptance_runner" || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    /bin/bash "$runner" --self-test >/dev/null || return 1
    /bin/bash "$inspector" --self-test >/dev/null || return 1
    /bin/bash "$acceptance_runner" --self-test >/dev/null || return 1
    [[ "$(sha256sum "$config" | awk '{ print $1 }')" = "$(/bin/bash "$installer" --render-config | sha256sum | awk '{ print $1 }')" ]] || return 1
    ! grep -Fq -- '--dry-run' "$installer" || return 1
    # Match the literal production source, not a parent-shell expansion.
    # shellcheck disable=SC2016
    grep -Fq 'systemd-tmpfiles --root="$shadow_root" --create caddy-ha.conf' \
        "$installer" || return 1
    grep -Fq 'shadow_state_metadata_reapplied' "$installer" || return 1
    grep -Fq 'shadow_sentinel_retained' "$installer" || return 1
}
test_tmpfiles_lifecycle() {
    local lifecycle_root=$1

    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 0
    mkdir -p "$lifecycle_root/etc/tmpfiles.d" "$lifecycle_root/run"
    /bin/bash "$installer" --render-shadow-config 1000 1000 1001 \
        >"$lifecycle_root/etc/tmpfiles.d/caddy-ha.conf"
    systemd-tmpfiles --root="$lifecycle_root" --create caddy-ha.conf
    [[ "$(stat -c '%u:%g:%a' "$lifecycle_root/run/caddy-ha")" = 1000:1001:750 ]] || return 1
    [[ "$(stat -c '%u:%g:%a' "$lifecycle_root/run/caddy-ha-notify")" = 1000:1000:700 ]] || return 1
    printf 'retained\n' >"$lifecycle_root/run/caddy-ha/sentinel"
    chmod 0777 "$lifecycle_root/run/caddy-ha"
    systemd-tmpfiles --root="$lifecycle_root" --create caddy-ha.conf
    [[ "$(stat -c '%u:%g:%a' "$lifecycle_root/run/caddy-ha")" = 1000:1001:750 ]] || return 1
    grep -Fxq retained "$lifecycle_root/run/caddy-ha/sentinel"
}
write_fake_ssh() {
    local fake_path=$1

    cp "$runner" "$fake_path.runner"
    sed -i "s#/usr/bin/ssh#$fake_path#g" "$fake_path.runner"
    # The quoted lines are source for the generated fake, not parent expansion.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >/dev/null' \
        'printf "%s\n" "$*" >>"$ACTION20ER_CALL_LOG"' \
        'if [[ "$*" == *"--rollback"* ]]; then' \
        '    while IFS= read -r label; do printf "action_20e_retry_node_check_%s=true\n" "$label"; done <"$ACTION20ER_ROLLBACK_LABELS"' \
        '    printf "action_20e_retry_node_rollback_complete=true\n"' \
        '    exit 0' \
        'fi' \
        'role=node-b' \
        '[[ "$*" == *"node-a"* ]] && role=node-a' \
        'if [[ "${ACTION20ER_FAIL_NODE_A:-0}" = 1 && "$role" = node-a ]]; then' \
        '    printf "action_20e_retry_node_check_identity_root=false\n"' \
        '    exit 1' \
        'fi' \
        'while IFS= read -r label; do' \
        '    [[ "${ACTION20ER_OMIT_LABEL:-}" = "$label" ]] && continue' \
        '    printf "action_20e_retry_node_check_%s=true\n" "$label"' \
        'done <"$ACTION20ER_LABELS"' \
        'printf "action_20e_retry_node_backup_path=/var/backups/caddy-ha/action20e-%s-runtime-directories.ABC123\n" "$role"' \
        'printf "%s\n" action_20e_retry_node_keepalived_mutated=false action_20e_retry_node_service_mutations=false action_20e_retry_node_vrrp_mutated=false action_20e_retry_node_vip_mutated=false action_20e_retry_node_notifier_invoked=false action_20e_retry_node_install_complete=true' \
        >"$fake_path"
    chmod 0755 "$fake_path" "$fake_path.runner"
}
test_intercepted_runner() {
    local intercept_root=$1
    local copied_root=$intercept_root/repository/Caddy
    local fake_ssh=$intercept_root/fake-ssh
    local status_value

    mkdir -p "$copied_root/scripts" "$copied_root/configs/tmpfiles.d"
    cp "$installer" "$runner" "$copied_root/scripts/"
    cp "$config" "$copied_root/configs/tmpfiles.d/"
    chmod 0755 "$copied_root/scripts/"*.sh
    chmod 0644 "$copied_root/configs/tmpfiles.d/caddy-ha.conf"
    write_fake_ssh "$fake_ssh"
    mv "$fake_ssh.runner" "$copied_root/scripts/$(basename "$runner")"
    /bin/bash "$installer" --expected-checks >"$intercept_root/labels"
    /bin/bash "$installer" --expected-rollback-checks >"$intercept_root/rollback-labels"
    : >"$intercept_root/calls"
    export ACTION20ER_CALL_LOG=$intercept_root/calls
    export ACTION20ER_LABELS=$intercept_root/labels
    export ACTION20ER_ROLLBACK_LABELS=$intercept_root/rollback-labels
    /bin/bash "$copied_root/scripts/$(basename "$runner")" \
        >"$intercept_root/success.out"
    grep -Fxq 'action_20e_retry_transaction_complete=true' "$intercept_root/success.out"
    [[ "$(wc -l <"$intercept_root/calls")" -eq 2 ]]
    : >"$intercept_root/calls"
    status_value=0
    ACTION20ER_FAIL_NODE_A=1 \
        /bin/bash "$copied_root/scripts/$(basename "$runner")" \
        >"$intercept_root/failure.out" 2>"$intercept_root/failure.err" || status_value=$?
    [[ "$status_value" -eq 1 ]]
    [[ "$(wc -l <"$intercept_root/calls")" -eq 3 ]]
    grep -Fxq 'action_20e_retry_node_b_rollback_accepted=true' "$intercept_root/failure.out"
    : >"$intercept_root/calls"
    status_value=0
    ACTION20ER_OMIT_LABEL=identity_root \
        /bin/bash "$copied_root/scripts/$(basename "$runner")" \
        >"$intercept_root/missing.out" 2>"$intercept_root/missing.err" || status_value=$?
    [[ "$status_value" -eq 1 ]]
    [[ "$(wc -l <"$intercept_root/calls")" -eq 1 ]]
    grep -Fxq 'action_20e_retry_node_a_contacted=false' "$intercept_root/missing.out"
}
write_fake_acceptance_ssh() {
    local fake_path=$1

    # The quoted lines are source for the generated fake, not parent expansion.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >/dev/null' \
        'printf "%s\n" "$*" >>"$ACTION20ERA_CALL_LOG"' \
        'while IFS= read -r label; do' \
        '    [[ "${ACTION20ERA_OMIT_LABEL:-}" = "$label" ]] && continue' \
        '    printf "action_20e_retry_a_probe_assertion_%s=true\n" "$label"' \
        'done <"$ACTION20ERA_LABELS"' \
        'printf "%s\n" action_20e_retry_a_probe_persistent_mutations=false action_20e_retry_a_probe_inspection_complete=true' \
        >"$fake_path"
    chmod 0755 "$fake_path"
}
test_intercepted_acceptance() {
    local acceptance_root=$1
    local copied_root=$acceptance_root/acceptance/Caddy
    local fake_ssh=$acceptance_root/fake-acceptance-ssh
    local copied_runner
    local status_value

    mkdir -p "$copied_root/scripts"
    cp "$inspector" "$acceptance_runner" "$copied_root/scripts/"
    chmod 0755 "$copied_root/scripts/"*.sh
    copied_runner=$copied_root/scripts/$(basename "$acceptance_runner")
    write_fake_acceptance_ssh "$fake_ssh"
    sed -i "s#/usr/bin/ssh#$fake_ssh#g" "$copied_runner"
    /bin/bash "$inspector" --expected-assertions >"$acceptance_root/acceptance-labels"
    : >"$acceptance_root/acceptance-calls"
    export ACTION20ERA_CALL_LOG=$acceptance_root/acceptance-calls
    export ACTION20ERA_LABELS=$acceptance_root/acceptance-labels
    /bin/bash "$copied_runner" >"$acceptance_root/acceptance-success.out"
    grep -Fxq 'action_20e_retry_a_acceptance_complete=true' "$acceptance_root/acceptance-success.out"
    [[ "$(wc -l <"$acceptance_root/acceptance-calls")" -eq 2 ]]
    : >"$acceptance_root/acceptance-calls"
    status_value=0
    ACTION20ERA_OMIT_LABEL=identity_root /bin/bash "$copied_runner" \
        >"$acceptance_root/acceptance-missing.out" 2>"$acceptance_root/acceptance-missing.err" || status_value=$?
    [[ "$status_value" -eq 1 ]]
    [[ "$(wc -l <"$acceptance_root/acceptance-calls")" -eq 1 ]]
    grep -Fxq 'action_20e_retry_a_node_b_accepted=false' "$acceptance_root/acceptance-missing.err"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf 'action_20e_retry_regression_self_test_complete=true\n'
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

verify_sources
test_root=$(mktemp -d /tmp/caddy-action20e-retry-regression.XXXXXX)
readonly test_root
trap 'rm -rf -- "$test_root"' EXIT
test_tmpfiles_lifecycle "$test_root/root"
test_intercepted_runner "$test_root"
test_intercepted_acceptance "$test_root"
printf 'action_20e_retry_regression_complete=true\n'
