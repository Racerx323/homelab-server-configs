#!/usr/bin/env python3
"""Real disposable Celery/Session/Restic integration, no production connection.

Host-specific sampler/user-systemd and SSH staging remain live qualification gaps.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Nautobot/ansible/scripts'))
from workload_session import Session, native_command


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def command(argv, timeout=900, data=None):
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(argv, stdin=subprocess.PIPE if data else subprocess.DEVNULL, stdout=out, stderr=err)
        try:
            if data:
                process.stdin.write(data); process.stdin.close()
            deadline=time.monotonic()+timeout
            while process.poll() is None:
                if time.monotonic()>deadline or out.tell()>4194304 or err.tell()>4194304:
                    raise RuntimeError('local_command_time_or_output_bound')
                time.sleep(0.1)
        finally:
            if process.poll() is None: process.kill(); process.wait(timeout=10)
        result=process

        out.seek(0); err.seek(0)
        if result.returncode:
            raise RuntimeError(err.read().decode()[-3000:] or out.read().decode()[-3000:])
        return out.read().decode().strip()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--database-fixture', type=Path, help='Optional private disposable-only migrated dump; flushed before use')
    for name in ('app-image','postgres-image','redis-image','restic'): parser.add_argument('--'+name, required=True)
    args=parser.parse_args()
    for image in (args.app_image,args.postgres_image,args.redis_image):
        assert __import__('re').fullmatch('[0-9a-f]{64}',image)
    assert Path(args.restic).is_absolute()
    args.output.mkdir(mode=0o700)
    prefix='nautobot-session-'+uuid.uuid4().hex[:12]; network=prefix+'-net'; containers=[]; net=False
    producer=load('producer',ROOT/'restic/scripts/application-backup.py')
    generator=load('generator',ROOT/'Nautobot/ansible/scripts/make-workload-fixture.py')
    contract=yaml.safe_load((ROOT/'Nautobot/manifests/workload-test.yaml').read_text())
    # Accelerated functional qualification, not the production duration/headroom test.
    contract['fixture'].update(locations=2,devices=30,interfaces_per_device=4,ip_assignments=30)
    dataset=generator.dataset(contract)
    for phase in contract['phases']: phase['minimum_seconds']=1
    summary={'started':time.time(), 'restic_version':command([args.restic,'version']), 'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), ROOT/'restic/scripts/application-backup.py', *[ROOT/'Nautobot/ansible/scripts'/n for n in ('workload_session.py','workload_control.py','workload_jobs.py','workload_adapter.py','workload_sampler.py')]]}, 'passed':False,'host_sampler_tested':False,'ansible_host_staging_tested':False,
             'images':{'app':args.app_image,'postgresql':args.postgres_image,'redis':args.redis_image}}
    with tempfile.TemporaryDirectory(prefix='nautobot-session-local-') as temporary:
        work=Path(temporary); work.chmod(0o755)
        (work/'jobs').mkdir()
        for name in ('workload_adapter.py','workload_jobs.py'):
            shutil.copyfile(ROOT/'Nautobot/ansible/scripts'/name,work/'jobs'/name)
        shutil.copyfile(ROOT/'Nautobot/ansible/scripts/workload_control.py',work/'workload_control.py')
        config=work/'nautobot_config.py'
        config.write_text("from nautobot.core.settings import *\nPLUGINS=['nautobot_dns_models']\nINSTALLATION_METRICS_ENABLED=False\nMETRICS_ENABLED=False\nJOBS_ROOT='/work/jobs'\n")
        env=work/'test.env'
        env.write_text('NAUTOBOT_SECRET_KEY='+secrets.token_hex(40)+'\nNAUTOBOT_DB_HOST=postgresql\nNAUTOBOT_DB_USER=nautobot\nNAUTOBOT_DB_NAME=workload_disposable\nNAUTOBOT_REDIS_HOST=redis\nNAUTOBOT_CONFIG=/work/nautobot_config.py\nPYTHONDONTWRITEBYTECODE=1\n')
        env.chmod(0o600)
        setup="import os; assert os.environ['NAUTOBOT_DB_NAME']=='workload_disposable'; import nautobot; nautobot.setup(); from django.core.management import call_command; call_command('migrate',interactive=False,verbosity=0); from django.contrib.auth import get_user_model; get_user_model().objects.create(username='admin',is_active=True,is_superuser=True); from nautobot.extras.models import Job; Job.objects.filter(module_name='workload_jobs').delete()"
        if args.database_fixture:
            producer.protected(args.database_fixture)
            summary['database_fixture_sha256']=producer.digest(args.database_fixture)
            setup=setup.replace("call_command('migrate',interactive=False,verbosity=0);", "call_command('migrate',interactive=False,verbosity=0);call_command('flush',interactive=False,verbosity=0);")
        try:
            command(['podman','network','create','--internal',network]);net=True
            for role,image,options in (
                ('postgresql',args.postgres_image,['-e','POSTGRES_HOST_AUTH_METHOD=trust','-e','POSTGRES_USER=nautobot','-e','POSTGRES_DB=workload_disposable','--tmpfs','/var/lib/postgresql/data:rw,size=1g']),
                ('redis',args.redis_image,[])):
                name=prefix+'-'+role;containers.append(name)
                command(['podman','run','-d','--ulimit','fsize=1073741824:1073741824','--name',name,'--network',network,'--network-alias',role,'--memory','1536m','--cpus','2',*options,image])
            app=prefix+'-app';containers.append(app)
            command(['podman','run','-d','--ulimit','fsize=1073741824:1073741824','--name',app,'--network',network,'--memory','3g','--cpus','2','--env-file',str(env),'-v',str(work)+':/work:ro','--entrypoint','sleep',args.app_image,'infinity'])
            for _ in range(60):
                ready=subprocess.run(['podman','exec',containers[0],'pg_isready','-U','nautobot'],capture_output=True)
                dns=subprocess.run(['podman','exec',app,'python3','-c',"import socket;socket.getaddrinfo('postgresql',5432)"],capture_output=True)
                if ready.returncode == 0 and dns.returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('disposable_database_or_dns_not_ready')
            if args.database_fixture:
                command(['podman','exec','-i',containers[0],'pg_restore','--exit-on-error','-U','nautobot','-d','workload_disposable'],data=args.database_fixture.read_bytes(),timeout=120)
            command(['podman','exec',app,'python3','-c',setup],timeout=900)
            # Keep Django loaded for the disposable client. Production SSH/exec staging
            # is deliberately not claimed by this API/phase-engine qualification.
            bridge_code = """import sys,json
sys.path.insert(0,'/work')
sys.path.insert(0,'/work/jobs')
import nautobot
nautobot.setup()
from workload_control import perform
from django.db import close_old_connections
for line in sys.stdin:
    try:
        close_old_connections()
        value=perform(json.loads(line))
    except Exception as error:
        import traceback;traceback.print_exc(file=sys.stderr)
        value={'failed':True,'error_class':type(error).__name__}
    print('WORKLOAD_CONTROL='+json.dumps(value),flush=True)
"""
            bridge_errors=tempfile.TemporaryFile()
            bridge_process=subprocess.Popen(['podman','exec','-i',app,'python3','-u','-c',bridge_code],
                stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=bridge_errors)
            buffered=b''
            def client(request):
                import select
                nonlocal buffered
                bridge_process.stdin.write(json.dumps(request).encode()+b'\n');bridge_process.stdin.flush()
                deadline=time.monotonic()+90
                while True:
                    while b'\n' in buffered:
                        line,buffered=buffered.split(b'\n',1)
                        if line.startswith(b'WORKLOAD_CONTROL='):
                            result=json.loads(line[len(b'WORKLOAD_CONTROL='):])
                            if result.get('failed'):raise RuntimeError(json.dumps(result))
                            return result
                    if time.monotonic()>deadline or len(buffered)>4194304 or bridge_errors.tell()>4194304:
                        raise RuntimeError('native_bridge_bound')
                    if select.select([bridge_process.stdout],[],[],0.1)[0]:
                        part=os.read(bridge_process.stdout.fileno(),65536)
                        if not part:raise RuntimeError('native_bridge_closed')
                        buffered+=part
            registration={k:str(uuid.uuid4()) for k in ('PilotImport','PilotExport','PilotAudit')}
            client({'action':'register','registration':registration})
            command(['podman','exec','-d',app,'nautobot-server','celery','worker','--loglevel','WARNING','--concurrency','2'])
            # Backend readiness is proven by real Job completion, not this launch status.
            backup_root=work/'backup';backup_root.mkdir(mode=0o700)
            repository=args.output/'disposable-restic-repository'
            for name,content in [('password',secrets.token_hex(32)),('credentials.json','{}'),('repository',str(repository))]:
                p=backup_root/name;p.write_text(content);p.chmod(0o600)
            base=[args.restic,'--no-cache','--repository-file',str(backup_root/'repository'),'--password-file',str(backup_root/'password')]
            command(base+['init','--repository-version','2']) # Disposable test setup only.
            repository_id=json.loads(command(base+['cat','config']))['id']
            assets=work/'assets';assets.mkdir();(assets/'media').mkdir();(assets/'media'/'qualification.txt').write_text('disposable application media\n')
            (assets/'images.json').write_text(json.dumps(summary['images']))
            (assets/'hashes.json').write_text(json.dumps({'nautobot_config.py':hashlib.sha256(config.read_bytes()).hexdigest()}))
            versions="import nautobot;nautobot.setup();import json,importlib.metadata;from django.db.migrations.recorder import MigrationRecorder;print(json.dumps({'nautobot':nautobot.__version__,'dns_models':importlib.metadata.version('nautobot-dns-models'),'migrations':list(MigrationRecorder.Migration.objects.order_by('app','name').values_list('app','name'))}))"
            podman=shutil.which('podman')
            captures={
                'postgresql_custom_dump':[podman,'exec',containers[0],'pg_dump','-U','nautobot','-d','workload_disposable','-Fc'],
                'media':['/usr/bin/tar','-C',str(assets/'media'),'-cf','-','.'],
                'configuration':['/usr/bin/cat',str(config)],
                'image_dependency_manifest':['/usr/bin/cat',str(assets/'images.json')],
                'quadlet_config_hashes':['/usr/bin/cat',str(assets/'hashes.json')],
                'versions_migrations':[podman,'exec',app,'python3','-c',versions]}
            specification={'schema_version':1,'operation_id':'disposable-workload','authorized':True,
                'execution_uid':os.getuid(),'required_filesystem':command(['/usr/bin/findmnt','-n','-o','SOURCE','--target',str(backup_root)]),
                'repository_id':repository_id,'repository_url':str(repository),'restic':args.restic,'restic_version':command([args.restic,'version']),
                'hostname':'disposable','source_consistency_reviewed':True,'timeout_seconds':1700,
                'captures':{k:{'argv':v,'maximum_bytes':67108864} for k,v in captures.items()},
                'dump_validator':[podman,'exec','-i',containers[0],'pg_restore','--list']}
            # Local rootless Podman needs this user's environment, not any production credential.
            def capture(argv, environment, deadline, **kwargs):
                if argv[0]==podman:
                    environment=dict(environment,HOME=os.environ['HOME'],XDG_RUNTIME_DIR=os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())))
                return producer.invoke(argv,environment,deadline,**kwargs)
            def backup():
                result=producer.run(backup_root,specification,capture)
                if not result['integrity_passed']: raise RuntimeError(json.dumps(result))
                return result
            session=Session(args.output,contract,client,backup)
            try:
                result=session.execute(dataset,'disposable-workload')
                summary.update(result,passed=True,celery_dispatch_tested=True,jobs=len(session.jobs))
                probe="import sys;sys.path.insert(0,'/work');import nautobot;nautobot.setup();from workload_control import perform;import json;print(json.dumps(perform("+repr({'action':'status','id':session.jobs[0]['id']})+")))"
                probe_result=json.loads(native_command([podman,'exec','-i',app,'python3','-'],probe.encode()))
                assert probe_result['status']=='SUCCESS'
                summary['native_command_boundary_verified']=True

                stopped=session.cancel_owned()
                summary['completed_job_liveness_verified']=stopped
                assert stopped,'completed_worker_liveness_unknown'
                # Real cancellation: hold the adapter's PostgreSQL lock so a native
                # audit stays running while the scoped cancel path is exercised.
                lock_process=subprocess.Popen([podman,'exec',containers[0],'psql','-U','nautobot','-d','workload_disposable','-Atc',
                    'SELECT pg_advisory_lock(78310923); SELECT pg_sleep(20);'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                try:
                    deadline=time.monotonic()+10
                    while command([podman,'exec',containers[0],'psql','-U','nautobot','-d','workload_disposable','-Atc',
                            "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND objid=78310923 AND granted"]) != '1':
                        assert time.monotonic()<deadline,'test_lock_not_acquired'
                        time.sleep(0.1)
                    cancel_root=args.output/'active-cancellation';cancel_root.mkdir(mode=0o700)
                    cancellation=Session(cancel_root,contract,client,backup)
                    cancellation.ownership=session.ownership
                    identities=cancellation.submit('audit',dataset)
                    deadline=time.monotonic()+4
                    while True:
                        row=client({'action':'status','id':identities[0]})
                        if row['started'] is not None and not row['terminal']:break
                        assert time.monotonic()<deadline and not row['terminal'],'active_job_not_observed'
                        time.sleep(0.1)
                    cancelled=cancellation.cancel_owned()
                    final_job=client({'action':'status','id':identities[0]})
                    (cancel_root/'final-job.json').write_text(json.dumps(final_job))
                    assert cancelled,'active_cancellation_unresolved'
                    assert final_job['done']-final_job['started']<4,'job_reached_its_own_five_second_lock_timeout'
                    summary['active_cancellation_verified']=True
                finally:
                    # Bounded test lock expires by itself; never kill other sessions.
                    lock_process.wait(timeout=25)

            finally:
                client({'action':'disable','registration':registration})
        except Exception as error:
            summary['passed']=False
            summary['failure_class']=type(error).__name__
            for name in containers:
                logs=subprocess.run(['podman','logs','--tail','40',name],capture_output=True,timeout=30)
                (args.output/(name+'.log')).write_bytes((logs.stdout+logs.stderr)[-65536:])
            (args.output/'failure.txt').write_text(str(error)[-4000:])
            raise
        finally:
            summary['finished']=time.time()
            if 'bridge_process' in locals():
                if bridge_process.poll() is None:
                    bridge_process.stdin.close()
                    try:bridge_process.wait(timeout=10)
                    except subprocess.TimeoutExpired:bridge_process.kill();bridge_process.wait(timeout=10)
                bridge_errors.seek(0)
                (args.output/'bridge.stderr').write_bytes(bridge_errors.read(4194304))
                bridge_errors.close()
            if 'backup_root' in locals():
                for file in backup_root.glob('application-*.json'):
                    shutil.copyfile(file,args.output/file.name)
            cleanup=[]
            for name in reversed(containers):
                r=subprocess.run(['podman','rm','-f','--volumes',name],capture_output=True)
                cleanup.append({'name':name,'removed':r.returncode==0})
            if net:
                r=subprocess.run(['podman','network','rm',network],capture_output=True)
                cleanup.append({'name':network,'removed':r.returncode==0})
            (args.output/'cleanup.json').write_text(json.dumps(cleanup,indent=2)+'\n')
            summary['cleanup_passed']=all(x['removed'] for x in cleanup)
            if not summary['cleanup_passed']:summary['passed']=False
            (args.output/'result.json').write_text(json.dumps(summary,indent=2)+'\n')
            if not summary['cleanup_passed']: raise RuntimeError('cleanup_incomplete')
    print(json.dumps(summary))

if __name__=='__main__':main()
