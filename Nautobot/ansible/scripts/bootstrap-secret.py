#!/usr/bin/env python3
"""Resolve approved bootstrap input into controller tmpfs only at execution."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

spec = importlib.util.spec_from_file_location('credentials', Path(__file__).with_name('provision-credentials.py'))
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)
IDENTITY = Path('/home/aaron/code/.local-evidence/nautobot-runtime-preparation-20260921/bootstrap-inputs.json')


def resolve(directory, expected_identity_hash):
    root = Path(directory)
    s = root.lstat()
    if (root.parent != Path('/dev/shm') or not re.fullmatch(r'nautobot-bootstrap\.[A-Za-z0-9_]+', root.name)
            or not stat.S_ISDIR(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o700):
        raise ValueError('private_root')
    s = IDENTITY.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o600 or s.st_size > 4096:
        raise ValueError('identity_metadata')
    raw = IDENTITY.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected_identity_hash:
        raise ValueError('identity_changed')
    identity = json.loads(raw)
    if set(identity) != {'username', 'email'} or identity['username'] != 'admin' or '@' not in identity['email']:
        raise ValueError('identity_shape')
    password = provider.doppler('secrets', 'get', 'NAUTOBOT_INITIAL_ADMIN_PASSWORD', '--plain', '--config', 'prd_nautobot').strip()
    if not re.fullmatch('[0-9a-f]{64}', password):
        raise ValueError('password_properties')
    provider.write_private(root/'input.json', json.dumps({**identity, 'password': password}))


if __name__ == '__main__':
    os.umask(0o077)
    try:
        resolve(sys.argv[1], sys.argv[2])
    except Exception:
        print('bootstrap_input_resolution_failed')
        raise SystemExit(69)
