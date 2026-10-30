#!/usr/bin/python3
"""Offline tests of actual guards/archives/IPC; never contact or panic any host."""
import ast
import hashlib
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
import struct
import unittest
from unittest.mock import patch, Mock, MagicMock

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

    def test_streamed_executable_hash_exceeds_text_capture_bound(self):
        source=r.SOURCES['helper.py']
        helper=r.module('hash_test_helper',source.read_bytes())
        path=self.root/'ntpd';raw=b'\x7fELF'+b'x'*(helper.LIMIT+1)
        path.write_bytes(raw);path.chmod(0o755)
        self.assertEqual(helper.file_record(path)['error'],'file capture bound exceeded')
        row=w.executable_record(path)
        self.assertEqual(row['sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(row['size'],len(raw));self.assertNotIn('base64',row)
        self.assertNotIn('sha256',w.executable_record(path,limit=len(raw)-1))
        self.assertEqual(w.executable_record(path,limit=len(raw))['sha256'],row['sha256'])

    def test_executable_types_permissions_and_links(self):
        path=self.root/'native';path.write_bytes(b'content');path.chmod(0o755)
        link=self.root/'linked';link.symlink_to(path)
        folder=self.root/'indirect';folder.symlink_to(self.root,target_is_directory=True)
        fifo=self.root/'fifo';os.mkfifo(fifo)
        for candidate in (link,folder/'native',fifo,self.root,self.root/'missing'):
            with self.subTest(path=candidate):
                row=w.executable_record(candidate)
                self.assertIn('error',row);self.assertNotIn('sha256',row)
        path.chmod(0o644)
        self.assertIn('execute permission',w.executable_record(path)['error'])
        path.write_bytes(b'');path.chmod(0o755)
        self.assertIn('size outside',w.executable_record(path)['error'])

    def test_executable_replacement_during_hash_is_rejected(self):
        path=self.root/'native';path.write_bytes(b'original');path.chmod(0o755)
        replacement=self.root/'replacement';replacement.write_bytes(b'new-data');replacement.chmod(0o755)
        original=hashlib.sha256
        def replacing_digest():
            replacement.replace(path)
            return original()
        with patch.object(w.hashlib,'sha256',side_effect=replacing_digest):
            row=w.executable_record(path)
        self.assertIn('changed during read',row['error']);self.assertNotIn('sha256',row)

    def test_executable_mutation_during_hash_is_rejected(self):
        path=self.root/'native';path.write_bytes(b'original');path.chmod(0o755)
        original=hashlib.sha256
        def changing_digest():
            path.write_bytes(b'changed-size')
            return original()
        with patch.object(w.hashlib,'sha256',side_effect=changing_digest):
            row=w.executable_record(path)
        self.assertIn('changed during read',row['error']);self.assertNotIn('sha256',row)

    def test_protected_preserves_specific_failure_and_trust_checks(self):
        for row,why in (({'error':'file capture bound exceeded'},'capture bound'),
                        ({'missing':True},'missing'),
                        ({'sha256':'a','changed_during_read':True},'changed during read'),
                        ({'sha256':'a','uid':1000,'mode':0o755},'untrusted'),
                        ({'sha256':'a','uid':0,'mode':0o777},'untrusted'),
                        ({'sha256':'wrong','uid':0,'mode':0o755},'file drift')):
            with self.subTest(reason=why),patch.object(w,'executable_record',return_value=row),patch.object(w,'emit') as emit:
                with self.assertRaisesRegex(ValueError,why):w.protected('/fixed/ntpd','a',executable=True)
                self.assertEqual(emit.call_args.args[0]['failed_file'],{'path':'/fixed/ntpd','record':row})

    def test_failed_timing_preserves_values_without_service_actions(self):
        native={'peers':[{'variables':{'offset':15.1,'jitter':18.0}}]}
        classifier=type('Classifier',(),{'measurement_checks':staticmethod(lambda *_:{'offset':False,'jitter':False})})()
        with patch.object(w,'identity',return_value='boot'),patch.object(w,'command',return_value={'stdout':json.dumps(native)}),\
             patch.object(w,'cutover',classifier),patch.object(w,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'NTP not ready'):w.health('boot')
        row=emit.call_args.args[0]
        self.assertEqual(row['native'],native);self.assertFalse(row['checks']['jitter'])

    def test_recovery_worker_checks_service_even_when_precision_fails(self):
        native={'system':{'leap':0,'stratum':1},'peers':[
            {'status':7<<8,'variables':{'srcadr':'SHM(2)','reach':1,'offset':15,'jitter':float('nan')}}]}
        cutover=r.module('cutover_recovery_test',r.SOURCES['cutover.py'].read_bytes())
        state=Mock(side_effect=ValueError('service checked'))
        with patch.object(w,'identity',return_value='boot'), \
             patch.object(w,'command',return_value={'stdout':json.dumps(native)}), \
             patch.object(w,'cutover',cutover),patch.object(w,'p',Mock(state=state)), \
             patch.object(w,'RECIPE',{'maximum_pps_offset_ms':5,'maximum_pps_jitter_ms':1,'nts_servers':[]}), \
             patch.object(w,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'service checked'):w.health('boot',strict=False)
        state.assert_called_once()
        captured=emit.call_args.args[0]
        self.assertEqual(json.dumps(captured['native'],sort_keys=True),json.dumps(native,sort_keys=True))
        self.assertFalse(captured['checks']['finite_timing'])
        self.assertEqual(captured['stage'],'service-health')

    def test_observed_boot_requires_bound_accepted_results(self):
        folder=self.root/'observation';folder.mkdir(mode=0o700)
        results=folder/'results';results.mkdir(mode=0o700)
        boot='12345678-1234-1234-1234-123456789abc'
        facts=dict.fromkeys(('completed','all_31_on_time','all_timing_samples_pass',
            'service_continuity','boot_continuity','protected_hashes_unchanged',
            'watchdog_policy_unchanged','watchdog_owner_unchanged','watchdog_state_unchanged'),True)
        records={'assessment.json':r.encoded(facts),'boot.stdout':boot.encode(),
            'finish-boot.stdout':boot.encode(),'identity.stdout':b'j2-svntp1\n',
            'finish-kernel.stdout':b'Linux 6.18.50+rpt-rpi-v8',
            'finish-protected_hashes.stdout':('a'*64+'  /etc/ntp.conf\n').encode()}
        for name,raw in records.items():r.create(results/name,raw)
        r.create(results/'results-manifest.json',{n:{'sha256':r.sha(v),'size':len(v)} for n,v in records.items()})
        r.create(folder/'manifest.json',{})
        r.create(folder/'outcome.json',{'approved_manifest_sha256':r.sha(r.read(folder/'manifest.json')),
            'assessment_sha256':r.sha(records['assessment.json']),'bounded_timing_and_client_acceptance':True})
        base={'boot':'old','protected':{'/etc/ntp.conf':'a'*64},'native_policy':'preserved'}
        value=r.observed_baseline(base,folder)
        self.assertEqual(value['boot'],boot);self.assertEqual(value['native_policy'],'preserved')
        self.assertFalse(value['post_update_observation']['five_minute_recovery_accepted'])
        self.assertEqual(base['boot'],'old')
        with self.assertRaisesRegex(ValueError,'NTP configuration drift'):
            r.observed_baseline(dict(base,protected={'/etc/ntp.conf':'b'*64}),folder)
        (results/'boot.stdout').write_text('changed')
        with self.assertRaisesRegex(ValueError,'result drift'):r.observed_baseline(base,folder)

    def test_review_binding_survives_canonical_json_roundtrip(self):
        spec={'purpose':'single-panic-watchdog-recovery','operation_id':'test',
              'expires_epoch':1,'directory':'/private/review',
              'authentication':{'identity_file':'/private/key','public_fingerprint':'fingerprint'},
              'post_update_observation':{'outcome_sha256':'a','input_manifest_sha256':'b'}}
        self.assertEqual(r.review(spec),r.review(json.loads(r.encoded(spec))))

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
            'COMMANDS':dict.fromkeys(('addresses','routes4','routes6','network_runtime','listeners','leap_journal'),['network'])})()
        readiness=type('Readiness',(),{'COMMANDS':dict.fromkeys(('mounts','boot_mount'),['/usr/bin/findmnt'])})()
        for failure in ('journal', 'native', 'maintenance'):
            def native_file(path, **kwargs):
                if failure == 'native' and path.endswith('/ntpd'):
                    raise ValueError('native file rejected')
                return {'sha256':'a'*64}
            with self.subTest(failure=failure),patch.object(w,'critical',return_value={'boot':'old'}),\
                 patch.object(w,'health',return_value={'healthy':True}),\
                 patch.object(w.os,'statvfs',return_value=capacity),patch.object(w,'command',side_effect=command),\
                 patch.object(w,'p',helper),patch.object(w,'r',readiness),\
                 patch.object(w,'protected',side_effect=native_file),\
                 patch.object(w,'journal_context',return_value={'boot':'old'}),\
                 patch.object(w,'journal_policy',return_value={'healthy':failure != 'journal'}),\
                 patch.object(w,'emit') as emit:
                if failure == 'maintenance':
                    helper.text_record=lambda path,*_: {'missing':True} if 'needrestart' in path else {'text':'40000'}
                with self.assertRaises(ValueError):w.full('old')
            row=emit.call_args.args[0]
            self.assertFalse(row['capture_complete']);self.assertEqual(row['partial']['errors']['stdout'],'retained error')
            self.assertEqual(row['partial']['health'],{'healthy':True})
            if failure == 'native':
                self.assertEqual(row['partial']['native_tools'],{'/usr/local/bin/ntpq':{'sha256':'a'*64}})
            if failure == 'maintenance':
                self.assertEqual(len(row['partial']['native_tools']),3)
                self.assertEqual(row['partial']['maintenance_records']['/var/lib/needrestart-reporting/last-success.json'],{'missing':True})
                self.assertIn('needrestart-reporting',row['error'])

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
        r.evaluate_timing(0,1800,[1740,1770,1800],'new','old')
        for end,stamps,boot in [(1800.01,[1740,1770,1800.01],'new'),(299,[240,269,299],'new'),(290,[260,290],'new'),(300,[240,270,300],'old')]:
            with self.assertRaises(ValueError):r.evaluate_timing(0,end,stamps,boot,'old')

    def test_native_availability_does_not_require_precision_or_all_upstreams(self):
        w.RECIPE={'nts_servers':['allowed.example']}
        def value(source, status=6, **extra):
            return {'system':{'leap':0,'stratum':2}, 'peers':[
                {'status':status<<8,'variables':{'srcadr':source,'reach':1,**extra}}]}
        for source in ('SHM(0)','127.127.28.0','SHM(2)','127.127.28.2'):
            self.assertTrue(w.native_available(value(source)))
        nts=value('192.0.2.1',0x66,srchost='allowed.example',ntscookies=3)
        self.assertTrue(w.native_available(nts))
        for bad in (value('192.0.2.1',6,srchost='allowed.example',ntscookies=3),
                    value('SHM(2)',5),value('192.0.2.2',0x66,srchost='unknown',ntscookies=3)):
            self.assertFalse(w.native_available(bad))
        for system in ({'leap':3,'stratum':1},{'leap':0,'stratum':16}):
            self.assertFalse(w.native_available({**nts,'system':system}))
        nts['peers'][0]['variables']['ntscookies']=0
        self.assertFalse(w.native_available(nts))

    def test_pps_selection_supersedes_serial_system_peer(self):
        value={'system':{'leap':0,'stratum':1},'peers':[
            {'status':6<<8,'variables':{'srcadr':'SHM(0)','reach':1}},
            {'status':7<<8,'variables':{'srcadr':'SHM(2)','reach':1}}]}
        self.assertTrue(w.native_available(value))
        value['peers'][1]['status']=6<<8
        self.assertFalse(w.native_available(value))

    def client_replies(self, change=None, failure=False):
        nonce=b'12345678';raw=bytearray(48);raw[0]=0x24;raw[1]=2
        raw[12:16]=b'NTS!';raw[24:32]=nonce
        stamp=struct.pack('!II',int(time.time()+2208988800),0)
        raw[32:40]=stamp;raw[40:48]=stamp
        if change: change(raw)
        socks=[MagicMock(),MagicMock()]
        for sock in socks:
            sock.__enter__.return_value=sock;sock.recv.return_value=bytes(raw)
        if failure:socks[0].recv.side_effect=socket.timeout('v4 timeout')
        with patch.object(r.socket,'socket',side_effect=socks),patch.object(r.secrets,'token_bytes',return_value=nonce):
            rows=r.recovery_clients({'client.py':r.SOURCES['client.py'].read_bytes()})
        self.assertTrue(socks[1].send.called)
        return list(rows.values())

    def test_general_client_availability_is_not_pps_precision(self):
        for row in self.client_replies():
            self.assertTrue(row['available']);self.assertFalse(row['precision'])
        for row in self.client_replies(lambda b:(b.__setitem__(1,1),b.__setitem__(slice(12,16),b'PPS\0'))):
            self.assertTrue(row['available']);self.assertTrue(row['precision'])

    def test_both_families_attempted_when_first_times_out(self):
        rows=self.client_replies(failure=True)
        self.assertFalse(rows[0]['available']);self.assertTrue(rows[1]['available'])

    def test_client_unsynchronized_kod_nonce_and_stale_timestamps_rejected(self):
        for change in (lambda b:b.__setitem__(0,0xe4),lambda b:b.__setitem__(1,0),
                       lambda b:b.__setitem__(slice(24,32),b'wrong!!!'),
                       lambda b:b.__setitem__(slice(32,40),bytes(8)),
                       lambda b:b.__setitem__(slice(40,48),bytes(8))):
            with self.subTest(change=change):
                self.assertTrue(all(not row['available'] for row in self.client_replies(change)))

    def test_clients_retained_when_native_collection_fails(self):
        packets={'v4':{'available':True,'precision':False},'v6':{'available':True,'precision':False}}
        record=Mock()
        with patch.object(r,'recovery_clients',return_value=packets) as clients, \
             patch.object(r,'observe',side_effect=ValueError('native unavailable')):
            row=r.recovery_sample({}, {},self.root,record,'new')
        clients.assert_called_once();self.assertFalse(row['available'])
        self.assertEqual(row['clients'],packets)
        self.assertEqual(record.save.call_args_list[0].args,('recovery-clients',packets))

    def test_native_precision_failure_does_not_fail_availability(self):
        packets={k:{'available':True,'precision':True} for k in ('v4','v6')}
        with patch.object(r,'recovery_clients',return_value=packets) as clients, \
             patch.object(r,'observe',return_value={'available':True,'precision':False}):
            row=r.recovery_sample({}, {},self.root,Mock(),'new')
        clients.assert_called_once()
        self.assertTrue(row['available']);self.assertFalse(row['precision'])

    def test_over_budget_sample_cannot_pass_availability(self):
        packets={k:{'available':True,'precision':True} for k in ('v4','v6')}
        with patch.object(r,'recovery_clients',return_value=packets), \
             patch.object(r,'observe',return_value={'available':True,'precision':True}), \
             patch.object(r.time,'monotonic',side_effect=[0,4,10.1]):
            row=r.recovery_sample({}, {},self.root,Mock(),'new')
        self.assertFalse(row['bounded']);self.assertFalse(row['available']);self.assertFalse(row['precision'])

    def observe_clock(self, result, *, converge=1000, available=True, boot_at=0,
                      stability_failure=False, stability_gap=False, interrupt=False, native_loss=False, second_reset=False):
        # Exercise the actual observer's fixed deadlines with a deterministic clock.
        clock=[0.0];record=Mock();samples=[]
        def sleep(seconds):clock[0]+=seconds
        def observe(*args):
            clock[0]+=.1
            if second_reset and samples:return {'boot':'other'}
            return {'boot':'new' if clock[0]>=boot_at else 'old'}
        def sample(*args):
            clock[0]+=1
            if interrupt and len(samples)>1:raise KeyboardInterrupt()
            precise=clock[0]>=converge
            if stability_failure and result['stages']['convergence']['passed']:precise=False
            if stability_gap and result['stages']['convergence']['passed']:clock[0]+=76
            native={'boot':'new','available':available,'precision':precise,
                    'units':{'timeservice.service':{'stdout':'MainPID=1\nInvocationID=a\nNRestarts=0\n'}}}
            if native_loss and samples:native=None
            row={'bounded':True,'finished':clock[0],'native':native,'available':available,'precision':precise,
                 'clients':{k:{'available':available,'finished':clock[0]} for k in ('v4','v6')}}
            samples.append(row)
            return row
        with patch.object(r.time,'monotonic',side_effect=lambda:clock[0]), \
             patch.object(r.time,'sleep',side_effect=sleep),patch.object(r,'observe',side_effect=observe), \
             patch.object(r,'recovery_sample',side_effect=sample):
            r.recovery_observation({}, {},self.root,record,'old',-2,0,result)
        return samples,record

    def test_availability_then_later_convergence_and_full_stability(self):
        result={};samples,_=self.observe_clock(result)
        stages=result['stages']
        self.assertTrue(all(v['passed'] for v in stages.values()))
        self.assertLess(stages['availability']['finished'],300)
        self.assertGreater(stages['convergence']['finished'],1000)
        self.assertGreaterEqual(stages['stability']['finished']-stages['convergence']['finished'],1800)
        self.assertEqual(set(stages['availability']['first_success']),{'native','v4','v6'})
        self.assertFalse(samples[0]['precision'])

    def test_unavailable_service_stops_at_five_minutes(self):
        result={}
        with self.assertRaisesRegex(ValueError,'availability deadline'):
            self.observe_clock(result,available=False)
        self.assertTrue(result['stages']['boot_network']['passed'])
        self.assertFalse(result['stages']['availability']['passed'])

    def test_settling_deadline_not_extended_or_window_restarted(self):
        result={}
        with self.assertRaisesRegex(ValueError,'convergence deadline'):
            self.observe_clock(result,converge=1801)
        self.assertTrue(result['stages']['availability']['passed'])
        self.assertFalse(result['stages']['convergence']['passed'])
        self.assertFalse(result['stages']['stability']['passed'])

    def test_stability_failure_or_gap_preserves_earlier_stages(self):
        for option in ('stability_failure','stability_gap'):
            result={}
            with self.assertRaisesRegex(ValueError,'stability'):
                self.observe_clock(result,converge=0,**{option:True})
            self.assertTrue(result['stages']['availability']['passed'])
            self.assertTrue(result['stages']['convergence']['passed'])
            self.assertFalse(result['stages']['stability']['passed'])

    def test_late_boot_does_not_pass_boot_gate(self):
        result={};self.observe_clock(result,boot_at=65,converge=0)
        self.assertFalse(result['stages']['boot_network']['passed'])
        self.assertTrue(result['stages']['availability']['passed'])

    def test_no_boot_escalates_without_client_or_native_acceptance(self):
        for boot_at in (120,121):
            result={}
            with self.assertRaisesRegex(ValueError,'120-second escalation'):
                self.observe_clock(result,boot_at=boot_at)
            self.assertFalse(result['stages']['availability']['passed'])

    def test_native_loss_or_second_reset_stops_after_availability(self):
        for option,reason in (('native_loss','native service observation lost'),('second_reset','second reset')):
            result={}
            with self.assertRaisesRegex(ValueError,reason):self.observe_clock(result,**{option:True})
            self.assertTrue(result['stages']['availability']['passed'])
            self.assertFalse(result['stages']['convergence']['passed'])

    def test_interruption_preserves_observed_availability(self):
        result={}
        with self.assertRaises(KeyboardInterrupt):self.observe_clock(result,interrupt=True)
        self.assertTrue(result['stages']['availability']['passed'])
        self.assertFalse(result['stages']['convergence']['passed'])

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

    def snapshot_fixture(self):
        d=self.root/'snapshot';d.mkdir(mode=0o700);(d/'results').mkdir(mode=0o700)
        boot='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        spec={'hostname':'j2-svntp1','target':'ama@10.1.0.51','reference_boot_id':boot}
        def manifest(root, files):
            for name,raw in files.items():r.create(root/name,raw)
            return r.encoded({name:{'sha256':r.sha(raw),'size':len(raw)} for name,raw in files.items()})
        inputs=r.encoded({'members':json.loads(manifest(d,{'spec.json':r.encoded(spec)}))})
        r.create(d/'manifest.json',inputs)
        receipt=r.encoded({'approved_sha256':r.sha(inputs)})
        client=r.encoded({'queries_denied':True,'leap':0,'stratum':1,'refid':'PPS'})
        results={'execution.json':receipt,'capture-result.json':r.encoded({
            'capture_complete':True,'returncodes':{'boot':0},'target_mutation':False,'panic':False,'retry':False}),
            'boot.stdout':boot.encode(),'finish-boot.stdout':boot.encode(),
            'identity.stdout':b'j2-svntp1','kernel.stdout':b'Linux 6.18.50+rpt-rpi-v8 #1 SMP aarch64 GNU/Linux',
            'services.stdout':b'same','finish-services.stdout':b'same',
            'client-0.stdout':client,'client-1.stdout':client,
            'protected_hashes.stdout':b'abc  /etc/ntp.conf\n'}
        records=manifest(d/'results',results);r.create(d/'results/results-manifest.json',records)
        outcome={'capture_accepted':True,'approved_manifest_sha256':r.sha(inputs),
            'results_manifest_sha256':r.sha(records),'approved_receipt_sha256':r.sha(receipt),
            'observed_boot':boot,'services_stable':True,'all_observed_services_running':True,
            'timing_checks':{'offset':True}}
        r.create(d/'outcome.json',outcome)
        return d,{'boot':'old','protected':{'/etc/ntp.conf':'abc'},'manager':{'retained':True}}

    def test_snapshot_advances_only_boot_without_stability_claim(self):
        d,base=self.snapshot_fixture();result=r.snapshot_baseline(base,d)
        self.assertEqual(result['protected'],base['protected'])
        self.assertEqual(result['manager'],base['manager']);self.assertEqual(base['boot'],'old')
        self.assertNotEqual(result['boot'],base['boot'])
        self.assertTrue(result['readiness_snapshot']['bounded_snapshot_only'])
        for key in ('hardware_attribution_accepted','historical_recovery_accepted','sustained_stability_accepted'):
            self.assertFalse(result['readiness_snapshot'][key])

    def test_snapshot_capture_tampering_rejected(self):
        d,base=self.snapshot_fixture();(d/'results/boot.stdout').write_text('different')
        with self.assertRaisesRegex(ValueError,'member drift'):r.snapshot_baseline(base,d)

    def test_snapshot_false_acceptance_and_receipt_drift_rejected(self):
        d,base=self.snapshot_fixture();path=d/'outcome.json';outcome=json.loads(path.read_bytes())
        for field,value,error in [('capture_accepted',False,'accepted snapshot'),
                                  ('approved_receipt_sha256','wrong','receipt binding'),
                                  ('services_stable',False,'service continuity'),
                                  ('observed_boot','different','boot continuity')]:
            path.write_bytes(r.encoded(dict(outcome,**{field:value})))
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,error):r.snapshot_baseline(base,d)

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
