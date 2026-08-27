#!/bin/bash
set -euo pipefail
set +x
umask 077
ulimit -c 0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "${script_dir}/../.." && pwd -P)
readonly script_dir repository_root
readonly writer="${script_dir}/protected_doppler_master_write.py"
readonly regression="${repository_root}/backblaze-b2/tests/master-key-rotation-launcher-regression.py"
readonly operation_file="${repository_root}/backblaze-b2/manifests/operation.yaml"
readonly operation_schema="${repository_root}/backblaze-b2/schemas/operation.schema.json"
readonly bundle_domain=backblaze-b2-master-key-rotation-bundle-v1
readonly -a bundle_files=(
    backblaze-b2/docs/B2_ARCHITECTURE.md
    backblaze-b2/docs/MANAGEMENT_CREDENTIAL_DECISION.md
    backblaze-b2/docs/MASTER_KEY_ROTATION.md
    backblaze-b2/docs/MASTER_KEY_ROTATION_PREFLIGHT.md
    backblaze-b2/manifests/operation.yaml
    backblaze-b2/schemas/operation.schema.json
    backblaze-b2/scripts/protected_doppler_master_write.py
    backblaze-b2/scripts/run-master-key-rotation.sh
    backblaze-b2/tests/master-key-rotation-launcher-regression.py
    backblaze-b2/tests/protected-doppler-master-write-regression.py
)

usage() {
    printf '%s\n' \
        "Usage:" \
        "  ${0##*/} show-bundle" \
        "  ${0##*/} execute BUNDLE_SHA256" \
        "  ${0##*/} self-test"
}

operation_ready() {
    python3 -c \
        'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(str(bool(data["operation"]["authorization_ready"])).lower())' \
        "${operation_file}"
}

operation_blockers() {
    python3 -c \
        'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(",".join(data.get("authorization", {}).get("blockers", [])))' \
        "${operation_file}"
}

live_execution_enabled() {
    python3 -c \
        'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(str(bool(data.get("implementation", {}).get("live_execution_enabled", False))).lower())' \
        "${operation_file}"
}

validate_operation() {
    check-jsonschema --schemafile "${operation_schema}" "${operation_file}"
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
    local bundle_list calculated_hash
    bundle_list=$(mktemp /tmp/backblaze-b2-master-key-rotation-bundle.XXXXXX)
    write_bundle_file_hashes "${bundle_list}"
    calculated_hash=$(
        {
            printf '%s\n' "${bundle_domain}"
            cat "${bundle_list}"
        } | sha256sum | cut -d ' ' -f 1
    )
    rm -f -- "${bundle_list}"
    printf '%s\n' "${calculated_hash}"
}

show_bundle() {
    local bundle_list
    validate_operation
    bundle_list=$(mktemp /tmp/backblaze-b2-master-key-rotation-bundle.XXXXXX)
    write_bundle_file_hashes "${bundle_list}"
    printf 'authorization_ready=%s\n' "$(operation_ready)"
    printf 'authorization_blockers=%s\n' "$(operation_blockers)"
    printf 'bundle_sha256=%s\n' "$(calculate_bundle_hash)"
    cat "${bundle_list}"
    rm -f -- "${bundle_list}"
}

write_terminal_evidence() {
    local evidence_directory=$1
    local bundle_sha256=$2
    local phase=$3
    local result=$4
    local error_class=$5
    local writer_hash=null

    if [[ -f ${evidence_directory}/doppler-write-result.json ]]; then
        writer_hash=$(sha256sum "${evidence_directory}/doppler-write-result.json" | cut -d ' ' -f 1)
        writer_hash=\"${writer_hash}\"
    fi
    python3 -c '
import json, os, sys
path, bundle, phase, result, error_class, writer_hash = sys.argv[1:]
document = {
    "schema_version": 1,
    "operation": "backblaze-b2-master-key-rotation-v1",
    "bundle_sha256": bundle,
    "terminal_phase": phase,
    "result": result,
    "error_class": None if error_class == "none" else error_class,
    "doppler_writer_evidence_sha256": json.loads(writer_hash),
    "credential_values_or_identifiers_retained": False,
}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(document, stream, sort_keys=True)
    stream.write("\n")
' "${evidence_directory}/terminal-result.json" "${bundle_sha256}" \
        "${phase}" "${result}" "${error_class}" "${writer_hash}"
}

execute_rotation() {
    local authorized_hash=$1
    local calculated_hash evidence_directory key_id_fifo key_value_fifo
    local key_id_value key_value writer_pid='' writer_status acknowledgement
    local terminal_phase=pre_mutation terminal_result=blocked terminal_error=interrupted
    local -a feeder_pids=()

    validate_operation
    if [[ $(operation_ready) != true ]] ||
        [[ $(live_execution_enabled) != true ]] ||
        [[ -n $(operation_blockers) ]]; then
        printf 'error: operation is not authorization-ready\n' >&2
        return 69
    fi
    calculated_hash=$(calculate_bundle_hash)
    if [[ ! ${authorized_hash} =~ ^[0-9a-f]{64}$ || ${authorized_hash} != "${calculated_hash}" ]]; then
        printf 'error: authorized bundle hash does not match current inputs\n' >&2
        return 66
    fi
    [[ -r /dev/tty && -w /dev/tty ]] || {
        printf 'error: interactive controlling terminal required\n' >&2
        return 65
    }

    evidence_directory=$(mktemp -d /tmp/backblaze-b2-master-key-rotation.XXXXXX)
    chmod 0700 "${evidence_directory}"
    write_bundle_file_hashes "${evidence_directory}/bundle-files.sha256"
    printf '%s\n' "${calculated_hash}" >"${evidence_directory}/bundle.sha256"
    chmod 0600 "${evidence_directory}/bundle-files.sha256" "${evidence_directory}/bundle.sha256"

    cleanup_rotation() {
        local cleanup_status=$?
        local feeder_process
        trap - EXIT HUP INT TERM
        set +e
        unset key_id_value key_value
        for feeder_process in "${feeder_pids[@]:-}"; do
            kill "${feeder_process}" 2>/dev/null || true
            wait "${feeder_process}" 2>/dev/null || true
        done
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
    trap cleanup_rotation EXIT
    trap 'terminal_error=hangup; exit 129' HUP
    trap 'terminal_error=interrupted; exit 130' INT
    trap 'terminal_error=terminated; exit 143' TERM

    set -o pipefail
    doppler --no-check-version --no-read-env --silent \
        configs --project homelab-dev --environment prd --json |
        jq -e '[.[] | select(.name == "prd_b2_admin")] | length == 0' >/dev/null || {
        terminal_error=doppler_config_not_absent
        return 2
    }
    terminal_phase=doppler_config_creation_attempted
    terminal_result=manual_intervention
    doppler --no-check-version --no-read-env --silent configs create prd_b2_admin \
        --project homelab-dev --environment prd
    terminal_phase=doppler_config_created
    terminal_result=incomplete

    printf '%s' \
        'Existing account-level master application-key ID (shown on the App Keys page): ' \
        >/dev/tty
    IFS= read -r -s key_id_value </dev/tty
    printf '\n' >/dev/tty
    [[ -n ${key_id_value} ]] || {
        terminal_result=incomplete
        terminal_error=master_key_id_not_supplied
        return 2
    }

    printf '%s\n' \
        'Generate the new master key value in the authenticated Backblaze console.' \
        'The account-level master application-key ID does not change.' \
        'Keep the one-time value visible. Type generated only after generation completes.' >/dev/tty
    IFS= read -r acknowledgement </dev/tty
    [[ ${acknowledgement} == generated ]] || {
        terminal_result=incomplete
        terminal_error=provider_generation_not_confirmed
        return 2
    }
    terminal_phase=master_generated
    terminal_result=manual_intervention

    printf '%s' 'New one-time master application-key value: ' >/dev/tty
    IFS= read -r -s key_value </dev/tty
    printf '\n' >/dev/tty
    [[ -n ${key_value} ]] || {
        terminal_result=manual_intervention
        terminal_error=master_key_value_not_supplied
        return 2
    }

    key_id_fifo="${evidence_directory}/master-key-id.fifo"
    key_value_fifo="${evidence_directory}/master-key-value.fifo"
    mkfifo -m 0600 "${key_id_fifo}" "${key_value_fifo}"
    python3 "${writer}" --evidence-root "${evidence_directory}" \
        --key-id-fifo "$(basename -- "${key_id_fifo}")" \
        --key-value-fifo "$(basename -- "${key_value_fifo}")" \
        --bundle-sha256 "${calculated_hash}" &
    writer_pid=$!

    (printf '%s' "${key_id_value}" >"${key_id_fifo}") &
    feeder_pids+=("$!")
    unset key_id_value
    (printf '%s' "${key_value}" >"${key_value_fifo}") &
    feeder_pids+=("$!")
    unset key_value

    set +e
    wait "${writer_pid}"
    writer_status=$?
    set -e
    ((writer_status == 0)) || {
        terminal_result=manual_intervention
        terminal_error=protected_doppler_write_failed
        return "${writer_status}"
    }
    terminal_phase=credentials_stored

    printf '%s\n' \
        'Confirm the console reports the old master invalidated, then type old-master-invalidated.' >/dev/tty
    IFS= read -r acknowledgement </dev/tty
    [[ ${acknowledgement} == old-master-invalidated ]] || {
        terminal_result=manual_intervention
        terminal_error=old_master_invalidation_not_confirmed
        return 2
    }
    terminal_phase=accepted
    terminal_result=completed
    terminal_error=none
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
        execute_rotation "$2"
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
