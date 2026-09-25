#!/usr/bin/env python3
"""Neutral tests plus opt-in real PostgreSQL qualification inside isolated Podman."""
import copy
import os
from pathlib import Path
import sys
import unittest
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ansible/scripts'))
import logical_database as logical


class ReceiptTests(unittest.TestCase):
    def test_missing_receipt_rejected(self):
        with self.assertRaises(ValueError):
            logical.compare({}, {})

    def test_no_partial_receipt(self):
        with self.assertRaises(ValueError):
            logical.compare({'format': 'postgresql17-logical-v1'}, {'format': 'postgresql17-logical-v1'})


@unittest.skipUnless(os.environ.get('LOGICAL_TEST_DATABASE') == 'disposable', 'requires isolated PostgreSQL')
class PostgreSQLTests(unittest.TestCase):
    def setUp(self):
        import psycopg2
        self.db = psycopg2.connect(host='postgresql', user='postgres', dbname='postgres', connect_timeout=5)
        self.db.autocommit = True
        self.sql('DROP SCHEMA IF EXISTS fixture CASCADE; CREATE SCHEMA fixture; '
                 'CREATE TABLE fixture.data (v text,n numeric,stamp timestamptz,b bytea); '
                 'CREATE TABLE fixture.empty (id integer); CREATE SEQUENCE fixture.seq; '
                 "INSERT INTO fixture.data VALUES (NULL,1.20,'2026-01-01 00:00:00+00',decode('00ff','hex')),"
                 "('',2.00,NULL,NULL),('雪',NULL,NULL,NULL),('雪',NULL,NULL,NULL)")

    def tearDown(self):
        self.db.close()

    def sql(self, statement):
        self.db.autocommit = True
        with self.db.cursor() as cur:
            cur.execute(statement)

    def capture(self, **kwargs):
        return logical.identity(self.db, **kwargs)

    def test_stability_order_types_duplicates_and_empty(self):
        before = self.capture()
        self.sql('CREATE TABLE fixture.reordered AS SELECT * FROM fixture.data ORDER BY v DESC; '
                 'TRUNCATE fixture.data; INSERT INTO fixture.data SELECT * FROM fixture.reordered; DROP TABLE fixture.reordered')
        self.assertTrue(logical.compare(before, self.capture())['equal'])
        self.sql("DELETE FROM fixture.data WHERE ctid IN (SELECT ctid FROM fixture.data WHERE v='雪' LIMIT 1)")
        self.assertFalse(logical.compare(before, self.capture())['equal'])

    def test_null_and_empty_distinct(self):
        before = self.capture()
        self.sql("UPDATE fixture.data SET v='' WHERE v IS NULL")
        self.assertIn('tables', logical.compare(before, self.capture())['changed_sections'])

    def test_schema_sequence_and_empty_table_changes(self):
        before = self.capture()
        self.sql("SELECT nextval('fixture.seq')")
        self.assertIn('sequences', logical.compare(before, self.capture())['changed_sections'])
        self.sql('ALTER TABLE fixture.empty ADD COLUMN added text')
        self.assertIn('definitions', logical.compare(before, self.capture())['changed_sections'])
        self.sql('DROP TABLE fixture.empty')
        self.assertIn('tables', logical.compare(before, self.capture())['changed_sections'])

    def test_limits_and_unsupported_objects(self):
        with self.assertRaisesRegex(ValueError, 'logical_capture_limit'):
            self.capture(row_limit=1)
        with self.assertRaisesRegex(ValueError, 'logical_capture_limit'):
            self.capture(byte_limit=1)
        self.sql('CREATE MATERIALIZED VIEW fixture.unsupported AS SELECT 1')
        with self.assertRaisesRegex(ValueError, 'unsupported_relation_inventory'):
            self.capture()

    def test_repeatable_read_excludes_concurrent_committed_row(self):
        import psycopg2
        before = self.capture()
        db = self.db
        class ConcurrentWriter:
            fired = False
            def __getattr__(self, name):
                return getattr(db, name)
            def cursor(self, *args, **kwargs):
                if kwargs.get('name') and not self.fired:
                    self.fired = True
                    other = psycopg2.connect(host='postgresql', user='postgres', dbname='postgres')
                    try:
                        with other.cursor() as cur:
                            cur.execute("INSERT INTO fixture.data(v) VALUES ('concurrent')")
                        other.commit()
                    finally:
                        other.close()
                return db.cursor(*args, **kwargs)
        snapshot = logical.identity(ConcurrentWriter())
        self.assertTrue(logical.compare(before, snapshot)['equal'])
        self.assertFalse(logical.compare(before, self.capture())['equal'])

    def test_connection_not_left_in_transaction(self):
        self.capture()
        self.assertEqual(self.db.get_transaction_status(), 0)


if __name__ == '__main__':
    unittest.main()
