#!/usr/bin/env python3
"""Private Podman adapters and independent safety watchdog; Ansible sequences actions."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time
from contextlib import contextmanager
sys.dont_write_bytecode=True
support=Path(__file__).with_name('load-node.py')
if not support.exists():support=Path(__file__).with_name('image-load-node.py')
s=importlib.util.spec_from_file_location('image_node',support);n=importlib.util.module_from_spec(s);s.loader.exec_module(n)
require=n.require
LABEL='io.homelab.nautobot.auth-trial'
ROLES=('postgresql','redis','probe')
MEMORY={'postgresql':768,'redis':512,'probe':1536}
CHECKS=['settings_and_plugin_registration','postgresql_positive_and_wrong_password',
        'redis_cache_positive_missing_wrong_password','redis_broker_positive_missing_wrong_password']


def save(root,name,data):
    path=root/(name+'.json');tmp=root/(name+'.new')
    tmp.write_text(json.dumps(data,indent=2)+'\n');os.chmod(tmp,0o600);tmp.replace(path)


def read(root,name):return json.loads((root/(name+'.json')).read_text())


def pod(args,timeout=30,observer=None):
    # Never persist raw stdout/stderr: inspect contains environment credentials.
    return n.bounded.capture(n.USER+args,timeout=timeout,limit=1024*1024,env=n.ENV,observer=observer)


DIAGNOSTIC_CODES=frozenset(('watchdog_not_live','resource_guard','kernel_storage_or_health_event',
    'container_inspection','container_identity','container_ownership','container_image',
    'container_exposure','published_ports','configured_memory','container_network',
    'configuration_bind','secret_mount','unreviewed_data_mount','tmpfs_set','tmpfs_size',
    'missing_bind','container_cgroup','effective_limits','container_not_running',
    'probe_failed_or_unexpected_output','command_timeout','output_limit'))


def diagnostic_error(error):
    # Exact controlled identifiers only. Never persist arbitrary exception text.
    message=str(error)
    if type(error) is RuntimeError and message in DIAGNOSTIC_CODES:return message
    if type(error) is RuntimeError and re.fullmatch(r'command_failed:runuser:-?[0-9]+',message):return 'command_nonzero'
    return 'unclassified_failure'


def observed_probe(root):
    def observe(rc,out,err):
        record=read(root,'diagnostic')
        for key in ('probe_phase','completed_checks'):record.pop(key,None)
        record['command_rc']=rc
        record['output_category']='no_valid_probe_result'
        try:
            value=json.loads(out.decode('utf-8').strip().splitlines()[-1])
            phases={'isolation','settings','postgresql','redis_cache','redis_broker'}
            if (set(value)=={'accepted','checks','production_runtime_accepted','administrator_created','failed_phase','error'}
                    and value['accepted'] is False and value['production_runtime_accepted'] is False
                    and value['administrator_created'] is False and value['failed_phase'] in phases
                    and value['error']=='check_or_connection_cleanup_failed'
                    and value['checks'] in [CHECKS[:i] for i in range(5)]):
                record.update(output_category='probe_rejected',probe_phase=value['failed_phase'],completed_checks=value['checks'])
            elif value=={'accepted':True,'checks':CHECKS,'production_runtime_accepted':False,'administrator_created':False}:
                record['output_category']='probe_reported_success'
        except (ValueError,UnicodeError,IndexError,TypeError):pass
        save(root,'diagnostic',record)
    return observe


def probe_action(root,spec):
    record={'action':'probe','phase':'guard','status':'running'}
    def phase(name,role=None):
        record.update(phase=name,role=role);save(root,'diagnostic',record)
    try:
        phase('guard');guard(root)
        for selected in ROLES:
            phase('inspect',selected);v=container(root,selected)
            phase('validate',selected);validate_container(root,spec,selected,v)
            require(v['State']['Running'],'container_not_running')
            phase('effective_limits',selected);effective_limits(v['State']['Pid'],v['Id'],selected)
        phase('resolve_probe','probe');cid=container(root,'probe')['Id']
        phase('django_shell','probe')
        code="exec(compile(open('/run/nautobot-qualification/probe.py').read(), '/run/nautobot-qualification/probe.py', 'exec'), {'__name__':'__main__'})"
        out=pod(['exec',cid,'nautobot-server','shell','--interface','python','--command',code],timeout=120,observer=observed_probe(root))
        record=read(root,'diagnostic');phase('parse_probe','probe')
        save(root,'probe-result',probe_result(out))
        phase('post_guard');guard(root)
        record.update(status='passed');save(root,'diagnostic',record)
    except Exception as error:
        record=read(root,'diagnostic');record.update(status='failed',category=diagnostic_error(error))
        save(root,'diagnostic',record);raise


def identity(root):
    require(root.parent==Path('/var/tmp') and re.fullmatch(r'nautobot-auth-[a-z0-9_]+',root.name),'trial_directory')
    return root.name


@contextmanager
def locked(root):
    with (root/'lock').open('a') as f:
        end=time.monotonic()+160
        while True:
            try:fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);break
            except BlockingIOError:
                require(time.monotonic()<end,'operation_lock_timeout');time.sleep(.2)
        try:yield
        finally:fcntl.flock(f,fcntl.LOCK_UN)


def guard(root):
    state=read(root,'watchdog-ready')
    require(not (root/'stop').exists() and not (root/'finish').exists() and
            time.monotonic()<state['deadline'] and time.monotonic()-state['heartbeat']<20,'watchdog_not_live')
    n.health(read(root,'spec'));n.journal(read(root,'before')['cursor'])


def create_args(root,spec,role):
    token=identity(root);home='/var/lib/nautobot/runtime';memory=MEMORY[role]
    ref=spec['images']['custom' if role=='probe' else role]['reference']
    args=['create','--name',token+'-'+role,'--label',LABEL+'='+token,'--pull=never',
          '--network',token,'--network-alias',role,'--image-volume=ignore','--read-only',
          '--read-only-tmpfs=false','--tmpfs','/tmp:rw,size=64m,mode=1777',
          '--tmpfs','/run:rw,size=16m,mode=0755','--memory='+str(memory)+'m',
          '--memory-swap='+str(memory)+'m','--cpus=2','--pids-limit=256','--timeout=900',
          '--security-opt=no-new-privileges','--cap-drop=NET_RAW','--log-driver=none']
    if role=='postgresql':
        args += ['--env-file',home+'/postgresql.env','--env','POSTGRES_USER=nautobot','--env','POSTGRES_DB=nautobot',
                 '--tmpfs','/var/lib/postgresql/data:rw,size=512m,mode=0700',
                 '--tmpfs','/var/run/postgresql:rw,size=16m,mode=3775',ref]
    elif role=='redis':
        args += ['--env-file',home+'/redis.env','--secret','nautobot-redis-config,type=mount,target=redis.conf,uid=999,gid=999,mode=0400',
                 '--tmpfs','/data:rw,size=128m,mode=0755',ref,'redis-server','/run/secrets/redis.conf']
    else:
        args += ['--env-file',home+'/migration.env','--env','NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py',
                 '--env','PYTHONDONTWRITEBYTECODE=1','--tmpfs','/prom_cache:rw,size=8m,mode=1777',
                 '--volume',home+'/nautobot_config.py:/opt/nautobot/nautobot_config.py:ro',
                 '--volume',str(root/'probe.py')+':/run/nautobot-qualification/probe.py:ro',
                 '--volume',str(root/'isolated-trial')+':/run/nautobot-qualification/isolated-trial:ro',
                 '--entrypoint','/bin/sleep',ref,'infinity']
    return args


def container(root,role):
    values=json.loads(pod(['container','inspect',identity(root)+'-'+role]))
    require(isinstance(values,list) and len(values)==1,'container_inspection')
    value=values[0];cid=value['Id']
    require(re.fullmatch('[a-f0-9]{64}',cid) is not None and value['Name'].lstrip('/')==identity(root)+'-'+role,'container_identity')
    require(value['Config']['Labels'].get(LABEL)==identity(root),'container_ownership')
    return value


def validate_container(root,spec,role,v):
    require(v['Image'].removeprefix('sha256:')==spec['images']['custom' if role=='probe' else role]['image_id'].removeprefix('sha256:'),'container_image')
    h=v['HostConfig'];require(h['ReadonlyRootfs'] and not h.get('Privileged') and not h.get('PortBindings'),'container_exposure')
    require(not any(v.get('NetworkSettings',{}).get('Ports',{}).values()),'published_ports')
    require(h['Memory']==MEMORY[role]*1024**2 and h['MemorySwap']==h['Memory'],'configured_memory')
    require(set(v['NetworkSettings']['Networks'])=={identity(root)},'container_network')
    binds={} if role!='probe' else {
        '/opt/nautobot/nautobot_config.py':'/var/lib/nautobot/runtime/nautobot_config.py',
        '/run/nautobot-qualification/probe.py':str(root/'probe.py'),
        '/run/nautobot-qualification/isolated-trial':str(root/'isolated-trial')}
    sizes={'/tmp':64,'/run':16}
    sizes.update({'/var/lib/postgresql/data':512,'/var/run/postgresql':16} if role=='postgresql' else {'/data':128} if role=='redis' else {'/prom_cache':8})
    tmp=set(sizes)
    for mount in v.get('Mounts',[]):
        dest=mount['Destination']
        if dest in binds:require(mount['Type']=='bind' and mount['Source']==binds[dest] and not mount['RW'],'configuration_bind')
        elif role=='redis' and dest=='/run/secrets/redis.conf':require(not mount['RW'],'secret_mount')
        else:require(mount['Type']=='tmpfs' and dest in tmp,'unreviewed_data_mount')
    require(set(h.get('Tmpfs',{}))==tmp,'tmpfs_set')
    for destination,megabytes in sizes.items():
        options=h['Tmpfs'][destination].split(',')
        size=[x.removeprefix('size=') for x in options if x.startswith('size=')]
        require(len(size)==1 and size[0].lower() in {str(megabytes)+'m',str(megabytes*1024**2)},'tmpfs_size')
    require({m['Destination'] for m in v.get('Mounts',[]) if m['Destination'] in binds}==set(binds),'missing_bind')


def effective_limits(pid,cid,role):
    row=Path('/proc/'+str(pid)+'/cgroup').read_text().strip()
    require(row.startswith('0::/') and cid in row,'container_cgroup')
    path=Path('/sys/fs/cgroup'+row[3:]);mem=[];swap=[];cpu=[]
    while path!=Path('/sys/fs/cgroup'):
        for filename,values in [('memory.max',mem),('memory.swap.max',swap)]:
            value=(path/filename).read_text().strip()
            if value!='max':values.append(int(value))
        quota,period=(path/'cpu.max').read_text().split()
        if quota!='max':cpu.append(int(quota)/int(period))
        path=path.parent
    require(mem and 0<min(mem)<=MEMORY[role]*1024**2 and swap and min(swap)==0 and cpu and 0<min(cpu)<=2,'effective_limits')
    return {'memory_max':min(mem),'swap_max':min(swap),'cpus':min(cpu)}


def probe_result(output):
    value=json.loads(output.strip().splitlines()[-1])
    require(set(value)=={'accepted','checks','production_runtime_accepted','administrator_created'} and
            value['accepted'] is True and value['checks']==CHECKS and
            value['production_runtime_accepted'] is False and value['administrator_created'] is False,'probe_failed_or_unexpected_output')
    return value


def preflight(root):
    identity(root);spec=read(root,'spec');n.journal(full=True);cursor=n.journal()
    before=n.inventory(spec)
    expected=set()
    for name,item in spec['images'].items():
        value=n.image_check(json.loads(pod(['image','inspect',item['reference']])),item)
        expected.add(value['Id'].removeprefix('sha256:'))
    require({i['Id'].removeprefix('sha256:') for i in before['images']}==expected,'image_set')
    before.update(cursor=cursor,images_expected=sorted(expected));save(root,'before',before)


def action(root,mode,role):
    spec=read(root,'spec')
    with locked(root):
        if mode=='probe':
            probe_action(root,spec);return
        guard(root)
        if mode=='network':
            pod(['network','create','--internal','--label',LABEL+'='+identity(root),identity(root)])
            v=json.loads(pod(['network','inspect',identity(root)]))[0]
            require(v.get('internal') and v.get('labels',{}).get(LABEL)==identity(root),'network_isolation')
            save(root,'network',{'id':v['id'],'name':v['name']})
        elif mode=='create':
            require(role in ROLES,'role');pod(create_args(root,spec,role),timeout=45)
            v=container(root,role);validate_container(root,spec,role,v);save(root,role,{'id':v['Id'],'validated':True})
        elif mode=='start':
            v=container(root,role);validate_container(root,spec,role,v);pod(['start',v['Id']],timeout=30)
            v=container(root,role);require(v['State']['Running'],'container_not_running')
            limits=effective_limits(v['State']['Pid'],v['Id'],role);save(root,role,{'id':v['Id'],'limits':limits,'started':True})
        elif mode=='ready':
            v=container(root,role);require(v['State']['Running'],'service_exited')
            args=['pg_isready','-U','nautobot','-d','nautobot'] if role=='postgresql' else ['redis-cli','--raw','ping']
            output=pod(['exec',v['Id'],*args],timeout=10)
            if role=='redis':require(output.strip()=='PONG','redis_not_ready')
        else:raise RuntimeError('unknown_action')
        guard(root)


def cleanup(root, sample=None):
    """Attempt every owned object's teardown; no prune, volumes, images or secrets."""
    result={};token=identity(root)
    with locked(root):
        for role in reversed(ROLES):
            try:
                rows=json.loads(pod(['ps','-a','--format','json']))
                matching=[v for v in rows if token+'-'+role in v.get('Names',[])]
                if matching:
                    v=container(root,role)
                    require(len(matching)==1 and matching[0]['Id']==v['Id'],'cleanup_identity')
                    try:
                        if v['State']['Running']:pod(['stop','--time=10',v['Id']],timeout=20)
                    finally:
                        # rm refuses a running object; never force an ambiguous teardown.
                        pod(['rm',v['Id']],timeout=20)
                rows=json.loads(pod(['ps','-a','--format','json']))
                require(not any(token+'-'+role in v.get('Names',[]) for v in rows),'container_residue')
                result[role]=True
            except Exception:result[role]=False
            if sample is not None:
                try:sample()
                except Exception:result['observation']=False
        try:
            nets=json.loads(pod(['network','ls','--format','json']))
            if any(v.get('name',v.get('Name'))==token for v in nets):
                v=json.loads(pod(['network','inspect',token]))[0]
                require(v.get('labels',{}).get(LABEL)==token,'network_cleanup_ownership')
                pod(['network','rm',v['id']])
            require(not any(v.get('name',v.get('Name'))==token for v in json.loads(pod(['network','ls','--format','json']))),'network_residue')
            result['network']=True
        except Exception:result['network']=False
        if sample is not None:
            try:sample()
            except Exception:result['observation']=False
    save(root,'cleanup',result);return all(result.values())


def watchdog(root):
    spec=read(root,'spec');started=time.monotonic();deadline=started+900;last=started;samples=[]
    result={'accepted':False,'reason':'not_finished','controller_independent':True}
    try:
        while True:
            now=time.monotonic();require(now-last<=15,'sample_gap');last=now
            samples.append(n.health(spec));n.journal(read(root,'before')['cursor'])
            save(root,'watchdog-ready',{'deadline':deadline,'heartbeat':time.monotonic()})
            if (root/'finish').exists():break
            require(not (root/'stop').exists() and now<deadline,'stopped_or_deadline')
            time.sleep(5)
        require(read(root,'probe-result')['accepted'],'probe_not_accepted');result['reason']='probe_passed'
    except Exception:result['reason']='trial_failed_or_guard_triggered'
    finally:
        (root/'stop').touch()
        try:
            def sample_cleanup():
                nonlocal last
                now=time.monotonic();require(now-last<=15,'cleanup_sample_gap');last=now
                samples.append(n.health(spec));n.journal(read(root,'before')['cursor'])
            cleaned=cleanup(root,sample_cleanup);result['cleanup_passed']=cleaned
            end=time.monotonic()+75;last=time.monotonic()
            while True:
                now=time.monotonic();require(now-last<=15,'post_cleanup_sample_gap');last=now
                samples.append(n.health(spec));n.journal(read(root,'before')['cursor'])
                if now>=end:break
                time.sleep(5)
            after=n.inventory(spec);before=read(root,'before')
            require(all(after[k]==before[k] for k in ('files','secrets','networks')),'configuration_drift')
            require({x['Id'] for x in after['images']}=={x['Id'] for x in before['images']},'image_drift')
            result.update(accepted=cleaned and result['reason']=='probe_passed',post_cleanup_seconds=time.monotonic()-(end-75),continuity_passed=True)
        except Exception:result.update(accepted=False,postflight_failed=True)
        result['samples']=samples;save(root,'result',result)


def emergency(root):
    # systemd runs this even if the watchdog is killed or hits RuntimeMaxSec.
    if (root/'result.json').exists() and read(root,'result').get('accepted'):return
    (root/'stop').touch();cleaned=cleanup(root)
    save(root,'emergency',{'accepted':False,'cleanup_passed':cleaned})


def main():
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['preflight','watchdog','emergency','network','create','start','ready','probe','finish','status']);parser.add_argument('root',type=Path);parser.add_argument('role',nargs='?');a=parser.parse_args();root=a.root
    require(os.geteuid()==0,'root_monitor');identity(root)
    if a.mode=='preflight':preflight(root)
    elif a.mode=='watchdog':watchdog(root)
    elif a.mode=='emergency':emergency(root)
    elif a.mode=='finish':(root/'finish').touch()
    elif a.mode=='status':
        require((root/'result.json').exists(),'observation_incomplete');require(read(root,'result')['accepted'],'trial_failed')
    else:action(root,a.mode,a.role)
    print(json.dumps({'mode':a.mode,'passed':True}))


if __name__=='__main__':
    try:main()
    except Exception:
        print('trial step failed; raw output suppressed')
        raise SystemExit(69)
