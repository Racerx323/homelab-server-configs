#!/usr/bin/env python3
"""Offline cold-copy, ledger, invocation and orchestration boundaries."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml
sys.dont_write_bytecode = True
ROOT=Path(__file__).resolve().parents[2]
def load(name,file):
 s=importlib.util.spec_from_file_location(name,ROOT/'Nautobot/ansible/scripts'/file)
 m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
node=load('inspection','inspect-retained-database.py');launcher=load('gate','run-database-inspection.py')

class Inspection(unittest.TestCase):
 def test_actual_cold_copy_preserves_content_links_and_metadata(self):
  with tempfile.TemporaryDirectory() as tmp:
   source=Path(tmp)/'source';source.mkdir(mode=0o700)
   (source/'data').write_bytes(b'a'*5000000);(source/'data').chmod(0o600)
   os.link(source/'data',source/'hard');(source/'link').symlink_to('data')
   result=node.copy_tree(source,Path(tmp)/'copy')
   self.assertTrue(result['verified']);self.assertEqual(node.tree(source),node.tree(Path(tmp)/'copy'))
   with self.assertRaisesRegex(ValueError,'copy_exists'):node.copy_tree(source,Path(tmp)/'copy')

 def test_copy_failure_and_corruption_do_not_pass(self):
  with tempfile.TemporaryDirectory() as tmp:
   source=Path(tmp)/'source';source.mkdir();(source/'data').write_text('original')
   with patch.object(node.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['cp'])):
    with self.assertRaises(subprocess.CalledProcessError):node.copy_tree(source,Path(tmp)/'copy')
   original=node.tree
   def corrupt(p):
    if p.name=='copy':(p/'data').write_text('bad')
    return original(p)
   with patch.object(node,'tree',side_effect=corrupt):
    with self.assertRaisesRegex(ValueError,'copy_mismatch'):node.copy_tree(source,Path(tmp)/'copy')

 def test_external_links_and_special_files_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   source=Path(tmp);(source/'link').symlink_to('/etc/passwd')
   with self.assertRaisesRegex(ValueError,'external_link'):node.tree(source)
   (source/'link').unlink();os.mkfifo(source/'pipe')
   with self.assertRaisesRegex(ValueError,'special_file'):node.tree(source)

 def test_stale_or_failed_invocation_never_ready(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);(root/'preservation.json').write_text(json.dumps({'previous_postgresql_invocation':'a'*32}))
   for state in ({'ActiveState':'active','InvocationID':'a'*32},{'ActiveState':'failed','InvocationID':'b'*32}):
    with patch.object(node,'state',return_value=state):
     with self.assertRaisesRegex(ValueError,'postgres_not_ready'):node.ready(root,{})

 def test_no_container_writers_even_when_units_stopped(self):
  with patch.object(node,'state',return_value={'ActiveState':'inactive'}),patch.object(node.runtime,'podman',return_value=[{'State':'running'}]):
   with self.assertRaisesRegex(ValueError,'container_residue'):node.stopped()

 def test_present_absent_and_malformed_ledger(self):
  base={'database':'nautobot','version':'170007','read_only':'on','ledger_exists':False,'migrations':[]}
  self.assertFalse(node.parse_ledger(json.dumps(base))['ledger_exists'])
  row={'app':'dcim','name':'0001_initial','applied':'2026-09-22T01:00:00+00:00'}
  v={**base,'ledger_exists':True,'migrations':[row]};self.assertEqual(node.parse_ledger(json.dumps(v)),v)
  for bad in ({**base,'read_only':'off'},{**base,'migrations':[row]}, {**v,'migrations':[row,row]}, {**v,'migrations':[{**row,'name':'password=secret'}]}):
   with self.assertRaises(ValueError):node.parse_ledger(json.dumps(bad))

 def test_sql_is_read_only_and_bounded(self):
  raw=json.dumps({'database':'nautobot','version':'170007','read_only':'on','ledger_exists':False,'migrations':[]}).encode()
  with patch.object(node,'ready'),patch.object(node,'query_sql',return_value=raw) as run:
   self.assertTrue(node.ledger(Path('/tmp'),{})['passed'])
  sql=run.call_args.args[0]
  self.assertTrue(sql.startswith('BEGIN READ ONLY;'))
  self.assertIn("statement_timeout = '10s'",sql);self.assertIn('LIMIT 10001',sql)
  self.assertIn('\\if :present',sql);self.assertNotIn('CREATE',sql)

 def test_wrong_bundle_does_not_launch(self):
  with patch.object(launcher,'validate',return_value={}),patch.object(launcher,'rows',return_value=[]),patch.object(launcher.bounded,'drain_process',side_effect=AssertionError('must not run')):
   with self.assertRaisesRegex(launcher.bounded.PreflightBlocked,'bundle_hash_mismatch'):launcher.execute('0'*64)

 def test_actual_ansible_failure_runs_stop(self):
  play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/inspect-retained-database.yaml').read_text())[0]
  block=play['tasks'][0];task=copy.deepcopy(next(t for t in block['block'] if t['name'].startswith('Request only')));task['ansible.builtin.command']['argv']=['/bin/false']
  stop=copy.deepcopy(block['always'][0]);stop['ansible.builtin.command']['argv']=['/bin/true']
  # Production always boundary, async submission and stop task, with harmless executables.
  fixture=[{'hosts':'localhost','gather_facts':False,'tasks':[{'block':[task],'rescue':[{'ansible.builtin.debug':{'msg':'expected fixture failure'}}],'always':[stop,{'ansible.builtin.assert':{'that':'inspection_stop.rc == 0'}}]}]}]
  with tempfile.TemporaryDirectory() as tmp:
   f=Path(tmp)/'play.yaml';f.write_text(yaml.safe_dump(fixture))
   p=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(f)],capture_output=True,timeout=45)
   self.assertEqual(p.returncode,0,p.stdout.decode()+p.stderr.decode())
  names=[x['name'] for x in block['block']]
  self.assertTrue(names[0].startswith('Arm independent'))
  self.assertIn('--no-block',next(t for t in block['block'] if t['name'].startswith('Request only'))['ansible.builtin.command']['argv'])
  self.assertIn('inspection_stopped.rc',next(t for t in block['always'] if t['name'].startswith('Disarm guard'))['when'])

 def test_playbook_syntax(self):
  p=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','--syntax-check','-i',str(ROOT/'inventory/prod/hosts.yaml'),str(ROOT/'Nautobot/ansible/playbooks/inspect-retained-database.yaml')],capture_output=True,timeout=45)
  self.assertEqual(p.returncode,0,p.stderr.decode())

if __name__=='__main__':unittest.main(verbosity=2)
