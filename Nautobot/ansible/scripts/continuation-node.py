#!/usr/bin/env python3
"""Continuation identity, progress and stopped-state checks; Ansible orchestrates."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import time
sys.dont_write_bytecode = True
spec=importlib.util.spec_from_file_location('inspection',Path(__file__).with_name('inspect-retained-database.py'))
inspection=importlib.util.module_from_spec(spec);spec.loader.exec_module(inspection)
runtime=inspection.runtime
spec=importlib.util.spec_from_file_location('progress',Path(__file__).with_name('migration-continuation.py'))
progress=importlib.util.module_from_spec(spec);spec.loader.exec_module(progress)
require=inspection.require
HOME=Path('/var/lib/nautobot/runtime')
EVIDENCE=HOME/'continuation-evidence'


def copied_trees(op):
    path=Path(op['continuation']['cold_copy'])
    require(path.parent==Path('/var/lib/nautobot/recovery') and not path.is_symlink(),'copy_boundary')
    runtime.storage.ancestry(path)
    for parent in (path.parent,path):
        s=parent.lstat();require(stat.S_ISDIR(s.st_mode) and s.st_uid==0 and stat.S_IMODE(s.st_mode)==0o700,'copy_parent')
    for name,expected in op['continuation']['cold_volumes'].items():
        inspection.no_submounts(path/name)
        rows=inspection.tree(path/name)
        require(hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()==expected['tree_sha256']
                and len(rows)==expected['entries'],'cold_copy_changed')
    return True


def preflight(root,op):
    require(os.geteuid()==0,'root_required')
    before=inspection.stopped();before_op=json.loads(json.dumps(op))
    before_op['runtime']['artifact_sha256']=op['continuation']['previous_artifact_sha256']
    inspection.identities(before_op);copied_trees(op)
    for suffix in ('.timer','.service'):
        require(inspection.command(['/usr/bin/systemctl','show',op['guard_unit']+suffix,'--property=LoadState','--value']).strip()=='not-found','existing_guard')
    for name in ('migration-continuation.py','migration-continuation-inputs.json','continuation-evidence'):
        require(not (HOME/name).exists() and not (HOME/name).is_symlink(),'continuation_residue')
    runtime.protected(HOME/'initialize-application.py',0o644)
    require(inspection.file_hash(HOME/'initialize-application.py')==op['continuation']['previous_initializer_sha256'],'initializer_drift')
    require(inspection.command(['/usr/bin/findmnt','--noheadings','--output','SOURCE','--target',str(HOME)]).strip()=='/dev/sda2','storage_mount')
    require(shutil.disk_usage(HOME).free>=4*1024**3,'disk_headroom')
    mem=dict(line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())
    require(int(mem['MemAvailable'].split()[0])*1024>=4*1024**3,'memory_headroom')
    for role in ('postgresql','redis'):
        name='nautobot-'+role+'_data';v=runtime.podman('volume','inspect',name)[0]
        path=Path(v['Mountpoint']);expected=Path('/var/lib/nautobot/.local/share/containers/storage/volumes')/name/'_data'
        require(path==expected and path.resolve()==expected,'volume_path');inspection.no_submounts(path)
        if role=='postgresql':require((path/'PG_VERSION').read_text().strip()=='17' and not (path/'postmaster.pid').exists(),'postgres_not_cold')
    result={'passed':True,'before':before,'cold_copies_verified':True}
    runtime.storage.record(root,'preflight.json',result)
    return result


def ready(root,op):
    before=json.loads((root/'preflight.json').read_text())['before'];services={}
    for role in ('postgresql','redis'):
        state=inspection.state(role)
        require(state['ActiveState']=='active' and re.fullmatch('[0-9a-f]{32}',state.get('InvocationID',''))
                and state['InvocationID']!=before[role].get('InvocationID'),'stale_service')
        v=runtime.podman('inspect','nautobot-'+role)[0]
        services[role]=runtime.container_evidence(v,role,op['runtime']['images'][role]['id'])
        pid=v['State']['Pid'];line=Path('/proc/'+str(pid)+'/cgroup').read_text().strip()
        require(line.startswith('0::/') and v['Id'] in line,'container_cgroup')
        path=Path('/sys/fs/cgroup'+line[3:]);limits=[]
        while path!=Path('/sys/fs/cgroup'):
            limit=(path/'memory.max').read_text().strip()
            if limit!='max':limits.append(int(limit))
            path=path.parent
        require(limits and 0<min(limits)<=services[role]['memory_bytes'],'effective_memory')
        services[role]['effective_memory_bytes']=min(limits)
    return {'passed':True,'services':services}


def evidence_uid():
    raw=inspection.command(runtime.USER+['/usr/bin/podman','unshare','cat','/proc/self/uid_map'])
    for line in raw.splitlines():
        inside,outside,size=map(int,line.split())
        if inside<=999<inside+size:return outside+999-inside
    raise ValueError('uid_mapping')


def installed(op):
    inspection.identities(op)
    for name,digest in op['continuation']['installed_files'].items():
        runtime.protected(HOME/name,0o644)
        require(inspection.file_hash(HOME/name)==digest,'installed_file_drift')
    return {'passed':True}


def read_safe(path,limit):
    s=path.lstat();require(stat.S_ISREG(s.st_mode) and s.st_uid==evidence_uid() and stat.S_IMODE(s.st_mode)==0o600
                            and s.st_size<=limit,'evidence_metadata')
    return path.read_text()


def events(op):
    contract=json.loads((HOME/'migration-continuation-inputs.json').read_text())
    known={tuple(k) for k in contract['known_migrations']};rows=[]
    path=EVIDENCE/'progress.jsonl'
    if not path.exists():return rows
    for line in read_safe(path,2*1024*1024).splitlines():
        v=json.loads(line);require(isinstance(v,dict),'event_shape')
        base={'event','elapsed','token'};event=v.get('event')
        fields={'step_start':{'step'},'step_end':{'step','exit_status','error'},'phase':{'phase'},
                'migration_start':{'app','migration'},'migration_complete':{'app','migration'}}
        require(event in fields and set(v)==base|fields[event],'event_shape')
        require(v['token']==op['continuation']['invocation_nonce'] and type(v['elapsed']) in (int,float) and 0<=v['elapsed']<=2100,'event_identity')
        if 'step' in v: require(v['step'] in dict(progress.STEPS),'step_identity')
        if 'phase' in v: require(v['phase'] in progress.PHASES.values(),'phase_identity')
        if 'app' in v: require((v['app'],v['migration']) in known,'migration_identity')
        if event=='step_end':
            require(v['exit_status'] is None or type(v['exit_status']) is int,'exit_status')
            require(v['error'] in (None,'timeout','output_limit'),'error_identity')
        rows.append(v);require(len(rows)<=5000,'progress_size')
    return rows


def receipt(op):
    v=json.loads(read_safe(EVIDENCE/'receipt.json',2*1024*1024))
    require(set(v)<= {'passed','token','steps','migration_attempted','pending_before','error','elapsed','memory_limit_bytes','swap_limit_bytes','uid'},'receipt_shape')
    require(v['token']==op['continuation']['invocation_nonce'] and type(v['passed']) is bool and type(v['migration_attempted']) is bool,'receipt_identity')
    require(v.get('error') in progress.FAILURES | {None,'continuation_failed'},'receipt_error')
    require(type(v['elapsed']) in (int,float) and 0<=v['elapsed']<=2100,'receipt_elapsed')
    for k in ('uid','memory_limit_bytes','swap_limit_bytes'): require(type(v.get(k)) is int,'receipt_limits')
    known={tuple(k) for k in json.loads((HOME/'migration-continuation-inputs.json').read_text())['known_migrations']}
    require(all(isinstance(k,list) and len(k)==2 and tuple(k) in known for k in v.get('pending_before',[])),'receipt_plan')
    require(isinstance(v['steps'],dict) and set(v['steps'])<=set(dict(progress.STEPS)),'receipt_steps')
    for step in v['steps'].values():
        require(set(step)=={'exit_status','error','bytes'} and (step['exit_status'] is None or type(step['exit_status']) is int)
                and step['error'] in (None,'timeout','output_limit') and type(step['bytes']) is int
                and 0<=step['bytes']<=9*1024*1024,'receipt_step')
    return v


def latest(root,name,data):
    target=root/name
    if target.exists() or target.is_symlink():
        info=target.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid==os.geteuid()
                and stat.S_IMODE(info.st_mode)==0o600,'latest_metadata')
    with tempfile.NamedTemporaryFile(mode='w',dir=root,delete=False) as f:
        tmp=Path(f.name)
        try:
            json.dump(data,f,sort_keys=True);f.flush();os.fsync(f.fileno())
            os.replace(tmp,target)
        finally:
            tmp.unlink(missing_ok=True)


def poll(root,op):
    before=json.loads((root/'preflight.json').read_text())['before']['migration'];state=inspection.state('migration')
    new = bool(re.fullmatch('[0-9a-f]{32}',state.get('InvocationID',''))) and state['InvocationID']!=before.get('InvocationID')
    if not new and state.get('ActiveState') in ('inactive','failed','activating'):
        wait=root/'invocation-wait.json'
        if not wait.exists():runtime.storage.record(root,'invocation-wait.json',{'start':time.monotonic()})
        require(time.monotonic()-json.loads(wait.read_text())['start']<30,'stale_migration')
        return {'passed':False,'pending':True,'awaiting_new_invocation':True}
    require(new,'stale_migration')
    rows=events(op)
    latest(root,'native-progress.json',{'events':rows,'invocation':state['InvocationID']})
    if state['ActiveState']=='activating':return {'passed':False,'pending':True,'invocation':state['InvocationID'],'events':len(rows)}
    require(state['ActiveState']=='active' and state['Result']=='success' and state['ExecMainStatus']=='0','migration_failed')
    v=receipt(op)
    require(v['passed'] and v['migration_attempted'] and set(v['steps'])==set(dict(progress.STEPS))
            and all(s['exit_status']==0 and not s['error'] for s in v['steps'].values()),'native_not_complete')
    require(v['memory_limit_bytes']==1610612736 and v['swap_limit_bytes']==0 and v['uid']!=0,'migration_limits')
    require([r['step'] for r in rows if r['event']=='step_end']==list(dict(progress.STEPS)),'progress_incomplete')
    installed(op)
    status=ready(root,op)
    return {'passed':True,'invocation':state['InvocationID'],'native':v,'services':status['services']}


def evidence(root,op):
    result={'passed':True,'events':events(op)}
    if (EVIDENCE/'receipt.json').exists():result['receipt']=receipt(op)
    return result


def guard_stop(root):
    statuses=[]
    for role in ('migration','redis','postgresql'):
        try:
            inspection.command(runtime.USER+['/usr/bin/systemctl','--user','stop','--no-block','nautobot-'+role+'.service'],15)
            statuses.append(0)
        except Exception:statuses.append(69)
    runtime.storage.record(root,'guard-stop.json',{'requested':statuses})
    return {'passed':all(s==0 for s in statuses)}


def main():
    os.umask(0o077);os.chdir('/')
    mode,directory=sys.argv[1:];root=Path(directory)
    require(root.parent==Path('/tmp') and re.fullmatch(r'nautobot-runtime\.[A-Za-z0-9_]+',root.name),'root_boundary')
    op=json.loads((root/'operation.json').read_text())
    try:
        if mode=='preflight':v=preflight(root,op)
        elif mode=='installed':v=installed(op)
        elif mode=='ready':v=ready(root,op)
        elif mode=='poll':v=poll(root,op)
        elif mode=='evidence':v=evidence(root,op)
        elif mode=='guard-stop':v=guard_stop(root)
        elif mode=='stopped':v={'passed':True,'services':inspection.stopped(),'cold_copies_verified':copied_trees(op)}
        else:v=runtime.storage.journal(mode,root,op)
        print(json.dumps(v));return 0 if v.get('passed',True) else 75
    except Exception as exc:
        allowed={'cold_copy_changed','copy_boundary','copy_parent','initializer_drift','continuation_residue','existing_guard','disk_headroom','memory_headroom','stale_service','stale_migration','migration_failed','native_not_complete','progress_incomplete','receipt_identity','installed_file_drift','evidence_metadata','configuration_drift','boot_drift','unit_drift','container_residue'}
        code=str(exc) if isinstance(exc,ValueError) and str(exc) in allowed else 'continuation_boundary_failed'
        print(json.dumps({'passed':False,'error':code}));return 69

if __name__=='__main__':raise SystemExit(main())
