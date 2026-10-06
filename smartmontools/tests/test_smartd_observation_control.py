#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]/'scripts'
spec = importlib.util.spec_from_file_location('control', SCRIPTS/'smartd-observation-control.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Control(unittest.TestCase):
    def test_detached_parent_exits_status_is_read_only_and_cancel_owns_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'evidence').mkdir(mode=0o700)
            fixture = ('import signal,time\nsignal.signal(signal.SIGTERM,lambda *_:exit(0))\n'
                       'print("Monitoring 0 ATA/SATA, 0 SCSI/SAS and 1 NVMe devices",flush=True)\n'
                       'print(" [NVMe call: opcode=0x02, size=0x0234, nsid=0xffffffff, cdw10=0x008c0006]",flush=True)\n'
                       'print(" [NVMe call succeeded: result=0x00000000",flush=True)\n'
                       'time.sleep(30)\n')
            program = ('import importlib.util,json,sys\nfrom pathlib import Path\n'
                       's=importlib.util.spec_from_file_location("c",'+repr(str(SCRIPTS/'smartd-observation-control.py'))+')\n'
                       'c=importlib.util.module_from_spec(s);s.loader.exec_module(c)\n'
                       'o=c.load("o",Path('+repr(str(SCRIPTS/'observe-smartd.py'))+'))\n'
                       'root=Path('+repr(d)+')\n'
                       'def worker():\n'
                       ' return o.supervise([sys.executable,"-c",'+repr(fixture)+'],root/"evidence",lambda:None,'
                       'duration=30,minimum_checks=1,audit_seconds=.03,settle_seconds=.05)\n'
                       'print(json.dumps(c.detach(root,worker)))\n')
            # A still-inherited stdout pipe would hang communicate after the
            # parent exits; this exercises the real fork/setsid/descriptor path.
            parent = subprocess.run([sys.executable, '-B', '-c', program], capture_output=True, timeout=5)
            self.assertEqual(parent.returncode, 0, parent.stderr)
            initial = json.loads(parent.stdout)
            self.assertEqual(initial['state'], 'running')
            try:
                deadline = time.monotonic()+3
                while not (root/'evidence/progress.json').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((root/'evidence/progress.json').exists())
                before = (root/'status.json').stat().st_mtime_ns
                self.assertTrue(m.status(root)['supervisor_alive'])
                self.assertEqual((root/'status.json').stat().st_mtime_ns, before)
                with self.assertRaises(FileExistsError):
                    m.detach(root, lambda: self.fail('duplicate launched'))
                self.assertTrue(m.cancel(root)['cancellation_requested'])
                deadline = time.monotonic()+3
                while time.monotonic() < deadline:
                    record = m.status(root)
                    if record['state'] in ('cancelled', 'failed', 'complete'):
                        break
                    time.sleep(.02)
                self.assertEqual(record['state'], 'cancelled')
                self.assertTrue(record['result']['candidate_exited'])
                self.assertGreaterEqual(record['result']['post_exit_observation_seconds'], .05)
                with self.assertRaises(ValueError):
                    m.cancel(root)
            finally:
                if m.status(root)['state'] in ('running', 'stopping'):
                    m.cancel(root)

    def test_stale_identity_and_public_directory_refuse_cancel(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            who = m.identity(os.getpid())
            who['start_ticks'] = 'wrong'
            m.atomic(root, {'state': 'running', 'supervisor': who})
            self.assertEqual(m.status(root)['state'], 'lost_supervisor')
            with self.assertRaises(ValueError):
                m.cancel(root)
            root.chmod(0o755)
            with self.assertRaisesRegex(ValueError, 'unsafe_trial_root'):
                m.status(root)

    def test_audit_checks_identity_state_counters_and_kernel(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name in ('evidence', 'state'):
                (root/name).mkdir()
            baseline = {'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                        'hashes':{'a':'hash'}, 'services':{'stdout':'service'},
                        'ioerr_cnt':'0x2', 'ext4_errors':'0'}
            h = SimpleNamespace(cursor=lambda:'cursor', config_identity=lambda:{'a':'hash'},
                                checked=lambda _:'service', observer_inactive=lambda:None,
                                storage_since=lambda _:('',False))
            candidate = SimpleNamespace(counters=lambda:{'ioerr_cnt':'0x2','ext4_errors':'0'})
            audit = m.make_audit(root, baseline, h, candidate)
            captured = patch.object(m, 'capture_journal', return_value=('next',False))
            capture = captured.start()
            self.addCleanup(captured.stop)
            audit()
            state = root/'state/test.nvme.state'
            state.write_text('# smartd state file\nself-test-errors = 1\n')
            with self.assertRaisesRegex(ValueError, 'candidate_selftest_errors'):
                audit()
            state.write_text('# smartd state file\n')
            capture.return_value = ('next',True)
            with self.assertRaisesRegex(ValueError, 'kernel_storage_fault'):
                audit()
            capture.return_value = ('next',False)
            candidate.counters = lambda:{'ioerr_cnt':'0x3','ext4_errors':'0'}
            with self.assertRaisesRegex(ValueError, 'storage_counters_changed'):
                audit()

    def test_journal_rolling_cursor_preserves_faults_and_refuses_gaps(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            rows = [{'__CURSOR':'b','_TRANSPORT':'kernel','MESSAGE':'I/O error'},
                    {'__CURSOR':'c','SYSLOG_IDENTIFIER':'smartd','MESSAGE':'Self-Test Log error count increased'},
                    {'__CURSOR':'d','MESSAGE':'unrelated private message'}]
            replies = iter(['{"__CURSOR":"a"}\n', '\n'.join(json.dumps(x) for x in rows)])
            h = SimpleNamespace(checked=lambda _:next(replies), PATTERN='I/O error')
            self.assertEqual(m.capture_journal(root,'a',h), ('d',True))
            self.assertIn('I/O error', (root/'kernel.jsonl').read_text())
            self.assertIn('Self-Test', (root/'production-smartd.jsonl').read_text())
            self.assertNotIn('unrelated private', ''.join(p.read_text() for p in root.iterdir()))
            receipt = json.loads((root/'journal-checkpoints.jsonl').read_text())
            self.assertEqual((receipt['from'],receipt['to'],receipt['rows_seen']), ('a','d',3))
            h.checked = lambda _:'{"__CURSOR":"wrong"}\n'
            with self.assertRaisesRegex(ValueError, 'journal_cursor_gap'):
                m.capture_journal(root,'d',h)
            with self.assertRaisesRegex(ValueError, 'journal_evidence_limit'):
                m.append_bounded(root/'kernel.jsonl', b'large', 1)

    def test_changed_private_input_stops_before_other_audits(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            path = root/'frozen-input'
            path.write_text('original')
            audit = m.make_audit(root, {'ioerr_cnt':'0x2','ext4_errors':'0'},
                                 SimpleNamespace(cursor=lambda:'cursor'), None, ['frozen-input'])
            path.write_text('changed')
            with self.assertRaisesRegex(ValueError, 'private_input_changed'):
                audit()


if __name__ == '__main__':
    unittest.main()
