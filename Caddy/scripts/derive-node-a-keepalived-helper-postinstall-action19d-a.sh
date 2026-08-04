#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19d_a
readonly base_derivation_sha256=7ba7ca096db09c48b57c32ae62bf300b3aa16aa6b6f8d4cf033d83624395dd1b
readonly base_inspector_sha256=74b4fbafc25850dace3b0057a7b74a3464936425869952ac21113c11e2652250
readonly base_runner_sha256=8c24121c3e8a1f4f8719b6445228c690745671217bc54bd6e7c12c866869c34f
readonly expected_keepalived_tree_sha256=dad64e4ac7fdbaab2dbdc4bf88feab59d4b6f99ee51ac562e67f968967072f66
readonly expected_backup_manifest_sha256=cf153d8b050f05a958a48e2266d0bac433dbcce37d09bbf4588529b072ea1ec7
readonly expected_backup_path=/var/backups/caddy-ha/action19d-node-a-keepalived-helpers.VMlVJR
readonly rendered_inspector_name=inspect-node-a-keepalived-helper-postinstall-action19d-a.sh
readonly rendered_runner_name=run-node-a-keepalived-helper-postinstall-action19d-a.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_derivation="$script_directory/derive-node-b-keepalived-helper-postinstall-action19b-b.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_derivation" && ! -L "$base_derivation" ]] || return 1
    [[ "$(file_hash "$base_derivation")" = "$base_derivation_sha256" ]] ||
        return 1
}

transform_inspector() {
    local source_path=$1
    local output_path=$2

    sed \
        -e 's/action_19b_b/action_19d_a/g' \
        -e 's/action19b-b/action19d-a/g' \
        -e 's/caddy-action19b-b/caddy-action19d-a/g' \
        -e 's/node-b-keepalived-helper-postinstall-action19b-b/node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/hostname_node_b/hostname_node_a/g' \
        -e 's/j1-svpihole00/j1-svpihole0/g' \
        -e 's/10\.1\.0\.54/10.1.0.53/g' \
        -e 's/fd36:5aa8:6971:1::54/fd36:5aa8:6971:1::53/g' \
        -e "s/68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f/$expected_keepalived_tree_sha256/g" \
        -e 's/action15-health-follow-redirects/action16ar-retry-node-a-default-deny/g' \
        -e "s#/var/backups/caddy-ha/action19b-retry-node-b-keepalived-helpers\.98dYgc#$expected_backup_path#g" \
        -e "s/1ea24e88eeab706fe64a4005ddadaf6bda3de1236838f05f82cf630f3f298adc/$expected_backup_manifest_sha256/g" \
        -e 's/action19b_retry/action19d/g' \
        -e 's/action19b-retry-node-b-keepalived-helpers/action19d-node-a-keepalived-helpers/g' \
        -e 's/caddy-action19b-retry/caddy-action19d/g' \
        -e 's/\.check-caddy\.action19b-retry/\.check-caddy.action19d/g' \
        -e 's/\.lsyncd-ha-failover-notify\.action19b-retry/\.lsyncd-ha-failover-notify.action19d/g' \
        -e "s/'action=action19b-retry'/'action=action19d'/g" \
        -e 's/action19a/action19c/g' \
        -e 's/action19c-node-b/action19c-node-a/g' \
        "$source_path" >"$output_path"
    chmod 0755 "$output_path"
}

transform_runner() {
    local source_path=$1
    local inspector_hash=$2
    local output_path=$3

    sed \
        -e 's/action_19b_b/action_19d_a/g' \
        -e 's/action19b-b/action19d-a/g' \
        -e 's/ACTION19BB/ACTION19DA/g' \
        -e 's/CADDY_ACTION19BB/CADDY_ACTION19DA/g' \
        -e 's/caddy-action19b-b/caddy-action19d-a/g' \
        -e 's/node-b-keepalived-helper-postinstall-action19b-b/node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/inspect-node-b-keepalived-helper-postinstall-action19b-b/inspect-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/inspect-node-b-keepalived-helper-postinstall-action19d-a/inspect-node-a-keepalived-helper-postinstall-action19d-a/g' \
        -e 's/pi@10\.1\.0\.54/pi@10.1.0.53/g' \
        -e 's/pihole00\.local\.theama\.co/pihole0.local.theama.co/g' \
        -e "s/74b4fbafc25850dace3b0057a7b74a3464936425869952ac21113c11e2652250/$inspector_hash/g" \
        -e "s#/var/backups/caddy-ha/action19b-retry-node-b-keepalived-helpers\.98dYgc#$expected_backup_path#g" \
        -e "s/1ea24e88eeab706fe64a4005ddadaf6bda3de1236838f05f82cf630f3f298adc/$expected_backup_manifest_sha256/g" \
        -e 's/action19b_retry/action19d/g' \
        -e 's/action19a/action19c/g' \
        "$source_path" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local base_root
    local base_inspector
    local base_runner
    local rendered_inspector
    local rendered_runner
    local rendered_inspector_sha256

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    base_root=$(mktemp -d /tmp/caddy-action19d-a-base.XXXXXX) || return 1
    if ! /bin/bash "$base_derivation" --output-directory "$base_root"; then
        rm -rf -- "$base_root"
        return 1
    fi
    base_inspector=$base_root/inspect-node-b-keepalived-helper-postinstall-action19b-b.sh
    base_runner=$base_root/run-node-b-keepalived-helper-postinstall-action19b-b.sh
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] || {
        rm -rf -- "$base_root"
        return 1
    }
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] || {
        rm -rf -- "$base_root"
        return 1
    }
    rendered_inspector=$output_directory/$rendered_inspector_name
    rendered_runner=$output_directory/$rendered_runner_name
    transform_inspector "$base_inspector" "$rendered_inspector"
    rendered_inspector_sha256=$(file_hash "$rendered_inspector")
    transform_runner "$base_runner" "$rendered_inspector_sha256" \
        "$rendered_runner"
    rm -rf -- "$base_root"

    if grep -Eq \
        'action_19b_b|action19b|action19a|node-b|j1-svpihole00|10\.1\.0\.54|fd36:5aa8:6971:1::54|pihole00\.' \
        "$rendered_inspector" "$rendered_runner"; then
        return 1
    fi
    grep -Fq "readonly expected_backup_path=$expected_backup_path" \
        "$rendered_inspector" "$rendered_runner" || return 1
    grep -Fq "readonly expected_backup_manifest_sha256=$expected_backup_manifest_sha256" \
        "$rendered_inspector" "$rendered_runner" || return 1
}

self_test() {
    local self_test_root

    verify_sources || return 1
    self_test_root=$(mktemp -d /tmp/caddy-action19d-a-derive.XXXXXX) ||
        return 1
    if ! render_pair "$self_test_root"; then
        rm -rf -- "$self_test_root"
        return 1
    fi
    bash -n "$self_test_root/$rendered_inspector_name" \
        "$self_test_root/$rendered_runner_name" || {
        rm -rf -- "$self_test_root"
        return 1
    }
    /bin/bash "$self_test_root/$rendered_inspector_name" --self-test \
        >/dev/null || {
        rm -rf -- "$self_test_root"
        return 1
    }
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
