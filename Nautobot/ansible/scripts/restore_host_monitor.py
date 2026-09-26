#!/usr/bin/env python3
"""Root read-only host sampler; communicates bounded health to the rootless guard.

Ansible starts this in a transient system service. It never stops production.
"""
import argparse
import json
import os
from pathlib import Path
import re
import time

import workload_sampler as sampler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--token', required=True)
    args = parser.parse_args()
    if os.getuid() != 0 or not re.fullmatch('nautobot-restore-[a-f0-9]{24}', args.token):
        raise ValueError('monitor_scope')
    root = Path('/run')/(args.token+'-monitor')
    root.mkdir(mode=0o755)  # Refuse retained state; parent /run is root-owned.
    cursor = sampler.run(['/usr/bin/journalctl', '-n', '0', '--show-cursor', '--no-pager']).strip().split('-- cursor: ')[-1]
    reader = sampler.Reader(cursor)
    contract = {'sampling':{'maximum_gap_seconds':15},
                'stop_criteria':{'mem_available_below_bytes':1536*1024**2,'temperature_above_celsius':80}}
    first = previous = None
    started = time.monotonic()
    try:
        while time.monotonic()-started < 4200:
            sample = reader.sample()
            if first is None: first = sample
            sampler.validate(sample, first, previous, contract)
            previous = sample
            value = {'passed':True,'monotonic':time.monotonic(),'boot_id':sample['boot_id']}
            temporary = root/'sample.new'
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
            with os.fdopen(fd,'w') as stream: json.dump(value,stream)
            os.replace(temporary,root/'sample.json')
            time.sleep(5)
        raise ValueError('monitor_deadline')
    except Exception as error:
        # Readers treat missing/stale or failed evidence as stop, never health.
        value = sampler.failure_receipt(error)
        with (root/'failure.json').open('x') as stream: json.dump(value,stream)
        raise


if __name__ == '__main__': main()
