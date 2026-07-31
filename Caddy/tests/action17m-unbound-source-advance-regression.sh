#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
workspace_root=$(cd -- "$caddy_root/../.." && pwd)
readonly workspace_root
readonly source_local_zone="$workspace_root/homelab-dns/Unbound/configs/pihole0-local-zone.conf"
readonly current_source_sha256=fdd771afc7069e9bb5c08367798f454b36bd5fbc2be0be4b0cd0b251ca01218b
readonly prior_source_sha256=e59624fdbb47e7e059177ea7ca86c39179a71e77fdcdbf640753cc73be44a23f
readonly accepted_live_sha256=8a7d1c6d2235e6f37a98dfd3e10165b49968fcc5f3e898ce0b359f70bc0456d1

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_artifact_hash() {
    local artifact_path=$1
    local expected_hash=$2

    [[ -f "$artifact_path" && ! -L "$artifact_path" ]]
    [[ "$(file_hash "$artifact_path")" == "$expected_hash" ]]
}

strip_pi_hole_ula_advance() {
    sed \
        -e '/pihole[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::55/d' \
        -e '/pihole0[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::53/d' \
        -e '/pihole00[.]local[.]theama[.]co[.].*IN AAAA fd36:5aa8:6971:1::54/d' \
        -e '/local-data-ptr: "fd36:5aa8:6971:1::55 pihole[.]local[.]theama[.]co[.]"/d' \
        -e '/local-data-ptr: "fd36:5aa8:6971:1::53 pihole0[.]local[.]theama[.]co[.]"/d' \
        -e '/local-data-ptr: "fd36:5aa8:6971:1::54 pihole00[.]local[.]theama[.]co[.]"/d' \
        "$1"
}

run_regression() {
    local prior_reconstructed_hash
    local live_reconstructed_hash
    local record_text
    local -a record_texts=(
        '    local-data: "pihole.local.theama.co. IN AAAA fd36:5aa8:6971:1::55"'
        '    local-data: "pihole0.local.theama.co. IN AAAA fd36:5aa8:6971:1::53"'
        '    local-data: "pihole00.local.theama.co. IN AAAA fd36:5aa8:6971:1::54"'
        '    local-data-ptr: "fd36:5aa8:6971:1::55 pihole.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::53 pihole0.local.theama.co."'
        '    local-data-ptr: "fd36:5aa8:6971:1::54 pihole00.local.theama.co."'
    )

    assert_artifact_hash \
        "$caddy_root/scripts/inspect-dual-node-dns-sync-readiness-action17l.sh" \
        fe8d5f2e0a2fb245d35d695747286141ed75e83147f6b00ce46729da6ec1a80a
    assert_artifact_hash \
        "$caddy_root/tests/action17l-dual-node-dns-sync-readiness-regression.sh" \
        d94d32b571059c85bdd4b105ce0de914f5711619e4a17d98a57ac9132bb78417
    assert_artifact_hash \
        "$caddy_root/tests/action17l-historical-unbound-source-advance-regression.sh" \
        2e06d533ea7b2af529fa9ba5b5f272c7a75e33115473f2ec1a06dc3dd3878269
    assert_artifact_hash \
        "$caddy_root/scripts/run-dual-node-dns-sync-readiness-action17l.sh" \
        2e20f239f3bf7bd0cb8c6a0ad59e0caab7ddfb95c3637638c08dd17208828102
    assert_artifact_hash "$source_local_zone" "$current_source_sha256"

    for record_text in "${record_texts[@]}"; do
        [[ "$(grep -Fxc "$record_text" "$source_local_zone" || true)" -eq 1 ]]
    done
    [[ "$(grep -Fxc \
        '    local-data: "homeassistant.local.theama.co. IN A 10.1.2.120"' \
        "$source_local_zone" || true)" -eq 1 ]]
    [[ "$(grep -Fxc \
        '    local-data-ptr: "10.1.2.120 homeassistant.local.theama.co."' \
        "$source_local_zone" || true)" -eq 1 ]]
    [[ "$(grep -Ec \
        'homeassistant[.]local[.]theama[.]co[.].*IN AAAA|local-data-ptr:.*(2600:|fe80:|fd36:).*homeassistant' \
        "$source_local_zone" || true)" -eq 0 ]]
    [[ "$(grep -Ec \
        'proxy[.]local[.]theama[.]co|pihole-admin[.]local[.]theama[.]co|::56|10[.]1[.]0[.]56' \
        "$source_local_zone" || true)" -eq 0 ]]

    prior_reconstructed_hash=$(
        strip_pi_hole_ula_advance "$source_local_zone" | sha256sum |
            awk '{ print $1 }'
    )
    [[ "$prior_reconstructed_hash" == "$prior_source_sha256" ]]
    live_reconstructed_hash=$(
        strip_pi_hole_ula_advance "$source_local_zone" |
            sed '/homeassistant[.]local[.]theama[.]co/d' |
            sha256sum | awk '{ print $1 }'
    )
    [[ "$live_reconstructed_hash" == "$accepted_live_sha256" ]]

    printf 'action_17m_unbound_source_advance_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
