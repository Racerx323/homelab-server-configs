#!/usr/bin/env python3
"""Prepare an offline, hash-bound Webmin candidate. Never contacts a target."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

WEBMIN = Path(__file__).resolve().parents[1]
FILES = ('fdisk/fdisk-lib.pl', 'smart-status/smart-status-lib.pl',
         'system-status/system-status-lib.pl')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, output):
    source, output = Path(source).resolve(), Path(output).absolute()
    spec_path = WEBMIN / 'patches/disk-only-discovery.json'
    spec = json.loads(spec_path.read_text())
    patch = WEBMIN / 'patches/disk-only-discovery.patch'
    if set(spec['files']) != set(FILES) or digest(patch) != spec['patch_sha256']:
        raise ValueError('Candidate manifest or patch mismatch')
    for name in FILES:
        path = source / name
        if path.is_symlink() or not path.is_file() or digest(path) != spec['files'][name]['before']:
            raise ValueError('Baseline mismatch: ' + name)
    # All baseline checks precede creation. Existing output is never overwritten.
    output.mkdir(mode=0o700)
    for tree in ['before', 'after']:
        for name in FILES:
            path = output / tree / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, path)
    shutil.copyfile(patch, output / patch.name)
    shutil.copyfile(spec_path, output / 'manifest.json')
    shutil.copyfile(WEBMIN / 'docs/DISK_DISCOVERY_DEPLOYMENT.md', output / 'DEPLOYMENT.md')
    subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '-d', str(output / 'after'),
                    '-i', str(output / patch.name)], check=True, capture_output=True)
    for name in FILES:
        if digest(output / 'after' / name) != spec['files'][name]['after']:
            raise ValueError('Patched source mismatch: ' + name)
    members = sorted(p for p in output.rglob('*') if p.is_file())
    (output / 'SHA256SUMS').write_text(''.join(
        f'{digest(p)}  {p.relative_to(output)}\n' for p in members))
    members.append(output / 'SHA256SUMS')
    bundle = output / 'candidate.tar'
    with tarfile.open(bundle, 'w', format=tarfile.USTAR_FORMAT) as archive:
        for p in sorted(members):
            info = archive.gettarinfo(str(p), str(p.relative_to(output)))
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ''
            info.mode = 0o600
            with p.open('rb') as stream:
                archive.addfile(info, stream)
    return bundle, digest(bundle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Local directory containing the three pinned module sources')
    parser.add_argument('output', type=Path, help='New local staging directory; must not exist')
    args = parser.parse_args()
    bundle, sha = prepare(args.source, args.output)
    print(f'{sha}  {bundle}')


if __name__ == '__main__':
    main()
