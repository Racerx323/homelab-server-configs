#!/usr/bin/env python3
"""Bounded native-command diagnostics; retain redacted failure output only."""
import os
import re
import selectors
import subprocess
import time


def redact(raw, environment=None):
    text = raw.decode('utf-8', errors='replace') if isinstance(raw, bytes) else raw
    environment = os.environ if environment is None else environment
    values = sorted({v for v in environment.values() if len(v) >= 8}, key=len, reverse=True)
    for value in values:
        text = text.replace(value, '[REDACTED]')
    text = re.sub(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^\s/@]+(?::[^\s/@]*)?@', r'\1[REDACTED]@', text)
    text = re.sub(r'(?i)((?:password|token|secret|api_key)\s*[=:]\s*)[^\s,;]+', r'\1[REDACTED]', text)
    return ''.join(c if c in '\n\t' or ord(c) >= 32 else '?' for c in text)


def command(argv, timeout):
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    selector = selectors.DefaultSelector(); buffers = {}; totals = {}; start = time.monotonic(); error = None
    for stream in (p.stdout, p.stderr):
        os.set_blocking(stream.fileno(), False);selector.register(stream, selectors.EVENT_READ)
        buffers[stream] = bytearray();totals[stream] = 0
    try:
        while selector.get_map():
            if time.monotonic()-start >= timeout:
                error = 'timeout';break
            for key, _ in selector.select(.1):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj);continue
                totals[key.fileobj] += len(data)
                buffers[key.fileobj].extend(data)
                del buffers[key.fileobj][:-16384]
                if totals[key.fileobj] >= 4194304:
                    error = 'output_limit';break
            if error:break
        if error:p.kill()
        try:rc=p.wait(timeout=max(.01,timeout-(time.monotonic()-start)))
        except subprocess.TimeoutExpired:
            error='timeout';p.kill();rc=p.wait()
        result={'exit_status':rc,'output_limited':error=='output_limit'}
        if error:result['error']=error
        if rc != 0 or error:
            result['diagnostics']={'stdout':redact(bytes(buffers[p.stdout])),
                                   'stderr':redact(bytes(buffers[p.stderr])),
                                   'tail_truncated':any(n>16384 for n in totals.values())}
        return result
    finally:
        if p.poll() is None:p.kill();p.wait()
        selector.close();p.stdout.close();p.stderr.close()
        for value in buffers.values():value[:] = b''
