#!/usr/bin/env python3
"""Native Restic dry-run and local disposal, with optional actual Ansible execution."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS)); sys.dont_write_bytecode = True
import disposal_qualification as node
from recurring_protection import atomic


def tree(root):
    files = {}; directories = {}
    for path in [root, *root.rglob('*')]:
        info = path.lstat(); row = dict(uid=info.st_uid, gid=info.st_gid, mode=info.st_mode & 0o777)
        if path.is_file():
            row['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        (files if path.is_file() else directories)[str(path.relative_to(root))] = row
    return dict(files=files, directories=directories)


class Contracts(unittest.TestCase):
    def test_policy_is_dry_run_and_stable_group(self):
        self.assertIn('--dry-run', node.POLICY)
        self.assertNotIn('--prune', node.POLICY)
        self.assertEqual(node.POLICY[node.POLICY.index('--group-by')+1], 'host,tags')

    def test_real_transport_and_tamper_refusal(self):
        op = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if op['operation'].get('stage') != 'recurring_disposal_retention_qualification':
            self.skipTest('no pending disposal operation')
        spec = importlib.util.spec_from_file_location('bundle', SCRIPTS/'disposal-bundle.py')
        bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory)/'candidate'
            accepted = yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text())
            if accepted.get('recurring_disposal', {}).get('operation_id') == op['operation']['id']:
                with self.assertRaisesRegex(ValueError, 'accepted_source_drift'):
                    bundle.transport.freeze(candidate)
                return
            bundle.transport.freeze(candidate)
            digest = bundle.transport.sha(candidate/'bundle.json'); bundle.transport.verify(candidate, digest)
            (candidate/'runtime/scripts/recurring_disposal.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'input_drift'):
                bundle.transport.verify(candidate, digest)


@unittest.skipUnless(os.environ.get('RESTIC_BINARY'), 'set RESTIC_BINARY for disposable native repository tests')
class Native(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.base = Path(self.temp.name)
        self.restic = str(Path(os.environ['RESTIC_BINARY']).resolve())
        self.password = self.base/'password'; self.password.write_text('local-disposable-password'); self.password.chmod(0o600)
        self.repo = self.base/'repository'
        self.env = dict(os.environ, TZ='America/Chicago', AWS_EC2_METADATA_DISABLED='true')
        self.cli('init')
        self.runroot = self.base/'run'; self.runroot.mkdir(mode=0o700)
        payload = self.runroot/'payload'; payload.mkdir(mode=0o700)
        names = ('configuration','image_dependency_manifest','media','postgresql_custom_dump','quadlet_config_hashes','versions_migrations')
        for name in names:
            path = payload/name; path.write_bytes(('disposable '+name).encode()); path.chmod(0o600)
        spec = dict(operation_id='nautobot-recurring', captures={n:{'maximum_bytes':1024} for n in names})
        self.cli('backup','--json','--host','j2-svpi4mf','--tag','nautobot-recurring',str(payload))
        self.cli('check','--read-data')
        snapshot = json.loads(self.cli('snapshots','--json'))[0]['id']
        hashes = {n:hashlib.sha256((payload/n).read_bytes()).hexdigest() for n in names}
        receipt = dict(specification_sha256=hashlib.sha256(json.dumps(spec,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                       capture_passed=True, content_sha256=hashes, credential_cleanup={'password':True,'credentials.json':True},
                       upload_passed=True, integrity_passed=True, backup_exit_status=0, integrity_exit_status=0,
                       snapshot_id=snapshot, new_snapshot_ids=[snapshot])
        atomic(self.runroot/'application-backup.json', spec)
        atomic(self.runroot/'application-capture-result.json', receipt)
        atomic(self.runroot/'application-backup-result.json', receipt)
        self.capture = self.base/'capture'; self.capture.mkdir(mode=0o700)
        state = self.capture/'state'; state.mkdir(mode=0o700)
        atomic(state/'state.json', dict(phase='complete', root=str(self.runroot), exit_status=0))
        for name in ('run.lock','state.lock'):
            (state/name).touch(mode=0o600)
        self.evidence = self.base/'evidence'; self.evidence.mkdir(mode=0o700)
        self.doppler = self.base/'doppler'
        self.doppler.write_text("#!/usr/bin/python3\nimport sys\nprint('local-disposable-password' if sys.argv[-2].endswith('PASSWORD') else 'local-disposable-key')\n")
        self.doppler.chmod(0o700)
        token = self.base/'token'; token.write_text('dp.st.'+'local-disposable'); token.chmod(0o600)
        identity = pwd.getpwuid(os.getuid())
        self.op = dict(operation=dict(id='local-disposal-test',stage='recurring_disposal_retention_qualification',
                                     execution_enabled=True,authorization_ready=True),
                       target=dict(uid=os.getuid(),gid=os.getgid(),user=identity.pw_name,home=identity.pw_dir,address='127.0.0.1'),
                       boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(), payload_root=str(self.runroot),
                       capture_root=str(self.capture),evidence_root=str(self.evidence),snapshot_id=snapshot,snapshot_ids=[snapshot],
                       eligible_snapshot_ids=[snapshot],protected_snapshot_ids=[],payload_tree=tree(self.runroot),
                       qualification_tree=tree(self.capture),services={},payload_file_metadata={n:dict(bytes=(payload/n).stat().st_size,
                           nlink=1,device=(payload/n).stat().st_dev,inode=(payload/n).stat().st_ino) for n in names},
                       restic=dict(path=self.restic,sha256=hashlib.sha256(Path(self.restic).read_bytes()).hexdigest()),
                       doppler_sha256=hashlib.sha256(self.doppler.read_bytes()).hexdigest(),
                       repository=dict(url=str(self.repo),id=json.loads(self.cli('cat','config'))['id']),
                       credentials=dict(project='homelab-dev',config='prd_nautobot_backup',read_only=True,
                           expires_at='2099-01-01T00:00:00+00:00',token_file=str(token),doppler=str(self.doppler)))

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, *args):
        return subprocess.check_output([self.restic,'--no-cache','--repo',str(self.repo),
            '--password-file',str(self.password),*args],env=self.env,stderr=subprocess.PIPE,timeout=90)

    def run_node(self):
        spec=importlib.util.spec_from_file_location('local_producer',ROOT/'restic/scripts/application-backup.py')
        producer=importlib.util.module_from_spec(spec);spec.loader.exec_module(producer)
        return node.run(self.op,self.evidence,lambda:{},call=producer.invoke)

    def test_actual_repository_disposal_and_recovery_source(self):
        before = tree(self.repo)
        self.assertEqual(self.run_node(),0)
        self.assertEqual(list((self.runroot/'payload').iterdir()),[])
        self.assertEqual(tree(self.repo),before)
        self.assertFalse(list((self.evidence/'credentials').iterdir()))
        self.assertEqual(self.run_node(),1)
        restore = self.base/'recovery-proof'
        self.cli('restore',self.op['snapshot_id'],'--target',str(restore))
        restored = restore/str(self.runroot/'payload').lstrip('/')
        self.assertEqual({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in restored.iterdir()},
                         json.loads((self.runroot/'application-backup-result.json').read_text())['content_sha256'])

    def test_remote_inventory_drift_retains_payload_and_cleans_credentials(self):
        self.op['snapshot_ids'].append('f'*64)
        self.assertEqual(self.run_node(),1)
        self.assertEqual(len(list((self.runroot/'payload').iterdir())),6)
        self.assertFalse(list((self.evidence/'credentials').iterdir()))

    def test_lock_conflict_refuses_deletion(self):
        with node.lock(self.capture/'state/run.lock',blocking=False):
            self.assertEqual(self.run_node(),1)
        self.assertEqual(len(list((self.runroot/'payload').iterdir())),6)
        self.assertFalse((self.evidence/'credentials').exists())

    def test_interrupted_partial_disposal_is_not_replayed(self):
        original = os.unlink; calls = []
        def interrupt(name,*args,**kwargs):
            if kwargs.get('dir_fd') is not None:
                calls.append(name)
                if len(calls)==2:
                    raise InterruptedError('local deletion interrupted')
            return original(name,*args,**kwargs)
        with patch('recurring_disposal.os.unlink',side_effect=interrupt):
            self.assertEqual(self.run_node(),1)
        self.assertEqual(len(list((self.runroot/'payload').iterdir())),5)
        self.assertEqual(json.loads((self.evidence/'result.json').read_text())['phase'],'manual_intervention')
        self.assertEqual(self.run_node(),1)
        self.assertEqual(len(list((self.runroot/'payload').iterdir())),5)

    def test_sparse_months_days_unrelated_snapshots_and_unique_paths(self):
        dates = [f'2024-{m:02}-03' for m in range(1,13)]+[f'2025-{m:02}-03' for m in (2,6,10)]+[
            f'2026-10-{d:02}' for d in (1,3,6,9,12,15,18,21,24,27,30)]
        for date in dates:
            source=self.base/('capture-'+date);source.mkdir();(source/'value').write_text(date)
            self.cli('backup','--json','--host','j2-svpi4mf','--tag','nautobot-recurring','--time',date+' 03:20:00',str(source))
        source=self.base/'historical';source.mkdir();(source/'value').write_text('preserve')
        self.cli('backup','--json','--host','j2-svpi4mf','--tag','recovery-reference',str(source))
        rows=json.loads(self.cli('snapshots','--json'));self.op['snapshot_ids']=[r['id'] for r in rows]
        self.op['eligible_snapshot_ids']=[r['id'] for r in rows if r['tags']==['nautobot-recurring']]
        self.op['protected_snapshot_ids']=[r['id'] for r in rows if r['tags']==['recovery-reference']]
        before=tree(self.repo);self.assertEqual(self.run_node(),0);report=json.loads((self.evidence/'retention-analysis.json').read_text())
        self.assertTrue(report['would_remove']);self.assertEqual(report['excluded'],self.op['protected_snapshot_ids'])
        self.assertIn(self.op['snapshot_id'],report['keep']);self.assertEqual(tree(self.repo),before)

    @unittest.skipUnless(os.environ.get('NAUTOBOT_DISPOSAL_NATIVE')=='1','opt-in actual local playbook/user-systemd test')
    def test_actual_playbook_service_and_replay_refusal(self):
        scripts=self.capture/'scripts';scripts.mkdir(mode=0o700);probe=scripts/'recurring_node.py'
        probe.write_text("import subprocess\ndef health():\n r=subprocess.check_output(['/usr/bin/systemctl','--user','show','dbus.service','--property=Id,ActiveState,SubState,InvocationID'],text=True,timeout=10)\n return {'dbus.service':dict(l.split('=',1) for l in r.splitlines())}\n");probe.chmod(0o600)
        scope={};exec(probe.read_text(),scope);self.op['services']=scope['health']();self.op['qualification_tree']=tree(self.capture)
        self.evidence.rmdir();bundle=self.base/'bundle';runtime=bundle/'runtime';(runtime/'scripts').mkdir(parents=True)
        for name in ('disposal_qualification.py','recurring_disposal.py','recurring_delivery.py','recurring_protection.py','capture_retained.py'):
            shutil.copyfile(SCRIPTS/name,runtime/'scripts'/name)
        shutil.copyfile(ROOT/'restic/scripts/application-backup.py',runtime/'scripts/application-backup.py')
        (runtime/'operation.json').write_text(json.dumps(self.op))
        inventory=self.base/'inventory';inventory.write_text('[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_connection=local\n')
        inputs=self.base/'inputs.json';inputs.write_text(json.dumps(dict(capture_bundle_verified=True,capture_operation=self.op,capture_bundle=str(bundle),ansible_become=False)))
        command=['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),shutil.which('ansible-playbook'),'-i',str(inventory),str(ROOT/'Nautobot/ansible/playbooks/qualify-disposal.yaml'),'-e','@'+str(inputs)]
        for attempt in range(2):
            result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=480)
            if attempt==0:self.assertEqual(result.returncode,0,result.stdout[-6000:])
            else:self.assertNotEqual(result.returncode,0)
        self.assertEqual(list((self.runroot/'payload').iterdir()),[])
        self.assertFalse(list((self.evidence/'credentials').iterdir()))
        self.assertEqual(subprocess.check_output(['/usr/bin/systemctl','--user','show','nautobot-disposal-qualification.service','--property=ActiveState','--value'],text=True).strip(),'inactive')


if __name__=='__main__':unittest.main()
