#!/usr/bin/env python3
"""Bounded PostgreSQL 17 logical identity. Writer control is an external prerequisite.

Requires psycopg2 already provided by the application image. Never exports rows.
This is a comparison receipt, not a backup or proof that writers were quiesced.
"""
import hashlib
import json
import time

LIMIT_ROWS = 1000000
LIMIT_BYTES = 256 * 1024 * 1024
LIMIT_SECONDS = 300


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode()


def identity(connection, *, row_limit=LIMIT_ROWS, byte_limit=LIMIT_BYTES):
    from psycopg2 import sql
    started = time.monotonic()
    total_rows = total_bytes = 0
    result = {'format': 'postgresql17-logical-v1', 'tables': {}, 'sequences': {}}
    connection.set_session(isolation_level='REPEATABLE READ', readonly=True, autocommit=False)
    try:
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL statement_timeout='60s'; SET LOCAL lock_timeout='5s'; "
                           "SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO, YMD'; "
                           "SET LOCAL intervalstyle='iso_8601'; SET LOCAL extra_float_digits=3; "
                           "SET LOCAL bytea_output='hex'; SET LOCAL row_security=off; SET LOCAL search_path=pg_catalog")
            cursor.execute('SHOW server_version_num')
            result['server_version_num'] = cursor.fetchone()[0]
            if not 170000 <= int(result['server_version_num']) < 180000:
                raise ValueError('unsupported_postgresql_version')
            scope = "n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'"
            cursor.execute('SELECT n.nspname FROM pg_namespace n WHERE ' + scope + ' ORDER BY 1')
            result['schemas'] = [row[0] for row in cursor]
            cursor.execute('SELECT n.nspname,c.relname,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE ' + scope + ' ORDER BY 1,2')
            relations = cursor.fetchall()
            if len(relations) > 4096 or any(row[2] not in ('r', 'S', 'i', 'v') for row in relations):
                raise ValueError('unsupported_relation_inventory')
            cursor.execute('SELECT count(*) FROM pg_largeobject_metadata')
            if cursor.fetchone()[0]:
                raise ValueError('large_objects_not_supported')
            # Include definitions independently of data; no OIDs enter the receipt.
            cursor.execute("SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE " + scope + " AND t.typtype='d'")
            if cursor.fetchone()[0]:
                raise ValueError('domains_not_supported')
            queries = {
                'functions': 'SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE ' + scope + " AND p.prokind IN ('f','p') ORDER BY 1,2,3",
                'triggers': 'SELECT n.nspname,c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE ' + scope + ' AND NOT t.tgisinternal ORDER BY 1,2,3',
                'extensions': 'SELECT extname,extversion FROM pg_extension ORDER BY 1',
                'columns': "SELECT n.nspname,c.relname,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum WHERE " + scope + " AND a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','v') ORDER BY n.nspname,c.relname,a.attnum",
                'constraints': 'SELECT n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE ' + scope + ' ORDER BY 1,2,3',
                'indexes': 'SELECT n.nspname,c.relname,pg_get_indexdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE ' + scope + " AND c.relkind='i' ORDER BY 1,2",
                'views': 'SELECT n.nspname,c.relname,pg_get_viewdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE ' + scope + " AND c.relkind='v' ORDER BY 1,2",
                'enums': 'SELECT n.nspname,t.typname,e.enumlabel FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace JOIN pg_enum e ON e.enumtypid=t.oid WHERE ' + scope + ' ORDER BY n.nspname,t.typname,e.enumsortorder',
                'sequence_definitions': 'SELECT schemaname,sequencename,data_type::text,start_value,min_value,max_value,increment_by,cycle,cache_size FROM pg_sequences WHERE schemaname !~ \'^pg_\' ORDER BY 1,2',
            }
            result['definitions'] = {}
            for name, query in queries.items():
                cursor.execute(query)
                rows = cursor.fetchmany(20001)
                if len(rows) > 20000:
                    raise ValueError('definition_limit')
                result['definitions'][name] = hashlib.sha256(canonical(rows)).hexdigest()
            for schema, table, kind in relations:
                if time.monotonic() - started > LIMIT_SECONDS:
                    raise ValueError('logical_capture_limit')
                key = json.dumps([schema, table], ensure_ascii=True)
                if kind == 'S':
                    cursor.execute(sql.SQL('SELECT last_value,is_called FROM {}').format(sql.Identifier(schema, table)))
                    result['sequences'][key] = list(cursor.fetchone())
                if kind != 'r':
                    continue
                hashes = []
                # ONLY avoids counting inherited rows twice. Named cursor bounds fetching.
                with connection.cursor(name='logical_rows') as rows:
                    rows.execute(sql.SQL('SELECT row_to_json(t)::text FROM ONLY {} t').format(sql.Identifier(schema, table)))
                    rows.itersize = 128
                    for (row,) in rows:
                        encoded = row.encode('utf-8')
                        total_rows += 1
                        total_bytes += len(encoded)
                        if total_rows > row_limit or total_bytes > byte_limit or time.monotonic() - started > LIMIT_SECONDS:
                            raise ValueError('logical_capture_limit')
                        hashes.append(hashlib.sha256(encoded).digest())
                # Fixed-width sorted hashes preserve duplicates and ignore physical row order.
                digest = hashlib.sha256(b''.join(sorted(hashes))).hexdigest()
                result['tables'][key] = {'rows': len(hashes), 'sha256': digest}
        if time.monotonic() - started > LIMIT_SECONDS:
            raise ValueError('logical_capture_limit')
        return result
    finally:
        connection.rollback()


def compare(before, after):
    if before.get('format') != 'postgresql17-logical-v1' or after.get('format') != before['format']:
        raise ValueError('logical_format')
    required = {'format', 'server_version_num', 'schemas', 'definitions', 'tables', 'sequences'}
    if set(before) != required or set(after) != required or not before['tables'] or not after['tables']:
        raise ValueError('incomplete_identity')
    changed = [name for name in sorted(required) if before[name] != after[name]]
    return {'equal': not changed, 'changed_sections': changed, 'writer_control_required': True}
