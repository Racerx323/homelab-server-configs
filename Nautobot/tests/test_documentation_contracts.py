#!/usr/bin/env python3
"""Offline documentation, bundle-reference and validation-wiring contracts."""
import json
from pathlib import Path
import re
import subprocess
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
COMPONENT = ROOT / 'Nautobot'
# These require explicitly selected local runtimes and must not silently execute
# Podman or install dependencies in the offline CI entrypoint.
OPT_IN_TESTS = {
    'test_metrics_tmpfs.py': 'NAUTOBOT_TMPFS_TEST_IMAGE',
    'test_startup_journal.py': 'NAUTOBOT_JOURNAL_TEST_IMAGE',
    'test_startup_server.py': 'NAUTOBOT_SERVER_TEST_PYTHON',
}


# These schema constants and the byte-preserved inactive template describe
# historical contracts. Resolve their document paths at the documented snapshot,
# never treat those strings as current bundle inputs.
HISTORICAL_DOCUMENT_REFERENCES = {
    ('manifests/deferred-restic-initialization.yaml', 'ISOLATED_BACKUP_RESTORE.md'),
    ('schemas/repository-initialization.schema.json', 'ISOLATED_BACKUP_RESTORE.md'),
    ('schemas/operation.schema.json', 'ISOLATED_BACKUP_RESTORE.md'),
    ('schemas/host-convergence.schema.json', 'HOST_BASELINE_CONVERGENCE.md'),
}
DOCUMENT_SNAPSHOT = '368f93a3286f15d0803ae783164fa78414d4b78f'


def headings(text):
    result = set()
    seen = {}
    fenced = False
    for line in text.splitlines():
        if line.startswith('```'):
            fenced = not fenced
        if fenced or not re.match(r'^#{1,6} ', line):
            continue
        title = re.sub(r'^#+ ', '', line).lower()
        anchor = re.sub(r'[^\w\- ]', '', title).replace(' ', '-')
        count = seen.get(anchor, 0)
        seen[anchor] = count + 1
        result.add(anchor + (f'-{count}' if count else ''))
    return result


class DocumentationContracts(unittest.TestCase):
    def test_current_manual_links_and_sections_resolve(self):
        for path in (COMPONENT / 'docs').glob('*.md'):
            for link in re.findall(r'\]\(([^)\s]+)\)', path.read_text()):
                if '://' in link:
                    continue
                filename, _, anchor = link.partition('#')
                target = path.parent / filename if filename else path
                with self.subTest(document=path.name, link=link):
                    self.assertTrue(target.exists(), f'Missing local link: {target}')
                    if anchor and target.suffix == '.md':
                        self.assertIn(anchor, headings(target.read_text()))

    def test_executable_and_schema_document_paths_exist(self):
        for directory in ('ansible', 'schemas', 'manifests', 'tests'):
            for path in (COMPONENT / directory).rglob('*'):
                if not path.is_file() or '__pycache__' in str(path) or 'fixtures' in path.parts:
                    continue
                if path.suffix not in ('.py', '.sh', '.json', '.yaml', '.md'):
                    continue
                for reference in re.findall(r'Nautobot/docs/[A-Z_]+\.md', path.read_text()):
                    with self.subTest(source=str(path.relative_to(ROOT)), reference=reference):
                        historical = (str(path.relative_to(COMPONENT)), Path(reference).name)
                        if historical in HISTORICAL_DOCUMENT_REFERENCES:
                            subprocess.run(['git', 'cat-file', '-e', DOCUMENT_SNAPSHOT + ':' + reference],
                                           cwd=ROOT, check=True, capture_output=True)
                        else:
                            self.assertTrue((ROOT / reference).is_file())

    def test_schemas_and_local_references_are_valid(self):
        def references(value):
            if isinstance(value, dict):
                if '$ref' in value:
                    yield value['$ref']
                for child in value.values():
                    yield from references(child)
            elif isinstance(value, list):
                for child in value:
                    yield from references(child)
        for path in (COMPONENT / 'schemas').glob('*.json'):
            schema = json.loads(path.read_text())
            Draft202012Validator.check_schema(schema)
            for reference in references(schema):
                filename = reference.split('#')[0]
                if filename and '://' not in filename:
                    self.assertTrue((path.parent / filename).is_file(), reference)

    def test_every_test_has_an_offline_entry_or_explicit_opt_in(self):
        hooks = (ROOT / '.pre-commit-config.yaml').read_text()
        runner = (COMPONENT / 'tests/run-validation.py').read_text()
        self.assertIn("h['id'].startswith('nautobot-')", runner)
        self.assertIn('python Nautobot/tests/run-validation.py',
                      (ROOT / '.github/workflows/validation.yml').read_text())
        for path in (COMPONENT / 'tests').glob('test_*.py'):
            with self.subTest(test=path.name):
                if path.name in OPT_IN_TESTS:
                    text = path.read_text()
                    self.assertIn('@unittest.skipUnless', text)
                    self.assertIn(OPT_IN_TESTS[path.name], text)
                else:
                    self.assertIn(path.name, hooks + runner)


if __name__ == '__main__':
    unittest.main()
