#!/usr/bin/env python3
"""Prepare disposable inputs for the actual target playbook from a synthetic capture.

First run qualify-application-restore.yaml to create a synthetic source fixture.
Never use a production recovery directory with this qualification helper.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import secrets
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Nautobot/tests'))
from restore_local import archive, save, digest
spec = importlib.util.spec_from_file_location('capture', ROOT/'Nautobot/ansible/scripts/workload_capture.py')
capture = importlib.util.module_from_spec(spec); spec.loader.exec_module(capture)


def prepare(fixture, dump_sha256, parent):
    os.umask(0o077)
    fixture = fixture.resolve()
    if not re.fullmatch(r'/tmp/nautobot-restore-local-[A-Za-z0-9_-]+/run-[a-f0-9]{8}', str(fixture)):
        raise ValueError('synthetic_fixture_only')
    source = json.loads((fixture/'qualification.json').read_text())
    dump = fixture/'payload/postgresql_custom_dump'
    if digest(dump) != dump_sha256: raise ValueError('fixture_hash')
    token = 'nautobot-restore-'+secrets.token_hex(12)
    root = parent/token; root.mkdir(mode=0o700, parents=True)
    images = dict(source['images']); images['application'] = images.pop('app')
    save(root/'runtime.json', {'token': token, 'uid': os.getuid(), 'context': 'disposable',
                             'images': images, 'production_containers': [],
                             'restic_helper': str(ROOT/'restic/scripts/application-restore.py')})
    (root/'django-secret').write_text(secrets.token_hex(40))
    reference = fixture/('logical-reference.json' if source.get('recurring_logical') else 'source-logical.json')
    # Preserve exact reference bytes: recurring receipts bind their SHA-256.
    (root/'logical-reference.json').write_bytes(reference.read_bytes())
    payload = root/'source-payload'; payload.mkdir(mode=0o700)
    (payload/'postgresql_custom_dump').write_bytes(dump.read_bytes())
    config = (fixture/'nautobot_config.py').read_bytes()
    files = {'/var/lib/nautobot/runtime/nautobot_config.py': config,
             '/var/lib/nautobot/.config/containers/systemd/nautobot-web.container': b'[Container]\nImage=synthetic\n'}
    expected = {'media': archive(payload/'media', {'.':None,'devicetype-images':None,'health_check_storage_test':None,'image-attachments':None})}
    for section in ('configuration','quadlet_config_hashes'):
        members = dict(files)
        if section == 'quadlet_config_hashes':
            members['SHA256.json'] = json.dumps({k:hashlib.sha256(v).hexdigest() for k,v in files.items()},sort_keys=True).encode()
        with (payload/section).open('wb') as output: capture.archive(members, output)
        expected[section] = {k.lstrip('/'): {'type':'file','sha256':hashlib.sha256(v).hexdigest()} for k,v in members.items()}
    members = {'desired-state.yaml': b'synthetic: true\n','requirements.lock': b'nautobot==3.2.3\n',
               'qualified-image.json': json.dumps(images).encode(), 'observed-images-before-stop.json': json.dumps({role:'sha256:'+images['application' if role in ('web','worker','scheduler') else role] for role in ('postgresql','redis','web','worker','scheduler')},sort_keys=True).encode()}
    with (payload/'image_dependency_manifest').open('wb') as output: capture.archive(members, output)
    expected['image_dependency_manifest'] = {k:{'type':'file','sha256':hashlib.sha256(v).hexdigest()} for k,v in members.items()}
    metadata = json.loads((fixture/'source-metadata.json').read_text())
    versions = {'versions':metadata['versions'], 'migrations':[
        {'app':a,'name':n,'applied':t} for a,n,t in metadata['migrations']]}
    if source.get('recurring_logical'):
        captured = json.loads((fixture/'payload/versions_migrations').read_text())
        versions.update({k: captured[k] for k in ('logical_reference', 'logical_capture')})
    save(payload/'versions_migrations', versions)
    save(root/'members.json', expected)
    retrieval = root/'retrieval'; retrieval.mkdir(mode=0o700)
    (retrieval/'repository').write_text(str(root/'disposable-repository'))
    (retrieval/'password').write_text(secrets.token_hex(32)); save(retrieval/'credentials.json', {})
    base = [source['restic'], '--no-cache', '--repository-file',str(retrieval/'repository'), '--password-file',str(retrieval/'password')]
    def restic(*argv): return subprocess.check_output(base+list(argv), timeout=120)
    restic('init','--repository-version','2'); restic('backup','--host','disposable-local','--tag',token,str(payload))
    row = json.loads(restic('snapshots','--json'))[0]
    save(retrieval/'restore.json', {'snapshot_id':row['id'], 'repository_id':json.loads(restic('cat','config'))['id'],
        'repository_url':str(root/'disposable-repository'), 'hostname':'disposable-local', 'tags':[token],
        'payload_path':str(payload),'restic':source['restic'],
        'restic_version':subprocess.check_output([source['restic'],'version']).decode().strip(),
        'content_sha256':{p.name:digest(p) for p in payload.iterdir()},
        'maximum_bytes':{p.name:268435456 if p.name=='postgresql_custom_dump' else 16777216 for p in payload.iterdir()}})
    save(root/'ansible.json', {'restore_verified':True,'restore_execution_authorized':True,'restore_context':'disposable',
        'restore_root':str(root),'restore_token':token,'restore_scripts':str(ROOT/'Nautobot/ansible/scripts'),
        'restore_restic_helper':str(ROOT/'restic/scripts/application-restore.py')})
    return root


def delivery(fixture, dump_sha256, parent, reject_snapshot=False):
    os.umask(0o077)
    spec = importlib.util.spec_from_file_location('restore_bundle', ROOT/'Nautobot/ansible/scripts/application-restore-bundle.py')
    bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
    parent.mkdir(mode=0o700, exist_ok=False)
    source = prepare(fixture, dump_sha256, parent/'sources')
    token=source.name;root=parent/'runtime'/token;monitor=parent/'monitor';inputs=parent/'inputs';inputs.mkdir(mode=0o700)
    runtime=json.loads((source/'runtime.json').read_text());runtime['restic_helper']=str(root/'scripts/application-restore.py')
    (inputs/'runtime.json').write_text(json.dumps(runtime))
    files=[]
    def add(path,destination): files.append({'source':str(path),'destination':str(destination),'uid':os.getuid(),'sha256':bundle.sha(path)})
    for name in bundle.SCRIPTS+('application-restore.py','application-backup.py'):add(ROOT/bundle.FILES[name],root/'scripts'/name)
    add(inputs/'runtime.json',root/'runtime.json')
    for name in ('members.json','logical-reference.json'):add(source/name,root/name)
    if reject_snapshot:
        contract=json.loads((source/'retrieval/restore.json').read_text());contract['snapshot_id']='0'*64
        (source/'retrieval/restore.json').write_text(json.dumps(contract))
    for name in ('restore.json','repository'):add(source/'retrieval'/name,root/'retrieval'/name)
    secret=inputs/'credentials.json'
    secret.write_text(json.dumps({'django':(source/'django-secret').read_text(),
        'password':(source/'retrieval/password').read_text(),'id':'synthetic','key':'synthetic'}));secret.chmod(0o600)
    for path in (source/'django-secret',source/'retrieval/password',source/'retrieval/credentials.json'):path.unlink()
    evidence=parent/'receipts';evidence.mkdir(mode=0o700)
    extra={'restore_verified':True,'restore_execution_authorized':True,'restore_stage':True,'restore_context':'disposable',
           'restore_root':str(root),'restore_token':token,'restore_scripts':str(root/'scripts'),
           'restore_monitor_scripts':str(monitor),'restore_stage_uid':os.getuid(),'restore_files':files,
           'restore_credentials_file':str(secret),'restore_receipts':bundle.RECEIPTS,'restore_evidence':str(evidence)}
    (parent/'ansible.json').write_text(json.dumps(extra))
    (parent/'inventory.ini').write_text('[restore_target]\nlocalhost ansible_connection=local\n')
    return parent/'ansible.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--dump-sha256', required=True)
    parser.add_argument('--parent', type=Path, required=True)
    parser.add_argument('--delivery', action='store_true', help='Prepare the real staging and credential-delivery inputs')
    parser.add_argument('--reject-snapshot', action='store_true', help='Delivery failure case using an invalid snapshot')
    args = parser.parse_args()
    if args.reject_snapshot and not args.delivery:
        parser.error('--reject-snapshot requires --delivery')
    if args.delivery:
        print(delivery(args.fixture, args.dump_sha256, args.parent, args.reject_snapshot))
    else:
        print(prepare(args.fixture, args.dump_sha256, args.parent))


if __name__ == '__main__': main()
