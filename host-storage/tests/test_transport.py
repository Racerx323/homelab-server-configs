import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


transport = module('transport', 'transport.py')
runner = module('runner', 'run-operation.py')
BRIDGE = '152d:0583'


class RenderTests(unittest.TestCase):
    def test_preserve_whitespace_and_newline(self):
        for suffix in (b'', b'\n', b'  \n', b'\t'):
            data = b'console=tty1  root=PARTUUID=123 rootwait' + suffix
            expected = b'console=tty1  root=PARTUUID=123 rootwait usb-storage.quirks=152d:0583:u' + suffix
            self.assertEqual(transport.render(data, BRIDGE), expected)
            self.assertEqual(transport.render(expected, BRIDGE), expected)

    def test_preserve_other_bridges_and_arguments(self):
        data = b'root=x usb-storage.quirks=1234:5678:t\tquiet\n'
        self.assertEqual(transport.render(data, BRIDGE), b'root=x usb-storage.quirks=1234:5678:t,152d:0583:u\tquiet\n')

    def test_conflicts_fail(self):
        for data in (b'', b'\n', b'root=x\nquiet\n', b'root=x\n\n', b'root=x\r\n', b'root=\x00x',
                     b'root=x usb-storage.quirks=', b'root=x usb-storage.quirks=152d:0583:t',
                     b'root=x usb-storage.quirks=152d:0583:u,152d:0583:u',
                     b'root=x usb-storage.quirks=152d:0583:u usb-storage.quirks=1234:5678:u'):
            with self.subTest(data=data), self.assertRaises(ValueError):
                transport.render(data, BRIDGE)

    def test_existing_uppercase_id_unchanged(self):
        data = b'root=x usb-storage.quirks=152D:0583:u\n'
        self.assertEqual(transport.render(data, BRIDGE), data)

    def test_other_parameter_not_mistaken_for_quirk(self):
        data = b'root=x not-usb-storage.quirks=abc'
        self.assertEqual(transport.render(data, BRIDGE), data + b' usb-storage.quirks=152d:0583:u')

    def test_unsupported_platform_stops_before_device_reads(self):
        with patch.object(transport, 'command', return_value='x86_64'):
            with self.assertRaisesRegex(ValueError, 'architecture'):
                transport.collect({'architecture': 'aarch64'})


class OperationTests(unittest.TestCase):
    def operation(self):
        return dict(id='fixture', host='j2-svpi4mf', address='127.0.0.1', user='ama',
                    backup_path='/boot/firmware/cmdline.txt.host-storage-fixture.bak',
                    expected_boot_id='', expected_root_uuid='', expected_boot_sha256='',
                    proposed_boot_sha256='', authorize_apply=False, authorize_reboot=False,
                    authorize_rollback=False, recovery_confirmed=False, expect_new_boot=False)

    def test_profile_selected_from_inventory(self):
        _, host, profile = runner.prepare(self.operation())
        self.assertEqual(host['storage']['root']['transport_profile'], profile['id'])
        self.assertEqual(profile['bridge'], BRIDGE)

    def test_unknown_fields_and_unsafe_identity_rejected(self):
        for fields in ({'host': '../../etc/passwd'}, {'address': 'host;command'}, {'user': '-oProxyCommand=x'},
                       {'authorize_apply': 'yes'}, {'extra': 1}, {'backup_path': '/etc/passwd'}):
            with self.subTest(fields=fields), self.assertRaises(Exception):
                runner.prepare(self.operation() | fields)

    def test_bundle_changes_with_authorization(self):
        operation = self.operation()
        host_path, _, _ = runner.prepare(operation)
        before, _ = runner.bundle(operation, host_path)
        after, _ = runner.bundle(operation | {'authorize_apply': True}, host_path)
        self.assertNotEqual(before, after)

    def test_mutation_requires_reviewed_digest_before_evidence_or_contact(self):
        with tempfile.TemporaryDirectory() as directory:
            operation = Path(directory) / 'operation.json'
            operation.write_text(json.dumps(self.operation()))
            with patch('sys.argv', ['runner', '--stage', 'apply', '--operation', str(operation)]):
                with self.assertRaisesRegex(ValueError, 'bundle digest'):
                    runner.main()

class TopologyTests(unittest.TestCase):
    def test_actual_ancestry_rejects_wrong_bridge_and_ambiguous_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            usb = root / 'usb'
            interface = usb / 'interface'
            disk = interface / 'scsi/block/sda'
            disk.mkdir(parents=True)
            (usb / 'idVendor').write_text('152d\n')
            (usb / 'idProduct').write_text('0583\n')
            driver = root / 'drivers/usb-storage'
            driver.mkdir(parents=True)
            (interface / 'driver').symlink_to(driver)
            self.assertEqual(transport.usb_transport(disk, BRIDGE), (BRIDGE, 'usb-storage'))
            with self.assertRaisesRegex(ValueError, 'ancestry'):
                transport.usb_transport(disk, '152d:0580')
            other = root / 'drivers/uas'
            other.mkdir()
            (usb / 'driver').symlink_to(other)
            with self.assertRaisesRegex(ValueError, 'ancestry'):
                transport.usb_transport(disk, BRIDGE)


if __name__ == '__main__':
    unittest.main()
