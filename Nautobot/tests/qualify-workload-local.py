#!/usr/bin/env python3
"""Disposable rootless Podman qualification. No SSH, production inputs or ports."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]

def command(argv, timeout=900):
    result = subprocess.run(argv, capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode()[-8000:] or result.stdout.decode()[-8000:])
    return result.stdout.decode().strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--small', action='store_true', help='Small fixture for native bridge regression')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--app-image', required=True, help='Locally built image ID, not production image')
    parser.add_argument('--postgres-image', required=True)
    parser.add_argument('--redis-image', required=True)
    args = parser.parse_args()
    args.output.mkdir(mode=0o700, parents=False, exist_ok=False)
    for value in (args.app_image, args.postgres_image, args.redis_image):
        if not __import__('re').fullmatch('[0-9a-f]{64}|sha256:[0-9a-f]{64}', value):
            raise ValueError('immutable_image_ID_required')
    prefix = 'nautobot-workload-' + uuid.uuid4().hex[:12]
    network = prefix + '-net'
    containers = []
    created_network = False
    with tempfile.TemporaryDirectory(prefix='nautobot-native-') as temporary:
        work = Path(temporary); work.chmod(0o755)
        (work/'jobs').mkdir()
        for name in ('workload_adapter.py', 'workload_jobs.py'):
            shutil.copyfile(ROOT/'Nautobot/ansible/scripts'/name, work/'jobs'/name)
        shutil.copyfile(ROOT/'Nautobot/ansible/scripts/workload_control.py', work/'workload_control.py')
        shutil.copyfile(Path(__file__).with_name('workload_native.py'), work/'native.py')
        spec = importlib.util.spec_from_file_location('fixture', ROOT/'Nautobot/ansible/scripts/make-workload-fixture.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        contract = None
        if args.small:
            import yaml
            contract = yaml.safe_load((ROOT/'Nautobot/manifests/workload-test.yaml').read_text())
            contract['fixture'].update(locations=2, devices=3, interfaces_per_device=2, ip_assignments=3)
        (work/'dataset.json').write_bytes(module.canonical(module.dataset(contract)))
        (work/'nautobot_config.py').write_text("from nautobot.core.settings import *\nPLUGINS=['nautobot_dns_models']\nINSTALLATION_METRICS_ENABLED=False\nMETRICS_ENABLED=False\nJOBS_ROOT='/work/jobs'\n")
        env = work/'test.env'
        env.write_text('NAUTOBOT_SECRET_KEY='+secrets.token_hex(40)+'\nNAUTOBOT_DB_HOST=postgresql\nNAUTOBOT_DB_USER=nautobot\nNAUTOBOT_DB_NAME=workload_disposable\nNAUTOBOT_REDIS_HOST=redis\nNAUTOBOT_CONFIG=/work/nautobot_config.py\nPYTHONDONTWRITEBYTECODE=1\n')
        env.chmod(0o600)
        try:
            command(['podman', 'network', 'create', '--internal', network]); created_network = True
            for role, image, options in (
                ('postgresql', args.postgres_image, ['-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_USER=nautobot', '-e', 'POSTGRES_DB=workload_disposable', '--tmpfs', '/var/lib/postgresql/data:rw,size=1g']),
                ('redis', args.redis_image, [])):
                name=prefix+'-'+role
                command(['podman','run','-d','--name',name,'--network',network,'--network-alias',role,'--memory','1536m','--cpus','2',*options,image])
                containers.append(name)
            for _ in range(60):
                ready=subprocess.run(['podman','exec',containers[0],'pg_isready','-U','nautobot'],capture_output=True)
                if ready.returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('postgres_readiness')
            name = prefix+'-app'; containers.append(name)
            started=time.time()
            result=subprocess.run(['podman','run','--name',name,'--network',network,'--memory','3g','--cpus','2',
                '--env-file',str(env),'-v',str(work)+':/work:ro','--entrypoint','python3',args.app_image,'/work/native.py'],
                capture_output=True,timeout=1200)
            (args.output/'native.stdout').write_bytes(result.stdout)
            (args.output/'native.stderr').write_bytes(result.stderr)
            summary={'exit_status': result.returncode,'start_utc_epoch':started,'end_utc_epoch':time.time(),
                     'images':{'app':args.app_image,'postgresql':args.postgres_image,'redis':args.redis_image},
                     'input_sha256':{str(p.relative_to(work)):hashlib.sha256(p.read_bytes()).hexdigest() for p in work.rglob('*') if p.is_file() and p.name != 'test.env'}}
            (args.output/'result.json').write_text(json.dumps(summary,indent=2)+'\n')
            if result.returncode: raise RuntimeError('native_qualification_failed; inspect private output')
            print(result.stdout.decode()[-4000:])
        finally:
            cleanup=[]
            for name in reversed(containers):
                r=subprocess.run(['podman','rm','-f','--volumes',name],capture_output=True)
                cleanup.append({'name':name,'removed':r.returncode==0})
            if created_network:
                r=subprocess.run(['podman','network','rm',network],capture_output=True)
                cleanup.append({'name':network,'removed':r.returncode==0})
            (args.output/'cleanup.json').write_text(json.dumps(cleanup,indent=2)+'\n')
            if not all(r['removed'] for r in cleanup): raise RuntimeError('local_cleanup_incomplete')

if __name__=='__main__':main()
