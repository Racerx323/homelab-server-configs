#!/usr/bin/env python3
"""Real Ansible/Restic boundary test with disposable writer-command adapters.

No production services, provider or host contact. Writer adapters intentionally
model failure; they do not qualify systemd recovery or a node-local watchdog.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]


def call(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, timeout=300, **kwargs).stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--restic', required=True, type=Path)
    parser.add_argument('--dump', required=True, type=Path, help='Disposable-only PostgreSQL custom dump')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert args.restic.is_absolute() and args.dump.read_bytes().startswith(b'PGDMP')
    args.output.mkdir(mode=0o700)
    results = []
    with tempfile.TemporaryDirectory(prefix='nautobot-capture-test.') as directory:
        root = Path(directory)
        source = root/'source'; source.mkdir(mode=0o700)
        (source/'password').write_text(secrets.token_hex(32)); (source/'password').chmod(0o600)
        (source/'credentials.json').write_text('{}'); (source/'credentials.json').chmod(0o600)
        for scenario in ('success', 'capture_failure', 'resume_failure', 'health_failure', 'payload_drift', 'upload_failure', 'integrity_failure'):
            run = Path(tempfile.mkdtemp(prefix='nautobot-capture-case.'))
            try:
                state = run/'writer'; state.write_text('running')
                events = run/'events'
                repository = run/'repo'
                call([str(args.restic), '--no-cache', '-r', str(repository), '-p', str(source/'password'), 'init', '--repository-version', '2'])
                repo_id = json.loads(call([str(args.restic), '-r', str(repository), '-p', str(source/'password'), 'cat', 'config']))['id']
                driver = run/'driver.py'
                # This executable is a test adapter, never installed on a target.
                driver.write_text('''import pathlib,subprocess,sys
root=pathlib.Path(__file__).parent
mode=sys.argv[1]
scenario='''+repr(scenario)+'''
with (root/'events').open('a') as out:out.write(mode+'\\n')
if mode=='pause': (root/'writer').write_text('paused')
elif mode=='resume':
    if scenario=='resume_failure':sys.exit(1)
    (root/'writer').write_text('running')
elif mode=='resume_remaining': pass
elif mode=='health':
    assert (root/'writer').read_text()=='running'
    if scenario=='health_failure':sys.exit(1)
    if scenario=='payload_drift':(root/'payload/media').write_text('changed')
elif mode=='capture':
    assert (root/'writer').read_text()=='paused'
    if scenario=='capture_failure':sys.exit(1)
    sys.stdout.buffer.write(pathlib.Path('''+repr(str(args.dump))+''').read_bytes())
elif mode=='restic':
    if 'backup' in sys.argv:
        assert (root/'writer').read_text()=='running'
        with (root/'events').open('a') as out:out.write('upload\\n')
        if scenario=='upload_failure':sys.exit(1)
    if 'check' in sys.argv and scenario=='integrity_failure':sys.exit(1)
    sys.exit(subprocess.call(['''+repr(str(args.restic))+''']+sys.argv[2:]))
else:raise ValueError('mode')
''')
                wrapper = run/'restic'
                wrapper.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv('+repr(sys.executable)+', ['+repr(sys.executable)+','+repr(str(driver))+',"restic"]+sys.argv[1:])\n'); wrapper.chmod(0o700)
                payload_source = run/'fixture'; payload_source.write_text('synthetic content\n')
                sections = ('postgresql_custom_dump', 'media', 'configuration', 'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations')
                spec = {'schema_version':1,'operation_id':'disposable-capture','authorized':True,'repository_id':repo_id,
                        'restic':str(wrapper),'restic_version':call([str(args.restic),'version']).decode().strip(),
                        'repository_url':str(repository),'hostname':'disposable','execution_uid':os.getuid(),
                        'source_consistency_reviewed':True,'timeout_seconds':120,
                        'required_filesystem':call(['/usr/bin/findmnt','-n','-o','SOURCE','--target',str(run)]).decode().strip(),
                        'captures':{name:{'argv':[sys.executable,str(driver),'capture'] if name=='postgresql_custom_dump' else ['/usr/bin/cat',str(payload_source)],'maximum_bytes':67108864} for name in sections},
                        'dump_validator':['/usr/bin/test','-s','/dev/stdin']}
                # Full dump parsing is independently covered by the disposable database
                # qualification; this test focuses on lifecycle and upload boundaries.
                for name,value in [('application-backup.json',json.dumps(spec)),('repository',str(repository))]:
                    (run/name).write_text(value); (run/name).chmod(0o600)
                variables = {'application_capture_authorized':True,'application_backup_root':str(run),
                             'application_guard_check_argv':['/bin/true'],
                             'application_pause_commands':[[sys.executable,str(driver),'pause']],
                             'application_resume_commands':[[sys.executable,str(driver),'resume'],[sys.executable,str(driver),'resume_remaining']],
                             'application_health_argv':[sys.executable,str(driver),'health'],
                             'application_backup_credentials':{name:str(source/name) for name in ('password','credentials.json')},
                             'application_producer_argv':[sys.executable,str(ROOT/'restic/scripts/application-backup.py')]}
                play = root/'play.yaml'
                play.write_text(yaml.safe_dump([{'name':'Disposable capture boundary','hosts':'localhost','connection':'local','gather_facts':False,
                    'vars':variables,'tasks':[{'ansible.builtin.include_tasks':str(ROOT/'Nautobot/ansible/tasks/capture-resume-upload.yaml')}]}]))
                result = subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,',str(play)],capture_output=True,timeout=240)
                (args.output/(scenario+'.log')).write_bytes(result.stdout+result.stderr)
                log = events.read_text().splitlines()
                snapshots = json.loads(call([str(args.restic),'-r',str(repository),'-p',str(source/'password'),'snapshots','--json']))
                assert (result.returncode==0)==(scenario=='success'), (scenario,result.returncode)
                assert 'resume' in log and 'resume_remaining' in log and 'health' in log, (scenario,log)
                assert not any((run/name).exists() for name in ('password','credentials.json'))
                if scenario in ('capture_failure','resume_failure','health_failure','payload_drift'):
                    assert 'upload' not in log and not snapshots, (scenario,log)
                else:
                    assert log.index('resume') < log.index('health') < log.index('upload')
                    assert len(snapshots)==(0 if scenario=='upload_failure' else 1)
                if scenario!='resume_failure': assert state.read_text()=='running'
                results.append({'scenario':scenario,'passed':True,'ansible_exit':result.returncode,'snapshots':len(snapshots),'events':log})
            finally:
                shutil.rmtree(run)
    (args.output/'result.json').write_text(json.dumps({'cases':results,'production_recovery_qualified':False},indent=2)+'\n')
    print(json.dumps(results))


if __name__=='__main__': main()
