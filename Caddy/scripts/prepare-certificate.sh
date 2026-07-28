#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --output DIRECTORY [--minimum-days DAYS]\n' "${0##*/}"
}

output_dir=
minimum_days=30

while (($#)); do
    case "$1" in
        --output)
            output_dir=${2:-}
            shift 2
            ;;
        --minimum-days)
            minimum_days=${2:-}
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$output_dir" || ! "$minimum_days" =~ ^[0-9]+$ ]]; then
    usage >&2
    exit 2
fi

for variable_name in \
    CADDY_TLS_CERT_PEM \
    CADDY_TLS_CA_BUNDLE_PEM \
    CADDY_TLS_PRIVATE_KEY_PEM; do
    if [[ -z "${!variable_name:-}" ]]; then
        printf 'Required Doppler variable is empty: %s\n' "$variable_name" >&2
        exit 2
    fi
done

umask 077
mkdir -p -- "$output_dir"
chmod 0750 "$output_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-cert.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

leaf="$work_dir/leaf.pem"
bundle="$work_dir/ca-bundle.pem"
private_key="$work_dir/privkey.pem"

printf '%s\n' "$CADDY_TLS_CERT_PEM" >"$leaf"
printf '%s\n' "$CADDY_TLS_CA_BUNDLE_PEM" >"$bundle"
printf '%s\n' "$CADDY_TLS_PRIVATE_KEY_PEM" >"$private_key"

openssl x509 -in "$leaf" -noout >/dev/null
openssl pkey -in "$private_key" -noout >/dev/null

if ! openssl x509 -in "$leaf" -noout -ext subjectAltName |
    grep -Fq 'DNS:*.local.theama.co'; then
    printf 'Certificate does not contain DNS:*.local.theama.co.\n' >&2
    exit 1
fi

seconds_required=$((minimum_days * 86400))
if ! openssl x509 -in "$leaf" -checkend "$seconds_required" -noout; then
    printf 'Certificate expires within %s days.\n' "$minimum_days" >&2
    exit 1
fi

certificate_key_hash=$(
    openssl x509 -in "$leaf" -pubkey -noout |
        openssl pkey -pubin -outform DER 2>/dev/null |
        sha256sum |
        awk '{print $1}'
)
private_key_hash=$(
    openssl pkey -in "$private_key" -pubout -outform DER 2>/dev/null |
        sha256sum |
        awk '{print $1}'
)

if [[ "$certificate_key_hash" != "$private_key_hash" ]]; then
    printf 'Private key does not match the certificate.\n' >&2
    exit 1
fi

split_dir="$work_dir/split"
mkdir -p "$split_dir"
awk -v directory="$split_dir" '
    /-----BEGIN CERTIFICATE-----/ {
        count++
        filename = sprintf("%s/ca-%03d.pem", directory, count)
    }
    count > 0 {
        print > filename
    }
    /-----END CERTIFICATE-----/ {
        close(filename)
    }
' "$bundle"

shopt -s nullglob
ca_files=("$split_dir"/ca-*.pem)
if ((${#ca_files[@]} == 0)); then
    printf 'CA bundle contains no certificates.\n' >&2
    exit 1
fi

intermediates="$work_dir/intermediates.pem"
: >"$intermediates"
expected_issuer=$(
    openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 |
        cut -d= -f2-
)
root_subjects=()
for ca_file in "${ca_files[@]}"; do
    openssl x509 -in "$ca_file" -noout >/dev/null
    subject=$(openssl x509 -in "$ca_file" -noout -subject -nameopt RFC2253)
    issuer=$(openssl x509 -in "$ca_file" -noout -issuer -nameopt RFC2253)
    subject=${subject#subject=}
    issuer=${issuer#issuer=}
    if [[ "$subject" == "$issuer" ]]; then
        root_subjects+=("$subject")
        continue
    fi
    if [[ "$subject" != "$expected_issuer" ]]; then
        printf 'CA bundle is not in leaf-to-root chain order.\n' >&2
        exit 1
    fi
    cat "$ca_file" >>"$intermediates"
    expected_issuer=$issuer
done

if [[ ! -s "$intermediates" ]]; then
    printf 'CA bundle contains no intermediate certificates.\n' >&2
    exit 1
fi

root_match=false
for root_subject in "${root_subjects[@]}"; do
    if [[ "$root_subject" == "$expected_issuer" ]]; then
        root_match=true
        break
    fi
done
if [[ "$root_match" != true ]]; then
    printf 'CA bundle does not contain the chain root needed for completeness validation.\n' \
        >&2
    exit 1
fi

openssl verify -CAfile "$bundle" -untrusted "$intermediates" "$leaf" >/dev/null

fullchain="$work_dir/fullchain.pem"
cat "$leaf" "$intermediates" >"$fullchain"

install -m 0644 "$leaf" "$output_dir/leaf.pem"
install -m 0644 "$intermediates" "$output_dir/intermediates.pem"
install -m 0644 "$fullchain" "$output_dir/fullchain.pem"
install -m 0640 "$private_key" "$output_dir/privkey.pem"

fingerprint=$(openssl x509 -in "$leaf" -noout -fingerprint -sha256 | cut -d= -f2)
subject=$(openssl x509 -in "$leaf" -noout -subject -nameopt RFC2253 | cut -d= -f2-)
issuer=$(openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 | cut -d= -f2-)
not_before=$(openssl x509 -in "$leaf" -noout -startdate | cut -d= -f2-)
not_after=$(openssl x509 -in "$leaf" -noout -enddate | cut -d= -f2-)
sans=$(
    openssl x509 -in "$leaf" -noout -ext subjectAltName |
        tail -n +2 |
        tr -d '\n' |
        sed 's/^[[:space:]]*//'
)

jq -n \
    --arg subject "$subject" \
    --arg issuer "$issuer" \
    --arg not_before "$not_before" \
    --arg not_after "$not_after" \
    --arg fingerprint "$fingerprint" \
    --arg public_key_sha256 "$certificate_key_hash" \
    --arg sans "$sans" \
    --arg leaf_sha256 "$(sha256sum "$output_dir/leaf.pem" | awk '{print $1}')" \
    --arg chain_sha256 "$(sha256sum "$output_dir/fullchain.pem" | awk '{print $1}')" \
    '{
        subject: $subject,
        issuer: $issuer,
        not_before: $not_before,
        not_after: $not_after,
        fingerprint_sha256: $fingerprint,
        public_key_sha256: $public_key_sha256,
        subject_alt_names: $sans,
        leaf_sha256: $leaf_sha256,
        fullchain_sha256: $chain_sha256
    }' >"$output_dir/certificate-manifest.json"
chmod 0644 "$output_dir/certificate-manifest.json"

printf 'Certificate release prepared in %s\n' "$output_dir"
