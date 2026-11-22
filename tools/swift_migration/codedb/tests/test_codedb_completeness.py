#!/usr/bin/env python3
"""Tests that the code database misses no send in parts of the AST that the
default traversal skips or visits in only one of two forms: designated
initializers (the semantic form of an initializer list), the size of a
variable-length array (the type, not only its location), and the other
shapes of the probe fixtures.

Expected rows are written out by hand from the fixtures under
completeness_fixtures/. Where xcrun is available, the per-selector counts
are also checked against an object file that Xcode's Clang compiles from
the same fixture: the compiler is the ground truth of what is sent.
"""

import collections
import io
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import codedb  # noqa: E402
import crosscheck  # noqa: E402
import swiftdb  # noqa: E402
import test_codedb as base  # noqa: E402

FIXTURES = os.path.join(HERE, 'completeness_fixtures')


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def have_xcrun():
    try:
        return subprocess.run(['xcrun', '--find', 'clang'], capture_output=True).returncode == 0
    except OSError:
        return False


def make_root():
    d = base.make_temp('codedb-completeness-')
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURES, root)
    shutil.copytree(os.path.join(HERE, 'completeness_outside'), os.path.join(d, 'outside'))
    return root


def module_args(root, name):
    """Clang arguments of a unit that imports modules: the repository module
    LocalMod and the modules outside the repository OutsideKit (a framework)
    and plainlib."""
    outside = os.path.join(os.path.dirname(root), 'outside')
    return ('-fmodules', '-fmodules-cache-path=' + os.path.join(os.path.dirname(root), 'mc-' + name),
            '-I', os.path.join(root, 'modules', 'LocalMod'), '-F', os.path.join(outside, 'Frameworks'),
            '-I', os.path.join(outside, 'plainlib'))


def extract(root, main, extra=('-fobjc-arc',)):
    db = os.path.join(os.path.dirname(root), os.path.basename(main) + '.sqlite')
    if main.endswith('.mm'):
        extra = tuple(extra) + ('-std=c++17',)
    status, stderr, _ = base.extract(root, main, db, extra=extra)
    return db, status, stderr


def rows(db, sql, args=()):
    con = sqlite3.connect(db)
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


def sends(db):
    return rows(db, 'SELECT selector, line, col, implicit_accessor, enclosing_name FROM send '
                    'ORDER BY line, col, selector')


def send_counts(db):
    return collections.Counter(s for (s,) in rows(db, "SELECT selector FROM send WHERE receiver_kind NOT LIKE "
                                                      "'super%'"))


def object_call_sites(root, main):
    """Per-selector call sites in the object Xcode's Clang compiles."""
    out = os.path.join(os.path.dirname(root), os.path.basename(main) + '.o')
    lang = ['-x', 'objective-c++', '-std=c++17'] if main.endswith('.mm') else []
    subprocess.run(['xcrun', 'clang', '-c', '-arch', 'arm64', '-mmacosx-version-min=13.0', '-fobjc-arc', '-w'] +
                   lang + ['-I', os.path.join(root, 'sources'), os.path.join(root, main), '-o', out],
                   check=True, capture_output=True)
    with open(out, 'rb') as f:
        return crosscheck.read_object(f.read()).call_sites


D = '-[Shape(Designated) designated:]'
C = '-[Shape(Designated) controls:]'

# Every send in designated.m, by hand. implicit_accessor 1: dot syntax.
DESIGNATED = [
    ('sv', 11, 23, 1, D),     # {.c = x.sv}
    ('sv', 12, 28, 1, D),     # {[0] = x.sv}
    ('sv', 13, 24, 1, D),     # {.c = (x.sv)}
    ('sv', 14, 30, 1, D),     # (Outer){.c = x.sv}
    ('other', 15, 23, 1, D),  # {.c = x.other.sv}: the inner getter was always recorded
    ('sv', 15, 29, 1, D),     # ... and the outer one was not
    ('rect', 16, 23, 1, D),   # SRect
    ('range', 17, 24, 1, D),  # SRange
    ('vec', 18, 22, 1, D),    # ext_vector_type
    ('sv', 19, 24, 1, D),     # union
    ('sv', 20, 28, 1, D),     # anonymous structure member
    ('sv', 21, 25, 1, D),     # compound literal as an argument
    # An initializer that a later designator overrides is in the syntactic
    # form only. The compiler does not evaluate it (and warns); a getter there
    # that the syntactic form already converts (here rect, under .origin) is
    # recorded, one that it does not is not.
    ('rect', 22, 26, 1, D),
    ('sv', 22, 46, 1, D),
    ('sv', 25, 23, 1, C),     # with a scalar beside it
    ('iv', 25, 34, 1, C),     # scalar getters were always recorded
    ('explicitPoint', 26, 24, 0, C),
    ('sv', 27, 22, 1, C),     # positional
    ('iv', 28, 28, 1, C),     # nested braces
    ('iv', 29, 23, 1, C),     # conditional operator
    ('sv', 29, 30, 1, C),
    ('sv', 29, 37, 1, C),
]

V = '-[Shape(VLA) arrays:]'
VLA = [
    ('count', 7, 14, 0, V),   # int a[[x count]]
    ('length', 8, 24, 1, V),  # unsigned short b[x.length]
    ('other', 9, 14, 1, V),   # char c[x.other.length]
    ('length', 9, 20, 1, V),
    ('iv', 10, 23, 1, V),     # typedef int Row[x.iv]
]


class DesignatedInitializerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db, cls.status, cls.stderr = extract(cls.root, 'sources/designated.m')

    def test_clean(self):
        self.assertEqual(self.status, 0, self.stderr)

    def test_every_send(self):
        self.assertEqual(sends(self.db), DESIGNATED)

    def test_each_node_once(self):
        # A node both forms share (the receiver x.other, a scalar getter, an
        # explicit send) is reached twice and recorded once.
        self.assertEqual(rows(self.db, 'SELECT selector, line, col, count(*) FROM send GROUP BY selector, line, col '
                                       'HAVING count(*) > 1'), [])

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_against_the_compiler(self):
        expected = collections.Counter(r[0] for r in DESIGNATED)
        # The overridden initializer of line 22 is not evaluated.
        expected['rect'] -= 1
        self.assertEqual(dict(object_call_sites(self.root, 'sources/designated.m')), dict(expected))


class VariableLengthArrayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db, cls.status, cls.stderr = extract(cls.root, 'sources/vla.m')

    def test_clean(self):
        self.assertEqual(self.status, 0, self.stderr)

    def test_every_send(self):
        self.assertEqual(sends(self.db), VLA)

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_against_the_compiler(self):
        self.assertEqual(dict(object_call_sites(self.root, 'sources/vla.m')),
                         dict(collections.Counter(r[0] for r in VLA)))


MOD_H = 'modules/LocalMod/LocalMod.h'


class ModuleHeaderTest(unittest.TestCase):
    """Declarations in a repository header that units read only through a
    Clang module: the deserialized declarations reached no visitor, so the
    header's ivars, methods, properties, statics (and classes) were missing.
    They are recorded once per target and content, by the unit that holds
    the header's claim (decl_source.via_module 1)."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'mod.sqlite')
        cls.results = []
        for main in ('sources/mod_user.m', 'sources/mod_user2.m'):
            cls.results.append(base.extract(cls.root, main, cls.db, extra=module_args(cls.root, 'mod')))

    def test_clean(self):
        for status, stderr, _ in self.results:
            self.assertEqual(status, 0, stderr)

    def test_ivars(self):
        self.assertEqual(rows(self.db, 'SELECT class_name, name, container_kind, file, line FROM objc_ivar ORDER BY '
                                       'line'),
                         [('ModBase', '_count', 'interface', MOD_H, 5),
                          ('ModBase', '_object', 'interface', MOD_H, 6),
                          ('ModChild', '_extra', 'interface', MOD_H, 18)])

    def test_methods(self):
        self.assertEqual(rows(self.db, 'SELECT selector, container_name, container_kind, is_implicit, is_optional, '
                                       'is_definition, file, line FROM objc_method ORDER BY file, line, selector'),
                         [('setSize:', 'ModBase', 'interface', 1, 0, 0, MOD_H, 8),
                          ('size', 'ModBase', 'interface', 1, 0, 0, MOD_H, 8),
                          ('poke', 'ModBase', 'interface', 0, 0, 0, MOD_H, 9),
                          ('make', 'ModBase', 'interface', 0, 0, 0, MOD_H, 10),
                          ('required', 'ModProto', 'protocol', 0, 0, 0, MOD_H, 13),
                          ('optionalOne', 'ModProto', 'protocol', 0, 1, 0, MOD_H, 15),
                          ('catMethod', 'ModBase(ModCat)', 'category', 0, 0, 0, MOD_H, 22),
                          ('required', 'ModChild', 'implementation', 0, 0, 1, 'sources/mod_user.m', 5)])

    def test_properties(self):
        self.assertEqual(rows(self.db, 'SELECT name, container_name, getter_selector, setter_selector, file, line '
                                       'FROM objc_property'),
                         [('size', 'ModBase', 'size', 'setSize:', MOD_H, 8)])

    def test_statics(self):
        self.assertEqual(rows(self.db, 'SELECT name, kind, file, line FROM c_static ORDER BY line'),
                         [('ModGlobal', 'extern', MOD_H, 24), ('ModConstant', 'file-static', MOD_H, 25)])

    def test_classes_and_adoptions(self):
        self.assertEqual(rows(self.db, 'SELECT name, superclass, file, line FROM objc_class ORDER BY line'),
                         [('ModBase', None, MOD_H, 4), ('ModChild', 'ModBase', MOD_H, 17)])
        self.assertEqual(rows(self.db, 'SELECT class_or_category, container_kind, protocol, file, line FROM '
                                       'objc_adoption ORDER BY line'),
                         [('ModChild', 'interface', 'ModProto', MOD_H, 17),
                          ('ModChildProto', 'protocol', 'ModProto', MOD_H, 26)])

    def test_claimed_once(self):
        # The first unit claims the header; the second records none of its
        # rows.
        self.assertEqual(rows(self.db, 'SELECT d.path, d.via_module, d.view, t.main_file FROM decl_source d JOIN tu '
                                       't ON t.id = d.tu WHERE d.path = ?', (MOD_H,)),
                         [(MOD_H, 1, '', 'sources/mod_user.m')])
        self.assertEqual(rows(self.db, 'SELECT DISTINCT t.main_file FROM objc_method m JOIN tu t ON t.id = m.tu '
                                       'WHERE m.file = ?', (MOD_H,)), [('sources/mod_user.m',)])

    def test_reextraction_keeps_the_rows(self):
        db = os.path.join(os.path.dirname(self.root), 'mod-again.sqlite')
        for main in ('sources/mod_user.m', 'sources/mod_user2.m', 'sources/mod_user.m'):
            status, stderr, _ = base.extract(self.root, main, db, extra=module_args(self.root, 'mod'))
            self.assertEqual(status, 0, stderr)
        self.assertEqual(rows(db, 'SELECT count(*) FROM objc_ivar'), [(3,)])
        self.assertEqual(rows(db, 'SELECT count(*) FROM objc_method WHERE file = ?', (MOD_H,)), [(7,)])
        self.assertEqual(codedb.declaration_gaps(sqlite3.connect(db)), [])


OK = 'OutsideKit'
# The claim keys: the module, the deployment target, and objc++ for an
# Objective-C++ unit.
OK13 = OK + ' macosx13.0'
PL13 = 'plainlib macosx13.0'
SDK_METHODS = sorted([
    ('init', 'OKObject', 'class', 0, OK, 0, 0),
    ('new', 'OKObject', 'class', 1, OK, 0, 0),
    ('baseMethod', 'OKBase', 'protocol', 0, OK, 0, 0),
    ('requiredCallback:', 'OKDelegate', 'protocol', 0, OK, 0, 0),
    ('optionalCallback:', 'OKDelegate', 'protocol', 0, OK, 1, 0),
    ('optionalValue', 'OKDelegate', 'protocol', 0, OK, 1, 0),   # readonly: no setter
    ('canBecomeMain', 'OKWindow', 'class', 0, OK, 0, 0),
    ('isVisible', 'OKWindow', 'class', 0, OK, 0, 0),            # getter=
    ('setShown:', 'OKWindow', 'class', 0, OK, 0, 0),            # setter=
    ('shared', 'OKWindow', 'class', 1, OK, 0, 0),               # class property
    ('selectNext:', 'OKWindow', 'class', 0, OK, 0, 1),          # IBAction
    ('plain', 'OKWindow', 'class', 0, OK, 0, 0),
    ('extra', 'OKWindow(OKExtras)', 'category', 0, OK, 0, 0),
    ('plainThing', 'PLThing', 'class', 0, 'plainlib', 0, 0),
])


class SdkTablesTest(unittest.TestCase):
    """Declarations outside the repository: sdk_method, sdk_class and
    sdk_adoption, each module's recorded once by the unit that holds its
    claim; and the repository's classes and adoptions."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'sdk.sqlite')
        cls.results = [base.extract(cls.root, main, cls.db, extra=module_args(cls.root, 'sdk'))
                       for main in ('sources/sdk_user.m', 'sources/sdk_user2.m')]

    def test_clean(self):
        for status, stderr, _ in self.results:
            self.assertEqual(status, 0, stderr)

    def test_sdk_methods(self):
        self.assertEqual(sorted(rows(self.db, 'SELECT selector, container, container_kind, is_class_method, framework, '
                                              'is_optional, is_action FROM sdk_method')), SDK_METHODS)

    def test_sdk_classes_and_adoptions(self):
        self.assertEqual(sorted(rows(self.db, 'SELECT name, superclass, framework FROM sdk_class')),
                         [('OKObject', None, OK), ('OKWindow', 'OKObject', OK), ('PLThing', None, 'plainlib')])
        self.assertEqual(sorted(rows(self.db, 'SELECT container, container_kind, protocol FROM sdk_adoption')),
                         [('OKDelegate', 'protocol', 'OKBase'), ('OKWindow', 'class', 'OKDelegate'),
                          ('OKWindow(OKExtras)', 'category', 'OKBase')])

    def test_repository_class(self):
        self.assertEqual(rows(self.db, 'SELECT name, superclass, file, line FROM objc_class'),
                         [('MyWindow', 'OKWindow', 'sources/sdk_user.m', 5)])
        self.assertEqual(rows(self.db, 'SELECT class_or_category, container_kind, protocol FROM objc_adoption'),
                         [('MyWindow', 'interface', 'OKDelegate')])

    def test_claims(self):
        self.assertEqual(sorted(rows(self.db, 'SELECT c.module, t.main_file FROM sdk_claim c JOIN tu t ON t.id = '
                                              'c.tu')),
                         [(OK13, 'sources/sdk_user.m'), (PL13, 'sources/sdk_user.m')])
        self.assertEqual(sorted(rows(self.db, 'SELECT t.main_file, m.module FROM tu_module m JOIN tu t ON t.id = '
                                              'm.tu')),
                         [('sources/sdk_user.m', OK13), ('sources/sdk_user.m', PL13),
                          ('sources/sdk_user2.m', OK13)])
        self.assertEqual(rows(self.db, 'SELECT DISTINCT tu FROM sdk_method'), rows(
            self.db, "SELECT id FROM tu WHERE main_file = 'sources/sdk_user.m'"))

    def test_gap_when_the_claim_holder_is_gone(self):
        db = os.path.join(os.path.dirname(self.root), 'sdk-gap.sqlite')
        shutil.copy(self.db, db)
        con = sqlite3.connect(db)
        first, second = [r[0] for r in con.execute('SELECT id FROM tu ORDER BY main_file')]
        with con:
            for table in codedb.UNIT_TABLES:
                con.execute('DELETE FROM %s WHERE tu = ?' % table, (first,))
            con.execute('DELETE FROM tu WHERE id = ?', (first,))
        self.assertEqual(codedb.sdk_gaps(con), [(OK13, second)])
        con.close()
        # The second unit extracted again takes the claim.
        status, stderr, _ = base.extract(self.root, 'sources/sdk_user2.m', db, extra=module_args(self.root, 'sdk'))
        self.assertEqual(status, 0, stderr)
        con = sqlite3.connect(db)
        self.assertEqual(codedb.sdk_gaps(con), [])
        self.assertEqual(sorted(r for r in con.execute('SELECT selector, container, container_kind, is_class_method, '
                                                       'framework, is_optional, is_action FROM sdk_method')),
                         [r for r in SDK_METHODS if r[4] == OK])
        con.close()

    def test_reextraction_keeps_one_row_per_declaration(self):
        db = os.path.join(os.path.dirname(self.root), 'sdk-again.sqlite')
        for main in ('sources/sdk_user.m', 'sources/sdk_user2.m', 'sources/sdk_user.m', 'sources/sdk_user2.m'):
            status, stderr, _ = base.extract(self.root, main, db, extra=module_args(self.root, 'sdk'))
            self.assertEqual(status, 0, stderr)
        self.assertEqual(sorted(rows(db, 'SELECT selector, container, container_kind, is_class_method, framework, '
                                         'is_optional, is_action FROM sdk_method')), SDK_METHODS)



def outside_module_args(root, name):
    """Clang arguments of a unit that imports only modules outside the
    repository: no repository module map is on its search paths."""
    outside = os.path.join(os.path.dirname(root), 'outside')
    return ('-fmodules', '-fmodules-cache-path=' + os.path.join(os.path.dirname(root), 'mc-' + name),
            '-F', os.path.join(outside, 'Frameworks'), '-I', os.path.join(outside, 'plainlib'))


class SdkWalkTriggerTest(unittest.TestCase):
    """The walk of the declarations outside the repository is started by an
    unclaimed module outside the repository alone, with no repository module
    file to record, and what is claimed is what was walked."""

    def extract_all(self, name, mains):
        root = make_root()
        db = os.path.join(os.path.dirname(root), name + '.sqlite')
        for main in mains:
            status, stderr, _ = base.extract(root, main, db, extra=outside_module_args(root, name))
            self.assertEqual(status, 0, stderr)
            self.assertEqual(rows(db, "SELECT count(*) FROM tu_input WHERE path LIKE 'modules/%'"), [(0,)])
        return db

    def test_outside_module_alone(self):
        db = self.extract_all('trigger1', ['sources/sdk_user.m'])
        self.assertEqual(sorted(rows(db, 'SELECT name, superclass, framework FROM sdk_class')),
                         [('OKObject', None, OK), ('OKWindow', 'OKObject', OK), ('PLThing', None, 'plainlib')])
        self.assertEqual(sorted(rows(db, 'SELECT selector, container, container_kind, is_class_method, framework, '
                                         'is_optional, is_action FROM sdk_method')), SDK_METHODS)
        self.assertEqual(sorted(m for (m,) in rows(db, 'SELECT module FROM sdk_claim')), [OK13, PL13])

    def test_second_unit_whose_only_new_thing_is_another_outside_module(self):
        db = self.extract_all('trigger2', ['sources/sdk_user2.m', 'sources/sdk_user.m'])
        self.assertEqual(sorted(rows(db, 'SELECT c.module, t.main_file FROM sdk_claim c JOIN tu t ON t.id = c.tu')),
                         [(OK13, 'sources/sdk_user2.m'), (PL13, 'sources/sdk_user.m')])
        self.assertEqual(sorted(rows(db, 'SELECT s.name, t.main_file FROM sdk_class s JOIN tu t ON t.id = s.tu')),
                         [('OKObject', 'sources/sdk_user2.m'), ('OKWindow', 'sources/sdk_user2.m'),
                          ('PLThing', 'sources/sdk_user.m')])
        self.assertEqual(sorted(rows(db, 'SELECT selector, container, container_kind, is_class_method, framework, '
                                         'is_optional, is_action FROM sdk_method')), SDK_METHODS)



class SdkClaimConfigTest(unittest.TestCase):
    """A module's declarations depend on the deployment target and the
    language (availability #if, __cplusplus): the claim is keyed by module,
    deployment target and Objective-C++, so a unit built for another target
    or language walks the module again and records what only it sees."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'config.sqlite')
        cls.results = [base.extract(cls.root, main, cls.db, extra=module_args(cls.root, 'config') + extra)
                       for main, extra in (('sources/sdk_user.m', ()),
                                           ('sources/sdk_user2.m', ('--target=arm64-apple-macos15',)),
                                           ('sources/sdk_user3.mm', ('-std=c++17',)))]

    def test_clean(self):
        for status, stderr, _ in self.results:
            self.assertEqual(status, 0, stderr)

    def test_claims(self):
        self.assertEqual(sorted(rows(self.db, 'SELECT c.module, t.main_file FROM sdk_claim c JOIN tu t ON t.id = '
                                              'c.tu')),
                         [(OK13, 'sources/sdk_user.m'), (OK + ' macosx15.0', 'sources/sdk_user2.m'),
                          (PL13, 'sources/sdk_user.m'), (PL13 + ' objc++', 'sources/sdk_user3.mm')])

    def test_declarations_only_one_configuration_sees(self):
        self.assertEqual(rows(self.db, "SELECT DISTINCT container, module FROM sdk_method WHERE selector = "
                                       "'newInFifteen'"), [('OKWindow(OKExtras)', OK + ' macosx15.0')])
        self.assertEqual(rows(self.db, "SELECT DISTINCT container, module FROM sdk_method WHERE selector = "
                                       "'plainCxxOnly'"), [('PLThing', PL13 + ' objc++')])
        # The declarations every configuration sees are listed once by the
        # queries (DISTINCT).
        self.assertEqual(rows(self.db, "SELECT count(DISTINCT container) FROM sdk_method WHERE selector = 'plain'"),
                         [(1,)])



class ModuleBodyTest(unittest.TestCase):
    """Function bodies in a repository header read only through a module are
    not walked; the extractor counts them (tu.module_bodies_skipped) and
    update warns, so the limit is never a silent miss."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.paths = base.make_paths(cls.root)
        mains = ['sources/body_user.m']
        base.write_project(cls.root, {'T': mains})
        meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(cls.root)}
        args = ('-fmodules', '-fmodules-cache-path=' + os.path.join(os.path.dirname(cls.root), 'mc-body'), '-I',
                os.path.join(cls.root, 'modules', 'BodyMod'))
        with open(cls.paths.cdb, 'w') as f:
            f.write(json.dumps(meta) + '\n')
            for m in mains:
                f.write(json.dumps({'target': 'T', 'file': m, 'directory': cls.root,
                                    'arguments': base.clang_args(cls.root, m, args)}) + '\n')
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)

    def test_counted(self):
        self.assertEqual(self.status, 0, self.log)
        self.assertEqual(rows(self.paths.db, 'SELECT main_file, module_bodies_skipped FROM tu'),
                         [('sources/body_user.m', 1)])

    def test_update_warns(self):
        self.assertIn('warning: 1 function bodies in repository headers that units read only through a module are '
                      'not walked: their sends and references are not in the database (first: sources/body_user.m)',
                      self.log)


class TextualSdkHeaderTest(unittest.TestCase):
    """Headers outside the repository that units include without modules are
    claimed per header: a unit that includes a header no earlier unit
    included records it, although the earlier unit included another header
    of the same library."""

    def test_each_header_recorded_once(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'text.sqlite')
        extra = ('-I', os.path.join(os.path.dirname(root), 'outside', 'textlib'))
        for main in ('sources/text_user.m', 'sources/text_user2.m', 'sources/text_user.m'):
            status, stderr, _ = base.extract(root, main, db, extra=extra)
            self.assertEqual(status, 0, stderr)
        outside = os.path.join(os.path.dirname(root), 'outside', 'textlib')
        self.assertEqual(sorted(rows(db, 'SELECT selector, container, framework, module FROM sdk_method')),
                         [('first', 'TLFirst', 'textlib', 'textual:' + os.path.join(outside, 'TLFirst.h') +
                           ' macosx13.0'),
                          ('second', 'TLSecond', 'textlib', 'textual:' + os.path.join(outside, 'TLSecond.h') +
                           ' macosx13.0')])
        self.assertEqual(sorted(rows(db, 'SELECT name, superclass FROM sdk_class')),
                         [('TLFirst', None), ('TLSecond', 'TLFirst')])


class SdkQueryTest(unittest.TestCase):
    """The queries sdkmethods and classinfo, on a database that codedb.py
    update made from a compile database."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.paths = base.make_paths(cls.root)
        mains = ['sources/sdk_user.m', 'sources/sdk_user2.m']
        base.write_project(cls.root, {'T': mains})
        meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(cls.root)}
        with open(cls.paths.cdb, 'w') as f:
            f.write(json.dumps(meta) + '\n')
            for m in mains:
                f.write(json.dumps({'target': 'T', 'file': m, 'directory': cls.root, 'arguments': base.clang_args(
                    cls.root, m, module_args(cls.root, 'q'))}) + '\n')
        cls.status = codedb.update(cls.paths, log=lambda m: None)

    def query(self, *argv):
        out = io.StringIO()
        fn = {'sdkmethods': codedb.sdkmethods, 'classinfo': codedb.classinfo}[argv[0]]
        status = fn(self.paths, argv[1], out=out)
        return status, out.getvalue().split('\n--- status ---\n')[0]

    def test_update(self):
        self.assertEqual(self.status, 0)

    def test_sdkmethods(self):
        self.assertEqual(self.query('sdkmethods', 'optionalCallback:'),
                         (0, 'Declarations of optionalCallback: outside the repository: 1\n'
                             '  -[OKDelegate optionalCallback:]  in protocol, OutsideKit, optional\n'))
        self.assertEqual(self.query('sdkmethods', 'selectNext:'),
                         (0, 'Declarations of selectNext: outside the repository: 1\n'
                             '  -[OKWindow selectNext:]  in class, OutsideKit, IBAction\n'))
        self.assertEqual(self.query('sdkmethods', 'noSuchSelector')[0], 1)

    def test_classinfo(self):
        self.assertEqual(self.query('classinfo', 'MyWindow'),
                         (0, 'Class MyWindow: repository sources/sdk_user.m:5\n'
                             'superclass chain: MyWindow (repository sources/sdk_user.m:5) -> OKWindow (SDK OutsideKit) '
                             '-> OKObject (SDK OutsideKit)\n'
                             'protocols listed by the class or a superclass (and their categories and extensions): 2\n'
                             '  OKBase  by OKWindow(OKExtras)\n'
                             '  OKDelegate  by MyWindow\n'
                             'protocols inherited through protocols: 0\n'))
        self.assertEqual(self.query('classinfo', 'OKDelegateUser')[0], 1)



class SwiftClassInfoTest(unittest.TestCase):
    """classinfo of a class declared in Swift: objc_class records only
    Objective-C classes, and the Swift tables hold no superclass."""

    @classmethod
    def setUpClass(cls):
        SdkQueryTest.setUpClass.__func__(cls)
        con = sqlite3.connect(cls.paths.db)
        swiftdb.ensure_schema(con)
        with con:
            con.execute("INSERT INTO swift_objc_decl(unit, usr, selector, selector_source, swift_name, class_name, "
                        "kind, is_class_member, file, line, is_private, selector_derived, explicit_name, "
                        "is_override, implicit, in_migration_scope) VALUES(1, 's:4Mod10SwiftThingC3runyyF', 'run', "
                        "'derived', 'run()', 'SwiftThing', 'method', 0, 'sources/Thing.swift', 3, 0, 1, 0, 0, 0, "
                        "1)")
        con.close()

    def test_swift_class(self):
        self.assertEqual(SdkQueryTest.query(self, 'classinfo', 'SwiftThing'),
                         (0, 'Class SwiftThing: declared in Swift: superclass and adoptions are not in this database\n'
                             'superclass chain: SwiftThing (declared in Swift: superclass and adoptions are not in '
                             'this database)\n'
                             'protocols listed by the class or a superclass (and their categories and extensions): 0\n'
                             'protocols inherited through protocols: 0\n'))
        self.assertEqual(SdkQueryTest.query(self, 'classinfo', 'NoSuchClass')[0], 1)


def counts(ones, more=None):
    out = dict((s, 1) for s in ones.split())
    out.update(more or {})
    return out


# The send rows of probes.m per selector (the table of shapes in the
# fixture): each shape sends its own selector.
PROBES_M = counts(
    'i01 i02 i03 i05 i06 i07 i08 i09 i10 i13 m01 m02 m03 m05 m07 m08 m10 m11 m12 m13 m14 m15 m16 m17 m18 m20 m22 '
    'm24 o01 o02 o03 o04 o05 objectAtIndexedSubscript: objectForKeyedSubscript: r01 r02 r03 r04 r05 r07 r08 r09 '
    'r10 r11 r13 r14 r15 r16 r17 r18 r20 s01 setI02: setI03: setI04: setI05: setI10: setI11: setI12: '
    'setObject:atIndexedSubscript: setObject:forKeyedSubscript: setR05:', {'other': 7, 'r06': 2})
# Not recorded, as the compiler does not evaluate them: m06 (sizeof of an
# expression), m09 (@encode), m21 (the operand __builtin_choose_expr does
# not choose), m23 (an association _Generic does not select), r19 (an
# initializer a later designator overrides, unconverted).
# (object, database) where the compiler's call sites differ from the rows:
PROBES_M_DIFFERENCES = {
    # for ... in: the compiler sends it (the fast-enumeration rule).
    'countByEnumeratingWithState:objects:count:': (2, 0),
}
PROBES_MM = counts('i01 m01 m02 m03 m10 m11 m12 r05 r06 r07', {'m04': 1, 'm05': 3, 'm06': 3, 'm07': 3, 'm08': 1,
                                                                'm09': 1})
PROBES_MM_DIFFERENCES = {
    # A default argument: one row where it is written; evaluated at each call
    # that uses it.
    'm04': (2, 1),
    # Templates: a row in the template as written and one per instantiation;
    # the compiler emits the instantiations.
    'm05': (2, 3), 'm06': (2, 3), 'm07': (2, 3),
    # A member of a class template that is never instantiated, and an inline
    # member function that nothing calls: written, never emitted.
    'm08': (0, 1), 'm09': (0, 1),
}


class ProbeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.dbs = {}
        for main in ('sources/probes.m', 'sources/probes.mm'):
            cls.dbs[main] = extract(cls.root, main, extra=('-fobjc-arc', '-fblocks'))

    def test_clean(self):
        for main, (db, status, stderr) in self.dbs.items():
            self.assertEqual(status, 0, stderr)

    def test_send_rows(self):
        self.assertEqual(dict(send_counts(self.dbs['sources/probes.m'][0])), PROBES_M)
        self.assertEqual(dict(send_counts(self.dbs['sources/probes.mm'][0])), PROBES_MM)

    def test_each_node_once(self):
        for main, (db, _, _) in self.dbs.items():
            self.assertEqual(rows(db, 'SELECT selector, line, col, enclosing_usr, count(*) FROM send GROUP BY '
                                      'selector, line, col, enclosing_usr HAVING count(*) > 1'), [], main)

    def test_unevaluated_operands_in_the_state_tables(self):
        # References in an operand that is not evaluated are recorded with the
        # access unevaluated, as in sizeof.
        self.assertEqual(rows(self.dbs['sources/probes.m'][0], "SELECT ivar_name, access FROM ivar_ref WHERE "
                                                               "kind = 'direct' AND ivar_name IN ('_i14', '_i15', '_i16') "
                                                               "ORDER BY 1"),
                         [('_i14', 'unevaluated'), ('_i15', 'unevaluated'), ('_i16', 'unevaluated')])

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_against_the_compiler(self):
        for main, expected, differences in (('sources/probes.m', PROBES_M, PROBES_M_DIFFERENCES),
                                            ('sources/probes.mm', PROBES_MM, PROBES_MM_DIFFERENCES)):
            want = dict(expected)
            for sel, (obj, db) in differences.items():
                self.assertEqual(want.get(sel, 0), db, sel)
                want[sel] = obj
            got = dict(object_call_sites(self.root, main))
            self.assertEqual(got, dict((k, v) for k, v in want.items() if v), main)



class ExtraRowsNoteTest(unittest.TestCase):
    """The note every query prints about rows for sends the binary never
    makes matches what the extractor records: the operands of _Generic and
    __builtin_choose_expr that are not chosen have no rows (probes.m)."""

    def test_unchosen_operands_have_no_rows(self):
        root = make_root()
        db, status, stderr = extract(root, 'sources/probes.m')
        self.assertEqual(status, 0, stderr)
        sent = send_counts(db)
        self.assertEqual((sent['m20'], sent['m21'], sent['m22'], sent['m23']), (1, 0, 1, 0))

    def test_note(self):
        self.assertEqual(codedb.EXTRA_ROWS_NOTE,
                         'note: rows can be listed for sends the binary never makes: in a template pattern as well '
                         'as in its instantiations (both arms of an if constexpr in the pattern), in a default '
                         'argument that no call uses, in a static or inline function that is never emitted, and in '
                         'code that a constant condition skips (in_constant_false_branch marks the cases where the '
                         'compiler certainly emits nothing). The operands of _Generic and __builtin_choose_expr '
                         'that are not chosen are not listed. A send in code that no path from its function\'s '
                         'entry reaches in the unit\'s configuration is listed with the mark "unreachable code"; it '
                         'can be live in another configuration.')


CC = 'sources/constant_conditions.m'


class ConstantConditionTest(unittest.TestCase):
    """Rows in code the compiler does not emit because a condition folds to a
    constant: in_constant_false_branch, with the condition's place."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db, cls.status, cls.stderr = extract(cls.root, CC)

    def test_clean(self):
        self.assertEqual(self.status, 0, self.stderr)

    def test_marks(self):
        self.assertEqual(rows(self.db, 'SELECT selector, line, in_constant_false_branch, constant_condition_file, '
                                       'constant_condition_line FROM send ORDER BY line, col'),
                         [('a', 9, 1, CC, 9),                # if (0)
                          ('b', 10, 1, CC, 10),              # a const local
                          ('count', 10, 0, None, None),      # its else
                          ('lock', 11, 1, CC, 11),           # a static const
                          ('explicitPoint', 12, 1, CC, 12),  # an enumerator
                          ('other', 13, 0, None, None),      # while (0): emitted
                          ('iv', 14, 1, CC, 14),             # 0 && x
                          ('length', 15, 1, CC, 15),         # 1 || x
                          ('rect', 16, 1, CC, 16),           # c ? x : y
                          ('vec', 17, 0, None, None),        # not const
                          ('range', 18, 0, None, None),      # !debug is true
                          ('init', 19, 1, CC, 19)])          # else of if (1)

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_against_the_compiler(self):
        self.assertEqual(sorted(object_call_sites(self.root, CC)),
                         sorted(s for (s,) in rows(self.db, 'SELECT selector FROM send WHERE '
                                                            'in_constant_false_branch = 0')))



CF_M = 'sources/constant_forms.m'
CF_MM = 'sources/constant_forms.mm'


def object_call_sites_o0(root, main, arc):
    """Per-selector call sites in the object Xcode's Clang compiles at -O0,
    with or without ARC."""
    out = os.path.join(os.path.dirname(root), '%s-%s.o' % (os.path.basename(main), 'arc' if arc else 'mrc'))
    lang = ['-x', 'objective-c++', '-std=c++17'] if main.endswith('.mm') else ['-x', 'objective-c']
    subprocess.run(['xcrun', 'clang', '-c', '-O0', '-arch', 'arm64', '-mmacosx-version-min=13.0', '-w'] +
                   (['-fobjc-arc'] if arc else []) + lang + ['-I', os.path.join(root, 'sources'),
                                                            os.path.join(root, main), '-o', out],
                   check=True, capture_output=True)
    with open(out, 'rb') as f:
        return crosscheck.read_object(f.read()).call_sites


def marked_selectors(db):
    return sorted(s for (s,) in rows(db, 'SELECT selector FROM send WHERE in_constant_false_branch = 1'))


class ConstantFormsTest(unittest.TestCase):
    """in_constant_false_branch is sound: a row is marked only where the
    compiler emits nothing at -O0 (the skipped arm of an if whose condition
    folds; the skipped operand of a scalar rvalue conditional operator, &&
    or || that is not part of a branch condition). Everything else stays
    unmarked, even where the compiler happens to drop it."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.m, cls.m_status, cls.m_stderr = extract(cls.root, CF_M)
        cls.mm, cls.mm_status, cls.mm_stderr = extract(cls.root, CF_MM)

    def test_clean(self):
        self.assertEqual(self.m_status, 0, self.m_stderr)
        self.assertEqual(self.mm_status, 0, self.mm_stderr)

    def test_marked_in_objective_c(self):
        self.assertEqual(marked_selectors(self.m),
                         ['b1', 'b2', 'b4',                          # 0 && x, 1 || x, (0 && y) && x
                          'i1', 'i3', 'i5',                          # scalar ?:, ignored, a call's argument
                          'k01', 'k02', 'k03', 'k05', 'k06', 'k07', 'k08',  # if (constant)
                          'l1', 'o2', 'o3', 'o5', 's1', 'v1'])      # pointer, object (ARC), void, macro

    def test_marked_in_objective_c_plus_plus(self):
        self.assertEqual(marked_selectors(self.mm),
                         ['b1', 'b2',                  # false && x, true || x
                          'i1', 'i8',                  # scalar ?:, in a lambda
                          'k01', 'k02', 'k04',         # if (constexpr), if constexpr, const bool
                          'l1', 'l1', 'l3', 'l5',      # lvalue ?: (assigned, bound to a reference, member,
                          'o1', 'x1'])                 # copied), object, class-type lvalue copied

    def test_not_marked(self):
        # A label the skipped arm holds (goto, case of the enclosing
        # switch); a conditional or && inside a branch condition (CodeGen
        # emits both arms); an aggregate or complex result; a class-type
        # operand; GNU a ?: b.
        marked = set(marked_selectors(self.m))
        for sel in ('k09', 'k10', 'b5', 'b6', 'b8', 'c1', 'c2', 'b9', 'c3', 'c4', 'c7', 'i7', 'p1', 'z1', 'l3',
                    'g1', 'g3'):
            self.assertNotIn(sel, marked)
        marked = set(marked_selectors(self.mm))
        for sel in ('b3', 'b6', 'i4', 'i6'):
            self.assertNotIn(sel, marked)

    def test_references_marked_only_when_every_one_is_dead(self):
        # TWICE(x) expands x into a dead and a live operand at one place:
        # one row, live. A reference only in dead code is marked.
        self.assertEqual(rows(self.m, 'SELECT enclosing_name, in_constant_false_branch FROM ivar_ref ORDER BY line'),
                         [('-[CF(Forms) twiceIvar]', 0), ('-[CF(Forms) deadIvar]', 1)])
        self.assertEqual(rows(self.m, "SELECT enclosing_name, in_constant_false_branch FROM static_ref WHERE "
                                      "name = 'gCount'"),
                         [('-[CF(Forms) twiceStatic]', 0)])

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_marked_implies_not_emitted(self):
        # The property that makes the mark safe to use as an excuse: for
        # every selector of every fixture function, marked rows plus the
        # object's call sites never exceed the rows (a marked row is never
        # a call the compiler emitted), with and without ARC.
        for main, db in ((CF_M, self.m), (CF_MM, self.mm), (CC, None)):
            if db is None:
                db, status, stderr = extract(self.root, main)
                self.assertEqual(status, 0, stderr)
            total = collections.Counter()
            marked = collections.Counter()
            for sel, m in rows(db, "SELECT selector, in_constant_false_branch FROM send WHERE receiver_kind NOT "
                                   "LIKE 'super%'"):
                total[sel] += 1
                marked[sel] += m
            for arc in (True, False):
                sites = object_call_sites_o0(self.root, main, arc)
                for sel in total:
                    self.assertLessEqual(marked[sel] + sites.get(sel, 0), total[sel],
                                         '%s %s (arc %s): %d marked, %d call sites, %d rows' %
                                         (main, sel, arc, marked[sel], sites.get(sel, 0), total[sel]))


UC_M = 'sources/unreachable.m'
UC_MM = 'sources/unreachable.mm'


def unreachable_rows(db):
    return sorted(rows(db, 'SELECT selector, in_unreachable_code FROM send'))


class UnreachableCodeTest(unittest.TestCase):
    """in_unreachable_code: a send in a block of the function's control-flow
    graph (Clang's CFG) that no path from the entry reaches, in the unit's
    own configuration, where the skipped arm of an if or of a conditional
    operator whose condition folds as CodeGen folds it is not a path. A
    path ends at return, break, continue, goto, throw and @throw, and at a
    call the code generator treats as noreturn (a noreturn attribute,
    _Noreturn, [[noreturn]], __builtin_unreachable), not at the other
    calls where Clang's CFG ends it (__builtin_assume(0), __builtin_trap,
    __builtin_debugtrap, analyzer_noreturn). Checked against the compiler
    for the forms of the fixtures (a marked send is never one it emitted),
    and deliberately narrower than what the compiler drops (unreachable.m,
    unreachable.mm)."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.m, cls.m_status, cls.m_stderr = extract(cls.root, UC_M)
        cls.mm, cls.mm_status, cls.mm_stderr = extract(cls.root, UC_MM)

    def test_clean(self):
        self.assertEqual(self.m_status, 0, self.m_stderr)
        self.assertEqual(self.mm_status, 0, self.mm_stderr)

    def test_marked_in_objective_c(self):
        marked = [s for s, m in unreachable_rows(self.m) if m]
        self.assertEqual(marked, ['u01',      # after return
                                  'u02',      # after a noreturn call
                                  'u03',      # after if (!(0)) { noreturn } (ITAssertWithMessage(NO, ...))
                                  'u04',      # after 0 ? ... : noreturn (assert(NO), ITDebugAssert(NO))
                                  'u05',      # after a switch that returns in every case, default included
                                  'u06',      # after break
                                  'u07',      # after continue
                                  'u08',      # after goto
                                  'u09',      # after return in a block
                                  'u10:with:',  # after its own noreturn argument
                                  'u12',      # after @throw
                                  'u13',      # after return in an if
                                  'u14',      # after return in a method
                                  'u15'])     # after __builtin_unreachable

    def test_not_marked_in_objective_c(self):
        unmarked = [s for s, m in unreachable_rows(self.m) if not m]
        # n16 to n19: after __builtin_assume(0), __builtin_trap(),
        # __builtin_debugtrap() and an analyzer_noreturn function, where
        # Clang's CFG ends the path but the compiler emits what follows.
        self.assertEqual(unmarked, ['n01', 'n02', 'n03', 'n04', 'n05', 'n06', 'n07', 'n08', 'n09', 'n10', 'n11',
                                    'n12', 'n13', 'n14', 'n15', 'n16', 'n17', 'n18', 'n19', 'u11'])

    def test_objective_c_plus_plus(self):
        got = unreachable_rows(self.mm)
        self.assertEqual([s for s, m in got if m], ['t01', 'u01', 'u02', 'u03'])
        self.assertEqual(sorted(set(s for s, m in got if not m)), ['n02', 'n03', 't01'])
        # t01: the template pattern's row (not analyzed) and the
        # instantiation's (marked).
        self.assertEqual([r for r in got if r[0] == 't01'], [('t01', 0), ('t01', 1)])

    def test_the_query_shows_the_mark(self):
        con = sqlite3.connect(self.m)
        try:
            configuration = con.execute('SELECT configuration FROM tu').fetchone()[0]
        finally:
            con.close()
        self.assertEqual(codedb.unreachable_text(configuration),
                         'unreachable code (no path from the function\'s entry in this unit\'s configuration, %s)' %
                         (configuration or 'not recorded'))
        self.assertEqual(codedb.unreachable_text('Development'),
                         'unreachable code (no path from the function\'s entry in this unit\'s configuration, '
                         'Development)')

    @unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
    def test_marked_implies_not_emitted(self):
        # The property that makes the mark safe to use as an excuse: for
        # every selector, marked rows plus the object's call sites never
        # exceed the rows, with and without ARC; and here every marked
        # selector is absent from the object.
        for main, db in ((UC_M, self.m), (UC_MM, self.mm)):
            total = collections.Counter()
            marked = collections.Counter()
            for sel, m in rows(db, "SELECT selector, in_unreachable_code FROM send WHERE receiver_kind NOT LIKE "
                                   "'super%'"):
                total[sel] += 1
                marked[sel] += m
            for arc in (True, False):
                sites = object_call_sites_o0(self.root, main, arc)
                for sel in total:
                    self.assertLessEqual(marked[sel] + sites.get(sel, 0), total[sel],
                                         '%s %s (arc %s): %d marked, %d call sites, %d rows' %
                                         (main, sel, arc, marked[sel], sites.get(sel, 0), total[sel]))
                    if marked[sel]:
                        self.assertEqual(sites.get(sel, 0), 0, '%s %s (arc %s)' % (main, sel, arc))


if __name__ == '__main__':
    unittest.main()
