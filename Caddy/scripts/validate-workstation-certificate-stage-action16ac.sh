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
readonly minimum_days=30
readonly leaf_sha256=4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319
readonly intermediates_sha256=6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d
readonly fullchain_sha256=d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83
readonly manifest_sha256=0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df
readonly expected_not_after='Jan 19 23:59:59 2027 GMT'

readonly leaf="$stage/leaf.pem"
readonly intermediates="$stage/intermediates.pem"
readonly fullchain="$stage/fullchain.pem"
readonly private_key="$stage/privkey.pem"
readonly manifest="$stage/certificate-manifest.json"

stage_file_list() {
    find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
}

stage_metadata() {
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        "$stage" \
        "$leaf" \
        "$intermediates" \
        "$fullchain" \
        "$private_key" \
        "$manifest"
}

public_hashes() {
    sha256sum "$leaf" "$intermediates" "$fullchain" "$manifest"
}

leaf_public_key_hash() {
    openssl x509 -in "$leaf" -pubkey -noout |
        openssl pkey -pubin -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

private_public_key_hash() {
    openssl pkey -in "$private_key" -pubout -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$minimum_days" -eq 30 ]]
    [[ "$leaf_sha256" == 4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319 ]]
    [[ "$intermediates_sha256" == 6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d ]]
    [[ "$fullchain_sha256" == d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83 ]]
    [[ "$manifest_sha256" == 0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df ]]
    printf 'action_16ac_certificate_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -un)" == "$expected_owner" ]]
[[ "$(id -gn)" == "$expected_group" ]]
for command_path in \
    /usr/bin/awk \
    /usr/bin/cat \
    /usr/bin/cmp \
    /usr/bin/cut \
    /usr/bin/find \
    /usr/bin/grep \
    /usr/bin/jq \
    /usr/bin/openssl \
    /usr/bin/sed \
    /usr/bin/sha256sum \
    /usr/bin/stat \
    /usr/bin/tail \
    /usr/bin/tr; do
    [[ -x "$command_path" ]]
done

[[ -d "$stage" && ! -L "$stage" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == "$expected_owner:$expected_group:750" ]]
mapfile -t files_before < <(stage_file_list)
expected_files=(
    certificate-manifest.json
    fullchain.pem
    intermediates.pem
    leaf.pem
    privkey.pem
)
[[ "${files_before[*]}" == "${expected_files[*]}" ]]
if find "$stage" -type l -print -quit | grep -q .; then
    printf 'Certificate stage contains a symbolic link.\n' >&2
    exit 1
fi

for public_file in "$leaf" "$intermediates" "$fullchain" "$manifest"; do
    [[ -f "$public_file" && ! -L "$public_file" ]]
    [[ "$(stat -c '%U:%G:%a' "$public_file")" == "$expected_owner:$expected_group:644" ]]
done
[[ -f "$private_key" && ! -L "$private_key" ]]
[[ "$(stat -c '%U:%G:%a' "$private_key")" == "$expected_owner:$expected_group:640" ]]

[[ "$(sha256sum "$leaf" | awk '{ print $1 }')" == "$leaf_sha256" ]]
[[ "$(sha256sum "$intermediates" | awk '{ print $1 }')" == "$intermediates_sha256" ]]
[[ "$(sha256sum "$fullchain" | awk '{ print $1 }')" == "$fullchain_sha256" ]]
[[ "$(sha256sum "$manifest" | awk '{ print $1 }')" == "$manifest_sha256" ]]

metadata_before=$(stage_metadata)
public_hashes_before=$(public_hashes)
private_hash_before=$(sha256sum "$private_key" | awk '{ print $1 }')

openssl x509 -in "$leaf" -noout >/dev/null
openssl pkey -in "$private_key" -check -noout >/dev/null 2>&1
openssl x509 -in "$leaf" -checkend "$((minimum_days * 86400))" -noout \
    >/dev/null
not_after=$(openssl x509 -in "$leaf" -noout -enddate | cut -d= -f2-)
[[ "$not_after" == "$expected_not_after" ]]

sans=$(
    openssl x509 -in "$leaf" -noout -ext subjectAltName |
        tail -n +2 |
        tr -d '\n' |
        sed 's/^[[:space:]]*//'
)
grep -Fq 'DNS:*.local.theama.co' <<<"$sans"

certificate_key_hash=$(leaf_public_key_hash)
private_key_public_hash=$(private_public_key_hash)
[[ "$certificate_key_hash" == "$private_key_public_hash" ]]

leaf_subject=$(
    openssl x509 -in "$leaf" -noout -subject -nameopt RFC2253 |
        cut -d= -f2-
)
expected_issuer=$(
    openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 |
        cut -d= -f2-
)
[[ "$leaf_subject" != "$expected_issuer" ]]

certificate=
certificate_count=0
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == '-----BEGIN CERTIFICATE-----' ]]; then
        [[ -z "$certificate" ]]
        certificate=$line$'\n'
        continue
    fi
    [[ -n "$certificate" ]] || {
        [[ -z "$line" ]]
        continue
    }
    certificate+=$line$'\n'
    if [[ "$line" != '-----END CERTIFICATE-----' ]]; then
        continue
    fi

    subject=$(
        openssl x509 -in <(printf '%s' "$certificate") \
            -noout -subject -nameopt RFC2253 |
            cut -d= -f2-
    )
    issuer=$(
        openssl x509 -in <(printf '%s' "$certificate") \
            -noout -issuer -nameopt RFC2253 |
            cut -d= -f2-
    )
    [[ "$subject" != "$issuer" ]]
    [[ "$subject" == "$expected_issuer" ]]
    expected_issuer=$issuer
    certificate=
    ((certificate_count += 1))
done <"$intermediates"
[[ -z "$certificate" ]]
[[ "$certificate_count" -ge 1 ]]

cmp -s "$fullchain" <(cat "$leaf" "$intermediates")
openssl verify \
    -purpose sslserver \
    -CApath /etc/ssl/certs \
    -untrusted "$intermediates" \
    "$leaf" >/dev/null

manifest_subject=$(jq -er '.subject' "$manifest")
manifest_issuer=$(jq -er '.issuer' "$manifest")
manifest_not_before=$(jq -er '.not_before' "$manifest")
manifest_not_after=$(jq -er '.not_after' "$manifest")
manifest_fingerprint=$(jq -er '.fingerprint_sha256' "$manifest")
manifest_public_key=$(jq -er '.public_key_sha256' "$manifest")
manifest_sans=$(jq -er '.subject_alt_names' "$manifest")
manifest_leaf=$(jq -er '.leaf_sha256' "$manifest")
manifest_fullchain=$(jq -er '.fullchain_sha256' "$manifest")
fingerprint=$(
    openssl x509 -in "$leaf" -noout -fingerprint -sha256 |
        cut -d= -f2
)
not_before=$(openssl x509 -in "$leaf" -noout -startdate | cut -d= -f2-)
leaf_issuer=$(
    openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 |
        cut -d= -f2-
)

jq -e '
  keys == [
    "fingerprint_sha256",
    "fullchain_sha256",
    "issuer",
    "leaf_sha256",
    "not_after",
    "not_before",
    "public_key_sha256",
    "subject",
    "subject_alt_names"
  ]
' "$manifest" >/dev/null
[[ "$manifest_subject" == "$leaf_subject" ]]
[[ "$manifest_issuer" == "$leaf_issuer" ]]
[[ "$manifest_not_before" == "$not_before" ]]
[[ "$manifest_not_after" == "$not_after" ]]
[[ "$manifest_fingerprint" == "$fingerprint" ]]
[[ "$manifest_public_key" == "$certificate_key_hash" ]]
[[ "$manifest_sans" == "$sans" ]]
[[ "$manifest_leaf" == "$leaf_sha256" ]]
[[ "$manifest_fullchain" == "$fullchain_sha256" ]]

mapfile -t files_after < <(stage_file_list)
[[ "${files_after[*]}" == "${files_before[*]}" ]]
[[ "$(stage_metadata)" == "$metadata_before" ]]
[[ "$(public_hashes)" == "$public_hashes_before" ]]
[[ "$(sha256sum "$private_key" | awk '{ print $1 }')" == "$private_hash_before" ]]

printf 'certificate_stage=%s\n' "$stage"
printf 'certificate_leaf_sha256=%s\n' "$leaf_sha256"
printf 'certificate_intermediates_sha256=%s\n' "$intermediates_sha256"
printf 'certificate_fullchain_sha256=%s\n' "$fullchain_sha256"
printf 'certificate_manifest_sha256=%s\n' "$manifest_sha256"
printf 'certificate_not_after=%s\n' "$not_after"
printf 'certificate_intermediate_count=%s\n' "$certificate_count"
printf 'certificate_wildcard_san_present=true\n'
printf 'certificate_key_match=true\n'
printf 'certificate_chain_complete=true\n'
printf 'certificate_stage_unchanged=true\n'
printf 'certificate_stage_continuity_action16ac_complete=true\n'
