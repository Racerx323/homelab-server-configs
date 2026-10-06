#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1]/'scripts/observe-smartd.py'
spec = importlib.util.spec_from_file_location('observation', SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
CALL = ' [NVMe call: opcode=0x02, size=0x0234, nsid=0xffffffff, cdw10=0x008c0006]\n'
SUCCESS = ' [NVMe call succeeded: result=0x00000000\n'
MONITORING = 'Monitoring 0 ATA/SATA, 0 SCSI/SAS and 1 NVMe devices\n'
FIXTURE = ('import signal,time\n'
           'signal.signal(signal.SIGTERM,lambda *_:exit(0))\n'
           'print('+repr(MONITORING+CALL+SUCCESS)+',flush=True)\n'
           'time.sleep(30)\n')


class Observation(unittest.TestCase):
    def test_foreground_interval_and_private_paths(self):
        args = m.argv_for('/private')
        self.assertNotIn('-p', args)
        self.assertEqual(args[args.index('-i')+1], '1800')
        self.assertEqual(args[args.index('-q')+1], 'errors')
        for flag in ('-c', '-B', '-s', '-A', '-j'):
            self.assertTrue(args[args.index(flag)+1].startswith('/private/'))

    def test_registration_does_not_count_as_monitoring_and_chunks_are_supported(self):
        t = m.Transactions()
        data = (CALL+SUCCESS+MONITORING+CALL+SUCCESS).encode()
        for i in range(0, len(data), 7):
            t.feed(data[i:i+7], 1)
        self.assertEqual(t.completed, 1)
        self.assertIsNone(t.call_started)

    def test_unexpected_commands_faults_and_missing_results_fail(self):
        for data in ['Read Self-test Log failed\n', 'error count increased from 0 to 1\n',
                     CALL.replace('0x02', '0x14', 1), CALL+CALL, SUCCESS, 'x'*5000]:
            with self.assertRaises(ValueError):
                m.Transactions().feed(data.encode(), 1)

    def test_command_and_check_gap_deadlines(self):
        t = m.Transactions()
        with self.assertRaisesRegex(TimeoutError, 'first_check'):
            t.deadline(61, 0, 60, 1920)
        t.feed((MONITORING+CALL).encode(), 1)
        with self.assertRaisesRegex(TimeoutError, 'device_command'):
            t.deadline(62, 0, 60, 1920)
        t.feed(SUCCESS.encode(), 2)
        with self.assertRaisesRegex(TimeoutError, 'check_gap'):
            t.deadline(1923, 0, 60, 1920)

    def run_fixture(self, code, audit=lambda: None, **options):
        with tempfile.TemporaryDirectory() as d:
            result = m.supervise([sys.executable, '-c', code], d, audit,
                                 duration=.25, minimum_checks=1, audit_seconds=.03,
                                 settle_seconds=.05, **options)
            self.assertEqual(result, json.loads((Path(d)/'result.json').read_text()))
            self.assertTrue(result['candidate_exited'])
            self.assertGreaterEqual(result['post_exit_observation_seconds'], .05)
            return result

    def test_controlled_stop_and_stateful_process(self):
        result = self.run_fixture(FIXTURE)
        self.assertTrue(result['completed'])
        self.assertEqual(result['completed_checks'], 1)
        self.assertEqual(result['candidate_exit_status'], 0)
        self.assertFalse(result['accepted'])

    def test_early_exit_and_output_limit(self):
        result = self.run_fixture('print("early",flush=True)')
        self.assertIn('early_candidate_exit', result['failure'])
        result = self.run_fixture('print("x"*50000,flush=True);import time;time.sleep(30)', limit=100)
        self.assertIn('output_limit', result['failure'])
        self.assertFalse(result['completed'])

    def test_audit_fault_stops_candidate_and_final_audit_still_runs(self):
        calls = []
        def audit():
            calls.append(1)
            if len(calls) >= 2:
                raise ValueError('storage_drift')
        result = self.run_fixture(FIXTURE, audit)
        self.assertIn('storage_drift', result['failure'])
        self.assertGreaterEqual(len(calls), 3)
        self.assertFalse(result['completed'])

    def test_supervisor_death_kills_owned_candidate(self):
        with tempfile.TemporaryDirectory() as d:
            pidfile = Path(d)/'child.pid'
            program = ('import importlib.util,os,subprocess,sys,time\n'
                       's=importlib.util.spec_from_file_location("o",'+repr(str(SCRIPT))+')\n'
                       'm=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n'
                       'parent=os.getpid()\n'
                       'p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"],'
                       'preexec_fn=lambda:m.parent_death_guard(parent))\n'
                       'open('+repr(str(pidfile))+',"w").write(str(p.pid))\n'
                       'time.sleep(30)\n')
            parent = subprocess.Popen([sys.executable, '-c', program])
            child = None
            try:
                deadline = time.monotonic()+3
                while not pidfile.exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                child = int(pidfile.read_text())
                parent.kill()
                parent.wait(timeout=3)
                state = Path('/proc')/str(child)/'stat'
                while time.monotonic() < deadline:
                    if not state.exists() or state.read_text().split(') ',1)[1].startswith('Z '):
                        break
                    time.sleep(.02)
                else:
                    self.fail('candidate survived supervisor death')
            finally:
                if parent.poll() is None:
                    parent.kill(); parent.wait(timeout=3)
                if child and (Path('/proc')/str(child)).exists():
                    try:
                        os.kill(child, signal.SIGKILL)
                    except ProcessLookupError:
                        pass


if __name__ == '__main__':
    unittest.main()
