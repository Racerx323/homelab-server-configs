#!/usr/bin/env python3
"""Read-only directory-only media inspection/archive inside Podman's user namespace."""
import argparse
import json
import os
from pathlib import Path
import sys
import tarfile


def directories(root):
    if any(p.is_symlink() for p in (root,*root.parents)) or not root.is_dir():
        raise ValueError('media_root')
    found=[]; pending=[root]
    while pending:
        with os.scandir(pending.pop()) as entries:
            for entry in entries:
                if not entry.is_dir(follow_symlinks=False): raise ValueError('media_not_empty_directory_tree')
                path=Path(entry.path); name=str(path.relative_to(root))
                if len(name.encode())>1024 or any(ord(c)<32 for c in name): raise ValueError('media_name')
                found.append(name)
                if len(found)>100: raise ValueError('media_entry_limit')
                pending.append(path)
    return sorted(found)


def archive(root,stream):
    before=directories(root)
    with tarfile.open(fileobj=stream,mode='w|') as output:
        for name in ['.']+before:
            info=tarfile.TarInfo(name);info.type=tarfile.DIRTYPE;info.mode=0o750
            output.addfile(info)
    if directories(root)!=before: raise ValueError('media_changed')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('action',choices=['inspect','archive']);args=parser.parse_args()
    try:
        if args.action=='inspect': print(json.dumps(directories(args.root)))
        else: archive(args.root,sys.stdout.buffer)
    except Exception:
        print('media_namespace_failed',file=sys.stderr);raise SystemExit(1)
