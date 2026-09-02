#!/bin/bash

set -Eeuo pipefail
umask 077

readonly release_version='v0.26.0'
readonly archive_name='reconya-linux-arm64.tar.gz'
readonly archive_sha256='31e6ee19536e90c24d676446a950feee3d5e8e53fb6ef429e50568eb916be812'
readonly binary_name='reconya-linux-arm64'
readonly binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'
readonly release_base="https://github.com/Dyneteq/reconya/releases/download/$release_version"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s OUTPUT_TAR_GZ\n' "$0" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
readonly output_bundle="$1"
[[ $output_bundle == /* ]] || fail 'OUTPUT_TAR_GZ must be an absolute path'
[[ ! -e $output_bundle ]] || fail "output already exists: $output_bundle"

for command_name in curl sha256sum tar gzip file mktemp; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name"
done

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

curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$work_dir/$archive_name" "$release_base/$archive_name"
curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$work_dir/SHA256SUMS" "$release_base/SHA256SUMS"

publisher_line="$archive_sha256  $archive_name"
readonly publisher_line
publisher_line_count="$(awk -v expected="$publisher_line" '$0 == expected { count++ } END { print count + 0 }' "$work_dir/SHA256SUMS")"
readonly publisher_line_count
[[ $publisher_line_count -eq 1 ]] ||
    fail 'publisher checksum manifest does not contain the one exact pinned archive entry'
printf '%s\n' "$publisher_line" | (cd -- "$work_dir" && sha256sum --check --strict -)

mapfile -t archive_members < <(tar -tzf "$work_dir/$archive_name" | LC_ALL=C sort)
readonly archive_members
[[ ${#archive_members[@]} -eq 2 ]] || fail 'release archive must contain exactly two members'
[[ ${archive_members[0]} == '.env.example' ]] || fail 'unexpected release archive member set'
[[ ${archive_members[1]} == "$binary_name" ]] || fail 'unexpected release archive member set'
[[ -z $(tar -tvzf "$work_dir/$archive_name" | awk '$1 !~ /^-/ { print }') ]] ||
    fail 'release archive contains a non-regular member'

mkdir -m 0700 -- "$work_dir/extracted"
tar -xzf "$work_dir/$archive_name" -C "$work_dir/extracted" --no-same-owner --no-same-permissions
printf '%s  %s\n' "$binary_sha256" "$binary_name" |
    (cd -- "$work_dir/extracted" && sha256sum --check --strict -)
file "$work_dir/extracted/$binary_name" | grep -Fq 'ELF 64-bit LSB executable, ARM aarch64' ||
    fail 'candidate is not an ARM64 ELF executable'

mkdir -m 0700 -- "$work_dir/bundle"
install -m 0600 -- "$work_dir/$archive_name" "$work_dir/bundle/$archive_name"
install -m 0600 -- "$work_dir/SHA256SUMS" "$work_dir/bundle/SHA256SUMS"
install -m 0700 -- "$script_dir/deploy-reconya-update.sh" "$work_dir/bundle/deploy-reconya-update.sh"
install -m 0600 -- "$component_dir/operations/update-v0.26.0.md" "$work_dir/bundle/OPERATION.md"
install -m 0600 -- "$component_dir/manifests/reconya-v0.26.0.sha256" "$work_dir/bundle/reconya-v0.26.0.sha256"

tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "$work_dir/bundle" -cf - . | gzip -n >"$output_bundle"
chmod 0600 -- "$output_bundle"

printf 'bundle=%s\n' "$output_bundle"
printf 'bundle_sha256=%s\n' "$(sha256sum "$output_bundle" | awk '{print $1}')"
