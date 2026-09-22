#!/usr/bin/env python3
"""Run frozen read-only node checks over strict SSH; return sanitized decisions."""
import json
from pathlib import Path
import subprocess
import sys


def probe(mode, expected_path):
    expected = json.loads(Path(expected_path).read_text())
    source = Path(__file__).with_name('startup-runtime-check.py').read_text()
    source += '\ntry:\n print(json.dumps(main('+repr(mode)+','+repr(expected)+')))\nexcept Exception as exc:\n code=str(exc) if isinstance(exc,ValueError) and str(exc) in ERROR_CODES else "unexpected_runtime_failure"\n print(json.dumps({"passed":False,"error_class":code}));raise SystemExit(69)\n'
    p = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5',
                        'ama@10.1.2.170', 'cd / && sudo -n /usr/bin/python3 -'], input=source.encode(),
                       capture_output=True, timeout=240)
    if len(p.stdout) > 65536:
        raise ValueError('runtime_probe_failed')
    value = json.loads(p.stdout)
    if p.returncode and not value.get('error_class'):
        raise ValueError('runtime_probe_failed')
    return value


if __name__ == '__main__':
    try:
        print(json.dumps(probe(*sys.argv[1:])))
    except Exception:
        print(json.dumps({'passed': False, 'error_class': 'runtime_probe_failed'}));raise SystemExit(69)
