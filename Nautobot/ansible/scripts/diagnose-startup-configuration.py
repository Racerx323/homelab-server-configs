#!/usr/bin/env python3
"""One bounded configuration check; no migration, bootstrap or application startup."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('node',HERE/'startup-node.py')
node=importlib.util.module_from_spec(spec);spec.loader.exec_module(node)
USER=node.base.USER
NAME='nautobot-configuration-diagnostic'
LABEL='org.homelab.nautobot.diagnostic'


def require(value, code):
    if not value:raise ValueError(code)


def containers():
    return node.base.podman('ps','--all','--format','json')


def baseline(inputs):
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip()==inputs['boot_id'],'boot_drift')
    require(not containers(),'container_residue')
    require(all(node.processless(node.service(role)) for role in node.ROLES),'live_processes')
    import hashlib
    for filename,digest in inputs['file_sha256'].items():
        path=Path(filename)
        require(path.is_file() and not path.is_symlink() and hashlib.sha256(path.read_bytes()).hexdigest()==digest,'installed_file_drift')
    for name in ('postgresql.env','redis.env','migration.env'):
        node.base.protected(Path('/var/lib/nautobot/runtime')/name,0o600)
    v=node.base.podman('image','inspect',inputs['image'])[0]
    require(v['Id'].removeprefix('sha256:')==inputs['image_id'].removeprefix('sha256:') and v['Architecture']=='arm64','image_drift')
    return {'passed':True,'no_processes':True,'no_containers':True}


def cleanup(inputs):
    rows=containers()
    for row in rows:
        # Never remove a production or unrelated container.
        names=row.get('Names',[])
        if isinstance(names,str):names=[names]
        if NAME not in names:continue
        value=node.base.podman('inspect',row['Id'])[0]
        require(value['Config']['Labels'].get(LABEL)==inputs['identity'],'foreign_container')
        node.base.call(USER+['/usr/bin/podman','rm','--force',row['Id']],60)
    result=node.stop_all()
    result['no_containers']=not containers()
    result['passed']=result['passed'] and result['no_containers']
    return result


def check(inputs):
    require(not containers() or all(NAME not in row.get('Names',[]) for row in containers()),'probe_exists')
    for role in ('postgresql','redis'):
        require(node.healthy(role,node.service(role)),'data_service_not_ready')
    for role in ('migration','web','worker','scheduler'):
        require(node.processless(node.service(role)),'excluded_service_running')
    home='/var/lib/nautobot/runtime/'
    argv=USER+['/usr/bin/podman','run','--rm','-i','--name',NAME,'--label',LABEL+'='+inputs['identity'],
        '--pull','never','--network','nautobot-private','--read-only','--user','999:999','--memory','1536m','--memory-swap','1536m',
        '--env-file',home+'migration.env','--env','NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py',
        '--env','PYTHONDONTWRITEBYTECODE=1',
        '--volume',home+'nautobot_config.py:/opt/nautobot/nautobot_config.py:ro',
        '--volume',home+'startup-job.py:/opt/nautobot/jobs/startup_readiness.py:ro',
        '--volume','nautobot-nautobot_media:/opt/nautobot/media']
    for directory,size in [('git',16),('jobs',16),('static',256)]:
        argv+=['--tmpfs','/opt/nautobot/'+directory+':rw,size='+str(size)+'m,mode=1777']
    argv+=['--tmpfs','/tmp:rw,size=64m,mode=1777','--entrypoint','python3',inputs['image'],'-']
    payload=(HERE/'startup-command.py').read_text()+"\nprint(json.dumps(command(['nautobot-server','check'],120)))\n"
    payload='import json\n'+payload
    result=subprocess.run(argv,input=payload.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=180,cwd='/')
    require(result.returncode==0 and len(result.stdout)<=65536,'probe_transport_failed')
    value=json.loads(result.stdout)
    require(type(value.get('exit_status')) is int,'native_status_missing')
    # Output is already redacted inside the container where secret values exist.
    return {'passed':True,'configuration_passed':value['exit_status']==0,'native_result':value}


if __name__=='__main__':
    os.umask(0o077);os.chdir('/')
    try:
        mode=sys.argv[1];inputs=json.loads((HERE/'inputs.json').read_text())
        require(os.geteuid()==0,'root_required')
        result={'baseline':baseline,'cleanup':cleanup,'check':check}[mode](inputs)
        print(json.dumps(result));raise SystemExit(0 if result['passed'] else 69)
    except Exception:
        print(json.dumps({'passed':False,'error':'diagnostic_boundary_or_command_failed'}));raise SystemExit(69)
