#!/usr/bin/env python3
"""Tests for sdk_selectors.py, the interim text scan of SDK headers.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_sdk_selectors.py'

The scan is tested on fixture headers (tests/fixtures/sdk_selectors/SDK); one
smoke check reads the real SDK that xcrun names and is skipped, with a
message, when there is none.
"""

import io
import os
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import sdk_selectors as ss  # noqa: E402

FIXTURE_SDK = os.path.join(HERE, 'fixtures', 'sdk_selectors', 'SDK')


class MethodSelectorTest(unittest.TestCase):
    def test_shapes(self):
        m = ss.method_selector
        self.assertEqual(m('- (void)go'), ('go', False, False))
        self.assertEqual(m('+ (id)shared NS_SWIFT_NAME(shared())'), ('shared', True, False))
        self.assertEqual(m('- (IBAction)selectNextTab:(nullable id)sender API_AVAILABLE(macos(10.12))'),
                         ('selectNextTab:', False, True))
        self.assertEqual(m('- (void)a:(int)x\n      b:(void (^)(BOOL f, NSError *e))c'), ('a:b:', False, False))
        self.assertEqual(m('- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)'), ('log:', False, False))
        self.assertEqual(m('- (BOOL)unlabeled:(id)a :(id)b'), ('unlabeled::', False, False))
        self.assertEqual(m('- (void)foo:(int)ID bar:(int)y'), ('foo:bar:', False, False))
        self.assertIsNone(m('x = 1'))

    def test_a_method_with_no_return_type(self):
        # NSURLHandle.h: - initWithURL:(NSURL *)anURL cached:(BOOL)willCache;
        m = ss.method_selector
        self.assertEqual(m('- initWithURL:(NSURL *)anURL cached:(BOOL)willCache'), ('initWithURL:cached:', False, False))
        self.assertEqual(m('+ sharedThing'), ('sharedThing', True, False))
        self.assertEqual(m('- init API_UNAVAILABLE(macos)'), ('init', False, False))


class PropertySelectorTest(unittest.TestCase):
    def test_shapes(self):
        p = ss.property_selectors
        self.assertEqual(p('@property (readonly) BOOL canBecomeMainWindow'), [('canBecomeMainWindow', False)])
        self.assertEqual(p('@property (getter=isVisible, readonly) BOOL visible'), [('isVisible', False)])
        self.assertEqual(p('@property (nullable, copy) NSString *title NS_SWIFT_NAME(windowTitle)'),
                         [('title', False), ('setTitle:', False)])
        self.assertEqual(p('@property (setter=setTheFrame:) NSRect frame API_DEPRECATED("x", macos(10.0, 10.15))'),
                         [('frame', False), ('setTheFrame:', False)])
        self.assertEqual(p('@property (class, readonly, strong) FKWindow *sharedWindow'), [('sharedWindow', True)])
        self.assertEqual(p('@property (copy) void (^handler)(NSError * _Nullable error)'),
                         [('handler', False), ('setHandler:', False)])
        self.assertEqual(p('@property NSInteger first, second'),
                         [('first', False), ('setFirst:', False), ('second', False), ('setSecond:', False)])
        self.assertEqual(p('@property NSInteger ID'), [('ID', False), ('setID:', False)])
        self.assertEqual(p('@property (readonly) id x NS_REFINED_FOR_SWIFT'), [('x', False)])

    def test_two_availability_macros_with_arguments(self):
        # NSTask.h and NSFileManager.h.
        p = ss.property_selectors
        self.assertEqual(p('@property (nullable, copy) NSURL *currentDirectoryURL API_AVAILABLE(macos(10.13)) '
                           'API_UNAVAILABLE(ios, watchos, tvos)'),
                         [('currentDirectoryURL', False), ('setCurrentDirectoryURL:', False)])
        self.assertEqual(p('@property (readonly, copy) NSURL *homeDirectoryForCurrentUser API_AVAILABLE(macosx(10.12)) '
                           'API_UNAVAILABLE(ios, watchos, tvos)'), [('homeDirectoryForCurrentUser', False)])
        self.assertEqual(p('@property (readonly) Class classForPortCoder NS_SWIFT_UNAVAILABLE("Use X") '
                           'API_DEPRECATED("Use X", macosx(10.0, 10.13), ios(2.0,11.0))'), [('classForPortCoder', False)])
        self.assertEqual(p('@property NSInteger ID API_AVAILABLE(macos(10.0)) API_UNAVAILABLE(ios)'),
                         [('ID', False), ('setID:', False)])

    def test_a_block_property_with_a_macro_inside_the_parentheses(self):
        # NSTask.h, NSProgress.h, NSFileHandle.h.
        p = ss.property_selectors
        self.assertEqual(p('@property (nullable, copy) void (NS_SWIFT_SENDABLE ^terminationHandler)(NSTask *) '
                           'API_AVAILABLE(macos(10.7))'),
                         [('terminationHandler', False), ('setTerminationHandler:', False)])
        self.assertEqual(p('@property (nullable, copy) void (NS_SWIFT_SENDABLE ^ _Nullable cancellationHandler)(void)'),
                         [('cancellationHandler', False), ('setCancellationHandler:', False)])


class FailSafeTest(unittest.TestCase):
    def test_a_method_with_no_return_type_is_scanned_in_a_container(self):
        rows = ss.scan_header('@interface NSURLHandle : NSObject\n- initWithURL:(NSURL *)anURL cached:(BOOL)c;\n'
                              '@end\n')
        self.assertEqual(rows, [('class', 'NSURLHandle', '-', 'initWithURL:cached:', '')])

    def test_a_semicolon_inside_a_macro_string_does_not_end_the_declaration(self):
        # NSDrawer.h: API_DEPRECATED("Drawers are deprecated; consider using NSSplitViewController", ...)
        rows = ss.scan_header('@interface NSWindow(NSDrawers)\n@property (nullable, readonly, copy) NSArray<NSDrawer *> '
                              '*drawers API_DEPRECATED("Drawers are deprecated; consider X", macos(10.0,10.13));\n'
                              '- (void)after;\n@end\n')
        self.assertEqual(rows, [('category', 'NSWindow(NSDrawers)', '-', 'drawers', ''),
                                ('category', 'NSWindow(NSDrawers)', '-', 'after', '')])

    def test_a_declaration_the_scanner_cannot_read_is_counted_and_shown(self):
        failures = []
        rows = ss.scan_header('@interface FKThing : NSObject\n- (void)fine;\n@property (copy) ;\n- (void);\n'
                              '@end\n', failures=failures)
        self.assertEqual(rows, [('class', 'FKThing', '-', 'fine', '')])
        self.assertEqual([f[1] for f in failures], ['@property (copy)', '- (void)'])

    def test_main_reports_failures_and_strict_exits_non_zero(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            headers = os.path.join(d, 'SDK', 'System', 'Library', 'Frameworks', 'Bad.framework', 'Headers')
            os.makedirs(headers)
            with open(os.path.join(headers, 'Bad.h'), 'w') as f:
                f.write('@interface FKBad : NSObject\n- (void)fine;\n- (void);\n@end\n')
            out = os.path.join(d, 'out.tsv')
            err = io.StringIO()
            with unittest.mock.patch('sys.stdout', err):
                self.assertEqual(ss.main(['--sdk', os.path.join(d, 'SDK'), out]), 0)
            self.assertIn('declarations the scanner could not read: 1', err.getvalue())
            self.assertIn('Bad.h:3: - (void)', err.getvalue())
            with unittest.mock.patch('sys.stdout', io.StringIO()):
                self.assertEqual(ss.main(['--strict', '--sdk', os.path.join(d, 'SDK'), out]), 1)
        finally:
            import shutil
            shutil.rmtree(d)


class ScanTest(unittest.TestCase):
    def test_the_fixture_sdk(self):
        self.assertEqual(ss.scan_sdk(FIXTURE_SDK), [
            ('category', 'FKView()', '-', 'extensionMethod', 'Fake', ''),
            ('category', 'FKWindow(FKTabbing)', '-', 'mergeAllWindows:', 'Fake', ''),
            ('class', 'FKInner', '-', 'innerMethod', 'Inner', ''),
            ('class', 'FKWindow', '+', 'sharedWindow', 'Fake', ''),
            ('class', 'FKWindow', '+', 'windowWithNumber:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'ID', 'Fake', ''),
            ('class', 'FKWindow', '-', 'canBecomeMainWindow', 'Fake', ''),
            ('class', 'FKWindow', '-', 'first', 'Fake', ''),
            ('class', 'FKWindow', '-', 'frame', 'Fake', ''),
            ('class', 'FKWindow', '-', 'handler', 'Fake', ''),
            ('class', 'FKWindow', '-', 'initWithContentRect:styleMask:backing:defer:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'isVisible', 'Fake', ''),
            ('class', 'FKWindow', '-', 'log:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'performBlock:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'second', 'Fake', ''),
            ('class', 'FKWindow', '-', 'selectNextTab:', 'Fake', 'action'),
            ('class', 'FKWindow', '-', 'setFirst:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'setHandler:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'setID:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'setSecond:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'setTheFrame:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'setTitle:', 'Fake', ''),
            ('class', 'FKWindow', '-', 'title', 'Fake', ''),
            ('class', 'FKWindow', '-', 'unlabeled::', 'Fake', ''),
            ('protocol', 'FKWindowDelegate', '-', 'delegateName', 'Fake', 'optional'),
            ('protocol', 'FKWindowDelegate', '-', 'tableView:shouldSelectRow:', 'Fake', 'optional'),
            ('protocol', 'FKWindowDelegate', '-', 'windowAlsoRequired', 'Fake', ''),
            ('protocol', 'FKWindowDelegate', '-', 'windowDidResize:', 'Fake', 'optional'),
            ('protocol', 'FKWindowDelegate', '-', 'windowRequired:', 'Fake', ''),
            ('protocol', 'NSObject', '-', 'class', 'objc', ''),
        ])

    def test_output_is_labelled_and_entry_points_reads_it(self):
        out = io.StringIO()
        ss.write_rows(out, ss.scan_sdk(FIXTURE_SDK), FIXTURE_SDK)
        text = out.getvalue()
        self.assertTrue(text.startswith('# SDK selectors from a text scan of SDK headers, interim until the code '
                                        'database records SDK declarations.\n'))
        self.assertIn('class\tFKWindow\t-\tselectNextTab:\tFake\taction\n', text)
        self.assertIn('class\tFKWindow\t-\ttitle\tFake\n', text)
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'sdk.tsv')
            with open(path, 'w') as f:
                f.write(text)
            # entry_points imports the code database's modules; load only its reader.
            sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'codedb'))
            import entry_points as ep
            decls = ep.load_sdk_selectors(path)
            self.assertEqual(decls[(False, 'selectNextTab:')], [ep.SDKDecl('FKWindow', 'class', 'Fake', False, True)])
            self.assertEqual(decls[(True, 'sharedWindow')], [ep.SDKDecl('FKWindow', 'class', 'Fake', False, False)])
        finally:
            for f in os.listdir(d):
                os.remove(os.path.join(d, f))
            os.rmdir(d)

    def test_main_refuses_a_directory_that_is_not_an_sdk(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            self.assertEqual(ss.main(['--sdk', d, os.path.join(d, 'out.tsv')]), 2)
        finally:
            os.rmdir(d)


def real_sdk():
    try:
        r = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    path = r.stdout.strip()
    return path if r.returncode == 0 and os.path.isdir(os.path.join(path, 'System', 'Library', 'Frameworks')) else None


class RealSDKSmokeTest(unittest.TestCase):
    def test_well_known_declarations_are_found(self):
        sdk = real_sdk()
        if sdk is None:
            print('\nSKIPPED: no SDK found by xcrun --show-sdk-path; the real-SDK smoke check of sdk_selectors.py did '
                  'not run', file=sys.stderr)
            self.skipTest('no SDK found by xcrun --show-sdk-path')
        rows = ss.scan_sdk(sdk)
        found = set((container, sign, sel) for _, container, sign, sel, _, _ in rows)
        flags = dict(((container, sign, sel), f) for _, container, sign, sel, _, f in rows)
        wanted = [('NSTableViewDelegate', '-', 'tableView:viewForTableColumn:row:'),
                     ('NSWindow', '-', 'canBecomeMainWindow'),
                     ('NSServicesMenuRequestor', '-', 'readSelectionFromPasteboard:'),
                     ('NSWindow', '-', 'selectNextTab:'),
                     ('WKNavigationDelegate', '-', 'webView:didFinishNavigation:'),
                     ('NSComboBoxDelegate', '-', 'comboBoxSelectionDidChange:'),
                     ('CAAnimationDelegate', '-', 'animationDidStop:finished:'),
                     ('NSOutlineViewDataSource', '-', 'outlineView:numberOfChildrenOfItem:'),
                     ('NSView', '-', 'isOpaque'),
                     ('NSResponder', '-', 'cursorUpdate:'),
                     ('NSViewController', '-', 'nibName'),
                     ('NSToolbarDelegate', '-', 'toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:'),
                     ('NSURLSessionDataDelegate', '-', 'URLSession:dataTask:didReceiveData:'),
                     ('NSViewContentSelectionInfo', '-', 'selectionAnchorRect'),
                     ('NSControl(NSDeprecated)', '+', 'cellClass'),
                     ('NSTask', '-', 'currentDirectoryURL'), ('NSTask', '-', 'setCurrentDirectoryURL:'),
                     ('NSTask', '-', 'terminationHandler'), ('NSTask', '-', 'setTerminationHandler:'),
                     ('NSURLHandle', '-', 'initWithURL:cached:'), ('NSWindow(NSDrawers)', '-', 'drawers')]
        self.assertEqual([w for w in wanted if w not in found], [])
        self.assertEqual(flags[('NSWindow', '-', 'selectNextTab:')], 'action')
        self.assertEqual(flags[('NSComboBoxDelegate', '-', 'comboBoxSelectionDidChange:')], 'optional')


# --- What the frameworks implement at run time (--runtime-methods) ------------------

class RuntimeMethodsTest(unittest.TestCase):
    def test_the_line_format(self):
        ok = ss._RUNTIME_LINE.match
        self.assertTrue(ok('C\tNSWindow\tNSResponder'))
        self.assertTrue(ok('C\tNSObject\t'))
        self.assertTrue(ok('M\tNSWindow\t-\t_usesCustomDrawing'))
        self.assertTrue(ok('M\tNSWindow\t+\twindowWithContentViewController:'))
        self.assertFalse(ok('M\tNSWindow\t*\tfoo'))
        self.assertFalse(ok('M\tNSWindow\t-\t'))
        self.assertFalse(ok('objc[123]: Class X is implemented in both A and B'))

    def test_a_compiler_that_fails_is_an_error(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            with self.assertRaises(ss.RuntimeListError):
                ss.write_runtime_methods(os.path.join(d, 'out.tsv'), clang=('false',))
            self.assertFalse(os.path.exists(os.path.join(d, 'out.tsv')))
        finally:
            import shutil
            shutil.rmtree(d)

    def test_the_os_version_of_a_system_version_plist(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'SystemVersion.plist')
            with open(path, 'wb') as f:
                import plistlib
                plistlib.dump({'ProductName': 'macOS', 'ProductVersion': '27.0', 'ProductBuildVersion': '26A428'}, f)
            self.assertEqual(ss.os_version(path), 'macOS 27.0 (26A428)')
        finally:
            import shutil
            shutil.rmtree(d)


DUMP_FIXTURE = os.path.join(HERE, 'fixtures', 'sdk_selectors', 'RuntimeHeaders')


class DumpedHeadersTest(unittest.TestCase):
    """--runtime-methods-from-headers: a runtime method list converted from
    a tree of dumped runtime headers."""

    def test_method_selectors_take_the_keyword_parts_outside_parentheses(self):
        sel = ss.dumped_method_selector
        self.assertEqual(sel('- (id)scrollerImpPair;'), ('-', 'scrollerImpPair'))
        self.assertEqual(sel('+ (struct CGSize { double x0; double x1; })frameSizeForContentSize:(struct CGSize { '
                             'double x0; double x1; })a0 hasHorizontalScroller:(BOOL)a1;'),
                         ('+', 'frameSizeForContentSize:hasHorizontalScroller:'))
        self.assertEqual(sel('- (void)_performWithCompletion:(void (^ /* unknown block signature */)(id, BOOL))a0 '
                             'queue:(id)a1;'), ('-', '_performWithCompletion:queue:'))
        self.assertEqual(sel('- (id)_nested:(id<NSCopying> (^)(NSDictionary<NSString *, NSArray<id> *> *))a0;'),
                         ('-', '_nested:'))
        self.assertEqual(sel('- (void)_anonymous:(id)a0 :(id)a1;'), ('-', '_anonymous::'))
        # A selector whose first part has no name, and the compiler's
        # .cxx_destruct and .cxx_construct, are kept.
        self.assertEqual(sel('- (void):(id)a0 :(id)a1;'), ('-', '::'))
        self.assertEqual(sel('- (void):(id)a0 :(id)a1 newValue:(id)a2;'), ('-', '::newValue:'))
        self.assertEqual(sel('- (void).cxx_destruct;'), ('-', '.cxx_destruct'))
        self.assertEqual(sel('- (id).cxx_construct;'), ('-', '.cxx_construct'))
        self.assertEqual(sel('- (void)_drawRect:(struct CGRect { struct CGPoint { double x0; double x1; } x0; '
                             'struct CGSize { double x0; double x1; } x1; })a0 clip:(BOOL)a1;'),
                         ('-', '_drawRect:clip:'))
        self.assertIsNone(sel('@property BOOL x;'))
        self.assertIsNone(sel('- (void);'))

    def test_property_selectors(self):
        prop = ss.dumped_property_selectors
        self.assertEqual(prop('@property (class) Class rulerViewClass;'),
                         [('+', 'rulerViewClass'), ('+', 'setRulerViewClass:')])
        self.assertEqual(prop('@property (class, readonly) Class _horizontalScrollerClass;'),
                         [('+', '_horizontalScrollerClass')])
        self.assertEqual(prop('@property (readonly) struct NSEdgeInsets { double x0; double x1; double x2; double x3; '
                              '} _distancesScrolledFromDocumentEdges;'), [('-', '_distancesScrolledFromDocumentEdges')])
        self.assertEqual(prop('@property (nonatomic, setter=_setContentExtendsUnderHeader:) BOOL '
                              '_contentExtendsUnderHeader;'),
                         [('-', '_contentExtendsUnderHeader'), ('-', '_setContentExtendsUnderHeader:')])
        self.assertEqual(prop('@property (getter=isFindBarVisible) BOOL findBarVisible;'),
                         [('-', 'isFindBarVisible'), ('-', 'setFindBarVisible:')])
        self.assertEqual(prop('@property (copy, nonatomic) id /* block */ scrollHandler;'),
                         [('-', 'scrollHandler'), ('-', 'setScrollHandler:')])

    def test_the_fixture_tree_converts_to_a_list_entry_points_reads(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'runtime.tsv')
            out = io.StringIO()
            with unittest.mock.patch('sys.stdout', out):
                self.assertEqual(ss.main(['--runtime-methods-from-headers', DUMP_FIXTURE, '--os', 'macOS 13.6',
                                          '--source', 'fixture dump', path]), 0)
            self.assertIn('read 5 headers', out.getvalue())
            with open(path) as f:
                lines = f.read().split('\n')
            self.assertIn('# os: macOS 13.6', lines)
            self.assertIn('# kind: dumped-headers', lines)
            body_lines = [line for line in lines if line and not line.startswith('#')]
            self.assertEqual(lines[-2], '# end: C=%d M=%d' % (sum(1 for line in body_lines if line[0] == 'C'),
                                                             sum(1 for line in body_lines if line[0] == 'M')))
            self.assertEqual(lines[-1], '')
            self.assertIn('# source: fixture dump', lines)
            self.assertTrue(any(line.startswith('# Runtime methods: ' + ss.DUMP_LABEL) for line in lines))
            body = set(line for line in lines if line and not line.startswith('#'))
            self.assertTrue({'C\tNSScrollView\tNSView', 'C\tNSObject\t', 'C\tFixtureRoot\t',
                             'M\tNSScrollView\t+\tframeSizeForContentSize:hasHorizontalScroller:',
                             'M\tNSScrollView\t-\t_anonymous::', 'M\tNSScrollView\t+\tsetRulerViewClass:',
                             'M\tNSView\t-\tcategoryMethodOnView:', 'M\tNSObject\t+\talloc',
                             'M\tFixtureRoot\t-\trootOnly'} <= body, body)
            # No class line for a category, nothing from a protocol or a file
            # that is not a header.
            self.assertFalse(any(line.startswith('C\tNSView\t') for line in body))
            self.assertFalse(any('scrollViewProtocolOnly' in line or 'NotAClass' in line for line in body))
            self.assertEqual(sum(1 for line in body if line.startswith('M\tNSScrollView\t')), 20)
            sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'codedb'))
            import entry_points as ep
            rt = ep.load_runtime_methods(path)
            self.assertEqual(rt.os_version, 'macOS 13.6')
            self.assertEqual(rt.implementer('NSScrollView', False, 'allowedPocketEdges'), 'NSScrollView')
        finally:
            import shutil
            shutil.rmtree(d)

    def test_a_failed_conversion_leaves_no_list(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'runtime.tsv')
            with unittest.mock.patch.object(ss, 'scan_dumped_header', side_effect=RuntimeError('boom')):
                with self.assertRaises(RuntimeError):
                    ss.write_runtime_methods_from_headers(DUMP_FIXTURE, 'macOS 13.6', path)
            self.assertEqual(os.listdir(d), [])
        finally:
            import shutil
            shutil.rmtree(d)

    def test_the_os_is_required(self):
        err = io.StringIO()
        with unittest.mock.patch('sys.stderr', err):
            self.assertEqual(ss.main(['--runtime-methods-from-headers', DUMP_FIXTURE, '/dev/null']), 2)


def have_compiler():
    try:
        r = subprocess.run(['xcrun', '--find', 'clang'], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


class LiveWriterTest(unittest.TestCase):
    """--runtime-methods without running the compiler: the header, the
    trailer, frameworks that fail to load, and --app-bundle."""

    def fake_run(self, lines, loaded):
        """A subprocess.run stand-in: the compiler succeeds; the program
        prints lines and reports each framework as loaded or not."""
        def run(argv, **kw):
            if kw.get('stdout') is not None and not kw.get('capture_output'):
                kw['stdout'].write(''.join(line + '\n' for line in lines))
                stderr = ''.join('%s\t%s\n' % ('loaded' if ok else 'not loaded', p) for p, ok in zip(argv[1:], loaded))
                return subprocess.CompletedProcess(argv, 0, None, stderr)
            return subprocess.CompletedProcess(argv, 0, '', '')
        return run

    def test_the_list_has_a_kind_and_a_trailer_and_entry_points_reads_it(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'runtime.tsv')
            lines = ['C\tNSObject\t', 'M\tNSObject\t-\tdescription', 'C\tNSView\tNSObject']
            with unittest.mock.patch.object(ss.subprocess, 'run', self.fake_run(lines, [True, True])):
                written, loaded, skipped, version = ss.write_runtime_methods(path, frameworks=('AppKit', 'Foundation'))
            with open(path) as f:
                text = f.read().split('\n')
            self.assertIn('# kind: live', text)
            self.assertEqual(text[-2], '# end: C=2 M=1')
            sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'codedb'))
            import entry_points as ep
            rt = ep.load_runtime_methods(path)
            self.assertEqual((rt.kind, rt.frameworks), ('live', [('AppKit', True), ('Foundation', True)]))
            self.assertEqual(sorted(os.listdir(d)), ['runtime.tsv'])
        finally:
            import shutil
            shutil.rmtree(d)

    def test_a_framework_that_does_not_load_fails_the_run_unless_allowed(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'runtime.tsv')
            for argv, expected in ((['--runtime-methods', path], 1),
                                   (['--runtime-methods', '--allow-missing-frameworks', path], 0)):
                run = self.fake_run(['C\tNSObject\t'], [True, False] + [True] * 60)
                out = io.StringIO()
                with unittest.mock.patch.object(ss.subprocess, 'run', run), unittest.mock.patch('sys.stdout', out), \
                        unittest.mock.patch('sys.stderr', out):
                    self.assertEqual(ss.main(argv), expected, out.getvalue())
                self.assertIn('not loaded: %s' % ss.RUNTIME_FRAMEWORKS[1], out.getvalue())
                with open(path) as f:
                    self.assertIn('%s (not loaded)' % ss.RUNTIME_FRAMEWORKS[1], f.read())
        finally:
            import shutil
            shutil.rmtree(d)

    def test_app_bundle_frameworks_are_loaded_by_path(self):
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            fw = os.path.join(d, 'iTerm2.app', 'Contents', 'Frameworks')
            for name in ('Sparkle', 'NMSSH'):
                os.makedirs(os.path.join(fw, name + '.framework'))
                open(os.path.join(fw, name + '.framework', name), 'w').close()
            os.makedirs(os.path.join(fw, 'Empty.framework'))
            open(os.path.join(fw, 'libfoo.dylib'), 'w').close()
            got = ss.runtime_binaries(('AppKit',), os.path.join(d, 'iTerm2.app'))
            self.assertEqual(got, [ss.framework_binary('AppKit'), os.path.join(fw, 'NMSSH.framework', 'NMSSH'),
                                   os.path.join(fw, 'Sparkle.framework', 'Sparkle'), os.path.join(fw, 'libfoo.dylib')])
            self.assertEqual(ss.runtime_binaries(('AppKit',), None), [ss.framework_binary('AppKit')])
        finally:
            import shutil
            shutil.rmtree(d)


class RealRuntimeSmokeTest(unittest.TestCase):
    def test_well_known_runtime_facts(self):
        if not have_compiler():
            print('\nSKIPPED: no compiler found by xcrun --find clang; the real-runtime smoke check of '
                  'sdk_selectors.py --runtime-methods did not run', file=sys.stderr)
            self.skipTest('no compiler found by xcrun --find clang')
        d = tempfile.mkdtemp(prefix='sdk-selectors-test-')
        try:
            path = os.path.join(d, 'runtime.tsv')
            out = io.StringIO()
            with unittest.mock.patch('sys.stdout', out):
                self.assertEqual(ss.main(['--runtime-methods', path]), 0)
            self.assertIn('Results from it are INCOMPLETE by nature', out.getvalue())
            self.assertIn('frameworks loaded: %d of %d' % (len(ss.RUNTIME_FRAMEWORKS), len(ss.RUNTIME_FRAMEWORKS)),
                          out.getvalue())
            with open(path) as f:
                head = [next(f) for _ in range(5)]
            self.assertTrue(any(line.startswith('# os: ') for line in head), head)
            sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'codedb'))
            import entry_points as ep
            rt = ep.load_runtime_methods(path)
            self.assertEqual(rt.implementer('NSObject', False, 'description'), 'NSObject')
            self.assertEqual(rt.superclass('NSWindow'), 'NSResponder')
            self.assertEqual(rt.implementer('NSView', False, 'drawRect:'), 'NSView')
        finally:
            import shutil
            shutil.rmtree(d)


if __name__ == '__main__':
    unittest.main()
