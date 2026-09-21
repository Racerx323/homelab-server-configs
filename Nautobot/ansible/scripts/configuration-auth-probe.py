#!/usr/bin/env python3
"""Inactive in-container probe; invoke only through an approved disposable trial.

Run inside Nautobot's initialized Django shell. Never print settings, passwords,
connection URLs, query results, or raw exception messages.
"""
import copy
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit, unquote


class CheckFailed(Exception):
    pass


def require(condition, code):
    if not condition:
        raise CheckFailed(code)


def redis_location(value, database, password):
    parsed = urlsplit(value)
    require(parsed.scheme == 'redis' and parsed.hostname == 'redis' and
            parsed.port == 6379 and parsed.path == '/' + str(database) and
            not parsed.query and not parsed.fragment and not parsed.username and
            unquote(parsed.password or '') == password and bool(password),
            'redis_configuration')


def settings_check(settings, environ, app_names, versions):
    require(str(settings.SETTINGS_PATH) == '/opt/nautobot/nautobot_config.py', 'settings_path')
    require(not settings.DEBUG and not settings.INSTALLATION_METRICS_ENABLED, 'production_flags')
    require(set(settings.ALLOWED_HOSTS) == {'nautobot.local.theama.co', 'j2-svpi4mf.local.theama.co'}, 'allowed_hosts')
    require(list(settings.CSRF_TRUSTED_ORIGINS) == ['https://nautobot.local.theama.co'], 'csrf_origin')
    require(tuple(settings.SECURE_PROXY_SSL_HEADER) == ('HTTP_X_FORWARDED_PROTO', 'https'), 'proxy_header')
    require(settings.SECRET_KEY == environ['NAUTOBOT_SECRET_KEY'] and len(settings.SECRET_KEY) == 128, 'django_secret')
    require('NAUTOBOT_INITIAL_ADMIN_PASSWORD' not in environ, 'bootstrap_credential_present')
    require(list(settings.PLUGINS) == ['nautobot_dns_models'] and 'nautobot_dns_models' in app_names, 'plugin_registration')
    require(versions == {'nautobot': '3.2.3', 'nautobot-dns-models': '2.3.0'}, 'package_versions')
    database = settings.DATABASES['default']
    require(database['ENGINE'] == 'django.db.backends.postgresql' and
            database['HOST'] == 'postgresql' and str(database.get('PORT',5432)) == '5432' and
            database['NAME'] == database['USER'] == 'nautobot' and
            database['PASSWORD'] == environ['NAUTOBOT_DB_PASSWORD'] and bool(database['PASSWORD']), 'database_configuration')
    redis_location(settings.CACHES['default']['LOCATION'], 1, environ['NAUTOBOT_REDIS_PASSWORD'])
    redis_location(settings.CELERY_BROKER_URL, 0, environ['NAUTOBOT_REDIS_PASSWORD'])


def sqlstate(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        value = getattr(error, 'sqlstate', None) or getattr(error, 'pgcode', None)
        if value:
            return value
        error = getattr(error, '__cause__', None)
    return None


def postgres_check(factory, configuration):
    for negative in (False, True):
        config = copy.deepcopy(configuration)
        config['OPTIONS'] = {**config.get('OPTIONS', {}), 'connect_timeout': 5,
                             'options': '-c statement_timeout=5000'}
        config['CONN_MAX_AGE'] = 0
        if negative:
            config['PASSWORD'] = 'invalid-' + secrets.token_hex(32)
        connection = factory(config, alias='qualification_negative' if negative else 'qualification_positive')
        try:
            try:
                with connection.cursor() as cursor:
                    cursor.execute('SELECT current_user, current_database()')
                    row = cursor.fetchone()
            except Exception as error:
                require(negative and sqlstate(error) == '28P01',
                        'postgres_unexpected_failure')
            else:
                require(not negative, 'postgres_wrong_password_accepted')
                require(row == ('nautobot', 'nautobot'), 'postgres_identity')
        finally:
            connection.close()


def redis_check(factory, kwargs, authentication_error):
    for mode in ('correct', 'missing', 'wrong'):
        options = {**kwargs, 'socket_connect_timeout': 5, 'socket_timeout': 5}
        if mode != 'correct':
            options['password'] = None if mode == 'missing' else 'invalid-' + secrets.token_hex(32)
        client = factory(**options)
        try:
            try:
                pong = client.ping()
            except authentication_error:
                require(mode != 'correct', 'redis_valid_credentials_rejected')
            except Exception:
                raise CheckFailed('redis_unexpected_failure') from None
            else:
                require(mode == 'correct', 'redis_invalid_credentials_accepted')
                require(pong is True, 'redis_ping_result')
        finally:
            try:
                client.close()
            finally:
                client.connection_pool.disconnect()


def main():
    # The future launcher mounts this non-secret marker only for the isolated trial.
    result = {'accepted': False, 'checks': [], 'production_runtime_accepted': False,
              'administrator_created': False}
    phase = 'isolation'
    try:
        require(Path('/run/nautobot-qualification/isolated-trial').read_text().strip() ==
                'disposable-configuration-authentication', 'isolation_marker')
        phase = 'settings'
        from importlib.metadata import version
        from django.apps import apps
        from django.conf import settings
        from django.db import connections
        from django_redis import get_redis_connection
        import redis
        require(apps.ready, 'django_setup_incomplete')
        settings_check(settings, os.environ, [a.name for a in apps.get_app_configs()],
                       {name: version(name) for name in ('nautobot', 'nautobot-dns-models')})
        result['checks'].append('settings_and_plugin_registration')
        phase = 'postgresql'
        default = connections['default']
        postgres_check(type(default), default.settings_dict)
        result['checks'].append('postgresql_positive_and_wrong_password')
        phase = 'redis_cache'
        cache = get_redis_connection('default')
        try:
            factory = lambda **kw: redis.Redis(connection_pool=redis.ConnectionPool(
                connection_class=cache.connection_pool.connection_class, **kw))
            redis_check(factory, cache.connection_pool.connection_kwargs, redis.exceptions.AuthenticationError)
        finally:
            try:
                cache.close()
            finally:
                cache.connection_pool.disconnect()
        result['checks'].append('redis_cache_positive_missing_wrong_password')
        phase = 'redis_broker'
        broker = redis.Redis.from_url(settings.CELERY_BROKER_URL)
        try:
            factory = lambda **kw: redis.Redis(connection_pool=redis.ConnectionPool(
                connection_class=broker.connection_pool.connection_class, **kw))
            redis_check(factory, broker.connection_pool.connection_kwargs, redis.exceptions.AuthenticationError)
        finally:
            try:
                broker.close()
            finally:
                broker.connection_pool.disconnect()
        result['checks'].append('redis_broker_positive_missing_wrong_password')
        result['accepted'] = True
    except Exception:
        # Log categorical phase only, including for close/disconnect failures.
        result.update(failed_phase=phase, error='check_or_connection_cleanup_failed')
    print(json.dumps(result))
    return 0 if result['accepted'] else 69


if __name__ == '__main__':
    raise SystemExit(main())
