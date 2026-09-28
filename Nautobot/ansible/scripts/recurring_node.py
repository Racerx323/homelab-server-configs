#!/usr/bin/env python3
"""Rootless Nautobot recurring-backup bindings; Ansible owns writer ordering."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import resource
from recurring_protection import protected, require, atomic, Supervisor
from recurring_delivery import resolve, notify

ROLES=('postgresql','redis','web','worker','scheduler')
SCRIPTS=Path(__file__).resolve().parent
# Reuse the accepted capture encoders under the application account directly.
# The historical script's root/runuser behavior is left untouched.
capture_loader=importlib.util.spec_from_file_location('recurring_capture',SCRIPTS/'workload_capture.py')
capture=importlib.util.module_from_spec(capture_loader);capture_loader.loader.exec_module(capture)
capture.USER=[]


def bounded(argv, data=None, timeout=30):
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        def limit(): resource.setrlimit(resource.RLIMIT_FSIZE,(4*1024**2,4*1024**2))
        try:
            result=subprocess.run(argv,input=data,stdout=out,stderr=err,timeout=timeout,cwd='/',preexec_fn=limit)
        except (OSError,subprocess.TimeoutExpired): raise ValueError('native_command_failed') from None
        require(result.returncode==0 and out.tell()<4*1024**2 and err.tell()<4*1024**2,'native_command_failed')
        out.seek(0); return out.read()


def pod(argv, **kwargs): return bounded(['/usr/bin/podman',*argv],**kwargs)
def system(argv): return bounded(['/usr/bin/systemctl','--user',*argv])


def media_command(action):
    return ['/usr/bin/podman','unshare','/usr/bin/python3','-B',str(SCRIPTS/'media_namespace.py'),
            '--root',str(capture.MEDIA),action]


def media_directories():
    value=json.loads(bounded(media_command('inspect')))
    require(isinstance(value,list) and len(value)<=100 and all(isinstance(x,str) for x in value),'media_receipt')
    return value


capture.empty_media=media_directories


def states():
    raw=system(['show',*['nautobot-'+role+'.service' for role in ROLES],
                '--property=Id,ActiveState,SubState,InvocationID']).decode()
    result={}
    for group in raw.strip().split('\n\n'):
        row=dict(line.split('=',1) for line in group.splitlines() if '=' in line)
        result[row['Id']]=row
    require(set(result)=={'nautobot-'+r+'.service' for r in ROLES},'service_set')
    return result


def health():
    rows=states()
    require(all(r['ActiveState']=='active' and r['SubState']=='running' for r in rows.values()),'service_health')
    code="import http.client;c=http.client.HTTPConnection('127.0.0.1',8080,timeout=3);c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'});print(c.getresponse().status);c.close()"
    require(pod(['exec','nautobot-web','python3','-c',code]).strip()==b'200','http_health')
    return rows


def stopped():
    rows=states()
    require(all(rows['nautobot-'+r+'.service']['ActiveState']=='inactive' for r in ('web','worker','scheduler')),'writers_running')
    require(all(rows['nautobot-'+r+'.service']['ActiveState']=='active' for r in ('postgresql','redis')),'data_service_stopped')
    query="SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND backend_type='client backend'"
    require(bounded(capture.command(['psql','-X','-q','-A','-t','--no-password','-U','nautobot','-d','nautobot','-c',query])).strip()==b'0',
            'other_database_clients_present')


def load(path):
    protected(path); require(path.stat().st_size<1048576,'configuration_size'); return json.loads(path.read_text())


def binding(path):
    cfg=load(path)
    require(cfg['execution_authorized'] is True,'inactive_binding')
    require(os.getuid()==999 and socket.gethostname()=='j2-svpi4mf','target_identity')
    require(cfg['media_policy']=='empty_directories_only','media_policy')
    os.environ.update(HOME='/var/lib/nautobot',XDG_RUNTIME_DIR='/run/user/999',
                      DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/999/bus')
    return cfg


def scrub_idle():
    state=bounded(['/usr/bin/systemctl','show','e2scrub_all.service','--property=ActiveState','--value']).decode().strip()
    require(state=='inactive','filesystem_scrub_not_idle')


def prepare(path,cfg,root):
    protected(root,True)
    require(root.name.startswith('nautobot-recurring.'),'run_root')
    scrub_idle()
    before=health(); media=media_directories()
    capture.reviewed_files(cfg['artifact_sha256'])
    budget=sum(cfg['capture_limits'].values())
    require(shutil.disk_usage(root).free>=cfg['minimum_free_bytes']+budget,'capture_capacity')
    # Bound accumulation; retained captures require explicit disposal, never silent deletion.
    retained=sum(p.stat().st_size for parent in root.parent.glob('nautobot-recurring.*')
                 if parent.is_dir() and not parent.is_symlink() and parent.stat().st_uid==os.getuid()
                 for p in (parent/'payload').glob('*') if p.is_file() and not p.is_symlink())
    require(retained+budget<=cfg['maximum_retained_bytes'],'retained_capacity')
    images={role:pod(['inspect','--format','{{.Image}}','nautobot-'+role]).decode().strip().removeprefix('sha256:') for role in ROLES}
    require(images=={k:v.removeprefix('sha256:') for k,v in cfg['image_ids'].items()},'image_drift')
    versions=json.loads(pod(['exec','nautobot-web','python3','-c',
        "import importlib.metadata as m,json;print(json.dumps({p:m.version(p) for p in ('nautobot','nautobot-dns-models')}))"]))
    require(versions==cfg['versions'],'version_drift')
    for name in ('desired-state.yaml','requirements.lock','qualified-image.json'):
        item=cfg['metadata_files'][name]; source=Path(item['path'])
        require(not source.is_symlink() and source.stat().st_size<1048576,'metadata_source')
        raw=source.read_bytes(); require(hashlib.sha256(raw).hexdigest()==item['sha256'],'metadata_drift')
        (root/name).write_bytes(raw); (root/name).chmod(0o600)
    atomic(root/'backup-sources.json',{'consistency':'quiet_pilot_empty_media','quiet_window_confirmed':True,'files':cfg['artifact_sha256']})
    atomic(root/'recurring-before.json',{'services':before,'media':media,'images':images,'versions':versions,
                                       'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip()})
    base=['/usr/bin/python3',str(SCRIPTS/'recurring_node.py'),'--binding',str(path),'--root',str(root)]
    spec=dict(cfg['backup_template']); spec.update(execution_uid=999,authorized=True,source_consistency_reviewed=True,
        operation_id='nautobot-recurring',captures={name:{'argv':base+['section',name],'maximum_bytes':limit}
        for name,limit in cfg['capture_limits'].items()},dump_validator=base+['section','validate_dump'])
    # Validate against the actual shared producer before fetching credentials.
    loader=importlib.util.spec_from_file_location('producer',cfg['producer'])
    producer=importlib.util.module_from_spec(loader);loader.loader.exec_module(producer);producer.validate(spec)
    atomic(root/'application-backup.json',spec)
    (root/'repository').write_text(spec['repository_url']);(root/'repository').chmod(0o600)
    resolve(cfg['credentials'],root)
    atomic(root/'inputs.json',dict(application_capture_authorized=True,
        application_pause_commands=[base+['stop','scheduler'],base+['stop','web'],base+['drain'],base+['stop','worker']],
        application_resume_commands=[base+['start',r] for r in ('worker','web','scheduler')],
        application_health_argv=base+['health'],application_backup_credentials={
        'password':str(root/'source-password'),'credentials.json':str(root/'source-credentials.json')},
        application_producer_argv=['/usr/bin/python3',cfg['producer']]))


def section(root,cfg,name):
    require(name in capture.SECTIONS,'section')
    stopped(); old=load(root/'recurring-before.json')
    require(media_directories()==old['media'],'media_changed');capture.reviewed_files(cfg['artifact_sha256'])
    if name=='media':
        subprocess.run(media_command('archive'),check=True,timeout=30,cwd='/')
    elif name=='image_dependency_manifest':
        files={n:(root/n).read_bytes() for n in ('desired-state.yaml','requirements.lock','qualified-image.json')}
        files['observed-images-before-stop.json']=json.dumps(old['images'],sort_keys=True).encode()
        capture.archive(files,sys.stdout.buffer)
    elif name=='versions_migrations':
        query="SELECT json_agg(row_to_json(m)) FROM (SELECT app,name,applied FROM django_migrations ORDER BY app,name) m"
        raw=bounded(capture.command(['psql','-X','-q','-A','-t','--no-password','-U','nautobot','-d','nautobot',
                                    '-c','BEGIN READ ONLY; '+query+'; COMMIT;']))
        print(json.dumps({'versions':old['versions'],'migrations':json.loads(raw)}))
    else:
        original=sys.argv
        try:
            sys.argv=[str(SCRIPTS/'workload_capture.py'),'--root',str(root),name];capture.main()
        finally: sys.argv=original
    require(media_directories()==old['media'],'media_changed')



def supervisor_binding(binding_path, state_directory, installed_scripts, ansible):
    """Inactive definition with exact service-account commands; no target access."""
    for path in (binding_path,state_directory,installed_scripts,ansible):
        require(Path(path).is_absolute(),'binding_path')
    base=['/usr/bin/python3',str(Path(installed_scripts)/'recurring_node.py'),'--binding',str(binding_path)]
    return dict(schema_version=1,execution_authorized=False,state_directory=str(state_directory),
        unit_prefix='nautobot-protection',timezone='America/Chicago',start_hour=3,end_hour=4,
        capture_seconds=450,recovery_seconds=240,run_seconds=1800,prepare_argv=base+['prepare'],
        ansible_argv=[str(ansible),'-i','localhost,',str(Path(installed_scripts).parent/'playbooks/recurring-capture.yaml')],
        resume_commands=[base+['start',r] for r in ('worker','web','scheduler')],
        health_argv=base+['health'],notification_argv=base+['notify'],
        dispose_successful_payload=True,staging_directory='/var/lib/nautobot/protection/staging',staging_filesystem='ext4')


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser();parser.add_argument('--binding',type=Path,required=True)
    parser.add_argument('--root',type=Path);parser.add_argument('action',choices=['prepare','stop','start','drain','health','section','notify'])
    parser.add_argument('argument',nargs='?');args=parser.parse_args();cfg=binding(args.binding)
    root=args.root
    if args.action=='prepare': prepare(args.binding,cfg,Path(args.argument));return
    if args.action=='notify':
        directory=Path(cfg['state_directory']); state=load(directory/'state.json') if (directory/'state.json').exists() else {'phase':'idle'}
        if state['phase'] in ('preflight','armed','recovering','resumed'): return
        if state['phase'] in ('failed','recovered_failure','manual_intervention'): event='failure'
        elif Supervisor(Path(cfg['supervisor_configuration'])).missed()!=0: event='missed'
        else: event='recovery'
        require(notify(directory,event,cfg['notification']),'notification_delivery_failed');return
    if args.action in ('start','stop'):
        require(args.argument in ('web','worker','scheduler'),'writer_scope')
        if args.action=='stop': Supervisor(Path(cfg['supervisor_configuration'])).check()
        system([args.action,'nautobot-'+args.argument+'.service']);return
    if args.action=='health':
        current=health()
        if root:
            old=load(root/'recurring-before.json')
            require(old['boot_id']==Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'boot_changed')
            require(all(current['nautobot-'+r+'.service']['InvocationID']==old['services']['nautobot-'+r+'.service']['InvocationID']
                        for r in ('postgresql','redis')),'data_service_restarted')
        return
    require(root is not None,'root_required');protected(root,True)
    if args.action=='drain':
        code=(SCRIPTS/'recovery_probe.py').read_text()+"\nprint(json.dumps(native_drain()))\n"
        pod(['exec','-i','nautobot-worker','nautobot-server','shell','--interface','python','--command',
             'import sys;exec(sys.stdin.read())'],data=code.encode(),timeout=210)
    else: section(root,cfg,args.argument)


if __name__=='__main__':
    try: main()
    except Exception:
        print(json.dumps({'failed':True,'reason':'recurring_binding_failed'}),file=sys.stderr);raise SystemExit(1)
