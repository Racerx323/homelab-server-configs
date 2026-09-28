#!/usr/bin/env python3
"""Node-local schedule/lease boundary; Ansible owns capture and writer ordering.

The independent systemd recovery service first quiesces the backup cgroup, then
attempts every reviewed resume command. No provider, notification or retention API.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timedelta
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import tempfile
import time
from zoneinfo import ZoneInfo


class Blocked(ValueError):
    pass


def require(ok, code):
    if not ok: raise Blocked(code)


def protected(path, directory=False):
    info = path.lstat()
    require((stat.S_ISDIR if directory else stat.S_ISREG)(info.st_mode)
            and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600)
            and not any(p.is_symlink() for p in path.parents), 'unsafe_metadata')


def atomic(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(value, out, sort_keys=True); out.write('\n'); out.flush(); os.fsync(out.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextmanager
def lock(path, blocking=True):
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        protected(path)
        fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        yield
    finally: os.close(fd)


def validate(config):
    require(set(config)-{'notification_argv','staging_directory','staging_filesystem','dispose_successful_payload'} == {'schema_version', 'execution_authorized', 'state_directory', 'unit_prefix',
            'timezone', 'start_hour', 'end_hour', 'capture_seconds', 'recovery_seconds',
            'run_seconds', 'prepare_argv', 'ansible_argv', 'resume_commands', 'health_argv'}, 'configuration_fields')
    require(config['schema_version'] == 1 and config['execution_authorized'] is True, 'inactive_configuration')
    require(re.fullmatch(r'nautobot-protection(?:-[a-z0-9]{1,32})?', config['unit_prefix']), 'unit_scope')
    require(config['timezone'] == 'America/Chicago', 'timezone')
    require(type(config['start_hour']) is int and type(config['end_hour']) is int
            and 0 <= config['start_hour'] < config['end_hour'] <= 24, 'window')
    for key, maximum in [('capture_seconds', 600), ('recovery_seconds', 300), ('run_seconds', 7200)]:
        require(type(config[key]) is int and 1 <= config[key] <= maximum, 'deadline')
    require(config['capture_seconds'] + config['recovery_seconds'] < config['run_seconds'], 'run_deadline')
    require(Path(config['state_directory']).is_absolute(), 'state_directory')
    require(('staging_directory' in config)==('staging_filesystem' in config),'staging_fields')
    if 'staging_directory' in config:
        require(Path(config['staging_directory']).is_absolute() and config['staging_filesystem']=='ext4','staging_contract')
    require(type(config.get('dispose_successful_payload',False)) is bool,'disposal_flag')
    commands = [config[k] for k in ('prepare_argv', 'ansible_argv', 'health_argv')] + config['resume_commands']
    if 'notification_argv' in config: commands.append(config['notification_argv'])
    require(0 < len(config['resume_commands']) <= 3, 'resume_commands')
    for argv in commands:
        require(isinstance(argv, list) and 0 < len(argv) <= 32 and all(isinstance(a, str)
                and len(a) <= 4096 and not any(c in a for c in '\x00\r\n') for a in argv)
                and Path(argv[0]).is_absolute(), 'command_shape')


def in_window(config, now):
    local = now.astimezone(ZoneInfo(config['timezone']))
    end = local.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(hours=config['end_hour'])
    return (config['start_hour'] <= local.hour < config['end_hour']
            and (end-local).total_seconds() >= config['capture_seconds'] + config['recovery_seconds'])


class Supervisor:
    def __init__(self, path):
        protected(path)
        require(path.stat().st_size < 65536, 'configuration_size')
        self.path = path
        self.raw = path.read_bytes()
        self.config = json.loads(self.raw); validate(self.config)
        self.state_dir = Path(self.config['state_directory']); protected(self.state_dir, True)
        self.prefix = self.config['unit_prefix']

    def control(self, *args):
        return subprocess.run(['/usr/bin/systemctl', '--user', *args], capture_output=True, timeout=30)

    def state(self):
        path = self.state_dir/'state.json'
        if not path.exists(): return {'phase': 'idle'}
        protected(path); require(path.stat().st_size < 65536, 'state_size')
        return json.loads(path.read_text())

    def write(self, state):
        atomic(self.state_dir/'state.json', state)

    def check_binding(self, state):
        require(state.get('configuration_sha256') == hashlib.sha256(self.raw).hexdigest(), 'configuration_changed')
        root = Path(state['root']); protected(root, True)
        parent=Path(self.config.get('staging_directory','/tmp'))
        if 'staging_directory' in self.config: protected(parent,True)
        require(root.parent==parent and re.fullmatch(r'nautobot-recurring\.[a-z0-9_]+',root.name), 'run_root')
        return root

    @staticmethod
    def command(argv, timeout):
        # Commands persist their own protected evidence; never journal raw output.
        try:
            process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, cwd='/', start_new_session=True)
            try: return process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(); return 124
        except OSError: return 127

    def check(self):
        with lock(self.state_dir/'state.lock'):
            state = self.state(); self.check_binding(state)
            require(state['phase'] == 'armed' and time.monotonic() < state['deadline'], 'guard_not_armed')
            require(self.control('is-active', '--quiet', self.prefix+'-guard.timer').returncode == 0, 'guard_not_active')

    def recovered(self):
        # Timer race is settled by this lock. A guard that wins first owns recovery;
        # it cannot be disarmed by an Ansible task that is still running.
        require(self.command(self.config['health_argv'], self.config['recovery_seconds']/8) == 0, 'health_failed')
        with lock(self.state_dir/'state.lock'):
            state = self.state(); self.check_binding(state)
            require(state['phase'] == 'armed' and time.monotonic() < state['deadline'], 'guard_already_due')
            state.update(phase='resumed', resumed_at=time.time()); self.write(state)
        require(self.control('stop', self.prefix+'-guard.timer').returncode == 0, 'guard_disarm_failed')

    def run(self):
        try:
            with lock(self.state_dir/'run.lock', blocking=False): return self.run_locked()
        except BlockingIOError:
            atomic(self.state_dir/'last-skip.json', {'reason':'overlap', 'at':time.time()}); return 3

    def run_locked(self):
        config = self.config
        with lock(self.state_dir/'state.lock'):
            previous = self.state()
            require(previous['phase'] not in ('preflight', 'armed', 'recovering', 'manual_intervention'), 'unresolved_recovery')
            if not in_window(config, datetime.now(ZoneInfo(config['timezone']))):
                atomic(self.state_dir/'last-skip.json', {'reason':'outside_window', 'at':time.time()}); return 3
        parent=Path(config.get('staging_directory','/tmp'))
        if 'staging_directory' in config:
            protected(parent,True)
            result=subprocess.run(['/usr/bin/findmnt','--noheadings','--output','FSTYPE','--target',str(parent)],
                                  capture_output=True,timeout=10,check=True)
            require(result.stdout.decode().strip()==config['staging_filesystem'],'staging_filesystem')
        root = Path(tempfile.mkdtemp(prefix='nautobot-recurring.',dir=parent)); root.chmod(0o700)
        # Prepare must resolve credentials, verify original service state and build
        # protected inputs.json before any writer pause; it is consumer-owned.
        state = {'phase':'preflight', 'root':str(root), 'configuration_sha256':hashlib.sha256(self.raw).hexdigest(),
                 'started_at':time.time(), 'previous_success':previous.get('last_success', previous.get('previous_success'))}
        self.write(state)
        rc = 1
        try:
            require(self.command(config['prepare_argv']+[str(root)], 120) == 0, 'prepare_failed')
            require(in_window(config, datetime.now(ZoneInfo(config['timezone']))), 'window_expired')
            protected(root/'inputs.json')
            with lock(self.state_dir/'state.lock'):
                state.update(phase='armed', deadline=time.monotonic()+config['capture_seconds']); self.write(state)
            require(self.control('start', self.prefix+'-guard.timer').returncode == 0, 'guard_start_failed')
            self.check()
            rc = self.command(config['ansible_argv']+['--extra-vars', '@'+str(root/'inputs.json'), '--extra-vars',
                json.dumps({'application_backup_root':str(root), 'protection_configuration':str(self.path), 'protection_script':str(Path(__file__).resolve())})], config['run_seconds'])
            self.cleanup(root)
            with lock(self.state_dir/'state.lock'):
                state = self.state()
                require(state['phase'] == 'resumed', 'resume_not_verified')
                if rc == 0 and config.get('dispose_successful_payload',False):
                    try:
                        self.check_binding(state)
                        require(self.command(config['health_argv'],30)==0,'disposal_health')
                        from recurring_disposal import dispose
                        dispose(root,protected,require,atomic)
                    except Exception:
                        state.update(phase='manual_intervention',reason='payload_disposal_failed'); self.write(state)
                        raise
                state.update(phase='complete' if rc == 0 else 'failed', finished_at=time.time(), exit_status=rc)
                if rc == 0: state['last_success'] = time.time()
                self.write(state)
            return rc
        finally:
            state = self.state()
            if state['phase'] == 'armed':
                self.control('start', '--no-block', self.prefix+'-recovery.service')
            try: self.cleanup(root)
            except Exception:
                state = self.state(); state.update(phase='manual_intervention', reason='credential_cleanup_failed'); self.write(state)
                raise
            if state['phase'] == 'preflight':
                state.update(phase='failed', reason='preflight_failed', finished_at=time.time()); self.write(state)

    @staticmethod
    def cleanup(root):
        protected(root, True)
        # Only the declared transient credentials; captured payload is retained.
        failures = []
        for name in ('password', 'credentials.json', 'source-password', 'source-credentials.json'):
            p = root/name
            try:
                if p.exists() or p.is_symlink(): protected(p); p.unlink()
            except Exception: failures.append(name)
        require(not failures, 'credential_cleanup_failed')

    def guard(self):
        return self.recover(timer=True)

    def recover(self, timer=False):
        try:
            with lock(self.state_dir/'recovery.lock', blocking=False):
                return self.recover_locked(timer)
        except BlockingIOError: return 0

    def recover_locked(self, timer=False):
        with lock(self.state_dir/'state.lock'):
            state = self.state()
            eligible = ('armed', 'recovering') if timer else ('preflight', 'armed', 'recovering', 'resumed')
            if state['phase'] not in eligible: return 0
            root = self.check_binding(state)
            paused_possible = state['phase'] != 'preflight'
            state['phase'] = 'recovering'; self.write(state)
        # Stop the whole backup cgroup before resuming; do not race a late pause.
        self.control('stop', '--no-block', self.prefix+'.service')
        deadline = time.monotonic()+self.config['recovery_seconds']/2
        while True:
            result = self.control('show', self.prefix+'.service', '--property=ActiveState', '--value')
            if result.returncode == 0 and result.stdout.strip() in (b'inactive', b'failed'): break
            if time.monotonic() >= deadline:
                state.update(phase='manual_intervention', reason='backup_not_quiescent'); self.write(state); return 1
            time.sleep(0.1)
        statuses = [self.command(argv, self.config['recovery_seconds']/8) for argv in self.config['resume_commands']] if paused_possible else []
        health = self.command(self.config['health_argv'], self.config['recovery_seconds']/8)
        cleanup = True
        try: self.cleanup(root)
        except Exception: cleanup = False
        state.update(phase='recovered_failure' if not any(statuses) and health == 0 and cleanup else 'manual_intervention',
                     resume_statuses=statuses, health_status=health, credential_cleanup=cleanup, finished_at=time.time())
        self.write(state)
        self.control('stop', self.prefix+'-guard.timer')
        return 0 if state['phase'] == 'recovered_failure' else 1

    def missed(self):
        state = self.state()
        success = state.get('last_success', state.get('previous_success'))
        now = datetime.now(ZoneInfo(self.config['timezone']))
        expected = now.date() if now.hour >= self.config['end_hour'] else (now-timedelta(days=1)).date()
        passed = (isinstance(success, (int,float)) and success <= time.time()
                  and datetime.fromtimestamp(success, now.tzinfo).date() >= expected)
        atomic(self.state_dir/'freshness.json', {'checked_at':time.time(), 'fresh':passed})
        return 0 if passed else 1


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('action', choices=('run','recover','guard','check','recovered','missed'))
    args=parser.parse_args()
    try: return getattr(Supervisor(args.config), args.action)()
    except Exception as error:
        print(json.dumps({'failed':True,'reason':str(error) if isinstance(error,Blocked) else type(error).__name__}))
        return 1


if __name__=='__main__': raise SystemExit(main())
