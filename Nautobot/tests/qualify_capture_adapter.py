#!/usr/bin/env python3
"""Exercise the current dump adapter with a real disposable PostgreSQL dump."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def call(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=120, **kwargs)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--image', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--expect-dump-failure', action='store_true')
    args = p.parse_args(); args.output.mkdir(mode=0o700)
    cid = call(['podman', 'run', '-d', '--pull=never', '--network=none', '-e',
                'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=nautobot', args.image]).stdout.decode().strip()
    try:
        prefix = ['podman', 'exec', '-i', '--user', 'postgres', cid]
        deadline = time.monotonic()+60
        while subprocess.run(prefix+['pg_isready', '-U', 'postgres', '-d', 'nautobot'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            assert time.monotonic() < deadline
            time.sleep(0.5)
        call(prefix+['psql', '-U', 'postgres', '-d', 'nautobot', '-c',
                    'CREATE ROLE nautobot LOGIN; CREATE TABLE sample AS SELECT n, md5(n::text) value FROM generate_series(1,1000) n;'])
        dump = call(prefix+['pg_dump', '-U', 'postgres', '-d', 'nautobot', '-Fc']).stdout
        assert dump.startswith(b'PGDMP')
        call(prefix+['pg_restore', '--list'], input=dump)
        with tempfile.TemporaryDirectory(prefix='capture-adapter.') as tmp:
            root = Path(tmp); root.chmod(0o700)
            media = root/'media'; media.mkdir()
            config = root/'configuration.py'; config.write_text('# disposable\n')
            files = {str(config): hashlib.sha256(config.read_bytes()).hexdigest()}
            for name, data in {'recurring-before.json': {'media': []}, 'backup-sources.json':
                               {'consistency': 'quiet_pilot_empty_media', 'quiet_window_confirmed': True, 'files': files}}.items():
                path = root/name; path.write_text(json.dumps(data)); path.chmod(0o600)
            driver = root/'adapter.py'
            driver.write_text('''import sys,json
from pathlib import Path
sys.path.insert(0,'''+repr(str(ROOT/'Nautobot/ansible/scripts'))+''')
import recurring_node as node
root=Path('''+repr(str(root))+''')
node.capture.CONFIG=root/'configuration.py'
node.capture.MEDIA=root/'media'
node.capture.command=lambda argv: '''+repr(prefix)+'''+['timeout','30',*argv]
node.states=lambda: {'nautobot-'+role+'.service':{'ActiveState':'active' if role in ('postgresql','redis') else 'inactive'} for role in node.ROLES}
node.section(root,{'artifact_sha256':json.loads((root/'backup-sources.json').read_text())['files']},'validate_dump')
''')
            result = subprocess.run([sys.executable, str(driver)], input=dump, capture_output=True, timeout=120)
            (args.output/'adapter.stderr').write_bytes(result.stderr)
            assert (result.returncode != 0) == args.expect_dump_failure, result.stderr.decode()
            if args.expect_dump_failure:
                assert b'input file is too short' in result.stderr or b'did not find magic string' in result.stderr, result.stderr
            else:
                damaged = subprocess.run([sys.executable, str(driver)], input=b'not a PostgreSQL archive', capture_output=True, timeout=120)
                assert damaged.returncode != 0
            summary={'real_postgresql_dump':True,'direct_parser_passed':True,'adapter_exit_status':result.returncode,
                     'expected_failure_reproduced':args.expect_dump_failure,'corrupt_dump_refused':not args.expect_dump_failure,
                     'dump_bytes':len(dump),'dump_sha256':hashlib.sha256(dump).hexdigest()}
            (args.output/'results.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
    finally:
        call(['podman', 'rm', '-f', '--volumes', cid])
        (args.output/'cleanup.json').write_text(json.dumps({'container_id':cid,'removed':True})+'\n')


if __name__ == '__main__':
    os.umask(0o077)
    main()
