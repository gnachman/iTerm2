#!/usr/bin/env python3
"""Tests for the code database's declarations and references: methods,
properties, @selector expressions, reflective calls, the claims on header
declarations, and the methods, selrefs, reflective and reach queries.

Run with the other code database tests:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_*.py'

Like test_codedb.py, it needs only Homebrew LLVM and the SDK: the fixtures
under selector_fixtures/ declare their own root class and runtime functions.
Expected rows are written out by hand from the fixtures.
"""

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
import test_codedb as base  # noqa: E402

SELECTOR_FIXTURES = os.path.join(HERE, 'selector_fixtures')
H = 'sources/methods.h'
M = 'sources/methods.m'
S = 'sources/selectors.m'
NO_MACRO = (None, None, None, None, None, None)
# The captions of reach's group of methods declared in parsed code of the
# repository, with 0 and 1 rows.
INSIDE_NONE = ('Methods in this repository that it overrides or protocol requirements it satisfies: 0 (Objective-C '
               'sends to the class or protocol are among the message sends above; Swift callers are not in this '
               'database)')
INSIDE_ONE = ('Methods in this repository that it overrides or protocol requirements it satisfies: 1 (Objective-C '
              'sends to the class or protocol are among the message sends above; Swift callers are not in this '
              'database)')
NO_OBJC_CALLER = ('No Objective-C caller found. This selector satisfies or overrides declarations in this repository '
                  '(listed above); callers written in Swift, or reaching it through a xib, are not in this database.')


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def make_selector_root():
    d = base.make_temp('codedb-sel-')
    root = os.path.join(d, 'repo')
    shutil.copytree(SELECTOR_FIXTURES, root)
    return root


def extract(root, main, db, target='T'):
    return base.extract(root, main, db, target=target)


def rows(db, sql):
    con = sqlite3.connect(db)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


METHOD_COLUMNS = ('selector, is_class_method, container_name, container_kind, is_definition, is_implicit, '
                  'is_synthesized_accessor, is_optional, property_usr, return_type, file, line, col, macro_name, '
                  'macro_file, macro_line, macro_role, expansion_line, expansion_col')
PROPERTY_COLUMNS = ('name, kind, is_class_property, container_name, container_kind, getter_selector, setter_selector, '
                    'attributes, ivar_name, is_readonly, is_implicit, type, file, line, col')
SELREF_COLUMNS = ('selector, kind, enclosing_name, in_block, file, line, col, macro_name, macro_file, macro_line, '
                  'macro_role, expansion_line, expansion_col')
REFLECTIVE_COLUMNS = ('file, line, col, function_or_selector, call_kind, kind, argument_index, argument_kind, '
                      'argument_text, argument_constant, resolved_selector, resolved_class, receiver_type, '
                      'enclosing_name, in_block, macro_name, macro_role')

COUNT = 'c:objc(cs)Gadget(py)count'
ON = 'c:objc(cs)Gadget(py)on'
SIZE = 'c:objc(cs)Gadget(py)size'
SIDES = 'c:objc(pl)Shape(py)sides'

# Every method in methods.h and methods.m, by hand from the fixtures.
EXPECTED_METHODS = [
    ('sides', 0, 'Shape', 'protocol', 0, 1, 0, 0, SIDES, 'int', H, 4, 37) + NO_MACRO,
    ('draw', 0, 'Shape', 'protocol', 0, 0, 0, 0, None, 'void', H, 5, 9) + NO_MACRO,
    ('shapeNamed:', 1, 'Shape', 'protocol', 0, 0, 0, 1, None, 'id', H, 7, 7) + NO_MACRO,
    # Auto-synthesized accessors: declared in the interface and synthesized
    # in the implementation, both at the property.
    ('count', 0, 'Gadget', 'implementation', 0, 1, 1, 0, COUNT, 'int', H, 10, 27) + NO_MACRO,
    ('count', 0, 'Gadget', 'interface', 0, 1, 0, 0, COUNT, 'int', H, 10, 27) + NO_MACRO,
    ('setCount:', 0, 'Gadget', 'implementation', 0, 1, 1, 0, COUNT, 'void', H, 10, 27) + NO_MACRO,
    ('setCount:', 0, 'Gadget', 'interface', 0, 1, 0, 0, COUNT, 'void', H, 10, 27) + NO_MACRO,
    # getter= and setter=.
    ('isOn', 0, 'Gadget', 'implementation', 0, 1, 1, 0, ON, 'int', H, 11, 54) + NO_MACRO,
    ('isOn', 0, 'Gadget', 'interface', 0, 1, 0, 0, ON, 'int', H, 11, 54) + NO_MACRO,
    ('turn:', 0, 'Gadget', 'implementation', 0, 1, 1, 0, ON, 'void', H, 11, 54) + NO_MACRO,
    ('turn:', 0, 'Gadget', 'interface', 0, 1, 0, 0, ON, 'void', H, 11, 54) + NO_MACRO,
    # Readonly with a custom getter that the implementation writes: no
    # synthesized accessor.
    ('label', 0, 'Gadget', 'interface', 0, 1, 0, 0, 'c:objc(cs)Gadget(py)name', 'id', H, 12, 50) + NO_MACRO,
    # Readonly here, readwrite in the class extension: the setter is declared
    # there.
    ('size', 0, 'Gadget', 'implementation', 0, 1, 1, 0, SIZE, 'int', H, 13, 37) + NO_MACRO,
    ('size', 0, 'Gadget', 'interface', 0, 1, 0, 0, SIZE, 'int', H, 13, 37) + NO_MACRO,
    # @dynamic: declared, never synthesized.
    ('dyn', 0, 'Gadget', 'interface', 0, 1, 0, 0, 'c:objc(cs)Gadget(py)dyn', 'id', H, 14, 34) + NO_MACRO,
    ('setDyn:', 0, 'Gadget', 'interface', 0, 1, 0, 0, 'c:objc(cs)Gadget(py)dyn', 'void', H, 14, 34) + NO_MACRO,
    ('setShared:', 1, 'Gadget', 'interface', 0, 1, 0, 0, 'c:objc(cs)Gadget(cpy)shared', 'void', H, 15, 34) + NO_MACRO,
    ('shared', 1, 'Gadget', 'interface', 0, 1, 0, 0, 'c:objc(cs)Gadget(cpy)shared', 'int', H, 15, 34) + NO_MACRO,
    ('reset:with:', 0, 'Gadget', 'interface', 0, 0, 0, 0, None, 'void', H, 16, 9) + NO_MACRO,
    ('extra', 0, 'Gadget(Extras)', 'category', 0, 0, 0, 0, None, 'void', H, 19, 9) + NO_MACRO,
    ('extraCount', 0, 'Gadget(Extras)', 'category', 0, 1, 0, 0, 'c:objc(cs)Gadget(py)extraCount', 'int', H, 20,
     37) + NO_MACRO,
    ('setSize:', 0, 'Gadget()', 'extension', 0, 1, 0, 0, SIZE, 'void', M, 8, 38) + NO_MACRO,
    ('setSize:', 0, 'Gadget', 'implementation', 0, 1, 1, 0, SIZE, 'void', M, 8, 38) + NO_MACRO,
    ('hidden', 0, 'Gadget()', 'extension', 0, 0, 0, 0, None, 'void', M, 9, 9) + NO_MACRO,
    # Declared by a macro's body: recorded where the macro is used.
    ('weakSelf', 0, 'Gadget()', 'extension', 0, 0, 0, 0, None, 'id', M, 10, 1, 'DECLARE_WEAK', M, 6, 'body', 10, 1),
    # @synthesize of a protocol's property: at the @synthesize.
    ('sides', 0, 'Gadget', 'implementation', 0, 1, 1, 0, SIDES, 'int', M, 13, 1) + NO_MACRO,
    ('shared', 1, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'int', M, 15, 8) + NO_MACRO,
    ('setShared:', 1, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'void', M, 16, 9) + NO_MACRO,
    ('label', 0, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'id', M, 17, 7) + NO_MACRO,
    ('draw', 0, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'void', M, 18, 9) + NO_MACRO,
    ('hidden', 0, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'void', M, 19, 9) + NO_MACRO,
    ('reset:with:', 0, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'void', M, 20, 9) + NO_MACRO,
    ('weakSelf', 0, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'id', M, 21, 7) + NO_MACRO,
    # Made by token pasting: the assembled selector, at the macro's use.
    ('key_alpha', 1, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'id', M, 22, 1, 'DEFINE_SETTING', M, 3, 'pasted',
     22, 1),
    ('load_alpha', 1, 'Gadget', 'implementation', 1, 0, 0, 0, None, 'int', M, 22, 1, 'DEFINE_SETTING', M, 3, 'pasted',
     22, 1),
    ('extra', 0, 'Gadget(Extras)', 'category-implementation', 1, 0, 0, 0, None, 'void', M, 25, 9) + NO_MACRO,
    ('extraCount', 0, 'Gadget(Extras)', 'category-implementation', 1, 0, 0, 0, None, 'int', M, 26, 8) + NO_MACRO,
]

EXPECTED_PROPERTIES = [
    ('sides', 'declaration', 0, 'Shape', 'protocol', 'sides', None, 'nonatomic,readonly', None, 1, 0, 'int', H, 4, 37),
    ('count', 'declaration', 0, 'Gadget', 'interface', 'count', 'setCount:', 'nonatomic', None, 0, 0, 'int', H, 10,
     27),
    ('count', 'synthesize', 0, 'Gadget', 'implementation', 'count', 'setCount:', 'nonatomic', '_count', 0, 1, 'int',
     H, 10, 27),
    ('on', 'declaration', 0, 'Gadget', 'interface', 'isOn', 'turn:', 'nonatomic,getter=isOn,setter=turn:', None, 0,
     0, 'int', H, 11, 54),
    ('on', 'synthesize', 0, 'Gadget', 'implementation', 'isOn', 'turn:', 'nonatomic,getter=isOn,setter=turn:', '_on',
     0, 1, 'int', H, 11, 54),
    ('name', 'declaration', 0, 'Gadget', 'interface', 'label', None, 'nonatomic,readonly,getter=label', None, 1, 0,
     'id', H, 12, 50),
    # Readonly as written here, although the class extension makes it
    # readwrite.
    ('size', 'declaration', 0, 'Gadget', 'interface', 'size', None, 'nonatomic,readonly', None, 1, 0, 'int', H, 13,
     37),
    ('dyn', 'declaration', 0, 'Gadget', 'interface', 'dyn', 'setDyn:', 'nonatomic,strong', None, 0, 0, 'id', H, 14,
     34),
    ('shared', 'declaration', 1, 'Gadget', 'interface', 'shared', 'setShared:', 'class,nonatomic', None, 0, 0, 'int',
     H, 15, 34),
    ('extraCount', 'declaration', 0, 'Gadget(Extras)', 'category', 'extraCount', None, 'nonatomic,readonly', None, 1,
     0, 'int', H, 20, 37),
    ('size', 'declaration', 0, 'Gadget()', 'extension', 'size', 'setSize:', 'nonatomic,readwrite', None, 0, 0, 'int',
     M, 8, 38),
    ('size', 'synthesize', 0, 'Gadget', 'implementation', 'size', 'setSize:', 'nonatomic,readwrite', '_size', 0, 1,
     'int', M, 8, 38),
    ('sides', 'synthesize', 0, 'Gadget', 'implementation', 'sides', None, 'nonatomic,readonly', '_sides', 1, 0, 'int',
     M, 13, 13),
    ('dyn', 'dynamic', 0, 'Gadget', 'implementation', 'dyn', 'setDyn:', 'nonatomic,strong', None, 0, 0, 'id', M, 14,
     10),
]

EXPECTED_SELECTOR_REFS = [
    ('save:', 'selector-expr', 'Selectors', 0, S, 10, 36) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 11, 23) + NO_MACRO,
    ('save:', 'selector-expr', 'Selectors', 0, S, 12, 23) + NO_MACRO,
    ('insert:at:', 'selector-expr', 'Selectors', 0, S, 13, 23) + NO_MACRO,
    # In a macro argument, and in a macro's body.
    ('open:', 'selector-expr', 'Selectors', 0, S, 14, 20, 'SEL_OF', S, 3, 'argument', 14, 13),
    ('reload', 'selector-expr', 'Selectors', 0, S, 15, 13, 'RELOAD_SEL', S, 4, 'body', 15, 13),
    ('inBlock', 'selector-expr', 'Selectors', 1, S, 16, 44) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 17, 57) + NO_MACRO,
    ('Gadget', 'selector-expr', 'Selectors', 0, S, 22, 54) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 26, 34) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 30, 37) + NO_MACRO,
    ('title', 'selector-expr', 'Selectors', 0, S, 34, 51) + NO_MACRO,
    ('count', 'selector-expr', 'Selectors', 0, S, 38, 64) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 42, 28) + NO_MACRO,
    ('save:', 'selector-expr', 'Selectors', 0, S, 46, 26) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 48, 84) + NO_MACRO,
    ('reload', 'selector-expr', 'Selectors', 0, S, 50, 50) + NO_MACRO,
]

F, MSG = 'function', 'message'
B = 'Base *'
SEL_FN = 'Selectors'
EXPECTED_REFLECTIVE = [
    # A stringified macro argument (@#name) is a string literal.
    (M, 22, 1, 'valueForKey:', MSG, 'key', 0, 'string-literal', 'alpha', None, None, None, 'Class',
     '+[Gadget key_alpha]', 0, 'DEFINE_SETTING', 'body'),
    # NSSelectorFromString: each argument kind, and adjacent literals joined.
    (S, 17, 5, 'NSSelectorFromString', F, 'selector', 0, 'selector-expr', 'reload', None, 'reload', None, None, SEL_FN,
     0, None, None),
    (S, 18, 5, 'NSSelectorFromString', F, 'selector', 0, 'string-literal', 'reload', None, 'reload', None, None,
     SEL_FN, 0, None, None),
    (S, 19, 5, 'NSSelectorFromString', F, 'selector', 0, 'string-literal', 'reload', None, 'reload', None, None,
     SEL_FN, 0, None, None),
    (S, 20, 5, 'NSSelectorFromString', F, 'selector', 0, 'constant', 'name', 'kNameKey', 'name', None, None, SEL_FN, 0,
     None, None),
    (S, 21, 5, 'NSSelectorFromString', F, 'selector', 0, 'dynamic', 'dynamicName', None, None, None, None, SEL_FN, 0,
     None, None),
    # NSClassFromString.
    (S, 22, 5, 'NSClassFromString', F, 'class', 0, 'selector-expr', 'Gadget', None, 'Gadget', 'Gadget', None, SEL_FN,
     0, None, None),
    (S, 23, 5, 'NSClassFromString', F, 'class', 0, 'string-literal', 'Gadget', None, None, 'Gadget', None, SEL_FN, 0,
     None, None),
    (S, 24, 5, 'NSClassFromString', F, 'class', 0, 'constant', 'name', 'kNameKey', None, 'name', None, SEL_FN, 0, None,
     None),
    (S, 25, 5, 'NSClassFromString', F, 'class', 0, 'dynamic', 'dynamicName', None, None, None, None, SEL_FN, 0, None,
     None),
    # performSelector: and a variant; a call that turns a literal or constant
    # into a selector counts as that literal or constant.
    (S, 26, 8, 'performSelector:', MSG, 'selector', 0, 'selector-expr', 'reload', None, 'reload', None, B, SEL_FN, 0,
     None, None),
    (S, 27, 8, 'performSelector:', MSG, 'selector', 0, 'string-literal', 'save:', None, 'save:', None, B, SEL_FN, 0,
     None, None),
    (S, 27, 24, 'NSSelectorFromString', F, 'selector', 0, 'string-literal', 'save:', None, 'save:', None, None, SEL_FN,
     0, None, None),
    (S, 28, 8, 'performSelector:', MSG, 'selector', 0, 'constant', 'save:', 'kSaveSel', 'save:', None, B, SEL_FN, 0,
     None, None),
    (S, 29, 8, 'performSelector:withObject:afterDelay:', MSG, 'selector', 0, 'dynamic', 's', None, None, None, B,
     SEL_FN, 0, None, None),
    # respondsToSelector:.
    (S, 30, 8, 'respondsToSelector:', MSG, 'selector', 0, 'selector-expr', 'reload', None, 'reload', None, B, SEL_FN,
     0, None, None),
    (S, 31, 8, 'respondsToSelector:', MSG, 'selector', 0, 'string-literal', 'save:', None, 'save:', None, B, SEL_FN, 0,
     None, None),
    (S, 31, 27, 'NSSelectorFromString', F, 'selector', 0, 'string-literal', 'save:', None, 'save:', None, None, SEL_FN,
     0, None, None),
    (S, 32, 8, 'respondsToSelector:', MSG, 'selector', 0, 'constant', 'name', 'kNameKey', 'name', None, B, SEL_FN, 0,
     None, None),
    (S, 32, 27, 'NSSelectorFromString', F, 'selector', 0, 'constant', 'name', 'kNameKey', 'name', None, None, SEL_FN,
     0, None, None),
    (S, 33, 8, 'respondsToSelector:', MSG, 'selector', 0, 'dynamic', 's', None, None, None, B, SEL_FN, 0, None, None),
    # valueForKey:; the constant is a macro whose replacement is a literal.
    (S, 34, 8, 'valueForKey:', MSG, 'key', 0, 'selector-expr', 'title', None, 'title', None, B, SEL_FN, 0, None, None),
    (S, 35, 8, 'valueForKey:', MSG, 'key', 0, 'string-literal', 'title', None, None, None, B, SEL_FN, 0, None, None),
    (S, 36, 8, 'valueForKey:', MSG, 'key', 0, 'constant', 'title', 'kTitleKey', None, None, B, SEL_FN, 0, None, None),
    (S, 37, 8, 'valueForKey:', MSG, 'key', 0, 'dynamic', 'dynamicName', None, None, None, B, SEL_FN, 0, None, None),
    # addObserver:forKeyPath:options:context:.
    (S, 38, 8, 'addObserver:forKeyPath:options:context:', MSG, 'key-path', 1, 'selector-expr', 'count', None, 'count',
     None, B, SEL_FN, 0, None, None),
    (S, 39, 8, 'addObserver:forKeyPath:options:context:', MSG, 'key-path', 1, 'string-literal', 'title', None, None,
     None, B, SEL_FN, 0, None, None),
    (S, 40, 8, 'addObserver:forKeyPath:options:context:', MSG, 'key-path', 1, 'constant', 'name', 'kNameKey', None,
     None, B, SEL_FN, 0, None, None),
    (S, 41, 8, 'addObserver:forKeyPath:options:context:', MSG, 'key-path', 1, 'dynamic', 'dynamicName', None, None,
     None, B, SEL_FN, 0, None, None),
    # setAction:, and its dot-syntax form.
    (S, 42, 8, 'setAction:', MSG, 'selector', 0, 'selector-expr', 'reload', None, 'reload', None, B, SEL_FN, 0, None,
     None),
    (S, 43, 8, 'setAction:', MSG, 'selector', 0, 'string-literal', 'open:', None, 'open:', None, B, SEL_FN, 0, None,
     None),
    (S, 43, 18, 'NSSelectorFromString', F, 'selector', 0, 'string-literal', 'open:', None, 'open:', None, None, SEL_FN,
     0, None, None),
    (S, 44, 8, 'setAction:', MSG, 'selector', 0, 'constant', 'save:', 'kSaveSel', 'save:', None, B, SEL_FN, 0, None,
     None),
    (S, 45, 8, 'setAction:', MSG, 'selector', 0, 'dynamic', 's', None, None, None, B, SEL_FN, 0, None, None),
    (S, 46, 7, 'setAction:', MSG, 'selector', 0, 'selector-expr', 'save:', None, 'save:', None, B, SEL_FN, 0, None,
     None),
    (S, 47, 8, 'setValue:forKey:', MSG, 'key', 1, 'string-literal', 'title', None, None, None, B, SEL_FN, 0, None,
     None),
    # Swizzling: the Method's selector and class, followed one call down.
    (S, 48, 5, 'method_exchangeImplementations', F, 'method', 0, 'selector-expr', 'reload', None, 'reload', 'Base',
     None, SEL_FN, 0, None, None),
    (S, 48, 5, 'method_exchangeImplementations', F, 'method', 1, 'dynamic',
     'class_getInstanceMethod(NSClassFromString(@"Gadget"), s)', None, None, None, None, SEL_FN, 0, None, None),
    (S, 48, 36, 'class_getInstanceMethod', F, 'selector', 1, 'selector-expr', 'reload', None, 'reload', 'Base', None,
     SEL_FN, 0, None, None),
    (S, 49, 36, 'class_getInstanceMethod', F, 'selector', 1, 'dynamic', 's', None, None, 'Gadget', None, SEL_FN, 0,
     None, None),
    (S, 49, 60, 'NSClassFromString', F, 'class', 0, 'string-literal', 'Gadget', None, None, 'Gadget', None, SEL_FN, 0,
     None, None),
    # objc_msgSend called through a cast.
    (S, 50, 23, 'objc_msgSend', F, 'selector', 1, 'selector-expr', 'reload', None, 'reload', None, None, SEL_FN, 0,
     None, None),
    (S, 51, 5, 'sel_registerName', F, 'selector', 0, 'string-literal', 'save:', None, 'save:', None, None, SEL_FN, 0,
     None, None),
]


class DeclarationTablesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'd.sqlite')
        cls.status_m, cls.stderr_m, _ = extract(cls.root, M, cls.db)
        cls.status_s, cls.stderr_s, _ = extract(cls.root, S, cls.db)

    def test_clean_status(self):
        self.assertEqual((self.status_m, self.status_s), (0, 0), self.stderr_m + self.stderr_s)

    def test_every_method_exactly(self):
        self.assertEqual(rows(self.db, "SELECT %s FROM objc_method WHERE file != 'sources/sel_base.h' "
                                       "ORDER BY file, line, col, selector, container_kind" % METHOD_COLUMNS),
                         EXPECTED_METHODS)

    def test_every_container_kind(self):
        self.assertEqual(rows(self.db, 'SELECT DISTINCT container_kind FROM objc_method ORDER BY 1'),
                         [('category',), ('category-implementation',), ('extension',), ('implementation',),
                          ('interface',), ('protocol',)])

    def test_identifiers_and_encodings(self):
        self.assertEqual(rows(self.db, "SELECT usr, container_usr, type_encoding, in_migration_scope FROM objc_method "
                                       "WHERE selector IN ('reset:with:', 'load_alpha') ORDER BY file, selector"),
                         [('c:objc(cs)Gadget(im)reset:with:', 'c:objc(cs)Gadget', 'v24@0:8i16i20', 1),
                          ('c:objc(cs)Gadget(cm)load_alpha', 'c:objc(cs)Gadget', 'i16@0:8', 1),
                          ('c:objc(cs)Gadget(im)reset:with:', 'c:objc(cs)Gadget', 'v24@0:8i16i20', 1)])
        self.assertEqual(rows(self.db, "SELECT DISTINCT container_usr FROM objc_method WHERE container_kind IN "
                                       "('category', 'category-implementation', 'protocol')"),
                         [('c:objc(pl)Shape',), ('c:objc(cy)Gadget@Extras',)])

    def test_header_of_the_root_class(self):
        # The fixture's own runtime header is in the repository, so its
        # methods are recorded too, once.
        self.assertEqual(rows(self.db, "SELECT count(*), count(DISTINCT tu) FROM objc_method WHERE "
                                       "file = 'sources/sel_base.h'"), [(11, 1)])

    def test_every_property_exactly(self):
        self.assertEqual(rows(self.db, 'SELECT %s FROM objc_property ORDER BY file, line, col, kind' % PROPERTY_COLUMNS),
                         EXPECTED_PROPERTIES)

    def test_property_usr_joins_its_accessors(self):
        self.assertEqual(rows(self.db, "SELECT DISTINCT p.name, m.selector FROM objc_property p JOIN objc_method m ON "
                                       "m.property_usr = p.usr WHERE p.name = 'on' ORDER BY 2"),
                         [('on', 'isOn'), ('on', 'turn:')])

    def test_every_selector_expression_exactly(self):
        self.assertEqual(rows(self.db, 'SELECT %s FROM selector_ref ORDER BY file, line, col' % SELREF_COLUMNS),
                         EXPECTED_SELECTOR_REFS)

    def test_every_reflective_call_exactly(self):
        self.assertEqual(rows(self.db, 'SELECT %s FROM reflective_call ORDER BY file, line, col, argument_index'
                                       % REFLECTIVE_COLUMNS), EXPECTED_REFLECTIVE)

    def test_each_argument_kind_for_each_required_call(self):
        kinds = {}
        for name, kind in rows(self.db, 'SELECT function_or_selector, argument_kind FROM reflective_call'):
            kinds.setdefault(name, set()).add(kind)
        every = {'selector-expr', 'string-literal', 'constant', 'dynamic'}
        for name in ('NSSelectorFromString', 'NSClassFromString', 'respondsToSelector:', 'valueForKey:',
                     'addObserver:forKeyPath:options:context:', 'setAction:'):
            self.assertEqual(kinds[name], every, name)
        self.assertEqual(kinds['performSelector:'] | kinds['performSelector:withObject:afterDelay:'], every)

    def test_sends_of_the_fixture_are_still_recorded(self):
        # Reflective calls are sends as well.
        self.assertEqual(rows(self.db, "SELECT count(*) FROM send WHERE file = 'sources/selectors.m'"), [(23,)])


LONG_NAME = 'a' * 210
SHAPES = (
    '// Fixture written by the test. Line numbers are part of the expectations.\n'
    '#import "sel_base.h"\n'
    'void Shapes(Base *b, NSString *n, NSString *%s) {\n'
    '    [b valueForKey:[n\n'
    '                       self_or_nil]];\n'
    '    [b valueForKey:%s];\n'
    '    (void)sizeof(@selector(unevaluated));\n'
    '    __typeof__(NSSelectorFromString(@"typeofArgument")) t = 0;\n'
    '    b.action = NSSelectorFromString(@"viaDotSyntax");\n'
    '    ((Base *)NSClassFromString(@"Receiver")).action = @selector(viaBase);\n'
    '    (void)t;\n'
    '}\n') % (LONG_NAME, LONG_NAME)


class MoreShapesTest(unittest.TestCase):
    def test_dynamic_text_unevaluated_operands_and_dot_syntax(self):
        root = make_selector_root()
        with open(os.path.join(root, 'sources', 'sel_base.h'), 'a') as f:
            f.write('@interface NSString (Fixture)\n- (NSString *)self_or_nil;\n@end\n')
        with open(os.path.join(root, 'sources', 'shapes.m'), 'w') as f:
            f.write(SHAPES)
        db = os.path.join(os.path.dirname(root), 's.sqlite')
        status, stderr, _ = extract(root, 'sources/shapes.m', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(rows(db, 'SELECT line, col, function_or_selector, argument_kind, argument_text FROM '
                                  'reflective_call ORDER BY line, col'), [
            # Whitespace in the spelling is collapsed to one space.
            (4, 8, 'valueForKey:', 'dynamic', '[n self_or_nil]'),
            # At most 200 bytes.
            (6, 8, 'valueForKey:', 'dynamic', 'a' * 200),
            # The dot-syntax setter and the call in its right-hand side are
            # each recorded once.
            (9, 7, 'setAction:', 'string-literal', 'viaDotSyntax'),
            (9, 16, 'NSSelectorFromString', 'string-literal', 'viaDotSyntax'),
            # The base of a property reference is visited twice by the AST
            # visitor; it is recorded once.
            (10, 14, 'NSClassFromString', 'string-literal', 'Receiver'),
            (10, 46, 'setAction:', 'selector-expr', 'viaBase'),
        ])
        # Nothing in sizeof or __typeof__; the one in the dot-syntax
        # assignment once.
        self.assertEqual(rows(db, 'SELECT selector, line, col FROM selector_ref'), [('viaBase', 10, 65)])


ARGUMENTS_M = ('// Fixture written by the test. Line numbers are part of the expectations.\n'
               '#import "sel_base.h"\n'
               '#define nil ((id)0)\n'
               '#define NULL ((void *)0)\n'
               'static NSString *const kConstStatic = @"constStatic";\n'
               'static NSString *kMutableStatic = @"mutableInitial";\n'
               'static NSString *kUnassignedStatic = @"unassigned";\n'
               '@interface Holder : Base\n'
               '@end\n'
               '@implementation Holder\n'
               '- (void)run:(int)flag {\n'
               '    static NSString *const kLocalConst = @"localConst";\n'
               '    static NSString *sLocal = @"localInitial";\n'
               '    if (flag) { kMutableStatic = @"other"; sLocal = @"localOther"; }\n'
               '    [self valueForKey:kConstStatic];\n'
               '    [self valueForKey:kLocalConst];\n'
               '    [self valueForKey:kMutableStatic];\n'
               '    [self valueForKey:sLocal];\n'
               '    [self valueForKey:kUnassignedStatic];\n'
               '    [self respondsToSelector:_cmd];\n'
               '    [self valueForKey:nil];\n'
               '    NSSelectorFromString(NULL);\n'
               '    [self performSelector:NSSelectorFromString(nil)];\n'
               '}\n'
               '@end\n'
               '@interface Message : Base\n'
               '- (void)setAction:(int)a;\n'
               '@end\n'
               '// A protobuf message\'s setAction: takes an enum; its 0 is not nil.\n'
               'void SetCode(Message *m) { [m setAction:0]; }\n')


class ArgumentKindTest(unittest.TestCase):
    """Statics resolve only when they cannot change; nil and _cmd are kinds
    of their own, left out of the default listing."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        with open(os.path.join(cls.root, 'sources', 'arguments.m'), 'w') as f:
            f.write(ARGUMENTS_M)
        cls.paths = base.make_paths(cls.root)
        base.write_cdb(cls.root, cls.paths.cdb, mains=('sources/arguments.m',))
        cls.status = codedb.update(cls.paths, log=lambda m: None)

    def test_rows(self):
        self.assertEqual(self.status, 0)
        self.assertEqual(rows(self.paths.db, 'SELECT line, col, function_or_selector, argument_kind, argument_text, '
                                             'argument_constant, resolved_selector FROM reflective_call '
                                             'ORDER BY line, col'), [
            # A static or static local that is const resolves to its
            # initializer.
            (15, 11, 'valueForKey:', 'constant', 'constStatic', 'kConstStatic', None),
            (16, 11, 'valueForKey:', 'constant', 'localConst', 'kLocalConst', None),
            # One that is not const can be assigned: dynamic, whether or not
            # it is.
            (17, 11, 'valueForKey:', 'dynamic', 'kMutableStatic', None, None),
            (18, 11, 'valueForKey:', 'dynamic', 'sLocal', None, None),
            (19, 11, 'valueForKey:', 'dynamic', 'kUnassignedStatic', None, None),
            (20, 11, 'respondsToSelector:', 'self-selector', '_cmd', None, None),
            (21, 11, 'valueForKey:', 'nil', 'nil', None, None),
            (22, 5, 'NSSelectorFromString', 'nil', 'NULL', None, None),
            (23, 11, 'performSelector:', 'nil', 'NSSelectorFromString(nil)', None, None),
            (23, 27, 'NSSelectorFromString', 'nil', 'nil', None, None),
            (30, 31, 'setAction:', 'dynamic', '0', None, None),
        ])

    def test_default_listing_leaves_out_nil_and_cmd(self):
        out = io.StringIO()
        self.assertEqual(codedb.reflective(self.paths, out=out), 0)
        lines = split(out.getvalue())[0]
        self.assertEqual(lines, [
            'sources/arguments.m: 4',
            '  sources/arguments.m:17:11  -[Holder run:]  valueForKey: argument 0 (key): dynamic kMutableStatic  '
            'receiver Holder *  targets T',
            '  sources/arguments.m:18:11  -[Holder run:]  valueForKey: argument 0 (key): dynamic sLocal  receiver '
            'Holder *  targets T',
            '  sources/arguments.m:19:11  -[Holder run:]  valueForKey: argument 0 (key): dynamic kUnassignedStatic  '
            'receiver Holder *  targets T',
            '  sources/arguments.m:30:31  SetCode  setAction: argument 0 (selector): dynamic 0  receiver Message *  '
            'targets T',
            'by call: valueForKey: 3, setAction: 1',
            'not listed: 4 arguments that are nil, NULL or 0 (argument kind nil) and 1 that is _cmd (argument kind '
            'self-selector); codedb.py reflective --all lists them',
        ])


RUNTIME_M = ('// Fixture written by the test. Line numbers are part of the expectations.\n'
             '#import "sel_base.h"\n'
             'typedef void (*IMP)(void);\n'
             'IMP method_setImplementation(Method m, IMP imp);\n'
             'IMP method_getImplementation(Method m);\n'
             'IMP imp_implementationWithBlock(id block);\n'
             'Method *class_copyMethodList(Class c, unsigned *n);\n'
             'struct objc_method_description { SEL name; char *types; };\n'
             'struct objc_method_description protocol_getMethodDescription(id p, SEL s, int req, int inst);\n'
             'Class objc_allocateClassPair(Class s, const char *name, unsigned long extra);\n'
             'Class object_setClass(id o, Class c);\n'
             'void Swizzle(Base *b, Method m, IMP imp, unsigned n) {\n'
             '    method_setImplementation(m, imp);\n'
             '    method_getImplementation(m);\n'
             '    imp_implementationWithBlock(b);\n'
             '    class_copyMethodList(NSClassFromString(@"Gadget"), &n);\n'
             '    protocol_getMethodDescription(b, @selector(reload), 1, 1);\n'
             '    objc_allocateClassPair([Base class], "Made", 0);\n'
             '    object_setClass(b, NSClassFromString(@"Gadget"));\n'
             '}\n')


class RuntimeFunctionsTest(unittest.TestCase):
    """The runtime functions that replace implementations, list methods and
    make classes are recognized reflective calls."""

    def test_rows(self):
        root = make_selector_root()
        with open(os.path.join(root, 'sources', 'runtime.m'), 'w') as f:
            f.write(RUNTIME_M)
        db = os.path.join(os.path.dirname(root), 'r.sqlite')
        status, stderr, _ = extract(root, 'sources/runtime.m', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(rows(db, "SELECT line, function_or_selector, kind, argument_index, argument_kind, "
                                  "argument_text, resolved_selector, resolved_class FROM reflective_call WHERE "
                                  "function_or_selector != 'NSClassFromString' ORDER BY line"), [
            (13, 'method_setImplementation', 'method', 0, 'dynamic', 'm', None, None),
            (14, 'method_getImplementation', 'method', 0, 'dynamic', 'm', None, None),
            (15, 'imp_implementationWithBlock', 'implementation', 0, 'dynamic', 'b', None, None),
            (16, 'class_copyMethodList', 'class', 0, 'string-literal', 'Gadget', None, 'Gadget'),
            (17, 'protocol_getMethodDescription', 'selector', 1, 'selector-expr', 'reload', 'reload', None),
            (18, 'objc_allocateClassPair', 'class', 1, 'string-literal', 'Made', None, 'Made'),
            (19, 'object_setClass', 'class', 1, 'string-literal', 'Gadget', None, 'Gadget'),
        ])

    def test_property_list_and_name_functions(self):
        root = make_selector_root()
        with open(os.path.join(root, 'sources', 'props.m'), 'w') as f:
            f.write('// Fixture written by the test. Line numbers are part of the expectations.\n'
                    '#import "sel_base.h"\n'
                    'typedef struct objc_property *objc_property_t;\n'
                    'objc_property_t *class_copyPropertyList(Class c, unsigned *n);\n'
                    'const char *property_getName(objc_property_t p);\n'
                    'SEL method_getName(Method m);\n'
                    'void Props(Method m, unsigned n) {\n'
                    '    objc_property_t *ps = class_copyPropertyList(NSClassFromString(@"Gadget"), &n);\n'
                    '    property_getName(ps[0]);\n'
                    '    method_getName(m);\n'
                    '}\n')
        db = os.path.join(os.path.dirname(root), 'p.sqlite')
        status, stderr, _ = extract(root, 'sources/props.m', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(rows(db, "SELECT line, function_or_selector, kind, argument_index, argument_kind, "
                                  "argument_text, resolved_selector, resolved_class FROM reflective_call WHERE "
                                  "function_or_selector != 'NSClassFromString' ORDER BY line"), [
            (8, 'class_copyPropertyList', 'class', 0, 'string-literal', 'Gadget', None, 'Gadget'),
            (9, 'property_getName', 'property', 0, 'dynamic', 'ps[0]', None, None),
            (10, 'method_getName', 'method', 0, 'dynamic', 'm', None, None),
        ])

    def test_methods_statement_names_only_recognized_calls(self):
        paths = base.make_paths(make_selector_root())
        names = set(line.split('\t')[0] for line in codedb.reflective_table(paths).splitlines()[1:])
        statement = [item for item in codedb.METHODS_NOT_IN_DATABASE if 'codedb.py reflective' in item]
        self.assertEqual(len(statement), 1)
        for name in ('class_addMethod', 'class_replaceMethod', 'method_exchangeImplementations',
                     'method_setImplementation', 'imp_implementationWithBlock'):
            self.assertIn(name, statement[0])
            self.assertIn(name, names)


class ClaimTest(unittest.TestCase):
    """A header's declarations are recorded once per target and content."""

    def setUp(self):
        self.root = make_selector_root()
        self.db = os.path.join(os.path.dirname(self.root), 'c.sqlite')

    def header_rows(self):
        return rows(self.db, "SELECT t.target, t.main_file, count(*) FROM objc_method m JOIN tu t ON t.id = m.tu "
                             "WHERE m.file = 'sources/methods.h' GROUP BY 1, 2 ORDER BY 1, 2")

    def test_second_unit_of_a_target_skips_a_claimed_header(self):
        self.assertEqual(extract(self.root, 'sources/user.m', self.db)[0], 0)
        self.assertEqual(extract(self.root, M, self.db)[0], 0)
        # methods.m still records its own implementation's rows located in
        # methods.h (synthesized accessors).
        self.assertEqual(self.header_rows(), [('T', 'sources/methods.m', 5), ('T', 'sources/user.m', 16)])
        self.assertEqual(rows(self.db, "SELECT count(*) FROM objc_property WHERE kind = 'declaration' AND "
                                       "file = 'sources/methods.h'"), [(8,)])
        self.assertEqual(rows(self.db, "SELECT d.path, t.main_file, d.via_module FROM decl_source d JOIN tu t ON "
                                       "t.id = d.tu ORDER BY 1"),
                         [('sources/methods.h', 'sources/user.m', 0), ('sources/methods.m', 'sources/methods.m', 0),
                          ('sources/sel_base.h', 'sources/user.m', 0), ('sources/user.m', 'sources/user.m', 0)])

    def test_another_target_records_its_own(self):
        extract(self.root, 'sources/user.m', self.db)
        extract(self.root, 'sources/user.m', self.db, target='U')
        self.assertEqual(self.header_rows(), [('T', 'sources/user.m', 16), ('U', 'sources/user.m', 16)])

    def test_reextracting_the_recording_unit_keeps_the_rows(self):
        extract(self.root, 'sources/user.m', self.db)
        extract(self.root, M, self.db)
        extract(self.root, 'sources/user.m', self.db)
        self.assertEqual(self.header_rows(), [('T', 'sources/methods.m', 5), ('T', 'sources/user.m', 16)])

    def test_implementation_in_a_file_another_unit_includes(self):
        # As PTYWindow.m includes iTermWindowImpl.m: the including unit
        # claims methods.m first, and methods.m still records the rows of its
        # own implementation.
        with open(os.path.join(self.root, 'sources', 'includer.m'), 'w') as f:
            f.write('#import "methods.m"\n')
        self.assertEqual(extract(self.root, 'sources/includer.m', self.db)[0], 0)
        self.assertEqual(extract(self.root, M, self.db)[0], 0)
        self.assertEqual(rows(self.db, "SELECT t.main_file, count(*) FROM objc_method m JOIN tu t ON t.id = m.tu "
                                       "WHERE m.container_kind IN ('implementation', 'category-implementation') "
                                       "GROUP BY 1 ORDER BY 1"),
                         [('sources/includer.m', 18), ('sources/methods.m', 18)])
        # The extension in methods.m is a declaration: claimed by includer.m.
        self.assertEqual(rows(self.db, "SELECT DISTINCT t.main_file FROM objc_method m JOIN tu t ON t.id = m.tu "
                                       "WHERE m.container_kind = 'extension'"), [('sources/includer.m',)])

    def test_gaps_are_per_target(self):
        extract(self.root, 'sources/user.m', self.db)
        extract(self.root, 'sources/user.m', self.db, target='U')
        extract(self.root, M, self.db)
        con = sqlite3.connect(self.db)
        self.assertEqual(codedb.declaration_gaps(con), [])
        con.execute("DELETE FROM decl_source WHERE path = 'sources/methods.h' AND target = 'T'")
        self.assertEqual([g[:2] for g in codedb.declaration_gaps(con)], [('sources/methods.h', 'T')])
        con.close()

    def test_changed_header_is_claimed_again(self):
        extract(self.root, 'sources/user.m', self.db)
        with open(os.path.join(self.root, H), 'a') as f:
            f.write('@interface Gadget (More)\n- (void)more;\n@end\n')
        extract(self.root, M, self.db)
        # methods.m read the header at its new content, which nobody had
        # recorded: it records all of it (16 declarations, the new one, and
        # 5 synthesized accessors).
        self.assertEqual(self.header_rows(), [('T', 'sources/methods.m', 22), ('T', 'sources/user.m', 16)])


class GapTest(unittest.TestCase):
    """update fills the declarations of a file whose recording unit was
    removed, and a query that uses declarations says when it has not."""

    def setUp(self):
        self.root = make_selector_root()
        self.paths = base.make_paths(self.root)

    def test_removed_recording_unit_is_replaced(self):
        base.write_cdb(self.root, self.paths.cdb, mains=('sources/user.m', M, S))
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)
        base.write_cdb(self.root, self.paths.cdb, mains=(M, S))
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 0)
        self.assertIn('removing T sources/user.m from the database: it is not in the compile database', log)
        self.assertTrue(any(m.startswith('[1/1] T sources/methods.m (declarations of sources/methods.h are recorded by '
                                         'no unit): ok') for m in log), log)
        self.assertEqual(rows(self.paths.db, "SELECT t.main_file, count(*) FROM objc_method m JOIN tu t ON "
                                             "t.id = m.tu WHERE m.file = 'sources/methods.h' GROUP BY 1"),
                         [('sources/methods.m', 21)])
        con = sqlite3.connect(self.paths.db)
        self.assertEqual(codedb.declaration_gaps(con), [])
        con.close()

    def test_gap_makes_methods_and_reach_incomplete_but_not_selrefs(self):
        base.write_cdb(self.root, self.paths.cdb, mains=(M, S, 'sources/user.m'))
        codedb.update(self.paths, log=lambda m: None)
        con = sqlite3.connect(self.paths.db)
        con.execute("DELETE FROM decl_source WHERE path = 'sources/methods.h'")
        con.commit()
        con.close()
        out = io.StringIO()
        self.assertEqual(codedb.methods(self.paths, 'count', out=out), 3)
        self.assertIn('INCOMPLETE: 1 files that current units read have no recorded declarations (the unit that '
                      'recorded them was removed or no longer reads them), first: sources/methods.h (T). Run '
                      'codedb.py update.\n', out.getvalue())
        self.assertIn('declarations: 1 files that current units read have none recorded\n    sources/methods.h (T)\n',
                      out.getvalue())
        self.assertEqual(codedb.reach(self.paths, 'count', out=io.StringIO()), 3)
        self.assertEqual(codedb.selrefs(self.paths, 'reload', out=io.StringIO()), 0)


COND_H = ('// Fixture written by the test. Line numbers are part of the expectations.\n'
          '#import "sel_base.h"\n'
          '@interface Conditional : Base\n'
          '- (void)always;\n'
          '#ifdef ENABLE_EXTRA\n'
          '- (void)onlyWithExtra;\n'
          '#endif\n'
          '@end\n')
COND_PLAIN = '#import "cond.h"\nvoid Plain(Conditional *c) { [c always]; }\n'
# As iTermProfilePreferences.m defines ENABLE_DEPRECATED_ADVANCED_SETTINGS
# before it imports iTermAdvancedSettingsModel.h.
COND_EXTRA = '#define ENABLE_EXTRA 1\n#import "cond.h"\nvoid Extra(Conditional *c) { [c onlyWithExtra]; }\n'
# As DebugLogging.h hides its Objective-C from C units.
CLOG_H = ('// Fixture written by the test. Line numbers are part of the expectations.\n'
          'void CLog(const char *s);\n'
          '#ifdef __OBJC__\n'
          '__attribute__((objc_root_class))\n'
          '@interface Logger\n'
          '- (void)logObjC;\n'
          '@end\n'
          '#endif\n')
CLOG_C = '#include "clog.h"\nvoid CLog(const char *s) {}\n'
CLOG_USER = '#import "clog.h"\nvoid UseLog(Logger *l) { [l logObjC]; }\n'
COMPLETE = 'declarations: every file that current units read has them recorded\n'


class ViewTest(unittest.TestCase):
    """A header's declarations are recorded once per target, content and
    view: a unit that skips other parts of the header, or reads it in
    another language, records its own rows for it."""

    def setUp(self):
        self.root = make_selector_root()
        self.paths = base.make_paths(self.root)
        for name, text in (('cond.h', COND_H), ('cond_plain.m', COND_PLAIN), ('cond_extra.m', COND_EXTRA),
                           ('clog.h', CLOG_H), ('clog.c', CLOG_C), ('clog_user.m', CLOG_USER)):
            with open(os.path.join(self.root, 'sources', name), 'w') as f:
                f.write(text)

    def build(self, *mains):
        base.write_cdb(self.root, self.paths.cdb, mains=mains)
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)

    def methods(self, selector):
        out = io.StringIO()
        status = codedb.methods(self.paths, selector, out=out)
        lines, block = split(out.getvalue())
        return status, lines, block

    def check_ifdef(self):
        status, lines, block = self.methods('onlyWithExtra')
        self.assertEqual((status, lines), (0, [
            'sources/cond.h:6:9  -[Conditional onlyWithExtra]  interface declaration  in 1 of 2 views of this file '
            'in T (recorded by sources/cond_extra.m)  targets T']))
        self.assertIn(COMPLETE, block)
        self.assertNotIn('INCOMPLETE', block)
        # In both views: one row, with no note.
        status, lines, block = self.methods('always')
        self.assertEqual((status, lines), (0, ['sources/cond.h:4:9  -[Conditional always]  interface declaration  '
                                               'targets T']))
        self.assertEqual(rows(self.paths.db, "SELECT count(DISTINCT view), count(*) FROM decl_source WHERE "
                                             "path = 'sources/cond.h'"), [(2, 2)])

    def test_ifdef_header_read_first_without_the_macro(self):
        self.build('sources/cond_plain.m', 'sources/cond_extra.m')
        self.check_ifdef()

    def test_ifdef_header_read_first_with_the_macro(self):
        self.build('sources/cond_extra.m', 'sources/cond_plain.m')
        self.check_ifdef()

    def test_c_unit_reads_the_header_first(self):
        self.build('sources/clog.c', 'sources/clog_user.m')
        status, lines, block = self.methods('logObjC')
        self.assertEqual((status, lines), (0, [
            'sources/clog.h:6:9  -[Logger logObjC]  interface declaration  in 1 of 2 views of this file in T '
            '(recorded by sources/clog_user.m)  targets T']))
        self.assertIn(COMPLETE, block)
        self.assertNotIn('INCOMPLETE', block)

    def test_same_view_is_recorded_once(self):
        # Two units that see the header alike: the second records nothing
        # for it.
        self.build('sources/cond_plain.m', 'sources/user.m', 'sources/cond_extra.m')
        with open(os.path.join(self.root, 'sources', 'cond_plain2.m'), 'w') as f:
            f.write(COND_PLAIN)
        self.build('sources/cond_plain.m', 'sources/cond_plain2.m', 'sources/cond_extra.m')
        self.assertEqual(rows(self.paths.db, "SELECT t.main_file FROM decl_source d JOIN tu t ON t.id = d.tu WHERE "
                                             "d.path = 'sources/cond.h' ORDER BY 1"),
                         [('sources/cond_extra.m',), ('sources/cond_plain.m',)])

    def test_gap_is_per_view(self):
        self.build('sources/cond_plain.m', 'sources/cond_extra.m')
        con = sqlite3.connect(self.paths.db)
        try:
            self.assertEqual(codedb.declaration_gaps(con), [])
            con.execute("DELETE FROM decl_source WHERE path = 'sources/cond.h' AND tu = (SELECT id FROM tu WHERE "
                        "main_file = 'sources/cond_extra.m')")
            self.assertEqual([g[:2] for g in codedb.declaration_gaps(con)], [('sources/cond.h', 'T')])
        finally:
            con.close()


# Stands for an SDK header: outside the repository, on the include path.
SDK_APP_H = ('// Fixture outside the repository.\n'
             '__attribute__((objc_root_class))\n'
             '@interface SDKObject\n'
             '@end\n'
             '@interface SDKView : SDKObject\n'
             '- (void)drawRect:(int)r;\n'
             '@end\n'
             '@protocol SDKAppDelegate\n'
             '@optional\n'
             '- (id)applicationDockMenu:(id)sender;\n'
             '@end\n'
             '@protocol SDKTableDelegate\n'
             '@optional\n'
             '- (id)tableView:(id)t viewForRow:(int)r;\n'
             '@end\n')
OVERRIDES_M = ('// Fixture written by the test. Line numbers are part of the expectations.\n'
               '#import "sdk_app.h"\n'
               '@protocol RepoProtocol\n'
               '- (void)repoRequirement;\n'
               '@end\n'
               '@interface RepoView : SDKView\n'
               '- (void)repoMethod;\n'
               '@end\n'
               '@interface AppDelegate : SDKObject <SDKAppDelegate>\n'
               '@end\n'
               '@interface MyView : RepoView <RepoProtocol>\n'
               '@end\n'
               '@interface MyView (Table) <SDKTableDelegate>\n'
               '@end\n'
               '@implementation RepoView\n'
               '- (void)repoMethod {}\n'
               '- (void)drawRect:(int)r {}\n'
               '@end\n'
               '@implementation AppDelegate\n'
               '- (id)applicationDockMenu:(id)sender { return 0; }\n'
               '- (void)lonely {}\n'
               '@end\n'
               '@implementation MyView\n'
               '- (void)repoMethod {}\n'
               '- (void)repoRequirement {}\n'
               '@end\n'
               '@implementation MyView (Table)\n'
               '- (id)tableView:(id)t viewForRow:(int)r { return 0; }\n'
               '@end\n')
O = 'sources/overrides.m'


class OverrideTest(unittest.TestCase):
    """What a method overrides or satisfies, and the methods outside the
    repository that may call it."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        cls.outside = os.path.join(os.path.dirname(cls.root), 'outside')
        os.makedirs(cls.outside)
        cls.sdk_h = os.path.join(cls.outside, 'sdk_app.h')
        with open(cls.sdk_h, 'w') as f:
            f.write(SDK_APP_H)
        with open(os.path.join(cls.root, O), 'w') as f:
            f.write(OVERRIDES_M)
        cls.paths = base.make_paths(cls.root)
        base.write_cdb(cls.root, cls.paths.cdb, mains=(O,))
        cls.status = codedb.update(cls.paths, log=lambda m: None)

    def ask(self, query, selector):
        out = io.StringIO()
        status = query(self.paths, selector, out=out)
        lines, block = split(out.getvalue())
        return status, lines, block

    def test_override_rows(self):
        self.assertEqual(self.status, 0)
        self.assertEqual(rows(self.paths.db, 'SELECT m.container_name, m.selector, m.is_definition, m.line, '
                                             'o.overridden_usr, o.overridden_container, o.overridden_container_kind, '
                                             'o.overridden_file, o.overridden_line, o.outside_repository, '
                                             'o.is_optional_requirement FROM objc_method_override o JOIN objc_method '
                                             'm ON m.id = o.method ORDER BY m.line'), [
            ('RepoView', 'drawRect:', 1, 17, 'c:objc(cs)SDKView(im)drawRect:', 'SDKView', 'interface', self.sdk_h, 6,
             1, 0),
            ('AppDelegate', 'applicationDockMenu:', 1, 20, 'c:objc(pl)SDKAppDelegate(im)applicationDockMenu:',
             'SDKAppDelegate', 'protocol', self.sdk_h, 10, 1, 1),
            ('MyView', 'repoMethod', 1, 24, 'c:objc(cs)RepoView(im)repoMethod', 'RepoView', 'interface', O, 7, 0, 0),
            ('MyView', 'repoRequirement', 1, 25, 'c:objc(pl)RepoProtocol(im)repoRequirement', 'RepoProtocol',
             'protocol', O, 4, 0, 0),
            ('MyView(Table)', 'tableView:viewForRow:', 1, 28, 'c:objc(pl)SDKTableDelegate(im)tableView:viewForRow:',
             'SDKTableDelegate', 'protocol', self.sdk_h, 14, 1, 1),
        ])

    def reach_groups(self, selector):
        status, lines, block = self.ask(codedb.reach, selector)
        start = next(i for i, line in enumerate(lines) if line.startswith('May be called by code outside'))
        end = lines.index('Not covered by reach:')
        return status, lines[start:end], lines[end:], block

    def test_reach_sdk_protocol_optional_method(self):
        status, groups, _, _ = self.reach_groups('applicationDockMenu:')
        self.assertEqual(status, 0)
        self.assertEqual(groups, [
            'May be called by code outside this database: 1',
            '  sources/overrides.m:20:7  -[AppDelegate applicationDockMenu:]  satisfies SDKAppDelegate '
            '-applicationDockMenu: (optional), declared outside the repository in %s  targets T' % self.sdk_h,
            INSIDE_NONE,
        ])

    def test_reach_sdk_superclass_method(self):
        status, groups, _, _ = self.reach_groups('drawRect:')
        self.assertEqual(status, 0)
        self.assertEqual(groups[:2], [
            'May be called by code outside this database: 1',
            '  sources/overrides.m:17:9  -[RepoView drawRect:]  overrides SDKView -drawRect:, declared outside the '
            'repository in %s  targets T' % self.sdk_h])

    def test_reach_category_satisfies_sdk_protocol(self):
        status, groups, _, _ = self.reach_groups('tableView:viewForRow:')
        self.assertEqual(status, 0)
        self.assertEqual(groups[:2], [
            'May be called by code outside this database: 1',
            '  sources/overrides.m:28:7  -[MyView(Table) tableView:viewForRow:]  satisfies SDKTableDelegate '
            '-tableView:viewForRow: (optional), declared outside the repository in %s  targets T' % self.sdk_h])

    def test_reach_in_repository_override_is_not_a_row(self):
        status, groups, _, _ = self.reach_groups('repoMethod')
        self.assertEqual(status, 1)
        self.assertEqual(groups, [
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/overrides.m:24:9  -[MyView repoMethod]  overrides RepoView -repoMethod, declared at '
            'sources/overrides.m:7  targets T',
            NO_OBJC_CALLER,
        ])
        self.assertEqual(self.reach_groups('repoRequirement')[1][2],
                         '  sources/overrides.m:25:9  -[MyView repoRequirement]  satisfies RepoProtocol '
                         '-repoRequirement (required), declared at sources/overrides.m:4  targets T')

    def test_reach_method_that_overrides_nothing(self):
        status, groups, not_covered, block = self.reach_groups('lonely')
        self.assertEqual(status, 1)
        self.assertEqual(groups, ['May be called by code outside this database: 0', INSIDE_NONE])
        self.assertIn('  - ' + codedb.FRAMEWORK_CALLERS_NOT_COVERED, not_covered)
        for item in codedb.NOT_IN_DATABASE_COMMON:
            self.assertIn('  - %s\n' % item, block)
        self.assertNotIn('see "Not covered by reach" above', block)

    def test_methods_lists_the_outside_callers(self):
        status, lines, _ = self.ask(codedb.methods, 'applicationDockMenu:')
        self.assertEqual(status, 0)
        self.assertEqual(lines, [
            'sources/overrides.m:20:7  -[AppDelegate applicationDockMenu:]  implementation definition  targets T',
            'May be called by code outside this database: 1',
            '  sources/overrides.m:20:7  -[AppDelegate applicationDockMenu:]  satisfies SDKAppDelegate '
            '-applicationDockMenu: (optional), declared outside the repository in %s  targets T' % self.sdk_h,
        ])
        self.assertEqual(self.ask(codedb.methods, 'lonely')[1], [
            'sources/overrides.m:21:9  -[AppDelegate lonely]  implementation definition  targets T'])

    def test_methods_caption_of_the_repository_group_claims_no_sends(self):
        status, lines, _ = self.ask(codedb.methods, 'repoMethod')
        self.assertEqual(status, 0)
        self.assertEqual(lines[-2:], [
            'Methods in this repository that it overrides or protocol requirements it satisfies: 1 (run codedb.py '
            'reach repoMethod for its senders)',
            '  sources/overrides.m:24:9  -[MyView repoMethod]  overrides RepoView -repoMethod, declared at '
            'sources/overrides.m:7  targets T',
        ])


# Declarations whose owner's code is not in the database although the header
# is inside the repository: a prebuilt framework bundle, a header the Swift
# compiler generates, and a header read only through a compiled module. The
# last protocol is an ordinary one whose owner is parsed.
OWNER_FILES = {
    'outside/sdk_owner.h': ('@protocol SDKDelegate\n'
                            '@optional\n'
                            '- (void)sdkDidStart;\n'
                            '@end\n'),
    'repo/sources/Kit.framework/Headers/KitPicker.h': ('@protocol KitPickerDelegate\n'
                                                       '- (void)picker:(id)p didPick:(id)x;\n'
                                                       '@end\n'),
    'repo/sources/Gen-Swift.h': ('@protocol GenDelegate\n'
                                 '- (void)genDidFinish;\n'
                                 '@end\n'),
    'repo/modkit/ModKit.h': ('@protocol ModDelegate\n'
                             '- (void)modDidLoad;\n'
                             '@end\n'),
    'repo/modkit/module.modulemap': 'module ModKit { header "ModKit.h" export * }\n',
    'repo/sources/repo_delegate.h': ('@protocol RepoDelegate\n'
                                     '- (void)repoDidChange;\n'
                                     '@end\n'),
    'repo/sources/owner.m': ('// Fixture written by the test. Line numbers are part of the expectations.\n'
                             '#import "sel_base.h"\n'
                             '#import "sdk_owner.h"\n'
                             '#import "Kit.framework/Headers/KitPicker.h"\n'
                             '#import "Gen-Swift.h"\n'
                             '#import "repo_delegate.h"\n'
                             '@import ModKit;\n'
                             '@interface Owner : Base <SDKDelegate, KitPickerDelegate, GenDelegate, ModDelegate, '
                             'RepoDelegate>\n'
                             '@end\n'
                             '@implementation Owner\n'
                             '- (void)sdkDidStart {}\n'
                             '- (void)picker:(id)p didPick:(id)x {}\n'
                             '- (void)genDidFinish {}\n'
                             '- (void)modDidLoad {}\n'
                             '- (void)repoDidChange {}\n'
                             '@end\n'),
}
OWNER_M = 'sources/owner.m'


class OwnerParsedTest(unittest.TestCase):
    """A declaration in the repository whose owner's code is not parsed (a
    prebuilt framework, a generated -Swift.h header, a header read only
    through a module) may be called by code outside this database."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        work = os.path.dirname(cls.root)
        for rel, text in OWNER_FILES.items():
            p = os.path.join(work, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w') as f:
                f.write(text)
        cls.cache = base.make_temp('codedb-mc-')
        cls.paths = base.make_paths(cls.root)
        base.write_cdb(cls.root, cls.paths.cdb, mains=(OWNER_M,))
        with open(cls.paths.cdb) as f:
            lines = [json.loads(line) for line in f]
        for entry in lines[1:]:
            entry['arguments'] = (['-fmodules', '-fmodules-cache-path=' + cls.cache,
                                   '-I', os.path.join(cls.root, 'modkit')] + entry['arguments'])
        with open(cls.paths.cdb, 'w') as f:
            f.write(''.join(json.dumps(e) + '\n' for e in lines))
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)
        cls.sdk_h = os.path.join(work, 'outside', 'sdk_owner.h')

    def ask(self, query, selector):
        out = io.StringIO()
        status = query(self.paths, selector, out=out)
        lines, block = split(out.getvalue())
        return status, lines, block

    def groups(self, query, selector):
        status, lines, _ = self.ask(query, selector)
        start = next(i for i, line in enumerate(lines) if line.startswith('May be called by code outside'))
        end = lines.index('Not covered by reach:') if 'Not covered by reach:' in lines else len(lines)
        return status, lines[start:end]

    def test_owner_parsed_rows(self):
        self.assertEqual(self.status, 0, self.log)
        self.assertEqual(rows(self.paths.db, 'SELECT m.selector, o.overridden_container, o.overridden_file, '
                                             'o.overridden_line, o.outside_repository, o.owner_parsed FROM '
                                             'objc_method_override o JOIN objc_method m ON m.id = o.method '
                                             'ORDER BY m.line'), [
            ('sdkDidStart', 'SDKDelegate', self.sdk_h, 3, 1, 0),
            ('picker:didPick:', 'KitPickerDelegate', 'sources/Kit.framework/Headers/KitPicker.h', 2, 0, 0),
            ('genDidFinish', 'GenDelegate', 'sources/Gen-Swift.h', 2, 0, 0),
            ('modDidLoad', 'ModDelegate', 'modkit/ModKit.h', 2, 0, 0),
            ('repoDidChange', 'RepoDelegate', 'sources/repo_delegate.h', 2, 0, 1),
        ])

    def test_reach_framework_delegate(self):
        self.assertEqual(self.groups(codedb.reach, 'picker:didPick:'), (0, [
            'May be called by code outside this database: 1',
            '  sources/owner.m:12:9  -[Owner picker:didPick:]  satisfies KitPickerDelegate -picker:didPick: '
            '(required), declared in Kit.framework, whose code is not in this database  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_swift_generated_header(self):
        self.assertEqual(self.groups(codedb.reach, 'genDidFinish'), (0, [
            'May be called by code outside this database: 1',
            '  sources/owner.m:13:9  -[Owner genDidFinish]  satisfies GenDelegate -genDidFinish (required), '
            'declared by Swift code, which is not in this database (Gen-Swift.h)  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_header_read_only_through_a_module(self):
        self.assertEqual(self.groups(codedb.reach, 'modDidLoad'), (0, [
            'May be called by code outside this database: 1',
            '  sources/owner.m:14:9  -[Owner modDidLoad]  satisfies ModDelegate -modDidLoad (required), declared '
            'at modkit/ModKit.h:2, in a header read only through a compiled module, whose code may not be in this '
            'database  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_parsed_owner_stays_in_the_repository_group(self):
        self.assertEqual(self.groups(codedb.reach, 'repoDidChange'), (1, [
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/owner.m:15:9  -[Owner repoDidChange]  satisfies RepoDelegate -repoDidChange (required), '
            'declared at sources/repo_delegate.h:2  targets T',
            NO_OBJC_CALLER,
        ]))

    def test_methods_lists_the_framework_delegate_as_outside(self):
        self.assertEqual(self.groups(codedb.methods, 'picker:didPick:'), (0, [
            'May be called by code outside this database: 1',
            '  sources/owner.m:12:9  -[Owner picker:didPick:]  satisfies KitPickerDelegate -picker:didPick: '
            '(required), declared in Kit.framework, whose code is not in this database  targets T',
        ]))


# Declarations in categories and class extensions. A category in the
# repository on a class whose code is not in this database (the SDK, a
# prebuilt framework) declares a method that code may call: a private method
# the category redeclares, as PTYWindow.m does for NSWindow. A category or
# class extension on a class of the repository does not. The protocol is
# declared in the repository; one of its methods has an Objective-C send and
# the other none. SDKPrivateFrame stands for a private SDK class that a .m
# file of the repository declares itself, with no @implementation, as
# PTYWindow.m does NSThemeFrame.
CATEGORY_FILES = {
    'outside/sdk_cat.h': ('// Fixture outside the repository.\n'
                          '__attribute__((objc_root_class))\n'
                          '@interface SDKObject\n'
                          '@end\n'
                          '@interface SDKWindow : SDKObject\n'
                          '@end\n'),
    'repo/sources/Kit.framework/Headers/KitView.h': ('#import "sdk_cat.h"\n'
                                                     '@interface KitView : SDKObject\n'
                                                     '@end\n'),
    'repo/sources/catowner.m': ('// Fixture written by the test. Line numbers are part of the expectations.\n'
                                '#import "sdk_cat.h"\n'
                                '@interface SDKWindow (Private)\n'
                                '- (double)_titlebarHeight;\n'
                                '@end\n'
                                '@interface SDKWindow ()\n'
                                '- (int)_cursorType;\n'
                                '@end\n'
                                '@interface RepoBase : SDKObject\n'
                                '@end\n'
                                '@interface RepoBase (Hooks)\n'
                                '- (void)categoryHook;\n'
                                '@end\n'
                                '@interface MyWindow : SDKWindow\n'
                                '@end\n'
                                '@interface MyWindow ()\n'
                                '- (void)extensionHook;\n'
                                '@end\n'
                                '@interface RepoSub : RepoBase\n'
                                '@end\n'
                                '@interface MySubWindow : MyWindow\n'
                                '@end\n'
                                '@protocol ToolbarDelegate\n'
                                '- (void)toolbarDidChange;\n'
                                '- (void)toolbarWillChange;\n'
                                '@end\n'
                                '@interface Toolbar : RepoBase <ToolbarDelegate>\n'
                                '@end\n'
                                '@implementation RepoBase\n'
                                '@end\n'
                                '@implementation MyWindow\n'
                                '- (double)_titlebarHeight { return 0; }\n'
                                '- (int)_cursorType { return 0; }\n'
                                '- (void)extensionHook {}\n'
                                '@end\n'
                                '@implementation RepoSub\n'
                                '- (void)categoryHook {}\n'
                                '@end\n'
                                '@implementation MySubWindow\n'
                                '- (void)extensionHook {}\n'
                                '@end\n'
                                '@implementation Toolbar\n'
                                '- (void)toolbarDidChange {}\n'
                                '- (void)toolbarWillChange {}\n'
                                '@end\n'
                                'void Poke(Toolbar *t) { [t toolbarWillChange]; }\n'
                                '#import "Kit.framework/Headers/KitView.h"\n'
                                '@interface KitView (Private)\n'
                                '- (void)_kitHook;\n'
                                '@end\n'
                                '@interface MyKitView : KitView\n'
                                '@end\n'
                                '@implementation MyKitView\n'
                                '- (void)_kitHook {}\n'
                                '@end\n'
                                '#import "cat_base.h"\n'
                                '@interface HeaderSub : HeaderBase\n'
                                '@end\n'
                                '@implementation HeaderSub\n'
                                '- (void)headerHook {}\n'
                                '@end\n'
                                '@interface SDKPrivateFrame : SDKObject\n'
                                '@end\n'
                                '@interface SDKPrivateFrame (Private)\n'
                                '- (double)_frameHeight;\n'
                                '@end\n'
                                '@interface MyFrame : SDKPrivateFrame\n'
                                '@end\n'
                                '@implementation MyFrame\n'
                                '- (double)_frameHeight { return 0; }\n'
                                '@end\n'),
    # A class of the repository, implemented in a unit that is not here.
    'repo/sources/cat_base.h': ('#import "sdk_cat.h"\n'
                                '@interface HeaderBase : SDKObject\n'
                                '@end\n'
                                '@interface HeaderBase (Hooks)\n'
                                '- (void)headerHook;\n'
                                '@end\n'),
}
CAT_M = 'sources/catowner.m'


class CategoryOwnerTest(unittest.TestCase):
    """An override of a method declared in a category or class extension is
    judged by the class the category extends."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        work = os.path.dirname(cls.root)
        for rel, text in CATEGORY_FILES.items():
            p = os.path.join(work, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w') as f:
                f.write(text)
        cls.paths = base.make_paths(cls.root)
        base.write_cdb(cls.root, cls.paths.cdb, mains=(CAT_M,))
        cls.log = []
        cls.status = codedb.update(cls.paths, log=cls.log.append)

    def ask(self, query, selector):
        out = io.StringIO()
        status = query(self.paths, selector, out=out)
        lines, _ = split(out.getvalue())
        return status, lines

    def groups(self, selector):
        status, lines = self.ask(codedb.reach, selector)
        start = next(i for i, line in enumerate(lines) if line.startswith('May be called by code outside'))
        return status, lines[start:lines.index('Not covered by reach:')]

    def test_override_rows(self):
        self.assertEqual(self.status, 0, self.log)
        self.assertEqual(rows(self.paths.db, 'SELECT m.container_name, m.selector, m.line, o.overridden_container, '
                                             'o.overridden_container_kind, o.overridden_file, o.overridden_line, '
                                             'o.outside_repository, o.owner_parsed, o.overridden_class, '
                                             'o.overridden_class_parsed FROM objc_method_override o JOIN objc_method '
                                             'm ON m.id = o.method ORDER BY m.line'), [
            ('MyWindow', '_titlebarHeight', 32, 'SDKWindow(Private)', 'category', CAT_M, 4, 0, 0, 'SDKWindow', 0),
            ('MyWindow', '_cursorType', 33, 'SDKWindow()', 'extension', CAT_M, 7, 0, 0, 'SDKWindow', 0),
            ('RepoSub', 'categoryHook', 37, 'RepoBase(Hooks)', 'category', CAT_M, 12, 0, 1, 'RepoBase', 1),
            ('MySubWindow', 'extensionHook', 40, 'MyWindow()', 'extension', CAT_M, 17, 0, 1, 'MyWindow', 1),
            ('Toolbar', 'toolbarDidChange', 43, 'ToolbarDelegate', 'protocol', CAT_M, 24, 0, 1, None, None),
            ('Toolbar', 'toolbarWillChange', 44, 'ToolbarDelegate', 'protocol', CAT_M, 25, 0, 1, None, None),
            ('MyKitView', '_kitHook', 54, 'KitView(Private)', 'category', CAT_M, 49, 0, 0, 'KitView', 0),
            ('HeaderSub', 'headerHook', 60, 'HeaderBase(Hooks)', 'category', 'sources/cat_base.h', 5, 0, 1,
             'HeaderBase', 1),
            ('MyFrame', '_frameHeight', 70, 'SDKPrivateFrame(Private)', 'category', CAT_M, 65, 0, 0,
             'SDKPrivateFrame', 0),
        ])

    def test_reach_category_on_a_class_a_source_file_declares_without_implementing(self):
        self.assertEqual(self.groups('_frameHeight'), (0, [
            'May be called by code outside this database: 1',
            '  sources/catowner.m:70:11  -[MyFrame _frameHeight]  overrides SDKPrivateFrame(Private) -_frameHeight, '
            'declared in this repository at sources/catowner.m:65 as a category on SDKPrivateFrame, a class whose '
            'code is not in this database; code there calls it only if the selector is its own, as when the '
            'category redeclares a private method  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_category_on_a_header_class_implemented_elsewhere(self):
        self.assertEqual(self.groups('headerHook'), (1, [
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/catowner.m:60:9  -[HeaderSub headerHook]  overrides HeaderBase(Hooks) -headerHook, declared at '
            'sources/cat_base.h:5  targets T',
            NO_OBJC_CALLER,
        ]))

    def test_reach_category_on_an_sdk_class(self):
        self.assertEqual(self.groups('_titlebarHeight'), (0, [
            'May be called by code outside this database: 1',
            '  sources/catowner.m:32:11  -[MyWindow _titlebarHeight]  overrides SDKWindow(Private) -_titlebarHeight, '
            'declared in this repository at sources/catowner.m:4 as a category on SDKWindow, a class whose code is '
            'not in this database; code there calls it only if the selector is its own, as when the category '
            'redeclares a private method  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_class_extension_of_an_sdk_class(self):
        self.assertEqual(self.groups('_cursorType'), (0, [
            'May be called by code outside this database: 1',
            '  sources/catowner.m:33:8  -[MyWindow _cursorType]  overrides SDKWindow() -_cursorType, declared in '
            'this repository at sources/catowner.m:7 as a class extension of SDKWindow, a class whose code is not in '
            'this database; code there calls it only if the selector is its own, as when the class extension '
            'redeclares a private method  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_category_on_a_prebuilt_framework_class(self):
        self.assertEqual(self.groups('_kitHook'), (0, [
            'May be called by code outside this database: 1',
            '  sources/catowner.m:54:9  -[MyKitView _kitHook]  overrides KitView(Private) -_kitHook, declared in '
            'this repository at sources/catowner.m:49 as a category on KitView, a class whose code is not in this '
            'database; code there calls it only if the selector is its own, as when the category redeclares a '
            'private method  targets T',
            INSIDE_NONE,
        ]))

    def test_reach_category_and_extension_on_repository_classes(self):
        self.assertEqual(self.groups('categoryHook'), (1, [
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/catowner.m:37:9  -[RepoSub categoryHook]  overrides RepoBase(Hooks) -categoryHook, declared at '
            'sources/catowner.m:12  targets T',
            NO_OBJC_CALLER,
        ]))
        self.assertEqual(self.groups('extensionHook'), (1, [
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/catowner.m:40:9  -[MySubWindow extensionHook]  overrides MyWindow() -extensionHook, declared '
            'at sources/catowner.m:17  targets T',
            NO_OBJC_CALLER,
        ]))

    def test_reach_repository_protocol_with_only_swift_callers(self):
        # The shape of sessionDidChangeDesiredToolbarItems:, whose callers
        # are all Swift: no Objective-C send, so reach says so.
        status, lines = self.ask(codedb.reach, 'toolbarDidChange')
        self.assertEqual(status, 1)
        self.assertEqual(lines[:7], [
            'Message sends of toolbarDidChange: 0',
            '@selector expressions and reflective calls resolving to toolbarDidChange: 0',
            'Key-value coding and key paths naming toolbarDidChange: 0',
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/catowner.m:43:9  -[Toolbar toolbarDidChange]  satisfies ToolbarDelegate -toolbarDidChange '
            '(required), declared at sources/catowner.m:24  targets T',
            NO_OBJC_CALLER,
        ])
        self.assertEqual(lines[7], 'Not covered by reach:')

    def test_reach_repository_protocol_with_a_send_has_no_note(self):
        status, lines = self.ask(codedb.reach, 'toolbarWillChange')
        self.assertEqual(status, 0)
        self.assertEqual(lines[:8], [
            'Message sends of toolbarWillChange: 1',
            '  sources/catowner.m:46:28  Poke  receiver Toolbar *  targets T',
            '@selector expressions and reflective calls resolving to toolbarWillChange: 0',
            'Key-value coding and key paths naming toolbarWillChange: 0',
            'May be called by code outside this database: 0',
            INSIDE_ONE,
            '  sources/catowner.m:44:9  -[Toolbar toolbarWillChange]  satisfies ToolbarDelegate -toolbarWillChange '
            '(required), declared at sources/catowner.m:25  targets T',
            'Not covered by reach:',
        ])


DIAMOND_M = ('// Fixture written by the test.\n'
             '#import "sel_base.h"\n'
             '@protocol Root\n'
             '- (void)rootThing;\n'
             '@end\n'
             '@protocol Left <Root>\n'
             '@end\n'
             '@protocol Right <Root>\n'
             '@end\n'
             '@interface Diamond : Base <Left, Right>\n'
             '@end\n'
             '@implementation Diamond\n'
             '- (void)rootThing {}\n'
             '@end\n')


class DuplicateRowsTest(unittest.TestCase):
    def test_requirement_reached_through_two_protocols_has_one_override_row(self):
        root = make_selector_root()
        with open(os.path.join(root, 'sources', 'diamond.m'), 'w') as f:
            f.write(DIAMOND_M)
        db = os.path.join(os.path.dirname(root), 'dm.sqlite')
        status, stderr, _ = extract(root, 'sources/diamond.m', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(rows(db, 'SELECT m.selector, m.line, o.overridden_container, o.overridden_line FROM '
                                  'objc_method_override o JOIN objc_method m ON m.id = o.method'),
                         [('rootThing', 13, 'Root', 4)])

    def test_unit_with_header_and_implementation_records_no_identical_method_rows(self):
        # methods.m claims methods.h and holds Gadget's @implementation: an
        # auto-synthesized accessor has one interface row (the implicit
        # declaration) and one implementation row (the synthesized accessor),
        # both at the property, and no row twice.
        root = make_selector_root()
        db = os.path.join(os.path.dirname(root), 'dup.sqlite')
        self.assertEqual(extract(root, M, db)[0], 0)
        columns = ('tu, usr, selector, is_class_method, container_usr, container_name, container_kind, class_name, '
                   'is_definition, is_implicit, is_synthesized_accessor, is_optional, property_usr, return_type, '
                   'type_encoding, file, line, col, macro_name, macro_file, macro_line, macro_role, expansion_line, '
                   'expansion_col, in_migration_scope')
        self.assertEqual(rows(db, 'SELECT count(*) FROM (SELECT 1 FROM objc_method GROUP BY %s HAVING count(*) > 1)'
                                  % columns), [(0,)])
        self.assertEqual(rows(db, "SELECT container_kind, is_implicit, is_synthesized_accessor FROM objc_method "
                                  "WHERE selector = 'count' ORDER BY container_kind"),
                         [('implementation', 1, 1), ('interface', 1, 0)])


class NotCoveredTextTest(unittest.TestCase):
    def test_framework_callers_text(self):
        self.assertEqual(codedb.FRAMEWORK_CALLERS_NOT_COVERED, (
            'calls made by system frameworks and other code that is not in this database (prebuilt frameworks in '
            'the repository, Swift) are not recorded. A method that overrides or implements something declared in '
            'code that is not in this database is listed above as possibly called from outside. Methods the '
            'frameworks call without a declaration the method overrides that its unit can see are not identified, '
            'for example: a method of a protocol the class does not declare it adopts (validateUserInterfaceItem: '
            'in a class that declares NSMenuItemValidation but not NSUserInterfaceValidations); an override of a '
            "private framework method that no public header declares (an NSWindow subclass's "
            '_usesCustomDrawing); +load in a category on NSObject itself; actions sent through the responder chain '
            'and methods named only in xibs, storyboards, the sdef or plists; and accessors reached only by '
            'key-value coding from a binding'))

    def test_reach_help_text_on_the_repository_group(self):
        self.assertIn('Exit 0 if any group has rows, the methods declared in parsed code of the repository not '
                      'counting (Objective-C sends to them are among its sends, Swift references among the Swift '
                      'references).', ' '.join(codedb.__doc__.split()))
        self.assertNotIn('sends to them are among its sends)', ' '.join(codedb.__doc__.split()))

    def test_methods_text_on_module_headers(self):
        self.assertIn('declarations in a header read only through a compiled module', codedb.METHODS_NOT_IN_DATABASE)

    def test_invisible_overrides_text(self):
        self.assertIn(
            'overrides the defining unit cannot see: the overrides listed above include only relationships visible '
            'through declarations that unit can see, so a method that overrides a superclass method declared only '
            "in the superclass's .m file, or that satisfies a conformance declared only in a superclass's "
            'private class extension, is not listed; codedb.py methods SELECTOR lists every definition in every '
            'class', codedb.REACH_NOT_COVERED)


class KeyTest(unittest.TestCase):
    def test_kvc_keys_underscore_forms(self):
        self.assertEqual(codedb.kvc_keys('_title'), ['_title', 'title'])
        self.assertEqual(codedb.kvc_keys('_getTitle'), ['_getTitle', 'title', 'Title', 'getTitle'])
        self.assertEqual(codedb.kvc_keys('_setTitle:'), ['title', 'Title'])
        # _is<Key> is not a method the accessor search tries (only an instance
        # variable); _isHidden is reached as _<key> for the key isHidden.
        self.assertEqual(codedb.kvc_keys('_isHidden'), ['_isHidden', 'isHidden'])

    def test_kvc_keys(self):
        self.assertEqual(codedb.kvc_keys('count'), ['count'])
        self.assertEqual(codedb.kvc_keys('isOn'), ['isOn', 'on', 'On'])
        self.assertEqual(codedb.kvc_keys('setFrame:'), ['frame', 'Frame'])
        self.assertEqual(codedb.kvc_keys('countOfItems'), ['countOfItems', 'items', 'Items'])
        self.assertEqual(codedb.kvc_keys('insertObject:inItemsAtIndex:'), ['items', 'Items'])
        self.assertEqual(codedb.kvc_keys('keyPathsForValuesAffectingTitle'),
                         ['keyPathsForValuesAffectingTitle', 'title', 'Title'])
        self.assertEqual(codedb.kvc_keys('validateName:error:'), ['name', 'Name'])
        self.assertEqual(codedb.kvc_keys('reset:with:'), [])

    def test_kvc_keys_follow_the_accessor_search(self):
        # <Key> is the key with its first letter capitalized: setURL: is
        # reached by the key URL, not uRL.
        self.assertEqual(codedb.kvc_keys('setURL:'), ['URL'])
        self.assertEqual(codedb.kvc_keys('countOfURLs'), ['countOfURLs', 'URLs'])
        self.assertEqual(codedb.kvc_keys('setX:'), ['x', 'X'])
        self.assertEqual(codedb.kvc_keys('setFoo:'), ['foo', 'Foo'])
        self.assertEqual(codedb.kvc_keys('isFoo'), ['isFoo', 'foo', 'Foo'])
        self.assertEqual(codedb.kvc_keys('_isFoo'), ['_isFoo', 'isFoo'])
        self.assertEqual(codedb.kvc_keys('_getFoo'), ['_getFoo', 'foo', 'Foo', 'getFoo'])
        self.assertEqual(codedb.kvc_keys('countOfFoo'), ['countOfFoo', 'foo', 'Foo'])

    def test_key_matches(self):
        self.assertTrue(codedb.key_matches('key', 'title', ['title']))
        self.assertFalse(codedb.key_matches('key', 'subtitle', ['title']))
        self.assertTrue(codedb.key_matches('key-path', 'window.title', ['title']))
        self.assertFalse(codedb.key_matches('key-path', 'window.titles', ['title']))
        self.assertTrue(codedb.key_matches('predicate-format', 'title == %@ AND count > 1', ['count']))
        self.assertFalse(codedb.key_matches('predicate-format', 'counter > 1', ['count']))
        self.assertFalse(codedb.key_matches('selector', 'count', ['count']))
        self.assertFalse(codedb.key_matches('key', None, ['count']))


def split(text):
    body, _, block = text.partition('\n--- status ---\n')
    return body.splitlines(), block


class SelectorQueryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_selector_root()
        cls.paths = base.make_paths(cls.root)
        base.write_cdb(cls.root, cls.paths.cdb, mains=(M, S, 'sources/user.m'))
        codedb.update(cls.paths, log=lambda m: None)

    def ask(self, query, *args, **kw):
        out = io.StringIO()
        status = query(self.paths, *args, out=out, **kw)
        lines, block = split(out.getvalue())
        return status, lines, block

    def test_methods(self):
        status, lines, block = self.ask(codedb.methods, 'count')
        self.assertEqual(status, 0)
        self.assertEqual(lines, [
            'sources/methods.h:10:27  -[Gadget count]  implementation synthesized accessor of property count  targets T',
            'sources/methods.h:10:27  -[Gadget count]  interface declaration (implicit), accessor of property count  '
            'targets T',
        ])
        self.assertIn('declarations: every file that current units read has them recorded\n', block)
        self.assertIn(codedb.DECLARATIONS_NOTE + '\n', block)
        for item in codedb.METHODS_NOT_IN_DATABASE:
            self.assertIn('  - %s\n' % item, block)
        self.assertIn(codedb.METHODS_SPEC.exit_text + '\n', block)
        self.assertNotIn('INCOMPLETE', block)

    def test_methods_made_by_macros_and_protocols(self):
        self.assertEqual(self.ask(codedb.methods, 'load_alpha')[1], [
            'sources/methods.m:22:1  +[Gadget load_alpha]  implementation definition  macro DEFINE_SETTING pasted '
            '(defined sources/methods.m:3, used at 22:1)  targets T'])
        self.assertEqual(self.ask(codedb.methods, 'weakSelf')[1], [
            'sources/methods.m:10:1  -[Gadget() weakSelf]  extension declaration  macro DECLARE_WEAK body (defined '
            'sources/methods.m:6, used at 10:1)  targets T',
            'sources/methods.m:21:7  -[Gadget weakSelf]  implementation definition  targets T'])
        self.assertEqual(self.ask(codedb.methods, 'shapeNamed:')[1], [
            'sources/methods.h:7:7  +[Shape shapeNamed:]  protocol declaration, optional  targets T'])

    def test_methods_none(self):
        status, lines, block = self.ask(codedb.methods, 'noSuchMethod')
        self.assertEqual((status, lines), (1, []))

    def test_selrefs(self):
        status, lines, block = self.ask(codedb.selrefs, 'reload')
        self.assertEqual(status, 0)
        self.assertEqual(lines, [
            'sources/selectors.m:11:23  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:15:13  Selectors  @selector(reload)  macro RELOAD_SEL body (defined '
            'sources/selectors.m:4, used at 15:13)  targets T',
            'sources/selectors.m:17:5  Selectors  NSSelectorFromString argument 0 (selector): selector-expr reload  '
            'targets T',
            'sources/selectors.m:17:57  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:18:5  Selectors  NSSelectorFromString argument 0 (selector): string-literal "reload"  '
            'targets T',
            'sources/selectors.m:19:5  Selectors  NSSelectorFromString argument 0 (selector): string-literal "reload"  '
            'targets T',
            'sources/selectors.m:26:8  Selectors  performSelector: argument 0 (selector): selector-expr reload  '
            'receiver Base *  targets T',
            'sources/selectors.m:26:34  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:30:8  Selectors  respondsToSelector: argument 0 (selector): selector-expr reload  '
            'receiver Base *  targets T',
            'sources/selectors.m:30:37  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:42:8  Selectors  setAction: argument 0 (selector): selector-expr reload  '
            'receiver Base *  targets T',
            'sources/selectors.m:42:28  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:48:5  Selectors  method_exchangeImplementations argument 0 (method): selector-expr '
            'reload, class Base  targets T',
            'sources/selectors.m:48:36  Selectors  class_getInstanceMethod argument 1 (selector): selector-expr '
            'reload, class Base  targets T',
            'sources/selectors.m:48:84  Selectors  @selector(reload)  targets T',
            'sources/selectors.m:50:23  Selectors  objc_msgSend argument 1 (selector): selector-expr reload  targets T',
            'sources/selectors.m:50:50  Selectors  @selector(reload)  targets T',
        ])
        for item in codedb.SELREFS_NOT_IN_DATABASE:
            self.assertIn('  - %s\n' % item, block)
        self.assertNotIn('declarations:', block)

    def test_selrefs_constant_and_block(self):
        self.assertEqual(self.ask(codedb.selrefs, 'name')[1], [
            'sources/selectors.m:20:5  Selectors  NSSelectorFromString argument 0 (selector): constant "name" '
            '(kNameKey)  targets T',
            'sources/selectors.m:32:8  Selectors  respondsToSelector: argument 0 (selector): constant "name" '
            '(kNameKey)  receiver Base *  targets T',
            'sources/selectors.m:32:27  Selectors  NSSelectorFromString argument 0 (selector): constant "name" '
            '(kNameKey)  targets T'])
        self.assertEqual(self.ask(codedb.selrefs, 'inBlock')[1], [
            'sources/selectors.m:16:44  Selectors  @selector(inBlock)  in block  targets T'])

    def test_reflective_dynamic_by_default(self):
        expected = [
            'sources/selectors.m: 9',
            '  sources/selectors.m:21:5  Selectors  NSSelectorFromString argument 0 (selector): dynamic dynamicName  '
            'targets T',
            '  sources/selectors.m:25:5  Selectors  NSClassFromString argument 0 (class): dynamic dynamicName  targets T',
            '  sources/selectors.m:29:8  Selectors  performSelector:withObject:afterDelay: argument 0 (selector): '
            'dynamic s  receiver Base *  targets T',
            '  sources/selectors.m:33:8  Selectors  respondsToSelector: argument 0 (selector): dynamic s  receiver Base '
            '*  targets T',
            '  sources/selectors.m:37:8  Selectors  valueForKey: argument 0 (key): dynamic dynamicName  receiver Base *'
            '  targets T',
            '  sources/selectors.m:41:8  Selectors  addObserver:forKeyPath:options:context: argument 1 (key-path): '
            'dynamic dynamicName  receiver Base *  targets T',
            '  sources/selectors.m:45:8  Selectors  setAction: argument 0 (selector): dynamic s  receiver Base *  '
            'targets T',
            '  sources/selectors.m:48:5  Selectors  method_exchangeImplementations argument 1 (method): dynamic '
            'class_getInstanceMethod(NSClassFromString(@"Gadget"), s)  targets T',
            '  sources/selectors.m:49:36  Selectors  class_getInstanceMethod argument 1 (selector): dynamic s, class '
            'Gadget  targets T',
            'by call: NSClassFromString 1, NSSelectorFromString 1, addObserver:forKeyPath:options:context: 1, '
            'class_getInstanceMethod 1, method_exchangeImplementations 1, performSelector:withObject:afterDelay: 1, '
            'respondsToSelector: 1, setAction: 1, valueForKey: 1',
            'not listed: 0 arguments that are nil, NULL or 0 (argument kind nil) and 0 that are _cmd (argument kind '
            'self-selector); codedb.py reflective --all lists them',
        ]
        status, lines, block = self.ask(codedb.reflective)
        self.assertEqual((status, lines), (0, expected))
        self.assertIn('rows printed: 9;', block)
        for item in codedb.REFLECTIVE_NOT_IN_DATABASE:
            self.assertIn('  - %s\n' % item, block)

    def test_reflective_all_and_kind(self):
        status, lines, block = self.ask(codedb.reflective, everything=True)
        self.assertEqual(lines[:2], ['sources/methods.m: 1',
                                     '  sources/methods.m:22:1  +[Gadget key_alpha]  valueForKey: argument 0 (key): '
                                     'string-literal "alpha"  receiver Class  macro DEFINE_SETTING body (defined '
                                     'sources/methods.m:3, used at 22:1)  targets T'])
        self.assertEqual(lines[2], 'sources/selectors.m: 42')
        status, lines, block = self.ask(codedb.reflective, everything=True, kind='key-path')
        self.assertEqual(lines[0], 'sources/selectors.m: 4')
        self.assertEqual(self.ask(codedb.reflective, kind='protocol')[:2], (1, []))

    def test_reach_property_getter(self):
        status, lines, block = self.ask(codedb.reach, 'count')
        self.assertEqual(status, 0)
        self.assertEqual(lines[:10], [
            'Message sends of count: 1',
            '  sources/user.m:4:15  UseGadget  receiver Gadget *  targets T',
            '@selector expressions and reflective calls resolving to count: 2',
            '  sources/selectors.m:38:8  Selectors  addObserver:forKeyPath:options:context: argument 1 (key-path): '
            'selector-expr count  receiver Base *  targets T',
            '  sources/selectors.m:38:64  Selectors  @selector(count)  targets T',
            'Key-value coding and key paths naming count: 1',
            '  sources/selectors.m:38:8  Selectors  addObserver:forKeyPath:options:context: argument 1 (key-path): '
            'selector-expr count  receiver Base *  targets T',
            'May be called by code outside this database: 0',
            INSIDE_NONE,
            'Not covered by reach:',
        ])
        self.assertEqual(lines[10], '  - 9 reflective calls whose argument is not a literal (5 selector, 1 class, '
                                    '1 key, 1 key-path, 1 method) can reach any selector, class or key: codedb.py '
                                    'reflective lists them')
        self.assertEqual(lines[11:-1], ['  - %s' % item for item in
                                        codedb.REACH_NOT_COVERED + [codedb.FRAMEWORK_CALLERS_NOT_COVERED]])
        # Then the text search of the code no unit compiles.
        self.assertTrue(lines[-1].startswith('Objective-C code that is not compiled: 0 ranges in 0 files'), lines[-1])
        self.assertIn('rows printed: 4;', block)
        self.assertIn('Not in this database:\n' + ''.join('  - %s\n' % item for item in codedb.NOT_IN_DATABASE_COMMON),
                      block)

    def test_reach_keys_from_literals_and_constants(self):
        lines = self.ask(codedb.reach, 'title')[1]
        self.assertIn('Key-value coding and key paths naming title: 5', lines)
        start = lines.index('Key-value coding and key paths naming title: 5')
        self.assertEqual(lines[start + 1:start + 6], [
            '  sources/selectors.m:34:8  Selectors  valueForKey: argument 0 (key): selector-expr title  receiver Base *'
            '  targets T',
            '  sources/selectors.m:35:8  Selectors  valueForKey: argument 0 (key): string-literal "title"  receiver '
            'Base *  targets T',
            '  sources/selectors.m:36:8  Selectors  valueForKey: argument 0 (key): constant "title" (kTitleKey)  '
            'receiver Base *  targets T',
            '  sources/selectors.m:39:8  Selectors  addObserver:forKeyPath:options:context: argument 1 (key-path): '
            'string-literal "title"  receiver Base *  targets T',
            '  sources/selectors.m:47:8  Selectors  setValue:forKey: argument 1 (key): string-literal "title"  '
            'receiver Base *  targets T',
        ])

    def test_reach_setter_with_custom_name_uses_the_property(self):
        status, lines, block = self.ask(codedb.reach, 'turn:')
        self.assertEqual(status, 1)
        self.assertEqual(lines[:6], ['Message sends of turn:: 0',
                                     '@selector expressions and reflective calls resolving to turn:: 0',
                                     'Key-value coding and key paths naming on: 0',
                                     'May be called by code outside this database: 0',
                                     INSIDE_NONE,
                                     'Not covered by reach:'])

    def test_reach_getter_with_custom_name_uses_the_property(self):
        lines = self.ask(codedb.reach, 'label')[1]
        start = lines.index('Key-value coding and key paths naming label, name: 1')
        self.assertEqual(lines[start + 1], '  sources/selectors.m:40:8  Selectors  addObserver:forKeyPath:options:context: '
                                           'argument 1 (key-path): constant "name" (kNameKey)  receiver Base *  targets T')

    def test_reach_not_an_accessor_and_with_sends(self):
        status, lines, block = self.ask(codedb.reach, 'performSelector:')
        self.assertEqual(status, 0)
        self.assertEqual(lines[:5], [
            'Message sends of performSelector:: 3',
            '  sources/selectors.m:26:8  Selectors  receiver Base *  targets T',
            '  sources/selectors.m:27:8  Selectors  receiver Base *  targets T',
            '  sources/selectors.m:28:8  Selectors  receiver Base *  targets T',
            '@selector expressions and reflective calls resolving to performSelector:: 0'])
        self.assertEqual(lines[5], 'Key-value coding and key paths naming no key: performSelector: is not an accessor '
                                   'of a property or a key-value coding shape: 0')

    def test_main_exit_statuses(self):
        common = ['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb, '--extractor', base.EXTRACTOR]
        saved = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = io.StringIO(), io.StringIO()
        try:
            statuses = [codedb.main(common + args) for args in (
                ['methods', 'count'], ['methods', 'nothing'], ['selrefs', 'reload'], ['selrefs', 'nothing'],
                ['reach', 'reload'], ['reach', 'nothing:at:'], ['reflective'], ['reflective', '--dynamic'],
                ['reflective', '--kind', 'protocol'])]
            missing = codedb.main(['--root', self.root, '--db', '/nonexistent/x.sqlite', 'methods', 'count'])
            listing = codedb.main(common + ['reflective', '--list'])
            output = sys.stdout.getvalue()
            unbuilt = codedb.main(common[:-1] + [os.path.join(self.root, 'none'), 'reflective', '--list'])
        finally:
            sys.stdout, sys.stderr = saved
        self.assertEqual(statuses, [0, 1, 0, 1, 0, 1, 0, 0, 1])
        self.assertEqual((missing, listing, unbuilt), (2, 0, 2))
        self.assertIn('name\tcall\tmatch\targument\tnames\tclass_argument\tcomment\n', output)
        self.assertIn('NSSelectorFromString\tfunction\texact\t0\tselector\t-1\tselector from a string\n', output)
        self.assertIn('performSelector\tmessage\tprefix\t0\tselector\t-1\t', output)

    def test_list_matches_the_extractor_table(self):
        table = codedb.reflective_table(self.paths)
        with open(os.path.join(base.CODEDB_DIR, 'extractor', 'reflective_table.h')) as f:
            source = f.read()
        entries = table.splitlines()[1:]
        self.assertEqual(len(entries), source.count('    {"'))
        self.assertIn('setAction:\tmessage\texact\t0\tselector\t-1\tcontrol or menu item action', entries)


class SelectorQueryMarksTest(unittest.TestCase):
    """Rows of a unit that is not current are marked, and the answer is
    incomplete, for every new query."""

    def setUp(self):
        self.root = make_selector_root()
        self.paths = base.make_paths(self.root)
        base.write_cdb(self.root, self.paths.cdb, mains=(M, S, 'sources/user.m'))
        codedb.update(self.paths, log=lambda m: None)
        con = sqlite3.connect(self.paths.db)
        con.execute("UPDATE tu_input SET digest = 'x' WHERE path = 'sources/selectors.m'")
        con.commit()
        con.close()

    def test_stale_rows_are_marked_and_exit_3(self):
        mark = 'STALE (input changed: sources/selectors.m)'
        for query, args in ((codedb.selrefs, ('save:',)), (codedb.reach, ('title',)), (codedb.reflective, ())):
            out = io.StringIO()
            self.assertEqual(query(self.paths, *args, out=out), 3, query)
            lines, block = split(out.getvalue())
            marked = [line for line in lines if mark in line]
            self.assertTrue(marked, (query, lines))
            self.assertIn('INCOMPLETE: 1 of 3 units are not current', block)
        out = io.StringIO()
        self.assertEqual(codedb.methods(self.paths, 'count', out=out), 3)
        self.assertNotIn('STALE', split(out.getvalue())[0][0])

    def test_method_rows_of_a_stale_unit_are_marked(self):
        con = sqlite3.connect(self.paths.db)
        con.execute("UPDATE tu_input SET digest = 'x' WHERE path = 'sources/methods.m'")
        con.commit()
        con.close()
        out = io.StringIO()
        self.assertEqual(codedb.methods(self.paths, 'load_alpha', out=out), 3)
        self.assertEqual(split(out.getvalue())[0], [
            'sources/methods.m:22:1  +[Gadget load_alpha]  implementation definition  macro DEFINE_SETTING pasted '
            '(defined sources/methods.m:3, used at 22:1)  targets T  STALE (input changed: sources/methods.m)'])
        self.assertIn('rows printed: 1; from units that are not current: 1 (marked)\n', out.getvalue())


class NotParsedSearchTest(unittest.TestCase):
    """With no rows, a file that is not parsed and that mentions the selector
    in a form the query searches makes the answer incomplete."""

    def setUp(self):
        self.root = make_selector_root()
        self.paths = base.make_paths(self.root)
        with open(os.path.join(self.root, 'sources', 'lonely.m'), 'w') as f:
            f.write('// not compiled\n- (void)lonely:(int)x {}\nSEL s = @selector(lonely:);\n'
                    '@property (nonatomic) int solitary;\n')
        base.write_cdb(self.root, self.paths.cdb, mains=(M, S, 'sources/user.m'))
        codedb.update(self.paths, log=lambda m: None)

    def test_methods_finds_a_declaration_line(self):
        out = io.StringIO()
        self.assertEqual(codedb.methods(self.paths, 'lonely:', out=out), 3)
        self.assertIn('    sources/lonely.m:2 (method declaration): - (void)lonely:(int)x {}\n', out.getvalue())
        self.assertIn(codedb.METHODS_SEARCH_FORMS + '\n', out.getvalue())
        out = io.StringIO()
        self.assertEqual(codedb.methods(self.paths, 'setSolitary:', out=out), 3)
        self.assertIn('    sources/lonely.m:4 (property solitary): @property (nonatomic) int solitary;\n',
                      out.getvalue())

    def test_selrefs_and_reach_find_the_selector(self):
        out = io.StringIO()
        self.assertEqual(codedb.selrefs(self.paths, 'lonely:', out=out), 3)
        self.assertIn('    sources/lonely.m:3 (@selector): SEL s = @selector(lonely:);\n', out.getvalue())
        out = io.StringIO()
        self.assertEqual(codedb.reach(self.paths, 'lonely:', out=out), 3)
        self.assertIn('    sources/lonely.m:3 (message send; @selector): SEL s = @selector(lonely:);\n', out.getvalue())
        self.assertEqual(codedb.selrefs(self.paths, 'nowhere', out=io.StringIO()), 1)


if __name__ == '__main__':
    unittest.main()
