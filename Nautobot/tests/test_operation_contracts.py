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
        if operation['operation']['state'] == 'clean':
            self.assertEqual(operation, {'schema_version': 1, 'operation': {
                'state': 'clean', 'authorization_ready': False}})
        elif operation['operation'].get('stage') == 'administrator_bootstrap':
            validate(json.loads((ROOT / 'Nautobot/schemas/administrator-bootstrap.schema.json').read_text()), operation)
            self.assertFalse(operation['runtime']['first_install_only'])
            self.assertEqual(operation['runtime']['services'], ['postgresql', 'redis'])
            self.assertFalse(operation['acceptance']['application_accepted'])
        elif operation['operation'].get('stage') == 'retained_database_inspection':
            validate(json.loads((ROOT / 'Nautobot/schemas/database-inspection.schema.json').read_text()), operation)
            self.assertEqual(operation['runtime']['services'], ['postgresql'])
            self.assertFalse(operation['acceptance']['initialization_accepted'])
        elif operation['operation'].get('stage') == 'runtime_continuation':
            validate(json.loads((ROOT / 'Nautobot/schemas/runtime-continuation.schema.json').read_text()), operation)
            self.assertFalse(operation['runtime']['first_install_only'])
            self.assertEqual(operation['runtime']['services'], ['postgresql', 'redis', 'migration'])
            self.assertFalse(operation['failure']['automatic_restore'])
            self.assertFalse(operation['acceptance']['application_accepted'])
        elif operation['operation'].get('stage') == 'workload_qualification':
            from jsonschema import RefResolver
            schema = json.loads((ROOT/'Nautobot/schemas/workload-operation.schema.json').read_text())
            Draft202012Validator(schema, resolver=RefResolver(base_uri=(ROOT/'Nautobot/schemas').as_uri()+'/', referrer=schema)).validate(operation)
            self.assertFalse(operation['scope']['restore'])
            self.assertFalse(operation['scope']['service_restart'])
            self.assertEqual(operation['execution']['operation_id'], operation['operation']['id'])
        elif operation['operation'].get('stage') == 'application_startup':
            contract = json.loads((ROOT / 'Nautobot/schemas/startup-operation.schema.json').read_text())
            validate(contract, operation)
            self.assertIn(contract, SCHEMA['oneOf'])
            self.assertFalse(operation['scope']['automatic_restore'])
            self.assertFalse(operation['scope']['reboot'])
            self.assertFalse(operation['scope']['caddy_publication'])
        elif operation['operation'].get('stage') == 'runtime_initialization':
            validate(json.loads((ROOT / 'Nautobot/schemas/runtime-initialization.schema.json').read_text()), operation)
            self.assertEqual(operation['authorization']['approval_record'], 'not_yet_granted_exact_bundle_required')
            self.assertEqual(operation['runtime']['services'], ['postgresql', 'redis', 'migration'])
        elif operation['operation'].get('stage') == 'isolated_canary_restore':
            validate(json.loads((ROOT / 'Nautobot/schemas/canary-restore.schema.json').read_text()), operation)
            self.assertEqual(operation['authorization']['approval_record'], 'not_yet_granted_exact_bundle_required')
            self.assertEqual(operation['implementation']['state'], 'reviewed')
        elif operation['operation'].get('stage') == 'canary_backup_integrity':
            validate(json.loads((ROOT / 'Nautobot/schemas/canary-backup.schema.json').read_text()), operation)
            self.assertEqual(operation['authorization']['approval_record'], 'not_yet_granted')
            self.assertEqual(operation['implementation']['state'], 'reviewed')
        elif operation['operation'].get('stage') == 'restic_repository_initialization':
            branch = next(item for item in SCHEMA['oneOf']
                          if item.get('title') == 'Reviewed standalone Restic initialization')
            validate(branch, operation)
            self.assertEqual(operation['authorization']['approval_record'], 'not_yet_granted')
        elif operation['operation'].get('stage') == 'repository_absence_preflight':
            branch = next(item for item in SCHEMA['oneOf']
                          if item.get('title') == 'Fresh read-only repository absence preflight')
            validate(branch, operation)
            self.assertFalse(operation['authorization']['mutation_authorized'])
            self.assertEqual(operation['repository']['initialized_state'], 'unknown')
        else:
            schema_name = {'credential_provisioning': 'credential-operation.schema.json',
                           'image_loading': 'image-load.schema.json',
                           'configuration_authentication': 'authentication-trial.schema.json'}.get(
                               operation['operation'].get('stage'), 'image-build.schema.json')
            validate(json.loads((ROOT / 'Nautobot/schemas' / schema_name).read_text()), operation)
            self.assertFalse(operation['authorization']['mutation_authorized'])
            self.assertFalse(any(operation['boundaries'].values()))
        accepted = yaml.safe_load((ROOT / 'Nautobot/manifests/accepted-live-state.yaml').read_text())
        validate(json.loads((ROOT / 'Nautobot/schemas/accepted-host-baseline.schema.json').read_text()), accepted)
        self.assertFalse(any(accepted['boundaries'].values()))

    def test_canary_definition_boundaries(self):
        import hashlib
        schema=json.loads((ROOT/'Nautobot/schemas/canary-backup.schema.json').read_text())
        document={key:copy.deepcopy(value['const']) for key,value in schema['properties'].items()}
        validate(schema,document)
        file=document['dataset']['files'][0]
        self.assertEqual(len(file['content_utf8'].encode()),file['size_bytes'])
        self.assertEqual(hashlib.sha256(file['content_utf8'].encode()).hexdigest(),file['sha256'])
        for section,key,value in [('authorization','approval_record','implicitly_granted'),
                                  ('snapshot_identity','selection','latest'),
                                  ('commands','integrity',['check']),
                                  ('failure_and_recovery','automatic_delete',True),
                                  ('acceptance','restore_accepted',True)]:
            bad=copy.deepcopy(document);bad[section][key]=value
            with self.assertRaises(ValidationError):validate(schema,bad)

    def test_restore_definition_pins_identity_and_isolation(self):
        schema=json.loads((ROOT/'Nautobot/schemas/canary-restore.schema.json').read_text())
        document={key:copy.deepcopy(value['const']) for key,value in schema['properties'].items()}
        validate(schema,document)
        accepted=json.loads((ROOT/'Nautobot/manifests/canary-backup-result.json').read_text())
        self.assertEqual(document['snapshot']['id'], accepted['snapshot_id'])
        self.assertEqual(document['snapshot']['restore_selector'], accepted['snapshot_id']+':'+accepted['source']['root'])
        self.assertEqual(document['expected_tree']['files'][0]['sha256'], accepted['source']['file']['sha256'])
        for section,key,value in [('authorization','approval_record','implicitly_granted'),
                                  ('snapshot','id','latest'),
                                  ('destination','new_empty_directory_required',False),
                                  ('destination','source_overlap_allowed',True),
                                  ('expected_tree','extra_paths_allowed',True),
                                  ('acceptance','application_recovery_accepted',True)]:
            bad=copy.deepcopy(document);bad[section][key]=value
            with self.assertRaises(ValidationError):validate(schema,bad)

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

    def test_startup_identity_requires_provenance_and_preserves_scope(self):
        schema = json.loads((ROOT / 'Nautobot/schemas/accepted-host-baseline.schema.json').read_text())
        accepted = yaml.safe_load((ROOT / 'Nautobot/manifests/accepted-live-state.yaml').read_text())
        validate(schema, accepted)
        identity = accepted['application_startup']
        for key in identity:
            bad = copy.deepcopy(accepted)
            del bad['application_startup'][key]
            with self.assertRaises(ValidationError): validate(schema, bad)
        for key, value in [('scope', 'full_runtime_accepted'), ('archive_commit', 'pending'),
                           ('result_sha256', ''), ('reviewed_at', 'yesterday'),
                           ('remaining_gates', []), ('artifact_sha256', {})]:
            bad = copy.deepcopy(accepted)
            bad['application_startup'][key] = value
            with self.assertRaises(ValidationError): validate(schema, bad)
        self.assertFalse(accepted['boundaries']['runtime_accepted'])
        baseline_only = copy.deepcopy(accepted)
        del baseline_only['application_startup']
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
