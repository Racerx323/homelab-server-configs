#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_builder
readonly source_installer_sha256=186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0
readonly source_runner_sha256=f5aca1865ce91f6c80c46f807aa3517e3f37b92715f9b41ff48ec49bc491779b
readonly template_sha256=af384fc989eaf6581579ace9f09477d23c6612618fb8eca194c37db890992779
readonly candidate_fragment_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_installer=$script_directory/install-node-a-caddy-health-group-action20f.sh
readonly source_runner=$script_directory/run-node-a-caddy-health-group-correction-action20f.sh
readonly template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_builder_label=$1
    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_builder_label" >&2
    return 1
}
transform_common() {
    # Dollar-prefixed expressions are literal successor source.
    # shellcheck disable=SC2016
    sed \
        -e 's/action_20f/action_20g/g' \
        -e 's/action20f/action20g/g' \
        -e 's/Action 20f/Action 20g/g' \
        -e 's/action16ar-retry-node-a-default-deny/action15-health-follow-redirects/g' \
        -e 's/3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5/294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d/g' \
        -e 's/6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39/7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270/g' \
        -e 's/2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8/f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113/g' \
        -e 's/cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2/e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6/g' \
        -e 's/j1-svpihole0/j1-svpihole00/g' \
        -e 's/pihole0\.local\.theama\.co/pihole00.local.theama.co/g' \
        -e 's/10\.1\.0\.53/@ACTION20G_NODE_IPV4@/g' \
        -e 's/10\.1\.0\.54/10.1.0.53/g' \
        -e 's/@ACTION20G_NODE_IPV4@/10.1.0.54/g' \
        -e 's/fd36:5aa8:6971:1::53/@ACTION20G_NODE_IPV6@/g' \
        -e 's/fd36:5aa8:6971:1::54/fd36:5aa8:6971:1::53/g' \
        -e 's/@ACTION20G_NODE_IPV6@/fd36:5aa8:6971:1::54/g' \
        -e 's/@CADDY_PRIORITY@|140/@CADDY_PRIORITY@|100/g' \
        -e 's/hostname_node_a/hostname_node_b/g' \
        -e 's/node=node-a/node=node-b/g' \
        -e 's/node-a-health-group/node-b-health-group/g' \
        -e 's/node_b_contacted/node_a_contacted/g' \
        -e 's/dns_ipv4_present/dns_ipv4_absent/g' \
        -e 's/dns_ipv6_present/dns_ipv6_absent/g' \
        -e 's/dns_ipv4_still_present/dns_ipv4_still_absent/g' \
        -e 's/dns_ipv6_still_present/dns_ipv6_still_absent/g' \
        -e 's/"$dns_ipv4")" -eq 1/"$dns_ipv4")" -eq 0/g' \
        -e 's/"$dns_ipv6")" -eq 1/"$dns_ipv6")" -eq 0/g' \
        -e 's/ -eq 993/ -eq 992/g' \
        -e 's/ -eq 991/ -eq 990/g'
}
build() {
    local action20g_output_root=$1
    local action20g_installer=$action20g_output_root/install-node-b-caddy-health-group-action20g.sh
    local action20g_runner=$action20g_output_root/run-node-b-caddy-health-group-correction-action20g.sh
    local action20g_installer_hash

    install -d -m 0700 "$action20g_output_root"
    transform_common <"$source_installer" >"$action20g_installer"
    chmod 0755 "$action20g_installer"
    action20g_installer_hash=$(file_hash "$action20g_installer")
    transform_common <"$source_runner" |
        sed \
            -e 's/install-node-a-caddy-health-group-action20g/install-node-b-caddy-health-group-action20g/g' \
            -e 's|readonly caddy_root=${script_directory%/scripts}|readonly caddy_root=${CADDY_ACTION20G_SOURCE_ROOT:?}|' \
            -e "s/186dc4cc62e96bf2387e84fb4714618ebd57d31535181d17e46e1a69e76e59d0/$action20g_installer_hash/g" \
            >"$action20g_runner"
    chmod 0755 "$action20g_runner"
    record_check installer_syntax /bin/bash -n "$action20g_installer"
    record_check runner_syntax /bin/bash -n "$action20g_runner"
    record_check candidate_hash_pin grep -Fqx \
        "readonly candidate_fragment_sha256=$candidate_fragment_sha256" "$action20g_installer"
    record_check node_b_target grep -Fqx 'readonly expected_target=pi@10.1.0.54' "$action20g_runner"
    # The prefix expression is literal successor source.
    # shellcheck disable=SC2016
    record_check node_a_contact_prohibited grep -Fq '${prefix}_node_a_contacted=false' "$action20g_runner"
    record_check reload_absent test "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start)[[:space:]]+keepalived' "$action20g_installer" || true)" -eq 0
    printf '%s_installer_sha256=%s\n' "$prefix" "$action20g_installer_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20g_runner")"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        record_check source_installer_hash test "$(file_hash "$source_installer")" = "$source_installer_sha256"
        record_check source_runner_hash test "$(file_hash "$source_runner")" = "$source_runner_sha256"
        record_check template_hash test "$(file_hash "$template")" = "$template_sha256"
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20g_test_root=$(mktemp -d /tmp/caddy-action20g-builder.XXXXXX)
        trap 'rm -rf -- "$action20g_test_root"' EXIT
        build "$action20g_test_root"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
