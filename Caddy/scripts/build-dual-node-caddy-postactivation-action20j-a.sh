#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_a_builder
readonly source_builder_sha256=b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3
readonly source_probe_sha256=aa86451cea27a257ff9b14ca10e774a6189e4859df3fcf9bb1449f889bff54e2
readonly source_runner_sha256=5c7d5b9c3732371b6b3e0b5422b7e1772f723887103f168d827fe1c95cac50a8
readonly accepted_action20j_outer_sha256=50d302239c5675784e100bff358355651d30bdd96f8d02094c565f6403186ae7
readonly accepted_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly accepted_node_b_main_sha256=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
readonly accepted_node_b_fragment_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270
readonly action20j_started_at='2026-08-06 17:38:00-05:00'

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_builder=$script_directory/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh
readonly accepted_action20j_outer=$script_directory/run-node-b-caddy-vrrp-activation-action20j-outer.sh
readonly collision_checker=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20j_a_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20j_a_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20j_a_builder_label" >&2
    return 1
}
render_probe() {
    local action20j_a_builder_input=$1
    local action20j_a_builder_output=$2
    local action20j_a_builder_common=$3

    sed \
        -e 's/action_20d_retry10_a_retry_probe/action_20j_a_probe/g' \
        -e "s/9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab/$accepted_health_sha256/g" \
        -e "s/e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6/$accepted_node_b_main_sha256/g" \
        -e "s/294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d/$accepted_node_b_fragment_sha256/g" \
        -e "s/expected_health_user='    user keepalived_script'/expected_health_user='    user keepalived_script caddy-tls'/" \
        -e 's/expected_include_count=0/expected_include_count=1/' \
        -e 's/expected_vrrp_state=inactive_fragment/expected_vrrp_state=BACKUP/' \
        -e 's/expected_backup_count=0/expected_backup_count=1/' \
        -e 's/retry10_backup_count_exact/activation_backup_count_exact/g' \
        -e 's/retry10_backup_contract_exact/activation_backup_contract_exact/g' \
        -e 's/retry10_run_residue_absent/action20j_run_residue_absent/g' \
        -e 's/retry10_tmp_residue_absent/action20j_tmp_residue_absent/g' \
        "$action20j_a_builder_input" >"$action20j_a_builder_common"

    awk -v health_hash="$accepted_health_sha256" \
        -v node_b_old_main="e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6" \
        -v journal_since="$action20j_started_at" '
        /^readonly node_a_backup=/ {
            print
            print "readonly node_b_backup=/var/backups/caddy-ha/action20j-node-b-caddy-vrrp.jpRuFz"
            print "readonly journal_since=\047" journal_since "\047"
            next
        }
        /^        lsyncd_inactive caddy_ipv4_count_exact/ {
            sub(/lsyncd_inactive /,
                "lsyncd_inactive keepalived_script_identity_exact caddy_tls_identity_exact caddy_tls_membership_exact ")
            print
            next
        }
        /^        before_snapshot_complete health_status_zero/ {
            sub(/before_snapshot_complete /,
                "before_snapshot_complete health_context_exact journal_status_zero journal_stdout_safe journal_stderr_safe journal_no_caddy_fault journal_no_health_failure journal_no_health_overlap journal_no_ttl_hl_rejection ")
            print
            next
        }
        /\[\[ "\$\(expected_assertions \| wc -l\)" -eq 47 \]\]/ {
            sub(/47/, "58")
            print
            next
        }
        /\[\[ "\$\(expected_assertions \| LC_ALL=C sort -u \| wc -l\)" -eq 47 \]\]/ {
            sub(/47/, "58")
            print
            next
        }
        /printf .backup=%s/ && /tree_hash/ {
            sub(/\$node_a_backup/, "$expected_backup_path")
            print
            next
        }
        /^validate_backup_contract\(\) \{/ {
            print "validate_node_b_backup() {"
            print "    [[ -d \"$node_b_backup\" && ! -L \"$node_b_backup\" ]] || return 1"
            print "    [[ \"$(stat -c \047%U:%G:%a\047 \"$node_b_backup\")\" = root:root:700 ]] || return 1"
            print "    [[ \"$(stat -c \047%U:%G:%a\047 \"$node_b_backup/keepalived.conf.before\")\" = root:root:600 ]] || return 1"
            print "    [[ \"$(file_hash \"$node_b_backup/keepalived.conf.before\")\" = " node_b_old_main " ]] || return 1"
            print "    [[ \"$(stat -c \047%U:%G:%a\047 \"$node_b_backup/manifest\")\" = root:root:600 ]] || return 1"
            print "    [[ \"$(wc -l <\"$node_b_backup/manifest\")\" -eq 7 ]] || return 1"
            print "    grep -Fqx \047action=20j\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \047node=node-b\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \047main_sha256=" node_b_old_main "\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \047main_owner=root\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \047main_group=root\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \047main_mode=0644\047 \"$node_b_backup/manifest\" || return 1"
            print "    grep -Fqx \"include_record=$include_record\" \"$node_b_backup/manifest\""
            print "}"
            print "validate_backup_contract() {"
            print "    case \"$node_role\" in"
            print "        node-a) validate_node_a_backup ;;"
            print "        node-b) validate_node_b_backup ;;"
            print "        *) return 1 ;;"
            print "    esac"
            print "}"
            skip_backup = 1
            next
        }
        skip_backup {
            if ($0 == "}") skip_backup = 0
            next
        }
        /^    node-a\)/ { role = "node-a"; print; next }
        /^    node-b\)/ { role = "node-b"; print; next }
        /^    \*\) exit 64/ { role = ""; print; next }
        /expected_backup_count=1/ && role == "node-a" {
            print
            print "        expected_backup_path=$node_a_backup"
            print "        expected_backup_pattern=action20d-retry10-node-a-caddy-vrrp.*"
            print "        expected_script_uid=993"
            print "        expected_tls_gid=991"
            next
        }
        /expected_backup_count=1/ && role == "node-b" {
            print
            print "        expected_backup_path=$node_b_backup"
            print "        expected_backup_pattern=action20j-node-b-caddy-vrrp.*"
            print "        expected_script_uid=992"
            print "        expected_tls_gid=990"
            next
        }
        /^readonly expected_dns_count expected_vrrp_state expected_backup_count/ {
            print
            print "readonly expected_backup_path expected_backup_pattern expected_script_uid expected_tls_gid"
            next
        }
        /^readonly health_stderr=/ {
            print
            print "readonly journal_stdout=$work_root/journal.stdout"
            print "readonly journal_stderr=$work_root/journal.stderr"
            next
        }
        /^: >"\$health_stderr"/ {
            print
            print ": >\"$journal_stdout\""
            print ": >\"$journal_stderr\""
            next
        }
        /^chmod 0600 "\$health_stdout" "\$health_stderr"/ {
            print "chmod 0600 \"$health_stdout\" \"$health_stderr\" \"$journal_stdout\" \"$journal_stderr\""
            next
        }
        /^health_status=0$/ {
            print "script_uid=$(id -u keepalived_script 2>/dev/null || true)"
            print "tls_gid=$(getent group caddy-tls 2>/dev/null | cut -d: -f3 || true)"
            print "readonly script_uid tls_gid"
            print
            print
            next
        }
        /^"\$health_helper" >"\$health_stdout"/ {
            print "setpriv --reuid \"$script_uid\" --regid \"$tls_gid\" --clear-groups -- \"$health_helper\" >\"$health_stdout\" 2>\"$health_stderr\" || health_status=$?"
            next
        }
        /^emit_stream health_stderr / {
            print
            print "journal_status=0"
            print "journalctl --no-pager -o short-iso-precise -u keepalived.service --since \"$journal_since\" >\"$journal_stdout\" 2>\"$journal_stderr\" || journal_status=$?"
            print "readonly journal_status"
            print "emit_stream journal_stdout \"$journal_stdout\""
            print "emit_stream journal_stderr \"$journal_stderr\""
            next
        }
        /^run_assertion lsyncd_inactive / {
            print
            print "run_assertion keepalived_script_identity_exact test \"$script_uid\" = \"$expected_script_uid\""
            print "run_assertion caddy_tls_identity_exact test \"$tls_gid\" = \"$expected_tls_gid\""
            print "run_assertion caddy_tls_membership_exact test \"$(id -nG keepalived_script 2>/dev/null | tr \047 \047 \047\\n\047 | grep -Fxc caddy-tls || true)\" -eq 1"
            next
        }
        /^if \[\[ "\$node_role" = node-a \]\]; then$/ && !vrrp_done {
            print "run_assertion vrrp_contract_exact test \"$(sed -n \0471p\047 /run/caddy-ha/vrrp-state 2>/dev/null || true)\" = \"$expected_vrrp_state\""
            skip_vrrp = 1
            vrrp_done = 1
            next
        }
        skip_vrrp {
            if ($0 == "fi") skip_vrrp = 0
            next
        }
        /^run_assertion activation_backup_count_exact test/ {
            print "run_assertion activation_backup_count_exact test \\"
            getline
            print "    \"$(find \"$backup_root\" -mindepth 1 -maxdepth 1 -type d -name \"$expected_backup_pattern\" -printf . 2>/dev/null | wc -c)\" -eq \"$expected_backup_count\""
            next
        }
        /^run_assertion action20j_run_residue_absent test/ {
            print "run_assertion action20j_run_residue_absent test \\"
            getline
            print "    \"$(find /run -maxdepth 1 -name \047caddy-action20j-*\047 ! -path \"$work_root\" -printf . 2>/dev/null | wc -c)\" -eq 0"
            next
        }
        /^run_assertion action20j_tmp_residue_absent test/ {
            print "run_assertion action20j_tmp_residue_absent test \\"
            getline
            print "    \"$(find /tmp -maxdepth 1 -name \047caddy-action20j-*\047 -printf . 2>/dev/null | wc -c)\" -eq 0"
            next
        }
        /^run_assertion before_snapshot_complete / {
            print
            print "run_assertion health_context_exact test \"$script_uid:$tls_gid\" = \"$expected_script_uid:$expected_tls_gid\""
            print "run_assertion journal_status_zero test \"$journal_status\" -eq 0"
            print "run_assertion journal_stdout_safe safe_stream \"$journal_stdout\""
            print "run_assertion journal_stderr_safe safe_stream \"$journal_stderr\""
            print "run_assertion journal_no_caddy_fault test \"$(grep -Ec \047CADDY_(IPV4|IPV6|DUALSTACK).*FAULT|Caddy HA.*FAULT\047 \"$journal_stdout\" || true)\" -eq 0"
            print "run_assertion journal_no_health_failure test \"$(grep -Ec \047Script `check_caddy` now returning ([1-9]|[1-9][0-9]+)|check_caddy.*(failed|timed out)\047 \"$journal_stdout\" || true)\" -eq 0"
            print "run_assertion journal_no_health_overlap test \"$(grep -Fxc \047Track script check_caddy is already running, expect idle - skipping run\047 \"$journal_stdout\" || true)\" -eq 0"
            print "run_assertion journal_no_ttl_hl_rejection test \"$(grep -Ec \047CADDY_IPV(4|6).*TTL/HL .* not in range\047 \"$journal_stdout\" || true)\" -eq 0"
            next
        }
        /^printf .%s_health_helper_invoked=true/ {
            print
            print "printf \047%s_health_execution_context=%s:%s:clear-groups\\n\047 \"$prefix\" \"$script_uid\" \"$tls_gid\""
            print "printf \047%s_keepalived_journal_since=%s\\n\047 \"$prefix\" \"$journal_since\""
            print "printf \047%s_keepalived_journal_captured=true\\n\047 \"$prefix\""
            next
        }
        { print }
    ' "$action20j_a_builder_common" >"$action20j_a_builder_output"
}
render_runner() {
    local action20j_a_builder_input=$1
    local action20j_a_builder_output=$2
    local action20j_a_builder_probe_hash=$3

    sed \
        -e 's/action_20d_retry10_a_retry/action_20j_a/g' \
        -e 's/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh/inspect-dual-node-caddy-postactivation-action20j-a.sh/g' \
        -e "s/readonly probe_sha256=$source_probe_sha256/readonly probe_sha256=$action20j_a_builder_probe_hash/" \
        -e 's/CADDY_ACTION20D_RETRY10_A_SSH_BINARY/CADDY_ACTION20J_A_SSH_BINARY/g' \
        -e 's/node_b_fragment_inactive/node_b_backup_state/g' \
        -e 's/value_expected_vrrp_state=inactive_fragment/value_expected_vrrp_state=BACKUP/g' \
        -e 's/write_probe_fixture node-b 0 0 inactive_fragment/write_probe_fixture node-b 0 0 BACKUP/' \
        "$action20j_a_builder_input" >"$action20j_a_builder_output"
}
validate_outputs() {
    local action20j_a_builder_probe=$1
    local action20j_a_builder_runner=$2
    local action20j_a_builder_probe_hash

    action20j_a_builder_probe_hash=$(file_hash "$action20j_a_builder_probe") || return 1
    record_check probe_syntax /bin/bash -n "$action20j_a_builder_probe" || return 1
    record_check runner_syntax /bin/bash -n "$action20j_a_builder_runner" || return 1
    record_check probe_collision /bin/bash "$collision_checker" "$action20j_a_builder_probe" || return 1
    record_check runner_collision /bin/bash "$collision_checker" "$action20j_a_builder_runner" || return 1
    record_check probe_health_hash grep -Fqx \
        "readonly health_sha256=$accepted_health_sha256" "$action20j_a_builder_probe" || return 1
    record_check probe_node_b_main grep -Fqx \
        "        expected_main_sha256=$accepted_node_b_main_sha256" \
        "$action20j_a_builder_probe" || return 1
    record_check probe_node_b_fragment grep -Fqx \
        "        expected_fragment_sha256=$accepted_node_b_fragment_sha256" \
        "$action20j_a_builder_probe" || return 1
    record_check probe_node_b_backup grep -Fqx \
        'readonly node_b_backup=/var/backups/caddy-ha/action20j-node-b-caddy-vrrp.jpRuFz' \
        "$action20j_a_builder_probe" || return 1
    # The dollar expressions are an intentional literal generated-source contract.
    # shellcheck disable=SC2016
    record_check probe_exact_context grep -Fq \
        'setpriv --reuid "$script_uid" --regid "$tls_gid" --clear-groups' \
        "$action20j_a_builder_probe" || return 1
    record_check probe_journal_boundary grep -Fqx \
        "readonly journal_since='$action20j_started_at'" "$action20j_a_builder_probe" || return 1
    record_check runner_probe_pin grep -Fqx \
        "readonly probe_sha256=$action20j_a_builder_probe_hash" \
        "$action20j_a_builder_runner" || return 1
    record_check runner_node_b_backup grep -Fq node_b_backup_state \
        "$action20j_a_builder_runner" || return 1
    record_check probe_self_test /bin/bash "$action20j_a_builder_probe" --self-test || return 1
    record_check runner_self_test /bin/bash "$action20j_a_builder_runner" --self-test || return 1
    record_check runner_contract_test /bin/bash "$action20j_a_builder_runner" --contract-test
}
build() (
    local action20j_a_builder_output_root=$1
    local action20j_a_builder_source_root=$action20j_a_builder_output_root/source
    local action20j_a_builder_source_probe
    local action20j_a_builder_source_runner
    local action20j_a_builder_probe=$action20j_a_builder_output_root/inspect-dual-node-caddy-postactivation-action20j-a.sh
    local action20j_a_builder_runner=$action20j_a_builder_output_root/run-dual-node-caddy-postactivation-action20j-a.sh
    local action20j_a_builder_common=$action20j_a_builder_output_root/probe.common
    local action20j_a_builder_probe_hash

    install -d -m 0700 "$action20j_a_builder_output_root" "$action20j_a_builder_source_root"
    record_check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    record_check accepted_action20j_outer_hash test \
        "$(file_hash "$accepted_action20j_outer")" = \
        "$accepted_action20j_outer_sha256" || return 1
    /bin/bash "$source_builder" --output "$action20j_a_builder_source_root" >/dev/null || return 1
    action20j_a_builder_source_probe=$action20j_a_builder_source_root/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
    action20j_a_builder_source_runner=$action20j_a_builder_source_root/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
    record_check source_probe_hash test "$(file_hash "$action20j_a_builder_source_probe")" = \
        "$source_probe_sha256" || return 1
    record_check source_runner_hash test "$(file_hash "$action20j_a_builder_source_runner")" = \
        "$source_runner_sha256" || return 1
    render_probe "$action20j_a_builder_source_probe" "$action20j_a_builder_probe" \
        "$action20j_a_builder_common"
    chmod 0700 "$action20j_a_builder_probe"
    action20j_a_builder_probe_hash=$(file_hash "$action20j_a_builder_probe")
    render_runner "$action20j_a_builder_source_runner" "$action20j_a_builder_runner" \
        "$action20j_a_builder_probe_hash"
    chmod 0700 "$action20j_a_builder_runner"
    rm -rf -- "$action20j_a_builder_source_root"
    rm -f -- "$action20j_a_builder_common"
    validate_outputs "$action20j_a_builder_probe" "$action20j_a_builder_runner" || return 1
    printf '%s_probe_sha256=%s\n' "$prefix" "$action20j_a_builder_probe_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20j_a_builder_runner")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20j-a-builder.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT INT TERM
        build "$test_root/output"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test|--contract-test\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
