#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077

if [[ $# -eq 0 ]]; then
    printf 'Usage: %s COMMAND [ARG...]\n' "${0##*/}" >&2
    exit 64
fi

ansible_temp_directory=$(mktemp -d \
    /tmp/homelab-server-configs-ansible.XXXXXX)
readonly ansible_temp_directory

# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2317
cleanup_ansible_temp_directory() {
    case "$ansible_temp_directory" in
        /tmp/homelab-server-configs-ansible.??????) ;;
        *)
            printf 'Refusing unsafe Ansible temporary path: %s\n' \
                "$ansible_temp_directory" >&2
            return 70
            ;;
    esac

    if [[ -L "$ansible_temp_directory" ]]; then
        printf 'Refusing symbolic-link Ansible temporary path: %s\n' \
            "$ansible_temp_directory" >&2
        return 70
    fi

    rm -rf -- "$ansible_temp_directory"
}

trap cleanup_ansible_temp_directory EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

chmod 0700 "$ansible_temp_directory"
export ANSIBLE_LOCAL_TEMP="$ansible_temp_directory"

set +e
"$@"
command_status=$?
set -e

exit "$command_status"
