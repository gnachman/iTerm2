"""Tests for tools/swift_migration/ivar_ownership_check.py, which compares
the ivar ownership in a runtime snapshot with the code database.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_ivar_ownership_check.py'

Each test builds a small database with the columns of the code database's
objc_impl, objc_ivar and tu tables that the tool reads (schema 11), and a
snapshot in format 3 written in the shape runtime_snapshot.sh writes.
"""

import io
import os
import sqlite3
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)

import ivar_ownership_check  # noqa: E402

HEADER = '# Objective-C runtime snapshot, format 3\narchitecture arm64\nbuild-configuration Development\nbuild-variant ASan\n'


def section(name, arc_flag, ivars, language='objc', extra=()):
    lines = ['class ' + name, '  language ' + language, '  superclass NSObject', '  image iTerm2',
             '  ivar-arc-flag ' + arc_flag, '  strong-ivar-layout', '  weak-ivar-layout']
    lines += ['  ' + e for e in extra]
    for ivar_name, types, label, layout in ivars:
        lines.append('  ivar %s types=%s ownership=%s layout=%s' % (ivar_name, types, label, layout))
    lines.append('end class ' + name)
    return '\n'.join(lines) + '\n'


class Database:
    """A database with the tables and columns the tool reads."""

    def __init__(self, path, version=11):
        self.con = sqlite3.connect(path)
        self.con.executescript('''
            CREATE TABLE tu(id INTEGER PRIMARY KEY, main_file TEXT NOT NULL, extracted_at TEXT NOT NULL);
            CREATE TABLE objc_impl(id INTEGER PRIMARY KEY, tu INTEGER NOT NULL, class_name TEXT NOT NULL,
                                   category TEXT, arc INTEGER NOT NULL, file TEXT NOT NULL);
            CREATE TABLE objc_ivar(id INTEGER PRIMARY KEY, tu INTEGER NOT NULL, class_name TEXT NOT NULL,
                                   name TEXT NOT NULL, type TEXT NOT NULL, type_class TEXT NOT NULL,
                                   ownership TEXT NOT NULL, arc INTEGER NOT NULL, record_has_objects INTEGER,
                                   file TEXT NOT NULL DEFAULT '');
        ''')
        self.con.execute('PRAGMA user_version = %d' % version)
        self.next_tu = 1

    def implementation(self, class_name, arc, ivars, category=None, file=None, extracted_at='2026-11-20T12:00:00Z',
                       ivar_file=None):
        tu = self.next_tu
        self.next_tu += 1
        file = file or 'sources/%s.m' % class_name
        self.con.execute('INSERT INTO tu(id, main_file, extracted_at) VALUES (?, ?, ?)', (tu, file, extracted_at))
        self.con.execute('INSERT INTO objc_impl(tu, class_name, category, arc, file) VALUES (?, ?, ?, ?, ?)',
                         (tu, class_name, category, arc, file))
        for name, typ, type_class, ownership, has_objects in ivars:
            self.con.execute('INSERT INTO objc_ivar(tu, class_name, name, type, type_class, ownership, arc, '
                             'record_has_objects, file) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                             (tu, class_name, name, typ, type_class, ownership, arc, has_objects, ivar_file or file))
        self.con.commit()


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.directory.name, 'codedb.sqlite')
        self.db = Database(self.db_path)

    def tearDown(self):
        self.db.con.close()
        self.directory.cleanup()

    def run_tool(self, snapshot_text, db_path=None, root=None):
        path = os.path.join(self.directory.name, 'snapshot.txt')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(snapshot_text)
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = ivar_ownership_check.main(['--db', db_path or self.db_path, '--root', root or self.directory.name, path])
        return status, out.getvalue(), err.getvalue()

    def test_agreement_and_compiler_answers(self):
        self.db.implementation('A', 1, [('_s', 'NSObject *__strong', 'object', 'strong', 0),
                                        ('_w', 'NSObject *__weak', 'object', 'weak', 0),
                                        ('_u', 'NSObject *__unsafe_unretained', 'object', 'unsafe_unretained', 0),
                                        ('_n', 'NSInteger', 'scalar', 'none', 0),
                                        ('_r', 'NSRect', 'struct', 'none', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_n', 'q', 'scalar', ''),
                                                                    ('_r', '{CGRect=}', 'struct-or-cxx-object', ''),
                                                                    ('_s', '@', 'strong', 's'),
                                                                    ('_u', '@', 'unretained-or-manual', ''),
                                                                    ('_w', '@', 'weak', 'w')]))
        self.assertEqual(status, 0, out)
        self.assertIn('  _s  runtime: strong layout=s  [strong (runtime layout)]  compiler: NSObject *__strong (object, strong, ARC)  agrees\n', out)
        self.assertIn('  _w  runtime: weak layout=w', out)
        self.assertIn('compiler: NSObject *__unsafe_unretained (object, unsafe_unretained, ARC)  compiler\n', out)
        self.assertIn('compiler: NSRect (struct, holds no object pointers, ARC)  compiler\n', out)
        self.assertTrue(out.endswith('0 disagreements\n'), out)

    def test_strong_layout_against_unretained_declaration_disagrees(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'unsafe_unretained', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')]))
        self.assertEqual(status, 1)
        self.assertIn('  DISAGREES\n', out)
        self.assertTrue(out.endswith('1 disagreement\n'), out)

    def test_unretained_against_strong_declaration_disagrees(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'unretained-or-manual', '')]))
        self.assertEqual(status, 1, out)

    def test_arc_flag_against_compiler_mode(self):
        self.db.implementation('A', 0, [('_o', 'id', 'object', 'manual', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'unretained-or-manual', '')]))
        self.assertEqual(status, 1)
        self.assertIn('DISAGREES: the runtime ARC flag is set, but the compiler compiled the @implementation without ARC', out)

    def test_manual_class(self):
        self.db.implementation('M', 0, [('_o', 'id', 'object', 'manual', 0)])
        status, out, _ = self.run_tool(HEADER + section('M', 'clear', [('_o', '@', 'manual', '')]))
        self.assertEqual(status, 0, out)
        self.assertIn('compiler: id (object, manual, manual reference counting)  compiler\n', out)

    def test_manual_label_in_an_arc_class_disagrees(self):
        self.db.implementation('M', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, out, _ = self.run_tool(HEADER + section('M', 'unknown', [('_o', '@', 'manual', '')]))
        self.assertEqual(status, 1, out)

    def test_cxx_member(self):
        self.db.implementation('C', 1, [('_v', 'std::vector<id>', 'cxx-object', 'none', 0),
                                        ('_p', 'Plain', 'cxx-object', 'none', 0),
                                        ('_h', 'Holder', 'cxx-object', 'none', 1)],
                               file='sources/C.mm')
        status, out, _ = self.run_tool(HEADER + section('C', 'set', [('_h', '{Holder=@i}', 'arc-members', 's'),
                                                                    ('_p', '{Plain=ii}', 'struct-or-cxx-object', ''),
                                                                    ('_v', '{vector<id>=}', 'cxx-object', '')]))
        self.assertEqual(status, 0, out)
        self.assertIn('compiler: Plain (cxx-object, holds no object pointers, its destructor runs when the instance is destroyed, ARC)  compiler\n', out)
        self.assertIn('compiler: Holder (cxx-object, holds object pointers, its destructor runs when the instance is destroyed, ARC)  agrees\n', out)
        self.assertIn('[a C++ object: its destructor runs when the instance is destroyed; what its elements own depends on their types]', out)

    def test_struct_label_on_an_object_disagrees(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, _, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '{S=}', 'struct-or-cxx-object', '')]))
        self.assertEqual(status, 1)

    def test_scalar_label_on_an_object_disagrees(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, _, _ = self.run_tool(HEADER + section('A', 'set', [('_o', 'q', 'scalar', '')]))
        self.assertEqual(status, 1)

    def test_only_the_class_implementation_counts(self):
        # A category's unit sees the header ivar as compiled without ARC; it
        # does not govern the ivar's ownership.
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        self.db.implementation('A', 0, [('_o', 'id', 'object', 'manual', 0)], category='Extra', file='sources/A+Extra.m')
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')]))
        self.assertEqual(status, 0, out)
        self.assertNotIn('A+Extra', out)

    def test_header_ivar_recorded_by_another_unit_of_the_same_mode(self):
        # The extractor records a header's ivars once per ARC mode, from
        # whichever unit read the header first: here a unit that is not the
        # @implementation's, plus one compiled without ARC.
        self.db.implementation('A', 1, [])
        self.db.implementation('Other', 1, [], file='sources/Other.m')
        self.db.con.execute("INSERT INTO objc_ivar(tu, class_name, name, type, type_class, ownership, arc, record_has_objects) "
                            "VALUES (2, 'A', '_h', 'id', 'object', 'strong', 1, 0)")
        self.db.con.execute("INSERT INTO objc_ivar(tu, class_name, name, type, type_class, ownership, arc, record_has_objects) "
                            "VALUES (3, 'A', '_h', 'id', 'object', 'manual', 0, 0)")
        self.db.con.commit()
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_h', '@', 'strong', 's')]))
        self.assertEqual(status, 0, out)
        self.assertIn('compiler: id (object, strong, ARC)  agrees\n', out)

    def test_class_without_implementation_is_unknown(self):
        status, out, _ = self.run_tool(HEADER + section('NSView', 'set', [('_o', '@', 'strong', 's')]))
        self.assertEqual(status, 0, out)
        self.assertIn('class NSView: no @implementation in the database, so no compiler answer (unknown)\n', out)

    def test_swift_class(self):
        status, out, _ = self.run_tool(HEADER + section('S', 'set', [('value', '?', 'swift', '')], language='swift'))
        self.assertEqual(status, 0, out)
        self.assertIn('class S: a Swift class; ownership comes from the Swift declarations', out)

    def test_ownership_conflict_is_a_disagreement(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')],
                                                        extra=['OWNERSHIP-CONFLICT runtime-disagrees _o']))
        self.assertEqual(status, 1)
        self.assertIn('DISAGREES: the snapshot reports OWNERSHIP-CONFLICT runtime-disagrees _o', out)

    def test_ivar_missing_from_either_side(self):
        self.db.implementation('A', 1, [('_old', 'id', 'object', 'strong', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_new', '@', 'strong', 's')]))
        self.assertEqual(status, 0, out)
        self.assertIn('  _new  runtime: strong layout=s  [strong (runtime layout)]  compiler: no row for this ivar (unknown)\n', out)
        self.assertIn('  _old  not in the runtime snapshot', out)

    def test_escaped_names(self):
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@%22x%22', 'strong', 's')]))
        self.assertEqual(status, 0, out)

    def test_files_newer_than_the_database_are_warned_about(self):
        # The implementation and a header that declares an ivar both changed
        # after their unit was extracted; the answers stand, with a warning.
        self.db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)], file='sources/A.m',
                               extracted_at='2026-11-20T12:00:00Z', ivar_file='sources/A.h')
        os.makedirs(os.path.join(self.directory.name, 'sources'))
        for name in ['A.m', 'A.h']:
            path = os.path.join(self.directory.name, 'sources', name)
            with open(path, 'w') as f:
                f.write('')
            os.utime(path, (1795219200, 1795219200))  # 2026-11-21T00:00:00Z, after the extraction
        status, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')]))
        self.assertEqual(status, 0, out)
        self.assertIn('  WARNING: sources/A.h changed after its unit was extracted (2026-11-20T12:00:00Z); the compiler answers may be stale\n', out)
        self.assertIn('  WARNING: sources/A.m changed after its unit was extracted (2026-11-20T12:00:00Z); the compiler answers may be stale\n', out)
        # Files older than the extraction get no warning.
        for name in ['A.m', 'A.h']:
            os.utime(os.path.join(self.directory.name, 'sources', name), (1795170000, 1795170000))  # 2026-11-20T10:20:00Z, before it
        _, out, _ = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')]))
        self.assertNotIn('WARNING', out)

    def test_reads_the_code_databases_current_schema(self):
        # The tool refused every database once codedb.py moved to schema 12,
        # although the columns it reads did not change.
        sys.path.insert(0, os.path.join(TOOL_DIR, 'codedb'))
        import codedb
        current = os.path.join(self.directory.name, 'current.sqlite')
        db = Database(current, version=codedb.SCHEMA_VERSION)
        db.implementation('A', 1, [('_o', 'id', 'object', 'strong', 0)])
        db.con.close()
        status, out, err = self.run_tool(HEADER + section('A', 'set', [('_o', '@', 'strong', 's')]), db_path=current)
        self.assertEqual(status, 0, err)
        self.assertIn('agrees', out)

    def test_errors(self):
        status, _, err = self.run_tool(HEADER.replace('format 3', 'format 2') + section('A', 'set', []))
        self.assertEqual(status, 2)
        self.assertIn('format 3', err)
        other = os.path.join(self.directory.name, 'other.sqlite')
        Database(other, version=10).con.close()
        status, _, err = self.run_tool(HEADER + section('A', 'set', []), db_path=other)
        self.assertEqual(status, 2)
        self.assertIn('schema 10', err)
        status, _, err = self.run_tool(HEADER + section('A', 'set', []), db_path=os.path.join(self.directory.name, 'none.sqlite'))
        self.assertEqual(status, 2)
        self.assertIn('no database', err)


if __name__ == '__main__':
    unittest.main()
