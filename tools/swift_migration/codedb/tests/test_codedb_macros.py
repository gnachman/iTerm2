#!/usr/bin/env python3
"""Tests for the code database's preprocessor tables (macro_def, macro_undef,
macro_ast_fact, macro_expansion, macro_use_count, pp_condition, pp_skipped),
the queries macros, macrouses and skipped, the search of code no unit
compiles in reach and ivars, and macrolint.

Run with the other code database tests:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_*.py'

The fixtures under macro_fixtures/ need no SDK: mbase.h declares a root
class; macro_outside/ plays the SDK (a directory outside the repository).
a.m is compiled with MODE=1 and b.m with MODE=2, so that macros.h is read in
two views. Expected rows are written out by hand from the fixtures.
"""

import io
import json
import os
import shutil
import sqlite3
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import codedb  # noqa: E402
import test_codedb as base  # noqa: E402

A = 'sources/a.m'
B = 'sources/b.m'
H = 'sources/macros.h'
G = 'sources/mbase.h'
MAINS = ((A, ['-fobjc-arc', '-DMODE=1']), (B, ['-fobjc-arc', '-DMODE=2']))
RUN = '-[User run:]'


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def make_macro_root(fixtures='macro_fixtures'):
    d = base.make_temp('codedb-macros-')
    root = os.path.join(d, 'repo')
    shutil.copytree(os.path.join(HERE, fixtures), root)
    shutil.copytree(os.path.join(HERE, 'macro_outside'), os.path.join(d, 'outside'))
    return root


def write_cdb(root, path, mains=MAINS):
    base.write_project(root, {'T': [m for m, _ in mains]})
    meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(root)}
    with open(path, 'w') as f:
        f.write(json.dumps(meta) + '\n')
        for m, extra in mains:
            f.write(json.dumps({'target': 'T', 'file': m, 'directory': root,
                                'arguments': base.clang_args(root, m, extra)}) + '\n')


def rows(db, sql, params=()):
    con = sqlite3.connect(db)
    try:
        return con.execute(sql, params).fetchall()
    finally:
        con.close()


def split(text):
    body, _, block = text.partition('\n--- status ---\n')
    return body.splitlines(), block


# (name, kind, params, variadic, body, facts, file, line, col): every
# definition, as each unit's claim records it. macros.h is read in two views
# (MODE differs), so its definitions have a row from each unit; mbase.h is
# read in one view, recorded by a.m only.
def mdef(name, body, line, facts='', kind='object', params=None, variadic=0, file=H, col=9):
    return (name, kind, params, variadic, body, facts, file, line, col)


SHARED_DEFS = [
    mdef('LIMIT', '10', 5),
    mdef('SQUARE', '((x) * (x))', 6, 'multiple-evaluation', 'function', 'x'),
    mdef('LOGF', 'Logf(fmt, __VA_ARGS__)', 7, '', 'function', 'fmt, ...', 1),
    mdef('NAME_OF', '#x', 8, 'stringify unevaluated-parameter', 'function', 'x'),
    mdef('GETTER', 'get_##name', 9, 'paste unevaluated-parameter', 'function', 'name'),
    mdef('SEND_LOG', '[obj log:text]', 10, 'send', 'function', 'obj, text'),
    mdef('CALL', '[obj sel]', 11, 'send', 'function', 'obj, sel'),
    mdef('SELF_COUNT', '(self->_count + _count)', 12, 'self'),
    mdef('RETURN_IF', 'do { if (c) return 0; } while (0)', 13, 'control-flow-keyword return', 'function', 'c'),
    # A break inside the loop the macro opens does not leave it (no fact
    # break), but the body has the keyword.
    mdef('LOOP_BREAK', 'for (;;) { break; }', 14, 'control-flow-keyword'),
    mdef('ESCAPE_BREAK', 'break', 15, 'break control-flow-keyword'),
    mdef('WHERE', '__FILE__, __LINE__, __func__', 16, 'file-line'),
    mdef('TWICE', 'SQUARE(e)', 17, 'uses-macro', 'function', 'e'),
    mdef('ITBetaAssert', 'do { if (!(condition)) { LogObj(args); } } while (0)', 18, '', 'function',
         'condition, args...', 1),
    mdef('ITNonnilLock', '({ id it_nonnilLock_ = (lockExpression); ITBetaAssert(it_nonnilLock_ != nil, '
                         '@"@synchronized(%s) at %s:%d has a nil lock and runs unprotected", #lockExpression, '
                         '__FILE__, __LINE__); it_nonnilLock_; })', 19,
         'file-line statement-expression stringify uses-macro', 'function', 'lockExpression'),
    # The return is in the method the macro defines: no fact return.
    mdef('DEFINE_GETTER', '+ (int)name { return LIMIT; }', 26, 'control-flow-keyword method-definition uses-macro', 'function',
         'name'),
    mdef('DECLARE_CLASS', '@interface name : MRoot @end', 27, 'class-definition', 'function', 'name'),
    mdef('NOT_RETAINED', '__attribute__((objc_method_family(none)))', 28, 'method-family-attribute'),
    mdef('LEAKY', 'static int name##_storage = 0;', 29, 'paste static unevaluated-parameter', 'function', 'name'),
    mdef('AS_TYPE', '((T)(v) + sizeof(T))', 30, 'multiple-evaluation type-parameter', 'function', 'T, v'),
    mdef('FIRST_ONLY', '(a)', 31, 'unevaluated-parameter', 'function', 'a, b'),
    mdef('RUN_BLOCK', '^{ x; }', 32, 'block', 'function', 'x'),
    mdef('LOCKED', '@synchronized(o) { s; }', 33, 'synchronized', 'function', 'o, s'),
    mdef('SETTER_FOR', '[self set##Name:0]', 34, 'paste self send unevaluated-parameter', 'function', 'Name'),
    mdef('REDEFINED', '1', 35),
    mdef('REDEFINED', '2', 37),
    mdef('HAS_SDK', '1', 49),
    mdef('HAS_MODE', '1', 55),
    mdef('PING_SELECTOR', '@selector(ping)', 57, 'selector'),
    mdef('CMD_NAME', '_cmd', 58, 'cmd'),
    # A block literal with a return type, sent a message: the return is in the
    # block.
    mdef('BLOCK_OF', '[^id() { return [self x]; } copy]', 59, 'block control-flow-keyword self send', 'function', 'x'),
]
EXPECTED_DEFS = sorted(
    [(A,) + d for d in SHARED_DEFS] + [(B,) + d for d in SHARED_DEFS] + [
        (A,) + mdef('LOCAL', '1', 3, file=A),
        (B,) + mdef('LOCAL', '2', 3, file=B),
        (A,) + mdef('USER_CLASS', 'User', 43, file=A),
        # Each unit sees only the branch MODE selects.
        (A,) + mdef('KIND', '1', 39),
        (B,) + mdef('KIND', '2', 41),
        (A,) + mdef('MBASE_H', '', 3, file=G),
        (A,) + mdef('nil', '((id)0)', 14, file=G),
    ], key=lambda r: (r[7], r[8], r[1], r[0]))

DEF_SQL = ('SELECT t.main_file, d.name, d.kind, d.params, d.variadic, d.body, d.facts, d.file, d.line, d.col '
           'FROM macro_def d JOIN tu t ON t.id = d.tu ORDER BY d.file, d.line, d.name, t.main_file')

# (name, fact, detail, count) from a.m's expansions. b.m's have none: the
# declarations SDK_MAX makes in FIRST_ONLY's argument are not FIRST_ONLY's.
EXPECTED_AST_FACTS = [
    ('GETTER', 'declaration', 'get_x', 1),
    ('SEND_LOG', 'send', 'log:', 1),
    ('CALL', 'send', 'ping [argument]', 1),
    ('SELF_COUNT', 'ivar', '_count', 2),
    ('SELF_COUNT', 'self', 'written', 1),
    ('TWICE', 'expands', 'SQUARE', 1),
    ('ITNonnilLock', 'expands', 'ITBetaAssert', 1),
    ('ITNonnilLock', 'expands', 'nil', 1),
    ('DEFINE_GETTER', 'expands', 'LIMIT', 1),
    ('DEFINE_GETTER', 'method', '+[User limit] definition', 1),
    ('DECLARE_CLASS', 'class', '@interface Declared', 1),
    ('LEAKY', 'declaration', 'gThing_storage', 1),
    ('RUN_BLOCK', 'block', '', 1),
    ('SETTER_FOR', 'self', 'written', 1),
    ('SETTER_FOR', 'send', 'setFoo: [pasted]', 1),
    # It spells the class's name; the @implementation is written in the file.
    ('USER_CLASS', 'names-class', '@implementation User(Named)', 1),
    ('PING_SELECTOR', 'selector', 'ping', 1),
    ('CMD_NAME', 'cmd', '', 1),
]
AST_SQL = ('SELECT f.name, f.fact, f.detail, f.count FROM macro_ast_fact f JOIN tu t ON t.id = f.tu '
           'WHERE t.main_file = ? ORDER BY f.def_line, f.fact, f.detail')


# (main, name, def_file, def_line, nesting, parent, outer_name, outer_line,
#  outer_col, args, enclosing, file, line, col)
def exp(name, line, col, defline, args=None, nesting='none', parent=None, outer=None, oline=None, ocol=None,
        enclosing=RUN, main=A, deffile=H):
    return (main, name, deffile, defline, nesting, parent, outer or name, oline or line, ocol or col,
            json.dumps(args, separators=(',', ':'), ensure_ascii=False) if args is not None else None, enclosing, main, line, col)


EXPECTED_EXPANSIONS = sorted([
    exp('LEAKY', 4, 1, 29, ['gThing'], enclosing=None),
    exp('DECLARE_CLASS', 5, 1, 27, ['Declared'], enclosing=None),
    # The macro defines the method, so the method does not enclose it.
    exp('DEFINE_GETTER', 11, 1, 26, ['limit'], enclosing=None),
    exp('LIMIT', 11, 1, 5, nesting='body', parent='DEFINE_GETTER', outer='DEFINE_GETTER', enclosing=None),
    exp('NOT_RETAINED', 14, 26, 28),
    exp('SQUARE', 15, 13, 6, ['LIMIT']),
    exp('LIMIT', 15, 20, 5, nesting='argument', outer='SQUARE', oline=15, ocol=13),
    exp('TWICE', 16, 13, 17, ['LIMIT']),
    exp('SQUARE', 16, 13, 6, ['10'], nesting='body', parent='TWICE', outer='TWICE'),
    exp('LIMIT', 16, 19, 5, nesting='argument', outer='TWICE', oline=16, ocol=13),
    exp('SQUARE', 17, 13, 6, ['SQUARE(2)']),
    exp('SQUARE', 17, 20, 6, ['2'], nesting='argument', outer='SQUARE', oline=17, ocol=13),
    exp('LOGF', 18, 5, 7, ['"%d"', 'a']),
    exp('NAME_OF', 19, 21, 8, ['peer']),
    exp('GETTER', 20, 9, 9, ['x']),
    exp('SEND_LOG', 21, 5, 10, ['peer', 'n']),
    exp('CALL', 22, 5, 11, ['peer', 'ping']),
    exp('SELF_COUNT', 23, 13, 12),
    exp('RETURN_IF', 24, 5, 13, ['a > 100']),
    exp('LOOP_BREAK', 25, 5, 14),
    exp('WHERE', 26, 22, 16),
    exp('ITNonnilLock', 27, 19, 19, ['[peer lockObject]']),
    exp('ITBetaAssert', 27, 19, 18, ['it_nonnilLock_ != nil', '@"@synchronized(%s) at %s:%d has a nil lock and runs '
                                     'unprotected", "[peer lockObject]", __FILE__, __LINE__'],
        nesting='body', parent='ITNonnilLock', outer='ITNonnilLock'),
    exp('nil', 27, 19, 14, nesting='body', parent='ITNonnilLock', outer='ITNonnilLock', deffile=G),
    exp('AS_TYPE', 28, 18, 30, ['int', 'b']),
    exp('FIRST_ONLY', 28, 36, 31, ['c', 's']),
    exp('RUN_BLOCK', 30, 25, 32, ['_count++']),
    exp('LOCKED', 31, 5, 33, ['peer', '_count = 0']),
    exp('SETTER_FOR', 32, 5, 34, ['Foo']),
    exp('PING_SELECTOR', 35, 14, 57),
    exp('CMD_NAME', 36, 14, 58),
    exp('ESCAPE_BREAK', 38, 16, 15),
    exp('KIND', 40, 12, 39),
    exp('LOCAL', 40, 19, 3, deffile=A),
    exp('REDEFINED', 40, 56, 37),
    exp('USER_CLASS', 44, 17, 43, deffile=A, enclosing=None),
    exp('KIND', 5, 12, 41, main=B, enclosing='BValue'),
    exp('LOCAL', 5, 19, 3, main=B, enclosing='BValue', deffile=B),
    exp('FIRST_ONLY', 13, 12, 31, ['SDK_MAX(x, y)', '0'], main=B, enclosing='BMax'),
], key=lambda r: (r[0], r[12], r[13], r[1]))
EXPANSION_SQL = ('SELECT t.main_file, x.name, x.def_file, x.def_line, x.nesting, x.parent_name, x.outer_name, '
                 'x.outer_line, x.outer_col, x.args, x.enclosing_name, x.file, x.line, x.col FROM macro_expansion x '
                 'JOIN tu t ON t.id = x.tu ORDER BY t.main_file, x.line, x.col, x.name')

# (main, file, line, directive, condition, chain_line, value, include_guard)
EXPECTED_CONDITIONS = sorted([
    (A, G, 2, 'ifndef', 'MBASE_H', 2, 'true', 1),
    (A, H, 38, 'if', 'MODE == 1', 38, 'true', 0),
    (B, H, 38, 'if', 'MODE == 1', 38, 'false', 0),
    (A, H, 40, 'elif', 'MODE == 2', 38, 'not-evaluated', 0),
    (B, H, 40, 'elif', 'MODE == 2', 38, 'true', 0),
    # a.m skips from the #elif to the #endif, so it has no #else row.
    (B, H, 42, 'else', None, 38, 'false', 0),
    (A, H, 45, 'if', '0', 45, 'false', 0),
    (B, H, 45, 'if', '0', 45, 'false', 0),
    (A, H, 48, 'if', '__has_include(<sdkmacros.h>)', 48, 'true', 0),
    (B, H, 48, 'if', '__has_include(<sdkmacros.h>)', 48, 'true', 0),
    (A, H, 51, 'if', '__has_include("missing_header.h")', 51, 'false', 0),
    (B, H, 51, 'if', '__has_include("missing_header.h")', 51, 'false', 0),
    (A, H, 54, 'ifdef', 'MODE', 54, 'true', 0),
    (B, H, 54, 'ifdef', 'MODE', 54, 'true', 0),
    (B, B, 7, 'if', '0', 7, 'false', 0),
], key=lambda r: (r[1], r[2], r[0]))
CONDITION_SQL = ('SELECT t.main_file, c.file, c.line, c.directive, c.condition, c.chain_line, c.value, '
                 'c.include_guard FROM pp_condition c JOIN tu t ON t.id = c.tu ORDER BY c.file, c.line, t.main_file')

# (main, file, start, end, directive, condition, chain_line, include_guard)
EXPECTED_SKIPPED = sorted([
    (B, H, 38, 40, 'if', 'MODE == 1', 38, 0),
    (A, H, 40, 44, 'elif', 'MODE == 2', 38, 0),
    (B, H, 42, 44, 'else', None, 38, 0),
    (A, H, 45, 47, 'if', '0', 45, 0),
    (B, H, 45, 47, 'if', '0', 45, 0),
    (A, H, 51, 53, 'if', '__has_include("missing_header.h")', 51, 0),
    (B, H, 51, 53, 'if', '__has_include("missing_header.h")', 51, 0),
    (B, B, 7, 9, 'if', '0', 7, 0),
], key=lambda r: (r[1], r[2], r[0]))
SKIPPED_SQL = ('SELECT t.main_file, s.file, s.start_line, s.end_line, s.directive, s.condition, s.chain_line, '
               's.include_guard FROM pp_skipped s JOIN tu t ON t.id = s.tu ORDER BY s.file, s.start_line, '
               't.main_file')


class MacroTablesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_macro_root()
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb)
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)
        cls.db = cls.paths.db

    def query(self, fn, *args, **kwargs):
        out = io.StringIO()
        status = fn(self.paths, *args, out=out, **kwargs)
        return status, out.getvalue()

    def test_clean_update(self):
        self.assertEqual(self.status, 0, '\n'.join(self.log))

    def test_every_definition_exactly(self):
        self.assertEqual(rows(self.db, DEF_SQL), EXPECTED_DEFS)

    def test_definition_details(self):
        detail = dict(rows(self.db, "SELECT name, fact_detail FROM macro_def d JOIN tu t ON t.id = d.tu WHERE "
                                    "t.main_file = ?", (A,)))
        self.assertEqual(json.loads(detail['ITNonnilLock']),
                         {'file-line': ['__FILE__', '__LINE__'], 'stringify': ['lockExpression'],
                          'uses-macro': ['ITBetaAssert', 'nil']})
        self.assertEqual(json.loads(detail['AS_TYPE']),
                         {'multiple-evaluation': ['T'], 'type-parameter': ['T (cast)', 'T (sizeof)']})
        self.assertEqual(json.loads(detail['SETTER_FOR']),
                         {'paste': ['set##Name'], 'unevaluated-parameter': ['Name']})
        self.assertEqual(json.loads(detail['WHERE']), {'file-line': ['__FILE__', '__LINE__', '__func__']})

    def test_digest_previous_and_scope(self):
        got = rows(self.db, "SELECT DISTINCT name, line, previous_def, in_migration_scope, body_truncated, "
                            "length(body_digest) FROM macro_def WHERE name IN ('REDEFINED', 'LIMIT') ORDER BY line")
        # After an #undef there is no previous definition.
        self.assertEqual(got, [('LIMIT', 5, None, 1, 0, 16), ('REDEFINED', 35, None, 1, 0, 16),
                               ('REDEFINED', 37, None, 1, 0, 16)])
        # The same definition in two views has one digest.
        self.assertEqual(rows(self.db, "SELECT count(DISTINCT body_digest), count(DISTINCT view) FROM macro_def "
                                       "WHERE name = 'SQUARE'"), [(1, 2)])
        self.assertEqual(rows(self.db, "SELECT count(DISTINCT body_digest) FROM macro_def WHERE name = 'KIND'"),
                         [(2,)])

    def test_undef(self):
        self.assertEqual(rows(self.db, 'SELECT t.main_file, u.name, u.def_file, u.def_line, u.file, u.line, u.col, '
                                       'u.in_migration_scope FROM macro_undef u JOIN tu t ON t.id = u.tu ORDER BY '
                                       't.main_file'),
                         [(A, 'REDEFINED', H, 35, H, 36, 8, 1), (B, 'REDEFINED', H, 35, H, 36, 8, 1)])

    def test_ast_facts_exactly(self):
        self.assertEqual(rows(self.db, AST_SQL, (A,)), EXPECTED_AST_FACTS)
        self.assertEqual(rows(self.db, AST_SQL, (B,)), [])

    def test_every_expansion_exactly(self):
        self.assertEqual(rows(self.db, EXPANSION_SQL), EXPECTED_EXPANSIONS)

    def test_expansion_in_condition(self):
        # MODE is defined on the command line, so its uses in #if are counted,
        # not listed.
        self.assertEqual(rows(self.db, 'SELECT count(*) FROM macro_expansion WHERE in_condition = 1'), [(0,)])

    def test_join_key_of_rows_in_macros(self):
        # Every row made in a repository macro joins its outermost expansion
        # by file, expansion_line and expansion_col.
        for table in ('send', 'selector_ref', 'ivar_ref'):
            got = rows(self.db, "SELECT r.macro_name, (SELECT group_concat(DISTINCT x.outer_name) FROM "
                                "macro_expansion x WHERE x.file = r.file AND x.outer_line = r.expansion_line AND "
                                "x.outer_col = r.expansion_col) FROM %s r WHERE r.macro_role IS NOT NULL AND "
                                "r.macro_file NOT LIKE '/%%'" % table)
            self.assertTrue(got, table)
            for macro, joined in got:
                self.assertEqual(macro, joined, table)

    def test_use_counts_of_macros_outside_the_repository(self):
        got = rows(self.db, 'SELECT t.main_file, u.name, u.def_line, u.count, u.file, u.in_migration_scope FROM '
                            'macro_use_count u JOIN tu t ON t.id = u.tu ORDER BY t.main_file, u.file, u.name')
        self.assertEqual(got, [(A, 'SDK_MIN', 2, 1, A, 1), (A, 'SDK_PING', 3, 1, A, 1),
                               (A, 'MODE', 0, 1, H, 1), (B, 'SDK_MAX', 6, 1, B, 1), (B, 'MODE', 0, 2, H, 1)])
        self.assertEqual(rows(self.db, "SELECT DISTINCT def_file FROM macro_use_count WHERE name = 'MODE'"),
                         [('<built-in>',)])
        self.assertTrue(rows(self.db, "SELECT def_file FROM macro_use_count WHERE name = 'SDK_MIN'")[0][0].endswith(
            '/outside/sdkmacros.h'))

    def test_every_condition_exactly(self):
        self.assertEqual(rows(self.db, CONDITION_SQL), EXPECTED_CONDITIONS)

    def test_every_skipped_range_exactly(self):
        self.assertEqual(rows(self.db, SKIPPED_SQL), EXPECTED_SKIPPED)

    def test_views_match_tu_input(self):
        # Every row's view is its unit's view of the file.
        for table in ('macro_def', 'macro_expansion', 'pp_condition', 'pp_skipped'):
            self.assertEqual(rows(self.db, 'SELECT count(*) FROM %s r WHERE NOT EXISTS (SELECT 1 FROM tu_input i '
                                           'WHERE i.tu = r.tu AND i.path = r.file AND i.view = r.view)' % table),
                             [(0,)], table)

    # --- queries ---

    def test_macros_by_name_conflict(self):
        status, text = self.query(codedb.macros, name='KIND')
        self.assertEqual(status, 0)
        body, _ = split(text)
        self.assertEqual(body[0], 'Macro definitions named KIND: 2')
        self.assertIn('    CONFLICT: units see different definitions of KIND (2 bodies): sources/macros.h:39 (targets '
                      'T, 1 units); sources/macros.h:41 (targets T, 1 units)', body)
        # The #else branch no unit compiles is found as text.
        self.assertIn('definitions in code that no unit compiles (ranges every unit skips, searched as text): 1:', body)
        self.assertIn('  sources/macros.h:43  #define KIND 3', body)

    def test_macros_redefinition_is_not_a_conflict(self):
        status, text = self.query(codedb.macros, name='REDEFINED')
        body, _ = split(text)
        self.assertIn('    redefined: 2 definitions with different bodies, seen by the same units in turn: '
                      'sources/macros.h:35 (targets T, 2 units); sources/macros.h:37 (targets T, 2 units)', body)
        self.assertIn('    undefined at: sources/macros.h:36', body)
        self.assertFalse([line for line in body if 'CONFLICT' in line])

    def test_macros_conflict_across_files(self):
        _, text = self.query(codedb.macros, name='LOCAL')
        self.assertIn('CONFLICT: units see different definitions of LOCAL (2 bodies): sources/a.m:3 (targets T, 1 '
                      'units); sources/b.m:3 (targets T, 1 units)', text)

    def test_macros_by_kind(self):
        status, text = self.query(codedb.macros, cls='send')
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertEqual(body[0], 'Macro definitions of kind send (sends a message): 4')
        self.assertEqual([line.split('  ')[1] for line in body if line.startswith('sources/')],
                         ['#define SEND_LOG(obj, text)', '#define CALL(obj, sel)', '#define SETTER_FOR(Name)',
                          '#define BLOCK_OF(x)'])
        self.assertIn('    facts from the AST of its expansions: self (written); send (setFoo: [pasted])', body)

    def test_macros_by_file(self):
        status, text = self.query(codedb.macros, file=G)
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertEqual(body[:2], ['Macro definitions in sources/mbase.h: 2',
                                    'sources/mbase.h:3:9  #define MBASE_H  kinds: none of the kinds in '
                                    'hidden-callers.md section 6  targets T'])
        status, text = self.query(codedb.macros, file='sources/nothing.h')
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE: no unit in this database reads sources/nothing.h', text)

    def test_macros_unknown_kind_is_an_error(self):
        with self.assertRaises(codedb.CodeDBError):
            self.query(codedb.macros, cls='nonsense')

    def test_macrouses_of_a_macro(self):
        status, text = self.query(codedb.macrouses, 'LIMIT')
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertEqual(body[:4], [
            'Expansions of LIMIT: 3',
            'sources/a.m:11:1  (file scope)  made by the body of DEFINE_GETTER (outermost DEFINE_GETTER at 11:1)  '
            'targets T',
            'sources/a.m:15:20  -[User run:]  in an argument of SQUARE at 15:13  targets T',
            'sources/a.m:16:19  -[User run:]  in an argument of TWICE at 16:13  targets T'])

    def test_macrouses_of_a_macro_outside_the_repository(self):
        status, text = self.query(codedb.macrouses, 'SDK_MIN')
        self.assertEqual(status, 0)
        self.assertIn('  sources/a.m: 1', text)
        self.assertIn('is defined outside the repository', text)

    def test_macrouses_of_a_method_and_a_class(self):
        status, text = self.query(codedb.macrouses, RUN)
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertEqual(body[0], 'Macro expansions in the method -[User run:]: 31')
        self.assertIn('  SETTER_FOR (sources/macros.h:34): 1 sites; kinds: send, paste', body)
        self.assertIn('  SQUARE (sources/macros.h:6): 4 sites; kinds: none', body)
        status, text = self.query(codedb.macrouses, 'User')
        self.assertIn('  DEFINE_GETTER (sources/macros.h:26) makes +[User limit] definition', text)
        status, text = self.query(codedb.macrouses, '+[User limit]')
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertIn('  DEFINE_GETTER (sources/macros.h:26) makes +[User limit] definition', body)
        status, text = self.query(codedb.macrouses, 'BValue')
        self.assertEqual(split(text)[0][0], 'Macro expansions in the function BValue: 2')

    def test_skipped(self):
        status, text = self.query(codedb.skipped, H)
        body, _ = split(text)
        self.assertEqual(status, 0)
        self.assertEqual(body[:6], [
            'Ranges of sources/macros.h not compiled in some or all units: 5',
            'sources/macros.h:39-39  skipped in 1 of 2 units, compiled in the others (targets T)  by #if MODE == 1 '
            'at 38  targets T',
            'sources/macros.h:41-42  skipped in 1 of 2 units, compiled in the others (targets T)  by #elif MODE == 2 '
            'at 40  targets T',
            'sources/macros.h:43-43  skipped in every unit that reads it (2)  by #elif MODE == 2 at 40; #else at 42 '
            'of #if MODE == 1 at 38  targets T',
            'sources/macros.h:46-46  skipped in every unit that reads it (2)  by #if 0 at 45  targets T',
            'sources/macros.h:52-52  skipped in every unit that reads it (2)  by #if '
            '__has_include("missing_header.h") at 51  targets T'])
        self.assertIn('  38: #if MODE == 1: false in 1 units; true in 1 units', body)

    def test_skipped_header_guard_is_not_listed(self):
        status, text = self.query(codedb.skipped, G)
        body, _ = split(text)
        self.assertEqual(status, 1)
        self.assertEqual(body[0], 'Ranges of sources/mbase.h not compiled in some or all units: 0')
        self.assertIn('include guard (not listed): #ifndef MBASE_H at 2', body)

    def test_reach_searches_code_no_unit_compiles(self):
        status, text = self.query(codedb.reach, 'hiddenSelector')
        self.assertEqual(status, 3)
        self.assertIn('a text search of them for hiddenSelector finds 1 lines (possible references):\n'
                      '  sources/b.m:8  in a range no unit compiles: void Hidden(MRoot *r) { [r hiddenSelector]; [r ping]; }\n',
                      text)
        self.assertIn('INCOMPLETE: no rows, but code that no unit compiles mentions the name (text matches: 1', text)
        # With rows, a match does not make the answer incomplete.
        status, text = self.query(codedb.reach, 'ping')
        self.assertEqual(status, 0)
        self.assertIn('a text search of them for ping finds 1 lines (possible references):', text)
        self.assertIn('Objective-C code that is not compiled: 4 ranges in 2 files are skipped by every unit that reads '
                      'them', text)

    def test_ivars_searches_code_no_unit_compiles(self):
        status, text = self.query(codedb.ivars, 'User')
        self.assertEqual(status, 0)
        self.assertIn('a text search of them for User, _count finds 0 lines', text)


class MacroLintTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_macro_root()
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb)
        cls.status = codedb.update(cls.paths, log=lambda m: None)
        cls.tsv = os.path.join(os.path.dirname(cls.root), 'classification.tsv')

    def lint(self, **kwargs):
        out = io.StringIO()
        status = codedb.macrolint(self.paths, classification=self.tsv, out=out, **kwargs)
        return status, out.getvalue()

    def setUp(self):
        if os.path.exists(self.tsv):
            os.remove(self.tsv)

    def written(self):
        self.lint(write=True)
        return codedb.read_classification(self.tsv)

    def test_write_lists_every_macro_of_a_kind(self):
        got = [(r['name'], r['classes'], r['reading']) for r in self.written()]
        self.assertEqual(got, [
            ('BLOCK_OF', 'send,control-flow', 'UNREVIEWED'), ('CALL', 'send', 'UNREVIEWED'), ('CMD_NAME', 'context', 'UNREVIEWED'),
            ('DECLARE_CLASS', 'class', 'UNREVIEWED'), ('DEFINE_GETTER', 'control-flow,method', 'UNREVIEWED'),
            ('ESCAPE_BREAK', 'control-flow', 'UNREVIEWED'), ('GETTER', 'paste', 'UNREVIEWED'),
            ('ITNonnilLock', 'stringify,context', 'UNREVIEWED'), ('LEAKY', 'paste', 'UNREVIEWED'),
            ('LOOP_BREAK', 'control-flow', 'UNREVIEWED'),
            ('NAME_OF', 'stringify', 'UNREVIEWED'), ('NOT_RETAINED', 'method-family', 'UNREVIEWED'),
            ('RETURN_IF', 'control-flow', 'UNREVIEWED'), ('SEND_LOG', 'send', 'UNREVIEWED'),
            ('SETTER_FOR', 'send,paste', 'UNREVIEWED'), ('WHERE', 'context', 'UNREVIEWED')])

    def test_every_macro_in_scope_is_classified_or_listed(self):
        listed = set((r['name'], r['file'], r['digest']) for r in self.written())
        q = codedb.QueryContext(self.paths, codedb.MACROS_SPEC)
        try:
            subjects = codedb.lint_subjects(q)
        finally:
            q.close()
        self.assertEqual(len(subjects), 38)
        for d, classes, _ in subjects:
            self.assertTrue(not classes or (d.name, d.file, d.digest) in listed, d.name)

    def test_unreviewed_fails_unless_allowed(self):
        self.written()
        status, text = self.lint()
        self.assertEqual(status, 1)
        self.assertIn('registered and UNREVIEWED (nobody has read it yet): 16 (fails the lint', text)
        status, _ = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 0)

    def rewrite(self, edit):
        with open(self.tsv) as f:
            lines = f.read().split('\n')
        with open(self.tsv, 'w') as f:
            f.write('\n'.join(edit(lines)))

    def test_read_rows_pass(self):
        self.written()
        self.rewrite(lambda lines: [l.replace('\tUNREVIEWED', '\tread: expands to a send') for l in lines])
        status, text = self.lint()
        self.assertEqual(status, 0, text)
        # A rewrite keeps each reading whose digest is unchanged.
        self.lint(write=True)
        self.assertEqual(set(r['reading'] for r in codedb.read_classification(self.tsv)),
                         {'read: expands to a send'})

    def test_missing_row_fails(self):
        self.written()
        self.rewrite(lambda lines: [l for l in lines if not l.startswith('CALL\t')])
        status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 1)
        self.assertIn('NOT REGISTERED (add a row: codedb.py macrolint --write, then read it): 1\n'
                      '  CALL sources/macros.h:11  kinds send\n', text)

    def test_changed_definition_fails(self):
        self.written()
        self.rewrite(lambda lines: [l.replace(l.split('\t')[3], '0' * 16) if l.startswith('WHERE\t') else l
                                    for l in lines])
        status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 1)
        self.assertIn('DEFINITION CHANGED since it was registered', text)
        self.assertIn('  WHERE sources/macros.h:16  kinds context\n', text)
        self.assertNotIn('NO LONGER', text)

    def test_row_for_a_macro_that_is_gone_fails(self):
        self.written()
        self.rewrite(lambda lines: lines + ['GONE\tsources/macros.h\t99\t%s\tsend\tsend\tread' % ('1' * 16)])
        status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 1)
        self.assertIn('NO LONGER A MACRO OF THESE KINDS IN SCOPE (remove the row: codedb.py macrolint --write --prune, '
                      'on a complete database): 1\n  GONE sources/macros.h', text)

    def test_changed_kinds_fail(self):
        self.written()
        self.rewrite(lambda lines: [l.replace('\tsend,paste\t', '\tsend\t') for l in lines])
        status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 1)
        self.assertIn('  SETTER_FOR sources/macros.h:34  kinds now send,paste, registered send\n', text)

    def test_moved_definition_is_reported_without_failing(self):
        # A comment added above a macro moves its definition; the reading
        # still holds (same digest), but the row's line no longer names it.
        self.written()
        self.rewrite(lambda lines: [l.replace('\tsources/macros.h\t16\t', '\tsources/macros.h\t12\t')
                                    if l.startswith('WHERE\t') else l for l in lines])
        status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 0, text)
        self.assertIn('LINE MOVED (the definition is now at another line; not a failure: codedb.py macrolint --write '
                      'updates the line and keeps the reading): 1\n  WHERE sources/macros.h: row line 12, '
                      'definition line 16\n', text)
        self.lint(write=True)
        status, text = self.lint(allow_unreviewed=True)
        self.assertNotIn('LINE MOVED', text)

    def test_identical_redefinition_is_not_a_moved_line(self):
        # DEFINE_BOOL in iTermAdvancedSettingsModel.m is defined twice with
        # the same tokens: one row (one digest) for two definitions, whose
        # line is the first one's.
        real = codedb.lint_subjects

        def with_redefinition(q):
            subjects = real(q)
            extra = [(d._replace(line=d.line + 3), classes, words) for d, classes, words in subjects
                     if d.name == 'WHERE']
            return subjects + extra
        with mock.patch.object(codedb, 'lint_subjects', with_redefinition):
            self.written()
            status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 0, text)
        self.assertNotIn('LINE MOVED', text)
        # One row, so one unread row, not two.
        self.assertIn('registered and UNREVIEWED (nobody has read it yet): 16\n', text)

    def test_bad_file_is_an_error(self):
        with open(self.tsv, 'w') as f:
            f.write('just one field\n')
        with self.assertRaises(codedb.CodeDBError):
            self.lint()

    def edited_header(self):
        """A context in which macros.h has changed since the database was
        made, so that the database is incomplete."""
        test = self

        class Edited:
            def __enter__(self):
                with open(os.path.join(test.root, H), 'a') as f:
                    f.write('// edited\n')

            def __exit__(self, *exc):
                with open(os.path.join(test.root, H)) as f:
                    content = f.read()
                with open(os.path.join(test.root, H), 'w') as f:
                    f.write(content[:-len('// edited\n')])
        return Edited()

    def test_incomplete_database(self):
        self.written()
        with self.edited_header():
            status, text = self.lint(allow_unreviewed=True)
        # No failure found, but the answer may be incomplete.
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE:', text)

    def test_failure_in_an_incomplete_database_fails(self):
        # A gate must tell a failure from a pass: a failure found is exit 1
        # even when the database is incomplete, and both are said.
        self.written()
        self.rewrite(lambda lines: [l for l in lines if not l.startswith('CALL\t')])
        with self.edited_header():
            status, text = self.lint(allow_unreviewed=True)
        self.assertEqual(status, 1, text)
        self.assertIn('NOT REGISTERED', text)
        self.assertIn('INCOMPLETE:', text)
        self.assertIn('failures found (1); the database is also incomplete', text)

    def test_write_resets_the_reading_when_the_digest_changes(self):
        self.written()
        self.rewrite(lambda lines: [l.replace('\tUNREVIEWED', '\tread') for l in lines])
        self.rewrite(lambda lines: [l.replace(l.split('\t')[3], '0' * 16) if l.startswith('WHERE\t') else l
                                    for l in lines])
        self.lint(write=True)
        got = dict((r['name'], (r['digest'], r['reading'])) for r in codedb.read_classification(self.tsv))
        self.assertEqual(got['WHERE'][1], 'UNREVIEWED')
        self.assertNotEqual(got['WHERE'][0], '0' * 16)
        self.assertEqual(got['CALL'][1], 'read')
        self.assertEqual(sum(1 for r in codedb.read_classification(self.tsv) if r['name'] == 'WHERE'), 1)

    def test_write_keeps_rows_it_did_not_see_unless_pruned(self):
        self.written()
        gone = 'GONE\tsources/macros.h\t99\t%s\tsend\tsend\tread: a reading' % ('1' * 16)
        self.rewrite(lambda lines: lines + [gone])
        status, text = self.lint(write=True, allow_unreviewed=True)
        got = [r for r in codedb.read_classification(self.tsv) if r['name'] == 'GONE']
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]['reading'], 'read: a reading')
        self.assertTrue(got[0]['facts'].startswith(codedb.NOT_SEEN_MARK), got[0])
        self.assertEqual(status, 1)
        self.assertIn('kept 1 rows not seen in this run', text)
        # Kept again unchanged by a second write.
        self.lint(write=True)
        self.assertEqual(sum(1 for r in codedb.read_classification(self.tsv) if r['name'] == 'GONE'), 1)
        status, text = self.lint(write=True, prune=True, allow_unreviewed=True)
        self.assertEqual(status, 0, text)
        self.assertEqual([r for r in codedb.read_classification(self.tsv) if r['name'] == 'GONE'], [])

    def test_prune_is_refused_on_an_incomplete_database(self):
        self.written()
        with self.edited_header():
            with self.assertRaises(codedb.CodeDBError):
                self.lint(write=True, prune=True)

    def test_coverage_is_stated_and_uncompiled_definitions_listed(self):
        self.written()
        _, text = self.lint(allow_unreviewed=True)
        self.assertIn(codedb.LINT_COVERAGE_TEXT, text)
        # KIND 3 is in the #else neither MODE takes; NEVER under #if 0;
        # HAS_MISSING under a __has_include that is false.
        self.assertIn('#define in code that no captured unit compiles (not failures; read them by hand): 3\n'
                      '  sources/macros.h:43  in a range every unit skips: #define KIND 3\n'
                      '  sources/macros.h:46  in a range every unit skips: #define NEVER 1\n'
                      '  sources/macros.h:52  in a range every unit skips: #define HAS_MISSING 1\n', text)

    def test_checked_in_classification_file_parses(self):
        path = os.path.join(base.REPO, codedb.CLASSIFICATION_FILE)
        if not os.path.exists(path):
            self.skipTest('no classification file checked in')
        got = codedb.read_classification(path)
        self.assertTrue(got)
        for r in got:
            self.assertEqual(len(r['digest']), 16)
            kinds = [codedb.parse_kind_label(k)[0] for k in r['classes'].split(',')]
            self.assertTrue(set(kinds) <= set(codedb.MACRO_CLASSES), r)


# A fixture of its own for kinds that come through the macros a macro
# expands: wrappers, a cycle, a wrapper of a macro from outside the
# repository, and a send only the AST sees.
CLOSURE_FILES = {
    'sources/w.h': (
        '#pragma once\n'
        '#import <wsdk.h>\n'
        '__attribute__((objc_root_class))\n'
        '@interface WRoot\n'
        '- (void)ping;\n'
        '- (int)count;\n'
        '@end\n'
        '#define W_SEND(o) [o ping]\n'
        '#define W_ONE(o) W_SEND(o)\n'
        '#define W_TWO(o) W_ONE(o)\n'
        '#define W_TWO_UNUSED(o) W_ONE(o)\n'
        '#define W_FORWARD(o) W_LATER(o)\n'
        '#define W_LATER(o) [o ping]\n'
        '#define CYC_A(o) CYC_B(o)\n'
        '#define CYC_B(o) [o ping]; CYC_A(o)\n'
        '#define CYC_C CYC_D\n'
        '#define CYC_D CYC_C\n'
        '#define W_SDK(o) WSDK_PING(o)\n'
        '#define W_SDK_CALLED(o) WSDK_PING(o)\n'
        '#define W_DOT(o) ((o).count)\n'
        '#define W_PLAIN(x) ((x) + 1)\n'
        '#define W_STRING "W_SEND(x)"\n'),
    'sources/w.m': (
        '#import "w.h"\n'
        '@implementation WRoot\n'
        '- (void)ping {\n'
        '}\n'
        '- (int)count {\n'
        '    return 0;\n'
        '}\n'
        '- (int)use:(WRoot *)p {\n'
        '    W_TWO(p);\n'
        '    WSDK_PING(p);\n'
        '    W_SDK_CALLED(p);\n'
        '    return W_DOT(p) + W_PLAIN(1);\n'
        '}\n'
        '@end\n'),
}
CLOSURE_OUTSIDE = {'wsdk.h': '#define WSDK_PING(obj) [obj ping]\n'}


class MacroKindClosureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        d = base.make_temp('codedb-closure-')
        cls.root = os.path.join(d, 'repo')
        for path, text in CLOSURE_FILES.items():
            os.makedirs(os.path.dirname(os.path.join(cls.root, path)), exist_ok=True)
            with open(os.path.join(cls.root, path), 'w') as f:
                f.write(text)
        os.makedirs(os.path.join(d, 'outside'))
        for path, text in CLOSURE_OUTSIDE.items():
            with open(os.path.join(d, 'outside', path), 'w') as f:
                f.write(text)
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb, mains=(('sources/w.m', ['-fobjc-arc']),))
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)
        cls.tsv = os.path.join(d, 'classification.tsv')

    def lint(self, **kwargs):
        out = io.StringIO()
        status = codedb.macrolint(self.paths, classification=self.tsv, out=out, **kwargs)
        return status, out.getvalue()

    def classes(self):
        self.lint(write=True)
        return dict((r['name'], r['classes']) for r in codedb.read_classification(self.tsv))

    def test_update(self):
        self.assertEqual(self.status, 0, '\n'.join(self.log))

    def test_wrapper_two_levels_deep(self):
        got = self.classes()
        self.assertEqual(got['W_SEND'], 'send')
        self.assertEqual(got['W_ONE'], 'send (via W_SEND)')
        self.assertEqual(got['W_TWO'], 'send (via W_ONE)')
        # Never expanded: the edge comes from its tokens alone.
        self.assertEqual(got['W_TWO_UNUSED'], 'send (via W_ONE)')
        # A name in the body that is defined only later (the preprocessor
        # expands it at the use).
        self.assertEqual(got['W_FORWARD'], 'send (via W_LATER)')

    def test_cycle(self):
        got = self.classes()
        self.assertEqual(got['CYC_B'], 'send')
        self.assertEqual(got['CYC_A'], 'send (via CYC_B)')
        self.assertNotIn('CYC_C', got)
        self.assertNotIn('CYC_D', got)

    def test_wrapper_of_a_macro_outside_the_repository(self):
        got = self.classes()
        self.assertEqual(got['W_SDK'], 'send (via WSDK_PING)')
        self.assertEqual(got['W_SDK_CALLED'], 'send (via WSDK_PING)')
        _, text = self.lint(allow_unreviewed=True)
        self.assertIn('macros defined outside the repository that send (send rows with macro_role body or pasted '
                      'whose outermost macro is defined outside the repository): 1: WSDK_PING\n', text)

    def test_send_seen_only_in_the_ast(self):
        defs = rows(self.paths.db, "SELECT facts FROM macro_def WHERE name = 'W_DOT'")
        self.assertNotIn('send', defs[0][0].split())
        self.assertEqual(self.classes()['W_DOT'], 'send')

    def test_names_in_strings_are_not_edges(self):
        got = self.classes()
        self.assertNotIn('W_STRING', got)
        self.assertNotIn('W_PLAIN', got)

    def test_lint_counts_inherited_kinds(self):
        self.classes()
        _, text = self.lint(allow_unreviewed=True)
        self.assertIn('of which a kind only through the macros they expand: 7\n', text)

    def test_macros_query_shows_inherited_kinds(self):
        out = io.StringIO()
        codedb.macros(self.paths, name='W_TWO', out=out)
        self.assertIn('kinds: send (via W_ONE)', out.getvalue())
        out = io.StringIO()
        codedb.macros(self.paths, cls='send', out=out)
        self.assertIn('#define W_TWO(o)', out.getvalue())
        self.assertNotIn('#define W_PLAIN(x)', out.getvalue())


GUARD_FILES = {
    # A classic guard, included twice with #include: the second inclusion
    # is not read.
    'sources/g1.h': '#ifndef G1_H\n#define G1_H\nint g1(void);\n#endif\n',
    # #if !defined(X) with a comment before it.
    'sources/g2.h': '// comment\n#if !defined(G2_H)\n#define G2_H\nint g2(void);\n#endif  // G2_H\n',
    # A declaration before the #ifndef: not a guard, and its second
    # inclusion skips a range.
    'sources/g3.h': 'int g3a(void);\n#ifndef G3_H\n#define G3_H\nint g3(void);\n#endif\n',
    # #pragma once: no directive at all.
    'sources/g4.h': '#pragma once\nint g4(void);\n',
    # Code after the #endif: not a guard.
    'sources/g5.h': '#ifndef G5_H\n#define G5_H\nint g5(void);\n#endif\nint g5b(void);\n',
    # The directive after the #ifndef defines another name: not a guard.
    'sources/g6.h': '#ifndef G6_H\n#define G6_OTHER 1\nint g6(void);\n#endif\n',
    'sources/guards.m': ('#include "g1.h"\n#include "g1.h"\n#include "g2.h"\n#include "g3.h"\n#include "g3.h"\n'
                         '#include "g4.h"\n#include "g4.h"\n#include "g5.h"\n#include "g6.h"\n'
                         'int main(void) { return 0; }\n'),
}


class IncludeGuardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        d = base.make_temp('codedb-guards-')
        cls.root = os.path.join(d, 'repo')
        for path, text in GUARD_FILES.items():
            os.makedirs(os.path.dirname(os.path.join(cls.root, path)), exist_ok=True)
            with open(os.path.join(cls.root, path), 'w') as f:
                f.write(text)
        os.makedirs(os.path.join(d, 'outside'))
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb, mains=(('sources/guards.m', []),))
        cls.status = codedb.update(cls.paths, log=lambda m: None)

    def test_guards(self):
        self.assertEqual(self.status, 0)
        self.assertEqual(rows(self.paths.db, 'SELECT file, line, directive, condition, value, include_guard FROM '
                                             'pp_condition ORDER BY file, line'),
                         [('sources/g1.h', 1, 'ifndef', 'G1_H', 'true', 1),
                          ('sources/g2.h', 2, 'if', '!defined(G2_H)', 'true', 1),
                          ('sources/g3.h', 2, 'ifndef', 'G3_H', 'false,true', 0),
                          ('sources/g5.h', 1, 'ifndef', 'G5_H', 'true', 0),
                          ('sources/g6.h', 1, 'ifndef', 'G6_H', 'true', 0)])
        self.assertEqual(rows(self.paths.db, 'SELECT file, start_line, end_line, include_guard FROM pp_skipped'),
                         [('sources/g3.h', 2, 5, 0)])


if __name__ == '__main__':
    unittest.main()
