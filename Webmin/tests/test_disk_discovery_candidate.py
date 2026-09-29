"""Run actual baseline/patched Perl functions against synthetic kernel trees.

Literal path redirection is confined to the test loader; deployment bytes are
hash-checked separately. Fake partition tools consume canned output, never disks.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

WEBMIN = Path(__file__).resolve().parents[1]
FIXTURES = WEBMIN / 'tests/fixtures/disk-discovery'
BASELINE = FIXTURES / 'baseline'


class DiskDiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.staging = tempfile.TemporaryDirectory()
        cls.candidate = Path(cls.staging.name) / 'candidate'
        shutil.copytree(BASELINE, cls.candidate)
        spec = json.loads((WEBMIN / 'patches/disk-only-discovery.json').read_text())
        patch = WEBMIN / 'patches/disk-only-discovery.patch'
        assert hashlib.sha256(patch.read_bytes()).hexdigest() == spec['patch_sha256']
        for name, hashes in spec['files'].items():
            assert hashlib.sha256((BASELINE / name).read_bytes()).hexdigest() == hashes['before']
        subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '-d', str(cls.candidate), '-i', str(patch)], check=True, capture_output=True)
        for name, hashes in spec['files'].items():
            assert hashlib.sha256((cls.candidate / name).read_bytes()).hexdigest() == hashes['after']

    @classmethod
    def tearDownClass(cls):
        cls.staging.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('proc/partitions', 'major minor  #blocks  name\n 8 0 100 sda\n 8 1 90 sda1\n')
        self.write('proc/scsi/scsi', 'Attached devices:\n')
        self.disk('sda', 'Example', 'USB NVMe')
        self.disk('sdb', 'ATA', 'second')
        (self.root / 'dev/disk/by-id').mkdir(parents=True)
        (self.root / 'dev/disk/by-id/old').symlink_to('../../sda')
        self.write('tool-output', '')
        self.write('bin/parted', '#!' + sys.executable + '\nfrom pathlib import Path\nimport os\nr=Path(os.environ["FIXTURE_ROOT"])\nwith (r/"calls").open("a") as f: f.write("query\\n")\nprint((r/"tool-output").read_text())\n')
        (self.root / 'bin/parted').chmod(0o755)
        shutil.copy2(self.root / 'bin/parted', self.root / 'bin/fdisk')

    def write(self, name, text):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def disk(self, name, vendor, model):
        self.write('dev/' + name, '')
        self.write(f'sys/block/{name}/device/vendor', vendor + '\n')
        self.write(f'sys/block/{name}/device/model', model + '\n')
        (self.root / f'sys/class/block/{name}').mkdir(parents=True, exist_ok=True)

    def run_library(self, scenario='disk', baseline=False):
        source = (BASELINE if baseline else self.candidate) / 'fdisk/fdisk-lib.pl'
        env = dict(os.environ, PATH=str(self.root / 'bin') + ':' + os.environ['PATH'], FIXTURE_ROOT=str(self.root))
        p = subprocess.run(['perl', str(FIXTURES / 'driver.pl'), str(source), str(self.root), scenario], env=env, text=True, capture_output=True, timeout=15)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stderr, '')
        return json.loads(p.stdout)

    def parted_output(self, table='gpt'):
        partition = ' 1 1cyl 9cyl 8cyl ext4 name' if table == 'gpt' else ' 1 1cyl 9cyl 8cyl primary ext4'
        self.write('tool-output', f'Disk {self.root}/dev/sda: 10cyl\nBIOS cylinder,head,sector geometry: 10,4,8. Each cylinder is 16384b.\nPartition Table: {table}\n{partition}\n')

    def test_disk_only_no_partition_queries_or_cache(self):
        r = self.run_library()
        self.assertIsNone(r['error'])
        d = r['results'][0][0]
        self.assertEqual(d['model'], 'Example USB NVMe')
        self.assertNotIn('parts', d)
        self.assertNotIn('table', d)
        self.assertNotIn('size', d)
        self.assertEqual(r['cache'], [])
        self.assertFalse((self.root / 'calls').exists())

    def test_full_gpt_mbr_and_extended_match_baseline(self):
        for table in ['gpt', 'msdos']:
            with self.subTest(table=table):
                self.parted_output(table)
                if table == 'msdos':
                    with (self.root / 'tool-output').open('a') as f:
                        f.write(' 2 9cyl 10cyl 1cyl extended\n')
                original = self.run_library('full', True)
                changed = self.run_library('full')
                self.assertEqual(changed, original)
                self.assertEqual(changed['results'][0][0]['table'], table)
                self.assertTrue(changed['results'][0][0]['parts'])

    def test_full_fdisk_matches_baseline(self):
        self.write('tool-output', f'Disk {self.root}/dev/sda: 1 GiB, 1073741824 bytes, 2097152 sectors\nGeometry: 4 heads, 8 sectors/track, 10 cylinders\nUnits = cylinders of 32 * 512\nDisklabel type: gpt\n{self.root}/dev/sda1 1 9 9 4K Linux filesystem\n')
        self.assertEqual(self.run_library('full_fdisk'), self.run_library('full_fdisk', True))

    def test_cache_isolation_both_orders(self):
        self.parted_output()
        for scenario in ['disk_full', 'full_disk']:
            r = self.run_library(scenario)
            self.assertIsNone(r['error'])
            disk, full = r['results'] if scenario == 'disk_full' else reversed(r['results'])
            self.assertNotIn('parts', disk[0])
            self.assertTrue(full[0]['parts'])
            self.assertEqual(r['cache'], full)

    def test_replacement_refreshes_model_and_ids(self):
        r = self.run_library('refresh')
        a, b = [x[0] for x in r['results']]
        self.assertEqual(a['model'], 'Example USB NVMe')
        self.assertEqual(b['model'], 'Example Replacement')
        self.assertEqual(a['ids'], ['old'])
        self.assertEqual(b['ids'], ['new'])

    def test_add_remove_refreshes_inventory(self):
        r = self.run_library('remove_add')
        self.assertIsNone(r['error'])
        self.assertEqual([[Path(d['device']).name for d in v] for v in r['results']], [['sda'], ['sdb']])

    def test_disappearance_during_scan_fails(self):
        self.assertIn('Missing device', self.run_library('race')['error'])

    def test_missing_inventory_and_model_fail(self):
        (self.root / 'sys/block/sda/device/model').unlink()
        (self.root / 'sys/block/sda/device/vendor').unlink()
        self.assertIn('Missing disk model', self.run_library()['error'])
        (self.root / 'proc/partitions').unlink()
        self.assertIn('Cannot read disk inventory', self.run_library()['error'])

    def test_multi_drive_and_namespace_classification(self):
        names = ['sda', 'sdaa', 'nvme0n1', 'nvme0n2', 'mmcblk0', 'xvda', 'vda', 'hda']
        self.write('proc/partitions', 'major minor  #blocks  name\n' + ''.join(f'8 {i} 100 {n}\n' for i, n in enumerate(names)))
        self.write('proc/ide/hda/media', 'disk\n')
        self.write('proc/ide/hda/model', 'IDE fixture\n')
        for n in names:
            self.disk(n, 'Example', 'disk')
        r = self.run_library()
        self.assertIsNone(r['error'])
        self.assertEqual({Path(d['device']).name for d in r['results'][0]}, set(names))
        self.assertEqual({Path(d['device']).name: d['type'] for d in r['results'][0]}['vda'], 'virtio')
        self.assertFalse((self.root / 'calls').exists())

    def test_unpartitioned_and_delayed_id_links(self):
        (self.root / 'dev/disk/by-id/old').unlink()
        r = self.run_library()
        self.assertIsNone(r['error'])
        self.assertEqual(len(r['results'][0]), 1)
        self.assertIsNone(r['results'][0][0]['ids'])

    def test_smart_raid_and_scheduled_caller_contracts(self):
        p = subprocess.run(['perl', str(FIXTURES / 'smart-driver.pl'),
                            str(self.candidate / 'smart-status/smart-status-lib.pl'),
                            str(self.candidate / 'system-status/system-status-lib.pl')],
                           capture_output=True, text=True, timeout=15)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(p.stderr, '')
        self.assertIn('scheduled health retains passthrough', p.stdout)

    def test_health_query_implementation_is_unchanged(self):
        import re
        for name in ['get_drive_status', 'get_extra_args']:
            pattern = r'^sub ' + name + r'\n\{.*?^\}'
            before = re.search(pattern, (BASELINE / 'smart-status/smart-status-lib.pl').read_text(), re.M | re.S)
            after = re.search(pattern, (self.candidate / 'smart-status/smart-status-lib.pl').read_text(), re.M | re.S)
            self.assertEqual(before[0], after[0])

    def test_preparer_hash_gates_and_reproducible_bundle(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('prepare_discovery', WEBMIN / 'scripts/prepare-disk-discovery-candidate.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        a, sha_a = module.prepare(BASELINE, self.root / 'stage-a')
        b, sha_b = module.prepare(BASELINE, self.root / 'stage-b')
        self.assertEqual(sha_a, sha_b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
        with self.assertRaises(FileExistsError):
            module.prepare(BASELINE, self.root / 'stage-a')
        bad = self.root / 'bad'
        shutil.copytree(BASELINE, bad)
        (bad / 'fdisk/fdisk-lib.pl').write_text('drift')
        with self.assertRaisesRegex(ValueError, 'Baseline mismatch'):
            module.prepare(bad, self.root / 'rejected')
        self.assertFalse((self.root / 'rejected').exists())

    def test_legacy_controller_metadata_and_scsi_fallback(self):
        names = ['cciss/c0d0', 'rd/c0d0', 'ida/c0d0']
        self.write('proc/partitions', 'major minor  #blocks  name\n' + ''.join(f'8 {i} 100 {n}\n' for i, n in enumerate(names)))
        for n in names:
            self.write('dev/' + n, '')
        self.write('proc/driver/cciss/cciss0', 'cciss0: Smart Array\n')
        self.write('proc/rd/c0/current_status', 'Configuring Mylex\n')
        self.write('proc/driver/cpqarray/ida0', 'ida0: Compaq\n')
        r = self.run_library()
        self.assertIsNone(r['error'])
        self.assertEqual([d['model'] for d in r['results'][0]], ['Smart Array', 'Mylex', 'Compaq'])
        self.assertTrue(all(d['type'] == 'raid' for d in r['results'][0]))
        self.write('proc/partitions', 'major minor  #blocks  name\n 8 0 100 sda\n')
        shutil.rmtree(self.root / 'sys/block/sda/device')
        self.write('proc/scsi/scsi', 'Attached devices:\nHost: scsi0 Channel: 00 Id: 00 Lun: 00\n  Vendor: LSI Model: RAID fixture Rev: 1\n  Type: Direct-Access\n')
        r = self.run_library()
        self.assertIsNone(r['error'])
        self.assertIn('LSI', r['results'][0][0]['model'])
