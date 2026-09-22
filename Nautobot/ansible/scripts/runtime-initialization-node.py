#!/usr/bin/env python3
"""Sanitized initialization preflight and postconditions; Ansible owns changes."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
sys.dont_write_bytecode = True
common_path = Path(__file__).with_name('canary-backup.py')
if not common_path.is_file():
    common_path = Path(__file__).resolve().parents[3] / 'restic/scripts/canary-backup.py'
spec = importlib.util.spec_from_file_location('storage', common_path)
storage = importlib.util.module_from_spec(spec); spec.loader.exec_module(storage)
USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
PREFIX = 'NAUTOBOT_INITIALIZATION_RESULT='


def require(ok, code):
    if not ok: raise ValueError(code)


def call(argv, timeout=60):
    rc, out = storage.invoke(argv, {'PATH':'/usr/bin:/bin','LC_ALL':'C.UTF-8'}, timeout)
    require(rc == 0, 'command_failed')
    return out.decode()


def podman(*argv):
    return json.loads(call(USER + ['/usr/bin/podman', *argv]))


def protected(path, mode):
    s=path.lstat()
    require(stat.S_ISREG(s.st_mode) and s.st_uid == 999 and stat.S_IMODE(s.st_mode) == mode, 'file_metadata')


def environments(home):
    values={}
    for role in ('postgresql','redis','migration'):
        p=home/(role+'.env'); protected(p,0o600)
        require(p.stat().st_size < 65536,'environment_size')
        rows=p.read_text().splitlines(); data={}
        for line in rows:
            k,sep,v=line.partition('=')
            require(sep and k not in data and v,'environment_format');data[k]=v
        values[role]=data
    m=values['migration']
    require(m.get('NAUTOBOT_DB_PASSWORD') and m.get('NAUTOBOT_REDIS_PASSWORD')
            and m.get('NAUTOBOT_DB_PASSWORD') == values['postgresql'].get('POSTGRES_PASSWORD')
            and m.get('NAUTOBOT_REDIS_PASSWORD') == values['redis'].get('REDISCLI_AUTH')
            and m.get('NAUTOBOT_SECRET_KEY')
            and m.get('NAUTOBOT_DB_USER') == 'nautobot'
            and m.get('NAUTOBOT_DB_NAME') == 'nautobot'
            and m.get('NAUTOBOT_DB_HOST') == 'postgresql'
            and m.get('NAUTOBOT_REDIS_HOST') == 'redis', 'environment_consistency')


def preflight(root, op):
    require(os.geteuid()==0,'root_required')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip()==op['runtime']['expected_boot_id'],'boot_drift')
    home=Path('/var/lib/nautobot/runtime');storage.ancestry(home)
    require(home.stat().st_uid==999 and stat.S_IMODE(home.stat().st_mode)==0o700,'runtime_directory')
    environments(home)
    p=home/'nautobot_config.py';protected(p,0o644)
    require(hashlib.sha256(p.read_bytes()).hexdigest()==op['runtime']['configuration_sha256'],'configuration_identity')
    require(not (home/'initialize-application.py').exists() and not (home/'initialize-application.py').is_symlink(),'existing_initializer')
    images={}
    for role, expected in op['runtime']['images'].items():
        v=podman('image','inspect',expected['reference'])[0]
        require(v['Id'].removeprefix('sha256:')==expected['id'].removeprefix('sha256:')
                and v['Architecture']=='arm64' and v['Os']=='linux','image_identity')
        images[role]={'id':v['Id'],'architecture':v['Architecture']}
    mount=call(['/usr/bin/findmnt','--noheadings','--output','SOURCE','--target','/var/lib/nautobot']).strip()
    require(mount=='/dev/sda2','storage_mount')
    mem=dict(line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())
    require(int(mem['MemAvailable'].split()[0])*1024>=4*1024**3,'memory_headroom')
    require(shutil.disk_usage('/var/lib/nautobot').free>=4*1024**3,'disk_headroom')
    return {'passed':True,'images':images,'environment_consistent':True,'configuration_verified':True,
            'filesystem':mount,'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip()}


def migration_receipt(raw, require_success=True):
    entries=[json.loads(line) for line in raw.splitlines() if line]
    receipts=[]
    for entry in entries:
        message=entry.get('MESSAGE')
        require(isinstance(message,str),'journal_message_missing')
        if message.startswith(PREFIX):receipts.append(json.loads(message[len(PREFIX):]))
    require(len(receipts)==1,'migration_receipt_count')
    v=receipts[0]
    known=('configuration','post_upgrade','configuration_after','pending_migrations')
    steps={}
    for name,step in v.get('steps',{}).items():
        require(name in known and isinstance(step,dict),'migration_step_format')
        rc=step.get('exit_status')
        require(rc is None or type(rc)==int,'migration_status_format')
        steps[name]={'exit_status':rc,'output_limited':step.get('output_limited') is True,
                     'timeout':step.get('error')=='timeout'}
    safe={'passed':v.get('passed') is True,'migration_attempted':v.get('migration_attempted') is True,
          'steps':steps,'error_class':v.get('error') if v.get('error') in {'resource_limits','application_must_be_unprivileged',
          'deadline','writable_git','writable_jobs','writable_media','writable_static','startup_or_boundary_failed'} else None}
    for key in ('memory_limit_bytes','swap_limit_bytes','uid'):
        value=v.get(key);require(value is None or type(value)==int,'migration_metadata_format');safe[key]=value
    if require_success:
        require(safe['passed'] and safe['migration_attempted'],'native_initialization_failed')
        require(safe['memory_limit_bytes']==1610612736 and safe['swap_limit_bytes']==0
                and isinstance(safe['uid'],int) and safe['uid']!=0,'migration_limits')
        require(set(steps)==set(known),'native_steps')
        require(all(s['exit_status']==0 and not s['output_limited'] and not s['timeout'] for s in steps.values()),'native_exit_status')
    return safe


def read_migration(root, require_success=True):
    call(['/usr/bin/journalctl','--sync'],30)
    cursor=json.loads((root/'journal-baseline.json').read_text())['cursor']
    raw=call(['/usr/bin/journalctl','--after-cursor',cursor,'_UID=999',
              '_SYSTEMD_USER_UNIT=nautobot-migration.service','SYSLOG_IDENTIFIER=nautobot-initialization','-o','json','--no-pager','--quiet','--all'])
    return migration_receipt(raw,require_success)



def container_evidence(v, role, image_id):
    limit={'postgresql':1536,'redis':512}[role]*1024**2
    require(v['State']['Running'] and not v['State'].get('OOMKilled'), 'container_state')
    require(v['Image'].removeprefix('sha256:')==image_id.removeprefix('sha256:'),'running_image')
    require(not v['HostConfig'].get('PortBindings') and not any((v['NetworkSettings'].get('Ports') or {}).values()),'published_ports')
    require(set(v['NetworkSettings']['Networks'])=={'nautobot-private'},'private_network')
    require(v['HostConfig']['Memory']==limit,'configured_memory')
    health=v['State'].get('Health',v['State'].get('Healthcheck',{}))
    require(health.get('Status')=='healthy','service_health')
    mounts=[m for m in v['Mounts'] if m.get('Type')=='volume']
    expected='/var/lib/postgresql/data' if role=='postgresql' else '/data'
    require(any(m.get('Name')=='nautobot-'+role+'_data' and m.get('Destination')==expected for m in mounts),'durable_volume')
    return {'running':True,'healthy':True,'private':True,'memory_bytes':limit,'durable_volume':True}


def postflight(root, op):
    services={}
    for role in ('postgresql','redis'):
        v=podman('inspect','nautobot-'+role)[0]
        services[role]=container_evidence(v,role,op['runtime']['images'][role]['id'])
        pid=v['State']['Pid'];line=Path('/proc/'+str(pid)+'/cgroup').read_text().strip()
        require(line.startswith('0::/') and v['Id'] in line,'container_cgroup')
        path=Path('/sys/fs/cgroup'+line[3:]);limits=[]
        while path!=Path('/sys/fs/cgroup'):
            m=(path/'memory.max').read_text().strip()
            if m!='max':limits.append(int(m))
            path=path.parent
        require(limits and 0<min(limits)<=services[role]['memory_bytes'],'effective_memory')
        services[role]['effective_memory_bytes']=min(limits)
    receipt=read_migration(root)
    state=call(USER+['/usr/bin/systemctl','--user','show','nautobot-migration.service',
                      '--property=Result,ExecMainStatus,ActiveState'])
    require(all(x in state.splitlines() for x in ('Result=success','ExecMainStatus=0','ActiveState=active')),'migration_unit_state')
    for role in ('web','worker','scheduler'):
        require(not Path('/var/lib/nautobot/.config/containers/systemd/nautobot-'+role+'.container').exists(),'application_installed')
    environments(Path('/var/lib/nautobot/runtime'))
    p=Path('/var/lib/nautobot/runtime/nautobot_config.py');protected(p,0o644)
    require(hashlib.sha256(p.read_bytes()).hexdigest()==op['runtime']['configuration_sha256'],'configuration_drift')
    return {'passed':True,'services':services,'migration':receipt,'configuration_unchanged':True,
            'application_services_installed':False}


def main():
    os.umask(0o077)
    # runuser changes identity and HOME, but inherits cwd. All child commands
    # must start somewhere the rootless service account can traverse.
    os.chdir('/')
    mode, directory=sys.argv[1:];root=Path(directory)
    require(root.parent==Path('/tmp') and re.fullmatch(r'nautobot-runtime\.[A-Za-z0-9_]+',root.name),'root_boundary')
    op=json.loads((root/'operation.json').read_text())
    try:
        if mode=='preflight': result=preflight(root,op)
        elif mode=='postflight': result=postflight(root,op)
        elif mode=='migration-evidence': result=read_migration(root,False)
        else:result=storage.journal(mode,root,op)
        print(json.dumps(result));return 0 if result.get('passed',True) else 69
    except Exception as exc:
        allowed=str(exc) if isinstance(exc,ValueError) and re.fullmatch('[a-z_]+',str(exc)) else 'boundary_or_command_failed'
        print(json.dumps({'passed':False,'error_class':allowed}));return 69


if __name__=='__main__':raise SystemExit(main())
