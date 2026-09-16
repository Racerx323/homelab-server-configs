#!/usr/bin/env python3
"""Render a boot-only Pi memory-controller correction; never contact a host."""
import argparse
from pathlib import Path

TOKEN = b'cgroup_enable=memory'
QUIRK = b'usb-storage.quirks=152d:0583:u'


def render(original):
    if not original or len(original) > 16384:
        raise ValueError('invalid boot file size')
    original.decode('ascii')
    ending = b'\r\n' if original.endswith(b'\r\n') else b'\n' if original.endswith(b'\n') else b''
    line = original[:-len(ending)] if ending else original
    if any(c < 32 and c != 9 for c in line) or b'\x7f' in line or b'#' in line:
        raise ValueError('expected one plain kernel command line')
    tokens = line.split()
    quirks = [t for t in tokens if t.startswith(b'usb-storage.quirks=')]
    if quirks != [QUIRK] or len([t for t in tokens if t.startswith(b'root=')]) != 1:
        raise ValueError('unreviewed root or transport')
    for token in tokens:
        if token.startswith(b'cgroup_disable=') and b'memory' in token.split(b'=', 1)[1].split(b','):
            raise ValueError('explicit disabling argument needs separate review')
        if token.startswith(b'cgroup_memory='):
            raise ValueError('obsolete argument needs separate review')
        if token.startswith(b'cgroup_enable=') and b'memory' in token.split(b'=', 1)[1].split(b',') and token != TOKEN:
            raise ValueError('combined memory override needs separate review')
    if tokens.count(TOKEN) > 1:
        raise ValueError('duplicate memory override')
    return original if TOKEN in tokens else line + b' ' + TOKEN + ending


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    if args.source.is_symlink():
        parser.error('source symlink refused')
    result = render(args.source.read_bytes())
    with args.destination.open('xb') as stream:
        args.destination.chmod(0o600)
        stream.write(result)
