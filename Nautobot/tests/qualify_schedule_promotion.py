#!/usr/bin/env python3
"""Real SSH/sudo/Ansible five-file promotion and rollback in disposable systemd.

Application HTTP, mapped media and filesystem type are adapted. File copying,
permissions, package queries, service/timer guards, drift refusal and rollback use
the real implementation. No production connection, capture or provider access.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import yaml
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True, timeout=120, **kwargs)


def qualify(image, source, previous, output):
    output.mkdir(mode=0o700)
    with tempfile.TemporaryDirectory(prefix='logical-promotion.') as temporary:
        local = Path(temporary); candidate = local/'candidate'
        shutil.copytree(source, candidate)
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(local/'key')])
        cid = run(['podman', 'run', '-d', '--pull=never', '--systemd=always',
                   '--hostname', 'j2-svpi4mf', '--publish', '127.0.0.1::22', image]).stdout.strip()
        def container(*args): return run(['podman', 'exec', cid, *args])
        env = ['env', 'HOME=/var/lib/nautobot', 'XDG_RUNTIME_DIR=/run/user/999',
               'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus', 'PYTHONDONTWRITEBYTECODE=1']
        def user(*args): return container('sudo', '-u', 'nautobot', *env, *args)
        try:
            run(['podman','cp',str(local/'key.pub'),cid+':/home/operator/.ssh/authorized_keys'])
            container('chown','-R','operator:operator','/home/operator/.ssh')
            container('chmod','0700','/home/operator/.ssh')
            container('chmod','0600','/home/operator/.ssh/authorized_keys')
            for _ in range(30):
                if subprocess.run(['podman','exec',cid,'systemctl','is-active','ssh','user@999.service'],capture_output=True).returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('container_not_ready')
            op = yaml.safe_load((candidate/'operation.yaml').read_text())
            runtime = op['runtime_directory']; state = op['state_directory']; units = op['unit_directory']
            before = local/'before'; shutil.copytree(previous, before)
            # No production commands can dispatch from these qualification units.
            for name in op['unit_names']:
                text = ('[Timer]\nOnActiveSec=1h\nUnit='+name.removesuffix('.timer')+'.service\n[Install]\nWantedBy=timers.target\n'
                        if name.endswith('.timer') else '[Service]\nExecStart=/usr/bin/sleep infinity\n')
                (before/'units'/name).write_text(text)
            def hashes(directory):
                return {str(p.relative_to(directory)):hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in directory.rglob('*') if p.is_file()}
            old_hashes = hashes(before)
            op['promotion']['previous_runtime_sha256'] = old_hashes
            op['promotion']['python_cache_sha256'] = {}
            op['promotion']['installation_date'] = datetime.now(ZoneInfo('America/Chicago')).date().isoformat()
            desired = {**old_hashes, **{n:hashlib.sha256((candidate/'runtime'/n).read_bytes()).hexdigest() for n in op['promotion']['files']}}
            (candidate/'runtime-hashes.json').write_text(json.dumps(desired))
            container('install','-d','-m','0700','-o','999','-g','985',runtime,state,units,
                      '/var/lib/nautobot/protection/staging','/var/lib/nautobot/promotion-fixture')
            run(['podman','cp',str(before)+'/.',cid+':'+runtime])
            container('chown','-R','999:985',runtime)
            container('/usr/bin/python3','-c',"from pathlib import Path;import os; r=Path("+repr(runtime)+");[(p.chmod(0o700 if p.is_dir() else 0o600)) for p in [r,*r.rglob('*')]]")
            for role in ('postgresql','redis','web','worker','scheduler'):
                user('/usr/bin/python3','-c','from pathlib import Path;Path('+repr(units+'/nautobot-'+role+'.service')+').write_text("[Service]\\nExecStart=/usr/bin/sleep infinity\\n")')
            for name in op['unit_names']: user('/usr/bin/ln','-s',runtime+'/units/'+name,units+'/'+name)
            user('/usr/bin/systemctl','--user','daemon-reload')
            user('/usr/bin/systemctl','--user','start',*['nautobot-'+r+'.service' for r in ('postgresql','redis','web','worker','scheduler')])
            user('/usr/bin/systemctl','--user','enable','--now',*op['enabled_timers'])
            fixture = '/var/lib/nautobot/promotion-fixture'
            metadata = {'expires_at':'2099-01-01T00:00:00+00:00'}
            user('/usr/bin/python3','-c','from pathlib import Path;import os;os.umask(0o077);Path('+repr(fixture+'/token')+').write_text("disposable-only");Path('+repr(fixture+'/metadata.json')+').write_text('+repr(json.dumps(metadata))+')')
            op['credential_identity'] = metadata
            op['binding']['credentials'].update(token_file=fixture+'/token',metadata_file=fixture+'/metadata.json')
            op['binding']['minimum_free_bytes'] = 1048576
            op['boot_id'] = container('cat','/proc/sys/kernel/random/boot_id').stdout.strip()
            version, architecture = container('dpkg-query','-W','-f=${Version} ${Architecture}','libc6').stdout.split()
            op['packages'] = [{'name':'libc6','version':version,'architecture':architecture}]
            invocations = {n:user('/usr/bin/systemctl','--user','show',n,'--property=InvocationID','--value').stdout.strip()
                           for n in ['nautobot-'+r+'.service' for r in ('postgresql','redis','web','worker','scheduler')]}
            op['baseline'] = {'collected_at':datetime.now(timezone.utc).isoformat(),'artifact_sha256':{},
                              'binding_artifact_sha256':{},'media_directories':[],'service_invocations':invocations}
            user('/usr/bin/python3','-c','from pathlib import Path;import os;os.umask(0o077);Path('+repr(state+'/state.json')+').write_text('+repr(json.dumps(op['promotion']['state']))+')')
            # Keep the actual guard and native service queries; adapt only unavailable probes.
            guard = candidate/'schedule_install.py'
            adapter = '''
native_command = command
def command(argv):
    if argv[:3] == ['/usr/bin/podman','unshare','/usr/bin/find']: return 'd|'
    if argv[:3] == ['/usr/bin/podman','unshare','/usr/bin/python3']: return ''
    if argv[:3] == ['/usr/bin/podman','exec','nautobot-web']: return '200'
    if argv[:3] == ['/usr/bin/findmnt','-no','FSTYPE']: return 'ext4'
    return native_command(argv)
'''
            guard.write_text(guard.read_text().replace("if __name__ == '__main__':",adapter+"\nif __name__ == '__main__':"))
            play = yaml.safe_load((candidate/'playbook.yaml').read_text())
            play[0]['tasks'][0]['ansible.builtin.assert']['that'][-2] = "ansible_host == '127.0.0.1'"
            port = run(['podman','port',cid,'22/tcp']).stdout.strip().rsplit(':',1)[1]
            inventory = local/'inventory'
            inventory.write_text('[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_port='+port+
                ' ansible_user=operator ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file='+str(local/'key')+
                ' ansible_ssh_common_args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile='+str(local/'known_hosts')+'"\n')
            def execute(label, selected=None):
                evidence = output/label; evidence.mkdir(mode=0o700)
                (local/'playbook.yaml').write_text(yaml.safe_dump(selected or play))
                (local/'inputs.json').write_text(json.dumps(dict(capture_bundle_verified=True,capture_operation=op,
                    capture_bundle=str(candidate),capture_evidence=str(evidence))))
                with (evidence/'ansible.log').open('w') as log:
                    r = subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                        'ansible-playbook','-i',str(inventory),str(local/'playbook.yaml'),'-e','@'+str(local/'inputs.json')],
                        env={**os.environ,'ANSIBLE_CONFIG':str(candidate/'ansible.cfg')},stdout=log,stderr=subprocess.STDOUT,timeout=150)
                (evidence/'status.json').write_text(json.dumps({'exit_status':r.returncode}))
                return r.returncode
            def observed():
                code = "from pathlib import Path;import hashlib,json;r=Path("+repr(runtime)+");print(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in r.rglob('*') if p.is_file()}))"
                return json.loads(user('/usr/bin/python3','-B','-c',code).stdout)
            def reset():
                for name in op['promotion']['new_files']: container('rm','-f',runtime+'/'+name)
                for name in ('binding.json','scripts/recurring_node.py','scripts/recurring_disposal.py'):
                    run(['podman','cp',str(before/name),cid+':'+runtime+'/'+name])
                    container('chown','999:985',runtime+'/'+name);container('chmod','0600',runtime+'/'+name)
                assert observed() == old_hashes
            assert execute('promote') == 0 and observed() == desired
            assert execute('idempotent') == 0 and observed() == desired
            receipt = json.loads((output/'idempotent/promotion.json').read_text())
            assert receipt['promotion_needed'] is False
            reset()
            user('/usr/bin/systemctl','--user','start','nautobot-protection.service')
            assert execute('active-refusal') != 0 and observed() == old_hashes
            user('/usr/bin/systemctl','--user','stop','nautobot-protection.service')
            container('chmod','0644',runtime+'/binding.json')
            assert execute('permission-refusal') != 0 and observed() == old_hashes
            container('chmod','0600',runtime+'/binding.json')
            for count in (2,5):
                failed = copy.deepcopy(play); block = next(t['block'] for t in failed[0]['tasks'] if 'block' in t)
                template = block.pop(0); template.pop('loop')
                copies = []
                for n in op['promotion']['files'][:count]:
                    task = copy.deepcopy(template);task['vars']={'item':n};copies.append(task)
                block[:0] = [*copies,{'name':'Inject failure after real copies','ansible.builtin.fail':{'msg':'disposable copy-boundary failure'}}]
                label='rollback-'+str(count)
                assert execute(label,failed) != 0 and observed() == old_hashes
                assert (output/label/'rollback.json').exists()
            # A foreign replacement must survive rollback refusal for operator review.
            failed = copy.deepcopy(play);block=next(t['block'] for t in failed[0]['tasks'] if 'block' in t)
            block.insert(1,{'name':'Inject foreign bytes in disposable runtime','ansible.builtin.copy':{'content':'foreign','dest':runtime+'/binding.json','owner':'999','group':'985','mode':'0600'}})
            assert execute('foreign-rollback-refusal',failed) != 0
            assert user('/usr/bin/cat',runtime+'/binding.json').stdout == 'foreign'
            assert not (output/'foreign-rollback-refusal/rollback.json').exists()
            reset()
            result={'native_ssh_sudo_ansible':True,'promotion':True,'idempotence':True,'active_refusal':True,
                    'permission_refusal':True,'partial_and_complete_copy_rollback':True,'foreign_rollback_refusal':True,
                    'target_acceptance':False,'adapted_observations':['application HTTP','mapped media','filesystem type'],
                    'candidate_bundle_sha256':hashlib.sha256((source/'bundle.json').read_bytes()).hexdigest()}
            (output/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
        finally:
            run(['podman','rm','-f',cid])
            (output/'cleanup.json').write_text(json.dumps({'container_id':cid,'removed':True})+'\n')


if __name__ == '__main__':
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('--image',required=True);p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--previous-runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();qualify(a.image,a.candidate,a.previous_runtime,a.output)
