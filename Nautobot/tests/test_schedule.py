#!/usr/bin/env python3
"""Frozen schedule input and permission boundaries; no production access."""
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import yaml
from jsonschema import Draft202012Validator, ValidationError

ROOT = Path(__file__).resolve().parents[2]


class Schedule(unittest.TestCase):
    def test_bundle_generated_inputs_and_tamper_refusal(self):
        operation = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if operation['operation'].get('stage') != 'recurring_schedule_enablement':
            self.skipTest('no pending schedule definition')
        spec = importlib.util.spec_from_file_location('schedule_bundle', ROOT/'Nautobot/ansible/scripts/schedule-bundle.py')
        bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
        with tempfile.TemporaryDirectory() as temporary:
            # Acceptance advances the live record while the consumed operation
            # retains its original hash until archival. Bind only this local test
            # candidate to today's input; never rewrite the consumed definition.
            candidate_operation = copy.deepcopy(operation)
            # The fresh installer remains independently covered when the pending
            # operation is a promotion with external hash-bound rollback inputs.
            candidate_operation.pop('promotion', None)
            candidate_operation['accepted_sha256'] = bundle.transport.sha(
                ROOT/'Nautobot/manifests/accepted-live-state.yaml')
            definition = Path(temporary)/'operation.yaml'
            definition.write_text(yaml.safe_dump(candidate_operation, sort_keys=False))
            root = Path(temporary)/'candidate'; bundle.transport.freeze(root, definition)
            digest = bundle.transport.sha(root/'bundle.json')
            bundle.transport.verify(root, digest)
            self.assertFalse(operation['operation']['execution_enabled'])
            self.assertTrue(json.loads((root/'runtime/supervisor.json').read_text())['execution_authorized'])
            expected = json.loads((root/'runtime-hashes.json').read_text())
            self.assertNotIn('PLAN.md', expected)
            self.assertEqual(len(list((root/'runtime/units').iterdir())), 9)
            for name in ('runtime-hashes.json', 'runtime/units/nautobot-protection.timer',
                         'runtime/scripts/recurring_delivery.py'):
                path = root/name; original = path.read_bytes(); path.write_bytes(original+b'changed')
                with self.assertRaisesRegex(ValueError, 'input_drift'):
                    bundle.transport.verify(root, digest)
                path.write_bytes(original)

    def test_schedule_schema_refuses_scope_expansion(self):
        operation = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if operation['operation'].get('stage') != 'recurring_schedule_enablement':
            self.skipTest('no pending schedule definition')
        validator = Draft202012Validator(json.loads((ROOT/'Nautobot/schemas/recurring-schedule.schema.json').read_text()))
        validator.validate(operation)
        for key, value in [('latest_start_minute', 225), ('run_seconds', 3000),
                           ('start_hour', 2), ('dispose_successful_payload', False),
                           ('notification_argv', ['/bin/true'])]:
            bad = copy.deepcopy(operation); bad['supervisor'][key] = value
            with self.subTest(key=key), self.assertRaises(ValidationError): validator.validate(bad)
        bad = copy.deepcopy(operation); bad['enabled_timers'].append('unrelated.timer')
        with self.assertRaises(ValidationError): validator.validate(bad)


class PromotionGuards(unittest.TestCase):
    """Real temporary file/hash checks; native ownership and services use the opt-in qualifier."""
    def setUp(self):
        spec = importlib.util.spec_from_file_location('schedule_guard', ROOT/'Nautobot/ansible/scripts/schedule_install.py')
        self.guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.guard)
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.runtime = self.root/'runtime'; self.state = self.root/'state'
        self.runtime.mkdir(); self.state.mkdir(); (self.runtime/'scripts').mkdir()
        self.names = ['scripts/logical_database.py','scripts/recurring_logical.py',
                      'scripts/recurring_node.py','scripts/recurring_disposal.py','binding.json']
        self.old = {n:self.put(n,b'old') for n in self.names[2:]}
        self.new = {n:hashlib.sha256(b'new').hexdigest() for n in self.names}
        self.state_value = {'phase':'complete','configuration_sha256':'0'*64}
        (self.state/'state.json').write_text(json.dumps(self.state_value))
        self.op = {'runtime_directory':str(self.runtime),'state_directory':str(self.state),
            'baseline':{'collected_at':'2026-01-01T17:00:00+00:00'},'promotion':{'files':self.names,
            'new_files':self.names[:2],'state':self.state_value,'previous_runtime_sha256':self.old,
            'python_cache_sha256':{},'installation_date':'2026-01-01'}}
        now = datetime(2026,1,1,18,tzinfo=timezone.utc)
        class Clock(datetime):
            @classmethod
            def now(cls,tz=None): return now.astimezone(tz)
        for mock in (patch.object(self.guard,'datetime',Clock), patch.object(self.guard,'metadata'),
                     patch.object(self.guard,'system',return_value='inactive'),
                     patch.object(self.guard,'check',side_effect=self.check)):
            mock.start(); self.addCleanup(mock.stop)

    def put(self,name,raw):
        path=self.runtime/name;path.parent.mkdir(exist_ok=True);path.write_bytes(raw)
        return hashlib.sha256(raw).hexdigest()

    def check(self,op,expected,action):
        self.guard.runtime_files(self.runtime,expected)
        return {'installed':True}

    def call(self,action='promotion-preflight'):
        return self.guard.promotion_guard(self.op,self.new,action)

    def test_old_then_exact_new_is_idempotent(self):
        self.assertTrue(self.call()['promotion_needed'])
        for name in self.names:self.put(name,b'new')
        self.assertFalse(self.call()['promotion_needed'])

    def test_partial_update_refuses_new_admission(self):
        self.put(self.names[0],b'new')
        with self.assertRaises(self.guard.Refused):self.call()

    def test_state_drift_refuses_before_runtime_checks(self):
        (self.state/'state.json').write_text('{"phase":"recovering"}')
        with self.assertRaisesRegex(self.guard.Refused,'schedule_state_drift'):self.call()

    def test_active_capture_or_recovery_refuses(self):
        self.guard.system.return_value='active'
        with self.assertRaisesRegex(self.guard.Refused,'active_capture_or_recovery'):self.call()

    def test_date_and_stale_baseline_refuse(self):
        self.op['promotion']['installation_date']='2026-01-02'
        with self.assertRaisesRegex(self.guard.Refused,'promotion_window'):self.call()
        self.op['promotion']['installation_date']='2026-01-01'
        self.op['baseline']['collected_at']='2025-12-30T00:00:00+00:00'
        with self.assertRaisesRegex(self.guard.Refused,'baseline_expired'):self.call()

    def test_partial_rollback_allowed_foreign_bytes_refused(self):
        self.put(self.names[0],b'new');self.put('binding.json',b'new')
        self.call('promotion-rollback-guard')
        self.put('binding.json',b'foreign')
        with self.assertRaisesRegex(self.guard.Refused,'rollback_foreign_bytes'):
            self.call('promotion-rollback-guard')

    def test_missing_original_never_recreated_by_rollback(self):
        (self.runtime/'binding.json').unlink()
        with self.assertRaisesRegex(self.guard.Refused,'rollback_missing_original'):
            self.call('promotion-rollback-guard')


if __name__ == '__main__': unittest.main()
