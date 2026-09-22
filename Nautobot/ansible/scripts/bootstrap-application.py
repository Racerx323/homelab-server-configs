#!/usr/bin/env python3
"""Native administrator creation; child output is discarded, receipts are boolean."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

spec = importlib.util.spec_from_file_location('native', Path(__file__).with_name('initialize-application.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
INPUT = Path('/run/bootstrap/input.json')
PHASE_CODE = "import runpy; runpy.run_path('/run/bootstrap/bootstrap-application.py')['account_phase']('{phase}')"


def credentials(path=INPUT):
    s = path.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o600 or s.st_size > 4096:
        raise ValueError('input_metadata')
    value = json.loads(path.read_text())
    if (set(value) != {'username', 'email', 'password'} or value['username'] != 'admin'
            or not isinstance(value['email'], str) or '@' not in value['email']
            or not isinstance(value['password'], str) or len(value['password']) != 64):
        raise ValueError('input_shape')
    return value


def account_phase(phase):
    # Invoked inside native nautobot-server shell after Nautobot initializes Django.
    from django.contrib.auth import authenticate, get_user_model
    data = credentials()
    model = get_user_model()
    query = {model.USERNAME_FIELD: data['username']}
    if phase == 'absent':
        if model.objects.filter(**query).exists():
            raise SystemExit(17)
        return
    if phase != 'verify':
        raise SystemExit(19)
    user = model.objects.get(**query)
    checks = (user.get_username() == data['username'], user.email == data['email'],
              user.is_active, user.is_staff, user.is_superuser)
    if not all(checks):
        raise SystemExit(18)
    authenticated = authenticate(**query, password=data['password'])
    if authenticated is None or authenticated.pk != user.pk:
        raise SystemExit(20)


def bootstrap(runner=native.command, inspect=True):
    result = {'passed': False, 'creation_attempted': False, 'steps': {}}
    keys = ('DJANGO_SUPERUSER_USERNAME', 'DJANGO_SUPERUSER_EMAIL', 'DJANGO_SUPERUSER_PASSWORD')
    phase = 'input_or_resource_boundary'
    try:
        if inspect:
            if (os.getuid() != 999 or Path('/sys/fs/cgroup/memory.max').read_text().strip() != '1610612736'
                    or Path('/sys/fs/cgroup/memory.swap.max').read_text().strip() != '0'):
                raise ValueError('resource_boundary')
        data = credentials()
        steps = [('configuration', ['check']), ('pending_migrations', ['migrate', '--check']),
                 ('account_absent', ['shell', '--interface', 'python', '--command', PHASE_CODE.format(phase='absent')]),
                 ('creation', ['createsuperuser', '--noinput']),
                 ('account_verified', ['shell', '--interface', 'python', '--command', PHASE_CODE.format(phase='verify')])]
        for name, args in steps:
            phase = name
            if name == 'creation':
                result['creation_attempted'] = True
                os.environ.update(dict(zip(keys, (data['username'], data['email'], data['password']))))
            try:
                step = runner(['nautobot-server'] + args, 120)
            finally:
                for key in keys:
                    os.environ.pop(key, None)
            result['steps'][name] = step
            if step.get('exit_status') != 0 or step.get('error') or step.get('output_limited'):
                result['failed_phase'] = name
                return result
        result['passed'] = True
    except Exception:
        result['failed_phase'] = phase
    return result


if __name__ == '__main__':
    os.umask(0o077)
    result = bootstrap()
    print(json.dumps(result), flush=True)
    raise SystemExit(0 if result['passed'] else 69)
