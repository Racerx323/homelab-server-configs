#!/usr/bin/python3
"""Offline scope, content filtering and sealed one-attempt safety checks."""
import base64
import gzip
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('readiness',ROOT/'scripts/inspect-recovery-readiness.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
r.h=r.load(r.SOURCES['helper.py']);r.p=r.load(r.SOURCES['passive.py']);r.p.h=r.h
r.o=r.load(r.SOURCES['ownership.py']);r.o.h=r.h;r.o.p=r.p


class Readiness(unittest.TestCase):
    def bundle(self,directory,native=False):
        now=int(time.time())
        spec={'schema':1,'purpose':'watchdog-recovery-readiness','operation_id':directory.name,
            'directory':str(directory),'prepared_epoch':now,'expires_epoch':now+86400,
            'baseline_boot_id':'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            'baseline_file_hashes':{f:'a'*64 for f in r.p.PROTECTED},'baseline_capture_sha256':'b'*64,'members':{}}
        if native:
            spec.update(purpose=r.NATIVE_PURPOSE,kernel_release='6.18.50+rpt-rpi-v8')
        directory.mkdir(mode=0o700)
        files={n:f.read_bytes() for n,f in r.SOURCES.items()}
        files.update({'known_hosts':b'10.1.0.137 ssh-ed25519 TESTKEY\n','baseline.json':b'{"vendor_sha256":"test"}'})
        spec['members']={n:r.h.sha(raw) for n,raw in files.items()}
        files.update({'spec.json':r.h.encoded(spec),'review.md':r.review(spec).encode()})
        for n,raw in files.items():(directory/n).write_bytes(raw);(directory/n).chmod(0o600)
        with tarfile.open(directory/'inspection.tar','w') as archive:
            for n,raw in files.items():
                member=tarfile.TarInfo(n);member.size=len(raw);archive.addfile(member,io.BytesIO(raw))
        (directory/'inspection.tar').chmod(0o600)
        return r.h.sha((directory/'inspection.tar').read_bytes()),files,spec

    def test_closed_scope(self):
        with self.assertRaises(ValueError):r.validate({'purpose':'reboot'})
        for argv in r.COMMANDS.values():
            self.assertFalse(set(argv)&{'restart','reboot','panic','--flush','--rotate','--vacuum-time'})
        self.assertNotIn('sysrq-trigger',r.SYSCTLS)

    def test_kernel_filter(self):
        result=r.kernel_options('CONFIG_WATCHDOG=y\nCONFIG_BCM2835_WDT=y\n# CONFIG_PSTORE is not set\nCONFIG_CMDLINE="SECRET"\n')
        self.assertNotIn('SECRET',result);self.assertIn('CONFIG_PSTORE',result)

    def test_journal_filter(self):
        self.assertEqual(r.journal_fields('[Journal]\nStorage=persistent\nForwardToSocket=SECRET\n[Other]\nStorage=SECRET'),'Storage=persistent')

    def test_real_gzip_and_no_raw_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'config.gz';path.write_bytes(gzip.compress(b'CONFIG_WATCHDOG=y\nCONFIG_CMDLINE="SECRET"\n'))
            row=r.read_selected(path,r.kernel_options,True)
            self.assertNotIn('base64',row);self.assertNotIn('SECRET',json.dumps(row))

    def test_decompression_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'bomb.gz';path.write_bytes(gzip.compress(b'A'*(r.h.LIMIT+1)))
            with self.assertRaises(ValueError):r.read_selected(path,lambda x:x,True)

    def test_device_never_read(self):
        row=r.read_selected('/dev/null',lambda x:x)
        self.assertIn('error',row);self.assertNotIn('selected_text',row)

    def test_indirect_directory_not_enumerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'link';path.symlink_to('/etc')
            with patch.object(r.p,'names') as names:
                self.assertTrue(r.directory_metadata(path)['indirect_not_enumerated']);names.assert_not_called()

    def test_seal_and_source_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-recovery-readiness-test';digest,_,_=self.bundle(directory)
            r.prepare(directory,digest)
            with self.assertRaises(ValueError):r.prepare(directory,'0'*64)
            (directory/'review.md').write_text('changed')
            with self.assertRaises(ValueError):r.prepare(directory,digest)

    def test_expiry_and_one_use(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-recovery-readiness-test';digest,_,_=self.bundle(directory)
            with patch.object(r.time,'time',return_value=time.time()+86400):
                with self.assertRaises(ValueError):r.prepare(directory,digest)
            (directory/'execution.json').write_text('{}')
            with patch.object(r.h,'bounded') as transport:
                with self.assertRaises(FileExistsError):r.execute(types.SimpleNamespace(directory=directory,sha256=digest))
                transport.assert_not_called()

    def test_remote_namespace_without_contact(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-recovery-readiness-test';_,files,spec=self.bundle(directory)
            payload=r.payload(spec,files)
            # Initialize exact embedded modules without calling collection.
            namespace={};exec(payload.rsplit(b"\nsignal.signal(signal.SIGALRM",1)[0],namespace)
            self.assertIn('collect',namespace['readiness'])
            compile(payload,'<sealed>','exec')

    def test_timeout_consumes_receipt_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-recovery-readiness-test';digest,_,_=self.bundle(directory)
            with patch.object(r.h,'bounded',return_value={'stdout':'','stderr':'','returncode':None,'error':'timeout'}) as transport:
                result=r.execute(types.SimpleNamespace(directory=directory,sha256=digest))
            self.assertFalse(result['capture_complete']);self.assertEqual(transport.call_count,1)
            self.assertTrue((directory/'execution.json').exists())

    def test_native_token_filter(self):
        text='root=SECRET console=tty1 console=serial0,115200 quiet crashkernel=256M panic=0 SECRET=x console=bad;command'
        self.assertEqual(r.native_cmdline(text),'console=tty1 console=serial0,115200 quiet crashkernel=256M panic=0')

    def test_module_names_only_and_bounds(self):
        self.assertEqual(r.module_names('example 123 0 - Live 0x123456\n'),'example')
        with self.assertRaises(ValueError):r.module_names('invalid')
        with self.assertRaises(ValueError):r.module_names('example 1 0 - Live 0x0\n'*513)

    def test_native_config_does_not_export_command_line(self):
        text='CONFIG_KEXEC=y\nCONFIG_VT_CONSOLE=y\nCONFIG_CMDLINE="SECRET"\n'
        self.assertEqual(r.native_kernel_options(text),'CONFIG_KEXEC=y\nCONFIG_VT_CONSOLE=y')

    def test_native_release_drift_stops_extra_reads(self):
        with patch.object(r.p,'command',return_value={'stdout':'different\n','returncode':0}) as command, patch.object(r.p,'text_record') as read:
            result=r.native_inputs('6.18.50+rpt-rpi-v8')
        self.assertTrue(result['kernel_release_mismatch']);read.assert_not_called()
        self.assertEqual(command.call_count,len(r.NATIVE_COMMANDS))

    def test_native_frozen_scope_and_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-native-inputs-test';digest,files,spec=self.bundle(directory,True)
            r.prepare(directory,digest)
            self.assertIn('No failure injection',files['review.md'].decode())
            self.assertNotIn('/proc/sysrq-trigger',r.NATIVE_PATHS)
            compile(r.payload(spec,files),'<native>','exec')
            with self.assertRaises(ValueError):r.validate(dict(spec,kernel_release='../unsafe'))
            with self.assertRaises(ValueError):r.validate(dict(spec,purpose='reboot'))

    def test_native_missing_inputs_and_metadata_do_not_open_devices(self):
        with patch.object(r.p,'command',return_value={'stdout':'6.18.50+rpt-rpi-v8\n','returncode':0}), patch.object(r.p,'text_record',return_value={'missing':True}) as read, patch.object(r,'read_selected',return_value={'missing':True}), patch.object(r.p,'metadata',return_value={'missing':True}):
            result=r.native_inputs('6.18.50+rpt-rpi-v8')
        self.assertEqual(set(result['runtime']),set(r.NATIVE_PATHS))
        self.assertTrue(all(not call.args[0].startswith('/dev/') for call in read.call_args_list))

    def test_native_drift_cannot_complete(self):
        sample={'commands':{'kernel':{'returncode':0},'kernel_build':{'returncode':0}}}
        changed=dict(sample,changed=True)
        with patch.object(r.o,'collect',return_value={'capture_complete':True}), patch.object(r.o,'complete',return_value=True), patch.object(r.o,'configurations',return_value={}), patch.object(r.o,'manager',return_value={}), patch.object(r.p,'state',return_value={}), patch.object(r.h,'file_record',return_value={'sha256':'expected'}), patch.object(r,'native_inputs',side_effect=[sample,changed]):
            result=r.collect_native({'purpose':r.NATIVE_PURPOSE,'kernel_release':'6.18.50+rpt-rpi-v8'},{'vendor_sha256':'expected'})
        self.assertFalse(result['capture_complete']);self.assertFalse(result['native_stable'])
        self.assertFalse(result['reset_attribution_qualified'])

    def test_native_one_use_and_local_source_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-native-inputs-test';digest,_,_=self.bundle(directory,True)
            with patch.object(r.h,'bounded',return_value={'stdout':'','stderr':'','returncode':None,'error':'timeout'}) as transport:
                r.execute(types.SimpleNamespace(directory=directory,sha256=digest))
                with self.assertRaises(FileExistsError):r.execute(types.SimpleNamespace(directory=directory,sha256=digest))
            self.assertEqual(transport.call_count,1)
            changed=Path(tmp)/'changed.py';changed.write_text('changed source')
            with patch.dict(r.SOURCES,{'runner.py':changed}):
                with self.assertRaises(ValueError):r.prepare(directory,digest)

    def test_debugger_cmdline_excludes_unrelated_and_rejects_malformed(self):
        text='root=SECRET console=tty1 kgdboc.kgdboc=kms,kbd kgdboc_earlycon kgdbwait password=SECRET'
        self.assertEqual(r.debugger_cmdline(text),'console=tty1 kgdboc.kgdboc=kms,kbd kgdboc_earlycon kgdbwait')
        with self.assertRaises(ValueError):r.debugger_cmdline('kgdboc=ttyS0;bad')

    def test_debugger_narrow_reads_and_empty_missing_distinction(self):
        for parameter in ({'text':'\n'},{'missing':True},{'error':'unreadable'}):
            with patch.object(r.p,'command',return_value={'stdout':'6.18.50+rpt-rpi-v8\n','returncode':0}) as command, patch.object(r.p,'text_record',side_effect=[parameter,{'text':'0\n'}]) as read, patch.object(r,'read_selected',return_value={'selected_text':'console=tty1'}):
                result=r.debugger_inputs('6.18.50+rpt-rpi-v8')
            self.assertEqual(result['kgdboc_parameter'],parameter)
            self.assertEqual(command.call_count,1)
            self.assertEqual([c.args[0] for c in read.call_args_list],['/sys/module/kgdboc/parameters/kgdboc','/proc/sys/kernel/panic'])

    def test_debugger_release_mismatch_stops_reads(self):
        with patch.object(r.p,'command',return_value={'stdout':'changed\n','returncode':0}), patch.object(r.p,'text_record') as read:
            self.assertTrue(r.debugger_inputs('expected')['kernel_release_mismatch'])
        read.assert_not_called()

    def test_debugger_closed_spec_and_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/'watchdog-native-inputs-test';_,files,spec=self.bundle(directory,True)
            spec.update(purpose=r.DEBUGGER_PURPOSE,operation_id='watchdog-debugger-inputs-test',directory=str(Path(tmp)/'watchdog-debugger-inputs-test'))
            r.validate(spec);compile(r.payload(spec,files),'<debugger>','exec')
            self.assertIn('No trigger is selected',r.review(spec))
            with self.assertRaises(ValueError):r.validate(dict(spec,extra_read='/proc/kcore'))


if __name__=='__main__':unittest.main()
