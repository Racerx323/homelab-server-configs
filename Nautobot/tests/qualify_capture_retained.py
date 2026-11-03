#!/usr/bin/env python3
"""Exercise preservation and failed-unit release against disposable local user units."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from test_capture_retained import Retained


def ctl(*args):
    return subprocess.run(['/usr/bin/systemctl', '--user', *args], capture_output=True, text=True, timeout=30)


def qualify(output):
    fixture = Retained(); fixture.setUp()
    names = fixture.names
    linked = False
    try:
        assert all(ctl('show', n, '--property=LoadState', '--value').stdout.strip() == 'not-found' for n in names)
        for name in names:
            text = ('[Timer]\nOnActiveSec=1h\n' if name.endswith('.timer') else
                    '[Service]\nType=oneshot\nExecStart=/usr/bin/false\n')
            (fixture.root/'units'/name).write_text(text)
        assert ctl('link', '--runtime', *[str(fixture.root/'units'/n) for n in names]).returncode == 0
        linked = True
        assert ctl('daemon-reload').returncode == 0
        failed = [names[0], names[3]]
        for name in failed: assert ctl('start', name).returncode != 0
        payload, _ = fixture.terminal()
        properties = 'ActiveState,SubState,InvocationID,ExecMainStartTimestamp,MainPID,ControlPID,ControlGroup,Result'
        def show(name):
            if name not in names: return fixture.show(name)
            result = ctl('show', name, '--property='+properties); assert result.returncode == 0
            return dict(line.split('=', 1) for line in result.stdout.splitlines())
        fixture.spec['terminal']['units'] = {n: show(n) for n in names}
        fixture.units = Path(os.environ['XDG_RUNTIME_DIR'])/'systemd/user'
        result = fixture.apply(show=show)
        for name in failed: assert ctl('reset-failed', name).returncode == 0
        assert ctl('daemon-reload').returncode == 0
        assert all(ctl('show', n, '--property=LoadState', '--value').stdout.strip() == 'not-found' for n in names)
        assert (Path(result['preserved_directory'])/'state/state.json').exists()
        assert (payload/'dump').read_bytes() == b'retained payload'
        output.write_text(json.dumps({'local_user_systemd': True, 'failed_units_released': True,
                                     'latch_preserved': True, 'payload_unchanged': True,
                                     'target_acceptance': False}, indent=2)+'\n')
    finally:
        if linked:
            ctl('disable', '--runtime', *names)
            ctl('reset-failed', *names)
            ctl('daemon-reload')
        fixture.tearDown()


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    qualify(parser.parse_args().output)
