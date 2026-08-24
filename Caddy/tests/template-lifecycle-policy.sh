#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=template_lifecycle_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
repository_root=${test_directory%/Caddy/tests}
mode=check

if [[ $# -eq 0 ]]; then
    mode=self-test
elif [[ $# -eq 3 && $1 == --check && $2 == --repository-root ]]; then
    repository_root=$3
    [[ "$repository_root" == /tmp/* && -d "$repository_root" &&
        ! -L "$repository_root" ]] || exit 64
elif [[ $# -eq 1 && $1 == --self-test ]]; then
    mode=self-test
elif [[ $# -ne 1 || $1 != --check ]]; then
    exit 64
fi
readonly repository_root
readonly mode
readonly lifecycle_manifest=$repository_root/Caddy/manifests/template-lifecycle.tsv
readonly template_directory=$repository_root/Caddy/templates

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

[[ -f "$lifecycle_manifest" && ! -L "$lifecycle_manifest" ]] ||
    fail manifest_not_regular
diff -u \
    <(find "$template_directory" -maxdepth 1 -type f \
        -printf 'Caddy/templates/%f\n' | LC_ALL=C sort) \
    <(awk -F '\t' '!/^#/ && NF { print $1 }' "$lifecycle_manifest" |
        LC_ALL=C sort) >/dev/null || fail inventory_mismatch

awk -F '\t' '
    /^#/ || !NF { next }
    NF != 4 { invalid = 1; exit }
    $2 !~ /^(production-current|future-task)$/ { invalid = 1; exit }
    $3 !~ /^(yes|no)$/ { invalid = 1; exit }
    $2 == "production-current" && $3 == "no" && $1 != "Caddy/templates/README.md" { invalid = 1; exit }
    $2 == "future-task" && $3 != "no" { invalid = 1; exit }
    seen[$1]++ { invalid = 1; exit }
    END { exit invalid || length(seen) == 0 }
' "$lifecycle_manifest" || fail invalid_manifest_contract

grep -Fxq \
    $'Caddy/templates/README.md\tproduction-current\tno\tCaddy/templates/README.md' \
    "$lifecycle_manifest" || fail template_readme
grep -Fxq \
    $'Caddy/templates/authorized-key-receiver-finalized-v2.in\tproduction-current\tyes\tCaddy/manifests/synchronization-protocol-v2.yaml' \
    "$lifecycle_manifest" || fail receiver_template
grep -Fxq \
    $'Caddy/templates/caddy-ha.env-v2.in\tproduction-current\tyes\tCaddy/templates/caddy-ha.env-v2.in' \
    "$lifecycle_manifest" || fail environment_template
grep -Fxq \
    $'Caddy/templates/reverse-proxy.caddy.example\tfuture-task\tno\tCaddy/docs/caddy_plan-v1.1.md' \
    "$lifecycle_manifest" || fail future_reverse_proxy_template

[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-a.lua" ]] ||
    fail node_a_lsyncd_missing
[[ -f "$repository_root/Caddy/configs/lsyncd/caddy-node-b.lua" ]] ||
    fail node_b_lsyncd_missing
! grep -Eq 'include-historical|keepalived-caddy-ha|templates/lsyncd-' \
    "$repository_root/Caddy/scripts/render-node-config.sh" ||
    fail renderer_nonproduction_consumer

if [[ "$mode" = self-test ]]; then
    work_root=$(mktemp -d /tmp/caddy-template-lifecycle.XXXXXX)
    trap 'rm -rf -- "$work_root"' EXIT
    mkdir -p "$work_root/Caddy/manifests" "$work_root/Caddy/templates" \
        "$work_root/Caddy/configs/lsyncd" "$work_root/Caddy/scripts"
    cp -a "$repository_root/Caddy/templates/." "$work_root/Caddy/templates/"
    cp -a "$repository_root/Caddy/configs/lsyncd/." "$work_root/Caddy/configs/lsyncd/"
    cp "$repository_root/Caddy/manifests/template-lifecycle.tsv" \
        "$work_root/Caddy/manifests/"
    cp "$repository_root/Caddy/scripts/render-node-config.sh" \
        "$work_root/Caddy/scripts/"
    printf 'obsolete\n' >"$work_root/Caddy/templates/obsolete.in"
    if /bin/bash "$0" --check --repository-root "$work_root" >/dev/null 2>&1; then
        printf '%s_unregistered_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_unregistered_rejected=true\n' "$prefix"
fi

printf '%s_complete=true\n' "$prefix"
