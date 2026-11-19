#!/usr/bin/env python3
"""Tests for reflective_registry.py: a small registry and a database with
only the reflective_call table."""

import io
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import reflective_registry as rr  # noqa: E402

DOC = """# Reflective-site registry

## 2. Summary

### Database rows by mechanism and classification

| Mechanism | CLOSED | GENERIC | OPEN-INTERNAL | OPEN-EXTERNAL | NOT-REFLECTIVE | UNRESOLVED | Total |
|---|---|---|---|---|---|---|---|
| Selector from a string | 2 | 0 | 0 | 0 | 0 | 0 | 2 |
| Calling by selector | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| **Total** | **2** | **1** | **0** | **0** | **0** | **0** | **3** |

### Names that must be preserved

| Name | Resolves | Runtime name | Note | Sites |
|---|---|---|---|---|
| `foo:` | selector |  |  | a.m:10 |
| `bar` | selector |  |  | b.m:5 |

## 3. Dynamic sites

### Selector from a string

#### `sources/a.m`

- `sources/a.m:10` in `-[A x]`: `NSSelectorFromString` on `name`
- `sources/a.m:12` in `-[A x]`: `NSSelectorFromString` on `name`

  **CLOSED.** Reach: `foo:`.

  Names: `foo:`.

### Calling by selector

#### `sources/b.m`

- `sources/b.m:5` in `-[B y]`: `performSelector:` on `sel`

  **GENERIC.** Reach: `bar`.

  Names: `bar`.

## 4. Callers of generic helpers

Prose citing sources/a.m:10, not regenerated.
"""


def make_db(path, rows):
    con = sqlite3.connect(path)
    con.execute('CREATE TABLE reflective_call(id INTEGER PRIMARY KEY, function_or_selector TEXT, argument_index '
                'INTEGER, argument_kind TEXT, argument_text TEXT, enclosing_name TEXT, file TEXT, line INTEGER, '
                'col INTEGER, in_migration_scope INTEGER)')
    for r in rows:
        con.execute('INSERT INTO reflective_call(file, line, col, function_or_selector, argument_index, argument_text, '
                    'enclosing_name, argument_kind, in_migration_scope) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', r)
    con.commit()
    con.close()


ROWS = [('sources/a.m', 10, 5, 'NSSelectorFromString', 0, 'name', '-[A x]', 'dynamic', 1),
        ('sources/a.m', 12, 5, 'NSSelectorFromString', 0, 'name', '-[A x]', 'dynamic', 1),
        ('sources/b.m', 5, 3, 'performSelector:', 0, 'sel', '-[B y]', 'dynamic', 1),
        # Not dynamic, and not in scope: not sites of the registry.
        ('sources/b.m', 6, 3, 'performSelector:', 0, '@selector(z)', '-[B y]', 'selector-expr', 1),
        ('submodules/c.m', 1, 1, 'NSSelectorFromString', 0, 's', 'f', 'dynamic', 0)]


class RegistryTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='reflective-registry-')
        self.doc = os.path.join(self.dir, 'reflective-sites.md')
        self.db = os.path.join(self.dir, 'codedb.sqlite')
        with open(self.doc, 'w') as f:
            f.write(DOC)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def run_tool(self, command, rows=ROWS):
        if not os.path.exists(self.db):
            make_db(self.db, rows)
        out = io.StringIO()
        status = rr.main([command, '--db', self.db, '--doc', self.doc], out=out)
        return status, out.getvalue()

    def text(self):
        with open(self.doc) as f:
            return f.read()

    def test_clean(self):
        status, out = self.run_tool('check')
        self.assertEqual(status, 0, out)
        self.assertIn('database rows (dynamic, in scope, distinct file, line, column, call, argument index): 3\n', out)
        self.assertIn('bullets in section 3: 3\n', out)

    def test_moved_lines_are_rewritten_in_order(self):
        rows = [r[:1] + (r[1] + 7,) + r[2:] if r[0] == 'sources/a.m' else r for r in ROWS]
        status, out = self.run_tool('check', rows)
        self.assertEqual(status, 1)
        self.assertIn('LINE MOVED (update rewrites it): 2\n  sources/a.m:10 now 17 in -[A x]: NSSelectorFromString\n'
                      '  sources/a.m:12 now 19 in -[A x]: NSSelectorFromString\n', out)
        status, out = self.run_tool('update')
        self.assertEqual(status, 0, out)
        text = self.text()
        self.assertIn('- `sources/a.m:17` in `-[A x]`', text)
        self.assertIn('- `sources/a.m:19` in `-[A x]`', text)
        # Prose is left alone.
        self.assertIn('Prose citing sources/a.m:10, not regenerated.', text)
        status, _ = self.run_tool('check')
        self.assertEqual(status, 0)

    def test_new_site_refuses_update(self):
        rows = ROWS + [('sources/a.m', 30, 1, 'NSClassFromString', 0, 'className', '-[A z]', 'dynamic', 1)]
        status, out = self.run_tool('check', rows)
        self.assertEqual(status, 1)
        self.assertIn('NEW SITE (a row with no bullet: read it and write its entry): 1\n'
                      '  sources/a.m:30 in -[A z]: NSClassFromString on className\n', out)
        status, out = self.run_tool('update')
        self.assertEqual(status, 1)
        self.assertIn('update refused', out)
        self.assertEqual(self.text(), DOC)

    def test_stale_bullet(self):
        status, out = self.run_tool('check', ROWS[1:])
        self.assertEqual(status, 1)
        self.assertIn('STALE BULLET (a bullet with no row): 1\n  sources/a.m:12 in -[A x]: NSSelectorFromString on '
                      'name\n', out)

    def test_stale_bullet_alone_fails_check_and_refuses_update(self):
        # The site of sources/b.m:5 is gone and nothing moved: check fails on
        # the stale bullet alone, and update refuses and leaves the file.
        rows = [r for r in ROWS if not (r[0] == 'sources/b.m' and r[7] == 'dynamic')]
        status, out = self.run_tool('check', rows)
        self.assertIn('STALE BULLET (a bullet with no row): 1\n', out)
        self.assertIn('LINE MOVED (update rewrites it): 0\n', out)
        self.assertIn('NEW SITE (a row with no bullet: read it and write its entry): 0\n', out)
        self.assertEqual(status, 1, out)
        status, out = self.run_tool('update')
        self.assertEqual(status, 1, out)
        self.assertIn('update refused', out)
        self.assertEqual(self.text(), DOC)

    def test_summary_is_counted_from_the_bullets(self):
        with open(self.doc, 'w') as f:
            f.write(DOC.replace('| Selector from a string | 2 | 0 | 0 | 0 | 0 | 0 | 2 |',
                                '| Selector from a string | 3 | 0 | 0 | 0 | 0 | 0 | 3 |'))
        status, out = self.run_tool('check')
        self.assertEqual(status, 1)
        self.assertIn('SUMMARY (update rewrites the table): 1\n  Selector from a string, CLOSED: the table says 3, '
                      'section 3 has 2\n', out)
        status, out = self.run_tool('update')
        self.assertEqual(status, 0, out)
        self.assertEqual(self.text(), DOC)

    def test_a_row_is_counted_under_its_calls_mechanism(self):
        # An entry's bullets sit under the heading of most of its rows; a
        # performSelector: row of an entry under "Selector from a string" is
        # counted under "Calling by selector".
        doc = DOC.replace("- `sources/a.m:12` in `-[A x]`: `NSSelectorFromString` on `name`",
                          "- `sources/a.m:12` in `-[A x]`: `performSelector:` on `name`")
        doc = doc.replace('| Selector from a string | 2 | 0 | 0 | 0 | 0 | 0 | 2 |',
                          '| Selector from a string | 1 | 0 | 0 | 0 | 0 | 0 | 1 |')
        doc = doc.replace('| Calling by selector | 0 | 1 | 0 | 0 | 0 | 0 | 1 |',
                          '| Calling by selector | 1 | 1 | 0 | 0 | 0 | 0 | 2 |')
        with open(self.doc, 'w') as f:
            f.write(doc)
        rows = [r[:3] + ('performSelector:',) + r[4:] if r[1] == 12 else r for r in ROWS]
        status, out = self.run_tool('check', rows)
        self.assertEqual(status, 0, out)

    def test_names_table_is_the_union_of_names_lines(self):
        with open(self.doc, 'w') as f:
            f.write(DOC.replace('  Names: `bar`.', '  Names: `bar`, `baz`.'))
        status, out = self.run_tool('check')
        self.assertEqual(status, 1)
        self.assertIn('NAMES: 1\n  name in a Names: line but not in the names table: baz\n', out)

    def test_long_argument_is_cut_as_written(self):
        arg = 'x' * 95
        self.assertEqual(rr.bullet_argument(arg), 'x' * 87 + '...')
        self.assertEqual(rr.bullet_argument('a`b\nc'), "a'b c")

    def test_missing_database_is_an_error(self):
        out = io.StringIO()
        self.assertEqual(rr.main(['check', '--db', os.path.join(self.dir, 'none.sqlite'), '--doc', self.doc], out=out), 2)


if __name__ == '__main__':
    unittest.main()
