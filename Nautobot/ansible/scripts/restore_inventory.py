#!/usr/bin/env python3
"""Derive expected members from independent preserved capture inputs, offline."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile


def digest(data): return hashlib.sha256(data).hexdigest()


def inventory(files, directories, dependencies, images, expected):
    from workload_capture import archive
    config = '/var/lib/nautobot/runtime/nautobot_config.py'
    if config not in files: raise ValueError('configuration_missing')
    for name, sha in files.items():
        p = Path(name)
        if not re.fullmatch('[a-f0-9]{64}', sha): raise ValueError('source_hash')
        if name != config and not (str(p.parent) == '/var/lib/nautobot/.config/containers/systemd'
                and p.name.startswith('nautobot-') and p.suffix in ('.container','.network','.volume')):
            raise ValueError('source_path')
    members = {name.lstrip('/'): {'type':'file','sha256':sha} for name,sha in files.items()}
    result = {'configuration':members, 'quadlet_config_hashes':dict(members)}
    result['quadlet_config_hashes']['SHA256.json'] = {'type':'file','sha256':digest(json.dumps(files,sort_keys=True).encode())}
    media = io.BytesIO()
    with tarfile.open(fileobj=media, mode='w|') as stream:
        for name in ['.']+directories:
            path = Path(name)
            if path.is_absolute() or '..' in path.parts or str(path) != name: raise ValueError('media_path')
            item = tarfile.TarInfo(name); item.type = tarfile.DIRTYPE; item.mode = 0o750; stream.addfile(item)
    if digest(media.getvalue()) != expected['media']: raise ValueError('media_archive_identity')
    result['media'] = {name:{'type':'directory'} for name in ['.']+directories}
    if set(dependencies) != {'desired-state.yaml','requirements.lock','qualified-image.json'}:
        raise ValueError('dependency_files')
    contents = dict(dependencies); contents['observed-images-before-stop.json'] = json.dumps(images,sort_keys=True).encode()
    output = io.BytesIO(); archive(contents,output)
    if digest(output.getvalue()) != expected['image_dependency_manifest']: raise ValueError('dependency_archive_identity')
    result['image_dependency_manifest'] = {name:{'type':'file','sha256':digest(data)} for name,data in contents.items()}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--before',type=Path,required=True)
    parser.add_argument('--receipt',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    before=json.loads(args.before.read_text()); receipt=json.loads(args.receipt.read_text())
    files=json.loads((args.inputs/'backup-sources.json').read_text())['files']
    dependencies={name:(args.inputs/name).read_bytes() for name in ('desired-state.yaml','requirements.lock','qualified-image.json')}
    result=inventory(files,before['media'],dependencies,before['images'],receipt['content_sha256'])
    with args.output.open('x') as stream: json.dump(result,stream,sort_keys=True,indent=2)
    args.output.chmod(0o600)


if __name__ == '__main__': main()
