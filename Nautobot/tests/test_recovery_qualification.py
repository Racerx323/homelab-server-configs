#!/usr/bin/env python3
"""Recovery bundle boundaries; optional real local timer dispatch."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml
ROOT=Path(__file__).resolve().parents[2]
SCRIPTS=ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0,str(SCRIPTS));sys.dont_write_bytecode=True
import recovery_qualification as qualification


class RecoveryQualification(unittest.TestCase):
    def test_cursor_banner_and_fail_closed_input(self):
        cursor = '-- cursor: s=abc;i=12;b=def;m=123;t=456;x=789'
        for output in (cursor, '-- No entries --\n'+cursor+'\n'):
            self.assertEqual(qualification.journal_cursor(output), cursor)
        for output in (None, '', '-- No entries --', cursor+'\n'+cursor,
                       'journal message\n'+cursor, cursor+'\x1b', 'x'*4097):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, 'journal_cursor'):
                qualification.configure(Path('/nonexistent'), 'killed', output)

    def test_bundle_freeze_and_tamper_refusal(self):
        current=yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if current['operation'].get('stage')!='recurring_failure_recovery_timer_qualification':
            self.skipTest('no pending recovery trial')
        spec=importlib.util.spec_from_file_location('recovery_bundle',SCRIPTS/'recovery-timer-bundle.py')
        bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temporary:
            # Qualify a fresh local fixture without changing a consumed approval.
            current['accepted_sha256']=hashlib.sha256((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_bytes()).hexdigest()
            fixture=Path(temporary)/'operation.yaml';fixture.write_text(yaml.safe_dump(current))
            root=Path(temporary)/'candidate';bundle.transport.freeze(root,operation=fixture)
            digest=bundle.transport.sha(root/'bundle.json');bundle.transport.verify(root,digest)
            original=yaml.safe_load((root/'operation.yaml').read_text())
            if 'retained_state' in original:
                bad=json.loads(json.dumps(original));bad['retained_state']['directories']['.']['mode']=0o755
                (root/'operation.yaml').write_text(yaml.safe_dump(bad));(root/'runtime/operation.json').write_text(json.dumps(bad))
                with self.assertRaisesRegex(ValueError,'retained_permissions'):bundle.validate(root)
            for key,value in [('dispose_successful_payload',True),('recovery_seconds',300)]:
                bad=json.loads(json.dumps(original));bad['trials']['killed']['supervisor'][key]=value
                (root/'operation.yaml').write_text(yaml.safe_dump(bad));(root/'runtime/operation.json').write_text(json.dumps(bad))
                with self.assertRaises(ValueError):bundle.validate(root)
            (root/'operation.yaml').write_text(yaml.safe_dump(original));(root/'runtime/operation.json').write_text(json.dumps(original))
            (root/'runtime/scripts/recovery_qualification.py').write_text('tampered')
            with self.assertRaisesRegex(ValueError,'input_drift'):bundle.transport.verify(root,digest)

    @unittest.skipUnless(os.environ.get('NAUTOBOT_RECOVERY_NATIVE')=='1','opt-in real local timer')
    def test_actual_timer_helper_and_calendar_parser(self):
        with tempfile.TemporaryDirectory(prefix='nautobot-recovery-timer.') as temporary:
            root=Path(temporary);root.chmod(0o700)
            from test_recurring_protection import configuration
            config=configuration(root);config.update(start_hour=0,end_hour=24)
            with patch.object(qualification,'operation',return_value={'trials':{'killed':{'supervisor':config}}}):
                qualification.timer(root)
            result=json.loads((root/'timer/result.json').read_text())
            self.assertTrue(result['dispatched']);self.assertEqual(len(result['calendar']),4)
            self.assertFalse(result['production_timer_enabled'])
            for suffix in ('.service','.timer'):
                self.assertEqual(qualification.node.system(['show','nautobot-protection-timerqual'+suffix,'--property=LoadState','--value']).strip(),b'not-found')


if __name__=='__main__':unittest.main()
