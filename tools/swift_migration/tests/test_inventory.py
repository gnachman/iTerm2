"""Tests for tools/swift_migration/inventory.py: the summary, files, file, history and leaf subcommands.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The tool, and the test library once loaded, write no bytecode cache. Python
caches each test module itself as unittest imports it, before any code in it
runs, so without -B (or PYTHONDONTWRITEBYTECODE) a tests/__pycache__ appears.

Most tests use small fixture strings or the fixture tree in
fixtures/minirepo, which is copied to a temporary directory and made into a
git repository so that the results never depend on the real sources/. Two
smoke tests at the end run the script on the real tree and check only that
the output is non-empty and well formed.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import OrderedDict

from inventory_testlib import (FIXTURE, IVAR_SOURCE, REPO_ROOT, TEMP_DIRS, TOOL_DIR, MiniRepo, ScopeOverlayRepo,
                               add_scope_overlay, inv, make_repo, run_cli, run_main)


def tearDownModule():
    ScopeOverlayRepo.cleanup()
    MiniRepo.cleanup()


class ScopeTests(unittest.TestCase):
    def test_exclusion_reasons(self):
        self.assertEqual(inv.exclusion_reason('submodules/NMSSH/foo.m'), 'submodule')
        self.assertEqual(inv.exclusion_reason('submodules'), 'submodule')
        self.assertEqual(inv.exclusion_reason('sources/proto/Api.pbobjc.m'), 'generated (protobuf)')
        self.assertEqual(inv.exclusion_reason('sources/CoreDataGeneratedFiles/X.m'), 'generated (Core Data)')
        self.assertEqual(inv.exclusion_reason('sources/Other/X+CoreDataProperties.m'), 'generated (Core Data)')
        self.assertIsNotNone(inv.exclusion_reason('ThirdParty/LetsMove/PFMoveApplication.m'))
        self.assertIsNotNone(inv.exclusion_reason('ModernTests/FooTests.swift'))
        self.assertIsNone(inv.exclusion_reason('sources/PTYSession/PTYSession.m'))
        self.assertIsNone(inv.exclusion_reason('ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m'))

    def test_minirepo_file_set(self):
        i = MiniRepo.inventory()
        self.assertIn('sources/Foo.m', i.impl_files)
        self.assertIn('ThirdParty/PSMTabBarControl/source/PSMThing.m', i.impl_files)
        for p in i.impl_files + i.headers + i.swift_files:
            self.assertIsNone(inv.exclusion_reason(p), p)
        self.assertNotIn('sources/proto/Gen.pbobjc.m', i.impl_files)
        self.assertNotIn('sources/CoreDataGeneratedFiles/Thing+CoreDataProperties.m', i.impl_files)
        self.assertNotIn('ThirdParty/Other/Other.m', i.impl_files)
        self.assertNotIn('sources/vendored', i.impl_files + i.headers)
        self.assertEqual(i.excluded.get('submodule'), 1)
        self.assertEqual(i.excluded.get('generated (protobuf)'), 1)
        self.assertEqual(i.excluded.get('generated (Core Data)'), 1)


class MaskingTests(unittest.TestCase):
    def test_comments_and_strings_blanked_with_same_length(self):
        src = 'a = @"x // y"; // [b release]\n/* [c retain] */ d;\nchar q = \'"\';\n'
        masked = inv.mask_source(src)
        self.assertEqual(len(masked), len(src))
        self.assertEqual(masked.count('\n'), src.count('\n'))
        self.assertNotIn('release', masked)
        self.assertNotIn('retain', masked)
        self.assertIn('@"', masked)
        self.assertIn('d;', masked)

    def test_rr_sites(self):
        src = ('[x retain]; [y release]; [[[Foo alloc] init] autorelease];\n'
               '[super dealloc]; // [z release]\n- (oneway void)release { }\n'
               'NSLog(@"[a retain]");\n')
        self.assertEqual(inv.rr_sites(inv.mask_source(src)), (3, 1))

    def test_rr_sites_count_only_message_sends(self):
        # A variable named release passed as an argument (PTYMouseHandler.m) is not a site, nor is
        # one used as a subscript or array element.
        src = ('[self reportMouseEvent:release];\n[self reportMouseEvent: release ];\n'
               'x[release]; y = @[release]; z = @[a, release];\n'
               '[@"s" retain]; [array[0] release]; [(id)p autorelease]; [[x retain] release];\n'
               '[x\n    release];\n')
        self.assertEqual(inv.rr_sites(inv.mask_source(src)), (6, 0))


class PbxprojTests(unittest.TestCase):
    def membership(self):
        with open(os.path.join(FIXTURE, 'iTerm2.xcodeproj', 'project.pbxproj'), encoding='utf-8') as f:
            text = f.read()
        membership, targets, synchronized = inv.compute_target_membership(inv.parse_pbxproj(text))
        self.assertEqual(synchronized, ['ModernTests'])
        return membership, targets

    def test_parse_values(self):
        plist = inv.parse_pbxproj('// !$*UTF8*$!\n{ a = 1; b = ( "x y", z ); c = { d = "q\\"r"; }; }')
        self.assertEqual(plist['a'], '1')
        self.assertEqual(plist['b'], ['x y', 'z'])
        self.assertEqual(plist['c']['d'], 'q"r')

    def test_targets_and_arc(self):
        membership, targets = self.membership()
        self.assertIs(targets['iTerm2Shared']['arc'], False)
        self.assertIs(targets['iTerm2SharedARC']['arc'], True)
        self.assertEqual(membership['sources/Foo.m'][0]['target'], 'iTerm2Shared')
        self.assertIs(membership['sources/Foo.m'][0]['arc'], False)
        self.assertFalse(membership['sources/Foo.m'][0]['file_flag'])
        self.assertEqual(membership['sources/Bar.m'][0]['arc'], True)
        # Per-file -fobjc-arc in a non-ARC target.
        self.assertIs(membership['sources/FooSub.m'][0]['arc'], True)
        self.assertTrue(membership['sources/FooSub.m'][0]['file_flag'])
        self.assertEqual(membership['sources/FooSub.m'][0]['arc_source'], 'per-file COMPILER_FLAGS')
        # Path given relative to a group with a subdirectory, and SOURCE_ROOT.
        self.assertIn('sources/VT100/Hot.mm', membership)
        self.assertIn('sources/Util.c', membership)
        self.assertIn('ThirdParty/PSMTabBarControl/source/PSMThing.m', membership)

    def test_arc_state(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.arc_state('sources/Foo.m'), 'non-ARC')
        self.assertEqual(i.arc_state('sources/Bar.m'), 'ARC')
        self.assertEqual(i.arc_state('sources/FooSub.m'), 'ARC')
        self.assertEqual(i.arc_state('sources/Util.c'), 'n/a (C)')
        self.assertEqual(i.arc_state('sources/Lonely.m'), 'not compiled')

    def test_textually_included_file_inherits_arc(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.included_by('sources/Included.m'), ['sources/Foo.m'])
        self.assertEqual(i.arc_state('sources/Included.m'), 'non-ARC')
        rec = i.file_record('sources/Included.m')
        self.assertEqual(rec['targets'][0]['included_via'], 'sources/Foo.m')
        self.assertIn('inherited from sources/Foo.m', rec['targets'][0]['arc_source'])
        s = i.summary()
        self.assertIn('sources/Included.m', s['textually_included_implementation_files'])
        self.assertNotIn('sources/Included.m', s['not_compiled_by_any_target'])

    def test_mixed_configurations(self):
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = a.m; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = X; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1, C2 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( ); }; '
            'C1 = { isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_OBJC_ARC = YES; }; }; '
            'C2 = { isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_OBJC_ARC = NO; }; }; '
            '}; rootObject = P; }')
        membership, targets, _ = inv.compute_target_membership(plist)
        self.assertEqual(targets['X']['arc'], 'mixed')
        self.assertEqual(membership['a.m'][0]['arc'], 'mixed')

    def test_unset_arc_defaults_to_no_and_says_so(self):
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = main.m; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = X; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( ); }; '
            'C1 = { isa = XCBuildConfiguration; buildSettings = { }; }; '
            '}; rootObject = P; }')
        membership, targets, _ = inv.compute_target_membership(plist)
        self.assertIs(targets['X']['arc'], False)
        self.assertIn('default is NO', membership['main.m'][0]['arc_source'])




class StructureTests(unittest.TestCase):
    def setUp(self):
        self.of = inv.ObjCFile('Thing.m', IVAR_SOURCE)

    def test_ivars_from_three_places(self):
        by_name = {iv['name']: iv for iv in self.of.ivars}
        self.assertEqual(by_name['_inHeaderInterface']['declared'], '@interface in the .m')
        self.assertEqual(by_name['_inExtension']['declared'], 'class extension in the .m')
        self.assertEqual(by_name['_second']['declared'], 'class extension in the .m')
        self.assertEqual(by_name['_second']['type'], 'NSString *')
        self.assertEqual(by_name['_buf']['declared'], 'implementation block')
        self.assertEqual(by_name['_buf']['array'], '[8]')
        self.assertEqual(by_name['_handler']['kind'], 'block')
        self.assertEqual(by_name['_bit']['bitfield'], '1')
        self.assertTrue(all(iv['class'] == 'Thing' for iv in self.of.ivars))

    def test_header_ivar_location(self):
        of = inv.ObjCFile('Thing.h', '@interface Thing : NSObject {\n    int _a;\n}\n@end\n'
                                     '@interface Thing () {\n    int _b;\n}\n@end\n')
        locations = {iv['name']: iv['declared'] for iv in of.ivars}
        self.assertEqual(locations, {'_a': 'header @interface', '_b': 'class extension in a header'})

    def test_statics(self):
        statics = {s['name']: s for s in self.of.statics}
        self.assertEqual(statics['sShared']['kind'], 'variable')
        self.assertEqual(statics['kName']['kind'], 'variable')
        self.assertEqual(statics['kTable']['kind'], 'variable')
        self.assertEqual(statics['Helper']['kind'], 'function')
        self.assertEqual(len(statics['Helper']['lines']), 2)  # prototype and definition
        self.assertEqual(statics['Inline']['kind'], 'function')  # NS_INLINE is static inline
        self.assertNotIn('Thing', statics)

    def test_methods_and_functions(self):
        selectors = [m['selector'] for m in self.of.methods]
        self.assertEqual(selectors, ['custom', 'work:'])
        self.assertEqual(sorted(f['name'] for f in self.of.functions), ['Helper', 'Inline'])

    def test_selector_extraction(self):
        self.assertEqual(inv.method_selector('- (void)foo:(int)a bar:(NSString *)b'), 'foo:bar:')
        self.assertEqual(inv.method_selector('+ (instancetype)shared NS_SWIFT_NAME(shared())'), 'shared')
        self.assertEqual(inv.method_selector('- (void)run:(void (^)(BOOL x))block'), 'run:')



class HazardTests(unittest.TestCase):
    def test_text_hazards(self):
        src = '''
+ (void)load { }
- (void)forwardInvocation:(NSInvocation *)inv { }
- (void)f {
    [self performSelector:@selector(x) withObject:nil afterDelay:0];
    [a makeObjectsPerformSelector:@selector(y)];
    SEL s = NSSelectorFromString(name);
    NSLog(@"%@", NSStringFromSelector(@selector(z)));
    NSLog(@"%@", NSStringFromSelector(_cmd));
    NSString *n = NSStringFromSelector(sel);
    Class c = NSClassFromString(@"Foo");
    class_addMethod(c, s, imp, "v@:");
    objc_setAssociatedObject(self, k, v, 0);
    [self respondsToSelector:s];
    @synchronized (self) { }
    @try { } @catch (id e) { }
    _Atomic int q;
    // performSelector: in a comment
    NSLog(@"NSClassFromString( in a string");
}
'''
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual(h['performSelector'], 1)
        self.assertEqual(h['makeObjectsPerformSelector'], 1)
        self.assertEqual(h['NSSelectorFromString'], 1)
        self.assertEqual(h['NSStringFromSelector(_cmd)'], 1)
        self.assertEqual(h['NSStringFromSelector(variable)'], 1)
        self.assertEqual(h['NSClassFromString'], 1)
        self.assertEqual(h['method replacement'], 1)
        self.assertEqual(h['forwarding'], 1)
        self.assertEqual(h['associated objects'], 1)
        self.assertEqual(h['respondsToSelector'], 1)
        self.assertEqual(h['@synchronized'], 1)
        self.assertEqual(h['@try'], 1)
        self.assertEqual(h['+load/+initialize'], 1)
        self.assertEqual(h['atomics'], 1)

    def test_macros(self):
        src = ('#define DEF(n) - (int)n { return 1; }\n'
               '#define DEF2(n) \\\n    + (BOOL)n { \\\n    return YES; }\n'
               '#define CAT(a, b) a##b\n'
               '#define LOG(f, ...) NSLog(f, ##__VA_ARGS__)\n'
               '#define SUB(a) (a - (int)b)\n'
               '#define STORE(n) static int s_##n\n')
        macros = dict((m['name'], m) for m in inv.parse_macros(inv.mask_source(src)))
        self.assertTrue(macros['DEF']['defines_method'])
        self.assertTrue(macros['DEF2']['defines_method'])
        self.assertTrue(macros['CAT']['token_pasting'])
        self.assertFalse(macros['LOG']['token_pasting'])
        self.assertFalse(macros['SUB']['defines_method'])
        self.assertTrue(macros['STORE']['declares_static'])

    def test_file_level_flags(self):
        rec = MiniRepo.inventory().file_record('sources/Foo.m', detail=True)
        h = rec['hazards']
        for key in ('NSCoding', 'sdef class', '@synchronized', '@try', '+load/+initialize',
                    'atomics', 'macros', 'performSelector', 'method replacement'):
            self.assertIn(key, h)
        self.assertEqual(h['performSelector'], 1)  # the one in a string is not counted
        bar = MiniRepo.inventory().file_record('sources/Bar.m', detail=True)
        self.assertEqual(bar['xib'], {'Bar': ['sources/Bar.xib']})


class RelationTests(unittest.TestCase):
    def test_relations(self):
        i = MiniRepo.inventory()
        foo = i.class_relations('Foo')
        self.assertEqual(foo['superclass'], 'NSObject')
        self.assertEqual([s['name'] for s in foo['objc_subclasses']], ['FooSub'])
        self.assertEqual(sorted(c['category'] for c in foo['categories']), ['Extras', 'Extras', 'Scripting', 'Testing'])
        self.assertEqual(len(foo['class_extensions']), 2)
        self.assertEqual(foo['swift_extensions'], ['sources/Swifty.swift:5'])
        self.assertEqual(foo['swift_extensions_outside_scope'], ['ModernTests/FooTests.swift:3'])
        bar = i.class_relations('Bar')
        self.assertEqual(sorted((s['name'], s['in_scope']) for s in bar['swift_subclasses']),
                         [('BarSwiftSpy', False), ('SwiftBar', True)])
        self.assertEqual(i.swift_classes['SwiftBar']['objc_name'], 'iTermSwiftBar')
        self.assertNotIn('NotAClass', i.swift_classes)  # in a comment
        self.assertNotIn('func', i.swift_classes)
        self.assertIn('GenericThing', i.swift_classes)

    def test_fan_in_and_state(self):
        i = MiniRepo.inventory()
        bar = i.fan_in('sources/Bar.m')
        self.assertEqual(bar['importers'], 3)
        self.assertEqual(bar['header_importers'], 1)
        self.assertTrue(bar['in_bridging_header'])
        self.assertIsNone(i.fan_in('sources/Lonely.m'))
        rec = i.file_record('sources/Foo.m')
        self.assertTrue(rec['migration_state']['partially_ported'])
        self.assertEqual(rec['arc'], 'non-ARC')

    def test_objcxx(self):
        i = MiniRepo.inventory()
        self.assertTrue(i.objcxx_class('sources/VT100/Hot.mm')['class'].startswith('C++ essential'))
        self.assertIsNone(i.objcxx_class('sources/Foo.m'))
        self.assertEqual(inv.cxx_markers(inv.mask_source('#ifdef __cplusplus\nextern "C" {\n'
                                                         'namespace x {}\n#endif\nint a;\n')), [])
        self.assertIn('std::', inv.cxx_markers(inv.mask_source('std::vector<int> v;')))

    def test_leaf_excludes_classes_with_objc_subclasses(self):
        result = MiniRepo.inventory().leaf(max_fan_in=10, max_reach=100)
        paths = [r['path'] for r in result['candidates']]
        self.assertNotIn('sources/Foo.m', paths)
        self.assertIn('sources/FooSub.m', paths)
        subclassed = dict((f['path'], f['details'])
                          for f in result['deferred']['classes with Objective-C subclasses']['files'])
        self.assertEqual(subclassed['sources/Foo.m'], ['1 Objective-C subclasses (0 outside scope)'])
        hot = dict((f['path'], f['details']) for f in result['deferred']['probable hot path']['files'])
        self.assertEqual(hot, {'sources/VT100/Hot.mm': ['in sources/VT100']})
        reaches = [r['reach'] for r in result['candidates']]
        self.assertEqual(reaches, sorted(reaches))

    def test_leaf_excludes_class_subclassed_outside_scope(self):
        # Bar is subclassed by BarSpy in ModernTests; Objective-C cannot subclass a Swift class.
        result = MiniRepo.inventory().leaf(max_fan_in=10, max_reach=100)
        self.assertNotIn('sources/Bar.m', [r['path'] for r in result['candidates']])
        subclassed = dict((f['path'], f['details'])
                          for f in result['deferred']['classes with Objective-C subclasses']['files'])
        self.assertEqual(subclassed['sources/Bar.m'], ['1 Objective-C subclasses (1 outside scope)'])

    def test_leaf_shows_what_the_dossier_must_address(self):
        rows = dict((r['path'], r) for r in MiniRepo.inventory().leaf()['candidates'])
        self.assertEqual(rows['sources/Owner.m']['address'], [
            'xib customClass', 'ownership attribute', 'ownership-transferring method name', 'imported outside scope', "xib File's Owner", 'xib binding',
            'xib runtime attribute', 'methods named by convention (2)', 'First Responder action'])
        self.assertEqual(rows['sources/Bound.m']['address'], [
            'key-value coding/observing (3)', 'xib customClass', 'xib binding', 'methods named by convention'])
        self.assertEqual(rows['ThirdParty/PSMTabBarControl/source/PSMThing.m']['address'], ['non-ARC'])
        self.assertEqual(rows['sources/Foo+Scripting.m']['address'], ['sdef method', 'sdef key'])
        # Mixed+Private.h holds a class extension of Mixed; OwnerTests.m creates Mixed by name.
        self.assertEqual(rows['sources/Mixed.mm']['address'], ['class extensions in other files (1)', 'C++ in its header',
                                                               'created by name'])
        self.assertEqual(rows['sources/Plain.mm']['address'], ['partially ported', 'no C++ at all', 'xib not parsed'])
        self.assertEqual(rows['sources/Base.m']['address'], [
            'categories declared in other files with no implementation found (1, 1 outside scope)', 'Swift subclasses (1)'])
        # NSClassFromString(@"Foo") creates Foo, not its subclasses.
        self.assertEqual(rows['sources/FooSub.m']['address'], [])
        self.assertEqual(rows['sources/Multi+Extra.m']['address'], [])
        self.assertEqual(rows['sources/iTermThing+Extra.m']['address'], [])
        self.assertEqual(sorted(rows), [
            'ThirdParty/PSMTabBarControl/source/PSMThing.m', 'sources/Base.m', 'sources/Bound.m',
            'sources/Foo+Scripting.m', 'sources/FooSub.m', 'sources/LocalGlobal.m', 'sources/Mixed.mm',
            'sources/Multi+Extra.m', 'sources/Owner.m', 'sources/Plain.mm', 'sources/iTermThing+Extra.m'])

    def test_leaf_deferred_lists(self):
        result = MiniRepo.inventory().leaf()
        lists = dict((name, dict((f['path'], f['details']) for f in d['files']))
                     for name, d in result['deferred'].items())
        self.assertEqual(lists['wholly conditional'],
                         {'sources/Conditional.m': ['lines 7 to 10 are all under #if FIXTURE_FEATURE']})
        self.assertEqual(lists['parse incomplete'],
                         {'sources/Broken.m': ['sources/Broken.m:7: unmatched {; the rest of the file was not parsed']})
        self.assertEqual(lists['must stay in Objective-C for now'], {
            'sources/Forwarder.m': ['forwarding methods (forwardInvocation: and the like)'],
            'sources/Hazardous.m': ['@try: Swift cannot catch NSException'],
            'sources/Loader.m': ['implements +load or +initialize, which a Swift class cannot'],
            'sources/Lookup.m': ['reads method or property metadata from the runtime (a reflective site, '
                                 'hidden-callers.md section 2)'],
            'sources/Proxy.m': ['FixtureProxy is an NSProxy subclass'],
            'sources/ProxyChild.m': ['FixtureProxyChild is an NSProxy subclass'],
            'sources/Reflect.m': ['method-list enumeration'],
            'sources/Swizzle.m': ['swizzling or method replacement']})
        self.assertEqual(lists["needs the owner's permission"], {'sources/Assoc.m': ['associated objects']})
        self.assertEqual(lists['needs a design decision first'], {
            'sources/Multi.m': ['sources/Multi.m defines method-defining macro WEAKLY_REFERENCEABLE'],
            'sources/Nonnull.m': ['sources/Nonnull.m defines class-defining macro DECLARE_GENERATED']})
        self.assertEqual(sorted(lists['class named by a macro']),
                         ['sources/Nonnull.m', 'sources/Window.m', 'sources/WindowImpl.m'])
        self.assertEqual(sorted(lists['classes with Objective-C subclasses']),
                         ['sources/Family.m', 'sources/Plugin.m', 'sources/Proxy.m'])
        self.assertEqual(lists['foundation categories'],
                         {'sources/NSString+Fixture.m': ['categories on NSString(Fixture)']})
        self.assertEqual(lists['built into other executables'], {
            'sources/ServerMain.c': ['also or only compiled by pidinfo'],
            'sources/Util.c': ['also or only compiled by pidinfo']})
        self.assertEqual(sorted(lists['not compiled']), ['sources/Concurrency.m', 'sources/Lonely.m', 'sources/PTYTextView.m'])
        self.assertEqual(lists['included by another file'], {'sources/Included.m': ['#included by sources/Foo.m'],
                                                             'sources/WindowImpl.m': ['#included by sources/Window.m']})
        self.assertEqual(lists['probable hot path'], {'sources/VT100/Hot.mm': ['in sources/VT100']})
        self.assertEqual(sorted(lists['categories implemented in other files']),
                         ['sources/Multi.m', 'sources/PluginImpl.m', 'sources/iTermThing.m'])
        self.assertEqual(sorted(lists['stays in C: atomics']), ['sources/Atomic.m'])
        self.assertEqual(sorted(lists['giant classes']), ['sources/PTYTab+Scripting.m', 'sources/PTYTextView.m'])
        self.assertEqual(sorted(lists['defines C functions or globals declared in a header']), ['sources/Util.c'])
        # The 23 files deferred before the atomics, categories and giant-class rules, plus Atomic.m,
        # PTYTab+Scripting.m, PTYTextView.m, PluginImpl.m and iTermThing.m, and Concurrency.m (not compiled).
        self.assertEqual(result['deferred_files'], 29)
        self.assertEqual(result['outside_thresholds'], {'direct fan-in above 2': 4, 'transitive reach above 10': 0})
        self.assertEqual(result['not_established']['unresolved_class_name_sites'],
                         ['ModernTests/OwnerTests.m:10', 'sources/Plugin.m:30'])
        self.assertEqual(result['not_established']['unparsed_xibs'], ['sources/Unparsable.xib'])
        self.assertEqual(len(result['not_established']['dynamic_selector_sites']), 32)
        for name, d in result['deferred'].items():
            self.assertEqual(d['process'], inv.DEFERRED_LISTS[name][1])

    def test_leaf_thresholds_are_inclusive(self):
        i = MiniRepo.inventory()
        f = i.fan_in('sources/Base.m')
        self.assertEqual(f['importers'], 2)          # Hub.h and Nonnull.m
        self.assertEqual(f['header_importers'], 1)
        self.assertEqual(f['reach'], 6)              # plus Bar.m, Lonely.m, Hazardous.m, Family.m via Hub.h
        self.assertIn('sources/Base.m', [r['path'] for r in i.leaf(max_fan_in=2, max_reach=6)['candidates']])
        result = i.leaf(max_fan_in=1, max_reach=6)
        self.assertNotIn('sources/Base.m', [r['path'] for r in result['candidates']])
        # Bar.m, Base.m and Foo.m, and Buttons.m and ButtonStyle.m through the prefix header.
        self.assertEqual(result['outside_thresholds']['direct fan-in above 1'], 5)
        result = i.leaf(max_fan_in=2, max_reach=5)
        self.assertNotIn('sources/Base.m', [r['path'] for r in result['candidates']])
        self.assertEqual(result['outside_thresholds']['transitive reach above 5'], 1)

    def test_leaf_transitive_reach(self):
        i = MiniRepo.inventory()
        rows = i.leaf(max_fan_in=2, max_reach=2)['candidates']
        self.assertNotIn('sources/Base.m', [r['path'] for r in rows])
        base = [r for r in i.leaf(max_fan_in=2, max_reach=10)['candidates'] if r['path'] == 'sources/Base.m'][0]
        self.assertEqual(base['reach'], 6)

    def test_leaf_flags_foundation_categories(self):
        result = MiniRepo.inventory().leaf(max_fan_in=10, max_reach=100)
        self.assertNotIn('sources/NSString+Fixture.m', [r['path'] for r in result['candidates']])
        self.assertEqual([f['path'] for f in result['deferred']['foundation categories']['files']],
                         ['sources/NSString+Fixture.m'])

    def test_leaf_text_output(self):
        code, out, err = run_cli(MiniRepo.path(), 'leaf', '--deferred')
        self.assertEqual(code, 0, err)
        self.assertIn('    sources/Assoc.m: associated objects', out)
        self.assertIn('wholly conditional (1): ', out)
        self.assertIn('2 calls create a class from a name known only at run time', out)
        self.assertIn('sources/Plugin.m:30', out)
        code, out, err = run_cli(MiniRepo.path(), 'leaf')
        self.assertNotIn('sources/Assoc.m: associated objects', out)
        self.assertIn('(--deferred lists the files in each.)', out)
        data = json.loads(run_cli(MiniRepo.path(), '--json', 'leaf')[1])
        self.assertEqual(data['deferred']["needs the owner's permission"]['count'], 1)
        self.assertNotIn('files', data['deferred']["needs the owner's permission"])


class ConditionalTests(unittest.TestCase):
    def test_wholly_conditional(self):
        def cond(src):
            return inv.wholly_conditional(inv.mask_source(src))
        self.assertEqual(cond('#import "a.h"\n#if A\nNS_ASSUME_NONNULL_BEGIN\nint x;\n#if B\nint y;\n#endif\n'
                              'NS_ASSUME_NONNULL_END\n#endif\n'),
                         {'condition': 'A', 'first_line': 4, 'last_line': 6})
        self.assertEqual(cond('#ifdef A\nint x;\n#endif\n#ifdef A\nint y;\n#endif\n'),
                         {'condition': 'defined(A)', 'first_line': 2, 'last_line': 5})
        self.assertEqual(cond('#if A\n#if B\nint x;\n#endif\n#endif\n'),
                         {'condition': 'A && B', 'first_line': 3, 'last_line': 3})
        self.assertIsNone(cond('#if A\nint x;\n#else\nint y;\n#endif\n'))
        self.assertEqual(cond('#if A\nint x;\n#elif B\nint y;\n#endif\n'), None)
        self.assertIsNone(cond('int x;\n#if A\nint y;\n#endif\n'))
        self.assertIsNone(cond('#if A\nint y;\n#endif\nint x;\n'))
        self.assertIsNone(cond('// only a comment\n'))
        # An include guard is not a condition on the code.
        self.assertIsNone(cond('#ifndef GUARD_H\n#define GUARD_H\nint x;\n#endif\n'))
        self.assertEqual(cond('#ifndef FEATURE\nint x;\n#endif\n'),
                         {'condition': '!defined(FEATURE)', 'first_line': 2, 'last_line': 2})
        self.assertEqual(cond('#if 0\nint x;\n#else\n#endif\n'), {'condition': '0', 'first_line': 2, 'last_line': 2})
        self.assertEqual(cond('#if A\n#else\nint x;\n#endif\n'),
                         {'condition': 'not (A)', 'first_line': 3, 'last_line': 3})

    def test_conditional_file_in_every_view(self):
        i = MiniRepo.inventory()
        rec = i.file_record('sources/Conditional.m')
        self.assertEqual(rec['wholly_conditional'], {'condition': 'FIXTURE_FEATURE', 'first_line': 7, 'last_line': 10})
        self.assertIsNone(i.file_record('sources/Base.m')['wholly_conditional'])
        s = i.summary()
        self.assertEqual(s['progress']['wholly_conditional'],
                         {'files': 1, 'lines': 13, 'paths': ['sources/Conditional.m']})
        code, out, err = run_cli(MiniRepo.path(), 'file', 'Conditional.m')
        self.assertIn('CONDITIONAL: every line of code (lines 7 to 10) is under #if FIXTURE_FEATURE', out)
        self.assertIn('wholly conditional: lines 7 to 10 are all under #if FIXTURE_FEATURE', out)
        code, out, err = run_cli(MiniRepo.path(), 'files', '--filter', 'Conditional')
        self.assertEqual(out.splitlines()[2].split()[-1], 'cond')
        code, out, err = run_cli(MiniRepo.path(), 'summary')
        self.assertIn('of which 13 lines in 1 implementation files are wholly under a preprocessor condition', out)


class HiddenCallerTests(unittest.TestCase):
    def test_file_details(self):
        rec = MiniRepo.inventory().file_record('sources/Owner.m', detail=True)
        self.assertEqual(rec['ownership_attributes'], [
            'sources/Owner.h:4: FIXTURE_NOT_COPY (a macro from sources/Macros.h that applies an ownership or '
            'method-family attribute)'])
        self.assertEqual(rec['imported_outside_scope'], ['ModernTests/OwnerTests.m'])
        self.assertEqual(rec['methods_named_by_convention'], ['-countOfItems', '-objectInItemsAtIndex:'])
        self.assertEqual(rec['first_responder_actions'], {'fixtureZoom:': ['sources/Owner.xib']})
        self.assertEqual(rec['xib_connections'], [
            {'xib': 'sources/Owner.xib', 'object': 'customClass OwnerBadge',
             'references': {'outlets': 0, 'incoming_outlets': 1, 'actions': 0, 'bindings': 0,
                            'runtime_attributes': 1}},
            {'xib': 'sources/Owner.xib', 'object': 'File\'s Owner (the file names "Owner")',
             'references': {'outlets': 1, 'incoming_outlets': 0, 'actions': 1, 'bindings': 1,
                            'runtime_attributes': 0}}])
        # -copyTitle is in the copy family.
        self.assertEqual(rec['hazards'], {'xib customClass': 1, 'ownership attribute': 1,
                                          'ownership-transferring method name': 1, 'imported outside scope': 1,
                                          "xib File's Owner": 1, 'xib binding': 1, 'xib runtime attribute': 1,
                                          'methods named by convention': 2, 'First Responder action': 1})

    def test_created_by_name(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.file_record('sources/PluginImpl.m', detail=True)['created_by_name'], [
            'Bystander: may be created by name at sources/Plugin.m:22 (any class implementing -initWithFixture:)',
            'FixtureResponder: may be created by name at sources/Plugin.m:22 (any class implementing '
            '-initWithFixture:)',
            'LoadableThing: may be created by name at sources/Plugin.m:14 (any class conforming to FixtureLoadable)',
            'PluginImpl: may be created by name at sources/Plugin.m:6 (any subclass of PluginBase)'])
        self.assertEqual(i.file_record('sources/Bar.m', detail=True)['created_by_name'],
                         ['Bar: created by name at sources/Foo.m:88'])
        self.assertEqual(i.unresolved_class_sites, ['ModernTests/OwnerTests.m:10', 'sources/Plugin.m:30'])

    def test_created_by_name_reaches_indirect_subclasses(self):
        def mutate(root):
            with open(os.path.join(root, 'sources', 'PluginGrandchild.m'), 'w') as f:
                f.write('#import "Plugin.h"\n@interface PluginGrandchild : PluginImpl\n@end\n'
                        '@implementation PluginGrandchild\n@end\n')
        i = inv.Inventory(make_repo(mutate))
        self.assertEqual(i.file_record('sources/PluginGrandchild.m', detail=True)['created_by_name'], [
            'PluginGrandchild: may be created by name at sources/Plugin.m:6 (any subclass of PluginBase)'])

    def test_runtime_hazards(self):
        rec = MiniRepo.inventory().file_record('sources/Lookup.m')
        self.assertEqual(rec['hazards'], {'runtime method lookup': 2, 'runtime class query': 1})
        src = ('method_setImplementation(m, i); class_replaceMethod(c, s, i, t); object_setClass(o, c);\n'
               'class_copyPropertyList(c, &n); objc_copyClassList(&n);\n'
               'method_getTypeEncoding(m); property_getName(p); class_getMethodImplementation(c, s);\n'
               'object_getClass(o); class_respondsToSelector(c, s);\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual((h['method replacement'], h['method-list enumeration'], h['runtime method lookup'],
                          h['runtime class query']), (3, 2, 3, 2))

    def test_more_hidden_callers(self):
        src = ('NSString *s = NSStringFromClass([self class]);\n'
               'const char *n = sel_getName(sel);\n'
               'objc_setAssociatedObject(self, _cmd, v, 0);\n'
               'NSLog(@"%@", NSStringFromSelector(_cmd));\n'
               'id t = [NSApp targetForAction:@selector(copy:)];\n'
               '[m setEventHandler:self andSelector:@selector(h:withReply:) forEventClass:1 andEventID:2];\n'
               '[alert beginSheetModalForWindow:w modalDelegate:self didEndSelector:@selector(e:) contextInfo:nil];\n'
               '[self respondsToSelector:@selector(r)];\n'
               '+ (BOOL)automaticallyNotifiesObserversOfFoo { return NO; }\n'
               '[NSPredicate predicateWithFormat:@"name == %@", x];\n'
               '[NSSortDescriptor sortDescriptorWithKey:@"k" ascending:YES];\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual(h['NSStringFromClass'], 1)
        self.assertEqual(h['NSStringFromSelector(variable)'], 1)
        self.assertEqual(h['NSStringFromSelector(_cmd)'], 1)
        self.assertEqual(h['_cmd as a value'], 1)
        self.assertEqual(h['sendAction'], 1)
        self.assertEqual(h['selector registration'], 2)
        self.assertEqual(h['respondsToSelector'], 1)
        self.assertEqual(h['key-value coding/observing'], 3)
        load = inv.HAZARD_PATTERNS['+load/+initialize']
        self.assertTrue(load.search('+ (void)initialize NS_REQUIRES_SUPER {\n'))
        self.assertTrue(load.search('+ (void)load {\n'))
        self.assertFalse(load.search('+ (void)loadFrom:(id)x {\n'))
        self.assertFalse(load.search('+ (void)load:(id)x {\n'))

    def test_naming_convention_selectors(self):
        for sel in ('countOfSessions', 'valueInSessionsAtIndex:', 'insertObject:inItemsAtIndex:',
                    'removeObjectFromItemsAtIndex:', 'validateName:error:', 'keyPathsForValuesAffectingTitle',
                    'automaticallyNotifiesObserversOfTitle', 'valueInTabsWithUniqueID:', 'objectSpecifier',
                    'application:delegateHandlesKey:'):
            self.assertTrue(inv._CONVENTION_SELECTOR.match(sel), sel)
        for sel in ('count', 'countOf', 'valueForKey:', 'insertObject:atIndex:', 'validate'):
            self.assertFalse(inv._CONVENTION_SELECTOR.match(sel), sel)

    def test_class_declared_in_another_header(self):
        # WidgetCore has no WidgetCore.h; its @interface is in WidgetAPI.h, which two files import.
        def mutate(root):
            files = {
                'sources/WidgetAPI.h': '@interface WidgetCore : NSObject\n@end\n',
                'sources/Flow.h': '#define CHECK(x) if (!(x)) { return; }\n',
                'sources/WidgetCore.m': ('#import "WidgetAPI.h"\n#import "Flow.h"\n@implementation WidgetCore\n'
                                         '- (void)f {\n    CHECK(1);\n}\n@end\n'),
                'sources/UsesWidget1.m': '#import "WidgetAPI.h"\n',
                'sources/UsesWidget2.m': '#import "WidgetAPI.h"\n',
            }
            for path, text in files.items():
                with open(os.path.join(root, path), 'w') as f:
                    f.write(text)
        i = inv.Inventory(make_repo(mutate))
        f = i.fan_in('sources/WidgetCore.m')
        # WidgetAPI.h stands in for the missing WidgetCore.h, so it is not also one of the other headers.
        self.assertEqual((f['header'], f['other_headers'], f['importers'], f['reach']),
                         ('sources/WidgetAPI.h', [], 2, 2))
        rec = i.file_record('sources/WidgetCore.m', detail=True)
        self.assertEqual(rec['control_flow_macros'], ['CHECK (from sources/Flow.h)'])
        self.assertEqual(rec['hazards']['control flow in a macro'], 1)
        self.assertNotIn('sources/WidgetCore.m', [r['path'] for r in i.leaf(max_fan_in=1)['candidates']])

    def test_undo_by_invocation(self):
        h = inv.file_hazards(inv.mask_source('[[undo prepareWithInvocationTarget:self] setFoo:x];\n'))
        self.assertEqual(h['NSInvocation'], 1)

    def test_parse_problems(self):
        def mutate(root):
            with open(os.path.join(root, 'sources', 'Nameless.m'), 'w') as f:
                f.write('@implementation\n@end\n')
        i = inv.Inventory(make_repo(mutate))
        self.assertEqual(i.parse_problems('sources/Nameless.m'), ['1 @implementation lines but 0 parsed'])
        self.assertEqual(i.parse_problems('sources/Base.m'), [])


class ScopeProjectAndRelationDetailTests(unittest.TestCase):
    """Exclusions, ARC settings, Swift superclasses, Objective-C++ classes, and xib and sdef flags."""

    def test_exclusions_outside_their_directories(self):
        self.assertEqual(inv.exclusion_reason('sources/Other/Api.pbobjc.m'), 'generated (protobuf)')
        self.assertEqual(inv.exclusion_reason('sources/Other/Thing+CoreDataClass.m'), 'generated (Core Data)')
        self.assertIsNone(inv.exclusion_reason('sources/Other/pbobjc.m'))

    def test_swift_superclass_is_the_first_inherited_name(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.swift_classes['SwiftPair']['superclass'], 'Base')
        self.assertEqual(i.swift_classes['SwiftPair']['inherits'], ['Base', 'NSCopying'])
        self.assertEqual([s['name'] for s in i.class_relations('Base')['swift_subclasses']], ['SwiftPair'])

    def test_partially_unset_arc_configuration(self):
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = a.m; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = X; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1, C2 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( ); }; '
            'C1 = { isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_OBJC_ARC = YES; }; }; '
            'C2 = { isa = XCBuildConfiguration; buildSettings = { }; }; '
            '}; rootObject = P; }')
        membership, targets, _ = inv.compute_target_membership(plist)
        self.assertEqual(targets['X']['arc'], 'mixed')
        self.assertEqual(targets['X']['arc_source'], "CLANG_ENABLE_OBJC_ARC in the target's build configurations "
                                                     "(unset in some configurations, which default to NO)")

    def test_conditional_arc_setting_is_reported(self):
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = a.m; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = X; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( ); }; '
            'C1 = { isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_OBJC_ARC = YES; '
            '"CLANG_ENABLE_OBJC_ARC[arch=x86_64]" = NO; }; }; '
            '}; rootObject = P; }')
        membership, targets, _ = inv.compute_target_membership(plist)
        self.assertEqual(targets['X']['xcconfig_unread'],
                         ['conditional setting CLANG_ENABLE_OBJC_ARC[arch=x86_64] is not evaluated'])

    def test_objcxx_classes(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.objcxx_class('sources/Mixed.mm'),
                         {'class': 'C++ in its header', 'markers': [],
                          'header_markers': {'sources/Mixed.h': ['C++ standard header']}})
        self.assertEqual(i.objcxx_class('sources/Plain.mm')['class'], 'no C++ at all')

    def test_xib_and_sdef_key_flags(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.file_record('sources/Bar.m')['hazards']['xib customClass'], 1)
        rec = i.file_record('sources/Foo+Scripting.m', detail=True)
        self.assertEqual(rec['sdef_keys'], ['-[Foo setTitle:]'])
        self.assertEqual(rec['hazards'], {'sdef method': 1, 'sdef key': 1})


def commit_messages(root, messages):
    """Makes one empty commit per (date, message) in the repository at root."""
    for date, message in messages:
        env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.com',
                   GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@example.com',
                   GIT_AUTHOR_DATE=date + 'T12:00:00Z', GIT_COMMITTER_DATE=date + 'T12:00:00Z')
        subprocess.run(['git', 'commit', '-q', '--allow-empty', '-m', message], cwd=root, check=True, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class TrailerTests(unittest.TestCase):
    """Swift-Port trailers as git reads them, in commits made for the purpose."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_repo()
        commit_messages(cls.root, [
            ('2026-01-01', 'Subject\n\nSwift-Port: Foo kind=test'),
            ('2026-02-01', 'Subject\n\nSwift-Port: Foo kind=port\nSwift-Port: Foo kind=port\n'
                           'Swift-Port: Bar kind=weird\nSwift-Port: broken'),
            ('2026-02-02', 'Swift-Port: InSubject kind=test'),
            ('2026-02-03', 'Subject\n\nProse in the final paragraph.\nSwift-Port: Mixed kind=port'),
            ('2026-02-04', 'Subject\n\n  Swift-Port: Indented kind=test'),
            ('2026-02-05', 'Subject\n\nSwift-Port: Middle kind=test\n\nMore prose.'),
            ('2026-02-06', 'Subject\n\nBody.\n\nSwift-Port: Signed kind=arc\nSigned-off-by: t <t@example.com>'),
            ('2026-02-07', 'Subject\n\nswift-port: Lower kind=test\nSwift-Port : Spaced kind=test'),
            ('2026-02-08', 'Subject\n\nX-Swift-Port: Baz kind=port\nSwift-Porting: Qux kind=port'),
            ('2026-02-09', 'Subject\n\nSwift-Port: Port kind=Port\nSwift-Port: Extra kind=port trailing'),
            ('2026-02-10', 'Subject\n\nSwift-Port: Same kind=test\nX-Swift-Port: Same kind=test'),
        ])
        cls.units, cls.problems = inv.history_from_git(cls.root)

    def test_counted_units(self):
        self.assertEqual(list(self.units), ['Same', 'Lower', 'Spaced', 'Signed', 'Foo'])
        self.assertEqual(self.units['Foo']['kinds'], {'port': 1, 'test': 1})  # once per commit
        self.assertEqual(self.units['Foo']['first_date'], '2026-01-01')
        self.assertEqual(self.units['Foo']['last_date'], '2026-02-01')
        self.assertEqual(len(self.units['Foo']['commits']), 2)
        self.assertEqual(self.units['Signed']['kinds'], {'arc': 1})

    def test_problems(self):
        got = sorted((p['problem'], p['line']) for p in self.problems)
        not_a_trailer = 'not counted: git does not read this line as a Swift-Port trailer'
        self.assertEqual(got, sorted([
            ('counted, but not written exactly as Swift-Port: <unit> kind=<kind>', 'Swift-Port : Spaced kind=test'),
            ('counted, but not written exactly as Swift-Port: <unit> kind=<kind>', 'swift-port: Lower kind=test'),
            ('malformed trailer (not counted)', 'Swift-Port: Extra kind=port trailing'),
            ('malformed trailer (not counted)', 'Swift-Port: broken'),
            ('repeated in the same commit; counted once', 'Swift-Port: Foo kind=port'),
            (not_a_trailer, 'Swift-Port: InSubject kind=test'),
            (not_a_trailer, 'Swift-Port: Indented kind=test'),
            (not_a_trailer, 'Swift-Port: Middle kind=test'),
            (not_a_trailer, 'Swift-Port: Mixed kind=port'),
            (not_a_trailer, 'Swift-Porting: Qux kind=port'),
            (not_a_trailer, 'X-Swift-Port: Baz kind=port'),
            (not_a_trailer, 'X-Swift-Port: Same kind=test'),
            ('unknown kind Port (not counted)', 'Swift-Port: Port kind=Port'),
            ('unknown kind weird (not counted)', 'Swift-Port: Bar kind=weird'),
        ]))

    def test_unparsable_git_output_is_an_error(self):
        with self.assertRaises(inv.InventoryError):
            inv.parse_trailers('abc\x1f2026-01-01\x1fno trailer field\x1e')

    def test_minirepo_history(self):
        units, problems = MiniRepo.inventory().history()
        self.assertEqual(list(units), ['Foo'])
        self.assertEqual(units['Foo']['kinds'], {'port': 1, 'test': 1})
        self.assertEqual(units['Foo']['last_date'], '2026-01-02')
        kinds = sorted(p['problem'] for p in problems)
        not_a_trailer = 'not counted: git does not read this line as a Swift-Port trailer'
        self.assertEqual(kinds, ['malformed trailer (not counted)', not_a_trailer, not_a_trailer, not_a_trailer,
                                 'unknown kind bogus (not counted)'])

    def test_history_for_missing_unit(self):
        code, out, _ = run_cli(MiniRepo.path(), 'history', 'nosuch')
        self.assertEqual(code, 1)
        self.assertIn('No Swift-Port trailers for unit nosuch', out)
        self.assertIn('commits reachable from HEAD', out)
        code, out, _ = run_cli(MiniRepo.path(), 'history', 'Foo')
        self.assertEqual(code, 0)
        code, out, _ = run_cli(MiniRepo.path(), '--json', 'history')
        self.assertEqual(json.loads(out)['scope'], 'commits reachable from HEAD')


class ArgumentTests(unittest.TestCase):
    def test_bad_numbers_are_rejected(self):
        root = MiniRepo.path()
        for args in (['leaf', '--limit', '0'], ['leaf', '--limit', '-3'], ['leaf', '--max-fan-in', '-1'],
                     ['leaf', '--max-reach', '-1'], ['files', '--limit', '0'], ['files', '--limit', '-3'],
                     ['leaf', '--limit', 'x']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 2, (args, out, err))
            self.assertEqual(out, '', args)
            self.assertIn('argument', err, args)

    def test_files_limit_states_the_total(self):
        root = MiniRepo.path()
        code, out, err = run_cli(root, 'files', '--limit', '2')
        self.assertEqual(code, 0, err)
        self.assertIn('Showing 2 of 44 files.', out)
        data = json.loads(run_cli(root, '--json', 'files', '--limit', '2')[1])
        self.assertEqual((data['total'], data['shown'], len(data['files'])), (44, 2, 2))
        code, out, err = run_cli(root, 'files')
        self.assertIn('44 files.', out)

    def test_leaf_limit_states_the_total(self):
        root = MiniRepo.path()
        code, out, err = run_cli(root, 'leaf', '--limit', '3')
        self.assertEqual(code, 0, err)
        self.assertIn('Offered: 11 files of the leaf tier', out)
        self.assertIn('Showing 3 of 11.', out)
        data = json.loads(run_cli(root, '--json', 'leaf', '--limit', '3')[1])
        self.assertEqual((data['candidates_total'], data['candidates_shown'], len(data['candidates'])), (11, 3, 3))


class SummaryTests(unittest.TestCase):
    def test_minirepo_summary(self):
        s = MiniRepo.inventory().summary()
        self.assertEqual(s['implementation_files'], 44)
        self.assertEqual(s['files_in_non_arc_target'], 5)  # includes Included.m, via Foo.m
        self.assertEqual(s['objc_files_compiled_without_arc'], 4)  # Hazardous.m has -fno-objc-arc
        self.assertEqual(s['not_compiled_by_any_target'], ['sources/Concurrency.m', 'sources/Lonely.m', 'sources/PTYTextView.m'])
        self.assertEqual(s['progress']['null_unspecified'], 1)
        self.assertEqual(s['progress']['markers']['SWIFT-MIGRATION-SHIM']['occurrences'], 1)
        # ivar_thing in PSMThing.m and MyClass_ivar_set_foo in RuntimeUse.swift; not ivar_getName or
        # ivar_getTypeEncoding, and not the mention in docs/swift-migration.
        self.assertEqual(s['progress']['ivar_accessor_uses'], 2)
        # Foo (FooSub), Bar (BarSpy in ModernTests), Parent (Child), PluginBase, FixtureProxy.
        self.assertEqual(s['classes_with_objc_subclasses'], 5)
        self.assertEqual(s['classes_with_objc_subclasses_outside_scope'], 1)

    def test_reliability_covers_every_field(self):
        root = MiniRepo.path()

        def check(args, rows_key=None):
            data = json.loads(run_main(['--root', root, '--json'] + args))
            reliability = data['reliability']
            for key in data:
                if key not in ('warnings', 'reliability'):
                    self.assertIn(key, reliability, (args, key))
            for row in (data[rows_key] if rows_key else []):
                for key in row:
                    self.assertIn(key, reliability, (args, key))
            if 'targets' in reliability:
                self.assertEqual(reliability['targets']['reliability'], 'heuristic')
        check(['summary'])
        check(['files'], 'files')
        check(['file', 'Owner.m'])
        check(['history'])
        check(['leaf', '--deferred'], 'candidates')

    def test_cli_json(self):
        root = MiniRepo.path()
        for args in (['summary'], ['files'], ['file', 'Foo'], ['leaf'], ['history']):
            out = run_main(['--root', root, '--json'] + args)
            data = json.loads(out)
            self.assertIn('reliability', data, args)
            for field, info in data['reliability'].items():
                self.assertIn(info['reliability'], ('exact', 'heuristic'), field)
            out = run_main(['--root', root] + args)
            self.assertTrue(out.strip(), args)


class ParserSafetyTests(unittest.TestCase):
    def test_unmatched_brace_warns(self):
        of = inv.ObjCFile('x.m', '@implementation A\n- (void)f {\n    if (x) {\n}\n')
        self.assertTrue(any('unmatched' in w for w in of.warnings))

    def test_static_function_returning_generic_with_block_type(self):
        # Found by the crude static count on DebugLogging.m: the ( inside <...> is not the parameter list.
        of = inv.ObjCFile('x.m', 'static NSMutableDictionary<NSString *, NSString *(^)(void)> *Providers(void) {\n'
                                 '    return nil;\n}\n')
        self.assertEqual([(s['name'], s['kind']) for s in of.statics], [('Providers', 'function')])
        self.assertEqual(of.warnings, [])

    def test_crude_count_agrees_on_simple_file(self):
        of = inv.ObjCFile('x.m', '@implementation A\n- (void)f {\n}\n@end\n')
        self.assertEqual(of.crude_method_count, 1)
        self.assertEqual(len(of.methods), 1)
        self.assertEqual(of.warnings, [])

    def test_crude_count_warns_when_parse_misses(self):
        # The parser finds everything in real text today, so drop its result and rerun the check.
        of = inv.ObjCFile('x.m', '@implementation A\n- (void)f {\n}\nstatic int s;\n@end\n')
        of.methods = []
        of.statics = []
        of.warnings = []
        of._self_check()
        self.assertTrue(any('method definitions' in w for w in of.warnings), of.warnings)
        self.assertTrue(any('static' in w for w in of.warnings), of.warnings)

    def test_new_hazards(self):
        src = ('[a sortUsingSelector:@selector(x)];\n'
               '[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(t:) userInfo:nil repeats:NO];\n'
               '[um registerUndoWithTarget:self selector:@selector(u:) object:nil];\n'
               '[x setValue:y forKey:@"k"];\n[x addObserver:self forKeyPath:@"k" options:0 context:nil];\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual(h['sort by selector'], 1)
        self.assertEqual(h['selector registration'], 2)
        self.assertEqual(h['key-value coding/observing'], 2)


class FailureModeTests(unittest.TestCase):
    def test_runs_from_a_subdirectory(self):
        root = MiniRepo.path()
        code, out, err = run_cli(os.path.join(root, 'sources'), '--json', 'summary')
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)['implementation_files'], 44)
        code, out, err = run_cli(os.path.join(root, 'sources', 'VT100'), '--json', 'leaf')
        self.assertEqual(code, 0, err)
        self.assertTrue(json.loads(out)['candidates'])
        code, out, err = run_cli(os.path.join(root, 'sources'), 'file', 'Foo.m')
        self.assertEqual(code, 0, err)

    def assert_fails_everywhere(self, root, text):
        for args in (['summary'], ['files'], ['file', 'Foo'], ['leaf']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 2, (args, out, err))
            self.assertIn('error', err)
            self.assertIn(text, err)
            self.assertEqual(out, '')

    def test_broken_project(self):
        def mutate(root):
            with open(os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj'), 'w') as f:
                f.write('{ objects = { broken')
        self.assert_fails_everywhere(make_repo(mutate), 'project.pbxproj')

    def test_missing_project(self):
        def mutate(root):
            os.remove(os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj'))
        self.assert_fails_everywhere(make_repo(mutate), 'not found')

    def test_empty_scope(self):
        def mutate(root):
            shutil.rmtree(os.path.join(root, 'sources'))
            shutil.rmtree(os.path.join(root, 'ThirdParty'))
        root = make_repo(mutate)
        code, out, err = run_cli(root, 'summary')
        self.assertEqual(code, 2)
        self.assertIn('no in-scope implementation files', err)

    def test_not_a_repository(self):
        d = tempfile.mkdtemp(prefix='inventory-test-')
        TEMP_DIRS.append(d)
        code, out, err = run_cli(d, 'summary')
        self.assertEqual(code, 2)
        self.assertIn('not inside a git repository', err)
        code, out, err = run_cli(d, 'history')
        self.assertEqual(code, 2)

    def test_optional_subcommands_missing(self):
        # The core alone, without inventory_state.py and inventory_verify.py.
        d = tempfile.mkdtemp(prefix='inventory-test-')
        TEMP_DIRS.append(d)
        shutil.copy(os.path.join(TOOL_DIR, 'inventory.py'), d)
        tool = os.path.join(d, 'inventory.py')
        for args, missing in ((['state', 'Foo.m'], 'inventory_state.py'), (['verify'], 'inventory_verify.py')):
            proc = subprocess.run([sys.executable, tool] + args, cwd=MiniRepo.path(),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            err = proc.stderr.decode('utf-8')
            self.assertEqual(proc.returncode, 2, err)
            self.assertIn('the %s subcommand is not available: %s could not be imported' % (args[0], missing), err)
            self.assertEqual(proc.stdout, b'')
        proc = subprocess.run([sys.executable, tool, '--json', 'summary'], cwd=MiniRepo.path(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout.decode('utf-8'))['implementation_files'], 44)

    def test_unknown_file_name(self):
        code, out, err = run_cli(MiniRepo.path(), 'file', 'NoSuchFile.m')
        self.assertEqual(code, 2)
        self.assertIn('no in-scope implementation file', err)

    def test_unreadable_file(self):
        root = make_repo()
        path = os.path.join(root, 'sources', 'Lonely.m')
        os.chmod(path, 0)
        try:
            if os.access(path, os.R_OK):
                self.skipTest('running with privileges that ignore file modes')
            code, out, err = run_cli(root, 'summary')
            self.assertEqual(code, 2)
            self.assertIn('cannot read sources/Lonely.m', err)
            self.assertNotIn('Traceback', err)
        finally:
            os.chmod(path, 0o644)

    def test_non_utf8_warns(self):
        def mutate(root):
            with open(os.path.join(root, 'sources', 'Lonely.m'), 'ab') as f:
                f.write(b'// caf\xe9\n')
        code, out, err = run_cli(make_repo(mutate), 'summary')
        self.assertEqual(code, 0, err)
        self.assertIn('sources/Lonely.m is not valid UTF-8', err)

    def test_synchronized_group_over_scope_warns(self):
        def mutate(root):
            p = os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj')
            with open(p) as f:
                text = f.read()
            with open(p, 'w') as f:
                f.write(text.replace('path = ModernTests;', 'path = sources;'))
        code, out, err = run_cli(make_repo(mutate), 'summary')
        self.assertEqual(code, 0, err)
        self.assertIn('synchronized folder sources', err)


class MacroTargetAndParserDetailTests(unittest.TestCase):
    """Classes named by macros, other targets, sdef methods, statics, per-file ARC flags, markers, the
    bridging header, xcconfig files, selectors, trailer blocks, hazards and help text."""

    def inv(self):
        return MiniRepo.inventory()

    def test_macro_named_classes_are_resolved(self):
        i = self.inv()
        self.assertNotIn('THE_CLASS', i.primary_impl_file)
        self.assertNotIn('THE_CLASS', i.interfaces)
        self.assertEqual(i.primary_impl_file.get('Window'), 'sources/WindowImpl.m')
        self.assertEqual(i.primary_impl_file.get('Panel'), 'sources/WindowImpl.m')
        self.assertTrue(any('THE_CLASS' in w for w in i.warnings), i.warnings)
        self.assertEqual(i.file_record('sources/WindowImpl.m')['classes'], ['Panel', 'Window'])

    def test_macro_named_class_files_are_not_leaf_candidates(self):
        i = self.inv()
        result = i.leaf(max_fan_in=100, max_reach=1000)
        paths = [r['path'] for r in result['candidates']]
        self.assertNotIn('sources/WindowImpl.m', paths)
        self.assertNotIn('sources/Window.m', paths)
        self.assertEqual(sorted(f['path'] for f in result['deferred']['class named by a macro']['files']),
                         ['sources/Nonnull.m', 'sources/Window.m', 'sources/WindowImpl.m'])

    def test_class_declared_inside_a_define_is_not_a_class(self):
        i = self.inv()
        self.assertNotIn('t', i.interfaces)
        self.assertNotIn('t', i.objc_subclasses.get('Base', []))

    def test_files_built_by_other_targets_are_listed_separately(self):
        i = self.inv()
        result = i.leaf(max_fan_in=100, max_reach=1000)
        paths = [r['path'] for r in result['candidates']]
        self.assertNotIn('sources/Util.c', paths)
        self.assertNotIn('sources/ServerMain.c', paths)
        self.assertTrue(all('targets' in r for r in result['candidates']))
        other = dict((f['path'], f['details']) for f in result['deferred']['built into other executables']['files'])
        self.assertEqual(other, {'sources/ServerMain.c': ['also or only compiled by pidinfo'],
                                 'sources/Util.c': ['also or only compiled by pidinfo']})

    def test_sdef_methods_flag_category_files(self):
        i = self.inv()
        rec = i.file_record('sources/Foo+Scripting.m')
        self.assertIn('sdef method', rec['hazards'])
        rows = dict((r['path'], r) for r in i.leaf(max_fan_in=100, max_reach=1000)['candidates'])
        self.assertIn('sdef method', rows['sources/Foo+Scripting.m']['address'])

    def test_statics_after_bare_macro(self):
        of = self.inv().objc_file('sources/Nonnull.m')
        statics = dict((s['name'], s['kind']) for s in of.statics)
        self.assertEqual(statics.get('NonnullIsValid'), 'function')
        self.assertEqual(statics.get('sNonnullCount'), 'variable')
        self.assertNotIn('DECLARE_GENERATED', [f['name'] for f in of.functions])
        self.assertTrue([f for f in of.functions if f['name'] == 'NonnullIsValid' and f['static']])
        self.assertEqual(of.warnings, [])

    def test_per_file_no_arc_flag(self):
        i = self.inv()
        self.assertEqual(i.arc_state('sources/Hazardous.m'), 'non-ARC')
        t = i.targets_for('sources/Hazardous.m')[0]
        self.assertTrue(t['file_flag'])
        self.assertIs(t['arc'], False)

    def test_marker_counts_exclude_docs(self):
        markers = self.inv().marker_counts()
        self.assertEqual(markers['SWIFT-MIGRATION-SHIM']['occurrences'], 1)

    def test_iuo_marker_is_counted(self):
        # The implicitly unwrapped type marker (decisions.md, 2026-11-20) is counted like the others, outside the
        # paths that describe the markers.
        def mutate(root):
            with open(os.path.join(root, 'sources', 'Iuo.swift'), 'w') as f:
                f.write('// SWIFT-MIGRATION-IUO: unannotated header\nfunc f(a: Int!) { }\n'
                        'func g(b: Int!) { } // SWIFT-MIGRATION-IUO: same\n')
            with open(os.path.join(root, 'docs', 'swift-migration', 'iuo.md'), 'w') as f:
                f.write('// SWIFT-MIGRATION-IUO: described, not used\n')
        root = make_repo(mutate)
        markers = inv.Inventory(root).marker_counts()
        self.assertEqual(markers['SWIFT-MIGRATION-IUO'], {'occurrences': 2, 'files': 1})
        code, out, err = run_cli(root, 'summary')
        self.assertEqual(code, 0, err)
        self.assertIn('  SWIFT-MIGRATION-IUO: 2 in 1 files\n', out)

    def test_checked_arithmetic_helper_calls_are_counted(self):
        # The helper calls are scaffolding removed in stage two, and the inventory counts the ones that remain
        # (decisions.md, 2026-11-20). Calls in comments and strings, other names that only start the same way,
        # the helper library itself and its own tests are not counted.
        def mutate(root):
            os.makedirs(os.path.join(root, 'sources', 'Infrastructure'), exist_ok=True)
            os.makedirs(os.path.join(root, 'ModernTests'), exist_ok=True)
            with open(os.path.join(root, 'sources', 'Ported.swift'), 'w') as f:
                f.write('func f(a: Int32, b: Int32, d: Double) -> Int32 {\n'
                        '    let s = it_add(a, b) &+ it_add(a, 1)\n'
                        '    let n = it_narrow(it_multiply(Int(a), 3), to: Int16.self)\n'
                        '    _ = it_floatToInteger (d, to: Int32.self)\n'
                        '    // it_subtract(a, b) in a comment\n'
                        '    _ = "it_negate(a) in a string"\n'
                        '    _ = x.it_addObject(y)\n'
                        '    _ = it_addressString\n'
                        '    return it_shiftLeft(s, Int(n)) + it_subtract(a, b) + it_negate(a)\n'
                        '}\n')
            with open(os.path.join(root, 'sources', 'Other.swift'), 'w') as f:
                f.write('let v = it_narrow(1, to: Int8.self)\n')
            with open(os.path.join(root, 'sources', 'Infrastructure', 'SwiftMigrationHelpers.swift'), 'w') as f:
                f.write('func it_add<T>(_ a: T, _ b: T) -> T { return it_add(a, b, onFailure: f) }\n')
            with open(os.path.join(root, 'ModernTests', 'SwiftMigrationHelpersTests.swift'), 'w') as f:
                f.write('let t = it_add(1, 2)\n')
            with open(os.path.join(root, 'docs', 'swift-migration', 'helpers.md'), 'w') as f:
                f.write('it_add(a, b)\n')
        root = make_repo(mutate)
        calls = inv.Inventory(root).helper_call_counts()
        self.assertEqual(calls['calls'], 9)
        self.assertEqual(calls['files'], 2)
        self.assertEqual(calls['by_helper'], OrderedDict([
            ('it_add', 2), ('it_subtract', 1), ('it_multiply', 1), ('it_negate', 1), ('it_shiftLeft', 1),
            ('it_narrow', 2), ('it_floatToInteger', 1)]))
        code, out, err = run_cli(root, 'summary')
        self.assertEqual(code, 0, err)
        self.assertIn('  Checked-arithmetic helper calls (scaffolding, removed in stage two): 9 in 2 files '
                      '(it_add 2, it_subtract 1, it_multiply 1, it_negate 1, it_shiftLeft 1, it_narrow 2, '
                      'it_floatToInteger 1)\n', out)
        code, out, err = run_cli(root, '--json', 'summary')
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)['progress']['helper_calls']['calls'], 9)

    def test_missing_bridging_header_is_an_error(self):
        def mutate(root):
            os.remove(os.path.join(root, 'sources', 'iTerm2SharedARC-Bridging-Header.h'))
        code, out, err = run_cli(make_repo(mutate), 'summary')
        self.assertEqual(code, 2)
        self.assertIn('Bridging-Header', err)

    def test_xcconfig_is_read(self):
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F, X ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = a.m; sourceTree = "<group>"; }; '
            'X = { isa = PBXFileReference; path = base.xcconfig; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = Y; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( ); }; '
            'C1 = { isa = XCBuildConfiguration; baseConfigurationReference = X; buildSettings = { }; }; '
            '}; rootObject = P; }')
        membership, targets, _ = inv.compute_target_membership(
            plist, read_file=lambda path: 'CLANG_ENABLE_OBJC_ARC = YES\n' if path == 'base.xcconfig' else None)
        self.assertIs(targets['Y']['arc'], True)
        self.assertIn('xcconfig', targets['Y']['arc_source'])

    def test_unnamed_selector_keywords(self):
        self.assertEqual(inv.method_selector('- (NSData *)reportDECDSR:(int)code :(int)subcode'), 'reportDECDSR::')
        of = self.inv().objc_file('sources/Family.m')
        self.assertIn('report::', [m['selector'] for m in of.methods])

    def test_trailer_block_rules(self):
        # git reads trailers only in the final paragraph, and only when every line of it is a
        # trailer (or a known git trailer is present): one line with a Unicode dash voids the block.
        root = make_repo()
        commit_messages(root, [('2026-01-01',
                                'Swift-Port: Subject kind=test\n\nBody.\nSwift-Port: Middle kind=test\n\n'
                                'More body.\n\nSwift-Port: Foo kind=port\nSwift-Port: Foo kind=port\n'
                                'Swift-Porting: Bar kind=port\nX-Swift-Port: Baz kind=port\n'
                                'Swift\u2010Port: Qux kind=port')])
        units, problems = inv.history_from_git(root)
        self.assertEqual(units, {})
        self.assertEqual([p['problem'] for p in problems], [inv.TRAILER_NOT_READ] * 7)

    def test_more_hazards(self):
        src = ('[NSApp sendAction:@selector(x:) to:nil from:self];\n[self doesNotRecognizeSelector:_cmd];\n'
               '[x conformsToProtocol:@protocol(P)];\n- (NSScriptObjectSpecifier *)objectSpecifier { }\n'
               '+ (NSSet *)keyPathsForValuesAffectingFoo { }\n')
        h = inv.file_hazards(inv.mask_source(src))
        for k in ('sendAction', 'doesNotRecognizeSelector', 'conformsToProtocol', 'objectSpecifier',
                  'key-value coding/observing'):
            self.assertIn(k, h)

    def test_help_and_labels(self):
        code, out, err = run_cli(MiniRepo.path(), 'leaf', '--help')
        self.assertIn('Objective-C subclasses', out)
        self.assertIn('other targets', out)
        self.assertNotIn('module docstring', out)
        self.assertTrue(inv.is_hot_path('sources/CharacterSets/iTermCharacterWidth.c'))


class MacroClassUseTests(unittest.TestCase):
    def test_file_invoking_a_class_defining_macro_is_not_a_leaf_candidate(self):
        i = MiniRepo.inventory()
        paths = [r['path'] for r in i.leaf(max_fan_in=100, max_reach=1000)['candidates']]
        self.assertNotIn('sources/Nonnull.m', paths)
        self.assertTrue(any('DECLARE_GENERATED(Generated)' in w for w in i.warnings), i.warnings)


class PrefixHeaderTests(unittest.TestCase):
    """GCC_PREFIX_HEADER: every header the prefix header imports, directly or not, is imported by every
    file of the target. In the fixture, sources/Fixture.pch imports Buttons.h, which imports
    ButtonStyle.h; iTerm2Shared sets it in one of its two configurations and iTerm2SharedARC in both
    (once written with $(SRCROOT)). Those targets compile 38 in-scope implementation files: Foo.m,
    FooSub.m, Util.c and PSMThing.m, and 34 in iTerm2SharedARC."""

    def test_prefix_header_read_per_target(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.targets['iTerm2Shared']['prefix_headers'], ['sources/Fixture.pch'])
        self.assertEqual(i.targets['iTerm2Shared']['prefix_header_source'],
                         'GCC_PREFIX_HEADER set in 1 of 2 build configurations')
        self.assertEqual(i.targets['iTerm2SharedARC']['prefix_headers'], ['sources/Fixture.pch'])
        self.assertEqual(i.targets['iTerm2SharedARC']['prefix_header_source'],
                         'GCC_PREFIX_HEADER set in 2 of 2 build configurations')
        self.assertEqual(i.targets['pidinfo']['prefix_headers'], [])
        self.assertEqual(i.prefix_closure, {'sources/Fixture.pch': ['sources/ButtonStyle.h', 'sources/Buttons.h']})

    def test_fan_in_and_reach_through_the_prefix_header(self):
        i = MiniRepo.inventory()
        f = i.fan_in('sources/ButtonStyle.m')
        # Buttons.h and LocalGlobal.m import it by text; the other 36 of the 38 files of the two
        # targets, less ButtonStyle.m itself, import it only through the prefix header.
        self.assertEqual((f['importers'], f['header_importers'], f['reach']), (38, 1, 38))
        self.assertEqual(f['prefix_header'], {'via': ['sources/Fixture.pch'],
                                              'targets': ['iTerm2Shared', 'iTerm2SharedARC'],
                                              'importers_only_through_it': 36})
        f = i.fan_in('sources/Buttons.m')
        self.assertEqual((f['importers'], f['header_importers'], f['reach']), (37, 0, 37))
        self.assertIsNone(i.fan_in('sources/Base.m')['prefix_header'])

    def test_prefix_header_shown_in_every_view(self):
        root = MiniRepo.path()
        code, out, err = run_cli(root, 'file', 'ButtonStyle.m')
        self.assertEqual(code, 0, err)
        self.assertIn('of which 36 only through the prefix header sources/Fixture.pch (every file compiled by '
                      'iTerm2Shared, iTerm2SharedARC)', out)
        code, out, err = run_cli(root, 'files', '--filter', 'ButtonStyle')
        self.assertEqual(out.splitlines()[2].split()[4], '38(1h)/38p')
        self.assertIn('p: the count includes files that import the header only through a prefix header', out)
        code, out, err = run_cli(root, 'leaf', '--max-fan-in', '100', '--max-reach', '1000')
        row = [l for l in out.splitlines() if l.startswith('sources/ButtonStyle.m')][0]
        self.assertIn(' 38p ', row)
        self.assertIn('header imported through the prefix header sources/Fixture.pch', row)
        self.assertNotIn('nothing detected', row)
        self.assertEqual(MiniRepo.inventory().leaf()['outside_thresholds'],
                         {'direct fan-in above 2': 4, 'transitive reach above 10': 0})

    def test_prefix_header_from_project_configurations(self):
        # Set only at the project level, and written with ${PROJECT_DIR}: the target inherits it.
        plist = inv.parse_pbxproj(
            '{ objects = { P = { isa = PBXProject; buildConfigurationList = PL; mainGroup = G; '
            'targets = ( T ); }; G = { isa = PBXGroup; children = ( F ); sourceTree = "<group>"; }; '
            'F = { isa = PBXFileReference; path = a.m; sourceTree = "<group>"; }; '
            'B = { isa = PBXBuildFile; fileRef = F; }; S = { isa = PBXSourcesBuildPhase; files = ( B ); }; '
            'T = { isa = PBXNativeTarget; name = X; buildPhases = ( S ); buildConfigurationList = TL; }; '
            'TL = { isa = XCConfigurationList; buildConfigurations = ( C1 ); }; '
            'PL = { isa = XCConfigurationList; buildConfigurations = ( C2 ); }; '
            'C1 = { isa = XCBuildConfiguration; buildSettings = { }; }; '
            'C2 = { isa = XCBuildConfiguration; buildSettings = { GCC_PREFIX_HEADER = "${PROJECT_DIR}/src/P.pch"; }; }; '
            '}; rootObject = P; }')
        _, targets, _ = inv.compute_target_membership(plist)
        self.assertEqual(targets['X']['prefix_headers'], ['src/P.pch'])
        self.assertEqual(targets['X']['prefix_header_source'], 'GCC_PREFIX_HEADER set in 1 of 1 build configurations')

    def test_missing_prefix_header_is_an_error(self):
        def mutate(root):
            os.remove(os.path.join(root, 'sources', 'Fixture.pch'))
        code, out, err = run_cli(make_repo(mutate), 'summary')
        self.assertEqual(code, 2, err)
        self.assertIn('prefix header sources/Fixture.pch of target iTerm2Shared', err)
        self.assertEqual(out, '')


class CSymbolTests(unittest.TestCase):
    """Files that define non-static C functions or globals whose names appear in a header."""

    def test_symbols_found(self):
        i = MiniRepo.inventory()
        self.assertEqual([x['name'] for x in i.file_record('sources/Buttons.m')['c_symbols_in_headers']],
                         ['kFixtureButtonKey', 'FixtureLocalizedOK', 'gButtonsB', 'FixtureHandlerFor',
                          'FixtureOnlyExternInM'])  # in full in CSymbolCoverageTests
        # A function and a global that no header names, and statics, do not count.
        self.assertEqual(i.file_record('sources/LocalGlobal.m')['c_symbols_in_headers'], [])
        self.assertEqual(i.file_record('sources/Foo.m')['c_symbols_in_headers'], [])

    def test_deferred(self):
        lists = leaf_lists(MiniRepo.inventory().leaf())
        self.assertEqual(lists['defines C functions or globals declared in a header'],
                         {'sources/Util.c': ['function util (line 7), declared in sources/Util.h']})
        lists = leaf_lists(MiniRepo.inventory().leaf(max_fan_in=100, max_reach=1000))
        self.assertEqual(lists['defines C functions or globals declared in a header']['sources/Buttons.m'], [
            'global kFixtureButtonKey (line 3), declared in sources/Buttons.h',
            'function FixtureLocalizedOK (line 6), declared in sources/Buttons.h',
            'global gButtonsB (line 17), declared in sources/ButtonStyle.h',
            'function FixtureHandlerFor (line 19), declared in sources/ButtonStyle.h',
            'function FixtureOnlyExternInM (line 23), declared in ModernTests/OwnerTests.m'])
        self.assertEqual(inv.DEFERRED_LISTS['defines C functions or globals declared in a header'][1],
                         'interop.md')

    def test_declarations_that_are_not_definitions(self):
        src = ('extern int gDeclared;\nFOUNDATION_EXPORT NSString *const kExported;\nint Prototype(int x);\n'
               'typedef struct { int a; } Pair;\nstruct Named { int b; };\nenum { kA, kB };\n'
               'typedef NS_ENUM(NSInteger, Mode) { ModeA };\nvoid (*gHandler)(int) = 0;\n'
               'const CGFloat kWidth = 3;\n@interface X : NSObject\n- (void)m;\n@end\n'
               '@implementation X\nint gInImplementation;\n- (void)m {\n    int local = 0;\n}\n@end\n')
        of = inv.ObjCFile('x.m', src)
        self.assertEqual([(g['name'], g['line']) for g in of.globals],
                         [('gHandler', 8), ('kWidth', 9), ('gInImplementation', 14)])


class XibAndSdefTests(unittest.TestCase):
    def test_missing_sdef_is_an_error(self):
        def mutate(root):
            os.remove(os.path.join(root, 'iTerm2.sdef'))
        root = make_repo(mutate)
        for args in (['summary'], ['files'], ['file', 'Foo'], ['leaf']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 2, (args, err))
            self.assertIn('iTerm2.sdef not found', err)
            self.assertEqual(out, '')

    def test_unparsable_sdef_is_an_error(self):
        def mutate(root):
            with open(os.path.join(root, 'iTerm2.sdef'), 'w') as f:
                f.write('<dictionary><suite name="x">\n')
        code, out, err = run_cli(make_repo(mutate), 'leaf')
        self.assertEqual(code, 2, err)
        self.assertIn('iTerm2.sdef is not well-formed XML', err)
        self.assertEqual(out, '')

    def test_unparsable_xib_flags_every_class_it_may_name(self):
        i = MiniRepo.inventory()
        self.assertTrue(any(w.startswith('sources/Unparsable.xib is not well-formed XML') for w in i.warnings))
        self.assertEqual(i.file_record('sources/Lonely.m')['hazards'], {'xib customClass': 1, 'xib not parsed': 1})
        # Plain is named in the broken file, though not as a customClass that the text scan reads.
        self.assertEqual(i.file_record('sources/Plain.mm')['hazards'], {'xib not parsed': 1})
        rows = dict((r['path'], r) for r in i.leaf()['candidates'])
        self.assertEqual(rows['sources/Plain.mm']['address'], ['partially ported', 'no C++ at all', 'xib not parsed'])

    def test_unparsable_xib_listed_in_every_view(self):
        root = MiniRepo.path()
        for args in (['summary'], ['files'], ['file', 'Plain.mm'], ['leaf']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 0, (args, err))
            self.assertIn('Not established by this tool:', out, args)
            self.assertIn('1 xib files could not be parsed, so their connections and the classes they name were '
                          'not checked: sources/Unparsable.xib', out, args)
            data = json.loads(run_cli(root, '--json', *args)[1])
            self.assertEqual(data['not_established']['unparsed_xibs'], ['sources/Unparsable.xib'], args)


class NotCheckedTests(unittest.TestCase):
    def test_not_checked_in_leaf_and_file(self):
        root = MiniRepo.path()
        for args in (['leaf'], ['file', 'FooSub.m']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 0, err)
            self.assertIn('Not checked by this tool:\n', out, args)
            for line in inv.NOT_CHECKED:
                self.assertIn('  ' + line + '\n', out, args)
            data = json.loads(run_cli(root, '--json', *args)[1])
            self.assertEqual(data['not_checked'], list(inv.NOT_CHECKED), args)
        self.assertIn('entry-point census', inv.NOT_CHECKED[0])
        self.assertIn('Info.plist', inv.NOT_CHECKED[0])
        self.assertTrue(any('owner-queue.md' in line and 'stored-state corpus' in line for line in inv.NOT_CHECKED))
        self.assertTrue(any('hot-paths.md' in line for line in inv.NOT_CHECKED))
        self.assertTrue(any('claims.md' in line for line in inv.NOT_CHECKED))
        self.assertTrue(any('soaking' in line for line in inv.NOT_CHECKED))

    def test_no_overclaim(self):
        code, out, err = run_cli(MiniRepo.path(), 'leaf', '--help')
        self.assertNotIn('every hazard', out.replace('\n', ' '))
        code, out, err = run_cli(MiniRepo.path(), 'leaf')
        self.assertNotIn('every hazard', out)
        self.assertNotIn('every hazard', inv.__doc__.replace('\n', ' '))

    def test_dynamic_selector_sites(self):
        i = MiniRepo.inventory()
        self.assertEqual(len(i.dynamic_selector_sites), 32)  # listed in SelectorDispatchTests
        root = MiniRepo.path()
        for args in (['leaf'], ['file', 'FooSub.m']):
            out = run_cli(root, *args)[1]
            self.assertIn('32 sites in the tree dispatch or build a selector that this tool cannot see as a literal, so '
                          'any method could be reached from them; what they reach is not determined here (the '
                          'entry-point census, phase0.md section 2).\n', out, args)
            self.assertIn('2 calls create a class from a name known only at run time', out, args)
            data = json.loads(run_cli(root, '--json', *args)[1])
            self.assertEqual(len(data['not_established']['dynamic_selector_sites']), 32, args)
            self.assertEqual(data['not_established']['unresolved_class_name_sites'],
                             ['ModernTests/OwnerTests.m:10', 'sources/Plugin.m:30'], args)


class DeferralRuleTests(unittest.TestCase):
    def test_atomics_stay_in_c(self):
        lists = leaf_lists(MiniRepo.inventory().leaf())
        # <stdatomic.h>, _Atomic, atomic_fetch_add and OSAtomicIncrement32Barrier.
        self.assertEqual(lists['stays in C: atomics'], {'sources/Atomic.m': ['uses C atomics (4 matches)']})
        # Foo.h has more than two importers; with the limits raised, Foo.m is deferred for its atomics too.
        lists = leaf_lists(MiniRepo.inventory().leaf(max_fan_in=100, max_reach=1000))
        self.assertEqual(lists['stays in C: atomics']['sources/Foo.m'], ['uses C atomics (2 matches)'])
        self.assertEqual(inv.DEFERRED_LISTS['stays in C: atomics'][1], 'concurrency.md section 4')

    def test_categories_implemented_elsewhere(self):
        lists = leaf_lists(MiniRepo.inventory().leaf(max_fan_in=100, max_reach=1000))
        cats = lists['categories implemented in other files']
        self.assertEqual(cats, {
            'sources/Foo.m': ['Foo(Scripting) at sources/Foo+Scripting.m:3', 'Foo(Extras) at sources/FooSub.m:10'],
            'sources/Multi.m': ['Multi(Extra) at sources/Multi+Extra.m:3'],
            'sources/PluginImpl.m': ['Bystander(Fixture) at sources/iTermThing+Extra.m:8'],
            'sources/iTermThing.m': ['iTermThing(Extra) at sources/iTermThing+Extra.m:3']})

    def test_category_declared_only_is_shown_not_deferred(self):
        i = MiniRepo.inventory()
        rec = i.file_record('sources/Base.m')
        self.assertEqual(rec['categories_declared_only'], ['Base(Spying) at ModernTests/BarTests.m:21, outside scope'])
        rows = dict((r['path'], r) for r in i.leaf()['candidates'])
        self.assertEqual(rows['sources/Base.m']['address'], [
            'categories declared in other files with no implementation found (1, 1 outside scope)', 'Swift subclasses (1)'])
        foo = i.file_record('sources/Foo.m')
        self.assertEqual((foo['external_category_count'], foo['external_categories_outside_scope']), (4, 1))
        self.assertEqual(foo['categories_declared_only'], ['Foo(Testing) at ModernTests/BarTests.m:13, outside scope'])

    def test_giant_classes(self):
        lists = leaf_lists(MiniRepo.inventory().leaf())
        self.assertEqual(lists['giant classes'],
                         {'sources/PTYTab+Scripting.m': ['implements part of PTYTab (category Scripting)'],
                          'sources/PTYTextView.m': ['implements PTYTextView']})
        self.assertEqual(inv.DEFERRED_LISTS['giant classes'][1], 'large-code.md section 1')

    def test_concurrency_primitives_are_shown(self):
        rows = dict((r['path'], r) for r in MiniRepo.inventory().leaf()['candidates'])
        self.assertEqual(rows['sources/LocalGlobal.m']['address'], [
            'performSelector (4)', 'NSSelectorFromString (2)', 'NSInvocation', 'lock (2)', 'objc_msgSend (2)',
            'methodForSelector', 'selector registration', 'sendAction', 'block dispatched to a queue',
            'dynamic selector site (13)'])
        src = ('NSRecursiveLock *a; NSCondition *b; NSConditionLock *c; os_unfair_lock d = OS_UNFAIR_LOCK_INIT;\n'
               'os_unfair_lock_lock(&d); pthread_mutex_lock(&m); pthread_rwlock_rdlock(&r);\n'
               'dispatch_semaphore_t s = dispatch_semaphore_create(0); dispatch_semaphore_wait(s, 0);\n'
               'dispatch_sync(q, ^{}); dispatch_after(t, q, ^{}); [[NSOperationQueue mainQueue] addOperation:o];\n'
               'dispatch_barrier_async(q, ^{});\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual((h['lock'], h['dispatch semaphore'], h['block dispatched to a queue']), (7, 3, 4))


class ToolDirectoryExclusionTests(unittest.TestCase):
    """The fixture holds tools/swift_migration/Decoy.m (a subclass of FooSub, a marker, an ivar_ use and a
    selector built from a string) and tools/swift_migration/Decoy.xib (customClass FooSub). None of it
    may reach any result, as the real tool's own fixture repository must not."""

    def test_decoy_is_ignored(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.class_relations('FooSub')['objc_subclasses'], [])
        self.assertNotIn('FooSub', i.xib_classes)
        self.assertFalse(any(s.startswith('tools/') for s in i.dynamic_selector_sites))
        s = i.summary()
        self.assertEqual(s['progress']['markers']['SWIFT-MIGRATION-SHIM'], {'occurrences': 1, 'files': 1})
        self.assertEqual(s['progress']['ivar_accessor_uses'], 2)
        rows = dict((r['path'], r) for r in i.leaf()['candidates'])
        self.assertEqual(rows['sources/FooSub.m']['address'], [])
        self.assertEqual(inv.MARKER_EXCLUDED_PATHS, ('docs/swift-migration', 'tools/swift_migration'))


class SmallRuleTests(unittest.TestCase):
    def test_scripting_key_value_coding_overrides(self):
        for sel in ('valueWithUniqueID:inPropertyWithKey:', 'valueWithName:inPropertyWithKey:',
                    'valueAtIndex:inPropertyWithKey:', 'insertValue:inPropertyWithKey:',
                    'insertValue:atIndex:inPropertyWithKey:', 'removeValueAtIndex:fromPropertyWithKey:',
                    'replaceValueAtIndex:inPropertyWithKey:withValue:', 'coerceValue:forKey:',
                    'indicesOfObjectsByEvaluatingObjectSpecifier:'):
            self.assertTrue(inv._CONVENTION_SELECTOR.match(sel), sel)
        self.assertFalse(inv._CONVENTION_SELECTOR.match('indicesOfObjectsByEvaluatingObjectSpecifier'))

    def test_nsstringfromselector_of_a_literal_is_a_hazard(self):
        h = inv.file_hazards(inv.mask_source('NSString *k = NSStringFromSelector(@selector(title));\n'))
        self.assertEqual(h, {'NSStringFromSelector(@selector)': 1})

    def test_underscore_trailer_near_miss(self):
        root = make_repo()
        commit_messages(root, [('2026-01-01', 'Subject\n\nSwift_Port: Foo kind=port')])
        units, problems = inv.history_from_git(root)
        self.assertEqual(units, {})
        self.assertEqual(problems[0]['line'], 'Swift_Port: Foo kind=port')

    def test_summary_history_reliability_is_heuristic(self):
        self.assertEqual(inv.reliability_for('summary')['history']['reliability'], 'heuristic')
        self.assertEqual(inv.reliability_for('file')['history']['reliability'], 'exact')

    def test_codes_name_real_hazards(self):
        self.assertNotIn('runtime API', inv.HAZARD_CODES)

    def test_created_by_name_says_it_over_approximates(self):
        out = run_cli(MiniRepo.path(), 'file', 'PluginImpl.m')[1]
        self.assertIn('over-approximation', out)


class SelectorDispatchTests(unittest.TestCase):
    """Every call that dispatches a selector it does not see as an @selector or #selector literal."""

    def test_sites(self):
        self.assertEqual(MiniRepo.inventory().dynamic_selector_sites, [
            'ModernTests/OwnerTests.m:8: performSelector', 'ModernTests/OwnerTests.m:8: NSSelectorFromString',
            'sources/Concurrency.m:47: targetForAction', 'sources/Concurrency.m:48: performSelectorOnMainThread',
            'sources/Dynamic.swift:4: Selector', 'sources/Dynamic.swift:6: NSSelectorFromString',
            'sources/Dynamic.swift:14: perform', 'sources/Dynamic.swift:17: selector',
            # item.action = action, .perform( of a member access and item.doubleAction = action; #selector, nil
            # and an enum case on lines 22, 23 and 26 are not.
            'sources/Dynamic.swift:21: action =', 'sources/Dynamic.swift:24: perform',
            'sources/Dynamic.swift:25: doubleAction =',
            # sendAction(, tryToPerform( and perform( with a name as the first argument, target(forAction: and
            # action: with a name; lines 31, 34, 36, 38 and 39 pass #selector or nil, line 40 passes a label,
            # line 41 a closure, and line 44 declares a function named perform. In lines 47 to 51, action: and
            # selector: are followed by types or are inside #selector literals. Lines 54 to 57 pass nil, string
            # literals, an enum case, an array and capitalized names; lines 59 to 66 declare parameters named
            # action and selector.
            'sources/Dynamic.swift:30: sendAction', 'sources/Dynamic.swift:32: tryToPerform',
            'sources/Dynamic.swift:33: target(forAction:)', 'sources/Dynamic.swift:35: perform',
            'sources/Dynamic.swift:37: action:',
            # A parenthesized argument may be a selector.
            'sources/Dynamic.swift:69: action:',
            'sources/Foo.m:86: performSelector', 'sources/Foo.m:86: NSSelectorFromString',
            'sources/LocalGlobal.m:12: sel_getUid', 'sources/LocalGlobal.m:15: performSelector',
            'sources/LocalGlobal.m:21: it_performNonObjectReturningSelector',
            'sources/LocalGlobal.m:22: fixture_dispatch', 'sources/LocalGlobal.m:24: sendAction',
            'sources/LocalGlobal.m:25: methodForSelector', 'sources/LocalGlobal.m:26: setSelector',
            'sources/LocalGlobal.m:27: selector', 'sources/LocalGlobal.m:28: objc_msgSend',
            # A call to a SEL-taking C function found in scope, without a selector literal; the call on line 31
            # passes @selector(description) and is not a site.
            'sources/LocalGlobal.m:30: LocalHelper',
            # A selector variable assigned to an action, by dot syntax, setAction: and setDoubleAction:; line 34
            # assigns an @selector literal.
            'sources/LocalGlobal.m:33: action =', 'sources/LocalGlobal.m:35: setAction',
            'sources/LocalGlobal.m:36: setDoubleAction'])

    def test_wrappers_found_from_sel_parameters(self):
        i = MiniRepo.inventory()
        self.assertIn('fixture_dispatch', i.selector_wrapper_keywords)
        self.assertEqual(i.selector_wrapper_functions, ['LocalDispatch', 'LocalHelper'])

    def test_hazard_on_the_file(self):
        h = MiniRepo.inventory().file_record('sources/LocalGlobal.m')['hazards']
        self.assertEqual(h['performSelector'], 4)
        self.assertEqual(h['dynamic selector site'], 13)
        src = '[x it_performAutoreleasedObjectReturningSelector:s withObject:nil]; [a makeObjectsPerformSelector:s];\n'
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual((h['performSelector'], h['makeObjectsPerformSelector']), (1, 1))


class ClassNameScopeTests(unittest.TestCase):
    def test_sites_outside_scope(self):
        i = MiniRepo.inventory()
        self.assertEqual(i.unresolved_class_sites, ['ModernTests/OwnerTests.m:10', 'sources/Plugin.m:30'])
        self.assertEqual(i.file_record('sources/Mixed.mm', detail=True)['created_by_name'],
                         ['Mixed: created by name at ModernTests/OwnerTests.m:9'])


class ConcurrencyHazardTests(unittest.TestCase):
    def test_dispatch_family_and_state(self):
        h = MiniRepo.inventory().file_record('sources/Concurrency.m')['hazards']
        self.assertEqual(dict((k, h[k]) for k in ('block dispatched to a queue', 'dispatch group or once', 'volatile',
                                                  'thread-local storage', 'atomic property')),
                         {'block dispatched to a queue': 3, 'dispatch group or once': 4, 'volatile': 1,
                          'thread-local storage': 1, 'atomic property': 2})
        src = ('__thread int a; _Thread_local int b; pthread_key_create(&k, 0); pthread_getspecific(k);\n'
               'dispatch_io_read(ch, 0, 1, q, handler); dispatch_after(t, q, blk); dispatch_apply_f(n, q, c, f);\n'
               'dispatch_get_main_queue(); dispatch_time(0, 1);\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual((h['thread-local storage'], h['block dispatched to a queue']), (4, 3))
        # Any other dispatch_ call counts when a block literal is among its arguments.
        h = inv.file_hazards(inv.mask_source('dispatch_custom_thing(q, ^{ });\ndispatch_custom_thing(q, f);\n'))
        self.assertEqual(h['block dispatched to a queue'], 1)

    def test_queries_nil_and_macros_that_only_branch(self):
        rec = MiniRepo.inventory().file_record('sources/Concurrency.m')
        # gConcurrentSelf is declared extern only in Concurrency.m itself; CONCURRENT_CHECK branches but
        # defines no function; respondsToSelector: and fixture_dispatch:nil dispatch nothing.
        self.assertEqual(rec['c_symbols_in_headers'], [])
        self.assertNotIn('function-defining macro', rec['hazards'])
        self.assertEqual(rec['hazards']['dynamic selector site'], 2)


class CSymbolCoverageTests(unittest.TestCase):
    def test_other_declarations(self):
        rec = MiniRepo.inventory().file_record('sources/Buttons.m')
        self.assertEqual(rec['c_symbols_in_headers'], [
            {'kind': 'global', 'name': 'kFixtureButtonKey', 'line': 3, 'declared_in': ['sources/Buttons.h']},
            {'kind': 'function', 'name': 'FixtureLocalizedOK', 'line': 6, 'declared_in': ['sources/Buttons.h']},
            {'kind': 'global', 'name': 'gButtonsB', 'line': 17, 'declared_in': ['sources/ButtonStyle.h']},
            {'kind': 'function', 'name': 'FixtureHandlerFor', 'line': 19, 'declared_in': ['sources/ButtonStyle.h']},
            {'kind': 'function', 'name': 'FixtureOnlyExternInM', 'line': 23,
             'declared_in': ['ModernTests/OwnerTests.m']}])
        # FIXTURE_DEFINE_GETTER's body also returns.
        self.assertEqual(rec['hazards'], {'control flow in a macro': 1, 'function-defining macro': 1})
        self.assertTrue(any('through macros' in line for line in inv.NOT_CHECKED))
        self.assertTrue(any('nm' in line.split() for line in inv.NOT_CHECKED))


class LiteralConstantTests(unittest.TestCase):
    def test_not_checked_text(self):
        self.assertEqual(inv.NOT_CHECKED, (
            'Which methods or classes can be reached by name from other files is not determined here: selector '
            'strings, tables of selector names, the app\'s Info.plist entries (such as service handlers and the '
            'principal class) and reflective sites. That is the job of the entry-point census (phase0.md section 2).',
            'Whether the file is on a hot path outside the hot-path directories (performance.md section 2).',
            'hot-paths.md: whether the unit is already deferred there as a hot path.',
            'claims.md: whether the unit is already claimed, in progress or parked.',
            'Whether anything the file depends on is still soaking (workflow.md section 5).',
            'Blocks recorded in owner-queue.md are not checked, except that leaf defers the files in which the '
            'stored-state rules below find stored state (owner-queue.md Q7: units that encode or decode stored state '
            'are blocked until the stored-state corpus exists).',
            'C functions and globals defined or declared through macros (including names made by token pasting) are '
            'not seen by the C-symbol rule; a file that invokes a function-defining macro is flagged instead.',
            'Whether another object file references a file\'s C symbols: the authoritative check is nm on the built '
            'object files, which this tool does not run.',
            'Stored state is found by four rules, and file NAME gives the line, the text, the rule and the entry of '
            'every match: (1) direct API use: keyed archivers and coders, keyed coding, NSCoding, restorable-state '
            'methods, arrangements, property-list serialization, dictionaryWithContentsOfFile:, '
            'dictionaryWithContentsOfURL:, arrayWithContentsOfFile:, arrayWithContentsOfURL:, and writeToFile: or '
            'writeToURL: without an encoding: keyword, CFPreferences, writes '
            'to a receiver that is user defaults by its text, Core Data and SQLite; (2) a use of a class or helper on '
            'the named list of iTerm2\'s stored-state API (STORED_STATE_API in inventory.py, each entry with what it '
            'persists; iTermAdvancedSettingsModel counts only for setters, because reading an advanced setting gets a '
            'value the model has already decoded, and the two settings pane base classes count only through rules 3 '
            'and 4, because naming a pane stores nothing); (3) a typed keyed setter (setBool:, setInt:, setInteger:, '
            'setUnsignedInteger:, setFloat:, setDouble:, setString: or setObject: with forKey:) whose key is a KEY_ '
            'or k...Preference... constant, or such a setter or setObjectsFromDictionary: sent to self, super, '
            'weakSelf or strongSelf in a class whose superclass chain in scope reaches a listed class or a class that '
            'has such a setter with a constant key; (4) a class whose superclass chain in scope reaches a listed '
            'class. Nothing else is followed: a call to a method that stores state is not itself a match.',
            'Not detected: stored state reached through project methods and classes not on the named list, '
            'dictionaries built here and saved by another file (profile dictionaries built with KEY_ constants in '
            'literals or subscripts, status bar knob and trigger parameter dictionaries), writes through a variable '
            'the text does not tie to user defaults, key paths bound in xibs, and generic file and JSON I/O '
            '(stringWithContentsOf..., dataWithContentsOf..., initWithContentsOf..., createFileAtPath:contents:, '
            'NSFileHandle, fopen, NSJSONSerialization, and strings written with an encoding). Every dossier lists '
            'the unit\'s '
            'stored-state surfaces by reading (lifecycle.md section 1, step 2).',
            'Calls to block-dispatching wrappers are found by name only: a wrapper whose name is shorter than 8 '
            'characters, is shared with an in-scope method that does not dispatch its block, or is one of the common '
            'Cocoa block keywords completionHandler, completionBlock, usingBlock, withBlock, withReply, replyHandler, '
            'errorHandler, resultHandler and performBlock is not used, and a call through a block, a function '
            'pointer, a protocol the text cannot follow or a Swift method is not seen.',
            'Calls to methods and functions that wrap a lock, semaphore, atomic operation, @synchronized, forwarding, '
            'key-value observing, timer or class-from-name API are detected only for the wrappers named here: '
            'anything named for swizzling (swizzl), the associated-object wrappers (names containing AssociatedObject '
            'or AssociatedDictionary, and attachMetadata:toTexture: and metadataForTexture:), '
            'iTermUserDefaultsObserver, and iTerm2\'s concurrency classes and functions (iTermThread, '
            'iTermSynchronizedState, iTermMainThreadState, iTermCallback, iTermThreadChecker, iTermTaskQueue, '
            'iTermGCD, iTermMutationQueue, iTermLegacyAtomicMutableArrayOfWeakObjects, iTermPreciseTimersLock and the '
            'iTermAtomic functions). A call to any other wrapper, such as the iTermPreciseTimer functions, which use '
            'atomics, is not detected.',
            'Methods in the init family are not flagged as ownership-transferring, although hidden-callers.md section '
            '6 lists init with alloc, new, copy and mutableCopy: nearly every class has initializers, so the flag '
            'would be on every file, and a Swift initializer exposed to Objective-C keeps the init family\'s '
            'convention. An init method that returns an object other than self, or that is not an initializer, is '
            'found by reading.',
        ))

    def test_hot_path_dirs_and_kinds(self):
        self.assertEqual(inv.HOT_PATH_DIRS, (
            'sources/VT100/', 'sources/VT100Screen/', 'sources/LineBuffer/', 'sources/MetalRenderer/',
            'sources/Drawing/', 'sources/CharacterSets/', 'sources/ScreenChar/'))
        self.assertEqual(inv.KNOWN_KINDS, ('tool', 'dossier', 'test', 'annotate', 'arc', 'undynamic', 'extract', 'decxx',
                                           'explicit', 'port', 'fix', 'improve'))

    def test_optional_subcommands_turn_off_bytecode(self):
        saved = sys.dont_write_bytecode
        try:
            sys.dont_write_bytecode = False
            inv.optional_subcommands()
            self.assertTrue(sys.dont_write_bytecode)
        finally:
            sys.dont_write_bytecode = saved

    def test_not_established_json_carries_the_fixed_statements(self):
        ne = MiniRepo.inventory().not_established()
        self.assertEqual(ne['fixed_statements'], list(inv.NOT_ESTABLISHED_FIXED))
        out = run_cli(MiniRepo.path(), 'leaf')[1]
        for line in inv.NOT_ESTABLISHED_FIXED:
            self.assertIn('  ' + line + '\n', out)

    def test_citations(self):
        self.assertEqual(inv.DEFERRED_LISTS['must stay in Objective-C for now'][1],
                         'hidden-callers.md sections 2 and 5; translation-rules.md sections 3 and 5; lifecycle.md '
                         'section 2; concurrency.md section 5')
        out = run_cli(MiniRepo.path(), 'leaf', '--help')[1].replace('\n', ' ')
        self.assertIn('or says that no process rule covers it yet', ' '.join(out.split()))


class MoreHazardTests(unittest.TestCase):
    def test_ownership_family_goto_and_stringifying_macros(self):
        rec = MiniRepo.inventory().file_record('sources/Concurrency.m')
        self.assertEqual(rec['hazards']['ownership-transferring method name'], 3)  # +newThing, -copyState, -mutableCopyState
        self.assertEqual(rec['hazards']['goto'], 1)
        self.assertEqual(rec['hazards']['stringifying macro'], 1)

    def test_class_extension_in_another_header_is_shown(self):
        rows = dict((r['path'], r) for r in MiniRepo.inventory().leaf()['candidates'])
        self.assertIn('class extensions in other files (1)', rows['sources/Mixed.mm']['address'])


class HistoryFoldTests(unittest.TestCase):
    def test_folded_and_repeated_trailers(self):
        root = make_repo()
        commit_messages(root, [('2026-01-01', 'Subject\n\nSwift-Port: Fold\n kind=port\nSwift-Port: Twice kind=test\n'
                                              'Swift-Port: Twice kind=test')])
        units, problems = inv.history_from_git(root)
        self.assertEqual(sorted(units), ['Fold', 'Twice'])
        self.assertEqual([(p['problem'], p['line']) for p in problems], [
            ('counted, but not written exactly as Swift-Port: <unit> kind=<kind>', 'Swift-Port: Fold kind=port'),
            ('repeated in the same commit; counted once', 'Swift-Port: Twice kind=test')])


class StoredStateTests(unittest.TestCase):
    def test_hazard(self):
        src = ('NSData *d = [NSKeyedArchiver archivedDataWithRootObject:x requiringSecureCoding:YES error:nil];\n'
               'id y = [NSKeyedUnarchiver unarchivedObjectOfClass:c fromData:d error:nil];\n'
               '[NSPropertyListSerialization dataWithPropertyList:p format:f options:0 error:nil];\n'
               '- (void)encodeWithCoder:(NSCoder *)c { }\n'
               '[[NSUserDefaults standardUserDefaults] setObject:v forKey:k];\n'
               '[[iTermUserDefaults userDefaults] setBool:YES forKey:k];\n'
               '[[NSUserDefaults standardUserDefaults] objectForKey:k];\n')
        # Two matches on each of the first two lines (the class and the archiving keyword), on the fourth
        # (encodeWithCoder: and NSCoder) and on the sixth (iTermUserDefaults, on the named list, and the write to
        # user defaults); one on each of the third and fifth; a read does not count.
        self.assertEqual(inv.file_hazards(inv.mask_source(src))['stored state'], 10)

    def test_deferred(self):
        lists = leaf_lists(MiniRepo.inventory().leaf())
        self.assertEqual(lists['encodes or decodes stored state'],
                         {'sources/Concurrency.m': ['1 match; first at line 30: setInteger: (rule 1, user defaults '
                                                    'write)']})
        self.assertEqual(inv.DEFERRED_LISTS['encodes or decodes stored state'][1],
                         'stored-state.md; owner-queue.md Q7')
        rec = MiniRepo.inventory().file_record('sources/Concurrency.m', detail=True)
        self.assertEqual(rec['stored_state'], [
            {'line': 30, 'text': 'setInteger:', 'rule': 1, 'entry': 'user defaults write',
             'why': 'a set or remove message, or a property assignment, to a receiver that is user defaults by its '
                    'text'}])
        out = run_cli(MiniRepo.path(), 'file', 'Concurrency.m')[1]
        self.assertIn('    stored state at line 30: setInteger: (rule 1, user defaults write: a set or remove message, '
                      'or a property assignment, to a receiver that is user defaults by its text)\n', out)
        out = run_cli(MiniRepo.path(), 'leaf', '--deferred')[1]
        self.assertIn('    sources/Concurrency.m: 1 match; first at line 30: setInteger: (rule 1, user defaults write)\n',
                      out)


def stored_state_by_line(src):
    """{line: [(rule, entry), ...]} for the matches of rules 1, 2 and 3 that need no class information."""
    masked = inv.mask_source(src)
    lines = inv.LineIndex(masked)
    found = {}
    for m in inv.stored_state_matches(masked)[0]:
        found.setdefault(lines.line(m['offset']), []).append((m['rule'], m['entry']))
    return found


# Each line with the (rule, entry) of every match on it, in order, worked out by hand. No line depends on another.
STORED_STATE_LINES = [
    ('id a = [data it_unarchivedObjectOfClasses:@[ [NSDictionary class] ]];', [(2, 'NSData+iTerm archive helpers')]),
    ('NSData *b = [NSData it_dataWithArchivedObject:dict];', [(2, 'NSData+iTerm archive helpers')]),
    ('id c = [data it_unarchivedObjectOfBasicClassesWithError:&error];', [(2, 'NSData+iTerm archive helpers')]),
    ('NSData *s = [NSData it_dataWithSecurelyArchivedObject:o error:nil];', [(2, 'NSData+iTerm archive helpers')]),
    ('- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder {',
     [(1, 'archiving or coder keyword'), (2, 'iTermGraphEncoder')]),
    ('[coder encodeObject:x forKey:@"k"];', [(1, 'keyed coding')]),
    ('x = [coder decodeObjectOfClass:[A class] forKey:@"k"];', [(1, 'keyed coding')]),
    ('n = [coder decodeIntegerForKey:@"n"];', [(1, 'keyed coding')]),
    ('NSKeyedUnarchiver *u = nil;', [(1, 'keyed archiver')]),
    ('id p = NSPropertyListSerialization.class;', [(1, 'property list serialization')]),
    ('@interface X : NSObject<NSSecureCoding>', [(1, 'NSCoding')]),
    ('NSCoder *coder2 = nil;', [(1, 'NSCoder')]),
    ('- (NSDictionary *)restorableState {', [(1, 'restorable state')]),
    ('[view restoreFromState:state];', [(1, 'restorable state')]),
    ('[window invalidateRestorableState];', [(1, 'restorable state')]),
    ('window.restorationClass = [X class];', [(1, 'restorable state')]),
    ('[window setRestorable:NO];', [(1, 'restorable state')]),
    ('[self restoreState:s];', [(1, 'restorable state')]),
    ('[w encodeRestorableStateIfNeeded];', [(1, 'restorable state')]),
    ('[NSApp restoreWindowWithIdentifier:i state:s completionHandler:h];', [(1, 'restorable state')]),
    ('NSArray *a2 = [NSArray arrayWithContentsOfURL:u];', [(1, 'file read or written whole')]),
    ('[x copyItem:y writeToFile:p atomically:YES];', [(1, 'file read or written whole')]),
    ('[d writeToFile:[p stringByAppendingString:[self name:a encoding:e]] atomically:YES];',
     [(1, 'file read or written whole')]),
    ('NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];', [(1, 'file read or written whole')]),
    ('[d writeToFile:p atomically:YES];', [(1, 'file read or written whole')]),
    ('[d writeToURL:[f URLByAppendingPathComponent:[x encoding]] atomically:YES];', [(1, 'file read or written whole')]),
    ('WRITE([d writeToFile:p atomically:YES]);', [(1, 'file read or written whole')]),
    ('CFPreferencesSetAppValue(k, v, app);', [(1, 'CFPreferences')]),
    ('NSArray *w = [self savedArrangementNames];', [(1, 'arrangement')]),
    ('[self readWithDecoder:d];', [(1, 'archiving or coder keyword')]),
    ('[self.userDefaults setBool:YES forKey:k];', [(1, 'user defaults write')]),
    ('self.userDefaults.mode = 2;', [(1, 'user defaults write')]),
    ('NSManagedObjectContext *moc = nil;', [(1, 'Core Data')]),
    ('id e2 = [NSEntityDescription insertNewObjectForEntityForName:n inManagedObjectContext:moc];',
     [(1, 'Core Data')]),
    ('NSFetchRequest *r = nil;', [(1, 'Core Data')]),
    ('NSPersistentContainer *pc = nil;', [(1, 'Core Data')]),
    ('sqlite3_open(path, &db);', [(1, 'SQLite')]),
    ('sqlite3 *db2 = NULL;', [(1, 'SQLite')]),
    ('[iTermPreferences setInt:3 forKey:k];', [(2, 'iTermPreferences')]),
    ('BOOL b2 = [iTermPreferences boolForKey:k];', [(2, 'iTermPreferences')]),
    ('[iTermUserDefaults setGlobalSearchMode:2];', [(2, 'iTermUserDefaults'), (1, 'user defaults write')]),
    # The dot write and the reference start at the same place; the named entry is reported.
    ('iTermUserDefaults.searchHistory = q;', [(2, 'iTermUserDefaults')]),
    ('[iTermAdvancedSettingsModel setNoSyncFoo:YES];', [(2, 'iTermAdvancedSettingsModel')]),
    ('iTermAdvancedSettingsModel.foo = 1;', [(2, 'iTermAdvancedSettingsModel')]),
    ('[iTermProfilePreferences setObject:v forKey:k inProfile:p model:m];', [(2, 'iTermProfilePreferences')]),
    ('[iTermWarning setIdentifier:k isSilenced:YES];', [(2, 'iTermWarning silencing')]),
    ('BOOL q2 = [iTermWarning identifierIsSilenced:k];', [(2, 'iTermWarning silencing')]),
    ('[iTermWarning unsilenceIdentifier:k];', [(2, 'iTermWarning silencing')]),
    ('iTermWarning.showRememberedAlerts = YES;', [(2, 'iTermWarning silencing')]),
    ('[ITAddressBookMgr setDefaultsInBookmark:d];', [(2, 'ITAddressBookMgr writes')]),
    ('NSColor *c2 = [ITAddressBookMgr decodeColor:plist];', [(2, 'ITAddressBookMgr writes')]),
    ('ProfileModel *m = [ProfileModel sharedInstance];', [(2, 'ProfileModel'), (2, 'ProfileModel')]),
    ('[self.model setBool:YES forKey:KEY_FIXTURE];', [(3, 'key KEY_FIXTURE')]),
    ('[x setObject:v forKey:kPreferenceKeyFixture];', [(3, 'key kPreferenceKeyFixture')]),
    ('[x setString:[y name] forKey:KEY_NAME inProfile:p];', [(3, 'key KEY_NAME')]),
    ('[x setUnsignedInteger:(1 + 2) forKey:kPhonyPreferenceKeyFixture];', [(3, 'key kPhonyPreferenceKeyFixture')]),
    ('[x setInt:1 forKey:KEY_A]; [x setInteger:1 forKey:KEY_B]; [x setFloat:1 forKey:KEY_C];',
     [(3, 'key KEY_A'), (3, 'key KEY_B'), (3, 'key KEY_C')]),
    ('[x setDouble:1 forKey:KEY_D];', [(3, 'key KEY_D')]),
    # Not in a message at all.
    ('y setBool:1 forKey:KEY_GG ', []),
    ('[x setInt:1 forKey:KEY_E];', [(3, 'key KEY_E')]),
    # None of these counts: a string written with an encoding, Metal encoders, a dictionary or a constant that is
    # not a preference key, reads, a longer class name, a property that only shares a name with iTermWarning's
    # silencing, a warning shown without silencing, a send to self that needs class information, a forward
    # declaration, an import, a key that is a property of a constant, and a remove.
    ('[s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];', []),
    ('[s writeToURL:[f URLByAppendingPathComponent:@"x"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];', []),
    ('id e = [self renderEncoder:pass];', []),
    ('[self updateRenderEncoderWithDescriptor:d];', []),
    ('[dict setObject:v forKey:k];', []),
    ('[dict setObject:v forKey:kFixtureKey];', []),
    ('[[NSUserDefaults standardUserDefaults] boolForKey:k];', []),
    ('BOOL f = iTermUserDefaultsX.searchHistory == nil;', []),
    ('[iTermAdvancedSettingsModel useFixture];', []),
    ('BOOL g = iTermAdvancedSettingsModel.foo == 1;', []),
    ('id t = iTermPreferencesModel.title;', []),
    ('x.identifier = y;', []),
    ('[iTermWarning showWarningWithTitle:t actions:a identifier:@"k" silenceable:kiTermWarningTypePermanentlySilenceable '
     'window:nil];', []),
    ('[self setObject:v forKey:key];', []),
    ('@class iTermPreferences;', []),
    ('#import <iTermPreferences.h>', []),
    ('[x setObject:v forKey:KEY_A.lowercaseString];', []),
    ('[x removeObjectForKey:KEY_NAME];', []),
    ('x = [iTermAdvancedSettingsModel valueForKey:k];', []),
    ('[x setObject:v forKey:keyPreferenceThing];', []),
    ('[x setObject:[d valueForX:a forKey:KEY_Z inY:b] forKey:k];', []),
    ('[x applyTo:y setBool:YES forKey:KEY_F];', []),
    ('[x copyItem:y writeToFile:p atomically:YES encoding:e error:nil];', []),
    ('[self.userDefaults objectForKey:k];', []),
    ('[obj applyTo:userDefaults setFlag:YES];', []),
    ('- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container {', []),
    ('WITH_TARGET(userDefaults setFlag:YES);', []),
]


class StoredStateRuleTests(unittest.TestCase):
    """Rules 1, 2 and 3 for the forms that need no class information, line by line."""

    def test_each_line_alone(self):
        for line, expected in STORED_STATE_LINES:
            found = stored_state_by_line(line)
            self.assertEqual(found.get(1, []), expected, line)

    def test_all_lines_together(self):
        src = '\n'.join(line for line, _ in STORED_STATE_LINES) + '\n'
        found = stored_state_by_line(src)
        expected = dict((n, e) for n, (_, e) in enumerate(STORED_STATE_LINES, 1) if e)
        self.assertEqual(found, expected)
        self.assertEqual(inv.file_hazards(inv.mask_source(src))['stored state'],
                         sum(len(e) for _, e in STORED_STATE_LINES))
        self.assertEqual(len(inv.stored_state_sites(inv.mask_source(src))), sum(len(e) for _, e in STORED_STATE_LINES))

    def test_writes_through_a_variable(self):
        # The second line of each depends on the declaration on the first.
        for snippet, expected in (
                ('NSUserDefaults *ud = X();\n[ud removeObjectForKey:k];', {2: [(1, 'user defaults write')]}),
                ('NSUserDefaults *const cd = X();\n[cd setObject:v forKey:k];', {2: [(1, 'user defaults write')]}),
                ('id prefs = [NSUserDefaults standardUserDefaults];\n[prefs setInteger:1 forKey:k];',
                 {2: [(1, 'user defaults write')]}),
                ('id store = [iTermUserDefaults userDefaults];\n[store setBool:YES forKey:k];',
                 {1: [(2, 'iTermUserDefaults')], 2: [(1, 'user defaults write')]}),
                ('NSUserDefaults *ud = X();\n[ud removePersistentDomainForName:n];', {2: [(1, 'user defaults write')]}),
                ('NSUserDefaults *ud = X();\n[ud objectForKey:k];', {})):
            self.assertEqual(stored_state_by_line(snippet), expected, snippet)

    def test_text_and_why(self):
        def first(src):
            m = inv.stored_state_matches(inv.mask_source(src))[0][0]
            return m['text'], m['why']
        self.assertEqual(first('[iTermAdvancedSettingsModel setNoSyncFoo:YES];'),
                         ('iTermAdvancedSettingsModel setNoSyncFoo:',
                          'advanced settings, kept in user defaults (only setters count: reading an advanced setting '
                          'gets a value the model has already decoded)'))
        self.assertEqual(first('[iTermWarning setIdentifier:k isSilenced:YES];'),
                         ('iTermWarning setIdentifier', 'remembered answers to warnings, kept in user defaults'))
        self.assertEqual(first('[x setFloat:1 forKey:KEY_C];'),
                         ('setFloat:', 'a typed keyed setter whose key is a profile or preference key constant'))
        self.assertEqual(first('x = [coder decodeObjectOfClass:[A class] forKey:@"k"];'),
                         ('decodeObjectOfClass:[A class] forKey:', 'encodes or decodes a value by key'))
        self.assertEqual(first('id a = [d it_unarchivedObjectOfClasses:c];'), ('it_unarchivedObjectOfClasses:', 'keyed archives'))
        self.assertEqual(first('iTermGraphDatabase *g;'),
                         ('iTermGraphDatabase', 'the restoration graph, saved in an SQLite database'))
        self.assertEqual(first('self.userDefaults.mode = 2;')[0], 'userDefaults.mode =')

    def test_self_sends_wait_for_class_information(self):
        masked = inv.mask_source('[self setObject:v forKey:key];\n[super setBool:YES forKey:self.key];\n'
                                 '[self setObjectsFromDictionary:d];\n[other setObject:v forKey:key];\n'
                                 '[self setValue:v forKey:key];\n[self setString:s];\n[self setInt:1 forKey:KEY_A];\n')
        matches, self_sends = inv.stored_state_matches(masked)
        lines = inv.LineIndex(masked)
        self.assertEqual([(lines.line(s['offset']), s['text'], s['receiver']) for s in self_sends],
                         [(1, 'setObject:', 'self'), (2, 'setBool:', 'super'), (3, 'setObjectsFromDictionary:', 'self')])
        # A constant key needs no class information.
        self.assertEqual([(lines.line(m['offset']), m['rule']) for m in matches], [(7, 3)])

    def test_named_list(self):
        self.assertEqual([(name, kind) for name, kind, _, _ in inv.STORED_STATE_API], [
            ('iTermPreferences', 'class'), ('iTermProfilePreferences', 'class'), ('iTermUserDefaults', 'class'),
            ('iTermAdvancedSettingsModel', 'setter'), ('iTermRemotePreferences', 'class'),
            ('iTermSecureUserDefaults', 'class'), ('iTermPersistentRateLimitedUpdate', 'class'),
            ('iTermPreferencesBaseViewController', 'base'), ('iTermProfilePreferencesBaseViewController', 'base'),
            ('iTermWarning silencing', 'message'), ('NSData+iTerm archive helpers', 'keyword'),
            ('iTermGraphEncoder', 'class'), ('iTermGraphDeltaEncoder', 'class'), ('iTermEncoderGraphRecord', 'class'),
            ('iTermGraphDatabase', 'class'), ('iTermGraphTableTransformer', 'class'), ('iTermEncoderAdapter', 'class'),
            ('iTermGraphEncoderAdapter', 'class'), ('iTermMutableDictionaryEncoderAdapter', 'class'),
            ('iTermGraphCodable', 'class'), ('iTermGraphEncodable', 'class'), ('iTermDatabase', 'class'),
            ('iTermDatabaseResultSet', 'class'), ('iTermSqliteDatabaseImpl', 'class'), ('FMDatabase', 'class'),
            ('FMResultSet', 'class'), ('iTermRestorableStateController', 'class'),
            ('iTermRestorableStateDriver', 'class'), ('iTermRestorableStateRecord', 'class'),
            ('iTermRestorableStateRestorer', 'class'), ('iTermRestorableStateSaver', 'class'),
            ('iTermRestorableStateSQLite', 'class'), ('iTermRestorableStateSaving', 'class'),
            ('iTermRestorableStateRestoring', 'class'), ('iTermRestorableStateIndex', 'class'),
            ('iTermRestorableWindowController', 'class'), ('PseudoTerminalRestorer', 'class'),
            ('iTermRestorableSession', 'class'), ('ProfileModel', 'class'), ('ITAddressBookMgr writes', 'message'),
            ('iTermProfileModelJournalModel', 'class'), ('iTermProfileModelJournalParams', 'class'),
            ('BookmarkJournalEntry', 'class'), ('iTermDynamicProfileManager', 'class'),
            ('iTermSnippetsModel', 'class'), ('iTermActionsModel', 'class'), ('iTermShellHistoryController', 'class'), ('iTermCommandHistoryEntryMO', 'class'),
            ('iTermCommandHistoryCommandUseMO', 'class'), ('iTermHostRecordMO', 'class'),
            ('iTermRecentDirectoryMO', 'class')])
        words = dict((name, words) for name, _, words, _ in inv.STORED_STATE_API if words)
        self.assertEqual(words, {
            'iTermWarning silencing': ('iTermWarning', 'unsilenceIdentifier', 'setIdentifier', 'identifierIsSilenced',
                                       'silenceEpisodeTokenForIdentifier', 'clearSavedSelectionForIdentifier',
                                       'conditionalSavedSelectionForIdentifier', 'setShowRememberedAlerts',
                                       'showRememberedAlerts'),
            'NSData+iTerm archive helpers': ('it_dataWithArchivedObject', 'it_dataWithSecurelyArchivedObject',
                                             'it_unarchivedObjectOfClasses', 'it_unarchivedObjectOfBasicClassesWithError'),
            'ITAddressBookMgr writes': ('ITAddressBookMgr', 'encodeColor', 'decodeColor', 'setDefaultsInBookmark',
                                        'removeProfile')})
        self.assertTrue(all(persists for _, _, _, persists in inv.STORED_STATE_API))

    def test_each_entry_matches(self):
        for name, kind, words, _ in inv.STORED_STATE_API:
            if kind == 'class':
                self.assertEqual(stored_state_by_line('%s *x = nil;' % name), {1: [(2, name)]}, name)
                self.assertEqual(stored_state_by_line('id<%s> y = (%s *)z;' % (name, name)), {1: [(2, name), (2, name)]})
                self.assertEqual(stored_state_by_line('%sX *x; X%s *y;' % (name, name)), {}, name)
            elif kind == 'base':
                # Only being one, or sending a setter to self in a subclass of one, counts (rules 3 and 4).
                self.assertEqual(stored_state_by_line('%s *x = nil;' % name), {}, name)
            elif kind == 'message':
                for word in words[1:]:
                    self.assertEqual(stored_state_by_line('[%s %s:x];' % (words[0], word)), {1: [(2, name)]}, word)
                    self.assertEqual(stored_state_by_line('[other %s:x];' % word), {}, word)
                    self.assertEqual(stored_state_by_line('[%s %sX:x];' % (words[0], word)), {}, word)
                self.assertEqual(stored_state_by_line('[%s somethingElse:x];' % words[0]), {}, name)
            elif kind == 'keyword':
                for word in words:
                    self.assertEqual(stored_state_by_line('id v = [x %s:y];' % word), {1: [(2, name)]}, word)
                    # A longer keyword is not the helper, though rule 1 still sees archiving in it.
                    self.assertEqual(stored_state_by_line('id v = [x %sX:y];' % word),
                                     {1: [(1, 'archiving or coder keyword')]}, word)
                    self.assertEqual(stored_state_by_line('id v = x.%s;' % word), {}, word)
                    self.assertEqual(stored_state_by_line('id v = [x X%s:y];' % word),
                                     {1: [(1, 'archiving or coder keyword')]}, word)


STORE_BASE_M = """#import "StoreBase.h"

@implementation StoreBase

- (void)reset {
    [self setBool:NO forKey:KEY_FIXTURE_FLAG];
}

@end
"""

STORE_SUB_M = """#import "FooSub.h"

@implementation FooSub

- (void)setName:(NSString *)name {
    [self setObject:name forKey:@"name"];
}

@end

@implementation Foo (Extras)
- (void)extra {
    [self setObject:nil forKey:@"x"];
}
@end
"""

STORE_DEEP_M = """#import "FooSub.h"

@interface DeepSub : FooSub
@end

@implementation DeepSub

- (void)apply:(NSString *)key value:(id)v other:(id)other {
    [super setInt:1 forKey:self.key];
    [weakSelf setFloat:2 forKey:key];
    [strongSelf setDouble:2 forKey:key];
    [other setObject:v forKey:key];
    [self setValue:v forKey:key];
    [self setObjectsFromDictionary:v];
    [self setString:v];
}

@end

@interface Plain2 : NSObject
@end

@implementation Plain2

- (void)apply:(NSString *)key value:(id)v {
    [self setObject:v forKey:key];
}

@end

@interface Plain3 : NSObject
@end
@interface Plain4 : Plain3
@end

@implementation Plain3
- (void)load2 {
    ProfileModel *m = nil;
}
@end

@implementation Plain4
- (void)save:(id)v {
    [self setObject:v forKey:@"k"];
}
@end
"""

PANE_H = """@interface iTermProfilePreferencesBaseViewController : NSViewController
@end
@interface FixturePane : iTermProfilePreferencesBaseViewController
@end
@interface FixtureDeepPane : FixturePane
@end
"""

PANE_M = """#import "Pane.h"

@implementation FixturePane
- (void)changed:(NSString *)key {
    [self setFloat:1 forKey:key];
}
@end

@implementation FixtureDeepPane
@end

@interface FixtureLocalPane : FixturePane
@end

@implementation FixturePane (Extra)
@end
"""

WHY_SELF_SEND = ('a typed keyed setter or setObjectsFromDictionary: sent to self or super in a subclass of a class on '
                 'the named list or of a class with a typed keyed setter whose key is a constant')
WHY_PANE = 'a subclass of a class on the named list (a profile settings pane; its setters write the profile)'


def inheritance_repo():
    def mutate(root):
        files = {'sources/StoreBase.h': '@interface StoreBase : NSObject\n@end\n', 'sources/StoreBase.m': STORE_BASE_M,
                 'sources/FooSub.h': '#import "Foo.h"\n#import "StoreBase.h"\n\n@interface FooSub : StoreBase\n@end\n\n'
                                     '@interface Foo (Extras)\n- (void)extra;\n@end\n',
                 'sources/FooSub.m': STORE_SUB_M, 'sources/Deep.m': STORE_DEEP_M, 'sources/Pane.h': PANE_H,
                 'sources/Pane.m': PANE_M}
        for path, text in files.items():
            with open(os.path.join(root, path), 'w') as f:
                f.write(text)
    return make_repo(mutate)


class StoredStateInheritanceTests(unittest.TestCase):
    """Rule 3 for sends to self and super, and rule 4."""

    @classmethod
    def setUpClass(cls):
        cls.root = inheritance_repo()
        cls.inv = inv.Inventory(cls.root)

    def stored(self, path):
        return self.inv.file_record(path, detail=True)['stored_state']

    def test_constant_key_flags_the_class(self):
        self.assertEqual(self.stored('sources/StoreBase.m'), [
            {'line': 6, 'text': 'setBool:', 'rule': 3, 'entry': 'key KEY_FIXTURE_FLAG',
             'why': 'a typed keyed setter whose key is a profile or preference key constant'}])

    def test_self_in_a_subclass_of_a_flagged_class(self):
        # Foo (Extras) is a category on Foo, whose superclass is NSObject: line 13 does not count.
        self.assertEqual(self.stored('sources/FooSub.m'), [
            {'line': 6, 'text': 'setObject:', 'rule': 3,
             'entry': 'self in FooSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6)',
             'why': WHY_SELF_SEND}])
        self.assertEqual(self.stored('sources/Deep.m'), [
            {'line': 9, 'text': 'setInt:', 'rule': 3,
             'entry': 'super in DeepSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6)',
             'why': WHY_SELF_SEND},
            {'line': 10, 'text': 'setFloat:', 'rule': 3,
             'entry': 'weakSelf in DeepSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6)',
             'why': WHY_SELF_SEND},
            {'line': 11, 'text': 'setDouble:', 'rule': 3,
             'entry': 'strongSelf in DeepSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6)',
             'why': WHY_SELF_SEND},
            {'line': 14, 'text': 'setObjectsFromDictionary:', 'rule': 3,
             'entry': 'self in DeepSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6)',
             'why': WHY_SELF_SEND},
            # Plain3 has a rule 2 match but no typed keyed setter, so line 44 in its subclass does not count.
            {'line': 38, 'text': 'ProfileModel', 'rule': 2, 'entry': 'ProfileModel',
             'why': 'the profiles, saved in user defaults'}])

    def test_subclass_of_a_listed_class(self):
        self.assertEqual(self.stored('sources/Pane.m'), [
            {'line': 3, 'text': '@implementation FixturePane', 'rule': 4,
             'entry': 'superclass iTermProfilePreferencesBaseViewController', 'why': WHY_PANE},
            {'line': 5, 'text': 'setFloat:', 'rule': 3,
             'entry': 'self in FixturePane, which inherits from iTermProfilePreferencesBaseViewController (named list)',
             'why': WHY_SELF_SEND},
            {'line': 9, 'text': '@implementation FixtureDeepPane', 'rule': 4,
             'entry': 'superclass iTermProfilePreferencesBaseViewController through FixturePane', 'why': WHY_PANE}])
        self.assertEqual(self.inv.file_record('sources/Pane.m')['hazards']['stored state'], 3)

    def test_leaf_defers_with_the_first_reason(self):
        result = self.inv.leaf()
        self.assertNotIn('sources/FooSub.m', [r['path'] for r in result['candidates']])
        self.assertEqual(leaf_lists(result)['encodes or decodes stored state']['sources/FooSub.m'], [
            '1 match; first at line 6: setObject: (rule 3, self in FooSub, which inherits from StoreBase (rule 3 at '
            'sources/StoreBase.m:6))'])
        out = run_cli(self.root, 'file', 'Deep.m')[1]
        self.assertIn('  leaf: not offered, whatever its fan-in and reach:\n', out)
        self.assertIn('    encodes or decodes stored state: 5 matches; first at line 9: setInt: (rule 3, super in '
                      'DeepSub, which inherits from StoreBase (rule 3 at sources/StoreBase.m:6))', out)
        self.assertIn('    stored state at line 14: setObjectsFromDictionary: (rule 3, self in DeepSub, which inherits '
                      'from StoreBase (rule 3 at sources/StoreBase.m:6): %s)\n' % WHY_SELF_SEND, out)
        data = json.loads(run_cli(self.root, '--json', 'file', 'Pane.m')[1])
        self.assertEqual([(m['line'], m['rule']) for m in data['stored_state']], [(3, 4), (5, 3), (9, 4)])


WORKER_M = """#import <Foundation/Foundation.h>

@implementation FixtureWorker

- (void)performLater:(void (^)(void))block {
    dispatch_async(dispatch_get_main_queue(), block);
}

- (void)performLaterTwice:(void (^)(void))block {
    [self performLater:block];
}

- (void)performLaterThrice:(void (^)(void))block {
    [self performLaterTwice:block];
}

- (void)completionHandler:(void (^)(void))block {
    dispatch_async(dispatch_get_main_queue(), block);
}

@end

void FixtureRunLater(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), block);
}
"""

# Replaces sources/Multi+Extra.m, which iTerm2SharedARC compiles and leaf offers with nothing detected.
WRAPPER_CALLS_M = """#import "Multi.h"

@implementation Multi (Extra)

- (void)extraWork {
    [self.worker performLaterThrice:^{
    }];
    [self.worker performLater:^{
    }];
    [self.session completionHandler:^{ }];
    FixtureRunLater(^{ });
}

@end
"""


def wrapper_repo(extra=None):
    def mutate(root):
        files = {'sources/Worker.m': WORKER_M, 'sources/Multi+Extra.m': WRAPPER_CALLS_M}
        files.update(extra or {})
        for path, text in files.items():
            with open(os.path.join(root, path), 'w') as f:
                f.write(text)
    return make_repo(mutate)


class WrapperDiscoveryTests(unittest.TestCase):
    """Methods and functions that dispatch a block parameter, and the calls to them."""

    @classmethod
    def setUpClass(cls):
        cls.root = wrapper_repo()
        cls.inv = inv.Inventory(cls.root)

    def test_wrappers_found(self):
        # Concurrency.m's run:queue:source:handler: dispatches its handler, but run and handler are too short;
        # completionHandler is a common Cocoa keyword and is never used.
        w = self.inv.hazard_wrappers.as_dict()
        self.assertEqual(w['block_dispatch'], {'keywords': ['performLater', 'performLaterThrice', 'performLaterTwice'],
                                               'functions': ['FixtureRunLater'], 'passes': 3, 'max_passes': 60})
        # performLater: and FixtureRunLater first; then performLaterTwice:, which calls performLater:; then
        # performLaterThrice:; then nothing new.
        self.assertEqual(self.inv.wrapper_passes, 3)
        self.assertEqual(self.inv.warnings, [w for w in self.inv.warnings if 'wrappers' not in w])

    def test_calls_are_hazards_and_name_the_wrapper(self):
        rec = self.inv.file_record('sources/Multi+Extra.m', detail=True)
        self.assertEqual(rec['hazards'], {'block dispatched to a queue': 3})
        self.assertEqual(rec['hazard_lines'], {'block dispatched to a queue': [6, 8, 11]})
        self.assertEqual(rec['dispatch_wrapper_calls'], [
            {'line': 6, 'wrapper': 'performLaterThrice:', 'defined_at': '-[FixtureWorker performLaterThrice:] at '
                                                                        'sources/Worker.m:13'},
            {'line': 8, 'wrapper': 'performLater:', 'defined_at': '-[FixtureWorker performLater:] at sources/Worker.m:5'},
            {'line': 11, 'wrapper': 'FixtureRunLater()', 'defined_at': 'FixtureRunLater() at sources/Worker.m:23'}])
        self.assertEqual(self.inv.deferral_reasons(rec), {})
        code, out, err = run_cli(self.root, 'file', 'Multi+Extra.m')
        self.assertEqual(code, 0, err)
        self.assertIn('    block dispatched to a queue      3  (lines 6, 8, 11)\n', out)
        self.assertIn('    block dispatched through a wrapper at line 6: performLaterThrice: (-[FixtureWorker '
                      'performLaterThrice:] at sources/Worker.m:13)\n', out)

    def test_pass_limit_warns(self):
        saved = inv.Inventory.WRAPPER_MAX_PASSES
        try:
            inv.Inventory.WRAPPER_MAX_PASSES = 2
            i = inv.Inventory(self.root)
        finally:
            inv.Inventory.WRAPPER_MAX_PASSES = saved
        self.assertEqual(i.wrapper_passes, 2)
        self.assertIn('the search for block-dispatching wrappers stopped after 2 passes without settling; calls to '
                      'some wrappers may be missed', i.warnings)
        self.assertNotIn('performLaterThrice', i.hazard_wrappers.keywords)
        self.assertEqual(inv.Inventory.WRAPPER_MAX_PASSES, 60)

    def test_cocoa_keywords_are_never_wrappers(self):
        self.assertEqual(inv.BLOCK_KEYWORDS_NEVER_WRAPPERS, (
            'completionHandler', 'completionBlock', 'usingBlock', 'withBlock', 'withReply', 'replyHandler',
            'errorHandler', 'resultHandler', 'performBlock'))
        self.assertNotIn('completionHandler', self.inv.hazard_wrappers.keywords)

    def test_summary_line(self):
        out = run_cli(self.root, 'summary')[1]
        self.assertIn('Block-dispatching wrappers found in scope, whose calls count as a block dispatched to a queue '
                      '(heuristic; the names are in the JSON output): 3 keywords, 1 functions, found in 3 passes of '
                      'at most 60\n', out)
        data = json.loads(run_cli(self.root, '--json', 'summary')[1])
        self.assertEqual(data['hazard_wrappers']['block_dispatch']['functions'], ['FixtureRunLater'])


class WrapperUsabilityTests(unittest.TestCase):
    """A wrapper's name is used only when every in-scope method or function with that name dispatches (and no
    function of that name is static)."""

    def inventory_with(self, extra):
        return inv.Inventory(wrapper_repo({'sources/Other.m': extra}))

    def test_static_function_of_the_same_name(self):
        i = self.inventory_with('static void FixtureRunLater(dispatch_block_t b) {\n'
                                '    dispatch_async(dispatch_get_main_queue(), b);\n}\n')
        self.assertEqual(i.hazard_wrappers.functions, [])
        self.assertEqual(i.file_record('sources/Multi+Extra.m', detail=True)['hazard_lines'],
                         {'block dispatched to a queue': [6, 8]})

    def test_function_of_the_same_name_that_does_not_dispatch(self):
        i = self.inventory_with('void FixtureRunLater(dispatch_block_t b) {\n    b();\n}\n')
        self.assertEqual(i.hazard_wrappers.functions, [])

    def test_keyword_that_carries_no_block_in_another_wrapper(self):
        i = self.inventory_with('@implementation Other\n- (void)performLater:(id)x then:(dispatch_block_t)b {\n'
                                '    dispatch_async(dispatch_get_main_queue(), b);\n}\n@end\n')
        self.assertEqual(i.hazard_wrappers.keywords, [])

    def test_keyword_of_a_method_that_does_not_dispatch(self):
        i = self.inventory_with('@implementation Other\n- (void)performLater:(void (^)(void))b {\n    b();\n}\n@end\n')
        self.assertEqual(i.hazard_wrappers.keywords, [])

    def test_declarations_and_selector_literals_are_not_calls(self):
        i = inv.Inventory(wrapper_repo({'sources/Multi+Extra.m':
            '#import "Multi.h"\nextern void FixtureRunLater(dispatch_block_t b);\n@implementation Multi (Extra)\n'
            '- (void)performLater:(id)c;\n- (void)extraWork {\n    SEL s = @selector(performLater:);\n'
            '    FixtureRunLater(^{ });\n}\n@end\n'}))
        self.assertEqual(i.file_record('sources/Multi+Extra.m', detail=True)['hazard_lines'],
                         {'block dispatched to a queue': [7]})


class HazardWrapperMatchingTests(unittest.TestCase):
    def test_calls_and_non_calls(self):
        w = inv.DispatchWrappers(keywords=['performLater'], functions=['FixtureRunLater'])
        src = ('[w performLater:^{ }];\n'               # 1
               'FixtureRunLater(^{ });\n'               # 2
               'return FixtureRunLater(b);\n'           # 3
               # None of these is a call.
               '[w myperformLater:^{ }];\n'
               '[w performLaterX:^{ }];\n'
               '- (void)performLater:(id)b;\n'
               'SEL a = @selector(performLater:);\n'
               'void FixtureRunLater(dispatch_block_t b);\n'
               'NSData *FixtureRunLater(void);\n')
        masked = inv.mask_source(src)
        lines = inv.LineIndex(masked)
        found = w.dispatch_offsets(masked)
        self.assertEqual(sorted((lines.line(o), name) for o, name in found.items()),
                         [(1, 'performLater:'), (2, 'FixtureRunLater()'), (3, 'FixtureRunLater()')])
        self.assertEqual(inv.file_hazards(masked, w), {'block dispatched to a queue': 3})
        self.assertEqual(inv.file_hazards(masked), {})


class ThreadHazardTests(unittest.TestCase):
    def test_thread_starts(self):
        src = ('[NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];\n'
               'pthread_create(&t, NULL, f, NULL);\n'
               'NSThread *t2 = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];\n'
               '[thread start];\n'
               '[self.ioThread start];\n'
               '[_thread start];\n'
               # None of these starts a thread.
               '[timer start]; [[NSThread currentThread] name]; [self startThread]; [thread cancel];\n')
        masked = inv.mask_source(src)
        lines = inv.LineIndex(masked)
        self.assertEqual(inv.file_hazards(masked)['thread created or started'], 6)
        self.assertEqual([lines.line(o) for o in inv.hazard_sites(masked)['thread created or started']],
                         [1, 2, 3, 4, 5, 6])

    def test_nsthread_subclass(self):
        def mutate(root):
            with open(os.path.join(root, 'sources', 'BgThread.m'), 'w') as f:
                f.write('@interface BgThread : NSThread\n@end\n@interface BgThreadChild : BgThread\n@end\n\n'
                        '@implementation BgThread\n+ (NSThread *)shared {\n    static NSThread *thread;\n'
                        '    thread = [[BgThread alloc] init];\n    [thread start];\n    return thread;\n}\n@end\n\n'
                        '@implementation BgThreadChild\n@end\n')
        i = inv.Inventory(make_repo(mutate))
        rec = i.file_record('sources/BgThread.m', detail=True)
        self.assertEqual(rec['hazards']['NSThread subclass'], 2)
        self.assertEqual(rec['hazard_lines']['NSThread subclass'], [6, 15])
        self.assertEqual(rec['hazard_lines']['thread created or started'], [10])
        self.assertEqual(inv.HAZARD_CODES['NSThread subclass'], 'NSTHR')
        self.assertEqual(inv.HAZARD_CODES['thread created or started'], 'THR')


class MissingFileTests(unittest.TestCase):
    def test_missing_tracked_file_is_reported_where_it_matters(self):
        root = make_repo()
        os.remove(os.path.join(root, 'sources', 'Lonely.m'))
        line = ('  1 tracked files that this tool would read are missing from the working tree and were not read, so '
                'nothing about them is established, and the relations and hazards that depend on them (subclasses, '
                'categories and extensions they declare, xib classes and connections, and the selector and '
                'class-name sites in them) could not be established: sources/Lonely.m\n')
        for args in (['leaf'], ['file', 'FooSub.m'], ['summary'], ['files']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 0, err)
            self.assertIn(line, out, args)
        data = json.loads(run_cli(root, '--json', 'leaf')[1])
        self.assertEqual(data['not_established']['missing_from_working_tree'], ['sources/Lonely.m'])
        code, out, err = run_cli(root, 'file', 'Lonely.m')
        self.assertEqual(code, 2)
        self.assertIn('sources/Lonely.m is tracked by git but missing from the working tree', err)


class AtomicPropertyLineTests(unittest.TestCase):
    def test_lines_are_given(self):
        rec = MiniRepo.inventory().file_record('sources/Concurrency.m', detail=True)
        self.assertEqual(rec['atomic_properties'], ['sources/Concurrency.m:10: atomicCount',
                                                    'sources/Concurrency.m:11: defaultAtomic'])
        self.assertEqual(rec['hazard_lines']['atomic property'], [10, 11])
        out = run_cli(MiniRepo.path(), 'file', 'Concurrency.m')[1]
        self.assertIn('    atomic property                  2  (lines 10, 11)\n', out)
        self.assertIn('    atomic property: sources/Concurrency.m:11: defaultAtomic\n', out)


class SelectorFormTests(unittest.TestCase):
    def test_forms_are_stated(self):
        self.assertEqual(inv.SELECTOR_SITE_FORMS, OrderedDict([
            ('Objective-C', 'NSSelectorFromString, sel_registerName and sel_getUid with an argument that is not a '
                            'string literal; a message keyword in the perform...Selector family or ending in Selector '
                            'or selector (other than respondsToSelector:, instancesRespondToSelector:, '
                            'NSStringFromSelector and doesNotRecognizeSelector:), sendAction:, tryToPerform:, '
                            'targetForAction:, setAction: or setDoubleAction:, whose argument is not an @selector '
                            'literal or nil; objc_msgSend and its variants without an @selector literal or SEL among '
                            'their arguments; calls to the selector-taking methods and functions found in scope '
                            'without an @selector literal; and an assignment to .action or .doubleAction that is not '
                            'an @selector literal or nil'),
            ('Swift', 'Selector(...) and NSSelectorFromString(...) with an argument that is not a string literal; '
                      'perform( with or without a receiver, sendAction( and tryToPerform( whose first argument is a '
                      'name, a member access, Selector(...) or NSSelectorFromString(...); target(forAction:, selector: '
                      'and action: whose argument is not a #selector literal, a string literal, nil, a capitalized '
                      'name, a closure, an array or an enum case, outside a #selector literal and '
                      'outside the parameters of a func, init, subscript or enum case declaration; and an assignment to .action or .doubleAction that is not a #selector literal, nil or an '
                      'enum case')]))
        out = run_cli(MiniRepo.path(), 'leaf')[1]
        self.assertIn('    Counted in Objective-C: %s.\n    Counted in Swift: %s.\n    No other form is counted, so '
                      'the count is complete only for these forms.\n'
                      % (inv.SELECTOR_SITE_FORMS['Objective-C'], inv.SELECTOR_SITE_FORMS['Swift']), out)
        data = json.loads(run_cli(MiniRepo.path(), '--json', 'leaf')[1])
        self.assertEqual(data['not_established']['selector_site_forms'], inv.SELECTOR_SITE_FORMS)
        self.assertIn('Objective-C forms counted', inv.RELIABILITY['not_established'][1])


class ActionAssignmentScanTests(unittest.TestCase):
    def test_file_with_only_an_action_assignment(self):
        def mutate(root):
            with open(os.path.join(root, 'sources', 'ActionOnly.m'), 'w') as f:
                f.write('void ActionOnly(NSMenuItem *item, id x) {\n    item.action = x;\n'
                        '    BOOL same = item.action == x;\n}\n')
        i = inv.Inventory(make_repo(mutate))
        self.assertEqual([x for x in i.dynamic_selector_sites if x.startswith('sources/ActionOnly.m')],
                         ['sources/ActionOnly.m:2: action ='])


class BlockDispatchTests(unittest.TestCase):
    def test_keywords_that_dispatch_a_block_literal(self):
        src = ('[self.thread dispatchAsync:^(id state) { }];\n'
               '[queue addOperationWithBlock:^{ }];\n'
               '[[NSRunLoop mainRunLoop] performBlock:^{ }];\n'
               '[NSThread detachNewThreadWithBlock:^{ }];\n'
               '[center addObserverForName:n object:nil queue:q usingBlock:^(NSNotification *note) { }];\n'
               # Each spelling of each word alone.
               '[x dispatch:^{ }];\n'
               '[x runDispatched:^{ }];\n'
               '[x runSync:^{ }];\n'
               '[x async:^{ }];\n'
               '[x threadRun:^{ }];\n'
               '[x schedulePerformBlock:^{ }];\n'
               '[x operationBlock:^{ }];\n'
               # Neither counts: a block that runs in place, and no block literal.
               '[x enumerateObjectsUsingBlock:^(id o, NSUInteger i, BOOL *s) { }];\n'
               '[self.thread dispatchAsync:block];\n')
        masked = inv.mask_source(src)
        # detachNewThreadWithBlock: also starts a thread.
        self.assertEqual(inv.file_hazards(masked), {'block dispatched to a queue': 12, 'thread created or started': 1})
        lines = inv.LineIndex(masked)
        self.assertEqual([lines.line(o) for o in inv.dispatch_sites(masked)[0]], list(range(1, 13)))
        for line in src.split('\n')[:12]:
            self.assertEqual(len(inv.dispatch_sites(inv.mask_source(line))[0]), 1, line)

    def test_block_parameters(self):
        self.assertEqual(inv.block_parameter_keywords(
            '- (void)run:(int)n handler:(void (^)(int))h queue:(dispatch_queue_t)q then:(dispatch_block_t)b '
            'done:(iTermDoneBlock)d'), ['handler', 'then', 'done'])
        self.assertTrue(inv.has_block_parameter('void Run(int n, void (^handler)(void))'))
        self.assertFalse(inv.has_block_parameter('void Run(int n, id handler)'))


class ProjectWrapperTests(unittest.TestCase):
    """iTerm2's own wrappers of swizzling, associated objects, key-value observing and concurrency."""

    def test_wrapper_calls(self):
        src = ('[iTermSelectorSwizzler swizzleSelector:s fromClass:c withBlock:b closure:^{ }];\n'   # 2 swizzl
               '[obj swizzleInstanceMethodSelector:s withBlock:b];\n'
               '[view it_setAssociatedObject:v forKey:k];\n'
               'id a = [view it_associatedObjectForKey:k];\n'
               'NSMutableDictionary *d = [cell psm_yosemiteAssociatedDictionary];\n'
               '[iTermTexture attachMetadata:m toTexture:t];\n'
               'id m2 = [iTermTexture metadataForTexture:t];\n'
               'iTermUserDefaultsObserver *o = [[iTermUserDefaultsObserver alloc] init];\n'          # 2 KVO
               '[self.thread dispatchSync:^(id state) { }];\n'
               'iTermSynchronizedState *s2 = nil; iTermCallback *cb = nil;\n'                         # 2 helper
               'iTermAtomicInt64Add(counter, 1);\n'
               # Not wrappers: names that only contain the words.
               'iTermThreadSafetyWidget *w; NSString *associated = nil;\n')
        h = inv.file_hazards(inv.mask_source(src))
        self.assertEqual((h['method replacement'], h['associated objects'], h['key-value coding/observing'],
                          h['iTerm2 concurrency helper']), (3, 5, 2, 3))
        self.assertEqual(h['block dispatched to a queue'], 1)
        # Each line alone, so that no other line's text lets it pass.
        for line, kind in zip(src.split('\n')[:8], ['method replacement'] * 2 + ['associated objects'] * 5 +
                              ['key-value coding/observing']):
            self.assertIn(kind, inv.file_hazards(inv.mask_source(line)), line)
        names = ('iTermThread *a; iTermSynchronizedState *b; iTermMainThreadState *c; iTermCallback *d; '
                 'iTermThreadChecker *e; iTermTaskQueue *f; iTermGCD *g; iTermMutationQueueJoinState *h; '
                 'iTermLegacyAtomicMutableArrayOfWeakObjects *i; iTermPreciseTimersLock *j; iTermAtomicInt64 *k;\n')
        self.assertEqual(inv.file_hazards(inv.mask_source(names))['iTerm2 concurrency helper'], 11)


class HistoryUnitTests(unittest.TestCase):
    def test_problems_for_the_unit_only(self):
        root = make_repo()
        commit_messages(root, [
            ('2026-01-01', 'Subject\n\nSwift-Port: Foo kind=port\nSwift-Port: Foo kind=port'),
            ('2026-01-02', 'Subject\n\nSwift-Port: Bar kind=weird\nSwift-Port: Baz kind=bogus'),
            ('2026-01-03', 'Subject\n\nX-Swift-Port: Foo kind=test')])
        code, out, err = run_cli(root, 'history', 'Foo')
        self.assertEqual(code, 0, err)
        self.assertIn('repeated in the same commit; counted once: Swift-Port: Foo kind=port', out)
        self.assertIn('not counted: git does not read this line as a Swift-Port trailer: X-Swift-Port: Foo kind=test',
                      out)
        self.assertNotIn('Bar', out)
        self.assertIn('2 trailer problems for other units (history without a unit lists them).', out)
        data = json.loads(run_cli(root, '--json', 'history', 'Foo')[1])
        self.assertEqual((len(data['problems']), data['problems_elsewhere']), (2, 2))
        data = json.loads(run_cli(root, '--json', 'history')[1])
        self.assertEqual((len(data['problems']), data['problems_elsewhere']), (4, 0))
        self.assertEqual(inv.trailer_problem_unit({'line': 'Swift-Porting: Qux kind=port'}), 'Qux')


class InputFailureTests(unittest.TestCase):
    def test_sdef_without_classes_is_an_error(self):
        def mutate(root):
            with open(os.path.join(root, 'iTerm2.sdef'), 'w') as f:
                f.write('<dictionary><suite name="x"></suite></dictionary>\n')
        code, out, err = run_cli(make_repo(mutate), 'leaf')
        self.assertEqual(code, 2, err)
        self.assertIn('iTerm2.sdef names no classes', err)
        self.assertEqual(out, '')

    def test_missing_root_is_an_error(self):
        for args in (['summary'], ['history']):
            code, out, err = run_cli(MiniRepo.path(), '--root', '/nonexistent/inventory-root', *args)
            self.assertEqual(code, 2, (args, err))
            self.assertIn('inventory.py: error: /nonexistent/inventory-root is not a directory', err)
            self.assertNotIn('Traceback', err)


class NotEstablishedTextTests(unittest.TestCase):
    def test_leaf_summarizes_the_sites(self):
        root = MiniRepo.path()
        out = run_cli(root, 'leaf')[1]
        self.assertIn('    By directory: sources 30, ModernTests 2.\n', out)
        self.assertIn('    By call: NSSelectorFromString 3, perform 3, performSelector 3, action = 2, action: 2, '
                      'selector 2, sendAction 2, LocalHelper 1, Selector 1, doubleAction = 1, fixture_dispatch 1, '
                      'it_performNonObjectReturningSelector 1, methodForSelector 1, objc_msgSend 1, '
                      'performSelectorOnMainThread 1, sel_getUid 1, setAction 1, setDoubleAction 1, setSelector 1, '
                      'target(forAction:) 1, targetForAction 1, tryToPerform 1.\n', out)
        self.assertIn('    Every site is listed in the JSON output (not_established.dynamic_selector_sites) and by leaf '
                      'and file with --all-sites.\n', out)
        self.assertNotIn('sources/LocalGlobal.m:12: sel_getUid', out)
        out = run_cli(root, 'leaf', '--all-sites')[1]
        self.assertIn('    Every site:\n      ModernTests/OwnerTests.m:8: performSelector\n', out)
        self.assertIn('      sources/LocalGlobal.m:35: setAction\n', out)

    def test_file_lists_its_own_sites(self):
        root = MiniRepo.path()
        out = run_cli(root, 'file', 'LocalGlobal.m')[1]
        self.assertIn('    In sources/LocalGlobal.m: 13:\n'
                      '      sources/LocalGlobal.m:12: sel_getUid\n      sources/LocalGlobal.m:15: performSelector\n'
                      '      sources/LocalGlobal.m:21: it_performNonObjectReturningSelector\n'
                      '      sources/LocalGlobal.m:22: fixture_dispatch\n      sources/LocalGlobal.m:24: sendAction\n'
                      '      sources/LocalGlobal.m:25: methodForSelector\n      sources/LocalGlobal.m:26: setSelector\n'
                      '      sources/LocalGlobal.m:27: selector\n      sources/LocalGlobal.m:28: objc_msgSend\n'
                      '      sources/LocalGlobal.m:30: LocalHelper\n      sources/LocalGlobal.m:33: action =\n'
                      '      sources/LocalGlobal.m:35: setAction\n      sources/LocalGlobal.m:36: setDoubleAction\n'
                      '    By directory:', out)
        self.assertNotIn('ModernTests/OwnerTests.m:8', out)
        self.assertIn('    dynamic selector site            13  (lines 12, 15, 21, 22, 24, 25, 26, 27, 28, 30, 33, 35, '
                      '36)\n', out)
        out = run_cli(root, 'file', 'FooSub.m')[1]
        self.assertIn('    In sources/FooSub.m: 0\n', out)
        data = json.loads(run_cli(root, '--json', 'file', 'FooSub.m')[1])
        self.assertEqual(len(data['not_established']['dynamic_selector_sites']), 32)

    def test_summary_counts_only(self):
        out = run_cli(MiniRepo.path(), 'summary')[1]
        self.assertIn('32 sites in the tree dispatch or build a selector', out)
        self.assertNotIn('By directory', out)
        self.assertNotIn('LocalGlobal.m:12', out)


class SelectorLiteralEndTests(unittest.TestCase):
    def test_label_after_a_closed_selector_literal_is_a_site(self):
        src = 'let action = #selector(NSResponder.selectAll(_:))\nlet item = NSMenuItem(title: "", action: action)\n'
        masked = inv.mask_source(src, swift=True)
        self.assertFalse(inv._in_swift_selector_literal(masked, masked.index('action: action')))
        inside = inv.mask_source('let s = #selector(foo(action:))\n', swift=True)
        self.assertTrue(inv._in_swift_selector_literal(inside, inside.index('action:')))

        def mutate(root):
            with open(os.path.join(root, 'sources', 'SelectorAfter.swift'), 'w') as f:
                f.write('final class SelectorAfter {\n'
                        '    private let action = #selector(NSResponder.selectAll(_:))\n'
                        '    func make() -> NSMenuItem {\n'
                        '        return NSMenuItem(title: "Find", action: action, keyEquivalent: "f")\n'
                        '    }\n'
                        '}\n')
        i = inv.Inventory(make_repo(mutate))
        self.assertEqual([x for x in i.dynamic_selector_sites if x.startswith('sources/SelectorAfter.swift')],
                         ['sources/SelectorAfter.swift:4: action:'])


class MissingOutsideScopeTests(unittest.TestCase):
    def test_missing_files_outside_scope_and_xibs_are_reported(self):
        root = make_repo()
        os.remove(os.path.join(root, 'ModernTests', 'BarTests.m'))
        os.remove(os.path.join(root, 'sources', 'Bar.xib'))
        line = ('  2 tracked files that this tool would read are missing from the working tree and were not read, so '
                'nothing about them is established, and the relations and hazards that depend on them (subclasses, '
                'categories and extensions they declare, xib classes and connections, and the selector and '
                'class-name sites in them) could not be established: ModernTests/BarTests.m, sources/Bar.xib\n')
        for args in (['leaf'], ['file', 'Bar.m'], ['summary']):
            code, out, err = run_cli(root, *args)
            self.assertEqual(code, 0, err)
            self.assertIn(line, out, args)
            data = json.loads(run_cli(root, '--json', *args)[1])
            self.assertEqual(data['not_established']['missing_from_working_tree'],
                             ['ModernTests/BarTests.m', 'sources/Bar.xib'], args)
        doc = ' '.join(inv.__doc__.split())
        self.assertIn('A tracked file that this tool would read (in scope or not, xib and storyboard files included) '
                      'but that is missing from the working tree is not read; it is listed under Not established by '
                      'this tool by every subcommand, because the relations and hazards that depend on it could not '
                      'be established.', doc)
        self.assertIn('tracked files missing from the working tree that this tool would read, in scope or not, xib '
                      'and storyboard files included',
                      inv.RELIABILITY['not_established'][1])


class StoredStateWordingTests(unittest.TestCase):
    RULE_1 = ('dictionaryWithContentsOfFile:, dictionaryWithContentsOfURL:, arrayWithContentsOfFile:, '
              'arrayWithContentsOfURL:, and writeToFile: or writeToURL: without an encoding: keyword')
    NOT_DETECTED = ('generic file and JSON I/O (stringWithContentsOf..., dataWithContentsOf..., '
                    'initWithContentsOf..., createFileAtPath:contents:, NSFileHandle, fopen, NSJSONSerialization, '
                    'and strings written with an encoding)')

    def test_rule_one_says_what_it_matches(self):
        stored = [line for line in inv.NOT_CHECKED if line.startswith('Stored state is found by four rules')]
        self.assertEqual(len(stored), 1)
        self.assertIn(self.RULE_1, stored[0])
        self.assertNotIn('read or written whole', stored[0])
        doc = ' '.join(inv.__doc__.split())
        self.assertIn(self.RULE_1, doc)
        self.assertNotIn('read or written whole', doc)
        not_detected = [line for line in inv.NOT_CHECKED if line.startswith('Not detected: stored state')]
        self.assertEqual(len(not_detected), 1)
        self.assertIn(self.NOT_DETECTED, not_detected[0])


class PragmaMarkStoredStateTests(unittest.TestCase):
    def test_pragma_mark_is_not_a_match(self):
        self.assertEqual(inv.stored_state_matches(inv.mask_source('#pragma mark - NSCoding\n'))[0], [])
        self.assertEqual(inv.stored_state_matches(inv.mask_source('  #  pragma mark NSKeyedArchiver\n'))[0], [])
        src = '#pragma mark - NSCoding\n@interface X : NSObject <NSSecureCoding>\n@end\n'
        matches = inv.stored_state_matches(inv.mask_source(src))[0]
        self.assertEqual([(m['text'], m['entry']) for m in matches], [('NSSecureCoding', 'NSCoding')])
        self.assertEqual(matches[0]['offset'], src.index('NSSecureCoding'))


class HazardLineDetailTests(unittest.TestCase):
    def test_ownership_family_and_stringifying_macro_lines(self):
        rec = MiniRepo.inventory().file_record('sources/Concurrency.m', detail=True)
        self.assertEqual(rec['hazard_lines']['ownership-transferring method name'], [36, 40, 52])
        self.assertEqual(rec['hazard_lines']['stringifying macro'], [30])
        self.assertEqual(rec['ownership_transferring_methods'],
                         ['sources/Concurrency.m:36: newThing', 'sources/Concurrency.m:40: copyState',
                          'sources/Concurrency.m:52: mutableCopyState'])
        out = run_cli(MiniRepo.path(), 'file', 'Concurrency.m')[1]
        self.assertIn('    ownership-transferring method name 3  (lines 36, 40, 52)\n', out)
        self.assertIn('    stringifying macro               1  (line 30)\n', out)
        self.assertIn('    ownership-transferring method name: sources/Concurrency.m:40: copyState\n', out)
        data = json.loads(run_cli(MiniRepo.path(), '--json', 'file', 'Concurrency.m')[1])
        self.assertEqual(data['hazard_lines']['stringifying macro'], [30])
        self.assertEqual(data['ownership_transferring_methods'], rec['ownership_transferring_methods'])


class HazardSearchReferenceTests(unittest.TestCase):
    def test_leaf_footer_points_at_the_searches(self):
        where = 'by the text searches defined in inventory.py (HAZARD_PATTERNS and Inventory.file_record)'
        out = ' '.join(run_cli(MiniRepo.path(), 'leaf')[1].split())
        self.assertIn('The last column lists the hazards this tool detects in it ' + where + ';', out)
        self.assertNotIn('listed in inventory.py --help', out)
        self.assertIn('hazards this tool detects in it ' + where + ';', ' '.join(inv.__doc__.split()))
        self.assertTrue(hasattr(inv, 'HAZARD_PATTERNS') and hasattr(inv.Inventory, 'file_record'))


def leaf_lists(result):
    return dict((name, dict((f['path'], f['details']) for f in d['files'])) for name, d in result['deferred'].items())


NEW_SCOPE_ROOTS = ('SignedArchive', 'pidinfo', 'iTerm2SandboxedWorker', 'ShellLauncher', 'ColorPicker',
                   'SearchableComboListView', 'BetterFontPicker')
OVERLAY_PROJECTS_SEARCHED = ('iTerm2.xcodeproj, ColorPicker/ColorPicker.xcodeproj, '
                             'SignedArchive/SignedArchive.xcodeproj')


class ScopeConstantTests(unittest.TestCase):
    """The scope of README.md section 2, as widened by the owner on 2026-11-19, held in one constant."""

    def test_scope_roots_are_readme_section_2(self):
        self.assertEqual(inv.SCOPE_ROOTS, ('sources', 'ThirdParty/PSMTabBarControl') + NEW_SCOPE_ROOTS)
        self.assertEqual(inv.SCOPE_WIDENED, '2026-11-19')

    def test_new_directories_are_in_scope_and_built_frameworks_are_not(self):
        for root in NEW_SCOPE_ROOTS:
            self.assertIsNone(inv.exclusion_reason(root + '/x/File.m'), root)
        self.assertEqual(inv.exclusion_reason('ColorPicker/ColorPicker.framework/Versions/A/Headers/CPKPopover.h'),
                         'generated (built framework)')
        self.assertEqual(inv.exclusion_reason('BetterFontPicker/BetterFontPicker.framework/Versions/A/Headers/'
                                              'BetterFontPicker-Swift.h'), 'generated (built framework)')
        self.assertEqual(inv.exclusion_reason('ThirdParty/LetsMove/PFMoveApplication.m'),
                         'outside the scope directories (README.md section 2)')
        self.assertEqual(inv.exclusion_reason('Companion/Sources/X.m'),
                         'outside the scope directories (README.md section 2)')

    def test_scope_is_written_only_in_the_constant(self):
        with open(os.path.join(TOOL_DIR, 'inventory.py'), encoding='utf-8') as f:
            text = f.read()
        self.assertEqual(text.count('PSMTabBarControl'), 1)
        # 'sources' as a key of a target summary is the count of its source files, not the scope.
        self.assertEqual(len(re.findall(r"'sources'(?!\]|:)", text)), 1)
        self.assertNotIn('under sources/', text)
        self.assertNotIn('sources/ and', text)

    def test_help_states_the_scope_and_the_category_rule(self):
        code, out, _ = run_cli(REPO_ROOT, '--help')
        self.assertEqual(code, 0)
        flat = ' '.join(out.split())
        for root in inv.SCOPE_ROOTS:
            self.assertIn(root + '/', flat)
        self.assertIn('widened by the owner on 2026-11-19', flat)
        self.assertIn('Test, demo and tool code:', flat)
        self.assertIn('com.apple.product-type.bundle.unit-test', flat)
        self.assertIn('Every other target is treated as building the app or one of its helper programs (in '
                      'iTerm2.xcodeproj/project.pbxproj, every target that is not a test bundle; elsewhere, frameworks, '
                      'libraries, XPC services and bundles). This is by product type, so a library that only standalone '
                      'tools use, or a test application in iTerm2.xcodeproj/project.pbxproj, is treated as a product.',
                      flat)
        self.assertNotIn('builds the app or one of its helper programs', flat)


class ScopeOverlayTests(unittest.TestCase):
    """fixtures/scope_overlay: files in the new scope directories, two Xcode projects of their own, and their test,
    demo, tool and generated files."""

    def test_file_set_and_exclusions(self):
        i = ScopeOverlayRepo.inventory()
        for p in ('pidinfo/PidLeaf.m', 'pidinfo/PidHelper.m', 'ColorPicker/ColorPicker/CPKThing.m',
                  'SignedArchive/SignedArchive/SIGThing.m', 'SignedArchive/resign/main.c',
                  'SignedArchive/SignedArchive/SIGShared.c', 'sources/SharedWithTests.m'):
            self.assertIn(p, i.impl_files)
        self.assertEqual(len(i.impl_files), 51)
        for p in ('ColorPicker/ColorPickerDemo/AppDelegate.m', 'ColorPicker/ColorPickerTests/CPKThingTests.m',
                  'SignedArchive/sign/main.m'):
            self.assertNotIn(p, i.impl_files)
        self.assertNotIn('ColorPicker/ColorPicker.framework/Versions/A/Headers/CPKThing.h', i.headers)
        self.assertNotIn('ColorPicker/ColorPickerDemo/AppDelegate.h', i.headers)
        self.assertNotIn('SignedArchive/sign/sign-Bridging-Header.h', i.headers)
        self.assertIn('ColorPicker/ColorPicker/CPKThing.h', i.headers)
        self.assertEqual(i.excluded, {'generated (protobuf)': 1, 'generated (Core Data)': 1,
                                      'generated (built framework)': 1, 'test code': 1, 'demo code': 3,
                                      'tool code': 2})

    def test_file_compiled_by_a_product_target_and_a_test_or_tool_target_stays_in_scope(self):
        i = ScopeOverlayRepo.inventory()

        def targets(p):
            return [(t['target'], i.targets[t['target']]['category']) for t in i.file_record(p)['targets']]
        self.assertEqual(targets('sources/SharedWithTests.m'), [('iTerm2SharedARC', 'product'), ('OverlayTests', 'test')])
        self.assertEqual(targets('SignedArchive/SignedArchive/SIGShared.c'),
                         [('SignedArchive/SignedArchive.xcodeproj:SignedArchive', 'product'),
                          ('SignedArchive/SignedArchive.xcodeproj:sign', 'tool')])
        for p in ('sources/SharedWithTests.m', 'SignedArchive/SignedArchive/SIGShared.c'):
            self.assertIn(p, i.impl_files)
            self.assertNotIn(p, i.non_product)
            self.assertNotIn(p, i.excluded_files)
        s = i.summary()
        self.assertEqual(s['by_scope_root']['sources']['implementation_files'], 44)
        self.assertEqual(s['by_scope_root']['SignedArchive']['implementation_files'], 3)
        self.assertNotIn('sources/SharedWithTests.m', s['scope']['non_product_code'])
        self.assertNotIn('SignedArchive/SignedArchive/SIGShared.c', s['scope']['non_product_code'])

    def test_swift_file_of_a_demo_target_is_demo_code(self):
        i = ScopeOverlayRepo.inventory()
        self.assertEqual(i.non_product['ColorPicker/ColorPickerDemo/DemoView.swift']['category'], 'demo')
        self.assertEqual(i.excluded_files['ColorPicker/ColorPickerDemo/DemoView.swift'], 'demo code')
        self.assertNotIn('ColorPicker/ColorPickerDemo/DemoView.swift', i.swift_files)
        self.assertEqual(i.summary()['by_scope_root']['ColorPicker']['swift_files'], 0)

    def test_projects_searched(self):
        i = ScopeOverlayRepo.inventory()
        self.assertEqual(i.projects, ['iTerm2.xcodeproj', 'ColorPicker/ColorPicker.xcodeproj',
                                      'SignedArchive/SignedArchive.xcodeproj'])

    def test_targets_and_arc_from_each_project(self):
        i = ScopeOverlayRepo.inventory()

        def targets(p):
            return [(t['target'], t['arc']) for t in i.file_record(p)['targets']]
        self.assertEqual(targets('ColorPicker/ColorPicker/CPKThing.m'),
                         [('ColorPicker/ColorPicker.xcodeproj:ColorPicker', True)])
        self.assertEqual(i.arc_state('ColorPicker/ColorPicker/CPKThing.m'), 'ARC')
        # CLANG_ENABLE_OBJC_ARC unset in that project's target and project: Xcode's default of NO.
        self.assertEqual(targets('SignedArchive/SignedArchive/SIGThing.m'),
                         [('SignedArchive/SignedArchive.xcodeproj:SignedArchive', False)])
        self.assertEqual(i.arc_state('SignedArchive/SignedArchive/SIGThing.m'), 'non-ARC')
        self.assertIn('Xcode default is NO', i.file_record('SignedArchive/SignedArchive/SIGThing.m')['targets'][0]
                      ['arc_source'])
        self.assertEqual(targets('pidinfo/PidLeaf.m'), [('iTerm2SharedARC', True)])
        self.assertEqual(targets('pidinfo/PidHelper.m'), [('pidinfo', True)])
        self.assertEqual(targets('SignedArchive/resign/main.c'), [])
        self.assertEqual(i.arc_state('SignedArchive/resign/main.c'), 'not compiled')
        t = i.targets['ColorPicker/ColorPicker.xcodeproj:ColorPickerTests']
        self.assertEqual((t['project'], t['product_type'], t['category']),
                         ('ColorPicker/ColorPicker.xcodeproj', 'com.apple.product-type.bundle.unit-test', 'test'))
        t = i.targets['pidinfo']
        self.assertEqual((t['project'], t['product_type'], t['category']),
                         ('iTerm2.xcodeproj', 'com.apple.product-type.tool', 'product'))
        self.assertEqual(i.targets['SignedArchive/SignedArchive.xcodeproj:sign']['category'], 'tool')
        self.assertEqual(i.targets['ColorPicker/ColorPicker.xcodeproj:ColorPickerDemo']['category'], 'demo')
        self.assertEqual(i.targets['ColorPicker/ColorPicker.xcodeproj:ColorPicker']['category'], 'product')

    def test_test_demo_and_tool_code(self):
        i = ScopeOverlayRepo.inventory()
        self.assertEqual({p: (r['category'], r['targets'], r['lines']) for p, r in i.non_product.items()}, {
            'ColorPicker/ColorPickerDemo/AppDelegate.h': ('demo', ['ColorPicker/ColorPicker.xcodeproj:ColorPickerDemo'], 4),
            'ColorPicker/ColorPickerDemo/AppDelegate.m': ('demo', ['ColorPicker/ColorPicker.xcodeproj:ColorPickerDemo'], 4),
            'ColorPicker/ColorPickerDemo/DemoView.swift': ('demo', ['ColorPicker/ColorPicker.xcodeproj:ColorPickerDemo'],
                                                           4),
            'ColorPicker/ColorPickerTests/CPKThingTests.m': ('test', ['ColorPicker/ColorPicker.xcodeproj:ColorPickerTests'],
                                                             8),
            'SignedArchive/sign/main.m': ('tool', ['SignedArchive/SignedArchive.xcodeproj:sign'], 5),
            'SignedArchive/sign/sign-Bridging-Header.h': ('tool', ['SignedArchive/SignedArchive.xcodeproj:sign'], 1),
        })
        with self.assertRaises(inv.InventoryError) as cm:
            i.resolve('ColorPicker/ColorPickerDemo/AppDelegate.m')
        self.assertIn('demo code', str(cm.exception))

    def test_relations_fan_in_and_hazards_cover_the_new_directories(self):
        i = ScopeOverlayRepo.inventory()
        self.assertEqual(i.class_relations('CPKThing')['objc_subclasses'],
                         [{'name': 'CPKSubThing', 'where': 'ColorPicker/ColorPicker/CPKThing.m:3', 'in_scope': True}])
        self.assertEqual(i.fan_in('pidinfo/PidLeaf.m')['importers'], 1)
        # Foo.m, Lonely.m and the bridging header in the fixture, and now pidinfo/PidHelper.m.
        self.assertEqual(i.fan_in('sources/Bar.m')['importers'], 4)
        self.assertEqual(i.file_record('pidinfo/PidLeaf.m')['hazards'], {'@synchronized': 1})
        # NSKeyedArchiver and archivedDataWithRootObject:, both rule 1, on line 6.
        self.assertEqual(i.file_record('SignedArchive/SignedArchive/SIGThing.m')['hazards']['stored state'], 2)
        # The test bundle and the tool import these headers from outside scope.
        self.assertEqual(i.file_record('ColorPicker/ColorPicker/CPKThing.m')['hazards']['imported outside scope'], 1)
        self.assertEqual(i.file_record('SignedArchive/SignedArchive/SIGThing.m')['hazards']['imported outside scope'],
                         2)

    def test_prefix_header_of_another_project(self):
        i = ScopeOverlayRepo.inventory()
        self.assertEqual(i.fan_in('SignedArchive/SignedArchive/SIGThing.m')['prefix_header'],
                         {'via': ['SignedArchive/SignedArchive/SIG-Prefix.pch'],
                          'targets': ['SignedArchive/SignedArchive.xcodeproj:SignedArchive'],
                          # SIGShared.c, which the SignedArchive target compiles and which imports nothing.
                          'importers_only_through_it': 1})

    def test_leaf(self):
        i = ScopeOverlayRepo.inventory()
        result = i.leaf()
        self.assertIn('pidinfo/PidLeaf.m', [c['path'] for c in result['candidates']])

        def reasons(p):
            return {k: v for k, v in i.deferral_reasons(i.file_record(p)).items()}
        self.assertEqual(reasons('pidinfo/PidLeaf.m'), {})
        self.assertEqual(reasons('pidinfo/PidHelper.m'), {'built into other executables': ['also or only compiled by '
                                                                                            'pidinfo']})
        self.assertEqual(reasons('ColorPicker/ColorPicker/CPKThing.m'), {
            'classes with Objective-C subclasses': ['1 Objective-C subclasses (0 outside scope)'],
            'built into other executables': ['also or only compiled by ColorPicker/ColorPicker.xcodeproj:ColorPicker']})
        self.assertEqual(sorted(reasons('SignedArchive/SignedArchive/SIGThing.m')),
                         ['built into other executables', 'encodes or decodes stored state'])
        self.assertEqual(reasons('SignedArchive/resign/main.c'), {
            'not compiled': ['compiled by no target of any project found (searched: %s)' % OVERLAY_PROJECTS_SEARCHED]})
        by_root = result['by_scope_root']
        self.assertEqual(list(by_root), list(inv.SCOPE_ROOTS))
        self.assertEqual(by_root['pidinfo'], {'offered': 1, 'deferred': 1, 'outside_thresholds': 0})
        self.assertEqual(by_root['ColorPicker'], {'offered': 0, 'deferred': 1, 'outside_thresholds': 0})
        self.assertEqual(by_root['SignedArchive'], {'offered': 0, 'deferred': 3, 'outside_thresholds': 0})
        self.assertEqual(by_root['ShellLauncher'], {'offered': 0, 'deferred': 0, 'outside_thresholds': 0})
        self.assertEqual(sum(v['offered'] for v in by_root.values()), len(result['candidates']))
        self.assertEqual(sum(v['deferred'] for v in by_root.values()), result['deferred_files'])

    def test_summary_per_directory(self):
        s = ScopeOverlayRepo.inventory().summary()
        self.assertEqual(s['scope']['roots'], list(inv.SCOPE_ROOTS))
        self.assertEqual(s['scope']['widened'], '2026-11-19')
        self.assertEqual(s['projects_searched'], ['iTerm2.xcodeproj', 'ColorPicker/ColorPicker.xcodeproj',
                                                  'SignedArchive/SignedArchive.xcodeproj'])
        by_root = s['by_scope_root']
        self.assertEqual(list(by_root), list(inv.SCOPE_ROOTS))
        self.assertEqual(by_root['pidinfo'], {'implementation_files': 2, 'implementation_lines': 19, 'header_files': 1,
                                              'header_lines': 5, 'swift_files': 0, 'excluded': {}})
        self.assertEqual(by_root['ColorPicker'], {'implementation_files': 1, 'implementation_lines': 10,
                                                  'header_files': 1, 'header_lines': 4, 'swift_files': 0,
                                                  'excluded': {'demo code': 3, 'generated (built framework)': 1,
                                                               'test code': 1}})
        self.assertEqual(by_root['SignedArchive'], {'implementation_files': 3, 'implementation_lines': 15,
                                                    'header_files': 1, 'header_lines': 4, 'swift_files': 0,
                                                    'excluded': {'tool code': 2}})
        self.assertEqual(by_root['ThirdParty/PSMTabBarControl']['implementation_files'], 1)
        self.assertEqual(by_root['sources']['implementation_files'], 44)
        self.assertEqual(sum(v['implementation_files'] for v in by_root.values()), s['implementation_files'])
        self.assertEqual(sum(v['implementation_lines'] for v in by_root.values()), s['implementation_lines'])
        self.assertEqual(sum(v['header_lines'] for v in by_root.values()), s['header_lines'])
        self.assertEqual(s['not_compiled_by_any_target'], ['SignedArchive/resign/main.c', 'sources/Concurrency.m',
                                                           'sources/Lonely.m', 'sources/PTYTextView.m'])
        self.assertEqual(sorted(s['scope']['non_product_code']), sorted(ScopeOverlayRepo.inventory().non_product))
        self.assertEqual(s['scope']['excluded_files']['ColorPicker/ColorPicker.framework/Versions/A/Headers/CPKThing.h'],
                         'generated (built framework)')

    def test_summary_text(self):
        out = run_main(['--root', ScopeOverlayRepo.path(), 'summary'])
        flat = ' '.join(out.split())
        self.assertIn('Scope (README.md section 2, widened by the owner on 2026-11-19)', flat)
        self.assertRegex(out, r'(?m)^\s*pidinfo/\s+2\s+19\s+1\s+5\s+0\s')
        self.assertRegex(out, r'(?m)^\s*SignedArchive/\s+3\s+15\s+1\s+4\s+0\s+tool code 2')
        self.assertIn('Projects searched for targets: %s' % OVERLAY_PROJECTS_SEARCHED, flat)
        self.assertIn('ColorPicker/ColorPickerTests/CPKThingTests.m (test:', flat)
        self.assertIn('Compiled by no target of any project found: 4', flat)

    def test_leaf_text(self):
        out = run_main(['--root', ScopeOverlayRepo.path(), 'leaf'])
        flat = ' '.join(out.split())
        self.assertIn('By scope directory (offered, deferred, outside the tier):', flat)
        self.assertIn('pidinfo/ 1, 1, 0', flat)

    def test_broken_or_incomplete_sub_project_is_an_error(self):
        def broken(root):
            add_scope_overlay(root)
            with open(os.path.join(root, 'ColorPicker', 'ColorPicker.xcodeproj', 'project.pbxproj'), 'w') as f:
                f.write('{ objects = { ')
        code, _, stderr = run_cli(make_repo(mutate=broken), 'summary')
        self.assertEqual(code, 2)
        self.assertIn('cannot parse ColorPicker/ColorPicker.xcodeproj/project.pbxproj', stderr)

        def no_prefix(root):
            add_scope_overlay(root)
            os.remove(os.path.join(root, 'SignedArchive', 'SignedArchive', 'SIG-Prefix.pch'))
        code, _, stderr = run_cli(make_repo(mutate=no_prefix), 'summary')
        self.assertEqual(code, 2)
        self.assertIn('SignedArchive/SignedArchive/SIG-Prefix.pch of target '
                      'SignedArchive/SignedArchive.xcodeproj:SignedArchive (GCC_PREFIX_HEADER in '
                      'SignedArchive/SignedArchive.xcodeproj/project.pbxproj)', stderr)


@unittest.skipIf(os.environ.get('INVENTORY_SKIP_REAL_TREE'), 'real-tree smoke tests skipped by request')
class RealTreeSmokeTests(unittest.TestCase):
    """Runs on the real repository; asserts only shape, never contents."""

    def run_tool(self, *args):
        proc = subprocess.run([sys.executable, os.path.join(TOOL_DIR, 'inventory.py')] + list(args),
                              cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr.decode('utf-8', 'replace'))
        return proc.stdout.decode('utf-8')

    def test_summary_json(self):
        s = json.loads(self.run_tool('--json', 'summary'))
        self.assertGreater(s['implementation_files'], 0)
        self.assertGreater(s['implementation_lines'], 0)
        self.assertIn('progress', s)
        self.assertIn('reliability', s)
        # The search for block-dispatching wrappers settles well inside its bound.
        w = s['hazard_wrappers']['block_dispatch']
        self.assertGreaterEqual(w['passes'], 1)
        self.assertLessEqual(w['passes'], w['max_passes'] // 3)
        self.assertFalse(any('wrappers stopped' in x for x in s['warnings']))

    def test_files_text(self):
        out = self.run_tool('files', '--limit', '5')
        self.assertIn('path', out.splitlines()[0])


if __name__ == '__main__':
    unittest.main()
