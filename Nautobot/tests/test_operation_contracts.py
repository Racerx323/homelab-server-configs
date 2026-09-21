#!/usr/bin/env python3
"""Offline negative tests for inactive backup and provenance contracts."""
import copy
import json
from pathlib import Path
import unittest
import yaml
from jsonschema import Draft202012Validator, FormatChecker, ValidationError
ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT / 'Nautobot/schemas/operation.schema.json').read_text())
BACKUP = SCHEMA['oneOf'][2]['properties']


def validate(schema, value):
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(value)


class Contracts(unittest.TestCase):
    def test_unverified_prerequisites_are_explicit(self):
        for name, result in [('host_baseline', 'host_baseline_accepted'),
                             ('repository_initialization', 'repository_initialization_accepted')]:
            schema = BACKUP['prerequisites']['properties'][name]
            value = {'state': 'unverified', 'required_result': result,
                     'evidence': None, 'reason': 'Terminal acceptance not yet performed'}
            validate(schema, value)
            for bad in ({}, {**value, 'evidence': {}}, {**value, 'state': 'accepted'},
                        {**value, 'required_result': 'storage_soak_healthy_isolated_restore_pending'}):
                with self.assertRaises(ValidationError): validate(schema, bad)

    def test_terminal_proof_requires_complete_bound_identity(self):
        schema = BACKUP['prerequisites']['properties']['repository_initialization']
        value = {'state': 'accepted', 'required_result': 'repository_initialization_accepted',
                 'evidence': {'operation_id': 'offline-fixture', 'terminal_tag': 'offline-terminal',
                              'archive_commit': 'a'*40, 'bundle_sha256': 'b'*64,
                              'record_sha256': 'c'*64, 'accepted_identity_sha256': 'd'*64,
                              'accepted_at': '2026-09-16T12:00:00Z', 'target': 'j2-svpi4mf'}}
        validate(schema, value)
        for key in value['evidence']:
            bad = copy.deepcopy(value); del bad['evidence'][key]
            with self.assertRaises(ValidationError): validate(schema, bad)
        for key, replacement in [('accepted_at', 'yesterday'), ('bundle_sha256', 'wrong'),
                                 ('target', 'different-host')]:
            bad = copy.deepcopy(value); bad['evidence'][key] = replacement
            with self.assertRaises(ValidationError): validate(schema, bad)

    def test_order_and_acceptance_cannot_be_weakened(self):
        contracts = [BACKUP['workflow']['properties']['ordered_actions'],
                     BACKUP['acceptance']['properties']['require'],
                     BACKUP['acceptance']['properties']['boundaries'],
                     BACKUP['evidence']['properties']['records']]
        for schema in contracts:
            value = schema['const']; validate(schema, value)
            for bad in ([], value[:-1], list(reversed(value)), ['anything']):
                with self.assertRaises(ValidationError): validate(schema, bad)

    def test_clean_slot_and_accepted_identity(self):
        operation = yaml.safe_load((ROOT / 'Nautobot/manifests/operation.yaml').read_text())
        self.assertEqual(operation, {'schema_version': 1, 'operation': {
            'state': 'clean', 'authorization_ready': False}})
        accepted = yaml.safe_load((ROOT / 'Nautobot/manifests/accepted-live-state.yaml').read_text())
        validate(json.loads((ROOT / 'Nautobot/schemas/accepted-host-baseline.schema.json').read_text()), accepted)
        self.assertFalse(any(accepted['boundaries'].values()))

    def test_dual_stack_acceptance_requires_complete_provenance(self):
        schema = json.loads((ROOT / 'Nautobot/schemas/accepted-host-baseline.schema.json').read_text())
        accepted = yaml.safe_load((ROOT / 'Nautobot/manifests/accepted-live-state.yaml').read_text())
        validate(schema, accepted)
        for field in accepted['dual_stack_identity']:
            bad = copy.deepcopy(accepted)
            del bad['dual_stack_identity'][field]
            with self.assertRaises(ValidationError): validate(schema, bad)
        for field, value in [('ipv6', '::1'), ('definition_commit', 'unarchived'),
                             ('terminal_evidence_sha256', ''), ('limitations', [])]:
            bad = copy.deepcopy(accepted)
            bad['dual_stack_identity'][field] = value
            with self.assertRaises(ValidationError): validate(schema, bad)
        baseline_only = copy.deepcopy(accepted)
        del baseline_only['dual_stack_identity']
        validate(schema, baseline_only)

    def test_status_provenance_matches_frozen_definition(self):
        schema = json.loads((ROOT / 'Nautobot/schemas/host-convergence.schema.json').read_text())
        operation = copy.deepcopy(schema['const'])
        validate(schema, operation)
        p = operation['preparation_review']
        self.assertFalse(p['status_provenance']['live_refresh_performed'])
        self.assertFalse(p['status_provenance']['historical_authorizations_are_reusable'])
        for key in ('package_cleanup', 'post_cleanup_preflight', 'completed_preflight'):
            self.assertIsNone(p[key]['observed_at'])
            self.assertEqual(p[key]['timestamp_status'], 'not_established_from_reviewed_record')
        validate({'type':'string','format':'date-time'}, p['webmin_followup_observation']['observed_at'])
        self.assertNotIn('correction_authorized', p['readiness_review'])
        self.assertNotIn('reboot_authorized', p['readiness_review']['memory_correction'])
        bad = copy.deepcopy(operation)
        bad['preparation_review']['readiness_review']['memory_correction']['authorization_reusable'] = True
        with self.assertRaises(ValidationError): validate(schema, bad)


if __name__ == '__main__': unittest.main()
