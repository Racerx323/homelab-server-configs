"""Disposable Celery/Redis/PostgreSQL integration fixture, never a production Job."""
import os
import time
from celery import Celery

app = Celery('preservation_fixture', broker='redis://:qualification-only@redis:6379/0', backend='redis://:qualification-only@redis:6379/2')


@app.task(name='preservation_fixture.hold')
def hold():
    time.sleep(8)
    return 1


def main():
    import psycopg2
    import redis
    import recovery_probe as probe
    import logical_database
    client = redis.Redis(host='redis', password='qualification-only', socket_timeout=5)
    for _ in range(30):
        if app.control.inspect(timeout=1).ping(): break
        time.sleep(1)
    else: raise RuntimeError('worker_missing')
    assert probe.drain(app, client)['consecutive_observations'] == 2
    key = b'fixture-unused-priority\x06\x169'
    client.rpush(key, b'fixture')
    assert not probe.broker_empty(client)
    client.delete(key)  # Owned disposable fixture only; production drain never deletes.
    client.hset('unacked', 'fixture', 'fixture')
    assert not probe.broker_empty(client)
    client.delete('unacked')
    task = hold.delay()
    time.sleep(1)
    started = time.monotonic()
    assert probe.drain(app, client, timeout=60)['worker_empty']
    assert time.monotonic() - started >= 5
    assert task.get(timeout=30) == 1
    db=psycopg2.connect(host='postgresql',dbname='nautobot',user='nautobot',password='qualification-only')
    with db.cursor() as cur: cur.execute('CREATE TABLE fixture (id integer); INSERT INTO fixture VALUES (1)')
    db.commit(); db.close()
    before=probe.logical()
    assert logical_database.compare(before, probe.logical())['equal']
    print('native_drain_priority_unacked_task_completion_and_logical_client_passed')


if __name__=='__main__': main()
