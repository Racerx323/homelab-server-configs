#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-final-deployment-action29i.sh
readonly outer=$caddy_root/scripts/run-final-deployment-acceptance-action29i-outer.sh
readonly dns_probe=$caddy_root/scripts/run-dual-node-dns-record-families-action24-retry4-outer.sh
readonly regression=$test_directory/action29i-final-deployment-acceptance-regression.sh
readonly manifest=$caddy_root/manifests/caddy-final-deployment-acceptance-action29i.yaml
readonly dns_repo=${CADDY_ACTION29F_DNS_REPO:-/home/aaron/code/homelab-dns}

/bin/bash -n "$inspector" "$outer" "$dns_probe" "$regression"
/bin/bash "$regression"
shellcheck "$inspector" "$outer" "$dns_probe" "$regression"
/bin/bash "$test_directory/shfmt-canonical.sh" --check "$inspector" "$outer" "$dns_probe" "$regression"
/bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
/bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/portable-awk-policy.sh" --check "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
/bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
/bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
/bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
if [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]]; then
    [[ "$(sha256sum "$dns_repo/Pi-Hole/configs/pihole-FTL.conf" | awk '{ print $1 }')" = a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3 ]]
    [[ "$(sha256sum "$dns_repo/Pi-Hole/configs/local.theama.co.conf" | awk '{ print $1 }')" = 39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026 ]]
    printf 'action_29i_focused_pihole_v5_sources=passed\n'
else
    printf 'action_29i_focused_pihole_v5_sources=host_authoritative\n'
fi
if command -v yamllint >/dev/null 2>&1; then
    yamllint -s "$manifest"
    printf 'action_29i_focused_yaml_validation=passed\n'
else
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
    printf 'action_29i_focused_yaml_validation=host_authoritative\n'
fi
/bin/bash "$outer" --self-test
printf 'action_29i_focused_validation_complete=true\n'
