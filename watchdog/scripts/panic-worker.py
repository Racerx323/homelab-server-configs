#!/usr/bin/python3
"""Fixed j2 panic worker. Loaded only by the sealed controller; no standalone CLI."""
import base64
import hashlib
import json
import math
import os
import re
from pathlib import Path
import secrets
import signal
import socket
import stat
import sys
import time

# Dependencies are injected from the hash-checked bundle, never from a target file.
h = p = o = r = cutover = None
MEASURE = b''
SPEC = {}
BASE = {}
ENV = {'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
       'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
BOOT = '/proc/sys/kernel/random/boot_id'
CONFIG = '/boot/config-6.18.50+rpt-rpi-v8'
SYSCALL_PATH = '/proc/sysrq-trigger'
RECIPE = {'maximum_pps_offset_ms': 5, 'maximum_pps_jitter_ms': 1,
          'nts_servers': ['time.cloudflare.com', 'ohio.time.system76.com', 'oregon.time.system76.com']}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identity(expected=None):
    require(os.geteuid() == 0 and socket.gethostname() == 'j2-svntp1', 'target identity')
    boot = Path(BOOT).read_text().strip()
    require(expected is None or boot == expected, 'boot drift')
    require(time.time() < SPEC['expires_epoch'], 'expired worker')
    return boot


def command(argv, timeout=10):
    row = h.bounded(argv, timeout=timeout, limit=h.LIMIT, env=ENV)
    if row.get('returncode') != 0 or row.get('error'):
        emit({'capture_complete': False, 'failed_command': row})
        raise ValueError('command failed: '+argv[0])
    return row


def executable_record(path, limit=64*1024**2):
    """Hash a bounded regular executable without retaining its contents."""
    path = Path(path)
    row = {}
    def signature(info):
        return tuple(getattr(info, key) for key in (
            'st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink',
            'st_size', 'st_mtime_ns', 'st_ctime_ns'))
    try:
        require(path.is_absolute(), 'absolute path required')
        require(not any(parent.is_symlink() for parent in path.parents), 'symlink ancestor')
        info = path.lstat()
        row = {'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid,
               'size': info.st_size, 'inode': info.st_ino, 'device': info.st_dev,
               'nlink': info.st_nlink, 'mtime_ns': info.st_mtime_ns}
        require(stat.S_ISREG(info.st_mode), 'regular file required')
        require(info.st_mode & stat.S_IXUSR, 'owner execute permission required')
        require(0 < info.st_size <= limit, 'executable size outside 1..'+str(limit)+' bytes')
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
        with os.fdopen(fd, 'rb') as stream:
            require(signature(os.fstat(stream.fileno())) == signature(info), 'file identity changed before read')
            digest = hashlib.sha256(); total = 0
            while chunk := stream.read(min(65536, limit-total+1)):
                total += len(chunk)
                require(total <= limit, 'executable grew beyond byte bound')
                digest.update(chunk)
            require(total == info.st_size and signature(os.fstat(stream.fileno())) == signature(info)
                    and signature(path.lstat()) == signature(info), 'file changed during read')
        row['sha256'] = digest.hexdigest()
    except (OSError, ValueError) as error:
        row['error'] = str(error)
    return row


def protected(path, digest=None, executable=False):
    row = executable_record(path) if executable else h.file_record(path)
    try:
        reason = row.get('error') or ('missing' if row.get('missing') else
                 'changed during read' if row.get('changed_during_read') else 'digest unavailable')
        require('sha256' in row and not row.get('changed_during_read'), 'file unavailable: '+path+': '+reason)
        require(row['uid'] == 0 and not row['mode'] & 0o022, 'untrusted file: '+path)
        require(digest is None or row['sha256'] == digest, 'file drift: '+path)
    except ValueError as error:
        emit({'capture_complete': False, 'failed_file': {'path': path, 'record': row}, 'error': str(error)})
        raise
    return row


def safe_native(native):
    require(not native.get('kernel_release_mismatch'), 'kernel drift')
    require(native['commands']['kernel'].get('returncode') == 0, 'uname failed')
    for key, field, expected in [('kgdboc_parameter', 'text', '\n'),
                                ('panic_timeout', 'text', '0\n'),
                                ('cmdline_policy', 'selected_text', 'console=tty1')]:
        row = native[key]
        require(not row.get('error') and not row.get('changed_during_read')
                and row.get(field) == expected, 'native policy drift: '+key)


def safe_owner(row):
    matches = row.get('matches', [])
    require(row.get('scan_complete') is True and not row.get('gaps'), 'ownership scan gap')
    require(len(matches) == 1, 'one device owner required')
    owner = matches[0]
    require(owner['pid'] == 1 and owner['uid'] == 0
            and owner['exe_link'] == '/usr/lib/systemd/systemd'
            and owner['recheck_stable'] is True, 'watchdog owner drift')


def critical(expected):
    boot = identity(expected)
    native = r.debugger_inputs(SPEC['kernel_release']); safe_native(native)
    version = command(['/usr/bin/systemctl', '--version'])
    require(version['stdout'] == BASE['systemd_version'], 'systemd version drift')
    protected(CONFIG, BASE['kernel_config_sha256'])
    files = {name: protected(name, digest) for name, digest in BASE['protected'].items()}
    manager = o.manager()
    require(manager.get('returncode') == 0 and p.properties(manager) == BASE['manager'], 'manager drift')
    configs = o.configurations()
    require(configs == BASE['configuration'], 'watchdog configuration drift')
    owners = o.owners(); safe_owner(owners)
    watchdog = {k: p.text_record('/sys/class/watchdog/watchdog0/'+k, True)
                for k in ('identity', 'state', 'timeout', 'nowayout', 'bootstatus')}
    for key in ('identity', 'state', 'timeout', 'nowayout'):
        require(watchdog[key].get('text') == BASE['watchdog'][key], 'watchdog metadata drift')
    require(identity(expected) == boot, 'boot changed during critical scan')
    return {'boot': boot, 'native': native, 'files': files, 'manager': manager,
            'configuration': configs, 'owners': owners, 'watchdog': watchdog}


def native_available(value):
    """Accept synchronized service on a permitted source, independently of precision."""
    system = value['system']
    if int(system.get('leap', 3)) != 0 or not 1 <= int(system.get('stratum', 16)) <= 15:
        return False
    selected = [p for p in value['peers'] if ((p['status'] >> 8) & 7) in (6, 7)]
    # PPS can supersede the system peer; do not require both to be the system source.
    pps = [p for p in selected if ((p['status'] >> 8) & 7) == 7]
    selected = pps or selected
    if len(selected) != 1:
        return False
    peer = selected[0]; variables = peer['variables']
    if int(variables.get('reach', 0)) == 0:
        return False
    if variables.get('srcadr') in ('SHM(0)', '127.127.28.0', 'SHM(2)', '127.127.28.2'):
        return True
    return (variables.get('srchost') in RECIPE['nts_servers']
            and (peer['status'] >> 8) & 0x60 == 0x60
            and int(variables.get('ntscookies', 0)) > 0)


def health(expected, strict=True):
    boot = identity(expected); start = time.monotonic()
    # Source-built native protocol library; read-only localhost variables/cookie counts.
    native = command(['/usr/bin/python3', '-I', '-B', '-c', MEASURE.decode()])
    value = json.loads(native['stdout'])
    finite_timing = True
    for peer in value['peers']:
        for key in ('offset', 'jitter'):
            try:
                finite_timing = finite_timing and math.isfinite(float(peer['variables'][key]))
            except (KeyError, TypeError, ValueError):
                finite_timing = False
    try:
        checks = cutover.measurement_checks(value, RECIPE)
    except (ValueError, KeyError, TypeError):
        if strict: raise
        checks = {'measurement_complete': False}
    checks['finite_timing'] = finite_timing
    if strict and (not checks or not all(v is True for v in checks.values())):
        emit({'capture_complete': False, 'stage': 'health', 'native': value, 'checks': checks,
              'error': 'NTP not ready'})
    if strict:
        require(checks and all(v is True for v in checks.values()), 'NTP not ready')
    units = {}
    try:
        units = p.state()
        for unit in p.CORE:
            require(units[unit].get('returncode') == 0, 'unit query failed')
            props = p.properties(units[unit])
            require(props.get('ActiveState') == 'active' and props.get('UnitFileState') == 'enabled', 'core unit inactive/disabled')
        service = p.properties(units['timeservice.service'])
        processes = command(['/usr/bin/ps', '-eo', 'pid,ppid,euid,egid,comm'])
        rows = [line.split() for line in processes['stdout'].splitlines()[1:]]
        ntp = [x for x in rows if len(x) == 5 and x[4] == 'ntpd']
        gps = [x for x in rows if len(x) == 5 and x[4] == 'gpsd']
        require(len(ntp) == len(gps) == 1, 'daemon count')
        for row, name in [(ntp[0], 'ntpd'), (gps[0], 'gpsd')]:
            require(row[2:4] == BASE['credentials'][name], 'daemon credentials')
            require(row[1] == service['MainPID'], 'daemon supervisor parent')
            require(os.readlink('/proc/'+row[0]+'/exe') == '/usr/local/sbin/'+name, 'daemon executable')
            status = p.text_record('/proc/'+row[0]+'/status')['text']
            ids = {line.split(':', 1)[0]: line.split(':', 1)[1].split()
                   for line in status.splitlines() if line.startswith(('Uid:', 'Gid:'))}
            require(ids == {'Uid': [BASE['credentials'][name][0]]*4,
                            'Gid': [BASE['credentials'][name][1]]*4}, 'full daemon credentials')
        require(service.get('NRestarts') == '0' and not service.get('DropInPaths'), 'supervisor restart/override')
        numbers = set()
        for path in ('/dev/serial0', '/dev/pps0'):
            resolved = Path(path).resolve()
            require(str(resolved).startswith('/dev/'), 'receiver alias escaped /dev')
            metadata = os.stat(resolved)
            require(stat.S_ISCHR(metadata.st_mode), 'receiver character identity')
            numbers.add(metadata.st_rdev)
        held = set()
        for fd in p.names('/proc/'+gps[0][0]+'/fd', 128):
            info = os.stat(fd)
            if stat.S_ISCHR(info.st_mode): held.add(info.st_rdev)
        require(numbers <= held, 'GPSD does not hold both receiver devices')
        require(identity(expected) == boot and time.monotonic()-start <= 10, 'health duration/boot')
    except BaseException as error:
        emit({'capture_complete': False, 'stage': 'service-health', 'native': value,
              'checks': checks, 'units': units, 'error': str(error)})
        raise
    return {'boot': boot, 'native': value, 'checks': checks, 'units': units,
            'available': native_available(value),
            'precision': bool(checks) and all(v is True for v in checks.values()),
            'daemon_metadata': ntp+gps, 'elapsed': time.monotonic()-start}


def journal_context(expected):
    identity(expected)
    unit = command(['/usr/bin/systemctl', 'show', 'timeservice.service',
                    '--property=MainPID,InvocationID,ExecMainStartTimestampMonotonic,NRestarts'])
    props = p.properties(unit)
    require(re.fullmatch('[0-9a-f]{32}', props.get('InvocationID', '')), 'service invocation missing')
    require(props.get('NRestarts') == '0', 'service restarted')
    main = int(props['MainPID']); origin = int(props['ExecMainStartTimestampMonotonic'])/1_000_000
    require(main > 0 and origin > 0, 'service start missing')
    processes = command(['/usr/bin/ps', '-eo', 'pid,ppid,comm'])
    rows = [x.split() for x in processes['stdout'].splitlines()[1:]]
    ntp = [x for x in rows if len(x) == 3 and x[2] == 'ntpd']
    require(len(ntp) == 1 and int(ntp[0][1]) == main, 'current NTP child mismatch')
    pid = int(ntp[0][0]); path = '/proc/'+str(pid)
    require(os.readlink(path+'/exe') == '/usr/local/sbin/ntpd', 'NTP executable mismatch')
    raw = p.text_record(path+'/stat')['text']
    fields = raw.rsplit(')', 1)[1].split()
    require(int(raw.split('(', 1)[0]) == pid and int(fields[1]) == main, 'NTP process drift')
    ticks = os.sysconf('SC_CLK_TCK'); require(ticks > 0, 'clock tick frequency')
    started = int(fields[19])/ticks
    require(started >= origin, 'NTP start precedes supervisor')
    identity(expected)
    return {'boot': expected, 'ntpd_pid': pid, 'ntpd_started': started,
            'supervisor_pid': main, 'supervisor_started': origin, 'invocation': props['InvocationID']}


def journal_policy(raw, boot, context):
    rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
    require(len(rows) < 200, 'journal cap reached; coverage incomplete')
    require(context['boot'] == boot and context['ntpd_pid'] > 0
            and math.isfinite(context['ntpd_started']) and context['ntpd_started'] > 0,
            'journal context missing')
    ntp = []; other = []
    for row in rows:
        require(row.get('_BOOT_ID') == boot.replace('-', '') and row.get('PRIORITY') in ('0','1','2','3'),
                'journal boot/priority mismatch')
        stamp = int(row['__MONOTONIC_TIMESTAMP'])/1_000_000
        require(stamp >= 0, 'invalid journal time')
        if row.get('_SYSTEMD_UNIT') == 'timeservice.service':
            # The reused classifier skips pre-origin rows; this adapter must not.
            if stamp < context['ntpd_started'] or row.get('_SYSTEMD_INVOCATION_ID') != context['invocation']:
                other.append(row)
            else: ntp.append(json.dumps(row))
        else: other.append(row)
    classified = cutover.journal_health('\n'.join(ntp), boot, context['ntpd_started'], context['ntpd_pid'])
    return {'healthy': classified['healthy'] and not other,
            'ntp': classified, 'other_unresolved': other}


def full(expected):
    result = {}
    try:
        result.update(critical(expected))
        result['health'] = health(expected)
        result['capacity'] = {}
        for path in ('/', '/var/log/ntpstats'):
            capacity = os.statvfs(path)
            require(capacity.f_bavail*capacity.f_frsize >= 10*1024**3, 'available byte floor')
            require(capacity.f_files > 0 and capacity.f_favail/capacity.f_files >= .05, 'available inode floor')
            result['capacity'][path] = {'available_bytes': capacity.f_bavail*capacity.f_frsize,
                                       'available_inodes': capacity.f_favail, 'inodes': capacity.f_files}
        for name in ('mounts', 'boot_mount'):
            row = command(r.COMMANDS[name]); fs = json.loads(row['stdout'])['filesystems']
            require(len(fs) == 1 and 'rw' in fs[0]['vfs-options'].split(','), 'filesystem not writable')
            result[name] = row
        result['temperature'] = p.text_record('/sys/class/thermal/thermal_zone0/temp', True)
        require(int(result['temperature']['text']) < 80000, 'thermal fault')
        # Native firmware query, not a stress test or counter reset.
        result['throttled'] = command(['/usr/bin/vcgencmd', 'get_throttled'])
        require(result['throttled']['stdout'].strip() == 'throttled=0x0', 'throttle/undervoltage needs disposition')
        result['network'] = {k: command(p.COMMANDS[k]) for k in ('addresses', 'routes4', 'routes6', 'network_runtime', 'listeners')}
        addresses = json.loads(result['network']['addresses']['stdout'])
        current = {a['local'] for x in addresses for a in x['addr_info']}
        require(set(SPEC['endpoints']) <= current, 'fixed addresses absent')
        result['journal_context_before'] = journal_context(expected)
        result['errors'] = command(['/usr/bin/journalctl', '-b', '-p', '0..3', '--quiet', '--no-pager', '-o', 'json', '-n', '200'])
        result['journal_context_after'] = journal_context(expected)
        require(result['journal_context_before'] == result['journal_context_after'], 'journal process continuity')
        result['journal_policy'] = journal_policy(result['errors']['stdout'], expected, result['journal_context_before'])
        require(result['journal_policy']['healthy'], 'unresolved current boot errors require review')
        result['native_tools'] = {}
        for path in ('/usr/local/bin/ntpq', '/usr/local/sbin/ntpd', '/usr/local/sbin/gpsd'):
            result['native_tools'][path] = protected(path, executable=True)
        result['leap_records'] = command(p.COMMANDS['leap_journal'])
        result['maintenance_records'] = {}
        for name in ('/var/lib/ntpstats-retention/last-success.json',
                     '/var/lib/needrestart-reporting/last-success.json'):
            row = p.text_record(name)
            result['maintenance_records'][name] = row
            require('text' in row and not row.get('changed_during_read'), 'maintenance evidence unavailable: '+name)
        require(identity(expected) == expected, 'full capture boot drift')
        return result
    except (Exception, WorkerDeadline) as error:
        emit({'capture_complete': False, 'stage': 'full', 'error': str(error), 'partial': result})
        raise


def emit(value):
    sys.stdout.write(json.dumps(value, sort_keys=True)+'\n'); sys.stdout.flush()


def grant_valid(value, nonce, ready, now):
    require(set(value) == {'nonce', 'operation_id', 'action'}, 'grant shape')
    require(value == {'nonce': nonce, 'operation_id': SPEC['operation_id'], 'action': 'panic-once'}, 'grant binding')
    require(0 <= now-ready <= 8, 'grant expired')


def trigger():
    started = time.monotonic()
    boot = identity(BASE['boot'])
    command(['/usr/bin/sync'], timeout=30)
    # Recheck all destructive prerequisites after sync, before READY.
    fresh = critical(boot)
    health_offset = time.monotonic()-started
    sample = health(boot)
    ready = time.monotonic(); nonce = secrets.token_hex(32)
    emit({'ready': True, 'nonce': nonce, 'critical': fresh, 'health': sample, 'health_started_offset': health_offset})
    signal.alarm(8)
    raw = sys.stdin.buffer.readline(1025)
    require(len(raw) <= 1024 and raw.endswith(b'\n'), 'bounded complete grant')
    grant_valid(json.loads(raw), nonce, ready, time.monotonic())
    identity(boot)
    # One attempt only. No retry even if open/write raises or connection disappears.
    fd = os.open(SYSCALL_PATH, os.O_WRONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        require(stat.S_ISREG(os.fstat(fd).st_mode), 'unexpected SysRq interface type')
        os.write(fd, b'c')
    finally:
        os.close(fd)
    raise RuntimeError('panic write returned; attempt consumed')


class WorkerDeadline(BaseException):
    """Cannot be swallowed by bounded command error reporting."""


def journal(expected):
    result = {'capture_complete': False, 'operation_id': SPEC['operation_id']}
    try:
        result['boot_before'] = identity(expected)
        result['errors'] = command(['/usr/bin/journalctl', '-b', '-p', '0..3', '--quiet',
                                    '--no-pager', '-o', 'json', '-n', '200'])
        result['boot_after'] = identity(expected)
        require(result['boot_before'] == result['boot_after'], 'journal boot changed')
        result['capture_complete'] = True
        return result
    except (Exception, WorkerDeadline) as error:
        emit({**result, 'error': str(error)})
        raise


def package_metadata():
    return {'dpkg_status': protected('/var/lib/dpkg/status'),
            'apt_lists': {str(name): p.metadata(name) for name in p.names('/var/lib/apt/lists', 256)},
            'history': {name: p.metadata(name) for name in (
                '/var/log/apt/history.log', '/var/log/apt/history.log.1.gz',
                '/var/log/dpkg.log', '/var/log/dpkg.log.1', '/var/run/reboot-required',
                '/var/run/reboot-required.pkgs')}}


def journal_inputs(expected):
    result = {'capture_complete': False, 'operation_id': SPEC['operation_id']}
    try:
        result['boot_before'] = identity(expected)
        result['context_before'] = journal_context(expected)
        result['package_metadata_before'] = package_metadata()
        paths = ('/usr/lib/udev/rules.d/90-alsa-restore.rules',
                 '/etc/udev/rules.d/90-alsa-restore.rules', '/run/udev/rules.d/90-alsa-restore.rules')
        result['rules'] = {}
        for path in paths:
            row = p.metadata(path)
            if not row.get('missing') and not row.get('link'):
                row['content'] = p.text_record(path)
            result['rules'][path] = row
        result['package_owner'] = command(['/usr/bin/dpkg-query', '-S', paths[0]])
        result['packages'] = command(['/usr/bin/dpkg-query', '-W',
            '-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\t${db:Status-Abbrev}\n',
            'alsa-utils', 'udev'])
        result['installed_packages'] = command(['/usr/bin/dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${db:Status-Abbrev}\n'])
        result['selections'] = command(['/usr/bin/dpkg', '--get-selections'])
        result['upgrade_simulation'] = command(['/usr/bin/apt-get', '--simulate', '-o', 'Debug::NoLocking=1',
            '-o', 'Dir::Cache::pkgcache=', '-o', 'Dir::Cache::srcpkgcache=', 'upgrade'], timeout=30)
        result['package_metadata_after'] = package_metadata()
        require(result['package_metadata_before'] == result['package_metadata_after'], 'package metadata changed during inspection')
        result['journal'] = journal(expected)
        result['context_after'] = journal_context(expected)
        result['boot_after'] = identity(expected)
        require(result['context_before'] == result['context_after'], 'journal process continuity')
        result['policy_assessment'] = journal_policy(result['journal']['errors']['stdout'], expected, result['context_before'])
        # Complete inspection may identify a blocking policy result; never accepts a panic.
        result['capture_complete'] = True
        return result
    except (Exception, WorkerDeadline) as error:
        emit({**result, 'error': str(error)})
        raise


def entry(mode, expected):
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(WorkerDeadline('worker deadline')))
    signal.alarm({'boot': 2, 'health': 10, 'recovery': 10, 'full': 120, 'trigger': 90, 'journal': 30, 'journal-inputs': 90}[mode])
    if mode == 'trigger':
        trigger()
    elif mode == 'journal-inputs':
        emit(journal_inputs(expected))
    elif mode == 'journal':
        emit(journal(expected))
    elif mode == 'recovery':
        emit(health(expected, strict=False))
    elif mode == 'boot':
        emit({'boot': identity()})
    else:
        emit((full if mode == 'full' else health)(expected))
