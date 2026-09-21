#!/usr/bin/env python3
"""Credential path fixtures: never contact Doppler, SSH or Podman."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('credentials',ROOT/'Nautobot/ansible/scripts/provision-credentials.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)


class Credentials(unittest.TestCase):
    def test_payload_consumers_and_injection_rejection(self):
        values={k:('ab'*64 if i==0 else ('%02x'%(i+1))*32) for i,k in enumerate(c.KEYS)}
        payload=c.payloads(values)
        self.assertEqual(len(payload),7)
        for body in payload.values():self.assertNotIn(values[c.KEYS[3]],body)
        self.assertNotIn(values[c.KEYS[0]],payload['postgresql.env'])
        self.assertNotIn(values[c.KEYS[1]],payload['redis.env'])
        for value in ['bad\nINJECT=yes','a'*63,'a'*65]:
            with self.assertRaises(c.Blocked):c.payloads({**values,c.KEYS[2]:value})

    def simulate(self,fail=None):
        stored={};calls=[];payload_paths=[]
        def api(*args):
            calls.append(args)
            stage='get' if args[:2]==('secrets','get') else 'upload' if 'upload' in args else 'create' if 'create' in args else 'read'
            if fail==stage:raise c.Blocked('fixture_failure')
            if args[0]=='configs' and 'create' not in args:
                return json.dumps([{'name':'prd','environment':'prd'}]+([{'name':'prd_nautobot'}] if fail=='exists' else []))
            if args[:2]==('secrets','--only-names'):
                if fail=='shape':return 'null'
                return json.dumps(dict.fromkeys(c.META|set(stored)))
            if 'upload' in args:
                path=Path(args[2]);payload_paths.append(path);self.assertEqual(path.stat().st_mode&0o777,0o600)
                stored.update(json.loads(path.read_text()));return 'output must not be logged'
            if stage=='get':return stored[args[2]]
            return '{}'
        def play(mode,payload):
            if mode==fail:raise c.Blocked('fixture_failure')
            if payload:
                payload_paths.append(payload)
                self.assertEqual(len(list(payload.glob('*.env'))),6)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            original=tempfile.TemporaryDirectory
            class CleanupFails:
                def __init__(self,*args,**kwargs):self.inner=original(*args,**kwargs)
                def __enter__(self):return self.inner.__enter__()
                def __exit__(self,*args):
                    self.inner.__exit__(*args)
                    raise OSError('private cleanup failure')
            with patch.object(c,'doppler',side_effect=api), patch.object(c.tempfile,'TemporaryDirectory',CleanupFails if fail=='cleanup' else original):
                rc=c.transact(root,root,play)
            report=(root/'result.json').read_text()
            for v in stored.values():self.assertNotIn(v,report)
            for p in payload_paths:self.assertFalse(p.exists())
            return rc,json.loads(report),calls

    def test_success_and_secret_cleanup(self):
        rc,result,calls=self.simulate();self.assertEqual(rc,0);self.assertTrue(result['accepted'])
        self.assertEqual(result['doppler_state'],'verified')
        self.assertFalse(result['runtime_started'])

    def test_each_failure_stops_without_retry_or_rotation(self):
        for phase in ['preflight','exists','shape','create','upload','get','inject']:
            with self.subTest(phase=phase):
                rc,result,calls=self.simulate(phase);self.assertEqual(rc,69);self.assertFalse(result['accepted'])
                self.assertLessEqual(sum('upload' in call for call in calls),1)
                self.assertFalse(any('delete' in call for call in calls))
                if phase in ['preflight','exists','shape']:self.assertFalse(any('create' in x for x in calls))

    def test_cleanup_failure_is_not_accepted(self):
        rc,result,_=self.simulate('cleanup')
        self.assertEqual(rc,69)
        self.assertEqual(result['phase'],'complete')
        self.assertFalse(result['accepted'])

    def test_all_secret_tasks_hide_output_and_diff(self):
        import yaml
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/provision-credentials.yaml').read_text())[0]
        block=next(t for t in play['tasks'] if 'block' in t)
        self.assertTrue(block['no_log']);self.assertFalse(block['diff'])
        self.assertEqual(block['when'],"credential_mode == 'inject'")
        self.assertNotIn('bootstrap',str(block))

    def test_command_context_and_successful_empty_secret_list(self):
        import yaml
        from jinja2 import Environment
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/provision-credentials.yaml').read_text())[0]
        self.assertEqual(play['module_defaults']['ansible.builtin.command']['chdir'],'/')
        task=next(t for t in play['tasks'] if t['name']=='Refuse existing rootless containers or secrets')
        env=Environment();env.filters['from_json']=json.loads
        check=env.compile_expression(task['ansible.builtin.assert']['that'][1])
        for output,expected in [('',True),('[]',True),('[{"Name":"existing"}]',False)]:
            self.assertEqual(check(objects={'results':[{}, {'stdout':output}]}),expected)
        with self.assertRaises(ValueError):check(objects={'results':[{}, {'stdout':'invalid'}]})
        metadata=next(t for t in play['tasks'] if t['name']=='Read existing rootless object metadata')
        self.assertNotIn('failed_when',metadata)
        self.assertNotIn('ignore_errors',metadata)

    def test_private_process_error_timeout_and_output_cap(self):
        self.assertEqual(c.private_run([sys.executable,'-c','print("ok")']).strip(),'ok')
        for code,timeout in [('import sys;print("sensitive",file=sys.stderr);sys.exit(1)',3),('import time;time.sleep(3)',.05),('print("x"*2000000)',3)]:
            with self.assertRaises(c.Blocked) as error:c.private_run([sys.executable,'-c',code],timeout=timeout)
            self.assertNotIn('sensitive',str(error.exception))

    def test_frozen_bundle_tamper_and_no_contact_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            bundle=Path(tmp)/'bundle';c.prepare(bundle);digest=c.sha(bundle/'SHA256SUMS.json');c.verify(bundle,digest)
            (bundle/'settings.py').write_text('tamper')
            with patch.object(c,'transact') as contact:
                with self.assertRaises(c.Blocked):c.execute(bundle,digest)
                contact.assert_not_called()


if __name__=='__main__':unittest.main()
