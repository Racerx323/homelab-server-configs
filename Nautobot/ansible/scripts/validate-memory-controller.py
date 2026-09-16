#!/usr/bin/env python3
"""Offline boot-renderer fixtures; no host, service or boot mutation."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('planner', Path(__file__).with_name('plan-memory-controller.py'))
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)
BASE = b'usb-storage.quirks=152d:0583:u  root=PARTUUID=fixture\trootwait'


class Rendering(unittest.TestCase):
    def test_preserves_all_original_bytes_and_line_ending(self):
        for ending in [b'', b'\n', b'\r\n']:
            self.assertEqual(planner.render(BASE + ending), BASE + b' cgroup_enable=memory' + ending)

    def test_idempotent(self):
        result = planner.render(BASE + b'\n')
        self.assertEqual(planner.render(result), result)

    def test_ambiguous_and_conflicting_arguments_stop(self):
        for extra in [b' cgroup_disable=memory', b' cgroup_disable=cpu,memory',
                      b' cgroup_memory=1', b' cgroup_enable=cpu,memory',
                      b' cgroup_enable=memory cgroup_enable=memory',
                      b' root=/dev/other', b' usb-storage.quirks=152d:0583:u']:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                planner.render(BASE + extra)

    def test_invalid_files_stop(self):
        for data in [b'', BASE+b'\nother', BASE+b'\n\n', BASE+b'\x00',
                     BASE+b' # comment', BASE.replace(planner.QUIRK, b''), b'x'*16385]:
            with self.subTest(data=data[:30]), self.assertRaises(ValueError):
                planner.render(data)


if __name__ == '__main__':
    unittest.main()
