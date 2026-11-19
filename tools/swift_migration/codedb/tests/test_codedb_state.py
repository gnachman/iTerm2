#!/usr/bin/env python3
"""Tests for the code database's state tables: ivars (objc_ivar), statics
and globals (c_static), and the references to them (ivar_ref, static_ref),
and the ivars, ivarrefs, statics and staticrefs queries.

Run with the other code database tests:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_*.py'

Like test_codedb.py, it needs only Homebrew LLVM and the SDK: the fixtures
under state_fixtures/ declare their own root class. Expected rows are written
out by hand from the fixtures. holder.m, category.m and cxx.mm are compiled
with ARC and peer.m with manual reference counting, so that holder.h is read
in both modes.
"""

import io
import json
import os
import shutil
import sqlite3
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import codedb  # noqa: E402
import test_codedb as base  # noqa: E402

STATE_FIXTURES = os.path.join(HERE, 'state_fixtures')
H = 'sources/holder.h'
M = 'sources/holder.m'
P = 'sources/peer.m'
C = 'sources/category.m'
X = 'sources/cxx.mm'
ARC = ['-fobjc-arc']
# The units in the order update extracts them, with their extra arguments.
MAINS = ((M, ARC), (C, ARC), (P, []), (X, ARC + ['-std=c++17']))


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def make_state_root():
    d = base.make_temp('codedb-state-')
    root = os.path.join(d, 'repo')
    shutil.copytree(STATE_FIXTURES, root)
    return root


def write_cdb(root, path, mains=MAINS):
    """A compile database and a project for the mains, each with its own
    extra arguments."""
    base.write_project(root, {'T': [m for m, _ in mains]})
    meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(root)}
    with open(path, 'w') as f:
        f.write(json.dumps(meta) + '\n')
        for m, extra in mains:
            f.write(json.dumps({'target': 'T', 'file': m, 'directory': root,
                                'arguments': base.clang_args(root, m, extra)}) + '\n')


def rows(db, sql):
    con = sqlite3.connect(db)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


def split(text):
    body, _, block = text.partition('\n--- status ---\n')
    return body.splitlines(), block


IVAR_COLUMNS = ('i.class_name, i.name, i.container_kind, i.type, i.canonical_type, i.type_class, i.object_class, '
                'i.object_protocols, i.record_name, i.bit_width, i.record_has_objects, i.ownership_written, '
                'i.ownership, i.arc, i.access, i.is_iboutlet, i.synthesized_by, i.property_name, i.file, i.line, '
                'i.col, t.main_file')
N = None


def ivar(cls, name, kind, typ, canon, tclass, file, line, col, unit, ocls=N, protos=N, record=N, width=N,
         has_objects=N, written=N, own='none', arc=1, access='protected', outlet=0, synth=N, prop=N):
    return (cls, name, kind, typ, canon, tclass, ocls, protos, record, width, has_objects, written, own, arc, access,
            outlet, synth, prop, file, line, col, unit)


def header_ivars(arc, unit):
    """The ivars of holder.h's @interface, as a unit in ARC (arc 1) or manual
    reference counting reads them."""
    strong = 'strong' if arc else 'manual'
    sid = '__strong id' if arc else 'id'
    return [
        ivar('Holder', '_plain', 'interface', sid, sid, 'object', H, 7, 8, unit, ocls='id', own=strong, arc=arc),
        # Manual reference counting keeps __weak in the type but does not
        # honor it (no objc_storeWeak without -fobjc-weak).
        ivar('Holder', '_weakRef', 'interface', '__weak id', '__weak id', 'object', H, 8, 15, unit, ocls='id',
             written='weak', own='weak' if arc else 'manual', arc=arc),
        ivar('Holder', '_publicCount', 'interface', 'int', 'int', 'scalar', H, 10, 9, unit, arc=arc, access='public'),
        ivar('Holder', '_rect', 'interface', 'Rect2', 'Rect2', 'struct', H, 12, 11, unit, record='Rect2',
             has_objects=0, arc=arc, access='package'),
        ivar('Holder', '_count', 'interface', 'int', 'int', 'scalar', H, 14, 9, unit, arc=arc),
        ivar('Holder', '_flag', 'interface', 'unsigned int', 'unsigned int', 'bit-field', H, 15, 14, unit, width=1,
             arc=arc),
        ivar('Holder', '_outlet', 'interface', sid, sid, 'object', H, 16, 17, unit, ocls='id', own=strong, arc=arc,
             outlet=1),
        ivar('Holder', '_drawer', 'interface', sid + '<Drawing>', sid + '<Drawing>', 'object', H, 18, 17, unit,
             ocls='id', protos='Drawing', own=strong, arc=arc, access='private'),
        ivar('Holder', '_handler', 'interface', 'void (^__strong)(void)' if arc else 'void (^)(void)',
             'void (^__strong)(void)' if arc else 'void (^)(void)', 'block', H, 19, 12, unit, own=strong, arc=arc,
             access='private'),
        ivar('Holder', '_cursor', 'interface', 'char *', 'char *', 'c-pointer', H, 20, 11, unit, arc=arc,
             access='private'),
        ivar('Holder', '_buf', 'interface', 'int[4]', 'int[4]', 'array', H, 21, 9, unit, arc=arc, access='private'),
        ivar('Holder', '_atomicCount', 'interface', '_Atomic(int)', '_Atomic(int)', 'atomic', H, 22, 17, unit,
             arc=arc, access='private'),
        ivar('Holder', '_number', 'interface', 'Number2', 'Number2', 'union', H, 23, 13, unit, record='Number2',
             has_objects=0, arc=arc, access='private'),
        ivar('Holder', '_cls', 'interface', '__unsafe_unretained Class' if arc else 'Class',
             '__unsafe_unretained Class' if arc else 'Class', 'object', H, 24, 11, unit, ocls='Class',
             own='unsafe_unretained' if arc else 'manual', arc=arc, access='private'),
    ]


EXPECTED_IVARS = sorted(
    header_ivars(1, M) + header_ivars(0, P) + [
        # Auto-synthesized: at the property, by the implementation's unit.
        ivar('Holder', '_title', 'implementation', 'NSString *__strong', 'NSString *__strong', 'object', H, 26, 39, M,
             ocls='NSString', own='strong', access='private', synth='automatic', prop='title'),
        ivar('Holder', '_delegate', 'implementation', '__weak id', '__weak id', 'object', H, 27, 32, M, ocls='id',
             own='weak', access='private', synth='automatic', prop='delegate'),
        ivar('Holder', '_extCount', 'extension', 'int', 'int', 'scalar', M, 13, 9, M, access='private'),
        ivar('Holder', '_unsafe', 'implementation', '__unsafe_unretained id', '__unsafe_unretained id', 'object', M,
             17, 28, M, ocls='id', written='unsafe_unretained', own='unsafe_unretained', access='private'),
        ivar('Holder', '_storage', 'implementation', 'int', 'int', 'scalar', M, 18, 9, M, access='private'),
        ivar('Holder', '_boxed', 'implementation', 'Boxed2', 'Boxed2', 'struct', M, 19, 12, M, record='Boxed2',
             has_objects=1, access='private'),
        # @synthesize other; makes an ivar named other.
        ivar('Holder', 'other', 'implementation', 'int', 'int', 'scalar', M, 22, 13, M, access='private',
             synth='explicit', prop='other'),
        ivar('Peer', '_retained', 'interface', 'id', 'id', 'object', P, 4, 8, P, ocls='id', own='manual', arc=0),
        # Manual reference counting drops __unsafe_unretained from the type.
        ivar('Peer', '_loose', 'interface', 'id', 'id', 'object', P, 5, 28, P, ocls='id', own='manual', arc=0),
        # A bit-field last among a class's ivars: the compiler adds an
        # unnamed ivar after it, which is not recorded.
        ivar('Peer', '_peerFlag', 'interface', 'unsigned int', 'unsigned int', 'bit-field', P, 6, 14, P, width=1, arc=0),
        ivar('CxxThing', '_counter', 'implementation', 'Counter', 'Counter', 'cxx-object', X, 12, 13, X,
             record='Counter', has_objects=0, access='private'),
        ivar('CxxThing', '_frame', 'implementation', 'Rect2', 'Rect2', 'struct', X, 13, 11, X, record='Rect2',
             has_objects=0, access='private'),
        ivar('CxxThing', '_tint', 'implementation', 'Vec4', 'float __attribute__((ext_vector_type(4)))', 'vector', X,
             14, 10, X, access='private'),
    ], key=lambda r: (r[18], r[19], r[20], r[13]))

REF_COLUMNS = ('r.ivar_class, r.ivar_name, r.file, r.line, r.col, r.enclosing_name, r.enclosing_class, r.kind, '
               'r.access, r.partial, r.base_kind, r.in_block, r.in_once_block, r.macro_role')


def ref(cls, name, file, line, col, enclosing, access, base_kind='implicit-self', partial=0, in_block=0,
        kind='direct', role=None, enclosing_class=None):
    if enclosing_class is None:
        enclosing_class = enclosing.split('[')[1].split(' ')[0].split('(')[0]
    return (cls, name, file, line, col, enclosing, enclosing_class, kind, access, partial, base_kind, in_block, 0,
            role)


RUN = '-[Holder run:]'
EXPECTED_IVAR_REFS = [
    # The synthesized accessors, at their @synthesize or property.
    ref('Holder', '_title', H, 26, 39, '-[Holder setTitle:]', 'write', 'self', kind='synthesized-setter'),
    ref('Holder', '_title', H, 26, 39, '-[Holder title]', 'read', 'self', kind='synthesized-getter'),
    ref('Holder', '_delegate', H, 27, 32, '-[Holder delegate]', 'read', 'self', kind='synthesized-getter'),
    ref('Holder', '_delegate', H, 27, 32, '-[Holder setDelegate:]', 'write', 'self', kind='synthesized-setter'),
    ref('Holder', '_storage', M, 21, 1, '-[Holder renamed]', 'read', 'self', kind='synthesized-getter'),
    ref('Holder', 'other', M, 22, 1, '-[Holder other]', 'read', 'self', kind='synthesized-getter'),
    ref('Holder', 'other', M, 22, 1, '-[Holder setOther:]', 'write', 'self', kind='synthesized-setter'),
    ref('Holder', '_count', M, 24, 5, RUN, 'write'),
    ref('Holder', '_count', M, 25, 5, RUN, 'rmw'),
    ref('Holder', '_count', M, 26, 5, RUN, 'rmw'),
    ref('Holder', '_count', M, 27, 13, RUN, 'read'),
    ref('Holder', '_count', M, 28, 11, RUN, 'byref'),
    ref('Holder', '_extCount', M, 29, 15, RUN, 'address'),
    ref('Holder', '_count', M, 30, 11, RUN, 'write', 'self'),
    ref('Holder', '_count', M, 31, 11, RUN, 'write', 'parameter'),
    ref('Holder', '_rect', M, 32, 5, RUN, 'write', partial=1),
    ref('Holder', '_buf', M, 33, 5, RUN, 'write', partial=1),
    ref('Holder', '_plain', M, 34, 20, RUN, 'synchronized'),
    ref('Holder', '_count', M, 36, 18, RUN, 'unevaluated'),
    ref('Holder', '_count', M, 37, 10, RUN, 'rmw', role='argument'),
    ref('Holder', '_count', M, 38, 5, RUN, 'write', role='body'),
    ref('Holder', '_unsafe', M, 39, 5, RUN, 'write'),
    ref('Holder', '_plain', M, 39, 15, RUN, 'read'),
    ref('Holder', '_cursor', M, 45, 5, RUN, 'write'),
    ref('Holder', '_count', M, 48, 26, '-[Holder blocks]', 'write', in_block=1),
    ref('Holder', '_count', M, 52, 21, '-[Holder blocks]', 'write', 'weak-strong-local', in_block=1),
    ref('Holder', '_count', C, 7, 5, '-[Holder(Extra) bumpFromCategory]', 'rmw'),
    ref('Holder', '_count', C, 12, 12, '-[SubHolder inherited]', 'read'),
    ref('Holder', '_publicCount', P, 12, 8, '-[Peer poke:]', 'write', 'parameter'),
    ref('Holder', '_publicCount', P, 12, 26, '-[Peer poke:]', 'read', 'parameter'),
    ref('Peer', '_retained', P, 13, 5, '-[Peer poke:]', 'write'),
    ref('Peer', '_loose', P, 15, 26, '-[Peer poke:]', 'write', in_block=1),
    ref('Peer', '_retained', P, 15, 35, '-[Peer poke:]', 'read', in_block=1),
    ref('CxxThing', '_counter', X, 18, 5, '-[CxxThing tick]', 'rmw', partial=1),
    ref('CxxThing', '_frame', X, 19, 31, '-[CxxThing tick]', 'read', partial=1),
    # A C++ operator= call.
    ref('CxxThing', '_counter', X, 35, 5, '-[CxxThing(More) reset]', 'write'),
]

STATIC_COLUMNS = ('s.name, s.kind, s.enclosing_name, s.type, s.type_class, s.object_class, s.record_name, s.ownership, '
                  's.arc, s.is_const, s.pointee_const, s.init_kind, s.thread_local, s.file, s.line, s.col, t.main_file')


def static(name, kind, typ, tclass, file, line, col, unit, enclosing=N, ocls=N, record=N, own='none', arc=1,
           const=0, pointee=N, init='none', tls=0):
    return (name, kind, enclosing, typ, tclass, ocls, record, own, arc, const, pointee, init, tls, file, line, col,
            unit)


def header_statics(arc, unit):
    return [
        static('gHolderCount', 'extern', 'int', 'scalar', H, 3, 12, unit, arc=arc),
        static('kExported', 'extern', 'NSString *const __strong' if arc else 'NSString *const', 'object', H, 4, 24,
               unit, ocls='NSString', own='strong' if arc else 'manual', arc=arc, const=1),
        static('kHeaderLimit', 'file-static', 'const int', 'scalar', H, 5, 18, unit, arc=arc, const=1,
               init='literal'),
    ]


SHARED = '+[Holder shared]'
EXPECTED_STATICS = sorted(header_statics(1, M) + header_statics(0, P) + [
    static('gHolderCount', 'global', 'int', 'scalar', M, 5, 5, M, init='literal'),
    static('kExported', 'global', 'NSString *const __strong', 'object', M, 6, 17, M, ocls='NSString', own='strong',
           const=1, init='literal'),
    static('sCounter', 'file-static', 'int', 'scalar', M, 7, 12, M),
    static('kName', 'file-static', 'NSString *const __strong', 'object', M, 8, 24, M, ocls='NSString', own='strong',
           const=1, init='literal'),
    static('sMutable', 'file-static', 'NSString *__strong', 'object', M, 9, 18, M, ocls='NSString', own='strong'),
    static('sPrefix', 'file-static', 'const char *', 'c-pointer', M, 10, 20, M, pointee=1, init='literal'),
    static('sShared', 'local-static', 'Holder *__strong', 'object', M, 58, 20, M, enclosing=SHARED, ocls='Holder',
           own='strong'),
    static('onceToken', 'local-static', 'dispatch_once_t', 'scalar', M, 59, 28, M, enclosing=SHARED),
    static('calls', 'local-static', 'int', 'scalar', M, 63, 16, M, enclosing=SHARED),
    static('sGlobalCounter', 'file-static', 'Counter', 'cxx-object', X, 7, 16, X, record='Counter', init='runtime'),
    static('tCount', 'global', 'int', 'scalar', X, 8, 18, X, tls=1),
    static('sFramePtr', 'file-static', 'Rect2 *', 'c-pointer', X, 22, 15, X, pointee=0),
    # Const one level down, not two.
    static('sNames', 'file-static', 'char *const *', 'c-pointer', X, 23, 21, X, pointee=0),
    static('sMixed', 'file-static', 'int', 'scalar', X, 24, 12, X),
    static('token', 'local-static', 'dispatch_once_t', 'scalar', X, 27, 28, X, enclosing='Poke'),
], key=lambda r: (r[13], r[14], r[15], r[8]))

STATIC_REF_COLUMNS = ('r.name, r.var_kind, r.file, r.line, r.col, r.enclosing_name, r.access, r.partial, r.in_block, '
                      'r.in_once_block, r.macro_role')
EXPECTED_STATIC_REFS = [
    ('sCounter', 'file-static', M, 40, 5, RUN, 'write', 0, 0, 0, None),
    ('sCounter', 'file-static', M, 40, 16, RUN, 'read', 0, 0, 0, None),
    ('sMutable', 'file-static', M, 41, 5, RUN, 'write', 0, 0, 0, None),
    ('kName', 'file-static', M, 41, 16, RUN, 'read', 0, 0, 0, None),
    ('gHolderCount', 'global', M, 42, 5, RUN, 'rmw', 0, 0, 0, None),
    ('sPrefix', 'file-static', M, 43, 11, RUN, 'read', 0, 0, 0, None),
    ('kHeaderLimit', 'file-static', M, 44, 11, RUN, 'read', 0, 0, 0, None),
    ('onceToken', 'local-static', M, 60, 20, SHARED, 'once-token', 0, 0, 0, None),
    ('sShared', 'local-static', M, 61, 9, SHARED, 'write', 0, 1, 1, None),
    ('calls', 'local-static', M, 64, 5, SHARED, 'rmw', 0, 0, 0, None),
    ('sShared', 'local-static', M, 65, 12, SHARED, 'read', 0, 0, 0, None),
    ('gHolderCount', 'global', P, 14, 5, '-[Peer poke:]', 'write', 0, 0, 0, None),
    ('tCount', 'global', X, 17, 5, '-[CxxThing tick]', 'rmw', 0, 0, 0, None),
    ('sGlobalCounter', 'file-static', X, 19, 12, '-[CxxThing tick]', 'read', 1, 0, 0, None),
    # A member through '->' is a read of the pointer.
    ('sFramePtr', 'file-static', X, 26, 5, 'Poke', 'read', 0, 0, 0, None),
    ('token', 'local-static', X, 28, 20, 'Poke', 'once-token', 0, 0, 0, None),
    ('sMixed', 'file-static', X, 28, 30, 'Poke', 'write', 0, 1, 1, None),
    ('sMixed', 'file-static', X, 29, 5, 'Poke', 'write', 0, 0, 0, None),
    ('sNames', 'file-static', X, 30, 11, 'Poke', 'read', 0, 0, 0, None),
]


class StateTablesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_state_root()
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb)
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)
        cls.db = cls.paths.db

    def test_clean_update(self):
        self.assertEqual(self.status, 0, '\n'.join(self.log))

    def test_every_ivar_exactly(self):
        got = rows(self.db, 'SELECT %s FROM objc_ivar i JOIN tu t ON t.id = i.tu ORDER BY i.file, i.line, i.col, '
                            'i.arc' % IVAR_COLUMNS)
        self.assertEqual(got, EXPECTED_IVARS)

    def test_ivar_usr_and_scope(self):
        self.assertEqual(rows(self.db, "SELECT DISTINCT usr, in_migration_scope FROM objc_ivar WHERE name IN "
                                       "('_count', '_extCount', 'other') ORDER BY name"),
                         [('c:objc(cs)Holder@_count', 1), ('c:objc(cs)Holder@_extCount', 1),
                          ('c:objc(cs)Holder@other', 1)])

    def test_every_ivar_reference_exactly(self):
        got = rows(self.db, 'SELECT %s FROM ivar_ref r ORDER BY r.file, r.line, r.col, r.enclosing_name'
                            % REF_COLUMNS)
        self.assertEqual(got, sorted(EXPECTED_IVAR_REFS, key=lambda r: (r[2], r[3], r[4], r[5])))

    def test_ivar_ref_joins_its_ivar(self):
        # Every reference names an ivar the database has.
        self.assertEqual(rows(self.db, 'SELECT count(*) FROM ivar_ref r WHERE NOT EXISTS (SELECT 1 FROM objc_ivar i '
                                       'WHERE i.usr = r.ivar_usr)'), [(0,)])

    def test_property_to_ivar_join_key(self):
        # A send of a property's accessor reaches the ivar that backs it:
        # send -> objc_method (target_usr) -> objc_property (synthesize) ->
        # objc_ivar.
        self.assertEqual(rows(self.db, "SELECT name, ivar_name, ivar_usr, is_implicit FROM objc_property WHERE "
                                       "kind = 'synthesize' ORDER BY name"),
                         [('delegate', '_delegate', 'c:objc(cs)Holder@_delegate', 1),
                          ('other', 'other', 'c:objc(cs)Holder@other', 0),
                          ('renamed', '_storage', 'c:objc(cs)Holder@_storage', 0),
                          ('title', '_title', 'c:objc(cs)Holder@_title', 1)])

    def test_every_static_exactly(self):
        got = rows(self.db, 'SELECT %s FROM c_static s JOIN tu t ON t.id = s.tu ORDER BY s.file, s.line, s.col, '
                            's.arc' % STATIC_COLUMNS)
        self.assertEqual(got, EXPECTED_STATICS)

    def test_extern_matches_its_definition(self):
        self.assertEqual(rows(self.db, "SELECT DISTINCT kind, usr FROM c_static WHERE name = 'gHolderCount' "
                                       "ORDER BY kind"),
                         [('extern', 'c:@gHolderCount'), ('global', 'c:@gHolderCount')])

    def test_every_static_reference_exactly(self):
        got = rows(self.db, 'SELECT %s FROM static_ref r ORDER BY r.file, r.line, r.col' % STATIC_REF_COLUMNS)
        self.assertEqual(got, sorted(EXPECTED_STATIC_REFS, key=lambda r: (r[2], r[3], r[4])))

    def test_static_ref_joins_its_static(self):
        self.assertEqual(rows(self.db, 'SELECT count(*) FROM static_ref r WHERE NOT EXISTS (SELECT 1 FROM c_static s '
                                       'WHERE s.usr = r.var_usr)'), [(0,)])

    def test_header_views_differ_by_arc_mode(self):
        # holder.h is claimed once for ARC (holder.m; category.m reads it the
        # same way and records nothing) and once for manual reference
        # counting (peer.m).
        self.assertEqual(rows(self.db, "SELECT t.main_file FROM decl_source d JOIN tu t ON t.id = d.tu WHERE "
                                       "d.path = 'sources/holder.h' ORDER BY 1"), [(M,), (P,)])


class StateQueryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_state_root()
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb)
        codedb.update(cls.paths, log=lambda m: None)

    def ask(self, query, *args):
        out = io.StringIO()
        status = query(self.paths, *args, out=out)
        lines, block = split(out.getvalue())
        return status, lines, block

    def test_ivars_table(self):
        status, lines, block = self.ask(codedb.ivars, 'Holder')
        self.assertEqual(status, 0, '\n'.join(lines) + block)
        self.assertNotIn('INCOMPLETE', block)
        text = '\n'.join(lines)
        self.assertEqual(lines[0], 'Ivars of Holder: 21')
        # The conflict between the two modes, for the same declaration.
        # The class's own code is ARC: that row governs, and the manual
        # reference counting row is only how peer.m sees the header.
        self.assertEqual(lines[1], 'Holder is implemented in sources/category.m (category Extra), sources/holder.m, '
                                   'compiled with ARC')
        self.assertIn('_plain  sources/holder.h:7:8  interface, protected  __strong id, object id, strong (ARC, the '
                      'class\'s own code)  CONFLICT: Holder is implemented in sources/category.m (category Extra), '
                      'sources/holder.m, compiled with ARC, which governs; as seen by units of the other mode (not the '
                      'class\'s own code): manual reference counting: id, manual (recorded by sources/peer.m)', text)
        self.assertNotIn('retain hint', text)
        # A backed property with its attributes, and the counts.
        self.assertIn('_title  sources/holder.h:26:39  implementation, private  NSString *__strong, object NSString, '
                      'strong (ARC)  synthesized automatically for property title (nonatomic,copy)', text)
        self.assertIn('_storage  sources/holder.m:18:9  implementation, private  int, scalar, none (ARC)  backs '
                      'property renamed (atomic,readonly) by @synthesize', text)
        self.assertIn('    references 14: read 2, write 6, rmw 4, byref 1, unevaluated 1; direct 14, synthesized '
                      'accessor 0; in blocks 2 (capture self strongly 1, through a weak-strong local 1); from other '
                      'objects 1; from other classes 1; from other files 2', text)
        self.assertIn('    by method: -[Holder run:] 10 (read 1, write 4, rmw 3, byref 1, unevaluated 1); -[Holder '
                      'blocks] 2 (write 2); -[Holder(Extra) bumpFromCategory] 1 (rmw 1); -[SubHolder inherited] 1 '
                      '(read 1)', text)
        self.assertIn('_flag  sources/holder.h:15:14  interface, protected  unsigned int, bit-field width 1, none (ARC '
                      'and manual reference counting)', text)
        self.assertIn('Methods of Holder that reach ivars of other classes directly: 0', text)

    def test_ivars_reached_from_other_classes(self):
        status, lines, block = self.ask(codedb.ivars, 'Peer')
        self.assertEqual(status, 0)
        text = '\n'.join(lines)
        self.assertIn('Methods of Peer that reach ivars of other classes directly: 1', text)
        self.assertIn('  -[Peer poke:]: Holder._publicCount (read 1, write 1)', text)

    def test_ivars_of_unknown_class(self):
        status, lines, block = self.ask(codedb.ivars, 'Nobody')
        self.assertEqual((status, lines[0]), (1, 'Ivars of Nobody: 0'))

    def test_ivarrefs(self):
        status, lines, block = self.ask(codedb.ivarrefs, 'Holder', '_count')
        self.assertEqual(status, 0)
        self.assertIn('sources/holder.m:52:21  -[Holder blocks]  write  base weak-strong local  in block  targets T',
                      lines)
        self.assertIn('sources/holder.m:37:10  -[Holder run:]  rmw  base implicit self  macro BUMP argument (defined '
                      'sources/holder.m:3, used at 37:5)  targets T', lines)
        self.assertIn('sources/holder.m:48:26  -[Holder blocks]  write  base implicit self  in block (captures self '
                      'strongly)  targets T', lines)

    def test_ivarrefs_synthesized(self):
        status, lines, block = self.ask(codedb.ivarrefs, 'Holder', '_title')
        self.assertEqual(status, 0)
        self.assertIn('sources/holder.h:26:39  -[Holder setTitle:]  write  synthesized setter  targets T', lines)

    def test_statics_of_file(self):
        status, lines, block = self.ask(codedb.statics, M)
        self.assertEqual(status, 0)
        text = '\n'.join(lines)
        self.assertIn('sShared  sources/holder.m:58:20  local-static in +[Holder shared]  Holder *__strong, object '
                      'Holder, strong (ARC)  initializer none  every write, address-of or by-reference use recorded '
                      'is in a dispatch_once block', text)
        self.assertIn('gHolderCount  sources/holder.m:5:5  global  int, scalar  initializer literal  written (counting '
                      'address-of and by-reference uses) from 2 functions', text)
        self.assertIn('kName  sources/holder.m:8:24  file-static  NSString *const __strong, object NSString, strong '
                      '(ARC)  const  initializer literal  no write, address-of or by-reference use recorded after its '
                      'initialization  targets T', lines)
        # A static defined in a header has a copy in each unit that includes
        # it.
        self.assertIn('kHeaderLimit  sources/holder.h:5:18  file-static  const int, scalar  const  initializer literal  '
                      'defined in a header: each including unit has its own copy; 3 units include it  no write, '
                      'address-of or by-reference use recorded after its initialization  targets T', lines)
        self.assertIn(codedb.STATE_LIMITS_LINE, lines)
        self.assertIn(codedb.STATE_SWIFT_LINE_STATICS, lines)

    def test_statics_written_once_and_again(self):
        status, lines, block = self.ask(codedb.statics, X)
        self.assertEqual(status, 0)
        self.assertIn('sMixed  sources/cxx.mm:24:12  file-static  int, scalar  initializer none  written (counting '
                      'address-of and by-reference uses) from 1 function  targets T', lines)

    def test_statics_of_a_file_no_unit_reads(self):
        status, lines, block = self.ask(codedb.statics, 'sources/nothere.m')
        self.assertEqual((status, lines[0]), (3, 'Statics declared or used in sources/nothere.m: 0'))
        self.assertIn('INCOMPLETE: no unit in this database reads sources/nothere.m (it is not parsed, or not a file '
                      'of the repository)', block)

    def test_statics_of_class(self):
        status, lines, block = self.ask(codedb.statics, 'CxxThing')
        self.assertEqual(status, 0)
        text = '\n'.join(lines)
        self.assertIn('sGlobalCounter', text)
        self.assertIn('tCount', text)
        self.assertNotIn('sCounter', text)

    def test_staticrefs(self):
        status, lines, block = self.ask(codedb.staticrefs, 'gHolderCount')
        self.assertEqual(status, 0)
        self.assertEqual(lines[0], 'Statics named gHolderCount: 1; references: 2')
        self.assertIn('    also declared: extern at sources/holder.h:3:12', lines)
        self.assertIn('  sources/peer.m:14:5  -[Peer poke:]  write  targets T', lines)
        self.assertIn('  sources/holder.m:42:5  -[Holder run:]  rmw  targets T', lines)

    def test_stale_unit_makes_queries_incomplete(self):
        root = make_state_root()
        paths = base.make_paths(root)
        write_cdb(root, paths.cdb)
        codedb.update(paths, log=lambda m: None)
        with open(os.path.join(root, P), 'a') as f:
            f.write('\n')
        for query, args in ((codedb.ivars, ('Holder',)), (codedb.ivarrefs, ('Holder', '_count')),
                            (codedb.statics, (M,)), (codedb.staticrefs, ('sCounter',))):
            out = io.StringIO()
            self.assertEqual(query(paths, *args, out=out), 3, query.__name__)
            self.assertIn('INCOMPLETE: 1 of 4 units are not current', out.getvalue())

    def test_unit_not_in_the_database_is_reported(self):
        root = make_state_root()
        paths = base.make_paths(root)
        write_cdb(root, paths.cdb, mains=MAINS[:1])
        codedb.update(paths, log=lambda m: None)
        write_cdb(root, paths.cdb)
        out = io.StringIO()
        self.assertEqual(codedb.ivars(paths, 'Holder', out=out), 3)
        self.assertIn('missing 3', out.getvalue())

    def test_command_line(self):
        for argv, want in ((['ivars', 'Holder'], 0), (['ivarrefs', 'Holder', '_count'], 0),
                           (['statics', M], 0), (['staticrefs', 'sCounter'], 0), (['ivars', 'Nobody'], 1)):
            out = io.StringIO()
            saved = sys.stdout
            sys.stdout = out
            try:
                status = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                      '--extractor', base.EXTRACTOR] + argv)
            finally:
                sys.stdout = saved
            self.assertEqual(status, want, argv)



# --- Implementing units, retain hints, array decay, @synchronized, C++ ------

MN = 'sources/mrc_note.m'
MH = 'sources/mrc_note.h'
MR = 'sources/mrc_reader.m'
D = 'sources/decay.m'
SY = 'sources/sync.m'
L = 'sources/lambda.mm'
MAINS2 = ((MN, []), (MR, ARC), (D, ARC), (SY, ARC), (L, ARC + ['-std=c++17']))
LOCK = 'ivar c:objc(cs)Locker@_lock'
WORK = '-[Locker work]'


def ref2(cls, name, file, line, col, enclosing, access, partial=0, base_kind='implicit-self', in_block=0, role=None,
         hint=None, lock=None, lam=None, enclosing_class=None, kind='direct'):
    if enclosing_class is None:
        enclosing_class = enclosing.split('[')[1].split(' ')[0].split('(')[0]
    return (cls, name, file, line, col, enclosing, enclosing_class, kind, access, partial, base_kind, in_block,
            role, hint, lock, lam)


REF2_COLUMNS = ('r.ivar_class, r.ivar_name, r.file, r.line, r.col, r.enclosing_name, r.enclosing_class, r.kind, '
                'r.access, r.partial, r.base_kind, r.in_block, r.macro_role, r.retain_hint, r.sync_lock, r.in_lambda')
SETUP = '-[MrcNote setUp:]'
TEARDOWN = '-[MrcNote tearDown]'
RUN2 = '-[Arrays run:]'
LRUN = '-[Lam run]'
EXPECTED_IVAR_REFS2 = sorted([
    ref2('MrcNote', '_title', MN, 4, 1, '-[MrcNote setTitle:]', 'write', base_kind='self', kind='synthesized-setter'),
    ref2('MrcNote', '_title', MN, 4, 1, '-[MrcNote title]', 'read', base_kind='self', kind='synthesized-getter'),
    ref2('MrcNote', '_kept', MN, 6, 5, SETUP, 'write', hint='assigned-owned'),
    ref2('MrcNote', '_button', MN, 7, 5, SETUP, 'write'),
    ref2('MrcNote', '_copied', MN, 8, 5, SETUP, 'write', hint='assigned-owned'),
    ref2('MrcNote', '_size', MN, 9, 5, SETUP, 'write'),
    ref2('MrcNote', '_kept', MN, 10, 6, SETUP, 'read', hint='release'),
    ref2('MrcNote', '_kept', MN, 13, 6, TEARDOWN, 'read', hint='release'),
    ref2('MrcNote', '_copied', MN, 14, 6, TEARDOWN, 'read', hint='autorelease'),
    ref2('MrcNote', '_kept', MN, 15, 5, TEARDOWN, 'write', hint='assigned-owned'),
    ref2('Dual', '_shared', MN, 20, 5, '-[Dual touch]', 'write'),
    ref2('Dual', '_shared', MR, 5, 5, '-[Dual(Arc) arcTouch]', 'write'),
    # Arrays that decay to pointers: a read only where the pointer is to
    # const.
    ref2('Arrays', '_src', D, 25, 21, RUN2, 'read'),
    # memmove is the fortified macro: its argument is seen twice (once in
    # __builtin_object_size, which does not evaluate it) and recorded once.
    ref2('Arrays', '_last', D, 26, 13, RUN2, 'byref', role='argument'),
    ref2('Arrays', '_stats', D, 27, 15, RUN2, 'byref'),
    ref2('Arrays', '_stats', D, 29, 5, RUN2, 'write', partial=1),
    ref2('Arrays', '_stats', D, 30, 11, RUN2, 'read', partial=1),
    ref2('Arrays', '_src', D, 31, 22, RUN2, 'read'),
    ref2('Arrays', '_src', D, 32, 15, RUN2, 'byref'),
    ref2('Arrays', '_src', D, 33, 9, RUN2, 'byref'),
    ref2('Arrays', '_pair', D, 34, 15, RUN2, 'byref', partial=1),
    ref2('Arrays', '_n', D, 35, 14, RUN2, 'read'),
    ref2('Arrays', '_n', D, 36, 16, RUN2, 'byref'),
    # @synchronized, directly and through ITNonnilLock, and the lock each
    # reference is lexically under.
    ref2('Locker', '_lock', SY, 21, 12, '-[Locker other]', 'read'),
    ref2('Locker', '_lock', SY, 24, 33, WORK, 'synchronized', role='argument'),
    ref2('Locker', '_a', SY, 25, 9, WORK, 'write', lock=LOCK),
    ref2('Locker', '_b', SY, 26, 9, WORK, 'rmw', lock=LOCK),
    ref2('Locker', '_lock', SY, 28, 20, WORK, 'synchronized'),
    ref2('Locker', '_b', SY, 29, 9, WORK, 'write', lock=LOCK),
    ref2('Locker', '_a', SY, 32, 9, WORK, 'write', lock='self'),
    ref2('Locker', '_a', SY, 35, 9, WORK, 'write', lock='static c:sync.m@sLock'),
    ref2('Locker', '_b', SY, 38, 9, WORK, 'write', lock='class Locker'),
    ref2('Locker', '_a', SY, 41, 32, WORK, 'write', in_block=1, lock='other [self other]'),
    ref2('Locker', '_a', SY, 44, 5, WORK, 'write'),
    # A non-const C++ reference bound to an ivar; lambdas.
    ref2('Lam', '_n', L, 12, 14, LRUN, 'address'),
    ref2('Lam', '_m', L, 13, 20, LRUN, 'read'),
    ref2('Lam', '_k', L, 14, 26, LRUN, 'write', lam='self by reference'),
    ref2('Lam', '_k', L, 15, 34, LRUN, 'read', lam='self by copy'),
    ref2('Lam', '_m', L, 17, 43, LRUN, 'read', base_kind='local', lam='init-capture'),
], key=lambda r: (r[2], r[3], r[4], r[5]))

EXPECTED_STATIC_REFS2 = sorted([
    ('gPipe', D, 24, 10, RUN2, 'byref', 0, None),
    ('gPrefix', D, 25, 12, RUN2, 'byref', 0, None),
    ('gName', D, 28, 18, RUN2, 'read', 0, None),
    ('gName', D, 40, 12, '-[Arrays name]', 'read', 0, None),
    ('gName', D, 43, 12, '-[Arrays mutableName]', 'byref', 0, None),
    ('sLock', SY, 34, 33, WORK, 'synchronized', 0, None),
    ('sTotal', L, 18, 22, LRUN, 'write', 0, 'not captured'),
], key=lambda r: (r[1], r[2], r[3]))


class StateRoundTwoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_state_root()
        cls.paths = base.make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb, mains=MAINS2)
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)
        cls.db = cls.paths.db

    def ask(self, query, *args, **kwargs):
        out = io.StringIO()
        status = query(self.paths, *args, out=out, **kwargs)
        lines, block = split(out.getvalue())
        return status, lines, block

    def test_clean_update(self):
        self.assertEqual(self.status, 0, '\n'.join(self.log))

    def test_implementing_units(self):
        self.assertEqual(rows(self.db, 'SELECT i.class_name, i.category, i.file, i.line, i.col, i.arc, t.main_file '
                                       'FROM objc_impl i JOIN tu t ON t.id = i.tu ORDER BY i.file, i.line'),
                         [('Arrays', None, D, 16, 17, 1, D),
                          ('Lam', None, L, 6, 17, 1, L),
                          ('MrcNote', None, MN, 3, 17, 0, MN),
                          ('Dual', None, MN, 18, 17, 0, MN),
                          ('Dual', 'Arc', MR, 3, 17, 1, MR),
                          ('Locker', None, SY, 15, 17, 1, SY)])

    def test_every_ivar_reference_exactly(self):
        got = rows(self.db, 'SELECT %s FROM ivar_ref r ORDER BY r.file, r.line, r.col, r.enclosing_name' % REF2_COLUMNS)
        self.assertEqual(got, EXPECTED_IVAR_REFS2)

    def test_every_static_reference_exactly(self):
        got = rows(self.db, 'SELECT r.name, r.file, r.line, r.col, r.enclosing_name, r.access, r.partial, r.in_lambda '
                            'FROM static_ref r ORDER BY r.file, r.line, r.col')
        self.assertEqual(got, EXPECTED_STATIC_REFS2)

    def test_manual_class_governs_its_ownership(self):
        status, lines, block = self.ask(codedb.ivars, 'MrcNote')
        self.assertEqual(status, 0, '\n'.join(lines) + block)
        self.assertEqual(lines[1], 'MrcNote is implemented in sources/mrc_note.m, compiled with manual reference '
                                   'counting')
        self.assertEqual(lines[2], codedb.MRC_NOTE)
        text = '\n'.join(lines)
        self.assertIn('_button  sources/mrc_note.h:11:8  interface, protected  id, object id, manual (manual reference '
                      'counting, the class\'s own code)  CONFLICT: MrcNote is implemented in sources/mrc_note.m, '
                      'compiled with manual reference counting, which governs; as seen by units of the other mode '
                      '(not the class\'s own code): ARC: __strong id, strong (recorded by sources/mrc_reader.m)  '
                      'targets T', lines)
        i = lines.index([x for x in lines if x.startswith('_button ')][0])
        self.assertEqual(lines[i + 1:i + 4], [
            '    references 1: write 1; direct 1, synthesized accessor 0; in blocks 0; from other objects 0; from '
            'other classes 0; from other files 0',
            '    by method: -[MrcNote setUp:] 1 (write 1)',
            '    retain hint (a hint, not proof): never retained or released in this class (effectively an unretained '
            'reference)'])
        self.assertIn('    retain hint (a hint, not proof): retained or released by hand in 4 places (assigned an '
                      'owned result 2, release 2)', lines)
        self.assertIn('    retain hint (a hint, not proof): retained or released by hand in 2 places (assigned an '
                      'owned result 1, autorelease 1)', lines)
        self.assertIn('    retain hint (a hint, not proof): retained by the synthesized setter of property title '
                      '(nonatomic,retain)', lines)
        # No hint for a scalar.
        j = lines.index([x for x in lines if x.startswith('_size ')][0])
        self.assertFalse(lines[j + 3].startswith('    retain hint'), lines[j + 3])
        self.assertNotIn('units disagree', text)

    def test_class_implemented_in_both_modes(self):
        status, lines, block = self.ask(codedb.ivars, 'Dual')
        self.assertEqual(status, 0, '\n'.join(lines) + block)
        self.assertEqual(lines[1], 'Dual is implemented in both modes: sources/mrc_note.m (manual reference counting), '
                                   'sources/mrc_reader.m (category Arc, ARC); each governs the references in its own '
                                   'file')
        self.assertIn('_shared  sources/mrc_note.h:20:8  interface, protected  CONFLICT: Dual is implemented in both '
                      'modes: sources/mrc_note.m (manual reference counting), sources/mrc_reader.m (category Arc, '
                      'ARC); each governs the references in its own file: ARC: __strong id, strong (recorded by '
                      'sources/mrc_reader.m); manual reference counting: id, manual (recorded by sources/mrc_note.m)  '
                      'targets T', lines)
        self.assertIn('    retain hint (a hint, not proof): never retained or released in this class (effectively an '
                      'unretained reference)', lines)

    def test_ivarrefs_names_the_implementation(self):
        status, lines, block = self.ask(codedb.ivarrefs, 'MrcNote', '_kept')
        self.assertEqual(status, 0)
        self.assertEqual(lines[1], 'MrcNote is implemented in sources/mrc_note.m, compiled with manual reference '
                                   'counting')
        self.assertIn('sources/mrc_note.m:10:6  -[MrcNote setUp:]  read  base implicit self  receives release  '
                      'targets T', lines)
        self.assertIn('sources/mrc_note.m:6:5  -[MrcNote setUp:]  write  base implicit self  assigned an owned result  '
                      'targets T', lines)

    def test_synchronized_in_ivars(self):
        status, lines, block = self.ask(codedb.ivars, 'Locker')
        self.assertEqual(status, 0, '\n'.join(lines) + block)
        self.assertIn('    used as the lock of @synchronized bodies that access: _a 1, _b 2', lines)
        self.assertIn('    inside @synchronized bodies: 4 of 5 references (on _lock 1, self 1, sLock 1, [self other] '
                      '1; 1 of them in a block, which can run after the lock is released)', lines)
        self.assertIn('    inside @synchronized bodies: 3 of 3 references (on _lock 2, class Locker 1)', lines)
        self.assertIn(codedb.STATE_LIMITS_LINE, lines)

    def test_ivarrefs_lock(self):
        status, lines, block = self.ask(codedb.ivarrefs, 'Locker', '_a')
        self.assertEqual(status, 0)
        self.assertIn('sources/sync.m:41:32  -[Locker work]  write  base implicit self  in block (captures self '
                      'strongly)  under @synchronized ([self other])  targets T', lines)
        self.assertIn('sources/sync.m:25:9  -[Locker work]  write  base implicit self  under @synchronized (_lock)  '
                      'targets T', lines)

    def test_lambda_capture_in_ivarrefs(self):
        status, lines, block = self.ask(codedb.ivarrefs, 'Lam', '_k')
        self.assertIn('sources/lambda.mm:14:26  -[Lam run]  write  base implicit self  in lambda (self by reference)  '
                      'targets T', lines)

    def test_staticrefs_of_decayed_array(self):
        status, lines, block = self.ask(codedb.staticrefs, 'gName')
        self.assertEqual(status, 0)
        self.assertIn('gName  sources/decay.m:13:13  file-static  char[8], array  initializer none  written (counting '
                      'address-of and by-reference uses) from 1 function  targets T', lines)
        self.assertIn('  sources/decay.m:43:12  -[Arrays mutableName]  byref  targets T', lines)


DUP_ENTRIES = (('T', 'sources/dup_a.c'), ('U', 'sources/dup_b.c'))


class StaticTargetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_state_root()
        cls.paths = base.make_paths(cls.root)
        base.write_project(cls.root, {t: [m] for t, m in DUP_ENTRIES})
        meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(cls.root)}
        with open(cls.paths.cdb, 'w') as f:
            f.write(json.dumps(meta) + '\n')
            for t, m in DUP_ENTRIES:
                f.write(json.dumps({'target': t, 'file': m, 'directory': cls.root,
                                    'arguments': base.clang_args(cls.root, m)}) + '\n')
        cls.status = codedb.update(cls.paths, log=lambda m: None)

    def ask(self, query, *args, **kwargs):
        out = io.StringIO()
        status = query(self.paths, *args, out=out, **kwargs)
        return status, split(out.getvalue())[0]

    def test_globals_of_two_targets_are_separate(self):
        status, lines = self.ask(codedb.staticrefs, 'gDup')
        self.assertEqual(status, 0, '\n'.join(lines))
        self.assertEqual(lines[0], 'Statics named gDup: 2; references: 2')
        self.assertEqual(lines[1:], [
            'gDup  sources/dup_a.c:3:5  global  int, scalar  initializer literal  in target T (2 targets define '
            'gDup: each has its own)  written (counting address-of and by-reference uses) from 1 function  targets T',
            '    also declared: extern at sources/dup.h:2:12',
            '  sources/dup_a.c:5:5  SetA  write  targets T',
            'gDup  sources/dup_b.c:3:5  global  int, scalar  initializer literal  in target U (2 targets define '
            'gDup: each has its own)  written (counting address-of and by-reference uses) from 1 function  targets U',
            '    also declared: extern at sources/dup.h:2:12',
            '  sources/dup_b.c:5:5  SetB  write  targets U',
            codedb.STATE_LIMITS_LINE,
            codedb.STATE_SWIFT_LINE_STATICS])

    def test_header_static_per_unit(self):
        status, lines = self.ask(codedb.staticrefs, 'sHeaderCounter', per_unit=True)
        self.assertEqual(status, 0, '\n'.join(lines))
        self.assertIn('sHeaderCounter  sources/dup.h:3:12  file-static  int, scalar  initializer none  defined in a '
                      'header: each including unit has its own copy; 2 units include it  written (counting address-of '
                      'and by-reference uses) from 2 functions  targets T,U', lines)
        self.assertIn('    in unit sources/dup_a.c (target T): SetA: rmw 1', lines)
        self.assertIn('    in unit sources/dup_b.c (target U): SetB: write 1', lines)


class ModuleCacheTest(unittest.TestCase):
    def test_command_digest_ignores_the_module_cache(self):
        a = ['-x', 'objective-c', '-fmodules-cache-path=/one', 'x.m']
        b = ['-x', 'objective-c', '-fmodules-cache-path=/two', 'x.m']
        self.assertEqual(codedb.command_digest(a), codedb.command_digest(b))
        self.assertNotEqual(codedb.command_digest(a), codedb.command_digest(['-x', 'objective-c', 'y.m']))

    def test_a_copy_with_its_own_module_cache_is_current(self):
        root = make_state_root()
        paths = base.make_paths(root)
        write_cdb(root, paths.cdb, mains=MAINS[:1])
        # The compile database names one module cache, as build_cdb writes it.
        entries = list(codedb.read_cdb(paths.cdb))
        with open(paths.cdb, 'w') as f:
            for e in entries:
                if not e.get('meta'):
                    e['arguments'] = e['arguments'] + ['-fmodules-cache-path=' + os.path.join(root, 'cache-a')]
                f.write(json.dumps(e) + '\n')
        self.assertEqual(codedb.update(paths, log=lambda m: None), 0)
        other = os.path.join(root, 'cache-b')
        copy = codedb.Paths(root, db=paths.db, cdb=paths.cdb, extractor=paths.extractor, module_cache=other)
        log = []
        self.assertEqual(codedb.update(copy, log=log.append), 0)
        self.assertTrue(any('skipped as current 1' in m for m in log), log)
        self.assertNotIn('command changed', '\n'.join(log))
        # A unit extracted under the copy (here from the command line) is
        # given the copy's cache, and stays current for both.
        saved = sys.stderr
        sys.stderr = io.StringIO()
        try:
            status = codedb.main(['--root', root, '--db', paths.db, '--cdb', paths.cdb, '--extractor',
                                  paths.extractor, '--module-cache', other, 'update', '--objc-only', '--force'])
        finally:
            sys.stderr = saved
        self.assertEqual(status, 0)
        self.assertEqual(rows(paths.db, "SELECT count(*) FROM tu WHERE arguments LIKE '%cache-b%'"), [(1,)])
        log = []
        self.assertEqual(codedb.update(paths, log=log.append), 0)
        self.assertTrue(any('skipped as current 1' in m for m in log), log)


if __name__ == '__main__':
    unittest.main()
