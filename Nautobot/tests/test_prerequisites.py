#!/usr/bin/env python3
"""Real guards and Ansible task flow with disposable package-manager fixtures.

No package installation, host contact or native ARM64 acceptance.
"""
import importlib.util
from importlib.machinery import ModuleSpec
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import prerequisite_node as node

spec = importlib.util.spec_from_file_location('prerequisite_bundle', SCRIPTS / 'prerequisite-bundle.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


def fixture_repository(root):
    """Use current inputs with synthetic operation data, independent of archives."""
    for name, source in bundle.FILES.items():
        if name in ('operation.yaml', 'qualification.json'):
            continue
        target = root / source
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source, target)
    schema = json.loads((root / bundle.FILES['schema.json']).read_text())['properties']
    candidate = yaml.safe_load((root / bundle.FILES['recurring-protection.yaml']).read_text())
    accepted = yaml.safe_load((root / bundle.FILES['accepted-state.yaml']).read_text())
    packages = [dict(p, architecture='all', source='debian')
                for p in candidate['dependency_transaction_lock']['new_packages']]
    doppler = candidate['prerequisite_preparation']['packages']['doppler']
    packages.append(dict({key: doppler[key] for key in ('name', 'version', 'sha256', 'url')},
                         architecture='arm64', source='doppler'))
    sources = {}
    for name, definition in schema['sources']['properties'].items():
        props = definition['properties']
        sources[name] = {key: value['const'] for key, value in props.items() if key != 'sha256'}
        sources[name]['sha256'] = {key: '0' * 64 for key in props['sha256']['required']}
    op = {
        'schema_version': 1,
        'operation': {'id': 'disposable-fixture', 'stage': 'recurring_prerequisite_installation',
                      'state': 'pending', 'authorization_ready': False, 'execution_enabled': False,
                      'source_commit': '0' * 40},
        'target': schema['target']['const'],
        'plan_sha256': bundle.sha(root / bundle.FILES['PLAN.md']),
        'baseline': {'collected_at': '2000-01-01T00:00:00+00:00', 'packages_sha256': '0' * 64,
                     'artifact_sha256': accepted['application_startup']['artifact_sha256'],
                     'raw_sha256': {'fixture': '0' * 64}, 'foreign_architectures': [],
                     'mapped_media': {path: {'exists': True, 'uid': 123, 'gid': 123,
                                             'mode': '0700', 'symlink': False}
                                      for path in schema['baseline']['properties']['mapped_media']['required']}},
        'sources': sources, 'packages': packages, 'minimum_free_bytes': 16 * 1024**3,
        'mutation_boundary': {'packages': 'fixture pins only',
                              'directories': schema['mutation_boundary']['properties']['directories']['const'],
                              'directory_owner': '999:985', 'directory_mode': '0700',
                              'temporary_stage': '/tmp/disposable-fixture', 'side_effects': 'fixture only',
                              'credentials': False, 'units_or_timers': False},
        'command_template': 'fixture only',
    }
    for key in ('acceptance', 'rollback', 'external_inputs', 'unresolved_prerequisites', 'later_stages'):
        op[key] = ['fixture only']
    (root / bundle.FILES['operation.yaml']).write_text(yaml.safe_dump(op))
    (root / bundle.FILES['qualification.json']).write_text('{}\n')
    return op


class Guards(unittest.TestCase):
    def test_single_candidate_preserves_disabled_repository_definition(self):
        class SourceFixture:
            def create_module(self, spec):
                return None
            def exec_module(self, module):
                module.verify_sources = lambda root, operation: None
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repository = root / 'repository'
            op = fixture_repository(repository)
            source = repository / bundle.FILES['operation.yaml']
            original = source.read_bytes()
            self.assertFalse(op['operation']['execution_enabled'])
            inputs = root / 'inputs'
            inputs.mkdir()
            for filename in bundle.external_names(op):
                (inputs / filename).write_text('disposable source fixture')
            destination = root / 'candidate'
            with patch.object(bundle.importlib.util, 'spec_from_file_location',
                              return_value=ModuleSpec('source_fixture', SourceFixture())), \
                    patch.object(bundle, 'ROOT', repository), patch('builtins.print'):
                bundle.freeze(destination, inputs)
            digest = bundle.sha(destination / 'bundle.json')
            manifest, frozen = bundle.verify(destination, digest)
            self.assertTrue(frozen['operation']['execution_enabled'])
            self.assertTrue(frozen['operation']['authorization_ready'])
            self.assertEqual(source.read_bytes(), original)
            self.assertFalse((destination / '__pycache__').exists())
            self.assertEqual(len(bundle.target_names(frozen)), 12)
            self.assertLess(bundle.target_names(frozen), set(manifest['files']))
            self.assertFalse(bundle.target_names(frozen) & {'PLAN.md', 'OPERATIONS.md', 'debian.Packages'})
            (destination / 'operation.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'input_identity'):
                bundle.verify(destination, digest)

    def test_neutral_operation_refuses_freeze_before_creating_candidate(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            operation = root / bundle.FILES['operation.yaml']
            operation.parent.mkdir(parents=True)
            operation.write_text('schema_version: 1\noperation: {state: clean, authorization_ready: false}\n')
            destination = root / 'candidate'
            with patch.object(bundle, 'ROOT', root), self.assertRaisesRegex(ValueError, 'operation_stage'):
                bundle.freeze(destination, root / 'absent-inputs')
            self.assertFalse(destination.exists())

    def test_failed_command_keeps_bounded_sanitized_diagnostics(self):
        with self.assertRaises(node.CommandFailure) as caught:
            node.command(['/usr/bin/python3', '-c',
                          "import sys;print('solver refused');sys.stderr.write('bad\\x1b' + 'x'*20000);sys.exit(100)"])
        details = caught.exception.details
        self.assertEqual(details['exit_status'], 100)
        self.assertIn('solver refused', details['stdout'])
        self.assertLessEqual(len(details['stderr']), 16384)
        self.assertNotIn('\x1b', details['stderr'])
        self.assertNotIn('argv', details)

    def test_capture_does_not_limit_command_files(self):
        self.assertEqual(node.command(['/usr/bin/python3', '-c',
                         "import sys,tempfile; f=tempfile.TemporaryFile(); "
                         "f.write(b'x'*(8*1024**2)); print(f.tell()); print(sys.stdin.read())"],
                         data='wrapper input'), '8388608\nwrapper input\n')

    def test_output_overflow_and_timeout_are_bounded(self):
        for stream in ('stdout', 'stderr'):
            with self.subTest(stream=stream), self.assertRaises(node.CommandFailure) as caught:
                node.command(['/usr/bin/python3', '-c',
                              f"import sys; sys.{stream}.write('x'*(5*1024**2))"])
            self.assertTrue(caught.exception.details['output_limited'])
            self.assertLessEqual(len(caught.exception.details[stream]), 16384)
        with self.assertRaises(node.CommandFailure) as caught:
            node.command(['/usr/bin/python3', '-c', 'import time; time.sleep(10)'], timeout=0.1)
        self.assertTrue(caught.exception.details['timed_out'])

    def test_native_apt_mark_with_cold_private_cache(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            argv = ['/usr/bin/apt-mark', '-o', 'Dir::Cache::pkgcache=' + str(root / 'pkgcache.bin'),
                    '-o', 'Dir::Cache::srcpkgcache=' + str(root / 'srcpkgcache.bin'), 'showmanual']
            result = node.command(argv)
            self.assertEqual(set(result.splitlines()),
                             set(subprocess.check_output(['/usr/bin/apt-mark', 'showmanual'], text=True).splitlines()))
            self.assertGreater((root / 'pkgcache.bin').stat().st_size, 4 * 1024**2)

    def test_real_preflight_absent_present_partial_and_unrelated_drift(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            old = {'existing': ['1', 'arm64', 'installed']}
            pins = [{'name': 'one', 'version': '1', 'architecture': 'all'},
                    {'name': 'two', 'version': '2', 'architecture': 'all'}]
            op = {'packages': pins, 'minimum_free_bytes': 1,
                  'baseline': {'packages_sha256': node.package_digest(old, ['one', 'two']), 'foreign_architectures': ['armhf']}}
            events = []
            def command(argv, timeout=90):
                events.append(argv)
                if argv[:2] == ['/usr/bin/dpkg', '--print-architecture']:
                    return 'arm64'
                if argv[:2] == ['/usr/bin/dpkg', '--print-foreign-architectures']:
                    return 'armhf\n'
                if argv[0] == '/usr/bin/findmnt':
                    return 'ext4'
                if argv[0] == '/usr/bin/apt-get':
                    self.assertIn('--simulate', argv)
                    return 'Inst one (1 fixture [all])\nInst two (2 fixture [all])'
                return ''
            account = SimpleNamespace(pw_uid=999, pw_gid=985, pw_dir='/var/lib/nautobot')
            installed = {p['name']: [p['version'], p['architecture'], 'installed'] for p in pins}
            for rows, error in [(old, None), ({**old, **installed}, None),
                                ({**old, 'one': installed['one']}, 'partial_install'),
                                ({'existing': ['2', 'arm64', 'installed']}, 'unrelated_package_drift')]:
                (root / 'before.json').unlink(missing_ok=True)
                with patch.object(node.pwd, 'getpwnam', return_value=account), \
                        patch.object(node, 'verify_sources'), patch.object(node, 'packages', return_value=rows), \
                        patch.object(node, 'directory'), patch.object(node, 'DIRECTORIES', (str(root / 'new'),)), \
                        patch.object(node, 'continuity', return_value={}), \
                        patch.object(node.shutil, 'disk_usage', return_value=SimpleNamespace(free=2)), \
                        patch.object(node, 'command', side_effect=command):
                    if error:
                        with self.assertRaisesRegex(ValueError, error):
                            node.preflight(root, op)
                        self.assertFalse((root / 'before.json').exists())
                    else:
                        result = node.preflight(root, op)
                        self.assertEqual(result['missing'], ['one', 'two'] if rows == old else [])
                        self.assertFalse((root / 'new').exists())

    def test_exact_transaction_refuses_upgrade_removal_extra_or_missing(self):
        node.transaction('Inst demo (1 local-deb [all])\nConf demo (1 local-deb [all])', {'demo': '1'})
        for raw in ('Inst demo [0] (1 local-deb [all])', 'Remv other [1]',
                    'Inst extra (1 local-deb [all])', ''):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                node.transaction(raw, {'demo': '1'})
        node.transaction('Purg demo [1]', {'demo': '1'}, 'Purg')
        with self.assertRaises(ValueError):
            node.transaction('Purg demo [1]\nPurg other [1]', {'demo': '1'}, 'Purg')

    def test_simulation_and_install_share_local_only_acquisition(self):
        root = Path('/tmp/reviewed-stage')
        simulation = node.apt_install(root, {'demo': '1'}, simulate=True)
        installation = node.apt_install(root, {'demo': '1'})
        self.assertEqual(simulation[2:], installation[2:])
        self.assertNotIn('--no-download', simulation)
        options = [simulation[i + 1] for i, value in enumerate(simulation) if value == '-o']
        self.assertIn('Dir::Etc::sourcelist=', options)
        self.assertIn('Dir::Etc::sourceparts=', options)
        self.assertEqual(simulation[-1], str(root / 'demo.deb'))

    def test_package_digest_tracks_unrelated_dependency_drift(self):
        rows = {'existing': ['1', 'arm64', 'installed']}
        value = node.package_digest(rows, ['new'])
        self.assertEqual(value, node.package_digest({**rows, 'new': ['1', 'all', 'installed']}, ['new']))
        self.assertNotEqual(value, node.package_digest({'existing': ['2', 'arm64', 'installed']}, ['new']))

    def test_paths_refuse_symlinks_permissions_and_nonempty_rollback(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            path = root / 'protection'
            path.mkdir(mode=0o700)
            node.directory(path, os.getuid(), os.getgid())
            path.chmod(0o755)
            with self.assertRaises(ValueError):
                node.directory(path, os.getuid(), os.getgid())
            link = root / 'link'
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                node.safe_path(link / 'child')
            path.chmod(0o700)
            (path / 'retained').write_text('keep')
            node.save(root, 'before.json', {'created_directories': [str(path)], 'packages': {}, 'manual': '', 'services': {}})
            original = node.directory
            with patch.object(node, 'directory', side_effect=lambda p: original(p, os.getuid(), os.getgid())):
                with self.assertRaises(OSError):
                    node.rollback_directories(root, {})
            self.assertEqual((path / 'retained').read_text(), 'keep')

    def test_rollback_refuses_unrelated_drift(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            node.save(root, 'before.json', {'packages': {'old': ['1', 'all', 'installed']}})
            with patch.object(node, 'packages', return_value={'old': ['2', 'all', 'installed']}):
                with self.assertRaisesRegex(ValueError, 'unrelated_drift'):
                    node.rollback_plan(root, {'packages': []})

    def test_pending_schema_bindings_and_disabled_execution(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repository = root / 'repository'
            op = fixture_repository(repository)
            Draft202012Validator(json.loads((ROOT / 'Nautobot/schemas/recurring-prerequisites.schema.json').read_text())).validate(op)
            for dest, source in bundle.FILES.items():
                shutil.copyfile(repository / source, root / dest)
            bundle.validate(root, op)
            op['packages'][0]['version'] = 'unreviewed'
            with self.assertRaises(ValueError):
                bundle.validate(root, op)
        with patch.object(bundle, 'verify', return_value=({}, {'operation': {'execution_enabled': False}})), \
                patch.object(bundle.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'execution_disabled'):
                bundle.execute(Path('/unused'), 'unused', Path('/unused'))
            run.assert_not_called()

    def test_signed_chain_real_gpg_and_deb_control_refuses_tampering(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            home = root / 'gpg'
            home.mkdir(mode=0o700)
            def run(argv):
                result = subprocess.run(argv, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                return result.stdout
            gpg = ['/usr/bin/gpg', '--homedir', str(home), '--batch', '--pinentry-mode', 'loopback', '--passphrase', '']
            run(gpg + ['--quick-gen-key', 'Disposable fixture <fixture@invalid>', 'ed25519', 'sign', '0'])
            keys = run(gpg + ['--with-colons', '--list-keys']).decode()
            fingerprint = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
            (root / 'fixture.gpg').write_bytes(run(gpg + ['--export']))
            control = root / 'package/DEBIAN'
            control.mkdir(parents=True)
            control.chmod(0o755)
            (control / 'control').write_text('Package: demo\nVersion: 1\nArchitecture: all\nMaintainer: Fixture <fixture@invalid>\nDescription: disposable, never installed\n')
            run(['/usr/bin/dpkg-deb', '--build', str(root / 'package'), str(root / 'demo.deb')])
            package = {'name': 'demo', 'version': '1', 'architecture': 'all', 'source': 'fixture', 'sha256': node.sha(root / 'demo.deb')}
            (root / 'Packages').write_text('Package: demo\nVersion: 1\nArchitecture: all\nSHA256: ' + package['sha256'] + '\n')
            (root / 'Release').write_text('SHA256:\n ' + node.sha(root / 'Packages') + ' ' + str((root / 'Packages').stat().st_size) + ' main/binary-arm64/Packages\n')
            run(gpg + ['--clearsign', '--output', str(root / 'InRelease'), str(root / 'Release')])
            run(['/usr/bin/gpgconf', '--homedir', str(home), '--kill', 'gpg-agent'])
            source = {'keyring': 'fixture.gpg', 'release': 'InRelease', 'index': 'Packages',
                      'fingerprint': fingerprint, 'index_path': 'main/binary-arm64/Packages',
                      'sha256': {n: node.sha(root / n) for n in ('fixture.gpg', 'InRelease', 'Packages')}}
            op = {'sources': {'fixture': source}, 'packages': [package]}
            node.verify_sources(root, op)
            source['fingerprint'] = '0' * 40
            with self.assertRaisesRegex(ValueError, 'signer_identity'):
                node.verify_sources(root, op)
            source['fingerprint'] = fingerprint
            with (root / 'demo.deb').open('ab') as stream:
                stream.write(b'tamper')
            with self.assertRaisesRegex(ValueError, 'package_hash'):
                node.verify_sources(root, op)
            (root / 'Packages').write_text('substituted index')
            with self.assertRaisesRegex(ValueError, 'source_hash'):
                node.verify_sources(root, op)
            source['sha256']['Packages'] = node.sha(root / 'Packages')
            with self.assertRaisesRegex(ValueError, 'signed_index_identity'):
                node.verify_sources(root, op)


class FullPlaybook(unittest.TestCase):
    @unittest.skipUnless(os.geteuid() == 0, 'run in a disposable rootless user namespace')
    def test_real_staging_apt_preflight_failure_and_receipt_collection(self):
        """Run the production playbook; real APT may simulate but never install."""
        with tempfile.TemporaryDirectory(prefix='nautobot-prerequisite-full.') as name:
            root = Path(name)
            inputs = root / 'inputs'
            inputs.mkdir()
            stage = root / 'stage'
            evidence = root / 'receipts'
            evidence.mkdir(mode=0o700)
            status = root / 'dpkg-status'
            status.write_text('')
            (root / 'lists').mkdir()
            control = root / 'package/DEBIAN'
            control.mkdir(parents=True)
            control.chmod(0o755)
            (control / 'control').write_text(
                'Package: nautobot-prerequisite-fixture\nVersion: 1\nArchitecture: all\n'
                'Maintainer: Fixture <fixture@invalid>\nDescription: simulation only\n'
                'Depends: nautobot-prerequisite-nonexistent-dependency\n')
            deb = inputs / 'nautobot-prerequisite-fixture.deb'
            subprocess.run(['/usr/bin/dpkg-deb', '--build', '--root-owner-group',
                            str(root / 'package'), str(deb)], check=True, capture_output=True)
            directories = [str(root / 'protection'), str(root / 'protection/staging')]
            op = {'operation': {'stage': 'recurring_prerequisite_installation', 'execution_enabled': True},
                  'packages': [{'name': 'nautobot-prerequisite-fixture', 'version': '1', 'architecture': 'all'}],
                  'baseline': {'packages_sha256': node.package_digest({}, []), 'foreign_architectures': []},
                  'minimum_free_bytes': 1}
            (inputs / 'operation.json').write_text(json.dumps(op))
            shutil.copyfile(ROOT / 'tests/repository/run-with-ansible-local-temp.sh', inputs / 'ansible-temp.sh')
            # Only host identity/state probes are fixtures. Production main(),
            # stage guards, preflight, command capture and APT simulation run.
            (inputs / 'prerequisite_node.py').write_text('''import sys
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, ''' + repr(str(SCRIPTS)) + ''')
import prerequisite_node as n
n.socket.gethostname=lambda:'j2-svpi4mf'
n.pwd.getpwnam=lambda name:SimpleNamespace(pw_uid=999,pw_gid=985,pw_dir='/var/lib/nautobot')
n.packages=lambda:{}
n.continuity=lambda op:{}
n.shutil.disk_usage=lambda path:SimpleNamespace(free=2)
n.DIRECTORIES=''' + repr(tuple(directories)) + '''
directory=n.directory
n.directory=lambda path,*args:None if str(path)=='/var/lib/nautobot' else directory(path,*args)
command=n.command
def run(argv,timeout=90,data=None):
 if argv[0]=='/usr/bin/apt-get':
  assert '--simulate' in argv, 'real package mutation forbidden in fixture'
  options=['-o','Dir::State::status=''' + str(status) + '''','-o','Dir::State::lists=''' + str(root / 'lists') + '''']
  return command([argv[0],*options,*argv[1:]],timeout,data)
 if argv[:2]==['/usr/bin/dpkg','--print-architecture']:return 'arm64'
 if argv[0]=='/usr/bin/findmnt':return 'ext4'
 if argv[0]=='/usr/bin/apt-mark':
  return command([argv[0],'-o','Dir::Cache::pkgcache=''' + str(root / 'pkgcache.bin') + '''',
                  '-o','Dir::Cache::srcpkgcache=''' + str(root / 'srcpkgcache.bin') + '''',*argv[1:]],timeout,data)
 if argv[0]=='/usr/bin/dpkg':return ''
 raise RuntimeError('unexpected fixture command')
n.command=run
n.main()
''')
            for path in inputs.iterdir():
                path.chmod(0o600)
            hashes = {path.name: node.sha(path) for path in inputs.iterdir()}
            values = {'prerequisite_verified': True, 'prerequisite_operation': op,
                      'prerequisite_bundle': str(inputs), 'prerequisite_root': str(stage),
                      'prerequisite_hashes': hashes, 'prerequisite_evidence': str(evidence)}
            variables = root / 'inputs.json'
            variables.write_text(json.dumps(values))
            inventory = root / 'inventory.ini'
            inventory.write_text('[inventory_automation]\nj2-svpi4mf ansible_connection=local ansible_become=false ansible_python_interpreter=/usr/bin/python3\n')
            result = subprocess.run(['/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
                                     shutil.which('ansible-playbook'), '-i', str(inventory),
                                     str(ROOT / 'Nautobot/ansible/playbooks/install-recurring-prerequisites.yaml'),
                                     '-e', '@' + str(variables)], capture_output=True, text=True, timeout=120,
                                    env={**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'Nautobot/ansible/ansible.cfg')})
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((evidence / 'before.json').exists(), result.stdout + result.stderr)
            failure = json.loads((evidence / 'failure-preflight.json').read_text())
            self.assertEqual(failure['command']['executable'], 'apt-get')
            self.assertEqual(failure['command']['exit_status'], 100)
            self.assertIn('nautobot-prerequisite-nonexistent-dependency',
                          failure['command']['stdout'] + failure['command']['stderr'])
            self.assertFalse(Path(directories[0]).exists())
            self.assertFalse((evidence / 'rollback.json').exists())
            self.assertEqual({p.name for p in stage.iterdir()},
                             set(hashes) | {'archives', 'before.json', 'failure-preflight.json'})


class AnsibleFlow(unittest.TestCase):
    def test_real_convergence_idempotence_partial_failure_and_reverse_rollback(self):
        # Run the exact production task include. Only the external package manager,
        # service manager and command versions are disposable fixtures.
        with tempfile.TemporaryDirectory(prefix='nautobot-prerequisite-test.') as name:
            root = Path(name)
            driver = root / 'prerequisite_node.py'
            driver.write_text('''import sys,json,os
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, ''' + repr(str(SCRIPTS)) + ''')
import prerequisite_node as n
root=Path(sys.argv[2]);phase=sys.argv[1]
state=root/'fixture-packages.json';rows=json.loads(state.read_text())
op=json.loads((root/'operation.json').read_text())
if phase.startswith('install'):
 state.write_text(json.dumps({'demo':['1','all','installed']}))
 sys.exit(7 if phase=='install-fail' else 0)
if phase=='purge':state.write_text('{}');sys.exit(0)
def command(argv,timeout=90,data=None):
 if argv[:2]==['/usr/bin/dpkg','--audit']:return ''
 if argv[:2]==['/usr/bin/apt-mark','showmanual']:return 'demo\\n' if rows else ''
 if argv[0]=='/usr/bin/apt-get':return 'Purg demo [1]'
 if '/usr/bin/ansible-playbook' in argv:return 'ansible-playbook [core 2.19.11]'
 if '/usr/bin/doppler' in argv:return 'v3.76.6'
 if argv[0]=='/usr/bin/findmnt':return 'ext4'
 raise RuntimeError('unexpected fixture command')
directory=n.directory
with patch.object(n,'packages',return_value=rows),patch.object(n,'command',side_effect=command),patch.object(n,'continuity',return_value={}),patch.object(n,'DIRECTORIES',tuple(op['mutation_boundary']['directories'])),patch.object(n,'directory',side_effect=lambda p:directory(p,os.getuid(),os.getgid())):
 if phase=='accept':
  if (root/'reject-acceptance').exists():raise ValueError('fixture acceptance failure')
  n.accept(root,op);result={}
 elif phase=='rollback-plan':
  n.rollback_plan(root,op);result={'argv':['/usr/bin/python3',str(Path(__file__)), 'purge',str(root)] if rows else []}
 elif phase=='rollback-directories':n.rollback_directories(root,op);result={}
 else:raise ValueError('unexpected phase')
 print(json.dumps(result))
''')
            directories = [str(root / 'protection'), str(root / 'protection/staging')]
            op = {'target': {'uid': os.getuid(), 'gid': os.getgid()},
                  'mutation_boundary': {'directories': directories},
                  'minimum_free_bytes': 1, 'packages': [{'name': 'demo', 'version': '1', 'architecture': 'all'}]}
            (root / 'operation.json').write_text(json.dumps(op))
            (root / 'ansible-temp.sh').write_text((ROOT / 'tests/repository/run-with-ansible-local-temp.sh').read_text())
            state = root / 'fixture-packages.json'
            state.write_text('{}')
            before = {'packages': {}, 'manual': '', 'services': {}, 'created_directories': directories}
            play = root / 'play.yaml'
            play.write_text(yaml.safe_dump([{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                'tasks': [{'ansible.builtin.include_tasks': str(ROOT / 'Nautobot/ansible/tasks/install-recurring-prerequisites.yaml')}]}]))
            ansible = shutil.which('ansible-playbook')
            self.assertIsNotNone(ansible, 'Ansible is required; do not silently skip qualification')
            def apply(phase, missing):
                values = {'prerequisite_root': str(root), 'prerequisite_operation': op,
                          'prerequisite_plan': {'stdout': json.dumps({'missing': missing,
                              'install_argv': ['/usr/bin/python3', str(driver), phase, str(root)]})}}
                inputs = root / 'inputs.json'
                inputs.write_text(json.dumps(values))
                return subprocess.run(['/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
                                       ansible, '-i', 'localhost,', str(play), '-e', '@' + str(inputs)],
                                      capture_output=True, text=True, timeout=90,
                                      env={**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'Nautobot/ansible/ansible.cfg')})
            node.save(root, 'before.json', before)
            first = apply('install', ['demo'])
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            (root / 'postconditions.json').unlink()
            (root / 'before.json').unlink()
            node.save(root, 'before.json', {**before, 'packages': json.loads(state.read_text()), 'manual': 'demo\n', 'created_directories': []})
            second = apply('install', [])
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertRegex(second.stdout, r'changed=0\s')
            for name in reversed(directories):
                Path(name).rmdir()
            for scenario in ('install-fail', 'accept-fail'):
                state.write_text('{}')
                for filename in ('before.json', 'rollback.json', 'postconditions.json'):
                    (root / filename).unlink(missing_ok=True)
                node.save(root, 'before.json', before)
                if scenario == 'accept-fail':
                    (root / 'reject-acceptance').touch()
                failed = apply('install-fail' if scenario == 'install-fail' else 'install', ['demo'])
                self.assertNotEqual(failed.returncode, 0)
                self.assertEqual(json.loads(state.read_text()), {})
                self.assertTrue(json.loads((root / 'rollback.json').read_text())['restored'], failed.stdout + failed.stderr)
                self.assertFalse(Path(directories[0]).exists())


if __name__ == '__main__':
    unittest.main()
