#!/usr/bin/env python3
"""Real recurring sections, Restic and isolated restore; no production contact.

Only service-state/path adapters are synthetic. Database, logical probe, dump,
producer, upload, full integrity, restore comparison and disposal are real.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import recurring_logical as logical
import recurring_node as node
from recurring_disposal import dispose
from recurring_protection import atomic, protected, require


def call(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, timeout=900, **kwargs).stdout


def controller_loss(image, output):
    """Kill the probe client and its process group; conmon must still expire it."""
    token = uuid.uuid4().hex
    selector = ['podman', 'ps', '-aq', '--filter', 'label=nautobot.logical='+token]
    with tempfile.TemporaryDirectory(prefix='logical-client-loss.') as tmp:
        env = Path(tmp)/'empty.env'; env.touch(mode=0o600)
        code = ("import sys,types\nsys.path.insert(0,"+repr(str(SCRIPTS))+")\n"
                + "import recurring_logical as l,recurring_node as n\n"
                + "l.uuid.uuid4=lambda:types.SimpleNamespace(hex="+repr(token)+")\n"
                + "l.code=lambda:'import time;time.sleep(90)'\n"
                + "l.probe(n.pod,"+repr(image)+",network='none',env_file="+repr(str(env))+")\n")
        process = subprocess.Popen([sys.executable, '-B', '-c', code], start_new_session=True,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        started = time.monotonic()
        try:
            while not call(['podman', 'ps', '-q', '--filter', 'label=nautobot.logical='+token]).strip():
                assert process.poll() is None and time.monotonic()-started < 15
                time.sleep(0.2)
            os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
            while call(selector).strip():
                assert time.monotonic()-started < 45, 'helper_survived_client_loss'
                time.sleep(1)
            value = {'client_killed': True, 'helper_removed': True, 'elapsed_seconds': time.monotonic()-started}
            atomic(output, value)
            return value
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
            ids = call(selector).decode().split()
            if ids: call(['podman', 'rm', '-f', *ids])


def main():
    p = argparse.ArgumentParser()
    for role in ('app', 'postgres', 'redis'):
        p.add_argument('--'+role+'-image', required=True)
    p.add_argument('--restic', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    for value in (args.app_image, args.postgres_image, args.redis_image):
        assert re.fullmatch(r'(sha256:)?[0-9a-f]{64}', value)
    args.output.mkdir(mode=0o700)
    prefix = 'nautobot-logical-test-'+uuid.uuid4().hex[:12]
    network = prefix+'-net'
    names = []
    created = False
    results = {'production_accepted': False, 'target_timing_accepted': False}
    with tempfile.TemporaryDirectory(prefix='nautobot-logical-inputs.') as temporary:
        work = Path(temporary); work.chmod(0o755)
        env = work/'probe.env'
        env.write_text('NAUTOBOT_DB_PASSWORD=qualification-only\nNAUTOBOT_REDIS_PASSWORD=qualification-only\n')
        env.chmod(0o600)
        try:
            call(['podman', 'network', 'create', '--internal', network]); created = True
            for role, image, extra in (
                ('postgresql', args.postgres_image, ['--tmpfs', '/var/lib/postgresql/data:rw,size=1g',
                 '-e', 'POSTGRES_USER=nautobot', '-e', 'POSTGRES_DB=nautobot', '-e', 'POSTGRES_PASSWORD=qualification-only']),
                ('redis', args.redis_image, [])):
                name = prefix+'-'+role; names.append(name)
                argv = ['podman', 'run', '-d', '--pull=never', '--name', name, '--network', network,
                        '--network-alias', role, '--memory', '1536m', '--cpus', '2', *extra, image]
                if role == 'redis': argv += ['redis-server', '--requirepass', 'qualification-only']
                call(argv)
            pg = ['podman', 'exec', '-i', names[0]]
            for _ in range(60):
                if subprocess.run(pg+['pg_isready', '-U', 'nautobot'], capture_output=True).returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('postgres_readiness')
            def sql(statement):
                return call(pg+['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'nautobot', '-d', 'nautobot', '-c', statement])
            loader = importlib.util.spec_from_file_location('fixture', SCRIPTS/'make-workload-fixture.py')
            fixture = importlib.util.module_from_spec(loader); loader.loader.exec_module(fixture)
            (work/'dataset.json').write_bytes(fixture.canonical(fixture.dataset(fixture.pilot_contract())))
            (work/'nautobot_config.py').write_text("from nautobot.core.settings import *\nPLUGINS=['nautobot_dns_models']\nINSTALLATION_METRICS_ENABLED=False\nMETRICS_ENABLED=False\n")
            for f in ('dataset.json', 'nautobot_config.py'): (work/f).chmod(0o644)
            setup = prefix+'-setup'; names.append(setup)
            setup_code = "import json,nautobot;nautobot.setup();from django.core.management import call_command;call_command('migrate',interactive=False,verbosity=0);from workload_adapter import apply,DjangoStore;apply(json.load(open('/work/dataset.json')),DjangoStore(),write=True)"
            print('migrating_and_importing_agreed_pilot', flush=True)
            out = call(['podman', 'run', '--name', setup, '--pull=never', '--network', network, '--memory', '3g', '--cpus', '2',
                        '--env-file', str(env), '-e', 'NAUTOBOT_SECRET_KEY='+secrets.token_hex(40),
                        '-e', 'NAUTOBOT_DB_HOST=postgresql', '-e', 'NAUTOBOT_DB_USER=nautobot', '-e', 'NAUTOBOT_DB_NAME=nautobot',
                        '-e', 'NAUTOBOT_REDIS_HOST=redis', '-e', 'NAUTOBOT_CONFIG=/work/nautobot_config.py',
                        '-e', 'PYTHONDONTWRITEBYTECODE=1', '-e', 'PYTHONPATH=/scripts',
                        '-v', str(work)+':/work:ro', '-v', str(SCRIPTS)+':/scripts:ro', '--entrypoint', 'python3', args.app_image,
                        '-c', setup_code])
            (args.output/'setup.stdout').write_bytes(out)
            print('pilot_ready_capturing', flush=True)
            run = args.output/'run'; run.mkdir(mode=0o700)
            config = run/'configuration.py'; config.write_text('# disposable\n'); config.chmod(0o600)
            files = {str(config): hashlib.sha256(config.read_bytes()).hexdigest()}
            for n in ('desired-state.yaml', 'requirements.lock', 'qualified-image.json'): atomic(run/n, {})
            atomic(run/'recurring-before.json', {'media': [], 'images': {'web': args.app_image}, 'versions': {'nautobot': '3.2.3', 'nautobot-dns-models': '2.3.0'}})
            atomic(run/'backup-sources.json', {'consistency': 'quiet_pilot_empty_media', 'quiet_window_confirmed': True, 'files': files})
            # Remap only local namespace, paths and absent systemd. No data-result fixtures.
            driver = run/'adapter.py'
            driver.write_text("import os,sys,json\nfrom pathlib import Path\nsys.path.insert(0,"+repr(str(SCRIPTS))+")\n"
                + "import recurring_node as n\nroot=Path("+repr(str(run))+")\n"
                + "os.environ.update("+repr({k: os.environ[k] for k in ('HOME', 'XDG_RUNTIME_DIR') if k in os.environ})+")\n"
                + "n.capture.CONFIG=root/'configuration.py'\nn.media_directories=lambda: []\nn.capture.empty_media=lambda: []\n"
                + "n.capture.command=lambda argv: "+repr(pg)+"+['timeout','60',*argv]\n"
                + "n.states=lambda: {'nautobot-'+r+'.service':{'ActiveState':'active' if r in ('postgresql','redis') else 'inactive'} for r in n.ROLES}\n"
                + "original=n.pod\ndef pod(argv,**kw):\n if '--network' in argv: argv[argv.index('--network')+1]="+repr(network)+"\n if '--env-file' in argv: argv[argv.index('--env-file')+1]="+repr(str(env))+"\n return original(argv,**kw)\nn.pod=pod\n"
                + "if sys.argv[-1]=='media': n.capture.archive({},sys.stdout.buffer)\nelse: n.section(root,"+repr({'artifact_sha256': files, 'logical_reference': True, 'image_ids': {'web': args.app_image}})+",sys.argv[-1])\n")
            password = args.output/'password'; password.write_text(secrets.token_hex(32)); password.chmod(0o600)
            repo = args.output/'repository'
            restic = [str(args.restic), '--no-cache', '-r', str(repo), '-p', str(password)]
            call(restic+['init', '--repository-version', '2'])
            rid = json.loads(call(restic+['cat', 'config']))['id']
            base = [sys.executable, str(driver), '--logical-reference']
            spec = dict(schema_version=1, operation_id='nautobot-recurring', authorized=True, repository_id=rid,
                        restic=str(args.restic), restic_version=call([str(args.restic), 'version']).decode().strip(),
                        repository_url=str(repo), hostname='disposable', execution_uid=os.getuid(),
                        source_consistency_reviewed=True, timeout_seconds=450,
                        required_filesystem=call(['findmnt', '-n', '-o', 'SOURCE', '--target', str(run)]).decode().strip(),
                        captures={n: {'argv': base+[n], 'maximum_bytes': 128*1024**2 if n=='postgresql_custom_dump' else 4*1024**2}
                                  for n in node.capture.SECTIONS if n != 'validate_dump'}, dump_validator=base+['validate_dump'])
            atomic(run/'application-backup.json', spec)
            (run/'repository').write_text(str(repo)); (run/'repository').chmod(0o600)
            def credentials():
                (run/'password').write_bytes(password.read_bytes()); (run/'password').chmod(0o600)
                atomic(run/'credentials.json', {})
            producer = [sys.executable, str(ROOT/'restic/scripts/application-backup.py'), '--root', str(run)]
            credentials(); started = time.monotonic()
            call(producer+['--phase', 'capture'])
            results['capture_seconds'] = time.monotonic()-started
            assert results['capture_seconds'] < 450
            receipt = logical.read(run/'logical-capture.json'); results['logical_capture'] = receipt
            reference = logical.read(run/'logical-reference.json')
            assert len(reference['tables']) > 100
            results['table_count'] = len(reference['tables'])
            credentials(); call(producer+['--phase', 'upload'])
            upload = logical.read(run/'application-backup-result.json')
            assert upload['integrity_passed']
            # A second isolated DB service with the same network alias is unnecessary:
            # disconnect the source, restore into a new DB container on this private network.
            call(['podman', 'network', 'disconnect', network, names[0]])
            restored = prefix+'-restored'; names.append(restored)
            call(['podman', 'run', '-d', '--pull=never', '--name', restored, '--network', network, '--network-alias', 'postgresql',
                  '--memory', '1536m', '--cpus', '2', '--tmpfs', '/var/lib/postgresql/data:rw,size=1g',
                  '-e', 'POSTGRES_USER=nautobot', '-e', 'POSTGRES_DB=nautobot', '-e', 'POSTGRES_PASSWORD=qualification-only', args.postgres_image])
            for _ in range(60):
                if subprocess.run(['podman', 'exec', restored, 'pg_isready', '-U', 'nautobot'], capture_output=True).returncode == 0: break
                time.sleep(1)
            else: raise RuntimeError('restore_readiness')
            fetched = call(restic+['dump', upload['snapshot_id'], str(run/'payload/postgresql_custom_dump')])
            assert hashlib.sha256(fetched).hexdigest() == receipt['dump_sha256']
            call(['podman', 'exec', '-i', restored, 'pg_restore', '--exit-on-error', '-U', 'nautobot', '-d', 'nautobot'], input=fetched)
            restored_identity, seconds = logical.probe(node.pod, args.app_image, network=network, env_file=env)
            assert logical.compare(reference, restored_identity)['equal']; results['restore_equal'] = True
            # Real sequence drift must be refused, including a valid but different reference.
            call(['podman', 'exec', restored, 'psql', '-U', 'nautobot', '-d', 'nautobot', '-c', "SELECT nextval('django_migrations_id_seq')"])
            changed, _ = logical.probe(node.pod, args.app_image, network=network, env_file=env)
            assert not logical.compare(reference, changed)['equal']; results['sequence_drift_refused'] = True
            saved = (run/'logical-reference.json').read_bytes()
            atomic(run/'logical-reference.json', changed)
            try:
                dispose(run, protected, require, atomic); raise AssertionError('changed_reference_disposed')
            except ValueError: pass
            assert len(list((run/'payload').iterdir())) == 6
            (run/'logical-reference.json').write_bytes(saved)
            # Missing reference also leaves all six payloads intact.
            (run/'logical-reference.json').rename(run/'saved-reference.json')
            try:
                dispose(run, protected, require, atomic); raise AssertionError('missing_reference_disposed')
            except FileNotFoundError: pass
            (run/'saved-reference.json').rename(run/'logical-reference.json')
            dispose(run, protected, require, atomic)
            assert not list((run/'payload').iterdir()) and (run/'logical-reference.json').read_bytes() == saved
            results['retained_after_disposal'] = True
            # Exercise conmon's own deadline with the actual production run options.
            started = time.monotonic()
            with patch.object(logical, 'code', return_value='import time;time.sleep(90)'):
                try:
                    logical.probe(node.pod, args.app_image, network=network, env_file=env)
                    raise AssertionError('hung_probe_accepted')
                except ValueError: pass
            results['hung_probe_seconds'] = time.monotonic()-started
            assert results['hung_probe_seconds'] < 45
            assert not call(['podman', 'ps', '-aq', '--filter', 'label=nautobot.logical']).strip()
            results['helper_cleanup'] = True
            results['controller_loss'] = controller_loss(args.app_image, args.output/'controller-loss.json')
            results['images'] = {'app': args.app_image, 'postgres': args.postgres_image, 'redis': args.redis_image}
            atomic(args.output/'result.json', results)
            print(json.dumps(results), flush=True)
        finally:
            cleanup = {n: subprocess.run(['podman', 'rm', '-f', '--volumes', n], capture_output=True).returncode == 0 for n in reversed(names)}
            if created: cleanup[network] = subprocess.run(['podman', 'network', 'rm', network], capture_output=True).returncode == 0
            atomic(args.output/'cleanup.json', cleanup)
            if not all(cleanup.values()): raise RuntimeError('local_cleanup_incomplete')


if __name__ == '__main__':
    os.umask(0o077)
    main()
