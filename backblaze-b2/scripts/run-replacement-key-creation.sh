#!/bin/bash
set -euo pipefail
set +x
umask 077
ulimit -c 0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "${script_dir}/../.." && pwd -P)
readonly script_dir repository_root
readonly client="${script_dir}/replacement_key_creation.py"
readonly writer="${script_dir}/protected_doppler_candidate_write.py"
readonly regression="${repository_root}/backblaze-b2/tests/replacement-key-creation-regression.py"
readonly operation_file="${repository_root}/backblaze-b2/manifests/operation.yaml"
readonly operation_schema="${repository_root}/backblaze-b2/schemas/operation.schema.json"
readonly exact_schema="${repository_root}/backblaze-b2/schemas/replacement-key-creation.schema.json"
readonly expected_operation_id=backblaze-b2-replacement-key-creation-v1
readonly bundle_domain=backblaze-b2-replacement-key-creation-bundle-v1
readonly -a bundle_files=(
    backblaze-b2/docs/B2_ARCHITECTURE.md
    backblaze-b2/docs/CAPABILITY_REMEDIATION_DECISION.md
    backblaze-b2/docs/REPLACEMENT_KEY_CREATION.md
    backblaze-b2/manifests/desired-state.yaml
    backblaze-b2/manifests/operation.yaml
    backblaze-b2/schemas/desired-state.schema.json
    backblaze-b2/schemas/operation.schema.json
    backblaze-b2/schemas/replacement-key-creation.schema.json
    backblaze-b2/scripts/capability_remediation_preflight.py
    backblaze-b2/scripts/protected_doppler_candidate_write.py
    backblaze-b2/scripts/replacement_key_creation.py
    backblaze-b2/scripts/run-replacement-key-creation.sh
    backblaze-b2/tests/capability-remediation-preflight-regression.py
    backblaze-b2/tests/replacement-key-creation-regression.py
)

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-bundle" \
        "  ${0##*/} execute BUNDLE_SHA256" \
        "  ${0##*/} self-test"
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

validate_operation() {
    check-jsonschema --schemafile "${operation_schema}" "${operation_file}"
    check-jsonschema --schemafile "${exact_schema}" "${operation_file}"
    if [[ $(operation_id) != "${expected_operation_id}" ]]; then
        printf 'error: active operation does not belong to this launcher\n' >&2
        return 69
    fi
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

    file_list=$(mktemp /tmp/backblaze-b2-replacement-key-bundle.XXXXXX)
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
    file_list=$(mktemp /tmp/backblaze-b2-replacement-key-bundle.XXXXXX)
    write_bundle_file_hashes "${file_list}"
    printf 'authorization_ready=%s\n' "$(operation_ready)"
    printf 'authorization_blockers=%s\n' "$(operation_blockers)"
    printf 'bundle_sha256=%s\n' "$(calculate_bundle_hash)"
    cat "${file_list}"
    rm -f -- "${file_list}"
}

evidence_result() {
    local evidence_path=$1

    [[ -f ${evidence_path} ]] || {
        printf 'missing'
        return
    }
    python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("result", "invalid"))' \
        "${evidence_path}"
}

provider_create_attempted() {
    local evidence_path=$1

    [[ -f ${evidence_path} ]] || {
        printf 'unknown'
        return
    }
    python3 -c \
        'import json,sys; value=json.load(open(sys.argv[1], encoding="utf-8")).get("provider_create_attempted"); print("true" if value is True else "false" if value is False else "unknown")' \
        "${evidence_path}"
}

write_terminal_evidence() {
    local evidence_directory=$1
    local bundle_sha256=$2
    local phase=$3
    local result=$4
    local error_class=$5
    local provider_hash=null candidate_hash=null

    if [[ -f ${evidence_directory}/provider-result.json ]]; then
        provider_hash=$(sha256sum "${evidence_directory}/provider-result.json" | cut -d ' ' -f 1)
        provider_hash=\"${provider_hash}\"
    fi
    if [[ -f ${evidence_directory}/candidate-write-result.json ]]; then
        candidate_hash=$(sha256sum "${evidence_directory}/candidate-write-result.json" | cut -d ' ' -f 1)
        candidate_hash=\"${candidate_hash}\"
    fi
    python3 -c '
import json, os, sys
path, bundle, phase, result, error_class, provider_hash, candidate_hash = sys.argv[1:]
document = {
    "schema_version": 1,
    "operation": "backblaze-b2-replacement-key-creation-v1",
    "bundle_sha256": bundle,
    "terminal_phase": phase,
    "result": result,
    "error_class": None if error_class == "none" else error_class,
    "provider_evidence_sha256": json.loads(provider_hash),
    "candidate_writer_evidence_sha256": json.loads(candidate_hash),
    "credential_values_or_identifiers_retained": False,
    "automatic_retry_performed": False,
    "automatic_provider_or_secret_cleanup_performed": False,
    "credential_accepted_for_use": False,
}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(document, stream, sort_keys=True)
    stream.write("\n")
' "${evidence_directory}/terminal-result.json" "${bundle_sha256}" \
        "${phase}" "${result}" "${error_class}" "${provider_hash}" "${candidate_hash}"
}

execute_creation() {
    local authorized_hash=$1
    local calculated_hash evidence_directory key_id_fifo key_value_fifo
    local client_status writer_status create_attempted candidate_result
    local writer_pid=''
    local terminal_phase=pre_mutation terminal_result=blocked terminal_error=interrupted

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

    evidence_directory=$(mktemp -d /tmp/backblaze-b2-replacement-key-creation.XXXXXX)
    chmod 0700 "${evidence_directory}"
    write_bundle_file_hashes "${evidence_directory}/bundle-files.sha256"
    printf '%s\n' "${calculated_hash}" >"${evidence_directory}/bundle.sha256"
    chmod 0600 "${evidence_directory}/bundle-files.sha256" "${evidence_directory}/bundle.sha256"
    key_id_fifo="${evidence_directory}/candidate-key-id.fifo"
    key_value_fifo="${evidence_directory}/candidate-key-value.fifo"
    mkfifo -m 0600 "${key_id_fifo}" "${key_value_fifo}"

    cleanup_creation() {
        local cleanup_status=$?
        trap - EXIT HUP INT TERM
        set +e
        if [[ -n ${writer_pid} ]]; then
            kill "${writer_pid}" 2>/dev/null || true
            wait "${writer_pid}" 2>/dev/null || true
        fi
        [[ ! -p ${key_id_fifo:-} ]] || rm -f -- "${key_id_fifo}"
        [[ ! -p ${key_value_fifo:-} ]] || rm -f -- "${key_value_fifo}"
        if [[ ! -e ${evidence_directory}/terminal-result.json ]]; then
            write_terminal_evidence "${evidence_directory}" "${calculated_hash}" \
                "${terminal_phase}" "${terminal_result}" "${terminal_error}" || cleanup_status=1
        fi
        printf 'evidence_root=%s\n' "${evidence_directory}"
        exit "${cleanup_status}"
    }
    trap cleanup_creation EXIT
    trap 'terminal_error=hangup; exit 129' HUP
    trap 'terminal_error=interrupted; exit 130' INT
    trap 'terminal_error=terminated; exit 143' TERM

    terminal_phase=protected_writer_started
    python3 "${writer}" \
        --evidence-root "${evidence_directory}" \
        --key-id-fifo "$(basename -- "${key_id_fifo}")" \
        --key-value-fifo "$(basename -- "${key_value_fifo}")" \
        --bundle-sha256 "${calculated_hash}" &
    writer_pid=$!

    terminal_phase=provider_client_started
    terminal_result=manual_intervention
    set +e
    python3 "${client}" \
        --evidence-root "${evidence_directory}" \
        --key-id-fifo "$(basename -- "${key_id_fifo}")" \
        --key-value-fifo "$(basename -- "${key_value_fifo}")" \
        --bundle-sha256 "${calculated_hash}"
    client_status=$?
    set -e
    if ((client_status != 0)); then
        create_attempted=$(provider_create_attempted "${evidence_directory}/provider-result.json")
        if [[ ${create_attempted} == false ]]; then
            terminal_result=blocked
        fi
        terminal_error=provider_client_failed
        return "${client_status}"
    fi
    terminal_phase=provider_created_and_values_delivered

    set +e
    wait "${writer_pid}"
    writer_status=$?
    set -e
    writer_pid=''
    candidate_result=$(evidence_result "${evidence_directory}/candidate-write-result.json")
    if ((writer_status != 0)) || [[ ${candidate_result} != stored ]]; then
        terminal_error=protected_candidate_write_failed
        return 2
    fi

    terminal_phase=candidate_credentials_stored
    terminal_result=completed
    terminal_error=none
    write_terminal_evidence "${evidence_directory}" "${calculated_hash}" \
        "${terminal_phase}" "${terminal_result}" "${terminal_error}"
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
        execute_creation "$2"
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
