#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_builder
readonly source_transaction_sha256=ac8a71333493c28735603bcc9ad74d8dbd4802a2b1b425b4bf4f1c40ce6c04d6
readonly source_runner_sha256=30c297807ed7f0fb48e41c5c653f3c4168b2aa5a05053162c9ece58ef87a88d4
readonly collision_checker_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly accepted_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly accepted_fragment_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270
readonly accepted_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_transaction=$script_directory/activate-node-a-caddy-vrrp-action20d-retry10.sh
readonly source_runner=$script_directory/run-node-a-caddy-vrrp-activation-action20d-retry10.sh
readonly collision_checker=${script_directory%/scripts}/tests/check-shell-readonly-local-collisions-v2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20j_builder_label" >&2
    return 1
}
render_transaction() {
    local action20j_builder_input=$1
    local action20j_builder_output=$2
    local action20j_builder_common=$3

    sed \
        -e 's/action_20d_retry10/action_20j/g' \
        -e 's/action20d-retry10/action20j/g' \
        -e 's/action=20d-retry10/action=20j/g' \
        -e "s/9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab/$accepted_health_sha256/g" \
        -e "s/294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d/$accepted_fragment_sha256/g" \
        -e "s/expected_health_user_line='    user keepalived_script'/expected_health_user_line='    user keepalived_script caddy-tls'/" \
        -e "s/grep -Fxc '    priority 140'/grep -Fxc '    priority 100'/" \
        -e "s/grep -Fxc '    unicast_src_ip 10\.1\.0\.53'/grep -Fxc '    unicast_src_ip 10.1.0.54'/" \
        -e "s/grep -Fxc '        10\.1\.0\.54 min_ttl 255 max_ttl 255'/grep -Fxc '        10.1.0.53 min_ttl 255 max_ttl 255'/" \
        -e "s/grep -Fxc '    unicast_src_ip fd36:5aa8:6971:1::53'/grep -Fxc '    unicast_src_ip fd36:5aa8:6971:1::54'/" \
        -e "s/grep -Fxc '        fd36:5aa8:6971:1::54 min_ttl 255 max_ttl 255'/grep -Fxc '        fd36:5aa8:6971:1::53 min_ttl 255 max_ttl 255'/" \
        -e 's/action20d-retry10-node-a-caddy-vrrp/action20j-node-b-caddy-vrrp/g' \
        "$action20j_builder_input" >"$action20j_builder_common"

    awk -v environment_hash="$accepted_environment_sha256" '
        /^readonly notification_helper_sha256=/ {
            print
            print "readonly environment_file=/etc/default/caddy-ha"
            print "readonly environment_sha256=" environment_hash
            next
        }
        /include_absent keepalived_active caddy_active lighttpd_active can_reload \\/ {
            sub(/can_reload \\/, "can_reload environment_regular environment_hash \\")
            print
            print "        caddy_validation_pre validation_residue_absent_pre \\"
            next
        }
        /^configure_role\(\) \{/ {
            print "run_full_caddy_validation() ("
            print "    local action20j_validation_root"
            print "    local action20j_script_uid"
            print "    local action20j_tls_gid"
            print "    local action20j_status=0"
            print ""
            print "    action20j_script_uid=$(id -u keepalived_script) || return 1"
            print "    action20j_tls_gid=$(getent group caddy-tls | cut -d: -f3) || return 1"
            print "    action20j_validation_root=$(mktemp -d /run/caddy-action20j-validation.XXXXXX) || return 1"
            print "    trap '\''rm -rf -- \"$action20j_validation_root\"'\'' EXIT INT TERM"
            print "    chown root:\"$action20j_tls_gid\" \"$action20j_validation_root\" || return 1"
            print "    chmod 0710 \"$action20j_validation_root\" || return 1"
            print "    install -d -o \"$action20j_script_uid\" -g \"$action20j_tls_gid\" -m 0700 \"$action20j_validation_root/home\" \"$action20j_validation_root/config\" \"$action20j_validation_root/data\" || return 1"
            print "    setpriv --reuid \"$action20j_script_uid\" --regid \"$action20j_tls_gid\" --clear-groups -- env HOME=\"$action20j_validation_root/home\" XDG_CONFIG_HOME=\"$action20j_validation_root/config\" XDG_DATA_HOME=\"$action20j_validation_root/data\" /bin/bash -c '\''set -a; source /etc/default/caddy-ha; set +a; : \"${NODE_ROLE:?}\"; : \"${NODE_FQDN:?}\"; : \"${NODE_IPV4:?}\"; : \"${NODE_IPV6:?}\"; exec caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile'\'' || action20j_status=$?"
            print "    return \"$action20j_status\""
            print ")"
            print ""
            print
            next
        }
        /^        \[\[ "\$node_role" = node-a \]\] \|\| exit 64$/ {
            if (case_mode == "activate" || case_mode == "rollback") {
                print "        [[ \"$node_role\" = node-b ]] || exit 64"
            } else if (case_mode == "inspect") {
                print "        [[ \"$node_role\" = node-a || \"$node_role\" = node-b ]] || exit 64"
            } else {
                print
            }
            next
        }
        /^    --activate\)/ { case_mode = "activate"; print; next }
        /^    --inspect\)/ { case_mode = "inspect"; print; next }
        /^    --rollback\)/ { case_mode = "rollback"; print; next }
        /^    --[a-z-]+\)/ { case_mode = ""; print; next }
        /\[\[ "\$\(expected_checks \| wc -l\)" -eq 113 \]\]/ {
            sub(/113/, "117")
        }
        /\[\[ "\$\(expected_checks \| LC_ALL=C sort -u \| wc -l\)" -eq 113 \]\]/ {
            sub(/113/, "117")
        }
        /^record_check can_reload / {
            print
            getline
            print
            print "record_check environment_regular test -f \"$environment_file\""
            print "record_check environment_hash test \"$(file_hash \"$environment_file\")\" = \"$environment_sha256\""
            print "record_captured_check caddy_validation_pre caddy_validation_pre \"$transaction_root\" run_full_caddy_validation"
            print "record_check validation_residue_absent_pre test -z \"$(find /run -mindepth 1 -maxdepth 1 -name '\''caddy-action20j-validation.*'\'' -print -quit 2>/dev/null)\""
            next
        }
        { print }
    ' "$action20j_builder_common" >"$action20j_builder_output"
}
render_runner() {
    local action20j_builder_input=$1
    local action20j_builder_output=$2
    local action20j_builder_common=$3
    local action20j_builder_transaction_hash=$4

    sed \
        -e 's/action_20d_retry10/action_20j/g' \
        -e 's/action20d-retry10/action20j/g' \
        -e 's/CADDY_ACTION20D_RETRY_SSH_BINARY/CADDY_ACTION20J_SSH_BINARY/g' \
        -e 's#activate-node-a-caddy-vrrp-action20j\.sh#activate-node-b-caddy-vrrp-action20j.sh#g' \
        -e "s/$source_transaction_sha256/$action20j_builder_transaction_hash/g" \
        -e 's/node_a_backup/node_b_backup/g' \
        -e 's/node_a_activated/node_b_activated/g' \
        -e 's/invoke_remote node_a_rollback node-a/invoke_remote node_b_rollback node-b/' \
        -e 's#\$work_directory/node_a_rollback\.stdout#$work_directory/node_b_rollback.stdout#g' \
        -e 's/validate_activation node-a "\$contract_root/validate_activation node-b "$contract_root/g' \
        -e 's/action20j-node-a-caddy-vrrp/action20j-node-b-caddy-vrrp/g' \
        "$action20j_builder_input" >"$action20j_builder_common"

    awk '
        function print_success_tail() {
            print "if invoke_remote node_a_pre node-a --inspect; then"
            print "    validate_inspection node-a \"$work_directory/node_a_pre.stdout\" \"$work_directory/node_a_pre.stderr\" || exit 97"
            print "else"
            print "    exit $?"
            print "fi"
            print "if invoke_remote node_b_activate node-b --activate; then"
            print "    node_b_activated=true"
            print "    node_b_backup=$(extract_backup \"$work_directory/node_b_activate.stdout\") || exit 97"
            print "    validate_activation node-b \"$work_directory/node_b_activate.stdout\" \"$work_directory/node_b_activate.stderr\" || exit 97"
            print "else"
            print "    exit $?"
            print "fi"
            print "invoke_remote node_b_post node-b --inspect"
            print "validate_inspection node-b \"$work_directory/node_b_post.stdout\" \"$work_directory/node_b_post.stderr\""
            print "invoke_remote node_a_post node-a --inspect"
            print "validate_inspection node-a \"$work_directory/node_a_post.stdout\" \"$work_directory/node_a_post.stderr\""
            print "printf '\''%s_check_single_ipv4_owner_node_a=true\\n'\'' \"$prefix\""
            print "printf '\''%s_check_single_ipv6_owner_node_a=true\\n'\'' \"$prefix\""
            print "printf '\''%s_check_node_b_backup_state=true\\n'\'' \"$prefix\""
            print "printf '\''%s_check_dualstack_owner_node_a=true\\n'\'' \"$prefix\""
            print "printf '\''%s_check_dns_owner_unchanged_node_a=true\\n'\'' \"$prefix\""
            print "printf '\''%s_check_notification_attempt_expected=true\\n'\'' \"$prefix\""
            print "printf '\''%s_node_b_backup_path=%s\\n'\'' \"$prefix\" \"$node_b_backup\""
            print "printf '\''%s_persistent_mutation_scope=one_node_b_main_include,one_node_b_rollback_backup\\n'\'' \"$prefix\""
            print "printf '\''%s_node_a_persistent_mutations=false\\n'\'' \"$prefix\""
            print "printf '\''%s_activation_accepted=true\\n'\'' \"$prefix\""
            print "action_complete=true"
            print "rm -rf -- \"$work_directory\""
            print "trap - EXIT"
        }
        /^        node-b\) printf/ { print; next }
        /^            '\''action_20j_node_value_node_role=node-a'\''/ && contract_mode {
            sub(/node-a/, "node-b")
            print
            next
        }
        /^            '\''action_20j_node_value_vrrp_state=MASTER'\''/ && contract_mode {
            sub(/MASTER/, "BACKUP")
            print
            next
        }
        /^            '\''action_20j_node_value_caddy_ipv[46]_count=1'\''/ && contract_mode {
            sub(/=1/, "=0")
            print
            next
        }
        /action20j-node-a-caddy-vrrp\.FIXTURE/ && contract_mode {
            sub(/node-a/, "node-b")
            print
            next
        }
        /^    --contract-test\)/ { contract_mode = 1; print; next }
        /^    ""\)/ { contract_mode = 0; print; next }
        /^    if \[\[ "\$node_b_activated" = true/ { in_rollback = 1; print; next }
        in_rollback && /^    if \[\[ "\$rollback_failed" = true \]\]; then/ {
            print "    if invoke_remote node_a_rollback_continuity node-a --inspect; then"
            print "        validate_inspection node-a \"$work_directory/node_a_rollback_continuity.stdout\" \"$work_directory/node_a_rollback_continuity.stderr\" || rollback_failed=true"
            print "    else"
            print "        rollback_failed=true"
            print "    fi"
            print ""
            print
            in_rollback = 0
            next
        }
        /^if invoke_remote node_a_activate node-a --activate; then/ {
            print_success_tail()
            exit
        }
        { print }
    ' "$action20j_builder_common" >"$action20j_builder_output"
}
build() (
    local action20j_builder_output_root=$1
    local action20j_builder_transaction=$action20j_builder_output_root/scripts/activate-node-b-caddy-vrrp-action20j.sh
    local action20j_builder_runner=$action20j_builder_output_root/scripts/run-node-b-caddy-vrrp-activation-action20j.sh
    local action20j_builder_collision=$action20j_builder_output_root/tests/check-shell-readonly-local-collisions-v2.sh
    local action20j_builder_transaction_common=$action20j_builder_output_root/transaction.common
    local action20j_builder_runner_common=$action20j_builder_output_root/runner.common
    local action20j_builder_transaction_hash

    install -d -m 0700 "$action20j_builder_output_root" \
        "$action20j_builder_output_root/scripts" \
        "$action20j_builder_output_root/tests"
    record_check source_transaction_hash test \
        "$(file_hash "$source_transaction")" = "$source_transaction_sha256" || return 1
    record_check source_runner_hash test "$(file_hash "$source_runner")" = \
        "$source_runner_sha256" || return 1
    record_check collision_checker_hash test "$(file_hash "$collision_checker")" = \
        "$collision_checker_sha256" || return 1
    install -m 0755 "$collision_checker" "$action20j_builder_collision"
    render_transaction "$source_transaction" "$action20j_builder_transaction" \
        "$action20j_builder_transaction_common"
    chmod 0755 "$action20j_builder_transaction"
    action20j_builder_transaction_hash=$(file_hash "$action20j_builder_transaction")
    render_runner "$source_runner" "$action20j_builder_runner" \
        "$action20j_builder_runner_common" "$action20j_builder_transaction_hash"
    chmod 0755 "$action20j_builder_runner"
    rm -f -- "$action20j_builder_transaction_common" \
        "$action20j_builder_runner_common"

    record_check transaction_syntax /bin/bash -n "$action20j_builder_transaction" || return 1
    record_check runner_syntax /bin/bash -n "$action20j_builder_runner" || return 1
    record_check transaction_node_b_only grep -Fqx \
        '        [[ "$node_role" = node-b ]] || exit 64' \
        "$action20j_builder_transaction" || return 1
    record_check transaction_fragment_hash grep -Fqx \
        "            expected_fragment_sha256=$accepted_fragment_sha256" \
        "$action20j_builder_transaction" || return 1
    record_check transaction_health_hash grep -Fqx \
        "readonly health_helper_sha256=$accepted_health_sha256" \
        "$action20j_builder_transaction" || return 1
    record_check transaction_environment_hash grep -Fqx \
        "readonly environment_sha256=$accepted_environment_sha256" \
        "$action20j_builder_transaction" || return 1
    record_check transaction_priority grep -Fq \
        "grep -Fxc '    priority 100'" "$action20j_builder_transaction" || return 1
    record_check transaction_ipv4_source grep -Fq \
        "grep -Fxc '    unicast_src_ip 10.1.0.54'" \
        "$action20j_builder_transaction" || return 1
    record_check transaction_ipv6_source grep -Fq \
        "grep -Fxc '    unicast_src_ip fd36:5aa8:6971:1::54'" \
        "$action20j_builder_transaction" || return 1
    record_check transaction_full_validation grep -Fq \
        'exec caddy validate --config /etc/caddy/current/Caddyfile --adapter caddyfile' \
        "$action20j_builder_transaction" || return 1
    record_check transaction_direct_run_stage grep -Fq \
        'mktemp -d /run/caddy-action20j-validation.XXXXXX' \
        "$action20j_builder_transaction" || return 1
    record_check runner_node_a_pre grep -Fqx \
        'if invoke_remote node_a_pre node-a --inspect; then' \
        "$action20j_builder_runner" || return 1
    record_check runner_node_b_activation grep -Fqx \
        'if invoke_remote node_b_activate node-b --activate; then' \
        "$action20j_builder_runner" || return 1
    record_check runner_node_b_post grep -Fqx \
        'invoke_remote node_b_post node-b --inspect' \
        "$action20j_builder_runner" || return 1
    record_check runner_node_a_post grep -Fqx \
        'invoke_remote node_a_post node-a --inspect' \
        "$action20j_builder_runner" || return 1
    record_check runner_rollback_node_b grep -Fq \
        'invoke_remote node_b_rollback node-b --rollback' \
        "$action20j_builder_runner" || return 1
    record_check runner_rollback_node_a_continuity grep -Fq \
        'invoke_remote node_a_rollback_continuity node-a --inspect' \
        "$action20j_builder_runner" || return 1
    /bin/bash "$action20j_builder_transaction" --self-test >/dev/null || return 1
    /bin/bash "$action20j_builder_transaction" --candidate-contract-test >/dev/null || return 1
    /bin/bash "$action20j_builder_runner" --self-test >/dev/null || return 1
    /bin/bash "$action20j_builder_runner" --contract-test >/dev/null || return 1
    printf '%s_transaction_sha256=%s\n' "$prefix" \
        "$action20j_builder_transaction_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20j_builder_runner")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20j-builder.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT INT TERM
        build "$test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
