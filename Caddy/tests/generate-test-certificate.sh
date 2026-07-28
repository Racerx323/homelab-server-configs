#!/usr/bin/env bash
set -euo pipefail

output_dir=${1:?output directory required}
mkdir -p "$output_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/caddy-test-ca.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

openssl genrsa -out "$work_dir/root.key" 2048 >/dev/null 2>&1
openssl req \
    -x509 \
    -new \
    -key "$work_dir/root.key" \
    -sha256 \
    -days 3650 \
    -subj '/CN=Caddy HA Test Root' \
    -out "$work_dir/root.pem" >/dev/null 2>&1

openssl genrsa -out "$work_dir/intermediate.key" 2048 >/dev/null 2>&1
openssl req \
    -new \
    -key "$work_dir/intermediate.key" \
    -subj '/CN=Caddy HA Test Intermediate' \
    -out "$work_dir/intermediate.csr" >/dev/null 2>&1

cat >"$work_dir/intermediate.ext" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 \
    -req \
    -in "$work_dir/intermediate.csr" \
    -CA "$work_dir/root.pem" \
    -CAkey "$work_dir/root.key" \
    -CAcreateserial \
    -days 1825 \
    -sha256 \
    -extfile "$work_dir/intermediate.ext" \
    -out "$work_dir/intermediate.pem" >/dev/null 2>&1

openssl genrsa -out "$output_dir/input.key" 2048 >/dev/null 2>&1
openssl req \
    -new \
    -key "$output_dir/input.key" \
    -subj '/CN=*.local.theama.co' \
    -out "$work_dir/leaf.csr" >/dev/null 2>&1

cat >"$work_dir/leaf.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:*.local.theama.co
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 \
    -req \
    -in "$work_dir/leaf.csr" \
    -CA "$work_dir/intermediate.pem" \
    -CAkey "$work_dir/intermediate.key" \
    -CAcreateserial \
    -days 365 \
    -sha256 \
    -extfile "$work_dir/leaf.ext" \
    -out "$output_dir/input.cert" >/dev/null 2>&1

cat "$work_dir/intermediate.pem" "$work_dir/root.pem" \
    >"$output_dir/input.ca-bundle"
