#!/usr/bin/env python3
"""Inactive in-container probe; invoke only through an approved disposable trial.

Run inside Nautobot's initialized Django shell. Never print settings, passwords,
connection URLs, query results, or raw exception messages.
"""
import contextlib
import copy
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit, unquote


FAILURE_CODES = frozenset(('native_configuration_check', 'allowed_hosts', 'bootstrap_credential_present', 'csrf_origin', 'database_engine', 'database_host', 'database_name', 'database_password', 'database_port', 'database_user', 'django_secret', 'django_setup_incomplete', 'isolation_marker', 'package_versions', 'plugin_registration', 'postgres_identity', 'postgres_server_port', 'postgres_unexpected_failure', 'postgres_positive_failure', 'postgres_negative_missing_sqlstate', 'postgres_negative_unexpected_sqlstate', 'postgres_positive_cleanup_failure', 'postgres_negative_cleanup_failure', 'postgres_wrong_password_accepted', 'production_flags', 'proxy_header', 'redis_configuration', 'redis_invalid_credentials_accepted', 'redis_ping_result', 'redis_unexpected_failure', 'redis_valid_credentials_rejected', 'settings_path', 'unclassified_failure'))
EXCEPTION_CATEGORIES = frozenset(('CheckFailed', 'ImportError', 'ModuleNotFoundError', 'AttributeError', 'KeyError', 'TypeError', 'ValueError', 'OSError', 'PermissionError', 'FileNotFoundError', 'OperationalError', 'ProgrammingError', 'ImproperlyConfigured', 'AppRegistryNotReady'))

PG_ATTEMPTS = frozenset(('positive', 'negative'))
PG_STEPS = frozenset(('construct', 'cursor', 'query', 'fetch', 'close'))
PG_SQLSTATES = frozenset(('absent', '28P01', '28000', '08001', '08006', '3D000', '42501', 'other'))


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
    require(database['ENGINE'] == 'django.db.backends.postgresql', 'database_engine')
    require(database['HOST'] == 'postgresql', 'database_host')
    require(database['NAME'] == 'nautobot', 'database_name')
    require(database['USER'] == 'nautobot', 'database_user')
    require(database['PASSWORD'] == environ['NAUTOBOT_DB_PASSWORD'] and bool(database['PASSWORD']), 'database_password')
    require(str(database.get('PORT','')) in ('','5432') and
            environ.get('PGPORT','5432') == '5432', 'database_port')
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


def postgres_failure(code, attempt, step, error):
    failure = CheckFailed(code)
    state = sqlstate(error)
    state = 'absent' if state is None else state if isinstance(state, str) and state in PG_SQLSTATES - {'absent', 'other'} else 'other'
    category = type(error).__name__
    failure.postgres_diagnostic = {
        'attempt': attempt, 'step': step,
        'exception_category': category if category in EXCEPTION_CATEGORIES else 'unclassified',
        'sqlstate': state,
    }
    return failure


def postgres_check(factory, configuration, *, include_negative=False):
    for negative in ((False, True) if include_negative else (False,)):
        attempt = 'negative' if negative else 'positive'
        config = copy.deepcopy(configuration)
        config['OPTIONS'] = {**config.get('OPTIONS', {}), 'connect_timeout': 5,
                             'options': '-c statement_timeout=5000'}
        config['CONN_MAX_AGE'] = 0
        if negative:
            config['PASSWORD'] = 'invalid-' + secrets.token_hex(32)
        connection = None
        step = 'construct'
        try:
            try:
                connection = factory(config, alias='qualification_' + attempt)
                step = 'cursor'
                with connection.cursor() as cursor:
                    step = 'query'
                    cursor.execute('SELECT current_user, current_database(), inet_server_port()')
                    step = 'fetch'
                    row = cursor.fetchone()
            except Exception as error:
                state = sqlstate(error)
                if not negative or state != '28P01':
                    code = ('postgres_positive_failure' if not negative else
                            'postgres_negative_missing_sqlstate' if state is None else
                            'postgres_negative_unexpected_sqlstate')
                    raise postgres_failure(code, attempt, step, error) from None
            else:
                require(not negative, 'postgres_wrong_password_accepted')
                require(row[:2] == ('nautobot', 'nautobot'), 'postgres_identity')
                require(len(row) == 3 and row[2] == 5432, 'postgres_server_port')
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception as error:
                    raise postgres_failure('postgres_' + attempt + '_cleanup_failure',
                                           attempt, 'close', error) from None


def redis_check(factory, kwargs, authentication_error, *, include_negative=False):
    for mode in (('correct', 'missing', 'wrong') if include_negative else ('correct',)):
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


def native_configuration_check():
    from django.core.management import call_command
    # Discard command text; only a fixed outcome code reaches evidence.
    with open(os.devnull, 'w') as sink, contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
        try:
            call_command('check', verbosity=0, stdout=sink, stderr=sink)
        except Exception:
            raise CheckFailed('native_configuration_check') from None


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
        phase = 'native_check'
        native_configuration_check()
        result['checks'].append('native_configuration_check')
        phase = 'postgresql'
        default = connections['default']
        postgres_check(type(default), default.settings_dict)
        result['checks'].append('postgresql_positive_identity_port')
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
        result['checks'].append('redis_cache_positive')
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
        result['checks'].append('redis_broker_positive')
        result['accepted'] = True
    except Exception as error:
        # Preserve known assertion identifiers, never arbitrary exception messages.
        code=error.args[0] if type(error) is CheckFailed and len(error.args)==1 else None
        code=code if isinstance(code,str) and code in FAILURE_CODES else 'unclassified_failure'
        category=type(error).__name__ if type(error).__name__ in EXCEPTION_CATEGORIES else 'unclassified'
        result.update(failed_phase=phase, error='check_or_connection_cleanup_failed',
                      failure_code=code, exception_category=category)
        if type(error) is CheckFailed and hasattr(error, 'postgres_diagnostic'):
            result['postgres_diagnostic'] = error.postgres_diagnostic
    print(json.dumps(result))
    return 0 if result['accepted'] else 69


if __name__ == '__main__':
    raise SystemExit(main())
