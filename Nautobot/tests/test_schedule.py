#!/usr/bin/env python3
"""Frozen schedule input and permission boundaries; no production access."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
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


if __name__ == '__main__': unittest.main()
