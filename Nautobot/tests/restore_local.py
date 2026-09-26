#!/usr/bin/env python3
"""Phase adapter for Ansible's disposable application restore qualification only."""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Nautobot/ansible/scripts'))
import restore_payload


def call(argv, *, data=None, limit=4194304, timeout=900):
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        with tempfile.TemporaryFile() as source:
            if data is not None: source.write(data); source.seek(0)
            process = subprocess.Popen(argv, stdin=source, stdout=out, stderr=err)
            try:
                deadline = time.monotonic()+timeout
                while process.poll() is None:
                    if time.monotonic() > deadline or out.tell() > limit or err.tell() > 4194304:
                        raise RuntimeError('command_bound')
                    time.sleep(.1)
                if process.returncode:
                    err.seek(0)
                    (FAILURE_ROOT/'command-error.txt').write_bytes(err.read())
                    raise RuntimeError('command_exit_'+str(process.returncode))
                if out.tell() > limit: raise RuntimeError('output_bound')
                out.seek(0); return out.read()
            finally:
                if process.poll() is None: process.kill(); process.wait(timeout=10)


def save(path, value):
    path.write_text(json.dumps(value, indent=2)); path.chmod(0o600)


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def archive(path, files):
    expected = {}
    with tarfile.open(path, 'w') as stream:
        for name, data in files.items():
            member = tarfile.TarInfo(name)
            if data is None:
                member.type = tarfile.DIRTYPE; expected[name] = {'type': 'directory'}
            else:
                member.size = len(data); expected[name] = {'type':'file','sha256':hashlib.sha256(data).hexdigest()}
            stream.addfile(member, io.BytesIO(data) if data is not None else None)
    return expected


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['setup','capture','retrieve','extract','restore','compare','application','negative','cleanup'])
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); work = args.root.resolve()
    global FAILURE_ROOT
    FAILURE_ROOT = work
    spec = json.loads((work/'qualification.json').read_text())
    prefix = spec['prefix']; network = prefix+'-net'
    if not __import__('re').fullmatch('nautobot-restore-local-[a-f0-9]{12}', prefix): raise ValueError('owned_prefix')
    for image in spec['images'].values():
        if not __import__('re').fullmatch('[a-f0-9]{64}', image): raise ValueError('immutable_image')
    pg, redis, app = [prefix+'-'+role for role in ('postgresql','redis','app')]
    def pgexec(*argv, data=None):
        return call(['podman','exec','-i',pg,*argv], data=data, limit=268435456)
    def native(phase, database):
        return call(['podman','exec','-e','NAUTOBOT_DB_NAME='+database,app,'python3','/tests/restore_native.py',phase])
    def metadata(raw): return json.loads(raw.decode().split('RESTORE_METADATA=')[-1])
    def restic(*args):
        return call([spec['restic'],'--no-cache','--repository-file',str(work/'repository'),
                     '--password-file',str(work/'password'),*args])
    if args.phase == 'setup':
        for image in spec['images'].values(): call(['podman','image','exists',image])
        call(['podman','network','create','--internal','--label','nautobot.restore.local='+prefix,network])
        for role,name,options in (
            ('postgresql',pg,['--network-alias','postgresql','--tmpfs','/var/lib/postgresql/data:rw,size=1g',
                              '-e','POSTGRES_HOST_AUTH_METHOD=trust','-e','POSTGRES_USER=nautobot','-e','POSTGRES_DB=source_fixture']),
            ('redis',redis,['--network-alias','redis'])):
            call(['podman','run','-d','--pull=never','--name',name,'--network',network,'--memory','1536m','--cpus','2',
                  '--label','nautobot.restore.local='+prefix,*options,spec['images'][role]])
        config = "from nautobot.core.settings import *\nPLUGINS=['nautobot_dns_models']\nINSTALLATION_METRICS_ENABLED=False\nMETRICS_ENABLED=False\nALLOWED_HOSTS=['localhost']\n"
        (work/'nautobot_config.py').write_text(config)
        env = work/'app.env'
        env.write_text('NAUTOBOT_SECRET_KEY='+secrets.token_hex(40)+'\nNAUTOBOT_DB_HOST=postgresql\nNAUTOBOT_DB_USER=nautobot\nNAUTOBOT_DB_NAME=source_fixture\nNAUTOBOT_REDIS_HOST=redis\nNAUTOBOT_CONFIG=/work/nautobot_config.py\nPYTHONDONTWRITEBYTECODE=1\n')
        env.chmod(0o600)
        call(['podman','run','-d','--pull=never','--name',app,'--network',network,'--memory','3g','--cpus','2',
              '--label','nautobot.restore.local='+prefix,'--user','0','-e','HOME=/opt/nautobot','--env-file',str(env),
              '-v',str(work)+':/work:ro','-v',str(ROOT/'Nautobot/tests')+':/tests:ro',
              '-v',str(ROOT/'Nautobot/ansible/scripts')+':/scripts:ro',
              '--entrypoint','sleep',spec['images']['app'],'infinity'])
        for _ in range(60):
            ready=subprocess.run(['podman','exec',pg,'pg_isready','-U','nautobot'],capture_output=True)
            if ready.returncode==0: break
            time.sleep(1)
        else: raise RuntimeError('database_unready')
        net=json.loads(call(['podman','network','inspect',network]))[0]
        if not net['internal']: raise ValueError('network_not_internal')
        for name in (pg,redis,app):
            obj=json.loads(call(['podman','inspect',name]))[0]
            if obj['HostConfig'].get('PortBindings'): raise ValueError('published_ports')
        # No Internet packet is sent: the isolated namespace must have no default route.
        call(['podman','exec',app,'python3','-c',"assert not any(line.split()[1]=='00000000' for line in open('/proc/net/route').read().splitlines()[1:])"])
        if 'disposable_fixture' in spec:
            fixture=Path(spec['disposable_fixture'])
            if fixture.is_symlink() or digest(fixture)!=spec['disposable_fixture_sha256']:
                raise ValueError('disposable_fixture_identity')
            pgexec('pg_restore','--exit-on-error','--single-transaction','-U','nautobot','-d','source_fixture',data=fixture.read_bytes())
            source_metadata=metadata(native('metadata','source_fixture'))
        else:
            source_metadata=metadata(native('seed','source_fixture'))
        save(work/'source-metadata.json',source_metadata)
        save(work/'source-logical.json',json.loads(native('logical','source_fixture')))
    elif args.phase == 'capture':
        payload=work/'payload'; payload.mkdir(mode=0o700)
        (payload/'postgresql_custom_dump').write_bytes(pgexec('pg_dump','-U','nautobot','-d','source_fixture','-Fc'))
        expected={}
        config=(work/'nautobot_config.py').read_bytes()
        expected['media']=archive(payload/'media',{'.':None,'images':None})
        expected['configuration']=archive(payload/'configuration',{'nautobot_config.py':config})
        expected['quadlet_config_hashes']=archive(payload/'quadlet_config_hashes',{'SHA256.json':json.dumps({'nautobot_config.py':hashlib.sha256(config).hexdigest()}).encode()})
        expected['image_dependency_manifest']=archive(payload/'image_dependency_manifest',{'images.json':json.dumps(spec['images']).encode()})
        source=json.loads((work/'source-metadata.json').read_text())
        save(payload/'versions_migrations',{k:source[k] for k in ('versions','migrations')})
        save(work/'members.json',expected)
        (work/'repository').write_text(str(work/'disposable-repository'))
        (work/'password').write_text(secrets.token_hex(32))
        restic('init','--repository-version','2')
        restic('backup','--host','disposable-local','--tag',prefix,str(payload))
        row=json.loads(restic('snapshots','--json'))[0]
        contract={'snapshot_id':row['id'],'repository_id':json.loads(restic('cat','config'))['id'],
                  'repository_url':str(work/'disposable-repository'),'hostname':'disposable-local','tags':[prefix],
                  'payload_path':str(payload),'restic':spec['restic'],
                  'restic_version':call([spec['restic'],'version']).decode().strip(),
                  'content_sha256':{p.name:digest(p) for p in payload.iterdir()},
                  'maximum_bytes':{p.name:268435456 if p.name=='postgresql_custom_dump' else 16777216 for p in payload.iterdir()}}
        save(work/'contract.json',contract)
    elif args.phase == 'retrieve':
        destination=work/'retrieval';destination.mkdir(mode=0o700)
        for name in ('repository','password'):
            (destination/name).write_bytes((work/name).read_bytes())
        save(destination/'credentials.json',{})
        save(destination/'restore.json',json.loads((work/'contract.json').read_text()))
        call([sys.executable,str(ROOT/'restic/scripts/application-restore.py'),'--root',str(destination)],timeout=1250)
    elif args.phase == 'extract':
        restore_payload.extract(work/'retrieval/retrieved',work/'extracted',json.loads((work/'members.json').read_text()))
        # Prove recovery of configuration bytes before using its reviewed mapping.
        if (work/'extracted/configuration/nautobot_config.py').read_bytes() != (work/'nautobot_config.py').read_bytes():
            raise ValueError('config_mismatch')
    elif args.phase == 'restore':
        import restore_runtime
        restore_runtime.import_database(call, pg, 'restored_fixture', prefix,
                                        work/'retrieval/retrieved/postgresql_custom_dump')
    elif args.phase == 'compare':
        import logical_database
        before=json.loads((work/'source-logical.json').read_text())
        after=json.loads(native('logical','restored_fixture'))
        result=logical_database.compare(before,after)
        if not result['equal']: raise ValueError('logical_mismatch')
        save(work/'comparison.json',result)
    elif args.phase == 'application':
        observed=metadata(native('check','restored_fixture'))
        if observed!=json.loads((work/'source-metadata.json').read_text()): raise ValueError('metadata_or_export_mismatch')
        save(work/'application.json',{'native_checks':True,'health':True,'metadata_and_export_equal':True})
    elif args.phase == 'negative':
        import copy
        module_spec=importlib.util.spec_from_file_location('retriever',ROOT/'restic/scripts/application-restore.py')
        retriever=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(retriever)
        original=json.loads((work/'contract.json').read_text())
        results={}
        for case in ('snapshot','hash','repository'):
            contract=copy.deepcopy(original)
            if case=='snapshot':contract['snapshot_id']='0'*64
            elif case=='repository':contract['repository_id']='0'*64
            else:contract['content_sha256']['postgresql_custom_dump']='0'*64
            destination=work/('negative-'+case);destination.mkdir(mode=0o700)
            for name in ('repository','password'):(destination/name).write_bytes((work/name).read_bytes())
            save(destination/'credentials.json',{})
            result=retriever.retrieve(destination,contract)
            if result['retrieved'] or not all(result['credential_cleanup'].values()):raise ValueError('negative_retrieval')
            results[case]=True
        # Exercise corruption against the actual restored database, then discard it.
        import logical_database
        before=json.loads(native('logical','restored_fixture'))
        pgexec('psql','-X','-v','ON_ERROR_STOP=1','-U','nautobot','-d','restored_fixture','-c',
               "UPDATE dcim_manufacturer SET description='changed' WHERE name='isolated-restore-fixture'")
        if logical_database.compare(before,json.loads(native('logical','restored_fixture')))['equal']:
            raise ValueError('changed_data_accepted')
        results['database_content_mismatch']=True
        save(work/'negative.json',results)
    elif args.phase == 'cleanup':
        cleanup={}
        for name in (app,redis,pg):
            found=subprocess.run(['podman','container','exists',name],capture_output=True)
            if found.returncode==1: cleanup[name]=True;continue
            try:
                obj=json.loads(call(['podman','inspect',name]))[0]
                if obj['Config']['Labels'].get('nautobot.restore.local')!=prefix: raise ValueError('ownership')
                call(['podman','rm','-f','--volumes',name])
                cleanup[name]=subprocess.run(['podman','container','exists',name],capture_output=True).returncode==1
            except Exception: cleanup[name]=False
        try:
            if subprocess.run(['podman','network','exists',network],capture_output=True).returncode==0:
                info=json.loads(call(['podman','network','inspect',network]))[0]
                if info.get('labels',{}).get('nautobot.restore.local')!=prefix:raise ValueError('network_owner')
                call(['podman','network','rm',network])
            cleanup['network']=subprocess.run(['podman','network','exists',network],capture_output=True).returncode==1
        except Exception: cleanup['network']=False
        for path in (work/'app.env',work/'password',work/'retrieval/password',work/'retrieval/credentials.json'):
            try: path.unlink(missing_ok=True);cleanup[path.name]=not path.exists()
            except Exception: cleanup[path.name]=False
        save(work/'cleanup.json',cleanup)
        if not all(cleanup.values()): raise RuntimeError('cleanup_incomplete')
    save(work/(args.phase+'-passed.json'),{'passed':True,'phase':args.phase,'production_authorized':False})


if __name__=='__main__':main()
