#!/usr/bin/env python3
"""One Pi quota comparison. systemd owns workload lifetime and ExecStopPost recovery."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys

CGROUP = Path('/sys/fs/cgroup/system.slice/webmin.service')
OVERRIDE = Path('/run/systemd/system.control/webmin.service.d/50-CPUQuota.conf')
BOOT = Path('/proc/sys/kernel/random/boot_id')


def command(*args, timeout=5):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError({'command': list(args[:2]), 'status': result.returncode})
    return result.stdout.strip()


def require(ok, check, expected, observed):
    if not ok:
        raise ValueError({'check': check, 'expected': expected, 'observed': observed})


def state_now():
    controls = {k: (CGROUP/k).read_text().strip() for k in
                ('cpu.max', 'memory.high', 'memory.max', 'memory.swap.max')}
    paths = command('/usr/bin/systemctl', 'show', 'webmin.service',
                    '-p', 'FragmentPath', '-p', 'DropInPaths', '--value').split()
    # Retain file identities, never contents; the one owned runtime override is separate.
    files = {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths if p != str(OVERRIDE)}
    return dict(boot=BOOT.read_text().strip(), inode=CGROUP.stat().st_ino, unit_files=files,
                main=command('/usr/bin/systemctl', 'show', 'webmin.service', '-p', 'MainPID', '--value'),
                controls=controls)


def save(root, name, value):
    temp = root/(name+'.tmp')
    temp.write_text(json.dumps(value, sort_keys=True)+'\n')
    temp.replace(root/name)


def quota(percent):
    command('/usr/bin/systemctl', 'set-property', '--runtime', 'webmin.service', f'CPUQuota={percent}%')


def restore(root):
    saved = json.loads((root/'baseline.json').read_text())
    result = {'restored': False}
    try:
        require(BOOT.read_text().strip() == saved['boot'], 'boot', saved['boot'], BOOT.read_text().strip())
        # Lower the effective ceiling first, even if later file/identity checks fail.
        quota(100)
        require(not OVERRIDE.is_symlink(), 'runtime_override', 'not symlink', str(OVERRIDE))
        prior = saved['override']
        if prior is None:
            OVERRIDE.unlink()
            if not saved['override_directory_existed']:
                OVERRIDE.parent.rmdir()  # Refuse to remove unexpected additional files.
        else:
            OVERRIDE.write_bytes(base64.b64decode(prior['bytes']))
            os.chown(OVERRIDE, prior['uid'], prior['gid'])
            os.chmod(OVERRIDE, prior['mode'])
        command('/usr/bin/systemctl', 'daemon-reload')
        after = state_now()
        require(after == {k: saved[k] for k in after}, 'restored_state',
                {k: saved[k] for k in after}, after)
        require((not OVERRIDE.exists()) if prior is None else
                OVERRIDE.read_bytes() == base64.b64decode(prior['bytes']),
                'runtime_override_restored', True, False)
        result.update(restored=True, observed=after)
    except Exception as error:
        result['error'] = str(error)[:2000]
        raise
    finally:
        save(root, 'restoration.json', result)


def worker(root):
    before = json.loads((root/'baseline.json').read_text())
    observed = state_now()
    require(observed == {k: before[k] for k in observed}, 'admitted_state',
            {k: before[k] for k in observed}, observed)
    quota(200)
    spec = importlib.util.spec_from_file_location('diagnostic', root/'diagnose-http.py')
    diagnostic = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnostic)
    return diagnostic.compare_loopback(expected_cpus=2)


def unit_command(root):
    script = root/'compare-loopback-quota.py'
    cleanup = f'/usr/bin/timeout --kill-after=2s 18s /usr/bin/python3 -I -B {script} restore'
    return ['/usr/bin/systemd-run', '--quiet', '--wait', '--pipe', '--collect', '--unit='+root.name,
            '--property=Type=exec', '--property=RuntimeMaxSec=60s', '--property=TimeoutStopSec=20s',
            '--property=KillMode=control-group', '--property=UMask=0077',
            '--property=ExecStopPost='+cleanup,
            '/usr/bin/python3', '-I', '-B', str(script), 'worker']


def launch(root):
    require(socket.gethostname() == 'j2-svpi3bmf', 'hostname', 'j2-svpi3bmf', socket.gethostname())
    before = state_now()
    expected = {'cpu.max': '100000 100000', 'memory.high': '134217728',
                'memory.max': '201326592', 'memory.swap.max': '0'}
    print(json.dumps({'admission': before}), flush=True)
    require(before['controls'] == expected and int(before['main']) > 0,
            'baseline', expected, before)
    ancestors = {}
    for parent in CGROUP.parents:
        if str(parent) == '/sys/fs': break
        f = parent/'cpu.max'
        if f.exists():
            value = f.read_text().strip(); ancestors[str(f)] = value
            q, period = value.split()
            require(q == 'max' or int(q) >= 2*int(period), 'ancestor_quota', '>=2 CPUs or max', ancestors)
    cpus = (CGROUP/'cpuset.cpus.effective').read_text().strip()
    count = sum((int(p.split('-')[1])-int(p.split('-')[0])+1) if '-' in p else 1 for p in cpus.split(','))
    require(count >= 2, 'effective_cpus', '>=2', cpus)
    before['override'] = None
    require(all(not p.is_symlink() for p in OVERRIDE.parents), 'override_parents', 'no symlinks', str(OVERRIDE))
    require(not OVERRIDE.is_symlink(), 'runtime_override', 'not symlink', str(OVERRIDE))
    if OVERRIDE.exists():
        st = OVERRIDE.stat()
        require(stat.S_ISREG(st.st_mode) and st.st_uid == 0 and st.st_size <= 4096,
                'runtime_override_metadata', 'root regular <=4096 bytes', str(OVERRIDE))
        before['override'] = dict(bytes=base64.b64encode(OVERRIDE.read_bytes()).decode(),
                                  mode=stat.S_IMODE(st.st_mode), uid=st.st_uid, gid=st.st_gid)
    before['ancestors'] = ancestors; before['cpus'] = cpus
    before['override_directory_existed'] = OVERRIDE.parent.exists()
    save(root, 'baseline.json', before)
    print(json.dumps({'ancestors': ancestors, 'effective_cpus': cpus,
                      'prior_runtime_override_present': before['override'] is not None}), flush=True)
    with (root/'measurement.jsonl').open('w') as output, (root/'unit.stderr').open('w') as errors:
        run = subprocess.run(unit_command(root), stdout=output, stderr=errors, timeout=95)
    print((root/'measurement.jsonl').read_text(), end='', flush=True)
    restored = json.loads((root/'restoration.json').read_text()) if (root/'restoration.json').exists() else {'restored': False}
    print(json.dumps({'unit_exit': run.returncode, 'restoration': restored,
                      'remote_evidence': str(root)}), flush=True)
    return 0 if run.returncode == 0 and restored.get('restored') else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('launch', 'worker', 'restore'))
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(__file__).absolute().parent
    require(os.geteuid() == 0 and root.parent == Path('/run') and root.name.startswith('webmin-quota-')
            and not root.is_symlink() and stat.S_IMODE(root.stat().st_mode) == 0o700
            and root.stat().st_uid == 0, 'private_root', 'root-private /run/webmin-quota-*', str(root))
    try:
        status = {'launch': launch, 'worker': worker, 'restore': restore}[args.phase](root)
    except Exception as error:
        print(json.dumps({'phase': args.phase, 'error': str(error)[:2000]}), flush=True)
        raise SystemExit(1)
    raise SystemExit(status or 0)
