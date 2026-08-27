#!/bin/bash
set -euo pipefail
set +x
umask 077
ulimit -c 0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "${script_dir}/../.." && pwd -P)
readonly script_dir repository_root
readonly client="${script_dir}/capability_remediation_preflight.py"
readonly regression="${repository_root}/backblaze-b2/tests/capability-remediation-preflight-regression.py"
readonly operation_file="${repository_root}/backblaze-b2/manifests/operation.yaml"
readonly operation_schema="${repository_root}/backblaze-b2/schemas/operation.schema.json"
readonly expected_operation_id=backblaze-b2-capability-remediation-preflight-v2
readonly bundle_domain="backblaze-b2-capability-remediation-preflight-bundle-v2"
readonly -a bundle_files=(
    backblaze-b2/docs/B2_ARCHITECTURE.md
    backblaze-b2/docs/CAPABILITY_REMEDIATION_DECISION.md
    backblaze-b2/docs/CAPABILITY_REMEDIATION_PREFLIGHT.md
    backblaze-b2/docs/MANAGEMENT_CREDENTIAL_DECISION.md
    backblaze-b2/manifests/desired-state.yaml
    backblaze-b2/manifests/operation.yaml
    backblaze-b2/schemas/desired-state.schema.json
    backblaze-b2/schemas/operation.schema.json
    backblaze-b2/schemas/capability-remediation-preflight.schema.json
    backblaze-b2/scripts/capability_remediation_preflight.py
    backblaze-b2/scripts/run-capability-remediation-preflight.sh
    backblaze-b2/tests/capability-remediation-preflight-regression.py
)

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-bundle" \
        "  ${0##*/} execute BUNDLE_SHA256" \
        "  ${0##*/} self-test"
}

validate_operation() {
    check-jsonschema --schemafile "${operation_schema}" "${operation_file}"
    if [[ $(operation_id) != "${expected_operation_id}" ]]; then
        printf 'error: active operation does not belong to this launcher\n' >&2
        return 69
    fi
}

operation_id() {
    python3 -c \
        'import sys,yaml; print(yaml.safe_load(open(sys.argv[1], encoding="utf-8")).get("operation", {}).get("id", ""))' \
        "${operation_file}"
}

operation_ready() {
    python3 -c \
        'import sys,yaml; print(str(bool(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["operation"]["authorization_ready"])).lower())' \
        "${operation_file}"
}

operation_blockers() {
    python3 -c \
        'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(",".join(data.get("authorization", {}).get("blockers", ["no_active_operation"])))' \
        "${operation_file}"
}

live_execution_enabled() {
    python3 -c \
        'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(str(bool(data.get("implementation", {}).get("live_execution_enabled", False))).lower())' \
        "${operation_file}"
}

write_bundle_file_hashes() {
    local destination=$1
    local relative_path

    : >"${destination}"
    for relative_path in "${bundle_files[@]}"; do
        [[ -f ${repository_root}/${relative_path} && ! -L ${repository_root}/${relative_path} ]] || {
            printf 'invalid bundle input: %s\n' "${relative_path}" >&2
            return 1
        }
        printf '%s  %s\n' \
            "$(sha256sum "${repository_root}/${relative_path}" | cut -d ' ' -f 1)" \
            "${relative_path}" >>"${destination}"
    done
}

calculate_bundle_hash() {
    local file_list calculated

    file_list=$(mktemp /tmp/backblaze-b2-capability-preflight-bundle.XXXXXX)
    write_bundle_file_hashes "${file_list}"
    calculated=$(
        {
            printf '%s\n' "${bundle_domain}"
            cat "${file_list}"
        } | sha256sum | cut -d ' ' -f 1
    )
    rm -f -- "${file_list}"
    printf '%s\n' "${calculated}"
}

show_bundle() {
    local file_list

    validate_operation
    file_list=$(mktemp /tmp/backblaze-b2-capability-preflight-bundle.XXXXXX)
    write_bundle_file_hashes "${file_list}"
    printf 'authorization_ready=%s\n' "$(operation_ready)"
    printf 'authorization_blockers=%s\n' "$(operation_blockers)"
    printf 'bundle_sha256=%s\n' "$(calculate_bundle_hash)"
    cat "${file_list}"
    rm -f -- "${file_list}"
}

execute_preflight() {
    local authorized_hash=$1
    local calculated_hash evidence_root client_status

    validate_operation
    if [[ $(operation_ready) != true || $(live_execution_enabled) != true || -n $(operation_blockers) ]]; then
        printf 'error: operation is not authorization-ready; blockers=%s\n' \
            "$(operation_blockers)" >&2
        return 69
    fi
    calculated_hash=$(calculate_bundle_hash)
    if [[ ! ${authorized_hash} =~ ^[0-9a-f]{64}$ || ${authorized_hash} != "${calculated_hash}" ]]; then
        printf 'error: authorized bundle hash does not match current inputs\n' >&2
        return 66
    fi
    evidence_root=$(mktemp -d /tmp/backblaze-b2-capability-preflight.XXXXXX)
    chmod 0700 "${evidence_root}"
    write_bundle_file_hashes "${evidence_root}/bundle-files.sha256"
    printf '%s\n' "${calculated_hash}" >"${evidence_root}/bundle.sha256"
    chmod 0600 "${evidence_root}/bundle-files.sha256" "${evidence_root}/bundle.sha256"

    set +e
    python3 "${client}" \
        --evidence-root "${evidence_root}" \
        --bundle-sha256 "${calculated_hash}"
    client_status=$?
    set -e

    printf 'evidence_root=%s\n' "${evidence_root}"
    return "${client_status}"
}

case ${1:-} in
    show-bundle)
        (($# == 1)) || {
            usage >&2
            exit 64
        }
        show_bundle
        ;;
    execute)
        (($# == 2)) || {
            usage >&2
            exit 64
        }
        execute_preflight "$2"
        ;;
    self-test)
        (($# == 1)) || {
            usage >&2
            exit 64
        }
        python3 "${regression}"
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
