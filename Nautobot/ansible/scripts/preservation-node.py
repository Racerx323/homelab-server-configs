#!/usr/bin/env python3
"""Preservation observations/captures. Ansible owns service transitions and secrets."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import re
import shutil
import subprocess
import sys
import tempfile
import time
import workload_capture as capture
import logical_database

spec = importlib.util.spec_from_file_location('node', Path(__file__).with_name('logout-node.py'))
node = importlib.util.module_from_spec(spec); spec.loader.exec_module(node)


REASONS = frozenset(('broker_key_limit','broker_unacked_type','broker_unacked_index_type',
    'worker_reply_coverage','worker_identity_changed','worker_reply_shape','drain_timeout_no_cancellation',
    'unreviewed_broker','unreviewed_broker_keys','broker_not_empty_after_worker_stop',
    'other_database_clients_present','unsupported_postgresql_version','unsupported_relation_inventory',
    'large_objects_not_supported','domains_not_supported','definition_limit','logical_capture_limit',
    'environment_metadata','baseline_drift','baseline_service','image_drift','capture_capacity',
    'writers_not_stopped','helper_exists','helper_ownership','drain_receipt_missing','source_changed',
    'media_changed','resource_guard_failed','preservation_not_verified','target_identity',
    'services_not_ready','boot_changed','data_service_restarted','storage_error','resumed_state_changed',
    'bounded_command_failed','native_probe_failed','command_timeout','command_output_limit',
    'cli_configuration_missing','cli_import_failed','cli_permission_denied','cli_arguments_rejected'))


def safe_reason(error):
    return str(error) if isinstance(error, ValueError) and str(error) in REASONS else 'native_probe_failed'


def bounded(argv, data=None, timeout=60):
    def limits(): resource.setrlimit(resource.RLIMIT_FSIZE, (4 * 1024**2, 4 * 1024**2))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            result = subprocess.run(argv, input=data, stdout=out, stderr=err, timeout=timeout,
                                    cwd='/', preexec_fn=limits)
        except subprocess.TimeoutExpired:
            raise ValueError('command_timeout') from None
        out.seek(0); raw = out.read(4 * 1024**2 + 1)
        err.seek(0); errors = err.read(4 * 1024**2 + 1)
    if max(len(raw), len(errors)) > 4 * 1024**2:
        raise ValueError('command_output_limit')
    if result.returncode:
        for line in raw.decode(errors='replace').splitlines():
            if line.startswith('PRESERVATION_ERROR=') and line.removeprefix('PRESERVATION_ERROR=') in REASONS:
                raise ValueError(line.removeprefix('PRESERVATION_ERROR='))
        # Classify only known pre-probe failures; never retain exception messages,
        # source lines or paths (a CLI error can contain credentials or code).
        diagnostics = errors.decode(errors='replace')
        patterns = (
            (r'^FileNotFoundError: Configuration file not found at ', 'cli_configuration_missing'),
            (r'^ModuleNotFoundError:', 'cli_import_failed'),
            (r'^PermissionError:', 'cli_permission_denied'),
            (r'^nautobot-server: error: (?:unrecognized arguments|argument )', 'cli_arguments_rejected'),
        )
        for pattern, reason in patterns:
            if re.search(pattern, diagnostics, re.MULTILINE):
                raise ValueError(reason)
        raise ValueError('bounded_command_failed')
    return raw


def save(root, name, data): node.write(root, name + '.json', data)
def load(root, name): return json.loads((root / (name + '.json')).read_text())
def pod(args, **kwargs): return bounded(node.USER + ['/usr/bin/podman', *args], **kwargs)


def drain_command():
    # Nautobot's outer parser owns -c/--config-path. Keep source off argv too.
    return ['exec', '-i', 'nautobot-worker', 'nautobot-server', 'shell',
            '--interface', 'python', '--command', 'import sys;exec(sys.stdin.read())']



def verify_artifacts(op):
    node.artifacts({'baseline': {'artifact_sha256': op['artifact_sha256']}})
    bounded(['/usr/bin/python3', '-I', '/usr/local/lib/nautobot-network/backend_guard.py', 'check'])


def stopped():
    raw = bounded(node.USER + ['/usr/bin/systemctl', '--user', 'show',
        *['nautobot-' + r + '.service' for r in ('web','worker','scheduler')],
        '--property=Id,ActiveState,MainPID']).decode()
    rows = [node.pairs(part) for part in raw.strip().split('\n\n')]
    if len(rows) != 3 or any(r.get('ActiveState') != 'inactive' or r.get('MainPID') != '0' for r in rows):
        raise ValueError('writers_not_stopped')


def logical(root, op, phase):
    stopped(); verify_artifacts(op)
    name = 'nautobot-preservation-' + op['token'] + '-' + phase
    # Reject pre-existing names; only the invocation's unique helper can be removed.
    existing = pod(['ps', '-a', '--format', '{{.Names}}']).decode().splitlines()
    if name in existing:
        raise ValueError('helper_exists')
    script = ('import types,sys,json\nm=types.ModuleType("logical_database");sys.modules[m.__name__]=m\n'
              + 'exec(' + repr((root/'logical_database.py').read_text()) + ',m.__dict__)\n'
              + (root/'recovery_probe.py').read_text() + '\ntry: print(json.dumps(logical()))\nexcept Exception as error:\n print(\"PRESERVATION_ERROR=\"+(str(error) if type(error) is ValueError and str(error) in ' + repr(REASONS) + ' else \"native_probe_failed\"));sys.exit(69)\n')
    argv = ['run', '--name', name, '--label', 'nautobot.preservation=' + op['token'], '--pull=never',
            '--network', 'nautobot-private', '--read-only', '--user', '999:999',
            '--memory', '768m', '--memory-swap', '768m', '--cpus', '1', '--pids-limit', '64',
            '--env-file', '/var/lib/nautobot/runtime/web.env', '-e', 'PYTHONDONTWRITEBYTECODE=1',
            '--entrypoint', 'python3', '-i', op['app_image_id'], '-']
    try:
        receipt = json.loads(pod(argv, data=script.encode(), timeout=360))
        save(root, phase, receipt)
    finally:
        names = pod(['ps', '-a', '--format', '{{.Names}}']).decode().splitlines()
        if name in names:
            label = pod(['inspect', '--format', '{{index .Config.Labels "nautobot.preservation"}}', name]).decode().strip()
            if label != op['token']:
                raise ValueError('helper_ownership')
            pod(['rm', '-f', '--volumes', name])
    return receipt


def before(root, op):
    verify_artifacts(op)
    backup=load(root,'application-backup')
    if shutil.disk_usage(root).free <= sum(c['maximum_bytes'] for c in backup['captures'].values()):
        raise ValueError('capture_capacity')
    for role in node.ROLES:
        path=Path('/var/lib/nautobot/runtime')/(role+'.env')
        info=path.lstat()
        if path.is_symlink() or not path.is_file() or info.st_uid!=999 or info.st_mode & 0o777 != 0o600:
            raise ValueError('environment_metadata')
    snapshot = node.snapshot()
    if snapshot['boot_id'] != op['boot_id'] or snapshot['http_status'] != '200':
        raise ValueError('baseline_drift')
    for role in node.ROLES:
        row = snapshot['units']['nautobot-' + role + '.service']
        if row['ActiveState'] != 'active' or row['SubState'] != 'running' or row['Result'] != 'success' or row['NRestarts'] != '0':
            raise ValueError('baseline_service')
    images = {}
    for role in node.ROLES:
        images[role] = pod(['inspect', '--format', '{{.Image}}', 'nautobot-' + role]).decode().strip()
        if not images[role].startswith('sha256:'): images[role] = 'sha256:' + images[role]
        if images[role] != op['image_ids'][role]:
            raise ValueError('image_drift')
    code = "import importlib.metadata as m,json;print(json.dumps({p:m.version(p) for p in ('nautobot','nautobot-dns-models')}))"
    versions = json.loads(pod(['exec','nautobot-web','python3','-B','-c',code]))
    save(root,'before',{'snapshot':snapshot,'images':images,'versions':versions,
                       'media':capture.empty_media(),
                       'cursor':bounded(['/usr/bin/journalctl','-n','0','--show-cursor','--no-pager']).decode().strip().split('-- cursor: ')[-1]})


def section(root, op, name):
    stopped(); verify_artifacts(op)
    metadata = load(root,'before')
    if capture.empty_media() != metadata['media']:
        raise ValueError('media_changed')
    if name not in ('image_dependency_manifest','versions_migrations'):
        subprocess.run(['/usr/bin/python3','-B',str(root/'workload_capture.py'),'--root',str(root),name], check=True, timeout=630)
        return
    if name == 'image_dependency_manifest':
        files = {p:(root/p).read_bytes() for p in ('desired-state.yaml','requirements.lock','qualified-image.json')}
        files['observed-images-before-stop.json'] = json.dumps(metadata['images'],sort_keys=True).encode()
        capture.archive(files,sys.stdout.buffer)
    else:
        sql = 'SELECT json_agg(row_to_json(m)) FROM (SELECT app,name,applied FROM django_migrations ORDER BY app,name) m'
        raw = bounded(capture.command(['psql','-X','-q','-A','-t','--no-password','-U','nautobot','-d','nautobot','-c','BEGIN READ ONLY; '+sql+'; COMMIT;']))
        print(json.dumps({'versions':metadata['versions'],'migrations':json.loads(raw)}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('phase', choices=['before','drain','logical-before','logical-after','compare','after','section'])
    parser.add_argument('section_name', nargs='?')
    args = parser.parse_args(); root=args.root; op=load(root,'preservation')
    if os.getuid()!=0 or bounded(['/usr/bin/hostname']).decode().strip()!='j2-svpi4mf':
        raise ValueError('target_identity')
    if args.phase=='before': before(root,op)
    elif args.phase=='drain':
        code=(root/'recovery_probe.py').read_text()+"\ntry: print('PRESERVATION_DRAIN='+json.dumps(native_drain()))\nexcept Exception as error:\n print('PRESERVATION_ERROR='+(str(error) if type(error) is ValueError and str(error) in "+repr(REASONS)+" else 'native_probe_failed'));raise SystemExit(69)"
        raw=pod(drain_command(),data=code.encode(),timeout=240).decode()
        rows=[r.removeprefix('PRESERVATION_DRAIN=') for r in raw.splitlines() if r.startswith('PRESERVATION_DRAIN=')]
        if len(rows)!=1: raise ValueError('drain_receipt_missing')
        save(root,'drain',json.loads(rows[0]))
    elif args.phase in ('logical-before','logical-after'): logical(root,op,args.phase)
    elif args.phase=='section': section(root,op,args.section_name)
    elif args.phase=='compare':
        stopped()
        comparison=logical_database.compare(load(root,'logical-before'),load(root,'logical-after'))
        backup=load(root,'application-backup-result')
        if load(root,'backup-resource-review')['passed'] is not True: raise ValueError('resource_guard_failed')
        if not comparison['equal'] or not backup['upload_passed'] or not backup['integrity_passed'] or not all(backup['credential_cleanup'].values()):
            raise ValueError('preservation_not_verified')
        if capture.empty_media()!=load(root,'before')['media']: raise ValueError('media_changed')
        save(root,'comparison',{'equal':True,'snapshot_id':backup['snapshot_id'],'restore_verified':False})
    else:
        verify_artifacts(op)
        old=load(root,'before'); deadline=time.monotonic()+600
        while True:
            try:
                current=node.snapshot()
                if current['http_status']!='200' or any(r['ActiveState']!='active' or r['SubState']!='running' for r in current['units'].values()):
                    raise ValueError('services_not_ready')
                break
            except Exception:
                if time.monotonic()>deadline: raise
                time.sleep(5)
        if current['boot_id']!=old['snapshot']['boot_id']: raise ValueError('boot_changed')
        for role in ('postgresql','redis'):
            key='nautobot-'+role+'.service'
            if current['units'][key]['InvocationID']!=old['snapshot']['units'][key]['InvocationID']:
                raise ValueError('data_service_restarted')
        time.sleep(75)
        journal=bounded(['/usr/bin/journalctl','-k','--after-cursor',old['cursor'],'--no-pager']).decode()
        if node.STORAGE.search(journal): raise ValueError('storage_error')
        settled=node.snapshot()
        if settled['boot_id'] != current['boot_id'] or settled['http_status'] != '200' or any(settled['units'][key] != row for key,row in current['units'].items()):
            raise ValueError('resumed_state_changed')
        save(root,'after',{'healthy':True,'accepted':False,'snapshot':current,'restored_service_checks':True})


if __name__=='__main__':
    try: main()
    except Exception as exc:
        print(json.dumps({'passed':False,'failure_class':type(exc).__name__,'reason':safe_reason(exc)}),file=sys.stderr)
        raise SystemExit(69)
