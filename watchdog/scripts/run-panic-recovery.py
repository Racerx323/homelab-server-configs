#!/usr/bin/python3
"""Seal/check one attended watchdog panic attempt; execution needs its exact hash."""
import argparse
import base64
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import secrets
import selectors
import signal
import socket
import stat
import struct
import subprocess
import tarfile
import time
import types

ROOT = Path(__file__).resolve().parents[1]
NTP = (ROOT/'../../homelab-ntp/ntpsec').resolve()
SOURCES = {'runner.py': ROOT/'scripts/run-panic-recovery.py',
           'worker.py': ROOT/'scripts/panic-worker.py',
           'tests.py': ROOT/'tests/test_panic_recovery.py',
           'helper.py': NTP/'scripts/run-production-inspection.py',
           'passive.py': NTP/'scripts/run-phase3-node-inspection.py',
           'ownership.py': NTP/'scripts/run-watchdog-inspection.py',
           'readiness.py': ROOT/'scripts/inspect-recovery-readiness.py',
           'measurement.py': NTP/'scripts/measure-time-service.py',
           'cutover.py': NTP/'scripts/service-cutover-stage.py',
           'client.py': NTP/'scripts/check-time-client.py',
           'contract.md': ROOT/'docs/CONTROLLED-PANIC-REVIEW.md'}
LIMIT = 1024**2
ENV = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
TIMING = {'health': 300, 'reset': 30, 'escalation': 120, 'stability': 1800,
          'cadence': 60, 'gap': 75, 'total': 2700, 'reservation': 5400}


def encoded(v): return (json.dumps(v, sort_keys=True)+'\n').encode()
def sha(raw): return hashlib.sha256(raw).hexdigest()


def require(ok, why):
    if not ok: raise ValueError(why)


def private_dir(path):
    path = Path(path).absolute()
    require(path.resolve() == path, 'indirect evidence directory')
    info = path.stat()
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
            and not info.st_mode & 0o077, 'owner-private evidence directory required')
    return path


def read(path, limit=16*LIMIT):
    require(path.resolve() == path.absolute(), 'indirect input')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        info = os.fstat(f.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and info.st_nlink == 1 and not info.st_mode & 0o077, 'private regular input')
        raw = f.read(limit+1)
        require(len(raw) <= limit, 'input size bound')
        require(os.fstat(f.fileno()).st_mtime_ns == info.st_mtime_ns, 'input changed')
        return raw


def create(path, value):
    raw = value if isinstance(value, bytes) else encoded(value)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(parent)
    finally: os.close(parent)


def module(name, raw):
    m = types.ModuleType(name); m.__file__ = '/sealed/'+name+'.py'
    exec(compile(raw, m.__file__, 'exec'), m.__dict__)
    return m


def dependencies(files):
    h = module('helper', files['helper.py'])
    p = module('passive', files['passive.py']); p.h = h
    o = module('ownership', files['ownership.py']); o.h = h; o.p = p
    r = module('readiness', files['readiness.py']); r.h = h; r.p = p; r.o = o
    w = module('worker', files['worker.py']); w.h = h; w.p = p; w.o = o; w.r = r
    w.cutover = module('cutover', files['cutover.py']); w.MEASURE = files['measurement.py']
    return w


def payload(spec, files, mode, expected):
    require(mode in ('boot', 'health', 'full', 'trigger', 'journal', 'journal-inputs'), 'closed worker mode')
    # Load only repository-owned, hash-pinned source. No target file import or staging.
    names = ('helper.py', 'passive.py', 'ownership.py', 'readiness.py', 'worker.py', 'cutover.py', 'measurement.py')
    bootstrap = ('import types, json\n'+__import__('inspect').getsource(module)
                 +__import__('inspect').getsource(dependencies)
                 +'files='+repr({k: files[k] for k in names})+'\n'
                 +'w=dependencies(files)\nw.SPEC='+repr(spec)+'\nw.BASE='+repr(json.loads(files['baseline.json']))+'\n'
                 +'w.entry('+repr(mode)+','+repr(expected)+')\n')
    # One complete source line; the second line is the optional one-use grant.
    return ('exec('+repr(bootstrap)+')\n').encode()


def authentication(path):
    """Validate an external secret reference without recording private key bytes."""
    path = Path(path).absolute()
    require(path.resolve() == path, 'indirect authentication input')
    info = path.stat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
            and info.st_nlink == 1 and not info.st_mode & 0o077, 'private authentication input')
    parent = path.parent.stat()
    require(parent.st_uid == os.getuid() and not parent.st_mode & 0o022, 'authentication parent permissions')
    proc = subprocess.run(['/usr/bin/ssh-keygen', '-y', '-P', '', '-f', str(path)],
                          capture_output=True, timeout=5, env=ENV)
    require(proc.returncode == 0, 'identity unavailable for noninteractive authentication')
    parts = proc.stdout.split()
    require(len(parts) in (2, 3) and parts[0] == b'ssh-ed25519', 'Ed25519 identity required')
    after = path.stat()
    fields = ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_nlink', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    require(all(getattr(after, k) == getattr(info, k) for k in fields), 'authentication input changed')
    fingerprint = 'SHA256:'+base64.b64encode(hashlib.sha256(base64.b64decode(parts[1], validate=True)).digest()).decode().rstrip('=')
    return {'identity_file': str(path), 'public_fingerprint': fingerprint,
            'agent': 'none', 'method': 'publickey'}


def ssh(directory, spec):
    opts = ['IdentityAgent=none', 'IdentitiesOnly=yes', 'PreferredAuthentications=publickey',
            'PasswordAuthentication=no', 'KbdInteractiveAuthentication=no', 'BatchMode=yes', 'StrictHostKeyChecking=yes', 'HostKeyAlgorithms=ssh-ed25519',
            'UpdateHostKeys=no', 'ProxyCommand=none', 'ProxyJump=none', 'ControlMaster=no',
            'ControlPath=none', 'ControlPersist=no', 'PermitLocalCommand=no', 'ClearAllForwardings=yes',
            'ForwardAgent=no', 'ForwardX11=no', 'GlobalKnownHostsFile=/dev/null',
            'UserKnownHostsFile='+str(directory/'known_hosts'), 'HostKeyAlias=10.1.0.137',
            'ConnectTimeout=3', 'ConnectionAttempts=1', 'ServerAliveInterval=5', 'ServerAliveCountMax=1']
    return ['/usr/bin/ssh', '-F', '/dev/null', '-T', '-i', spec['authentication']['identity_file'], *[v for x in opts for v in ('-o', x)],
            'ama@10.1.0.51', "cd / && sudo -n /usr/bin/python3 -I -B -c 'import sys; exec(sys.stdin.buffer.readline())'"]


class Record:
    def __init__(self, directory):
        self.directory = directory; self.number = 0; self.total = 0

    def save(self, label, value):
        raw = encoded({'epoch': time.time(), 'monotonic': time.monotonic(), 'label': label, 'data': value})
        require(self.total+len(raw) <= 64*LIMIT, 'total evidence bound')
        self.number += 1; self.total += len(raw)
        create(self.directory/f'event-{self.number:04d}-{label}.json', raw)


def observe(spec, files, directory, record, mode, boot, timeout):
    require(mode != 'trigger', 'read-only observation only')
    h = module('helper', files['helper.py'])
    result = h.bounded(ssh(directory, spec), timeout=timeout, limit=LIMIT,
                       payload=payload(spec, files, mode, boot), env=ENV)
    record.save(mode, result)
    require(result.get('returncode') == 0 and not result.get('error'), 'observation failed')
    rows = [json.loads(line) for line in result['stdout'].splitlines() if line.strip()]
    require(len(rows) == 1 and rows[0].get('capture_complete') is not False, 'incomplete observation')
    return rows[0]


def clients(files, administrative=False):
    parser = module('client', files['client.py']); result = {}
    for endpoint in ('10.1.0.51', 'fd36:5aa8:6971:1::51'):
        family = socket.AF_INET6 if ':' in endpoint else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as s:
            s.settimeout(2); s.connect((endpoint, 123)); nonce = secrets.token_bytes(8)
            packet = bytearray(48); packet[0] = 0x23; packet[40:48] = nonce
            s.send(packet); result[endpoint] = parser.ntp_response(s.recv(512), nonce)
            if administrative:
                s.send(struct.pack('!BBHHHHH', 0x26, 2, 1, 0, 0, 0, 0))
                try: s.recv(512)
                except socket.timeout: result[endpoint]['queries_denied'] = True
                else: raise ValueError('external administrative response')
    return result


def sample(spec, files, directory, record, boot):
    start = time.monotonic()
    native = observe(spec, files, directory, record, 'health', boot, 10)
    packets = clients(files); record.save('clients', packets)
    require(time.monotonic()-start <= 10, 'combined health sample exceeds 10 seconds')
    return native, time.monotonic()


def stable_service(first, later):
    def state(v):
        raw = v['units']['timeservice.service']['stdout']
        pairs = [line.split('=', 1) for line in raw.splitlines() if '=' in line]
        row = dict(pairs)
        require(len(row) == len(pairs), 'duplicate service properties')
        return tuple(row.get(k) for k in ('MainPID', 'InvocationID', 'NRestarts'))
    require(first['boot'] == later['boot'] and state(first) == state(later), 'supervisor restarted')


def validate_operator(value, digest, now):
    fields = ('aaron_attending', 'console_identifies_j2', 'laptop_independent_power',
              'peer_serving', 'antenna_on_j1', 'j2_port_identified', 'recovery_card_available',
              'reservation_90_minutes', 'no_other_reset_actions', 'notes_ready')
    require(value.get('bundle_sha256') == digest and 0 <= now-value['epoch'] <= 300, 'operator record binding/freshness')
    require(all(value.get(k) is True for k in fields), 'operator prerequisites incomplete')
    require(isinstance(value.get('clock_uncertainty_seconds'), (int, float))
            and 0 <= value['clock_uncertainty_seconds'] <= 2, 'clock uncertainty')
    require(value.get('fallback_identity') == 'unknown-hold-powered-off'
            or (isinstance(value.get('fallback_identity'), str) and 1 <= len(value['fallback_identity']) <= 256), 'fallback identity disposition')


def trigger_channel(spec, files, directory, record, operator_path, digest):
    """Only this function can send a grant. READY without grant expires remotely."""
    create(directory/'armed.json', {'sha256': digest, 'epoch': time.time(), 'monotonic': time.monotonic()})
    launched = time.monotonic()
    proc = subprocess.Popen(ssh(directory, spec), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, start_new_session=True, env=ENV)
    output = {'stdout': bytearray(), 'stderr': bytearray()}
    pending = memoryview(payload(spec, files, 'trigger', json.loads(files['baseline.json'])['boot']))
    deadline = time.monotonic()+90; submitted = None; healthy = None
    try:
        with selectors.DefaultSelector() as poll:
            for name in ('stdout', 'stderr', 'stdin'):
                stream = getattr(proc, name); os.set_blocking(stream.fileno(), False)
                poll.register(stream, selectors.EVENT_WRITE if name == 'stdin' else selectors.EVENT_READ, name)
            while time.monotonic() < deadline and poll.get_map():
                for key, _ in poll.select(min(.25, max(0, deadline-time.monotonic()))):
                    if key.data == 'stdin':
                        if pending: pending = pending[os.write(key.fd, pending[:65536]):]
                        if not pending: poll.unregister(key.fileobj)
                        continue
                    data = os.read(key.fd, 65536)
                    if not data: poll.unregister(key.fileobj); continue
                    output[key.data].extend(data)
                    require(len(output[key.data]) <= LIMIT, 'trigger output bound')
                    if key.data == 'stdout' and b'\n' in output['stdout'] and submitted is None:
                        ready = json.loads(output['stdout'].split(b'\n')[0])
                        require(ready.get('ready') is True and re.fullmatch('[0-9a-f]{64}', ready['nonce']), 'worker readiness')
                        record.save('ready', ready)
                        packets = clients(files); record.save('final-clients', packets)
                        offset = ready['health_started_offset']
                        require(isinstance(offset, (int, float)) and 0 <= offset <= 90, 'health offset')
                        healthy = launched+offset-2  # Conservative lower bound, includes clock uncertainty.
                        require(0 <= time.monotonic()-healthy <= 10, 'final health stale')
                        validate_operator(json.loads(read(operator_path)), digest, time.time())
                        submitted = time.monotonic()
                        create(directory/'submitted.json', {'epoch': time.time(), 'monotonic': submitted,
                               'healthy_monotonic': healthy, 'sha256': digest})
                        record.save('submitted', {'nonce': ready['nonce'], 'monotonic': submitted})
                        grant = encoded({'nonce': ready['nonce'], 'operation_id': spec['operation_id'], 'action': 'panic-once'})
                        # One nonblocking write, never retry a partial or failed grant.
                        require(os.write(proc.stdin.fileno(), grant) == len(grant), 'partial grant; consumed')
                        proc.stdin.close(); deadline = submitted+5
                if proc.poll() is not None and submitted is None:
                    raise ValueError('worker exited before submission')
    finally:
        if proc.poll() is None:
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
        status = proc.wait()
        for stream in (proc.stdin, proc.stdout, proc.stderr):
            if stream and not stream.closed: stream.close()
        record.save('trigger-transport', {'returncode': status, **{k: bytes(v).decode('utf-8', 'replace') for k,v in output.items()}})
    require(submitted is not None, 'no submission; armed receipt remains consumed')
    return healthy, submitted


def evaluate_timing(healthy, confirmation, stamps, boot, initial_boot):
    require(boot != initial_boot, 'new boot required')
    require(len(stamps) >= 3 and all(b-a >= 30 for a,b in zip(stamps[-3:],stamps[-2:])), 'three spaced samples required')
    require(confirmation-healthy <= TIMING['health'], 'five-minute resilience failed')


def execute(directory, digest, operator_path):
    spec, files = prepare(directory, digest, window=True)
    require(spec['purpose'] == 'single-panic-watchdog-recovery', 'panic execution purpose required')
    operator_path = operator_path.absolute()
    operator = json.loads(read(operator_path)); validate_operator(operator, digest, time.time())
    require(authentication(spec['authentication']['identity_file']) == spec['authentication'], 'authentication identity drift')
    # Receipt precedes all target contact, including preflight. It is never deleted.
    create(directory/'execution.json', {'sha256': digest, 'epoch': time.time(), 'monotonic': time.monotonic(),
                                      'operator_record': operator, 'operator_sha256': sha(read(operator_path))})
    record = Record(directory); initial = json.loads(files['baseline.json'])['boot']
    result = {'execution_accepted': False, 'operator_acceptance_pending': True, 'trigger_attempted': False}
    try:
        start = time.monotonic()
        baseline = observe(spec, files, directory, record, 'full', initial, 120)
        first = None
        for i in range(3):
            if i: time.sleep(30)
            value, _ = sample(spec, files, directory, record, initial)
            if first is None: first = value
            stable_service(first, value)
        require(time.monotonic()-start <= 900, 'stale preflight')
        htime, submit = trigger_channel(spec, files, directory, record, operator_path, digest)
        result['trigger_attempted'] = True
        boot = None; stamps = []; first = None; new_boot = None
        while time.monotonic() < htime+300:
            loop = time.monotonic()
            try:
                observed = observe(spec, files, directory, record, 'boot', None, 3)['boot']
                if observed == initial: raise ValueError('old boot still running')
                if new_boot is None: new_boot = observed
                require(new_boot == observed, 'unplanned second reset')
                boot = observed
                value, finished = sample(spec, files, directory, record, boot)
                if first is None: first = value
                stable_service(first, value)
                if not stamps or finished-stamps[-1] >= 30: stamps.append(finished)
                if len(stamps) >= 3: break
            except (ValueError, OSError, TimeoutError) as error:
                record.save('health-not-ready', {'error': str(error)})
                if 'second reset' in str(error) or 'supervisor restarted' in str(error): raise
                stamps = []; first = None
            if time.monotonic() >= submit+120 and boot is None:
                raise ValueError('120-second escalation: use attended console plan')
            time.sleep(max(0, 5-(time.monotonic()-loop)))
        confirmation = time.monotonic()
        evaluate_timing(htime, confirmation, stamps, boot, initial)
        result['five_minute_health'] = True
        record.save('health-restored', {'H': htime, 'C': confirmation, 'boot': boot, 'samples': stamps})
        deadline = confirmation+1800; last = confirmation
        while last < deadline:
            time.sleep(max(0, min(last+60, deadline)-time.monotonic()))
            value, finished = sample(spec, files, directory, record, boot)
            stable_service(first, value)
            require(finished-last <= 75 and finished-submit <= 2700, 'stability gap/deadline')
            last = finished
        final = observe(spec, files, directory, record, 'full', boot, 120)
        require({k: v['sha256'] for k,v in final['native_tools'].items()} ==
                {k: v['sha256'] for k,v in baseline['native_tools'].items()}, 'native executable drift')
        record.save('final-clients-and-denial', clients(files, administrative=True))
        record.save('reconciliation', {'before': baseline['network'], 'after': final['network'],
                                      'operator_comparison_required': True})
        require(time.monotonic()-submit <= 2700, 'automatic work cap')
        result.update(stability_complete=True, new_boot=boot, hardware_attribution='pending independent KVM evidence',
                      restoration='no persistent changes; compare captured configuration/network before acceptance')
    except (Exception, KeyboardInterrupt) as error:
        result.update(error=str(error), held=True, no_retry=True)
    finally:
        result['trigger_attempted'] = (directory/'submitted.json').exists()
        result['armed'] = (directory/'armed.json').exists()
        create(directory/'result.json', result)
    return result


def inspect_journal(directory, digest):
    spec, files = prepare(directory, digest, window=True)
    require(spec['purpose'] in ('watchdog-error-journal', 'watchdog-journal-inputs'), 'journal inspection purpose required')
    require(authentication(spec['authentication']['identity_file']) == spec['authentication'], 'authentication identity drift')
    create(directory/'execution.json', {'sha256': digest, 'epoch': time.time(), 'purpose': spec['purpose']})
    record = Record(directory)
    result = {'capture_complete': False, 'production_accepted': False, 'trigger_attempted': False}
    try:
        mode = 'journal-inputs' if spec['purpose'] == 'watchdog-journal-inputs' else 'journal'
        capture = observe(spec, files, directory, record, mode, json.loads(files['baseline.json'])['boot'], 100 if mode == 'journal-inputs' else 40)
        require(capture.get('operation_id') == spec['operation_id'] and capture.get('capture_complete') is True,
                'journal capture binding')
        result['capture_complete'] = True
    except (Exception, KeyboardInterrupt) as error:
        result.update(error=str(error), held=True, no_retry=True)
    create(directory/'result.json', result)
    return result


def journal_review(spec):
    return f"""# Read-only current-boot error journal inspection

Sealed, unexecuted; exact-hash approval required. Operation {spec['operation_id']}.
Target only j2-svntp1 at ama@10.1.0.51, strict Ed25519 host alias 10.1.0.137.
Expires epoch {spec['expires_epoch']}; conservative shared validity check requires
90 minutes remaining. No target contact is authorized by preparation.

## Exact scope

One isolated Python worker through noninteractive sudo. Check root/hostname and
/proc/sys/kernel/random/boot_id before and after one journal command:
`/usr/bin/journalctl -b -p 0..3 --quiet --no-pager -o json -n 200`.
Require the accepted baseline boot ID; drift stops without journal capture.
Capture at most the latest 200 priority 0–3 current-boot entries, not all journals.
The command is limited to ten seconds and 1 MiB per stream; worker alarm 30 seconds,
controller 40 seconds and retained SSH stream 1 MiB. A bound failure is incomplete.
Journal messages/metadata may contain sensitive operational data; retain privately.
No automatic classification, remediation or acceptance of nonempty entries.
A later snapshot cannot prove exactly which entries existed during the failed v2.

External identity: `{spec['authentication']['identity_file']}`; public fingerprint
`{spec['authentication']['public_fingerprint']}`. Local owner/mode/link checks and
noninteractive availability precede the one-use receipt. No private key contents
are bundled or logged. Agent/password/keyboard-interactive authentication disabled.

The shared controller contains panic support, but the inspect entrypoint requires
journal purpose and calls only journal mode. The panic execute entrypoint rejects
this purpose before operator processing or a receipt. No operator attendance is
needed for this non-mutating inspection. No sync, device open, service action,
panic, reboot, notification, journal flush/rotation, installation or retry.
Only routine SSH/sudo/journal access logging is possible. Existing services continue.

## Evidence and next decision

Exclusive fsynced receipt precedes SSH. Retain command output, status, exceptions
and partial results. Require both boot IDs to match and bounded command success.
A complete capture is not a healthy-host or recovery acceptance. Assess each entry's
time, unit and relevance before deciding whether correction or a reviewed baseline
exception is appropriate. Preserve the current panic guard until that decision.
The earlier readiness inspection explicitly excluded journal bodies; its acceptance
never established this later-added strict zero-error condition. Qualified OBS-02
and D1–D5, bounded OBS-04 and five-minute recovery remain unchanged; OBS-09 unstarted.

After separate approval, from homelab-server-configs:
`python3 -I -B watchdog/scripts/run-panic-recovery.py inspect --directory {spec['directory']} --sha256 APPROVED_SHA256`
"""


def inputs_review(spec):
    return f"""# Read-only watchdog journal policy inputs

Sealed, unexecuted. Exact-hash execution approval required for {spec['operation_id']}.
Expires epoch {spec['expires_epoch']}; shared validity check requires 90 minutes remaining.
Target j2-svntp1 only, ama@10.1.0.51 with strict Ed25519 alias 10.1.0.137.

## Scope and prerequisites

Require accepted boot/root/hostname. Before and after collection, read only
systemctl show timeservice.service properties MainPID, InvocationID,
ExecMainStartTimestampMonotonic and NRestarts; ps -eo pid,ppid,comm; the single
ntpd child's /proc/PID/exe link and /proc/PID/stat; local SC_CLK_TCK. Require the
expected supervisor parent/executable and unchanged child birth/invocation.
No environment, credentials, device contents or broad filesystem traversal.

Read metadata and at most 64 KiB of the exact vendor file
/usr/lib/udev/rules.d/90-alsa-restore.rules and same-named /etc/udev/rules.d and
/run/udev/rules.d overrides. Record symlink targets without traversing them.
Read dpkg-query -S ownership for the vendor path and dpkg-query -W package,
version, source/version and installation status for alsa-utils and udev.
This does not establish all possible differently named or /usr/local rule overrides.
Repeat only the bounded current-boot priority 0–3 journal query, latest 200
JSON records, with boot continuity. A reached cap cannot pass policy assessment.
Retain privately; messages and metadata may contain sensitive operational data.

Also read installed package/version/status inventory with dpkg-query -W and
held selections with dpkg --get-selections. Run apt-get --simulate upgrade against
existing local indexes only, with Debug::NoLocking=1 and both binary cache paths
empty. This is a 30-second simulation, not an upgrade or metadata refresh.
Retain proposed/kept-back package output; it may differ from Webmin and may be
stale. Compare root-owned dpkg status hash/metadata and at most 256 direct APT-list
entry metadata records before/after. Read metadata only for apt history.log,
history.log.1.gz, dpkg.log, dpkg.log.1 and reboot-required markers. Do not read
history bodies, sources/credentials or remote repositories. Metadata timestamps
cannot establish when every pending update first became available.

Worker alarm 90 seconds; controller 100 seconds; other commands ten seconds and
1 MiB per stream; controller SSH output 1 MiB. Failed commands/completed partial
fields are retained. Capture failure never accepts a host or panic. The locally
qualified policy assessment reuses the accepted NTP classifier with current PID,
process-start monotonic time and invocation; it leaves all udev errors unresolved.

External identity `{spec['authentication']['identity_file']}`, public fingerprint
`{spec['authentication']['public_fingerprint']}`. Validate local key properties
before the exclusive fsynced receipt; agent/password/keyboard-interactive auth
are disabled. No private key contents are bundled or logged. No automatic retry.
The inspect entrypoint cannot invoke panic; panic execution rejects this purpose.
No package/configuration changes, udev reload/test/trigger, sync, reboot, service
restart, notification or failure injection. Normal access logging may occur.

## Acceptance and disposition

Complete capture requires bound target/boot, stable process context and successful
bounded reads; it does not require the diagnostic policy result to be healthy.
Assess installed rule bytes/version against Debian bug 1104719 and determine
whether the two errors have the same cause. Do not infer local impact or waive
errors solely from that upstream report. Assess the operator-reported update backlog and reconcile the commissioning
package baseline before choosing correction or a narrow evidenced exception.
Kernel/systemd updates require renewed source/reset-path qualification; no new panic seal before disposition and read-only policy
qualification. Preserve OBS-02/D1–D5, bounded OBS-04 and five-minute resilience.

After approval, from homelab-server-configs:
`python3 -I -B watchdog/scripts/run-panic-recovery.py inspect --directory {spec['directory']} --sha256 APPROVED_SHA256`
"""


def validate(spec):
    auth = spec['authentication']
    require(set(auth) == {'identity_file', 'public_fingerprint', 'agent', 'method'}
            and Path(auth['identity_file']).is_absolute() and auth['agent'] == 'none'
            and auth['method'] == 'publickey'
            and re.fullmatch(r'SHA256:[A-Za-z0-9+/]{43}', auth['public_fingerprint']), 'authentication contract')
    require(spec['schema'] == 1 and spec['purpose'] in ('single-panic-watchdog-recovery', 'watchdog-error-journal', 'watchdog-journal-inputs'), 'scope')
    require(spec['hostname'] == 'j2-svntp1' and spec['endpoints'] == ['10.1.0.51','fd36:5aa8:6971:1::51'], 'target')
    require(spec['kernel_release'] == '6.18.50+rpt-rpi-v8' and spec['timing'] == TIMING, 'qualified policy')
    require(spec['expires_epoch']-spec['prepared_epoch'] == 86400, 'validity')
    prefix = spec['purpose'] if spec['purpose'].startswith('watchdog-') else 'watchdog-panic-recovery'
    require(re.fullmatch(prefix+r'-[0-9]{8}-v[0-9]+', spec['operation_id']), 'operation identity')


def review(spec):
    if spec['purpose'] == 'watchdog-journal-inputs': return inputs_review(spec)
    if spec['purpose'] == 'watchdog-error-journal': return journal_review(spec)
    return f'''# Single controlled-panic watchdog execution/recovery review

Sealed, unexecuted; separate approval of this archive's SHA-256 is required.
Operation `{spec['operation_id']}` targets j2-svntp1 only. Expiry epoch
{spec['expires_epoch']}; start with at least 90 minutes remaining. No execution
occurred during preparation. See the bundled `contract.md` for mechanism,
independent evidence, timing and attended manual-recovery branches.

## Exact executable scope

The controller streams frozen Python to strict-key `ama@10.1.0.51`, alias
10.1.0.137, using noninteractive sudo and isolated system Python. Nothing is
installed. Authentication uses external private identity
`{spec['authentication']['identity_file']}` with public fingerprint
`{spec['authentication']['public_fingerprint']}`. The key is not bundled, hashed,
or logged. Local ownership/mode/link checks and noninteractive public-key
extraction must pass before the execution receipt. Agent, password and keyboard
interactive authentication are disabled; only this explicit identity is offered.
Every observation and the trigger channel use the same restricted SSH options.
Local qualification does not establish server acceptance. The consumed v1
attempt failed SSH authentication before remote execution and must not be replayed.
The sole destructive path runs sync once, rechecks native/ownership
and health, emits a nonce, and waits at most eight seconds for the controller's
single grant. It then opens /proc/sysrq-trigger once and writes ASCII c once.
No grant, EOF, stale state, nonce mismatch or expired window exits without a
panic. Any uncertain submission consumes the attempt; no automatic replay.

Read scopes are exact in worker.py: retained boot and four protected file hashes,
manager/drop-in policy, bounded descriptor metadata and watchdog sysfs from the
existing inspectors; installed kernel config hash, kgdboc/boot options/panic=0;
core/leap unit metadata; native NTP localhost variables and counts for five
associations; selected process PID/parent, executable links and all UID/GID values, GPSD fd
metadata for serial0/PPS ownership (no device opens); root/boot mounts,
statvfs, thermal_zone0, vcgencmd get_throttled; addresses, routes, DNS runtime and
listeners; current NTP child /proc/PID/stat and clock ticks, supervisor monotonic
start/invocation around journal capture; current-boot error journal capped at 200 records, existing leap journal
capped at 60, the two existing retention/reporting last-success JSON records,
and hashes/metadata of ntpq, ntpd and gpsd. No credential contents,
private NTS cookies, GPS device reader, package action or forced maintenance job.

Current-boot errors are classified using the existing bounded NTP startup policy,
with fresh child/start/invocation provenance. Other errors, malformed records,
reached record caps or any sticky throttling flag stop preflight for assessment.
Native NTP checks use the existing measurement and cutover acceptance code.
Each health sample additionally sends one NTP request to each fixed IP family;
final reconciliation alone adds one administrative-denial probe per family.
No peer/master/controller access, test message, network setting or policy change.
Existing scheduled jobs/alerts remain enabled and may respond to the outage.

## State, timing and independent evidence

Exclusive fsynced execution receipt precedes target contact; armed and submitted
receipts survive interruption. There is no execute-resume or retry command.
Submission uncertainty cannot be resolved by another panic. The worker has an
independent alarm; after READY the grant expires in eight seconds. Controller
loss before grant leaves the machine running; loss after a possible grant hands
over to attended KVM recovery, with attribution unproved until reviewed.

Bounded SSH reconnection is read-only: once per five seconds, three-second boot
query limit. Native/client health sample <=10 seconds; require three consecutive
healthy observations >=30 seconds apart within 300 seconds of the final healthy
baseline. The destructive-channel baseline conservatively uses controller launch time plus
worker elapsed time before native health began, minus two seconds uncertainty.
Transport/startup delay therefore lengthens the measured outage bound. Reject
submission if this baseline is more than ten seconds old.
Observed reset bound is 30 seconds from independently confirmed panic, with
<=2 seconds observation uncertainty; hardware timing expectation is not a guarantee.
At 120 seconds without a new boot, automatic work stops for console escalation.
After healthy recovery, observe 30 minutes at 60-second cadence, gaps <=75 seconds.
Total automatic work <=45 minutes after submission. Hardware attribution and
network/record reconciliation require human review; controller completion alone
never marks recovery accepted or begins OBS-09.

Per command/stream <=1 MiB; aggregate saved events <=64 MiB; full capture <=120
seconds; sync <=30 seconds; trigger channel <=90 seconds plus five seconds of
post-submission transport capture. Worker native health alarm is ten seconds.
All raw evidence is local/private. SSH/sudo and reads may create routine logs.
All exact source/input hashes are in spec.json; no historical code is imported.

Aaron's operator-record.json must be completed freshly for this exact archive:
attendance, identified KVM/laptop, peer and antenna continuity, identified j2
PoE connection, working fallback card, available 90 minutes, independent notes
and <=2-second clock uncertainty. Unknown old-card identity means hold powered
off pending a separate recovery disposition. The record is an execution-time
observation, never a substitute for execution approval. Record panic/reset KVM
event bounds and interventions separately as described in operator-notes.md.

## Restoration and limits

No persistent target artifacts are created and no configuration rollback is
needed. A panic can lose writes or damage media; automatic recovery is not assured.
On failure Aaron may perform only the contract's node-only physical PoE recovery
once with the current card, followed by its guarded previous-card fallback.
No switch API, debugger reboot, second panic, filesystem repair, reimage, shared
power action or service/configuration change is authorized by this scope.
Intervention before reset makes expiry attribution inconclusive. Late recovery
cannot pass five-minute resilience. Preserve both cards, logs and consumed receipt.

OBS-02/D1–D5 and bounded OBS-04 unchanged; OBS-09 unstarted. Native hardware
recovery and console attribution remain live qualification, not local test results.

After exact-hash approval and fresh operator confirmation, from the repository:
`python3 -I -B watchdog/scripts/run-panic-recovery.py execute --directory {spec['directory']} --sha256 APPROVED_SHA256 --operator-record {spec['directory']}/operator-record.json`
'''


def prepare(directory, digest, window=False):
    directory = private_dir(directory); raw = read(directory/'execution.tar')
    require(sha(raw) == digest, 'archive SHA mismatch')
    expected = set(SOURCES) | {'spec.json','review.md','baseline.json','known_hosts','operator-template.json','operator-notes.md','qualification.json'}
    with tarfile.open(fileobj=io.BytesIO(raw)) as a:
        rows = a.getmembers()
        require(len(rows) == len(expected) and {m.name for m in rows} == expected
                and all(m.isfile() and m.size <= LIMIT for m in rows), 'closed bounded archive')
        files = {m.name: a.extractfile(m).read() for m in rows}
    spec = json.loads(files['spec.json']); validate(spec)
    require(spec['directory'] == str(directory) and spec['operation_id'] == directory.name, 'directory binding')
    require(files['review.md'] == review(spec).encode(), 'review binding')
    require(spec['members'] == {k: sha(v) for k,v in files.items() if k not in ('spec.json','review.md')}, 'member hash')
    for name, source in SOURCES.items(): require(files[name] == source.read_bytes(), 'repository source drift: '+name)
    for name in expected: require(read(directory/name) == files[name], 'local artifact drift: '+name)
    if window: require(spec['prepared_epoch']-300 <= time.time() < spec['expires_epoch']-5400, 'execution window')
    return spec, files


def seal(directory, baseline, readiness, assessment, qualification, identity_file, scope="panic"):
    require(not directory.exists(), 'existing operation directory')
    outcome = json.loads(read(baseline/'outcome.json'))
    require(outcome.get('capture_accepted') is True and outcome.get('debugger_transport_gap_resolved') is True, 'accepted debugger baseline')
    for name,digest in outcome['evidence_sha256'].items():
        require(Path(name).name == name and sha(read(baseline/name,32*LIMIT)) == digest, 'baseline evidence drift')
    ready_outcome = json.loads(read(readiness/'outcome.json'))
    require(ready_outcome.get('capture_accepted') is True, 'accepted readiness baseline')
    for name, digest in ready_outcome['evidence_sha256'].items():
        require(Path(name).name == name and sha(read(readiness/name,32*LIMIT)) == digest, 'readiness evidence drift')
    ready_capture = json.loads(read(readiness/'stdout.txt'))
    comparison = json.loads(read(assessment/'config-comparison.json'))
    require(comparison.get('matches') is True and comparison['published_sha256'] == comparison['captured_sha256'], 'exact config mapping')
    require(sha(read(assessment/'published-kernel.config')) == comparison['published_sha256'], 'published config changed')
    capture = json.loads(read(baseline/'stdout.txt'))
    require(capture['capture_complete'], 'incomplete baseline')
    files = {n:p.read_bytes() for n,p in SOURCES.items()}
    proof = json.loads(read(qualification))
    require(proof.get('qualified_sources') == {n:sha(raw) for n,raw in files.items()}, 'qualification source drift')
    require(proof.get('panic_tests_exit') == 0 and proof.get('inspection_tests_exit') == 0
            and proof.get('target_contact') is False, 'local guard qualification required')
    files['qualification.json'] = encoded(proof)
    with tarfile.open(fileobj=io.BytesIO(read(baseline/'inspection.tar'))) as a:
        files['known_hosts'] = a.extractfile('known_hosts').read()
    require(re.fullmatch(rb'10\.1\.0\.137 ssh-ed25519 [A-Za-z0-9+/=]+\n?', files['known_hosts']), 'host pin')
    base = {'boot': capture['boot_after'], 'protected': {k:v['sha256'] for k,v in capture['protected_after'].items()},
            'configuration': capture['configuration_after'],
            'manager': dict(x.split('=',1) for x in capture['manager_after']['stdout'].splitlines()),
            'watchdog': {k:v['text'] for k,v in capture['watchdog_sysfs'].items()},
            'kernel_config_sha256': comparison['captured_sha256'],
            'systemd_version': ready_capture['readiness_commands']['systemd_version']['stdout'],
            'source_assessment': {name:sha(read(assessment/name)) for name in ('assessment.md','assessment-manifest.json','config-comparison.json')},
            'readiness_outcome_sha256': sha(read(readiness/'outcome.json')),
            'credentials': {'ntpd':['999','985'], 'gpsd':['65534','20']},
            'accepted_outcome_sha256': sha(read(baseline/'outcome.json')),
            'evidence_sha256': outcome['evidence_sha256']}
    files['baseline.json'] = encoded(base)
    files['operator-template.json'] = encoded({'bundle_sha256':'FILL_FROM_SEAL','epoch':0,
        **{k:False for k in ('aaron_attending','console_identifies_j2','laptop_independent_power','peer_serving','antenna_on_j1',
        'j2_port_identified','recovery_card_available','reservation_90_minutes','no_other_reset_actions','notes_ready')},
        'clock_uncertainty_seconds':None,'fallback_identity':'unknown-hold-powered-off'})
    files['operator-notes.md'] = b'''# Independent operator record\n\nBefore execute, copy operator-template.json to private operator-record.json and\ncomplete it from Aaron's fresh confirmation. Never fill boolean observations by\nassumption. Epoch must be within five minutes when checked, including before grant.\nRetain UTC/monotonic clock correlation and any clock disagreement.\n\nRecord host identification, panic text, reset/boot transitions and interventions\nas earliest/latest elapsed bounds relative to submitted.json monotonic time.\nDo not derive a panic time from SSH loss. Video optional. No KVM event evidence\nmeans attribution stays inconclusive. Preserve original notes privately.\n\nReview reset.latest - panic.earliest <=30 seconds including <=2 seconds timing\nuncertainty, no alternate reset/power intervention, native path exclusions, new\nboot and health. Read result.json plus every failed/partial sample. No automatic\nacceptance or retry. At failure Aaron owns the console/card recovery or explicit\nhold, with next attended check within 60 minutes.\n'''
    auth = authentication(identity_file)
    now = int(time.time()); spec = {'schema':1,'purpose':{'journal':'watchdog-error-journal','inputs':'watchdog-journal-inputs','panic':'single-panic-watchdog-recovery'}[scope],'operation_id':directory.name,
        'authentication':auth,'directory':str(directory),'prepared_epoch':now,'expires_epoch':now+86400,
        'hostname':'j2-svntp1','endpoints':['10.1.0.51','fd36:5aa8:6971:1::51'],
        'kernel_release':'6.18.50+rpt-rpi-v8','timing':TIMING,'members':{k:sha(v) for k,v in files.items()}}
    validate(spec); files.update({'spec.json':encoded(spec),'review.md':review(spec).encode()})
    directory.mkdir(mode=0o700)
    for name,raw in files.items(): create(directory/name,raw)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer,mode='w',format=tarfile.USTAR_FORMAT) as a:
        for name,raw in sorted(files.items()):
            m=tarfile.TarInfo(name);m.size=len(raw);m.mode=0o600;a.addfile(m,io.BytesIO(raw))
    create(directory/'execution.tar',buffer.getvalue()); digest=sha(buffer.getvalue()); prepare(directory,digest)
    result={'sha256':digest,'execution_ready':True,'execution_approved':False,'target_contact':False,'expires_epoch':spec['expires_epoch']}
    create(directory/'sealing.json',result); return result


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__); sub=parser.add_subparsers(dest='action',required=True)
    p=sub.add_parser('seal');p.add_argument('--directory',type=Path,required=True);p.add_argument('--baseline',type=Path,required=True);p.add_argument('--readiness',type=Path,required=True);p.add_argument('--assessment',type=Path,required=True);p.add_argument('--qualification',type=Path,required=True);p.add_argument('--identity-file',type=Path,required=True);p.add_argument('--scope',choices=('panic','journal','inputs'),default='panic')
    for action in ('check','execute','inspect'):
        p=sub.add_parser(action);p.add_argument('--directory',type=Path,required=True);p.add_argument('--sha256',required=True)
        if action=='execute':p.add_argument('--operator-record',type=Path,required=True)
    args=parser.parse_args(); directory=args.directory.absolute()
    if args.action=='seal':result=seal(directory,args.baseline.absolute(),args.readiness.absolute(),args.assessment.absolute(),args.qualification.absolute(),args.identity_file.absolute(),args.scope)
    elif args.action=='check':prepare(directory,args.sha256);result={'integrity':True,'target_contact':False}
    elif args.action=='inspect':result=inspect_journal(directory,args.sha256)
    else:result=execute(directory,args.sha256,args.operator_record)
    print(json.dumps(result,sort_keys=True))
    if args.action in ('execute','inspect') and result.get('held'):raise SystemExit(1)


if __name__=='__main__':main()
