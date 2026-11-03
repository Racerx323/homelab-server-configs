#!/usr/bin/env python3
"""Real SSH/sudo transition regression in an existing disposable Podman image."""
import argparse
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import yaml

ROOT = Path(__file__).resolve().parents[2]


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=180, **kwargs)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--image', required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    args.output.mkdir(mode=0o700)
    play = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/qualify-capture-resume.yaml').read_text())[0]
    block = next(t['block'] for t in play['tasks'] if 'block' in t)
    task = next(t for t in block if t['name'] == 'Start the one-shot trial without enabling any schedule')
    assert 'async' not in task and 'poll' not in task
    with tempfile.TemporaryDirectory(prefix='capture-transition.') as tmp:
        root = Path(tmp)
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root/'key')])
        cid = run(['podman', 'run', '-d', '--pull=never', '--publish', '127.0.0.1::22',
                   '--entrypoint', '/usr/sbin/sshd', args.image, '-D', '-e']).stdout.strip()
        try:
            run(['podman', 'cp', str(root/'key.pub'), cid+':/home/operator/.ssh/authorized_keys'])
            run(['podman', 'exec', cid, '/bin/sh', '-c',
                 'chown -R operator:operator /home/operator/.ssh; chmod 0600 /home/operator/.ssh/authorized_keys; '
                 'mkdir -p /home/nautobot/async; chown -R nautobot:nautobot /home/nautobot/async; '
                 'chmod 0700 /home/nautobot/async; ! command -v setfacl'])
            port = run(['podman', 'port', cid, '22/tcp']).stdout.strip().rsplit(':', 1)[1]
            (root/'inventory').write_text('trial ansible_host=127.0.0.1 ansible_port='+port+
                ' ansible_user=operator ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file='+str(root/'key')+
                ' ansible_ssh_common_args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile='+str(root/'known_hosts')+'"\n')
            (root/'ansible.cfg').write_text('[defaults]\nretry_files_enabled=False\n[ssh_connection]\npipelining=True\n')
            results = []
            for scenario in ('old_async', 'synchronous_success', 'synchronous_failure'):
                selected = copy.deepcopy(task)
                # Exercise the real task's module/transport/become settings with a harmless process.
                selected['ansible.builtin.command']['argv'] = ['/usr/bin/python3', '-c',
                    'import os,time,sys; assert os.getuid()==999; time.sleep(2); print("uid=999 complete"); sys.exit('+('7' if scenario.endswith('failure') else '0')+')']
                if scenario == 'old_async':
                    selected.update({'async': 30, 'poll': 1, 'vars': {'ansible_async_dir': '/home/nautobot/async'}})
                selected['register'] = 'transition'
                selected['ignore_errors'] = True
                tasks = [selected, {'ansible.builtin.copy': {'content': '{{ transition | to_json }}', 'dest': str(root/'result.json')},
                                    'delegate_to': 'localhost', 'become': False}]
                probe = [{'hosts': 'trial', 'gather_facts': False, 'become': True, 'become_user': 'nautobot', 'tasks': tasks}]
                (root/'probe.yaml').write_text(yaml.safe_dump(probe))
                start = time.monotonic()
                result = run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                              'ansible-playbook', '-i', str(root/'inventory'), str(root/'probe.yaml')],
                             env={**os.environ, 'ANSIBLE_CONFIG': str(root/'ansible.cfg')}, cwd=ROOT)
                (args.output/(scenario+'.log')).write_text(result.stdout+result.stderr)
                data = json.loads((root/'result.json').read_text())
                if scenario == 'old_async':
                    assert data['failed'] and 'Failed to set permissions' in data['msg'], data
                else:
                    assert data['rc'] == (7 if scenario.endswith('failure') else 0), data
                    assert data['stdout'] == 'uid=999 complete' and time.monotonic()-start >= 2, data
                results.append({'scenario': scenario, 'passed': True})
            (args.output/'results.json').write_text(json.dumps(results, indent=2)+'\n')
            print(json.dumps(results))
        finally:
            run(['podman', 'rm', '-f', cid])
            (args.output/'cleanup.json').write_text(json.dumps({'container_id': cid, 'removed': True})+'\n')


if __name__ == '__main__':
    os.umask(0o077)
    main()
