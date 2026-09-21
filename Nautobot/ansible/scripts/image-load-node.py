#!/usr/bin/env python3
"""Node assertions and per-command watchdog; Ansible owns image-load sequencing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import signal
import subprocess
import sys
import tempfile
import time
import importlib.util

_support = Path(__file__).with_name('bounded.py')
if not _support.exists():
    _support = Path(__file__).with_name('image-build-node.py')
_spec = importlib.util.spec_from_file_location('bounded', _support)
bounded = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bounded)
GIB = 1024**3
ERRORS = re.compile(r'reset.*USB|USB.*reset|I/O error|EXT4-fs (?:error|warning)|Buffer I/O|uas.*(?:abort|error)|under.voltage|out of memory|oom-kill|timed out.*(?:scsi|usb)|(?:scsi|usb).*timed out', re.I)
ENV = dict(PATH='/usr/sbin:/usr/bin:/sbin:/bin', HOME='/var/lib/nautobot', XDG_RUNTIME_DIR='/run/user/999', LC_ALL='C.UTF-8')
USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env', *[f'{k}={v}' for k,v in ENV.items()], '/usr/bin/podman']
FILES = ['postgresql.env', 'redis.env', 'migration.env', 'web.env', 'worker.env', 'scheduler.env', 'nautobot_config.py']


def require(ok, code):
    if not ok:
        raise RuntimeError(code)


def run(argv, timeout=20):
    return bounded.capture(argv, timeout=timeout, limit=1024*1024, env=ENV)


def pod(args):
    return run(USER + args)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def metadata(path, mode):
    st = path.lstat()
    require(not path.is_symlink() and st.st_uid == 999 and st.st_gid == 985 and st.st_mode & 0o777 == mode, 'file_metadata')
    return [st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns, st.st_mode, st.st_uid, st.st_gid]


def health(spec):
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == spec['boot_id'], 'boot_drift')
    mem = int(re.search(r'^MemAvailable:\s+(\d+)', Path('/proc/meminfo').read_text(), re.M)[1])*1024
    temp = int(Path('/sys/class/thermal/thermal_zone0/temp').read_text())
    free = os.statvfs('/var/lib/nautobot'); free = free.f_bavail*free.f_frsize
    throttle = run(['/usr/bin/vcgencmd', 'get_throttled']).strip()
    require(mem >= spec['min_available_bytes'] and temp < 80000 and free >= spec['min_free_bytes'] and throttle == 'throttled=0x0', 'resource_guard')
    return {'monotonic': time.monotonic(), 'available_bytes': mem, 'temperature_millic': temp, 'free_bytes': free, 'throttled': throttle}


def journal(cursor=None, full=False):
    args = ['journalctl', '-k', '-b', '--no-pager', '--output=json']
    if cursor:
        args += ['--after-cursor', cursor]
    elif not full:
        args += ['-n', '1']
    rows = [json.loads(x) for x in run(args).splitlines() if x]
    if cursor or full:
        require(not any(ERRORS.search(str(x.get('MESSAGE',''))) for x in rows), 'kernel_storage_or_health_event')
    else:
        require(bool(rows) and '__CURSOR' in rows[-1], 'journal_cursor_missing')
        return rows[-1]['__CURSOR']


def network_metadata(values):
    require(isinstance(values, list) and all(isinstance(v, dict) for v in values), 'network_metadata_shape')
    # Podman synthesizes the unused default network's creation time on each query.
    # Compare all configuration fields while excluding only this volatile timestamp.
    return [{k: v for k, v in item.items() if k != 'created'} for item in values]


def secret_metadata():
    # secret ls accepts a Go template, not the images/network JSON shortcut.
    names = pod(['secret', 'ls', '--format', '{{.Name}}']).strip().splitlines()
    require(names == ['nautobot-redis-config'], 'secret_identity')
    values = json.loads(pod(['secret', 'inspect', 'nautobot-redis-config']))
    require(isinstance(values, list) and len(values) == 1 and
            values[0].get('Spec', {}).get('Name') == 'nautobot-redis-config' and
            isinstance(values[0].get('ID'), str) and bool(values[0]['ID']) and
            'SecretData' not in values[0], 'secret_metadata_shape')
    return values


def inventory(spec):
    require(run(['hostnamectl','--static']).strip() == 'j2-svpi4mf' and os.uname().machine == 'aarch64', 'host_identity')
    account = pwd.getpwnam('nautobot')
    require((account.pw_uid,account.pw_gid,account.pw_dir) == (999,985,'/var/lib/nautobot'), 'account_identity')
    require(pod(['--version']).strip() == 'podman version 5.4.2', 'podman_version_drift')
    require(run(['systemctl','is-active','user@999.service']).strip() == 'active', 'user_manager')
    require(not run(['systemctl','--failed','--no-legend','--plain']).strip(), 'failed_units')
    info=json.loads(pod(['info','--format','json']))
    require(info['host']['security']['rootless'] is True and info['store']['graphRoot']=='/var/lib/nautobot/.local/share/containers/storage', 'runtime_store_identity')
    mount=json.loads(run(['findmnt','--json','--target','/var/lib/nautobot']))['filesystems']
    require(len(mount)==1 and mount[0]['source']=='/dev/sda2' and mount[0]['fstype']=='ext4','root_storage_identity')
    require(json.loads(pod(['ps','-a','--format','json'])) == [], 'existing_containers')
    require(json.loads(pod(['volume','ls','--format','json']) or '[]') == [], 'existing_volumes')
    nets = network_metadata(json.loads(pod(['network','ls','--format','json'])))
    require(all(n.get('Name',n.get('name')) == 'podman' for n in nets), 'existing_networks')
    home = Path('/var/lib/nautobot')
    require(home.is_dir() and not home.is_symlink() and home.stat().st_uid == 999, 'home_identity')
    require(not list((home/'.config/containers/systemd').glob('*.container')) and not list((home/'.config/containers/systemd').glob('*.volume')) and not list((home/'.config/containers/systemd').glob('*.network')), 'existing_quadlets')
    runtime = home/'runtime'; metadata(runtime,0o700)
    require(runtime.is_dir() and sorted(p.name for p in runtime.iterdir()) == sorted(FILES), 'runtime_file_set')
    files = {name:metadata(runtime/name,0o644 if name.endswith('.py') else 0o600) for name in FILES}
    require(all((runtime/name).is_file() for name in FILES), 'runtime_regular_files')
    require(digest(runtime/'nautobot_config.py') == spec['settings_sha256'], 'settings_drift')
    secrets = secret_metadata()
    images = json.loads(pod(['images','--format','json']) or '[]')
    health(spec)
    return {'files':files,'secrets':secrets,'networks':nets,'images':images}


def image_check(data, expected, repository=True):
    require(isinstance(data,list) and len(data)==1, 'image_inspection_shape')
    value=data[0]
    require(value.get('Os')=='linux' and value.get('Architecture')=='arm64', 'image_platform')
    require(value.get('Digest')==expected['digest'], 'image_manifest_digest')
    if repository:
        require(expected['reference'] in value.get('RepoDigests',[]), 'image_repository_digest')
    if expected.get('image_id'):
        require(value.get('Id','').removeprefix('sha256:')==expected['image_id'].removeprefix('sha256:'), 'image_config_id')
    return {k:value.get(k) for k in ('Id','Digest','RepoDigests','Architecture','Os','Size')}


def command(spec, name):
    if name=='custom':
        return ['load','--input',spec['archive']]
    if name=='alias':
        return ['tag',spec['images']['custom']['image_id'],'localhost/nautobot-homelab:qualified']
    require(name in ('postgresql','redis'), 'unknown_image_step')
    return ['pull','--platform=linux/arm64/v8','--retry=0','--tls-verify=true',spec['images'][name]['reference']]


def guarded(root,spec,name):
    unit='nautobot-load-'+root.name.removeprefix('nautobot-load-')+'-'+name
    require(re.fullmatch(r'nautobot-load-[A-Za-z0-9_-]+',unit) is not None, 'unit_identity')
    journal(json.loads((root/'before.json').read_text())['cursor'])
    health(spec)
    args=['systemd-run','--unit='+unit,'--uid=999','--gid=985','--property=WorkingDirectory=/',
          '--property=MemoryMax=3G','--property=MemorySwapMax=0','--property=CPUQuota=200%',
          '--property=RuntimeMaxSec=900','--property=TimeoutStopSec=15','--property=KillMode=control-group',
          '--wait','--pipe','/usr/bin/env',*[f'{k}={v}' for k,v in ENV.items()],
          '/usr/bin/python3',str(root/'node.py'),'limited',str(root),name]
    report={'step':name,'mutation_attempted':True,'accepted':False,'samples':[]}
    (root/(name+'-result.json')).write_text(json.dumps(report))
    started=time.monotonic(); last=started; process=None
    try:
        with tempfile.TemporaryFile() as output:
            process=subprocess.Popen(args,stdout=output,stderr=output,cwd='/',start_new_session=True)
            finished=None
            while True:
                now=time.monotonic()
                require(now-last<=15 and now-started<1020, 'coverage_gap_or_timeout')
                last=now
                require(os.fstat(output.fileno()).st_size<4*1024*1024, 'output_limit')
                report['samples'].append(health(spec))
                journal(json.loads((root/'before.json').read_text())['cursor'])
                if process.poll() is not None:
                    require(process.returncode==0,'image_command_failed')
                    if finished is None: finished=time.monotonic()
                    if time.monotonic()-finished>=75: break
                time.sleep(5)
            report.update(accepted=True,elapsed_seconds=time.monotonic()-started,post_exit_seconds=time.monotonic()-finished)
    except Exception as exc:
        report['error']=str(exc) if isinstance(exc,RuntimeError) else 'watchdog_failed'
        report['accepted']=False
        raise
    finally:
        # Stop only this operation's unit, even if the controller connection died.
        try:
            if process is not None and process.poll() is None:
                run(['systemctl','stop',unit+'.service'],timeout=25)
                process.wait(timeout=10)
            state=run(['systemctl','show',unit+'.service','--property=ActiveState','--value']).strip()
            require(state in ('inactive','failed'), 'image_worker_not_stopped')
            report['worker_stopped']=True
        except Exception:
            report['accepted']=False
            report['worker_stopped']=False
            raise
        finally:
            (root/(name+'-result.json')).write_text(json.dumps(report,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['before','guarded','limited','verify-loaded','verify-image','after']);parser.add_argument('root',type=Path);parser.add_argument('step',nargs='?');a=parser.parse_args()
    root=a.root; spec=json.loads((root/'spec.json').read_text())
    if a.mode=='limited':
        require(os.getuid()==999 and os.getgid()==985,'limited_user')
        row=Path('/proc/self/cgroup').read_text().strip()
        require(row.startswith('0::/system.slice/nautobot-load-'),'limited_cgroup')
        bounded.limits(Path('/sys/fs/cgroup'+row[3:]))
        os.execve('/usr/bin/podman',['podman',*command(spec,a.step)],ENV)
    require(os.geteuid()==0,'root_monitor_required')
    if a.mode=='before':
        journal(full=True);cursor=journal()
        before=inventory(spec);require(before['images']==[],'existing_images')
        path=Path(spec['archive']);require(path.is_file() and not path.is_symlink() and path.stat().st_size==spec['archive_bytes'],'archive_metadata')
        require(digest(path)==spec['archive_sha256'],'archive_hash')
        run(['/usr/sbin/runuser','--user','nautobot','--','test','-r',str(path)])
        journal(cursor);before['cursor']=cursor;(root/'before.json').write_text(json.dumps(before,indent=2)+'\n')
    elif a.mode=='guarded':guarded(root,spec,a.step)
    elif a.mode=='verify-loaded':
        value=image_check(json.loads(pod(['image','inspect',spec['images']['custom']['image_id']])),spec['images']['custom'],repository=False)
        (root/'loaded-image.json').write_text(json.dumps(value,indent=2)+'\n')
    elif a.mode=='verify-image':
        value=image_check(json.loads(pod(['image','inspect',spec['images'][a.step]['reference']])),spec['images'][a.step])
        (root/(a.step+'-image.json')).write_text(json.dumps(value,indent=2)+'\n')
    else:
        before=json.loads((root/'before.json').read_text()); after=inventory(spec)
        require(all(after[k]==before[k] for k in ['files','secrets','networks']),'configuration_or_object_drift')
        ids=set()
        for name,expected in spec['images'].items():
            value=image_check(json.loads(pod(['image','inspect',expected['reference']])),expected)
            ids.add(value['Id'].removeprefix('sha256:'))
        actual={i.get('Id',i.get('id','')).removeprefix('sha256:') for i in after['images']}
        require(actual==ids,'unexpected_image_set');journal(before['cursor'])
        after.update(accepted=True,runtime_started=False,administrator_created=False)
        (root/'after.json').write_text(json.dumps(after,indent=2)+'\n')
    print(json.dumps({'mode':a.mode,'passed':True}))


if __name__=='__main__':
    try:main()
    except Exception as exc:
        if os.geteuid() == 0 and len(sys.argv) > 2:
            path = Path(sys.argv[2])
            if path.is_dir() and path.parent == Path('/var/tmp') and path.name.startswith('nautobot-load-'):
                record = {'mode': sys.argv[1], 'accepted': False,
                          'error': str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__}
                (path/'failure.json').write_text(json.dumps(record, indent=2)+'\n')
        print('image-load check failed; retained node evidence requires review')
        raise SystemExit(69)
