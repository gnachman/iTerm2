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

import collections
import io
import json
import os
import shutil
import sys
import tempfile
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


def body_method(sel, lines):
    """A method whose body is lines long, opening brace to closing brace."""
    return '- (int)%s {\n%s    return 0;\n}\n' % (sel, ''.join('    // body line\n' for _ in range(lines - 3)))


# The trivial path (conditions T1 to T8).
# The shape of the category the trivial path was made for: two methods, one
# reached by key-value coding, on a class whose own file is large.
add_class(QUALIFY_FILES, 'iTermQApp', '\n- (int)qappValue;', one_line_method('qappValue', 20))
QUALIFY_FILES['sources/QAppScripting.h'] = ('#import "QApp.h"\n@interface iTermQApp (Scripting)\n'
                                            '- (id)currentScriptingThing;\n@end\n')
QUALIFY_FILES['sources/QAppScripting.m'] = (
    '#import "QAppScripting.h"\n@implementation iTermQApp (Scripting)\n'
    '- (id)valueForUndefinedKey:(NSString *)key {\n    return @[];\n}\n'
    '- (id)currentScriptingThing {\n    return @([self qappValue]);\n}\n@end\n')
# A category whose body has a block, which ARC copies differently.
QUALIFY_FILES['sources/QAppBlocks.m'] = (
    '#import "QApp.h"\n@implementation iTermQApp (Blocks)\n'
    '- (void)qappRun {\n    void (^b)(void) = ^{\n    };\n    b();\n}\n@end\n')
# A category in a file named for its class: part of the class's unit, and
# also classified on its own, since it can move alone.
QUALIFY_FILES['sources/iTermQApp+Extra.m'] = ('#import "QApp.h"\n@implementation iTermQApp (Extra)\n'
                                              '- (int)qappExtra {\n    return 2;\n}\n@end\n')
# A category of an SDK class, a unit of its own.
QUALIFY_FILES['sources/NSString+QExtra.h'] = ('#import <Foundation/Foundation.h>\n@interface NSString (QExtra)\n'
                                              '- (NSString *)qextraTrimmed;\n@end\n')
QUALIFY_FILES['sources/NSString+QExtra.m'] = (
    '#import "NSString+QExtra.h"\n@implementation NSString (QExtra)\n- (NSString *)qextraTrimmed {\n'
    '    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];\n}\n@end\n')
# The boundary at 50 body lines: two methods of 25, then one line more.
add_class(QUALIFY_FILES, 'iTermQFifty', '\n- (int)qfiftyA;\n- (int)qfiftyB;',
          body_method('qfiftyA', 25) + body_method('qfiftyB', 25))
add_class(QUALIFY_FILES, 'iTermQFiftyOne', '\n- (int)qfiftyOneA;\n- (int)qfiftyOneB;',
          body_method('qfiftyOneA', 25) + body_method('qfiftyOneB', 26))
# T2: a static variable that is not const (and one that is, which passes).
add_class(QUALIFY_FILES, 'iTermQStatic', '\n- (int)qstaticNext;',
          '- (int)qstaticNext {\n    return ++gQStaticCount;\n}\n')
QUALIFY_FILES['sources/QStatic.m'] = QUALIFY_FILES['sources/QStatic.m'].replace(
    '@implementation', 'static int gQStaticCount;\nstatic NSString *const kQStaticName = @"q";\n@implementation')
# T4: ownership code without ARC: a retain, a retained-result family, and
# the same block in a file without ARC and in one with it.
add_class(QUALIFY_FILES, 'iTermQRetain', '\n- (id)qretainKeep:(id)x;',
          '- (id)qretainKeep:(id)x {\n    return [x retain];\n}\n')
add_class(QUALIFY_FILES, 'iTermQMaker', '\n- (id)newQMakerThing;',
          '- (id)newQMakerThing {\n    return [[NSObject alloc] init];\n}\n')
BLOCK_BODY = '- (void)qblockRun {\n    void (^b)(void) = ^{\n    };\n    b();\n}\n'
add_class(QUALIFY_FILES, 'iTermQBlock', '\n- (void)qblockRun;', BLOCK_BODY)
add_class(QUALIFY_FILES, 'iTermQBlockArc', '\n- (void)qblockRun;', BLOCK_BODY)
# T6: a C pointer; and an &error out-parameter, which passes.
add_class(QUALIFY_FILES, 'iTermQPointer', '\n- (int)qpointerFirst:(int *)values;',
          '- (int)qpointerFirst:(int *)values {\n    return values[0];\n}\n')
add_class(QUALIFY_FILES, 'iTermQErrorOut', '\n- (NSString *)qerrorOutRead:(NSString *)path;',
          '- (NSString *)qerrorOutRead:(NSString *)path {\n    NSError *error = nil;\n'
          '    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];\n'
          '    return s ?: error.localizedDescription;\n}\n')
# T8: an Objective-C subclass outside the unit.
add_class(QUALIFY_FILES, 'iTermQParent', '\n- (int)qparentValue;', one_line_method('qparentValue', 21))
QUALIFY_FILES['sources/QChild.h'] = '#import "QParent.h"\n@interface iTermQChild : iTermQParent\n@end\n'
QUALIFY_FILES['sources/QChild.m'] = '#import "QChild.h"\n@implementation iTermQChild\n@end\n'
# Named in the sdef: that does not stop the trivial path.
add_class(QUALIFY_FILES, 'iTermQScript', '\n- (int)qscriptValue;', one_line_method('qscriptValue', 22))
# Two classes in one file: the second's storage and -dealloc stop the
# first, since a port moves the whole file.
QUALIFY_FILES['sources/QPair.h'] = ('#import <Foundation/Foundation.h>\n@interface iTermQPairA : NSObject\n'
                                    '- (int)qpairAValue;\n@end\n@interface iTermQPairB : NSObject\n'
                                    '@property (nonatomic) int qpairBCount;\n@end\n')
QUALIFY_FILES['sources/QPair.m'] = ('#import "QPair.h"\n@implementation iTermQPairA\n- (int)qpairAValue {\n'
                                    '    return 1;\n}\n@end\n@implementation iTermQPairB\n- (void)dealloc {\n'
                                    '    [super dealloc];\n}\n@end\n')
# Core Data is stored state: a send to its classes, or a category of an
# entity's class (the fixture's model maps the entity Thing to iTermThingMO).
add_class(QUALIFY_FILES, 'iTermQCoreData', '\n- (id)qcoreDataInsert:(NSManagedObjectContext *)context;',
          '- (id)qcoreDataInsert:(NSManagedObjectContext *)context {\n'
          '    return [NSEntityDescription insertNewObjectForEntityForName:@"Thing" inManagedObjectContext:context];\n'
          '}\n', imports='#import <CoreData/CoreData.h>\n')
QUALIFY_FILES['sources/QThing.h'] = ('#import <Foundation/Foundation.h>\n@interface iTermThingMO : NSObject\n@end\n'
                                     '@interface iTermThingMO (QAdditions)\n- (NSString *)qthingKey;\n@end\n')
QUALIFY_FILES['sources/QThingAdditions.m'] = ('#import "QThing.h"\n@implementation iTermThingMO (QAdditions)\n'
                                              '- (NSString *)qthingKey {\n    return @"k";\n}\n@end\n')
# An associated object set through a macro another header defines: the
# text search of the unit's files cannot see it, Clang's AST can.
QUALIFY_FILES['sources/QSetMacro.h'] = ('#import <objc/runtime.h>\n#define QSET(o, k, v) objc_setAssociatedObject(o, '
                                          'k, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC)\n')
add_class(QUALIFY_FILES, 'iTermQAssocMacro', '\n- (void)qassocMacroSet:(id)v;',
          '- (void)qassocMacroSet:(id)v {\n    QSET(self, @selector(qassocMacroSet:), v);\n}\n',
          imports='#import "QSetMacro.h"\n')
# Core Foundation ownership, which a Swift port cannot promise to
# Objective-C callers, in files compiled with ARC; and a borrowed CGContextRef
# passing through, which is allowed.
CG = '#import <CoreGraphics/CoreGraphics.h>\n'
add_class(QUALIFY_FILES, 'iTermQCFRelease', '\n- (void)qcfFree:(CGColorRef)c;',
          '- (void)qcfFree:(CGColorRef)c {\n    CGColorRelease(c);\n}\n', imports=CG)
add_class(QUALIFY_FILES, 'iTermQCFCreate', '\n- (CGColorRef)qcfColor;',
          '- (CGColorRef)qcfColor {\n    return CGColorCreateGenericRGB(1, 0, 0, 1);\n}\n', imports=CG)
add_class(QUALIFY_FILES, 'iTermQBridgeTransfer', '\n- (id)qbridgeTake:(CFStringRef)s;',
          '- (id)qbridgeTake:(CFStringRef)s {\n    return (__bridge_transfer NSString *)s;\n}\n', imports=CG)
add_class(QUALIFY_FILES, 'iTermQRetainedNew', '\n- (CGImageRef)newQImage;',
          '- (CGImageRef)newQImage CF_RETURNS_RETAINED {\n    return NULL;\n}\n', imports=CG)
add_class(QUALIFY_FILES, 'iTermQBorrowedCtx', '\n- (void)qborrowedDraw:(CGContextRef)ctx;',
          '- (void)qborrowedDraw:(CGContextRef)ctx {\n    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));\n}\n',
          imports=CG)
# Reserved paths (docs/swift-migration/reserved.md): a class under the
# reserved directory, one in a directory whose name only starts the same,
# and a class elsewhere whose CLASS+Something category file is under it.
QUALIFY_FILES['docs/swift-migration/reserved.md'] = (
    '# Reserved\n\n| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n'
    '| `sources/Settings/` | 2026-11-27 | being reworked | when the owner says so |\n'
    '| sources/settings/ | 2026-11-27 | the wrong case, which matches nothing | never |\n')
QUALIFY_FILES['sources/Settings/QReserved.h'] = ('#import <Foundation/Foundation.h>\n@interface iTermQReserved : '
                                                 'NSObject\n- (int)qreservedValue;\n@end\n')
QUALIFY_FILES['sources/Settings/QReserved.m'] = ('#import "QReserved.h"\n@implementation iTermQReserved\n' +
                                                 one_line_method('qreservedValue', 30) + '@end\n')
QUALIFY_FILES['sources/SettingsExtra/QSettingsExtra.h'] = (
    '#import <Foundation/Foundation.h>\n@interface iTermQSettingsExtra : NSObject\n- (int)qsettingsExtraValue;\n'
    '@end\n')
QUALIFY_FILES['sources/SettingsExtra/QSettingsExtra.m'] = (
    '#import "QSettingsExtra.h"\n@implementation iTermQSettingsExtra\n' + one_line_method('qsettingsExtraValue', 31) +
    '@end\n')
add_class(QUALIFY_FILES, 'iTermQOutside', '\n- (int)qoutsideValue;', one_line_method('qoutsideValue', 32))
QUALIFY_FILES['sources/Settings/iTermQOutside+Pane.m'] = (
    '#import "../QOutside.h"\n@implementation iTermQOutside (Pane)\n' + one_line_method('qoutsidePane', 33) +
    '@end\n')
# Two classes in one file outside the reserved directory, the second with a
# CLASS+Something category file under it: a port of either moves the file.
QUALIFY_FILES['sources/QPairR.h'] = ('#import <Foundation/Foundation.h>\n@interface iTermQPairRA : NSObject\n'
                                     '- (int)qpairRAValue;\n@end\n@interface iTermQPairRB : NSObject\n'
                                     '- (int)qpairRBValue;\n@end\n')
QUALIFY_FILES['sources/QPairR.m'] = ('#import "QPairR.h"\n@implementation iTermQPairRA\n' +
                                     one_line_method('qpairRAValue', 34) + '@end\n@implementation iTermQPairRB\n' +
                                     one_line_method('qpairRBValue', 35) + '@end\n')
QUALIFY_FILES['sources/Settings/iTermQPairRB+Pane.m'] = (
    '#import "../QPairR.h"\n@implementation iTermQPairRB (Pane)\n' + one_line_method('qpairRBPane', 36) + '@end\n')
ARC_FILES = ('sources/QBlockArc.m', 'sources/QCFRelease.m', 'sources/QCFCreate.m', 'sources/QBridgeTransfer.m',
             'sources/QRetainedNew.m', 'sources/QBorrowedCtx.m')
SDEF_CLASS = '    <class name="qscript" code="Qscr" plural="qscripts">\n      <cocoa class="iTermQScript"/>\n    </class>\n'

EXTRA_MAINS = tuple(f for f in QUALIFY_FILES if f.endswith(('.m', '.mm')) and f.startswith('sources/') and
                    f != 'sources/ShyUnbuilt.m')
EXTRA_TEST_MAINS = ('ModernTests/iTermQLeafTests.m',)
# Modules keep each file's AST dump small (Foundation is not dumped), as in
# the app's own compile commands; one file is compiled with ARC.
MODULE_CACHE = tempfile.mkdtemp(prefix='qualify-test-modcache-')
EXTRA_ARGS = dict((m, ['-fmodules', '-fmodules-cache-path=' + MODULE_CACHE]) for m in EXTRA_MAINS)
for _m in ARC_FILES:
    EXTRA_ARGS[_m] = EXTRA_ARGS[_m] + ['-fobjc-arc']


def write_qualify_files(root):
    for rel, text in QUALIFY_FILES.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(text)
    sdef = os.path.join(root, 'iTerm2.sdef')
    with open(sdef) as f:
        text = f.read()
    with open(sdef, 'w') as f:
        f.write(text.replace('  </suite>', SDEF_CLASS + '  </suite>'))


def build_fixture():
    return harness.build(edit=write_qualify_files, extra_mains=EXTRA_MAINS, extra_test_mains=EXTRA_TEST_MAINS,
                         extra_args=EXTRA_ARGS)


def tearDownModule():
    harness.cleanup()
    shutil.rmtree(MODULE_CACHE, ignore_errors=True)


class QualifyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths = build_fixture()

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

    def test_a_unit_under_a_reserved_prefix_is_reserved(self):
        status, d = self.run_json('iTermQReserved')
        self.assertEqual(status, qu.EXIT_RESERVED)
        self.assertEqual(d['path'], 'reserved')
        self.assertEqual(d['reserved'], 'sources/Settings/')
        self.assertEqual([c['id'] for c in d['conditions']], list(qu.CONDITION_IDS), 'every condition is reported')
        self.assertEqual([c['id'] for c in d['trivial_conditions']], list(qu.TRIVIAL_CONDITIONS))
        status, text = self.run_text('iTermQReserved')
        self.assertIn('\nPath: reserved (sources/Settings/: not to be ported; docs/swift-migration/reserved.md).\n',
                      text)

    def test_a_unit_in_a_directory_that_only_starts_like_a_reserved_one_is_not_reserved(self):
        status, d = self.run_json('iTermQSettingsExtra')
        self.assertEqual(d['path'], 'trivial', d)
        self.assertIsNone(d['reserved'])
        self.assertEqual(status, 0)

    def test_a_category_file_under_a_reserved_prefix_reserves_the_class_unit_and_the_split_unit(self):
        status, d = self.run_json('iTermQOutside')
        self.assertEqual((d['path'], status), ('reserved', qu.EXIT_RESERVED))
        status, d = self.run_json('iTermQOutside(Pane)')
        self.assertEqual((d['path'], status), ('reserved', qu.EXIT_RESERVED))

    def test_another_class_of_the_file_with_a_category_file_under_a_reserved_prefix_reserves_the_unit(self):
        for name in ('iTermQPairRA', 'iTermQPairRB'):
            status, d = self.run_json(name)
            self.assertEqual((d['path'], d['reserved'], status), ('reserved', 'sources/Settings/', qu.EXIT_RESERVED),
                             name)

    def test_reserved_names_another_table(self):
        other = os.path.join(self.root, 'tmp-other-reserved.md')
        with open(other, 'w') as f:
            f.write('| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n'
                    '| sources/SettingsExtra/ | 2026-11-27 | a test | never |\n')
        try:
            status, d = self.run_json('iTermQSettingsExtra', '--reserved', other)
            self.assertEqual((d['path'], d['reserved'], status), ('reserved', 'sources/SettingsExtra/',
                                                                  qu.EXIT_RESERVED))
            status, d = self.run_json('iTermQReserved', '--reserved', other)
            self.assertEqual(d['path'], 'trivial', d)
            status = qu.main(self.args() + ['iTermQReserved', '--reserved', other + '.absent'], out=io.StringIO())
            self.assertEqual(status, 2)
        finally:
            os.remove(other)

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

    # --- The trivial path.

    def trivial_statuses(self, d):
        return dict((c['id'], c['status']) for c in d['trivial_conditions'])

    def trivial_condition(self, d, tid):
        return next(c for c in d['trivial_conditions'] if c['id'] == tid)

    def test_every_trivial_condition_is_reported(self):
        status, d = self.run_json('iTermQScript')
        self.assertEqual([c['id'] for c in d['trivial_conditions']], list(qu.TRIVIAL_CONDITIONS))
        for c in d['trivial_conditions']:
            self.assertIn(c['status'], ('PASS', 'FAIL', 'MANUAL'))
            self.assertTrue(c['evidence'] and c['how'], c['id'])

    def test_named_in_the_sdef_but_trivial(self):
        status, d = self.run_json('iTermQScript')
        self.assertEqual(self.statuses(d)['3b'], 'FAIL')
        self.assertEqual(set(self.trivial_statuses(d).values()), {'PASS'}, d['trivial_conditions'])
        self.assertEqual(d['path'], 'trivial')
        self.assertEqual(d['body_lines'], 3)
        self.assertEqual(status, 1, 'the exit status still answers the light conditions')
        status, text = self.run_text('iTermQScript')
        self.assertIn('Path: trivial.', text)
        self.assertRegex(text, r'(?m)^PASS +T1 ')

    def test_reflective_names_do_not_stop_the_trivial_path(self):
        for cls_name, cid in (('iTermQXib', '3a'), ('iTermQPlist', '3b'), ('iTermQSel', '3f'),
                              ('iTermQReflect', '3d'), ('iTermQTyped', '2'), ('iTermQBig', '1')):
            status, d = self.run_json(cls_name)
            self.assertEqual(self.statuses(d)[cid], 'FAIL', cls_name)
            self.assertEqual(d['path'], 'trivial', (cls_name, [c for c in d['trivial_conditions']
                                                               if c['status'] != 'PASS']))

    def test_body_lines_not_file_lines(self):
        status, d = self.run_json('iTermQBig')
        self.assertGreater(d['implementation_lines'], 500)
        self.assertEqual(d['body_lines'], 3)

    def test_the_boundary_at_fifty_body_lines(self):
        status, d = self.run_json('iTermQFifty')
        self.assertEqual(d['body_lines'], 50)
        self.assertEqual(self.trivial_statuses(d)['T1'], 'PASS')
        self.assertEqual(d['path'], 'trivial')
        status, d = self.run_json('iTermQFiftyOne')
        self.assertEqual(d['body_lines'], 51)
        self.assertEqual(self.trivial_statuses(d)['T1'], 'FAIL')
        self.assertEqual(d['path'], 'light')

    # Each trivial condition, with a fixture that fails it and no other.
    TRIVIAL_ALONE = [('T1', 'iTermQFiftyOne'), ('T2', 'iTermQStatic'), ('T2', 'iTermQLeaf'), ('T2', 'iTermQIvar'),
                     ('T3', 'iTermQLock'), ('T4', 'iTermQRetain'), ('T4', 'iTermQMaker'), ('T4', 'iTermQBlock'),
                     ('T5', 'iTermQCxx'), ('T6', 'iTermQPointer'), ('T7', 'iTermQLoad'), ('T7', 'iTermQSwizzle'),
                     ('T8', 'iTermQStore'), ('T8', 'iTermQHot'), ('T8', 'iTermQCoder'), ('T8', 'iTermQParent'),
                     ('T8', 'iTermQProfileKey'), ('T8', 'iTermQCoreData')]

    def test_every_trivial_condition_fails_alone_on_its_fixture(self):
        self.assertEqual(sorted(set(t for t, _ in self.TRIVIAL_ALONE)), sorted(qu.TRIVIAL_CONDITIONS))
        for tid, cls_name in self.TRIVIAL_ALONE:
            status, d = self.run_json(cls_name)
            bad = sorted(c['id'] for c in d['trivial_conditions'] if c['status'] != 'PASS')
            self.assertEqual(bad, [tid], (cls_name, [c for c in d['trivial_conditions'] if c['status'] != 'PASS']))
            self.assertEqual(self.trivial_statuses(d)[tid], 'FAIL', cls_name)
            self.assertNotEqual(d['path'], 'trivial', cls_name)

    def test_a_manual_condition_is_never_trivial(self):
        for cls_name, tid in (('iTermQStoreClient', 'T8'), ('iTermQPerFrame', 'T8'), ('iTermQTimer', 'T3')):
            status, d = self.run_json(cls_name)
            self.assertEqual(self.trivial_statuses(d)[tid], 'MANUAL', (cls_name, self.trivial_condition(d, tid)))
            self.assertNotEqual(d['path'], 'trivial', cls_name)

    def test_the_trivial_evidence_names_what_stops_it(self):
        status, d = self.run_json('iTermQStatic')
        text = '\n'.join(self.trivial_condition(d, 'T2')['evidence'])
        self.assertIn('gQStaticCount', text)
        self.assertNotIn('kQStaticName', text, 'a const static is not state')
        status, d = self.run_json('iTermQRetain')
        self.assertIn('sends retain', '\n'.join(self.trivial_condition(d, 'T4')['evidence']))
        status, d = self.run_json('iTermQPointer')
        self.assertIn('a C pointer (int *)', '\n'.join(self.trivial_condition(d, 'T6')['evidence']))
        status, d = self.run_json('iTermQParent')
        self.assertIn('iTermQChild', '\n'.join(self.trivial_condition(d, 'T8')['evidence']))

    def test_arc_makes_a_block_harmless(self):
        status, d = self.run_json('iTermQBlockArc')
        self.assertEqual(self.trivial_statuses(d)['T4'], 'PASS', self.trivial_condition(d, 'T4'))
        self.assertIn('compiled with ARC', '\n'.join(self.trivial_condition(d, 'T4')['evidence']))
        self.assertEqual(d['path'], 'trivial')

    def test_without_arc_nothing_ownership_related_folds_the_arc_step(self):
        status, d = self.run_json('iTermQScript')
        self.assertIn('the port is the move to ARC', '\n'.join(self.trivial_condition(d, 'T4')['evidence']))

    def test_an_error_out_parameter_is_not_an_unsafe_pointer(self):
        status, d = self.run_json('iTermQErrorOut')
        self.assertEqual(self.trivial_statuses(d)['T6'], 'PASS', self.trivial_condition(d, 'T6'))
        self.assertEqual(d['path'], 'trivial')

    def test_the_scripting_category_shape_is_trivial(self):
        status, d = self.run_json('iTermQApp(Scripting)')
        self.assertEqual(d['unit_files'], ['sources/QAppScripting.h', 'sources/QAppScripting.m'])
        self.assertEqual(d['path'], 'trivial', [c for c in d['trivial_conditions'] if c['status'] != 'PASS'])
        self.assertEqual(d['body_lines'], 6)
        self.assertEqual(d['conditions'], [], 'the light conditions are not evaluated for a category')
        self.assertEqual(status, 0)
        status, text = self.run_text('iTermQApp(Scripting)')
        self.assertIn('not evaluated for a category unit', text)

    def test_a_category_that_is_not_trivial_takes_the_full_path(self):
        status, d = self.run_json('iTermQApp(Blocks)')
        self.assertEqual(self.trivial_statuses(d)['T4'], 'FAIL')
        self.assertEqual(d['path'], 'full')
        self.assertEqual(status, 1)

    def test_a_category_of_a_core_data_entity_is_not_trivial(self):
        status, d = self.run_json('iTermThingMO(QAdditions)')
        c = self.trivial_condition(d, 'T8')
        self.assertEqual(c['status'], 'FAIL', c)
        self.assertIn('Core Data entity', '\n'.join(c['evidence']))
        self.assertEqual(d['path'], 'full')

    def test_an_associated_object_through_a_macro_is_seen(self):
        status, d = self.run_json('iTermQAssocMacro')
        c = self.trivial_condition(d, 'T7')
        self.assertEqual(c['status'], 'FAIL', c)
        self.assertIn('objc_setAssociatedObject', '\n'.join(c['evidence']))
        self.assertNotEqual(d['path'], 'trivial')

    def test_core_foundation_ownership_is_not_trivial_even_with_arc(self):
        for cls_name, what in (('iTermQCFRelease', 'CGColorRelease'), ('iTermQCFCreate', 'CGColorCreateGenericRGB'),
                               ('iTermQBridgeTransfer', '__bridge_transfer'), ('iTermQRetainedNew', 'retained')):
            status, d = self.run_json(cls_name)
            c = self.trivial_condition(d, 'T4')
            self.assertEqual(c['status'], 'FAIL', (cls_name, c))
            self.assertIn(what, '\n'.join(c['evidence']), cls_name)
            self.assertNotEqual(d['path'], 'trivial', cls_name)

    def test_a_borrowed_core_graphics_value_passing_through_is_trivial(self):
        status, d = self.run_json('iTermQBorrowedCtx')
        self.assertEqual(d['path'], 'trivial', [c for c in d['trivial_conditions'] if c['status'] != 'PASS'])

    def test_every_class_of_the_file_counts(self):
        status, d = self.run_json('iTermQPairA')
        st = self.trivial_statuses(d)
        self.assertEqual(st['T2'], 'FAIL', self.trivial_condition(d, 'T2'))
        self.assertIn('qpairBCount', '\n'.join(self.trivial_condition(d, 'T2')['evidence']))
        self.assertEqual(st['T7'], 'FAIL', self.trivial_condition(d, 'T7'))
        self.assertNotEqual(d['path'], 'trivial')

    def test_classify(self):
        status, d = self.run_json('--classify')
        self.assertEqual(status, 0)
        by = dict((u['unit'], u) for u in d['classified'])
        for name in ('iTermQScript', 'iTermQXib', 'iTermQFifty', 'iTermQErrorOut', 'NSString(QExtra)',
                     'iTermQApp(Scripting)'):
            self.assertEqual(by[name]['path'], 'trivial', by[name])
        for name in ('iTermQFiftyOne', 'iTermQRel'):
            self.assertEqual(by[name]['path'], 'light', by[name])
        for name in ('iTermQBusy', 'iTermQApp(Blocks)', 'iTermQCxx'):
            self.assertEqual(by[name]['path'], 'full', by[name])
        self.assertEqual(by['iTermQFiftyOne']['not_trivial_because'], ['T1'])
        self.assertEqual(sum(d['counts'].values()), d['units'])
        self.assertEqual(by['iTermQApp(Extra)']['part_of'], 'iTermQApp')
        self.assertEqual(by['iTermQApp(Extra)']['path'], 'trivial')
        self.assertIsNone(by['iTermQApp']['part_of'])
        self.assertEqual(sum(d['split_counts'].values()),
                         sum(1 for u in d['classified'] if u['part_of']))
        self.assertEqual(d['units'], sum(1 for u in d['classified'] if not u['part_of']))
        pair = [u for u in d['classified'] if 'iTermQPairA' in u['classes'] or 'iTermQPairB' in u['classes']]
        self.assertEqual(len(pair), 1, 'one unit per implementation file')
        self.assertEqual(pair[0]['classes'], ['iTermQPairA', 'iTermQPairB'])
        trivial = [u['body_lines'] for u in d['classified'] if u['path'] == 'trivial']
        self.assertEqual(trivial, sorted(trivial))
        status, text = self.run_text('--classify')
        self.assertRegex(text, r'trivial \d+, light \d+, full \d+, reserved \d+')
        for name in ('iTermQReserved', 'iTermQOutside', 'iTermQOutside(Pane)'):
            self.assertEqual((by[name]['path'], by[name]['reserved']), ('reserved', 'sources/Settings/'), by[name])
        self.assertEqual(by['iTermQOutside(Pane)']['part_of'], 'iTermQOutside')
        self.assertEqual(by['iTermQSettingsExtra']['path'], 'trivial', by['iTermQSettingsExtra'])
        self.assertIsNone(by['iTermQSettingsExtra']['reserved'])
        self.assertEqual(d['counts']['reserved'], sum(1 for u in d['classified']
                                                      if u['path'] == 'reserved' and not u['part_of']))
        self.assertEqual(d['split_counts']['reserved'], sum(1 for u in d['classified']
                                                            if u['path'] == 'reserved' and u['part_of']))
        self.assertIn('iTermQPairRB(Pane)', [u['unit'] for u in d['classified'] if u['path'] == 'reserved'])
        pair = next(u for u in d['classified'] if 'iTermQPairRA' in u['classes'])
        self.assertEqual(pair['classes'], ['iTermQPairRA', 'iTermQPairRB'])
        self.assertEqual((pair['path'], pair['reserved']), ('reserved', 'sources/Settings/'), pair)
        self.assertEqual(d['reserved_unmatched'], ['sources/settings/'])
        self.assertIn('WARN: the reserved prefix sources/settings/', text)

    def test_list_puts_the_reserved_classes_apart(self):
        status, d = self.run_json('--list')
        listed = [c['class'] for c in d['classes']]
        self.assertNotIn('iTermQReserved', listed)
        self.assertIn('iTermQSettingsExtra', listed)
        reserved = dict((c['class'], c['reserved']) for c in d['reserved_classes'])
        self.assertEqual(reserved.get('iTermQReserved'), 'sources/Settings/')
        self.assertEqual(d['reserved'], len(d['reserved_classes']))

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
        cls.root, cls.paths = build_fixture()
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


class IncompletenessTest(unittest.TestCase):
    """The incomplete lines are given whole (database_incomplete, as before)
    and split into the database's own rows, which a database refresh makes
    current, and the registry and resource files, which it cannot."""

    def test_the_database_lines_are_kept_apart_from_the_registry_and_resource_lines(self):
        class Resources:
            problems = [('sources/X.xib', 'cannot be read')]

        class Census:
            resources = Resources()

            def objc_incomplete(self):
                return ['INCOMPLETE: 3 of 10 units are not current']

            def swift_incomplete(self):
                return ['INCOMPLETE: 1 of 11 Swift modules are not current']

            def registry_incomplete(self):
                return ['INCOMPLETE: 2 dynamic reflective call sites are not in the registry']

        d = qu.incompleteness(Census())
        rows = ['INCOMPLETE: 3 of 10 units are not current', 'INCOMPLETE: 1 of 11 Swift modules are not current']
        other = ['INCOMPLETE: 2 dynamic reflective call sites are not in the registry',
                 'INCOMPLETE: sources/X.xib: cannot be read']
        self.assertEqual(list(d.keys()),
                         ['database_incomplete', 'database_rows_incomplete', 'registry_or_resources_incomplete'])
        self.assertEqual(d['database_incomplete'], rows + other)
        self.assertEqual(d['database_rows_incomplete'], rows)
        self.assertEqual(d['registry_or_resources_incomplete'], other)
        self.assertEqual(qu.database_incomplete(Census()), rows + other)


RESERVED_DOC = ('# Reserved paths\n\nSome words.\n\n'
                '| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n'
                '| `sources/Settings/` | 2026-11-27 | being reworked | when the owner says so |\n'
                '| sources/Other | 2026-11-27 | a second row | never |\n\nMore words after the table.\n')


class ReservedPathTest(unittest.TestCase):
    """docs/swift-migration/reserved.md: a unit whose implementation file is
    under a reserved path prefix takes no path at all. These tests need no
    code database: they drive the reading of the table, the prefix match,
    the path and exit status, the counts and the text forms directly."""

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='qualify-reserved-test-')

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, text, name='reserved.md'):
        path = os.path.join(self.dir, name)
        with open(path, 'w') as f:
            f.write(text)
        return path

    def test_the_table_gives_the_prefixes(self):
        self.assertEqual(qu.read_reserved(self.write(RESERVED_DOC)), ['sources/Settings/', 'sources/Other'])

    def test_a_table_with_no_rows_reserves_nothing(self):
        path = self.write('# Reserved\n\n| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n')
        self.assertEqual(qu.read_reserved(path), [])

    def test_a_missing_default_file_reserves_nothing(self):
        self.assertEqual(qu.read_reserved(os.path.join(self.dir, 'absent.md')), [])

    def test_a_missing_file_named_on_the_command_line_is_an_error(self):
        with self.assertRaises(qu.QualifyError):
            qu.read_reserved(os.path.join(self.dir, 'absent.md'), required=True)

    def test_a_malformed_table_is_an_error(self):
        header = '| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n'
        for bad in ('# Reserved\n\nNo table at all.\n',
                    header + '| sources/Settings/ | 2026-11-27 | too few cells |\n',
                    header + '|  | 2026-11-27 | no prefix | never |\n',
                    header + '| /sources/Settings/ | 2026-11-27 | absolute | never |\n',
                    header + '| sources/../Settings/ | 2026-11-27 | climbs out | never |\n',
                    header + '| sources/Settings/ | yesterday | not a date | never |\n',
                    '| Path prefix | Date | Reason | Ends |\n| sources/Settings/ | 2026-11-27 | no rule | never |\n'):
            with self.assertRaises(qu.QualifyError, msg=bad):
                qu.read_reserved(self.write(bad))

    def test_a_row_after_a_blank_line_in_the_table_is_an_error(self):
        path = self.write('| Path prefix | Date | Reason | Ends |\n|---|---|---|---|\n'
                          '| sources/Settings/ | 2026-11-27 | first | never |\n\n'
                          '| sources/Other/ | 2026-11-27 | dropped by the blank line | never |\n')
        with self.assertRaisesRegex(qu.QualifyError, r'reserved\.md:5:'):
            qu.read_reserved(path)

    def test_a_prefix_that_matches_no_file_is_reported(self):
        files = ['sources/Settings/Pane.m', 'sources/Leaf.m']
        self.assertEqual(qu.unmatched_prefixes(files, ['sources/Settings/', 'sources/settings/', 'sources/Gone']),
                         ['sources/settings/', 'sources/Gone'])
        self.assertEqual(qu.unmatched_prefixes(files, []), [])

    def test_the_classify_text_warns_about_a_prefix_that_matches_nothing(self):
        d = self.classify_doc()
        d['reserved_unmatched'] = ['sources/settings/']
        out = io.StringIO()
        qu.write_classify(d, out)
        self.assertIn('\nWARN: the reserved prefix sources/settings/ in docs/swift-migration/reserved.md matches no '
                      'implementation file', out.getvalue())
        out = io.StringIO()
        qu.write_classify(self.classify_doc(), out)
        self.assertNotIn('WARN', out.getvalue())

    def test_the_exit_status_is_documented(self):
        self.assertIn('%d when the unit is reserved' % qu.EXIT_RESERVED, qu.__doc__)

    def test_a_unit_under_a_reserved_prefix_is_reserved(self):
        prefixes = ['sources/Settings/']
        self.assertEqual(qu.reserved_prefix(['sources/Settings/iTermSplitViewAnimation.m'], prefixes),
                         'sources/Settings/')
        self.assertEqual(qu.reserved_prefix(['sources/Settings/Deeper/Pane.m'], prefixes), 'sources/Settings/')

    def test_a_unit_elsewhere_is_not_reserved(self):
        self.assertIsNone(qu.reserved_prefix(['sources/Leaf.m'], ['sources/Settings/']))
        self.assertIsNone(qu.reserved_prefix(['sources/Leaf.m'], []))

    def test_prefixes_match_whole_path_components(self):
        for prefix in ('sources/Settings/', 'sources/Settings'):
            self.assertIsNone(qu.reserved_prefix(['sources/SettingsExtra/Foo.m'], [prefix]), prefix)
            self.assertIsNone(qu.reserved_prefix(['sources/SettingsFoo.m'], [prefix]), prefix)
            self.assertEqual(qu.reserved_prefix(['sources/Settings/Foo.m'], [prefix]), prefix)

    def test_any_implementation_file_of_the_unit_reserves_it(self):
        # A class unit includes its CLASS+Something category files.
        self.assertEqual(qu.reserved_prefix(['sources/Foo.m', 'sources/Settings/Foo+Pane.m'], ['sources/Settings/']),
                         'sources/Settings/')

    def test_the_reserved_path_and_its_exit_status(self):
        passing = [qu.Condition('T1', 'PASS', [], 'how')]
        failing = [qu.Condition('T1', 'FAIL', [], 'how')]
        self.assertEqual(qu.path_and_status(passing, False, None, None), ('trivial', 0))
        self.assertEqual(qu.path_and_status(failing, False, None, None), ('light', 0))
        self.assertEqual(qu.path_and_status(failing, True, None, None), ('full', 1))
        self.assertEqual(qu.path_and_status(passing, False, 'Cat', None), ('trivial', 0))
        self.assertEqual(qu.path_and_status(failing, False, 'Cat', None), ('full', 1))
        for trivial, fails, category in ((passing, False, None), (failing, True, None), (passing, False, 'Cat')):
            self.assertEqual(qu.path_and_status(trivial, fails, category, 'sources/Settings/'),
                             ('reserved', qu.EXIT_RESERVED))
        self.assertNotIn(qu.EXIT_RESERVED, (0, 1, 2, 3, 4, 5, 6))

    def test_the_classify_counts(self):
        units = [{'path': 'trivial'}, {'path': 'light'}, {'path': 'reserved'}, {'path': 'reserved'},
                 {'path': 'full'}]
        counts = qu.path_counts(units)
        self.assertEqual(list(counts.items()), [('trivial', 1), ('light', 1), ('full', 1), ('reserved', 2)])

    def single(self, path, reserved):
        cond = collections.OrderedDict([('id', 'T1'), ('condition', 'c'), ('status', 'PASS'), ('evidence', []),
                                        ('how', 'h')])
        return collections.OrderedDict([
            ('class', 'iTermQReserved'), ('unit_files', ['sources/Settings/QReserved.m']),
            ('implementation_lines', 5), ('body_lines', 3), ('path', path), ('reserved', reserved),
            ('database_incomplete', []), ('conditions', []), ('trivial_conditions', [cond]),
            ('exit_status', qu.EXIT_RESERVED if reserved else 0)])

    def test_the_single_unit_text_names_the_prefix_in_place_of_the_path(self):
        out = io.StringIO()
        qu.write_text(self.single('reserved', 'sources/Settings/'), out)
        text = out.getvalue()
        self.assertIn('\nPath: reserved (sources/Settings/: not to be ported; docs/swift-migration/reserved.md).\n',
                      text)
        self.assertNotIn('Path: trivial', text)
        self.assertIn('PASS    T1', text, 'every condition is still printed')
        self.assertIn('Exit %d.' % qu.EXIT_RESERVED, text)
        out = io.StringIO()
        qu.write_text(self.single('trivial', None), out)
        self.assertIn('\nPath: trivial.\n', out.getvalue())

    def classify_doc(self):
        unit = collections.OrderedDict([('unit', 'iTermQReserved'), ('classes', ['iTermQReserved']),
                                        ('file', 'sources/Settings/QReserved.m'), ('path', 'reserved'),
                                        ('reserved', 'sources/Settings/'), ('part_of', None), ('body_lines', None),
                                        ('implementation_lines', 5), ('not_trivial_because', []),
                                        ('stop_status', None)])
        return collections.OrderedDict([
            ('units', 1), ('counts', qu.path_counts([unit])), ('split_counts', qu.path_counts([])),
            ('database_incomplete', []), ('reserved_unmatched', []), ('classified', [unit]), ('exit_status', 0)])

    def test_the_classify_text_counts_and_lists_the_reserved_units(self):
        out = io.StringIO()
        qu.write_classify(self.classify_doc(), out)
        text = out.getvalue()
        self.assertRegex(text, r'trivial 0, light 0, full 0, reserved 1')
        row = next(line for line in text.split('\n') if line.startswith('reserved '))
        header = next(line for line in text.split('\n') if line.startswith('path '))
        self.assertRegex(row, r'^reserved +- +5  iTermQReserved +-     sources/Settings/QReserved.m  '
                              r'\(reserved: sources/Settings/\)$')
        self.assertEqual(row.index('sources/Settings/QReserved.m'), header.index('file'), 'columns stay aligned')

    def test_the_classify_text_of_a_document_without_reserved_counts(self):
        d = self.classify_doc()
        d['counts'] = collections.OrderedDict([('trivial', 0), ('light', 0), ('full', 0)])
        d['split_counts'] = collections.OrderedDict([('trivial', 0), ('light', 0), ('full', 0)])
        for u in d['classified']:
            u['path'] = 'light'
            del u['reserved']
        out = io.StringIO()
        qu.write_classify(d, out)
        self.assertIn('trivial 0, light 0, full 0\n', out.getvalue())

    def test_the_list_text_shows_the_reserved_classes_apart(self):
        d = collections.OrderedDict([
            ('considered', 2), ('qualifying', 1), ('reserved', 1), ('database_incomplete', []),
            ('classes', [collections.OrderedDict([('class', 'iTermQLeaf'), ('file', 'sources/Leaf.m'), ('lines', 6),
                                                  ('users', 1), ('manual', [])])]),
            ('reserved_classes', [collections.OrderedDict([('class', 'iTermQReserved'),
                                                           ('file', 'sources/Settings/QReserved.m'),
                                                           ('reserved', 'sources/Settings/')])]),
            ('exit_status', 0)])
        out = io.StringIO()
        qu.write_list(d, out)
        text = out.getvalue()
        table, _, after = text.partition('Reserved')
        self.assertIn('iTermQLeaf', table)
        self.assertNotIn('iTermQReserved', table)
        self.assertIn('iTermQReserved', after)
        self.assertIn('sources/Settings/', after)


if __name__ == '__main__':
    unittest.main()
