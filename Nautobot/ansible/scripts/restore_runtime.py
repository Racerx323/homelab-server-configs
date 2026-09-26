#!/usr/bin/env python3
"""Import a dump only into a fresh database in an independently owned restore container."""
import json
from pathlib import Path
import re


def import_database(call, container, database, token, dump):
    if not re.fullmatch('nautobot-restore-local-[a-f0-9]{12}', token):
        raise ValueError('restore_owner')
    if container != token+'-postgresql' or database != 'restored_fixture':
        raise ValueError('restore_destination')
    info = json.loads(call(['podman', 'inspect', container]))[0]
    if info['Config']['Labels'].get('nautobot.restore.local') != token:
        raise ValueError('restore_container_owner')
    if info['HostConfig'].get('PortBindings') or info.get('Mounts'):
        raise ValueError('restore_container_exposure_or_mounts')
    path = Path(dump)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 268435456:
        raise ValueError('restore_dump_metadata')
    raw = path.read_bytes()
    if raw[:5] != b'PGDMP': raise ValueError('restore_dump_format')
    command = ['podman', 'exec', '-i', container]
    # createdb must fail if the destination already exists; never use --clean.
    call(command + ['createdb', '-U', 'nautobot', database])
    call(command + ['pg_restore', '--exit-on-error', '--single-transaction', '-U',
                    'nautobot', '-d', database], data=raw)
