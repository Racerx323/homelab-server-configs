#!/usr/bin/env python3
"""Freeze local observation inputs into a deterministic review bundle; no SSH."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

WEBMIN = Path(__file__).resolve().parents[1]


def prepare(operation, output):
    operation, output = Path(operation), Path(output)
    spec = json.loads(operation.read_text())
    if spec['sample_seconds'] != 60 or spec['interval_seconds'] != 300:
        raise ValueError('This reviewed action requires one-minute samples and five-minute polling')
    if spec['expected_devices'] != ['/dev/sda']:
        raise ValueError('This reviewed action is limited to the qualified single disk')
    manifest = json.loads((WEBMIN / 'patches/disk-only-discovery.json').read_text())
    for name, hashes in manifest['files'].items():
        if spec['files'].get('/usr/share/webmin/' + name) != hashes['after']:
            raise ValueError('Operation does not pin the qualified discovery patch')
    output.mkdir(mode=0o700)
    sources = {'observer.py': WEBMIN / 'scripts/observe-disk-discovery.py',
               'start.py': WEBMIN / 'scripts/start-disk-discovery-observation.py',
               'operation.json': operation, 'PROCEDURE.md': WEBMIN / 'docs/DISK_DISCOVERY_OBSERVATION.md'}
    hashes = {}
    for name, source in sources.items():
        shutil.copyfile(source, output / name)
        hashes[name] = hashlib.sha256((output / name).read_bytes()).hexdigest()
    (output / 'checksums.json').write_text(json.dumps(hashes, sort_keys=True, indent=2) + '\n')
    bundle = output / 'observation.tar'
    with tarfile.open(bundle, 'w', format=tarfile.USTAR_FORMAT) as archive:
        for name in sorted([*sources, 'checksums.json']):
            path = output / name
            info = archive.gettarinfo(str(path), name)
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ''
            info.mode = 0o600
            with path.open('rb') as stream:
                archive.addfile(info, stream)
    return bundle, hashlib.sha256(bundle.read_bytes()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    path, digest = prepare(args.operation, args.output)
    print(f'{digest}  {path}')
