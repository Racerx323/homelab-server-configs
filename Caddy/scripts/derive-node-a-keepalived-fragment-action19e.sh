#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19e
readonly base_installer_sha256=142eac9d91eb30c3ce2103cc98ef1d9dddd288fedb632398c589bade6c252db6
readonly base_runner_sha256=f45bde838b783b1ef6ff99f276ac1dab3df28a2f96eeea5dac14817ec1d71518
readonly node_b_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly node_a_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly node_b_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly node_a_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly rendered_installer_name=install-node-a-keepalived-fragment-action19e.sh
readonly rendered_runner_name=run-node-a-keepalived-fragment-install-action19e.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_installer="$script_directory/install-node-b-keepalived-fragment-action19a.sh"
readonly base_runner="$script_directory/run-node-b-keepalived-fragment-install-action19a.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_installer" && ! -L "$base_installer" ]] || return 1
    [[ -f "$base_runner" && ! -L "$base_runner" ]] || return 1
    [[ "$(file_hash "$base_installer")" = "$base_installer_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] || return 1
}

transform_common() {
    sed \
        -e 's/action_19a/action_19e/g' \
        -e 's/action19a/action19e/g' \
        -e 's/ACTION19A/ACTION19E/g' \
        -e 's/node-b/node-a/g' \
        -e 's/node_b/node_a/g' \
        -e 's/NODE_B/NODE_A/g' \
        -e 's/j1-svpihole00/j1-svpihole0/g' \
        -e 's/pihole00\.local\.theama\.co/pihole0.local.theama.co/g' \
        -e "s/$node_b_fragment_sha256/$node_a_fragment_sha256/g" \
        -e "s/$node_b_tree_sha256/$node_a_tree_sha256/g" \
        -e 's/10\.1\.0\.54/__NODE_A_IPV4__/g' \
        -e 's/10\.1\.0\.53/10.1.0.54/g' \
        -e 's/__NODE_A_IPV4__/10.1.0.53/g' \
        -e 's/fd36:5aa8:6971:1::54/__NODE_A_IPV6__/g' \
        -e 's/fd36:5aa8:6971:1::53/fd36:5aa8:6971:1::54/g' \
        -e 's/__NODE_A_IPV6__/fd36:5aa8:6971:1::53/g' \
        -e 's/priority 100/priority 140/g' \
        -e 's/render-node-b/render-node-a/g' \
        -e 's/install-node-b-keepalived-fragment-action19a\.sh/install-node-a-keepalived-fragment-action19e.sh/g' \
        "$1"
}

write_expected_checks_function() {
    cat <<'EXPECTED_CHECKS'
expected_checks() {
    local phase_label
    local property_name
    local unit_label
    local unit_name
    local -a fragment_labels=(
        regular not_symlink metadata hash_exact dualstack_group ipv4_instance
        ipv6_instance ipv4_vrid ipv6_vrid priority ipv4_source ipv4_peer
        ipv6_source ipv6_peer ipv4_vip ipv6_vip preempt_delay_count
        initial_backup_count health_user health_command notify_command
    )
    local -a static_pre=(
        identity_root working_directory_root hostname_node_a architecture_arm64
        physical_ipv4_exact physical_ipv6_exact stage_directory_regular
        stage_directory_not_symlink stage_directory_metadata
    )
    local -a static_after_staged=(
        candidate_parser_valid target_absent target_not_symlink
        main_configuration_regular main_configuration_not_symlink
        main_configuration_excludes_fragment accepted_keepalived_tree_hash
        main_hash_format health_script_regular health_script_not_symlink
        health_script_hash_exact notification_script_regular
        notification_script_not_symlink notification_script_hash_exact
        rollback_root_directory rollback_root_not_symlink
        rollback_root_metadata prior_backup_absent prior_install_stage_absent
        keepalived_active keepalived_enabled caddy_active lighttpd_active
        ipv4_vip_absent ipv6_vip_absent
    )
    local -a static_post=(
        live_fragment_parser_valid main_configuration_hash_unchanged
        main_configuration_still_excludes_fragment ipv4_vip_still_absent
        ipv6_vip_still_absent
    )
    local -a backup_labels=(
        backup_directory_regular backup_directory_not_symlink
        backup_directory_metadata backup_manifest_regular
        backup_manifest_not_symlink backup_manifest_metadata
        backup_manifest_content_exact
    )
    local label

    for label in "${static_pre[@]}"; do
        printf '%s_check_%s\n' "$prefix" "$label"
    done
    phase_label=staged_fragment
    for label in "${fragment_labels[@]}"; do
        printf '%s_check_%s_%s\n' "$prefix" "$phase_label" "$label"
    done
    for label in "${static_after_staged[@]}"; do
        printf '%s_check_%s\n' "$prefix" "$label"
    done
    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            printf '%s_check_pre_%s_%s_observed\n' "$prefix" "$unit_label" \
                "$property_name"
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                printf '%s_check_pre_%s_%s_observed\n' "$prefix" "$unit_label" \
                    "$property_name"
            done
        fi
    done
    phase_label=live_fragment
    for label in "${fragment_labels[@]}"; do
        printf '%s_check_%s_%s\n' "$prefix" "$phase_label" "$label"
    done
    for label in "${static_post[@]}"; do
        printf '%s_check_%s\n' "$prefix" "$label"
    done
    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            printf '%s_check_post_%s_%s_unchanged\n' "$prefix" "$unit_label" \
                "$property_name"
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                printf '%s_check_post_%s_%s_unchanged\n' "$prefix" "$unit_label" \
                    "$property_name"
            done
        fi
    done
    for label in "${backup_labels[@]}"; do
        printf '%s_check_%s\n' "$prefix" "$label"
    done
}
EXPECTED_CHECKS
}

transform_installer() {
    local output_path=$1
    local transformed_path
    local expected_function_path

    transformed_path=$(mktemp /tmp/caddy-action19e-installer.XXXXXX) || return 1
    expected_function_path=$(mktemp /tmp/caddy-action19e-checks.XXXXXX) || {
        rm -f -- "$transformed_path"
        return 1
    }
    transform_common "$base_installer" >"$transformed_path"
    write_expected_checks_function >"$expected_function_path"
    awk -v function_path="$expected_function_path" '
        $0 == "case \"${1:-}\" in" {
            while ((getline line < function_path) > 0) print line
            close(function_path)
            print
            next
        }
        $0 == "    --self-test)" {
            print "    --expected-checks)"
            print "        [[ $# -eq 1 ]] || exit 64"
            print "        expected_checks"
            print "        exit 0"
            print "        ;;"
        }
        { print }
    ' "$transformed_path" >"$output_path"
    rm -f -- "$transformed_path" "$expected_function_path"
    chmod 0755 "$output_path"
}

write_exact_validator() {
    cat <<'VALIDATOR'
validate_success() {
    local output_path=$1
    local observed_remote_status=$2
    local contract_root
    local expected_path
    local observed_path
    local required_marker

    [[ "$observed_remote_status" -eq 0 ]] || return 1
    contract_root=$(mktemp -d /tmp/caddy-action19e-success.XXXXXX) || return 1
    expected_path=$contract_root/expected
    observed_path=$contract_root/observed
    "$installer" --expected-checks | LC_ALL=C sort >"$expected_path" || {
        rm -rf -- "$contract_root"
        return 1
    }
    sed -n "s/^\(${prefix}_check_[A-Za-z0-9_]*\)=true$/\1/p" \
        "$output_path" | LC_ALL=C sort >"$observed_path" || {
        rm -rf -- "$contract_root"
        return 1
    }
    [[ "$(wc -l <"$expected_path")" -eq 154 ]] || {
        rm -rf -- "$contract_root"
        return 1
    }
    [[ "$(LC_ALL=C sort -u "$expected_path" | wc -l)" -eq 154 ]] || {
        rm -rf -- "$contract_root"
        return 1
    }
    [[ "$(wc -l <"$observed_path")" -eq 154 ]] || {
        rm -rf -- "$contract_root"
        return 1
    }
    [[ "$(LC_ALL=C sort -u "$observed_path" | wc -l)" -eq 154 ]] || {
        rm -rf -- "$contract_root"
        return 1
    }
    cmp -s "$expected_path" "$observed_path" || {
        rm -rf -- "$contract_root"
        return 1
    }
    rm -rf -- "$contract_root"
    [[ "$(grep -Ec "^${prefix}_check_[A-Za-z0-9_]+=false$" \
        "$output_path" || true)" -eq 0 ]] || return 1
    for required_marker in \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true"; do
        require_exact_line "$required_marker" "$output_path" || return 1
    done
    [[ "$(grep -Ec \
        "^${prefix}_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment\\.[A-Za-z0-9]+$" \
        "$output_path")" -eq 1 ]] || return 1
    ! grep -Eq "^${prefix}_(rollback_|manual_intervention_required=true)" \
        "$output_path"
}
VALIDATOR
}

write_exact_fixture() {
    cat <<'FIXTURE'
write_success_fixture() {
    local fixture_path=$1
    local expected_label

    : >"$fixture_path"
    while IFS= read -r expected_label; do
        printf '%s=true\n' "$expected_label"
    done < <("$installer" --expected-checks) >>"$fixture_path"
    printf '%s\n' \
        "${prefix}_preflight_complete=true" \
        "${prefix}_mutation_started=true" \
        "${prefix}_fragment_installed=true" \
        "${prefix}_main_configuration_mutated=false" \
        "${prefix}_keepalived_reloaded=false" \
        "${prefix}_keepalived_restarted=false" \
        "${prefix}_vrrp_transition_requested=false" \
        "${prefix}_vip_mutations=false" \
        "${prefix}_service_mutations=false" \
        "${prefix}_backup_path=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.FIXTURE" \
        "${prefix}_persistent_mutation_scope=fragment,rollback_backup" \
        "${prefix}_install_complete=true" >>"$fixture_path"
}
FIXTURE
}

transform_runner() {
    local installer_hash=$1
    local output_path=$2
    local transformed_path
    local validator_path
    local fixture_path

    transformed_path=$(mktemp /tmp/caddy-action19e-runner.XXXXXX) || return 1
    validator_path=$(mktemp /tmp/caddy-action19e-validator.XXXXXX) || return 1
    fixture_path=$(mktemp /tmp/caddy-action19e-fixture.XXXXXX) || return 1
    transform_common "$base_runner" | sed \
        -e "s/$base_installer_sha256/$installer_hash/g" \
        -e 's/%s_check_fixture_001=false/%s_check_identity_root=false/g' \
        >"$transformed_path"
    write_exact_validator >"$validator_path"
    write_exact_fixture >"$fixture_path"
    awk -v validator_path="$validator_path" -v fixture_path="$fixture_path" '
        $0 == "validate_success() {" {
            while ((getline line < validator_path) > 0) print line
            close(validator_path)
            skipping_success=1
            next
        }
        skipping_success && $0 == "validate_failure() {" {
            skipping_success=0
        }
        skipping_success { next }
        $0 == "write_success_fixture() {" {
            while ((getline line < fixture_path) > 0) print line
            close(fixture_path)
            skipping_fixture=1
            next
        }
        skipping_fixture && $0 == "case \"${1:-}\" in" {
            skipping_fixture=0
        }
        skipping_fixture { next }
        $0 == "    -o StrictHostKeyChecking=yes \\" {
            print
            print "    -o HostKeyAlias=\"$expected_host_alias\" \\"
            next
        }
        $0 == "    rm -rf -- \"$work_directory\"" {
            print
            print "    printf \x27%s_workstation_cleanup_complete=true\\n\x27 \"$prefix\""
            next
        }
        { print }
    ' "$transformed_path" >"$output_path"
    rm -f -- "$transformed_path" "$validator_path" "$fixture_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local installer_path=$output_directory/$rendered_installer_name
    local runner_path=$output_directory/$rendered_runner_name
    local installer_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    transform_installer "$installer_path"
    installer_hash=$(file_hash "$installer_path")
    transform_runner "$installer_hash" "$runner_path"
    bash -n "$installer_path" "$runner_path"
    [[ "$("$installer_path" --expected-checks | wc -l)" -eq 154 ]]
    [[ "$("$installer_path" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 154 ]]
}

self_test() {
    local self_test_root

    verify_sources || return 1
    self_test_root=$(mktemp -d /tmp/caddy-action19e-derive.XXXXXX) || return 1
    render_pair "$self_test_root" || {
        rm -rf -- "$self_test_root"
        return 1
    }
    /bin/bash "$self_test_root/$rendered_installer_name" --self-test >/dev/null
    rm -rf -- "$self_test_root"
    printf '%s_derivation_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_sources
        render_pair "$2"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
