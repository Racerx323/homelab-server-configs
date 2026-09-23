#!/usr/bin/env python3
"""Invoke the frozen Job probe through the actual running web container."""
import json
import subprocess


def probe():
    argv = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
            'XDG_RUNTIME_DIR=/run/user/999', '/usr/bin/podman', 'exec', 'nautobot-web',
            'nautobot-server', 'shell', '--interface', 'python', '--command',
            "import runpy;runpy.run_path('/run/startup-job-probe.py',run_name='__main__')"]
    script = 'import subprocess,sys\nr=subprocess.run(' + repr(argv) + ',cwd="/",capture_output=True,timeout=110)\nsys.stdout.buffer.write(r.stdout);sys.exit(r.returncode)\n'
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                             '-o', 'ConnectTimeout=5', 'ama@10.1.2.170', 'cd / && sudo -n /usr/bin/python3 -'],
                            input=script.encode(), capture_output=True, timeout=120)
    if result.returncode or len(result.stdout) > 65536:
        raise ValueError('job_probe_failed')
    lines = [line.removeprefix(b'STARTUP_JOB_RESULT=') for line in result.stdout.splitlines() if line.startswith(b'STARTUP_JOB_RESULT=')]
    if len(lines) != 1:
        raise ValueError('job_receipt_count')
    return json.loads(lines[0])


if __name__ == '__main__':
    try:
        print(json.dumps(probe()))
    except Exception:
        print(json.dumps({'job_completed': False, 'single_worker_concurrency_two': False}))
        raise SystemExit(69)
