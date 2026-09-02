#!/bin/bash

set -Eeuo pipefail
umask 077

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail 'usage: prepare-reconya-environment-config-deployment.sh OUTPUT_TAR_GZ'
readonly output_bundle="$1"
[[ $output_bundle == /* ]] || fail 'output path must be absolute'
[[ ! -e $output_bundle ]] || fail "output already exists: $output_bundle"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
component_dir="$(cd -- "$script_dir/.." && pwd)"
readonly component_dir
work_dir="$(mktemp -d)"
readonly work_dir
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

mkdir -m 0700 -- "$work_dir/bundle"
install -m 0600 -- "$component_dir/configs/svmf.env.example" "$work_dir/bundle/svmf.env.example"
install -m 0700 -- "$script_dir/deploy-reconya-environment-config.sh" "$work_dir/bundle/deploy-reconya-environment-config.sh"
install -m 0600 -- "$component_dir/operations/reconcile-environment-config.md" "$work_dir/bundle/OPERATION.md"

(
    cd -- "$work_dir/bundle"
    sha256sum -- OPERATION.md deploy-reconya-environment-config.sh svmf.env.example >BUNDLE-SHA256SUMS
)

tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "$work_dir/bundle" -cf - . | gzip -n >"$output_bundle"
chmod 0600 -- "$output_bundle"
printf 'bundle=%s\n' "$output_bundle"
printf 'bundle_sha256=%s\n' "$(sha256sum -- "$output_bundle" | awk '{print $1}')"
