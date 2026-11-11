#!/usr/bin/env python3
"""Launch the offline native application fixture; never contacts a live host."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]


def main():
    os.umask(0o077)
    evidence = Path(tempfile.mkdtemp(prefix='application-qualification-', dir=str(REPO.parent / '.local-evidence/uptime-kuma')))
    name = 'caddy-' + evidence.name
    print(evidence, flush=True)
    result = dict(status='failed', network='none', command='application-onboarding-regression.py',
                  launcher_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    sequence = 0

    def run(args, timeout=60, check=True):
        nonlocal sequence
        sequence += 1
        with (evidence/f'{sequence:02d}.stdout').open('w') as out, (evidence/f'{sequence:02d}.stderr').open('w') as err:
            process = subprocess.run(args, stdout=out, stderr=err, timeout=timeout)
        (evidence/f'{sequence:02d}.status').write_text(str(process.returncode)+'\n')
        if check and process.returncode:
            raise RuntimeError('qualification command failed: '+str(sequence))
        return process.returncode

    try:
        run(['podman','build','--pull=never','--network=none','-f',str(REPO/'Caddy/tests/Containerfile.application'),
             '-t','localhost/caddy-application-validation:local',str(REPO/'Caddy/tests')],timeout=300)
        result['image'] = subprocess.check_output(['podman','image','inspect','--format','{{.Id}}','localhost/caddy-application-validation:local'],text=True).strip()
        args = ['podman','run','-d','--pull','never','--name',name,'--systemd=always','--network','none','--cap-add','NET_ADMIN',
                '--tmpfs','/run','--tmpfs','/run/lock','--tmpfs','/app/data:rw,nosuid,nodev,size=64m',
                '-v',str(REPO.parent)+':/workspace:ro','-v',str(evidence)+':/qual','-e','CADDY_VALIDATION_CONTAINER=1']
        if os.environ.get('CADDY_APPLICATION_SCENARIO'):
            args += ['-e','CADDY_APPLICATION_SCENARIO='+os.environ['CADDY_APPLICATION_SCENARIO']]
        run(args+[result['image']])
        code = run(['podman','exec',name,'python3','/workspace/homelab-server-configs/Caddy/tests/application-onboarding-regression.py'],timeout=5400,check=False)
        result.update(status='passed' if code==0 else 'failed',exit=code)
    finally:
        run(['podman','exec',name,'/usr/bin/journalctl','-u','kuma-qualification-proxy.service','--no-pager','-n','80'],check=False)
        result['cleanup_status'] = run(['podman','rm','--force',name],check=False)
        if result['cleanup_status']:
            result['status']='failed'
        (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    raise SystemExit(0 if result['status']=='passed' else 1)


if __name__ == '__main__':
    main()
