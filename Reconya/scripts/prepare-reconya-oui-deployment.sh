#!/bin/bash

set -Eeuo pipefail
umask 077

readonly seed_sha256='e2fa93fcf56ce075e9fc860d47fb7ed1dc35a6e7b2617bea011475d09b804552'
readonly seed_records=40049

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ $# -eq 2 ]] || fail 'usage: prepare-reconya-oui-deployment.sh SEED_OUI_TXT OUTPUT_TAR_GZ'
readonly seed_file="$1"
readonly output_bundle="$2"
[[ $seed_file == /* && $output_bundle == /* ]] || fail 'both paths must be absolute'
[[ -f $seed_file && ! -L $seed_file ]] || fail 'seed must be a regular non-symlink'
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

[[ $(sha256sum -- "$seed_file" | awk '{print $1}') == "$seed_sha256" ]] || fail 'seed checksum mismatch'
[[ $(/bin/bash "$script_dir/update-reconya-oui.sh" validate "$seed_file") -eq $seed_records ]] ||
    fail 'seed structure or record count mismatch'

mkdir -m 0700 -- "$work_dir/bundle"
install -m 0600 -- "$seed_file" "$work_dir/bundle/oui.txt"
install -m 0700 -- "$script_dir/deploy-reconya-oui-updater.sh" "$work_dir/bundle/deploy-reconya-oui-updater.sh"
install -m 0700 -- "$script_dir/update-reconya-oui.sh" "$work_dir/bundle/update-reconya-oui.sh"
install -m 0600 -- "$component_dir/templates/reconya-oui-update.service" "$work_dir/bundle/reconya-oui-update.service"
install -m 0600 -- "$component_dir/templates/reconya-oui-update.timer" "$work_dir/bundle/reconya-oui-update.timer"
install -m 0600 -- "$component_dir/operations/install-oui-updater.md" "$work_dir/bundle/OPERATION.md"

(
    cd -- "$work_dir/bundle"
    sha256sum -- OPERATION.md deploy-reconya-oui-updater.sh oui.txt \
        reconya-oui-update.service reconya-oui-update.timer update-reconya-oui.sh \
        >BUNDLE-SHA256SUMS
)

tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "$work_dir/bundle" -cf - . | gzip -n >"$output_bundle"
chmod 0600 -- "$output_bundle"
printf 'bundle=%s\n' "$output_bundle"
printf 'bundle_sha256=%s\n' "$(sha256sum -- "$output_bundle" | awk '{print $1}')"
