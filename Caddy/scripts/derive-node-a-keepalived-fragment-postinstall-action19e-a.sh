#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19e_a
readonly base_inspector_sha256=d0869e875dd02e4e7e9658aa832ffd5851f6533d61e645571ff59d3e892deb77
readonly base_runner_sha256=0148cae3443a7ad8d08e5ea77a5de38fe9d5e68772521968a8bde15294b96ecb
readonly node_b_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly node_a_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
readonly node_b_backup=/var/backups/caddy-ha/action19a-node-b-keepalived-fragment.no5a5x
readonly node_a_backup=/var/backups/caddy-ha/action19e-node-a-keepalived-fragment.JgYBbS
readonly node_b_release=/etc/caddy/releases/action15-health-follow-redirects
readonly node_a_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly rendered_inspector_name=inspect-node-a-keepalived-fragment-postinstall-action19e-a.sh
readonly rendered_runner_name=run-node-a-keepalived-fragment-postinstall-action19e-a.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_inspector="$script_directory/inspect-node-b-keepalived-fragment-postinstall-action19a-b.sh"
readonly base_runner="$script_directory/run-node-b-keepalived-fragment-postinstall-action19a-b.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_inspector" && ! -L "$base_inspector" ]] || return 1
    [[ -f "$base_runner" && ! -L "$base_runner" ]] || return 1
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] ||
        return 1
}

transform_common() {
    sed \
        -e 's/action_19a_b/action_19e_a/g' \
        -e 's/action19a-b/action19e-a/g' \
        -e 's/ACTION19AB/ACTION19EA/g' \
        -e 's/CADDY_ACTION19AB/CADDY_ACTION19EA/g' \
        -e "s#$node_b_backup#$node_a_backup#g" \
        -e "s#$node_b_fragment_sha256#$node_a_fragment_sha256#g" \
        -e "s#$node_b_release#$node_a_release#g" \
        "$1"
}

transform_inspector() {
    local output_path=$1
    local transformed_path

    transformed_path=$(mktemp /tmp/caddy-action19e-a-inspector.XXXXXX) ||
        return 1
    transform_common "$base_inspector" |
        sed \
            -e 's/hostname_node_b/hostname_node_a/g' \
            -e 's/j1-svpihole00/j1-svpihole0/g' \
            -e 's/10\.1\.0\.54\/22/10.1.0.53\/22/g' \
            -e 's/fd36:5aa8:6971:1::54\/64/fd36:5aa8:6971:1::53\/64/g' \
            -e 's/priority 100/priority 140/g' \
            -e 's/unicast_src_ip 10\.1\.0\.54/unicast_src_ip 10.1.0.53/g' \
            -e 's/10\.1\.0\.53 min_ttl 255 max_ttl 255/10.1.0.54 min_ttl 255 max_ttl 255/g' \
            -e 's/unicast_src_ip fd36:5aa8:6971:1::54/unicast_src_ip fd36:5aa8:6971:1::53/g' \
            -e 's/fd36:5aa8:6971:1::53 min_ttl 255 max_ttl 255/fd36:5aa8:6971:1::54 min_ttl 255 max_ttl 255/g' \
            -e 's/action19a_run_stage/action19e_run_stage/g' \
            -e 's/action19a_tmp_stage/action19e_tmp_stage/g' \
            -e 's/action19a_install_stage/action19e_install_stage/g' \
            -e 's/action19a-node-b-keepalived-fragment/action19e-node-a-keepalived-fragment/g' \
            -e 's/caddy-action19a-stage/caddy-action19e-stage/g' \
            -e 's/caddy-action19a-/caddy-action19e-/g' \
            -e 's/\.caddy-ha\.conf\.action19a\./.caddy-ha.conf.action19e./g' \
            -e "s/action=action19a/action=action19e/g" \
            -e 's/node=node-b/node=node-a/g' \
            >"$transformed_path"
    install -m 0755 "$transformed_path" "$output_path"
    rm -f -- "$transformed_path"
}

transform_runner() {
    local inspector_hash=$1
    local output_path=$2
    local transformed_path

    transformed_path=$(mktemp /tmp/caddy-action19e-a-runner.XXXXXX) ||
        return 1
    transform_common "$base_runner" |
        sed \
            -e "s/$base_inspector_sha256/$inspector_hash/g" \
            -e 's#inspect-node-b-keepalived-fragment-postinstall-action19e-a\.sh#inspect-node-a-keepalived-fragment-postinstall-action19e-a.sh#g' \
            -e 's/pihole00\.local\.theama\.co/pihole0.local.theama.co/g' \
            -e 's/pi@10\.1\.0\.54/pi@10.1.0.53/g' \
            >"$transformed_path"
    install -m 0755 "$transformed_path" "$output_path"
    rm -f -- "$transformed_path"
}

render_pair() {
    local output_directory=$1
    local rendered_inspector=$output_directory/$rendered_inspector_name
    local rendered_runner=$output_directory/$rendered_runner_name
    local rendered_inspector_sha256

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    transform_inspector "$rendered_inspector" || return 1
    rendered_inspector_sha256=$(file_hash "$rendered_inspector") || return 1
    transform_runner "$rendered_inspector_sha256" "$rendered_runner" || return 1

    grep -Fq "readonly expected_backup_path=$node_a_backup" \
        "$rendered_inspector" "$rendered_runner" || return 1
    grep -Fq "readonly expected_fragment_sha256=$node_a_fragment_sha256" \
        "$rendered_inspector" "$rendered_runner" || return 1
    grep -Fq "readonly expected_active_release=$node_a_release" \
        "$rendered_inspector" || return 1
    grep -Fq 'hostname_node_a' "$rendered_inspector" || return 1
    grep -Fq 'priority 140' "$rendered_inspector" || return 1
    grep -Fq 'HostKeyAlias=pihole0.local.theama.co' "$rendered_runner" ||
        return 1
    grep -Fq 'pi@10.1.0.53' "$rendered_runner" || return 1
    ! grep -Eq 'node-b|pihole00|10\.1\.0\.54/22|::54/64|priority 100|action19a' \
        "$rendered_inspector" "$rendered_runner" || return 1
}

self_test() {
    local self_test_root

    verify_sources || return 1
    self_test_root=$(mktemp -d /tmp/caddy-action19e-a-derive.XXXXXX) ||
        return 1
    render_pair "$self_test_root" || {
        rm -rf -- "$self_test_root"
        return 1
    }
    bash -n "$self_test_root/$rendered_inspector_name" \
        "$self_test_root/$rendered_runner_name" || {
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
