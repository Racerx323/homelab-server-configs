#!/usr/bin/env python3
"""Validate bounded application tar sections completely before contained extraction."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tarfile

ARCHIVES = ('media', 'configuration', 'quadlet_config_hashes', 'image_dependency_manifest')


def extract(source, destination, expected):
    """Expected maps section to exact member names/types and independent file hashes."""
    if set(expected) != set(ARCHIVES): raise ValueError('archive_sections')
    entries = {}
    for section in ARCHIVES:
        path = source/section
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 16777216:
            raise ValueError('archive_source')
        with tarfile.open(path, mode='r:') as archive:
            members = {}
            total = 0
            for member in archive:
                name = member.name
                normalized = PurePosixPath(name)
                if (name in members or len(members) >= 512 or normalized.is_absolute()
                        or '..' in normalized.parts or (name != '.' and str(normalized) != name)
                        or not (member.isfile() or member.isdir())):
                    raise ValueError('unsafe_archive_member')
                if section == 'media' and not member.isdir(): raise ValueError('media_not_empty')
                total += member.size
                if member.size < 0 or total > 16777216: raise ValueError('expanded_size')
                data = archive.extractfile(member).read() if member.isfile() else None
                members[name] = data
            observed = {name: {'type': 'directory'} if data is None else
                        {'type': 'file', 'sha256': hashlib.sha256(data).hexdigest()}
                        for name, data in members.items()}
            if observed != expected[section]: raise ValueError('archive_inventory_mismatch')
            entries[section] = members
    # Validate all sections before creating any destination content.
    if any(p.is_symlink() for p in [destination, *destination.parents]): raise ValueError('destination_symlink')
    destination.mkdir(mode=0o700)
    for section, members in entries.items():
        base = destination/section
        base.mkdir(mode=0o700)
        for name, data in members.items():
            target = base/name
            if data is None:
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'wb') as stream: stream.write(data)
    metadata = json.loads((source/'versions_migrations').read_text())
    if set(metadata) != {'versions', 'migrations'}: raise ValueError('versions_migrations_fields')
    return metadata


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    extract(root/'retrieval/retrieved', root/'extracted', json.loads((root/'members.json').read_text()))


if __name__ == '__main__': main()
