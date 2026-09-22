#!/usr/bin/env python3
"""Opt-in local Podman test of the rendered metrics mount, without host contact."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.environ.get('NAUTOBOT_TMPFS_TEST_IMAGE'), 'requires explicit local Podman image')
class MetricsTmpfs(unittest.TestCase):
    def test_private_bounded_mount_is_fresh_for_each_container(self):
        spec = importlib.util.spec_from_file_location('render', ROOT/'Nautobot/ansible/scripts/render-runtime.py')
        render = importlib.util.module_from_spec(spec);spec.loader.exec_module(render)
        artifacts = render.render(yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text()),
                                  json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text()))
        mount = next(line.removeprefix('Tmpfs=') for line in artifacts['nautobot-migration.container'].splitlines()
                     if line.startswith('Tmpfs=/prom_cache:'))
        image = subprocess.check_output(['podman','image','inspect','--format','{{.Id}}',os.environ['NAUTOBOT_TMPFS_TEST_IMAGE']],text=True).strip()
        program = '''set -eu
[ "$(id -u)" = 999 ]
[ "$(stat -c '%u:%g:%a' /prom_cache)" = 0:0:1777 ]
[ ! -e /prom_cache/marker ]
printf metric > /prom_cache/marker
if touch /rootfs-must-stay-readonly 2>/dev/null; then exit 10; fi
if dd if=/dev/zero of=/prom_cache/limit bs=1048576 count=17 2>/dev/null; then exit 11; fi
[ "$(stat -c %s /prom_cache/limit)" -le 16777216 ]
'''
        for _ in range(2):
            with tempfile.TemporaryDirectory(prefix='nautobot-tmpfs-test.') as directory:
                cidfile = Path(directory)/'cid'
                try:
                    result = subprocess.run(['podman','run','--rm','--pull=never','--network=none',
                        '--read-only','--cap-drop=all','--user=999:999','--memory=64m',
                        '--cidfile',str(cidfile),'--tmpfs',mount,'--entrypoint=/bin/sh',image,'-ec',program],
                        capture_output=True,text=True,timeout=60)
                    self.assertEqual(result.returncode,0,result.stderr)
                finally:
                    if cidfile.exists():
                        subprocess.run(['podman','rm','--force','--ignore',cidfile.read_text().strip()],
                                       capture_output=True,timeout=30,check=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
