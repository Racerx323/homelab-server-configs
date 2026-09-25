#!/usr/bin/env python3
"""Monitor the owning backup producer; stop its process group on failed coverage."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import workload_sampler as sampler

ROLES = ('postgresql', 'redis')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    root = parser.parse_args().root
    before = json.loads((root/'before.json').read_text())
    contract = {'sampling': {'maximum_gap_seconds': 15},
                'stop_criteria': {'mem_available_below_bytes': 1610612736, 'temperature_above_celsius': 80}}
    reader = sampler.Reader(before['cursor'], roles=ROLES)
    first = reader.sample()
    sampler.validate(first, first, None, contract, roles=ROLES)
    if first['boot_id'] != before['snapshot']['boot_id']:
        raise ValueError('boot_changed')
    def terminated(*_): raise InterruptedError('cancelled')
    signal.signal(signal.SIGTERM, terminated)
    status = {'passed': False, 'samples': 1, 'maximum_gap_seconds': 0, 'producer_exit_status': None}
    process = None
    try:
        with tempfile.TemporaryFile() as output:
            process = subprocess.Popen(['/usr/bin/python3', '-B', str(root/'application-backup.py'), '--root', str(root)],
                                       stdout=output, stderr=output, start_new_session=True)
            previous = first
            deadline = time.monotonic() + 1750
            while True:
                if time.monotonic() >= deadline or output.tell() > 1048576:
                    raise ValueError('backup_deadline_or_output')
                sample = reader.sample()
                sampler.validate(sample, first, previous, contract, roles=ROLES)
                status['samples'] += 1
                status['maximum_gap_seconds'] = max(status['maximum_gap_seconds'], sample['start'] - previous['start'])
                previous = sample
                if process.poll() is not None:
                    status['producer_exit_status'] = process.returncode
                    if process.returncode:
                        raise ValueError('backup_failed')
                    status['passed'] = True
                    break
                time.sleep(5)
    except Exception as error:
        status['failure_class'] = type(error).__name__
        status['diagnostic'] = sampler.failure_receipt(error)
        if process is not None:
            try: os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
    finally:
        fd = os.open(root/'backup-resource-review.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream: json.dump(status, stream)
    return 0 if status['passed'] else 69


if __name__ == '__main__':
    raise SystemExit(main())
