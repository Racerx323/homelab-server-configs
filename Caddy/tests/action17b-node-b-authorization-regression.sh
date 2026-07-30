#!/usr/bin/env bash

set -euo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly driver="$caddy_root/scripts/authorize-node-a-sync-key-on-node-b-action17b.sh"
readonly runner="$caddy_root/scripts/run-node-b-authorize-node-a-sync-key-action17b.sh"
readonly driver_sha256=ebd126884ec1985b4561d5ac7fc16b54f93fb29e7d5de9fddbe4788925c27efe
readonly runner_sha256=8b9fdd593896a1f613275ca0ea8fe467c4f52f70610321968d563efaad3a7698
readonly node_a_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac+iOUCxRTMM0tA caddy-ha-sync'

assert_hash() {
    local path=$1
    local expected=$2

    [[ "$(sha256sum "$path" | awk '{ print $1 }')" == "$expected" ]]
}

assert_no_forbidden_commands() {
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$driver"; then
        printf 'Action 17b driver contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)|ssh[[:space:]]+-T' \
        "$driver"; then
        printf 'Action 17b driver contains a synchronization or peer command.\n' >&2
        return 1
    fi
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$driver" "$driver_sha256"
assert_hash "$runner" "$runner_sha256"
bash -n "$driver" "$runner"
"$driver" --self-test >/dev/null
"$runner" --contract-test >/dev/null

grep -Fq "readonly node_a_public_key='$node_a_key'" "$driver"
# These are intentional literal shell-source assertions.
# shellcheck disable=SC2016
grep -Fq \
    'readonly expected_authorization="from=\"10.1.0.53,fd36:5aa8:6971:1::53\",restrict,command=\"/usr/local/libexec/caddy-sync-rsync-receiver\" $node_a_public_key"' \
    "$driver"
grep -Fq 'readonly accepted_caddy_release=/etc/caddy/releases/action15-health-follow-redirects' \
    "$driver"
grep -Fq 'install -o caddy-sync -g caddy-sync -m 0600' "$driver"
# shellcheck disable=SC2016
grep -Fq '"$authorization_stage" "$authorized_keys"' "$driver"
# shellcheck disable=SC2016
grep -Fq 'rm -f -- "$authorized_keys"' "$driver"
grep -Fq 'validate_authorization_absent || rollback_failed=true' "$driver"
grep -Fq 'protected_state_unchanged=true' "$driver"
grep -Fq 'persistent_mutation_scope=authorized_keys_only' "$driver"
grep -Fq 'readonly expected_target=pi@10.1.0.54' "$runner"
grep -Fq 'readonly expected_host_alias=pihole00.local.theama.co' "$runner"
grep -Fq 'action_17b_rollback_complete=true' "$runner"
grep -Fq 'manual_intervention_required=true' "$runner"
assert_no_forbidden_commands

printf 'action_17b_node_b_authorization_regression_complete=true\n'
