#!/usr/bin/env python3
"""Kill an actual disposable user-systemd guard and independently verify finalization."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Nautobot/ansible/scripts'))
from restore_node import Restore, bounded, save, LABEL


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--qualified-root', type=Path, required=True)
    args = parser.parse_args()
    source = json.loads((args.qualified_root/'runtime.json').read_text())
    if source['context'] != 'disposable': raise ValueError('disposable_only')
    token = 'nautobot-restore-'+secrets.token_hex(12)
    root = args.qualified_root.parent/token; root.mkdir(mode=0o700)
    source['token'] = token
    save(root/'runtime.json', source)
    runtime = Restore(root)
    try:
        runtime.arm()
        # arm exits before resource creation: supervision must not depend on its process.
        runtime.active()
        bounded(['/usr/bin/podman','volume','create','--label',LABEL+'='+token,runtime.volume])
        bounded(['/usr/bin/podman','run','-d','--pull=never','--network=none','--name',runtime.name('application'),
                 '--label',LABEL+'='+token,'--memory=128m','--cpus=.25','--image-volume=ignore',
                 '--entrypoint=sleep',source['images']['application'],'infinity'])
        (root/'application.env').write_text('synthetic-credential'); (root/'application.env').chmod(0o600)
        bounded(['/usr/bin/systemctl','--user','kill','--kill-whom=main','--signal=SIGKILL',runtime.unit])
        for _ in range(60):
            if (root/'cleanup-result.json').exists(): break
            time.sleep(1)
        result = json.loads((root/'cleanup-result.json').read_text())
        if not all(result.values()): raise ValueError('guard_cleanup')
        for role in ('postgresql','redis','application'):
            if subprocess.run(['/usr/bin/podman','container','exists',runtime.name(role)], capture_output=True).returncode != 1:
                raise ValueError('container_retained')
        if subprocess.run(['/usr/bin/podman','volume','exists',runtime.volume],capture_output=True).returncode != 1:
            raise ValueError('volume_retained')
        save(root/'qualification.json', {'guard_survived_launcher_exit':True,'sigkill_cleanup':True,
                                        'containers_absent':True,'volume_absent':True,'credential_absent':not (root/'application.env').exists()})
        print(root)
    finally:
        subprocess.run(['/usr/bin/systemctl','--user','stop',runtime.unit],capture_output=True,timeout=240)
        runtime.cleanup()
        subprocess.run(['/usr/bin/systemctl','--user','reset-failed',runtime.unit],capture_output=True,timeout=10)


if __name__ == '__main__': main()
