#!/usr/bin/env python3
"""Qualify real preservation probes on disposable, private Podman services."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import uuid


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=240, **kwargs)


def main():
    parser=argparse.ArgumentParser()
    for name in ('postgres','redis','app'): parser.add_argument('--'+name+'-image',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    for value in (args.postgres_image,args.redis_image,args.app_image):
        if not re.fullmatch(r'(sha256:)?[0-9a-f]{64}',value): raise ValueError('immutable_image_required')
    args.output.mkdir(mode=0o700,exist_ok=False)
    prefix='nautobot-preservation-test-'+uuid.uuid4().hex[:12];network=prefix+'-net';names=[];created=False
    component=Path(__file__).resolve().parents[1]
    try:
        run(['podman','network','create','--internal',network],check=True);created=True
        for role,image,extra in (
            ('postgresql',args.postgres_image,['--tmpfs','/var/lib/postgresql/data:rw,size=512m','-e','POSTGRES_USER=nautobot','-e','POSTGRES_DB=nautobot','-e','POSTGRES_PASSWORD=qualification-only']),
            ('redis',args.redis_image,[])):
            name=prefix+'-'+role;names.append(name)
            command=['podman','run','-d','--name',name,'--network',network,'--network-alias',role,'--memory','768m','--cpus','1',*extra,image]
            if role=='redis':command+=['redis-server','--requirepass','qualification-only']
            run(command,check=True)
        for _ in range(60):
            if run(['podman','exec',names[0],'pg_isready','-U','nautobot']).returncode==0:break
            time.sleep(1)
        else:raise RuntimeError('postgres_not_ready')
        common=['--network',network,'--memory','768m','--cpus','1','-v',str(component)+':/work:ro',
                '-e','PYTHONPATH=/work/tests:/work/ansible/scripts','-e','PYTHONDONTWRITEBYTECODE=1',
                '-e','NAUTOBOT_DB_PASSWORD=qualification-only','-e','NAUTOBOT_REDIS_PASSWORD=qualification-only','--entrypoint','python3']
        worker=prefix+'-worker';names.append(worker)
        run(['podman','run','-d','--name',worker,*common,args.app_image,'-m','celery','-A','preservation_native.app',
             'worker','--pool=threads','--concurrency=1','--without-gossip','--without-mingle','--loglevel=WARNING'],check=True)
        client=prefix+'-client';names.append(client)
        result=run(['podman','run','--name',client,*common,args.app_image,'/work/tests/preservation_native.py'])
        (args.output/'tests.txt').write_text(result.stdout+result.stderr)
        (args.output/'result.json').write_text(json.dumps({'status':result.returncode,'images':[args.postgres_image,args.redis_image,args.app_image],
            'production_authorized':False,'arm64_qualified':False},indent=2))
        if result.returncode:raise RuntimeError('native_qualification_failed')
    finally:
        cleanup={name:run(['podman','rm','-f','--volumes',name]).returncode==0 for name in reversed(names)}
        if created:cleanup[network]=run(['podman','network','rm',network]).returncode==0
        (args.output/'cleanup.json').write_text(json.dumps(cleanup,indent=2))
        if not all(cleanup.values()):raise RuntimeError('cleanup_incomplete')


if __name__=='__main__':main()
