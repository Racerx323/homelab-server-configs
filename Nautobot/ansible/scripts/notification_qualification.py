#!/usr/bin/env python3
"""One bounded simulated transition pair through the existing notification sender."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import sys
import time

from capture_retained import verify_tree
import recurring_delivery as delivery
from recurring_protection import atomic, protected, require


def previews(op):
    """Freeze the exact wire messages, including the existing queue's identities."""
    result = {}
    for sequence, event in enumerate(('failure', 'recovery'), 1):
        payload = dict(
            event_id=hashlib.sha256((op['evidence_root']+'/state:'+str(sequence)+':'+event).encode()).hexdigest(),
            event=event, observed=op['observed'], severity='success' if event == 'recovery' else 'failure',
            transition=('unknown' if event == 'failure' else 'failure')+' -> '+event,
            impact='Protection restored.' if event == 'recovery' else 'Application recovery coverage needs review.',
            failure_class='none' if event == 'recovery' else 'backup-or-writer-recovery')
        result[event] = {'event_id': payload['event_id'], 'message': delivery.format_alert(op['notification'], payload)}
    return result


def run(op, evidence, health, sender=delivery.send_direct, sleep=time.sleep):
    if os.path.lexists(evidence/'state'):
        return 1
    result = {'accepted': False, 'submission_complete': False, 'attempts': [],
              'downstream_receipts': 'awaiting_Aaron', 'checks_passed': False}
    try:
        protected(evidence, True)
        require(os.getuid() == op['target']['uid'] and os.getgid() == op['target']['gid'], 'service_identity')
        require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == op['boot_id'], 'boot_changed')
        require(op['messages'] == previews(op), 'message_drift')
        require(op['attempts_per_message'] == 2 and op['retry_seconds'] == 15, 'retry_boundary')
        require(health() == op['services'], 'service_changed')
        for path, spec in op['preserved_trees'].items():
            verify_tree(Path(path), spec)
        # Exclusive queue creation is the node-side no-replay boundary, including after a crash.
        state = evidence/'state'
        state.mkdir(mode=0o700)
        atomic(evidence/'result.json', result)
        now = datetime.fromisoformat(op['observed']).timestamp()

        def send(contract, payload):
            expected = op['messages'][payload['event']]
            require(expected == {'event_id': payload['event_id'], 'message': delivery.format_alert(contract, payload)},
                    'wire_message_drift')
            row = {'event': payload['event'], 'event_id': payload['event_id'],
                   'started_at': datetime.now(timezone.utc).isoformat(), 'http_200': None}
            result['attempts'].append(row)
            atomic(evidence/'result.json', result)  # A lost response remains explicitly ambiguous.
            row['http_200'] = sender(contract, payload)
            row['finished_at'] = datetime.now(timezone.utc).isoformat()
            atomic(evidence/'result.json', result)
            return row['http_200']

        for event in ('failure', 'recovery'):
            for attempt in range(op['attempts_per_message']):
                if delivery.notify(state, event, op['notification'], sender=send, now=now):
                    break
                if attempt+1 < op['attempts_per_message']:
                    sleep(op['retry_seconds'])
            else:
                raise ValueError('submission_budget_exhausted')
        result['submission_complete'] = True
        for path, spec in op['preserved_trees'].items():
            verify_tree(Path(path), spec)
        require(health() == op['services'], 'service_changed')
        result['checks_passed'] = True
    except Exception as error:
        # Do not overwrite original receipts when refusing a replay.
        if isinstance(error, FileExistsError):
            return 1
        result['failure_class'] = type(error).__name__
        if isinstance(error, ValueError) and re.fullmatch('[a-z_]{1,80}', str(error)):
            result['reason'] = str(error)
    atomic(evidence/'result.json', result)
    return 0 if result['checks_passed'] else 1


def main():
    os.umask(0o077)
    sys.dont_write_bytecode = True
    path = Path(sys.argv[1]); protected(path)
    require(path.stat().st_size < 1048576, 'operation_size')
    op = json.loads(path.read_text()); evidence = path.parent
    require(op['operation']['execution_enabled'] is True and
            op['operation']['stage'] == 'recurring_notification_qualification', 'execution_disabled')
    require(evidence == Path(op['evidence_root']), 'evidence_root')
    # Reuse the accepted read-only service/HTTP probe only after verifying its entire tree.
    capture = Path(op['capture_root'])
    verify_tree(capture, op['preserved_trees'][str(capture)])
    sys.path.insert(0, str(capture/'scripts'))
    import recurring_node
    def terminated(*_):
        raise InterruptedError('cancelled')
    signal.signal(signal.SIGTERM, terminated)
    return run(op, evidence, recurring_node.health)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        raise SystemExit('notification_qualification_refused; inspect protected receipts')
