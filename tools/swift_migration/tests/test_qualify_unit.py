#!/usr/bin/env python3
"""Tests for qualify_unit.py, the light path's qualifying checks
(docs/swift-migration/lifecycle.md section 3).

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_qualify_unit.py'

The fixture is the entry-point census's (tests/fixtures/entry_points, built
by entry_points_harness.py with the real extractor and Swift reader) plus
the small classes QUALIFY_FILES writes, each made to pass or to fail
particular conditions. No xcodebuild, nothing written to tmp/codedb.
"""

import io
import json
import os
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import entry_points_harness as harness  # noqa: E402  (imports codedb and swiftdb first)
import qualify_unit as qu  # noqa: E402

PADDING = ''.join('// padding line %d\n' % i for i in range(520))

QUALIFY_FILES = {
    # A leaf: small, one outside user, its own test, nothing else.
    'sources/Leaf.h': '#import <Foundation/Foundation.h>\n@interface iTermQLeaf : NSObject\n'
                      '@property (nonatomic, copy) NSString *leafName;\n- (NSString *)leafGreeting;\n@end\n',
    'sources/Leaf.m': '#import "Leaf.h"\n@implementation iTermQLeaf\n- (NSString *)leafGreeting {\n'
                      '    return [@"hi " stringByAppendingString:self.leafName ?: @""];\n}\n@end\n',
    'sources/LeafUser.m': '#import "Leaf.h"\nvoid LeafUse(void) {\n    iTermQLeaf *leaf = [[iTermQLeaf alloc] init];\n'
                          '    leaf.leafName = @"x";\n    [leaf leafGreeting];\n}\n',
    'ModernTests/iTermQLeafTests.m': '#import "../sources/Leaf.h"\nvoid LeafTest(void) {\n'
                                     '    [[[iTermQLeaf alloc] init] leafGreeting];\n}\n',
    # Everything wrong.
    'sources/Busy.h': '#import <Foundation/Foundation.h>\n@interface iTermQBusy : NSObject <NSSecureCoding>\n'
                      '@property (copy) NSString *busyName;\n- (void)busyWork;\n@end\n',
    'sources/Busy.m': '#import "Busy.h"\n#import <objc/runtime.h>\n@implementation iTermQBusy\n'
                      '+ (BOOL)supportsSecureCoding {\n    return YES;\n}\n'
                      '+ (void)load {\n}\n'
                      '- (instancetype)initWithCoder:(NSCoder *)coder {\n    return [super init];\n}\n'
                      '- (void)encodeWithCoder:(NSCoder *)coder {\n'
                      '    [coder encodeObject:self.busyName forKey:@"n"];\n}\n'
                      '- (void)dealloc {\n    [[NSNotificationCenter defaultCenter] removeObserver:self];\n'
                      '    [super dealloc];\n}\n'
                      '- (void)busyWork {\n    @synchronized(self) {\n    }\n'
                      '    dispatch_async(dispatch_get_main_queue(), ^{\n    });\n'
                      '    [[NSUserDefaults standardUserDefaults] setObject:@"v" forKey:@"k"];\n'
                      '    objc_setAssociatedObject(self, "k", @1, OBJC_ASSOCIATION_RETAIN);\n'
                      '    NSLog(@"%@", NSStringFromClass(self.class));\n'
                      '    [self.busyName writeToFile:@"/tmp/x" atomically:YES encoding:NSUTF8StringEncoding '
                      'error:nil];\n}\n@end\n' + PADDING,
    'sources/BusyUser1.m': '#import "Busy.h"\nvoid BusyUse1(void) {\n    [[[iTermQBusy alloc] init] busyWork];\n}\n',
    'sources/BusyUser2.m': '#import "Busy.h"\nvoid BusyUse2(void) {\n    [[[iTermQBusy alloc] init] busyWork];\n}\n',
    'sources/BusyUser3.m': '#import "Busy.h"\nvoid BusyUse3(void) {\n    [[[iTermQBusy alloc] init] busyWork];\n}\n',
    'sources/BusyUser4.m': '#import "Busy.h"\nid BusyUse4(iTermQBusy *busy) {\n'
                           '    return [busy valueForKey:@"busyName"];\n}\n',
    # A leaf in a hot-path directory.
    'sources/VT100/Hot.h': '#import <Foundation/Foundation.h>\n@interface iTermQHot : NSObject\n'
                           '- (int)hotValue;\n@end\n',
    'sources/VT100/Hot.m': '#import "Hot.h"\n@implementation iTermQHot\n- (int)hotValue {\n    return 1;\n}\n@end\n',
    # A leaf that a file no target compiles names.
    'sources/Shy.h': '#import <Foundation/Foundation.h>\n@interface iTermQShy : NSObject\n- (int)shyValue;\n@end\n',
    'sources/Shy.m': '#import "Shy.h"\n@implementation iTermQShy\n- (int)shyValue {\n    return 2;\n}\n@end\n',
    'sources/ShyUnbuilt.m': '#import "Shy.h"\nvoid ShyUse(void) {\n    [[[iTermQShy alloc] init] shyValue];\n}\n',
    # A method whose selector another class shares and that a #selector
    # names (iTermWidget's go): the census hit may be for the other class.
    'sources/Shared.h': '#import <Foundation/Foundation.h>\n@interface iTermQShared : NSObject\n- (void)go;\n@end\n',
    'sources/Shared.m': '#import "Shared.h"\n@implementation iTermQShared\n- (void)go {\n}\n@end\n',
    # A method only this class has, named by @selector elsewhere.
    'sources/Sel.h': '#import <Foundation/Foundation.h>\n@interface iTermQSel : NSObject\n- (void)qselUnique;\n@end\n',
    'sources/Sel.m': '#import "Sel.h"\n@implementation iTermQSel\n- (void)qselUnique {\n}\n@end\n',
    'sources/SelUser.m': '#import "Sel.h"\nSEL SelUse(void) {\n    return @selector(qselUnique);\n}\n',
    # Objective-C++.
    'sources/Cxx.h': '#import <Foundation/Foundation.h>\n@interface iTermQCxx : NSObject\n- (int)cxxValue;\n@end\n',
    'sources/Cxx.mm': '#import "Cxx.h"\n@implementation iTermQCxx\n- (int)cxxValue {\n    return 3;\n}\n@end\n',
    # A -dealloc that only releases.
    'sources/Rel.h': '#import <Foundation/Foundation.h>\n@interface iTermQRel : NSObject {\n    NSString *_held;\n}\n'
                     '- (void)hold:(NSString *)s;\n@end\n',
    'sources/Rel.m': '#import "Rel.h"\n@implementation iTermQRel\n- (void)hold:(NSString *)s {\n'
                     '    [_held release];\n    _held = [s retain];\n}\n- (void)dealloc {\n    [_held release];\n'
                     '    [super dealloc];\n}\n@end\n',
    # An override of an NSObject method whose name a resource mentions.
    'sources/Init.h': '#import <Foundation/Foundation.h>\n@interface iTermQInit : NSObject\n'
                      '- (instancetype)init;\n@end\n',
    'sources/Init.m': '#import "Init.h"\n@implementation iTermQInit\n- (instancetype)init {\n'
                      '    return [super init];\n}\n'
                      '@end\n',
    'OtherResources/init.json': '{"call": "init"}\n',
    # The hot-path list, naming one fixture class.
    'docs/swift-migration/hot-paths.md': '# Hot paths\n\n| Unit | Reason | Added |\n|---|---|---|\n'
                                         '| `iTermQListedHot` | per frame | 2026-11-22 |\n',
    'sources/ListedHot.h': '#import <Foundation/Foundation.h>\n@interface iTermQListedHot : NSObject\n'
                           '- (int)listedValue;\n@end\n',
    'sources/ListedHot.m': '#import "ListedHot.h"\n@implementation iTermQListedHot\n- (int)listedValue {\n'
                           '    return 4;\n}\n@end\n',
}


def add_class(files, name, members, body, stem=None, ext='.m', imports=''):
    """A class iTermQName in sources/Name.h and Name.m (or stem)."""
    stem = stem or name.replace('iTermQ', 'Q')
    files['sources/%s.h' % stem] = ('#import <Foundation/Foundation.h>\n%s@interface %s : NSObject%s\n@end\n' %
                                    (imports, name, members))
    files['sources/%s%s' % (stem, ext)] = '#import "%s.h"\n@implementation %s\n%s@end\n' % (stem, name, body)


def one_line_method(sel, value):
    return '- (int)%s {\n    return %d;\n}\n' % (sel, value)


# One class per condition id (and per trigger of condition 7), each made to
# FAIL that condition and no other; and the MANUAL triggers.
add_class(QUALIFY_FILES, 'iTermQBig', '\n- (int)qbigValue;',
          one_line_method('qbigValue', 5) + ''.join('// big %d\n' % i for i in range(520)))
add_class(QUALIFY_FILES, 'iTermQTyped', '\n- (int)qtypedValue;', one_line_method('qtypedValue', 6))
for _i in range(1, 5):
    QUALIFY_FILES['sources/TypedUser%d.h' % _i] = (
        '#import <Foundation/Foundation.h>\n@class iTermQTyped;\n// iTermQTyped in a comment does not count\n'
        '@interface QTypedHolder%d : NSObject\n@property (nonatomic, strong) iTermQTyped *typed%d;\n@end\n' % (_i, _i))
add_class(QUALIFY_FILES, 'iTermQXib', '\n- (int)qxibValue;', one_line_method('qxibValue', 7))
QUALIFY_FILES['sources/QXib.xib'] = (
    '<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.Cocoa.XIB" version="3.0">\n'
    '    <objects>\n        <customObject id="-2" userLabel="File\'s Owner" customClass="iTermQXib"/>\n'
    '    </objects>\n</document>\n')
add_class(QUALIFY_FILES, 'iTermQPlist', '\n- (int)qplistValue;', one_line_method('qplistValue', 8))
QUALIFY_FILES['plists/QInfo.plist'] = (
    '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>NSPrincipalClass</key>\n'
    '\t<string>iTermQPlist</string>\n</dict>\n</plist>\n')
add_class(QUALIFY_FILES, 'iTermQCoder', ' <NSCoding>\n- (int)qcoderValue;',
          '- (instancetype)initWithCoder:(NSCoder *)coder {\n    return [super init];\n}\n'
          '- (void)encodeWithCoder:(NSCoder *)coder {\n}\n' + one_line_method('qcoderValue', 9))
add_class(QUALIFY_FILES, 'iTermQReflect', '\n- (NSString *)qreflectName;',
          '- (NSString *)qreflectName {\n    return NSStringFromClass(self.class);\n}\n')
add_class(QUALIFY_FILES, 'iTermQKvo', '\n- (void)qkvoTouch;',
          '- (void)qkvoTouch {\n    [self willChangeValueForKey:@"qkvoOther"];\n'
          '    [self didChangeValueForKey:@"qkvoOther"];\n}\n')
add_class(QUALIFY_FILES, 'iTermQLoad', '\n- (int)qloadValue;',
          '+ (void)load {\n}\n' + one_line_method('qloadValue', 10))
add_class(QUALIFY_FILES, 'iTermQDealloc', '\n- (int)qdeallocValue;',
          one_line_method('qdeallocValue', 11) + '- (void)dealloc {\n'
          '    [[NSNotificationCenter defaultCenter] removeObserver:self];\n    [super dealloc];\n}\n')
add_class(QUALIFY_FILES, 'iTermQAtomic', '\n@property (copy) NSString *qatomName;', '')
add_class(QUALIFY_FILES, 'iTermQAssoc', '\n- (void)qassocAttach;',
          '- (void)qassocAttach {\n    objc_setAssociatedObject(self, "k", nil, OBJC_ASSOCIATION_RETAIN);\n}\n',
          imports='#import <objc/runtime.h>\n')
add_class(QUALIFY_FILES, 'iTermQSwizzle', '\n+ (void)qswizzleSwap:(Method)a with:(Method)b;',
          '+ (void)qswizzleSwap:(Method)a with:(Method)b {\n    method_exchangeImplementations(a, b);\n}\n',
          imports='#import <objc/runtime.h>\n')
add_class(QUALIFY_FILES, 'iTermQIvar', ' {\n@public\n    int qivarCount;\n}\n- (int)qivarValue;',
          '- (int)qivarValue {\n    return qivarCount;\n}\n')
QUALIFY_FILES['sources/IvarUser.m'] = ('#import "QIvar.h"\nvoid IvarUse(void) {\n'
                                       '    iTermQIvar *o = [[iTermQIvar alloc] init];\n    o->qivarCount = 1;\n}\n')
add_class(QUALIFY_FILES, 'iTermQLock', '\n- (void)qlockRun;',
          '- (void)qlockRun {\n    @synchronized(self) {\n    }\n}\n')
add_class(QUALIFY_FILES, 'iTermQQueue', '\n- (void)qqueueRun;',
          '- (void)qqueueRun {\n    dispatch_async(dispatch_get_main_queue(), ^{\n    });\n}\n')
add_class(QUALIFY_FILES, 'iTermQStore', '\n- (void)qstoreSave;',
          '- (void)qstoreSave {\n    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"q"];\n}\n')
# Profile keys: a header of string macros, as ITAddressBookMgr.h is.
QUALIFY_FILES['sources/QKeys.h'] = ''.join('#define KEY_QFIELD%d @"QField%d"\n' % (_i, _i) for _i in range(25))
add_class(QUALIFY_FILES, 'iTermQProfileKey', '\n- (id)qprofileKeyRead:(NSDictionary *)d;',
          '- (id)qprofileKeyRead:(NSDictionary *)d {\n    return d[KEY_QFIELD3];\n}\n', imports='#import "QKeys.h"\n')
# One level of helper: a send to a class that itself fails condition 7.
add_class(QUALIFY_FILES, 'iTermQStoreClient', '\n- (void)qstoreClientRun;',
          '- (void)qstoreClientRun {\n    [[[iTermQStore alloc] init] qstoreSave];\n}\n',
          imports='#import "QStore.h"\n')
# Sent to from per-frame code (PTYTextView*).
add_class(QUALIFY_FILES, 'iTermQPerFrame', '\n- (int)qperFrameValue;', one_line_method('qperFrameValue', 12))
QUALIFY_FILES['sources/PTYTextViewQ.m'] = ('#import "QPerFrame.h"\nvoid PTYTextViewQUse(void) {\n'
                                           '    [[[iTermQPerFrame alloc] init] qperFrameValue];\n}\n')
# Used only by a class (iTermQMid) that per-frame code uses: one level.
add_class(QUALIFY_FILES, 'iTermQDeep', '\n- (int)qdeepValue;', one_line_method('qdeepValue', 13))
add_class(QUALIFY_FILES, 'iTermQMid', '\n- (int)qmidValue;',
          '- (int)qmidValue {\n    return [[[iTermQDeep alloc] init] qdeepValue];\n}\n', imports='#import "QDeep.h"\n')
QUALIFY_FILES['sources/PTYTextViewQ2.m'] = ('#import "QMid.h"\nvoid PTYTextViewQ2Use(void) {\n'
                                            '    [[[iTermQMid alloc] init] qmidValue];\n}\n')
# Schedules work with a timer.
add_class(QUALIFY_FILES, 'iTermQTimer', '\n- (void)qtimerStart;',
          '- (void)qtimerStart {\n    [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) {\n'
          '    }];\n}\n')

EXTRA_MAINS = tuple(f for f in QUALIFY_FILES if f.endswith(('.m', '.mm')) and f.startswith('sources/') and
                    f != 'sources/ShyUnbuilt.m')
EXTRA_TEST_MAINS = ('ModernTests/iTermQLeafTests.m',)


def write_qualify_files(root):
    for rel, text in QUALIFY_FILES.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(text)


def tearDownModule():
    harness.cleanup()


class QualifyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths = harness.build(edit=write_qualify_files, extra_mains=EXTRA_MAINS,
                                            extra_test_mains=EXTRA_TEST_MAINS)

    def args(self):
        p = self.paths
        return ['--root', self.root, '--db', p.db, '--cdb', p.cdb, '--fragments', p.fragments, '--swift-work',
                p.swift_work, '--swift-reader', p.swift_reader, '--extractor', p.extractor]

    def run_json(self, *argv):
        out = io.StringIO()
        status = qu.main(self.args() + ['--json'] + list(argv), out=out)
        return status, json.loads(out.getvalue())

    def run_text(self, *argv):
        out = io.StringIO()
        status = qu.main(self.args() + list(argv), out=out)
        return status, out.getvalue()

    def statuses(self, d):
        return dict((c['id'], c['status']) for c in d['conditions'])

    def condition(self, d, cid):
        return next(c for c in d['conditions'] if c['id'] == cid)

    def test_every_condition_of_lifecycle_section_3_is_reported(self):
        status, d = self.run_json('iTermQLeaf')
        self.assertEqual([c['id'] for c in d['conditions']], list(qu.CONDITION_IDS))
        for c in d['conditions']:
            self.assertIn(c['status'], ('PASS', 'FAIL', 'MANUAL'))
            self.assertTrue(c['how'], c['id'])
            self.assertTrue(c['evidence'], c['id'])

    def test_a_leaf_passes_everything_but_the_callers_thread(self):
        status, d = self.run_json('iTermQLeaf')
        st = self.statuses(d)
        self.assertEqual(st.pop('5c'), 'MANUAL')
        self.assertEqual(set(st.values()), {'PASS'}, st)
        self.assertEqual(status, 0)
        self.assertEqual(d['exit_status'], 0)
        self.assertEqual(d['unit_files'], ['sources/Leaf.h', 'sources/Leaf.m'])

    def test_users_from_the_database_without_the_units_own_tests(self):
        status, d = self.run_json('iTermQLeaf')
        users = self.condition(d, '2')
        text = '\n'.join(users['evidence'])
        self.assertIn('sources/LeafUser.m', text)
        self.assertIn('1 file', text)
        self.assertIn('not counted: ModernTests/iTermQLeafTests.m (the unit\'s own tests)', text)

    def test_the_callers_thread_can_be_recorded(self):
        status, d = self.run_json('iTermQLeaf', '--callers-thread', 'main thread: LeafUse runs from a menu action')
        c = self.condition(d, '5c')
        self.assertEqual(c['status'], 'RECORDED')
        self.assertEqual(status, 0)
        status, text = self.run_text('iTermQLeaf', '--callers-thread', 'main thread')
        self.assertRegex(text, r'(?m)^RECORDED +5c ')
        self.assertNotRegex(text, r'(?m)^PASS +5c ')
        self.assertIn('recorded by a person: main thread: LeafUse runs from a menu action', c['evidence'])

    def test_text_output_prints_status_evidence_and_how(self):
        status, text = self.run_text('iTermQLeaf')
        self.assertEqual(status, 0)
        self.assertRegex(text, r'(?m)^PASS +1 ')
        self.assertRegex(text, r'(?m)^MANUAL +5c ')
        self.assertIn('how: ', text)

    def test_everything_wrong(self):
        status, d = self.run_json('iTermQBusy')
        st = self.statuses(d)
        for cid in ('1', '2', '3c', '3d', '3e', '4b', '4c', '4d', '4e', '5a', '5b', '7'):
            self.assertEqual(st[cid], 'FAIL', (cid, self.condition(d, cid)))
        self.assertEqual(status, 1)
        self.assertIn('-[iTermQBusy dealloc] sends removeObserver:', '\n'.join(self.condition(d, '4c')['evidence']))
        self.assertIn('busyName', '\n'.join(self.condition(d, '4d')['evidence']))
        self.assertIn('sources/BusyUser4.m', '\n'.join(self.condition(d, '3e')['evidence']))
        self.assertIn('NSStringFromClass', '\n'.join(self.condition(d, '3d')['evidence']))
        self.assertIn('4 files', '\n'.join(self.condition(d, '2')['evidence']))

    def test_hot_path_directory(self):
        status, d = self.run_json('iTermQHot')
        st = self.statuses(d)
        self.assertEqual(st['6'], 'FAIL')
        self.assertEqual(status, 1)

    def test_hot_path_list(self):
        status, d = self.run_json('iTermQListedHot')
        c = self.condition(d, '6')
        self.assertEqual(c['status'], 'FAIL')
        self.assertIn('hot-paths.md lists iTermQListedHot', c['evidence'])

    def test_interface_builder_and_registry(self):
        status, d = self.run_json('iTermWidget')
        st = self.statuses(d)
        self.assertEqual(st['3a'], 'FAIL')
        self.assertIn('sources/Main.xib', '\n'.join(self.condition(d, '3a')['evidence']))
        self.assertEqual(st['3d'], 'FAIL')
        self.assertIn('iTermWidget.fooBar', '\n'.join(self.condition(d, '3d')['evidence']))

    def test_a_file_the_database_does_not_parse_is_counted_by_text(self):
        status, d = self.run_json('iTermQShy')
        c = self.condition(d, '2')
        self.assertEqual(c['status'], 'PASS')
        self.assertIn('sources/ShyUnbuilt.m', '\n'.join(c['evidence']))
        self.assertIn('text search', '\n'.join(c['evidence']))
        self.assertEqual(status, 0)

    def test_a_census_hit_on_a_shared_selector_is_manual(self):
        status, d = self.run_json('iTermQShared')
        c = self.condition(d, '3f')
        self.assertEqual(c['status'], 'MANUAL', c)
        self.assertIn('-go', '\n'.join(c['evidence']))

    def test_a_census_hit_on_a_selector_only_this_class_has_fails(self):
        status, d = self.run_json('iTermQSel')
        c = self.condition(d, '3f')
        self.assertEqual(c['status'], 'FAIL', c)
        self.assertIn('-qselUnique', '\n'.join(c['evidence']))

    def test_a_census_hit_on_a_selector_nsobject_declares_is_not_evidence(self):
        status, d = self.run_json('iTermQInit')
        c = self.condition(d, '3f')
        self.assertEqual(c['status'], 'PASS', c)
        self.assertIn('-init', '\n'.join(c['evidence']))
        self.assertIn('NSObject', '\n'.join(c['evidence']))

    # Each condition the tool can FAIL, with a fixture that FAILs it and
    # nothing else (5c is never FAIL: it is MANUAL or RECORDED).
    ALONE = [('1', 'iTermQBig'), ('2', 'iTermQTyped'), ('3a', 'iTermQXib'), ('3b', 'iTermQPlist'),
             ('3c', 'iTermQCoder'), ('3d', 'iTermQReflect'), ('3e', 'iTermQKvo'), ('3f', 'iTermQSel'),
             ('4a', 'iTermQCxx'), ('4b', 'iTermQLoad'), ('4c', 'iTermQDealloc'), ('4d', 'iTermQAtomic'),
             ('4e', 'iTermQAssoc'), ('4f', 'iTermQSwizzle'), ('4g', 'iTermQIvar'), ('5a', 'iTermQLock'),
             ('5b', 'iTermQQueue'), ('6', 'iTermQHot'), ('7', 'iTermQStore'), ('7', 'iTermQProfileKey')]

    def test_every_failable_condition_fails_alone_on_its_fixture(self):
        self.assertEqual(sorted(set(cid for cid, _ in self.ALONE)), sorted(x for x in qu.CONDITION_IDS if x != '5c'))
        for cid, cls_name in self.ALONE:
            status, d = self.run_json(cls_name)
            fails = sorted(c['id'] for c in d['conditions'] if c['status'] == 'FAIL')
            self.assertEqual(fails, [cid], (cls_name, [c for c in d['conditions'] if c['status'] != 'PASS']))
            self.assertEqual(status, 1, cls_name)

    def test_the_clean_fixture_passes_every_failable_condition(self):
        status, d = self.run_json('iTermQLeaf')
        for c in d['conditions']:
            self.assertEqual(c['status'], 'MANUAL' if c['id'] == '5c' else 'PASS', c)

    def test_type_only_mentions_count_as_users(self):
        status, d = self.run_json('iTermQTyped')
        c = self.condition(d, '2')
        text = '\n'.join(c['evidence'])
        self.assertIn('4 files', text)
        for i in range(1, 5):
            self.assertIn('sources/TypedUser%d.h' % i, text)
        self.assertIn('text search', text)

    def test_ivar_access_from_outside_counts_and_fails(self):
        status, d = self.run_json('iTermQIvar')
        self.assertIn('sources/IvarUser.m', '\n'.join(self.condition(d, '4g')['evidence']))
        self.assertIn('sources/IvarUser.m', '\n'.join(self.condition(d, '2')['evidence']))

    def test_a_send_to_a_class_that_stores_makes_storage_manual(self):
        status, d = self.run_json('iTermQStoreClient')
        c = self.condition(d, '7')
        self.assertEqual(c['status'], 'MANUAL', c)
        self.assertIn('iTermQStore', '\n'.join(c['evidence']))
        self.assertEqual(status, 0)

    def test_profile_key_macro_fails_storage(self):
        status, d = self.run_json('iTermQProfileKey')
        self.assertIn('KEY_QFIELD3', '\n'.join(self.condition(d, '7')['evidence']))

    def test_sent_to_from_per_frame_code_is_manual(self):
        status, d = self.run_json('iTermQPerFrame')
        c = self.condition(d, '6')
        self.assertEqual(c['status'], 'MANUAL', c)
        self.assertIn('sources/PTYTextViewQ.m', '\n'.join(c['evidence']))
        status, d = self.run_json('iTermQLeaf')
        self.assertIn('PTYTextView', '\n'.join(self.condition(d, '6')['evidence']))

    def test_used_by_a_class_that_per_frame_code_uses_is_manual(self):
        status, d = self.run_json('iTermQDeep')
        c = self.condition(d, '6')
        self.assertEqual(c['status'], 'MANUAL', c)
        text = '\n'.join(c['evidence'])
        self.assertIn('iTermQMid', text)
        self.assertIn('sources/PTYTextViewQ2.m', text)

    def test_a_timer_is_manual(self):
        status, d = self.run_json('iTermQTimer')
        c = self.condition(d, '5b')
        self.assertEqual(c['status'], 'MANUAL', c)
        self.assertIn('schedules work: timer', '\n'.join(c['evidence']))

    def test_objective_c_plus_plus(self):
        status, d = self.run_json('iTermQCxx')
        self.assertEqual(self.statuses(d)['4a'], 'FAIL')

    def test_a_dealloc_that_only_releases_passes(self):
        status, d = self.run_json('iTermQRel')
        self.assertEqual(self.statuses(d)['4c'], 'PASS', self.condition(d, '4c'))

    def test_not_an_objective_c_class(self):
        err = io.StringIO()
        out = io.StringIO()
        with mock.patch('sys.stderr', err):
            status = qu.main(self.args() + ['iTermPanel'], out=out)
        self.assertEqual(status, 2)
        self.assertIn('no Objective-C @implementation', err.getvalue())

    def test_list_prints_the_classes_with_no_failure_sorted_by_size(self):
        status, d = self.run_json('--list')
        names = [c['class'] for c in d['classes']]
        for good in ('iTermQLeaf', 'iTermQShy', 'iTermQShared', 'iTermQRel'):
            self.assertIn(good, names)
        for bad in ('iTermQBusy', 'iTermQHot', 'iTermWidget', 'iTermQSel', 'iTermQCxx'):
            self.assertNotIn(bad, names)
        lines = [c['lines'] for c in d['classes']]
        self.assertEqual(lines, sorted(lines))
        shy = next(c for c in d['classes'] if c['class'] == 'iTermQShy')
        self.assertEqual(shy['manual'], [])
        self.assertEqual(shy['users'], 1)  # counted by the labelled text search
        leaf = next(c for c in d['classes'] if c['class'] == 'iTermQLeaf')
        self.assertEqual(leaf['users'], 1)
        self.assertEqual(d['qualifying'], len(names))
        self.assertGreater(d['considered'], len(names))

    def test_list_agrees_with_the_single_class_answer(self):
        status, d = self.run_json('--list')
        for c in d['classes']:
            s, one = self.run_json(c['class'])
            self.assertEqual(s, 0, c['class'])
            manual = sorted(x['id'] for x in one['conditions'] if x['status'] == 'MANUAL' and x['id'] != '5c')
            self.assertEqual(manual, c['manual'], c['class'])


class StaleUnitTest(unittest.TestCase):
    """A unit whose file changed after the extraction: its database rows may
    be wrong, so a condition decided from them is MANUAL, never PASS."""

    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths = harness.build(edit=write_qualify_files, extra_mains=EXTRA_MAINS,
                                            extra_test_mains=EXTRA_TEST_MAINS)
        for rel in ('sources/Leaf.m', 'ModernTests/iTermQLeafTests.m', 'sources/LeafUser.m'):
            with open(os.path.join(cls.root, rel), 'a') as f:
                f.write('// changed after the extraction\n')

    def test_database_conditions_are_manual_with_the_reason(self):
        p = self.paths
        out = io.StringIO()
        status = qu.main(['--root', self.root, '--db', p.db, '--cdb', p.cdb, '--fragments', p.fragments,
                          '--swift-work', p.swift_work, '--swift-reader', p.swift_reader, '--extractor', p.extractor,
                          '--json', 'iTermQLeaf'], out=out)
        d = json.loads(out.getvalue())
        c = dict((x['id'], x) for x in d['conditions'])
        for cid in ('3c', '3e', '4b', '4c', '4d', '5a', '7'):
            self.assertEqual(c[cid]['status'], 'MANUAL', c[cid])
            self.assertTrue(any('sources/Leaf.m: stale' in e for e in c[cid]['evidence']), c[cid])
        self.assertEqual(c['1']['status'], 'PASS')
        # A stale file that mentions its selectors and properties may hold
        # references the database does not show.
        for cid in ('3e', '3f'):
            self.assertEqual(c[cid]['status'], 'MANUAL', c[cid])
            self.assertTrue(any('sources/LeafUser.m' in e for e in c[cid]['evidence']), c[cid])
            # A stale file of a test target is not an app caller (the census
            # counts tests apart).
            self.assertFalse(any('iTermQLeafTests.m' in e for e in c[cid]['evidence']), c[cid])
        # The unit's own test, stale too, is still not a user.
        # LeafUser.m is stale but still counted, by the database and the text
        # search of its present contents.
        self.assertEqual(c['2']['status'], 'PASS', c['2'])
        self.assertFalse(any('iTermQLeafTests.m names it' in e for e in c['2']['evidence']), c['2'])
        self.assertEqual(status, 0)


if __name__ == '__main__':
    unittest.main()
