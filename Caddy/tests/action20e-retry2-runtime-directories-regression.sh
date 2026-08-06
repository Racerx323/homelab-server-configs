#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly config=$caddy_root/configs/tmpfiles.d/caddy-ha.conf
readonly installer=$caddy_root/scripts/install-caddy-runtime-directories-action20e-retry2.sh
readonly runner=$caddy_root/scripts/run-dual-node-caddy-runtime-directories-action20e-retry2.sh
readonly collision=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$test_directory/conditional-validator-errexit-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_one() {
    local expected_line=$1
    local inspected_path=$2

    [[ "$(grep -Fxc "$expected_line" "$inspected_path")" -eq 1 ]]
}
verify_sources() {
    [[ -f "$config" && ! -L "$config" ]] || return 1
    [[ -f "$installer" && ! -L "$installer" && -x "$installer" ]] || return 1
    [[ -f "$runner" && ! -L "$runner" && -x "$runner" ]] || return 1
    [[ "$(stat -c '%a' "$config")" = 644 ]] || return 1
    /bin/bash -n "$installer" "$runner" || return 1
    shellcheck "$installer" "$runner" || return 1
    /bin/bash "$collision" "$0" "$installer" "$runner" >/dev/null || return 1
    /bin/bash "$conditional" >/dev/null || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    /bin/bash "$runner" --self-test >/dev/null || return 1
    [[ "$(file_hash "$config")" = "$(/bin/bash "$installer" --render-config | sha256sum | awk '{ print $1 }')" ]] || return 1
    [[ "$(/bin/bash "$installer" --expected-checks | wc -l)" -eq 101 ]] || return 1
    [[ "$(/bin/bash "$installer" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 101 ]] || return 1
    /bin/bash "$installer" --expected-checks | grep -Fxq tmpfiles_parent_regular || return 1
    /bin/bash "$installer" --expected-checks | grep -Fxq tmpfiles_parent_not_symlink || return 1
    /bin/bash "$installer" --expected-checks | grep -Fxq tmpfiles_parent_owner_exact || return 1
    ! grep -Fq -- '--dry-run' "$installer" || return 1
}
test_layout_production_function() {
    local layout_root=$1
    local layout_stdout=$2
    local current_identity

    current_identity=$(id -un):$(id -gn)
    mkdir -m 0700 "$layout_root"
    /bin/bash "$installer" --shadow-layout-test "$layout_root" >"$layout_stdout"
    require_one "action_20e_retry2_node_layout_test_root=${current_identity}:700" "$layout_stdout"
    require_one "action_20e_retry2_node_layout_test_etc=${current_identity}:700" "$layout_stdout"
    require_one "action_20e_retry2_node_layout_test_tmpfiles=${current_identity}:700" "$layout_stdout"
    [[ "$(stat -c '%a' "$layout_root/shadow-root")" = 700 ]]
    [[ "$(stat -c '%a' "$layout_root/shadow-root/etc")" = 700 ]]
    [[ "$(stat -c '%a' "$layout_root/shadow-root/etc/tmpfiles.d")" = 700 ]]
}
test_layout_rejects_nonempty_root() {
    local invalid_root=$1
    local invalid_status

    mkdir -m 0700 "$invalid_root"
    : >"$invalid_root/preexisting"
    invalid_status=0
    /bin/bash "$installer" --shadow-layout-test "$invalid_root" \
        >/dev/null 2>&1 || invalid_status=$?
    [[ "$invalid_status" -eq 64 ]]
}
verify_production_order() {
    local etc_check_line
    local etc_create_line
    local root_check_line
    local root_create_line
    local tmpfiles_check_line
    local tmpfiles_create_line

    # Match literal production source, not parent-shell expansion.
    # shellcheck disable=SC2016
    root_create_line=$(grep -nF 'create_secure_directory root root "$shadow_root"' "$installer" | tail -1 | cut -d: -f1)
    root_check_line=$(grep -nF 'run_check shadow_root_metadata_exact' "$installer" | cut -d: -f1)
    # shellcheck disable=SC2016
    etc_create_line=$(grep -nF 'create_secure_directory root root "$shadow_root/etc"' "$installer" | cut -d: -f1)
    etc_check_line=$(grep -nF 'run_check shadow_etc_metadata_exact' "$installer" | cut -d: -f1)
    # shellcheck disable=SC2016
    tmpfiles_create_line=$(grep -nF 'create_secure_directory root root "$shadow_root/etc/tmpfiles.d"' "$installer" | cut -d: -f1)
    tmpfiles_check_line=$(grep -nF 'run_check shadow_tmpfiles_metadata_exact' "$installer" | cut -d: -f1)
    [[ "$root_create_line" -lt "$root_check_line" ]]
    [[ "$root_check_line" -lt "$etc_create_line" ]]
    [[ "$etc_create_line" -lt "$etc_check_line" ]]
    [[ "$etc_check_line" -lt "$tmpfiles_create_line" ]]
    [[ "$tmpfiles_create_line" -lt "$tmpfiles_check_line" ]]
}
write_fake_ssh() {
    local fake_path=$1

    cp "$runner" "$fake_path.runner"
    sed -i "s#/usr/bin/ssh#$fake_path#g" "$fake_path.runner"
    # The quoted lines are generated fixture source.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >/dev/null' \
        'printf "%s\n" "$*" >>"$ACTION20ER2_CALL_LOG"' \
        'if [[ "$*" == *"--rollback"* ]]; then' \
        '    while IFS= read -r label; do printf "action_20e_retry2_node_check_%s=true\n" "$label"; done <"$ACTION20ER2_ROLLBACK_LABELS"' \
        '    printf "action_20e_retry2_node_rollback_complete=true\n"' \
        '    exit 0' \
        'fi' \
        'role=node-b' \
        '[[ "$*" == *"node-a"* ]] && role=node-a' \
        'if [[ "${ACTION20ER2_FAIL_NODE_A:-0}" = 1 && "$role" = node-a ]]; then' \
        '    printf "action_20e_retry2_node_check_identity_root=false\n"' \
        '    exit 1' \
        'fi' \
        'while IFS= read -r label; do' \
        '    [[ "${ACTION20ER2_OMIT_LABEL:-}" = "$label" ]] && continue' \
        '    printf "action_20e_retry2_node_check_%s=true\n" "$label"' \
        'done <"$ACTION20ER2_LABELS"' \
        'printf "action_20e_retry2_node_backup_path=/var/backups/caddy-ha/action20e-%s-runtime-directories.ABC123\n" "$role"' \
        'printf "%s\n" action_20e_retry2_node_keepalived_mutated=false action_20e_retry2_node_service_mutations=false action_20e_retry2_node_vrrp_mutated=false action_20e_retry2_node_vip_mutated=false action_20e_retry2_node_notifier_invoked=false action_20e_retry2_node_install_complete=true' \
        >"$fake_path"
    chmod 0755 "$fake_path" "$fake_path.runner"
}
test_intercepted_runner() {
    local copied_root=$1/repository/Caddy
    local fake_ssh=$1/fake-ssh
    local status_value

    mkdir -p "$copied_root/scripts" "$copied_root/configs/tmpfiles.d"
    cp "$installer" "$runner" "$copied_root/scripts/"
    cp "$config" "$copied_root/configs/tmpfiles.d/"
    chmod 0755 "$copied_root/scripts/"*.sh
    chmod 0644 "$copied_root/configs/tmpfiles.d/caddy-ha.conf"
    write_fake_ssh "$fake_ssh"
    mv "$fake_ssh.runner" "$copied_root/scripts/$(basename "$runner")"
    /bin/bash "$installer" --expected-checks >"$1/labels"
    /bin/bash "$installer" --expected-rollback-checks >"$1/rollback-labels"
    : >"$1/calls"
    export ACTION20ER2_CALL_LOG=$1/calls
    export ACTION20ER2_LABELS=$1/labels
    export ACTION20ER2_ROLLBACK_LABELS=$1/rollback-labels
    /bin/bash "$copied_root/scripts/$(basename "$runner")" >"$1/success.out"
    require_one 'action_20e_retry2_transaction_complete=true' "$1/success.out"
    require_one 'action_20e_retry2_vrrp_mutated=false' "$1/success.out"
    [[ "$(wc -l <"$1/calls")" -eq 2 ]]
    : >"$1/calls"
    status_value=0
    ACTION20ER2_FAIL_NODE_A=1 /bin/bash "$copied_root/scripts/$(basename "$runner")" \
        >"$1/failure.out" 2>"$1/failure.err" || status_value=$?
    [[ "$status_value" -eq 1 ]]
    [[ "$(wc -l <"$1/calls")" -eq 3 ]]
    require_one 'action_20e_retry2_node_b_rollback_accepted=true' "$1/failure.out"
    : >"$1/calls"
    status_value=0
    ACTION20ER2_OMIT_LABEL=shadow_root_metadata_exact \
        /bin/bash "$copied_root/scripts/$(basename "$runner")" \
        >"$1/missing.out" 2>"$1/missing.err" || status_value=$?
    [[ "$status_value" -eq 1 ]]
    [[ "$(wc -l <"$1/calls")" -eq 1 ]]
    require_one 'action_20e_retry2_node_a_contacted=false' "$1/missing.out"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf 'action_20e_retry2_regression_self_test_complete=true\n'
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

verify_sources
regression_root=$(mktemp -d /tmp/caddy-action20e-retry2-regression.XXXXXX)
readonly regression_root
regression_layout_root=$(mktemp -d /tmp/caddy-action20e-retry2-layout.XXXXXX)
readonly regression_layout_root
invalid_layout_root=$(mktemp -d /tmp/caddy-action20e-retry2-layout.XXXXXX)
readonly invalid_layout_root
rm -d -- "$regression_layout_root" "$invalid_layout_root"
trap 'rm -rf -- "$regression_root" "$regression_layout_root" "$invalid_layout_root"' EXIT
test_layout_production_function "$regression_layout_root" "$regression_root/layout.out"
test_layout_rejects_nonempty_root "$invalid_layout_root"
verify_production_order
test_intercepted_runner "$regression_root"
printf 'action_20e_retry2_regression_complete=true\n'
