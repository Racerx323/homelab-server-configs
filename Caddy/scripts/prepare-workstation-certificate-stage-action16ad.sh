#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly stage=/tmp/caddy-cert-node-b-action12
readonly expected_owner=aaron
readonly expected_group=aaron
readonly doppler_project=homelab-dev
readonly doppler_config=prd_caddy
readonly doppler_version=v3.76.1
readonly prepare_sha256=b2c6fa80b33e7dae20efed8da36b9c00c33fff40278d001467cad2de2880feb9
readonly validator_sha256=fbca4722dc3da0f28ab44bea9fb8b846cac9bb25439658ad3d3b33815250aacb

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly prepare_script="$script_dir/prepare-certificate.sh"
readonly validator="$script_dir/validate-workstation-certificate-stage-action16ac.sh"

if [[ "${1:-}" == --self-test ]]; then
    [[ "$stage" == /tmp/caddy-cert-node-b-action12 ]]
    [[ "$expected_owner:$expected_group" == aaron:aaron ]]
    [[ "$doppler_project/$doppler_config" == homelab-dev/prd_caddy ]]
    [[ "$doppler_version" == v3.76.1 ]]
    [[ "$prepare_sha256" == b2c6fa80b33e7dae20efed8da36b9c00c33fff40278d001467cad2de2880feb9 ]]
    [[ "$validator_sha256" == fbca4722dc3da0f28ab44bea9fb8b846cac9bb25439658ad3d3b33815250aacb ]]
    printf 'action_16ad_workstation_certificate_preparation_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -un)" == "$expected_owner" ]]
[[ "$(id -gn)" == "$expected_group" ]]
[[ -x /usr/bin/doppler ]]
[[ "$(/usr/bin/doppler --version)" == "$doppler_version" ]]

for artifact in "$prepare_script" "$validator"; do
    [[ -f "$artifact" && ! -L "$artifact" ]]
    [[ "$(stat -c '%U:%G:%a' "$artifact")" == "$expected_owner:$expected_group:755" ]]
done
[[ "$(sha256sum "$prepare_script" | awk '{ print $1 }')" == "$prepare_sha256" ]]
[[ "$(sha256sum "$validator" | awk '{ print $1 }')" == "$validator_sha256" ]]

[[ ! -e "$stage" && ! -L "$stage" ]]

cleanup_armed=true
cleanup() {
    if [[ "$cleanup_armed" == true ]]; then
        /usr/bin/rm -rf --one-file-system -- "$stage"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

/usr/bin/env \
    -u CADDY_TLS_CERT_PEM \
    -u CADDY_TLS_CA_BUNDLE_PEM \
    -u CADDY_TLS_PRIVATE_KEY_PEM \
    /usr/bin/doppler run \
    --project "$doppler_project" \
    --config "$doppler_config" \
    -- \
    "$prepare_script" \
    --output "$stage"

"$validator"

cleanup_armed=false
trap - EXIT HUP INT TERM

printf 'doppler_project=%s\n' "$doppler_project"
printf 'doppler_config=%s\n' "$doppler_config"
printf 'doppler_version=%s\n' "$doppler_version"
printf 'workstation_certificate_preparation_action16ad_complete=true\n'
