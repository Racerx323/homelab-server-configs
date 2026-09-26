#!/usr/bin/env python3
"""Bounded restore primitives; Ansible owns ordering, user systemd owns the guard.

Inputs must be staged by a reviewed launcher. This module never resolves secrets,
changes production services or authorizes an operation. Retrieval uses the Restic owner helper.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import subprocess
import tempfile
import time

LABEL = 'nautobot.restore.owner'
ROLES = ('postgresql', 'redis', 'application')
MEMORY = dict(zip(ROLES, (768, 128, 1024)))
CPU = dict(zip(ROLES, (0.75, 0.25, 1.0)))
SECRETS = ('application.env', 'postgresql.env', 'redis.conf', 'django-secret',
           'retrieval/password', 'retrieval/credentials.json')


class Blocked(Exception):
    pass


def require(ok, code):
    if not ok: raise Blocked(code)


def protected(path, directory=False):
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'symlink')
    info = path.stat()
    require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600), 'ownership_mode')
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode), 'file_type')


def save(path, value):
    temporary = path.with_suffix('.new')
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream: json.dump(value, stream, sort_keys=True)
    os.replace(temporary, path)


def bounded(argv, *, root=None, timeout=30, data=None, maximum=4194304):
    # stderr can contain credentials or application data; retain only status/class.
    with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        if data is not None: source.write(data); source.seek(0)
        process = subprocess.Popen(argv, stdin=source, stdout=out, stderr=err, start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, 'command_timeout')
                require(out.tell() <= maximum and err.tell() <= maximum, 'command_output_bound')
                if root is not None: require(not (root/'stopped.json').exists(), 'guard_stopped')
                time.sleep(.1)
            require(process.returncode == 0, 'command_exit_'+str(process.returncode))
            require(out.tell() <= maximum and err.tell() <= maximum, 'command_output_bound')
            out.seek(0)
            return out.read()
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)


class Restore:
    def __init__(self, root):
        self.root = root
        protected(root, True)
        protected(root/'runtime.json')
        self.spec = json.loads((root/'runtime.json').read_text())
        self.token = self.spec['token']
        require(re.fullmatch('nautobot-restore-[a-f0-9]{24}', self.token), 'token')
        require(root.name == self.token, 'root_token')
        require(self.spec['uid'] == os.getuid() != 0, 'rootless_user')
        require(set(self.spec['images']) == set(ROLES), 'images')
        for image in self.spec['images'].values(): require(re.fullmatch('[a-f0-9]{64}', image), 'image_pin')
        require(self.spec['context'] in ('target', 'disposable'), 'context')
        if self.spec['context'] == 'target':
            require(os.getuid() == 999 and root.parent == Path('/var/lib/nautobot/restore-tests'), 'target_root')
        else:
            require(root.parent.is_relative_to('/home/aaron/code/.local-evidence'), 'disposable_root')
        self.volume = self.token+'-data'
        self.unit = self.token+'-guard.service'

    def call(self, argv, **kwargs): return bounded(argv, root=self.root, **kwargs)
    def name(self, role): return self.token+'-'+role
    def inspect(self, role): return json.loads(bounded(['/usr/bin/podman', 'inspect', self.name(role)]))[0]

    def lock(self):
        fd = os.open(self.root/'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        return os.fdopen(fd, 'w')

    def active(self):
        require(not (self.root/'stopped.json').exists(), 'terminal_restore')
        receipt = json.loads((self.root/'guard.json').read_text())
        require(0 <= time.monotonic()-receipt['monotonic'] < 15, 'guard_stale')
        self.call(['/usr/bin/systemctl', '--user', 'is-active', self.unit])

    def production(self):
        result = {}
        for name in self.spec['production_containers']:
            require(re.fullmatch('nautobot-(postgresql|redis|web|worker|scheduler)', name), 'production_name')
            obj = json.loads(self.call(['/usr/bin/podman', 'inspect', name]))[0]
            require(obj['State']['Running'], 'production_not_running')
            result[name] = {k: obj[k] for k in ('Id', 'Image')}
            result[name]['StartedAt'] = obj['State']['StartedAt']
        if self.spec['context'] == 'target':
            require(len(result) == 5, 'production_inventory')
            code = "import urllib.request; assert urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8080/health/', headers={'Host':'nautobot.local.theama.co'}), timeout=5).status == 200"
            self.call(['/usr/bin/podman', 'exec', 'nautobot-web', 'python3', '-c', code])
        return result

    def host_health(self):
        if self.spec['context'] != 'target': return
        root = Path('/run')/(self.token+'-monitor')
        require(not root.is_symlink() and root.stat().st_uid == 0, 'host_monitor_owner')
        path = root/'sample.json'
        require(not path.is_symlink() and path.stat().st_uid == 0, 'host_sample_owner')
        require(not (root/'failure.json').exists(), 'host_monitor_failed')
        value = json.loads(path.read_text())
        require(value['passed'] is True and 0 <= time.monotonic()-value['monotonic'] < 15, 'host_monitor_stale')

    def sample(self):
        self.host_health()
        memory = {p[0].rstrip(':'): int(p[1]) for line in Path('/proc/meminfo').read_text().splitlines() if len(p := line.split()) >= 2}
        require(memory['MemAvailable'] >= 1536*1024, 'memory_floor')
        disk = os.statvfs(self.root)
        require(disk.f_bavail*disk.f_frsize >= 8*1024**3, 'disk_reserve')
        paths = [self.root]
        volume = subprocess.run(['/usr/bin/podman', 'volume', 'exists', self.volume], capture_output=True, timeout=10)
        require(volume.returncode in (0, 1), 'volume_query')
        if volume.returncode == 0:
            info = json.loads(bounded(['/usr/bin/podman', 'volume', 'inspect', self.volume]))[0]
            require(info.get('Labels', {}).get(LABEL) == self.token, 'volume_owner')
            paths.append(Path(info['Mountpoint']))
        # Allocated bytes, sampled threshold; this is not a filesystem quota.
        used = int(bounded(['/usr/bin/du', '-s', '-B1', str(self.root)], timeout=10).decode().splitlines()[0].split()[0])
        if len(paths) > 1:
            # Podman unshare permits readback of the rootless PostgreSQL UID tree.
            used += int(bounded(['/usr/bin/podman', 'unshare', '/usr/bin/du', '-s', '-B1', str(paths[1])], timeout=10).split()[0])
        require(used < 4*1024**3, 'working_set_stop')
        return {'monotonic': time.monotonic(), 'available_kib': memory['MemAvailable'], 'allocated_bytes': used}

    def arm(self):
        require(not (self.root/'guard.json').exists() and not (self.root/'stopped.json').exists(), 'already_started')
        self.sample()
        save(self.root/'production-before.json', self.production())
        script = str(Path(__file__).resolve())
        # Constrained root names contain no systemd command parsing metacharacters.
        require(re.fullmatch('/[A-Za-z0-9_./-]+', str(self.root)), 'guard_path')
        require(re.fullmatch('/[A-Za-z0-9_./-]+', script), 'guard_script')
        bounded(['/usr/bin/systemd-run', '--user', '--unit='+self.unit, '--property=Type=exec',
                 '--property=Restart=no', '--property=RuntimeMaxSec=3600', '--property=TimeoutStopSec=240',
                 '--property=ExecStopPost=/usr/bin/python3 -B '+script+' cleanup --root '+str(self.root),
                 '/usr/bin/python3', '-B', script, 'guard', '--root', str(self.root)])
        for _ in range(100):
            if (self.root/'guard.json').exists(): self.active(); return
            time.sleep(.1)
        raise Blocked('guard_unready')

    def guard(self):
        started = previous = time.monotonic()
        count = 0
        try:
            while time.monotonic()-started < 3540:
                require(time.monotonic()-previous < 15, 'sample_gap')
                previous = time.monotonic()
                sample = self.sample()
                count += 1
                sample['samples'] = count
                save(self.root/'guard.json', sample)
                time.sleep(5)
            raise Blocked('operation_deadline')
        except Exception as error:
            save(self.root/'guard-failure.json', {'class': type(error).__name__, 'reason': str(error) if isinstance(error, Blocked) else 'sampling_failed'})
            raise
        # systemd ExecStopPost independently cleans on success, failure or signal.

    def run(self, role, extra, command=()):
        self.active()
        self.call(['/usr/bin/podman', 'run', '-d', '--pull=never', '--name', self.name(role),
                   '--label', LABEL+'='+self.token, '--memory', str(MEMORY[role])+'m',
                   '--memory-swap', str(MEMORY[role])+'m', '--cpus', str(CPU[role]),
                   '--pids-limit', '256', '--image-volume=ignore', '--log-driver=none', *extra,
                   self.spec['images'][role], *command])
        obj = self.inspect(role)
        require(obj['Config']['Labels'].get(LABEL) == self.token and obj['Image'].removeprefix('sha256:') == self.spec['images'][role], 'runtime_identity')
        hc = obj['HostConfig']
        require(not hc.get('PortBindings') and hc['Memory'] == MEMORY[role]*1024**2
                and hc['MemorySwap'] == MEMORY[role]*1024**2, 'runtime_limits')
        require(hc['CpuQuota']/hc['CpuPeriod'] == CPU[role], 'cpu_limit')
        # Verify effective cgroup v2 controls, not just requested settings.
        pid = obj['State']['Pid']
        relative = Path('/proc/'+str(pid)+'/cgroup').read_text().strip().split('::', 1)[1]
        cgroup = Path('/sys/fs/cgroup')/relative.lstrip('/')
        require((cgroup/'memory.max').read_text().strip() == str(MEMORY[role]*1024**2), 'effective_memory')
        require((cgroup/'memory.swap.max').read_text().strip() == '0', 'effective_swap')
        quota, period = (cgroup/'cpu.max').read_text().split()
        require(quota != 'max' and int(quota)/int(period) == CPU[role], 'effective_cpu')

    def inject(self, raw):
        """Called under the phase lock: terminal cleanup can never be undone."""
        require(len(raw) <= 32768, 'credential_input_bound')
        values = json.loads(raw)
        require(set(values) == {'django', 'password', 'id', 'key'}, 'credential_fields')
        for value in values.values():
            require(isinstance(value, str) and 1 <= len(value) <= 8192
                    and not any(c in value for c in ('\n', '\r', '\0')), 'credential_format')
        require(len(values['django']) >= 32, 'django_secret_format')
        targets = {'django-secret': values['django'], 'retrieval/password': values['password'],
                   'retrieval/credentials.json': json.dumps({'id': values['id'], 'key': values['key']})}
        try:
            for name, value in targets.items():
                self.active()
                path = self.root/name
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'w') as stream: stream.write(value)
            self.active()
        except Exception:
            # Guard finalization also retries each file independently.
            for name in targets:
                path = self.root/name
                try:
                    if path.exists(): protected(path); path.unlink()
                except Exception: pass
            raise
        save(self.root/'credential-delivery.json', {'delivered': True})

    def retrieve(self):
        self.active()
        helper = self.spec['restic_helper']
        require(re.fullmatch('/[A-Za-z0-9_./-]+', helper), 'helper_path')
        self.call(['/usr/bin/systemd-run', '--user', '--wait', '--collect',
                   '--unit='+self.token+'-retrieval.service', '--property=Type=exec',
                   '--property=BindsTo='+self.unit, '--property=After='+self.unit,
                   '--property=CPUQuota=200%', '--property=MemoryMax=512M',
                   '--property=MemorySwapMax=0', '--property=RuntimeMaxSec=1200',
                   '--property=StandardOutput=null', '--property=StandardError=null',
                   '/usr/bin/python3', '-B', helper, '--root', str(self.root/'retrieval')], timeout=1230)

    def start(self):
        import secrets
        for role in ROLES:
            exists = subprocess.run(['/usr/bin/podman', 'container', 'exists', self.name(role)], capture_output=True, timeout=10)
            require(exists.returncode == 1, 'retained_container')
        require(subprocess.run(['/usr/bin/podman', 'volume', 'exists', self.volume], capture_output=True, timeout=10).returncode == 1, 'retained_volume')
        protected(self.root/'django-secret')
        secret = (self.root/'django-secret').read_text().strip()
        require(len(secret) >= 32 and '\n' not in secret and '\r' not in secret, 'django_secret_format')
        password = secrets.token_hex(32)
        (self.root/'postgresql.env').write_text('POSTGRES_USER=nautobot\nPOSTGRES_DB=postgres\nPOSTGRES_PASSWORD='+password+'\n')
        (self.root/'redis.conf').write_text('bind 127.0.0.1\nprotected-mode yes\nrequirepass '+password+'\nsave ""\nappendonly no\n')
        config = self.root/'extracted/configuration/var/lib/nautobot/runtime/nautobot_config.py'
        require(config.is_file() and not config.is_symlink(), 'recovered_config')
        (self.root/'application.env').write_text('NAUTOBOT_SECRET_KEY='+secret+'\nNAUTOBOT_DB_HOST=127.0.0.1\nNAUTOBOT_DB_NAME=nautobot_restore\nNAUTOBOT_DB_USER=nautobot\nNAUTOBOT_DB_PASSWORD='+password+'\nNAUTOBOT_REDIS_HOST=127.0.0.1\nNAUTOBOT_REDIS_PASSWORD='+password+'\nNAUTOBOT_CONFIG=/restore/config.py\nPYTHONDONTWRITEBYTECODE=1\nPROMETHEUS_MULTIPROC_DIR=/prom_cache\nHOME=/opt/nautobot\n')
        self.call(['/usr/bin/podman', 'volume', 'create', '--label', LABEL+'='+self.token, self.volume])
        self.run('postgresql', ['--network=none', '--env-file', str(self.root/'postgresql.env'),
                              '-v', self.volume+':/var/lib/postgresql/data'])
        anchor = self.inspect('postgresql')['Id']
        self.run('redis', ['--network=container:'+anchor, '--read-only', '--read-only-tmpfs=false', '--user=0',
                          '-v', str(self.root/'redis.conf')+':/restore/redis.conf:ro', '--entrypoint=redis-server'], ['/restore/redis.conf'])
        scripts = Path(__file__).parent
        self.run('application', ['--network=container:'+anchor, '--user=0', '--read-only', '--read-only-tmpfs=false',
                 '--cap-drop=all', '--security-opt=no-new-privileges', '--env-file', str(self.root/'application.env'),
                 '--tmpfs=/tmp:rw,size=128m,mode=1777', '--tmpfs=/prom_cache:rw,size=16m,mode=1777',
                 '--tmpfs=/opt/nautobot/git:rw,size=16m,mode=1777',
                 '--tmpfs=/opt/nautobot/jobs:rw,size=16m,mode=1777',
                 '--tmpfs=/opt/nautobot/static:rw,size=256m,mode=1777',
                 '-v', str(config)+':/restore/config.py:ro', '-v', str(scripts)+':/scripts:ro',
                 '-v', str(self.root/'extracted/media')+':/opt/nautobot/media:rw', '--entrypoint=sleep'], ['infinity'])
        self.isolation()
        for _ in range(60):
            ready = subprocess.run(['/usr/bin/podman', 'exec', self.name('postgresql'), 'pg_isready', '-U', 'nautobot'], capture_output=True, timeout=5)
            if ready.returncode == 0: return
            self.active(); time.sleep(1)
        raise Blocked('database_unready')

    def isolation(self):
        objects = [self.inspect(role) for role in ROLES]
        namespaces = {os.readlink('/proc/'+str(obj['State']['Pid'])+'/ns/net') for obj in objects}
        require(len(namespaces) == 1 and os.readlink('/proc/self/ns/net') not in namespaces, 'network_namespace')
        self.call(['/usr/bin/podman', 'exec', self.name('application'), 'python3', '-c',
                   "import os; assert sorted(os.listdir('/sys/class/net')) == ['lo']; assert len(open('/proc/net/route').read().splitlines()) == 1"])
        for obj in objects: require(not obj['HostConfig'].get('PortBindings'), 'published_port')

    def import_dump(self):
        self.isolation()
        path = self.root/'retrieval/retrieved/postgresql_custom_dump'
        require(not path.is_symlink() and path.stat().st_size <= 268435456, 'dump_metadata')
        raw = path.read_bytes(); require(raw[:5] == b'PGDMP', 'dump_format')
        self.call(['/usr/bin/podman', 'exec', self.name('postgresql'), 'createdb', '-U', 'nautobot', 'nautobot_restore'])
        self.call(['/usr/bin/podman', 'exec', '-i', self.name('postgresql'), 'timeout', '600', 'pg_restore',
                   '--exit-on-error', '--single-transaction', '-U', 'nautobot', '-d', 'nautobot_restore'], data=raw, timeout=620)

    def probe(self, phase, suffix=''):
        self.isolation()
        deadline = 360 if phase == 'logical' else 600
        raw = self.call(['/usr/bin/podman', 'exec', self.name('application'), 'timeout', str(deadline),
                         'python3', '-B', '/scripts/restore_probe.py', phase], timeout=deadline+20)
        result = json.loads(raw.decode().split('RESTORE_RESULT=')[-1])
        if 'failure' in result:
            save(self.root/(phase+'-diagnostic.json'), result['failure'])
            raise Blocked('native_probe_failed')
        if phase == 'logical':
            import logical_database
            reference = json.loads((self.root/'logical-reference.json').read_text())
            result = logical_database.compare(reference, result)
            save(self.root/('logical'+suffix+'-result.json'), result)
            require(result['equal'], 'logical_mismatch')
        else:
            expected = json.loads((self.root/'retrieval/retrieved/versions_migrations').read_text())
            require(result['versions'] == expected['versions'], 'versions_mismatch')
            from datetime import datetime
            normalize = lambda rows: [(r['app'], r['name'], datetime.fromisoformat(r['applied']).isoformat()) for r in rows]
            require(normalize(result['migrations']) == normalize(expected['migrations']), 'migration_ledger_mismatch')
        save(self.root/(phase+suffix+'-result.json'), result)

    def cleanup(self):
        # Latch first: concurrent commands abort and no later phase can create resources.
        if not (self.root/'stopped.json').exists(): save(self.root/'stopped.json', {'terminal': True})
        result = {}
        with self.lock():
            for role in reversed(ROLES):
                name = self.name(role)
                try:
                    status = subprocess.run(['/usr/bin/podman', 'container', 'exists', name], capture_output=True, timeout=10).returncode
                    require(status in (0, 1), 'container_query')
                    if status == 0:
                        obj = self.inspect(role)
                        require(obj['Config']['Labels'].get(LABEL) == self.token, 'container_owner')
                        bounded(['/usr/bin/podman', 'rm', '-f', '--time=5', name], timeout=30)
                    require(subprocess.run(['/usr/bin/podman', 'container', 'exists', name], capture_output=True, timeout=10).returncode == 1, 'container_residue')
                    result[role] = True
                except Exception: result[role] = False
            try:
                status = subprocess.run(['/usr/bin/podman', 'volume', 'exists', self.volume], capture_output=True, timeout=10).returncode
                require(status in (0, 1), 'volume_query')
                if status == 0:
                    info = json.loads(bounded(['/usr/bin/podman', 'volume', 'inspect', self.volume]))[0]
                    require(info.get('Labels', {}).get(LABEL) == self.token, 'volume_owner')
                    bounded(['/usr/bin/podman', 'volume', 'rm', self.volume])
                require(subprocess.run(['/usr/bin/podman', 'volume', 'exists', self.volume], capture_output=True, timeout=10).returncode == 1, 'volume_residue')
                result['volume'] = True
            except Exception: result['volume'] = False
            for name in SECRETS:
                try:
                    path = self.root/name
                    if path.exists() or path.is_symlink(): protected(path); path.unlink()
                    result[name] = not path.exists()
                except Exception: result[name] = False
            save(self.root/'cleanup-result.json', result)
        require(all(result.values()), 'cleanup_incomplete')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['arm', 'guard', 'inject', 'retrieve', 'start', 'import', 'logical', 'check', 'cleanup', 'finish', 'host-health'])
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    runtime = Restore(args.root)
    try:
        if args.phase == 'host-health': runtime.host_health()
        elif args.phase in ('arm', 'guard', 'cleanup'): getattr(runtime, args.phase)()
        elif args.phase == 'finish':
            # independent production readback is permitted after cleanup latch.
            runtime.call = bounded
            require(runtime.production() == json.loads((runtime.root/'production-before.json').read_text()), 'production_changed')
            require(not (runtime.root/'guard-failure.json').exists(), 'guard_failed')
        else:
            with runtime.lock():
                runtime.active()
                if args.phase == 'inject': runtime.inject(sys.stdin.buffer.read(32769))
                elif args.phase == 'retrieve': runtime.retrieve()
                elif args.phase == 'start': runtime.start()
                elif args.phase == 'import': runtime.import_dump()
                else:
                    runtime.probe(args.phase)
                    if args.phase == 'check':
                        expected = json.loads((runtime.root/'members.json').read_text())['media']
                        media = runtime.root/'extracted/media'
                        observed = {'.': {'type':'directory'}}
                        for path in media.rglob('*'):
                            require(path.is_dir() and not path.is_symlink(), 'media_changed')
                            observed[str(path.relative_to(media))] = {'type':'directory'}
                        require(observed == expected, 'media_changed')
                        runtime.active()
                        save(runtime.root/'checks-complete.json', {'passed': True})
    except Exception as error:
        save(runtime.root/(args.phase+'-failure.json'), {'class': type(error).__name__, 'reason': str(error) if isinstance(error, Blocked) else 'phase_failed'})
        return 1
    return 0


if __name__ == '__main__': raise SystemExit(main())
