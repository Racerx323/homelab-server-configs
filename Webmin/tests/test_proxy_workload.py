#!/usr/bin/env python3
"""Offline contracts and real owned-process cleanup; no browser or live target."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import itertools
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('workload', ROOT / 'scripts/supervise-proxy-workload.py')
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
spec = importlib.util.spec_from_file_location('handoff', ROOT / 'scripts/proxy-trial-handoff.py')
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
TOKEN = 'a' * 64


class Acceptance(unittest.TestCase):
    def evidence(self):
        browser = []
        for identity in ['a-ipv4', 'a-ipv6', 'b-ipv4', 'b-ipv6', 'vip-ipv4', 'vip-ipv6']:
            browser.extend([{'kind': 'path', 'id': identity, 'trusted_tls': True, 'login': True, 'port': 443, 'statistics_frames': 1},
                            {'kind': 'path-complete', 'id': identity, 'logout': True, 'old_session_denied': True}])
        for identity in ['a-ipv4', 'a-ipv6', 'b-ipv4', 'b-ipv6', 'vip-ipv4', 'vip-ipv6']:
            browser.extend({'kind': 'active', 'id': identity, 'monotonic_seconds': t / 2} for t in range(0, 191))
            browser.append({'kind': 'workload-end', 'id': identity, 'monotonic_seconds': 95.5})
        browser.extend([{'kind': 'accepted'}, {'kind': 'cleanup', 'passed': True}])
        for row in browser: row['token'] = TOKEN
        samples = [{'phase': 'scan', 'monotonic_seconds': 10050.5, 'scan_state': {'MainPID': '10'}}]
        summary = {'resource_scan_accepted': True, 'profile': {'workload_token': TOKEN}}
        clocks = [{'host_monotonic_seconds': 10050, 'controller_begin': 50, 'controller_end': 50.1},
                  {'host_monotonic_seconds': 10051, 'controller_begin': 51, 'controller_end': 51.1}]
        for row in clocks: row.update(token=TOKEN, boot_id='fixture-boot')
        return [browser, samples, summary, {'accepted': True}, clocks, TOKEN]

    def test_unrelated_clock_origins_are_bracketed(self):
        self.assertTrue(w.accept(*self.evidence())['accepted'])

    def test_missing_or_stale_evidence_cannot_pass(self):
        for failure in ('token', 'scan', 'resource', 'logout', 'tls', 'cleanup', 'bracket', 'wide', 'overlap', 'gap', 'old-session', 'short-other-path'):
            args = self.evidence()
            if failure == 'token': args[0][0]['token'] = 'b'*64
            if failure == 'scan': args[1] = []
            if failure == 'resource': args[2]['resource_scan_accepted'] = False
            if failure == 'logout': args[0][1]['logout'] = False
            if failure == 'old-session': args[0][1]['old_session_denied'] = False
            if failure == 'short-other-path':
                args[0] = [r for r in args[0] if not (r.get('id') == 'vip-ipv6' and r.get('kind') == 'active' and r['monotonic_seconds'] > 40)]
            if failure == 'tls': args[0][0]['trusted_tls'] = False
            if failure == 'cleanup': args[0][-1]['passed'] = False
            if failure == 'bracket': args[4] = args[4][:1]
            if failure == 'wide': args[4][-1]['controller_end'] = 60
            if failure == 'overlap':
                for row in args[4]: row['controller_begin'] += 100; row['controller_end'] += 100
            if failure == 'gap': args[0] = [r for r in args[0] if r.get('monotonic_seconds') not in (49, 49.5, 50, 50.5)]
            with self.subTest(failure=failure), self.assertRaises(ValueError): w.accept(*args)

    def test_actual_client_receipts_join_parent_verifier(self):
        # Actual client/receipt logic, synthetic browser adapter; scan/control
        # samples are synthetic to test the cross-clock interface, not capacity.
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / 'browser.json'
            run = subprocess.run(['node', str(ROOT / 'tests/test_proxy_statistics_client.cjs'),
                                  '--receipt', str(path)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stderr)
            browser = json.loads(path.read_text())
            pair = [r['monotonic_seconds'] for r in browser if r['kind'] == 'active' and r['id'] in ('a-ipv4', 'b-ipv6')]
            midpoint = (min(pair) + max(pair)) / 2
            clocks = [{'host_monotonic_seconds': t + 10000, 'controller_begin': t,
                       'controller_end': t + .1, 'token': TOKEN, 'boot_id': 'fixture-boot'}
                      for t in (midpoint - 1, midpoint + 1)]
            scan = [{'phase': 'scan', 'monotonic_seconds': midpoint + 10000, 'scan_state': {'MainPID': '10'}}]
            summary = {'resource_scan_accepted': True, 'profile': {'workload_token': TOKEN}}
            self.assertTrue(w.accept(browser, scan, summary, {'accepted': True}, clocks, TOKEN)['accepted'])

    def test_diagnostic_clock_envelope_and_resource_coverage(self):
        import copy
        boot = 'a'*8+'-'+ 'b'*4+'-'+ 'c'*4+'-'+ 'd'*4+'-'+ 'e'*12
        before = {host: dict(clock='linux-boottime', monotonic=1000, controller_begin=10, controller_end=10.1, boot_id=boot)
                  for host in ('backend', 'node-a', 'node-b')}
        after = {host: dict(clock='linux-boottime', monotonic=1030, controller_begin=40, controller_end=40.1, boot_id=boot) for host in before}
        samples = [dict(clock='linux-boottime', monotonic=1001+i, boot_id=boot, event_delta={unit: {'status': 'comparable', 'events': {'oom_kill': 0}}
                   for unit in ('webmin.service', 'uptime-kuma.service')}) for i in range(25)] + [{'terminal': True}]
        request = [dict(request_id='a'*32, node='node-a', boot_id=boot, start=1010, end=1015)]
        for case in ('pass', 'late', 'boot', 'gap', 'missing', 'uncertain', 'reset'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as name:
                root = Path(name); b, a, rows, req = map(copy.deepcopy, (before, after, samples, request))
                if case == 'late': req[0]['end'] = 1028
                if case == 'boot': a['backend']['boot_id'] = 'different'
                if case == 'gap': del rows[10:14]
                if case == 'missing': rows.pop()
                if case == 'uncertain': a['node-a']['controller_end'] += 6
                if case == 'reset': rows[12]['event_delta']['webmin.service']['status'] = 'unavailable-or-reset'
                for key, value in [('before', b), ('after', a), ('requests', req)]: w.write(root/key, value)
                (root/'samples').write_text(''.join(json.dumps(row)+'\n' for row in rows)); (root/'samples').chmod(0o600)
                if case == 'pass':
                    h.diagnostic_coverage(root/'before', root/'after', root/'samples', root/'requests', root/'receipt')
                    accepted = json.loads((root/'receipt').read_text())
                    self.assertTrue(accepted['coverage_accepted']); self.assertFalse(accepted['causal_attribution'])
                else:
                    with self.assertRaises(ValueError): h.diagnostic_coverage(root/'before', root/'after', root/'samples', root/'requests', root/'receipt')
                    self.assertFalse((root/'receipt').exists())

    def test_request_index_checks_real_readback_encoding_and_node_identity(self):
        import base64, hashlib
        with tempfile.TemporaryDirectory(prefix='caddy-ssh-evidence-serving_health.') as name:
            directory = Path(name)
            w.atomic_text(directory/'owner.log', 'evidence_directory='+name+'\n')
            record = 'a'*32+'\tnode-a\taaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\t1001\t1002\n'
            def stream(text):
                raw = text.encode()
                return 'file=application-requests.tsv bytes='+str(len(raw))+' sha256='+hashlib.sha256(raw).hexdigest()+'\n'+base64.b64encode(raw).decode()+'\n'
            w.atomic_text(directory/'application-primary-a-readback.stdout', stream(record))
            self.assertEqual(h.request_records(directory/'owner.log')[0]['start'], 1001)
            w.atomic_text(directory/'application-result-a-readback.stdout', stream(record))
            self.assertEqual(len(h.request_records(directory/'owner.log')), 1)
            path = directory/'application-result-a-readback.stdout'
            path.write_text(stream(record.replace('1002', '1003')))
            with self.assertRaisesRegex(ValueError, 'changed_request'): h.request_records(directory/'owner.log')
            path.write_text(stream(record.replace('node-a', 'node-b')))
            with self.assertRaisesRegex(ValueError, 'request_node'): h.request_records(directory/'owner.log')
            path.write_text(stream(record).replace('sha256=', 'sha256=0'))
            with self.assertRaisesRegex(ValueError, 'readback_metadata'): h.request_records(directory/'owner.log')

    def test_clock_capture_uses_fixed_read_only_command_and_retains_failure(self):
        from unittest.mock import patch
        from types import SimpleNamespace
        boot = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); w.write(root/'spec', {'clock_ssh_prefixes': {host: ['/usr/bin/ssh', 'fixture'] for host in ('backend', 'node-a', 'node-b')}})
            with patch.object(h.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=json.dumps({'clock': 'linux-boottime', 'boot_id': boot, 'monotonic': 1}))) as run:
                h.clock_capture(root/'spec', root/'clocks')
                self.assertEqual(run.call_count, 3)
                self.assertEqual(run.call_args.kwargs['timeout'], 5)
                self.assertIn('/proc/sys/kernel/random/boot_id', run.call_args.args[0][-1])
            with patch.object(h.subprocess, 'run', side_effect=subprocess.TimeoutExpired('PRIVATE', 5)):
                with self.assertRaises(ValueError): h.clock_capture(root/'spec', root/'failed')
                self.assertNotIn('PRIVATE', (root/'failed').read_text())

    def test_private_atomic_receipt_is_exclusive(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / 'receipt.json'
            w.write(path, {'accepted': False})
            self.assertEqual(json.loads(w.private(path)), {'accepted': False})
            with self.assertRaises(FileExistsError): w.write(path, {'accepted': True})
            path.chmod(0o644)
            with self.assertRaises(ValueError): w.private(path)

    def test_real_child_exits_on_owned_stop(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True)
        try:
            result = w.stop_owned(child, grace=1)
            self.assertTrue(result['group_gone'])
            self.assertIsNotNone(child.poll())
        finally:
            if child.poll() is None: child.kill(); child.wait()

    def test_handoff_cannot_hide_failed_browser_cleanup(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); result = root / 'workload.json'
            w.write(result, {'browser_cleanup': {'group_gone': False}})
            with self.assertRaisesRegex(ValueError, 'browser_cleanup'):
                h.finish(root / 'absent', result)

    def test_handoff_binds_exact_owner_child_and_refuses_replay(self):
        with patch.object(tempfile, '_get_candidate_names', side_effect=lambda: (format(i, 'x') for i in itertools.count())), tempfile.TemporaryDirectory(prefix='caddy-ssh-evidence-serving_health.', dir='/tmp') as name:
            root = Path(name); ready = root / 'application-trial-ready.tsv'; log = root / 'owner.log'; receipt = root / 'receipt.json'
            w.atomic_text(ready, 'test-child-123\n')
            w.atomic_text(log, 'application_trial_ready=' + str(ready) + '\n')
            h.ready(log, receipt); h.finish(receipt)
            self.assertEqual((root / 'application-trial-finish.tsv').read_text(), 'test-child-123\tcomplete\n')
            with self.assertRaises(FileExistsError): h.finish(receipt)

    def test_failed_observer_stops_owned_browser_before_cancel(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            spec = {'evidence_directory': name, 'token': TOKEN}
            for key in ('browser_receipt', 'samples', 'summary', 'observation'): spec[key] = str(root / key)
            for key in ('observer_argv', 'browser_argv'): spec[key] = [sys.executable, '-c', 'import time; time.sleep(60)']
            for key in ('state_argv', 'ready_argv', 'cancel_argv'): spec[key] = ['/fixture/' + key]
            calls = []
            def control(argv, **kwargs):
                calls.append(argv[0]); row = {'host_monotonic_seconds': 1, 'boot_id': 'fixture-boot', 'token': TOKEN, 'ready': True, 'failed': calls.count('/fixture/state_argv') > 1}
                return type('Result', (), {'returncode': 0, 'stdout': json.dumps(row)})()
            real_stop = w.stop_owned
            def stop(child, grace=15):
                calls.append('stop-owned'); return real_stop(child, grace=.1)
            with patch.object(w.subprocess, 'run', side_effect=control), patch.object(w, 'stop_owned', side_effect=stop):
                # Shorten only the observer's post-cancellation wait. Its native side
                # is absent here, so retaining incomplete cleanup is the expected result.
                original_wait = subprocess.Popen.wait
                def bounded_wait(child, timeout=None): return original_wait(child, timeout=.1 if timeout == 30 else timeout)
                with patch.object(subprocess.Popen, 'wait', bounded_wait):
                    self.assertEqual(w.supervise(spec, b'{}'), 1)
            self.assertLess(calls.index('stop-owned'), calls.index('/fixture/cancel_argv'))
            result = json.loads((root / 'workload-result.json').read_text())
            self.assertFalse(result['accepted'])
            self.assertTrue(result['browser_cleanup']['group_gone'])
            self.assertTrue(result['observer_cleanup_incomplete'])


if __name__ == '__main__': unittest.main()
