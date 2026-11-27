#!/usr/bin/env python3
"""Inventory of the Objective-C, C and C++ code still to be migrated to Swift.

Part of the Objective-C to Swift migration (docs/swift-migration/phase0.md,
section 1). Everything is computed from the working tree, the Xcode project
and git history on every run. Nothing is cached or written to disk; Python's
bytecode cache is turned off before the optional subcommand modules are
imported, so not even __pycache__ is written.

Works from the root of the git repository that contains the current
directory (or --root), wherever it is started. Python 3 standard library only.
Any failure (not a git repository, git failing, the Xcode project missing or
unparsable, a prefix header that cannot be read, iTerm2.sdef missing or not
well-formed, no in-scope files, an unreadable file) is an error on stderr and
exit status 2, never a plausible-looking answer. Non-fatal problems (a file
that is not UTF-8, a parser that could not follow a file, a xib that is not
well-formed) are printed as warnings on stderr and included in JSON output;
a xib that does not parse is also listed under "Not established" by every
subcommand, and every file whose classes it may name carries a hazard.

{SCOPE_PARAGRAPH}

{NON_PRODUCT_RULE}

.metal files are not counted. A tracked file that this tool would read (in
scope or not, xib and storyboard files included) but that is missing from the
working tree is not read; it is listed under Not established by this tool by
every subcommand, because the relations and hazards that depend on it could
not be established.

Relations (subclasses, categories, Swift extensions, accessor overrides) are
computed over every tracked .h, .m, .mm and .swift file outside submodules/
and tools/swift_migration/ (this tool and its fixture repository), including
ModernTests, other targets and the test, demo and tool code inside the scope
directories, because a class subclassed by a test cannot
become Swift either. Only in-scope Swift extensions count as partial porting.
xib and storyboard files are read from the same places.

Subcommands (add --json before or after the subcommand for machine output;
every JSON document carries a reliability map saying which fields are exact
and which are heuristic, and why):

  summary              Progress measures and totals (the default).
  files [options]      One row per implementation file (.m, .mm, .c).
                       --sort lines|fanin|reach|rr|path  --filter SUBSTRING
                       --limit N
  file NAME            Everything known about one implementation file, with
                       the line of each text hazard. NAME is a path, a file
                       name, a stem, or a class name. --all-sites
  state NAME           State table (objc-state.md) for every class implemented
                       in the file. Provided by inventory_state.py, which
                       documents it; unavailable if that file is missing.
  history [UNIT]       Swift-Port trailers in commits reachable from HEAD, as
                       git reads them (git log, %(trailers)), per unit. Only
                       kinds from README.md section 5 count. Malformed values,
                       unknown kinds, non-canonical spellings and lines that
                       look like a trailer but are not one are reported.
                       Exit status 1 if UNIT has no trailers.
  leaf [options]       The leaf tier: files whose header has direct fan-in
                       <= --max-fan-in (default 2) and transitive reach
                       <= --max-reach (default 10). A file is offered only if
                       no deferral rule applies to it (DEFERRED_LISTS: wholly
                       conditional, incomplete parse, probable hot path, giant
                       classes, must stay in Objective-C for now, stays in C:
                       atomics, defines C functions or globals declared in a
                       header, needs the owner's permission, needs a design
                       decision, class named by a macro, Objective-C
                       subclasses, categories implemented in other files,
                       foundation categories, other executables, not compiled,
                       #included by another file, encodes or decodes stored
                       state, which prints the first stored-state match with
                       its rule). Each offered file shows the
                       hazards this tool detects in it by the text searches
                       defined in inventory.py (HAZARD_PATTERNS and
                       Inventory.file_record); that is not everything its
                       dossier must cover.
                       Text hazards are searched for in Objective-C, C and
                       Objective-C++ implementation files only (.m, .c, .mm),
                       not in Swift files or headers.
                       The deferred lists are counted, and listed with
                       --deferred. The total is always printed. Every run
                       ends with "Not established by this tool" and "Not
                       checked by this tool". --limit N (at least 1)
                       --deferred  --all-sites (every selector site in the
                       tree, which is otherwise summarized)
  verify [options]     Compares the ivars and methods this tool finds with the
                       Objective-C metadata of a built binary. Provided by
                       inventory_verify.py (which needs inventory_state.py);
                       unavailable if either file is missing.

Stored state is found by four rules, and every match carries its line, the
text matched, the rule and the entry of that rule (file NAME lists them all):
  1. Direct API use: keyed archivers and coders, keyed coding, NSCoding,
     restorable-state methods, arrangements, property-list serialization,
     dictionaryWithContentsOfFile:, dictionaryWithContentsOfURL:,
     arrayWithContentsOfFile:, arrayWithContentsOfURL:, and writeToFile: or
     writeToURL: without an encoding: keyword, CFPreferences, writes to a
     receiver that is user defaults by its text, Core Data and SQLite
     (STORED_STATE_DIRECT). Generic file and JSON I/O is not matched.
  2. A use of an entry of STORED_STATE_API, the named list of iTerm2's own
     stored-state classes and helpers, each with what it persists.
  3. A typed keyed setter (setBool:, setInt:, setObject: and the like with
     forKey:) whose key is a KEY_ or k...Preference... constant; or such a
     setter, or setObjectsFromDictionary:, sent to self, super, weakSelf or
     strongSelf in a class whose superclass chain reaches a listed class or a
     class with a constant-key setter of its own.
  4. A class whose superclass chain reaches a listed class.
Nothing else is followed: a call to a project method that stores state is not
itself a match, so every dossier still lists stored-state surfaces by reading.

Classes named by a macro (@implementation THE_CLASS, with THE_CLASS defined
by the file that #includes it) are resolved to the real class names by
reading the #define lines, with a warning; classes declared by a function-like
macro (DECLARE_TEST(t)) cannot be listed, and every file involved is flagged.

What is exact and what is heuristic (every JSON document says it field by
field in its reliability map):

  Exact: paths, line counts, file counts, and Swift-Port trailers as git reads
    them. Marker counts are git grep counts of the literal text, outside
    submodules/, docs/swift-migration and tools/swift_migration (the last two
    describe the markers).

  Heuristic (text matching on comment- and string-stripped source, with no
  preprocessor: conditions are never evaluated, and both branches of every
  #if are seen):
    target membership and ARC (each project.pbxproj is parsed as structured data,
    per-target CLANG_ENABLE_OBJC_ARC in every build configuration, Xcode's
    default of NO when unset, overridden by per-file -fobjc-arc /
    -fno-objc-arc; conditional settings are reported, not evaluated; an
    implementation file #included by another takes the includer's targets,
    and that #include is found by text); null_unspecified and ivar_ accessor
    counts; files wholly under a preprocessor condition (the condition is
    named, never evaluated);
    retain/release site counts (nested sends such as
    [[[Foo alloc] init] autorelease] included; [super dealloc] counted
    separately); header fan-in and reach (an #import or #include whose file
    name matches the header's, counted within scope only, so importers in
    ModernTests and elsewhere are not counted; the bridging header counts as
    an importer, and the summary also gives the figure without it; every
    header a target's prefix header imports, directly or through other
    in-scope headers, counts as imported by every in-scope file the target
    compiles, and the output marks fan-in that includes them); class,
    category, extension, superclass and subclass relations (Objective-C
    @interface / @implementation lines and Swift class / extension
    declarations; classes renamed with @objc(Name) or NS_SWIFT_NAME are
    resolved where written next to the declaration); hazard flags (a mention
    of an API, not proof that it reaches anything, searched for in .m, .mm and
    .c files only; calls to methods and functions in scope found to dispatch a
    block parameter count as dispatches too); stored state (above); macro
    classification;
    the Objective-C++ class (the distinction between incidental C++ and C++
    essential to performance is a guess from the directory, and is labeled
    probable); hot-path flags (by directory only); xib and sdef names and
    connections; the classes a class-name call can create (an
    over-approximation: checks combined with AND are each treated alone);
    sites that build a selector from something other than a literal; C
    functions and globals named in a header; the leaf deferral rules, which
    are built from all of these.

  The leaf tier offers files for a dossier; it does not decide anything.
  What can reach a selector or class by name (selector strings, tables of
  selector names, Info.plist entries, reflective sites) is not determined
  here; that is the entry-point census (phase0.md section 2). leaf and file
  print, every time, a fixed list of what this tool does not check.
"""

from __future__ import annotations

import argparse
import bisect
import importlib
import json
import os
import re
import subprocess
import sys
import textwrap
import xml.etree.ElementTree as ElementTree
from collections import OrderedDict, defaultdict

# ---------------------------------------------------------------------------
# Scope

# The migration's scope, as docs/swift-migration/README.md section 2 defines it: the owner's own Objective-C, C and
# C++ compiled into the app or its helper programs, wherever it lives. These are the directories it lives in, as
# widened by the owner on SCOPE_WIDENED. This is the only place the scope is written; everything else, messages and
# help text included, is derived from it.
SCOPE_ROOTS = ('sources', 'ThirdParty/PSMTabBarControl', 'SignedArchive', 'pidinfo', 'iTerm2SandboxedWorker',
               'ShellLauncher', 'ColorPicker', 'SearchableComboListView', 'BetterFontPicker')
SCOPE_WIDENED = '2026-11-19'
OUTSIDE_SCOPE = 'outside the scope directories (README.md section 2)'


def scope_roots_text():
    """The scope directories as a reader sees them: 'a/, b/ and c/'."""
    names = [r + '/' for r in SCOPE_ROOTS]
    return names[0] if len(names) == 1 else ', '.join(names[:-1]) + ' and ' + names[-1]


def scope_root_of(path):
    """The scope directory that holds a repository-relative path (the longest that matches), or None."""
    found = [r for r in SCOPE_ROOTS if path == r or path.startswith(r + '/')]
    return max(found, key=len) if found else None


IMPL_EXTS = ('.m', '.mm', '.c')
OBJC_EXTS = ('.m', '.mm')
HEADER_EXT = '.h'
SWIFT_EXT = '.swift'
NON_ARC_TARGET = 'iTerm2Shared'
ARC_TARGET = 'iTerm2SharedARC'
MAIN_TARGETS = (NON_ARC_TARGET, ARC_TARGET)
PBXPROJ = 'iTerm2.xcodeproj/project.pbxproj'
# Some scope directories are built by Xcode projects of their own (ColorPicker/ColorPicker.xcodeproj and the like).
# Every project.pbxproj tracked by git under a scope directory is read the same way as PBXPROJ. Targets of PBXPROJ keep
# their plain names; a target of another project is named <project>:<target>, such as
# ColorPicker/ColorPicker.xcodeproj:ColorPicker.
PROJECT_FILE = 'project.pbxproj'
# Test, demo and tool code: what a target's product type says about the files it compiles. A file compiled only by
# targets in these categories is not compiled into the app or its helper programs, so it is outside the scope of
# README.md section 2 and is listed in its own category instead of being counted or offered. Every target of PBXPROJ
# other than a test bundle is treated as building the app or one of its helper programs (XPC services, the tools it
# runs, its libraries and frameworks); this is by product type, so a test application there counts as a product. In
# another project, the framework or library is treated as what the app uses (even SignedArchive's, which only its
# standalone tools link), an application target is a demo of it, and a command-line tool target is a standalone tool (such as SignedArchive's sign and verify),
# not a helper program of the app.
TEST_PRODUCT_TYPES = ('com.apple.product-type.bundle.unit-test', 'com.apple.product-type.bundle.ui-testing')
DEMO_PRODUCT_TYPES = ('com.apple.product-type.application',)
TOOL_PRODUCT_TYPES = ('com.apple.product-type.tool',)
NON_PRODUCT_CATEGORIES = OrderedDict([
    ('test', ('test code', 'compiled only by test bundles (%s), in any project' % ', '.join(TEST_PRODUCT_TYPES))),
    ('demo', ('demo code', 'compiled only by application targets (%s) of a project other than %s'
              % (', '.join(DEMO_PRODUCT_TYPES), PBXPROJ))),
    ('tool', ('tool code', 'compiled only by command-line tool targets (%s) of a project other than %s'
              % (', '.join(TOOL_PRODUCT_TYPES), PBXPROJ))),
])
NON_PRODUCT_RULE = (
    'Test, demo and tool code: a file in a scope directory that every target compiling it puts in one of these '
    'categories is not compiled into the app or its helper programs, so it is not counted in scope and never '
    'offered; summary lists it with its category. %s. A header takes the category of the implementation file with '
    'its name beside it, or of the targets whose Swift bridging header (SWIFT_OBJC_BRIDGING_HEADER) it is. Every other '
    'target is treated as building the app or one of its helper programs (in %s, every target that is not a test '
    'bundle; elsewhere, frameworks, libraries, XPC services and bundles). This is by product type, so a library that '
    'only standalone tools use, or a test application in %s, is treated as a product. A file compiled by targets of more than one of these categories takes the '
    'first in the order test, demo, tool.'
    % ('; '.join('%s: %s' % (label, why) for label, why in NON_PRODUCT_CATEGORIES.values()), PBXPROJ, PBXPROJ))


def target_category(product_type, in_main_project):
    """'test', 'demo', 'tool' (NON_PRODUCT_CATEGORIES) or 'product' for a target of this product type."""
    if product_type in TEST_PRODUCT_TYPES:
        return 'test'
    if not in_main_project and product_type in DEMO_PRODUCT_TYPES:
        return 'demo'
    if not in_main_project and product_type in TOOL_PRODUCT_TYPES:
        return 'tool'
    return 'product'


# The module docstring (also the epilog of --help) states the scope from the constants above.
SCOPE_PARAGRAPH = (
    'Scope (README.md section 2, widened by the owner on %s): the owner\'s own Objective-C, C and C++ compiled into the '
    'app or its helper programs, in files tracked by git under %s (SCOPE_ROOTS), excluding sources/proto (generated '
    'protobuf), sources/CoreDataGeneratedFiles and any +CoreDataProperties / +CoreDataClass file (generated Core '
    'Data), any file inside a built framework (*.framework) committed to the repository, test, demo and tool code '
    '(below), and everything under submodules/ (never read or listed). Gitlinks are skipped. summary lists every '
    'exclusion with its reason, and gives the counts for each scope directory as well as the totals.\n\n'
    'Targets and ARC come from %s and from every other Xcode project (project.pbxproj) tracked by git under a scope '
    'directory, all read the same way; a target of another project is named <project>:<target>. A file that none of '
    'them compiles is reported as compiled by no target of any project found, with the projects searched.'
    % (SCOPE_WIDENED, scope_roots_text(), PBXPROJ))
__doc__ = (__doc__.replace('{SCOPE_PARAGRAPH}', '\n\n'.join(textwrap.fill(para, 78, break_on_hyphens=False, break_long_words=False)
                                                            for para in SCOPE_PARAGRAPH.split('\n\n')))
           .replace('{NON_PRODUCT_RULE}', textwrap.fill(NON_PRODUCT_RULE, 78, break_on_hyphens=False,
                                                                  break_long_words=False)))

BRIDGING_HEADER = 'sources/iTerm2SharedARC-Bridging-Header.h'
SDEF_FILE = 'iTerm2.sdef'
# The giant classes of large-code.md section 1, emptied by extraction and never ported as files.
GIANT_CLASSES = ('PTYSession', 'PseudoTerminal', 'PTYTab', 'PTYTextView')
# performance.md section 2 names the first five. CharacterSets (per-character
# width and membership tests) and ScreenChar (the cell type and its arrays)
# are added because their functions run per character or per cell.
HOT_PATH_DIRS =('sources/VT100/', 'sources/VT100Screen/', 'sources/LineBuffer/',
                 'sources/MetalRenderer/', 'sources/Drawing/', 'sources/CharacterSets/',
                 'sources/ScreenChar/')
IVAR_ACCESSOR_PATTERN = re.compile(
    r'(?<![A-Za-z0-9_])ivar_(?!get(?:Name|Offset|TypeEncoding)\b)[A-Za-z0-9_]+|'
    r'\bsetIvar_[A-Za-z0-9_]+|'
    r'\b[A-Za-z][A-Za-z0-9]*_ivar_[A-Za-z0-9_]+')
MARKERS = ('SWIFT-MIGRATION-SHIM', 'SWIFT-MIGRATION-UNSAFE',
           'SWIFT-MIGRATION-FROZEN-REFERENCE', 'SWIFT-MIGRATION-IUO')
# Paths excluded from marker and ivar_ counts because they describe the
# markers rather than use them.
MARKER_EXCLUDED_PATHS = ('docs/swift-migration', 'tools/swift_migration')
# The checked-arithmetic helpers of translation-rules.md section 1. Their calls
# are scaffolding removed in stage two, and the summary counts the calls that
# remain (decisions.md, 2026-11-20).
ARITHMETIC_HELPERS = ('it_add', 'it_subtract', 'it_multiply', 'it_negate', 'it_shiftLeft', 'it_narrow',
                      'it_floatToInteger')
ARITHMETIC_HELPER_CALL = re.compile(r'(?<![A-Za-z0-9_.])(%s)\s*\(' % '|'.join(ARITHMETIC_HELPERS))
# The helper library, which defines the helpers and calls them internally, and
# its own tests. Neither is a port's use of a helper.
ARITHMETIC_HELPER_EXCLUDED_FILES = ('sources/Infrastructure/SwiftMigrationHelpers.swift',
                                    'ModernTests/SwiftMigrationHelpersTests.swift')
# This tool's own directory, which holds a fixture repository of Objective-C,
# xib and Swift files, is left out of the scans of the whole repository.
TOOL_DIR_PREFIX = 'tools/swift_migration/'
KNOWN_KINDS = ('tool', 'dossier', 'test', 'annotate', 'arc', 'undynamic', 'extract', 'decxx',
               'explicit', 'port', 'fix', 'improve')


# Why a file inside a scope directory is still not counted, for each reason exclusion_reason and the project reading
# give. summary prints each reason with every file it excludes. No third-party or generated code was found in the
# directories added on SCOPE_WIDENED other than the built framework copies (ColorPicker/CREDITS covers only the data
# file colors.txt), and the owner confirmed each directory is in scope (README.md section 2); third-party code under
# ThirdParty/ is outside the scope directories.
EXCLUSION_RULES = OrderedDict([
    ('submodule', 'everything under submodules/ (README.md section 2)'),
    ('generated (protobuf)', 'protobuf compiler output: sources/proto/ and any *.pbobjc.* file'),
    ('generated (Core Data)', 'Core Data generated files: sources/CoreDataGeneratedFiles/ and any '
                              '+CoreDataProperties or +CoreDataClass file'),
    ('generated (built framework)', 'a built framework (a *.framework directory) committed to the repository: its '
                                    'headers are copies made by building the project beside it, and its -Swift.h '
                                    'headers are written by the Swift compiler'),
    ('test code', NON_PRODUCT_CATEGORIES['test'][1]),
    ('demo code', NON_PRODUCT_CATEGORIES['demo'][1]),
    ('tool code', NON_PRODUCT_CATEGORIES['tool'][1]),
    ('missing from working tree', 'tracked by git but absent from the working tree, so not read (listed under Not '
                                  'established)'),
])


def exclusion_reason(path):
    """Returns why a repository-relative path is out of scope, or None.

    This is decided from the path alone. Test, demo and tool code is found later, from the Xcode projects
    (NON_PRODUCT_CATEGORIES)."""
    p = path.replace('\\', '/')
    if p == 'submodules' or p.startswith('submodules/') or '/submodules/' in p:
        return 'submodule'
    if scope_root_of(p) is None:
        return OUTSIDE_SCOPE
    if p.startswith('sources/proto/') or '.pbobjc.' in p:
        return 'generated (protobuf)'
    if (p.startswith('sources/CoreDataGeneratedFiles/') or '+CoreDataProperties.' in p
            or '+CoreDataClass.' in p):
        return 'generated (Core Data)'
    if any(part.endswith('.framework') for part in p.split('/')[:-1]):
        return 'generated (built framework)'
    return None


def is_hot_path(path):
    return any(path.startswith(d) for d in HOT_PATH_DIRS)


# ---------------------------------------------------------------------------
# Small helpers

def count_lines(text):
    """Line count with the same meaning as wc -l, plus a final unterminated line."""
    n = text.count('\n')
    if text and not text.endswith('\n'):
        n += 1
    return n


_C_LEX = re.compile(r'//[^\n]*|/\*.*?\*/|@?"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S)
_SWIFT_LEX = re.compile(r'//[^\n]*|/\*.*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"', re.S)
_NON_NEWLINE = re.compile(r'[^\n]')


def _blank(s):
    return _NON_NEWLINE.sub(' ', s)


def mask_source(text, swift=False):
    """Blanks comments and the contents of string and character literals.

    The result has the same length and line structure as the input, so
    offsets and line numbers are shared. String delimiters are kept so that
    @"..." still looks like an expression.
    """
    def repl(m):
        s = m.group(0)
        if s.startswith('//') or s.startswith('/*'):
            return _blank(s)
        if s.startswith('"""'):
            return '"""' + _blank(s[3:-3]) + '"""'
        lead = 2 if s.startswith('@') else 1
        return s[:lead] + _blank(s[lead:-1]) + s[-1]
    return (_SWIFT_LEX if swift else _C_LEX).sub(repl, text)


_PP_LINE = re.compile(r'^[ \t]*#(?:[^\n]*\\\n)*[^\n]*', re.M)
_PRAGMA_LINE = re.compile(r'^[ \t]*#[ \t]*pragma\b[^\n]*', re.M)


def strip_preprocessor(masked):
    """Blanks preprocessor directives, including continuation lines."""
    return _PP_LINE.sub(lambda m: _blank(m.group(0)), masked)


class LineIndex(object):
    def __init__(self, text):
        self.starts = [0]
        for m in re.finditer('\n', text):
            self.starts.append(m.end())

    def line(self, offset):
        return bisect.bisect_right(self.starts, offset)


def find_matching(text, open_index, open_ch='{', close_ch='}'):
    """Index of the bracket matching text[open_index], or len(text) - 1."""
    depth = 0
    pat = re.compile('[' + re.escape(open_ch + close_ch) + ']')
    for m in pat.finditer(text, open_index):
        if m.group(0) == open_ch:
            depth += 1
        else:
            depth -= 1
            if depth == 0:
                return m.start()
    return len(text) - 1


def remove_balanced(text, open_ch='(', close_ch=')', replacement=' '):
    """Removes every balanced bracket group, outermost first."""
    out = []
    depth = 0
    for ch in text:
        if ch == open_ch:
            if depth == 0:
                out.append(replacement)
            depth += 1
        elif ch == close_ch and depth > 0:
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return ''.join(out)


def split_top_level(text, sep=','):
    parts, depth, cur = [], 0, []
    for ch in text:
        if ch in '([{<':
            depth += 1
        elif ch in ')]}>':
            depth = max(0, depth - 1)
        if ch == sep and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append(''.join(cur))
    return parts


_ATTRIBUTE = re.compile(r'__attribute__\s*\(')


def strip_attributes(text):
    while True:
        m = _ATTRIBUTE.search(text)
        if not m:
            return text
        end = find_matching(text, m.end() - 1, '(', ')')
        text = text[:m.start()] + ' ' + text[end + 1:]


def ws(text):
    return ' '.join(text.split())


# ---------------------------------------------------------------------------
# Xcode project (OpenStep property list)

_PBX_TOKEN = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"((?:\\.|[^"\\])*)"|([A-Za-z0-9_$+/:.\-]+)|([{}()=;,])',
                        re.S)
_PBX_ESCAPES = {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'"}


def _pbx_unescape(s):
    return re.sub(r'\\(.)', lambda m: _PBX_ESCAPES.get(m.group(1), m.group(1)), s)


def parse_pbxproj(text):
    """Parses an OpenStep-format property list such as project.pbxproj."""
    tokens = []
    pos, n = 0, len(text)
    if text.startswith('// !$*UTF8*$!'):
        pos = text.index('\n') + 1
    while pos < n:
        m = _PBX_TOKEN.match(text, pos)
        if not m:
            raise ValueError('pbxproj: unexpected character at offset %d' % pos)
        pos = m.end()
        if m.group(1) is not None:
            tokens.append(('s', _pbx_unescape(m.group(1))))
        elif m.group(2) is not None:
            tokens.append(('s', m.group(2)))
        elif m.group(3) is not None:
            tokens.append(('p', m.group(3)))
    idx = [0]

    def value():
        kind, tok = tokens[idx[0]]
        idx[0] += 1
        if kind == 's':
            return tok
        if tok == '{':
            d = OrderedDict()
            while True:
                kind, tok = tokens[idx[0]]
                if kind == 'p' and tok == '}':
                    idx[0] += 1
                    return d
                key = value()
                kind, tok = tokens[idx[0]]
                if tok != '=':
                    raise ValueError('pbxproj: expected = after %r' % key)
                idx[0] += 1
                d[key] = value()
                kind, tok = tokens[idx[0]]
                if tok == ';':
                    idx[0] += 1
        if tok == '(':
            arr = []
            while True:
                kind, tok = tokens[idx[0]]
                if kind == 'p' and tok == ')':
                    idx[0] += 1
                    return arr
                arr.append(value())
                kind, tok = tokens[idx[0]]
                if tok == ',':
                    idx[0] += 1
        raise ValueError('pbxproj: unexpected token %r' % tok)
    return value()


def _arc_from_flags(flags):
    if not flags:
        return None
    toks = flags.split() if isinstance(flags, str) else list(flags)
    result = None
    for t in toks:
        if t == '-fobjc-arc':
            result = True
        elif t == '-fno-objc-arc':
            result = False
    return result


_BUILD_DIR_VARIABLES = re.compile(r'^(?:\$\((?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)\)|\$\{(?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)\})/')


def _prefix_header_path(value, project_dir):
    """A GCC_PREFIX_HEADER value as a repository-relative path; any other build variable is left in place."""
    value = _BUILD_DIR_VARIABLES.sub('', value.strip())
    return os.path.normpath(os.path.join(project_dir, value)) if '$' not in value else value


def compute_target_membership(plist, project_dir='', read_file=None):
    """Maps each compiled source path to a list of {target, arc} dicts.

    arc is True, False, or 'mixed' (build configurations disagree). The
    target value comes from CLANG_ENABLE_OBJC_ARC in each of the target's
    build configurations, falling back to the project's configurations and
    then to Xcode's default of NO; per-file COMPILER_FLAGS override it. A
    configuration's xcconfig (baseConfigurationReference) is read through
    read_file(path) for a plain CLANG_ENABLE_OBJC_ARC = line; one that cannot
    be read, or that uses #include, is reported in arc_source and in
    targets[...]['xcconfig_unread'].
    Each target summary also has prefix_headers, the GCC_PREFIX_HEADER values of
    all its build configurations as paths (a value holding a build variable
    other than SRCROOT, PROJECT_DIR or SOURCE_ROOT is left as written), and
    prefix_header_source, how many configurations set one; product_type, the target's productType; and
    bridging_headers, its SWIFT_OBJC_BRIDGING_HEADER values as paths, read the same way as the prefix header.
    Paths are relative to the repository when project_dir is the directory that holds the .xcodeproj.
    Also returns per-target summaries and the synchronized folders.
    """
    xcconfig_notes = []
    objects = plist['objects']
    root_obj = objects[plist['rootObject']]

    parent = {}
    for oid, obj in objects.items():
        if obj.get('isa') in ('PBXGroup', 'PBXVariantGroup', 'XCVersionGroup'):
            for child in obj.get('children', []):
                parent[child] = oid

    path_cache = {}

    def resolve(oid):
        if oid in path_cache:
            return path_cache[oid]
        obj = objects.get(oid)
        result = None
        if obj is not None:
            tree = obj.get('sourceTree', '<group>')
            p = obj.get('path', '')
            if tree == '<group>':
                par = parent.get(oid)
                if par is None:
                    base = project_dir
                else:
                    base = resolve(par)
                if base is not None:
                    result = os.path.normpath(os.path.join(base, p)) if (base or p) else ''
            elif tree == 'SOURCE_ROOT':
                result = os.path.normpath(os.path.join(project_dir, p))
            elif tree == '<absolute>':
                result = p
        if result == '.':
            result = ''
        path_cache[oid] = result
        return result

    def config_values(list_id, key):
        values = []
        lst = objects.get(list_id, {})
        for cid in lst.get('buildConfigurations', []):
            config = objects.get(cid, {})
            settings = config.get('buildSettings', {})
            value = settings.get(key)
            for k in settings:
                if k.startswith(key + '['):
                    xcconfig_notes.append('conditional setting %s is not evaluated' % k)
            ref = config.get('baseConfigurationReference')
            if value is None and ref:
                path = resolve(ref)
                text = read_file(path) if (read_file and path is not None) else None
                if text is None:
                    xcconfig_notes.append('xcconfig %s not read' % (path or ref))
                else:
                    m = re.search(r'(?m)^[ \t]*%s[ \t]*=[ \t]*(\w+)' % key, text)
                    if re.search(r'(?m)^[ \t]*%s\[' % key, text):
                        xcconfig_notes.append('xcconfig %s has a conditional %s, not evaluated' % (path, key))
                    if m:
                        value = m.group(1)
                        xcconfig_notes.append('from xcconfig %s' % path)
                    elif re.search(r'(?m)^[ \t]*#include', text):
                        xcconfig_notes.append('xcconfig %s uses #include, not followed' % path)
            values.append(value)
        return values

    project_values = config_values(root_obj.get('buildConfigurationList'), 'CLANG_ENABLE_OBJC_ARC')
    project_values_prefix = config_values(root_obj.get('buildConfigurationList'), 'GCC_PREFIX_HEADER')

    membership = defaultdict(list)
    targets = OrderedDict()
    for tid in root_obj.get('targets', []):
        target = objects.get(tid, {})
        if target.get('isa') != 'PBXNativeTarget':
            continue
        name = target.get('name')
        del xcconfig_notes[:]
        values = config_values(target.get('buildConfigurationList'), 'CLANG_ENABLE_OBJC_ARC')
        source = 'CLANG_ENABLE_OBJC_ARC in the target\'s build configurations'
        if values and all(v is None for v in values):
            values = project_values
            source = 'CLANG_ENABLE_OBJC_ARC unset in the target; project configurations used'
        if not values or all(v is None for v in values):
            source = 'CLANG_ENABLE_OBJC_ARC unset in the target and the project; Xcode default is NO'
        elif any(v is None for v in values):
            source += ' (unset in some configurations, which default to NO)'
        resolved = set()
        for v in values:
            if v is None:
                resolved.add(False)
            else:
                resolved.add(v == 'YES')
        if not resolved:
            target_arc = False
        elif len(resolved) == 1:
            target_arc = resolved.pop()
        else:
            target_arc = 'mixed'
        unread = [n for n in xcconfig_notes if 'not read' in n or 'not followed' in n or 'not evaluated' in n]
        if xcconfig_notes:
            source += '; ' + '; '.join(sorted(set(xcconfig_notes)))
        # The prefix header, from every build configuration (the same way as the ARC setting). A target
        # whose configurations name different prefix headers, or that sets one in only some of them, is
        # treated as importing all of them in every configuration.
        del xcconfig_notes[:]
        prefix_values = config_values(target.get('buildConfigurationList'), 'GCC_PREFIX_HEADER')
        if prefix_values and all(v is None for v in prefix_values):
            prefix_values = project_values_prefix
        prefix_notes = sorted(set(n for n in xcconfig_notes if 'not read' in n or 'not followed' in n
                                  or 'not evaluated' in n))
        prefix_headers = sorted(set(_prefix_header_path(v, project_dir) for v in prefix_values if v))
        # The Swift bridging header, read the same way; it is used only to give a header the category of its target.
        bridging_values = config_values(target.get('buildConfigurationList'), 'SWIFT_OBJC_BRIDGING_HEADER')
        targets[name] = {'arc': target_arc, 'arc_source': source, 'sources': 0, 'unresolved': 0,
                         'xcconfig_unread': unread + prefix_notes, 'prefix_headers': prefix_headers,
                         'prefix_header_source': 'GCC_PREFIX_HEADER set in %d of %d build configurations' % (
                             len([v for v in prefix_values if v]), len(prefix_values)),
                         'product_type': target.get('productType'),
                         'bridging_headers': sorted(set(_prefix_header_path(v, project_dir)
                                                        for v in bridging_values if v))}
        for phase_id in target.get('buildPhases', []):
            phase = objects.get(phase_id, {})
            if phase.get('isa') != 'PBXSourcesBuildPhase':
                continue
            for bf_id in phase.get('files', []):
                bf = objects.get(bf_id, {})
                path = resolve(bf.get('fileRef', ''))
                if path is None:
                    targets[name]['unresolved'] += 1
                    continue
                file_arc = _arc_from_flags(bf.get('settings', {}).get('COMPILER_FLAGS'))
                membership[path].append({
                    'target': name,
                    'arc': target_arc if file_arc is None else file_arc,
                    'file_flag': file_arc is not None,
                    'arc_source': ('per-file COMPILER_FLAGS' if file_arc is not None else source),
                })
                targets[name]['sources'] += 1
    synchronized = []
    for oid, obj in objects.items():
        if obj.get('isa') == 'PBXFileSystemSynchronizedRootGroup':
            path = resolve(oid)
            synchronized.append(path if path is not None else obj.get('path', '?'))
    return membership, targets, synchronized


# ---------------------------------------------------------------------------
# Objective-C, C and Swift text patterns used across the whole tree

_IMPORT_DIRECTIVE = re.compile(r'^[ \t]*#[ \t]*(?:import|include)\b', re.M)
_IMPORT_PATH = re.compile(r'#[ \t]*(?:import|include)\s*[<"]([^>"\n]+)[>"]')

_OBJC_CONTAINER = re.compile(
    r'@(interface|implementation)\s+(\w+)\s*(<[^>{}@;]*>)?\s*'
    r'(?:\(\s*(\w*)\s*\))?\s*(?::\s*(\w+)\s*(<[^{}@;]*?>)?)?\s*(<[^{}@;]*?>)?')
_OBJC_PROTOCOL_DEF = re.compile(r'@protocol\s+(\w+)(?!\s*[,;\w])')
_NS_SWIFT_NAME_BEFORE = re.compile(r'NS_SWIFT_NAME\s*\(\s*(\w+)\s*\)\s*$')

_SWIFT_CLASS_KEYWORD = re.compile(r'\bclass[ \t]+(\w+)')
_SWIFT_CLASS_PREFIX = re.compile(
    r'^[ \t]*((?:@\w+(?:\([^)\n]*\))?[ \t]+|(?:public|open|internal|fileprivate|private|final)[ \t]+)*)$')
_SWIFT_EXTENSION_KEYWORD = re.compile(r'\bextension[ \t]+([\w.]+)')
_SWIFT_EXTENSION_PREFIX = re.compile(
    r'^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|private|fileprivate|internal|open)[ \t]+)?$')
_SWIFT_NOT_CLASS_NAMES = {'func', 'var', 'let', 'subscript', 'init', 'deinit', 'protocol',
                          'override', 'class', 'static', 'final'}

# A retain, release or autorelease message send: the selector follows the end of a
# receiver expression (a name, a literal's closing quote, or a closing bracket or
# parenthesis), not a ':' (an argument), '[' (a subscript or array literal) or ','.
_RR_SITE = re.compile(r'(?<=[\w\])"}])\s+(retain|release|autorelease)\s*\]|\[\s*super\s+dealloc\s*\]')
_NULL_UNSPECIFIED = re.compile(r'\b(?:null_unspecified|_Null_unspecified|__null_unspecified)\b')
_STRICT_WARNINGS_IMPORT = re.compile(r'#\s*(?:import|include)\s*[<"](?:[^>"]*/)?iTermStrictWarnings\.h[>"]')

HAZARD_PATTERNS = OrderedDict([
    # Any perform...Selector keyword, including wrappers such as it_performNonObjectReturningSelector:.
    ('performSelector', re.compile(r'\b(?!makeObjectsPerformSelector)[A-Za-z_]*[pP]erform[A-Za-z]*Selector[A-Za-z]*\s*:')),
    ('makeObjectsPerformSelector', re.compile(r'\bmakeObjectsPerformSelector\w*\s*:')),
    ('NSSelectorFromString', re.compile(r'\b(?:NSSelectorFromString|sel_registerName|sel_getUid)\s*\(')),
    ('NSClassFromString', re.compile(
        r'\b(?:NSClassFromString|NSProtocolFromString|objc_getClass|objc_lookUpClass)\s*\(')),
    # The runtime API, in four groups (hidden-callers.md section 3).
    # The runtime functions, and anything named for swizzling (iTermSelectorSwizzler, swizzleSelector:,
    # swizzleInstanceMethodSelector:withBlock:).
    ('method replacement', re.compile(
        r'\b(?:method_exchangeImplementations|method_setImplementation|class_replaceMethod|class_addMethod|'
        r'class_addIvar|class_addProperty|class_addProtocol|imp_implementationWithBlock|objc_allocateClassPair|'
        r'objc_registerClassPair|objc_duplicateClass|object_setClass)\s*\(|\b\w*[Ss]wizzl\w*')),
    ('method-list enumeration', re.compile(
        r'\b(?:class_copyMethodList|class_copyPropertyList|class_copyIvarList|class_copyProtocolList|'
        r'protocol_copyMethodDescriptionList|protocol_copyPropertyList|objc_copyClassList|objc_getClassList)\s*\(')),
    ('runtime method lookup', re.compile(
        r'\b(?:class_getInstanceMethod|class_getClassMethod|class_getMethodImplementation\w*|'
        r'method_get\w+|method_copy\w+|property_get\w+|property_copy\w+|ivar_get\w+|object_getIvar|'
        r'object_setIvar\w*|class_getProperty|class_getInstanceVariable|class_getClassVariable|'
        r'protocol_getMethodDescription|protocol_getProperty)\s*\(')),
    ('runtime class query', re.compile(
        r'\b(?:object_getClass|object_getClassName|class_getName|class_getSuperclass|class_respondsToSelector|'
        r'class_conformsToProtocol|class_isMetaClass|objc_getMetaClass)\s*\(')),
    ('forwarding', re.compile(
        r'^[ \t]*[-+]\s*\([^)]*\)\s*(?:forwardInvocation|forwardingTargetForSelector|'
        r'methodSignatureForSelector|resolveInstanceMethod|resolveClassMethod)\s*:', re.M)),
    ('NSInvocation', re.compile(r'\bNSInvocation\b|\bprepareWithInvocationTarget\s*:')),
    ('respondsToSelector', re.compile(r'\b(?:respondsToSelector|instancesRespondToSelector)\s*:')),
    # The runtime functions and iTerm2's wrappers of them: it_setAssociatedObject:forKey:,
    # it_associatedObjectForKey:, psm_yosemiteAssociatedDictionary, and iTermTexture's metadata methods.
    ('associated objects', re.compile(r'\b\w*[aA]ssociated(?:Object|Dictionary)\w*|'
                                      r'\b(?:attachMetadata|metadataForTexture)\s*:')),
    ('@synchronized', re.compile(r'@synchronized\s*\(')),
    ('@try', re.compile(r'@try\b')),
    ('+load/+initialize', re.compile(r'^[ \t]*\+\s*\(\s*void\s*\)\s*(?:load|initialize)\b(?!\s*:)', re.M)),
    ('atomics', re.compile(r'\b_Atomic\b|\batomic_\w+|\bstd::atomic\b|\bOSAtomic\w+|<stdatomic\.h>')),
    # Concurrency primitives (concurrency.md section 10): shown, not deferred.
    ('lock', re.compile(r'\b(?:NSLock|NSRecursiveLock|NSCondition|NSConditionLock)\b|\bos_unfair_lock\w*|'
                        r'\bpthread_(?:mutex|rwlock)\w*')),
    ('dispatch semaphore', re.compile(r'\bdispatch_semaphore\w*')),
    # A thread created or started: detachNewThread..., pthread_create, [[NSThread alloc] ...], and -start sent to a
    # receiver whose name contains thread. Subclasses of NSThread are found from the class relations.
    ('thread created or started', re.compile(r'\bdetachNewThread\w*|\bpthread_create\s*\(|\[\s*\[\s*NSThread\s+alloc\s*\]|'
                                             r'\[\s*[\w.]*[Tt]hread\w*\s+start\s*\]')),
    # iTerm2's own classes and functions for threads, queues, thread-confined state and atomics (shown, not
    # deferred: they are callable from Swift, but the dossier's concurrency table must cover them).
    ('iTerm2 concurrency helper', re.compile(
        r'\b(?:iTermThread|iTermSynchronizedState|iTermMainThreadState|iTermCallback|iTermThreadChecker|'
        r'iTermTaskQueue|iTermGCD|iTermMutationQueue\w*|iTermLegacyAtomicMutableArrayOfWeakObjects|'
        r'iTermPreciseTimersLock|iTermAtomic\w*)\b')),
    # Found by stored_state_matches and Inventory.stored_state, which name the rule behind each match.
    ('stored state', None),
    ('goto', re.compile(r'\bgoto\b')),
    ('volatile', re.compile(r'\bvolatile\b')),
    ('thread-local storage', re.compile(r'\b(?:__thread|_Thread_local|thread_local|threadDictionary)\b|'
                                        r'\bpthread_(?:key_create|getspecific|setspecific)\b')),
    ('objc_msgSend', re.compile(r'\bobjc_msgSend\w*')),
    ('methodForSelector', re.compile(r'\b(?:methodForSelector|instanceMethodForSelector)\s*:')),
    ('sort by selector', re.compile(r'\b(?:sortedArrayUsingSelector|sortUsingSelector)\s*:')),
    ('selector registration', re.compile(
        r'\b(?:scheduledTimerWithTimeInterval|timerWithTimeInterval|initWithFireDate)\s*:[^;\]]*?\bselector\s*:|'
        r'\baddObserver\s*:[^;\]]*?\bselector\s*:|\bregisterUndoWithTarget\s*:[^;\]]*?\bselector\s*:|'
        r'\bsetEventHandler\s*:[^;\]]*?\bandSelector\s*:|'
        # Any other keyword ending in Selector that takes @selector(...), such as didEndSelector:.
        r'\b(?!(?:respondsToSelector|instancesRespondToSelector|performSelector\w*|methodForSelector|'
        r'instanceMethodForSelector|sortedArrayUsingSelector|sortUsingSelector|makeObjectsPerformSelector\w*|'
        r'doesNotRecognizeSelector|NSStringFromSelector)\s*:)\w*[Ss]elector\s*:\s*@selector\b')),
    ('key-value coding/observing', re.compile(
        r'\bvalueForKey(?:Path)?\s*:|\bsetValue\s*:[^;\]]*?\bforKey(?:Path)?\s*:|'
        r'\baddObserver\s*:[^;\]]*?\bforKeyPath\s*:|\bobserveValueForKeyPath\s*:|'
        r'\b(?:will|did)ChangeValueForKey\s*:|\bkeyPathsForValuesAffecting\w+|'
        r'\bautomaticallyNotifiesObserversOf\w+|\bmutable(?:Array|Set|OrderedSet)ValueForKey(?:Path)?\s*:|'
        r'\b(?:dictionaryWithValuesForKeys|setValuesForKeysWithDictionary)\s*:|\bpredicateWithFormat\s*:|'
        r'\bsortDescriptorWithKey\s*:|\binitWithKey\s*:[^;\]]*?\bascending\s*:|'
        r'\bbind\s*:[^;\]]*?\btoObject\s*:[^;\]]*?\bwithKeyPath\s*:|'
        # iTerm2's wrapper that observes user defaults by key path.
        r'\biTermUserDefaultsObserver\b')),
    ('sendAction', re.compile(r'\b(?:sendAction|tryToPerform|targetForAction|supplementalTargetForAction)\s*:')),
    ('doesNotRecognizeSelector', re.compile(r'\bdoesNotRecognizeSelector\s*:')),
    ('conformsToProtocol', re.compile(r'\bconformsToProtocol\s*:')),
    ('objectSpecifier', re.compile(r'\bobjectSpecifier\b')),
    ('NSStringFromClass', re.compile(r'\bNSStringFromClass\s*\(')),
])
_NSSTRING_FROM_SELECTOR = re.compile(r'\b(?:NSStringFromSelector|sel_getName)\s*\(\s*(@selector\b|_cmd\b|[^)\s]*)')
# _cmd used other than as the argument of NSStringFromSelector: as a key, or passed along.
_CMD_OTHER = re.compile(r'(?<!NSStringFromSelector\()(?<!sel_getName\()\b_cmd\b')
_NSCODING_PROTOCOL = re.compile(r'\bNS(?:Secure)?Coding\b')
_CODER_METHOD = re.compile(r'^[ \t]*-\s*\([^)]*\)\s*(initWithCoder|encodeWithCoder|restoreStateWithCoder|'
                           r'encodeRestorableStateWithCoder)\s*:', re.M)
# Attributes that change ownership or method family (hidden-callers.md section 6).
_OWNERSHIP_ATTRIBUTE = re.compile(
    r'\b(?:objc_method_family|ns_returns_retained|ns_returns_not_retained|ns_returns_autoreleased|ns_consumed|'
    r'ns_consumes_self|cf_returns_retained|cf_returns_not_retained|cf_consumed|NS_RETURNS_RETAINED|'
    r'NS_RETURNS_NOT_RETAINED|NS_RETURNS_INNER_POINTER|NS_CONSUMED|NS_CONSUMES_SELF|NS_REPLACES_RECEIVER|'
    r'CF_RETURNS_RETAINED|CF_RETURNS_NOT_RETAINED|CF_CONSUMED|NS_METHOD_FAMILY)\b')
# Selectors that Cocoa looks up by assembling a name: key-value coding collection
# and scripting accessors, observing helpers, validation (hidden-callers.md section 3).
_CONVENTION_SELECTOR = re.compile(
    r'^(?:countOf[A-Z]\w*|objectIn[A-Z]\w*AtIndex:|[a-z]\w*AtIndexes:|get[A-Z]\w*:range:|'
    r'insertObject:in[A-Z]\w*AtIndex:|insert[A-Z]\w*:atIndexes:|removeObjectFrom[A-Z]\w*AtIndex:|'
    r'remove[A-Z]\w*AtIndexes:|replaceObjectIn[A-Z]\w*AtIndex:withObject:|replace[A-Z]\w*AtIndexes:with[A-Z]\w*:|'
    r'enumeratorOf[A-Z]\w*|memberOf[A-Z]\w*:|valueIn[A-Z]\w*AtIndex:|valueIn[A-Z]\w*WithName:|'
    r'valueIn[A-Z]\w*WithUniqueID:|insertIn[A-Z]\w*:|insertIn[A-Z]\w*:atIndex:|removeFrom[A-Z]\w*AtIndex:|'
    r'replaceIn[A-Z]\w*:atIndex:|validate[A-Z]\w*:error:|keyPathsForValuesAffecting[A-Z]\w*|'
    r'automaticallyNotifiesObserversOf[A-Z]\w*|application:delegateHandlesKey:|indicesOf[A-Z]\w*:|'
    r'objectSpecifier|'
    # NSScriptKeyValueCoding overrides, which Cocoa scripting calls for any key.
    r'valueWithUniqueID:inPropertyWithKey:|valueWithName:inPropertyWithKey:|valueAtIndex:inPropertyWithKey:|'
    r'insertValue:inPropertyWithKey:|insertValue:atIndex:inPropertyWithKey:|'
    r'removeValueAtIndex:fromPropertyWithKey:|replaceValueAtIndex:inPropertyWithKey:withValue:|'
    r'coerceValue:forKey:)$')

# Method names in the new, copy, mutableCopy and alloc families, which transfer ownership under ARC
# (hidden-callers.md section 6). Initializers (the init family) are not listed.
_OWNERSHIP_FAMILY = re.compile(r'^(?:new|copy|mutableCopy|alloc)(?:[A-Z_:]|$)')

_DEFINE = re.compile(r'^[ \t]*#[ \t]*define[ \t]+(\w+)(\([^)]*\))?((?:[^\n]*\\\n)*[^\n]*)', re.M)
_METHOD_IN_MACRO = re.compile(r'(?:^|[;{}]|\\\n)\s*[-+]\s*\(\s*[\w\s\*<>,]+\)\s*\w|@implementation\b')
_VA_ARGS_PASTE = re.compile(r',?\s*##\s*__VA_ARGS__')

_CXX_MARKERS = OrderedDict([
    ('std::', re.compile(r'\bstd::')),
    ('scope operator ::', re.compile(r'\w\s*::\s*~?\w')),
    ('template', re.compile(r'\btemplate\s*<')),
    ('namespace', re.compile(r'\bnamespace\b')),
    ('C++ cast', re.compile(r'\b(?:static|reinterpret|const|dynamic)_cast\s*<')),
    ('nullptr', re.compile(r'\bnullptr\b')),
    ('constexpr', re.compile(r'\bconstexpr\b')),
    ('C++ class', re.compile(r'(?<![@\w])class\s+\w+\s*(?:final\s*)?[:{]')),
    ('C++ standard header', re.compile(
        r'^[ \t]*#[ \t]*(?:include|import)\s*<(?:vector|map|unordered_map|set|unordered_set|'
        r'algorithm|memory|string|atomic|random|numeric|functional|utility|deque|list|array|mutex|'
        r'thread|optional|tuple|limits|cmath|cstdlib|cstring|cstdint|iostream|sstream|queue|stack|'
        r'bitset|chrono|type_traits|cassert|cstdio|iterator|new)>', re.M)),
    ('auto', re.compile(r'\bauto\s+[\w&*]+\s*[=:(]')),
    ('new/delete', re.compile(r'\bdelete\s*(?:\[\s*\])?\s*\w+\s*;|\bnew\s+[A-Za-z_][\w:<>]*\s*[(\[{;]')),
    ('operator overload', re.compile(r'\boperator\s*(?:\(\)|\[\]|[-+*/=<>!&|^%~]+)\s*\(')),
])


def strip_cplusplus_blocks(masked):
    """Blanks the parts of a file only compiled as C++ (#ifdef __cplusplus), and directives."""
    out_lines = []
    stack = []  # entries: 'cxx' (inside C++-only branch), 'notcxx', 'other'
    for line in masked.split('\n'):
        m = re.match(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b(.*)$', line)
        if m:
            kind, rest = m.group(1), m.group(2)
            if kind in ('if', 'ifdef', 'ifndef'):
                if '__cplusplus' in rest:
                    negated = kind == 'ifndef' or re.search(r'!\s*(?:defined\s*\(?\s*)?__cplusplus', rest)
                    stack.append('notcxx' if negated else 'cxx')
                else:
                    stack.append('other')
            elif kind in ('else', 'elif') and stack:
                if stack[-1] == 'cxx':
                    stack[-1] = 'notcxx'
                elif stack[-1] == 'notcxx':
                    stack[-1] = 'cxx'
            elif kind == 'endif' and stack:
                stack.pop()
            out_lines.append(_blank(line))
            continue
        out_lines.append(_blank(line) if 'cxx' in stack else line)
    return '\n'.join(out_lines)


def cxx_markers(masked):
    """Names of C++ constructs found in masked source (heuristic)."""
    text = strip_cplusplus_blocks(masked)
    return [name for name, pat in _CXX_MARKERS.items() if pat.search(text)]


def parse_macros(masked):
    """Lists #define directives with their classification (heuristic)."""
    result = []
    for m in _DEFINE.finditer(masked):
        name, params, body = m.group(1), m.group(2), m.group(3)
        pasting_body = _VA_ARGS_PASTE.sub(' ', body)
        result.append({
            'name': name,
            'function_like': params is not None,
            'token_pasting': '##' in pasting_body,
            'defines_method': bool(_METHOD_IN_MACRO.search(body)),
            'declares_static': bool(re.search(r'\bstatic\b', body)),
            'defines_class': bool(re.search(r'@(?:interface|implementation)\b', body)),
            'stringifies': bool(re.search(r'(?<![#\w])#\s*[A-Za-z_]', re.sub(r'##', ' ', body))),
            'defines_function': any(fm.group(1) not in _C_KEYWORDS
                                    for fm in re.finditer(r'\b(\w+)\s*\([^()]*\)\s*\{', body)),
            'offset': m.start(),
        })
    return result


# An argument that is no selector at all.
_NO_SELECTOR = re.compile(r'(?:nil|Nil|NULL|nullptr|0)\b')
# The first argument of a Swift .perform( that looks like a selector: a name or a member access such as
# obj.action, Selector(...) or NSSelectorFromString(...).
_SWIFT_SELECTOR_ARGUMENT = re.compile(r'(?:[a-z_]\w*(?:\s*\.\s*\w+)*\s*[,)]|Selector\s*\(|NSSelectorFromString\s*\()')
# The start of a Swift argument that is not a selector: a string literal, a capitalized name (a type, or
# Selector(...), which is counted on its own), a closure, an array, or an enum case.
_SWIFT_NOT_A_SELECTOR = re.compile(r'[A-Z"{\[.]')
_SWIFT_DECLARATION_BEFORE_PAREN = re.compile(r'(?:\bfunc\s+[^\s(]+|\binit[?!]?|\bsubscript|\bcase\s+\w+)\s*(?:<[^<>]*>\s*)?$')


def _in_swift_declaration(masked, start):
    """True when start is inside the parameters of a Swift func, init or subscript declaration or the associated
    values of an enum case, at any depth of parentheses."""
    depth = 0
    for i in range(start - 1, max(-1, start - 2000), -1):
        ch = masked[i]
        if ch == ')':
            depth += 1
        elif ch == '(':
            if depth == 0:
                if _SWIFT_DECLARATION_BEFORE_PAREN.search(masked, max(0, i - 200), i):
                    return True
            else:
                depth -= 1
        elif ch in '{}':
            return False
    return False


def _in_swift_selector_literal(masked, start):
    """True when start is inside a Swift #selector(...) literal."""
    literal = masked.rfind('#selector', max(0, start - 200), start)
    if literal < 0:
        return False
    depth = 0
    for ch in masked[literal:start]:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth <= 0:
                return False  # the literal closed before start
    return depth > 0


# Keywords that ask about a selector rather than dispatch it.
_SELECTOR_QUERIES = ('respondsToSelector', 'instancesRespondToSelector', 'NSStringFromSelector',
                     'doesNotRecognizeSelector')

# Literal substrings, at least one of which a match of each hazard pattern must
# contain. Checked first because a substring test is far faster than a regex.
HAZARD_NEEDLES = {
    'performSelector': ('erformSelector', 'Selector'),
    'makeObjectsPerformSelector': ('makeObjectsPerformSelector',),
    'NSSelectorFromString': ('NSSelectorFromString', 'sel_'),
    'NSClassFromString': ('NSClassFromString', 'NSProtocolFromString', 'objc_'),
    'method replacement': ('method_', 'class_', 'imp_', 'objc_', 'object_', 'wizzl'),
    'method-list enumeration': ('class_', 'protocol_', 'objc_'),
    'runtime method lookup': ('class_', 'method_', 'property_', 'ivar_', 'object_', 'protocol_'),
    'runtime class query': ('object_', 'class_', 'objc_'),
    'forwarding': ('forwardInvocation', 'forwardingTarget', 'methodSignatureForSelector', 'resolve'),
    'NSInvocation': ('NSInvocation', 'prepareWithInvocationTarget'),
    'respondsToSelector': ('espondToSelector', 'espondsToSelector'),
    'associated objects': ('ssociated', 'attachMetadata', 'metadataForTexture'),
    'iTerm2 concurrency helper': ('iTerm',),
    '@synchronized': ('@synchronized',),
    '@try': ('@try',),
    '+load/+initialize': ('load', 'initialize'),
    'atomics': ('_Atomic', 'atomic', 'OSAtomic'),
    'lock': ('NSLock', 'NSRecursiveLock', 'NSCondition', 'os_unfair_lock', 'pthread_'),
    'dispatch semaphore': ('dispatch_semaphore',),
    'thread created or started': ('detachNewThread', 'pthread_create', 'NSThread', 'hread'),
    'goto': ('goto',),
    'volatile': ('volatile',),
    'thread-local storage': ('thread', 'Thread'),
    'objc_msgSend': ('objc_msgSend',),
    'methodForSelector': ('ethodForSelector',),
    'sort by selector': ('UsingSelector',),
    'selector registration': ('selector',),
    'key-value coding/observing': ('ForKey', 'forKey', 'keyPathsForValuesAffecting', 'automaticallyNotifies',
                                   'ForKeys', 'predicateWithFormat', 'WithKey', 'bind', 'iTermUserDefaultsObserver'),
    'sendAction': ('sendAction', 'tryToPerform', 'ForAction'),
    'doesNotRecognizeSelector': ('doesNotRecognizeSelector',),
    'conformsToProtocol': ('conformsToProtocol',),
    'objectSpecifier': ('objectSpecifier',),
    'NSStringFromClass': ('NSStringFromClass',),
}


# dispatch_ calls that run a block or handler on a queue, by name; any other dispatch_ call is counted when
# a block literal (^) is among its arguments.
_DISPATCH_BLOCK_NAME = re.compile(r'(?:async|sync|after|barrier_|apply|group_async|group_notify|source_set_\w*handler|'
                                  r'io_|read|write|data_apply|data_create|block_|workloop)')
_DISPATCH_CALL = re.compile(r'\bdispatch_(\w+)\s*\(')


# A message that hands a block literal to something that runs it elsewhere, by the keyword's name
# (heuristic, block_dispatch_keyword_sites): any keyword containing dispatch, sync (so async too), thread,
# perform...Block or operation...Block, with a block literal (^) as its argument, such as dispatchAsync:^,
# performBlock:^, addOperationWithBlock:^ or detachNewThreadWithBlock:^; and a block literal passed to
# usingBlock: in a message that also names a queue: (notification observers).
_BLOCK_DISPATCH_KEYWORD = re.compile(r'[Dd]ispatch|[Ss]ync|[Tt]hread|[Pp]erform\w*Block|[Oo]peration\w*Block')
_QUEUE_USING_BLOCK = re.compile(r'\bqueue\s*:[^;\]]*?\busingBlock\s*:\s*\^')


_KEYWORD_BEFORE_BLOCK = re.compile(r'\b(\w+)\s*:\s*$')


def block_dispatch_keyword_sites(masked):
    """Offsets of the messages described at _BLOCK_DISPATCH_KEYWORD in masked source. Each ^ is found with
    str.find and the keyword before it is checked, because a pattern that tests every word is slow."""
    found = []
    pos = masked.find('^')
    while pos >= 0:
        m = _KEYWORD_BEFORE_BLOCK.search(masked, max(0, pos - 200), pos)
        if m and _BLOCK_DISPATCH_KEYWORD.search(m.group(1)):
            found.append(m.start())
        pos = masked.find('^', pos + 1)
    if 'usingBlock' in masked:
        found.extend(m.start() for m in _QUEUE_USING_BLOCK.finditer(masked))
    return found


def dispatch_sites(masked, wrappers=None, words=None):
    """(offsets of blocks dispatched to a queue, offsets of dispatch group and once calls) in masked source.

    A dispatch_ call counts as dispatching a block when its name is in the
    block-taking family (async, sync, after, barrier, apply, group_async,
    group_notify, source handlers, io, data, block and workloop calls) or a
    block literal is among its arguments; dispatch_once is a primitive, not a
    dispatch. NSOperationQueue counts as dispatching, and so does a message
    matching _BLOCK_DISPATCH_KEYWORD and a call to a block-dispatching wrapper
    found in scope (DispatchWrappers). dispatch_group_* and dispatch_once calls
    are the primitives (semaphores are counted separately).
    """
    dispatched = set()
    primitives = []
    if 'NSOperationQueue' in masked:
        dispatched.update(m.start() for m in re.finditer(r'\bNSOperationQueue\b', masked))
    if 'dispatch_' in masked:
        for m in _DISPATCH_CALL.finditer(masked):
            name = m.group(1)
            if name.startswith('group_') or name.startswith('once'):
                primitives.append(m.start())
            if name.startswith('once') or name.startswith('semaphore'):
                continue
            close = find_matching(masked, m.end() - 1, '(', ')')
            if _DISPATCH_BLOCK_NAME.match(name) or '^' in masked[m.end():close]:
                dispatched.add(m.start())
    if '^' in masked:
        dispatched.update(block_dispatch_keyword_sites(masked))
    if wrappers is not None:
        dispatched.update(wrappers.dispatch_offsets(masked, words))
    return sorted(dispatched), primitives


def message_open(masked, keyword_start):
    """(index of the [, receiver text) of the message whose first keyword starts at keyword_start, or None.

    None when the keyword is not directly inside [ ], or is not the first
    keyword of its message.
    """
    depth = 0
    i = keyword_start - 1
    limit = max(0, keyword_start - 500)
    while i >= limit:
        ch = masked[i]
        if ch in ')]}':
            depth += 1
        elif ch in '([{':
            if depth == 0:
                if ch != '[':
                    return None
                receiver = masked[i + 1:keyword_start]
                flat = remove_balanced(remove_balanced(receiver, '[', ']'), '(', ')')
                return None if ':' in flat else (i, receiver)
            depth -= 1
        elif ch == ';' and depth == 0:
            return None
        i -= 1
    return None


def message_receiver(masked, keyword_start):
    """The receiver text of the message whose first keyword starts at keyword_start, or None (see message_open)."""
    found = message_open(masked, keyword_start)
    return found[1] if found else None


def is_declaration(masked, start):
    """True when start is inside an Objective-C method declaration or definition (by text): the statement
    before it, after any preprocessor and @-directive lines, begins with - or +."""
    statement = masked[max(masked.rfind(';', 0, start), masked.rfind('{', 0, start),
                           masked.rfind('}', 0, start)) + 1:start]
    code = '\n'.join(line for line in statement.split('\n') if not line.lstrip().startswith(('#', '@')))
    return code.lstrip()[:1] in ('-', '+')


def in_selector_literal(masked, start):
    """True when start is inside @selector(...) or #selector(...)."""
    return bool(re.search(r'[@#]selector\s*\(\s*[\w:]*$', masked[max(0, start - 80):start]))


# ---------------------------------------------------------------------------
# Stored state
#
# A file is found to encode or decode stored state by four rules, and every match names the rule and the entry
# behind it, so that a reader can check it from the line alone:
#   1. Direct API use: STORED_STATE_DIRECT, the archiving and coder keywords and arrangement names found by
#      stored_state_words, and writes to a receiver that is user defaults by its text (stored_state_matches).
#   2. A use of an entry of STORED_STATE_API, the named list of iTerm2's own stored-state classes and helpers.
#   3. A typed keyed setter (_TYPED_SETTER) whose key is a KEY_ or k...Preference... constant; or such a setter,
#      or setObjectsFromDictionary:, sent to self, super, weakSelf or strongSelf in a class whose superclass
#      chain reaches a class of the list or a class that has a constant-key setter of its own
#      (Inventory.stored_state, which has the class relations).
#   4. A class whose superclass chain reaches a class of the list (Inventory.stored_state).
# Nothing else is followed: a call to a method that stores state is not itself a match.

# Rule 1: (entry, what it is, literal substrings one of which every match contains, pattern).
STORED_STATE_DIRECT = (
    ('keyed archiver', 'writes or reads a keyed archive', ('NSKeyed',),
     re.compile(r'\bNSKeyed(?:Archiver|Unarchiver)\b')),
    ('property list serialization', 'converts a property list to or from data', ('NSPropertyListSerialization',),
     re.compile(r'\bNSPropertyListSerialization\b')),
    ('NSCoding', 'the NSCoding or NSSecureCoding protocol', ('Coding',), re.compile(r'\bNS(?:Secure)?Coding\b')),
    ('NSCoder', 'a coder, which reads or writes an archive', ('NSCoder',), re.compile(r'\bNSCoder\b')),
    # encodeObject:forKey:, decodeObjectOfClass:[X class] forKey:, decodeIntegerForKey:. The arguments may hold
    # brackets, so the search for forKey: stops only at the end of the statement.
    ('keyed coding', 'encodes or decodes a value by key', ('code',),
     re.compile(r'\b(?:en|de)code\w*\s*:[^;{}]*?\bforKey\s*:|\bdecode\w*ForKey\s*:')),
    # iTerm2's own (restorableState, restoreFromState:) and AppKit's.
    ('restorable state', 'saves or restores window or session state', ('estor',),
     re.compile(r'\b(?:restorableState\w*|restoreFromState\w*|restoreState\w*|encodeRestorableState\w*|'
                r'invalidateRestorableState|restoreWindowWithIdentifier\w*|restorationClass|setRestorable)\b')),
    # Whatever the receiver, except strings written with an encoding (writeToFile:atomically:encoding:error:,
    # which _written_with_encoding finds).
    ('file read or written whole', 'reads or writes a whole file, such as a property list', ('ContentsOf', 'writeTo'),
     re.compile(r'\b(?:dictionary|array)WithContentsOf(?:File|URL)\b|\bwriteTo(?:File|URL)\s*:')),
    ('CFPreferences', 'reads or writes preferences directly', ('CFPreferences',), re.compile(r'\bCFPreferences\w*\s*\(')),
    ('Core Data', 'Core Data, which saves records to a store',
     ('NSManagedObject', 'NSEntityDescription', 'NSFetchRequest', 'NSPersistent'),
     re.compile(r'\bNSManagedObject\w*|\bNSEntityDescription\b|\bNSFetchRequest\w*|\bNSPersistent\w*')),
    ('SQLite', 'SQLite, which saves records to a database file', ('sqlite3',), re.compile(r'\bsqlite3(?:_\w+)?\b')),
)
_ARCHIVING_WORD = ('archiving or coder keyword', 'a message keyword that names archiving or a coder')
_ARRANGEMENT_WORD = ('arrangement', 'names a window arrangement, which is saved by name')
_USER_DEFAULTS_WRITE = ('user defaults write', 'a set or remove message, or a property assignment, to a receiver '
                                               'that is user defaults by its text')

# Rule 2: the named list of iTerm2's stored-state API. Each entry is (name, kind, words, what it persists). kind
# says what counts as a use: 'class', the name as a whole word outside preprocessor lines and @class forward
# declarations; 'base', a class that counts only through rules 3 and 4, because naming it stores nothing;
# 'setter', a message to the class whose first keyword begins with set, or an assignment to one of its
# properties; 'message', one of words[1:] sent to the class words[0], as a message or a property; 'keyword', one
# of words as a message keyword. Built by searching the tree for classes whose own implementation
# uses rule 1 heavily or whose name marks them (Preferences, UserDefaults, Restorable, Restoration, Archive,
# Encoder, Decoder, Database, Arrangement), then read one by one; general-purpose classes are left out.
STORED_STATE_API = (
    ('iTermPreferences', 'class', (), 'global settings, kept in user defaults'),
    ('iTermProfilePreferences', 'class', (), 'values in profiles, which ProfileModel saves'),
    ('iTermUserDefaults', 'class', (), 'values kept in user defaults by iTerm2, read and written through typed '
                                       'accessors'),
    ('iTermAdvancedSettingsModel', 'setter', (), 'advanced settings, kept in user defaults (only setters count: '
                                                 'reading an advanced setting gets a value the model has already '
                                                 'decoded)'),
    ('iTermRemotePreferences', 'class', (), 'settings loaded from and saved to a custom folder or URL'),
    ('iTermSecureUserDefaults', 'class', (), 'settings kept in a file that only an administrator can change'),
    ('iTermPersistentRateLimitedUpdate', 'class', (), 'the time of its last update, kept in user defaults'),
    ('iTermPreferencesBaseViewController', 'base', (), 'a settings pane; its setters write user defaults'),
    ('iTermProfilePreferencesBaseViewController', 'base', (), 'a profile settings pane; its setters write the '
                                                              'profile'),
    ('iTermWarning silencing', 'message',
     ('iTermWarning', 'unsilenceIdentifier', 'setIdentifier', 'identifierIsSilenced', 'silenceEpisodeTokenForIdentifier',
      'clearSavedSelectionForIdentifier', 'conditionalSavedSelectionForIdentifier', 'setShowRememberedAlerts',
      'showRememberedAlerts'),
     'remembered answers to warnings, kept in user defaults'),
    ('NSData+iTerm archive helpers', 'keyword',
     ('it_dataWithArchivedObject', 'it_dataWithSecurelyArchivedObject', 'it_unarchivedObjectOfClasses',
      'it_unarchivedObjectOfBasicClassesWithError'),
     'keyed archives'),
    # The restoration graph, which window and session state is encoded into and saved in a database.
    ('iTermGraphEncoder', 'class', (), 'the restoration graph that window and session state is encoded into'),
    ('iTermGraphDeltaEncoder', 'class', (), 'changes to the restoration graph since the last save'),
    ('iTermEncoderGraphRecord', 'class', (), 'a node of the restoration graph as saved and loaded'),
    ('iTermGraphDatabase', 'class', (), 'the restoration graph, saved in an SQLite database'),
    ('iTermGraphTableTransformer', 'class', (), 'restoration graph records rebuilt from database rows'),
    ('iTermEncoderAdapter', 'class', (), 'state written through the restoration encoder interface'),
    ('iTermGraphEncoderAdapter', 'class', (), 'state written into the restoration graph through the encoder '
                                              'interface'),
    ('iTermMutableDictionaryEncoderAdapter', 'class', (), 'state written into a dictionary through the restoration '
                                                          'encoder interface'),
    ('iTermGraphCodable', 'class', (), 'objects encoded into and decoded from the restoration graph'),
    ('iTermGraphEncodable', 'class', (), 'objects encoded into the restoration graph'),
    # Databases.
    ('iTermDatabase', 'class', (), 'an SQLite database file'),
    ('iTermDatabaseResultSet', 'class', (), 'rows read from an SQLite database file'),
    ('iTermSqliteDatabaseImpl', 'class', (), 'an SQLite database file'),
    ('FMDatabase', 'class', (), 'an SQLite database file, through FMDB'),
    ('FMResultSet', 'class', (), 'rows read from an SQLite database file, through FMDB'),
    # Window state saved for restoration at launch, and the classes around it.
    ('iTermRestorableStateController', 'class', (), 'window state saved for restoration at launch'),
    ('iTermRestorableStateDriver', 'class', (), 'the cycle that saves and restores window state'),
    ('iTermRestorableStateRecord', 'class', (), 'the saved state of one window'),
    ('iTermRestorableStateRestorer', 'class', (), 'window state read back at launch'),
    ('iTermRestorableStateSaver', 'class', (), 'window state written for restoration'),
    ('iTermRestorableStateSQLite', 'class', (), 'window state saved in an SQLite database'),
    ('iTermRestorableStateSaving', 'class', (), 'objects whose state is saved for restoration'),
    ('iTermRestorableStateRestoring', 'class', (), 'objects whose state is restored at launch'),
    ('iTermRestorableStateIndex', 'class', (), 'the index of saved window state'),
    ('iTermRestorableWindowController', 'class', (), 'windows whose state is saved for restoration'),
    ('PseudoTerminalRestorer', 'class', (), 'windows restored from saved state at launch'),
    ('iTermRestorableSession', 'class', (), 'a closed or buried session kept with its arrangement, which restorable '
                                            'state saves'),
    # Profile storage.
    ('ProfileModel', 'class', (), 'the profiles, saved in user defaults'),
    ('ITAddressBookMgr writes', 'message',
     ('ITAddressBookMgr', 'encodeColor', 'decodeColor', 'setDefaultsInBookmark', 'removeProfile'),
     'colors encoded into and decoded from profiles, profile defaults, and profile removal'),
    ('iTermProfileModelJournalModel', 'class', (), 'changes to the saved profiles'),
    ('iTermProfileModelJournalParams', 'class', (), 'changes to the saved profiles'),
    ('BookmarkJournalEntry', 'class', (), 'a change to the saved profiles'),
    ('iTermDynamicProfileManager', 'class', (), 'profiles loaded from and written to dynamic profile files'),
    # Other models that save what the user makes.
    ('iTermSnippetsModel', 'class', (), 'the snippets, saved in user defaults'),
    ('iTermActionsModel', 'class', (), 'the actions, saved in user defaults'),
    # The shell history store and its Core Data entities.
    ('iTermShellHistoryController', 'class', (), 'the shell history store (Core Data)'),
    ('iTermCommandHistoryEntryMO', 'class', (), 'a command history record in the shell history store (Core Data)'),
    ('iTermCommandHistoryCommandUseMO', 'class', (), 'a command use record in the shell history store (Core Data)'),
    ('iTermHostRecordMO', 'class', (), 'a host record in the shell history store (Core Data)'),
    ('iTermRecentDirectoryMO', 'class', (), 'a recent directory record in the shell history store (Core Data)'),
)
# The classes of the list, for rules 3 and 4.
STORED_STATE_API_CLASSES = dict((name, persists) for name, kind, _, persists in STORED_STATE_API
                                if kind in ('class', 'base'))


def _named_api_pattern(name, kind, words):
    """The pattern for an entry of STORED_STATE_API that is not a plain class; group 1 or 2 is the use."""
    if kind == 'setter':
        return re.compile(r'\[\s*(%s\s+set[A-Z]\w*\s*:)(?!:)|\b(%s\s*\.\s*\w+\s*=)(?!=)' % (name, name))
    names = '|'.join(words[1:]) if kind == 'message' else '|'.join(words)
    if kind == 'message':
        return re.compile(r'\[\s*(%s\s+(?:%s)\b)|\b(%s\s*\.\s*(?:%s)\b)' % (words[0], names, words[0], names))
    return re.compile(r'\b((?:%s)\s*:)(?!:)' % names)


_NAMED_API_PATTERNS = tuple((name, persists, _named_api_pattern(name, kind, words),
                             words[0] if kind == 'message' else (name if kind == 'setter' else words))
                            for name, kind, words, persists in STORED_STATE_API if kind not in ('class', 'base'))

# Rule 3.
_TYPED_SETTER = re.compile(r'\b(set(?:Bool|Int|Integer|UnsignedInteger|Float|Double|String|Object|'
                           r'ObjectsFromDictionary))\s*:(?!:)')
_TYPED_SETTER_NEEDLES = ('setBool', 'setInt', 'setUnsignedInteger', 'setFloat', 'setDouble', 'setString',
                         'setObject')
_PREFERENCE_KEY = re.compile(r'KEY_\w+|k(?=[A-Z])\w*Preference\w*')
_FOR_KEY = re.compile(r'\bforKey\s*:')
_FOR_KEY_ARGUMENT = re.compile(r'\bforKey\s*:\s*([A-Za-z_]\w*)\s*(?=$|[A-Za-z_]\w*\s*:)')
SELF_RECEIVERS = ('self', 'super', 'weakSelf', 'strongSelf')
_CONSTANT_KEY_WHY = 'a typed keyed setter whose key is a profile or preference key constant'
_SELF_SEND_WHY = ('a typed keyed setter or setObjectsFromDictionary: sent to self or super in a subclass of a class '
                  'on the named list or of a class with a typed keyed setter whose key is a constant')
# When several rules match at the same place, the match is reported once, under the first rule in this order.
STORED_STATE_RULE_ORDER = (2, 1, 3, 4)

# User defaults writes: a message whose first keyword starts with set or removes an object or domain, sent to a
# receiver whose text contains "defaults" in any case or is a variable the file declares as NSUserDefaults * or
# assigns from standardUserDefaults or userDefaults; and an assignment through dot syntax to a property of a word
# containing "defaults".
_USER_DEFAULTS_RECEIVER = re.compile(r'(?i)defaults')
_STORED_STATE_WRITE_KEYWORD = re.compile(
    r'\b(?:set\w*|removeObject\w*|removePersistentDomain\w*|removeVolatileDomain\w*|removeSuiteNamed)\s*:(?!:)')
_DEFAULTS_VARIABLE = re.compile(
    r'\bNSUserDefaults\s*\*\s*(?:const\s+)?(\w+)|'
    r'\b(\w+)\s*=\s*\[\s*(?:NSUserDefaults|iTermUserDefaults)\s+(?:standardUserDefaults|userDefaults)\s*\]')
_PROPERTY_ASSIGNMENT = re.compile(r'\s*\.\s*\w+\s*=(?!=)')
# Words that are stored state wherever they occur, found by stored_state_words: any message keyword that names
# archiving or a coder (archivedDataWithRootObject:, initWithCoder:, encodeGraphWithEncoder:; Metal's render,
# compute, blit and command encoders are not coders), and any identifier naming a window arrangement.
_STORED_STATE_KEYWORD_WORD = re.compile(
    r'[Aa]rchiv|Coder|(?<![Rr]ender)(?<![Cc]ompute)(?<![Bb]lit)(?<![Cc]ommand)Encoder|Decoder')
_STORED_STATE_ANY_WORD = re.compile(r'[Aa]rrangement|ARRANGEMENT')
_STORED_STATE_WORD_NEEDLES = ('rchiv', 'oder', 'rrangement', 'RRANGEMENT')
_KEYWORD_COLON = re.compile(r'\s*:(?!:)')
_WORD_CHAR = re.compile(r'\w').match


def _word_at(text, pos, length):
    """(start, end) of the whole word that contains text[pos:pos + length]."""
    start, end = pos, pos + length
    while start > 0 and _WORD_CHAR(text[start - 1]):
        start -= 1
    while end < len(text) and _WORD_CHAR(text[end]):
        end += 1
    return start, end


def stored_state_words(masked):
    """Maps the offset of each word described above _STORED_STATE_KEYWORD_WORD in masked source to (end, entry,
    why). Each word is found with str.find, because a pattern that tests every word is slow on large files."""
    found = {}
    for needle in _STORED_STATE_WORD_NEEDLES:
        pos = masked.find(needle)
        while pos >= 0:
            start, end = _word_at(masked, pos, len(needle))
            word = masked[start:end]
            if _STORED_STATE_ANY_WORD.search(word):
                found[start] = (end, ) + _ARRANGEMENT_WORD
            elif _STORED_STATE_KEYWORD_WORD.search(word) and _KEYWORD_COLON.match(masked, end):
                found[start] = (masked.index(':', end) + 1, ) + _ARCHIVING_WORD
            pos = masked.find(needle, end)
    return found


def _written_with_encoding(masked, match):
    """True when a writeToFile: or writeToURL: match is part of a message with an encoding: keyword, looking past
    nested brackets and parentheses: to the end of the message, or to the end of the statement when the keyword is
    not the first of its message."""
    if not match.group(0).startswith('writeTo'):
        return False
    opened = message_open(masked, match.start())
    if opened:
        end = find_matching(masked, opened[0], '[', ']')
    else:
        end = masked.find(';', match.end())
        end = len(masked) if end < 0 else end
    rest = remove_balanced(remove_balanced(masked[match.end():end], '[', ']'), '(', ')')
    return bool(re.search(r'\bencoding\s*:', rest))


def _match(offset, text, rule, entry, why):
    return OrderedDict([('offset', offset), ('text', ws(text)[:60]), ('rule', rule), ('entry', entry), ('why', why)])


def _user_defaults_writes(masked):
    """Rule 1 user defaults writes in masked source, as matches."""
    out = []
    lowered = masked.lower()
    if 'defaults' not in lowered:
        return out
    variables = set(a or b for a, b in _DEFAULTS_VARIABLE.findall(masked))
    variable = re.compile(r'\b(?:%s)\b' % '|'.join(sorted(variables))) if variables else None
    for m in _STORED_STATE_WRITE_KEYWORD.finditer(masked):
        receiver = message_receiver(masked, m.start())
        if receiver is not None and (_USER_DEFAULTS_RECEIVER.search(receiver) or
                                     (variable is not None and variable.search(receiver))):
            out.append(_match(m.start(), m.group(0), 1, *_USER_DEFAULTS_WRITE))
    pos = lowered.find('defaults')
    while pos >= 0:
        start, end = _word_at(masked, pos, len('defaults'))
        a = _PROPERTY_ASSIGNMENT.match(masked, end)
        if a:
            out.append(_match(start, masked[start:a.end()], 1, *_USER_DEFAULTS_WRITE))
        pos = lowered.find('defaults', end)
    return out


def _named_api_uses(code):
    """Rule 2 matches in code (masked source with preprocessor lines blanked)."""
    out = []
    for name, kind, _, persists in STORED_STATE_API:
        if kind != 'class':
            continue
        pos = code.find(name)
        while pos >= 0:
            end = pos + len(name)
            if (pos == 0 or not _WORD_CHAR(code[pos - 1])) and (end == len(code) or not _WORD_CHAR(code[end])) and \
                    not code[code.rfind('\n', 0, pos) + 1:pos].lstrip().startswith('@class'):
                out.append(_match(pos, name, 2, name, persists))
            pos = code.find(name, end)
    for name, persists, pattern, needles in _NAMED_API_PATTERNS:
        if not any(n in code for n in ((needles,) if isinstance(needles, str) else needles)):
            continue
        for m in pattern.finditer(code):
            group = 1 if m.group(1) is not None else 2
            out.append(_match(m.start(group), m.group(group), 2, name, persists))
    return out


def _typed_setters(masked):
    """Rule 3 in masked source: (matches whose key is a constant, sends to self or super that need the class)."""
    matches, self_sends = [], []
    if not any(n in masked for n in _TYPED_SETTER_NEEDLES):
        return matches, self_sends
    for m in _TYPED_SETTER.finditer(masked):
        opened = message_open(masked, m.start())
        if opened is None:
            continue
        receiver = opened[1].strip()
        args = remove_balanced(remove_balanced(masked[m.end():find_matching(masked, opened[0], '[', ']')],
                                               '[', ']'), '(', ')')
        keyword = m.group(1)
        if keyword != 'setObjectsFromDictionary':
            if not _FOR_KEY.search(args):
                continue
            key = _FOR_KEY_ARGUMENT.search(args)
            if key and _PREFERENCE_KEY.match(key.group(1)):
                matches.append(_match(m.start(), keyword + ':', 3, 'key ' + key.group(1), _CONSTANT_KEY_WHY))
                continue
        if receiver in SELF_RECEIVERS:
            self_sends.append(OrderedDict([('offset', m.start()), ('text', keyword + ':'), ('receiver', receiver)]))
    return matches, self_sends


def first_by_rule(matches):
    """One match per offset, the one whose rule comes first in STORED_STATE_RULE_ORDER, sorted by offset."""
    best = {}
    for m in matches:
        if m['offset'] not in best or \
                STORED_STATE_RULE_ORDER.index(m['rule']) < STORED_STATE_RULE_ORDER.index(best[m['offset']]['rule']):
            best[m['offset']] = m
    return [best[o] for o in sorted(best)]


def stored_state_matches(masked):
    """Stored-state matches in masked source by rules 1, 2 and 3 for constant keys, and the typed keyed setters
    sent to self or super, which need the class relations (Inventory.stored_state). Returns (matches,
    self_sends); each match has offset, text, rule, entry and why."""
    found = []
    # Rule 1 does not look inside #pragma lines (#pragma mark - NSCoding names a section, it stores nothing).
    rule1 = _PRAGMA_LINE.sub(lambda m: _blank(m.group(0)), masked) if 'pragma' in masked else masked
    for start, (end, entry, why) in stored_state_words(rule1).items():
        found.append(_match(start, rule1[start:end], 1, entry, why))
    for entry, why, needles, pattern in STORED_STATE_DIRECT:
        if any(n in rule1 for n in needles):
            found.extend(_match(m.start(), m.group(0), 1, entry, why) for m in pattern.finditer(rule1)
                         if not _written_with_encoding(rule1, m))
    found.extend(_user_defaults_writes(rule1))
    found.extend(_named_api_uses(strip_preprocessor(masked)))
    typed, self_sends = _typed_setters(masked)
    found.extend(typed)
    return first_by_rule(found), self_sends


def stored_state_sites(masked):
    """Offsets of the stored-state matches in masked source that need no class relations (stored_state_matches)."""
    return [m['offset'] for m in stored_state_matches(masked)[0]]


_IDENTIFIER = re.compile(r'[A-Za-z_]\w*')
# A parameter type that is a block: written with ^, or a typedef whose name ends in Block or block_t.
_BLOCK_TYPE = re.compile(r'\^|\b\w*(?:Block|block_t)\b')


def block_parameter_keywords(signature):
    """The keywords of an Objective-C method signature whose parameter type is a block (by text)."""
    out = []
    for m in re.finditer(r'(\w+)\s*:\s*\(', signature):
        close = find_matching(signature, m.end() - 1, '(', ')')
        if _BLOCK_TYPE.search(signature[m.end():close]):
            out.append(m.group(1))
    return out


def has_block_parameter(header):
    """True when the parameter list of a C function, from the text before its body, has a block type."""
    open_ = header.find('(')
    return open_ >= 0 and bool(_BLOCK_TYPE.search(header[open_:]))


# Words that come before a function name in a declaration or definition but before a call too.
_CALL_PRECEDING_WORDS = ('return', 'else', 'case', 'do', 'sizeof', 'typeof')


def _is_call(masked, start):
    """True when the function name at start is called there, not declared or defined (by text)."""
    before = masked[max(0, start - 60):start].rstrip()
    word = re.search(r'(\w+)$', before)
    return not before.endswith('*') and not (word and word.group(1) not in _CALL_PRECEDING_WORDS)


_KEYWORD_TOKEN = re.compile(r'\b([A-Za-z_]\w*)\s*:(?!:)')
_CALL_TOKEN = re.compile(r'\b([A-Za-z_]\w*)\s*\(')

# Keywords of common AppKit and Foundation methods that take a block. An in-scope method with one of these
# keywords is never used as a block-dispatching wrapper, because every call to the system method would match.
BLOCK_KEYWORDS_NEVER_WRAPPERS = ('completionHandler', 'completionBlock', 'usingBlock', 'withBlock', 'withReply',
                                 'replyHandler', 'errorHandler', 'resultHandler', 'performBlock')


class DispatchWrappers(object):
    """Methods and functions in scope that dispatch a block parameter, so that a call to one is a dispatch.

    Found by Inventory._discover_wrappers: the keywords that carry a block
    parameter, and function names. defined_at maps each wrapper as printed
    (keyword: or name()) to where it is defined.
    """

    def __init__(self, keywords=(), functions=(), defined_at=None, passes=0, max_passes=0):
        self.keywords = sorted(keywords)
        self.functions = sorted(functions)
        self.defined_at = dict(defined_at or {})
        self.passes = passes
        self.max_passes = max_passes
        self._keywords = frozenset(keywords)
        self._functions = frozenset(functions)
        self._all = self._keywords | self._functions

    def _matches(self, names, pattern, masked, words):
        """(offset, match) for each place a name occurs as a word and pattern matches there. Each name is found
        with str.find, because a regular expression over every identifier is slow on large files."""
        out = []
        for name in names & words:
            pos = masked.find(name)
            while pos >= 0:
                end = pos + len(name)
                # The patterns begin with \\b, so only the end needs checking here.
                if end == len(masked) or not _WORD_CHAR(masked[end]):
                    m = pattern.match(masked, pos)
                    if m:
                        out.append((pos, m))
                pos = masked.find(name, end)
        return out

    def dispatch_offsets(self, masked, words=None):
        """Maps the offset of each call to a wrapper in masked source to the wrapper (keyword: or name())."""
        words = set(_IDENTIFIER.findall(masked)) & self._all if words is None else words
        out = {}
        if not words:
            return out
        for pos, m in self._matches(self._keywords, _KEYWORD_TOKEN, masked, words):
            if not is_declaration(masked, pos) and not in_selector_literal(masked, pos):
                out[pos] = m.group(1) + ':'
        for pos, m in self._matches(self._functions, _CALL_TOKEN, masked, words):
            if _is_call(masked, pos):
                out[pos] = m.group(1) + '()'
        return out

    def as_dict(self):
        return OrderedDict([('block_dispatch', OrderedDict([('keywords', self.keywords), ('functions', self.functions),
                                                            ('passes', self.passes),
                                                            ('max_passes', self.max_passes)]))])


def hazard_sites(masked, wrappers=None, words=None, dispatch=None, stored=None):
    """Maps each text hazard in a masked file to the offsets of its matches.

    words, when given, is the set of identifiers in the file that are
    wrapper names (DispatchWrappers); dispatch is (dispatched-block offsets,
    dispatch primitive offsets) and stored the stored-state offsets, when
    already found, so that they are not found again.
    """
    sites = OrderedDict()
    for name, pat in HAZARD_PATTERNS.items():
        if name == 'stored state':
            found = stored_state_sites(masked) if stored is None else sorted(stored)
        elif not any(needle in masked for needle in HAZARD_NEEDLES[name]):
            continue
        else:
            found = [m.start() for m in pat.finditer(masked)]
        if found:
            sites[name] = found
    if 'NSStringFromSelector' in masked or 'sel_getName' in masked:
        literal, cmd, var = [], [], []
        for m in _NSSTRING_FROM_SELECTOR.finditer(masked):
            arg = m.group(1)
            (literal if arg.startswith('@selector') else cmd if arg == '_cmd' else var).append(m.start())
        for name, found in (('NSStringFromSelector(@selector)', literal), ('NSStringFromSelector(_cmd)', cmd),
                            ('NSStringFromSelector(variable)', var)):
            if found:
                sites[name] = found
    dispatched, primitives = dispatch_sites(masked, wrappers, words) if dispatch is None else dispatch
    if dispatched:
        sites['block dispatched to a queue'] = dispatched
    if primitives:
        sites['dispatch group or once'] = primitives
    if '_cmd' in masked:
        other_cmd = [m.start() for m in _CMD_OTHER.finditer(masked)]
        if other_cmd:
            sites['_cmd as a value'] = other_cmd
    return sites


def file_hazards(masked, wrappers=None):
    """Counts each text hazard in a masked file."""
    return OrderedDict((name, len(found)) for name, found in hazard_sites(masked, wrappers).items())


_CONDITIONAL_DIRECTIVE = re.compile(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b[ \t]*(.*?)[ \t]*$')
# A line holding only a macro invocation such as NS_ASSUME_NONNULL_BEGIN.
_LONE_MACRO_LINE = re.compile(r'^[ \t]*[A-Z_][A-Z0-9_]*[ \t]*(?:\([^()\n]*\))?[ \t]*;?[ \t]*$')


def wholly_conditional(masked):
    """The preprocessor condition that every line of code in a file is under, or None.

    Returns {'condition': text, 'first_line': n, 'last_line': n} when all code
    (other than directives and lines holding only a macro invocation, such as
    NS_ASSUME_NONNULL_BEGIN) is inside #if blocks with a common outer
    condition. The condition is not evaluated: whether the code is compiled
    depends on build settings that this tool does not read.
    """
    stack = []  # (condition text, line of the #if); '' for an include guard
    common = None
    first = last = None
    lines = masked.split('\n')
    for number, line in enumerate(lines, 1):
        m = _CONDITIONAL_DIRECTIVE.match(line)
        if m:
            kind, rest = m.group(1), ws(m.group(2))
            if kind == 'if':
                stack.append((rest, number))
            elif kind == 'ifdef':
                stack.append(('defined(%s)' % rest, number))
            elif kind == 'ifndef':
                following = next((l for l in lines[number:] if l.strip()), '')
                guard = re.match(r'^[ \t]*#[ \t]*define[ \t]+%s\b' % re.escape(rest), following)
                stack.append(('' if guard else '!defined(%s)' % rest, number))
            elif kind == 'elif' and stack:
                stack[-1] = ('%s (elif after %s)' % (rest, stack[-1][0]), number)
            elif kind == 'else' and stack:
                stack[-1] = ('not (%s)' % stack[-1][0], number)
            elif kind == 'endif' and stack:
                stack.pop()
            continue
        if not line.strip() or line.lstrip().startswith('#') or _LONE_MACRO_LINE.match(line):
            continue
        if first is None:
            first = number
        last = number
        here = [c for c, _ in stack if c]
        if common is None:
            common = here
        else:
            n = 0
            while n < len(common) and n < len(here) and common[n] == here[n]:
                n += 1
            common = common[:n]
        if not common:
            return None
    if not common:
        return None
    return OrderedDict([('condition', ' && '.join(common)), ('first_line', first), ('last_line', last)])


def rr_sites(masked):
    """(retain/release/autorelease message sends, [super dealloc] sends) in masked source."""
    if 'retain' not in masked and 'release' not in masked and 'dealloc' not in masked:
        return 0, 0
    sites = _RR_SITE.findall(masked)
    return len([x for x in sites if x]), len([x for x in sites if not x])


def parse_imports(raw, masked):
    """File names imported or included by a file, as written (outside comments)."""
    result = []
    for m in _IMPORT_DIRECTIVE.finditer(masked):
        end = raw.find('\n', m.start())
        line = raw[m.start():end if end >= 0 else len(raw)]
        pm = _IMPORT_PATH.search(line)
        if pm:
            result.append(pm.group(1).strip())
    return result


def objc_containers(masked):
    """Finds @interface / @implementation declarations (heuristic, regex)."""
    out = []
    line_index = None
    for m in _OBJC_CONTAINER.finditer(masked):
        if line_index is None:
            line_index = LineIndex(masked)
        kind, name, generics, category, superclass = (m.group(1), m.group(2), m.group(3),
                                                      m.group(4), m.group(5))
        protocols = m.group(7) or m.group(6) if superclass else (m.group(7) or m.group(6))
        swift_name = None
        before = masked[max(0, m.start() - 200):m.start()]
        sm = _NS_SWIFT_NAME_BEFORE.search(before)
        if sm:
            swift_name = sm.group(1)
        out.append({
            'kind': kind,
            'name': name,
            'category': category,  # None: primary; '': class extension; else category name
            'superclass': superclass if category is None else None,
            'generics': generics.strip('<> ') if generics else None,
            'protocols': [p.strip() for p in protocols.strip('<> ').split(',')] if protocols else [],
            'line': line_index.line(m.start()),
            'swift_name': swift_name,
        })
    return out


def parse_xib(text):
    """Objects and connections of a xib or storyboard (XML).

    Returns {'classes': {object id: customClass}, 'outlets': [(source id,
    property, destination id)], 'actions': [(target id, selector)],
    'bindings': [(destination id, keyPath)], 'runtime_attributes': [(object
    id, keyPath)]}. File's Owner has id -2 and First Responder id -1. Raises
    ValueError if the text is not well-formed XML.
    """
    try:
        root = ElementTree.fromstring(text.encode('utf-8'))
    except ElementTree.ParseError as e:
        raise ValueError(str(e))
    info = {'classes': {}, 'outlets': [], 'actions': [], 'bindings': [], 'runtime_attributes': []}
    for el in root.iter():
        oid = el.get('id')
        if el.get('customClass'):
            info['classes'][oid] = el.get('customClass')
        for child in el:
            if child.tag == 'connections':
                for c in child:
                    if c.tag in ('outlet', 'outletCollection'):
                        info['outlets'].append((oid, c.get('property'), c.get('destination')))
                    elif c.tag == 'action':
                        info['actions'].append((c.get('target'), c.get('selector')))
                    elif c.tag == 'binding':
                        info['bindings'].append((c.get('destination'), c.get('keyPath')))
            elif child.tag == 'userDefinedRuntimeAttributes':
                for c in child:
                    info['runtime_attributes'].append((oid, c.get('keyPath')))
    return info


def xib_references(info, ids):
    """Counts of the connections in a parsed xib that reach the objects with the given ids.

    outlets are set on the objects; incoming_outlets point at them from other
    objects (delegate and dataSource outlets, for example).
    """
    ids = set(ids)
    return OrderedDict([
        ('outlets', len([o for o in info['outlets'] if o[0] in ids])),
        ('incoming_outlets', len([o for o in info['outlets'] if o[2] in ids])),
        ('actions', len([a for a in info['actions'] if a[0] in ids])),
        ('bindings', len([b for b in info['bindings'] if b[0] in ids])),
        ('runtime_attributes', len([r for r in info['runtime_attributes'] if r[0] in ids])),
    ])


def _line_prefix(text, offset):
    return text[text.rfind('\n', 0, offset) + 1:offset]


_SWIFT_ATTRIBUTE_LINE = re.compile(r'^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]*)+$')


def _preceding_attribute_lines(text, offset):
    """Attribute-only lines (such as @objc(Name)) directly above a declaration."""
    out = []
    end = text.rfind('\n', 0, offset)
    while end > 0 and len(out) < 4:
        start = text.rfind('\n', 0, end) + 1
        line = text[start:end]
        if not _SWIFT_ATTRIBUTE_LINE.match(line):
            break
        out.append(line)
        end = start - 1
    return ' '.join(out)


def swift_declarations(masked):
    """Swift class and extension declarations (heuristic, regex)."""
    classes, extensions = [], []
    line_index = LineIndex(masked)
    for m in _SWIFT_CLASS_KEYWORD.finditer(masked):
        name = m.group(1)
        if name in _SWIFT_NOT_CLASS_NAMES:
            continue
        pm = _SWIFT_CLASS_PREFIX.match(_line_prefix(masked, m.start()))
        if not pm:
            continue
        brace = masked.find('{', m.end())
        if brace < 0:
            continue
        rest = masked[m.end():brace]
        if re.search(r'[;=]|\bfunc\b|\bvar\b', rest):
            continue
        rest = rest.strip()
        if rest.startswith('<'):
            rest = rest[find_matching(rest, 0, '<', '>') + 1:].strip()
        attrs = (pm.group(1) or '') + ' ' + _preceding_attribute_lines(masked, m.start())
        objc_name = None
        om = re.search(r'@objc\((\w+)\)', attrs)
        if om:
            objc_name = om.group(1)
        inherits = []
        if rest.startswith(':'):
            clause = re.split(r'\bwhere\b', rest[1:])[0]
            inherits = [re.sub(r'<.*', '', part, flags=re.S).strip().split('.')[-1]
                        for part in split_top_level(clause) if part.strip()]
        classes.append({'name': name, 'objc_name': objc_name,
                        'superclass': inherits[0] if inherits else None,
                        'inherits': inherits, 'line': line_index.line(m.start())})
    for m in _SWIFT_EXTENSION_KEYWORD.finditer(masked):
        if not _SWIFT_EXTENSION_PREFIX.match(_line_prefix(masked, m.start())):
            continue
        extensions.append({'name': m.group(1), 'line': line_index.line(m.start())})
    return classes, extensions


# ---------------------------------------------------------------------------
# Structural parse of one Objective-C file (used by the state table)

_AT_WORD = re.compile(r'@(\w+)')
# A line holding only a macro invocation, such as NS_ASSUME_NONNULL_BEGIN or
# DECLARE_SOMETHING(x): no semicolon follows, so its name would otherwise start
# the next declaration.
_BARE_MACRO_LINE = re.compile(r'[ \t\r\n]*([A-Z_][A-Z0-9_]*)(?:[ \t]*\((?:[^()\n]|\([^()\n]*\))*\))?[ \t]*\n')


def strip_leading_bare_macros(text):
    """Returns (offset, names): where the real declaration starts, and the macros skipped."""
    pos = 0
    names = []
    while True:
        m = _BARE_MACRO_LINE.match(text, pos)
        if not m:
            return pos, names
        names.append(m.group(1))
        pos = m.end()


_METHOD_LINE = re.compile(r'(?m)^[ \t]*[-+][ \t]*\(')
_SCOPE_DIRECTIVES = ('optional', 'required', 'public', 'private', 'protected', 'package')
_SEMI_DIRECTIVES = ('property', 'synthesize', 'dynamic', 'class', 'compatibility_alias')
_STATIC_PREFIX = re.compile(r'^\s*(?:(?:extern|const|volatile|__unused|__used|inline|__inline__)\s+)*'
                            r'(static|NS_INLINE|CF_INLINE|NS_INLINE_SWIFT)\b')
_TYPEBODY = re.compile(r'(?:\b(?:struct|union|enum)\b[^()]*$)|NS_(?:ENUM|OPTIONS|CLOSED_ENUM|ERROR_ENUM)\s*\([^)]*\)\s*$')
_C_KEYWORDS = {'if', 'while', 'for', 'switch', 'return', 'sizeof', 'do', 'else', 'case',
               '__attribute__', 'typeof', '__typeof__', 'NS_SWIFT_NAME', 'API_AVAILABLE'}


def method_selector(signature):
    """Selector of an Objective-C method from its signature text."""
    s = signature.strip()
    if s[:1] in '-+':
        s = s[1:]
    s = remove_balanced(s)
    tokens = re.findall(r'\w+|:', s.split(',')[0])
    if ':' not in tokens:
        m = re.search(r'\w+', s)
        return m.group(0) if m else ''
    # Pattern: keyword ':' param, repeated; a ':' with no word before it (other
    # than the previous parameter's name) is an unnamed keyword.
    parts = []
    i = 0
    expect_keyword = True
    while i < len(tokens):
        tok = tokens[i]
        if expect_keyword:
            if tok == ':':
                parts.append(':')
                expect_keyword = False
            elif i + 1 < len(tokens) and tokens[i + 1] == ':':
                parts.append(tok + ':')
                i += 1
                expect_keyword = False
            else:
                break
        else:
            if tok == ':':
                parts.append(':')
            else:
                expect_keyword = True
        i += 1
    return ''.join(parts)


def function_name(header):
    """Name of a C function from the text before its body, or None."""
    # Lightweight generics such as NSDictionary<NSString *, id (^)(void)> can hold
    # parentheses that are not the parameter list.
    h = remove_balanced(strip_attributes(header), '<', '>')
    depth = 0
    for i, ch in enumerate(h):
        if ch == '(':
            if depth == 0:
                inner = h[i + 1:].lstrip()
                if inner[:1] in ('*', '^'):
                    # A function returning a function pointer: void (*Name(int kind))(int).
                    fm = re.match(r'[*^]\s*(\w+)\s*\(', inner)
                    return fm.group(1) if fm and fm.group(1) not in _C_KEYWORDS else None
                m = re.search(r'(\w+)\s*$', h[:i])
                if not m or m.group(1) in _C_KEYWORDS:
                    return None
                return m.group(1)
            depth += 1
        elif ch == ')':
            depth -= 1
    return None


def _has_top_level(text, ch):
    depth = 0
    for c in text:
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ch and depth == 0:
            return True
    return False


_TRAILING_ANNOTATION = re.compile(
    r'\s+((?:NS|API|CF|OBJC|ITERM|AV|MTL|SWIFT)_[A-Z0-9_]+|__\w+|UNAVAILABLE_ATTRIBUTE|DEPRECATED_ATTRIBUTE)'
    r'\s*(\((?:[^()]|\([^()]*\))*\))?\s*$')


def parse_declarator(decl):
    """Splits one C declarator into (name, type, array, bitfield, kind).

    kind is 'block', 'function pointer' or None.
    """
    d = strip_attributes(decl).strip()
    bitfield = None
    bm = re.search(r'(?<!:):\s*(\d+|\w+)\s*$', d)
    if bm and '::' not in d[bm.start() - 1:bm.start() + 1]:
        bitfield = bm.group(1)
        d = d[:bm.start()].rstrip()
    pm = re.search(r'\(\s*([*^])\s*(?:\w+\s+)*?(\w+)\s*\)', d)
    if pm:
        kind = 'block' if pm.group(1) == '^' else 'function pointer'
        name = pm.group(2)
        typ = ws(d[:pm.start()] + '(' + pm.group(1) + ')' + d[pm.end():])
        return name, typ, None, bitfield, kind
    array = None
    am = re.search(r'((?:\[[^\]]*\]\s*)+)$', d)
    if am:
        array = ws(am.group(1))
        d = d[:am.start()].rstrip()
    # Trailing annotation macros after the name, such as NS_SWIFT_NAME(x) or
    # API_AVAILABLE(...). Only known prefixes are removed, and only when what
    # is left still ends in a plausible name, so that an all-caps variable
    # name such as SESSION_ARRANGEMENT_ROWS is kept.
    while True:
        tm = _TRAILING_ANNOTATION.search(d)
        if not tm:
            break
        rest = d[:tm.start()].rstrip()
        lm = re.search(r'(\w+)$', rest)
        if not lm or lm.group(1) in ('const', 'volatile', 'unsigned', 'signed') or \
                not re.search(r'[\w*]\s*[\s*]\s*\w+$', rest):
            break
        d = rest
    nm = re.search(r'(\w+)\s*$', d)
    if not nm:
        return None, ws(d), array, bitfield, None
    name = nm.group(1)
    typ = ws(d[:nm.start()])
    return name, typ, array, bitfield, None


def container_protocols(match):
    """The protocols an @interface or @implementation line lists, from the
    groups of _OBJC_CONTAINER that hold a protocol list: after the superclass,
    after the category, and after the name of a root class (no superclass and
    no category; elsewhere a list after the name holds lightweight generic
    parameters), in order (heuristic, by text). A list right after the
    superclass holds the superclass's type arguments, not protocols, when
    another list follows it, when an item is a pointer type, or when an item
    is one of the class's own generic parameters (Foo<T> : Bar<T>)."""
    def items(text):
        return [ws(p) for p in split_top_level(text.strip()[1:-1]) if p.strip()] if text else []
    out = []
    params = items(match.group(3))
    if match.group(4) is None and match.group(5) is None:
        out += params
    after_super = items(match.group(6))
    if not (match.group(7) or any('*' in p or p in params for p in after_super)):
        out += after_super
    out += items(match.group(7))
    return out


def parse_ivar_block(body):
    """Ivar declarations in the text between the braces of an ivar block."""
    text = re.sub(r'@(?:public|private|protected|package)\b', ' ', body)
    decls, depth, cur, start = [], 0, [], 0
    for i, ch in enumerate(text):
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
        if ch == ';' and depth == 0:
            decls.append((''.join(cur), start))
            cur = []
            start = i + 1
        else:
            cur.append(ch)
    out = []
    for decl, off in decls:
        if not decl.strip():
            continue
        lead = len(decl) - len(decl.lstrip())
        stripped = decl.strip()
        if '{' in stripped:
            close = find_matching(stripped, stripped.index('{'))
            base = ws(stripped[:close + 1])
            rest = stripped[close + 1:]
            for part in split_top_level(rest):
                name, typ, array, bitfield, kind = parse_declarator('int ' + part)
                if name:
                    t = base + ((' ' + typ[3:].strip()) if typ.startswith('int') and typ[3:].strip() else '')
                    out.append({'name': name, 'type': ws(t), 'array': array, 'bitfield': bitfield,
                                'kind': kind, 'offset': off + lead})
            continue
        parts = split_top_level(stripped)
        name, typ, array, bitfield, kind = parse_declarator(parts[0])
        if not name:
            continue
        out.append({'name': name, 'type': typ, 'array': array, 'bitfield': bitfield, 'kind': kind,
                    'offset': off + lead})
        base = typ.rstrip('* ').strip()
        for p in parts[1:]:
            stars = len(re.match(r'\s*(\**)', p).group(1))
            n2, _, array2, bit2, kind2 = parse_declarator(base + ' ' + p.strip())
            if n2:
                out.append({'name': n2, 'type': ws(base + ' ' + '*' * stars),
                            'array': array2, 'bitfield': bit2, 'kind': kind2, 'offset': off + lead})
    return out


def parse_property(text):
    """Parses '@property (attrs) type name' (without the semicolon)."""
    m = re.match(r'@property\s*(?:\(([^)]*)\))?\s*(.*)$', text.strip(), re.S)
    if not m:
        return None
    attrs = [a.strip() for a in (m.group(1) or '').split(',') if a.strip()]
    name, typ, _, _, _ = parse_declarator(m.group(2))
    if not name:
        return None
    getter = setter = None
    for a in attrs:
        gm = re.match(r'getter\s*=\s*(\w+)', a)
        if gm:
            getter = gm.group(1)
        sm = re.match(r'setter\s*=\s*([\w:]+)', a)
        if sm:
            setter = sm.group(1)
    return {'name': name, 'type': typ, 'attributes': attrs,
            'getter': getter or name,
            'setter': setter or ('set' + name[:1].upper() + name[1:] + ':'),
            'readonly': 'readonly' in attrs,
            'nonatomic': 'nonatomic' in attrs,
            'class_property': 'class' in attrs}


_NOT_A_DEFINITION = re.compile(r'^\s*(?:(?:extern|typedef|using|namespace|template|class|FOUNDATION_EXPORT|'
                               r'FOUNDATION_EXTERN|APPKIT_EXTERN|UIKIT_EXTERN|CF_EXPORT|OBJC_EXTERN)\b|@)')
_EXTERN_WORD = re.compile(r'^\s*(?:extern|FOUNDATION_EXPORT|FOUNDATION_EXTERN|APPKIT_EXTERN|CF_EXPORT|OBJC_EXTERN)\b')


class ObjCFile(object):
    """Structural parse of one Objective-C or C file (heuristic).

    The core uses the containers, methods, functions (to find C functions and
    method bodies) and globals. The ivars, properties, @synthesize and
    @dynamic lists, and statics are used by the state table and verify
    subcommands (inventory_state.py and inventory_verify.py); the core keeps
    them here so that both share one parse.
    """

    def __init__(self, path, raw):
        self.path = path
        self.raw = raw
        self.masked = mask_source(raw)
        self.code = strip_preprocessor(self.masked)
        self.lines = LineIndex(raw)
        self.containers = []
        self.methods = []
        self.functions = []
        self.statics = []
        self.globals = []
        self.properties = []
        self.synthesizes = []
        self.dynamics = []
        self.ivars = []
        self.warnings = []
        self._parse()
        self._self_check()

    def line(self, offset):
        return self.lines.line(offset)

    def _parse(self):
        code = self.code
        n = len(code)
        i = 0
        header_start = 0
        container = None
        while i < n:
            c = code[i]
            if c == '@':
                m = _AT_WORD.match(code, i)
                word = m.group(1) if m else ''
                if word in ('interface', 'implementation'):
                    cm = _OBJC_CONTAINER.match(code, i)
                    if cm:
                        container = {
                            'kind': cm.group(1), 'name': cm.group(2), 'category': cm.group(4),
                            'superclass': cm.group(5) if cm.group(4) is None else None,
                            'protocols': container_protocols(cm),
                            'start': i, 'end': None, 'line': self.line(i),
                        }
                        self.containers.append(container)
                        j = cm.end()
                        while j < n and code[j] in ' \t\r\n':
                            j += 1
                        if j < n and code[j] == '{':
                            close = self._match(j)
                            where = self._ivar_location(container)
                            for iv in parse_ivar_block(code[j + 1:close]):
                                iv['offset'] += j + 1
                                iv['line'] = self.line(iv['offset'])
                                iv['condition'] = self.condition_at(iv['line'])
                                iv['class'] = container['name']
                                iv['declared'] = where
                                iv['file'] = self.path
                                self.ivars.append(iv)
                            j = close + 1
                        i = j
                        header_start = i
                        continue
                elif word == 'protocol':
                    fm = re.match(r'@protocol\s+[\w\s,]+;', code[i:i + 400])
                    if fm:
                        i += fm.end()
                        header_start = i
                        continue
                    pm = re.match(r'@protocol\s+(\w+)\s*(<[^>]*>)?', code[i:])
                    if pm:
                        container = {'kind': 'protocol', 'name': pm.group(1), 'category': None,
                                     'superclass': None, 'start': i, 'end': None,
                                     'line': self.line(i)}
                        self.containers.append(container)
                        i += pm.end()
                        header_start = i
                        continue
                elif word == 'end':
                    if container is not None:
                        container['end'] = i
                    container = None
                    i = m.end()
                    header_start = i
                    continue
                elif word in _SCOPE_DIRECTIVES:
                    i = m.end()
                    header_start = i
                    continue
                elif word in _SEMI_DIRECTIVES:
                    semi = code.find(';', i)
                    if semi < 0:
                        semi = n
                    self._directive(word, code[i:semi], i, container)
                    i = semi + 1
                    header_start = i
                    continue
            elif c == '{':
                header = code[header_start:i]
                close = self._match(i)
                h = header.strip()
                if (container is not None and container['kind'] == 'implementation'
                        and not (h.startswith('-') or h.startswith('+'))):
                    # A bare macro (such as ITERM_WEAKLY_REFERENCEABLE) before a method
                    # leaves its name at the start of the header. Start at the method.
                    starts = list(_METHOD_LINE.finditer(header))
                    if starts:
                        lead = starts[-1].start()
                        self.warnings.append('%s:%d: text before a method was taken to be a macro: %s'
                                             % (self.path, self.line(header_start), ws(header[:lead])[:60]))
                        header_start += lead
                        header = header[lead:]
                        h = header.strip()
                if h.startswith('-') or h.startswith('+'):
                    if container is not None and container['kind'] == 'implementation':
                        self.methods.append({
                            'class': container['name'], 'category': container['category'],
                            'sign': h[0], 'selector': method_selector(h),
                            'start': header_start + (len(header) - len(header.lstrip())),
                            'body_start': i, 'body_end': close,
                            'line': self.line(header_start + (len(header) - len(header.lstrip()))),
                        })
                    i = close + 1
                    header_start = i
                    continue
                skip, _ = strip_leading_bare_macros(header)
                if skip:
                    header_start += skip
                    header = header[skip:]
                    h = header.strip()
                if _has_top_level(h, '=') or _TYPEBODY.search(h) or re.search(r'extern\s+""\s*$', h):
                    # Initializer or type body: the declaration continues to the next ';'.
                    i = close + 1
                    continue
                name = function_name(h)
                if name:
                    is_static = bool(_STATIC_PREFIX.match(h))
                    off = header_start + (len(header) - len(header.lstrip()))
                    self.functions.append({'name': name, 'static': is_static, 'start': off,
                                           'body_start': i, 'body_end': close,
                                           'line': self.line(off)})
                    if is_static:
                        self._add_static('function', name, h, off)
                i = close + 1
                header_start = i
                continue
            elif c == ';':
                skip, _ = strip_leading_bare_macros(code[header_start:i])
                header_start += skip
                decl = code[header_start:i]
                if decl.strip():
                    self._declaration(decl, header_start + (len(decl) - len(decl.lstrip())), container)
                header_start = i + 1
            i += 1
        for cont in self.containers:
            if cont['end'] is None:
                cont['end'] = n

    def condition_at(self, line):
        """The #if conditions in force at a line, joined with &&, or None (by text)."""
        if not hasattr(self, '_line_conditions'):
            conds = []
            stack = []
            for text in self.masked.split('\n'):
                m = re.match(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b[ \t]*(.*?)[ \t]*$', text)
                if m:
                    kind, rest = m.group(1), ws(m.group(2))
                    conds.append(list(stack))
                    if kind == 'if':
                        stack.append(rest)
                    elif kind == 'ifdef':
                        stack.append('defined(%s)' % rest)
                    elif kind == 'ifndef':
                        stack.append('!defined(%s)' % rest)
                    elif kind == 'elif' and stack:
                        stack[-1] = '%s (elif after %s)' % (rest, stack[-1])
                    elif kind == 'else' and stack:
                        stack[-1] = 'not (%s)' % stack[-1]
                    elif kind == 'endif' and stack:
                        stack.pop()
                    continue
                conds.append(list(stack))
            self._line_conditions = conds
        if 1 <= line <= len(self._line_conditions):
            stack = self._line_conditions[line - 1]
            return ' && '.join(stack) if stack else None
        return None

    def _match(self, open_index):
        close = find_matching(self.code, open_index)
        if self.code[close:close + 1] != '}':
            self.warnings.append('%s:%d: unmatched {; the rest of the file was not parsed'
                                 % (self.path, self.line(open_index)))
        return close

    def _self_check(self):
        """Counts method definitions by a cruder rule and warns if the parse found fewer.

        The crude rule: a line in an @implementation, outside any braces, that
        begins with - or + and a parenthesis, and reaches a { before a ;.
        """
        crude = 0
        depth = 0
        in_impl = False
        code = self.code
        static_lines = set()
        for m in re.finditer(r'(?m)^[ \t]*@implementation\b|^[ \t]*@end\b|[{}]|^[-+][ \t]*\(|^[ \t]*static\b',
                             code):
            tok = m.group(0)
            if tok.strip() == 'static':
                if depth == 0:
                    static_lines.add(self.line(m.start()))
                continue
            if tok == '{':
                depth += 1
            elif tok == '}':
                depth = max(0, depth - 1)
            elif tok.strip().startswith('@implementation'):
                in_impl = True
            elif tok.strip().startswith('@end'):
                in_impl = False
            elif in_impl and depth == 0:
                brace = code.find('{', m.end())
                semi = code.find(';', m.end())
                if brace >= 0 and (semi < 0 or brace < semi):
                    crude += 1
        self.crude_method_count = crude
        parsed_static_lines = set(l for st in self.statics for l in st['lines'])
        missing_statics = sorted(static_lines - parsed_static_lines)
        self.crude_static_lines = sorted(static_lines)
        if missing_statics:
            self.warnings.append('%s: file-scope static declarations at lines %s were not parsed; some statics '
                                 'are missing from this analysis'
                                 % (self.path, ', '.join(str(l) for l in missing_statics[:10])))
        if crude > len(self.methods):
            self.warnings.append('%s: a crude count finds %d method definitions but the parse found %d; '
                                 'some methods are missing from this analysis'
                                 % (self.path, crude, len(self.methods)))

    def _ivar_location(self, container):
        in_header = self.path.endswith('.h')
        if container['kind'] == 'implementation':
            return 'implementation block'
        if container['category'] == '':
            return 'class extension in a header' if in_header else 'class extension in the .m'
        return 'header @interface' if in_header else '@interface in the .m'

    def _directive(self, word, text, offset, container):
        if container is None:
            return
        if word == 'property':
            prop = parse_property(text)
            if prop:
                prop.update({'class': container['name'], 'category': container['category'],
                             'container_kind': container['kind'], 'line': self.line(offset),
                             'file': self.path})
                self.properties.append(prop)
        elif word in ('synthesize', 'dynamic'):
            body = text[len('@' + word):]
            for part in body.split(','):
                pm = re.match(r'\s*(\w+)\s*(?:=\s*(\w+))?\s*$', part)
                if not pm:
                    continue
                if word == 'synthesize':
                    self.synthesizes.append({'class': container['name'], 'property': pm.group(1),
                                             'ivar': pm.group(2) or pm.group(1),
                                             'line': self.line(offset)})
                else:
                    self.dynamics.append({'class': container['name'], 'property': pm.group(1)})

    def _declaration(self, decl, offset, container=None):
        if not _STATIC_PREFIX.match(decl):
            if container is None or container['kind'] == 'implementation':
                self._global_definition(decl, offset)
            return
        flat = strip_attributes(decl)
        # Collapse every brace group (initializers, struct bodies) to {}.
        flat_nobraces = flat
        while True:
            collapsed = re.sub(r'\{[^{}]*\}', '\x01', flat_nobraces)
            if collapsed == flat_nobraces:
                break
            flat_nobraces = collapsed
        flat_nobraces = flat_nobraces.replace('\x01', '{}')
        before_eq = flat_nobraces.split('=')[0]
        name = function_name(before_eq) if '(' in before_eq else None
        if name and not re.search(r'\(\s*[*^]', before_eq):
            self._add_static('function', name, decl, offset)
            return
        # Variable(s). Drop any struct/union/enum body so the declarators remain.
        text = re.sub(r'\b(struct|union|enum)\s*(\w+)?\s*\{\}', r'\1 \2', flat_nobraces)
        text = re.sub(r'^\s*(?:(?:extern|const|volatile|__unused|__used)\s+)*static\b', '', text).strip()
        parts = split_top_level(text)
        first = parts[0].split('=')[0]
        name, typ, array, bitfield, kind = parse_declarator(first)
        if not name:
            return
        self._add_static('variable', name, decl, offset, type_=typ, array=array)
        base = typ.rstrip('* ').strip()
        for p in parts[1:]:
            n2, t2, a2, _, _ = parse_declarator(base + ' ' + p.split('=')[0].strip())
            if n2:
                self._add_static('variable', n2, decl, offset, type_=t2, array=a2)

    def _global_definition(self, decl, offset):
        """Records a file-scope variable defined without static (it has external linkage), by text.

        Declarations (extern and the like), typedefs, type definitions with no
        variable, and C++ using/namespace/template lines are not definitions and
        are skipped. A function prototype ends in its parameter list, so no
        variable name is found in it.
        """
        flat = strip_attributes(decl)
        while True:
            collapsed = re.sub(r'\{[^{}]*\}', '\x01', flat)
            if collapsed == flat:
                break
            flat = collapsed
        flat = flat.replace('\x01', '{}')
        has_initializer = '=' in flat
        if _NOT_A_DEFINITION.match(flat) and not (has_initializer and _EXTERN_WORD.match(flat)):
            return
        text = re.sub(r'\b(struct|union|enum)\s*(\w+)?\s*\{\}', r'\1 \2', flat).strip()
        text = re.sub(r'^\s*(?:(?:extern|const|volatile|__unused|__used|FOUNDATION_EXPORT|FOUNDATION_EXTERN)\s+)*',
                      '', text)
        parts = split_top_level(text)
        name, typ, _, _, _ = parse_declarator(parts[0].split('=')[0])
        if not name or not typ or typ in ('struct', 'union', 'enum') or re.match(r'^(?:struct|union|enum)\s+\w+$',
                                                                                 ws(text)):
            return
        self.globals.append({'name': name, 'line': self.line(offset)})
        base = typ.rstrip('* ').strip()
        for part in parts[1:]:
            other, _, _, _, _ = parse_declarator(base + ' ' + part.split('=')[0].strip())
            if other:
                self.globals.append({'name': other, 'line': self.line(offset)})

    def _add_static(self, kind, name, decl, offset, type_=None, array=None):
        for s in self.statics:
            if s['name'] == name and s['kind'] == kind:
                s['lines'].append(self.line(offset))
                return
        self.statics.append({'kind': kind, 'name': name, 'line': self.line(offset),
                             'lines': [self.line(offset)], 'type': type_, 'array': array,
                             'declaration': ws(decl)[:160]})

    # Bodies -------------------------------------------------------------

    def bodies(self):
        """(label, kind, start, end) for every method and function body."""
        out = []
        for m in self.methods:
            cat = '(%s)' % m['category'] if m['category'] else ''
            label = '%s[%s%s %s]' % (m['sign'], m['class'], cat, m['selector'])
            out.append((label, 'method', m['body_start'], m['body_end']))
        for f in self.functions:
            out.append((f['name'] + '()', 'function', f['body_start'], f['body_end']))
        out.sort(key=lambda t: t[2])
        return out


# ---------------------------------------------------------------------------
# Class names of system frameworks (foundation categories)

SYSTEM_CLASS_PREFIXES = ('NS', 'CA', 'MTL', 'WK', 'AV', 'CI', 'CN', 'GC', 'MTK', 'LA', 'UN', 'SF',
                         'CL', 'QL', 'IK', 'PDF', 'CK', 'OS', 'SC', 'DD', 'UT', 'AS', 'SK', 'CS',
                         'ASWeb', 'NE', 'NW', 'UI', 'VN', 'SB', 'MP', 'CX', 'PK', 'JS', 'XPC')


def _is_system_class(name):
    return any(name.startswith(p) and len(name) > len(p) and name[len(p)].isupper()
               for p in SYSTEM_CLASS_PREFIXES)


# ---------------------------------------------------------------------------
# Git history

# What git log reads: every commit reachable from HEAD whose message could hold a
# Swift-Port trailer or something that looks like one (the grep is
# case-insensitive and unanchored), with git's own reading of the message's
# Swift-Port trailers. git decides what a trailer is: only the final paragraph,
# and only when git takes that paragraph to be a trailer block.
HISTORY_SCOPE = 'commits reachable from HEAD'
GIT_LOG_TRAILER_ARGS = ['log', 'HEAD', '-i', '-E', '--grep=swift.{0,4}port',
                        '--format=%H%x1f%cs%x1f%B%x1f%(trailers:key=Swift-Port,unfold,separator=%x1d)%x1e']
_TRAILER_VALUE = re.compile(r'^(\S+)\s+kind=(\S+)$')
_CANONICAL_TRAILER = re.compile(r'^Swift-Port: \S+ kind=\S+$')
# Anything that looks like an attempt at the trailer: Swift-Porting:, X-Swift-Port:,
# swift port:, Swift_Port:, a dash other than U+002D, a space before the colon.
_TRAILER_NEAR_MISS = re.compile(r'(?i)swift[\W_]{0,3}port\w*\s*:')
TRAILER_NOT_READ = 'not counted: git does not read this line as a Swift-Port trailer'
TRAILER_NOT_CANONICAL = 'counted, but not written exactly as Swift-Port: <unit> kind=<kind>'
TRAILER_REPEATED = 'repeated in the same commit; counted once'


def parse_trailers(log_text):
    """Parses the output of git log with GIT_LOG_TRAILER_ARGS.

    A trailer counts when git reports it as a Swift-Port trailer, its value is
    <unit> kind=<kind> with a kind from README.md section 5, and it is the first
    such trailer for that unit and kind in its commit. Returns (units,
    problems): units maps unit name to {'kinds': {kind: count}, 'first_date',
    'last_date', 'commits': [hash...]}; problems lists malformed trailers,
    unknown kinds, trailers written in a form other than the canonical one, and
    lines that look like a trailer but that git does not read as one. Output
    that cannot be split into records is an error, not an empty result.
    """
    units = OrderedDict()
    problems = []
    for record in log_text.split('\x1e'):
        record = record.strip('\n')
        if not record.strip():
            continue
        fields = record.split('\x1f')
        if len(fields) != 4:
            raise InventoryError('cannot parse git log output: a record has %d fields, not 4: %r'
                                 % (len(fields), record[:120]))
        commit, date, body, trailer_text = fields[0].strip(), fields[1].strip(), fields[2], fields[3]
        trailers = []
        for t in trailer_text.split('\x1d'):
            key, sep, value = t.strip('\n').partition(':')
            if sep:
                trailers.append((key.strip(), value.strip()))
        # The message line each trailer came from, matched from the end of the message.
        lines = body.rstrip('\n').split('\n')
        line_of = []
        used = set()
        for key, value in trailers:
            found = None
            for i in range(len(lines) - 1, -1, -1):
                # A folded trailer continues on lines that begin with white space.
                j = i + 1
                while j < len(lines) and lines[j][:1] in (' ', '\t') and lines[j].strip():
                    j += 1
                k, sep, v = ' '.join(l.strip() for l in lines[i:j]).partition(':')
                if i not in used and sep and v.strip() == value and k.strip() == key:
                    found = i
                    used.update(range(i, j))
                    break
            line_of.append(found)
        for i, line in enumerate(lines):
            if i not in used and _TRAILER_NEAR_MISS.search(line):
                problems.append({'commit': commit, 'problem': TRAILER_NOT_READ, 'line': line.strip()})
        seen = set()
        for (key, value), index in zip(trailers, line_of):
            written = lines[index].strip() if index is not None and lines[index].strip().endswith(value) \
                else '%s: %s' % (key, value)
            m = _TRAILER_VALUE.match(value)
            if not m:
                problems.append({'commit': commit, 'problem': 'malformed trailer (not counted)', 'line': written})
                continue
            unit, kind = m.group(1), m.group(2)
            if kind not in KNOWN_KINDS:
                problems.append({'commit': commit, 'problem': 'unknown kind %s (not counted)' % kind,
                                 'line': written})
                continue
            if index is None or not _CANONICAL_TRAILER.match(lines[index]):
                problems.append({'commit': commit, 'problem': TRAILER_NOT_CANONICAL, 'line': written})
            if (unit, kind) in seen:
                problems.append({'commit': commit, 'problem': TRAILER_REPEATED, 'line': written})
                continue
            seen.add((unit, kind))
            u = units.setdefault(unit, {'kinds': OrderedDict(), 'first_date': date,
                                        'last_date': date, 'commits': []})
            u['kinds'][kind] = u['kinds'].get(kind, 0) + 1
            if date > u['last_date']:
                u['last_date'] = date
            if date < u['first_date']:
                u['first_date'] = date
            if commit not in u['commits']:
                u['commits'].append(commit)
    return units, problems


# ---------------------------------------------------------------------------
# Reliability of each reported field

EXACT = 'exact'
HEURISTIC = 'heuristic'

RELIABILITY = OrderedDict([
    # File records (files, file, and the rows of leaf).
    ('path', (EXACT, 'tracked by git, filtered by the scope rules')),
    ('lines', (EXACT, 'newline count, as wc -l, plus one for a last line with no newline')),
    ('targets', (HEURISTIC, 'from project.pbxproj; an entry with included_via is inherited from a file whose '
                            '#include of this one was found by text')),
    ('arc', (HEURISTIC, 'from targets: CLANG_ENABLE_OBJC_ARC per configuration and per-file compiler flags; '
                        'inherited for #included files, as for targets')),
    ('included_by', (HEURISTIC, '#include or #import of the .m file name, outside comments')),
    ('rr_sites', (HEURISTIC, 'retain, release and autorelease message sends found by text outside comments and '
                             'strings; includes code under #if 0')),
    ('super_dealloc_sites', (HEURISTIC, 'text matches of [super dealloc]')),
    ('fan_in', (HEURISTIC, 'in-scope files whose #import / #include names the header file, plus every in-scope '
                           'file of a target whose prefix header (GCC_PREFIX_HEADER) imports it, directly or through '
                           'other in-scope headers (conditions in the prefix header are not evaluated); importers '
                           'outside scope are not counted')),
    ('reach', (HEURISTIC, 'in-scope files that import the header, directly, through other in-scope headers, or '
                          'through a prefix header; it includes the direct importers')),
    ('classes', (HEURISTIC, '@implementation lines outside comments')),
    ('categories_implemented', (HEURISTIC, '@implementation Class (Category) lines outside comments')),
    ('relations', (HEURISTIC, '@interface / @implementation and Swift class / extension declarations in every '
                              'tracked file outside submodules/')),
    ('objc_subclass_count', (HEURISTIC, 'direct Objective-C subclasses anywhere in the repository outside '
                                        'submodules/, see relations')),
    ('objc_subclasses_outside_scope', (HEURISTIC, 'see objc_subclass_count')),
    ('swift_subclass_count', (HEURISTIC, 'direct Swift subclasses, see relations')),
    ('swift_extension_count', (HEURISTIC, 'Swift extension blocks in scope, see relations')),
    ('external_category_count', (HEURISTIC, 'categories on the class outside its own .m and .h')),
    ('external_categories_outside_scope', (HEURISTIC, 'see external_category_count')),
    ('categories_implemented_elsewhere', (HEURISTIC, '@implementation Class (Category) of a class implemented here, '
                                                     'in any other file found by relations')),
    ('categories_declared_only', (HEURISTIC, '@interface Class (Category) in another file with no @implementation '
                                             'of that category found anywhere')),
    ('categories_declared_only_outside_scope', (HEURISTIC, 'see categories_declared_only')),
    ('c_symbols_in_headers', (HEURISTIC, 'non-static C functions and file-scope variables defined in the file whose '
                                         'name appears, by text, in an in-scope header or on an extern line of any '
                                         'other tracked Objective-C, C or header file; macros are not expanded')),
    ('class_extensions_elsewhere', (HEURISTIC, 'class extensions (@interface Class ()) of its classes in other files')),
    ('hazards', (HEURISTIC, 'a mention of an API in code (comments and strings excluded), not proof that '
                            'anything is reached; an absent hazard means only that the text search found nothing. '
                            'Text hazards are searched for in the implementation file itself (.m, .mm or .c); '
                            'Swift files and headers are not searched for them')),
    ('hazard_lines', (HEURISTIC, 'the lines of the file where each text hazard was matched, as for hazards')),
    ('hazard_wrappers', (HEURISTIC, 'methods and functions in scope found by text to dispatch a block parameter '
                                    '(see Inventory._discover_wrappers), whose calls count as a block dispatched to '
                                    'a queue, with the number of passes the search took and its bound')),
    ('stored_state', (HEURISTIC, 'every stored-state match in the file by the four rules (see STORED_STATE_DIRECT and '
                                 'STORED_STATE_API in inventory.py): its line, the text matched, the rule, the entry of '
                                 'that rule that produced it and what that entry is; found by text')),
    ('stored_state_first', (HEURISTIC, 'the first stored-state match in the file (line, text, rule, entry), the reason '
                                       'leaf prints for deferring it; see stored_state')),
    ('dispatch_wrapper_calls', (HEURISTIC, 'calls to block-dispatching wrappers in the file, each with the wrapper and '
                                           'where it is defined; found by name, see hazard_wrappers')),
    ('atomic_properties', (HEURISTIC, 'properties declared without nonatomic in the file and its header, by text, '
                                      'each with its file and line')),
    ('macro_hits', (HEURISTIC, '#define bodies classified by text')),
    ('wholly_conditional', (HEURISTIC, '#if blocks found by text; the condition is reported, never evaluated')),
    ('parse_problems', (HEURISTIC, 'consistency checks of the text parse; an empty list means these checks passed, '
                                   'not that the parse is complete')),
    ('objcxx', (HEURISTIC, 'C++ constructs found by text; incidental versus essential is a guess from the '
                           'directory')),
    ('hot_path_dir', (HEURISTIC, 'by directory only')),
    ('migration_state', (HEURISTIC, 'language is exact; ARC as for arc; partially_ported means a Swift extension '
                                    'of the class exists in scope')),
    ('foundation_categories', (HEURISTIC, 'categories on classes with a system prefix (NS, CA, ...)')),
    ('nscoding', (HEURISTIC, 'NSCoding or NSSecureCoding in an @interface, or coder methods, by text')),
    ('xib', (HEURISTIC, 'customClass attributes of xib and storyboard XML, by text for files that do not parse')),
    ('xib_connections', (HEURISTIC, 'outlets, actions, bindings and runtime attributes from the XML, for objects '
                                    'of the class and for the File\'s Owner of nibs the file names by a string '
                                    'literal or that are named after one of its classes; references is null where '
                                    'the XML did not parse')),
    ('first_responder_actions', (HEURISTIC, 'xib actions whose target is First Responder, matched to the '
                                            'selectors of methods parsed from the file')),
    ('sdef', (HEURISTIC, 'cocoa class names in iTerm2.sdef, by text')),
    ('sdef_methods', (HEURISTIC, 'cocoa method selectors in iTerm2.sdef matched to parsed methods')),
    ('sdef_keys', (HEURISTIC, 'cocoa keys in iTerm2.sdef matched to parsed accessors of scripting classes')),
    ('control_flow_macros', (HEURISTIC, 'function-like macros in scope whose body contains return, break, '
                                        'continue or goto, invoked in the file, by text')),
    ('ownership_attributes', (HEURISTIC, 'ownership and method-family attributes, and macros whose body applies '
                                         'one, in the file and its header, by text')),
    ('ownership_transferring_methods', (HEURISTIC, 'methods parsed from the file whose selector is in the new, copy, '
                                                   'mutableCopy or alloc family, each with its line')),
    ('imported_outside_scope', (HEURISTIC, 'Objective-C files outside scope whose #import names the header')),
    ('created_by_name', (HEURISTIC, 'NSClassFromString, objc_getClass and objc_lookUpClass calls in every tracked '
                                    'Objective-C and Swift file outside submodules/ and tools/swift_migration/: a literal '
                                    'name, or the isSubclassOfClass:, conformsToProtocol: and '
                                    'instancesRespondToSelector: checks after the call in the same body; calls '
                                    'with neither are listed as unresolved by leaf')),
    ('methods_named_by_convention', (HEURISTIC, 'parsed selectors matching key-value coding, scripting, '
                                                'observing and validation naming patterns')),
    ('method_check', (HEURISTIC, 'methods found by the parser against a cruder count')),
    ('deferral', (HEURISTIC, 'the leaf deferral rules applied to the heuristic fields above')),
    # history.
    ('history', (HEURISTIC, 'units and counts are Swift-Port trailers in commits reachable from HEAD, as git reads '
                            'them; the trailer problems listed with them include near misses found by a text '
                            'pattern')),
    ('scope', (EXACT, 'which commits were read (history), or the scope rules (summary)')),
    ('units', (EXACT, 'Swift-Port trailers as git reads them, in commits reachable from HEAD')),
    ('problems', (HEURISTIC, 'malformed values and unknown kinds are exact; lines that look like a trailer are '
                             'found by a text pattern; with a unit, only problems whose line names that unit '
                             '(the first word after the colon)')),
    ('problems_elsewhere', (HEURISTIC, 'with a unit, the trailer problems that name another unit; 0 without one')),
    # summary.
    ('root', (EXACT, 'git rev-parse --show-toplevel')),
    ('relations_computed_over', (HEURISTIC, 'files that declare a related class, found by text')),
    ('projects_searched', (EXACT, 'the Xcode projects read for targets: %s and every project.pbxproj tracked by git '
                                  'under a scope directory' % PBXPROJ)),
    ('by_scope_root', (HEURISTIC, 'files, lines and exclusions per scope directory; lines are exact, and the test, '
                                  'demo and tool exclusions follow targets')),
    ('implementation_files', (EXACT, 'tracked .m, .mm and .c files in scope')),
    ('implementation_lines', (EXACT, 'newline count')),
    ('by_extension', (EXACT, 'files and lines per extension')),
    ('header_files', (EXACT, 'tracked .h files in scope')),
    ('header_lines', (EXACT, 'newline count')),
    ('objc_c_cxx_lines_total', (EXACT, 'implementation and header lines')),
    ('swift_files', (EXACT, 'tracked .swift files in scope')),
    ('files_in_non_arc_target', (HEURISTIC, 'from targets')),
    ('files_in_non_arc_target_with_rr_sites', (HEURISTIC, 'from targets and rr_sites')),
    ('objc_files_compiled_without_arc', (HEURISTIC, 'from targets')),
    ('rr_sites_total', (HEURISTIC, 'see rr_sites')),
    ('super_dealloc_sites_total', (HEURISTIC, 'see super_dealloc_sites')),
    ('not_compiled_by_any_target', (HEURISTIC, 'from targets')),
    ('textually_included_implementation_files', (HEURISTIC, 'see included_by')),
    ('fan_in_le_2', (HEURISTIC, 'see fan_in')),
    ('fan_in_le_2_not_counting_bridging_header', (HEURISTIC, 'see fan_in')),
    ('fan_in_gt_50', (HEURISTIC, 'see fan_in')),
    ('reach_le_2', (HEURISTIC, 'see reach')),
    ('classes_implemented_in_scope', (HEURISTIC, 'see classes')),
    ('classes_with_objc_subclasses', (HEURISTIC, 'see relations')),
    ('classes_with_objc_subclasses_outside_scope', (HEURISTIC, 'see relations')),
    ('classes_with_swift_subclasses', (HEURISTIC, 'see relations')),
    ('classes_with_swift_extensions', (HEURISTIC, 'see relations')),
    ('files_with_incomplete_parse', (HEURISTIC, 'see parse_problems')),
    ('progress', (HEURISTIC, 'lines are exact; marker counts are git grep counts of the literal text; '
                             'files compiled without ARC follow targets; null_unspecified, strict-warnings imports, '
                             'ivar_ accessor shapes and wholly conditional files are found by text; helper calls '
                             'are found by text with comments and strings masked')),
    # files and leaf.
    ('total', (EXACT, 'rows before --limit')),
    ('shown', (EXACT, 'rows after --limit')),
    ('files', (HEURISTIC, 'file records; see their fields')),
    ('thresholds', (EXACT, 'the limits given')),
    ('candidates_total', (HEURISTIC, 'offered files, from the heuristic fields')),
    ('candidates_shown', (EXACT, 'offered files shown after --limit')),
    ('candidates', (HEURISTIC, 'files that no deferral rule applies to, by the heuristic fields above; offered '
                               'for a dossier, not decided')),
    ('header_importers', (HEURISTIC, 'see fan_in')),
    ('has_header', (HEURISTIC, 'a header with the same stem, or a unique header of that name')),
    ('prefix_header', (HEURISTIC, 'the prefix headers through which the header is imported, and their targets; '
                                  'see fan_in')),
    ('swift_subclasses', (HEURISTIC, 'see swift_subclass_count')),
    ('address', (HEURISTIC, 'the hazards and flags this tool detects in the file by its text searches, not '
                            'everything the dossier must cover; an empty list means the text searches '
                            'found nothing')),
    ('deferred_files', (HEURISTIC, 'files of the leaf tier that a deferral rule applies to')),
    ('deferred', (HEURISTIC, 'the deferral rules applied to the heuristic fields')),
    ('outside_thresholds', (HEURISTIC, 'from fan_in and reach')),
    ('not_established', (HEURISTIC, 'class-name calls whose reach was not found and calls that dispatch or build '
                                    'a selector that is not a literal, both searched in every tracked Objective-C '
                                    'and Swift file outside submodules/ and tools/swift_migration/ (only the '
                                    'Objective-C forms counted and the Swift forms counted that selector_site_forms '
                                    'lists, so the count is not complete beyond them); xib files that did not parse; '
                                    'tracked files missing from the working tree that this tool would read, in scope '
                                    'or not, xib and storyboard files included; and the fixed limits of the '
                                    'text search; all found by text')),
    ('not_checked', (EXACT, 'a fixed statement of what this tool does not check')),
])

_RECORD_FIELDS = ['path', 'lines', 'targets', 'arc', 'included_by', 'rr_sites', 'super_dealloc_sites', 'fan_in',
                  'reach', 'classes', 'categories_implemented', 'foundation_categories', 'hazards', 'macro_hits',
                  'wholly_conditional', 'parse_problems', 'objcxx', 'hot_path_dir', 'migration_state',
                  'objc_subclass_count', 'objc_subclasses_outside_scope', 'swift_subclass_count',
                  'swift_extension_count', 'external_category_count', 'external_categories_outside_scope',
                  'categories_implemented_elsewhere', 'categories_declared_only',
                  'categories_declared_only_outside_scope', 'c_symbols_in_headers', 'class_extensions_elsewhere',
                  'stored_state_first']
MODE_FIELDS = OrderedDict([
    ('summary', ['root', 'scope', 'projects_searched', 'by_scope_root', 'relations_computed_over',
                 'implementation_files', 'implementation_lines',
                 'by_extension', 'header_files', 'header_lines', 'objc_c_cxx_lines_total', 'swift_files',
                 'targets', 'files_in_non_arc_target', 'files_in_non_arc_target_with_rr_sites',
                 'objc_files_compiled_without_arc', 'rr_sites_total', 'super_dealloc_sites_total',
                 'not_compiled_by_any_target', 'textually_included_implementation_files', 'fan_in_le_2',
                 'fan_in_le_2_not_counting_bridging_header', 'fan_in_gt_50', 'reach_le_2',
                 'classes_implemented_in_scope', 'classes_with_objc_subclasses',
                 'classes_with_objc_subclasses_outside_scope', 'classes_with_swift_subclasses',
                 'classes_with_swift_extensions', 'objcxx', 'files_with_incomplete_parse', 'progress', 'history',
                 'hazard_wrappers', 'not_established']),
    ('files', ['total', 'shown', 'files', 'not_established'] + _RECORD_FIELDS),
    ('file', _RECORD_FIELDS + ['hazard_lines', 'stored_state', 'dispatch_wrapper_calls', 'atomic_properties', 'relations', 'nscoding', 'xib', 'sdef', 'sdef_methods', 'sdef_keys',
                               'ownership_attributes', 'ownership_transferring_methods', 'control_flow_macros', 'imported_outside_scope', 'created_by_name',
                               'xib_connections', 'methods_named_by_convention', 'first_responder_actions',
                               'method_check', 'deferral', 'history', 'not_established', 'not_checked']),
    ('history', ['scope', 'units', 'problems', 'problems_elsewhere']),
    ('leaf', ['thresholds', 'candidates_total', 'candidates_shown', 'candidates', 'deferred_files', 'deferred',
              'outside_thresholds', 'by_scope_root', 'not_established', 'not_checked', 'path', 'targets', 'fan_in', 'header_importers', 'reach',
              'has_header', 'prefix_header', 'lines', 'arc', 'rr_sites', 'swift_subclasses', 'hazards', 'address']),
])


# Fields whose reliability differs in one subcommand's output.
MODE_RELIABILITY = {
    ('leaf', 'by_scope_root'): (HEURISTIC, 'offered, deferred and outside-the-tier files per scope directory, from '
                                           'the heuristic fields'),
    ('file', 'history'): (EXACT, 'Swift-Port trailers in commits reachable from HEAD, as git reads them, for units '
                                 'named after the file or its classes'),
}


def _reliability(mode, field):
    return MODE_RELIABILITY.get((mode, field), RELIABILITY[field])


def reliability_for(mode):
    return OrderedDict((f, OrderedDict([('reliability', _reliability(mode, f)[0]), ('why', _reliability(mode, f)[1])]))
                       for f in MODE_FIELDS[mode])


def reliability_help(mode):
    fields = MODE_FIELDS[mode]
    exact = [f for f in fields if _reliability(mode, f)[0] == EXACT]
    heur = [f for f in fields if _reliability(mode, f)[0] == HEURISTIC]
    return ('Exact fields: %s. Heuristic fields (text matching on comment- and string-stripped source, no '
            'preprocessor; see inventory.py --help): %s.' % (', '.join(exact) or 'none', ', '.join(heur) or 'none'))


# ---------------------------------------------------------------------------
# The inventory

# The lists of leaf-tier files that are not offered: name -> (reason, where the process says so).
DEFERRED_LISTS = OrderedDict([
    ('wholly conditional', ('every line of code is under a preprocessor condition, which this tool does not evaluate; '
                            'the code may not be compiled at all', 'hidden-callers.md section 6, item 8')),
    ('parse incomplete', ('the text parse of the file is incomplete, so the hazards found in it are not established',
                          'phase0.md section 1 (this inventory)')),
    ('reserved (reserved.md)', ('under a path prefix in docs/swift-migration/reserved.md, whose files are not ported '
                                'on any path until the owner ends the reservation',
                                'reserved.md; lifecycle.md section 3')),
    ('probable hot path', ('in a hot-path directory: hot paths are ported last, with the owner',
                           'performance.md section 2; plan.md section 1, step 7; workflow.md section 3')),
    ('giant classes', ('implements part of PTYSession, PseudoTerminal, PTYTab or PTYTextView, which are emptied by '
                       'extraction and never ported as files', 'large-code.md section 1')),
    ('must stay in Objective-C for now', ('proxies and forwarding, swizzling and method replacement, method-list '
                                          'enumeration and other reflective runtime use, @try, +load and +initialize',
                                          'hidden-callers.md sections 2 and 5; translation-rules.md sections 3 and 5; '
                                          'lifecycle.md section 2; concurrency.md section 5')),
    ('stays in C: atomics', ('uses C atomics, which Swift cannot use; atomics stay in C behind inline wrappers. '
                             'Heuristic: any match of the atomics search defers the file, whether or not atomics are '
                             'its purpose', 'concurrency.md section 4')),
    ('defines C functions or globals declared in a header', (
        'Objective-C cannot call a Swift free function or see a Swift-only constant or global, so a file that '
        'defines C functions or globals other files can use is not offered. Heuristic: a non-static function or '
        'file-scope variable defined here whose name appears in any in-scope header, found by text',
        'interop.md')),
    ('encodes or decodes stored state', (
        'units that encode or decode stored state are blocked until the stored-state corpus exists. Heuristic: any '
        'match of the four stored-state rules (direct API use; a use of iTerm2\'s named stored-state API; a typed '
        'keyed setter with a preference key constant, or sent to self in a subclass of a stored-state class; a '
        'subclass of a class on the named list); the first match is shown, and file NAME lists every match with its '
        'rule', 'stored-state.md; owner-queue.md Q7')),
    ("needs the owner's permission", ('associated objects are ported only with the owner\'s permission',
                                      'hidden-callers.md section 5; CLAUDE.md')),
    ('needs a design decision first', ('a macro that defines methods or classes, or pastes tokens into names, is a '
                                       'design decision made with the owner', 'hidden-callers.md section 6')),
    ('class named by a macro', ('a class here is named or declared by a macro, so the text does not show it',
                                'hidden-callers.md section 6')),
    ('classes with Objective-C subclasses', ('Objective-C cannot subclass a Swift class', 'interop.md')),
    ('categories implemented in other files', ('a class becomes eligible when its categories are done: an '
                                               'Objective-C category on it is implemented in another file, in '
                                               'scope or outside it (a category only declared does not defer)',
                                               'interop.md; orchestration.md section 2')),
    ('foundation categories', ('categories on system classes belong to the widely imported foundations',
                               'plan.md section 1, step 5')),
    ('built into other executables', ('another target compiles it (a target other than %s, in any project); '
                                      'porting it brings Swift into that target' % ' and '.join(MAIN_TARGETS),
                                      'no process rule yet; for the owner')),
    ('not compiled', ('no target of any project found compiles it (the projects searched are %s and every Xcode '
                      'project tracked under a scope directory), so a port could not be built or tested'
                      % os.path.dirname(PBXPROJ), 'no process rule yet; for the owner')),
    ('included by another file', ('it is compiled as part of the file that #includes it',
                                  'no process rule yet; for the owner')),
])


# What this tool does not check, printed by leaf and file every time. The census is the
# entry-point census of phase0.md section 2; this inventory does not try to be it.
NOT_CHECKED = (
    'Which methods or classes can be reached by name from other files is not determined here: selector strings, '
    'tables of selector names, the app\'s Info.plist entries (such as service handlers and the principal class) '
    'and reflective sites. That is the job of the entry-point census (phase0.md section 2).',
    'Whether the file is on a hot path outside the hot-path directories (performance.md section 2).',
    'hot-paths.md: whether the unit is already deferred there as a hot path.',
    'claims.md: whether the unit is already claimed, in progress or parked.',
    'Whether anything the file depends on is still soaking (workflow.md section 5).',
    'Blocks recorded in owner-queue.md are not checked, except that leaf defers the files in which the stored-state '
    'rules below find stored state (owner-queue.md Q7: units that encode or decode stored state are blocked until the '
    'stored-state corpus exists).',
    'C functions and globals defined or declared through macros (including names made by token pasting) are not '
    'seen by the C-symbol rule; a file that invokes a function-defining macro is flagged instead.',
    'Whether another object file references a file\'s C symbols: the authoritative check is nm on the built object '
    'files, which this tool does not run.',
    'Stored state is found by four rules, and file NAME gives the line, the text, the rule and the entry of every '
    'match: (1) direct API use: keyed archivers and coders, keyed coding, NSCoding, restorable-state methods, '
    'arrangements, property-list serialization, dictionaryWithContentsOfFile:, dictionaryWithContentsOfURL:, '
    'arrayWithContentsOfFile:, arrayWithContentsOfURL:, and writeToFile: or writeToURL: without an encoding: '
    'keyword, CFPreferences, writes to a receiver '
    'that is user defaults by its text, Core Data and SQLite; (2) a use of a class or helper on the named list of '
    'iTerm2\'s stored-state API (STORED_STATE_API in inventory.py, each entry with what it persists; '
    'iTermAdvancedSettingsModel counts only for setters, because reading an advanced setting gets a value the model '
    'has already decoded, and the two settings pane base classes count only through rules 3 and 4, because naming '
    'a pane stores nothing); (3) a typed keyed setter (setBool:, setInt:, setInteger:, setUnsignedInteger:, setFloat:, '
    'setDouble:, setString: or setObject: with forKey:) whose key is a KEY_ or k...Preference... constant, or such a '
    'setter or setObjectsFromDictionary: sent to self, super, weakSelf or strongSelf in a class whose superclass '
    'chain in scope reaches a listed class or a class that has such a setter with a constant key; (4) a class whose '
    'superclass chain in scope reaches a listed class. Nothing else is followed: a call to a method that stores '
    'state is not itself a match.',
    'Not detected: stored state reached through project methods and classes not on the named list, dictionaries '
    'built here and saved by another file (profile dictionaries built with KEY_ constants in literals or subscripts, '
    'status bar knob and trigger parameter dictionaries), writes through a variable the text does not tie to user '
    'defaults, key paths bound in xibs, and generic file and JSON I/O (stringWithContentsOf..., '
    'dataWithContentsOf..., initWithContentsOf..., createFileAtPath:contents:, NSFileHandle, fopen, '
    'NSJSONSerialization, and strings written with an encoding). Every dossier lists the unit\'s stored-state '
    'surfaces by reading '
    '(lifecycle.md section 1, step 2).',
    'Calls to block-dispatching wrappers are found by name only: a wrapper whose name is shorter than 8 characters, '
    'is shared with an in-scope method that does not dispatch its block, or is one of the common Cocoa block '
    'keywords completionHandler, completionBlock, usingBlock, withBlock, withReply, replyHandler, errorHandler, '
    'resultHandler and performBlock is not used, and a call through a block, a function pointer, a protocol the text '
    'cannot follow or a Swift method is not seen.',
    'Calls to methods and functions that wrap a lock, semaphore, atomic operation, @synchronized, forwarding, '
    'key-value observing, timer or class-from-name API are detected only for the wrappers named here: anything '
    'named for swizzling (swizzl), the associated-object wrappers (names containing AssociatedObject or '
    'AssociatedDictionary, and attachMetadata:toTexture: and metadataForTexture:), iTermUserDefaultsObserver, and '
    'iTerm2\'s concurrency classes and functions (iTermThread, iTermSynchronizedState, iTermMainThreadState, '
    'iTermCallback, iTermThreadChecker, iTermTaskQueue, iTermGCD, iTermMutationQueue, '
    'iTermLegacyAtomicMutableArrayOfWeakObjects, iTermPreciseTimersLock and the iTermAtomic functions). A call to '
    'any other wrapper, such as the iTermPreciseTimer functions, which use atomics, is not detected.',
    'Methods in the init family are not flagged as ownership-transferring, although hidden-callers.md section 6 '
    'lists init with alloc, new, copy and mutableCopy: nearly every class has initializers, so the flag would be on '
    'every file, and a Swift initializer exposed to Objective-C keeps the init family\'s convention. An init method '
    'that returns an object other than self, or that is not an initializer, is found by reading.',
)

# The forms of selector site that _dynamic_selector_sites counts, per language, stated with every count.
SELECTOR_SITE_FORMS = OrderedDict([
    ('Objective-C', 'NSSelectorFromString, sel_registerName and sel_getUid with an argument that is not a string '
                    'literal; a message keyword in the perform...Selector family or ending in Selector or selector '
                    '(other than respondsToSelector:, instancesRespondToSelector:, NSStringFromSelector and '
                    'doesNotRecognizeSelector:), sendAction:, tryToPerform:, targetForAction:, setAction: or '
                    'setDoubleAction:, whose argument is not an @selector literal or nil; objc_msgSend and its variants '
                    'without an @selector literal or SEL among their arguments; calls to the selector-taking methods '
                    'and functions found in scope without an @selector literal; and an assignment to .action or '
                    '.doubleAction that is not an @selector literal or nil'),
    ('Swift', 'Selector(...) and NSSelectorFromString(...) with an argument that is not a string literal; perform( '
              'with or without a receiver, sendAction( and tryToPerform( whose first argument is a name, a member '
              'access, Selector(...) or NSSelectorFromString(...); target(forAction:, selector: and action: whose '
              'argument is not a #selector literal, a string literal, nil, a capitalized name, a closure, an '
              'array or an enum case, outside a #selector literal and outside the parameters of a func, '
              'init, subscript or enum case declaration; and an assignment to .action or .doubleAction that is not a #selector literal, nil or an '
              'enum case'),
])

# Limits of the text search, stated with every "Not established" section, in text and JSON.
NOT_ESTABLISHED_FIXED = (
    'Hot paths are found by directory only; per-character, per-cell, per-token or per-frame code elsewhere is not '
    'detected.',
    'Preprocessor conditions are not evaluated, and callers that build a selector or class name from pieces at run '
    'time are not found by text (hidden-callers.md).',
)


class InventoryError(Exception):
    """A failure that must stop the run with a non-zero exit."""


def find_repo_root(start):
    if not os.path.isdir(start):
        raise InventoryError('%s is not a directory' % start)
    proc = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=start,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise InventoryError('%s is not inside a git repository: %s'
                             % (start, proc.stderr.decode('utf-8', 'replace').strip()))
    return proc.stdout.decode('utf-8').strip()


def git_or_fail(root, args, ok=(0,)):
    proc = subprocess.run(['git'] + list(args), cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode not in ok:
        raise InventoryError('git %s failed (exit %d): %s' % (
            ' '.join(args[:3]), proc.returncode, proc.stderr.decode('utf-8', 'replace').strip()))
    return proc.stdout.decode('utf-8', 'replace')


_REL_OBJC = re.compile(r'@interface\s+(\w+)\s*(?:<[^>{;]*>)?\s*(?::\s*(\w+)|\()|@implementation\s+(\w+)\s*\(')
_REL_SWIFT = re.compile(r'\bclass\s+(\w+)[^{\n]*?:\s*([\w.]+)|\bextension\s+([\w.]+)')


def trailer_problem_unit(problem):
    """The unit a trailer problem names: the first word after the colon of its line, or None."""
    _, sep, value = problem['line'].partition(':')
    words = value.split()
    return words[0] if sep and words else None


def history_from_git(root):
    log = git_or_fail(root, GIT_LOG_TRAILER_ARGS)
    return parse_trailers(log)


class Inventory(object):
    def __init__(self, root='.'):
        self.root = find_repo_root(os.path.abspath(root))
        self.warnings = []
        self.missing_files = []
        self._texts = {}
        self._masked = {}
        self._objc_files = {}
        self._reach = {}
        self._header_words = None
        self._externs = None
        self._identifiers = {}
        self._direct_dispatch = {}
        self._stored = {}
        self._reserved = None
        self._build()

    # Files ----------------------------------------------------------------

    def path(self, rel):
        return os.path.join(self.root, rel)

    def text(self, rel):
        if rel not in self._texts:
            try:
                with open(self.path(rel), 'rb') as f:
                    data = f.read()
            except OSError as e:
                raise InventoryError('cannot read %s: %s' % (rel, e))
            try:
                text = data.decode('utf-8')
            except UnicodeDecodeError:
                text = data.decode('utf-8', 'replace')
                self.warnings.append('%s is not valid UTF-8; undecodable bytes were replaced' % rel)
            self._texts[rel] = text
        return self._texts[rel]

    def masked(self, rel):
        if rel not in self._masked:
            self._masked[rel] = mask_source(self.text(rel), swift=rel.endswith(SWIFT_EXT))
        return self._masked[rel]

    def objc_file(self, rel):
        if rel not in self._objc_files:
            of = ObjCFile(rel, self.text(rel))
            self._objc_files[rel] = of
        return self._objc_files[rel]

    def _tracked(self):
        """In-scope paths and the exclusion counts. Also sets excluded_files (path -> reason, for gitlinks and for the
        files with a counted extension) and project_files (every project.pbxproj under a scope directory)."""
        out = git_or_fail(self.root, ['ls-files', '-s', '-z', '--'] + list(SCOPE_ROOTS))
        paths, excluded = [], defaultdict(int)
        self.excluded_files = OrderedDict()
        self.project_files = []
        counted = IMPL_EXTS + (HEADER_EXT, SWIFT_EXT)
        for entry in out.split('\0'):
            if not entry:
                continue
            meta, _, path = entry.partition('\t')
            if meta.split(' ')[0] == '160000':
                excluded['submodule'] += 1
                self.excluded_files[path] = 'submodule'
                continue
            reason = exclusion_reason(path)
            if path.endswith('.xcodeproj/' + PROJECT_FILE) and reason is None:
                self.project_files.append(path)
            if reason:
                if path.endswith(counted):
                    excluded[reason] += 1
                    self.excluded_files[path] = reason
                continue
            if not os.path.isfile(self.path(path)):
                excluded['missing from working tree'] += 1
                if path.endswith(counted):
                    self.missing_files.append(path)
                    self.excluded_files[path] = 'missing from working tree'
                continue
            paths.append(path)
        self.project_files.sort()
        return sorted(paths), dict(excluded)

    def _read_projects(self):
        """Reads PBXPROJ and every other project in project_files.

        Sets projects (the .xcodeproj directories searched, PBXPROJ's first), membership (path -> entries from every
        project), main_membership (PBXPROJ's alone), targets (name -> summary, with project, project_file and
        category added) and synchronized (project -> synchronized folders). Any project that is missing or cannot be
        parsed is fatal: every ARC answer depends on it.
        """
        self.projects, self.targets, self.synchronized = [], OrderedDict(), OrderedDict()
        self.membership = defaultdict(list)
        main_project = os.path.dirname(PBXPROJ)

        def read_file(path):
            full = self.path(path)
            return self.text(path) if os.path.isfile(full) else None
        for pbx in [PBXPROJ] + [p for p in self.project_files if p != PBXPROJ]:
            project = os.path.dirname(pbx)
            if not os.path.isfile(self.path(pbx)):
                raise InventoryError('%s not found' % pbx)
            try:
                membership, targets, synchronized = compute_target_membership(
                    parse_pbxproj(self.text(pbx)), project_dir=os.path.dirname(project), read_file=read_file)
            except (ValueError, KeyError, IndexError, TypeError, AttributeError) as e:
                raise InventoryError('cannot parse %s: %s' % (pbx, e))

            def label(name):
                return name if pbx == PBXPROJ else '%s:%s' % (project, name)
            for name, t in targets.items():
                t['project'] = project
                t['project_file'] = pbx
                t['category'] = target_category(t['product_type'], pbx == PBXPROJ)
                if label(name) in self.targets:
                    raise InventoryError('two targets are both named %s (%s)' % (label(name), pbx))
                self.targets[label(name)] = t
            for path, entries in membership.items():
                for e in entries:
                    e['target'] = label(e['target'])
                self.membership[path].extend(entries)
            if pbx == PBXPROJ:
                self.main_membership = membership
            self.projects.append(project)
            self.synchronized[project] = synchronized
        assert self.projects[0] == main_project

    def projects_text(self):
        return ', '.join(self.projects)

    def _separate_non_product(self, paths):
        """Takes test, demo and tool code (NON_PRODUCT_CATEGORIES) out of the in-scope paths, into non_product, and
        counts it in excluded and excluded_files. Returns the remaining paths."""
        self.non_product = OrderedDict()

        def record(path, category, targets):
            label = NON_PRODUCT_CATEGORIES[category][0]
            self.non_product[path] = OrderedDict([('category', category), ('reason', label),
                                                  ('targets', sorted(set(targets))),
                                                  ('lines', count_lines(self.text(path)))])
        for p in paths:
            if p.endswith(IMPL_EXTS + (SWIFT_EXT,)):
                entries = self.membership.get(p, [])
                category = self.non_product_category([e['target'] for e in entries])
                if category:
                    record(p, category, [e['target'] for e in entries])
        for p in paths:
            if not p.endswith(HEADER_EXT):
                continue
            stem = os.path.splitext(p)[0]
            beside = [stem + ext for ext in IMPL_EXTS if stem + ext in self.non_product]
            using = [name for name, t in self.targets.items() if p in t['bridging_headers']]
            if beside:
                record(p, self.non_product[beside[0]]['category'], self.non_product[beside[0]]['targets'])
            elif using and self.non_product_category(using):
                record(p, self.non_product_category(using), using)
        for p, r in sorted(self.non_product.items()):
            self.excluded[r['reason']] = self.excluded.get(r['reason'], 0) + 1
            self.excluded_files[p] = r['reason']
        self.non_product = OrderedDict(sorted(self.non_product.items()))
        return [p for p in paths if p not in self.non_product]

    def non_product_category(self, target_names):
        """The category of NON_PRODUCT_CATEGORIES that these targets put a file in, or None when there are none or one
        of them is treated as building the app or a helper program (a 'product' target). Targets of more than one
        category give the first, in the order test, demo, tool."""
        categories = set(self.targets[t]['category'] for t in target_names)
        if not categories or 'product' in categories:
            return None
        return [c for c in NON_PRODUCT_CATEGORIES if c in categories][0]

    def _relation_candidates(self):
        """Tracked Objective-C and Swift files outside scope (not submodules): outside the scope directories, or test,
        demo and tool code inside them. Those missing from the working tree are added to missing_files."""
        out = git_or_fail(self.root, ['ls-files', '-s', '-z', '--', '*.h', '*.m', '*.mm', '*.swift'])
        result = []
        for entry in out.split('\0'):
            if not entry:
                continue
            meta, _, path = entry.partition('\t')
            if meta.split(' ')[0] == '160000' or path.startswith(TOOL_DIR_PREFIX) or not (
                    exclusion_reason(path) == OUTSIDE_SCOPE or path in self.non_product):
                continue
            if os.path.isfile(self.path(path)):
                result.append(path)
            else:
                self.missing_files.append(path)
        return result

    def _build(self):
        paths, self.excluded = self._tracked()
        # Xcode projects. Any failure here is fatal: every ARC answer depends on them.
        self._read_projects()
        paths = self._separate_non_product(paths)
        self.impl_files = [p for p in paths if p.endswith(IMPL_EXTS)]
        self.headers = [p for p in paths if p.endswith(HEADER_EXT)]
        self.swift_files = [p for p in paths if p.endswith(SWIFT_EXT)]
        self.objc_sources = self.impl_files + self.headers
        self.in_scope = set(paths)
        if not self.impl_files:
            raise InventoryError('no in-scope implementation files found under %s in %s'
                                 % (scope_roots_text(), self.root))
        for name, t in self.targets.items():
            if t['xcconfig_unread']:
                self.warnings.append('target %s: %s; its ARC setting may be wrong' % (name, '; '.join(t['xcconfig_unread'])))
            if t['unresolved']:
                self.warnings.append('target %s: %d source entries in the project could not be resolved to a path'
                                     % (name, t['unresolved']))
        if BRIDGING_HEADER not in self.in_scope:
            raise InventoryError('%s not found; fan-in reports whether it imports each header, and without it the '
                             'tree is not laid out as this tool expects' % BRIDGING_HEADER)
        if not any(p in self.main_membership for p in self.impl_files):
            raise InventoryError('%s compiles none of the in-scope implementation files; '
                                 'the project or the scope is wrong' % PBXPROJ)
        for project, synchronized in self.synchronized.items():
            for sp in synchronized:
                if sp is not None and exclusion_reason(sp + '/x.m') is None:
                    self.warnings.append('%s: synchronized folder %s covers in-scope files; its members are not '
                                         'listed in the project and their targets are not known'
                                         % (os.path.join(project, PROJECT_FILE), sp))

        # Headers and imports (in scope only).
        self.header_by_basename = defaultdict(list)
        for h in self.headers:
            self.header_by_basename[os.path.basename(h)].append(h)
        self._hset = set(self.headers)
        self.importers = defaultdict(set)
        self.imports_of = {}
        for p in self.objc_sources:
            names = parse_imports(self.text(p), self.masked(p))
            self.imports_of[p] = names
            for name in names:
                self.importers[os.path.basename(name)].add(p)
        self._build_prefix_headers()

        # Declarations. In-scope files first, then every other tracked file that
        # declares a subclass, category or extension of a class already known.
        self.interfaces = defaultdict(list)
        self.implementations = defaultdict(list)
        self.protocol_files = defaultdict(set)
        self.swift_name_of = {}
        self.swift_classes = {}
        self.swift_subclasses = defaultdict(list)
        self.swift_extensions = defaultdict(list)
        # Object-like macros (#define NAME Value), to recognize a class named by a macro.
        self.object_macros = defaultdict(list)
        object_macro = re.compile(r'^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)[ \t]+([A-Za-z_]\w*)[ \t]*$', re.M)
        for p in self.objc_sources:
            if '#define' in self.masked(p):
                for m in object_macro.finditer(self.masked(p)):
                    self.object_macros[m.group(1)].append((p, m.group(2)))
        self.macro_class_aliases = {}   # (file, macro) -> [class names]
        self.macro_class_files = set()  # files with a container named by a macro, and their includers
        for p in self.objc_sources:
            self._add_objc_declarations(p)
        for p in self.swift_files:
            self._add_swift_declarations(p)
        self._outside_files = self._relation_candidates()
        self.relation_files_outside_scope = self._add_outside_declarations()

        self.superclass = {}
        for name, decls in self.interfaces.items():
            for d in sorted(decls, key=lambda d: not d['in_scope']):
                if d['category'] is None and d['superclass']:
                    self.superclass.setdefault(name, d['superclass'])
        self.objc_subclasses = defaultdict(list)
        for name, sup in self.superclass.items():
            self.objc_subclasses[sup].append(name)
        self.primary_impl_file = {}
        self.classes_in_file = defaultdict(list)
        self.categories_in_file = defaultdict(list)
        for name, decls in self.implementations.items():
            for d in decls:
                if not d['in_scope']:
                    continue
                if d['category'] is None:
                    self.primary_impl_file.setdefault(name, d['file'])
                    if name not in self.classes_in_file[d['file']]:
                        self.classes_in_file[d['file']].append(name)
                else:
                    self.categories_in_file[d['file']].append((name, d['category']))

        # xib and storyboard files: custom classes and connections.
        self.xib_classes = defaultdict(set)
        self.xibs = OrderedDict()           # path -> parse_xib result
        self.xibs_unparsed = []
        self.xib_by_name = defaultdict(list)
        self.first_responder_actions = defaultdict(set)   # selector -> xibs
        self.unparsed_xib_words = OrderedDict()   # path -> every identifier in the text of a xib that did not parse
        for x in git_or_fail(self.root, ['ls-files', '-z', '--', '*.xib', '*.storyboard']).split('\0'):
            if not x or exclusion_reason(x) == 'submodule' or x.startswith(TOOL_DIR_PREFIX):
                continue
            if not os.path.isfile(self.path(x)):
                self.missing_files.append(x)
                continue
            self.xib_by_name[os.path.splitext(os.path.basename(x))[0]].append(x)
            try:
                info = parse_xib(self.text(x))
            except ValueError as e:
                self.xibs_unparsed.append(x)
                self.unparsed_xib_words[x] = set(re.findall(r'[A-Za-z_]\w*', self.text(x)))
                self.warnings.append('%s is not well-formed XML (%s); only its customClass names were read, by text, '
                                     'and its outlets, actions, bindings and runtime attributes are not checked; '
                                     'every class whose name appears in its text is flagged' % (x, e))
                for m in re.finditer(r'<\w+\b[^>]*?\bcustomClass="([^"]+)"[^>]*>', self.text(x)):
                    self.xib_classes[m.group(1)].add(x)
                continue
            self.xibs[x] = info
            for cls in info['classes'].values():
                self.xib_classes[cls].add(x)
            for target, selector in info['actions']:
                if target == '-1' and selector:
                    self.first_responder_actions[selector].add(x)
        self.missing_files.sort()
        # iTerm2.sdef. Without it every scripting class would look free of AppleScript ties, so a
        # missing or unparsable file is fatal.
        if not os.path.isfile(self.path(SDEF_FILE)):
            raise InventoryError('%s not found; AppleScript classes, commands and keys could not be checked'
                                 % SDEF_FILE)
        try:
            sdef_root = ElementTree.fromstring(self.text(SDEF_FILE).encode('utf-8'))
        except ElementTree.ParseError as e:
            raise InventoryError('%s is not well-formed XML (%s); AppleScript classes, commands and keys could '
                                 'not be checked' % (SDEF_FILE, e))
        self.sdef_classes, self.sdef_methods, self.sdef_keys = set(), set(), set()
        for el in sdef_root.iter('cocoa'):
            for attr, found in (('class', self.sdef_classes), ('method', self.sdef_methods),
                                ('key', self.sdef_keys)):
                if el.get(attr):
                    found.add(el.get(attr))
        if not self.sdef_classes:
            raise InventoryError('%s names no classes (no <cocoa class="..."> element); AppleScript classes, commands '
                                 'and keys could not be checked' % SDEF_FILE)

        # Macros that define methods, for flagging their users.
        class_macros = {}
        self.method_macros = {}
        self.macros_by_file = {}
        for p in self.objc_sources:
            masked = self.masked(p)
            if '#define' not in masked and '# define' not in masked:
                continue
            macros = [m for m in parse_macros(masked)
                      if m['token_pasting'] or m['defines_method'] or m['declares_static'] or m['defines_class']]
            if macros:
                self.macros_by_file[p] = macros
            for m in macros:
                if m['defines_method']:
                    self.method_macros[m['name']] = p
                if m['defines_class']:
                    class_macros[m['name']] = p
        # Macros whose expansion applies an ownership or method-family attribute, and
        # function-like macros whose expansion returns, breaks, continues or jumps.
        self.ownership_macros = {}
        self.control_flow_macros = {}
        self.function_macros = {}
        self.stringifying_macros = {}
        for p in self.objc_sources:
            masked = self.masked(p)
            if '#define' in masked or '# define' in masked:
                for m in _DEFINE.finditer(masked):
                    if _OWNERSHIP_ATTRIBUTE.search(m.group(3) or ''):
                        self.ownership_macros[m.group(1)] = p
                    if m.group(2) is not None and re.search(r'\b(?:return|break|continue|goto)\b', m.group(3) or ''):
                        self.control_flow_macros[m.group(1)] = p
            for m in (parse_macros(masked) if '#define' in masked or '# define' in masked else []):
                if m['function_like'] and m['defines_function']:
                    self.function_macros[m['name']] = p
                if m['function_like'] and m['stringifies']:
                    self.stringifying_macros[m['name']] = p
        # Objective-C files outside scope (tests and other targets) that import in-scope headers.
        self.importers_outside_scope = defaultdict(set)
        for p in self._outside_files:
            if p.endswith(('.m', '.mm', '.h')):
                raw = self.text(p)
                if '#import' in raw or '#include' in raw:
                    for name in parse_imports(raw, self.masked(p)):
                        self.importers_outside_scope[os.path.basename(name)].add(p)
        self.hazard_wrappers = self._discover_wrappers()
        self._find_constant_key_setters()
        self.class_name_sites, self.unresolved_class_sites = self._class_name_sites()
        self.dynamic_selector_sites = self._dynamic_selector_sites()
        self.created_by_name = self._classes_created_by_name()

        # A file invoking a macro that declares or defines a class has classes the
        # text does not show; it is never a leaf candidate.
        for p in self.objc_sources:
            code = strip_preprocessor(self.masked(p))
            for name, where in sorted(class_macros.items()):
                if name in code:
                    for m in re.finditer(r'\b%s\s*\(\s*(\w*)' % re.escape(name), code):
                        self.macro_class_files.add(p)
                        self.warnings.append('%s:%d: %s(%s) declares or defines a class through a macro (from %s); '
                                             'that class is missing from every result'
                                             % (p, LineIndex(code).line(m.start()), name, m.group(1), where))

    def _resolve_import(self, importer, name):
        """In-scope headers an #import of name in importer can mean: the path next to it, else every
        in-scope header with that file name."""
        beside = os.path.normpath(os.path.join(os.path.dirname(importer), name))
        if beside in self._hset:
            return [beside]
        return list(self.header_by_basename.get(os.path.basename(name), []))

    def _build_prefix_headers(self):
        """Reads each target's prefix header and what it imports.

        Every in-scope header that a prefix header imports, directly or through
        other in-scope headers, is treated as imported by every in-scope
        Objective-C or C file the target compiles. Conditions in the prefix
        header (#ifdef __OBJC__) are not evaluated, so a C file counts too.
        A prefix header that cannot be read is fatal: without it fan-in would
        be too low.
        """
        self.prefix_closure = OrderedDict()      # prefix header -> sorted in-scope headers
        self.prefix_importers = defaultdict(set)  # header -> files importing it through a prefix header
        self.prefix_via = defaultdict(set)        # header -> set of (prefix header, target)
        for target, t in self.targets.items():
            for pch in t.get('prefix_headers', []):
                if pch not in self.prefix_closure:
                    if '$' in pch or not os.path.isfile(self.path(pch)):
                        raise InventoryError('cannot read the prefix header %s of target %s (GCC_PREFIX_HEADER in '
                                             '%s); the headers it imports would be missing from fan-in'
                                             % (pch, target, t['project_file']))
                    closure, todo = set(), [(pch, n) for n in parse_imports(self.text(pch), self.masked(pch))]
                    while todo:
                        importer, name = todo.pop()
                        for h in self._resolve_import(importer, name):
                            if h not in closure:
                                closure.add(h)
                                todo.extend((h, n) for n in self.imports_of.get(h, []))
                    self.prefix_closure[pch] = sorted(closure)
                compiled = set(p for p in self.impl_files
                               if any(e['target'] == target for e in self.membership.get(p, [])))
                for h in self.prefix_closure[pch]:
                    self.prefix_importers[h] |= compiled
                    self.prefix_via[h].add((pch, target))

    def _add_objc_declarations(self, p):
        masked = self.masked(p)
        if '@interface' not in masked and '@implementation' not in masked and '@protocol' not in masked:
            return
        in_scope = p in self.in_scope
        # Declarations inside #define bodies are not classes (DECLARE_TEST(t) and the like).
        for d0 in objc_containers(strip_preprocessor(masked)):
            if in_scope and d0['name'] in self.object_macros:
                names = self._resolve_macro_class(p, d0['name'])
                self.macro_class_files.add(p)
                self.macro_class_files.update(self.included_by(p))
                if names:
                    self.macro_class_aliases[(p, d0['name'])] = names
                    self.warnings.append('%s:%d: @%s %s names a macro; resolved by text to %s. Treat the results for '
                                         'these classes with care.' % (p, d0['line'], d0['kind'], d0['name'],
                                                                      ', '.join(names)))
                else:
                    self.warnings.append('%s:%d: @%s %s names a macro that could not be resolved by text; its '
                                         'class is missing from every result' % (p, d0['line'], d0['kind'],
                                                                                 d0['name']))
                expanded = [dict(d0, name=n, macro=d0['name']) for n in names]
            else:
                expanded = [d0]
            for d in expanded:
                self._add_container(d, p, in_scope)
        for m in _OBJC_PROTOCOL_DEF.finditer(masked):
            self.protocol_files[m.group(1)].add(p)

    def _resolve_macro_class(self, p, macro):
        """Values a macro has where p is #included (or in p itself), by reading #define lines."""
        values = []
        base = os.path.basename(p)
        define = re.compile(r'^[ \t]*#[ \t]*define[ \t]+%s[ \t]+(\w+)[ \t]*$' % re.escape(macro))
        undef = re.compile(r'^[ \t]*#[ \t]*undef[ \t]+%s\b' % re.escape(macro))
        for inc in self.included_by(p) or [p]:
            current = None
            raw_lines = self.text(inc).split('\n')
            for index, line in enumerate(self.masked(inc).split('\n')):
                dm = define.match(line)
                if dm:
                    current = dm.group(1)
                    if inc == p and current not in values:
                        values.append(current)
                elif undef.match(line):
                    current = None
                elif inc != p and current and _IMPORT_DIRECTIVE.match(line):
                    im = _IMPORT_PATH.search(raw_lines[index])
                    if im and os.path.basename(im.group(1)) == base and current not in values:
                        values.append(current)
        return values


    def _add_container(self, d, p, in_scope):
        d['file'] = p
        d['in_scope'] = in_scope
        if d['kind'] == 'interface':
            self.interfaces[d['name']].append(d)
            if d['swift_name'] and in_scope:
                self.swift_name_of[d['name']] = d['swift_name']
        else:
            self.implementations[d['name']].append(d)


    def classes_named(self, f, name):
        """Classes a container name in f stands for (a macro may stand for several)."""
        return self.macro_class_aliases.get((f, name), [name])

    def _add_swift_declarations(self, p):
        masked = self.masked(p)
        if 'class' not in masked and 'extension' not in masked:
            return
        in_scope = p in self.in_scope
        classes, extensions = swift_declarations(masked)
        for c in classes:
            c['file'] = p
            c['in_scope'] = in_scope
            if in_scope or c['name'] not in self.swift_classes:
                self.swift_classes.setdefault(c['name'], c)
            if c['superclass']:
                self.swift_subclasses[c['superclass']].append(c)
        for e in extensions:
            e['file'] = p
            e['in_scope'] = in_scope
            self.swift_extensions[e['name']].append(e)

    def _add_outside_declarations(self):
        """Adds declarations from tracked files outside scope that relate to known classes.

        A cheap scan of the raw text finds candidate files; only those are
        parsed. The scan repeats so that a test subclass of a test subclass is
        found too.
        """
        # Classes defined in scope (a primary @interface or @implementation, or
        # a Swift class), not classes that scope merely extends, such as NSObject.
        known = set(n for n, ds in self.interfaces.items() if any(d['category'] is None for d in ds)) | \
            set(n for n, ds in self.implementations.items() if any(d['category'] is None for d in ds)) | \
            set(self.swift_classes) | set(self.swift_name_of.values())
        refs = {}
        for p in self._outside_files:
            raw = self.text(p)
            names = set()
            if p.endswith(SWIFT_EXT):
                if 'class' in raw or 'extension' in raw:
                    for m in _REL_SWIFT.finditer(raw):
                        names.add((m.group(2) or m.group(3) or '').split('.')[-1])
            elif '@interface' in raw or '@implementation' in raw:
                for m in _REL_OBJC.finditer(raw):
                    # The superclass of @interface X : Y, else the class of a category.
                    names.add(m.group(2) or m.group(1) or m.group(3))
            names.discard('')
            if names:
                refs[p] = names
        used = []
        changed = True
        while changed:
            changed = False
            for p in sorted(refs):
                if refs[p] & known:
                    del refs[p]
                    used.append(p)
                    changed = True
                    if p.endswith(SWIFT_EXT):
                        self._add_swift_declarations(p)
                        known |= set(c['name'] for c in swift_declarations(self.masked(p))[0]
                                     if c['superclass'] in known)
                    else:
                        self._add_objc_declarations(p)
                        known |= set(d['name'] for d in objc_containers(self.masked(p))
                                     if d['category'] is None and d['superclass'] in known)
        return sorted(used)

    # Wrappers of hazards ------------------------------------------------------

    # A method name shorter than this is not used to find calls to a wrapper: short names such as run, then or
    # handler are also Cocoa keywords, and every caller of those would be flagged.
    WRAPPER_MIN_NAME = 8
    WRAPPER_MAX_PASSES = 60

    def _discover_wrappers(self):
        """Finds the in-scope methods and functions that dispatch a block parameter.

        A method or function with a block-typed parameter whose body
        dispatches a block (dispatch_sites) is a block-dispatching wrapper. A
        call to a wrapper is a dispatch in turn, so the search repeats until no
        wrapper is added, at most WRAPPER_MAX_PASSES times. A method keyword
        that carries a block parameter is used to find calls only when it is at
        least WRAPPER_MIN_NAME characters long, is not in
        BLOCK_KEYWORDS_NEVER_WRAPPERS, and every in-scope method with that
        keyword dispatches the block it carries, so a keyword shared with an
        ordinary method is never used. A function name is used when no in-scope
        function of that name is static or does not dispatch; a static function
        is called only from its own file, which already has the match. Also
        records each file's direct dispatch sites. Returns a DispatchWrappers.
        """
        entries = []
        bodies = {}   # path -> (sorted body starts, entries in the same order)
        # Implementation files only: a function in a header is almost always static inline, which is not
        # used (see above), and headers implement no methods.
        for p in self.impl_files:
            masked = self.masked(p)
            self._direct_dispatch[p] = dispatch_sites(masked)
            if '{' not in masked or '^' not in masked and 'Block' not in masked and 'block_t' not in masked:
                continue
            of = self.objc_file(p)
            mine = []
            for m in of.methods:
                cat = '(%s)' % m['category'] if m['category'] else ''
                mine.append({'kind': 'method', 'keywords': [k for k in m['selector'].split(':') if k],
                             'label': '%s[%s%s %s]' % (m['sign'], m['class'], cat, m['selector']),
                             'blocks': set(block_parameter_keywords(of.code[m['start']:m['body_start']])),
                             'start': m['body_start'], 'end': m['body_end'], 'static': False,
                             'where': '%s:%d' % (p, m['line'])})
            for f in of.functions:
                mine.append({'kind': 'function', 'name': f['name'], 'keywords': [], 'label': f['name'] + '()',
                             'blocks': has_block_parameter(of.code[f['start']:f['body_start']]),
                             'start': f['body_start'], 'end': f['body_end'], 'static': f['static'],
                             'where': '%s:%d' % (p, f['line'])})
            mine.sort(key=lambda e: e['start'])
            for e in mine:
                e['dispatch'] = False
            bodies[p] = ([e['start'] for e in mine], mine)
            entries.extend(mine)

        def mark(p, offsets):
            starts, mine = bodies[p]
            for off in offsets:
                i = bisect.bisect_right(starts, off) - 1
                if i >= 0 and mine[i]['start'] <= off <= mine[i]['end'] and mine[i]['blocks']:
                    mine[i]['dispatch'] = True

        for p in bodies:
            mark(p, self._direct_dispatch[p][0])
        with_keyword, functions = defaultdict(list), defaultdict(list)
        for e in entries:
            if e['kind'] == 'function':
                functions[e['name']].append(e)
            else:
                for k in e['keywords']:
                    with_keyword[k].append(e)

        def usable():
            """Maps each usable wrapper name to the first entry that defines it."""
            found_keywords, found_functions = OrderedDict(), OrderedDict()
            for e in entries:
                if not e['dispatch']:
                    continue
                if e['kind'] == 'function':
                    if all(x['dispatch'] and not x['static'] for x in functions[e['name']]):
                        found_functions.setdefault(e['name'], e)
                    continue
                for k in e['blocks']:
                    if len(k) >= self.WRAPPER_MIN_NAME and k not in BLOCK_KEYWORDS_NEVER_WRAPPERS and \
                            all(x['dispatch'] and k in x['blocks'] for x in with_keyword[k]):
                        found_keywords.setdefault(k, e)
            return found_keywords, found_functions

        used_keywords, used_functions = OrderedDict(), OrderedDict()
        self.wrapper_passes = 0
        identifiers = self._identifiers   # path -> every identifier in the file
        while True:
            keywords, functions_now = usable()
            new_keywords = [k for k in keywords if k not in used_keywords]
            new_functions = [f for f in functions_now if f not in used_functions]
            if not new_keywords and not new_functions:
                break
            if self.wrapper_passes == self.WRAPPER_MAX_PASSES:
                self.warnings.append('the search for block-dispatching wrappers stopped after %d passes without '
                                     'settling; calls to some wrappers may be missed' % self.WRAPPER_MAX_PASSES)
                break
            self.wrapper_passes += 1
            for k in new_keywords:
                used_keywords[k] = keywords[k]
            for f in new_functions:
                used_functions[f] = functions_now[f]
            step = DispatchWrappers(new_keywords, new_functions)
            for p in bodies:
                if p not in identifiers:
                    identifiers[p] = frozenset(_IDENTIFIER.findall(self.masked(p)))
                words = identifiers[p] & step._all
                if words:
                    mark(p, step.dispatch_offsets(self.masked(p), words))
        defined_at = dict((k + ':', '%s at %s' % (e['label'], e['where'])) for k, e in used_keywords.items())
        defined_at.update((f + '()', '%s at %s' % (e['label'], e['where'])) for f, e in used_functions.items())
        return DispatchWrappers(used_keywords, used_functions, defined_at, self.wrapper_passes,
                                self.WRAPPER_MAX_PASSES)

    # Stored state -------------------------------------------------------------

    def _ancestors(self, cls):
        """The superclass chain of cls, nearest first, without cls."""
        out, seen, c = [], {cls}, self.superclass.get(cls)
        while c and c not in seen:
            out.append(c)
            seen.add(c)
            c = self.superclass.get(c)
        return out

    def _class_at(self, path, offset):
        """The class of the method whose body holds offset in path, or None."""
        for m in self.objc_file(path).methods:
            if m['body_start'] <= offset <= m['body_end']:
                return m['class']
        return None

    def _find_constant_key_setters(self):
        """Maps each class with a rule 3 match whose key is a constant, in one of its own methods, to where the
        first one is; and keeps every file's matches of rules 1, 2 and 3 for Inventory.stored_state."""
        self._stored_direct = {}
        self.constant_key_setter_classes = {}
        for p in self.impl_files:
            masked = self.masked(p)
            matches, self_sends = stored_state_matches(masked)
            self._stored_direct[p] = (matches, self_sends)
            for m in matches:
                if m['rule'] == 3 and not p.endswith('.c'):
                    cls = self._class_at(p, m['offset'])
                    if cls and cls not in self.constant_key_setter_classes:
                        self.constant_key_setter_classes[cls] = '%s:%d' % (p, LineIndex(masked).line(m['offset']))

    def stored_state(self, path):
        """Every stored-state match in an implementation file, by the four rules (see STORED_STATE_DIRECT), sorted
        by offset, each with its line."""
        if path in self._stored:
            return self._stored[path]
        matches, self_sends = self._stored_direct[path]
        found = list(matches)
        if not path.endswith('.c'):
            for s in self_sends:
                cls = self._class_at(path, s['offset'])
                for ancestor in (self._ancestors(cls) if cls else []):
                    if ancestor in STORED_STATE_API_CLASSES:
                        source = 'named list'
                    elif ancestor in self.constant_key_setter_classes:
                        source = 'rule 3 at %s' % self.constant_key_setter_classes[ancestor]
                    else:
                        continue
                    found.append(_match(s['offset'], s['text'], 3, '%s in %s, which inherits from %s (%s)'
                                        % (s['receiver'], cls, ancestor, source), _SELF_SEND_WHY))
                    break
            for container in self.objc_file(path).containers:
                if container['kind'] != 'implementation' or container['category'] is not None:
                    continue
                for cls in self.classes_named(path, container['name']):
                    chain = self._ancestors(cls)
                    listed = [i for i, c in enumerate(chain) if c in STORED_STATE_API_CLASSES]
                    if listed:
                        ancestor = chain[listed[0]]
                        through = chain[:listed[0]]
                        found.append(_match(container['start'], '@implementation ' + container['name'], 4,
                                            'superclass ' + ancestor + (' through ' + ', '.join(through)
                                                                        if through else ''),
                                            'a subclass of a class on the named list (%s)'
                                            % STORED_STATE_API_CLASSES[ancestor]))
        lines = LineIndex(self.masked(path))
        result = []
        for m in first_by_rule(found):
            m = OrderedDict(m)
            m['line'] = lines.line(m['offset'])
            result.append(m)
        self._stored[path] = result
        return result

    # Classes created from a name ---------------------------------------------

    def _class_name_sites(self):
        """Calls that turn a string into a class, in every tracked Objective-C and Swift file outside
        submodules/ and this tool's directory (the same files as the selector scan).

        Returns (sites, unresolved). Each site is {'where', 'literal', 'bases',
        'protocols', 'selectors'}: a literal class name, or for a name known only
        at run time, the constraints the code applies to the class afterwards in
        the same method or function (isSubclassOfClass:[X class],
        conformsToProtocol:@protocol(P), instancesRespondToSelector:@selector(s)).
        A run-time name with no such constraint is unresolved: any class may be
        reached, and it is listed in unresolved.
        """
        sites, unresolved = [], []
        call = re.compile(r'\b(NSClassFromString|objc_getClass|objc_lookUpClass)\s*\(\s*')
        for p in sorted(set(self.objc_sources + self.swift_files + self._outside_files)):
            masked = self.masked(p)
            if 'NSClassFromString' not in masked and 'objc_getClass' not in masked and \
                    'objc_lookUpClass' not in masked:
                continue
            raw = self.text(p)
            lines = LineIndex(raw)
            bodies = None
            for m in call.finditer(masked):
                where = '%s:%d' % (p, lines.line(m.start()))
                lit = re.match(r'@?"([A-Za-z_]\w*)"\s*\)', raw[m.end():m.end() + 200])
                if lit:
                    sites.append(OrderedDict([('where', where), ('literal', lit.group(1)), ('bases', []),
                                              ('protocols', []), ('selectors', [])]))
                    continue
                end = len(masked)
                if not p.endswith(SWIFT_EXT):
                    if bodies is None:
                        bodies = self.objc_file(p).bodies()
                    enclosing = [b for b in bodies if b[2] <= m.start() <= b[3]]
                    end = enclosing[-1][3] if enclosing else m.end()
                else:
                    end = m.end()
                body = masked[m.start():end]
                site = OrderedDict([
                    ('where', where), ('literal', None),
                    ('bases', sorted(set(re.findall(r'isSubclassOfClass\s*:\s*\[\s*(\w+)\s+class\s*\]', body)))),
                    ('protocols', sorted(set(re.findall(r'conformsToProtocol\s*:\s*@protocol\s*\(\s*(\w+)\s*\)',
                                                        body)))),
                    ('selectors', sorted(set(re.findall(
                        r'instancesRespondToSelector\s*:\s*@selector\s*\(\s*([\w:]+)\s*\)', body))))])
                sites.append(site)
                if not (site['bases'] or site['protocols'] or site['selectors']):
                    unresolved.append(where)
        return sites, unresolved

    def _selector_wrappers(self):
        """Selector-taking methods and functions in scope: the keywords of method parameters typed SEL, and the
        names of C functions with a SEL parameter. Calls to them dispatch whatever selector they are given."""
        keywords, functions = set(), set()
        param = re.compile(r'\b(\w+)\s*:\s*\(\s*SEL\b[^)]*\)')
        function = re.compile(r'^[ \t]*(?![-+])[^\n;{}()]*?\b(\w+)\s*\(([^;{}()]*\bSEL\b[^;{}()]*)\)', re.M)
        for p in self.objc_sources:
            masked = self.masked(p)
            if 'SEL' not in masked:
                continue
            keywords.update(m.group(1) for m in param.finditer(masked))
            for m in function.finditer(strip_preprocessor(masked)):
                if m.group(1) not in _C_KEYWORDS and m.group(1) not in ('SEL', 'IMP'):
                    functions.add(m.group(1))
        return keywords, sorted(functions)

    def _dynamic_selector_sites(self):
        """Calls that dispatch or build a selector they do not see as a literal, in every tracked Objective-C
        and Swift file outside submodules/ and this tool's directory.

        Objective-C: NSSelectorFromString, sel_registerName and sel_getUid with
        an argument that is not a string literal; any message keyword in the
        perform...Selector family, or ending in Selector or selector (NSTimer
        and notification registration, setSelector:, methodForSelector: and the
        like, but not respondsToSelector: and other queries), sendAction:,
        tryToPerform: and targetForAction:, whose argument is not an @selector
        literal; objc_msgSend with no @selector literal among its arguments;
        and calls to the selector-taking wrappers found in scope (see
        _selector_wrappers) without an @selector literal. Swift: Selector(...)
        and NSSelectorFromString with an argument that is not a string literal,
        .perform( and selector: with an argument that is not a #selector
        literal. What they can reach is not determined; that is for the
        entry-point census. Returns 'path:line: call' strings.
        """
        self.selector_wrapper_keywords, self.selector_wrapper_functions = self._selector_wrappers()
        extra = '|'.join(re.escape(k) for k in sorted(self.selector_wrapper_keywords))
        objc_keyword = re.compile(r'\b([A-Za-z_]*[pP]erform[A-Za-z]*Selector[A-Za-z]*|\w*[Ss]elector|sendAction|'
                                  r'tryToPerform|targetForAction|setAction|setDoubleAction%s)\s*:\s*'
                                  % (('|' + extra) if extra else ''))
        # A selector held in a variable assigned to an action, in either language: item.action = sel.
        action_assignment = re.compile(r'\.\s*(action|doubleAction)\s*=(?!=)\s*')
        objc_string = re.compile(r'\b(NSSelectorFromString|sel_registerName|sel_getUid)\s*\(\s*')
        objc_calls = re.compile(r'\b(objc_msgSend\w*%s)\s*\(' % ''.join(
            '|' + re.escape(f) for f in self.selector_wrapper_functions))
        swift_string = re.compile(r'(?<![\w.#])(Selector|NSSelectorFromString)\s*\(\s*')
        swift_call = re.compile(r'(?<!\w)(perform|sendAction|tryToPerform)\s*\(\s*')
        swift_label = re.compile(r'\b(?:(selector|action)|target\s*\(\s*(forAction))\s*:\s*')
        sites = []
        for p in sorted(set(self.objc_sources + self.swift_files + self._outside_files)):
            raw = self.text(p)
            if 'elector' not in raw and 'sel_' not in raw and 'objc_msgSend' not in raw and 'perform' not in raw \
                    and 'ction' not in raw and not any(f in raw for f in self.selector_wrapper_functions) \
                    and not any(k in raw for k in self.selector_wrapper_keywords):
                continue
            masked = self.masked(p)
            found = []
            if p.endswith(SWIFT_EXT):
                for m in swift_string.finditer(masked):
                    if not masked.startswith('"', m.end()):
                        found.append((m.start(), m.group(1)))
                for m in swift_call.finditer(masked):
                    rest = masked[m.end():m.end() + 40]
                    # The first argument must look like a selector: a plain name other than nil, a member access,
                    # Selector(...) or NSSelectorFromString(...). A declaration such as func perform(_ x: Int) never
                    # has one, because a parameter has a label.
                    if _NO_SELECTOR.match(rest) or not _SWIFT_SELECTOR_ARGUMENT.match(rest):
                        continue
                    found.append((m.start(), m.group(1)))
                for m in swift_label.finditer(masked):
                    rest = masked[m.end():m.end() + 40]
                    if rest.startswith('#selector') or _NO_SELECTOR.match(rest) or _SWIFT_NOT_A_SELECTOR.match(rest) \
                            or _in_swift_selector_literal(masked, m.start()) or _in_swift_declaration(masked, m.start()):
                        continue
                    found.append((m.start(), 'target(forAction:)' if m.group(2) else
                                  ('action:' if m.group(1) == 'action' else 'selector')))
            else:
                for m in objc_string.finditer(masked):
                    if not masked.startswith('"', m.end()) and not masked.startswith('@"', m.end()):
                        found.append((m.start(), m.group(1)))
                for m in objc_keyword.finditer(masked):
                    name = m.group(1)
                    rest = masked[m.end():m.end() + 12]
                    if name in _SELECTOR_QUERIES or rest.startswith('@selector') or rest.startswith('(') or \
                            _NO_SELECTOR.match(rest):
                        continue  # a query, a literal, nil, or a method signature such as performSelector:(SEL)s
                    if re.search(r'[@#]selector\s*\(\s*[\w:]*$', masked[max(0, m.start() - 60):m.start()]):
                        continue  # part of a selector literal: @selector(performSelector:withObject:)
                    found.append((m.start(), name))
                for m in objc_calls.finditer(masked):
                    args = masked[m.end() - 1:find_matching(masked, m.end() - 1, '(', ')') + 1]
                    if '@selector' not in args and not re.search(r'\bSEL\b', args):
                        found.append((m.start(), m.group(1)))
            if 'ction' in masked:
                for m in action_assignment.finditer(masked):
                    rest = masked[m.end():m.end() + 12]
                    # Not a literal, nil, or a Swift enum case (.action = .close).
                    if rest.startswith(('@selector', '#selector', '.')) or _NO_SELECTOR.match(rest):
                        continue
                    found.append((m.start(), m.group(1) + ' ='))
            if found:
                lines = LineIndex(masked)
                sites.extend((p, lines.line(offset), offset, call) for offset, call in found)
        sites.sort()
        self.dynamic_selector_lines = defaultdict(list)
        for p, line, _, _ in sites:
            self.dynamic_selector_lines[p].append(line)
        return ['%s:%d: %s' % (p, line, call) for p, line, _, call in sites]

    def subclasses_in_scope(self, cls):
        """Every Objective-C subclass of cls, directly or indirectly, declared anywhere."""
        out, todo = [], [cls]
        while todo:
            for sub in self.objc_subclasses.get(todo.pop(), []):
                if sub not in out:
                    out.append(sub)
                    todo.append(sub)
        return out

    def _protocol_descendants(self, proto):
        """proto and every protocol that adopts it, directly or indirectly."""
        cache = self.__dict__.setdefault('_protocol_parent_cache', {})
        if not cache:
            for p in self.objc_sources:
                masked = self.masked(p)
                if '@protocol' in masked:
                    for m in re.finditer(r'@protocol\s+(\w+)\s*<([^>]*)>', masked):
                        for parent in m.group(2).split(','):
                            cache.setdefault(parent.strip(), set()).add(m.group(1))
        out, todo = {proto}, [proto]
        while todo:
            for child in cache.get(todo.pop(), ()):
                if child not in out:
                    out.add(child)
                    todo.append(child)
        return out

    def _classes_created_by_name(self):
        """Maps each class that a class-name site can reach to the reasons, by text."""
        reached = defaultdict(list)

        def add(cls, why, with_subclasses=True):
            for c in [cls] + (self.subclasses_in_scope(cls) if with_subclasses else []):
                if why not in reached[c]:
                    reached[c].append(why)

        for site in self.class_name_sites:
            if site['literal']:
                add(site['literal'], 'created by name at %s' % site['where'], with_subclasses=False)
            for base in site['bases']:
                add(base, 'may be created by name at %s (any subclass of %s)' % (site['where'], base))
            for proto in site['protocols']:
                protocols = self._protocol_descendants(proto)
                for name, decls in self.interfaces.items():
                    if any(set(d['protocols']) & protocols for d in decls):
                        add(name, 'may be created by name at %s (any class conforming to %s)' % (site['where'], proto))
            for selector in site['selectors']:
                for f in self.impl_files:
                    if f.endswith('.c'):
                        continue
                    for m in self.objc_file(f).methods:
                        if m['sign'] == '-' and m['selector'] == selector:
                            for cls in self.classes_named(f, m['class']):
                                add(cls, 'may be created by name at %s (any class implementing -%s)'
                                    % (site['where'], selector))
        return reached

    # Per-file facts --------------------------------------------------------

    def header_for(self, impl):
        stem = os.path.splitext(impl)[0]
        if stem + HEADER_EXT in self._hset:
            return stem + HEADER_EXT
        candidates = self.header_by_basename.get(os.path.basename(stem) + HEADER_EXT, [])
        return candidates[0] if len(candidates) == 1 else None

    def reach_of_header(self, header):
        """In-scope files importing the header directly or through other in-scope headers."""
        if header in self._reach:
            return self._reach[header]
        seen = set()
        todo = [os.path.basename(header)]
        while todo:
            base = todo.pop()
            for p in self.importers.get(base, ()):
                if p not in seen:
                    seen.add(p)
                    if p.endswith(HEADER_EXT):
                        todo.append(os.path.basename(p))
        # Files that import it through a prefix header. Every header it imports is in the same prefix
        # closure, so nothing more is reached through them.
        seen |= self.prefix_importers.get(header, set())
        seen.discard(header)
        self._reach[header] = seen
        return seen

    def class_headers(self, impl):
        """In-scope headers, other than the file's own, with the primary @interface of a class it implements."""
        own = self.header_for(impl)
        return sorted(set(d['file'] for cls in self.classes_in_file.get(impl, [])
                          for d in self.interfaces.get(cls, [])
                          if d['category'] is None and d['in_scope'] and d['file'].endswith(HEADER_EXT)
                          and d['file'] != own))

    def fan_in(self, impl):
        """Importers and reach of the file's header and of every other header declaring one of its classes."""
        own = self.header_for(impl)
        others = self.class_headers(impl)
        headers = ([own] if own else []) + others
        if not headers:
            return None
        header = headers[0]
        if not own:
            others = others[1:]
        base = os.path.basename(header)
        importers, reach, by_prefix, via = set(), set(), set(), set()
        for h in headers:
            importers |= set(self.importers.get(os.path.basename(h), set()))
            by_prefix |= self.prefix_importers.get(h, set())
            via |= self.prefix_via.get(h, set())
            reach |= self.reach_of_header(h)
        only_by_prefix = by_prefix - importers - set([impl] + headers)
        importers |= by_prefix
        importers -= set([impl] + headers)
        reach -= set([impl] + headers)
        prefix = None
        if via:
            prefix = OrderedDict([('via', sorted(set(v[0] for v in via))),
                                  ('targets', sorted(set(v[1] for v in via))),
                                  ('importers_only_through_it', len(only_by_prefix))])
        return OrderedDict([
            ('header', header),
            ('other_headers', others),
            ('importers', len(importers)),
            ('header_importers', len([p for p in importers if p.endswith(HEADER_EXT)])),
            ('in_bridging_header', BRIDGING_HEADER in importers),
            ('reach', len(reach)),
            ('reach_headers', len([p for p in reach if p.endswith(HEADER_EXT)])),
            ('ambiguous_basename', len(self.header_by_basename.get(base, [])) > 1),
            ('prefix_header', prefix),
        ])

    def included_by(self, impl):
        return sorted(p for p in self.importers.get(os.path.basename(impl), set())
                      if p != impl and p.endswith(IMPL_EXTS))

    def targets_for(self, impl, _depth=0):
        entries = self.membership.get(impl, [])
        if entries or _depth > 3:
            return entries
        inherited = []
        for includer in self.included_by(impl):
            for e in self.targets_for(includer, _depth + 1):
                e2 = dict(e)
                e2['included_via'] = includer
                e2['arc_source'] = 'inherited from %s, which #includes it (%s)' % (includer, e['arc_source'])
                inherited.append(e2)
        return inherited

    def arc_state(self, impl):
        """'ARC', 'non-ARC', 'mixed', 'not compiled', or 'n/a (C)'."""
        entries = self.targets_for(impl)
        if not entries:
            return 'not compiled'
        if impl.endswith('.c'):
            return 'n/a (C)'
        values = set(str(e['arc']) for e in entries)
        if values == {'True'}:
            return 'ARC'
        if values == {'False'}:
            return 'non-ARC'
        return 'mixed'

    def _where(self, d):
        return '%s:%d' % (d['file'], d['line'])

    def class_relations(self, cls):
        names = [cls] + ([self.swift_name_of[cls]] if cls in self.swift_name_of else [])
        objc_subs = []
        for sub in sorted(self.objc_subclasses.get(cls, [])):
            decl = [d for d in self.interfaces.get(sub, []) if d['category'] is None and d['superclass'] == cls]
            where = self._where(decl[0]) if decl else '?'
            objc_subs.append(OrderedDict([('name', sub), ('where', where),
                                          ('in_scope', bool(decl and decl[0]['in_scope']))]))
        swift_subs = []
        seen = set()
        for n in names:
            for c in self.swift_subclasses.get(n, []):
                if c['name'] not in seen:
                    seen.add(c['name'])
                    swift_subs.append(OrderedDict([('name', c['name']), ('where', self._where(c)),
                                                   ('in_scope', c['in_scope'])]))
        cats, exts = [], []
        for d in self.interfaces.get(cls, []):
            if d['category'] == '':
                exts.append(self._where(d))
            elif d['category']:
                cats.append(OrderedDict([('category', d['category']), ('where', self._where(d)),
                                         ('kind', 'interface'), ('in_scope', d['in_scope'])]))
        for d in self.implementations.get(cls, []):
            if d['category']:
                cats.append(OrderedDict([('category', d['category']), ('where', self._where(d)),
                                         ('kind', 'implementation'), ('in_scope', d['in_scope'])]))
        swift_exts, swift_exts_out = [], []
        for n in names:
            for e in self.swift_extensions.get(n, []):
                (swift_exts if e['in_scope'] else swift_exts_out).append(self._where(e))
        return OrderedDict([
            ('superclass', self.superclass.get(cls)),
            ('objc_subclasses', objc_subs),
            ('swift_subclasses', swift_subs),
            ('categories', cats),
            ('class_extensions', exts),
            ('swift_extensions', swift_exts),
            ('swift_extensions_outside_scope', swift_exts_out),
        ])

    def objcxx_class(self, impl):
        if not impl.endswith('.mm'):
            return None
        header = self.header_for(impl)
        header_markers = {}
        checked = [header] if header else []
        if header:
            for name in self.imports_of.get(header, []):
                for h in self.header_by_basename.get(os.path.basename(name), []):
                    checked.append(h)
        for h in checked:
            found = cxx_markers(self.masked(h))
            if found:
                header_markers[h] = found
        body = cxx_markers(self.masked(impl))
        if header_markers:
            cls = 'C++ in its header'
        elif not body:
            cls = 'no C++ at all'
        elif is_hot_path(impl):
            cls = 'C++ essential to performance (probable: hot-path directory)'
        else:
            cls = 'incidental C++ (probable)'
        return OrderedDict([('class', cls), ('markers', body), ('header_markers', header_markers)])

    def file_record(self, impl, detail=False):
        raw = self.text(impl)
        masked = self.masked(impl)
        classes = sorted(set(self.classes_in_file.get(impl, [])))
        rec = OrderedDict()
        rec['path'] = impl
        rec['lines'] = count_lines(raw)
        rec['targets'] = [OrderedDict([('target', e['target']), ('arc', e['arc']),
                                       ('per_file_flag', e['file_flag']),
                                       ('arc_source', e['arc_source']),
                                       ('included_via', e.get('included_via'))])
                          for e in self.targets_for(impl)]
        rec['arc'] = self.arc_state(impl)
        rec['included_by'] = self.included_by(impl)
        rec['rr_sites'], rec['super_dealloc_sites'] = rr_sites(masked)
        rec['fan_in'] = self.fan_in(impl)
        rec['classes'] = classes
        rec['categories_implemented'] = ['%s(%s)' % c for c in self.categories_in_file.get(impl, [])]
        rec['foundation_categories'] = sorted(set(
            '%s(%s)' % c for c in self.categories_in_file.get(impl, [])
            if _is_system_class(c[0]) and c[0] not in self.primary_impl_file))
        known = self._identifiers.get(impl)
        wrapper_calls = self.hazard_wrappers.dispatch_offsets(
            masked, None if known is None else known & self.hazard_wrappers._all)
        direct = self._direct_dispatch.get(impl) or dispatch_sites(masked)
        stored = self.stored_state(impl)
        sites = hazard_sites(masked, dispatch=(sorted(set(direct[0]) | set(wrapper_calls)), direct[1]),
                             stored=[m['offset'] for m in stored])
        line_index = LineIndex(masked)
        threads = []
        for container in ([] if impl.endswith('.c') else self.objc_file(impl).containers):
            if container['kind'] == 'implementation' and container['category'] is None and \
                    any('NSThread' in self._ancestors(c) for c in self.classes_named(impl, container['name'])):
                threads.append(container['start'])
        if threads:
            sites['NSThread subclass'] = threads
        hazards = OrderedDict((name, len(found)) for name, found in sites.items())
        hazard_lines = OrderedDict((name, sorted(set(line_index.line(o) for o in found)))
                                   for name, found in sites.items()) if detail else OrderedDict()
        nscoding = []
        xibs, sdef = OrderedDict(), []
        relations = OrderedDict()
        for cls in classes:
            for d in self.interfaces.get(cls, []):
                if d['in_scope'] and any(_NSCODING_PROTOCOL.fullmatch(p) for p in d['protocols']):
                    nscoding.append('%s adopts %s' % (cls, ', '.join(p for p in d['protocols']
                                                                     if _NSCODING_PROTOCOL.fullmatch(p))))
            if cls in self.xib_classes:
                xibs[cls] = sorted(self.xib_classes[cls])
            if cls in self.sdef_classes:
                sdef.append(cls)
            relations[cls] = self.class_relations(cls)
        coder = sorted(set(_CODER_METHOD.findall(masked)))
        if coder:
            nscoding.append('implements ' + ', '.join(c + ':' for c in coder))
        if nscoding:
            hazards['NSCoding'] = len(nscoding)
        if xibs:
            hazards['xib customClass'] = sum(len(v) for v in xibs.values())
        if sdef:
            hazards['sdef class'] = len(sdef)
        sdef_methods, sdef_keys = self._sdef_implementations(impl)
        if sdef_methods:
            hazards['sdef method'] = len(sdef_methods)
        if sdef_keys:
            hazards['sdef key'] = len(sdef_keys)
        header = self.header_for(impl)
        own_files = [impl] + ([header] if header else [])
        macro_hits = []
        for p in own_files:
            for m in self.macros_by_file.get(p, []):
                if m['token_pasting']:
                    macro_hits.append('%s defines token-pasting macro %s' % (p, m['name']))
                if m['defines_method']:
                    macro_hits.append('%s defines method-defining macro %s' % (p, m['name']))
                if m['defines_class']:
                    macro_hits.append('%s defines class-defining macro %s' % (p, m['name']))
        code = strip_preprocessor(masked)
        for name, where in sorted(self.method_macros.items()):
            if where != impl and name in code and re.search(r'\b%s\b' % re.escape(name), code):
                macro_hits.append('uses method-defining macro %s from %s' % (name, where))
        if macro_hits:
            hazards['macros'] = len(macro_hits)
        # Ownership and method-family attributes, written out or through a macro, here or in the header.
        ownership = []
        for p in own_files:
            pmasked = self.masked(p)
            for m in _OWNERSHIP_ATTRIBUTE.finditer(pmasked):
                ownership.append('%s:%d: %s' % (p, LineIndex(pmasked).line(m.start()), m.group(0)))
            pcode = strip_preprocessor(pmasked)
            for name, where in sorted(self.ownership_macros.items()):
                if name in pcode:
                    for m in re.finditer(r'\b%s\b' % re.escape(name), pcode):
                        ownership.append('%s:%d: %s (a macro from %s that applies an ownership or method-family '
                                         'attribute)' % (p, LineIndex(pcode).line(m.start()), name, where))
        if ownership:
            hazards['ownership attribute'] = len(ownership)
        control_flow = sorted('%s (from %s)' % (name, where) for name, where in self.control_flow_macros.items()
                              if name in code and re.search(r'\b%s\s*\(' % re.escape(name), code))
        if control_flow:
            hazards['control flow in a macro'] = len(control_flow)
        # A C function defined by a macro is not seen by the C-symbol rule.
        function_macro_uses = sum(len(re.findall(r'(?m)^[ \t]*%s\s*\(' % re.escape(name), code))
                                  for name in self.function_macros if name in code)
        if function_macro_uses:
            hazards['function-defining macro'] = function_macro_uses
        family_methods = [m for m in ([] if impl.endswith('.c') else self.objc_file(impl).methods)
                          if _OWNERSHIP_FAMILY.match(m['selector'])]
        family = sorted(set(m['selector'] for m in family_methods))
        if family:
            hazards['ownership-transferring method name'] = len(family)
            hazard_lines['ownership-transferring method name'] = sorted(set(m['line'] for m in family_methods))
        family_sites = sorted(set((m['line'], m['selector']) for m in family_methods))
        stringifying = sorted(line_index.line(m.start()) for name in self.stringifying_macros if name in code
                              for m in re.finditer(r'\b%s\s*\(' % re.escape(name), code))
        if stringifying:
            hazards['stringifying macro'] = len(stringifying)
            hazard_lines['stringifying macro'] = sorted(set(stringifying))
        selector_sites = self.dynamic_selector_lines.get(impl, [])
        if selector_sites:
            hazards['dynamic selector site'] = len(selector_sites)
            hazard_lines['dynamic selector site'] = sorted(set(selector_sites))
        atomic_properties = [] if impl.endswith('.c') else [
            prop for f in own_files for prop in self.objc_file(f).properties if not prop['nonatomic']]
        if atomic_properties:
            hazards['atomic property'] = len(atomic_properties)
            hazard_lines['atomic property'] = sorted(set(prop['line'] for prop in atomic_properties
                                                         if prop['file'] == impl))
        # Objective-C outside scope (tests, other targets) importing the header.
        outside_importers = sorted(self.importers_outside_scope.get(os.path.basename(header), ())) if header else []
        if outside_importers:
            hazards['imported outside scope'] = len(outside_importers)
        # Classes that a class-name call can create.
        created = ['%s: %s' % (cls, why) for cls in classes for why in self.created_by_name.get(cls, [])]
        if created:
            hazards['created by name'] = len(created)
        # Connections in xib files: to objects of the file's classes, and to the File's
        # Owner of a nib the file names (or that is named after one of its classes).
        connections = []
        for cls in classes:
            for x in sorted(self.xib_classes.get(cls, ())):
                info = self.xibs.get(x)
                ids = [i for i, c in info['classes'].items() if c == cls] if info else []
                refs = xib_references(info, ids) if info else None
                connections.append(OrderedDict([('xib', x), ('object', 'customClass %s' % cls), ('references', refs)]))
        nib_names = set(m.group(1) for m in re.finditer(r'@?"([A-Za-z_][\w.+-]*)"', raw)
                        if masked[m.start()] == raw[m.start()]) & set(self.xib_by_name)
        for name in sorted(nib_names | (set(classes) & set(self.xib_by_name))):
            for x in self.xib_by_name[name]:
                how = ('named after class %s' % name) if name in classes else ('the file names "%s"' % name)
                info = self.xibs.get(x)
                refs = xib_references(info, ['-2']) if info else None
                if refs is None or any(refs.values()):
                    connections.append(OrderedDict([('xib', x), ('object', "File's Owner (%s)" % how),
                                                    ('references', refs)]))
        owner = [c for c in connections if c['object'].startswith("File's Owner")]
        if owner:
            hazards["xib File's Owner"] = len(owner)
        for key, label in (('bindings', 'xib binding'), ('runtime_attributes', 'xib runtime attribute')):
            n = sum(c['references'][key] for c in connections if c['references'])
            if n:
                hazards[label] = n
        unread = set(c['xib'] for c in connections if c['references'] is None)
        unread |= set(x for x, words in self.unparsed_xib_words.items()
                      if any(cls in words for cls in classes))
        unread = sorted(unread)
        if unread:
            hazards['xib not parsed'] = len(unread)
        # Methods found by a convention or by the responder chain.
        methods = [] if impl.endswith('.c') else self.objc_file(impl).methods
        convention = sorted(set('%s%s' % (m['sign'], m['selector']) for m in methods
                                if _CONVENTION_SELECTOR.match(m['selector'])))
        if convention:
            hazards['methods named by convention'] = len(convention)
        first_responder = sorted(set(m['selector'] for m in methods
                                     if m['sign'] == '-' and m['selector'] in self.first_responder_actions))
        if first_responder:
            hazards['First Responder action'] = len(first_responder)
        rec['hazards'] = hazards
        rec['stored_state_first'] = OrderedDict((k, stored[0][k]) for k in ('line', 'text', 'rule', 'entry')) \
            if stored else None
        rec['macro_hits'] = macro_hits
        rec['wholly_conditional'] = wholly_conditional(masked)
        rec['parse_problems'] = self.parse_problems(impl)
        rec['objcxx'] = self.objcxx_class(impl)
        rec['hot_path_dir'] = is_hot_path(impl)
        partial = sorted(set(c for c in classes if relations[c]['swift_extensions']))
        rec['migration_state'] = OrderedDict([
            ('language', 'C' if impl.endswith('.c') else
             ('Objective-C++' if impl.endswith('.mm') else 'Objective-C')),
            ('arc', rec['arc']),
            ('partially_ported', bool(partial)),
            ('classes_with_swift_extensions', partial),
        ])
        rec['objc_subclass_count'] = sum(len(relations[c]['objc_subclasses']) for c in classes)
        rec['objc_subclasses_outside_scope'] = sum(
            1 for c in classes for s in relations[c]['objc_subclasses'] if not s['in_scope'])
        rec['swift_subclass_count'] = sum(len(relations[c]['swift_subclasses']) for c in classes)
        rec['swift_extension_count'] = sum(len(relations[c]['swift_extensions']) for c in classes)
        own = (impl + ':', (rec['fan_in']['header'] + ':') if rec['fan_in'] else None)
        external = [cat for c in classes for cat in relations[c]['categories']
                    if not cat['where'].startswith(own[0]) and not (own[1] and cat['where'].startswith(own[1]))]
        rec['external_category_count'] = len(external)
        rec['external_categories_outside_scope'] = len([c for c in external if not c['in_scope']])

        def cat_text(cls, cat):
            return '%s(%s) at %s%s' % (cls, cat['category'], cat['where'], '' if cat['in_scope'] else ', outside scope')
        implemented_names = set((c, cat['category']) for c in classes for cat in relations[c]['categories']
                                if cat['kind'] == 'implementation')
        rec['categories_implemented_elsewhere'] = [cat_text(c, cat) for c, cat in sorted(
            ((c, cat) for c in classes for cat in relations[c]['categories']
             if cat['kind'] == 'implementation' and not cat['where'].startswith(impl + ':')),
            key=lambda x: (x[1]['where'], x[0]))]
        declared_only = [(c, cat) for c in classes for cat in relations[c]['categories']
                         if cat['kind'] == 'interface' and (c, cat['category']) not in implemented_names
                         and not cat['where'].startswith(own[0]) and not (own[1] and cat['where'].startswith(own[1]))]
        rec['categories_declared_only'] = [cat_text(c, cat) for c, cat in
                                           sorted(declared_only, key=lambda x: (x[1]['where'], x[0]))]
        rec['categories_declared_only_outside_scope'] = len([1 for _, cat in declared_only if not cat['in_scope']])
        rec['c_symbols_in_headers'] = self.c_symbols_in_headers(impl)
        rec['class_extensions_elsewhere'] = sorted(
            where for c in classes for where in relations[c]['class_extensions']
            if not where.startswith(own[0]) and not (own[1] and where.startswith(own[1])))
        if detail:
            rec['hazard_lines'] = hazard_lines
            rec['stored_state'] = [OrderedDict((k, m[k]) for k in ('line', 'text', 'rule', 'entry', 'why'))
                                   for m in stored]
            rec['dispatch_wrapper_calls'] = [
                OrderedDict([('line', line_index.line(o)), ('wrapper', w),
                             ('defined_at', self.hazard_wrappers.defined_at.get(w))])
                for o, w in sorted(wrapper_calls.items())]
            rec['atomic_properties'] = ['%s:%d: %s' % (prop['file'], prop['line'], prop['name'])
                                        for prop in atomic_properties]
            rec['relations'] = relations
            rec['nscoding'] = nscoding
            rec['xib'] = xibs
            rec['sdef'] = sdef
            rec['sdef_methods'] = sdef_methods
            rec['sdef_keys'] = sdef_keys
            rec['ownership_attributes'] = ownership
            rec['ownership_transferring_methods'] = ['%s:%d: %s' % (impl, line, sel) for line, sel in family_sites]
            rec['control_flow_macros'] = control_flow
            rec['imported_outside_scope'] = outside_importers
            rec['created_by_name'] = created
            rec['xib_connections'] = connections
            rec['methods_named_by_convention'] = convention
            rec['first_responder_actions'] = OrderedDict(
                (sel, sorted(self.first_responder_actions[sel])) for sel in first_responder)
            if not impl.endswith('.c'):
                of = self.objc_file(impl)
                rec['method_check'] = OrderedDict([('parsed', len(of.methods)),
                                                   ('crude_count', of.crude_method_count),
                                                   ('warnings', of.warnings)])
        return rec

    def parse_problems(self, impl):
        """Reasons the text parse of a file may be incomplete, so that hazards found from it may be missing."""
        problems = []
        code = strip_preprocessor(self.masked(impl))
        for kind in ('interface', 'implementation'):
            written = len(re.findall(r'@%s\b' % kind, code))
            parsed = len([d for d in objc_containers(code) if d['kind'] == kind])
            if written != parsed:
                problems.append('%d @%s lines but %d parsed' % (written, kind, parsed))
        if not impl.endswith('.c'):
            for w in self.objc_file(impl).warnings:
                if 'unmatched {' in w or 'method definitions' in w:
                    problems.append(w)
        return problems

    def _sdef_implementations(self, impl):
        """Methods in impl that iTerm2.sdef names: handler selectors, and keys of scripting classes."""
        if impl.endswith('.c') or not (self.sdef_methods or self.sdef_keys):
            return [], []
        raw = self.text(impl)
        firsts = set(sel.split(':')[0] for sel in self.sdef_methods)
        implemented = set(n for c in self.classes_in_file.get(impl, []) for n in [c]) | \
            set(c for c, _ in self.categories_in_file.get(impl, []))
        if not (implemented & self.sdef_classes) and not any(f in raw for f in firsts):
            return [], []
        methods, keys = [], []
        for m in self.objc_file(impl).methods:
            classes = self.classes_named(impl, m['class'])
            label = '%s[%s %s]' % (m['sign'], '/'.join(classes), m['selector'])
            if m['selector'] in self.sdef_methods:
                methods.append(label)
            elif m['sign'] == '-' and set(classes) & self.sdef_classes:
                sel = m['selector']
                key = sel
                if sel.startswith('set') and sel.endswith(':') and sel.count(':') == 1:
                    key = sel[3:4].lower() + sel[4:-1]
                if key in self.sdef_keys:
                    keys.append(label)
        return methods, keys

    def header_words(self):
        """Maps each identifier written in an in-scope header (outside comments and strings) to those headers."""
        if self._header_words is None:
            words = defaultdict(list)
            for h in self.headers:
                for w in set(re.findall(r'[A-Za-z_]\w*', self.masked(h))):
                    words[w].append(h)
            self._header_words = words
        return self._header_words

    def extern_declarations(self):
        """Maps each identifier on an extern line (extern, FOUNDATION_EXPORT and the like) of any tracked
        Objective-C, C or header file outside submodules/ and this tool's directory to those files."""
        if self._externs is None:
            externs = defaultdict(set)
            line = re.compile(r'(?m)^[ \t]*(?:extern|FOUNDATION_EXPORT|FOUNDATION_EXTERN|APPKIT_EXTERN|UIKIT_EXTERN|'
                              r'CF_EXPORT|OBJC_EXTERN)\b[^\n]*')
            for p in sorted(set(self.objc_sources + [f for f in self._outside_files if not f.endswith(SWIFT_EXT)])):
                masked = self.masked(p)
                if 'extern' in masked or 'EXPORT' in masked or 'EXTERN' in masked:
                    for m in line.finditer(masked):
                        for w in re.findall(r'[A-Za-z_]\w*', m.group(0)):
                            externs[w].add(p)
            self._externs = externs
        return self._externs

    def c_symbols_in_headers(self, impl):
        """Non-static C functions and file-scope globals defined in impl that another file may declare.

        By text: a name written anywhere in an in-scope header, or on an extern
        line of any other tracked Objective-C, C or header file, counts as a
        declaration, so this over-approximates. Symbols defined or declared
        through macros are not seen. Objective-C cannot call a Swift free function
        or see a Swift-only global (interop.md), so other files may depend on
        these staying in C.
        """
        of = self.objc_file(impl)
        found = OrderedDict()
        for kind, items in (('function', [f for f in of.functions if not f['static']]), ('global', of.globals)):
            for item in items:
                where = set(self.header_words().get(item['name'], [])) | \
                    (self.extern_declarations().get(item['name'], set()) - {impl})
                if where and (kind, item['name']) not in found:
                    found[(kind, item['name'])] = OrderedDict([('kind', kind), ('name', item['name']),
                                                               ('line', item['line']),
                                                               ('declared_in', sorted(where))])
        return sorted(found.values(), key=lambda x: (x['line'], x['name']))

    def all_records(self):
        return [self.file_record(p) for p in self.impl_files]

    # Resolution -------------------------------------------------------------

    def resolve(self, name):
        if name in self.impl_files:
            return name
        cand = os.path.relpath(os.path.abspath(name), self.root) if os.path.exists(name) else name
        if cand in self.impl_files:
            return cand
        matches = [p for p in self.impl_files if os.path.basename(p) == name]
        if not matches:
            matches = [p for p in self.impl_files if os.path.splitext(os.path.basename(p))[0] == name]
        if not matches and name in self.primary_impl_file:
            matches = [self.primary_impl_file[name]]
        if len(matches) == 1:
            return matches[0]
        if not matches:
            categorized = [p for p in self.non_product if p.endswith(IMPL_EXTS) and (
                p == name or p == cand or os.path.basename(p) == name or os.path.splitext(os.path.basename(p))[0] == name)]
            if categorized:
                raise InventoryError('%s; such a file is outside scope. %s' % (
                    '; '.join('%s is %s (compiled by %s)' % (p, self.non_product[p]['reason'],
                                                             ', '.join(self.non_product[p]['targets']))
                              for p in categorized), NON_PRODUCT_RULE))
            missing = [p for p in self.missing_files if p == name or os.path.basename(p) == name or
                       os.path.splitext(os.path.basename(p))[0] == name]
            if missing:
                raise InventoryError('%s is tracked by git but missing from the working tree, so nothing about it '
                                     'can be reported' % ', '.join(missing))
            raise InventoryError('no in-scope implementation file matches %r' % name)
        raise InventoryError('ambiguous name %r: %s' % (name, ', '.join(matches)))

    # History and progress ----------------------------------------------------

    def history(self):
        return history_from_git(self.root)

    def _grep_scope(self):
        return ['--', '.'] + [':(exclude)%s' % p for p in MARKER_EXCLUDED_PATHS] + [':(exclude)submodules']

    def marker_counts(self):
        """Occurrences and files for each marker, outside the excluded paths."""
        args = ['grep', '-I', '-o', '-F']
        for marker in MARKERS:
            args += ['-e', marker]
        out = git_or_fail(self.root, args + self._grep_scope(), ok=(0, 1))
        result = OrderedDict((m, {'occurrences': 0, 'files': set()}) for m in MARKERS)
        for line in out.splitlines():
            path, _, match = line.rpartition(':')
            if match in result:
                result[match]['occurrences'] += 1
                result[match]['files'].add(path)
        for v in result.values():
            v['files'] = len(v['files'])
        return result

    def helper_call_counts(self):
        """Calls of the checked-arithmetic helpers in tracked Swift files.

        Outside the excluded paths, the helper library and its tests. Comments
        and string literals are masked first; a name preceded by a dot or by
        another identifier character (x.it_add(), it_addObject) is not a call.
        """
        args = ['grep', '-I', '-l', '-E', '-e', '(%s)' % '|'.join(ARITHMETIC_HELPERS)]
        out = git_or_fail(self.root, args + self._grep_scope(), ok=(0, 1))
        by_helper = OrderedDict((h, 0) for h in ARITHMETIC_HELPERS)
        files = 0
        for path in out.splitlines():
            if (not path.endswith(SWIFT_EXT) or path in ARITHMETIC_HELPER_EXCLUDED_FILES or
                    not os.path.isfile(self.path(path))):
                continue
            found = ARITHMETIC_HELPER_CALL.findall(self.masked(path))
            for name in found:
                by_helper[name] += 1
            if found:
                files += 1
        return OrderedDict([('calls', sum(by_helper.values())), ('files', files), ('by_helper', by_helper)])

    def ivar_accessor_uses(self):
        """Uses of the raw accessor shapes of objc-state.md section 2.

        Counts ivar_<name> and setIvar_<name> (property or selector) and
        <Class>_ivar_<name>, <Class>_ivar_set_<name>, <Class>_ivar_ptr_<name>
        (inline functions). The runtime's own ivar_getName, ivar_getOffset and
        ivar_getTypeEncoding are not accessors and are not counted.
        """
        out = git_or_fail(self.root, ['grep', '-I', '-l', '-F', '-e', 'ivar_', '-e', 'Ivar_'] +
                          self._grep_scope(), ok=(0, 1))
        pat = IVAR_ACCESSOR_PATTERN
        total = 0
        for path in out.splitlines():
            if path and os.path.isfile(self.path(path)):
                total += len(pat.findall(self.text(path)))
        return total

    def summary(self):
        records = self.all_records()
        impl_lines = sum(r['lines'] for r in records)
        header_lines = sum(count_lines(self.text(h)) for h in self.headers)
        by_ext = OrderedDict()
        for ext in IMPL_EXTS:
            rs = [r for r in records if r['path'].endswith(ext)]
            by_ext[ext] = {'files': len(rs), 'lines': sum(r['lines'] for r in rs)}
        non_arc_target = [r for r in records if any(t['target'] == NON_ARC_TARGET for t in r['targets'])]
        compiled_without_arc = [r for r in records if r['path'].endswith(OBJC_EXTS) and
                                any(t['arc'] is False for t in r['targets'])]
        not_compiled = [r['path'] for r in records if not r['targets']]
        included = [r['path'] for r in records if r['included_by']]
        fan = [r for r in records if r['fan_in'] is not None]
        low = [r for r in records if r['fan_in'] is None or r['fan_in']['importers'] <= 2]
        low_with_header = [r for r in fan if r['fan_in']['importers'] <= 2]
        low_no_bridge = [r for r in records if r['fan_in'] is None or
                         r['fan_in']['importers'] - (1 if r['fan_in']['in_bridging_header'] else 0) <= 2]
        high = [r for r in fan if r['fan_in']['importers'] > 50]
        in_scope_classes = set(self.primary_impl_file)
        with_objc_subs = [c for c in in_scope_classes if self.objc_subclasses.get(c)]
        with_objc_subs_out = [c for c in with_objc_subs
                              if any(not s['in_scope'] for s in self.class_relations(c)['objc_subclasses'])]
        with_swift_subs = [c for c in in_scope_classes if self.class_relations(c)['swift_subclasses']]
        partial = [c for c in in_scope_classes if self.class_relations(c)['swift_extensions']]
        null_unspec = sum(len(_NULL_UNSPECIFIED.findall(self.masked(p))) for p in self.objc_sources
                          if 'ull_unspecified' in self.text(p))
        strict = sorted(p for p in self.objc_sources if 'iTermStrictWarnings' in self.text(p) and
                        _STRICT_WARNINGS_IMPORT.search(self.text(p)))
        markers = self.marker_counts()
        units, problems = self.history()
        mm = [r for r in records if r['path'].endswith('.mm')]
        out = OrderedDict()
        out['root'] = self.root
        out['scope'] = OrderedDict([('roots', list(SCOPE_ROOTS)), ('widened', SCOPE_WIDENED),
                                    ('excluded', self.excluded),
                                    ('exclusion_rules', OrderedDict((k, v) for k, v in EXCLUSION_RULES.items()
                                                                    if k in self.excluded)),
                                    ('excluded_files', self.excluded_files),
                                    ('non_product_code', self.non_product),
                                    ('non_product_rule', NON_PRODUCT_RULE),
                                    ('not_counted', '.metal shader files are not counted; whether they '
                                                    'belong in scope is for the owner to decide')])
        out['projects_searched'] = list(self.projects)
        by_root = OrderedDict()
        for root in SCOPE_ROOTS:
            rs = [r for r in records if scope_root_of(r['path']) == root]
            hs = [h for h in self.headers if scope_root_of(h) == root]
            excluded = defaultdict(int)
            for path, reason in self.excluded_files.items():
                if scope_root_of(path) == root:
                    excluded[reason] += 1
            by_root[root] = OrderedDict([
                ('implementation_files', len(rs)), ('implementation_lines', sum(r['lines'] for r in rs)),
                ('header_files', len(hs)), ('header_lines', sum(count_lines(self.text(h)) for h in hs)),
                ('swift_files', len([p for p in self.swift_files if scope_root_of(p) == root])),
                ('excluded', OrderedDict(sorted(excluded.items())))])
        out['by_scope_root'] = by_root
        out['relations_computed_over'] = OrderedDict([
            ('in_scope_files', len(self.objc_sources) + len(self.swift_files)),
            ('outside_scope_files_with_related_declarations', len(self.relation_files_outside_scope)),
            ('rule', 'every tracked .h, .m, .mm and .swift file outside submodules/ and %s' % TOOL_DIR_PREFIX)])
        out['implementation_files'] = len(records)
        out['implementation_lines'] = impl_lines
        out['by_extension'] = by_ext
        out['header_files'] = len(self.headers)
        out['header_lines'] = header_lines
        out['objc_c_cxx_lines_total'] = impl_lines + header_lines
        out['swift_files'] = len(self.swift_files)
        out['targets'] = self.targets
        out['files_in_non_arc_target'] = len(non_arc_target)
        out['files_in_non_arc_target_with_rr_sites'] = len([r for r in non_arc_target if r['rr_sites']])
        out['objc_files_compiled_without_arc'] = len(compiled_without_arc)
        out['rr_sites_total'] = sum(r['rr_sites'] for r in records)
        out['super_dealloc_sites_total'] = sum(r['super_dealloc_sites'] for r in records)
        out['not_compiled_by_any_target'] = not_compiled
        out['textually_included_implementation_files'] = included
        out['fan_in_le_2'] = OrderedDict([('files', len(low)), ('lines', sum(r['lines'] for r in low)),
                                          ('with_header', len(low_with_header)),
                                          ('without_header', len(low) - len(low_with_header))])
        out['fan_in_le_2_not_counting_bridging_header'] = len(low_no_bridge)
        out['fan_in_gt_50'] = len(high)
        out['reach_le_2'] = len([r for r in records if r['fan_in'] is None or r['fan_in']['reach'] <= 2])
        out['classes_implemented_in_scope'] = len(in_scope_classes)
        out['classes_with_objc_subclasses'] = len(with_objc_subs)
        out['classes_with_objc_subclasses_outside_scope'] = len(with_objc_subs_out)
        out['classes_with_swift_subclasses'] = len(with_swift_subs)
        out['classes_with_swift_extensions'] = len(partial)
        out['objcxx'] = OrderedDict((r['path'], r['objcxx']['class']) for r in mm)
        conditional = [r for r in records if r['wholly_conditional']]
        out['files_with_incomplete_parse'] = [r['path'] for r in records if r['parse_problems']]
        out['progress'] = OrderedDict([
            ('objc_c_cxx_lines', impl_lines + header_lines),
            ('wholly_conditional', OrderedDict([('files', len(conditional)),
                                                ('lines', sum(r['lines'] for r in conditional)),
                                                ('paths', [r['path'] for r in conditional])])),
            ('files_compiled_without_arc', len(compiled_without_arc)),
            ('null_unspecified', null_unspec),
            ('files_importing_iTermStrictWarnings_h', len(strict)),
            ('markers', markers),
            ('ivar_accessor_uses', self.ivar_accessor_uses()),
            ('helper_calls', self.helper_call_counts()),
        ])
        out['history'] = OrderedDict([('scope', HISTORY_SCOPE), ('units', len(units)), ('trailer_problems', problems)])
        out['hazard_wrappers'] = self.hazard_wrappers.as_dict()
        return out

    # Leaf ordering ----------------------------------------------------------

    def _proxy_classes(self, classes):
        """Classes among these whose superclass chain reaches NSProxy."""
        out = []
        for cls in classes:
            seen, c = set(), cls
            while c and c not in seen:
                seen.add(c)
                if c == 'NSProxy':
                    out.append(cls)
                    break
                c = self.superclass.get(c)
        return out

    def reserved_prefixes(self):
        """The prefixes of docs/swift-migration/reserved.md (none when the
        file is missing), read once; a malformed file is an InventoryError."""
        if self._reserved is None:
            # reserved_paths.py, beside this tool, is imported only here, so
            # that the subcommands that do not defer files run without it.
            here = os.path.dirname(os.path.abspath(__file__))
            if here not in sys.path:
                sys.path.insert(0, here)
            try:
                module = importlib.import_module('reserved_paths')
            except ImportError as e:
                raise InventoryError('the reserved-path reader reserved_paths.py could not be imported (%s)' % e)
            try:
                self._reserved = module.read_reserved(os.path.join(self.root, module.RESERVED))
            except module.ReservedError as e:
                raise InventoryError(str(e))
            self._reserved_module = module
        return self._reserved

    def deferral_reasons(self, r):
        """Maps each deferred list (DEFERRED_LISTS) that file record r belongs in to the details."""
        h = r['hazards']
        reasons = OrderedDict()

        def add(name, detail):
            reasons.setdefault(name, []).append(detail)

        if r['wholly_conditional']:
            add('wholly conditional', 'lines %d to %d are all under #if %s' % (
                r['wholly_conditional']['first_line'], r['wholly_conditional']['last_line'],
                r['wholly_conditional']['condition']))
        for problem in r['parse_problems']:
            add('parse incomplete', problem)
        prefixes = self.reserved_prefixes()
        prefix = self._reserved_module.reserved_prefix([r['path']], prefixes) if prefixes else None
        if prefix:
            add('reserved (reserved.md)', 'under %s (docs/swift-migration/reserved.md)' % prefix)
        if r['hot_path_dir']:
            add('probable hot path', 'in %s' % os.path.dirname(r['path']))
        for cls in r['classes']:
            if cls in GIANT_CLASSES:
                add('giant classes', 'implements %s' % cls)
        for cls, cat in self.categories_in_file.get(r['path'], []):
            if cls in GIANT_CLASSES:
                add('giant classes', 'implements part of %s (category %s)' % (cls, cat))
        for cls in self._proxy_classes(r['classes']):
            add('must stay in Objective-C for now', '%s is an NSProxy subclass' % cls)
        for key, detail in (('forwarding', 'forwarding methods (forwardInvocation: and the like)'),
                            ('method replacement', 'swizzling or method replacement'),
                            ('method-list enumeration', 'method-list enumeration'),
                            ('runtime method lookup', 'reads method or property metadata from the runtime (a reflective '
                                                      'site, hidden-callers.md section 2)'),
                            ('@try', '@try: Swift cannot catch NSException'),
                            ('+load/+initialize', 'implements +load or +initialize, which a Swift class cannot')):
            if key in h:
                add('must stay in Objective-C for now', detail)
        if 'atomics' in h:
            add('stays in C: atomics', 'uses C atomics (%d matches)' % h['atomics'])
        for sym in r['c_symbols_in_headers']:
            add('defines C functions or globals declared in a header', '%s %s (line %d), declared in %s'
                % (sym['kind'], sym['name'], sym['line'], ', '.join(sym['declared_in'])))
        if 'stored state' in h:
            first = r['stored_state_first']
            add('encodes or decodes stored state', '%d match%s; first at line %d: %s (rule %d, %s)'
                % (h['stored state'], '' if h['stored state'] == 1 else 'es', first['line'], first['text'],
                   first['rule'], first['entry']))
        if 'associated objects' in h:
            add("needs the owner's permission", 'associated objects')
        for hit in r.get('macro_hits', []):
            add('needs a design decision first', hit)
        if r['path'] in self.macro_class_files:
            add('class named by a macro', 'defines a class through a macro, or #includes a file that does')
        if r['objc_subclass_count']:
            add('classes with Objective-C subclasses', '%d Objective-C subclasses (%d outside scope)'
                % (r['objc_subclass_count'], r['objc_subclasses_outside_scope']))
        for cat in r['categories_implemented_elsewhere']:
            add('categories implemented in other files', cat)
        if r['foundation_categories']:
            add('foundation categories', 'categories on %s' % ', '.join(r['foundation_categories']))
        others = sorted(set(t['target'] for t in r['targets']) - set(MAIN_TARGETS))
        if others:
            add('built into other executables', 'also or only compiled by %s' % ', '.join(others))
        if not r['targets']:
            add('not compiled', 'compiled by no target of any project found (searched: %s)' % self.projects_text())
        if r['included_by']:
            add('included by another file', '#included by %s' % ', '.join(r['included_by']))
        return reasons

    def leaf(self, max_fan_in=2, max_reach=10):
        """Files of the leaf tier: offered, or deferred with the reasons.

        A file whose header has direct fan-in above max_fan_in or transitive
        reach above max_reach is outside the tier and only counted. Of the
        rest, a file is offered only when no rule in DEFERRED_LISTS applies; the
        others are deferred, in every list that applies.
        """
        candidates = []
        deferred = OrderedDict((name, []) for name in DEFERRED_LISTS)
        deferred_files = 0
        outside = OrderedDict([('direct fan-in above %d' % max_fan_in, 0),
                               ('transitive reach above %d' % max_reach, 0)])
        by_root = OrderedDict((root, OrderedDict([('offered', 0), ('deferred', 0), ('outside_thresholds', 0)]))
                              for root in SCOPE_ROOTS)
        for r in self.all_records():
            f = r['fan_in']
            fan = f['importers'] if f else 0
            reach = f['reach'] if f else 0
            counts = by_root[scope_root_of(r['path'])]
            if fan > max_fan_in:
                outside['direct fan-in above %d' % max_fan_in] += 1
                counts['outside_thresholds'] += 1
                continue
            if reach > max_reach:
                outside['transitive reach above %d' % max_reach] += 1
                counts['outside_thresholds'] += 1
                continue
            reasons = self.deferral_reasons(r)
            if reasons:
                deferred_files += 1
                counts['deferred'] += 1
                for name, details in reasons.items():
                    deferred[name].append(OrderedDict([('path', r['path']), ('details', details)]))
                continue
            address = []
            if r['arc'] == 'non-ARC':
                address.append('non-ARC')
            elif r['arc'] == 'mixed':
                address.append('ARC mixed across targets')
            f_prefix = f['prefix_header'] if f else None
            if f_prefix:
                address.append('header imported through the prefix header %s (by every file of %s)'
                               % (', '.join(f_prefix['via']), ', '.join(f_prefix['targets'])))
            if r['class_extensions_elsewhere']:
                address.append('class extensions in other files (%d)' % len(r['class_extensions_elsewhere']))
            if r['categories_declared_only']:
                address.append('categories declared in other files with no implementation found (%d, %d outside scope)'
                               % (len(r['categories_declared_only']), r['categories_declared_only_outside_scope']))
            if r['migration_state']['partially_ported']:
                address.append('partially ported')
            if r['objcxx']:
                address.append(r['objcxx']['class'])
            if r['swift_subclass_count']:
                address.append('Swift subclasses (%d)' % r['swift_subclass_count'])
            for name, n in r['hazards'].items():
                address.append(name if n == 1 else '%s (%d)' % (name, n))
            counts['offered'] += 1
            candidates.append(OrderedDict([('path', r['path']), ('targets', [t['target'] for t in r['targets']]),
                                           ('fan_in', fan),
                                           ('header_importers', f['header_importers'] if f else 0),
                                           ('reach', reach), ('has_header', f is not None),
                                           ('prefix_header', f['prefix_header'] if f else None),
                                           ('lines', r['lines']), ('arc', r['arc']),
                                           ('rr_sites', r['rr_sites']),
                                           ('swift_subclasses', r['swift_subclass_count']),
                                           ('hazards', r['hazards']),
                                           ('address', address)]))
        candidates.sort(key=lambda x: (x['reach'], x['fan_in'], x['lines'], x['path']))
        return OrderedDict([
            ('candidates', candidates),
            ('deferred', OrderedDict((name, OrderedDict([('reason', DEFERRED_LISTS[name][0]),
                                                         ('process', DEFERRED_LISTS[name][1]),
                                                         ('files', files)]))
                                     for name, files in deferred.items())),
            ('deferred_files', deferred_files),
            ('outside_thresholds', outside),
            ('by_scope_root', by_root),
            ('not_established', self.not_established()),
        ])

    def not_established(self):
        """What this tool could not determine anywhere in the tree, for every subcommand's output."""
        return OrderedDict([
            ('unresolved_class_name_sites', list(self.unresolved_class_sites)),
            ('dynamic_selector_sites', list(self.dynamic_selector_sites)),
            ('selector_site_forms', OrderedDict(SELECTOR_SITE_FORMS)),
            ('unparsed_xibs', list(self.xibs_unparsed)),
            ('missing_from_working_tree', list(self.missing_files)),
            ('fixed_statements', list(NOT_ESTABLISHED_FIXED)),
        ])

# ---------------------------------------------------------------------------
# Output

def table(rows, headers, max_width=None):
    cols = [str(h) for h in headers]
    data = [[('' if v is None else str(v)) for v in row] for row in rows]
    widths = [len(c) for c in cols]
    for row in data:
        for i, v in enumerate(row):
            widths[i] = max(widths[i], len(v))
    if max_width:
        widths = [min(w, max_width) for w in widths]
    lines = ['  '.join(c.ljust(widths[i]) for i, c in enumerate(cols)).rstrip(),
             '  '.join('-' * w for w in widths)]
    for row in data:
        lines.append('  '.join((v if len(v) <= widths[i] else v[:widths[i] - 1] + '~').ljust(widths[i])
                               for i, v in enumerate(row)).rstrip())
    return '\n'.join(lines)


HAZARD_CODES = OrderedDict([
    ('performSelector', 'PS'), ('makeObjectsPerformSelector', 'MOPS'),
    ('NSSelectorFromString', 'SFS'), ('NSStringFromSelector(variable)', 'NSFSv'),
    ('NSStringFromSelector(_cmd)', 'NSFSc'), ('NSStringFromSelector(@selector)', 'NSFSl'),
    ('NSClassFromString', 'CFS'),
    ('forwarding', 'FWD'), ('NSInvocation', 'INV'), ('respondsToSelector', 'RTS'),
    ('associated objects', 'ASSOC'), ('NSCoding', 'COD'), ('xib customClass', 'XIB'),
    ('sdef class', 'SDEF'), ('@synchronized', 'SYN'), ('@try', 'TRY'), ('+load/+initialize', 'LOAD'),
    ('atomics', 'ATOM'), ('macros', 'MAC'), ('objc_msgSend', 'MSG'), ('methodForSelector', 'MFS'),
    ('sort by selector', 'SORT'), ('selector registration', 'SELREG'),
    ('key-value coding/observing', 'KVC'), ('method replacement', 'SWZ'), ('method-list enumeration', 'MLIST'),
    ('runtime method lookup', 'RTL'), ('runtime class query', 'RTC'), ("xib File's Owner", 'XOWN'),
    ('xib binding', 'XBIND'), ('xib runtime attribute', 'XRTA'), ('xib not parsed', 'XNP'),
    ('First Responder action', 'FR'), ('methods named by convention', 'CONV'), ('ownership attribute', 'OWN'),
    ('imported outside scope', 'IMPOUT'), ('created by name', 'BYNAME'), ('NSStringFromClass', 'NSFC'),
    ('_cmd as a value', 'CMD'), ('control flow in a macro', 'CFMAC'), ('sdef method', 'SDEFM'), ('sdef key', 'SDEFK'), ('sendAction', 'SEND'),
    ('doesNotRecognizeSelector', 'DNR'), ('conformsToProtocol', 'CTP'), ('objectSpecifier', 'OSPEC'),
    ('lock', 'LOCK'), ('dispatch semaphore', 'SEM'), ('block dispatched to a queue', 'DISP'),
    ('iTerm2 concurrency helper', 'ITHR'), ('stored state', 'STORE'), ('thread created or started', 'THR'),
    ('NSThread subclass', 'NSTHR'),
])


def hazard_codes(hazards):
    known = [HAZARD_CODES[k] for k in HAZARD_CODES if k in hazards]
    return ' '.join(known + sorted(k for k in hazards if k not in HAZARD_CODES))


def fmt_fan(rec):
    f = rec['fan_in']
    if f is None:
        return '-'
    return '%d(%dh)/%d%s' % (f['importers'], f['header_importers'], f['reach'], 'p' if f['prefix_header'] else '')


def print_not_established(ne, path=None, all_sites=False, brief=False):
    """Prints what this tool could not determine.

    The selector sites are summarized by directory and by call, with where
    to find the full list; all_sites prints every one. With path, the sites
    in that file are printed in full first. brief prints only the counts.
    """
    print('Not established by this tool:')
    sites = ne['unresolved_class_name_sites']
    if sites:
        print('  %d calls create a class from a name known only at run time, and the classes they can reach could not '
              'be determined; any class may be one of them%s'
              % (len(sites), ' (leaf and file list them)' if brief else ': ' + ', '.join(sites)))
    sites = ne['dynamic_selector_sites']
    if sites:
        print('  %d sites in the tree dispatch or build a selector that this tool cannot see as a literal, so any '
              'method could be reached from them; what they reach is not determined here (the entry-point census, '
              'phase0.md section 2).' % len(sites))
        forms = ne['selector_site_forms']
        print('    Counted in Objective-C: %s.' % forms['Objective-C'])
        print('    Counted in Swift: %s.' % forms['Swift'])
        print('    No other form is counted, so the count is complete only for these forms.')
        if path is not None:
            mine = [x for x in sites if x.startswith(path + ':')]
            print('    In %s: %d%s' % (path, len(mine), ':' if mine else ''))
            for x in mine:
                print('      ' + x)
        if all_sites:
            print('    Every site:')
            for x in sites:
                print('      ' + x)
        elif not brief:
            by_dir, by_call = defaultdict(int), defaultdict(int)
            for x in sites:
                where, _, call = x.partition(': ')
                by_dir[os.path.dirname(where.rsplit(':', 1)[0]) or '.'] += 1
                by_call[call] += 1

            def counted(d):
                return ', '.join('%s %d' % kv for kv in sorted(d.items(), key=lambda kv: (-kv[1], kv[0])))
            print('    By directory: %s.' % counted(by_dir))
            print('    By call: %s.' % counted(by_call))
        print('    Every site is listed in the JSON output (not_established.dynamic_selector_sites) and by leaf '
              'and file with --all-sites.')
    if ne['missing_from_working_tree']:
        print('  %d tracked files that this tool would read are missing from the working tree and were not read, so '
              'nothing about them is established, and the relations and hazards that depend on them (subclasses, '
              'categories and extensions they declare, xib classes and connections, and the selector and class-name '
              'sites in them) could not be established: %s'
              % (len(ne['missing_from_working_tree']), ', '.join(ne['missing_from_working_tree'])))
    if ne['unparsed_xibs']:
        print('  %d xib files could not be parsed, so their connections and the classes they name were not checked: '
              '%s' % (len(ne['unparsed_xibs']), ', '.join(ne['unparsed_xibs'])))
    for line in ne['fixed_statements']:
        print('  ' + line)


def print_not_checked():
    print('Not checked by this tool:')
    for line in NOT_CHECKED:
        print('  ' + line)


def fmt_targets(rec):
    if not rec['targets']:
        return 'none'
    return ','.join(t['target'] + ('' if t['arc'] is True else (':noarc' if t['arc'] is False else ':mixed'))
                    + ('*' if t['per_file_flag'] else '') + ('^' if t.get('included_via') else '')
                    for t in rec['targets'])


def err(msg):
    sys.stderr.write(msg + '\n')


def print_warnings(warnings):
    for w in warnings:
        err('warning: %s' % w)


def print_summary(s):
    p = print
    p('Repository: %s' % s['root'])
    p('Scope (README.md section 2, widened by the owner on %s): the owner\'s own Objective-C, C and C++ compiled into '
      'the app or its helper programs, in files tracked by git under %s' % (s['scope']['widened'], scope_roots_text()))
    p('  Projects searched for targets: %s' % ', '.join(s['projects_searched']))
    p('  Excluded files: %s' % ', '.join('%s %d' % (k, v) for k, v in sorted(s['scope']['excluded'].items())))
    for reason, why in s['scope']['exclusion_rules'].items():
        files = [path for path, r in s['scope']['excluded_files'].items() if r == reason]
        if reason in ('test code', 'demo code', 'tool code'):
            continue
        p('    %s (%s)%s' % (reason, why, (': ' + ', '.join(files)) if files else ''))
    if s['scope']['non_product_code']:
        p('    Test, demo and tool code (not compiled into the app or its helper programs; never offered): %s'
          % ', '.join('%s (%s: %s)' % (path, r['category'], ', '.join(r['targets']))
                      for path, r in s['scope']['non_product_code'].items()))
        p('    %s' % s['scope']['non_product_rule'])
    p('  Not counted: %s' % s['scope']['not_counted'])
    p('  By scope directory:')
    rows = [[root + '/', v['implementation_files'], v['implementation_lines'], v['header_files'], v['header_lines'],
             v['swift_files'], ', '.join('%s %d' % kv for kv in v['excluded'].items()) or '-']
            for root, v in s['by_scope_root'].items()]
    rows.append(['total', s['implementation_files'], s['implementation_lines'], s['header_files'], s['header_lines'],
                 s['swift_files'], ', '.join('%s %d' % kv for kv in sorted(s['scope']['excluded'].items())) or '-'])
    for line in table(rows, ['directory', 'impl files', 'impl lines', 'headers', 'header lines', 'swift',
                             'excluded']).splitlines():
        p('    ' + line)
    p('  Implementation files: %d, %d lines' % (s['implementation_files'], s['implementation_lines']))
    for ext, v in s['by_extension'].items():
        p('    %-4s %5d files %8d lines' % (ext, v['files'], v['lines']))
    p('  Headers: %d, %d lines' % (s['header_files'], s['header_lines']))
    p('  Swift files in scope: %d' % s['swift_files'])
    rc = s['relations_computed_over']
    p('  Relations (subclasses, categories, extensions) computed over %s: %d in-scope files plus %d files '
      'outside scope that declare related classes' % (rc['rule'], rc['in_scope_files'],
                                                       rc['outside_scope_files_with_related_declarations']))
    p('')
    p('Targets (from %s; a target of another project is named <project>:<target>)' % ', '.join(s['projects_searched']))
    for name, t in s['targets'].items():
        if t['sources']:
            p('  %-30s ARC=%-5s sources=%-5d %s%s' % (name, t['arc'], t['sources'], t['arc_source'],
                                                     '' if t['category'] == 'product' else
                                                     '; %s (%s)' % (NON_PRODUCT_CATEGORIES[t['category']][0],
                                                                   t['product_type'])))
    p('  In-scope files compiled by %s (non-ARC), including files #included by one: %d, of which %d have '
      'retain/release sites (heuristic)'
      % (NON_ARC_TARGET, s['files_in_non_arc_target'], s['files_in_non_arc_target_with_rr_sites']))
    p('  Explicit retain/release/autorelease sites (heuristic): %d; [super dealloc]: %d'
      % (s['rr_sites_total'], s['super_dealloc_sites_total']))
    if s['textually_included_implementation_files']:
        p('  Implementation files #included by another file (they take its ARC setting): %s'
          % ', '.join(s['textually_included_implementation_files']))
    if s['not_compiled_by_any_target']:
        p('  Compiled by no target of any project found: %d (%s)' % (len(s['not_compiled_by_any_target']),
                                                    ', '.join(s['not_compiled_by_any_target'][:8]) +
                                                    (' ...' if len(s['not_compiled_by_any_target']) > 8 else '')))
    p('')
    p('Fan-in (heuristic; in-scope importers of the same-named header)')
    f = s['fan_in_le_2']
    p('  Header imported directly by 2 or fewer other files: %d files (%d with a header, %d without), %d lines'
      % (f['files'], f['with_header'], f['without_header'], f['lines']))
    p('  Same, not counting the bridging header as an importer: %d files'
      % s['fan_in_le_2_not_counting_bridging_header'])
    p('  Header reached, directly or through other headers, by 2 or fewer files: %d' % s['reach_le_2'])
    p('  Header imported by more than 50 files: %d' % s['fan_in_gt_50'])
    p('')
    p('Classes (heuristic)')
    p('  Implemented in scope: %d' % s['classes_implemented_in_scope'])
    p('  With Objective-C subclasses: %d (%d have one outside scope, such as in ModernTests); '
      'with Swift subclasses: %d; with Swift extensions in scope: %d'
      % (s['classes_with_objc_subclasses'], s['classes_with_objc_subclasses_outside_scope'],
         s['classes_with_swift_subclasses'], s['classes_with_swift_extensions']))
    p('')
    p('Objective-C++ files (class is heuristic; see objcxx.md)')
    for path, cls in s['objcxx'].items():
        p('  %-75s %s' % (path, cls))
    p('')
    pr = s['progress']
    p('Progress measures (README.md section 2)')
    p('  Lines of Objective-C, C and C++ in scope: %d' % pr['objc_c_cxx_lines'])
    wc = pr['wholly_conditional']
    p('    of which %d lines in %d implementation files are wholly under a preprocessor condition, which this tool '
      'does not evaluate (such a file may not be compiled)%s'
      % (wc['lines'], wc['files'], (': ' + ', '.join(wc['paths'])) if wc['paths'] else ''))
    p('  Objective-C files compiled without ARC in at least one target: %d' % pr['files_compiled_without_arc'])
    p('  null_unspecified: %d' % pr['null_unspecified'])
    p('  Files importing iTermStrictWarnings.h: %d' % pr['files_importing_iTermStrictWarnings_h'])
    for k, v in pr['markers'].items():
        p('  %s: %d in %d files' % (k, v['occurrences'], v['files']))
    p('  ivar_ accessor uses (heuristic, by the shapes in objc-state.md section 2): %d' % pr['ivar_accessor_uses'])
    hc = pr['helper_calls']
    p('  Checked-arithmetic helper calls (scaffolding, removed in stage two): %d in %d files (%s)'
      % (hc['calls'], hc['files'], ', '.join('%s %d' % kv for kv in hc['by_helper'].items())))
    p('  (marker, ivar_ and helper call counts cover files tracked by git outside submodules/, %s; '
      'helper calls also leave out %s)' %
      (' and '.join(MARKER_EXCLUDED_PATHS), ' and '.join(ARITHMETIC_HELPER_EXCLUDED_FILES)))
    p('')
    if s['files_with_incomplete_parse']:
        p('Files whose text parse is incomplete, so their hazards may be missing: %s'
          % ', '.join(s['files_with_incomplete_parse']))
        p('')
    hw = s['hazard_wrappers']['block_dispatch']
    p('Block-dispatching wrappers found in scope, whose calls count as a block dispatched to a queue (heuristic; the '
      'names are in the JSON output): %d keywords, %d functions, found in %d passes of at most %d'
      % (len(hw['keywords']), len(hw['functions']), hw['passes'], hw['max_passes']))
    p('')
    p('Migration history (%s): %d units with Swift-Port trailers' % (HISTORY_SCOPE, s['history']['units']))
    for prob in s['history']['trailer_problems']:
        p('  WARNING %s %s: %s' % (prob['commit'][:10], prob['problem'], prob['line']))
    p('')
    print_not_established(s['not_established'], brief=True)
    p('')
    p(reliability_help('summary'))


def print_files(records, total, not_established):
    rows = []
    for r in records:
        notes = (['cond'] if r['wholly_conditional'] else []) + (['parse?'] if r['parse_problems'] else [])
        rows.append([r['path'], r['lines'], fmt_targets(r), r['rr_sites'], fmt_fan(r),
                     '%d/%d' % (r['objc_subclass_count'], r['swift_subclass_count']),
                     r['swift_extension_count'], hazard_codes(r['hazards']),
                     (r['objcxx']['class'].split(' (')[0] if r['objcxx'] else ''), ','.join(notes)])
    print(table(rows, ['path', 'lines', 'targets', 'rr', 'fan-in/reach', 'subs o/s', 'swext', 'hazards', 'objc++',
                       'notes']))
    print('')
    print('Showing %d of %d files.' % (len(records), total) if len(records) < total else '%d files.' % total)
    print('targets: :noarc means compiled without ARC; * a per-file compiler flag; ^ inherited from the file '
          'that #includes it.')
    print('rr: retain/release/autorelease sites, not counting [super dealloc].')
    print('fan-in/reach: direct in-scope importers of the header (of which headers) / all in-scope files that reach '
          'it, directly or through other headers; - means no header; p: the count includes files that import the '
          'header only through a prefix header (GCC_PREFIX_HEADER), which every file of its target imports.')
    print('subs o/s: direct Objective-C / Swift subclasses anywhere outside submodules/.')
    print('swext: Swift extension blocks in scope of classes implemented here (partially ported).')
    print('notes: cond means every line of code is under one preprocessor condition (not evaluated; the file may not '
          'be compiled); parse? means the text parse is incomplete, so hazards may be missing (see file NAME).')
    print('hazards: ' + ', '.join('%s=%s' % (v, k) for k, v in HAZARD_CODES.items()) + '. An empty hazards '
          'column means only that the text searches found nothing.')
    print('')
    print_not_established(not_established, brief=True)
    print('')
    print(reliability_help('files'))


def print_file(rec, units, all_sites=False):
    p = print
    p('%s' % rec['path'])
    p('  lines: %d' % rec['lines'])
    if rec['targets']:
        for t in rec['targets']:
            p('  target %s: ARC %s (%s)' % (t['target'], t['arc'], t['arc_source']))
    else:
        p('  targets: none')
    if rec['included_by']:
        p('  textually included by: %s' % ', '.join(rec['included_by']))
    p('  migration state: %s, %s%s' % (rec['migration_state']['language'], rec['arc'],
                                       ', partially ported (Swift extensions of %s)' %
                                       ', '.join(rec['migration_state']['classes_with_swift_extensions'])
                                       if rec['migration_state']['partially_ported'] else ''))
    p('  retain/release/autorelease sites (heuristic): %d; [super dealloc]: %d'
      % (rec['rr_sites'], rec['super_dealloc_sites']))
    f = rec['fan_in']
    if f:
        prefix = f['prefix_header']
        p('  header: %s; imported directly by %d other in-scope files (%d headers)%s; reached by %d files in all '
          '(%d headers), directly or through other headers%s (heuristic)'
          % (f['header'], f['importers'], f['header_importers'],
             (', of which %d only through the prefix header %s (every file compiled by %s)'
              % (prefix['importers_only_through_it'], ', '.join(prefix['via']), ', '.join(prefix['targets'])))
             if prefix else '', f['reach'], f['reach_headers'],
             '; imported by the bridging header' if f['in_bridging_header'] else ''))
    else:
        p('  header: none found')
    p('  hot-path directory: %s' % ('yes (probable hot path; confirm)' if rec['hot_path_dir'] else
                                    'no (by directory only; per-character, per-cell, per-token or per-frame code '
                                    'outside those directories is not detected)'))
    wc = rec['wholly_conditional']
    if wc:
        p('  CONDITIONAL: every line of code (lines %d to %d) is under #if %s. This tool does not evaluate '
          'conditions, so the file may not be compiled at all.' % (wc['first_line'], wc['last_line'], wc['condition']))
    for problem in rec['parse_problems']:
        p('  WARNING parse incomplete, so hazards may be missing: %s' % problem)
    if rec['objcxx']:
        p('  Objective-C++ class (heuristic): %s' % rec['objcxx']['class'])
        p('    C++ markers in the file: %s' % (', '.join(rec['objcxx']['markers']) or 'none found by text'))
        for h, m in rec['objcxx']['header_markers'].items():
            p('    C++ markers in %s: %s' % (h, ', '.join(m)))
    if rec['categories_implemented']:
        p('  categories implemented here: %s' % ', '.join(rec['categories_implemented']))
    if rec['foundation_categories']:
        p('  foundation code (categories on system classes, plan.md tier 5): %s'
          % ', '.join(rec['foundation_categories']))
    mc = rec.get('method_check')
    if mc:
        p('  methods parsed: %d (crude count %d)' % (mc['parsed'], mc['crude_count']))
        for w in mc['warnings']:
            p('    WARNING %s' % w)
    p('  hazards (heuristic text matches):')
    if not rec['hazards']:
        p('    none detected by these text searches')
    lines = rec.get('hazard_lines', {})
    for k, v in rec['hazards'].items():
        p('    %-32s %d%s' % (k, v, ('  (line%s %s)' % ('s' if len(lines[k]) > 1 else '', ', '.join(str(n) for n in lines[k])))
                               if lines.get(k) else ''))
    for m in rec.get('stored_state', []):
        p('    stored state at line %d: %s (rule %d, %s: %s)' % (m['line'], m['text'], m['rule'], m['entry'], m['why']))
    for c in rec.get('dispatch_wrapper_calls', []):
        p('    block dispatched through a wrapper at line %d: %s (%s)' % (c['line'], c['wrapper'], c['defined_at']))
    for line in rec.get('atomic_properties', []):
        p('    atomic property: %s' % line)
    for line in rec.get('nscoding', []):
        p('    NSCoding: %s' % line)
    for cls, xibs in rec.get('xib', {}).items():
        p('    xib customClass %s: %s' % (cls, ', '.join(xibs)))
    for cls in rec.get('sdef', []):
        p('    named in %s: %s' % (SDEF_FILE, cls))
    for line in rec.get('macro_hits', []):
        p('    macro: %s' % line)
    for line in rec.get('ownership_attributes', []):
        p('    ownership attribute: %s' % line)
    for line in rec.get('ownership_transferring_methods', []):
        p('    ownership-transferring method name: %s' % line)
    for line in rec.get('control_flow_macros', []):
        p('    uses a macro that can return, break, continue or jump: %s' % line)
    for path in rec.get('imported_outside_scope', []):
        p('    header imported outside scope by: %s' % path)
    if rec.get('created_by_name'):
        p('    created by name (an over-approximation: each isSubclassOfClass:, conformsToProtocol: and '
          'instancesRespondToSelector: check after the call is treated alone, as if the checks were combined with '
          'OR, and is not tied to the variable that holds the class):')
    for line in rec.get('created_by_name', []):
        p('      %s' % line)
    for sym in rec.get('c_symbols_in_headers', []):
        p('    C %s %s (line %d) is named in %s; Objective-C cannot call a Swift free function or see a Swift-only '
          'global' % (sym['kind'], sym['name'], sym['line'], ', '.join(sym['declared_in'])))
    for cat in rec.get('categories_implemented_elsewhere', []):
        p('    category implemented in another file: %s' % cat)
    for cat in rec.get('categories_declared_only', []):
        p('    category declared in another file with no implementation found: %s' % cat)
    for c in rec.get('xib_connections', []):
        refs = c['references']
        p('    xib %s, %s: %s' % (c['xib'], c['object'], 'not parsed, so connections are unknown' if refs is None else
                                ', '.join('%d %s' % (v, k.replace('_', ' ')) for k, v in refs.items())))
    if rec.get('methods_named_by_convention'):
        p('    methods named by convention: %s' % ', '.join(rec['methods_named_by_convention']))
    for sel, xibs in rec.get('first_responder_actions', {}).items():
        p('    First Responder action %s in %s' % (sel, ', '.join(xibs)))
    deferral = rec.get('deferral')
    if deferral is not None:
        if deferral:
            p('  leaf: not offered, whatever its fan-in and reach:')
            for name, details in deferral.items():
                p('    %s: %s' % (name, '; '.join(details)))
        else:
            p('  leaf: none of the deferral rules applies (they are built from the heuristic fields above); leaf '
              'offers it if it is within the fan-in and reach limits')

    def loc(x):
        return '%s (%s%s)' % (x['name'], x['where'], '' if x['in_scope'] else ', outside scope')

    for cls, rel in rec.get('relations', {}).items():
        p('  class %s : %s' % (cls, rel['superclass'] or '?'))
        p('    Objective-C subclasses: %s' % (', '.join(loc(x) for x in rel['objc_subclasses']) or 'none found'))
        p('    Swift subclasses: %s' % (', '.join(loc(x) for x in rel['swift_subclasses']) or 'none found'))
        p('    class extensions: %s' % (', '.join(rel['class_extensions']) or 'none found'))
        p('    categories: %s' % (', '.join('%s (%s, %s%s)' % (c['category'], c['kind'], c['where'],
                                                              '' if c['in_scope'] else ', outside scope')
                                           for c in rel['categories']) or 'none found'))
        p('    Swift extensions in scope (%d): %s' % (len(rel['swift_extensions']),
                                                      ', '.join(rel['swift_extensions']) or 'none found'))
        if rel['swift_extensions_outside_scope']:
            p('    Swift extensions outside scope: %s' % ', '.join(rel['swift_extensions_outside_scope']))
    p('  migration history (%s; units named after the file or its classes):' % HISTORY_SCOPE)
    if not units:
        p('    none')
    for name, u in units.items():
        p('    %s: %s, last %s' % (name, ', '.join('%s x%d' % kv for kv in u['kinds'].items()), u['last_date']))
    p('')
    print_not_established(rec['not_established'], path=rec['path'], all_sites=all_sites)
    p('')
    print_not_checked()
    p('')
    p(reliability_help('file'))


def print_history(units, problems, unit=None, elsewhere=0):
    print('Swift-Port trailers in %s, as git reads them' % HISTORY_SCOPE)
    rows = [[name, ', '.join('%s x%d' % kv for kv in u['kinds'].items()), u['first_date'], u['last_date'],
             len(u['commits'])] for name, u in units.items()]
    if rows:
        print(table(rows, ['unit', 'kinds', 'first', 'last', 'commits']))
    elif unit:
        print('No Swift-Port trailers for unit %s.' % unit)
    else:
        print('No Swift-Port trailers found.')
    for prob in problems:
        print('WARNING %s %s: %s' % (prob['commit'][:10], prob['problem'], prob['line']))
    if unit:
        print('%d trailer problems for other units (history without a unit lists them).' % elsewhere)


def print_leaf(result, max_fan_in, max_reach, shown, show_deferred, all_sites=False):
    rows = result['candidates'][:shown]
    print('Offered: %d files of the leaf tier (direct fan-in <= %d, transitive reach <= %d) that no rule below '
          'defers, ordered by reach, fan-in, then lines.%s'
          % (len(result['candidates']), max_fan_in, max_reach,
             '' if shown >= len(result['candidates']) else ' Showing %d of %d.' % (len(rows), len(result['candidates']))))
    if rows:
        print(table([[r['path'], ','.join(r['targets']),
                      ('%d%s' % (r['fan_in'], 'p' if r['prefix_header'] else '')) if r['has_header'] else '-',
                      r['header_importers'], r['reach'], r['lines'], r['arc'], r['rr_sites'],
                      '; '.join(r['address']) or 'nothing detected'] for r in rows],
                    ['path', 'targets', 'fan-in', 'hdr', 'reach', 'lines', 'arc', 'rr', 'the dossier must address']))
    print('Each offered file still needs its full dossier. The last column lists the hazards this tool detects '
          'in it by the text searches defined in inventory.py (HAZARD_PATTERNS and Inventory.file_record); it is not '
          'everything the dossier must cover '
          '(see "Not checked by this tool" below), and "nothing detected" means only that those searches found '
          'nothing. fan-in: direct in-scope importers of the header, - when the file has no header, p when it '
          'counts files that import the header only through a prefix header. hdr: headers among the direct '
          'importers (a header cannot import the generated Swift header, so each needs a forward declaration).')
    print('')
    counts = [(name, len(d['files'])) for name, d in result['deferred'].items() if d['files']]
    print('Deferred: %d files of the leaf tier are not offered. A file is in every list that applies:'
          % result['deferred_files'])
    for name, n in counts:
        d = result['deferred'][name]
        print('  %s (%d): %s [%s]' % (name, n, d['reason'], d['process']))
        if show_deferred:
            for f in d['files']:
                print('    %s: %s' % (f['path'], '; '.join(f['details'])))
    if counts and not show_deferred:
        print('  (--deferred lists the files in each.)')
    print('Outside the leaf tier: %s.' % ', '.join('%d with %s' % (v, k) for k, v in result['outside_thresholds'].items()))
    print('By scope directory (offered, deferred, outside the tier): %s.'
          % '; '.join('%s/ %d, %d, %d' % (root, c['offered'], c['deferred'], c['outside_thresholds'])
                      for root, c in result['by_scope_root'].items()))
    print('')
    print_not_established(result['not_established'], all_sites=all_sites)
    print('')
    print_not_checked()
    print('')
    print(reliability_help('leaf'))


# ---------------------------------------------------------------------------
# Command line

SUBCOMMAND_NOTES = {
    'summary': 'The scope and the date it was widened, the projects searched, totals and counts for each scope '
               'directory, every excluded file with its reason (test, demo and tool code included), totals by '
               'extension and target, fan-in and reach counts, class relation counts, the Objective-C++ classes, and '
               'the README section 2 progress measures.',
    'files': 'One row per in-scope .m, .mm and .c file: lines, targets and ARC, retain/release sites, fan-in and '
             'reach, subclasses, Swift extensions, hazard codes (legend printed after the table).',
    'file': 'Everything this tool finds for one file, including where each subclass, category and extension is, the '
            'ARC source per target, the methods the parser found against a cruder count, and history, followed by '
            'what it could not establish and what it does not check.',
    'history': 'Swift-Port trailers in commits reachable from HEAD, as git reads them, counted once per unit and '
               'kind in each commit, and only for the kinds in README.md section 5. Malformed values, unknown kinds, '
               'non-canonical spellings, and lines that look like a trailer but that git does not read as one, are '
               'reported. Exit status 1 when the unit asked for has no trailers.',
    'leaf': 'The leaf tier is the files whose header has direct fan-in <= --max-fan-in and transitive reach <= '
            '--max-reach. Of those, a file is offered only if no deferral rule applies; offered files are ordered by '
            'reach, fan-in and size, and each shows the hazards this tool detects in it by its text searches, which '
            'is not everything its dossier must cover. The other files are counted in named lists (wholly '
            'conditional, incomplete parse, probable hot path, giant classes, must stay in Objective-C for now, '
            'stays in C: atomics, defines C functions or globals declared in a header, needs the owner\'s '
            'permission, needs a design decision first, class named by a macro, classes with Objective-C '
            'subclasses (Objective-C cannot subclass Swift), categories implemented in other files, foundation '
            'categories, built into other executables (compiled by other targets than %s, in any project), not '
            'compiled (by no target of any project found), included by another file, encodes or decodes stored '
            'state), each with '
            'its reason and the process file that says so, or says that no process rule covers it yet; --deferred '
            'lists their files. What the tool could not establish, and what it does not '
            'check, are printed last, after the offered, deferred and outside-the-tier counts for each scope '
            'directory.' % ' and '.join(MAIN_TARGETS),
}

# Subcommands provided by other modules in this directory, in the order they
# appear in --help, with the core subcommand each follows. Each module defines
# SUBCOMMAND, HELP, NOTES, RELIABILITY (field -> (reliability, why)),
# MODE_FIELDS (the fields its output carries), add_arguments(parser) and
# run(args). A module that cannot be imported leaves its subcommand registered
# but unavailable, with the reason.
OPTIONAL_SUBCOMMANDS = (('state', 'inventory_state', 'file'), ('verify', 'inventory_verify', 'leaf'))


def optional_subcommands():
    """Maps each optional subcommand to its module, or to the reason it cannot be imported.

    The bytecode cache is turned off first, so that importing them writes no
    __pycache__ directory.
    """
    sys.dont_write_bytecode = True
    found = OrderedDict()
    for name, module_name, _ in OPTIONAL_SUBCOMMANDS:
        try:
            module = importlib.import_module(module_name)
        except ImportError as e:
            found[name] = 'the %s subcommand is not available: %s.py could not be imported (%s)' % (
                name, module_name, e)
            continue
        RELIABILITY.update(module.RELIABILITY)
        MODE_FIELDS[name] = list(module.MODE_FIELDS)
        SUBCOMMAND_NOTES[name] = module.NOTES
        found[name] = module
    return found


def positive_int(text):
    try:
        n = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError('%r is not an integer' % text)
    if n < 1:
        raise argparse.ArgumentTypeError('must be at least 1, not %d' % n)
    return n


def non_negative_int(text):
    try:
        n = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError('%r is not an integer' % text)
    if n < 0:
        raise argparse.ArgumentTypeError('must not be negative, not %d' % n)
    return n


def build_parser(optional=None):
    if optional is None:
        optional = optional_subcommands()
    parser = argparse.ArgumentParser(
        prog='inventory.py',
        epilog=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='Inventory of Objective-C, C and C++ for the Swift migration. Works from the root of the '
                    'git repository containing the current directory (or --root). Nothing is stored; '
                    'everything is recomputed. Results marked heuristic come from text matching, as described '
                    'below. Any failure exits non-zero with a message on stderr.')
    parser.add_argument('--json', action='store_true', help='machine-readable output, with a reliability map')
    parser.add_argument('--root', default='.', help='any directory inside the repository (default: current)')
    sub = parser.add_subparsers(dest='command')

    def add(name, help_text):
        sp = sub.add_parser(name, help=help_text,
                            description='%s. %s %s' % (help_text, SUBCOMMAND_NOTES[name], reliability_help(name)))
        sp.add_argument('--json', action='store_true', default=argparse.SUPPRESS)
        return sp

    def add_optional(after):
        for name, module_name, follows in OPTIONAL_SUBCOMMANDS:
            if follows != after:
                continue
            module = optional[name]
            if isinstance(module, str):
                sp = sub.add_parser(name, help='not available (%s.py could not be imported)' % module_name,
                                    description=module)
                sp.add_argument('rest', nargs=argparse.REMAINDER, help=argparse.SUPPRESS)
            else:
                module.add_arguments(add(name, module.HELP))

    add('summary', 'Progress measures and totals (default)')
    f = add('files', 'One row per implementation file')
    f.add_argument('--sort', choices=['path', 'lines', 'fanin', 'reach', 'rr'], default='path')
    f.add_argument('--filter', default=None, help='only paths containing this substring')
    f.add_argument('--limit', type=positive_int, default=None, help='show at most this many rows (at least 1)')
    d = add('file', 'Details for one implementation file')
    d.add_argument('name', help='path, file name, stem, or class name')
    d.add_argument('--all-sites', action='store_true', help='list every selector site in the tree under '
                   '"Not established", not only those in this file')
    add_optional('file')
    h = add('history', 'Swift-Port trailers per unit')
    h.add_argument('unit', nargs='?', default=None, help='only this unit; exit status 1 if it has no trailers')
    l = add('leaf', 'Candidate units for the leaf tier')
    l.add_argument('--max-fan-in', type=non_negative_int, default=2,
                   help='largest number of in-scope files importing the header directly (default 2)')
    l.add_argument('--max-reach', type=non_negative_int, default=10,
                   help='largest number of files reaching the header, directly or through other headers (default 10)')
    l.add_argument('--limit', type=positive_int, default=None,
                   help='show at most this many candidates (at least 1); the total is always printed')
    l.add_argument('--deferred', action='store_true',
                   help='also list the files in each deferred list, with the reasons')
    l.add_argument('--all-sites', action='store_true', help='list every selector site in the tree under '
                   '"Not established", not only the counts')
    add_optional('leaf')
    return parser


def emit_json(obj):
    def default(o):
        if isinstance(o, set):
            return sorted(o)
        raise TypeError(repr(o))
    json.dump(obj, sys.stdout, indent=2, default=default)
    sys.stdout.write('\n')


def run(args, optional=None):
    command = args.command or 'summary'
    if optional and command in optional:
        module = optional[command]
        if isinstance(module, str):
            raise InventoryError(module)
        return module.run(args)
    if command == 'history':
        root = find_repo_root(os.path.abspath(args.root))
        units, problems = history_from_git(root)
        elsewhere = 0
        if args.unit:
            units = OrderedDict((k, v) for k, v in units.items() if k == args.unit)
            own = [p for p in problems if trailer_problem_unit(p) == args.unit]
            elsewhere = len(problems) - len(own)
            problems = own
        if args.json:
            emit_json(OrderedDict([('scope', HISTORY_SCOPE), ('units', units), ('problems', problems),
                                   ('problems_elsewhere', elsewhere), ('reliability', reliability_for('history'))]))
        else:
            print_history(units, problems, args.unit, elsewhere)
        # A unit with no trailers is reported as a failure to find it.
        return 1 if args.unit and not units else 0
    inv = Inventory(args.root)
    if command == 'summary':
        s = inv.summary()
        s['not_established'] = inv.not_established()
        s['warnings'] = inv.warnings
        s['reliability'] = reliability_for('summary')
        emit_json(s) if args.json else print_summary(s)
    elif command == 'files':
        records = inv.all_records()
        if args.filter:
            records = [r for r in records if args.filter in r['path']]
        key = {'path': lambda r: r['path'], 'lines': lambda r: -r['lines'],
               'rr': lambda r: -r['rr_sites'],
               'fanin': lambda r: -(r['fan_in']['importers'] if r['fan_in'] else -1),
               'reach': lambda r: -(r['fan_in']['reach'] if r['fan_in'] else -1)}[args.sort]
        records.sort(key=key)
        total = len(records)
        if args.limit:
            records = records[:args.limit]
        if args.json:
            emit_json(OrderedDict([('total', total), ('shown', len(records)), ('files', records),
                                   ('not_established', inv.not_established()),
                                   ('warnings', inv.warnings), ('reliability', reliability_for('files'))]))
        else:
            print_files(records, total, inv.not_established())
    elif command == 'file':
        path = inv.resolve(args.name)
        rec = inv.file_record(path, detail=True)
        rec['deferral'] = inv.deferral_reasons(rec)
        all_units, _ = inv.history()
        names = {os.path.splitext(os.path.basename(path))[0]} | set(rec['classes'])
        units = OrderedDict((k, v) for k, v in all_units.items() if k in names)
        rec['history'] = units
        rec['not_established'] = inv.not_established()
        rec['not_checked'] = list(NOT_CHECKED)
        if args.json:
            rec['warnings'] = inv.warnings
            rec['reliability'] = reliability_for('file')
            emit_json(rec)
        else:
            print_file(rec, units, args.all_sites)
    elif command == 'leaf':
        result = inv.leaf(max_fan_in=args.max_fan_in, max_reach=args.max_reach)
        total = len(result['candidates'])
        shown = min(total, args.limit) if args.limit else total
        if args.json:
            deferred = OrderedDict((name, d if args.deferred else OrderedDict(
                [('reason', d['reason']), ('process', d['process']), ('count', len(d['files']))]))
                for name, d in result['deferred'].items())
            emit_json(OrderedDict([('thresholds', {'max_fan_in': args.max_fan_in, 'max_reach': args.max_reach}),
                                   ('candidates_total', total), ('candidates_shown', shown),
                                   ('candidates', result['candidates'][:shown]),
                                   ('deferred_files', result['deferred_files']), ('deferred', deferred),
                                   ('outside_thresholds', result['outside_thresholds']),
                                   ('by_scope_root', result['by_scope_root']),
                                   ('not_established', result['not_established']),
                                   ('not_checked', list(NOT_CHECKED)),
                                   ('warnings', inv.warnings), ('reliability', reliability_for('leaf'))]))
        else:
            print_leaf(result, args.max_fan_in, args.max_reach, shown, args.deferred, args.all_sites)
    print_warnings(inv.warnings)
    return 0


def main(argv=None):
    optional = optional_subcommands()
    args = build_parser(optional).parse_args(argv)
    try:
        return run(args, optional)
    except InventoryError as e:
        err('inventory.py: error: %s' % e)
        return 2


if __name__ == '__main__':
    # The optional subcommand modules import this file as `inventory`; make that
    # name refer to this module rather than load a second copy of it.
    sys.modules.setdefault('inventory', sys.modules[__name__])
    try:
        sys.exit(main())
    except BrokenPipeError:
        # Output piped to head or similar; not an error.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
