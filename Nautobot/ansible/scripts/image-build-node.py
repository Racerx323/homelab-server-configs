#!/usr/bin/env python3
"""Bounded image worker and independent root watchdog; invoked only by reviewed units."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time

GIB = 1024**3
AUDIT = None
ERRORS = re.compile(r'reset.*USB|USB.*reset|I/O error|EXT4-fs error|Buffer I/O|uas.*(?:abort|error)|under.voltage|out of memory|oom-kill', re.I)


def capture(argv, timeout=10, limit=262144, env=None, observer=None):
    """Bound both streams while draining; kill process group on any failure."""
    p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=env)
    sel = selectors.DefaultSelector()
    data = {'out': bytearray(), 'err': bytearray()}
    for stream, name in [(p.stdout, 'out'), (p.stderr, 'err')]:
        sel.register(stream, selectors.EVENT_READ, name)
    started_at = time.time()
    deadline = time.monotonic() + timeout
    try:
        while sel.get_map():
            if time.monotonic() >= deadline:
                raise RuntimeError('command_timeout')
            for key, _ in sel.select(.1):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    sel.unregister(key.fileobj)
                else:
                    data[key.data].extend(chunk)
                    if len(data[key.data]) > limit:
                        raise RuntimeError('output_limit')
        rc = p.wait(timeout=max(.01, deadline-time.monotonic()))
        if rc:
            raise RuntimeError('command_failed:' + Path(argv[0]).name + ':' + str(rc))
        return bytes(data['out']).decode('utf-8', errors='strict')
    except BaseException:
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        raise
    finally:
        if AUDIT is not None:
            record = {'argv':argv, 'started':started_at, 'finished':time.time(), 'rc':p.returncode,
                      'stdout':bytes(data['out']).decode(errors='replace'),
                      'stderr':bytes(data['err']).decode(errors='replace')}
            with AUDIT.open('a') as log:
                log.write(json.dumps(record)+'\n'); log.flush(); os.fsync(log.fileno())
            if AUDIT.stat().st_size > 32*1024**2:
                raise RuntimeError('command_evidence_limit')
        sel.close()
        p.stdout.close()
        p.stderr.close()
        if observer is not None:
            observer(p.returncode, bytes(data['out']), bytes(data['err']))


def save(path, value):
    with path.open('x', encoding='utf-8') as f:
        json.dump(value, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())


def limits(path):
    if (path/'memory.max').read_text().strip() != str(3*GIB):
        raise RuntimeError('memory_limit_not_effective')
    if (path/'memory.swap.max').read_text().strip() != '0':
        raise RuntimeError('swap_limit_not_effective')
    quota, period = (path/'cpu.max').read_text().split()
    if quota == 'max' or int(quota) != 2*int(period):
        raise RuntimeError('cpu_limit_not_effective')


def cgroup():
    rows = Path('/proc/self/cgroup').read_text().splitlines()
    if len(rows) != 1 or not rows[0].startswith('0::/system.slice/nautobot-image-'):
        raise RuntimeError('unexpected_worker_cgroup')
    return rows[0][3:]


def podman(root):
    return ['/usr/bin/podman', '--cgroup-manager=cgroupfs', '--root='+str(root/'work/store'),
            '--runroot='+str(root/'work/run'), '--storage-driver=overlay',
            '--events-backend=file']


def worker(root, spec):
    if os.getuid() != 999 or os.getgid() != 985 or os.uname().machine != 'aarch64':
        raise RuntimeError('worker_identity')
    parent = cgroup()
    cg = Path('/sys/fs/cgroup'+parent)
    limits(cg)
    # The service parent distributes domain controllers and cannot host processes.
    (cg/'worker').mkdir()
    (cg/'worker/cgroup.procs').write_text(str(os.getpid()))
    (cg/'cgroup.subtree_control').write_text('+cpu +memory +pids')
    if not {'cpu','memory','pids'} <= set((cg/'cgroup.subtree_control').read_text().split()):
        raise RuntimeError('delegation_incomplete')
    if (cg/'cgroup.procs').read_text().strip():
        raise RuntimeError('parent_not_empty')
    # Buildah assigns this path directly to OCI linux.cgroupsPath. Use an empty
    # leaf, not the controller-distributing service parent. Runtime creates it.
    build_leaf = parent+'/build'
    if (cg/'build').exists():
        raise RuntimeError('build_leaf_already_exists')
    save(root/'work/cgroup-layout.json', {'parent':parent, 'worker':parent+'/worker',
         'build_leaf':build_leaf, 'parent_limits_verified':True})
    for name, digest in spec['input_sha256'].items():
        p = root/'input'/name
        if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest() != digest:
            raise RuntimeError('input_drift')
    # New, exclusive store: neither inspect nor modify the default runtime store.
    for name in ['store', 'run', 'tmp']:
        (root/'work'/name).mkdir(mode=0o700)
    os.environ.clear()
    os.environ.update(HOME='/var/lib/nautobot', PATH='/usr/bin:/bin', LANG='C.UTF-8',
                      XDG_RUNTIME_DIR='/run/user/999', TMPDIR=str(root/'work/tmp'))
    auth = root/'work/auth.json'
    auth.write_text('{"auths":{}}\n')
    cmd = podman(root)
    base = spec['base_image']
    capture(cmd+['pull', '--authfile='+str(auth), '--platform=linux/arm64', '--tls-verify=true', base], 900, 4*1024**2)
    base_info = json.loads(capture(cmd+['image', 'inspect', base]))
    if len(base_info) != 1 or base_info[0].get('Architecture') != 'arm64' or base_info[0].get('Os') != 'linux':
        raise RuntimeError('base_platform')
    # cgroupfs and an explicit delegated parent prevent systemd sibling scopes.
    capture(cmd+['build', '--authfile='+str(auth), '--platform=linux/arm64', '--isolation=oci', '--cgroup-parent='+build_leaf,
                 '--cgroupns=host', '--pull=never', '--jobs=1', '--no-cache', '--layers=false',
                 '--http-proxy=false', '--network=private', '--iidfile='+str(root/'work/image.id'),
                 '--tag=localhost/nautobot-homelab:qualification-'+spec['id'], str(root/'input')], 1800, 4*1024**2)
    image_id = (root/'work/image.id').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image_id):
        raise RuntimeError('image_id_invalid')
    info = json.loads(capture(cmd+['image', 'inspect', image_id]))
    if len(info) != 1 or info[0].get('Architecture') != 'arm64' or info[0].get('Os') != 'linux':
        raise RuntimeError('output_platform')
    run = cmd+['run', '--rm', '--pull=never', '--network=none', '--read-only',
               '--tmpfs=/tmp:rw,size=64m', '--cgroups=disabled', '--cap-drop=all',
               '--security-opt=no-new-privileges', '--entrypoint=python3', image_id]
    code = ("import importlib.metadata as m,json; "
            "v={p:m.version(p) for p in ['nautobot','nautobot-dns-models']}; "
            "assert v=={'nautobot':'3.2.3','nautobot-dns-models':'2.3.0'},v; print(json.dumps(v))")
    versions = json.loads(capture(run+['-c', code], 60))
    if versions != {'nautobot':'3.2.3','nautobot-dns-models':'2.3.0'}:
        raise RuntimeError('package_version_mismatch')
    capture(run+['-m', 'pip', 'check'], 60)
    # Command discovery only: no migrations, servers, Jobs or database instances.
    help_run = run[:-2]+['--entrypoint=nautobot-server', image_id]
    for args in [['--help'], ['start', '--help'], ['celery', '--help']]:
        capture(help_run+args, 60)
    archive = root/'work/image.oci.tar'
    capture(cmd+['save', '--format=oci-archive', '--output='+str(archive), image_id], 600)
    import tarfile
    with tarfile.open(archive) as t:
        index = json.load(t.extractfile('index.json'))
        descriptors = index['manifests']
        if len(descriptors) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', descriptors[0]['digest']):
            raise RuntimeError('archive_manifest')
        digest = descriptors[0]['digest']
        manifest_bytes = t.extractfile('blobs/sha256/'+digest[7:]).read()
        if hashlib.sha256(manifest_bytes).hexdigest() != digest[7:]:
            raise RuntimeError('manifest_digest_mismatch')
        manifest = json.loads(manifest_bytes)
        for blob in [manifest['config']] + manifest['layers']:
            algorithm, value = blob['digest'].split(':')
            if algorithm != 'sha256' or not re.fullmatch('[0-9a-f]{64}', value):
                raise RuntimeError('blob_digest_invalid')
            h = hashlib.sha256()
            stream = t.extractfile('blobs/sha256/'+value)
            for chunk in iter(lambda: stream.read(1024**2), b''):
                h.update(chunk)
            if h.hexdigest() != value:
                raise RuntimeError('blob_digest_mismatch')
        config = json.load(t.extractfile('blobs/sha256/'+manifest['config']['digest'][7:]))
        if config['architecture'] != 'arm64' or config['os'] != 'linux':
            raise RuntimeError('archive_platform')
    h = hashlib.sha256()
    with archive.open('rb') as f:
        for chunk in iter(lambda: f.read(1024**2), b''):
            h.update(chunk)
    save(root/'work/worker-result.json', {'result':'static_image_checks_passed', 'image_id':image_id,
         'oci_manifest_digest':digest, 'archive_sha256':h.hexdigest(), 'versions':versions,
         'runtime_accepted':False, 'production_store_loaded':False})


def health(root, boot, initial_errors, cursor):
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != boot:
        raise RuntimeError('boot_changed')
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(mem['MemAvailable'].split()[0])*1024
    temperature = int(Path('/sys/class/thermal/thermal_zone0/temp').read_text())
    errors = int(Path('/sys/fs/ext4/sda2/errors_count').read_text())
    free = os.statvfs(root).f_bavail*os.statvfs(root).f_frsize
    size = int(capture(['du', '-sx', '--block-size=1', str(root/'work')], 3).split()[0])
    if available < 1536*1024**2 or temperature > 80000 or free < 20*GIB or size > 30*GIB:
        raise RuntimeError('resource_guard')
    if errors != initial_errors or errors != 0:
        raise RuntimeError('filesystem_errors')
    if capture(['vcgencmd', 'get_throttled'], 2).strip() != 'throttled=0x0':
        raise RuntimeError('throttling')
    if capture(['systemctl', '--failed', '--no-legend', '--plain'], 2).strip():
        raise RuntimeError('failed_unit')
    journal = capture(['journalctl', '-k', '--after-cursor='+cursor, '--no-pager', '-o', 'json'], 3)
    for line in journal.splitlines():
        if line.startswith('{') and ERRORS.search(str(json.loads(line).get('MESSAGE', ''))):
            raise RuntimeError('kernel_storage_or_oom_event')
    return {'epoch':time.time(), 'mem_available':available, 'temperature_millic':temperature,
            'free_bytes':free, 'work_bytes':size, 'ext4_errors':errors}


def watch(root, spec):
    if os.getuid() != 0:
        raise RuntimeError('watchdog_requires_root')
    unit = 'nautobot-image-'+spec['id']+'.service'
    started = False
    passed = False
    reason = None
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    if boot != spec['boot_id']:
        raise RuntimeError('baseline_boot_drift')
    cursor_text = capture(['journalctl', '-k', '-b', '-n', '0', '--show-cursor', '--no-pager'])
    match = re.search(r'^-- cursor: (.+)$', cursor_text, re.M)
    if not match:
        raise RuntimeError('journal_cursor_missing')
    cursor = match[1]
    errors = int(Path('/sys/fs/ext4/sda2/errors_count').read_text())
    save(root/'evidence/before.json', {'boot':boot, 'cursor':cursor, 'ext4_errors':errors})
    deadline = time.monotonic()+2700
    previous = time.monotonic()
    try:
        health(root, boot, errors, cursor)
        started = True  # Even a timed-out start can have launched the worker.
        capture(['systemctl', 'start', unit], 15)
        with (root/'evidence/samples.jsonl').open('x') as log:
            while True:
                now = time.monotonic()
                if now-previous > 15 or now >= deadline:
                    raise RuntimeError('coverage_or_deadline')
                previous = now
                row = health(root, boot, errors, cursor)
                state = capture(['systemctl', 'show', unit, '-p', 'ActiveState,SubState,Result,ExecMainStatus,ControlGroup'], 2)
                fields = dict(x.split('=', 1) for x in state.splitlines())
                row['unit'] = fields
                log.write(json.dumps(row)+'\n'); log.flush(); os.fsync(log.fileno())
                if fields['ActiveState'] == 'active' and fields['SubState'] == 'running':
                    cg = Path('/sys/fs/cgroup'+fields['ControlGroup'])
                    limits(cg)
                    events = dict(x.split() for x in (cg/'memory.events').read_text().splitlines())
                    if int(events['oom']) or int(events['oom_kill']):
                        raise RuntimeError('build_oom')
                elif fields['ActiveState'] == 'inactive':
                    if fields['Result'] != 'success' or fields['ExecMainStatus'] != '0':
                        raise RuntimeError('worker_failed')
                    result = json.loads((root/'work/worker-result.json').read_text())
                    if result.get('result') != 'static_image_checks_passed':
                        raise RuntimeError('worker_result_missing')
                    # Preserve delayed-event coverage after successful command completion.
                    for _ in range(15):
                        time.sleep(5)
                        if time.monotonic()-previous > 15 or time.monotonic() >= deadline:
                            raise RuntimeError('coverage_or_deadline')
                        previous = time.monotonic()
                        row = health(root, boot, errors, cursor)
                        log.write(json.dumps(row)+'\n'); log.flush(); os.fsync(log.fileno())
                    passed = True
                    break
                elif fields['ActiveState'] != 'activating':
                    raise RuntimeError('worker_state')
                time.sleep(max(0, 5-(time.monotonic()-now)))
    except BaseException as exc:
        reason = str(exc)[:200]
    finally:
        stop_ok = True
        if started:
            try:
                capture(['systemctl', 'stop', unit], 20)
                state = capture(['systemctl', 'show', unit, '--property=ActiveState', '--value'], 2).strip()
                if state not in ['inactive', 'failed']:
                    raise RuntimeError('worker_not_stopped')
                cg = Path('/sys/fs/cgroup/system.slice')/unit
                if cg.exists() and 'populated 1' in (cg/'cgroup.events').read_text():
                    raise RuntimeError('worker_descendants_remain')
            except Exception:
                stop_ok = False
        save(root/'evidence/result.json', {'passed':passed and stop_ok, 'reason':reason,
             'stop_confirmed':stop_ok, 'artifacts_retained':True, 'runtime_accepted':False})
    if not passed or not stop_ok:
        raise RuntimeError('qualification_failed_review_evidence')


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['worker', 'watch']); p.add_argument('root', type=Path)
    args = p.parse_args()
    root = args.root
    if not re.fullmatch(r'/var/tmp/nautobot-image-[0-9a-f]{12}', str(root)) or root.is_symlink():
        raise RuntimeError('unsafe_operation_root')
    spec = json.loads((root/'spec.json').read_text())
    if root.name != 'nautobot-image-'+spec['id']:
        raise RuntimeError('operation_identity')
    global AUDIT
    AUDIT = root/('work' if args.mode == 'worker' else 'evidence')/'commands.jsonl'
    (worker if args.mode == 'worker' else watch)(root, spec)


if __name__ == '__main__':
    main()
