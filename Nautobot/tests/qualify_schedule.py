#!/usr/bin/env python3
"""Real SSH/sudo installer and two calendar cycles in disposable user-systemd.

Only application, provider, media and filesystem-type observations are adapted.
Unit installation, journal access, permissions, hashes, package query, Ansible,
Restic upload/full check, disposal, notification HTTP and rollback are real.
"""
import argparse
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True, timeout=240, **kwargs)


def qualify(image, restic, output):
    output.mkdir(mode=0o700)
    with tempfile.TemporaryDirectory(prefix='schedule-qualification.') as temporary:
        local = Path(temporary)
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(local/'key')])
        cid = run(['podman', 'run', '-d', '--pull=never', '--systemd=always',
                   '--hostname', 'j2-svpi4mf', '--publish', '127.0.0.1::22', image]).stdout.strip()
        def container(*args): return run(['podman', 'exec', cid, *args])
        env = ['env', 'HOME=/var/lib/nautobot', 'XDG_RUNTIME_DIR=/run/user/999',
               'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus', 'PYTHONDONTWRITEBYTECODE=1']
        def user(*args): return container('sudo', '-u', 'nautobot', *env, *args)
        try:
            run(['podman', 'cp', str(local/'key.pub'), cid+':/home/operator/.ssh/authorized_keys'])
            container('chown', '-R', 'operator:operator', '/home/operator/.ssh')
            container('chmod', '0600', '/home/operator/.ssh/authorized_keys')
            for _ in range(30):
                if subprocess.run(['podman', 'exec', cid, 'systemctl', 'is-active', 'ssh', 'user@999.service'],
                                  capture_output=True).returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('container_not_ready')
            run(['podman', 'cp', str(restic), cid+':/usr/local/bin/restic'])
            container('chmod', '0755', '/usr/local/bin/restic')
            spec = importlib.util.spec_from_file_location('schedule_bundle', SCRIPTS/'schedule-bundle.py')
            bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
            candidate = local/'candidate'; bundle.transport.freeze(candidate)
            op = yaml.safe_load((candidate/'operation.yaml').read_text())
            runtime = op['runtime_directory']; state = op['state_directory']; base = '/var/lib/nautobot/schedule-fixture'
            container('install', '-d', '-m', '0700', '-o', '999', '-g', '985', base,
                      '/var/lib/nautobot/protection/staging')
            fixture = '''import json,pathlib,os
b=pathlib.Path('/var/lib/nautobot/schedule-fixture')
for n,v in [('password','disposable-local-only'),('token','dp.st.disposable'),('metadata.json',json.dumps({'expires_at':'2099-01-01T00:00:00+00:00'}))]:
 p=b/n;p.write_text(v);p.chmod(0o600)
'''
            user('/usr/bin/python3', '-c', fixture)
            user('/usr/local/bin/restic', '--no-cache', '-r', base+'/repository', '-p', base+'/password', 'init', '--repository-version', '2')
            config = json.loads(user('/usr/local/bin/restic', '-r', base+'/repository', '-p', base+'/password', 'cat', 'config').stdout)
            user('/usr/bin/python3', '-c', 'from pathlib import Path;Path('+repr(base+'/repository-id')+').write_text('+repr(config['id'])+')')
            # Native user services provide real InvocationIDs; HTTP/media are application adapters.
            user('/usr/bin/mkdir', '-p', '/var/lib/nautobot/.config/systemd/user')
            for role in ('postgresql', 'redis', 'web', 'worker', 'scheduler'):
                user('/usr/bin/python3', '-c', 'from pathlib import Path;Path('+repr('/var/lib/nautobot/.config/systemd/user/nautobot-'+role+'.service')+').write_text("[Service]\\nExecStart=/usr/bin/sleep infinity\\n")')
            user('/usr/bin/systemctl', '--user', 'daemon-reload')
            names = ['nautobot-'+r+'.service' for r in ('postgresql', 'redis', 'web', 'worker', 'scheduler')]
            user('/usr/bin/systemctl', '--user', 'start', *names)
            container('chmod', '0700', '/var/lib/nautobot/.config/systemd/user')
            op['boot_id'] = container('cat', '/proc/sys/kernel/random/boot_id').stdout.strip()
            digest = container('sha256sum', '/etc/debian_version').stdout.split()[0]
            op['baseline'] = {'collected_at': datetime.now(timezone.utc).isoformat(),
                'artifact_sha256': {'/etc/debian_version': digest}, 'binding_artifact_sha256': {},
                'service_invocations': {n: user('/usr/bin/systemctl', '--user', 'show', n, '--property=InvocationID', '--value').stdout.strip() for n in names},
                'media_directories': []}
            version, arch = container('dpkg-query', '-W', '-f=${Version} ${Architecture}', 'libc6').stdout.split()
            op['packages'] = [{'name': 'libc6', 'version': version, 'architecture': arch}]
            op['credential_identity'] = {'expires_at': '2099-01-01T00:00:00+00:00'}
            op['binding']['credentials'].update(token_file=base+'/token', metadata_file=base+'/metadata.json')
            op['binding']['minimum_free_bytes'] = 1048576
            op['binding']['capture_limits'] = {n: 1048576 for n in op['binding']['capture_limits']}
            guard = candidate/'schedule_install.py'
            text = guard.read_text()
            # Keep actual file/package/service-manager guards; replace only unavailable app/storage probes.
            insertion = '''
native_command = command
def command(argv):
    if argv[:3] == ['/usr/bin/podman','unshare','/usr/bin/find']: return 'd|'
    if argv[:3] == ['/usr/bin/podman','unshare','/usr/bin/python3']: return ''
    if argv[:3] == ['/usr/bin/findmnt','-no','FSTYPE']: return 'ext4'
    return native_command(argv)
def services():
    rows={}
    for role in ('postgresql','redis','web','worker','scheduler'):
        name='nautobot-'+role+'.service'
        assert system('show',name,'--property=ActiveState','--value')=='active'
        rows[name]=system('show',name,'--property=InvocationID','--value')
    return rows
'''
            text = text.replace("if __name__ == '__main__':", insertion+"\nif __name__ == '__main__':")
            guard.write_text(text); (candidate/'runtime/scripts/schedule_install.py').write_text(text)
            shutil.copyfile(ROOT/'Nautobot/tests/fixtures/schedule-driver.py', candidate/'runtime/scripts/schedule-driver.py')
            c = json.loads((candidate/'runtime/supervisor.json').read_text())
            driver = ['/usr/bin/python3', runtime+'/scripts/schedule-driver.py']
            c.update(start_hour=0, end_hour=24, prepare_argv=driver+['prepare'], resume_commands=[driver+['resume']],
                     health_argv=driver+['health'])
            c.pop('latest_start_minute'); c.pop('staging_directory'); c.pop('staging_filesystem')
            (candidate/'runtime/supervisor.json').write_text(json.dumps(c))
            b = json.loads((candidate/'runtime/binding.json').read_text())
            b['notification']['endpoint'] = 'http://127.0.0.1:18080/notify/apprise'
            (candidate/'runtime/binding.json').write_text(json.dumps(b))
            delivery = candidate/'runtime/scripts/recurring_delivery.py'
            delivery.write_text(delivery.read_text().replace('http://10.1.3.83:8000/notify/apprise', b['notification']['endpoint']))
            server = '''from http.server import HTTPServer,BaseHTTPRequestHandler
from pathlib import Path
class Handler(BaseHTTPRequestHandler):
 def do_POST(self):
  data=self.rfile.read(int(self.headers['Content-Length']))
  with Path('/var/lib/nautobot/schedule-fixture/notifications').open('ab') as out:out.write(data+b'\\n')
  self.send_response(200);self.end_headers()
 def log_message(self,*args):pass
HTTPServer(('127.0.0.1',18080),Handler).serve_forever()
'''
            (local/'notify_receiver.py').write_text(server)
            run(['podman', 'cp', str(local/'notify_receiver.py'), cid+':'+base+'/notify_receiver.py'])
            container('chown', '999:985', base+'/notify_receiver.py')
            user('/usr/bin/systemd-run', '--user', '--unit=schedule-fixture-http', '/usr/bin/python3', base+'/notify_receiver.py')
            user('/usr/bin/python3', '-c', "import socket,time;time.sleep(0.2);socket.create_connection(('127.0.0.1',18080),timeout=5).close()")
            # Accelerated real calendar dispatch; production calendar/cutoff tested separately.
            first = datetime.now(timezone.utc)+timedelta(seconds=45)
            second = first+timedelta(seconds=75)
            timer = candidate/'runtime/units/nautobot-protection.timer'
            timer.write_text(timer.read_text().replace('OnCalendar=*-*-* 03:20:00 America/Chicago',
                '\n'.join('OnCalendar='+t.strftime('%Y-%m-%d %H:%M:%S UTC') for t in (first, second))))
            for name in ('nautobot-protection-freshness.timer', 'nautobot-protection-notification.timer'):
                path = candidate/'runtime/units'/name
                path.write_text(path.read_text().replace('OnBootSec=5min', 'OnBootSec=2s'))
            (candidate/'runtime/operation.json').write_text(json.dumps(op))
            def hashes():
                rows={str(x.relative_to(candidate/'runtime')):hashlib.sha256(x.read_bytes()).hexdigest()
                      for x in (candidate/'runtime').rglob('*') if x.is_file()}
                (candidate/'runtime-hashes.json').write_text(json.dumps(rows))
            hashes()
            play = yaml.safe_load((candidate/'playbook.yaml').read_text())
            play[0]['tasks'][0]['ansible.builtin.assert']['that'][-2] = "ansible_host == '127.0.0.1'"
            (local/'playbook.yaml').write_text(yaml.safe_dump(play))
            port = run(['podman', 'port', cid, '22/tcp']).stdout.strip().rsplit(':', 1)[1]
            (local/'inventory').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_port='+port+
                ' ansible_user=operator ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file='+str(local/'key')+
                ' ansible_ssh_common_args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile='+str(local/'known_hosts')+'"\n')
            def install(label, current=op, selected=None):
                evidence = output/label; evidence.mkdir(mode=0o700)
                inputs = dict(capture_bundle_verified=True, capture_operation=current, capture_bundle=str(candidate), capture_evidence=str(evidence))
                (local/'inputs.json').write_text(json.dumps(inputs))
                result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                    'ansible-playbook', '-i', str(local/'inventory'), str(selected or local/'playbook.yaml'),
                    '-e', '@'+str(local/'inputs.json')], env={**os.environ, 'ANSIBLE_CONFIG':str(candidate/'ansible.cfg')},
                    cwd=ROOT, capture_output=True, text=True, timeout=240)
                (evidence/'ansible.log').write_text(result.stdout+result.stderr)
                (evidence/'status').write_text(str(result.returncode)+'\n')
                return result
            assert install('install').returncode == 0, 'install failed: inspect private log'
            idempotent = install('idempotent'); assert idempotent.returncode == 0 and 'changed=1' in idempotent.stdout and 'changed: [j2-svpi4mf]' not in idempotent.stdout
            if user('/usr/bin/systemctl', '--user', 'show', 'nautobot-protection-notification.service', '--property=Result', '--value').stdout.strip() != 'success':
                diagnostic = subprocess.run(['podman', 'exec', cid, 'sudo', '-u', 'nautobot', *env,
                    '/usr/bin/python3', '-c', 'import sys;sys.path.insert(0,'+repr(runtime+'/scripts')+');import recurring_node;sys.argv=["diagnostic","--binding",'+repr(runtime+'/binding.json')+',"notify"];recurring_node.main()'], capture_output=True, text=True)
                (output/'notification-diagnostic.log').write_text(diagnostic.stdout+diagnostic.stderr)
                raise AssertionError('native notification activation failed')
            deadline = time.monotonic()+180
            observed = []
            while time.monotonic()<deadline:
                completed = user('/usr/bin/python3', '-c', "from pathlib import Path;print(sum((p/'payload-disposal.json').exists() for p in Path('/tmp').glob('nautobot-recurring.*')))").stdout.strip()
                if completed == '2':
                    state_value = json.loads(user('cat', state+'/state.json').stdout)
                    if state_value['phase'] == 'complete':
                        observed = json.loads(user('/usr/local/bin/restic', '-r', base+'/repository', '-p', base+'/password', 'snapshots', '--json').stdout)
                        break
                time.sleep(5)
            assert len(observed)==2, 'two scheduled cycles did not complete'
            check_code = '''import json,pathlib
root=pathlib.Path('/tmp')
runs=[p for p in root.glob('nautobot-recurring.*') if (p/'application-backup-result.json').exists()]
assert len(runs)==2
for p in runs:
 r=json.loads((p/'application-backup-result.json').read_text());assert r['integrity_passed'] and r['upload_passed']
 assert json.loads((p/'payload-disposal.json').read_text())['phase']=='complete'
 assert list((p/'payload').iterdir())==[]
 assert not any((p/n).exists() for n in ('password','credentials.json','source-password','source-credentials.json'))
print(json.dumps([{'snapshot_id':json.loads((p/'application-backup-result.json').read_text())['snapshot_id'],'disposed':True} for p in runs]))
'''
            (output/'cycles.json').write_text(user('/usr/bin/python3', '-c', check_code).stdout)
            alerts = user('cat', base+'/notifications').stdout
            assert 'Missed' in alerts and 'Recovery' in alerts
            (output/'notification-receipts.jsonl').write_text(alerts)
            # Drift must be refused without modifying the drifted file or active timer identities.
            container('/bin/sh', '-c', 'printf drift >> '+runtime+'/scripts/schedule-driver.py')
            assert install('drift').returncode != 0
            run(['podman', 'cp', str(candidate/'runtime/scripts/schedule-driver.py'), cid+':'+runtime+'/scripts/schedule-driver.py'])
            container('chown','999:985',runtime+'/scripts/schedule-driver.py');container('chmod','0600',runtime+'/scripts/schedule-driver.py')
            altered = op['unit_directory']+'/nautobot-protection-freshness.timer'
            user('/usr/bin/ln', '-sf', runtime+'/units/nautobot-protection.timer', altered)
            assert install('unit-drift').returncode != 0
            assert user('/usr/bin/readlink', altered).stdout.strip() == runtime+'/units/nautobot-protection.timer'
            user('/usr/bin/ln', '-sf', runtime+'/units/nautobot-protection-freshness.timer', altered)
            dropin = op['unit_directory']+'/nautobot-protection-freshness.timer.d'
            user('/usr/bin/mkdir', dropin)
            user('/usr/bin/python3', '-c', 'from pathlib import Path;Path('+repr(dropin+'/override.conf')+').write_text("[Timer]\\nAccuracySec=5s\\n")')
            user('/usr/bin/systemctl', '--user', 'daemon-reload')
            assert install('dropin-drift').returncode != 0
            user('/usr/bin/rm', dropin+'/override.conf'); user('/usr/bin/rmdir', dropin)
            user('/usr/bin/systemctl', '--user', 'daemon-reload')
            user('/usr/bin/systemctl','--user','disable','--now',*op['enabled_timers'])
            for n in op['unit_names']: container('rm','-f',op['unit_directory']+'/'+n)
            user('/usr/bin/systemctl','--user','daemon-reload')
            # This removes only owned disposable test runtime/state, never production evidence.
            container('rm','-rf',runtime,state)
            failing = copy.deepcopy(play)
            block = next(t for t in failing[0]['tasks'] if 'block' in t)['block']
            block.insert(next(i for i,t in enumerate(block) if t['name']=='Enable only the three approved timers')+1,
                         {'name':'Inject disposable post-enable failure','ansible.builtin.fail':{'msg':'local rollback qualification'}})
            (local/'failure.yaml').write_text(yaml.safe_dump(failing))
            assert install('rollback', selected=local/'failure.yaml').returncode != 0
            for n in op['enabled_timers']:
                assert user('/usr/bin/systemctl','--user','show',n,'--property=ActiveState','--value').stdout.strip()!='active'
            assert container('test','-d',runtime).returncode==0
            summary={'installation':True,'idempotence':True,'calendar_cycles':2,'real_restic_snapshots':2,
                     'full_integrity_and_disposal':True,'missed_recovery_loopback_delivery':True,
                     'drift_refusal':True,'unit_and_dropin_drift_refusal':True,
                     'post_enable_rollback':True,'runtime_retained_on_failure':True,
                     'target_acceptance':False,'restic_sha256':hashlib.sha256(restic.read_bytes()).hexdigest()}
            (output/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
            print(json.dumps(summary))
        except Exception:
            diagnostics = "from pathlib import Path;paths=[Path('/var/lib/nautobot/protection/state/state.json'),*Path('/tmp').glob('nautobot-recurring.*/application-backup-result.json'),*Path('/tmp').glob('nautobot-recurring.*/ansible.log')];[(print(str(p)),print(p.read_text()[-18000:])) for p in paths if p.is_file()]"
            (output/'failure-state.log').write_text(container('/usr/bin/python3', '-c', diagnostics).stdout)
            (output/'failure-journal.log').write_text(container('journalctl','--no-pager','-n','150').stdout)
            raise
        finally:
            run(['podman','rm','-f',cid])
            (output/'cleanup.json').write_text(json.dumps({'container_id':cid,'removed':True})+'\n')


if __name__ == '__main__':
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--image',required=True);p.add_argument('--restic',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();qualify(a.image,a.restic,a.output)
