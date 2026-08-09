#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23d_builder
readonly source_driver_sha256=94821c3000a6e13317fe7b0f6d7a2238cefb27c1ef93a23e822bf1f534fa85f3
readonly source_outer_sha256=a993b08f230ec0ea8b88d5a88cac860e807d42cfea30284e2e52f36aeba93324
readonly source_regression_sha256=5d006bc96a284c9a33a6c9030456ebc6353b44a35da019f00e3924a4cc8e3c8e
readonly accepted_ftl_sha256=c96c3591fabd3cbae4c0b32c695e34a2923a5b52b38e935cda3f2bf24fce1d7b
readonly accepted_domain_sha256=a8305acbc27a9133d6e68e8b1a0fe9a462a975919233d71866d54b2e98810f96

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly source_driver=$script_directory/apply-node-b-pihole-ptr-policy-action23c.sh
readonly source_outer=$script_directory/run-node-b-pihole-ptr-policy-action23c-outer.sh
readonly source_regression=$caddy_root/tests/action23c-node-b-pihole-ptr-policy-regression.sh
case "${1:-}" in
    "")
        [[ $# -eq 0 ]] || exit 64
        target_driver=$script_directory/apply-node-b-pihole-ptr-policy-action23d.sh
        target_outer=$script_directory/run-node-b-pihole-ptr-policy-action23d-outer.sh
        target_regression=$caddy_root/tests/action23d-node-b-pihole-ptr-policy-regression.sh
        ;;
    --output-root)
        [[ $# -eq 2 && -d "$2" && ! -L "$2" ]] || exit 64
        target_driver=$2/apply-node-b-pihole-ptr-policy-action23d.sh
        target_outer=$2/run-node-b-pihole-ptr-policy-action23d-outer.sh
        target_regression=$2/action23d-node-b-pihole-ptr-policy-regression.sh
        ;;
    *) exit 64 ;;
esac
readonly target_driver target_outer target_regression

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
require_source() {
    local action23d_builder_source=$1
    local action23d_builder_expected_hash=$2

    # conditional-validator-explicit-failures-begin
    [[ -f "$action23d_builder_source" ]] || return 1
    [[ ! -L "$action23d_builder_source" ]] || return 1
    [[ "$(file_hash "$action23d_builder_source")" = "$action23d_builder_expected_hash" ]] || return 1
    # conditional-validator-explicit-failures-end
}
require_count() {
    local action23d_builder_pattern=$1
    local action23d_builder_expected_count=$2
    local action23d_builder_source=$3

    # conditional-validator-explicit-failures-begin
    [[ "$(grep -Fxc "$action23d_builder_pattern" "$action23d_builder_source" || true)" -eq "$action23d_builder_expected_count" ]] || return 1
    # conditional-validator-explicit-failures-end
}
record_gate() {
    local action23d_builder_gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$action23d_builder_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action23d_builder_gate_label" >&2
    return 1
}
render_common() {
    sed \
        -e 's/action_23c/action_23d/g' \
        -e 's/action23c/action23d/g' \
        -e 's/ACTION23C/ACTION23D/g' \
        "$1"
}

record_gate source_driver_hash require_source "$source_driver" "$source_driver_sha256"
record_gate source_outer_hash require_source "$source_outer" "$source_outer_sha256"
record_gate source_regression_hash require_source "$source_regression" "$source_regression_sha256"
record_gate source_ftl_metadata_count require_count \
    'record_check ftl_metadata test "$(stat -c '\''%U:%G:%a'\'' "$live_ftl")" = root:root:644 || exit 1' \
    1 "$source_driver"
record_gate source_candidate_install_count require_count \
    'install -o root -g root -m 0644 "$candidate" "$transaction_file"' \
    1 "$source_driver"
record_gate source_rollback_install_count require_count \
    '        if ! install -o root -g root -m 0644 "$backup_dir/pihole-FTL.conf.before" "$transaction_file"; then' \
    1 "$source_driver"

driver_stage=$(mktemp /tmp/caddy-action23d-driver.XXXXXX)
regression_stage=$(mktemp /tmp/caddy-action23d-regression.XXXXXX)
outer_stage=$(mktemp /tmp/caddy-action23d-outer.XXXXXX)
readonly driver_stage regression_stage outer_stage
cleanup() {
    local action23d_builder_status=$?

    rm -f -- "$driver_stage" "$regression_stage" "$outer_stage"
    exit "$action23d_builder_status"
}
trap cleanup EXIT

render_common "$source_driver" |
    sed \
        -e "/^readonly live_domain=/a\\readonly accepted_ftl_sha256=$accepted_ftl_sha256\nreadonly accepted_domain_sha256=$accepted_domain_sha256" \
        -e 's/ftl_metadata ftl_old_ptr_exact_once/ftl_metadata ftl_hash_accepted ftl_old_ptr_exact_once/' \
        -e 's/domain_metadata domain_exact_once/domain_metadata domain_hash_accepted domain_exact_once/' \
        -e "/^record_check ftl_metadata /a\\record_check ftl_hash_accepted test \"\$(file_hash \"\$live_ftl\")\" = \"\$accepted_ftl_sha256\" || exit 1" \
        -e "/^record_check domain_metadata /a\\record_check domain_hash_accepted test \"\$(file_hash \"\$live_domain\")\" = \"\$accepted_domain_sha256\" || exit 1" \
        -e 's/= root:root:644 || exit 1/= pihole:root:664 || exit 1/' \
        -e 's/install -o root -g root -m 0644 "$candidate"/install -o pihole -g root -m 0664 "$candidate"/' \
        -e 's/install -o root -g root -m 0644 "$backup_dir\/pihole-FTL.conf.before"/install -o pihole -g root -m 0664 "$backup_dir\/pihole-FTL.conf.before"/' \
        -e 's/= root:root:644 || exit 1/= pihole:root:664 || exit 1/g' \
        -e '/^record_check domain_metadata / s/pihole:root:664/root:root:644/' \
        -e 's/printf '\''action=23c\\n'\''/printf '\''action=23d\\n'\''/' \
        -e "/^    printf '%s_node_a_ssh=false\\\\n'/a\\    printf '%s_action_23c_rerun=false\\\\n' \"\$prefix\"" \
        -e "/^printf '%s_node_a_ssh=false\\\\n'/a\\printf '%s_action_23c_rerun=false\\\\n' \"\$prefix\"" \
        >"$driver_stage"

record_gate driver_ftl_hash_pin test \
    "$(grep -Fxc 'record_check ftl_hash_accepted test "$(file_hash "$live_ftl")" = "$accepted_ftl_sha256" || exit 1' "$driver_stage" || true)" -eq 1
record_gate driver_domain_hash_pin test \
    "$(grep -Fxc 'record_check domain_hash_accepted test "$(file_hash "$live_domain")" = "$accepted_domain_sha256" || exit 1' "$driver_stage" || true)" -eq 1
record_gate driver_live_metadata_count test \
    "$(grep -Fc 'pihole:root:664' "$driver_stage" || true)" -eq 2
record_gate driver_install_metadata_count test \
    "$(grep -Fc 'install -o pihole -g root -m 0664' "$driver_stage" || true)" -eq 2
record_gate driver_source_rerun_literal_absent test \
    "$(grep -Fc 'action_23d_action_23c_rerun=false' "$driver_stage" || true)" -eq 0
record_gate driver_syntax /bin/bash -n "$driver_stage"
driver_hash=$(file_hash "$driver_stage")
readonly driver_hash

render_common "$source_regression" |
    sed \
        -e '2a# shellcheck disable=SC2016' \
        -e 's/apply-node-b-pihole-ptr-policy-action23c/apply-node-b-pihole-ptr-policy-action23d/g' \
        -e 's/run-node-b-pihole-ptr-policy-action23c-outer/run-node-b-pihole-ptr-policy-action23d-outer/g' \
        -e "/record_check domain_hash_guard/a\\record_check observed_metadata_contract grep -Fq 'pihole:root:664' \"\$driver\"\nrecord_check candidate_metadata_contract grep -Fq 'install -o pihole -g root -m 0664 \"\$candidate\"' \"\$driver\"\nrecord_check source_driver_invocation_absent test \"\$(grep -Ec 'apply-node-b-pihole-ptr-policy-action23c|run-node-b-pihole-ptr-policy-action23c-outer' \"\$driver\" || true)\" -eq 0\nrecord_check source_outer_invocation_absent test \"\$(grep -Ec 'apply-node-b-pihole-ptr-policy-action23c|run-node-b-pihole-ptr-policy-action23c-outer' \"\$outer\" || true)\" -eq 0" \
        -e "/grep -Fqx 'action_23d_outer_action_23b_rerun=false'/a\\        grep -Fqx 'action_23d_outer_action_23c_rerun=false' \"\$action23d_regression_stdout\" || return 1" \
        >"$regression_stage"
record_gate regression_syntax /bin/bash -n "$regression_stage"
regression_hash=$(file_hash "$regression_stage")
readonly regression_hash

render_common "$source_outer" |
    sed \
        -e 's/apply-node-b-pihole-ptr-policy-action23c/apply-node-b-pihole-ptr-policy-action23d/g' \
        -e 's/action23c-node-b-pihole-ptr-policy-regression/action23d-node-b-pihole-ptr-policy-regression/g' \
        -e "s/^readonly driver_sha256=.*/readonly driver_sha256=$driver_hash/" \
        -e "s/^readonly regression_sha256=.*/readonly regression_sha256=$regression_hash/" \
        -e "/validate_assert node_a_ssh_false/a\\    validate_assert action23c_rerun_false require_one 'action_23d_action_23c_rerun=false' \"\$action23d_outer_stdout\" || return 1" \
        -e "/printf '%s_action_23b_rerun=false\\\\n'/a\\printf '%s_action_23c_rerun=false\\\\n' \"\$prefix\"" \
        >"$outer_stage"
record_gate outer_syntax /bin/bash -n "$outer_stage"

install -m 0755 "$driver_stage" "$target_driver"
install -m 0755 "$regression_stage" "$target_regression"
install -m 0755 "$outer_stage" "$target_outer"
record_gate target_driver_regular test -f "$target_driver"
record_gate target_regression_regular test -f "$target_regression"
record_gate target_outer_regular test -f "$target_outer"
printf '%s_driver_sha256=%s\n' "$prefix" "$(file_hash "$target_driver")"
printf '%s_regression_sha256=%s\n' "$prefix" "$(file_hash "$target_regression")"
printf '%s_outer_sha256=%s\n' "$prefix" "$(file_hash "$target_outer")"
printf '%s_complete=true\n' "$prefix"
