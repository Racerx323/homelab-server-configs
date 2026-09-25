"""Read-only preservation probes; caller owns writer control and process bounds."""
import json
import time


def broker_empty(client):
    """Inspect all Redis broker lists, including every priority suffix; never purge."""
    count = 0
    pending = 0
    for key in client.scan_iter(count=128):
        count += 1
        if count > 4096:
            raise ValueError('broker_key_limit')
        kind = client.type(key)
        if kind == b'list':
            pending += client.llen(key)
        elif key == b'unacked':
            if kind != b'hash':
                raise ValueError('broker_unacked_type')
            pending += client.hlen(key)
        elif key == b'unacked_index':
            if kind != b'zset':
                raise ValueError('broker_unacked_index_type')
            pending += client.zcard(key)
    return pending == 0


def worker_empty(inspector):
    identity = None
    for action in ('active', 'reserved', 'scheduled'):
        replies = getattr(inspector, action)()
        if not isinstance(replies, dict) or len(replies) != 1:
            raise ValueError('worker_reply_coverage')
        name, tasks = next(iter(replies.items()))
        if identity is not None and name != identity:
            raise ValueError('worker_identity_changed')
        identity = name
        if not isinstance(tasks, list):
            raise ValueError('worker_reply_shape')
        if tasks:
            return False
    return True


def drain(app, client, timeout=180, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + timeout
    consecutive = 0
    while clock() < deadline:
        clear = worker_empty(app.control.inspect(timeout=5)) and broker_empty(client)
        consecutive = consecutive + 1 if clear else 0
        if consecutive == 2:
            return {'worker_empty': True, 'broker_empty': True, 'consecutive_observations': 2}
        sleep(5)
    raise ValueError('drain_timeout_no_cancellation')


def native_drain():
    from django.conf import settings
    from nautobot.core.celery import app
    import redis
    from urllib.parse import urlsplit
    url = urlsplit(settings.CELERY_BROKER_URL)
    if url.scheme != 'redis' or url.hostname != 'redis' or url.path != '/0':
        raise ValueError('unreviewed_broker')
    options = app.conf.broker_transport_options or {}
    if any(options.get(k) for k in ('global_keyprefix', 'unacked_key', 'unacked_index_key')):
        raise ValueError('unreviewed_broker_keys')
    client = redis.Redis.from_url(settings.CELERY_BROKER_URL, socket_timeout=5, socket_connect_timeout=5)
    try:
        return drain(app, client)
    finally:
        client.close()


def logical():
    """Run in a one-shot image with existing app env; no Django initialization."""
    import os
    import psycopg2
    import redis
    from logical_database import identity
    client = redis.Redis(host='redis', port=6379, db=0, password=os.environ['NAUTOBOT_REDIS_PASSWORD'],
                         socket_timeout=5, socket_connect_timeout=5)
    db = None
    try:
        if not broker_empty(client):
            raise ValueError('broker_not_empty_after_worker_stop')
        db = psycopg2.connect(host='postgresql', port=5432, user='nautobot', dbname='nautobot',
                              password=os.environ['NAUTOBOT_DB_PASSWORD'], connect_timeout=5)
        with db.cursor() as cur:
            cur.execute("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND backend_type='client backend'")
            if cur.fetchone()[0]:
                raise ValueError('other_database_clients_present')
        db.rollback()
        return identity(db)
    finally:
        if db is not None:
            db.close()
        client.close()
