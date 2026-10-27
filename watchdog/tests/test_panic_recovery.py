#!/usr/bin/python3
"""Offline tests of actual guards/archives/IPC; never contact or panic any host."""
import ast
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import time
import tarfile
import subprocess
import socket
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/name)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

r=load('run-panic-recovery.py');w=load('panic-worker.py')


class Guards(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.root.chmod(0o700)
        w.SPEC={'operation_id':'test'}

    def tearDown(self):self.tmp.cleanup()

    def test_explicit_identity_shared_by_observer_and_trigger(self):
        spec={'purpose':'single-panic-watchdog-recovery','authentication':{'identity_file':'/private/key'}}
        argv=r.ssh(self.root,spec)
        self.assertEqual(argv[argv.index('-i')+1],'/private/key')
        for option in ('IdentityAgent=none','IdentitiesOnly=yes','PreferredAuthentications=publickey',
                       'PasswordAuthentication=no','KbdInteractiveAuthentication=no','ForwardAgent=no'):
            self.assertIn(option,argv)
        tree=ast.parse((ROOT/'scripts/run-panic-recovery.py').read_text())
        for name in ('observe','trigger_channel'):
            fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
            calls=[n for n in ast.walk(fn) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='ssh']
            self.assertEqual(len(calls),1)
            self.assertEqual([n.id for n in calls[0].args],['directory','spec'])

    def test_real_local_identity_validation(self):
        key=self.root/'key'
        subprocess.run(['/usr/bin/ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)],check=True,capture_output=True)
        auth=r.authentication(key)
        self.assertEqual(auth['identity_file'],str(key))
        self.assertTrue(auth['public_fingerprint'].startswith('SHA256:'))
        link=self.root/'linked';link.symlink_to(key)
        with self.assertRaises(ValueError):r.authentication(link)
        key.chmod(0o644)
        with self.assertRaises(ValueError):r.authentication(key)
        key.chmod(0o600)
        subprocess.run(['/usr/bin/ssh-keygen','-q','-p','-P','','-N','test-only','-f',str(key)],check=True,capture_output=True)
        with self.assertRaisesRegex(ValueError,'noninteractive'):r.authentication(key)

    def test_authentication_drift_precedes_receipt_and_contact(self):
        spec={'purpose':'single-panic-watchdog-recovery','authentication':{'identity_file':'/private/key'}}
        with patch.object(r,'prepare',return_value=(spec,{})),patch.object(r,'read',return_value=b'{}'),\
             patch.object(r,'validate_operator'),patch.object(r,'authentication',return_value={}),\
             patch.object(r,'observe') as contact:
            with self.assertRaisesRegex(ValueError,'identity drift'):r.execute(self.root,'a',self.root/'operator.json')
            contact.assert_not_called()
        self.assertFalse((self.root/'execution.json').exists())

    def test_journal_purpose_cannot_execute_panic(self):
        with patch.object(r,'prepare',return_value=({'purpose':'watchdog-error-journal'},{})),\
             patch.object(r,'create') as receipt,patch.object(r,'trigger_channel') as trigger:
            with self.assertRaisesRegex(ValueError,'panic execution purpose'):r.execute(self.root,'hash',self.root/'operator')
            receipt.assert_not_called();trigger.assert_not_called()

    def test_inspection_rejects_panic_purpose_before_receipt(self):
        with patch.object(r,'prepare',return_value=({'purpose':'single-panic-watchdog-recovery'},{})),\
             patch.object(r,'create') as receipt,patch.object(r,'observe') as observe:
            with self.assertRaisesRegex(ValueError,'journal inspection purpose'):r.inspect_journal(self.root,'hash')
            receipt.assert_not_called();observe.assert_not_called()

    def test_journal_retains_nonempty_entries_without_accepting_health(self):
        row={'returncode':0,'stdout':'{"MESSAGE":"retained test error"}\n','stderr':''}
        with patch.object(w,'identity',return_value='old'),patch.object(w,'command',return_value=row) as command:
            result=w.journal('old')
        self.assertTrue(result['capture_complete']);self.assertEqual(result['errors'],row)
        self.assertNotIn('production_accepted',result)
        command.assert_called_once_with(['/usr/bin/journalctl','-b','-p','0..3','--quiet','--no-pager','-o','json','-n','200'])

    def test_journal_boot_drift_retains_partial_capture(self):
        with patch.object(w,'identity',side_effect=['old',ValueError('boot drift')]),\
             patch.object(w,'command',return_value={'stdout':'retained'}),patch.object(w,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'boot drift'):w.journal('old')
        row=emit.call_args.args[0]
        self.assertFalse(row['capture_complete']);self.assertEqual(row['errors']['stdout'],'retained')

    def test_full_journal_rejection_retains_completed_fields(self):
        def command(argv):
            if argv[0]=='/usr/bin/vcgencmd':return {'stdout':'throttled=0x0'}
            if argv[0]=='/usr/bin/journalctl':return {'stdout':'retained error'}
            if argv[0]=='/usr/bin/findmnt':return {'stdout':'{"filesystems":[{"vfs-options":"rw"}]}'}
            return {'stdout':'[{"addr_info":[{"local":"10.1.0.51"}]}]'}
        w.SPEC={'endpoints':['10.1.0.51']}
        capacity=type('Capacity',(),{'f_bavail':20*1024**3,'f_frsize':1,'f_files':100,'f_favail':50})()
        helper=type('Passive',(),{'text_record':staticmethod(lambda *_:{'text':'40000'}),
            'COMMANDS':dict.fromkeys(('addresses','routes4','routes6','network_runtime','listeners'),['network'])})()
        readiness=type('Readiness',(),{'COMMANDS':dict.fromkeys(('mounts','boot_mount'),['/usr/bin/findmnt'])})()
        with patch.object(w,'critical',return_value={'boot':'old'}),patch.object(w,'health',return_value={'healthy':True}),\
             patch.object(w.os,'statvfs',return_value=capacity),patch.object(w,'command',side_effect=command),\
             patch.object(w,'p',helper),patch.object(w,'r',readiness),\
             patch.object(w,'journal_context',return_value={'boot':'old'}),\
             patch.object(w,'journal_policy',return_value={'healthy':False}),patch.object(w,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'current boot errors'):w.full('old')
        row=emit.call_args.args[0]
        self.assertFalse(row['capture_complete']);self.assertEqual(row['partial']['errors']['stdout'],'retained error')
        self.assertEqual(row['partial']['health'],{'healthy':True})

    def test_failed_command_retained_before_exception(self):
        helper=type('Helper',(),{'LIMIT':100,'bounded':staticmethod(lambda *a,**k:{'returncode':1,'stderr':'bounded failure'})})()
        with patch.object(w,'h',helper),patch.object(w,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'command failed'):w.command(['/fixed/read'])
        self.assertEqual(emit.call_args.args[0]['failed_command']['returncode'],1)

    def test_existing_ntp_policy_with_strict_outer_provenance(self):
        source=r.SOURCES['cutover.py']
        if not source.exists():self.skipTest('NTP classifier source absent')
        boot='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        context={'boot':boot,'ntpd_pid':836,'ntpd_started':26.0,'invocation':'a'*32}
        common={'_BOOT_ID':boot.replace('-',''),'PRIORITY':'3','_SYSTEMD_UNIT':'timeservice.service',
                '_EXE':'/usr/local/sbin/ntpd','_COMM':'ntpd','_TRANSPORT':'syslog',
                'SYSLOG_IDENTIFIER':'ntpd','_PID':'836','_SYSTEMD_INVOCATION_ID':'a'*32}
        messages=['SYNC: Found 5 servers, suggest minsane at least 3',
                  'NTSc: read 816 bytes','NTSc: Got 8 cookies, length 96, aead=15.']
        rows=[dict(common,MESSAGE=msg,__MONOTONIC_TIMESTAMP=str((27+i)*1000000)) for i,msg in enumerate(messages)]
        def raw(values):return '\n'.join(json.dumps(x) for x in values)
        with patch.object(w,'cutover',r.module('cutover',source.read_bytes())):
            self.assertTrue(w.journal_policy(raw(rows),boot,context)['healthy'])
            for key,value in [('_PID','837'),('_SYSTEMD_INVOCATION_ID','b'*32),
                              ('__MONOTONIC_TIMESTAMP','25000000'),('MESSAGE','TLS handshake failed')]:
                changed=[dict(rows[0],**{key:value}),*rows[1:]]
                self.assertFalse(w.journal_policy(raw(changed),boot,context)['healthy'])
            self.assertFalse(w.journal_policy(raw(rows+[rows[0]]),boot,context)['healthy'])
            self.assertFalse(w.journal_policy(raw(rows[:-1]),boot,context)['healthy'])
            udev=dict(rows[0],_SYSTEMD_UNIT='systemd-udevd.service',MESSAGE='missing label')
            self.assertFalse(w.journal_policy(raw(rows+[udev]),boot,context)['healthy'])
            with self.assertRaisesRegex(ValueError,'cap reached'):w.journal_policy(raw(rows[:1]*200),boot,context)
            with self.assertRaisesRegex(ValueError,'boot/priority'):w.journal_policy(raw([dict(rows[0],_BOOT_ID='b'*32)]),boot,context)

    def test_inputs_purpose_cannot_execute_panic(self):
        with patch.object(r,'prepare',return_value=({'purpose':'watchdog-journal-inputs'},{})),\
             patch.object(r,'trigger_channel') as trigger:
            with self.assertRaisesRegex(ValueError,'panic execution purpose'):r.execute(self.root,'hash',self.root/'operator')
            trigger.assert_not_called()
        self.assertFalse((self.root/'execution.json').exists())

    def test_package_inspection_only_simulates_upgrade(self):
        tree=ast.parse((ROOT/'scripts/panic-worker.py').read_text())
        fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='journal_inputs')
        argv=[ast.literal_eval(n.args[0]) for n in ast.walk(fn) if isinstance(n,ast.Call)
              and isinstance(n.func,ast.Name) and n.func.id=='command' and isinstance(n.args[0],ast.List)
              and all(isinstance(x,ast.Constant) for x in n.args[0].elts)]
        apt=[a for a in argv if a[0]=='/usr/bin/apt-get']
        self.assertEqual(len(apt),1)
        for flag in ('--simulate','Debug::NoLocking=1','Dir::Cache::pkgcache=','Dir::Cache::srcpkgcache='):
            self.assertIn(flag,apt[0])
        self.assertNotIn('update',apt[0]);self.assertEqual(apt[0][-1],'upgrade')

    def test_package_metadata_serializes_real_path_entries(self):
        item=self.root/'Release';item.write_text('local test metadata')
        passive=type('Passive',(),{'names':staticmethod(lambda *_:[item]),
            'metadata':staticmethod(lambda path:{'size':Path(path).stat().st_size} if Path(path).exists() else {'missing':True})})()
        with patch.object(w,'p',passive),patch.object(w,'protected',return_value={'sha256':'a'*64}):
            value=w.package_metadata()
            encoded=json.dumps(value,sort_keys=True)
        self.assertEqual(json.loads(encoded)['apt_lists'][str(item)]['size'],19)

    def test_exclusive_receipt_is_not_replayable(self):
        p=self.root/'receipt';r.create(p,{'n':1})
        with self.assertRaises(FileExistsError):r.create(p,{'n':2})
        self.assertEqual(json.loads(r.read(p)),{'n':1})
        self.assertEqual(p.stat().st_mode&0o777,0o600)

    def test_receipt_fsyncs_file_and_parent(self):
        with patch.object(r.os,'fsync',wraps=os.fsync) as sync:
            r.create(self.root/'receipt',{})
        self.assertEqual(sync.call_count,2)

    def test_private_input_rejects_links_modes_and_hardlinks(self):
        p=self.root/'input';r.create(p,b'x');q=self.root/'link';q.symlink_to(p)
        with self.assertRaises(ValueError):r.read(q)
        p.chmod(0o644)
        with self.assertRaises(ValueError):r.read(p)
        p.chmod(0o600);q.unlink();os.link(p,q)
        with self.assertRaises(ValueError):r.read(p)

    def test_grant_bound_to_nonce_operation_and_short_deadline(self):
        good={'nonce':'abc','operation_id':'test','action':'panic-once'}
        w.grant_valid(good,'abc',10,18)
        for changes in ({'nonce':'wrong'},{'operation_id':'other'},{'action':'reboot'},{'extra':True}):
            with self.assertRaises(ValueError):w.grant_valid({**good,**changes},'abc',10,11)
        for now in (9,18.001):
            with self.assertRaises(ValueError):w.grant_valid(good,'abc',10,now)

    def test_owner_gaps_or_second_owner_are_rejected(self):
        good={'scan_complete':True,'gaps':[],'matches':[{'pid':1,'uid':0,'exe_link':'/usr/lib/systemd/systemd','recheck_stable':True}]}
        w.safe_owner(good)
        for row in ({**good,'gaps':['race']},{**good,'scan_complete':False},{**good,'matches':good['matches']*2}):
            with self.assertRaises(ValueError):w.safe_owner(row)

    def test_missing_debugger_parameter_is_not_empty(self):
        good={'commands':{'kernel':{'returncode':0}},'kgdboc_parameter':{'text':'\n'},
              'panic_timeout':{'text':'0\n'},'cmdline_policy':{'selected_text':'console=tty1'}}
        w.safe_native(good)
        for row in ({**good,'kgdboc_parameter':{'missing':True}},
                    {**good,'panic_timeout':{'text':'10\n'}},
                    {**good,'cmdline_policy':{'selected_text':'console=tty1 kgdbwait'}}):
            with self.assertRaises(ValueError):w.safe_native(row)

    def test_timing_uses_third_sample_not_first_recovery(self):
        r.evaluate_timing(0,300,[240,270,300],'new','old')
        for end,stamps,boot in [(300.01,[240,270,300.01],'new'),(299,[240,269,299],'new'),(290,[260,290],'new'),(300,[240,270,300],'old')]:
            with self.assertRaises(ValueError):r.evaluate_timing(0,end,stamps,boot,'old')

    def test_operator_confirmation_not_approval_substitute(self):
        good={'bundle_sha256':'a','epoch':100,'clock_uncertainty_seconds':1,'fallback_identity':'unknown-hold-powered-off',
              **{k:True for k in ('aaron_attending','console_identifies_j2','laptop_independent_power','peer_serving',
              'antenna_on_j1','j2_port_identified','recovery_card_available','reservation_90_minutes','no_other_reset_actions','notes_ready')}}
        r.validate_operator(good,'a',101)
        for change in ({'bundle_sha256':'b'},{'epoch':0},{'aaron_attending':False},{'clock_uncertainty_seconds':3}):
            with self.assertRaises(ValueError):r.validate_operator({**good,**change},'a',301)

    def test_supervisor_restart_is_not_healthy_recovery(self):
        first={'boot':'new','units':{'timeservice.service':{'stdout':'MainPID=1\nInvocationID=a\nNRestarts=0\n'}}}
        r.stable_service(first,first)
        second={'boot':'new','units':{'timeservice.service':{'stdout':'MainPID=2\nInvocationID=b\nNRestarts=1\n'}}}
        with self.assertRaises(ValueError):r.stable_service(first,second)

    def test_worker_deadline_cannot_be_swallowed_as_command_error(self):
        self.assertFalse(issubclass(w.WorkerDeadline,Exception))

    def test_single_sysrq_write_and_no_standalone_execution(self):
        tree=ast.parse((ROOT/'scripts/panic-worker.py').read_text())
        writes=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)
                and isinstance(n.func.value,ast.Name) and n.func.value.id=='os' and n.func.attr=='write']
        self.assertEqual(len(writes),1);self.assertEqual(ast.literal_eval(writes[0].args[1]),b'c')
        self.assertNotIn("if __name__ == '__main__'",(ROOT/'scripts/panic-worker.py').read_text())

    def test_frozen_payload_compiles_without_target_calls(self):
        if any(not p.exists() for p in r.SOURCES.values()):self.skipTest('cross-repository dependency absent; payload compilation unavailable')
        files={n:p.read_bytes() for n,p in r.SOURCES.items()}
        files['baseline.json']=b'{"boot":"x"}'
        line=r.payload({'operation_id':'test'},files,'trigger','x')
        self.assertEqual(line.count(b'\n'),1)
        tree=ast.parse(line);inner=ast.literal_eval(tree.body[0].value.args[0]);compile(inner,'frozen','exec')
        with self.assertRaises(ValueError):r.payload({},files,'reboot','x')

    def test_actual_worker_rejects_bad_grant_without_any_write(self):
        w.BASE={'boot':'old'}
        incoming=type('Input',(),{'buffer':io.BytesIO(b'{"nonce":"wrong","operation_id":"test","action":"panic-once"}\n')})()
        with patch.object(w,'identity',return_value='old'),patch.object(w,'command'),\
             patch.object(w,'critical',return_value={}),patch.object(w,'health',return_value={}),\
             patch.object(w,'emit'),patch.object(w.secrets,'token_hex',return_value='correct'),\
             patch.object(w.sys,'stdin',incoming),patch.object(w.signal,'alarm'),\
             patch.object(w.os,'open') as opened:
            with self.assertRaises(ValueError):w.trigger()
            opened.assert_not_called()

    def test_actual_worker_one_write_primitive_on_regular_test_file(self):
        # Exercises the actual one-write path on a temporary file, never SysRq.
        # Bypassed live preflight is not evidence of hardware readiness/recovery.
        w.BASE={'boot':'old'};target=self.root/'regular-test-file';target.write_bytes(b'')
        incoming=type('Input',(),{'buffer':io.BytesIO(b'{"nonce":"correct","operation_id":"test","action":"panic-once"}\n')})()
        with patch.object(w,'identity',return_value='old'),patch.object(w,'command'),\
             patch.object(w,'critical',return_value={}),patch.object(w,'health',return_value={}),\
             patch.object(w,'emit'),patch.object(w.secrets,'token_hex',return_value='correct'),\
             patch.object(w.sys,'stdin',incoming),patch.object(w.signal,'alarm'),\
             patch.object(w,'SYSCALL_PATH',str(target)),patch.object(w.os,'write',wraps=os.write) as write:
            with self.assertRaisesRegex(RuntimeError,'attempt consumed'):w.trigger()
            self.assertEqual(write.call_count,1)
        self.assertEqual(target.read_bytes(),b'c')

    def test_actual_streamed_payload_rejects_controller_identity(self):
        if any(not p.exists() for p in r.SOURCES.values()):self.skipTest('cross-repository source absent')
        if socket.gethostname()=='j2-svntp1':self.skipTest('never exercise payload on the live target')
        files={n:p.read_bytes() for n,p in r.SOURCES.items()};files['baseline.json']=b'{}'
        raw=r.payload({'expires_epoch':time.time()+60},files,'boot',None)
        out=subprocess.run(['/usr/bin/python3','-I','-B','-c','import sys; exec(sys.stdin.buffer.readline())'],
                           input=raw,capture_output=True,timeout=5)
        self.assertNotEqual(out.returncode,0)
        self.assertIn(b'target identity',out.stderr)
        self.assertNotIn(b'ModuleNotFoundError',out.stderr)

    def make_archive(self):
        d=self.root/'watchdog-panic-recovery-20261026-v1';d.mkdir(mode=0o700)
        source=self.root/'source.py';source.write_text('value=1\n')
        self.sources={'runner.py':source}
        now=int(time.time());spec={'schema':1,'purpose':'single-panic-watchdog-recovery','operation_id':d.name,
          'authentication':{'identity_file':'/private/key','public_fingerprint':'SHA256:'+'A'*43,'agent':'none','method':'publickey'},
          'directory':str(d),'prepared_epoch':now,'expires_epoch':now+86400,'hostname':'j2-svntp1',
          'endpoints':['10.1.0.51','fd36:5aa8:6971:1::51'],'kernel_release':'6.18.50+rpt-rpi-v8','timing':r.TIMING}
        files={'runner.py':source.read_bytes(),'baseline.json':b'{}','known_hosts':b'pin',
               'operator-template.json':b'{}','operator-notes.md':b'notes','qualification.json':b'{}'}
        spec['members']={k:r.sha(v) for k,v in files.items()};files.update({'spec.json':r.encoded(spec),'review.md':r.review(spec).encode()})
        for n,b in files.items():r.create(d/n,b)
        out=io.BytesIO()
        with tarfile.open(fileobj=out,mode='w') as a:
            for n,b in files.items():
                m=tarfile.TarInfo(n);m.size=len(b);a.addfile(m,io.BytesIO(b))
        r.create(d/'execution.tar',out.getvalue());return d,r.sha(out.getvalue())

    def test_archive_wrong_hash_and_review_drift(self):
        d,digest=self.make_archive()
        with patch.object(r,'SOURCES',self.sources):
            r.prepare(d,digest)
            with self.assertRaises(ValueError):r.prepare(d,'0'*64)
            (d/'review.md').write_text('changed')
            with self.assertRaises(ValueError):r.prepare(d,digest)

    def test_source_drift_rejected(self):
        d,digest=self.make_archive();self.sources['runner.py'].write_text('changed')
        with patch.object(r,'SOURCES',self.sources):
            with self.assertRaises(ValueError):r.prepare(d,digest)

    def test_expiry_fails_before_target_contact(self):
        d,digest=self.make_archive()
        with patch.object(r,'SOURCES',self.sources),patch.object(r.time,'time',return_value=time.time()+86400):
            with self.assertRaises(ValueError):r.prepare(d,digest,window=True)

    def test_readonly_interface_rejects_destructive_mode(self):
        with self.assertRaises(ValueError):r.observe({}, {}, self.root,None,'trigger',None,10)

    def test_consumed_execution_rejected_before_ssh(self):
        r.create(self.root/'execution.json',{})
        with patch.object(r,'prepare',return_value=({'purpose':'single-panic-watchdog-recovery','authentication':{'identity_file':'/private/key'}},{})),patch.object(r,'read',return_value=b'{}'),\
             patch.object(r,'validate_operator'),patch.object(r,'authentication',return_value={'identity_file':'/private/key'}),patch.object(r,'observe') as contact:
            with self.assertRaises(FileExistsError):r.execute(self.root,'a',self.root/'operator.json')
            contact.assert_not_called()


if __name__=='__main__':unittest.main()
