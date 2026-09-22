#!/usr/bin/env python3
"""Offline bundle, guard, isolation and teardown regressions; no live target."""
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
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]


def module(name,path):
    s=importlib.util.spec_from_file_location(name,ROOT/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


c=module('controller','Nautobot/ansible/scripts/authentication-trial.py')
n=module('node','Nautobot/ansible/scripts/auth-trial-node.py')


class Trial(unittest.TestCase):
    def setUp(self):
        p=patch.dict(c.FILES,{'operation.yaml':'Nautobot/tests/fixtures/authentication-trial-operation.yaml',
            'PLAN.md':'Nautobot/tests/fixtures/historical-plan.md'});p.start();self.addCleanup(p.stop)

    def test_frozen_producer_tamper_and_no_contact(self):
        with tempfile.TemporaryDirectory() as tmp:
            b=Path(tmp)/'bundle';c.prepare(b);digest=c.sha(b/'SHA256SUMS.json');c.verify(b,digest)
            self.assertEqual(set(json.loads((b/'spec.json').read_text())['images']),{'custom','postgresql','redis'})
            (b/'probe.py').write_text('tamper')
            with patch.object(c.subprocess,'Popen') as contact:
                with self.assertRaises(ValueError):c.execute(b,digest)
                contact.assert_not_called()

    def test_probe_diagnostics_preserve_validation_category_without_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with patch.object(n,'guard'),patch.object(n,'container',return_value={}),patch.object(n,'validate_container',side_effect=RuntimeError('secret_mount')):
                with self.assertRaises(RuntimeError):n.probe_action(root,{})
            record=n.read(root,'diagnostic')
            self.assertEqual((record['phase'],record['role'],record['category']),('validate','postgresql','secret_mount'))
            self.assertEqual(n.diagnostic_error(RuntimeError('password=DO_NOT_RECORD')), 'unclassified_failure')

    def test_real_nonzero_capture_preserves_only_allowlisted_probe_diagnostics(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);n.save(root,'diagnostic',{'phase':'django_shell'})
            rejection={'accepted':False,'checks':n.CHECKS[:1],'production_runtime_accepted':False,
                       'administrator_created':False,'failed_phase':'postgresql','error':'check_or_connection_cleanup_failed'}
            code='import sys;print("private=DO_NOT_RECORD");print('+repr(json.dumps(rejection))+');print("password=DO_NOT_RECORD",file=sys.stderr);sys.exit(69)'
            with self.assertRaises(RuntimeError):
                n.n.bounded.capture([sys.executable,'-c',code],observer=n.observed_probe(root))
            record=n.read(root,'diagnostic');self.assertEqual(record['command_rc'],69)
            self.assertEqual(record['probe_phase'],'postgresql')
            self.assertNotIn('DO_NOT_RECORD',(root/'diagnostic.json').read_text())
            rejection['failed_phase']='secret=DO_NOT_RECORD'
            n.observed_probe(root)(69,json.dumps(rejection).encode(),b'private')
            self.assertNotIn('DO_NOT_RECORD',(root/'diagnostic.json').read_text())

    def test_postgres_diagnostic_vocabulary_and_redaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);n.save(root,'diagnostic',{'phase':'django_shell'})
            value={'accepted':False,'checks':n.CHECKS[:1],'production_runtime_accepted':False,
                   'administrator_created':False,'failed_phase':'postgresql','error':'check_or_connection_cleanup_failed',
                   'failure_code':'postgres_negative_missing_sqlstate','exception_category':'CheckFailed',
                   'postgres_diagnostic':{'attempt':'negative','step':'cursor','exception_category':'OperationalError','sqlstate':'absent'}}
            n.observed_probe(root)(69,json.dumps(value).encode(),b'')
            self.assertEqual(n.read(root,'diagnostic')['postgres_diagnostic'],value['postgres_diagnostic'])
            for key in value['postgres_diagnostic']:
                bad=copy.deepcopy(value);bad['postgres_diagnostic'][key]='PRIVATE_SECRET'
                n.observed_probe(root)(69,json.dumps(bad).encode(),b'')
                self.assertEqual(n.read(root,'diagnostic')['output_category'],'no_valid_probe_result')
                self.assertNotIn('PRIVATE_SECRET',(root/'diagnostic.json').read_text())

    def test_real_capture_timeout_and_output_limit_stay_fail_closed(self):
        for code,timeout,limit in [('import time;time.sleep(2)',.05,1024),('print("x"*4096)',2,64)]:
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);n.save(root,'diagnostic',{'phase':'django_shell'})
                with self.assertRaises(RuntimeError):n.n.bounded.capture([sys.executable,'-c',code],timeout=timeout,limit=limit,observer=n.observed_probe(root))
                self.assertNotEqual(n.read(root,'diagnostic')['output_category'],'probe_reported_success')

    def test_archival_gate_rejects_missing_changed_or_unpublished_predecessor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);tag='nautobot-configuration-auth-v1-failed'
            (root/'operation.yaml').write_text(yaml.safe_dump({'predecessor':{'terminal_tag':tag}}))
            (root/'predecessor-result.json').write_bytes(b'fixed failed result')
            good=[b'tag',b'fixed failed result',b'a'*40,b'a'*40+b'\trefs/tags/'+tag.encode()+b'\n']
            with patch.object(c.subprocess,'check_output',side_effect=good):c.archival_gate(root)
            for index,replacement in [(0,b'commit'),(1,b'changed'),(3,b'')]:
                bad=good.copy();bad[index]=replacement
                with patch.object(c.subprocess,'check_output',side_effect=bad):
                    with self.assertRaises(ValueError):c.archival_gate(root)

    def test_startup_trace_redacts_messages_paths_and_source_lines(self):
        raw=b'  File "/usr/local/lib/python3.12/site-packages/nautobot/core/cli/__init__.py", line 78, in _preprocess_settings\n    password="DO_NOT_RECORD"\n  File "/private/DO_NOT_RECORD.py", line 9, in private\nOSError: [Errno 30] Read-only file system: /private/DO_NOT_RECORD\n'
        result=n.startup_diagnostic(raw)
        self.assertEqual(result['filesystem_category'],'read_only_filesystem')
        self.assertEqual(result['exception_categories'],['OSError'])
        self.assertEqual(result['frames'],[{'source':'nautobot_cli','line':78}])
        self.assertNotIn('DO_NOT_RECORD',json.dumps(result))
        for raw,expected in [(b'PermissionError: [Errno 13] private','permission_denied'),(b'FileNotFoundError: [Errno 2] private','path_missing')]:
            self.assertEqual(n.startup_diagnostic(raw)['filesystem_category'],expected)
        self.assertEqual(n.startup_diagnostic(b'UnknownSecretError: private')['exception_categories'],[])

    def test_real_startup_failure_retains_safe_trace_on_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);n.save(root,'diagnostic',{'phase':'django_shell'})
            code='raise OSError(30,"DO_NOT_RECORD")'
            with self.assertRaises(RuntimeError):
                n.n.bounded.capture([sys.executable,'-c',code],observer=n.observed_probe(root))
            record=n.read(root,'diagnostic')
            self.assertEqual(record['command_rc'],1)
            self.assertEqual(record['startup_diagnostic']['filesystem_category'],'read_only_filesystem')
            self.assertNotIn('DO_NOT_RECORD',(root/'diagnostic.json').read_text())

    def test_assertion_codes_survive_node_observer_and_reject_private_values(self):
        probe=module('diagnostic_probe','Nautobot/ansible/scripts/configuration-auth-probe.py')
        self.assertEqual(n.FAILURE_CODES,probe.FAILURE_CODES)
        self.assertEqual(n.EXCEPTION_CATEGORIES,probe.EXCEPTION_CATEGORIES)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for code in probe.FAILURE_CODES:
                n.save(root,'diagnostic',{'phase':'django_shell'})
                value={'accepted':False,'checks':[],'production_runtime_accepted':False,'administrator_created':False,
                       'failed_phase':'settings','error':'check_or_connection_cleanup_failed','failure_code':code,'exception_category':'CheckFailed'}
                n.observed_probe(root)(69,json.dumps(value).encode(),b'')
                self.assertEqual(n.read(root,'diagnostic')['failure_code'],code)
            for field in ('failure_code','exception_category'):
                value[field]='PRIVATE_SECRET'
                n.observed_probe(root)(69,json.dumps(value).encode(),b'')
                self.assertEqual(n.read(root,'diagnostic')['output_category'],'no_valid_probe_result')
                self.assertNotIn('PRIVATE_SECRET',(root/'diagnostic.json').read_text())

    def test_clean_slot_refuses_activation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'clean';p.write_text('schema_version: 1\noperation: {state: clean}\n')
            with patch.dict(c.FILES,{'operation.yaml':str(p)}):
                with self.assertRaises(Exception):c.prepare(root/'bundle')

    def test_create_commands_have_no_publication_or_data_volume(self):
        root=Path('/var/tmp/nautobot-auth-fixture');spec={'images':{k:{'reference':'repo@sha256:'+'a'*64} for k in ['custom','postgresql','redis']}}
        for role in n.ROLES:
            args=n.create_args(root,spec,role)
            for flag in ['--pull=never','--image-volume=ignore','--read-only','--timeout=900','--cpus=2','--log-driver=none']:
                self.assertIn(flag,args)
            self.assertIn('--memory-swap='+str(n.MEMORY[role])+'m',args)
            self.assertFalse(any(x.startswith('--publish') or x=='--privileged' for x in args))
            self.assertFalse(any('INITIAL_ADMIN' in x for x in args))
            if role=='probe':self.assertIn('/bin/sleep',args);self.assertIn('infinity',args)

    def fixture(self):
        root=Path('/var/tmp/nautobot-auth-fixture');spec={'images':{'postgresql':{'image_id':'a'*64}}}
        v={'Image':'a'*64,'HostConfig':{'ReadonlyRootfs':True,'Privileged':False,'PortBindings':{},'Memory':768*1024**2,'MemorySwap':768*1024**2,'Tmpfs':{path:'rw,size='+str(size)+'m' for path,size in {'/tmp':64,'/run':16,'/var/lib/postgresql/data':512,'/run/postgresql':16}.items()}},'NetworkSettings':{'Ports':{},'Networks':{root.name:{}}},'Mounts':[]}
        return root,spec,v

    def test_mount_port_network_and_memory_rejection(self):
        root,spec,v=self.fixture();n.validate_container(root,spec,'postgresql',v)
        cases=[('HostConfig','ReadonlyRootfs',False),('HostConfig','PortBindings',{'5432/tcp':[{'HostPort':'5432'}]}),('HostConfig','MemorySwap',-1),('NetworkSettings','Networks',{'host':{}})]
        for parent,key,value in cases:
            bad=copy.deepcopy(v);bad[parent][key]=value
            with self.assertRaises(RuntimeError):n.validate_container(root,spec,'postgresql',bad)
        bad=copy.deepcopy(v);bad['HostConfig']['Tmpfs']['/tmp']='rw,size=4g'
        with self.assertRaises(RuntimeError):n.validate_container(root,spec,'postgresql',bad)
        bad=copy.deepcopy(v);bad['Mounts']=[{'Type':'volume','Destination':'/var/lib/postgresql/data','Source':'production'}]
        with self.assertRaises(RuntimeError):n.validate_container(root,spec,'postgresql',bad)

    def test_effective_limits_reject_unlimited_and_wrong_cgroup(self):
        cid='a'*64
        def content(path):
            if str(path).startswith('/proc/'):return '0::/fixture/'+cid+'\n'
            return {'memory.max':str(768*1024**2),'memory.swap.max':'0','cpu.max':'200000 100000'}[path.name]
        with patch.object(n.Path,'read_text',content):
            self.assertEqual(n.effective_limits(123,cid,'postgresql')['cpus'],2)
        for filename,value in [('memory.max','max'),('memory.swap.max','max'),('cpu.max','max 100000')]:
            def bad(path):return value if path.name==filename else content(path)
            with patch.object(n.Path,'read_text',bad):
                with self.assertRaises(RuntimeError):n.effective_limits(123,cid,'postgresql')
        with patch.object(n.Path,'read_text',return_value='0::/unrelated'):
            with self.assertRaises(RuntimeError):n.effective_limits(123,cid,'postgresql')

    def test_real_tmpfs_metadata_before_and_after_start(self):
        root,spec,v=self.fixture()
        for kind in ('symlink','canonical'):
            capture=json.loads((ROOT/('Nautobot/tests/fixtures/tmpfs-'+kind+'.json')).read_text())
            for state in ('before','after'):
                v['HostConfig']['Tmpfs']=capture[state]
                if kind=='canonical':n.validate_container(root,spec,'postgresql',v)
                else:
                    with self.assertRaises(RuntimeError):n.validate_container(root,spec,'postgresql',v)
        args=n.create_args(root,{'images':{'postgresql':{'reference':'fixture'}}},'postgresql')
        self.assertIn('/run/postgresql:rw,size=16m,mode=3775',args)
        self.assertFalse(any('/var/run/postgresql' in value for value in args))
        for mutate in ('missing','extra','oversized'):
            bad=copy.deepcopy(v)
            if mutate=='missing':del bad['HostConfig']['Tmpfs']['/run/postgresql']
            elif mutate=='extra':bad['HostConfig']['Tmpfs']['/unexpected']='rw,size=16m'
            else:bad['HostConfig']['Tmpfs']['/run/postgresql']='rw,size=32m'
            with self.assertRaises(RuntimeError):n.validate_container(root,spec,'postgresql',bad)

    def test_startup_tmpfs_is_bounded_and_does_not_shadow_settings_or_packages(self):
        root=Path('/var/tmp/nautobot-auth-fixture');spec={'images':{'custom':{'reference':'fixture','image_id':'a'*64}}}
        args=n.create_args(root,spec,'probe');mounts=[args[i+1] for i,x in enumerate(args) if x=='--tmpfs']
        for name in ('git','jobs','media','static'):
            self.assertIn('/opt/nautobot/'+name+':rw,size=16m,mode=1777',mounts)
        self.assertNotIn('/opt/nautobot',[x.split(':')[0] for x in mounts])
        self.assertNotIn('/opt/nautobot/.local',[x.split(':')[0] for x in mounts])
        v={'Image':'a'*64,'HostConfig':{'ReadonlyRootfs':True,'Privileged':False,'PortBindings':{},'Memory':1536*1024**2,'MemorySwap':1536*1024**2,'Tmpfs':dict(x.split(':',1) for x in mounts)},'NetworkSettings':{'Ports':{},'Networks':{root.name:{}}},'Mounts':[]}
        for i,arg in enumerate(args):
            if arg=='--volume':
                source,destination,mode=args[i+1].split(':')
                v['Mounts'].append({'Source':source,'Destination':destination,'Type':'bind','RW':mode!='ro'})
        n.validate_container(root,spec,'probe',v)
        for options in ('rw,size=32m,mode=1777','ro,size=16m,mode=1777','rw,size=16m,mode=0755'):
            bad=copy.deepcopy(v);bad['HostConfig']['Tmpfs']['/opt/nautobot/media']=options
            with self.assertRaises(RuntimeError):n.validate_container(root,spec,'probe',bad)
        bad=copy.deepcopy(v);bad['Mounts'][0]['RW']=True
        with self.assertRaises(RuntimeError):n.validate_container(root,spec,'probe',bad)

    def test_ownership_cannot_be_inferred_from_name_alone(self):
        root=Path('/var/tmp/nautobot-auth-fixture');v={'Id':'a'*64,'Name':root.name+'-redis','Config':{'Labels':{}}}
        with patch.object(n,'pod',return_value=json.dumps([v])):
            with self.assertRaises(RuntimeError):n.container(root,'redis')

    def test_strict_probe_output_drops_private_and_partial_results(self):
        good={'accepted':True,'checks':n.CHECKS,'production_runtime_accepted':False,'administrator_created':False}
        self.assertEqual(n.probe_result('framework banner\n'+json.dumps(good)),good)
        for bad in [{**good,'private':'secret'},{**good,'checks':n.CHECKS[:-1]},{**good,'accepted':False},{**good,'administrator_created':True}]:
            with self.assertRaises(RuntimeError):n.probe_result(json.dumps(bad))

    def test_cleanup_continues_after_failure_without_force_or_prune(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);token='nautobot-auth-fixture';present={r:r[0]*64 for r in n.ROLES};calls=[]
            def pod(args,timeout=30):
                calls.append(args)
                if args[:2]==['ps','-a']:return json.dumps([{'Names':[token+'-'+r],'Id':i} for r,i in present.items()])
                if args[0]=='stop' and args[-1]==present.get('probe'):raise RuntimeError('fixture_stop_failure')
                if args[0]=='rm':
                    role=next(r for r,i in present.items() if i==args[-1])
                    if role=='probe':raise RuntimeError('fixture_remove_failure')
                    del present[role];return ''
                if args[:2]==['network','ls']:return '[]'
                return ''
            def inspect(root,role):return {'Id':present[role],'State':{'Running':True}}
            with patch.object(n,'identity',return_value=token),patch.object(n,'pod',side_effect=pod),patch.object(n,'container',side_effect=inspect):
                self.assertFalse(n.cleanup(root))
            self.assertEqual(set(present),{'probe'})
            self.assertFalse(any('prune' in a or '--force' in a for a in calls))
            result=n.read(root,'cleanup');self.assertFalse(result['probe']);self.assertTrue(result['postgresql']);self.assertTrue(result['redis'])

    def test_guard_rejects_dead_or_stopped_watchdog(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);n.save(root,'watchdog-ready',{'deadline':0,'heartbeat':0})
            with self.assertRaises(RuntimeError):n.guard(root)
            n.save(root,'watchdog-ready',{'deadline':10**12,'heartbeat':10**12});(root/'stop').touch()
            with self.assertRaises(RuntimeError):n.guard(root)

    def watch(self,mode):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);n.save(root,'spec',{});n.save(root,'before',{'cursor':'fixture','files':{},'secrets':[],'networks':[],'images':[]})
            if mode=='success':
                (root/'finish').touch();n.save(root,'probe-result',{'accepted':True})
            clock=[0.0];calls=[]
            def monotonic():clock[0]+=.001;return clock[0]
            def sleep(seconds):clock[0]+=seconds
            def clean(root,sample=None):
                calls.append('cleanup')
                if sample:sample()
                return mode!='cleanup_failure'
            def health(spec):
                if mode=='health':raise RuntimeError('storage_or_health')
                return {'monotonic':monotonic()}
            with patch.object(n.time,'monotonic',side_effect=monotonic),patch.object(n.time,'sleep',side_effect=sleep),patch.object(n.n,'health',side_effect=health),patch.object(n.n,'journal'),patch.object(n.n,'inventory',return_value={'files':{},'secrets':[],'networks':[],'images':[]}),patch.object(n,'cleanup',side_effect=clean):
                n.watchdog(root)
            return n.read(root,'result'),calls,clock[0]

    def test_controller_loss_deadline_and_health_trigger_cleanup(self):
        for mode in ['lost_controller','health','cleanup_failure']:
            result,calls,elapsed=self.watch(mode);self.assertFalse(result['accepted']);self.assertEqual(calls,['cleanup'])
            if mode=='lost_controller':self.assertGreaterEqual(elapsed,900)
        result,calls,elapsed=self.watch('success');self.assertTrue(result['accepted']);self.assertGreaterEqual(result['post_cleanup_seconds'],75)

    def test_emergency_handler_cleans_after_watchdog_killed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with patch.object(n,'cleanup',return_value=False) as cleanup:n.emergency(root)
            cleanup.assert_called_once_with(root);self.assertTrue((root/'stop').exists());self.assertFalse(n.read(root,'emergency')['accepted'])

    def test_actual_ansible_always_finishes_and_collects_after_partial_start(self):
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/authentication-trial.yaml').read_text())[0]
        block=next(t for t in play['tasks'] if 'block' in t)
        with tempfile.TemporaryDirectory(prefix='auth-ansible-fixture-') as tmp:
            root=Path(tmp);node=root/'node';node.mkdir();evidence=root/'evidence';evidence.mkdir();(node/'watchdog-ready.json').write_text('{}')
            script="""import sys,json
from pathlib import Path
mode=sys.argv[1];root=Path(sys.argv[2]);role=sys.argv[3] if len(sys.argv)>3 else ''
with (root/'trace').open('a') as f:f.write(mode+' '+role+'\\n')
if mode=='finish':(root/'result.json').write_text('{"accepted":false}')
raise SystemExit(69 if mode=='start' and role=='postgresql' else 0)
"""
            (node/'node.py').write_text(script)
            fixture=[{'name':'Production trial failure fixture','hosts':'localhost','gather_facts':False,'vars':{'node':{'path':str(node)},'bundle_root':str(ROOT/'Nautobot/ansible/playbooks'),'evidence_root':str(evidence)},'tasks':[block]}]
            path=root/'play.yaml';path.write_text(yaml.safe_dump(fixture))
            p=subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(path)],capture_output=True,text=True,timeout=90)
            self.assertNotEqual(p.returncode,0)
            self.assertTrue((node/'trace').exists(),p.stdout+p.stderr)
            trace=(node/'trace').read_text();self.assertIn('finish',trace);self.assertNotIn('create redis',trace);self.assertNotIn('probe ',trace)
            self.assertTrue((evidence/'result.json').exists(),p.stdout+p.stderr)


if __name__=='__main__':unittest.main()
