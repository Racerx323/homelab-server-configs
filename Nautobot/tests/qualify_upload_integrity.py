#!/usr/bin/env python3
"""Disposable real Restic/PostgreSQL/Ansible/systemd upload qualification.

Only the application health probe and Doppler provider are local adapters.
Never uses production credentials, inventory, payloads or repository.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import subprocess
import sys
import time

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
sys.dont_write_bytecode = True
import upload_node as node


def call(argv, **kwargs):
    return subprocess.run(argv, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout


def write(path, value, mode=0o600):
    path.write_text(value if isinstance(value, str) else json.dumps(value))
    path.chmod(mode)


def tree(root):
    files, directories = {}, {}
    for path in [root, *root.rglob('*')]:
        info = path.stat()
        item = dict(uid=info.st_uid, gid=info.st_gid, mode=info.st_mode & 0o777)
        if path.is_file():
            item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            files[str(path.relative_to(root))] = item
        else:
            directories[str(path.relative_to(root))] = item
    return dict(files=files, directories=directories)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--restic', type=Path, required=True)
    parser.add_argument('--image', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(mode=0o700)
    actual = args.restic.resolve()
    cid = call(['podman', 'run', '-d', '--pull=never', '--network=none', '-e',
                'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=nautobot', args.image]).decode().strip()
    prefix = ['podman', 'exec', '-i', '--user', 'postgres', cid]
    summary = {}
    try:
        deadline = time.monotonic()+60
        while subprocess.run(prefix+['pg_isready', '-U', 'postgres', '-d', 'nautobot'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            assert time.monotonic() < deadline
            time.sleep(0.5)
        call(prefix+['psql', '-U', 'postgres', '-d', 'nautobot', '-c',
                    'CREATE TABLE sample AS SELECT n, md5(n::text) value FROM generate_series(1,1000) n;'])
        dump = call(prefix+['pg_dump', '-U', 'postgres', '-d', 'nautobot', '-Fc'])
        call(prefix+['pg_restore', '--list'], input=dump)
        # Import the unmodified producer; its capture receipt is created by real execution.
        spec = importlib.util.spec_from_file_location('producer', ROOT/'restic/scripts/application-backup.py')
        producer = importlib.util.module_from_spec(spec); spec.loader.exec_module(producer)
        for case in ('success', 'payload_drift', 'service_drift', 'preexisting_secret', 'integrity_failure', 'timeout'):
            base = args.output/case; base.mkdir(mode=0o700)
            payload = base/'capture'; payload.mkdir(mode=0o700)
            capture = base/'qualification'; capture.mkdir(mode=0o700)
            (capture/'state').mkdir(mode=0o700); write(capture/'state/run.lock', '')
            (capture/'scripts').mkdir(mode=0o700)
            # Disposable service adapter only; the production entrypoint is still exercised.
            write(capture/'scripts/recurring_node.py', 'def health():\n    return {"local_application": "healthy"}\n')
            source = base/'input'; source.mkdir(mode=0o700)
            (source/'dump').write_bytes(dump); (source/'dump').chmod(0o600)
            write(source/'metadata', 'disposable application metadata\n')
            password = secrets.token_hex(24)
            write(base/'password', password)
            repository = base/'repository'
            restic_args = [str(actual), '--no-cache', '-r', str(repository), '--password-file', str(base/'password')]
            call(restic_args+['init', '--repository-version', '2'])
            identity = json.loads(call(restic_args+['cat', 'config']))['id']
            # Faults occur at real command boundaries after actual snapshot creation.
            wrapper = base/'restic'
            write(wrapper, '#!/usr/bin/python3\nimport os,sys,time\n'
                  + ("if 'check' in sys.argv: sys.exit(23)\n" if case == 'integrity_failure' else '')
                  + ("if 'backup' in sys.argv: time.sleep(60)\n" if case == 'timeout' else '')
                  + f'os.execv({str(actual)!r}, [{str(actual)!r}, *sys.argv[1:]])\n', 0o700)
            contract = dict(schema_version=1, operation_id='local-upload', authorized=True,
                            repository_id=identity, repository_url=str(repository), restic=str(wrapper),
                            restic_version=call([str(actual), 'version']).decode().strip(), execution_uid=os.getuid(),
                            required_filesystem=call(['/usr/bin/findmnt', '-n', '-o', 'SOURCE', '--target', str(payload)]).decode().strip(),
                            hostname='disposable', source_consistency_reviewed=True, timeout_seconds=300,
                            dump_validator=prefix+['pg_restore', '--list'], captures={})
            contract['dump_validator'] = ['/usr/bin/env', 'HOME='+str(Path.home()),
                'XDG_RUNTIME_DIR=/run/user/'+str(os.getuid()), shutil.which('podman'), *contract['dump_validator'][1:]]
            for name in producer.SECTIONS:
                contract['captures'][name] = dict(argv=['/bin/cat', str(source/('dump' if name == 'postgresql_custom_dump' else 'metadata'))], maximum_bytes=1048576)
            write(payload/'repository', str(repository)); write(payload/'password', password)
            write(payload/'credentials.json', {}); write(payload/'application-backup.json', contract)
            captured = producer.run(payload, contract, phase='capture')
            assert captured['capture_passed'] and all(captured['credential_cleanup'].values())
            write(base/'token', 'dp.st.'+secrets.token_hex(24))
            write(base/'provider-values', dict(password=password, key_id=secrets.token_hex(12), key=secrets.token_hex(24)))
            provider = base/'doppler'
            write(provider, '#!/usr/bin/python3\nimport json,sys\n'
                  + f'v=json.load(open({str(base/"provider-values")!r}))\n'
                  + "name=sys.argv[-2]\nprint(v['password' if name.endswith('PASSWORD') else 'key_id' if name.endswith('_ID') else 'key'])\n", 0o700)
            bundle = base/'bundle'; (bundle/'runtime/scripts').mkdir(parents=True, mode=0o700)
            runtime = bundle/'runtime'
            for name in ('upload_node.py', 'capture_retained.py', 'recurring_delivery.py', 'recurring_protection.py'):
                shutil.copyfile(SCRIPTS/name, runtime/'scripts'/name)
            shutil.copyfile(ROOT/'restic/scripts/application-backup.py', runtime/'scripts/application-backup.py')
            op = dict(operation=dict(stage='recurring_upload_integrity_qualification', execution_enabled=True),
                      target=dict(name='j2-svpi4mf', address='127.0.0.1', uid=os.getuid(), gid=os.getgid(),
                                  user=pwd.getpwuid(os.getuid()).pw_name, home=str(Path.home())),
                      capture_root=str(capture), payload_root=str(payload), evidence_root=str(base/'evidence'),
                      boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                      qualification_tree=tree(capture), payload_tree=tree(payload),
                      restic=dict(path=str(wrapper), version=contract['restic_version'], sha256=hashlib.sha256(wrapper.read_bytes()).hexdigest()),
                      repository=dict(id=identity, url=str(repository)), content_sha256=captured['content_sha256'],
                      doppler_sha256=hashlib.sha256(provider.read_bytes()).hexdigest(),
                      services={'local_application':'healthy'}, credentials=dict(project='homelab-dev', config='prd_nautobot_backup',
                      read_only=True, expires_at='2099-01-01T00:00:00+00:00', token_file=str(base/'token'), doppler=str(provider)))
            if case == 'payload_drift': write(payload/'payload/media', 'changed')
            if case == 'service_drift': op['services'] = {'local_application':'different'}
            if case == 'preexisting_secret': write(payload/'password', password)
            write(runtime/'operation.json', op)
            playbook = ROOT/'Nautobot/ansible/playbooks/qualify-upload-integrity.yaml'
            if case == 'timeout':
                # Shorten only the native runtime deadline for a bounded failure test.
                testplay = base/'timeout.yaml'
                write(testplay, playbook.read_text().replace('RuntimeMaxSec=420', 'RuntimeMaxSec=3'))
                playbook = testplay
            write(base/'inventory', '[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_connection=local ansible_become=false ansible_python_interpreter=/usr/bin/python3\n')
            inputs = dict(capture_bundle_verified=True, capture_operation=op, capture_bundle=str(bundle), ansible_become=False)
            write(base/'inputs.json', inputs)
            argv = ['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), shutil.which('ansible-playbook'),
                    '-i', str(base/'inventory'), str(playbook), '-e', '@'+str(base/'inputs.json')]
            with (base/'ansible.log').open('wb') as log:
                result = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, timeout=150)
            assert (result.returncode == 0) == (case == 'success'), (case, result.returncode)
            snapshots = json.loads(call(restic_args+['snapshots', '--json']))
            expected = 1 if case in ('success', 'integrity_failure') else 0
            assert len(snapshots) == expected, (case, snapshots)
            assert not call(restic_args+['list', 'locks']).strip()
            for name in node.SECRETS:
                assert (payload/name).exists() == (case == 'preexisting_secret' and name == 'password'), (case, name)
            for name, digest in captured['content_sha256'].items():
                if case == 'payload_drift' and name == 'media': continue
                assert hashlib.sha256((payload/'payload'/name).read_bytes()).hexdigest() == digest
            assert tree(capture) == op['qualification_tree']
            if case == 'success':
                receipt = json.loads((payload/'application-backup-result.json').read_text())
                assert receipt['integrity_passed'] and receipt['snapshot_id'] == snapshots[0]['id']
                with (base/'replay.log').open('wb') as log:
                    replay = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, timeout=60)
                assert replay.returncode != 0
                assert len(json.loads(call(restic_args+['snapshots', '--json']))) == 1
            if case in ('timeout', 'integrity_failure'):
                assert all(json.loads((base/'evidence/cleanup.json').read_text()).values())
            summary[case] = dict(passed=True, ansible_exit_status=result.returncode, snapshots=len(snapshots))
            print(case+': passed', flush=True)
        write(args.output/'summary.json', dict(cases=summary, real_postgresql_dump=True,
              real_restic=True, real_ansible_playbook=True, real_user_systemd=True,
              adapters=['application health', 'Doppler provider'], production_acceptance=False))
    finally:
        call(['podman', 'rm', '-f', cid])


if __name__ == '__main__': main()
