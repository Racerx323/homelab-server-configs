#!/usr/bin/env python3
"""Apply reviewed non-secret Webmin settings without discarding other options."""
import argparse
import json
import os
from pathlib import Path
import stat
import tempfile


def render(raw, policy):
    if not policy or any(not isinstance(k, str) or not isinstance(v, str)
                         or not k.replace('_', '').isalnum()
                         or any(c in k + v for c in '\r\n\0') for k, v in policy.items()):
        raise ValueError('invalid policy')
    seen = set()
    lines = []
    for line in raw.decode().splitlines():
        key = line.partition('=')[0]
        if key in policy:
            if key in seen:
                raise ValueError('duplicate managed option: ' + key)
            seen.add(key)
        else:
            lines.append(line)
    return ('\n'.join(lines + [k + '=' + v for k, v in policy.items()]) + '\n').encode()


def configure(path, policy):
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError('symlink in configuration path')
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_size > 262144:
        raise ValueError('unsafe configuration file')
    original = path.read_bytes()
    updated = render(original, policy)
    fd, temporary = tempfile.mkstemp(prefix='.miniserv-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
            os.fchown(stream.fileno(), info.st_uid, info.st_gid)
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        current = path.stat()
        fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_mode', 'st_uid', 'st_gid')
        if any(getattr(current, k) != getattr(info, k) for k in fields) or path.read_bytes() != original:
            raise ValueError('configuration drift')
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text())
    if args.verify:
        raw = args.config.read_bytes()
        render(raw, policy)  # Reject ambiguous managed assignments before comparison.
        rows = dict(line.partition('=')[::2] for line in raw.decode().splitlines())
        if any(rows.get(k) != v for k, v in policy.items()):
            raise SystemExit('managed Webmin settings differ')
    else:
        configure(args.config, policy)
