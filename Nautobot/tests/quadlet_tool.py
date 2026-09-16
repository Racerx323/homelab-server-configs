#!/usr/bin/env python3
"""Prepare an integrity-checked local parser; tests never download tools implicitly."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
VERSION = '5.4.2'
SOURCE_SHA256 = '8da62c25956441b14d781099e803e38410a5753e5c7349bcd34615b9ca5ed4f2'
URL = f'https://github.com/containers/podman/archive/refs/tags/v{VERSION}.tar.gz'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cache():
    gitdir = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', '--absolute-git-dir'], text=True).strip()
    return Path(gitdir) / 'nautobot-tools' / f'quadlet-{VERSION}'


def resolve(directory=None):
    directory = directory or cache()
    binary, receipt = directory / 'quadlet', directory / 'receipt.json'
    try:
        record = json.loads(receipt.read_text())
        if binary.is_symlink() or receipt.is_symlink() or not os.access(binary, os.X_OK):
            raise ValueError('unsafe parser cache')
        if record != {'source_sha256': SOURCE_SHA256, 'binary_sha256': digest(binary)}:
            raise ValueError('parser cache integrity mismatch')
    except (OSError, ValueError) as error:
        raise RuntimeError('Prepare the pinned parser: python3 Nautobot/tests/quadlet_tool.py --prepare') from error
    return binary


def prepare(archive=None):
    directory = cache()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='build-', dir=directory) as tmp:
        work = Path(tmp)
        source = archive
        if source is None:
            source = work / 'source.tar.gz'
            urllib.request.urlretrieve(URL, source)
        if digest(source) != SOURCE_SHA256:
            raise ValueError('Podman source archive checksum mismatch')
        with tarfile.open(source) as stream:
            stream.extractall(work, filter='data')
        binary = work / 'quadlet'
        subprocess.run(['go', 'build', '-mod=vendor', '-o', str(binary), './cmd/quadlet'],
                       cwd=work / f'podman-{VERSION}', env={**os.environ, 'CGO_ENABLED': '0'}, check=True)
        record = {'source_sha256': SOURCE_SHA256, 'binary_sha256': digest(binary)}
        receipt = work / 'receipt.json'
        receipt.write_text(json.dumps(record) + '\n')
        binary.replace(directory / 'quadlet')
        receipt.replace(directory / 'receipt.json')
    return resolve(directory)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--archive', type=Path, help='Use an existing archive with the same pinned checksum')
    args = parser.parse_args()
    if args.archive and not args.prepare:
        parser.error('--archive requires --prepare')
    print(prepare(args.archive) if args.prepare else resolve())
