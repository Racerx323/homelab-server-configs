#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_derivation
readonly source_installer_sha256=d9c99084b6c36c962d310b2072e0194aab891e6db140fedffa9d2942eb4e00ff
readonly source_runner_sha256=5e3d776766747aad602613c587a49f281f19ae87a7609eb25b904e9c30a0812b
readonly prerequisite_derivation_sha256=30132cf21f3b5768f1f11548e5321d512104bfda8825751402e65b716ae212de
readonly prerequisite_inspector_sha256=57e3bf9d9ae61b4e2b6017118481f492bd29c5784e74710a367b620230e0bea9
readonly health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly inspector_name=inspect-node-a-keepalived-prerequisite-action19c-a.sh
readonly installer_name=install-node-a-keepalived-helpers-action19d.sh
readonly labels_name=action19d-node-a-keepalived-helper-check-labels.txt
readonly runner_name=run-node-a-keepalived-helper-install-action19d.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_installer="$script_directory/install-node-b-keepalived-helpers-action19b.sh"
readonly source_runner="$script_directory/run-node-b-keepalived-helper-install-action19b.sh"
readonly prerequisite_derivation="$script_directory/derive-node-a-keepalived-prerequisite-action19c-a.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_source() {
    local derivation_expected_hash=$1
    local derivation_source_path=$2

    [[ -f "$derivation_source_path" && ! -L "$derivation_source_path" ]] ||
        return 1
    [[ "$(file_hash "$derivation_source_path")" = "$derivation_expected_hash" ]] || return 1
}

render_installer() {
    local render_output=$1

    sed \
        -e 's/action_19b/action_19d/g' \
        -e 's/action19b/action19d/g' \
        -e 's/node-b/node-a/g' \
        -e 's/node_b/node_a/g' \
        -e 's/j1-svpihole00/j1-svpihole0/g' \
        -e 's/10\.1\.0\.54/10.1.0.53/g' \
        -e 's/fd36:5aa8:6971:1::54/fd36:5aa8:6971:1::53/g' \
        -e 's/action15-health-follow-redirects/action16ar-retry-node-a-default-deny/g' \
        -e 's/action_19a_a/action_19c_a/g' \
        -e 's/action19a_a/action19c_a/g' \
        -e 's/action19a-a/action19c-a/g' \
        -e 's/inspect-node-b-keepalived-helper-prerequisite-action19a-a/inspect-node-a-keepalived-prerequisite-action19c-a/g' \
        -e 's/inspect-node-a-keepalived-helper-prerequisite-action19c-a/inspect-node-a-keepalived-prerequisite-action19c-a/g' \
        -e "s/162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f/$prerequisite_inspector_sha256/g" \
        -e 's/\^action_19c_a_check_/^action_19c_a_assertion_/g' \
        -e 's/action_19c_a_check_/action_19c_a_assertion_/g' \
        -e 's/action_19c_a_helper_invoked=false/action_19c_a_helper_execution=false/g' \
        -e 's/action_19c_a_persistent_mutation=false/action_19c_a_persistent_mutations=false/g' \
        -e 's/action_19c_a_state_unchanged=true/action_19c_a_assertion_state_unchanged=true/g' \
        -e 's/action19a-node-a-keepalived-fragment/action19c-node-a-keepalived-fragment/g' \
        "$source_installer" >"$render_output"
    chmod 0755 "$render_output"
}

render_expected_labels() {
    local labels_installer=$1
    local labels_output=$2
    local labels_helper
    local labels_property
    local labels_source
    local labels_unit
    local labels_unit_name

    {
        sed -n \
            's/^[[:space:]]*require_check \([a-zA-Z0-9_][a-zA-Z0-9_]*\).*/action_19d_check_\1/p' \
            "$labels_installer"
        for labels_source in health notification action19c_a_inspector; do
            for labels_property in regular not_symlink metadata hash_exact syntax; do
                printf 'action_19d_check_stage_%s_%s\n' \
                    "$labels_source" "$labels_property"
            done
        done
        for labels_helper in health notification; do
            for labels_property in regular not_symlink metadata hash_exact syntax; do
                printf 'action_19d_check_live_%s_%s\n' \
                    "$labels_helper" "$labels_property"
            done
        done
        for labels_unit_name in \
            caddy.service lighttpd.service keepalived.service lsyncd.service \
            caddy-lsyncd.service caddy-sync-reconcile.path \
            caddy-sync-reconcile.service; do
            labels_unit=${labels_unit_name//[-.]/_}
            for labels_property in ActiveState SubState UnitFileState; do
                printf 'action_19d_check_pre_%s_%s_observed\n' \
                    "$labels_unit" "$labels_property"
                printf 'action_19d_check_post_%s_%s_unchanged\n' \
                    "$labels_unit" "$labels_property"
            done
            if [[ "$labels_unit_name" == *.service ]]; then
                for labels_property in MainPID NRestarts; do
                    printf 'action_19d_check_pre_%s_%s_observed\n' \
                        "$labels_unit" "$labels_property"
                    printf 'action_19d_check_post_%s_%s_unchanged\n' \
                        "$labels_unit" "$labels_property"
                done
            fi
        done
    } | LC_ALL=C sort -u >"$labels_output"
    chmod 0644 "$labels_output"
}

render_runner() {
    local runner_installer_sha256=$1
    local runner_labels_sha256=$2
    local runner_output=$3
    local runner_stage

    runner_stage=${runner_output}.stage
    sed \
        -e 's/action_19b/action_19d/g' \
        -e 's/action19b/action19d/g' \
        -e 's/node-b/node-a/g' \
        -e 's/pi@10\.1\.0\.54/pi@10.1.0.53/g' \
        -e 's/pihole00\.local\.theama\.co/pihole0.local.theama.co/g' \
        -e 's/action19a-a/action19c-a/g' \
        -e 's/inspect-node-b-keepalived-helper-prerequisite-action19a-a/inspect-node-a-keepalived-prerequisite-action19c-a/g' \
        -e 's/inspect-node-a-keepalived-helper-prerequisite-action19c-a/inspect-node-a-keepalived-prerequisite-action19c-a/g' \
        -e 's/install-node-b-keepalived-helpers-action19b/install-node-a-keepalived-helpers-action19d/g' \
        -e "s/162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f/$prerequisite_inspector_sha256/g" \
        -e "s/d9c99084b6c36c962d310b2072e0194aab891e6db140fedffa9d2942eb4e00ff/$runner_installer_sha256/g" \
        -e 's/ACTION19B_/ACTION19D_/g' \
        -e 's/ACTION19B_ARCHIVE/ACTION19D_ARCHIVE/g' \
        "$source_runner" >"$runner_stage"

    awk -v labels_hash="$runner_labels_sha256" -v labels_file="$labels_name" '
        /^readonly installer_sha256=/ {
            print
            print "readonly expected_labels_sha256=" labels_hash
            next
        }
        /^readonly installer=/ {
            print
            print "readonly expected_labels=\"$script_directory/" labels_file "\""
            next
        }
        /require_source "\$installer_sha256" "\$installer"/ {
            print
            print "    [[ -f \"$expected_labels\" && ! -L \"$expected_labels\" ]] || return 1"
            print "    [[ \"$(stat -c \047%U:%G:%a\047 \"$expected_labels\")\" = \"$(id -un):$(id -gn):644\" ]] || return 1"
            print "    [[ \"$(file_hash \"$expected_labels\")\" = \"$expected_labels_sha256\" ]] || return 1"
            next
        }
        /\[\[ "\$check_count" -ge 80 \]\]/ {
            print "    [[ \"$check_count\" -eq \"$(wc -l <\"$expected_labels\")\" ]] || return 1"
            print "    mapfile -t observed_check_labels < <(grep -E \"^${prefix}_check_[a-zA-Z0-9_]+=true$\" \"$output_path\" | cut -d= -f1 | LC_ALL=C sort -u) || return 1"
            print "    cmp -s \"$expected_labels\" <(printf \047%s\\n\047 \"${observed_check_labels[@]}\") || return 1"
            next
        }
        /local required_marker/ {
            print
            print "    local -a observed_check_labels=()"
            next
        }
        /^write_success_fixture\(\) \{/ {
            print
            print "    local fixture_path=$1"
            print ""
            print "    sed \047s/$/=true/\047 \"$expected_labels\" >\"$fixture_path\""
            print "    printf \047%s\\n\047 \"${prefix}_preflight_complete=true\" \"${prefix}_mutation_started=true\" \"${prefix}_helpers_invoked=false\" \"${prefix}_fragment_mutated=false\" \"${prefix}_keepalived_mutated=false\" \"${prefix}_vrrp_mutated=false\" \"${prefix}_vip_mutated=false\" \"${prefix}_service_mutations=false\" \"${prefix}_backup_path=/var/backups/caddy-ha/action19d-node-a-keepalived-helpers.ABC123\" \"${prefix}_persistent_mutation_scope=two_helpers,rollback_backup\" \"${prefix}_install_complete=true\" >>\"$fixture_path\""
            print "}"
            skipping_fixture=1
            next
        }
        skipping_fixture && /^}$/ {
            skipping_fixture=0
            next
        }
        skipping_fixture { next }
        { print }
    ' "$runner_stage" >"$runner_output"
    rm -f -- "$runner_stage"
    chmod 0755 "$runner_output"
}

render_all() {
    local output_directory=$1
    local prerequisite_root
    local rendered_installer
    local rendered_labels
    local rendered_runner
    local rendered_installer_sha256
    local rendered_labels_sha256

    install -d -m 0700 "$output_directory"
    prerequisite_root=$(mktemp -d /tmp/caddy-action19d-prerequisite.XXXXXX)
    trap 'rm -rf -- "$prerequisite_root"' RETURN
    /bin/bash "$prerequisite_derivation" --output-directory "$prerequisite_root"
    install -m 0755 "$prerequisite_root/Caddy/scripts/$inspector_name" \
        "$output_directory/$inspector_name"
    rendered_installer=$output_directory/$installer_name
    rendered_labels=$output_directory/$labels_name
    rendered_runner=$output_directory/$runner_name
    render_installer "$rendered_installer"
    render_expected_labels "$rendered_installer" "$rendered_labels"
    rendered_installer_sha256=$(file_hash "$rendered_installer")
    rendered_labels_sha256=$(file_hash "$rendered_labels")
    render_runner "$rendered_installer_sha256" "$rendered_labels_sha256" \
        "$rendered_runner"
    rm -rf -- "$prerequisite_root"
    trap - RETURN
}

verify_sources() {
    require_source "$source_installer_sha256" "$source_installer" || return 1
    require_source "$source_runner_sha256" "$source_runner" || return 1
    require_source "$prerequisite_derivation_sha256" \
        "$prerequisite_derivation" || return 1
    [[ "$(file_hash "$script_directory/check-caddy.sh")" = "$health_sha256" ]] ||
        return 1
    [[ "$(file_hash "$script_directory/lsyncd-ha-failover-notify.sh")" = "$notification_sha256" ]] || return 1
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --output)
        [[ $# -eq 2 ]] || exit 64
        verify_sources
        render_all "$2"
        printf '%s_render_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --self-test | --output DIRECTORY\n' "${0##*/}" >&2
        exit 64
        ;;
esac
