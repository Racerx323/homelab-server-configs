#!/usr/bin/env python3
"""Independent recurring-capture identity; enabled only by a reviewed binding."""
import hashlib
import json
from pathlib import Path
import re
import time
import uuid

from logical_database import compare
from recurring_protection import atomic, protected, require

SCRIPTS = Path(__file__).resolve().parent
PROBE_SECONDS = 25


def code():
    # Same probe as preservation, without starting Django or an application writer.
    return ("import sys,types,json\nm=types.ModuleType('logical_database')\n"
            + "exec(" + repr((SCRIPTS/'logical_database.py').read_text()) + ",m.__dict__)\n"
            + "m.LIMIT_SECONDS=20\nsys.modules['logical_database']=m\n"
            + (SCRIPTS/'recovery_probe.py').read_text()
            + "\ntry: print(json.dumps(logical(),sort_keys=True))\n"
            + "except Exception: raise SystemExit('logical_probe_failed')\n")


def probe(pod, image, *, network='nautobot-private', env_file='/var/lib/nautobot/runtime/web.env'):
    require(re.fullmatch(r'(sha256:)?[0-9a-f]{64}', image), 'logical_image')
    token = uuid.uuid4().hex
    name = 'nautobot-logical-' + token
    started = time.monotonic()
    try:
        raw = pod(['run', '--rm', '--name', name, '--label', 'nautobot.logical='+token,
                   '--timeout', str(PROBE_SECONDS), '--pull=never', '--network', network,
                   '--read-only', '--user', '999:999', '--memory', '768m', '--memory-swap', '768m',
                   '--cpus', '1', '--pids-limit', '64', '--env-file', str(env_file),
                   '-e', 'PYTHONDONTWRITEBYTECODE=1', '--entrypoint', 'python3', '-i', image, '-'],
                  data=code().encode(), timeout=35)
        require(len(raw) < 1048576, 'logical_reference_size')
        value = json.loads(raw)
        require(compare(value, value)['equal'], 'logical_reference_shape')
        return value, time.monotonic()-started
    finally:
        # Conmon also kills the helper if this controller disappears. Remove only
        # this invocation's uniquely labelled container if --rm has not done so.
        ids = pod(['ps', '-aq', '--filter', 'label=nautobot.logical='+token], timeout=5).decode().split()
        require(len(ids) <= 1 and all(re.fullmatch('[0-9a-f]{12,64}', i) for i in ids), 'logical_helper_identity')
        if ids:
            pod(['rm', '--force', '--time', '0', *ids], timeout=5)


def digest(path):
    protected(path)
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    protected(path)
    require(path.stat().st_size < 1048576, 'logical_receipt_size')
    return json.loads(path.read_text())


def specification_hash(spec):
    return hashlib.sha256(json.dumps(spec, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def begin(root, pod, image):
    require(not any((root/n).exists() for n in ('logical-before.json', 'logical-reference.json', 'logical-capture.json')),
            'logical_capture_consumed')
    value, seconds = probe(pod, image)
    atomic(root/'logical-before.json', {'identity': value, 'seconds': seconds})


def finish(root, pod, image):
    require(not (root/'logical-reference.json').exists() and not (root/'logical-capture.json').exists(),
            'logical_capture_consumed')
    before = read(root/'logical-before.json')
    after, seconds = probe(pod, image)
    require(compare(before['identity'], after)['equal'], 'logical_capture_changed')
    # Keep the pre-dump identity: the reference is not calculated from the dump.
    atomic(root/'logical-reference.json', before['identity'])
    receipt = {'format': 'recurring-logical-v1',
               'specification_sha256': specification_hash(read(root/'application-backup.json')),
               'dump_sha256': digest(root/'payload/postgresql_custom_dump'),
               'reference_sha256': digest(root/'logical-reference.json'),
               'before_seconds': before['seconds'], 'after_seconds': seconds,
               'comparison': compare(before['identity'], after)}
    atomic(root/'logical-capture.json', receipt)
    return {'logical_reference': before['identity'], 'logical_capture': receipt}


def verify_retained(root, spec, hashes):
    """Refuse disposal unless the independently retained reference matches capture."""
    reference = read(root/'logical-reference.json')
    receipt = read(root/'logical-capture.json')
    versions = read(root/'payload/versions_migrations')
    require(receipt['format'] == 'recurring-logical-v1'
            and receipt['specification_sha256'] == specification_hash(spec)
            and receipt['dump_sha256'] == hashes['postgresql_custom_dump']
            and receipt['reference_sha256'] == digest(root/'logical-reference.json')
            and receipt['comparison'] == compare(reference, reference)
            and versions['logical_reference'] == reference and versions['logical_capture'] == receipt,
            'logical_retention_mismatch')
