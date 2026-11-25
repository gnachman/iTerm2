#!/usr/bin/env python3
"""Tests for unit_ast.py, the AST facts behind the trivial path's conditions
T1, T4 and T6 (docs/swift-migration/lifecycle.md section 3).

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_unit_ast.py'

The pure parts run on literal input. AstFileTest parses a small file with
upstream clang 22 (as unit_ast.py finds it) and the SDK, with modules, in a
directory under the system's temporary directory; it is skipped when that
clang is missing.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import unit_ast  # noqa: E402

CLASSES = {'NSString', 'NSError', 'NSObject', 'NSArray', 'iTermFoo'}


class TypeTest(unittest.TestCase):
    def test_objective_c_pointers_are_safe(self):
        for t in ('NSString *', 'NSString * _Nonnull', 'NSArray<NSString *> *', '__kindof NSObject *',
                  'NSObject<NSCopying> *', 'id', 'id<NSCopying>', 'void (^)(NSString *)', 'NSInteger', 'CGRect',
                  'CFStringRef', 'SEL', 'iTermFoo *', 'const NSString *'):
            self.assertIsNone(unit_ast.unsafe_type(t, CLASSES), t)

    def test_c_pointers_and_arrays_are_unsafe(self):
        for t, why in (('char *', 'a C pointer'), ('const char *', 'a C pointer'), ('int[3]', 'a C array'),
                       ('NSError **', 'a pointer to a pointer'), ('NSError * _Nullable *', 'a pointer to a pointer'),
                       ('void (*)(int)', 'a function pointer'), ('struct foo *', 'a C pointer'),
                       ('CGFloat *', 'a C pointer'), ('void (^)(char *)', 'a C pointer'),
                       ('iTermUnknown *', 'a C pointer')):
            self.assertTrue((unit_ast.unsafe_type(t, CLASSES) or '').startswith(why), (t, why))

    def test_method_families(self):
        for sel, fam in (('copy', 'copy'), ('copyWithZone:', 'copy'), ('mutableCopy', 'mutableCopy'),
                         ('newThing', 'new'), ('alloc', 'alloc'), ('_newFoo', 'new'), ('copyright', None),
                         ('newline', None), ('init', None), ('valueForUndefinedKey:', None)):
            self.assertEqual(unit_ast.method_family(sel), fam, sel)


def dump(objs):
    """A dump in clang's layout: the translation unit at indent 0, its
    declarations at indent 4."""
    text = json.dumps({'id': '0x1', 'kind': 'TranslationUnitDecl', 'loc': {}, 'range': {'begin': {}, 'end': {}},
                       'inner': objs}, indent=2)
    return io.StringIO(text + '\n')


def loc(offset, **kw):
    d = {'offset': offset}
    d.update(kw)
    return d


class StreamTest(unittest.TestCase):
    def test_locations_carry_file_and_line_across_declarations(self):
        objs = [
            {'id': '0x2', 'kind': 'TypedefDecl', 'loc': loc(1, file='/h.h', line=3, col=1, tokLen=1),
             'range': {'begin': loc(1, col=1), 'end': loc(9, col=9)}},
            # Same file as the last location: no file key, but in /h.h.
            {'id': '0x3', 'kind': 'FunctionDecl', 'loc': loc(20, line=7, col=1), 'name': 'inHeader',
             'range': {'begin': loc(20, col=1), 'end': loc(30, line=9, col=1)}},
            {'id': '0x4', 'kind': 'FunctionDecl',
             'loc': loc(5, file='/m.m', line=2, col=5,
                        includedFrom={'file': '/other.m'}), 'name': 'inMain',
             'range': {'begin': loc(1, col=1), 'end': loc(40, line=6, col=1)},
             'inner': [{'id': '0x5', 'kind': 'CompoundStmt',
                        'range': {'begin': loc(12, line=2, col=12), 'end': loc(40, line=6, col=1)}}]},
            # Back in the main file's state: no file key at all.
            {'id': '0x6', 'kind': 'FunctionDecl', 'loc': loc(50, line=8, col=1), 'name': 'alsoMain',
             'range': {'begin': loc(50, col=1), 'end': loc(60, line=10, col=1)},
             'inner': [{'id': '0x7', 'kind': 'CompoundStmt',
                        'range': {'begin': loc(55, line=8, col=1), 'end': loc(60, line=10, col=1)}}]},
        ]
        decls = list(unit_ast.main_file_decls(dump(objs), '/m.m'))
        self.assertEqual([d['name'] for d in decls], ['inMain', 'alsoMain'])
        facts = unit_ast.Facts('/m.m', CLASSES, True)
        for d in decls:
            facts.top(d)
        r = facts.result()
        self.assertEqual([(b['name'], b['first'], b['last']) for b in r['bodies']],
                         [('inMain', 2, 6), ('alsoMain', 8, 10)])
        self.assertEqual(r['body_lines'], 5 + 3)

    def test_included_from_does_not_change_the_file(self):
        objs = [
            {'id': '0x2', 'kind': 'FunctionDecl', 'name': 'a',
             'loc': loc(1, file='/m.m', line=1, col=1, includedFrom={'file': '/h.h'}),
             'range': {'begin': loc(1, col=1), 'end': loc(2, col=2)}},
            {'id': '0x3', 'kind': 'FunctionDecl', 'name': 'b', 'loc': loc(3, line=4, col=1),
             'range': {'begin': loc(3, col=1), 'end': loc(4, col=2)}},
        ]
        self.assertEqual([d['name'] for d in unit_ast.main_file_decls(dump(objs), '/m.m')], ['a', 'b'])


SAMPLE = r'''#import <Foundation/Foundation.h>
@interface iTermFoo : NSObject
@end
@implementation iTermFoo
- (id)valueForUndefinedKey:(NSString *)key {
    return @[];
}
- (NSString *)describe:(NSString *)s {
    NSError *error = nil;
    NSString *t = [NSString stringWithContentsOfFile:s encoding:NSUTF8StringEncoding error:&error];
    return t ?: @"none";
}
@end
'''

OWNED = r'''#import <Foundation/Foundation.h>
static int Sum(int *values) {
    return values[0] + *values;
}
@interface iTermFoo : NSObject
@end
@implementation iTermFoo
- (id)keep:(id)x {
    void (^b)(void) = ^{
        NSLog(@"%s", __FUNCTION__);
    };
    b();
    return [[x retain] autorelease];
}
- (id)newThing {
    return [[NSObject alloc] init];
}
@end
'''


@unittest.skipUnless(any(os.access(os.path.join(p, 'bin', 'clang'), os.X_OK) for p in (
    os.environ.get('CODEDB_LLVM_PREFIX') or '/opt/homebrew/opt/llvm@22', '/usr/local/opt/llvm@22')),
    'no upstream clang 22')
class AstFileTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = os.path.realpath(tempfile.mkdtemp(prefix='unit-ast-test-'))
        cls.sdk = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True).stdout.strip()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def facts(self, name, text, arc=False):
        path = os.path.join(self.dir, name)
        with open(path, 'w') as f:
            f.write(text)
        args = ['-x', 'objective-c', '--target=arm64-apple-macos13', '-isysroot', self.sdk, '-fmodules',
                '-fmodules-cache-path=' + os.path.join(self.dir, 'modcache')] + (['-fobjc-arc'] if arc else []) + [
                    path]
        return unit_ast.file_facts(unit_ast.default_clang(), args, path, CLASSES, arc, cwd=self.dir)

    def test_a_small_category_shape_is_clean(self):
        f = self.facts('Sample.m', SAMPLE)
        self.assertEqual([(b['name'], b['lines']) for b in f['bodies']],
                         [('-[iTermFoo valueForUndefinedKey:]', 3), ('-[iTermFoo describe:]', 5)])
        self.assertEqual(f['body_lines'], 8)
        self.assertEqual(f['ownership'], [])
        self.assertEqual(f['unsafe'], [], 'an &error out-parameter is not an unsafe pointer')

    def test_ownership_and_unsafe_code_is_reported(self):
        f = self.facts('Owned.m', OWNED)
        own = '\n'.join(f['ownership'])
        for what in ('sends retain', 'sends autorelease', 'a block literal', 'newThing', 'new family'):
            self.assertIn(what, own)
        unsafe = '\n'.join(f['unsafe'])
        for what in ('ParmVarDecl values is a C pointer', 'a C subscript', 'a dereference', 'a C string'):
            self.assertIn(what, unsafe)
        self.assertEqual(f['body_lines'], 3 + 7 + 3)

    def test_under_arc_ownership_is_not_reported(self):
        f = self.facts('Arc.m', SAMPLE.replace('return @[];', 'void (^b)(void) = ^{};\n    b();\n    return @[];'),
                       arc=True)
        self.assertEqual(f['ownership'], [])
        self.assertTrue(f['arc'])

    def test_bridge_casts_under_arc(self):
        text = ('#import <Foundation/Foundation.h>\n'
                'CFTypeRef Keep(id o) {\n    return (__bridge_retained CFTypeRef)o;\n}\n'
                'id Take(CFStringRef s) {\n    return (__bridge_transfer NSString *)s;\n}\n'
                'id Borrow(CFStringRef s) {\n    return (__bridge NSString *)s;\n}\n')
        f = self.facts('Bridge.m', text, arc=True)
        self.assertEqual(f['retained'], ['line 3 a __bridge_retained cast', 'line 6 a __bridge_transfer cast'])

    def test_an_init_under_arc_is_not_retained_ownership(self):
        f = self.facts('Init.m', '#import <Foundation/Foundation.h>\n@interface iTermFoo : NSObject\n@end\n'
                       '@implementation iTermFoo\n- (instancetype)init {\n    return [super init];\n}\n@end\n', arc=True)
        self.assertEqual(f['retained'], [])

    def test_a_parse_error_is_an_error(self):
        with self.assertRaises(unit_ast.ASTError):
            self.facts('Broken.m', '@implementation Missing\n- (void)x { [self ' + '\n@end\n')


if __name__ == '__main__':
    unittest.main()
