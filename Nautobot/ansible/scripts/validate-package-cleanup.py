#!/usr/bin/env python3
"""Offline scope checks for package-cleanup transaction review."""
import importlib.util
from pathlib import Path
import sys
import unittest
import re
import yaml

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cleanup', Path(__file__).with_name('prepare-package-cleanup.py'))
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupScope(unittest.TestCase):
    def test_live_playbook_parser_handles_unversioned_residual_rows(self):
        play = yaml.safe_load((Path(__file__).parents[1]/'playbooks/purge-reviewed-packages.yaml').read_text())[0]
        task = next(t for t in play['tasks'] if t['name'] == 'Refuse extra removals installations or upgrades')
        expression = task['ansible.builtin.assert']['that'][0]
        pattern = re.search(r"regex_findall\('([^']+)'\)", expression)[1]
        self.assertEqual(re.findall(pattern, 'Purg one\nPurg two [1.0]\n'), ['one', 'two'])

    def test_exact_purge_and_removal_set(self):
        cleanup.reviewed_removals('Purg one\nRemv two [1.0]\n', ['one', 'two'])

    def test_missing_extra_duplicate_or_installation_is_rejected(self):
        for output in ['Purg one', 'Purg one\nPurg two\nPurg three',
                       'Purg one\nPurg one', 'Purg one\nPurg two\nInst dep',
                       'Purg one\nPurg two\nConf dep']:
            with self.subTest(output=output), self.assertRaises(ValueError):
                cleanup.reviewed_removals(output, ['one', 'two'])


if __name__ == '__main__':
    unittest.main()
