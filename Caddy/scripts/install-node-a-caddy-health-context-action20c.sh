#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20c
readonly health_target=/usr/local/libexec/check-caddy.sh
readonly keepalived_main=/etc/keepalived/keepalived.conf
readonly environment_file=/etc/default/caddy-ha
readonly rollback_root=/var/backups/caddy-ha
readonly active_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly expected_fragment_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS
readonly expected_old_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_candidate_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_baseline_sha256=bc1f5fc7dc9de385ba00e8f9868df6857306cc4268de6a899a73ccc7098c1ceb

stage_directory=
rollback_directory=
install_stage=
candidate_execution_stage=
mutation_started=false
transaction_complete=false
keepalived_main_before=
keepalived_tree_before=
current_target_before=
caddy_pid_before=
keepalived_pid_before=
lighttpd_pid_before=
fragment_backup_tree_before=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
tree_digest() {
    local digest_root=$1

    (
        cd "$digest_root"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
address_count() {
    local counted_address=$1

    ip -o address show | awk -v address="$counted_address" \
        '$4 == address { count++ } END { print count + 0 }'
}
require_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_a architecture_arm64 \
        stage_directory_regular stage_directory_not_symlink stage_directory_metadata \
        stage_candidate_regular stage_candidate_not_symlink stage_candidate_metadata \
        stage_candidate_hash_exact stage_candidate_syntax \
        stage_baseline_regular stage_baseline_not_symlink stage_baseline_metadata \
        stage_baseline_hash_exact stage_baseline_syntax \
        baseline_status_zero baseline_stderr_empty baseline_assertion_count_exact \
        baseline_assertion_labels_unique baseline_false_assertions_absent \
        baseline_role_node_a baseline_state_unchanged \
        baseline_persistent_mutations_false health_target_regular \
        health_target_not_symlink health_target_metadata health_target_old_hash_exact \
        fragment_regular fragment_not_symlink fragment_metadata fragment_hash_exact \
        fragment_backup_directory_regular fragment_backup_directory_not_symlink \
        fragment_backup_directory_metadata fragment_backup_manifest_regular \
        fragment_backup_manifest_not_symlink fragment_backup_manifest_metadata \
        fragment_backup_manifest_exact \
        environment_file_regular environment_file_not_symlink \
        keepalived_member_of_caddy_tls keepalived_caddy_tls_group_exact \
        active_release_exact active_fullchain_readable active_private_key_readable \
        tmp_parent_writable candidate_execution_stage_metadata candidate_execution_success \
        candidate_transient_residue_absent rollback_root_regular \
        rollback_root_not_symlink rollback_root_metadata prior_backup_absent \
        prior_install_stage_absent live_health_regular live_health_not_symlink \
        live_health_metadata live_health_candidate_hash_exact live_health_syntax \
        installed_helper_execution_success installed_helper_transient_residue_absent \
        backup_directory_regular backup_directory_not_symlink backup_directory_metadata \
        backup_helper_hash_exact backup_manifest_exact keepalived_main_hash_unchanged \
        keepalived_tree_hash_unchanged fragment_backup_tree_hash_unchanged \
        current_target_unchanged caddy_pid_unchanged \
        keepalived_pid_unchanged lighttpd_pid_unchanged caddy_ipv4_vip_absent \
        caddy_ipv6_vip_absent
}
validate_source() {
    local expected_hash=$1
    local source_label=$2
    local source_path=$3

    require_check "stage_${source_label}_regular" test -f "$source_path" || return 1
    require_check "stage_${source_label}_not_symlink" test ! -L "$source_path" || return 1
    require_check "stage_${source_label}_metadata" test \
        "$(stat -c '%U:%G:%a' "$source_path")" = root:root:700 || return 1
    require_check "stage_${source_label}_hash_exact" test \
        "$(file_hash "$source_path")" = "$expected_hash" || return 1
    require_check "stage_${source_label}_syntax" /bin/bash -n "$source_path" || return 1
}
validate_baseline() {
    local baseline_stderr=$stage_directory/baseline.stderr
    local baseline_stdout=$stage_directory/baseline.stdout
    local baseline_status=0
    local assertion_count
    local unique_count

    : >"$baseline_stdout"
    : >"$baseline_stderr"
    chmod 0600 "$baseline_stdout" "$baseline_stderr"
    /bin/bash "$stage_directory/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh" \
        --node node-a >"$baseline_stdout" 2>"$baseline_stderr" || baseline_status=$?
    require_check baseline_status_zero test "$baseline_status" -eq 0 || return 1
    require_check baseline_stderr_empty test ! -s "$baseline_stderr" || return 1
    assertion_count=$(grep -Ec '^action_20a_b_probe_assertion_[a-z0-9_]+=true$' \
        "$baseline_stdout" || true)
    unique_count=$(sed -n \
        's/^\(action_20a_b_probe_assertion_[a-z0-9_]*\)=true$/\1/p' \
        "$baseline_stdout" | LC_ALL=C sort -u | wc -l)
    require_check baseline_assertion_count_exact test "$assertion_count" -eq 79 || return 1
    require_check baseline_assertion_labels_unique test "$unique_count" -eq 79 || return 1
    require_check baseline_false_assertions_absent test \
        "$(grep -Ec '^action_20a_b_probe_assertion_[a-z0-9_]+=false$' \
            "$baseline_stdout" || true)" -eq 0 || return 1
    require_check baseline_role_node_a grep -Fxq \
        'action_20a_b_probe_value_node_role=node-a' "$baseline_stdout" || return 1
    require_check baseline_state_unchanged grep -Fxq \
        'action_20a_b_probe_assertion_state_unchanged=true' "$baseline_stdout" || return 1
    require_check baseline_persistent_mutations_false grep -Fxq \
        'action_20a_b_probe_persistent_mutations=false' "$baseline_stdout" || return 1
}
validate_prestate() {
    require_check identity_root test "$(id -u)" -eq 0 || return 1
    require_check working_directory_root test "$(pwd -P)" = / || return 1
    require_check hostname_node_a test "$(hostname)" = j1-svpihole0 || return 1
    require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64 || return 1
    require_check stage_directory_regular test -d "$stage_directory" || return 1
    require_check stage_directory_not_symlink test ! -L "$stage_directory" || return 1
    require_check stage_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 || return 1
    validate_source "$expected_candidate_sha256" candidate \
        "$stage_directory/check-caddy-action20b.sh" || return 1
    validate_source "$expected_baseline_sha256" baseline \
        "$stage_directory/inspect-dual-node-caddy-postfailure-continuity-action20a-b.sh" || return 1
    validate_baseline || return 1
    require_check health_target_regular test -f "$health_target" || return 1
    require_check health_target_not_symlink test ! -L "$health_target" || return 1
    require_check health_target_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    require_check health_target_old_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_old_health_sha256" || return 1
    require_check fragment_regular test -f "$fragment" || return 1
    require_check fragment_not_symlink test ! -L "$fragment" || return 1
    require_check fragment_metadata test \
        "$(stat -c '%U:%G:%a' "$fragment")" = root:root:644 || return 1
    require_check fragment_hash_exact test \
        "$(file_hash "$fragment")" = "$expected_fragment_sha256" || return 1
    require_check fragment_backup_directory_regular test -d \
        "$expected_fragment_backup_path" || return 1
    require_check fragment_backup_directory_not_symlink test ! -L \
        "$expected_fragment_backup_path" || return 1
    require_check fragment_backup_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$expected_fragment_backup_path")" = root:root:700 || return 1
    require_check fragment_backup_manifest_regular test -f \
        "$expected_fragment_backup_path/manifest" || return 1
    require_check fragment_backup_manifest_not_symlink test ! -L \
        "$expected_fragment_backup_path/manifest" || return 1
    require_check fragment_backup_manifest_metadata test \
        "$(stat -c '%U:%G:%a' "$expected_fragment_backup_path/manifest")" = root:root:600 || return 1
    # The positional parameters are intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    require_check fragment_backup_manifest_exact /bin/bash -c \
        'manifest=$1; main_hash=$2; fragment_hash=$3; [[ $(awk '\''END { print NR }'\'' "$manifest") -eq 6 ]] && grep -Fxq action=action19e "$manifest" && grep -Fxq node=node-a "$manifest" && grep -Fxq fragment_pre_state=absent "$manifest" && grep -Eq '\''^fragment_directory_preexisting=(true|false)$'\'' "$manifest" && grep -Fxq "main_configuration_sha256=$main_hash" "$manifest" && grep -Fxq "fragment_candidate_sha256=$fragment_hash" "$manifest"' \
        _ "$expected_fragment_backup_path/manifest" \
        "$(file_hash "$keepalived_main")" "$expected_fragment_sha256" || return 1
    require_check environment_file_regular test -f "$environment_file" || return 1
    require_check environment_file_not_symlink test ! -L "$environment_file" || return 1
    require_check keepalived_member_of_caddy_tls id -nG keepalived_script || return 1
    require_check keepalived_caddy_tls_group_exact /bin/bash -c \
        'id -nG keepalived_script | tr " " "\n" | grep -Fxq caddy-tls' || return 1
    current_target_before=$(readlink -e /etc/caddy/current) || return 1
    require_check active_release_exact test "$current_target_before" = "$active_release" || return 1
    require_check active_fullchain_readable runuser -u keepalived_script -- \
        test -r "$current_target_before/tls/fullchain.pem" || return 1
    require_check active_private_key_readable runuser -u keepalived_script -- \
        test -r "$current_target_before/tls/privkey.pem" || return 1
    require_check tmp_parent_writable runuser -u keepalived_script -- test -w /tmp || return 1
    candidate_execution_stage=$(mktemp /tmp/.check-caddy.action20c-validate.XXXXXX) ||
        return 1
    install -o root -g caddy-tls -m 0750 \
        "$stage_directory/check-caddy-action20b.sh" \
        "$candidate_execution_stage" || return 1
    require_check candidate_execution_stage_metadata test \
        "$(stat -c '%U:%G:%a' "$candidate_execution_stage")" = root:caddy-tls:750 ||
        return 1
    require_check candidate_execution_success runuser -u keepalived_script -- \
        "$candidate_execution_stage" || return 1
    rm -f -- "$candidate_execution_stage" || return 1
    candidate_execution_stage=
    require_check candidate_transient_residue_absent /bin/bash -c \
        '! find /tmp -mindepth 1 -maxdepth 1 \( -name '\''caddy-health.*'\'' -o -name '\''.check-caddy.action20c-validate.*'\'' \) -print -quit | grep -q .' ||
        return 1
    require_check rollback_root_regular test -d "$rollback_root" || return 1
    require_check rollback_root_not_symlink test ! -L "$rollback_root" || return 1
    require_check rollback_root_metadata test \
        "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700 || return 1
    require_check prior_backup_absent test -z \
        "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action20c-node-a-health-context.*' -print -quit)" || return 1
    require_check prior_install_stage_absent test -z \
        "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action20c.*' -print -quit)" || return 1
    keepalived_main_before=$(file_hash "$keepalived_main") || return 1
    keepalived_tree_before=$(tree_digest /etc/keepalived) || return 1
    caddy_pid_before=$(systemctl show caddy.service --property=MainPID --value) || return 1
    keepalived_pid_before=$(systemctl show keepalived.service --property=MainPID --value) || return 1
    lighttpd_pid_before=$(systemctl show lighttpd.service --property=MainPID --value) || return 1
    fragment_backup_tree_before=$(tree_digest "$expected_fragment_backup_path") || return 1
}
validate_backup() {
    require_check backup_directory_regular test -d "$rollback_directory" || return 1
    require_check backup_directory_not_symlink test ! -L "$rollback_directory" || return 1
    require_check backup_directory_metadata test \
        "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700 || return 1
    require_check backup_helper_hash_exact test \
        "$(file_hash "$rollback_directory/check-caddy.sh")" = \
        "$expected_old_health_sha256" || return 1
    require_check backup_manifest_exact grep -Fxq \
        "candidate_sha256=$expected_candidate_sha256" "$rollback_directory/manifest" || return 1
}
validate_poststate() {
    require_check live_health_regular test -f "$health_target" || return 1
    require_check live_health_not_symlink test ! -L "$health_target" || return 1
    require_check live_health_metadata test \
        "$(stat -c '%U:%G:%a' "$health_target")" = root:root:755 || return 1
    require_check live_health_candidate_hash_exact test \
        "$(file_hash "$health_target")" = "$expected_candidate_sha256" || return 1
    require_check live_health_syntax /bin/bash -n "$health_target" || return 1
    require_check installed_helper_execution_success runuser -u keepalived_script -- \
        "$health_target" || return 1
    require_check installed_helper_transient_residue_absent test -z \
        "$(find /tmp -mindepth 1 -maxdepth 1 -name 'caddy-health.*' -print -quit)" || return 1
    validate_backup || return 1
    require_check keepalived_main_hash_unchanged test \
        "$(file_hash "$keepalived_main")" = "$keepalived_main_before" || return 1
    require_check keepalived_tree_hash_unchanged test \
        "$(tree_digest /etc/keepalived)" = "$keepalived_tree_before" || return 1
    require_check fragment_backup_tree_hash_unchanged test \
        "$(tree_digest "$expected_fragment_backup_path")" = \
        "$fragment_backup_tree_before" || return 1
    require_check current_target_unchanged test \
        "$(readlink -e /etc/caddy/current)" = "$current_target_before" || return 1
    require_check caddy_pid_unchanged test \
        "$(systemctl show caddy.service --property=MainPID --value)" = "$caddy_pid_before" || return 1
    require_check keepalived_pid_unchanged test \
        "$(systemctl show keepalived.service --property=MainPID --value)" = "$keepalived_pid_before" || return 1
    require_check lighttpd_pid_unchanged test \
        "$(systemctl show lighttpd.service --property=MainPID --value)" = "$lighttpd_pid_before" || return 1
    require_check caddy_ipv4_vip_absent test "$(address_count 10.1.0.56/22)" -eq 0 || return 1
    require_check caddy_ipv6_vip_absent test \
        "$(address_count fd36:5aa8:6971:1::56/128)" -eq 0 || return 1
}
rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - ERR INT TERM EXIT
    if [[ -n "$candidate_execution_stage" ]]; then
        rm -f -- "$candidate_execution_stage" || rollback_failed=true
    fi
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    [[ -z "$install_stage" ]] || rm -f -- "$install_stage" || rollback_failed=true
    if [[ -n "$rollback_directory" && -f "$rollback_directory/check-caddy.sh" ]]; then
        install -o root -g root -m 0755 "$rollback_directory/check-caddy.sh" \
            "$health_target" || rollback_failed=true
    else
        rollback_failed=true
    fi
    [[ "$(file_hash "$health_target")" = "$expected_old_health_sha256" ]] || rollback_failed=true
    [[ "$(file_hash "$keepalived_main")" = "$keepalived_main_before" ]] || rollback_failed=true
    [[ "$(tree_digest /etc/keepalived)" = "$keepalived_tree_before" ]] || rollback_failed=true
    [[ "$(tree_digest "$expected_fragment_backup_path")" = "$fragment_backup_tree_before" ]] || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$original_status"
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --expected-check-count)
        [[ $# -eq 1 ]] || exit 64
        expected_checks | wc -l
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$expected_candidate_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_baseline_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    *)
        printf 'Usage: %s --expected-checks|--expected-check-count|--self-test|--stage DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

trap rollback ERR INT TERM EXIT
validate_prestate
printf '%s_preflight_complete=true\n' "$prefix"

mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
rollback_directory=$(mktemp -d "$rollback_root/action20c-node-a-health-context.XXXXXX")
chmod 0700 "$rollback_directory"
install -o root -g root -m 0600 "$health_target" \
    "$rollback_directory/check-caddy.sh"
printf '%s\n' \
    'action=action20c' \
    'node=node-a' \
    "old_health_sha256=$expected_old_health_sha256" \
    "candidate_sha256=$expected_candidate_sha256" \
    >"$rollback_directory/manifest"
chmod 0600 "$rollback_directory/manifest"

install_stage=$(mktemp /usr/local/libexec/.check-caddy.action20c.XXXXXX)
install -o root -g root -m 0755 "$stage_directory/check-caddy-action20b.sh" \
    "$install_stage"
mv -- "$install_stage" "$health_target"
install_stage=

validate_poststate
transaction_complete=true
trap - ERR INT TERM EXIT
printf '%s_helper_invoked_for_validation=true\n' "$prefix"
printf '%s_fragment_mutated=false\n' "$prefix"
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_persistent_mutation_scope=health_helper,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
