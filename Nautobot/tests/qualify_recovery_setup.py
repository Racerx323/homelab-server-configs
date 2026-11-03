#!/usr/bin/env python3
"""Actual preflight/setup over SSH/sudo in a disposable Debian systemd image.

Application health and mapped-media probes are local adapters; journal access,
identity, packages, files, rendering and unit validation use the real commands.
Never links/starts qualification units or resolves provider credentials.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True, timeout=180, **kwargs)


def qualify(image, output):
    output.mkdir(mode=0o700)
    with tempfile.TemporaryDirectory(prefix='recovery-setup.') as tmp:
        root = Path(tmp)
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root/'key')])
        cid = run(['podman', 'run', '-d', '--pull=never', '--systemd=always',
                   '--hostname', 'j2-svpi4mf', '--publish', '127.0.0.1::22', image]).stdout.strip()
        def container(*argv):
            return run(['podman', 'exec', cid, *argv])
        try:
            run(['podman', 'cp', str(root/'key.pub'), cid+':/home/operator/.ssh/authorized_keys'])
            container('/bin/sh', '-c', 'chown -R operator:operator /home/operator/.ssh; chmod 0600 /home/operator/.ssh/authorized_keys')
            for _ in range(30):
                ready = subprocess.run(['podman', 'exec', cid, 'systemctl', 'is-active',
                                        'ssh.service', 'systemd-journald.service', 'user@999.service'], capture_output=True)
                if ready.returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError('disposable_services_not_ready')
            env = ['env', 'HOME=/var/lib/nautobot', 'XDG_RUNTIME_DIR=/run/user/999',
                   'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
            container('sudo', '-u', 'nautobot', *env, 'systemctl', '--user', 'show',
                      'nautobot-protection-killed.service', '--property=LoadState', '--value')
            denied = subprocess.run(['podman', 'exec', cid, 'sudo', '-u', 'nautobot', *env,
                                     'journalctl', '--user', '--show-cursor', '-n', '0', '--no-pager'],
                                    capture_output=True, text=True, timeout=30)
            assert denied.returncode != 0 and 'permission' in denied.stderr.lower(), denied
            (output/'journal-permission.json').write_text(json.dumps({
                'service_uid': 999, 'unprivileged_rc': denied.returncode, 'stderr': denied.stderr,
                'root_cursor': container('journalctl', '--show-cursor', '-n', '0', '--no-pager').stdout}, indent=2)+'\n')
            spec = importlib.util.spec_from_file_location('recovery_bundle', SCRIPTS/'recovery-timer-bundle.py')
            bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
            candidate = root/'candidate'; bundle.transport.freeze(candidate)
            # Use the complete current setup prefix, stopping before runtime linking.
            play = yaml.safe_load((candidate/'playbook.yaml').read_text())[0]
            stop = next(i for i, task in enumerate(play['tasks']) if 'loop' in task)
            play['tasks'] = play['tasks'][:stop]
            play['tasks'][0]['ansible.builtin.assert']['that'][-2] = "ansible_host == '127.0.0.1'"
            case_tasks = yaml.safe_load((candidate/'recovery-case.yaml').read_text())
            block = next(t for t in case_tasks if 'block' in t)
            stop = next(i for i, task in enumerate(block['block']) if task['name'] == 'Link only runtime recovery units')
            block['block'] = block['block'][:stop]
            (root/'setup-case.yaml').write_text(yaml.safe_dump(case_tasks))
            play['tasks'].append({'name': 'Exercise both complete setup paths only',
                'ansible.builtin.include_tasks': str(root/'setup-case.yaml'),
                'loop': ['killed', 'deadline'], 'loop_control': {'loop_var': 'recovery_case'}})
            (root/'setup.yaml').write_text(yaml.safe_dump([play]))
            node = candidate/'runtime/scripts/recurring_node.py'
            node.write_text(node.read_text()+'''\n# Disposable application probes only; the setup path is unchanged.
def media_directories(): return ['local-media']
def health(timeout=30): return {'local_application_probe': True}
''')
            op = json.loads((candidate/'runtime/operation.json').read_text())
            op['operation']['execution_enabled'] = True
            op['boot_id'] = container('cat', '/proc/sys/kernel/random/boot_id').stdout.strip()
            op['controller_timeout_seconds'] = 1
            metadata = {'local': 'no credential values'}
            container('/bin/sh', '-c', "printf '%s' '{\"local\":\"no credential values\"}' > /var/lib/nautobot/metadata.json; chown 999:985 /var/lib/nautobot/metadata.json; chmod 0600 /var/lib/nautobot/metadata.json")
            artifact = '/etc/debian_version'
            digest = container('sha256sum', artifact).stdout.split()[0]
            version, architecture = container('dpkg-query', '-W', '-f=${Version} ${Architecture}', 'libc6').stdout.split()
            for trial in op['trials'].values():
                trial['baseline'].update(artifact_sha256={artifact: digest}, media_directories=['local-media'])
                trial['packages'] = [{'name': 'libc6', 'version': version, 'architecture': architecture}]
                trial['credential_identity'] = metadata
                trial['binding']['credentials']['metadata_file'] = '/var/lib/nautobot/metadata.json'
                trial['supervisor'].update(start_hour=0, end_hour=23, start_minute=0, end_minute=59)
                trial['supervisor'].pop('window_date', None)
            port = run(['podman', 'port', cid, '22/tcp']).stdout.strip().rsplit(':', 1)[1]
            (root/'inventory').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_port='+port+
                ' ansible_user=operator ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file='+str(root/'key')+
                ' ansible_ssh_common_args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile='+str(root/'known_hosts')+'"\n')
            (root/'ansible.cfg').write_text('[defaults]\nretry_files_enabled=False\n[ssh_connection]\npipelining=True\n')
            results = []
            for scenario in ('success', 'replay', 'artifact-drift', 'package-drift', 'metadata-drift'):
                current = copy.deepcopy(op)
                if scenario not in ('success', 'replay'):
                    container('rm', '-rf', '/var/lib/nautobot/protection/recovery-qualification')
                    trial = current['trials']['killed']
                    if scenario == 'artifact-drift': trial['baseline']['artifact_sha256'][artifact] = '0'*64
                    if scenario == 'package-drift': trial['packages'][0]['version'] = 'not-installed'
                    if scenario == 'metadata-drift': trial['credential_identity']['local'] = 'drift'
                (candidate/'runtime/operation.json').write_text(json.dumps(current))
                inputs = {'capture_operation': current, 'capture_bundle': str(candidate), 'capture_bundle_verified': True}
                (root/'inputs.json').write_text(json.dumps(inputs))
                result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                    'ansible-playbook', '-i', str(root/'inventory'), str(root/'setup.yaml'), '-e', '@'+str(root/'inputs.json')],
                    env={**os.environ, 'ANSIBLE_CONFIG': str(root/'ansible.cfg')}, cwd=ROOT,
                    capture_output=True, text=True, timeout=240)
                (output/(scenario+'.log')).write_text(result.stdout+result.stderr)
                assert (result.returncode == 0) == (scenario == 'success'), (scenario, result.stdout[-3000:])
                base = '/var/lib/nautobot/protection/recovery-qualification'
                if scenario in ('success', 'replay'):
                    snapshot = container('python3', '-c', '''import hashlib,json,pathlib,stat
r=pathlib.Path('/var/lib/nautobot/protection/recovery-qualification')
out={}
for case in ('killed','deadline'):
 d=r/case
 assert (d/'state/before.json').is_file() and (d/'binding.json').is_file() and (d/'supervisor.json').is_file()
 assert len(list((d/'units').iterdir()))==4
 c=d/'journal-cursor.json'; v=json.loads(c.read_text())
 assert v['cursor'].startswith('-- cursor: ') and '\\n' not in v['cursor']
 assert c.stat().st_uid==999 and stat.S_IMODE(c.stat().st_mode)==0o600
for p in r.rglob('*'):
 if p.is_file(): out[str(p.relative_to(r))]=hashlib.sha256(p.read_bytes()).hexdigest()
print(json.dumps(out,sort_keys=True))''').stdout
                    if scenario == 'success': before = snapshot
                    else: assert snapshot == before, 'replay_changed_retained_state'
                    assert json.loads(snapshot)['scripts/recovery_qualification.py'] == hashlib.sha256((SCRIPTS/'recovery_qualification.py').read_bytes()).hexdigest()
                else:
                    assert 'drift' in result.stdout
                    container('test', '!', '-e', base+'/killed/units')
                    container('test', '!', '-e', base+'/deadline')
                for case in ('killed', 'deadline'):
                    status = container('sudo', '-u', 'nautobot', *env, 'systemctl', '--user', 'show',
                                       'nautobot-protection-'+case+'.service', '--property=LoadState', '--value')
                    assert status.stdout.strip() == 'not-found'
                results.append({'scenario': scenario, 'passed': True, 'ansible_status': result.returncode})
            (output/'results.json').write_text(json.dumps({'accepted': False, 'cases': results,
                'limits': ['application health and media probes adapted', 'no production contact',
                           'no fault or timer execution in setup test']}, indent=2)+'\n')
            print(json.dumps(results))
        finally:
            run(['podman', 'rm', '-f', cid])
            (output/'cleanup.json').write_text(json.dumps({'container_id': cid, 'removed': True})+'\n')


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    qualify(args.image, args.output)
