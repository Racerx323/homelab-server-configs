#!/usr/bin/env python3
"""Neutral schedule/recovery boundary regressions; no production access."""
from datetime import datetime
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo

SCRIPTS = Path(__file__).resolve().parents[1]/'ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import recurring_protection as module
spec = importlib.util.spec_from_file_location('renderer', SCRIPTS/'render-recurring-protection.py')
renderer = importlib.util.module_from_spec(spec); spec.loader.exec_module(renderer)


def configuration(root, prefix='nautobot-protection-test'):
    return dict(schema_version=1, execution_authorized=True, state_directory=str(root), unit_prefix=prefix,
                timezone='America/Chicago', start_hour=3, end_hour=4, capture_seconds=180,
                recovery_seconds=90, run_seconds=3000, prepare_argv=['/bin/true'],
                ansible_argv=['/bin/true'], resume_commands=[['/bin/true'], ['/bin/true']], health_argv=['/bin/true'])


class ProtectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nautobot-recurring.')
        self.root = Path(self.tmp.name); self.root.chmod(0o700)
        self.config = configuration(self.root)
        self.path = self.root/'configuration.json'; module.atomic(self.path, self.config)
        self.supervisor = module.Supervisor(self.path)

    def tearDown(self): self.tmp.cleanup()

    def armed(self):
        import hashlib
        import time
        state = dict(phase='armed', root=str(self.root), deadline=time.monotonic()+100,
                     configuration_sha256=hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.supervisor.write(state)
        return state

    def test_staging_binding_rejects_other_root(self):
        self.config.update(staging_directory=str(self.root),staging_filesystem='ext4')
        module.atomic(self.path,self.config)
        self.supervisor=module.Supervisor(self.path)
        state=self.armed()
        with self.assertRaisesRegex(module.Blocked,'run_root'): self.supervisor.check_binding(state)
        child=self.root/'nautobot-recurring.test'; child.mkdir(mode=0o700)
        state['root']=str(child)
        self.assertEqual(self.supervisor.check_binding(state),child)
        self.config['staging_filesystem']='tmpfs'
        with self.assertRaisesRegex(module.Blocked,'staging_contract'): module.validate(self.config)

    def test_disposal_runs_under_exclusive_lock_after_resume(self):
        self.config['dispose_successful_payload']=True
        module.atomic(self.path,self.config); self.supervisor=module.Supervisor(self.path)
        created=[]
        def command(argv,timeout):
            state=self.supervisor.state(); root=Path(state['root'])
            if state['phase']=='preflight':
                created.append(root);module.atomic(root/'inputs.json',{})
            elif len(argv)>1:  # the Ansible invocation completes verified resume
                state['phase']='resumed';self.supervisor.write(state)
            return 0
        def dispose(root,*helpers):
            self.assertEqual(self.supervisor.state()['phase'],'resumed')
            with self.assertRaises(BlockingIOError):
                with module.lock(self.root/'run.lock',blocking=False): pass
        try:
            with patch.object(module,'in_window',return_value=True),patch.object(self.supervisor,'command',side_effect=command),patch.object(self.supervisor,'check'),patch.object(self.supervisor,'control',return_value=subprocess.CompletedProcess([],0)),patch('recurring_disposal.dispose',side_effect=dispose) as disposal:
                self.assertEqual(self.supervisor.run(),0)
                disposal.assert_called_once()
                self.assertEqual(self.supervisor.state()['phase'],'complete')
        finally:
            import shutil
            for root in created: shutil.rmtree(root)

    def test_dst_windows_and_remaining_recovery_budget(self):
        zone = ZoneInfo('America/Chicago')
        for date in ('2026-03-08', '2026-11-01'):
            self.assertTrue(module.in_window(self.config, datetime.fromisoformat(date+'T03:20:00').replace(tzinfo=zone)))
            for hour in ('02:59:00', '03:59:00', '04:00:00'):
                self.assertFalse(module.in_window(self.config, datetime.fromisoformat(date+'T'+hour).replace(tzinfo=zone)))

    def test_overlap_does_not_prepare(self):
        with module.lock(self.root/'run.lock'):
            self.assertEqual(self.supervisor.run(), 3)
        self.assertEqual(json.loads((self.root/'last-skip.json').read_text())['reason'], 'overlap')

    def test_pending_recovery_blocks_new_run(self):
        self.armed()
        with self.assertRaisesRegex(module.Blocked, 'unresolved_recovery'): self.supervisor.run()

    def test_bad_health_cannot_disarm(self):
        self.armed()
        with patch.object(self.supervisor, 'command', return_value=1):
            with self.assertRaisesRegex(module.Blocked, 'health_failed'): self.supervisor.recovered()
        self.assertEqual(self.supervisor.state()['phase'], 'armed')

    def test_recovery_attempts_every_resume_after_quiescence(self):
        self.armed()
        control = subprocess.CompletedProcess([], 0, stdout=b'inactive\n')
        with patch.object(self.supervisor, 'control', return_value=control) as ctl, patch.object(
                self.supervisor, 'command', side_effect=[1,0,0]) as command:
            self.assertEqual(self.supervisor.recover(), 1)
            self.assertEqual(command.call_count, 3)
            self.assertEqual(ctl.call_args_list[0].args, ('stop','--no-block','nautobot-protection-test.service'))
        self.assertEqual(self.supervisor.state()['phase'], 'manual_intervention')

    def test_duplicate_recovery_trigger_does_not_race(self):
        self.armed()
        with module.lock(self.root/'recovery.lock'), patch.object(self.supervisor,'control') as control:
            self.assertEqual(self.supervisor.recover(),0)
            control.assert_not_called()
        self.assertEqual(self.supervisor.state()['phase'],'armed')

    def test_late_timer_does_not_interrupt_upload(self):
        state = self.armed(); state['phase'] = 'resumed'; self.supervisor.write(state)
        with patch.object(self.supervisor, 'control') as control:
            self.assertEqual(self.supervisor.guard(), 0)
            control.assert_not_called()
        self.assertEqual(self.supervisor.state()['phase'], 'resumed')

    def test_cleanup_continues_after_bad_metadata(self):
        (self.root/'password').symlink_to('/does-not-exist')
        module.atomic(self.root/'credentials.json', {'test':True})
        with self.assertRaises(module.Blocked): self.supervisor.cleanup(self.root)
        self.assertFalse((self.root/'credentials.json').exists())

    def test_yesterday_success_is_missed_after_window(self):
        now = datetime(2026,9,28,4,5,tzinfo=ZoneInfo('America/Chicago'))
        old = datetime(2026,9,27,3,50,tzinfo=now.tzinfo).timestamp()
        self.supervisor.write(dict(phase='complete',last_success=old))
        with patch.object(module, 'datetime') as dt, patch.object(module.time, 'time', return_value=now.timestamp()):
            dt.now.return_value=now; dt.fromtimestamp.side_effect=datetime.fromtimestamp
            self.assertEqual(self.supervisor.missed(), 1)
            self.supervisor.write(dict(phase='complete',last_success=now.timestamp()-60))
            self.assertEqual(self.supervisor.missed(), 0)

    def test_units_use_oneshot_deadlines_no_catchup(self):
        units = renderer.render(self.path, SCRIPTS/'recurring_protection.py')
        self.assertIn('TimeoutStartSec=', units['nautobot-protection-test.service'])
        self.assertIn('KillMode=control-group', units['nautobot-protection-test.service'])
        self.assertIn('Persistent=false', units['nautobot-protection-test.timer'])
        self.assertIn('03:20:00 America/Chicago', units['nautobot-protection-test.timer'])
        for text in units.values(): self.assertNotIn('RuntimeMaxSec', text)


if __name__ == '__main__': unittest.main()
