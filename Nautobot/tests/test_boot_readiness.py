#!/usr/bin/env python3
"""Offline boot-readiness scope, tamper and real Ansible rollback checks."""
from datetime import datetime, timezone
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('bundle',ROOT/'Nautobot/ansible/scripts/boot-bundle.py')
bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)

class Boot(unittest.TestCase):
    def test_scope_and_frozen_integrity(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'bundle';out.mkdir()
            for n,src in bundle.FILES.items():(out/n).write_bytes((ROOT/src).read_bytes())
            (out/'nautobot-migration.container').write_text('fixture')
            (out/'inventory.ini').write_text('fixture')
            op=json.loads((ROOT/'Nautobot/tests/fixtures/boot-operation.json').read_text())
            op['baseline']['collected_at']=datetime.now(timezone.utc).isoformat()
            op['plan_sha256']=bundle.sha(out/'PLAN.md')
            for row in op['artifacts']:row['after_sha256']=bundle.sha(out/row['name'])
            (out/'operation.json').write_text(json.dumps(op))
            (out/'bundle.json').write_text(json.dumps({'source_commit':op['operation']['source_commit'],'stage':'boot_readiness','targets':['ama@10.1.2.170'],'files':{p.name:bundle.sha(p) for p in out.iterdir()}}))
            digest=bundle.sha(out/'bundle.json');bundle.verify(out,digest)
            op=json.loads((out/'operation.json').read_text());bad=copy.deepcopy(op)
            bad['artifacts'][0]['destination']='/etc/passwd'
            with self.assertRaises(ValueError):bundle.validate(bad,json.loads((out/'schema.json').read_text()))
            (out/'startup-application.py').write_text('changed')
            with self.assertRaisesRegex(ValueError,'input_identity'):bundle.verify(out,digest)

    def test_real_partial_install_restores_both_originals(self):
        source=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/boot-readiness.yaml').read_text())[0]['tasks'][0]
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);stage=root/'stage';stage.mkdir();payload=root/'payload';payload.mkdir()
            originals=[]
            for name in ('one','two'):
                (root/name).write_text('old-'+name);(stage/('original-'+name)).write_text('old-'+name)
                originals.append({'item':{'name':name,'destination':str(root/name)},'stat':{'uid':str(__import__('os').getuid()),'gid':str(__import__('os').getgid()),'mode':'0600'}})
            # First copy succeeds; second is deliberately unavailable. Run the real
            # production install and rescue copy tasks, with daemon/reader commands
            # replaced by local no-ops so this test cannot contact systemd/hosts.
            (payload/'one').write_text('new-one')
            task=copy.deepcopy(source)
            for section in ('block','rescue'):
                for t in task[section]:
                    if 'ansible.builtin.command' in t:t['ansible.builtin.command']={'argv':['/bin/true']}
            task.pop('always')
            play=[{'hosts':'localhost','gather_facts':False,'vars':{'boot_bundle':str(payload),'boot_evidence':str(root),'boot_operation':{'root':str(stage)},'boot_originals':{'results':originals}},'tasks':[task]}]
            p=root/'play.yaml';p.write_text(yaml.safe_dump(play))
            result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(p)],capture_output=True,text=True,cwd=ROOT)
            self.assertNotEqual(result.returncode,0)
            self.assertTrue((root/'rollback.json').exists(),result.stdout+result.stderr)
            for n in ('one','two'):self.assertEqual((root/n).read_text(),'old-'+n)

    def test_no_restart_and_syntax(self):
        p=ROOT/'Nautobot/ansible/playbooks/boot-readiness.yaml';s=p.read_text()
        self.assertIn('daemon-reload',s)
        for verb in ('"restart"','"start"','"reboot"','terminate-user'):self.assertNotIn(verb,s)
        result=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','--syntax-check','-i',str(ROOT/'inventory/prod/hosts.yaml'),str(p)],capture_output=True,text=True,cwd=ROOT)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':unittest.main()
