#!/usr/bin/env python3
"""The Objective-C selectors the SDK declares, from a text scan of its
headers: an interim source for entry_points.py --sdk-selectors, until the
code database records SDK declarations (the sdk_method table).

Part of the Objective-C to Swift migration (docs/swift-migration/phase0.md,
section 2). A method of a repository class whose selector the SDK declares
may be called by the system (an override, a delegate or data source method,
a services method, an action sent through the responder chain), so the
entry-point census never lists it as having no caller.

This is a text scan, which the project accepts only for what the compiler
does not give, and it is labelled as such in its output: it reads every
Headers/*.h under System/Library/Frameworks of the SDK (frameworks nested in
frameworks too) and usr/include/objc/*.h, strips comments and preprocessor
lines (so both branches of an #if are read, which can only add selectors),
recognizes @interface (class or category) and @protocol containers, method
declarations joined across lines up to ;, and @property declarations, from
which it derives the getter and, unless readonly, the setter, honoring
getter= and setter= and class properties. Availability and nullability
macros are tolerated wherever they appear.

Usage: sdk_selectors.py [--sdk PATH] [--strict] OUTPUT
       sdk_selectors.py --runtime-methods [--allow-missing-frameworks] [--app-bundle PATH] OUTPUT
       sdk_selectors.py --runtime-methods-from-headers DIR --os NAME [--source TEXT] OUTPUT
The SDK defaults to `xcrun --show-sdk-path`. OUTPUT gets one line per
declaration: kind<TAB>container<TAB>+|-<TAB>selector<TAB>framework[<TAB>flags]
(kind: class, protocol or category, a category's container written
Class(Category); flags: optional for an @optional protocol method, action for
a method declared to return IBAction), after # comment lines that say what it
is. A declaration inside an @interface or @protocol that begins with -, + or
@property and from which no selector could be read is counted, and the count
and the first 20 are printed; --strict makes that exit status 1.

--runtime-methods writes instead what the frameworks IMPLEMENT at run time,
private methods included, for entry_points.py --runtime-methods: a method of a
repository class that overrides a private framework method is called by the
framework, and no header declares it. It compiles a small Objective-C program
with xcrun clang in a temporary directory and runs it: the program loads the
frameworks of RUNTIME_FRAMEWORKS with dlopen, walks objc_copyClassList and
prints, for every class, its superclass and every instance and class method it
implements itself (class_copyMethodList of the class and of its metaclass).
It reads only the runtime of the machine it runs on: it launches no app,
sends no message to any class, and needs no window server. OUTPUT gets lines
C<TAB>class<TAB>superclass (empty for a root class) and
M<TAB>class<TAB>+|-<TAB>selector after # comment lines, among them
"# os: NAME VERSION (BUILD)", "# kind: live" and "# frameworks: ..." (each
framework loaded, or marked "(not loaded)"), and ends with a trailer line
"# end: C=n M=n" giving the counts, so that a list cut short is refused; it
is written to a temporary file and renamed. A framework that does not load
makes the exit status 1 unless --allow-missing-frameworks is given.
--app-bundle PATH also loads, by path, the frameworks and dylibs in
PATH/Contents/Frameworks of a built app, whose categories on framework
classes a list without them does not show. The list is specific to that OS release: a
private method present on one release may be absent on another, so it must
be regenerated for each release, and results from it are incomplete by
nature.

--runtime-methods-from-headers DIR --os NAME writes the same format from a
tree of dumped runtime headers of one release (for releases no machine at
hand runs; see "A runtime list from dumped runtime headers" below), with
"# kind: dumped-headers", a "# source:" line and the same trailer. The
headers are read as text and nothing in them is run; run this with
python3 -I. Such a list misses the methods other images add to a class
through categories, so it is weaker than one from --runtime-methods.
"""

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

LABEL = 'from a text scan of SDK headers, interim until the code database records SDK declarations'

_IDENT = re.compile(r'[A-Za-z_]\w*')
_BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.S)
_LINE_COMMENT = re.compile(r'//[^\n]*')
_DIRECTIVE = re.compile(r'^[ \t]*#(?:[^\n]*\\\n)*[^\n]*', re.M)
# A method declaration begins a line with - or + and a return type in
# parentheses or, for one that returns id written without it (NSURLHandle.h:
# - initWithURL:cached:), its first keyword.
_EVENT = re.compile(r'@interface\b|@protocol\b|@end\b|@optional\b|@required\b|@property\b|'
                    r'^[ \t]*[-+][ \t]*(?:\(|[A-Za-z_])', re.M)
# A trailing attribute macro: an identifier with an upper-case letter or an
# underscore and no lower-case letter (API_AVAILABLE, NS_SWIFT_NAME, NS_REFINED_FOR_SWIFT), or
# __attribute__, optionally followed by a parenthesized argument list.
_MACRO_NAME = re.compile(r'^(?:__attribute__|[A-Z_][A-Z0-9_]*)$')


def strip_source(text):
    """Text without comments and preprocessor lines, with line breaks kept."""
    def blank(m):
        return re.sub(r'[^\n]', ' ', m.group(0))
    text = _BLOCK_COMMENT.sub(blank, text)
    text = _LINE_COMMENT.sub('', text)
    return _DIRECTIVE.sub(blank, text)


def skip_parens(s, i):
    """The index just past the balanced parenthesized group starting at
    s[i] == '(' (len(s) if it does not close)."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(s)


def skip_space(s, i):
    while i < len(s) and s[i].isspace():
        i += 1
    return i


def declaration_end(text, start):
    """The index of the ; that ends the declaration beginning at start, past
    string and character literals and parentheses (API_DEPRECATED("...; ...",
    ...)), or -1."""
    depth = 0
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c in '"\'':
            i += 1
            while i < n and text[i] != c and text[i] != '\n':
                i += 2 if text[i] == '\\' else 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth = max(0, depth - 1)
        elif c == ';' and depth == 0:
            return i
        elif c == '@' and depth == 0 and text.startswith('@end', i):
            return -1 if i == start else i
        i += 1
    return -1


def method_selector(decl):
    """(selector, is_class_method, returns IBAction) of a method declaration
    beginning with - or + (up to its ;), or None."""
    i = skip_space(decl, 0)
    if i >= len(decl) or decl[i] not in '+-':
        return None
    is_class = decl[i] == '+'
    i = skip_space(decl, i + 1)
    if i < len(decl) and decl[i] == '(':
        end = skip_parens(decl, i)
        result = ' '.join(decl[i + 1:end - 1].split())
        i = skip_space(decl, end)
    else:
        result = 'id'  # no return type written: it returns id
    m = _IDENT.match(decl, i)
    if not m:
        return None
    first = m.group(0)
    i = skip_space(decl, m.end())
    if i >= len(decl) or decl[i] != ':':
        return first, is_class, result == 'IBAction'
    parts = []
    label = first
    while True:
        parts.append(label + ':')
        i = skip_space(decl, i + 1)  # past ':'
        if i < len(decl) and decl[i] == '(':
            i = skip_space(decl, skip_parens(decl, i))
        m = _IDENT.match(decl, i)
        if m:
            i = skip_space(decl, m.end())  # the parameter's name
        # Another part: a label followed by ':', or an unlabeled ':'.
        if i < len(decl) and decl[i] == ':':
            label = ''
            continue
        m = _IDENT.match(decl, i)
        if m:
            j = skip_space(decl, m.end())
            if j < len(decl) and decl[j] == ':':
                label = m.group(0)
                i = j
                continue
        break
    return ''.join(parts), is_class, result == 'IBAction'


def strip_trailing_macros(s):
    """s without trailing attribute macros and their argument lists: every
    trailing run of them (API_AVAILABLE(...) API_UNAVAILABLE(...)) is taken
    off, then the longest prefix that still ends in a declared name after a
    type is kept, so that a name in capitals (NSInteger ID) is not taken for
    a macro."""
    candidates = [s.rstrip()]
    while True:
        stripped = strip_one_macro(candidates[-1])
        if stripped is None:
            break
        candidates.append(stripped.rstrip())
    for c in reversed(candidates):
        if has_name(c):
            return c
    return candidates[0]


def strip_one_macro(s):
    """s without its last token when that is an attribute macro (with its
    argument list, if any), or None."""
    s = s.rstrip()
    if s.endswith(')'):
        depth = 0
        k = len(s) - 1
        while k >= 0:
            if s[k] == ')':
                depth += 1
            elif s[k] == '(':
                depth -= 1
                if depth == 0:
                    break
            k -= 1
        if k < 0:
            return None
        m = re.search(r'([A-Za-z_]\w*)\s*$', s[:k])
        return s[:m.start(1)] if m and _MACRO_NAME.match(m.group(1)) else None
    m = re.search(r'([A-Za-z_]\w*)$', s)
    return s[:m.start(1)] if m and _MACRO_NAME.match(m.group(1)) else None


def has_name(s):
    """Whether s still ends in a declared name after a type (so that what
    follows it can be an attribute macro, not the name itself)."""
    return bool(re.search(r'[\w*>)\]][\s*]+\w+\s*$', s) or re.search(r'\)\s*\(.*\)\s*$', s))


def property_selectors(decl):
    """[(selector, is_class_method)] of an @property declaration (up to its
    ;): the getter and, unless readonly, the setter of each name."""
    s = decl.strip()
    if not s.startswith('@property'):
        return []
    s = s[len('@property'):]
    attrs = []
    i = skip_space(s, 0)
    if i < len(s) and s[i] == '(':
        end = skip_parens(s, i)
        attrs = [a.strip() for a in s[i + 1:end - 1].split(',')]
        s = s[end:]
    getter = setter = None
    readonly = is_class = False
    for a in attrs:
        m = re.match(r'^getter\s*=\s*(\w+)$', a)
        if m:
            getter = m.group(1)
        m = re.match(r'^setter\s*=\s*([\w:]+)$', a)
        if m:
            setter = m.group(1)
        readonly = readonly or a == 'readonly'
        is_class = is_class or a == 'class'
    names = []
    for part in split_top_level(strip_trailing_macros(s)):
        part = strip_trailing_macros(part)
        m = _BLOCK_NAME.search(part)
        if m:  # a block or function pointer: void (^name)(...), void (NS_SWIFT_SENDABLE ^name)(...)
            names.append(m.group(1))
            continue
        m = re.search(r'(\w+)\s*(?:\[[^\]]*\])?\s*$', part)
        if m:
            names.append(m.group(1))
    out = []
    for name in names:
        out.append((getter or name, is_class))
        if not readonly:
            out.append((setter or 'set%s%s:' % (name[:1].upper(), name[1:]), is_class))
    return out


# The name of a block or function pointer property: (^name)(, with
# attribute macros before the caret (NS_SWIFT_SENDABLE ^name) and
# nullability or macros after it.
_BLOCK_NAME = re.compile(r'\(\s*(?:[A-Z_][A-Z0-9_]*\s+)*[\^*]\s*(?:(?:_Nullable|_Nonnull|_Null_unspecified|__nullable|'
                         r'__nonnull|[A-Z_][A-Z0-9_]*)\s+)*(\w+)\s*\)\s*\(')


def split_top_level(s):
    """s split at commas outside (), <> and []."""
    parts, depth, start = [], 0, 0
    for k, c in enumerate(s):
        if c in '(<[':
            depth += 1
        elif c in ')>]':
            depth -= 1
        elif c == ',' and depth == 0:
            parts.append(s[start:k])
            start = k + 1
    parts.append(s[start:])
    return [p for p in parts if p.strip()]


_INTERFACE = re.compile(r'@interface\s+(\w+)\s*(?:<[^>]*>)?\s*(?:\(\s*(\w*)\s*\))?')
_PROTOCOL = re.compile(r'@protocol\s+(\w+)')


def scan_header(text, failures=None):
    """[(kind, container, sign, selector, flags)] of one header's text.
    failures, if given, gets (line, first line of the declaration) for every
    declaration inside an @interface or @protocol that begins with -, + or
    @property and from which no selector could be read: the scan never
    loses one in silence."""
    text = strip_source(text)
    out = []
    container = None  # (kind, name)
    optional = False
    pos = 0
    while True:
        m = _EVENT.search(text, pos)
        if not m:
            break
        token = m.group(0).strip()
        start = m.start() + (len(m.group(0)) - len(m.group(0).lstrip()))
        if token == '@interface':
            im = _INTERFACE.match(text, start)
            if im:
                if im.group(2) is not None:
                    container = ('category', '%s(%s)' % (im.group(1), im.group(2)))
                else:
                    container = ('class', im.group(1))
                optional = False
            pos = m.end()
            continue
        if token == '@protocol':
            pm = _PROTOCOL.match(text, start)
            if pm:
                k = skip_space(text, pm.end())
                if k < len(text) and text[k] in ';,':
                    pos = k + 1  # a forward declaration
                    continue
                if k < len(text) and text[k] == '(':
                    pos = pm.end()  # @protocol(Name) in an expression
                    continue
                container = ('protocol', pm.group(1))
                optional = False
            pos = m.end()
            continue
        if token == '@end':
            container = None
            optional = False
            pos = m.end()
            continue
        if token == '@optional':
            optional = True
            pos = m.end()
            continue
        if token == '@required':
            optional = False
            pos = m.end()
            continue
        end = declaration_end(text, start)
        if end < 0:
            break
        decl = text[start:end]
        pos = end + 1
        if container is None:
            continue
        kind, name = container
        is_optional = optional and kind == 'protocol'
        found = False
        if token == '@property':
            for sel, is_class in property_selectors(decl):
                found = True
                out.append((kind, name, '+' if is_class else '-', sel, 'optional' if is_optional else ''))
        else:
            r = method_selector(decl)
            if r:
                found = True
                sel, is_class, action = r
                flags = [f for f, on in (('optional', is_optional), ('action', action)) if on]
                out.append((kind, name, '+' if is_class else '-', sel, ','.join(flags)))
        if not found and failures is not None:
            failures.append((text.count('\n', 0, start) + 1, ' '.join(decl.split('\n')[0].split())))
    return out


def header_files(sdk):
    """[(path, framework)] of the headers to scan, each file once."""
    out = []
    seen = set()
    frameworks = os.path.join(sdk, 'System', 'Library', 'Frameworks')
    for d, dirs, files in os.walk(frameworks, followlinks=True):
        dirs.sort()
        if os.path.basename(d) != 'Headers':
            continue
        parts = [p for p in os.path.relpath(d, frameworks).split(os.sep) if p.endswith('.framework')]
        framework = parts[-1][:-len('.framework')] if parts else '?'
        for f in sorted(files):
            if f.endswith('.h'):
                path = os.path.join(d, f)
                real = os.path.realpath(path)
                if real not in seen:
                    seen.add(real)
                    out.append((path, framework))
    objc = os.path.join(sdk, 'usr', 'include', 'objc')
    if os.path.isdir(objc):
        for f in sorted(os.listdir(objc)):
            if f.endswith('.h'):
                path = os.path.join(objc, f)
                real = os.path.realpath(path)
                if real not in seen:
                    seen.add(real)
                    out.append((path, 'objc'))
    return out


def scan_sdk(sdk, failures=None):
    """Sorted, distinct (kind, container, sign, selector, framework, flags).
    failures, if given, gets (path, line, text) of every declaration the
    scanner could not read (scan_header)."""
    rows = set()
    for path, framework in header_files(sdk):
        try:
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                text = f.read()
        except OSError:
            continue
        lost = []
        for kind, container, sign, sel, flags in scan_header(text, lost):
            rows.add((kind, container, sign, sel, framework, flags))
        if failures is not None:
            failures.extend((path, n, decl) for n, decl in lost)
    return sorted(rows)


def write_rows(out, rows, sdk):
    out.write('# SDK selectors %s.\n' % LABEL)
    out.write('# sdk: %s\n' % sdk)
    out.write('# columns: kind, container, +|-, selector, framework, flags (optional, action)\n')
    for kind, container, sign, sel, framework, flags in rows:
        out.write('\t'.join([kind, container, sign, sel, framework] + ([flags] if flags else [])) + '\n')


# --- What the frameworks implement at run time ------------------------------------

# The system frameworks the app's targets link (iTerm2.xcodeproj's Frameworks
# build phases) or import (#import <X/...>, @import X and Swift import X in
# sources/, which autolinking links), as of this writing. The frameworks
# built from this repository or shipped in it (NMSSH, CoreParse, Sparkle,
# BetterFontPicker and the others) are not system frameworks; their classes
# are not listed.
RUNTIME_FRAMEWORKS = (
    'AVFoundation', 'AVKit', 'AppKit', 'ApplicationServices', 'AudioToolbox', 'Carbon', 'Cocoa', 'Contacts',
    'CoreData', 'CoreFoundation', 'CoreGraphics', 'CoreImage', 'CoreLocation', 'CoreMedia', 'CoreServices',
    'CoreText', 'CoreVideo', 'Foundation', 'IOKit', 'ImageIO', 'JavaScriptCore', 'LocalAuthentication', 'Metal',
    'MetalKit', 'NaturalLanguage', 'Network', 'OpenDirectory', 'Quartz', 'QuartzCore', 'QuickLookUI',
    'ScreenCaptureKit', 'ScriptingBridge', 'Security', 'SwiftUI', 'SystemConfiguration', 'UniformTypeIdentifiers',
    'UserNotifications', 'VideoToolbox', 'WebKit',
    # Imported by Swift files in sources/ (autolinked) and missing from the
    # first version of this list (2026-11-20): Charts
    # (iTermHistogramVisualizationView), CryptoKit, FoundationModels (AITerm)
    # and OSLog; AddressBook is in the project's Frameworks build phase.
    'AddressBook', 'Charts', 'CryptoKit', 'FoundationModels', 'OSLog',
)
RUNTIME_LABEL = ('the methods the frameworks implement at run time, private methods included, from the Objective-C '
                 'runtime of the machine that wrote this file')
RUNTIME_PROGRAM = r"""
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

static void print_methods(Class cls, const char *name, char sign) {
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        printf("M\t%s\t%c\t%s\n", name, sign, sel_getName(method_getName(list[i])));
    }
    free(list);
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        void *handle = dlopen(argv[i], RTLD_LAZY | RTLD_GLOBAL);
        fprintf(stderr, "%s\t%s\n", handle ? "loaded" : "not loaded", argv[i]);
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        Class superclass = class_getSuperclass(classes[i]);
        printf("C\t%s\t%s\n", name, superclass ? class_getName(superclass) : "");
        print_methods(classes[i], name, '-');
        print_methods(object_getClass((id)classes[i]), name, '+');
    }
    free(classes);
    return 0;
}
"""
_RUNTIME_LINE = re.compile(r'^(?:C\t[^\t\n]+\t[^\t\n]*|M\t[^\t\n]+\t[-+]\t[^\t\n]+)$')


class RuntimeListError(Exception):
    """The runtime list could not be written."""


def os_version(path='/System/Library/CoreServices/SystemVersion.plist'):
    """NAME VERSION (BUILD) of the running OS."""
    with open(path, 'rb') as f:
        info = plistlib.load(f)
    return '%s %s (%s)' % (info.get('ProductName', '?'), info.get('ProductVersion', '?'),
                           info.get('ProductBuildVersion', '?'))


def framework_binary(name):
    return '/System/Library/Frameworks/%s.framework/%s' % (name, name)


def runtime_binaries(frameworks, app_bundle=None):
    """The paths the program loads: the system frameworks, then, with
    app_bundle, every framework binary and dylib in its Contents/Frameworks
    (the app's own embedded frameworks, loaded by path)."""
    out = [framework_binary(f) for f in frameworks]
    if app_bundle:
        fw = os.path.join(app_bundle, 'Contents', 'Frameworks')
        names = sorted(os.listdir(fw)) if os.path.isdir(fw) else []
        for name in names:
            if name.endswith('.framework'):
                binary = os.path.join(fw, name, name[:-len('.framework')])
                if os.path.isfile(binary):
                    out.append(binary)
        out += [os.path.join(fw, name) for name in names if name.endswith('.dylib')]
    return out


def atomic_output(output):
    """A temporary file next to output, to be renamed onto it once written
    in full, so that a run cut short leaves no list behind."""
    fd, tmp = tempfile.mkstemp(prefix='.' + os.path.basename(output) + '.',
                               dir=os.path.dirname(os.path.abspath(output)))
    os.close(fd)
    return tmp


def write_runtime_methods(output, frameworks=RUNTIME_FRAMEWORKS, clang=('xcrun', 'clang'), app_bundle=None):
    """Compile and run the program, then write OUTPUT: the header (with
    "# kind: live"), the program's lines, streamed, and a trailer line
    "# end: C=n M=n"; written to a temporary file and renamed. Returns
    (lines written, [(framework, loaded)], lines of the program's output
    that are not in the format, which are left out, OS version). Raises
    RuntimeListError when clang fails or the program does."""
    d = tempfile.mkdtemp(prefix='runtime-methods-')
    try:
        src = os.path.join(d, 'runtime_methods.m')
        exe = os.path.join(d, 'runtime_methods')
        with open(src, 'w') as f:
            f.write(RUNTIME_PROGRAM)
        try:
            r = subprocess.run(list(clang) + ['-x', 'objective-c', '-O0', '-w', '-o', exe, src, '-lobjc'],
                               capture_output=True, text=True)
        except OSError as e:
            raise RuntimeListError('cannot run %s (%s)' % (' '.join(clang), e.strerror or e))
        if r.returncode != 0:
            raise RuntimeListError('%s failed: %s' % (' '.join(clang), r.stderr.strip()[:2000]))
        raw = os.path.join(d, 'raw.tsv')
        with open(raw, 'w') as out:
            r = subprocess.run([exe] + runtime_binaries(frameworks, app_bundle), stdout=out, stderr=subprocess.PIPE,
                               text=True)
        if r.returncode != 0:
            raise RuntimeListError('the runtime program exited %d: %s' % (r.returncode, r.stderr.strip()[:2000]))
        loaded = []
        for line in r.stderr.split('\n'):
            state, _, path = line.partition('\t')
            if path:
                loaded.append((os.path.basename(path), state == 'loaded'))
        version = os_version()
        written = skipped = classes = methods = 0
        tmp = atomic_output(output)
        try:
            with open(raw, 'r', encoding='utf-8', errors='replace') as src_lines, \
                    open(tmp, 'w', encoding='utf-8') as out:
                out.write('# Runtime methods: %s.\n' % RUNTIME_LABEL)
                out.write('# os: %s\n' % version)
                out.write('# kind: live\n')
                out.write('# Specific to that OS version: a private method present on one release may be absent on '
                          'another, so this list must be regenerated for each OS release, and results from it are '
                          'INCOMPLETE by nature.\n')
                out.write('# frameworks: %s\n' % ', '.join('%s%s' % (name, '' if ok else ' (not loaded)')
                                                           for name, ok in loaded))
                out.write('# columns: C<TAB>class<TAB>superclass (empty for a root class), M<TAB>class<TAB>+|-<TAB>'
                          'selector\n')
                for line in src_lines:
                    line = line.rstrip('\n')
                    if _RUNTIME_LINE.match(line):
                        out.write(line + '\n')
                        written += 1
                        if line[0] == 'C':
                            classes += 1
                        else:
                            methods += 1
                    elif line:
                        skipped += 1
                out.write('# end: C=%d M=%d\n' % (classes, methods))
        except BaseException:
            os.unlink(tmp)
            raise
        os.replace(tmp, output)
        return written, loaded, skipped, version
    finally:
        shutil.rmtree(d, ignore_errors=True)


def runtime_main(output, allow_missing=False, app_bundle=None):
    try:
        written, loaded, skipped, version = write_runtime_methods(output, app_bundle=app_bundle)
    except (RuntimeListError, OSError) as e:
        print('sdk_selectors: error: %s' % e, file=sys.stderr)
        return 2
    missing = [name for name, ok in loaded if not ok]
    print('sdk_selectors: wrote %d lines of %s to %s' % (written, RUNTIME_LABEL, output))
    print('sdk_selectors: frameworks loaded: %d of %d%s' % (len(loaded) - len(missing), len(loaded),
                                                            ' (not loaded: %s)' % ', '.join(missing) if missing else ''))
    if skipped:
        print('sdk_selectors: %d lines of the program\'s output were not in the format and were left out' % skipped)
    print('sdk_selectors: this list is specific to %s: a private method present on one release may be absent on '
          'another; regenerate it for each OS release. Results from it are INCOMPLETE by nature.' % version)
    if missing and not allow_missing:
        print('sdk_selectors: error: frameworks did not load (not loaded: %s); the list marks them, and the census '
              'names them; --allow-missing-frameworks accepts that' % ', '.join(missing), file=sys.stderr)
        return 1
    return 0


# --- A runtime list from dumped runtime headers -----------------------------------
#
# Public dumps of the Objective-C runtime of past OS releases exist as trees
# of machine-written headers, one class per file (for example the
# kissalexandra/Runtime-Headers repository, one tarball per macOS release).
# --runtime-methods-from-headers DIR --os NAME OUTPUT converts such a tree
# into the format --runtime-methods writes, so a list per release can be
# given to entry_points.py. The headers are data: they are read as text and
# nothing in them is run. Their forms, as dumped:
#   @interface Name : Super <Protocols> {      a class and its superclass
#   @interface Name <Protocols> {  or  @interface Name   a root class
#   @interface Name (Category)                 a category: methods go to Name
#   @protocol Name ...                         skipped up to its @end
#   - (type)part:(type)a0 part:(type)a1;       a method; types may hold
#                                              parentheses, blocks and braces
#   @property (attrs) type name;               a getter (getter=), and a setter
#                                              (setter=) unless readonly;
#                                              class properties are + methods
# The dumps are not the live runtime: they miss what other images add to a
# class through categories (methods frameworks add to NSObject, among
# others), so a list from them is weaker than one from --runtime-methods.

_DUMP_INTERFACE = re.compile(r'^@interface\s+([A-Za-z_$][\w$.]*)\s*(?:\(\s*([\w$]*)\s*\)|:\s*([A-Za-z_$][\w$.]*))?')
_DUMP_PROPERTY = re.compile(r'^@property\s*(?:\(([^)]*)\))?\s*(.*?)\s*;\s*$')
_IDENT = re.compile(r'[A-Za-z_$][\w$]*')
_CXX = re.compile(r'\.cxx_(?:destruct|construct)\b')
DUMP_LABEL = 'derived from dumped runtime headers, not from a live runtime'


def skip_balanced(s, i):
    """The index after the balanced parenthesized group that starts at s[i]
    ('('), or len(s) if it does not close."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(s)


def dumped_method_selector(line):
    """(sign, selector) of a dumped method declaration line, or None: the
    keyword parts outside balanced parentheses (an empty keyword, as in
    foo::, is kept)."""
    line = line.strip()
    if not line or line[0] not in '+-':
        return None
    sign, n = line[0], len(line)

    def space(i):
        while i < n and line[i].isspace():
            i += 1
        return i

    i = space(1)
    if i < n and line[i] == '(':
        i = skip_balanced(line, i)
    m = _CXX.match(line, i)
    if m:
        return sign, m.group(0)
    parts = []
    while True:
        i = space(i)
        m = _IDENT.match(line, i)
        name = m.group(0) if m else ''
        if m:
            i = space(m.end())
        if i < n and line[i] == ':':
            parts.append(name + ':')
            i = space(i + 1)
            if i < n and line[i] == '(':
                i = space(skip_balanced(line, i))
            m = _IDENT.match(line, i)
            if m:
                i = m.end()
            continue
        if name and not parts:
            parts.append(name)
        break
    return (sign, ''.join(parts)) if parts else None


def dumped_property_selectors(line):
    """[(sign, selector)] of a dumped @property line: the getter (getter=),
    the setter (setter=) unless readonly; + for a class property."""
    m = _DUMP_PROPERTY.match(line.strip())
    if not m:
        return []
    attrs = [a.strip() for a in (m.group(1) or '').split(',') if a.strip()]
    decl = m.group(2)
    # The name is the last identifier, after any struct body or block type.
    names = _IDENT.findall(decl[decl.rfind('}') + 1:] if '}' in decl else decl)
    if not names:
        return []
    name = names[-1]
    sign = '+' if 'class' in attrs else '-'
    getter, setter = name, 'set%s%s:' % (name[0].upper(), name[1:])
    for a in attrs:
        if a.startswith('getter='):
            getter = a[len('getter='):].strip()
        elif a.startswith('setter='):
            setter = a[len('setter='):].strip()
    return [(sign, getter)] + ([] if 'readonly' in attrs else [(sign, setter)])


def scan_dumped_header(text):
    """([(class, superclass or None)], [(class, sign, selector)]) of one
    dumped header's text. A category's methods go to its class, with no
    class line; a protocol's lines are skipped."""
    classes, methods = [], []
    current, in_protocol = None, False
    for line in text.split('\n'):
        if in_protocol:
            if line.startswith('@end'):
                in_protocol = False
            continue
        if line.startswith('@protocol') and not line.rstrip().endswith(';'):
            in_protocol = True
            continue
        if line.startswith('@interface'):
            m = _DUMP_INTERFACE.match(line)
            if not m:
                current = None
                continue
            current = m.group(1)
            if m.group(2) is None and line[m.end(1):].lstrip()[:1] != '(':
                classes.append((current, m.group(3)))
            continue
        if line.startswith('@end'):
            current = None
            continue
        if current is None:
            continue
        if line[:1] in '+-':
            sel = dumped_method_selector(line)
            if sel:
                methods.append((current, sel[0], sel[1]))
        elif line.startswith('@property'):
            for sign, sel in dumped_property_selectors(line):
                methods.append((current, sign, sel))
    return classes, methods


def write_runtime_methods_from_headers(root, os_name, output, source=None):
    """Stream every .h under root into OUTPUT in the --runtime-methods
    format. Returns (headers read, class lines, method lines)."""
    tmp = atomic_output(output)
    try:
        counts = _write_dump(root, os_name, tmp, source)
    except BaseException:
        os.unlink(tmp)
        raise
    os.replace(tmp, output)
    return counts


def _write_dump(root, os_name, output, source):
    headers = class_lines = method_lines = 0
    with open(output, 'w', encoding='utf-8') as out:
        out.write('# Runtime methods: %s; the methods the classes of the dump implement, private methods included, '
                  'as far as the dump shows them.\n' % DUMP_LABEL)
        out.write('# os: %s\n' % os_name)
        out.write('# kind: dumped-headers\n')
        out.write('# source: %s\n' % (source or root))
        out.write('# Derived from dumped headers: methods that other images add to a class through categories (for '
                  'example those frameworks add to NSObject) are missing. Specific to that OS version; results from '
                  'it are INCOMPLETE by nature.\n')
        out.write('# columns: C<TAB>class<TAB>superclass (empty for a root class), M<TAB>class<TAB>+|-<TAB>'
                  'selector\n')
        for d, dirs, files in os.walk(root):
            dirs.sort()
            for name in sorted(files):
                if not name.endswith('.h'):
                    continue
                path = os.path.join(d, name)
                if os.path.islink(path):
                    continue
                try:
                    with open(path, 'r', encoding='utf-8', errors='replace') as f:
                        text = f.read()
                except OSError:
                    continue
                headers += 1
                classes, methods = scan_dumped_header(text)
                for cls, sup in classes:
                    out.write('C\t%s\t%s\n' % (cls, sup or ''))
                    class_lines += 1
                seen = set()
                for row in methods:
                    if row not in seen:
                        seen.add(row)
                        out.write('M\t%s\t%s\t%s\n' % row)
                        method_lines += 1
        out.write('# end: C=%d M=%d\n' % (class_lines, method_lines))
    return headers, class_lines, method_lines


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--sdk', help='the SDK (default: xcrun --show-sdk-path)')
    p.add_argument('--strict', action='store_true', help='exit 1 when a declaration could not be read')
    p.add_argument('--runtime-methods', action='store_true',
                   help='write what the frameworks implement at run time (private methods included) instead')
    p.add_argument('--runtime-methods-from-headers', metavar='DIR',
                   help='write a runtime method list converted from a tree of dumped runtime headers instead '
                   '(needs --os)')
    p.add_argument('--os', help='with --runtime-methods-from-headers: the OS release the dump is of, as the # os: '
                   'line names it (for example "macOS 13.6")')
    p.add_argument('--source', help='with --runtime-methods-from-headers: where the dump came from, for the # '
                   'source: line (default: DIR)')
    p.add_argument('--allow-missing-frameworks', action='store_true',
                   help='with --runtime-methods: exit 0 even when a framework did not load (the list marks it)')
    p.add_argument('--app-bundle', metavar='PATH',
                   help='with --runtime-methods: also load the frameworks and dylibs in PATH/Contents/Frameworks (the '
                   'app\'s own embedded frameworks, from a built app; read-only)')
    p.add_argument('output', metavar='OUTPUT')
    args = p.parse_args(argv)
    if args.runtime_methods_from_headers:
        if not args.os:
            print('sdk_selectors: error: --runtime-methods-from-headers needs --os', file=sys.stderr)
            return 2
        if not os.path.isdir(args.runtime_methods_from_headers):
            print('sdk_selectors: error: %s is not a directory' % args.runtime_methods_from_headers, file=sys.stderr)
            return 2
        headers, nc, nm = write_runtime_methods_from_headers(args.runtime_methods_from_headers, args.os, args.output,
                                                             args.source)
        print('sdk_selectors: read %d headers; wrote %d class lines and %d method lines (%s) of %s to %s' % (
            headers, nc, nm, DUMP_LABEL, args.os, args.output))
        return 0
    if args.runtime_methods:
        return runtime_main(args.output, args.allow_missing_frameworks, args.app_bundle)
    sdk = args.sdk or subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True,
                                     check=True).stdout.strip()
    if not os.path.isdir(os.path.join(sdk, 'System', 'Library', 'Frameworks')):
        print('sdk_selectors: error: %s has no System/Library/Frameworks' % sdk, file=sys.stderr)
        return 2
    failures = []
    rows = scan_sdk(sdk, failures)
    with open(args.output, 'w', encoding='utf-8') as f:
        write_rows(f, rows, sdk)
    print('sdk_selectors: wrote %d declarations %s to %s' % (len(rows), LABEL, args.output))
    print('sdk_selectors: declarations the scanner could not read: %d%s' % (
        len(failures), ' (first %d below); their selectors are missing from the file' % min(20, len(failures))
        if failures else ''))
    for path, n, decl in failures[:20]:
        print('  %s:%d: %s' % (os.path.relpath(path, sdk), n, decl))
    return 1 if failures and args.strict else 0


if __name__ == '__main__':
    sys.exit(main())
