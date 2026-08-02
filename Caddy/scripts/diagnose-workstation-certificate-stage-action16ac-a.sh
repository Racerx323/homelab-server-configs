#!/usr/bin/env bash

set -uo pipefail
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

pass_count=0
failure_count=0
skipped_count=0
first_failure=none

record_result() {
    local label=$1
    local result=$2

    case "$result" in
        pass)
            ((pass_count += 1))
            ;;
        fail)
            ((failure_count += 1))
            if [[ "$first_failure" == none ]]; then
                first_failure=$label
            fi
            ;;
        skipped)
            ((skipped_count += 1))
            ;;
        *)
            printf 'diagnostic_internal_result_error=true\n' >&2
            exit 2
            ;;
    esac
    printf '%s=%s\n' "$label" "$result"
}

bool_result() {
    local label=$1
    local value=$2

    if [[ "$value" == true ]]; then
        record_result "$label" pass
    else
        record_result "$label" fail
    fi
}

stage_file_list() {
    find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
}

stage_metadata() {
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        "$stage" \
        "$leaf" \
        "$intermediates" \
        "$fullchain" \
        "$private_key" \
        "$manifest" 2>/dev/null
}

public_hashes() {
    sha256sum "$leaf" "$intermediates" "$fullchain" "$manifest" 2>/dev/null
}

leaf_public_key_hash() {
    openssl x509 -in "$leaf" -pubkey -noout 2>/dev/null |
        openssl pkey -pubin -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

private_public_key_hash() {
    openssl pkey -in "$private_key" -passin pass: \
        -pubout -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

print_summary() {
    printf 'diagnostic_pass_count=%s\n' "$pass_count"
    printf 'diagnostic_failure_count=%s\n' "$failure_count"
    printf 'diagnostic_skipped_count=%s\n' "$skipped_count"
    printf 'diagnostic_first_failure=%s\n' "$first_failure"
    printf 'certificate_stage_diagnostic_action16ac_a_complete=true\n'
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$minimum_days" -eq 30 ]]
    [[ "$leaf_sha256" == 4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319 ]]
    [[ "$intermediates_sha256" == 6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d ]]
    [[ "$fullchain_sha256" == d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83 ]]
    [[ "$manifest_sha256" == 0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df ]]
    printf 'action_16ac_a_diagnostic_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

user_match=false
group_match=false
[[ "$(id -un 2>/dev/null)" == "$expected_owner" ]] && user_match=true
[[ "$(id -gn 2>/dev/null)" == "$expected_group" ]] && group_match=true
bool_result workstation_user "$user_match"
bool_result workstation_group "$group_match"

commands_ready=true
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
    [[ -x "$command_path" ]] || commands_ready=false
done
bool_result command_environment "$commands_ready"

stage_exists=false
stage_non_symlink=false
[[ -d "$stage" ]] && stage_exists=true
[[ "$stage_exists" == true && ! -L "$stage" ]] && stage_non_symlink=true
bool_result stage_exists "$stage_exists"
if [[ "$stage_exists" == true ]]; then
    bool_result stage_non_symlink "$stage_non_symlink"
else
    record_result stage_non_symlink skipped
fi

if [[ "$commands_ready" != true || "$stage_non_symlink" != true ]]; then
    for label in \
        stage_metadata \
        exact_file_set \
        stage_symlink_absence \
        public_file_metadata \
        private_key_metadata \
        leaf_hash \
        intermediates_hash \
        fullchain_hash \
        manifest_hash \
        leaf_parse \
        private_key_parse \
        validity_30_days \
        accepted_expiry \
        wildcard_san \
        certificate_key_match \
        intermediates_parse \
        intermediates_root_excluded \
        intermediates_order \
        fullchain_composition \
        workstation_chain_trust \
        manifest_parse \
        manifest_schema \
        manifest_subject \
        manifest_issuer \
        manifest_not_before \
        manifest_not_after \
        manifest_fingerprint \
        manifest_public_key \
        manifest_sans \
        manifest_leaf_hash \
        manifest_fullchain_hash \
        stage_file_set_unchanged \
        stage_metadata_unchanged \
        public_hashes_unchanged \
        private_key_unchanged; do
        record_result "$label" skipped
    done
    print_summary
    exit 0
fi

stage_stat=$(stat -c '%U:%G:%a' "$stage" 2>/dev/null || true)
printf 'stage_metadata_observed=%s\n' "${stage_stat:-unavailable}"
stage_metadata_match=false
[[ "$stage_stat" == "$expected_owner:$expected_group:750" ]] &&
    stage_metadata_match=true
bool_result stage_metadata "$stage_metadata_match"

mapfile -t files_before < <(stage_file_list)
expected_files=(
    certificate-manifest.json
    fullchain.pem
    intermediates.pem
    leaf.pem
    privkey.pem
)
printf 'stage_direct_entry_count=%s\n' "${#files_before[@]}"
exact_files=false
[[ "${files_before[*]}" == "${expected_files[*]}" ]] && exact_files=true
bool_result exact_file_set "$exact_files"

symlinks_absent=true
if find "$stage" -type l -print -quit 2>/dev/null | grep -q .; then
    symlinks_absent=false
fi
bool_result stage_symlink_absence "$symlinks_absent"

public_files_ready=true
public_metadata_match=true
for public_file in "$leaf" "$intermediates" "$fullchain" "$manifest"; do
    if [[ ! -f "$public_file" || -L "$public_file" ]]; then
        public_files_ready=false
        public_metadata_match=false
        continue
    fi
    [[ "$(stat -c '%U:%G:%a' "$public_file" 2>/dev/null)" == "$expected_owner:$expected_group:644" ]] ||
        public_metadata_match=false
done
if [[ "$public_files_ready" == true ]]; then
    bool_result public_file_metadata "$public_metadata_match"
else
    record_result public_file_metadata fail
fi

private_key_ready=false
private_metadata_match=false
if [[ -f "$private_key" && ! -L "$private_key" ]]; then
    private_key_ready=true
    [[ "$(stat -c '%U:%G:%a' "$private_key" 2>/dev/null)" == "$expected_owner:$expected_group:640" ]] &&
        private_metadata_match=true
fi
bool_result private_key_metadata "$private_metadata_match"

leaf_hash_observed=unavailable
intermediates_hash_observed=unavailable
fullchain_hash_observed=unavailable
manifest_hash_observed=unavailable
leaf_hash_match=false
intermediates_hash_match=false
fullchain_hash_match=false
manifest_hash_match=false

if [[ -f "$leaf" && ! -L "$leaf" ]]; then
    leaf_hash_observed=$(sha256sum "$leaf" 2>/dev/null | awk '{ print $1 }')
    [[ "$leaf_hash_observed" == "$leaf_sha256" ]] && leaf_hash_match=true
fi
if [[ -f "$intermediates" && ! -L "$intermediates" ]]; then
    intermediates_hash_observed=$(
        sha256sum "$intermediates" 2>/dev/null | awk '{ print $1 }'
    )
    [[ "$intermediates_hash_observed" == "$intermediates_sha256" ]] &&
        intermediates_hash_match=true
fi
if [[ -f "$fullchain" && ! -L "$fullchain" ]]; then
    fullchain_hash_observed=$(
        sha256sum "$fullchain" 2>/dev/null | awk '{ print $1 }'
    )
    [[ "$fullchain_hash_observed" == "$fullchain_sha256" ]] &&
        fullchain_hash_match=true
fi
if [[ -f "$manifest" && ! -L "$manifest" ]]; then
    manifest_hash_observed=$(
        sha256sum "$manifest" 2>/dev/null | awk '{ print $1 }'
    )
    [[ "$manifest_hash_observed" == "$manifest_sha256" ]] &&
        manifest_hash_match=true
fi

if [[ "$leaf_hash_match" == true ]]; then
    printf 'certificate_leaf_sha256_observed=%s\n' "$leaf_sha256"
else
    printf 'certificate_leaf_sha256_observed=mismatch_or_unavailable\n'
fi
if [[ "$intermediates_hash_match" == true ]]; then
    printf 'certificate_intermediates_sha256_observed=%s\n' \
        "$intermediates_sha256"
else
    printf 'certificate_intermediates_sha256_observed=mismatch_or_unavailable\n'
fi
if [[ "$fullchain_hash_match" == true ]]; then
    printf 'certificate_fullchain_sha256_observed=%s\n' "$fullchain_sha256"
else
    printf 'certificate_fullchain_sha256_observed=mismatch_or_unavailable\n'
fi
if [[ "$manifest_hash_match" == true ]]; then
    printf 'certificate_manifest_sha256_observed=%s\n' "$manifest_sha256"
else
    printf 'certificate_manifest_sha256_observed=mismatch_or_unavailable\n'
fi
bool_result leaf_hash "$leaf_hash_match"
bool_result intermediates_hash "$intermediates_hash_match"
bool_result fullchain_hash "$fullchain_hash_match"
bool_result manifest_hash "$manifest_hash_match"

snapshot_ready=false
metadata_before=
public_hashes_before=
private_hash_before=
if [[ "$public_files_ready" == true && "$private_key_ready" == true ]]; then
    metadata_before=$(stage_metadata)
    public_hashes_before=$(public_hashes)
    private_hash_before=$(
        sha256sum "$private_key" 2>/dev/null | awk '{ print $1 }'
    )
    if [[ -n "$metadata_before" && -n "$public_hashes_before" &&
        -n "$private_hash_before" ]]; then
        snapshot_ready=true
    fi
fi

leaf_parse=false
private_key_parse=false
if [[ -f "$leaf" && ! -L "$leaf" ]] &&
    openssl x509 -in "$leaf" -noout >/dev/null 2>&1; then
    leaf_parse=true
fi
if [[ "$private_key_ready" == true ]] &&
    openssl pkey -in "$private_key" -passin pass: \
        -check -noout >/dev/null 2>&1; then
    private_key_parse=true
fi
bool_result leaf_parse "$leaf_parse"
bool_result private_key_parse "$private_key_parse"

not_before=
not_after=
sans=
fingerprint=
leaf_subject=
leaf_issuer=
certificate_key_hash=
private_key_public_hash=

if [[ "$leaf_parse" == true ]]; then
    validity_pass=false
    if openssl x509 -in "$leaf" -checkend "$((minimum_days * 86400))" \
        -noout >/dev/null 2>&1; then
        validity_pass=true
    fi
    bool_result validity_30_days "$validity_pass"

    not_before=$(
        openssl x509 -in "$leaf" -noout -startdate 2>/dev/null |
            cut -d= -f2-
    )
    not_after=$(
        openssl x509 -in "$leaf" -noout -enddate 2>/dev/null |
            cut -d= -f2-
    )
    printf 'certificate_not_after_observed=%s\n' \
        "${not_after:-unavailable}"
    expiry_match=false
    [[ "$not_after" == "$expected_not_after" ]] && expiry_match=true
    bool_result accepted_expiry "$expiry_match"

    sans=$(
        openssl x509 -in "$leaf" -noout -ext subjectAltName 2>/dev/null |
            tail -n +2 |
            tr -d '\n' |
            sed 's/^[[:space:]]*//'
    )
    wildcard_present=false
    grep -Fq 'DNS:*.local.theama.co' <<<"$sans" &&
        wildcard_present=true
    bool_result wildcard_san "$wildcard_present"

    fingerprint=$(
        openssl x509 -in "$leaf" -noout -fingerprint -sha256 2>/dev/null |
            cut -d= -f2
    )
    leaf_subject=$(
        openssl x509 -in "$leaf" -noout -subject -nameopt RFC2253 \
            2>/dev/null |
            cut -d= -f2-
    )
    leaf_issuer=$(
        openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 \
            2>/dev/null |
            cut -d= -f2-
    )
    certificate_key_hash=$(leaf_public_key_hash)
else
    record_result validity_30_days skipped
    printf 'certificate_not_after_observed=unavailable\n'
    record_result accepted_expiry skipped
    record_result wildcard_san skipped
fi

if [[ "$leaf_parse" == true && "$private_key_parse" == true ]]; then
    private_key_public_hash=$(private_public_key_hash)
    key_match=false
    [[ -n "$certificate_key_hash" &&
        "$certificate_key_hash" == "$private_key_public_hash" ]] &&
        key_match=true
    bool_result certificate_key_match "$key_match"
else
    record_result certificate_key_match skipped
fi

intermediates_parse=false
intermediates_root_excluded=false
intermediates_order=false
certificate_count=0
subjects=()
issuers=()
certificate=
intermediate_structure_valid=true
if [[ -f "$intermediates" && ! -L "$intermediates" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == '-----BEGIN CERTIFICATE-----' ]]; then
            if [[ -n "$certificate" ]]; then
                intermediate_structure_valid=false
                break
            fi
            certificate=$line$'\n'
            continue
        fi
        if [[ -z "$certificate" ]]; then
            [[ -z "$line" ]] || intermediate_structure_valid=false
            continue
        fi
        certificate+=$line$'\n'
        if [[ "$line" != '-----END CERTIFICATE-----' ]]; then
            continue
        fi

        subject_output=$(
            openssl x509 -in <(printf '%s' "$certificate") \
                -noout -subject -nameopt RFC2253 2>/dev/null
        )
        subject_rc=$?
        issuer_output=$(
            openssl x509 -in <(printf '%s' "$certificate") \
                -noout -issuer -nameopt RFC2253 2>/dev/null
        )
        issuer_rc=$?
        if [[ "$subject_rc" -ne 0 || "$issuer_rc" -ne 0 ]]; then
            intermediate_structure_valid=false
        else
            subjects+=("${subject_output#subject=}")
            issuers+=("${issuer_output#issuer=}")
            ((certificate_count += 1))
        fi
        certificate=
    done <"$intermediates"
    [[ -z "$certificate" ]] || intermediate_structure_valid=false
fi
printf 'certificate_intermediate_count_observed=%s\n' "$certificate_count"

if [[ "$intermediate_structure_valid" == true &&
    "$certificate_count" -ge 1 ]]; then
    intermediates_parse=true
fi
bool_result intermediates_parse "$intermediates_parse"

if [[ "$intermediates_parse" == true ]]; then
    intermediates_root_excluded=true
    for ((index = 0; index < certificate_count; index++)); do
        if [[ "${subjects[$index]}" == "${issuers[$index]}" ]]; then
            intermediates_root_excluded=false
        fi
    done
    bool_result intermediates_root_excluded "$intermediates_root_excluded"
else
    record_result intermediates_root_excluded skipped
fi

if [[ "$leaf_parse" == true && "$intermediates_parse" == true ]]; then
    intermediates_order=true
    expected_issuer=$leaf_issuer
    for ((index = 0; index < certificate_count; index++)); do
        if [[ "${subjects[$index]}" != "$expected_issuer" ]]; then
            intermediates_order=false
        fi
        expected_issuer=${issuers[$index]}
    done
    bool_result intermediates_order "$intermediates_order"
else
    record_result intermediates_order skipped
fi

if [[ -f "$leaf" && ! -L "$leaf" &&
    -f "$intermediates" && ! -L "$intermediates" &&
    -f "$fullchain" && ! -L "$fullchain" ]]; then
    fullchain_composition=false
    cmp -s "$fullchain" <(cat "$leaf" "$intermediates") &&
        fullchain_composition=true
    bool_result fullchain_composition "$fullchain_composition"
else
    record_result fullchain_composition skipped
fi

if [[ "$leaf_parse" == true && "$intermediates_parse" == true ]]; then
    chain_trust=false
    if openssl verify \
        -purpose sslserver \
        -CApath /etc/ssl/certs \
        -untrusted "$intermediates" \
        "$leaf" >/dev/null 2>&1; then
        chain_trust=true
    fi
    bool_result workstation_chain_trust "$chain_trust"
else
    record_result workstation_chain_trust skipped
fi

manifest_parse=false
manifest_schema=false
if [[ -f "$manifest" && ! -L "$manifest" ]] &&
    jq -e . "$manifest" >/dev/null 2>&1; then
    manifest_parse=true
fi
bool_result manifest_parse "$manifest_parse"

if [[ "$manifest_parse" == true ]] &&
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
    ' "$manifest" >/dev/null 2>&1; then
    manifest_schema=true
fi
if [[ "$manifest_parse" == true ]]; then
    bool_result manifest_schema "$manifest_schema"
else
    record_result manifest_schema skipped
fi

manifest_values_ready=false
if [[ "$manifest_parse" == true && "$leaf_parse" == true &&
    -n "$certificate_key_hash" ]]; then
    manifest_values_ready=true
fi

if [[ "$manifest_values_ready" == true ]]; then
    manifest_subject=$(jq -er '.subject' "$manifest" 2>/dev/null || true)
    manifest_issuer=$(jq -er '.issuer' "$manifest" 2>/dev/null || true)
    manifest_not_before=$(
        jq -er '.not_before' "$manifest" 2>/dev/null || true
    )
    manifest_not_after=$(jq -er '.not_after' "$manifest" 2>/dev/null || true)
    manifest_fingerprint=$(
        jq -er '.fingerprint_sha256' "$manifest" 2>/dev/null || true
    )
    manifest_public_key=$(
        jq -er '.public_key_sha256' "$manifest" 2>/dev/null || true
    )
    manifest_sans=$(
        jq -er '.subject_alt_names' "$manifest" 2>/dev/null || true
    )
    manifest_leaf=$(jq -er '.leaf_sha256' "$manifest" 2>/dev/null || true)
    manifest_fullchain=$(
        jq -er '.fullchain_sha256' "$manifest" 2>/dev/null || true
    )

    value_match=false
    [[ "$manifest_subject" == "$leaf_subject" ]] && value_match=true
    bool_result manifest_subject "$value_match"
    value_match=false
    [[ "$manifest_issuer" == "$leaf_issuer" ]] && value_match=true
    bool_result manifest_issuer "$value_match"
    value_match=false
    [[ "$manifest_not_before" == "$not_before" ]] && value_match=true
    bool_result manifest_not_before "$value_match"
    value_match=false
    [[ "$manifest_not_after" == "$not_after" ]] && value_match=true
    bool_result manifest_not_after "$value_match"
    value_match=false
    [[ "$manifest_fingerprint" == "$fingerprint" ]] && value_match=true
    bool_result manifest_fingerprint "$value_match"
    value_match=false
    [[ "$manifest_public_key" == "$certificate_key_hash" ]] &&
        value_match=true
    bool_result manifest_public_key "$value_match"
    value_match=false
    [[ "$manifest_sans" == "$sans" ]] && value_match=true
    bool_result manifest_sans "$value_match"
    value_match=false
    [[ "$manifest_leaf" == "$leaf_sha256" ]] && value_match=true
    bool_result manifest_leaf_hash "$value_match"
    value_match=false
    [[ "$manifest_fullchain" == "$fullchain_sha256" ]] &&
        value_match=true
    bool_result manifest_fullchain_hash "$value_match"
else
    for label in \
        manifest_subject \
        manifest_issuer \
        manifest_not_before \
        manifest_not_after \
        manifest_fingerprint \
        manifest_public_key \
        manifest_sans \
        manifest_leaf_hash \
        manifest_fullchain_hash; do
        record_result "$label" skipped
    done
fi

if [[ -d "$stage" && ! -L "$stage" ]]; then
    mapfile -t files_after < <(stage_file_list)
    file_set_unchanged=false
    [[ "${files_after[*]}" == "${files_before[*]}" ]] &&
        file_set_unchanged=true
    bool_result stage_file_set_unchanged "$file_set_unchanged"
else
    record_result stage_file_set_unchanged fail
fi

if [[ "$snapshot_ready" == true ]]; then
    metadata_unchanged=false
    public_hashes_unchanged=false
    private_key_unchanged=false
    [[ "$(stage_metadata)" == "$metadata_before" ]] &&
        metadata_unchanged=true
    [[ "$(public_hashes)" == "$public_hashes_before" ]] &&
        public_hashes_unchanged=true
    private_hash_after=$(
        sha256sum "$private_key" 2>/dev/null | awk '{ print $1 }'
    )
    [[ -n "$private_hash_after" &&
        "$private_hash_after" == "$private_hash_before" ]] &&
        private_key_unchanged=true
    bool_result stage_metadata_unchanged "$metadata_unchanged"
    bool_result public_hashes_unchanged "$public_hashes_unchanged"
    bool_result private_key_unchanged "$private_key_unchanged"
else
    record_result stage_metadata_unchanged skipped
    record_result public_hashes_unchanged skipped
    record_result private_key_unchanged skipped
fi

print_summary
exit 0
