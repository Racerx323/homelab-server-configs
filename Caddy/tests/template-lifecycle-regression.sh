#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly policy=$test_directory/template-lifecycle-policy.sh

/bin/bash "$policy" --check >/dev/null

work_root=$(mktemp -d /tmp/caddy-template-lifecycle.XXXXXX)
readonly work_root
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
if /bin/bash "$policy" --check --repository-root "$work_root" >/dev/null 2>&1; then
    printf 'template_lifecycle_regression_unregistered_accepted=false\n' >&2
    exit 1
fi
printf 'template_lifecycle_regression_unregistered_rejected=true\n'
printf 'template_lifecycle_regression_complete=true\n'
