#!/usr/bin/env python3
"""Offline contract and adverse-evidence regression tests; no host contact."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import os
import tempfile
import shutil
import sys
import unittest

import yaml

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'Nautobot/ansible/scripts'
SPEC = importlib.util.spec_from_file_location('convergence', SCRIPTS / 'evaluate-host-convergence.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
# The frozen contract remains the offline probe/expectation fixture after archival.
# Live execution still reads only manifests/operation.yaml.
DOC = json.loads((ROOT / 'Nautobot/schemas/host-convergence.schema.json').read_text())['const']

LAUNCHER_SPEC = importlib.util.spec_from_file_location('launcher', SCRIPTS / 'run-host-convergence.py')
LAUNCHER = importlib.util.module_from_spec(LAUNCHER_SPEC)
LAUNCHER_SPEC.loader.exec_module(LAUNCHER)


def passing_fixture():
    doc = copy.deepcopy(DOC)
    doc['storage_evidence']['current_boot_validation'] = {
        'state': 'passed', 'boot_id': 'af1ed3ab-0bdc-422a-b893-bc3ccd924fde',
        'evidence_reference': 'synthetic-offline-storage-evidence',
    }
    # Synthetic expectations are deliberately distinct from unresolved live identity.
    doc['expected'].update(uid=999, gid=999, listeners=['tcp LISTEN 0.0.0.0:22 0.0.0.0:*'])
    doc['expected']['packages']['needrestart'] = 'fixture-version'
    doc['preparation_review']['probe_review']['storage_window_boot_id'] = 'af1ed3ab-0bdc-422a-b893-bc3ccd924fde'
    units = []
    for name in doc['expected']['required_units']:
        units.append(f'Id={name}\nLoadState=loaded\nActiveState=active\nUnitFileState=enabled')
    for name in doc['expected']['unwanted_units']:
        units.append(f'Id={name}\nLoadState=masked\nActiveState=inactive\nUnitFileState=masked')
    units.append('Id=keepalived.service\nLoadState=not-found\nActiveState=inactive\nUnitFileState=')
    outputs = {
        'privilege': '', 'boot_start': 'af1ed3ab-0bdc-422a-b893-bc3ccd924fde',
        'boot_end': 'af1ed3ab-0bdc-422a-b893-bc3ccd924fde',
        'packages': '\n'.join(f'{k}\t{v}\tinstalled' for k,v in doc['expected']['packages'].items()),
        'passwd': 'nautobot:x:999:999::/var/lib/nautobot:/usr/sbin/nologin',
        'identity': 'uid=999(nautobot) gid=999(nautobot) groups=999(nautobot)',
        'home': '999:999:750:directory', 'subuid': 'nautobot:165536:65536',
        'subgid': 'nautobot:165536:65536', 'linger': 'UID=999\nLinger=yes\nState=lingering',
        'podman': json.dumps({'host': {'security': {'rootless': True}}, 'store': {'graphRoot': '/var/lib/nautobot/.local/share/containers/storage'}}),
        'cgroup_controllers': 'cpuset cpu io memory pids',
        'units': '\n\n'.join(units), 'failed_units': '', 'keepalived_process': '',
        'keepalived_config': '', 'keepalived_config_symlink': '',
        'keepalived_unit_files': '', 'keepalived_units': '',
        'addresses': json.dumps([{'ifname':'eth0','addr_info':[{'local':'fd36:5aa8:6971:1::170','family':'inet6','prefixlen':64,'valid_life_time':4294967295,'preferred_life_time':4294967295}]}]),
        'root': '{"filesystems":[{"source":"/dev/sda2","fstype":"ext4","target":"/"}]}',
        'cmdline': 'root=/dev/sda2 usb-storage.quirks=152d:0583:u',
        'usb': 'DRIVERS=="usb-storage"\n\nATTRS{idVendor}=="152d"\nATTRS{idProduct}=="0583"\nATTRS{speed}=="5000"',
        'storage_events': '', 'smart': json.dumps({'smartctl':{'exit_status':0},'smart_status':{'passed':True},'nvme_smart_health_information_log':{'critical_warning':0,'media_errors':0,'num_err_log_entries':0},'temperature':{'current':44}}),
        'smart_settle': '', 'post_smart_storage_events': '',
        'ext4_errors': '0', 'ext4_metadata': 'Filesystem state:         clean',
        'temperature': "temp=51.1'C", 'throttling': 'throttled=0x0',
        'listeners': 'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*',
        'residue': 'Reading package lists...\n0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.',
    }
    results = [{'item':copy.deepcopy(p), 'cmd':p['argv'][:], 'stdout':outputs[p['id']], 'stderr':'',
                'rc':1 if p['id'] in {'keepalived_process','keepalived_config','keepalived_config_symlink'} else 0}
               for p in doc['preflight']['probes']]
    return doc, results


class Contract(unittest.TestCase):
    def test_optional_ui_listener_does_not_relax_required_or_exposure_checks(self):
        doc, results = passing_fixture()
        doc['expected']['optional_listeners'] = ['tcp LISTEN 127.0.0.1:555 0.0.0.0:*']
        row = next(r for r in results if r['item']['id'] == 'listeners')
        required = row['stdout']
        for extra in ['', '\ntcp LISTEN 0 5 127.0.0.1:555 0.0.0.0:*']:
            row['stdout'] = required + extra
            self.assertEqual(MODULE.evaluate(doc, results)['result'], 'preflight_passed_review_required')
        for invalid in ['', 'tcp LISTEN 0 5 127.0.0.1:555 0.0.0.0:*',
                        required + '\ntcp LISTEN 0 5 0.0.0.0:555 0.0.0.0:*',
                        required + '\n' + required]:
            row['stdout'] = invalid
            self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')

    def test_unit_file_no_matches_exit_one_requires_empty_clean_output(self):
        doc, results = passing_fixture()
        result = next(r for r in results if r['item']['id'] == 'keepalived_unit_files')
        result['rc'] = 1
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'preflight_passed_review_required')
        for patch in [{'stdout': 'keepalived.service enabled'}, {'stderr': 'permission denied'}, {'rc': 2}]:
            changed = copy.deepcopy(results)
            next(r for r in changed if r['item']['id'] == 'keepalived_unit_files').update(patch)
            self.assertEqual(MODULE.evaluate(doc, changed)['result'], 'blocked')

    def test_pass_and_unresolved_live_identity(self):
        doc, results = passing_fixture()
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'preflight_passed_review_required')
        self.assertEqual(MODULE.evaluate(DOC, results)['result'], 'blocked')

    def test_every_probe_rejects_failure_timeout_privilege_and_malformed_output(self):
        for index in range(len(DOC['preflight']['probes'])):
            for patch in [{'rc':124}, {'rc':137}, {'rc':127}, {'rc':1,'stderr':'sudo: a password is required'},
                          {'stdout':None}, {'stdout':'\x00'}, {'unreachable':True}, {'skipped':True}, {'cmd':['true']}]:
                with self.subTest(index=index, patch=patch):
                    doc, results = passing_fixture()
                    results[index].update(patch)
                    self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')

    def test_reported_reboot_requires_new_reviewed_storage_evidence(self):
        self.assertTrue(DOC['storage_evidence']['operator_report']['reboot_since_last_storage_validation'])
        self.assertTrue(DOC['storage_evidence']['operator_report']['live_verified'])
        self.assertEqual(DOC['component_ownership']['needrestart']['owner'], 'Needrestart/')
        for state in ['required', 'failed']:
            doc, results = passing_fixture()
            doc['storage_evidence']['current_boot_validation']['state'] = state
            self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')
        doc, results = passing_fixture()
        doc['storage_evidence']['current_boot_validation']['evidence_reference'] = None
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')
        doc, results = passing_fixture()
        new_boot = '11111111-2222-4333-8444-555555555555'
        for result in results:
            if result['item']['id'] in ['boot_start', 'boot_end']:
                result['stdout'] = new_boot
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')
        doc['storage_evidence']['current_boot_validation']['boot_id'] = new_boot
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')
        doc['preparation_review']['probe_review']['storage_window_boot_id'] = new_boot
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'preflight_passed_review_required')

    def test_drift(self):
        for name, value in {
            'packages':'podman\twrong\tinstalled', 'passwd':'nautobot:x:0:0::/:/bin/bash',
            'subuid':'nautobot:165536:65536\nother:165536:1', 'linger':'UID=999\nLinger=no\nState=active',
            'units':'', 'failed_units':'broken.service loaded failed failed', 'addresses':'[]',
            'root':'{}', 'cmdline':'usb-storage.quirks=152d:0583:u usb-storage.quirks=152d:0583:u',
            'usb':'DRIVERS=="uas"', 'storage_events':'I/O error, dev sda', 'smart':'{}',
            'post_smart_storage_events':'usb 2-2: reset SuperSpeed USB device',
            'cgroup_controllers':'cpuset cpu io pids',
            'ext4_errors':'garbage', 'temperature':"temp=80.1'C", 'throttling':'throttled=0x50000',
            'listeners':'tcp LISTEN 0 128 0.0.0.0:5432 0.0.0.0:*', 'residue':'Remv fixture [1]',
            'boot_end':'a-different-boot', 'home':'999:999:777:directory'
        }.items():
            with self.subTest(name=name):
                doc, results = passing_fixture()
                next(r for r in results if r['item']['id'] == name)['stdout'] = value
                self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')

    def test_retained_package_changes_reject_old_version_missing_frontend_and_wrong_arch(self):
        for old, new in [
            ('smartmontools\t7.5-2~bpo13+1\tinstalled', 'smartmontools\t7.4-3\tinstalled'),
            ('bsd-mailx\t8.1.2-0.20220412cvs-1.1\tinstalled', 'bsd-mailx\t8.1.2-0.20220412cvs-1.1\tconfig-files'),
            ('liblockfile1:arm64\t1.17-2\tinstalled', 'liblockfile1:amd64\t1.17-2\tinstalled'),
        ]:
            with self.subTest(package=old.split('\t')[0]):
                doc, results = passing_fixture()
                packages = next(r for r in results if r['item']['id'] == 'packages')
                self.assertIn(old, packages['stdout'])
                packages['stdout'] = packages['stdout'].replace(old, new)
                result = MODULE.evaluate(doc, results)
                self.assertEqual(result['result'], 'blocked')
                self.assertFalse(result['checks']['exact_packages_and_no_config_residue'])

    def test_empty_journal_status_is_not_confused_with_failed_collection(self):
        doc, results = passing_fixture()
        for row in results:
            if row['item']['id'] in ['storage_events', 'post_smart_storage_events']:
                row['rc'] = 1
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'preflight_passed_review_required')
        after = next(r for r in results if r['item']['id'] == 'post_smart_storage_events')
        after['stderr'] = 'journal read failed'
        self.assertEqual(MODULE.evaluate(doc, results)['result'], 'blocked')

    def test_exact_vectors_and_playbook_boundary(self):
        prefix = ['/usr/bin/sudo','-n','/usr/bin/timeout','--signal=TERM','--kill-after=5s','30s']
        probes = {p['id']:p['argv'] for p in DOC['preflight']['probes']}
        self.assertEqual(probes['podman'], prefix + ['/usr/sbin/runuser','--user','nautobot','--','/usr/bin/env','--chdir=/var/lib/nautobot','/usr/bin/podman','info','--format=json'])
        self.assertEqual(probes['packages'], prefix + ['/usr/bin/dpkg-query','--show','--showformat=${binary:Package}\t${Version}\t${db:Status-Status}\n'])
        self.assertEqual(probes['residue'], prefix + ['/usr/bin/apt-get','--simulate','autoremove'])
        self.assertEqual(probes['smart'], prefix + ['/usr/sbin/smartctl','--json','-q','noserial','-H','-i','-A','-l','error','/dev/sda'])
        self.assertEqual(probes['smart_settle'], prefix[:-1] + ['90s','/usr/bin/sleep','75'])
        names = list(probes)
        self.assertEqual(names[names.index('smart'):names.index('smart')+3],
                         ['smart', 'smart_settle', 'post_smart_storage_events'])
        for name in ['storage_events', 'post_smart_storage_events']:
            self.assertIn('--boot=0', probes[name])
            self.assertFalse(any(arg.startswith('--since=') for arg in probes[name]))
            self.assertIn('reset.*USB|USB.*reset', next(x for x in probes[name] if x.startswith('--grep=')))
        # Frozen reviewed schema binds the complete ordered argv catalog, including all other probes.
        schema = json.loads((ROOT/'Nautobot/schemas/host-convergence.schema.json').read_text())
        self.assertEqual(schema['const'], DOC)
        play = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/preflight-host-convergence.yaml').read_text())[0]
        tasks = play['tasks']
        self.assertFalse(play['become'])
        self.assertFalse(play['gather_facts'])
        self.assertEqual(tasks[0]['ansible.builtin.command'], {'argv':'{{ item.argv }}','expand_argument_vars':False})
        self.assertFalse(tasks[0]['failed_when'])
        self.assertFalse(tasks[0]['check_mode'])
        self.assertIn('ansible.builtin.copy', tasks[1])
        self.assertEqual(tasks[1]['delegate_to'], 'localhost')
        self.assertIn('ansible.builtin.command', tasks[2])
        self.assertIn('ansible.builtin.copy', tasks[3])
        self.assertIn('ansible.builtin.assert', tasks[4])

    def test_incomplete_extra_and_reordered_results(self):
        doc, results = passing_fixture()
        for invalid in [None, [], results[:-1], results + results[:1], results[::-1]]:
            self.assertEqual(MODULE.evaluate(doc, invalid)['result'], 'blocked')

    def test_execution_has_no_transport_or_cleanup_side_effects(self):
        result = subprocess.run([sys.executable, str(SCRIPTS/'run-host-convergence.py'), 'execute'], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 69)
        self.assertIn('blocked:', result.stdout)

    def test_source_snapshot_rejects_extras_symlinks_and_writable_inputs(self):
        root = Path(tempfile.mkdtemp(prefix='nautobot-convergence-source.', dir='/tmp'))
        try:
            for name in LAUNCHER.BUNDLE_FILES:
                p = root/name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes((ROOT/name).read_bytes())
                p.chmod(0o400)
            for p in [x for x in root.rglob('*') if x.is_dir()]:
                p.chmod(0o500)
            root.chmod(0o500)
            LAUNCHER.verify_snapshot(root)
            subprocess.run(['check-jsonschema', '--schemafile',
                            str(root/'Nautobot/schemas/operation.schema.json'),
                            str(root/'Nautobot/manifests/operation.yaml')],
                           check=True, capture_output=True, timeout=30)
            subprocess.run(['/bin/bash', str(root/'tests/repository/run-with-ansible-local-temp.sh'),
                            'ansible-playbook', '--syntax-check', '--inventory',
                            str(root/'inventory/prod/hosts.yaml'),
                            str(root/'Nautobot/ansible/playbooks/preflight-host-convergence.yaml')],
                           env={**os.environ, 'LC_ALL': 'C.UTF-8',
                                'ANSIBLE_CONFIG': str(root/'Nautobot/ansible/ansible.cfg')},
                           check=True, capture_output=True, timeout=30)
            candidate = root/LAUNCHER.BUNDLE_FILES[0]
            candidate.chmod(0o600)
            with self.assertRaises(ValueError):
                LAUNCHER.verify_snapshot(root)
            candidate.chmod(0o400)
            root.chmod(0o700)
            extra = root/'unexpected.cfg'
            extra.write_text('unreviewed')
            extra.chmod(0o400)
            root.chmod(0o500)
            with self.assertRaises(ValueError):
                LAUNCHER.verify_snapshot(root)
            root.chmod(0o700)
            extra.unlink()
            extra.symlink_to('/tmp')
            root.chmod(0o500)
            with self.assertRaises(ValueError):
                LAUNCHER.verify_snapshot(root)
        finally:
            root.chmod(0o700)
            for p in root.rglob('*'):
                if p.is_dir() and not p.is_symlink():
                    p.chmod(0o700)
            shutil.rmtree(root)

    def test_capture_and_cleanup(self):
        for program, timeout, limit, expected_error in [
            ('print("fixture")', 5, 1024, None),
            ('import time; print("before timeout", flush=True); time.sleep(10)', 0.1, 1024, 'timeout'),
            ('print("x" * 2000)', 5, 100, 'output_limit'),
        ]:
            with self.subTest(error=expected_error):
                root = Path(tempfile.mkdtemp(prefix=LAUNCHER.PREFIX, dir='/tmp'))
                try:
                    (root/'ansible-local').mkdir(mode=0o700)
                    status, error = LAUNCHER.capture([sys.executable, '-c', program], root, dict(os.environ), timeout, limit)
                    self.assertEqual(error, expected_error)
                    self.assertLessEqual((root/'ansible.stdout').stat().st_size, limit)
                    self.assertTrue((root/'process.json').exists())
                    self.assertTrue(LAUNCHER.cleanup_temp(root))
                    self.assertTrue((root/'ansible.stdout').exists())
                    (root/'ansible-local').symlink_to('/tmp')
                    with self.assertRaises(ValueError):
                        LAUNCHER.cleanup_temp(root)
                    (root/'ansible-local').unlink()
                finally:
                    shutil.rmtree(root)

    def test_schema_rejects_readiness_and_mutation(self):
        import jsonschema
        schema = json.loads((ROOT/'Nautobot/schemas/host-convergence.schema.json').read_text())
        jsonschema.validate(DOC, schema)
        for section, key, value in [('operation','authorization_ready',not DOC['operation']['authorization_ready']),
                                    ('preflight','execution_authorized',not DOC['preflight']['execution_authorized']),
                                    ('mutations','ordered',['install']),
                                    ('acceptance','state','accepted')]:
            changed = copy.deepcopy(DOC)
            changed[section][key] = value
            with self.assertRaises(jsonschema.ValidationError):
                jsonschema.validate(changed, schema)
        accepted = json.loads((ROOT/'Nautobot/schemas/accepted-host-baseline.schema.json').read_text())
        jsonschema.Draft202012Validator.check_schema(accepted)
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate({'schema_version':1}, accepted)

    def test_future_restore_capabilities_match_accepted_provider(self):
        schema = json.loads((ROOT/'Nautobot/schemas/operation.schema.json').read_text())
        branch = next(b for b in schema['oneOf'] if 'restic_repository' in b.get('properties', {}))
        capabilities = branch['properties']['restic_repository']['properties']['credentials']['properties']['bucket_scoped_capabilities_required']['const']
        provider = yaml.safe_load((ROOT/'backblaze-b2/manifests/accepted-live-state.yaml').read_text())
        self.assertEqual(capabilities, provider['application_key_policy']['capabilities'])

    def test_deferred_contract_is_preserved(self):
        old = subprocess.check_output(['git','show','c7bff00f5af7bb4c42a8d20dbf1d1152047d4a55:Nautobot/manifests/operation.yaml'], cwd=ROOT)
        self.assertEqual(old, (ROOT/'Nautobot/manifests/deferred-restic-initialization.yaml').read_bytes())
        self.assertFalse(DOC['deferred_contract']['active'])


if __name__ == '__main__':
    unittest.main()
