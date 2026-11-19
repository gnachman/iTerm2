#!/usr/bin/env python3
"""Type-aware lints for migration Swift, on the Swift compiler's AST
(docs/swift-migration/phase0.md, section 6).

Part of the Objective-C to Swift migration. The token lints
(swift_lints.py) stay the fast check on a staged change; these lints run
alongside them, for the rules that need types (owner-queue.md Q20 items 2
and 6, answered 2026-11-20). They read the JSON AST the compiler dumps
(-dump-ast -dump-ast-format json) through a streaming reader,
codedb/swiftreader/swift_ast_facts.cpp, which prints one line per node the
lints need; this script turns those into findings.

THE LINTS

  unsafe-pointer-arg-unmarked
      An argument the compiler converts implicitly to an unsafe pointer:
      &x to an Unsafe(Mutable)(Raw)Pointer or AutoreleasingUnsafeMutablePointer
      parameter (inout_to_pointer), an array or &array (array_to_pointer), a
      string (string_to_pointer). It needs "// SWIFT-MIGRATION-UNSAFE(hot):
      <reason>" or "// SWIFT-MIGRATION-SHIM: <reason>" on the line above, with
      exactly the placement swift_lints.py accepts for unsafe-pointer-unmarked
      (a marker comment, alone or at the end of a line, covers the line below
      it; a marker at the end of the converting line does not cover that
      line). translation-rules.md section 8; owner-queue.md Q20 item 6.
  iuo-objc-implicit-unwrap
      A value of an implicitly unwrapped type that the compiler force-unwraps
      implicitly (force_value_expr with implicit_iuo_unwrap), where the
      unwrapped expression refers to a declaration imported from Objective-C
      or C (its USR begins with "c:" but not with "c:@M@" or "c:@CM@", which
      mark a declaration written in Swift and exposed to Objective-C): a
      property, a method or function result. Bind it first (if let, guard let, ?. with a default, or ??).
      phase0.md section 6 ("Use of an implicitly unwrapped value from
      Objective-C without binding it first"); nullability.md section 4.
      The same implicit force of a value declared in Swift (an implicitly
      unwrapped property, parameter or local, which translation-rules.md
      section 7 allows or marks) is listed as a note, not a finding.
  integer-arithmetic
      A binary +, -, * or <<, a unary -, or a compound +=, -=, *= or <<=, of
      the standard library, on a fixed-width integer type (Int, UInt, Int8 to
      Int128, UInt8 to UInt128, whatever typealias names it), unless every
      operand is an integer literal (overflow there is a compile-time error)
      or a "// bounded-by-type: <reason>" comment covers the line (at the end
      of the line, or alone on the line above). Use the helpers (phase0.md
      section 7) or, where wrapping is relied on, &+, &-, &*, &<<.
      translation-rules.md section 1; phase0.md section 6. The compound
      assignments are included because they are the same operators.
  integer-init-nonliteral
      A call of an unlabeled initializer of a fixed-width integer type with
      one argument of a fixed-width integer or floating-point type that is
      not a literal: Int(d), Int32(n), UInt8(x), Int16(x) through .init(x),
      whether or not it can trap. Use numericCast, init(truncatingIfNeeded:),
      init(bitPattern:), init(exactly:), init(clamping:) or the helpers.
      phase0.md section 6; translation-rules.md section 1.

  Not reported, by design: anything inside a macro expansion (the code is
  not written in the file; counted under "skipped"), and nodes without a
  source range (code the compiler synthesizes; counted by the reader).
  Duplicates of one site (the dump repeats some expressions) are reported
  once.

WHICH FILES

  The same as swift_lints.py, by its own selection code (swift_lints.select),
  in the same modes: tree mode (every migration file at HEAD), --staged with
  --message or --not-a-port, REV, and --all-swift (a survey). Ported lines in
  files that are not migration files are linted by lines, as there. --paths
  lints the named files whole (a survey, for calibration).

  The AST is compiled from the working tree. A file whose content in the
  inspected source (the index for --staged, the commit for REV) differs from
  the working tree is incomplete, not linted.

HOW THE AST IS OBTAINED

  From the compile commands the code database captured after an app build
  (tmp/codedb/cdb-fragments/swift/: drivers.jsonl and each module's file
  list; see codedb/swiftdb.py), read only. For each module that holds a
  selected file, the captured driver command is translated as swiftdb.py
  translates it (no build products, a private module cache), the compiler's
  driver prints the frontend job (-driver-print-jobs), and one frontend
  process dumps only the selected files as primary files, with the rest of
  the module as secondary inputs. The reader runs that process under
  codedb/guard.sh (a memory cap) in its own process group with a time limit.

COMPLETENESS

  A selected file is incomplete, and is listed with the reason, when: there
  is no capture; it is in no captured module's file list (a file added since
  the capture: capture again); its content differs from the working tree;
  the compiler is not the version the reader was written against; the
  compiler exits with an error (a module with an error has no trustworthy
  AST, so every file of that job is incomplete); the job runs out of time or
  memory; the dump has no document for it; or the token lexer of
  swift_lints.py cannot read it (the markers are found with it). Any
  incomplete file makes the exit status 3, never 0.

Exit status: 0 no findings; 1 findings (including findings on ported
lines); 2 usage or environment error (as swift_lints.py, including a reader
that cannot be built); 3 incomplete (some selected file could not be
linted), which takes precedence over 1. Python 3 standard library; the
reader needs RapidJSON's headers to build (codedb/swiftreader/build.sh).
Writes only under its work directory (default tmp/swift_ast_lints/).
"""

import argparse
import bisect
import collections
import hashlib
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
from collections import OrderedDict, namedtuple

sys.dont_write_bytecode = True
TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.path.join(TOOL_DIR, 'codedb')
for _d in (TOOL_DIR, CODEDB_DIR):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import swift_lints as sl  # noqa: E402  (selection, the lexer and the marker rules)
import swiftdb  # noqa: E402  (read only: the capture, command translation, the frontend job)

READER_DIR = os.path.join(CODEDB_DIR, 'swiftreader')
READER_BUILD_SCRIPT = os.path.join(READER_DIR, 'build_ast_facts.sh')
# The files whose digest is the reader's version, in the order build_ast_facts.sh lists them to shasum.
READER_SOURCE_NAMES = ('build_ast_facts.sh', 'swift_ast_facts.cpp', 'dump_format.h')
GUARD = os.path.join(CODEDB_DIR, 'guard.sh')

EXIT_CLEAN = 0
EXIT_FINDINGS = 1
EXIT_ERROR = 2
EXIT_INCOMPLETE = 3

# Defaults for one frontend job: the memory cap of the compiler and the reader together (codedb's
# GUARD_LIMIT_KB), and the time limit.
DEFAULT_LIMIT_KB = 6000000
DEFAULT_TIMEOUT = 1800


def _written_against():
    with open(os.path.join(READER_DIR, 'dump_format.h'), encoding='utf-8') as f:
        m = re.search(r'kWrittenAgainst = "([0-9.]+)"', f.read())
    return m.group(1) if m else None


# The compiler version (major.minor) whose dump format the reader was written against.
WRITTEN_AGAINST = _written_against()

LINTS = OrderedDict([
    ('unsafe-pointer-arg-unmarked',
     'translation-rules.md section 8; owner-queue.md Q20 item 6: an argument converted implicitly to an unsafe '
     'pointer (&x, an array or &array, a string) needs "// SWIFT-MIGRATION-UNSAFE(hot): <reason>" or '
     '"// SWIFT-MIGRATION-SHIM: <reason>" on the line above, placed as swift_lints.py requires'),
    ('iuo-objc-implicit-unwrap',
     'phase0.md section 6; nullability.md section 4: an implicitly unwrapped value from Objective-C or C used '
     'without binding it first (the compiler force-unwraps it)'),
    ('integer-arithmetic',
     'phase0.md section 6; translation-rules.md section 1: plain +, -, *, <<, unary - (or +=, -=, *=, <<=) on a '
     'fixed-width integer without a helper or "// bounded-by-type: <reason>"'),
    ('integer-init-nonliteral',
     'phase0.md section 6; translation-rules.md section 1: an integer initializer applied to a non-literal integer or '
     'floating-point value; use numericCast, init(truncatingIfNeeded:), init(bitPattern:), init(exactly:), '
     'init(clamping:) or the helpers'),
])

# Every row of swift_lints.NOT_CHECKED, and the rules of translation-rules.md that a lint could check, with what
# this tool does about it: 'implemented' (a lint above), 'from the dump' (the dump has the facts; not built in
# this unit), 'needs facts the dump lacks', or 'review' (a question of meaning).
CLASSIFICATION = [
    ('Integer initializer applied to a non-literal', 'implemented', 'integer-init-nonliteral'),
    ('Plain +, -, *, unary - or << on a fixed-width integer without a helper or "// bounded-by-type:"',
     'implemented', 'integer-arithmetic (also +=, -=, *=, <<=)'),
    ('&x (or an array or string) passed to a pointer parameter needs the unsafe marker', 'implemented',
     'unsafe-pointer-arg-unmarked'),
    ('Use of an implicitly unwrapped value from Objective-C without binding it first', 'implemented',
     'iuo-objc-implicit-unwrap; the same for Swift declarations is a note'),
    ('An optional or implicitly unwrapped identifier passed to objc_sync_enter', 'from the dump',
     'the argument of the call of c:@F@objc_sync_enter is an erasure_expr whose operand type is Optional; a '
     'follow-up unit'),
    ('The lock constant is a let of non-optional type AnyObject', 'from the dump',
     'the declref_expr of the argument names a var_decl whose "let" flag and interface_type are in the dump; needs '
     'declarations matched to uses by USR within the file (locals have no USR: needs the declaration\'s range)'),
    ('os_unfair_lock or pthread_mutex_t stored property whose type is inferred', 'from the dump',
     'the var_decl\'s interface_type is the inferred type; a follow-up unit'),
    ('URL, Date, Data, IndexSet, Calendar or Locale where the Objective-C used the NS class',
     'needs facts the dump lacks', 'the Objective-C original; the dump has only the Swift'),
    ('NSNumber as? Int and similar bridging casts', 'from the dump',
     'conditional_checked_cast_expr whose operand type is NSNumber (or Any holding one: not decidable) and whose '
     'target is a numeric or Bool type; the Any case needs data flow'),
    ('== between Strings that came from NSString on data that can be non-ASCII', 'review',
     'where the value came from is data flow, and whether the data can be non-ASCII is a question of meaning'),
    ('New uses of the runtime APIs outside the registered sites', 'needs facts the dump lacks',
     'a separate Phase 0 item over all languages'),
    ('New macros of the classified kinds', 'needs facts the dump lacks', 'Objective-C macros, not Swift'),
    ('A type of the file\'s own named Task used as the standard Task', 'from the dump',
     'the decl_usr of each reference to Task says whether it is the standard library\'s (s:ScT...) or the file\'s; '
     'would remove the token lint\'s false findings, but cannot remove them from its output'),
    ('Stage-one versus stage-two files', 'needs facts the dump lacks',
     'the stage-two marker is checked against the code database, a separate unit'),
    ('@objc(OriginalName), @objc selectors, @objc dynamic', 'needs facts the dump lacks',
     'the Objective-C original and the census'),
    ('Captured locals that are var and were not __block go in a capture list', 'needs facts the dump lacks',
     'the Objective-C original (the dump has the captures: captured_value)'),
    ('@unknown default in a switch over an imported NS_ENUM', 'from the dump',
     'the compiler warns; the switch_stmt\'s subject type and its case_stmt kinds are in the dump'),
    ('Division and modulo by a non-constant get a zero check', 'needs facts the dump lacks',
     'the operator and operand types are in the dump, but whether a zero check precedes it is data flow; could '
     'list every integer / and % by a non-literal for review'),
    ('No assertion in a per-character, per-cell or per-token loop', 'review', 'a question of meaning'),
    ('Strong outlets stay strong; outlets keep their names', 'needs facts the dump lacks', 'the Objective-C original'),
    ('A nonnull parameter with Objective-C callers is optional in Swift and guarded', 'needs facts the dump lacks',
     'the header and the census'),
    ('Capture semantics and weak back-pointers are ported exactly', 'needs facts the dump lacks',
     'the Objective-C original'),
    ('A file-scope let constant', 'review', 'allowed (decisions.md, 2026-11-20); nothing to check'),
    ('An implicitly unwrapped property other than an outlet is listed in the commit message', 'review',
     'a property of the commit message'),
    ('A SWIFT-MIGRATION-IUO site is removed once it is no longer needed', 'review', 'a question of meaning'),
    ('The rule for which files are migration files', 'review', 'provisional until the pilot; shared with '
     'swift_lints.py'),
    ('A SWIFT-MIGRATION-UNSAFE(hot) marker names the measurement that justifies it', 'review',
     'a question of meaning'),
    ('A port of a function over about 150 lines carries an Oversize-Port trailer', 'review',
     'a commit requirement (function sizes are in the dump: the func_decl range)'),
    ('Methods called off the main thread in AppKit subclasses are nonisolated', 'needs facts the dump lacks',
     'the dossier\'s thread table'),
    ('Atomic properties, lazy var, queue affinity and run loop modes are ported faithfully',
     'needs facts the dump lacks', 'the dossier and the Objective-C original'),
    ('Raw ivar accessors are named ivar_foo and never interchanged with self.foo', 'needs facts the dump lacks',
     'the dossier\'s ivar table'),
    ('Banned trap calls (fatalError, assert, precondition, ...) resolved by declaration', 'from the dump',
     'the decl_usr of the callee says whether it is the standard library\'s; refines trap-call, which stays a '
     'token lint'),
    ('Unsigned subtraction that can wrap (count - 1 on an empty collection)', 'implemented',
     'part of integer-arithmetic: every - on an unsigned fixed-width type is reported'),
    ('Small-type promotion (uint8_t + uint8_t)', 'implemented', 'part of integer-arithmetic'),
    ('Float to integer conversion (Int(d) traps on NaN, infinity, out of range)', 'implemented',
     'part of integer-init-nonliteral'),
    ('Forming a range a..<b with a > b; removeFirst on an empty collection; Dictionary(uniqueKeysWithValues:); '
     'stride with a zero step', 'review', 'the calls are in the dump, but whether they can trap depends on values'),
    ('Overlapping access through inout or mutating calls that re-enter', 'needs facts the dump lacks',
     'the dossier\'s re-entrancy notes'),
]

INTEGER_TYPES = {
    '$sSiD': 'Int', '$sSuD': 'UInt', '$ss4Int8VD': 'Int8', '$ss5Int16VD': 'Int16', '$ss5Int32VD': 'Int32',
    '$ss5Int64VD': 'Int64', '$ss6Int128VD': 'Int128', '$ss5UInt8VD': 'UInt8', '$ss6UInt16VD': 'UInt16',
    '$ss6UInt32VD': 'UInt32', '$ss6UInt64VD': 'UInt64', '$ss7UInt128VD': 'UInt128',
}
FLOAT_TYPES = {
    '$sSdD': 'Double', '$sSfD': 'Float', '$ss7Float16VD': 'Float16', '$ss7Float80VD': 'Float80',
    '$s14CoreFoundation7CGFloatVD': 'CGFloat',
}
LITERAL_KINDS = frozenset(['integer_literal_expr', 'float_literal_expr'])
CONVERSION_WORDS = {'inout_to_pointer': '&x', 'string_to_pointer': 'string'}
_BOUNDED_RX = re.compile(r'// bounded-by-type: (\S.*?)\s*')

Finding = namedtuple('Finding', 'path line col lint message')
Fact = namedtuple('Fact', 'kind start fields in_macro implicit')


class UsageError(Exception):
    pass


class EnvironmentProblem(Exception):
    pass


# ---------------------------------------------------------------------------
# Tools and the reader

def find_tool(name):
    p = subprocess.run(['xcrun', '--find', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    path = p.stdout.decode().strip()
    if p.returncode != 0 or not path:
        raise EnvironmentProblem('xcrun cannot find %s' % name)
    return path


def sdk_path():
    p = subprocess.run(['xcrun', '--show-sdk-path'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    path = p.stdout.decode().strip()
    if p.returncode != 0 or not path:
        raise EnvironmentProblem('xcrun --show-sdk-path failed')
    return path


def compiler_version(swiftc=None):
    """The first line of `swiftc -version`, or None."""
    try:
        return swiftdb.compiler_version(swiftc or find_tool('swiftc'))
    except EnvironmentProblem:
        return None


def major_minor(version_text):
    return swiftdb.major_minor(version_text)


def reader_source_digest():
    def file_digest(p):
        with open(p, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    listing = ''.join('%s  %s\n' % (file_digest(os.path.join(READER_DIR, n)), n) for n in READER_SOURCE_NAMES)
    return hashlib.sha256(listing.encode('utf-8')).hexdigest()


def reader_version(exe):
    if not os.path.exists(exe):
        return None
    try:
        out = subprocess.run([exe, '--version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             timeout=60).stdout.decode().split()
    except (OSError, subprocess.SubprocessError):
        return None
    return out[1] if len(out) >= 3 and out[0] == 'swift_ast_facts' else None


def ensure_reader(path, log=print):
    """Builds the reader at path unless the binary there reports the digest of the current sources. Returns path."""
    want = reader_source_digest()
    if reader_version(path) == want:
        return path
    log('building the AST reader at %s' % path)
    p = subprocess.run([READER_BUILD_SCRIPT, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
    if p.returncode != 0:
        raise EnvironmentProblem('the AST reader build failed: %s' % p.stderr.decode('utf-8', 'replace').strip()[-2000:])
    if reader_version(path) != want:
        raise EnvironmentProblem('the AST reader at %s does not report the digest of its sources after a build' % path)
    return path


def run_in_group(cmd, timeout, cwd=None, stdout=None):
    """Runs cmd in its own session and process group; kills the whole group with SIGKILL when it has not finished
    in timeout seconds, and on every way out. Returns (status, stderr text, stdout bytes or None); status None
    means it timed out."""
    p = subprocess.Popen(cmd, cwd=cwd, stdout=stdout if stdout is not None else subprocess.PIPE,
                         stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        try:
            out, err = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            _kill_group(p.pid)
            out, err = p.communicate()
    finally:
        _kill_group(p.pid)
        if p.returncode is None:
            p.wait()
    return (None if timed_out else p.returncode), (err or b'').decode('utf-8', 'replace'), out


def _kill_group(pid):
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


# ---------------------------------------------------------------------------
# The reader's output

def iter_documents(lines):
    """Yields ('doc', path, [Fact]) for each document, in order, and ('summary', {key: int}, None) last; a
    document whose end is missing (the reader stopped) is yielded with path None as ('partial', path, facts)."""
    path = None
    facts = []
    for line in lines:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('\t')
        tag = parts[0]
        if tag == 'F':
            path = parts[1]
            facts = []
        elif tag == 'E':
            yield 'doc', path, facts
            path = None
            facts = []
        elif tag == 'S':
            summary = {}
            for k, v in zip(parts[1::2], parts[2::2]):
                try:
                    summary[k] = int(v)
                except ValueError:
                    summary[k] = v
            if path is not None:
                yield 'partial', path, facts
                path = None
            yield 'summary', summary, None
        elif tag in ('P', 'U', 'A', 'I'):
            flags = parts[-1]
            facts.append(Fact(tag, int(parts[1]), tuple(parts[2:-1]), 'm' in flags, 'i' in flags))
    if path is not None:
        yield 'partial', path, facts


def read_facts(lines):
    """({path: [Fact]}, summary) of the reader's output (for tests and small dumps)."""
    docs = OrderedDict()
    summary = {}
    for what, a, b in iter_documents(lines):
        if what == 'doc':
            docs[a] = b
        elif what == 'summary':
            summary = a
    return docs, summary


class LineIndex(object):
    """Line and column (Unicode code points, from 1) of byte offsets into UTF-8 source."""

    def __init__(self, data):
        self.data = data
        self.starts = [0] + [m.end() for m in re.finditer(b'\n', data)]

    def line_col(self, offset):
        i = bisect.bisect_right(self.starts, offset) - 1
        start = self.starts[i]
        return i + 1, len(self.data[start:offset].decode('utf-8', 'replace')) + 1


def bounded_by_type_lines(lexed):
    """The lines a "// bounded-by-type: <reason>" line comment covers: its own line when code precedes it on that
    line, otherwise the next line."""
    code_ends = [lexed.line(t.end - 1) for t in lexed.tokens if t.kind not in ('line_comment', 'block_comment')]
    code_starts = [t.start for t in lexed.tokens if t.kind not in ('line_comment', 'block_comment')]
    covered = set()
    for t in lexed.tokens:
        if t.kind != 'line_comment' or not _BOUNDED_RX.fullmatch(t.text):
            continue
        line = lexed.line(t.start)
        i = bisect.bisect_left(code_starts, t.start) - 1
        covered.add(line if i >= 0 and code_ends[i] == line else line + 1)
    return covered


def unsafe_marker_lines(path, lexed):
    """{marker line: (kind, reason)} of the unsafe markers, by swift_lints.py's own rule, so that placement is the
    same in both tools: a use on line L is covered by a marker on line L - 1."""
    linter = sl._FileLinter(path, lexed)
    linter.lint_markers()
    return linter.unsafe_marker_lines


class Demangler(object):
    """Readable type names for mangled ones, from swift-demangle, asked in batches and cached."""

    def __init__(self):
        self.cache = dict((k, v) for k, v in list(INTEGER_TYPES.items()) + list(FLOAT_TYPES.items()))
        self.tool = None

    def prime(self, names):
        want = sorted(set(n for n in names if n and n != '-' and n not in self.cache))
        if not want:
            return
        try:
            if self.tool is None:
                self.tool = find_tool('swift-demangle')
            p = subprocess.run([self.tool, '--simplified', '--compact'], input='\n'.join(want).encode(),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
            out = p.stdout.decode('utf-8', 'replace').split('\n')
        except (EnvironmentProblem, OSError, subprocess.SubprocessError):
            out = []
        for i, n in enumerate(want):
            self.cache[n] = out[i] if i < len(out) and out[i] else n

    def name(self, mangled):
        return self.cache.get(mangled, mangled)


def strip_inout(mangled):
    """The type of an inout operand ($ss5Int32VzD) without the inout ($ss5Int32VD)."""
    return mangled[:-2] + 'D' if mangled.endswith('zD') else mangled


def is_objc_usr(usr):
    """A declaration imported from Objective-C or C: a Clang USR (c:objc(...), c:@F@..., c:@NSApp), except those
    of declarations written in Swift and exposed to Objective-C, which Swift gives a Clang-style USR naming their
    module (c:@M@iTerm2SharedARC@objc(cs)...; c:@CM@ for C++ interop)."""
    return usr.startswith('c:') and not usr.startswith(('c:@M@', 'c:@CM@'))


def is_stdlib_usr(usr):
    """A declaration of the Swift standard library: its USR names module Swift (s:s...) or a standard substitution
    (s:Si..., s:SZ...). Declarations of other modules begin with s: and the module name's length."""
    return usr.startswith('s:s') or bool(re.match(r's:S[A-Za-z]', usr))


def lint_document(path, data, facts, demangler):
    """(findings, notes, skipped) for one file: data is its bytes (the content the compiler read), facts the
    reader's facts for it. path is the name used in findings. Raises sl.LexError when the token lexer cannot read
    the file (its markers and comments cannot be found)."""
    text = data.decode('utf-8')
    lexed = sl.lex(text)
    markers = unsafe_marker_lines(path, lexed)
    bounded = bounded_by_type_lines(lexed)
    index = LineIndex(data)
    demangler.prime([f.fields[1] for f in facts if f.kind == 'P'] + [f.fields[0] for f in facts if f.kind == 'U'])
    findings = OrderedDict()
    notes = []
    seen_notes = set()
    skipped = collections.Counter()

    def add(fact, lint, message):
        line, col = index.line_col(fact.start)
        findings.setdefault((line, col, lint), Finding(path, line, col, lint, message))

    for f in facts:
        if f.in_macro:
            skipped['in a macro expansion'] += 1
            continue
        line, col = index.line_col(f.start)
        if f.kind == 'P':
            conversion, ptype, operand = f.fields
            if conversion == 'array_to_pointer':
                what = '&array' if operand == 'inout_expr' else 'array'
            else:
                what = CONVERSION_WORDS.get(conversion, conversion)
            marker = markers.get(line - 1)
            if marker is None:
                add(f, 'unsafe-pointer-arg-unmarked',
                    '%s converted to %s (%s) without "// SWIFT-MIGRATION-UNSAFE(hot): <reason>" or '
                    '"// SWIFT-MIGRATION-SHIM: <reason>" on the line above'
                    % (what, demangler.name(ptype), conversion))
            elif (line, col, 'P') not in seen_notes:
                seen_notes.add((line, col, 'P'))
                notes.append(OrderedDict([('kind', 'marked-pointer-arg'), ('path', path), ('line', line),
                                          ('column', col), ('conversion', conversion), ('marker', marker[0]),
                                          ('reason', marker[1])]))
        elif f.kind == 'U':
            utype, usr, name = f.fields
            if is_objc_usr(usr):
                add(f, 'iuo-objc-implicit-unwrap',
                    'implicitly unwrapped %s from Objective-C (%s, %s) is force-unwrapped implicitly; bind it first'
                    % (demangler.name(utype), name, usr))
            elif (line, col, 'U') not in seen_notes:
                seen_notes.add((line, col, 'U'))
                notes.append(OrderedDict([('kind', 'implicit-unwrap-swift'), ('path', path), ('line', line),
                                          ('column', col), ('name', name), ('usr', usr)]))
        elif f.kind == 'A':
            op, operand_type, kinds, usr = f.fields
            ty = INTEGER_TYPES.get(strip_inout(operand_type))
            if ty is None or not is_stdlib_usr(usr):
                continue
            if all(k in LITERAL_KINDS for k in kinds.split(',')):
                continue
            if line in bounded:
                continue
            prefix = op.startswith('prefix')
            name = op[len('prefix'):] if prefix else op
            add(f, 'integer-arithmetic', '%s"%s" on %s without a helper or "// bounded-by-type: <reason>"'
                % ('unary ' if prefix else '', name, ty))
        elif f.kind == 'I':
            result, label, arg_type, arg_kind, count = f.fields
            ty = INTEGER_TYPES.get(result)
            source = INTEGER_TYPES.get(arg_type) or FLOAT_TYPES.get(arg_type)
            if ty is None or source is None or label != '-' or count != '1' or arg_kind in LITERAL_KINDS:
                continue
            add(f, 'integer-init-nonliteral',
                '%s(%s) on a non-literal; use numericCast, init(truncatingIfNeeded:), init(bitPattern:), '
                'init(exactly:), init(clamping:) or the helpers' % (ty, source))
    out = sorted(findings.values(), key=lambda x: (x.line, x.col, x.lint))
    return out, notes, skipped


def paired_lines(finding):
    """The lines a finding is about: its own, and the line above for the lints whose marker or comment may be
    there."""
    if finding.lint in ('unsafe-pointer-arg-unmarked', 'integer-arithmetic'):
        return (finding.line - 1, finding.line)
    return (finding.line,)


# ---------------------------------------------------------------------------
# Jobs

def restrict_primaries(job, keep):
    """The frontend job with only the files in keep as primary files (the others stay as secondary inputs: the
    file list) and one "-o -" for each."""
    out = []
    kept = []
    i = 0
    while i < len(job):
        x = job[i]
        if x == '-primary-file' and i + 1 < len(job):
            if job[i + 1] in keep:
                out += [x, job[i + 1]]
                kept.append(job[i + 1])
            i += 2
            continue
        if x == '-o' and i + 1 < len(job) and job[i + 1] == '-':
            i += 2
            continue
        out.append(x)
        i += 1
    for _ in kept:
        out += ['-o', '-']
    return out, kept


def standalone_job(files, primaries, header=None, module='Fixture', module_cache=None):
    """A frontend job that dumps primaries, compiling files (absolute paths) as one module with the SDK xcrun
    finds, and optionally an Objective-C bridging header."""
    job = [find_tool('swift-frontend'), '-frontend', '-dump-ast', '-dump-ast-format', 'json', '-sdk', sdk_path(),
           '-target', 'arm64-apple-macos13.0', '-module-name', module]
    if module_cache:
        job += ['-module-cache-path', module_cache]
    if header:
        job += ['-import-objc-header', header]
    for f in files:
        job += ['-primary-file', f] if f in primaries else [f]
    job += ['-o', '-'] * len(primaries)
    return job


Result = namedtuple('Result', 'files incomplete modules skipped')


def run_job(reader, job, primaries, work, limit_kb, timeout, cwd=None, label='job', reader_args=()):
    """Runs the reader on a frontend job. Returns (docs, incomplete, info): docs {primary: [Fact]} for every primary
    whose document is complete; incomplete [(primary, reason)]; info a dict of measurements."""
    os.makedirs(work, exist_ok=True)
    peak = os.path.join(work, 'peak-%s' % label)
    stderr_file = os.path.join(work, 'compiler-stderr-%s.txt' % label)
    cmd = [GUARD, '--limit-kb', str(limit_kb), '--peak-file', peak, '--', reader] + list(reader_args) + \
        ['--stderr-file', stderr_file, '--'] + job
    info = OrderedDict([('primaries', len(primaries))])
    t0 = time.time()
    with tempfile.TemporaryFile('w+', dir=work) as out:
        status, err, _ = run_in_group(cmd, timeout, cwd=cwd, stdout=out)
        info['seconds'] = round(time.time() - t0, 1)
        info['guard_peak_kb'] = swiftdb.read_peak(peak)
        out.seek(0)
        docs = OrderedDict()
        summary = {}
        partial = None
        for what, a, b in iter_documents(out):
            if what == 'doc':
                docs[a] = b
            elif what == 'partial':
                partial = a
            elif what == 'summary':
                summary = a
    info.update(summary)
    info['assertions'] = _count_assertions(stderr_file)
    reason = None
    if status is None:
        reason = 'the compiler and reader ran out of time (%d s); the process group was killed' % timeout
    elif status == 137:
        reason = 'killed by the memory cap (%d KB) of guard.sh' % limit_kb
    elif status != 0:
        tail = err.strip().splitlines()[-1] if err.strip() else 'status %d' % status
        reason = 'the compiler or reader failed: %s (compiler messages in %s)' % (tail, stderr_file)
    info['status'] = status
    if reason is not None:
        return OrderedDict(), [(p, reason) for p in primaries], info
    incomplete = []
    complete = OrderedDict()
    for p in primaries:
        if p in docs:
            complete[p] = docs[p]
        else:
            incomplete.append((p, 'the dump has no complete document for it%s'
                               % (' (it stopped in it)' if partial == p else '')))
    return complete, incomplete, info


def _count_assertions(path):
    n = 0
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                if 'Assertion failed' in line or 'assertion failed' in line:
                    n += 1
    except OSError:
        pass
    return n


def lint_standalone(reader, files, header=None, module_cache=None, work=None, limit_kb=DEFAULT_LIMIT_KB,
                    timeout=600):
    """Lints files (absolute paths) compiled together as one module without a capture: fixtures, and files that
    type-check on their own. Returns a Result whose files is {path: (findings, notes)}."""
    own = work is None
    work = work or tempfile.mkdtemp(prefix='swift-ast-lints-')
    try:
        job = standalone_job(files, set(files), header=header, module_cache=module_cache)
        docs, incomplete, info = run_job(reader, job, list(files), work, limit_kb, timeout)
        out = OrderedDict()
        skipped = collections.Counter()
        demangler = Demangler()
        for p, facts in docs.items():
            with open(p, 'rb') as f:
                data = f.read()
            try:
                findings, notes, sk = lint_document(p, data, facts, demangler)
            except sl.LexError as e:
                incomplete.append((p, 'the token lexer cannot read it: %s' % e.message))
                continue
            out[p] = (findings, notes)
            skipped.update(sk)
        return Result(out, incomplete, [info], skipped)
    finally:
        if own:
            import shutil
            shutil.rmtree(work, ignore_errors=True)


def module_jobs(capture_modules, wanted, root):
    """Assigns each wanted file (absolute real path) to the first captured module whose file list holds it.
    Returns ({module name: (module, [file as listed])}, [wanted files in no module])."""
    by_module = OrderedDict()
    found = set()
    for m in capture_modules:
        for listed in m.files:
            real = os.path.realpath(listed if os.path.isabs(listed) else os.path.join(root, listed))
            if real in wanted and real not in found:
                found.add(real)
                by_module.setdefault(m.name, (m, []))[1].append(listed)
    return by_module, sorted(set(wanted) - found)


_DUMP_AST_RX = re.compile(r'(?:^|\s)-dump-ast(?:\s|$)')
_PRIMARY_RX = re.compile(r'(?:^|\s)-primary-file\s+(\'[^\']*\'|"(?:[^"\\]|\\.)*"|\S+)')


def parse_print_jobs_fast(text):
    """The driver's jobs in the shape swiftdb.frontend_dump_job reads, without splitting every line: the driver
    prints one -dump-ast job per file of the module, each naming every file, so splitting all of them with shlex
    takes longer than the dump (16 s for the main module). The precompiled-header jobs and the first -dump-ast job,
    the template, are split whole; each other -dump-ast job is reduced to its primary files, which is all
    frontend_dump_job reads from it."""
    jobs = []
    have_template = False
    for line in text.splitlines():
        if not line.strip():
            continue
        # As swiftdb.frontend_dump_job decides: the tokens -dump-ast and -frontend (-dump-ast-format, which the
        # precompiled-header job has too, is not -dump-ast).
        is_dump = bool(_DUMP_AST_RX.search(line)) and ' -frontend' in line
        if is_dump and have_template:
            primaries = [shlex.split(x)[0] for x in _PRIMARY_RX.findall(line)]
            jobs.append(['-frontend', '-dump-ast'] + [y for p in primaries for y in ('-primary-file', p)])
            continue
        jobs.append(shlex.split(line))
        have_template = have_template or is_dump
    return jobs


def module_frontend_job(module, primaries, module_cache, sdk, root, work, timeout):
    """The frontend job that dumps primaries (as listed in module.files) of a captured module, from the compiler's
    own driver (-driver-print-jobs, as swiftdb.py asks it). The driver's output is kept in work, under a digest of
    the translated command, the file list and the compiler, and reused while they are unchanged. Raises
    EnvironmentProblem with the reason when the job cannot be made."""
    args, _ = swiftdb.translate_swift_command(module.driver_args, module_cache, sdk, file_list=module.file_list)
    with open(module.file_list, 'rb') as f:
        listing = f.read()
    key = hashlib.sha256(b'\0'.join([x.encode('utf-8') for x in args] + [listing] +
                                     [(compiler_version(args[0]) or '').encode('utf-8')])).hexdigest()
    cached = os.path.join(work, 'print-jobs-%s.txt' % key)
    if os.path.exists(cached):
        with open(cached, 'r', encoding='utf-8') as f:
            text = f.read()
    else:
        status, err, out = run_in_group(args + ['-dump-ast', '-dump-ast-format', 'json', '-driver-print-jobs'],
                                        timeout, cwd=root)
        if status != 0:
            raise EnvironmentProblem('the driver could not print the jobs of module %s: %s'
                                     % (module.name, (err.strip().splitlines() or ['status %s' % status])[-1]))
        text = out.decode('utf-8', 'replace')
        for old in os.listdir(work):
            if old.startswith('print-jobs-'):
                os.remove(os.path.join(work, old))
        with open(cached + '.tmp', 'w', encoding='utf-8') as f:
            f.write(text)
        os.replace(cached + '.tmp', cached)
    files_path = os.path.join(work, '%s-files.txt' % module.name)
    with open(files_path, 'w', encoding='utf-8') as f:
        f.write(''.join(x + '\n' for x in module.files))
    try:
        job = swiftdb.frontend_dump_job(parse_print_jobs_fast(text), module.files, files_path)
    except ValueError as e:
        raise EnvironmentProblem('module %s: %s' % (module.name, e))
    job, kept = restrict_primaries(job, set(primaries))
    return job, kept


# ---------------------------------------------------------------------------
# The command line

def run(argv):
    parser = argparse.ArgumentParser(
        prog='swift_ast_lints.py', formatter_class=argparse.RawDescriptionHelpFormatter,
        description=__doc__,
        epilog='Exit status: 0 no findings, 1 findings, 2 usage or environment error, 3 incomplete (a selected file '
               'could not be linted; takes precedence over 1). Which files: as swift_lints.py (--help there).')
    parser.add_argument('rev', nargs='?', help='lint the migration files this commit touches, and its ported lines')
    parser.add_argument('--staged', action='store_true', help='lint the migration files the staged change touches')
    parser.add_argument('--message', metavar='FILE', help='the pending commit message (as swift_lints.py)')
    parser.add_argument('--not-a-port', action='store_true', help='as swift_lints.py')
    parser.add_argument('--allow-incomplete-history', action='store_true', help='as swift_lints.py')
    parser.add_argument('--all-swift', action='store_true',
                        help='every tracked Swift file in the migration\'s scope (a survey; dumps whole modules)')
    parser.add_argument('--paths', nargs='+', metavar='PATH',
                        help='lint these Swift files whole, whether or not they are migration files (a survey)')
    parser.add_argument('--json', action='store_true', help='print JSON')
    parser.add_argument('--repo', metavar='DIR', help='the repository (default: the one containing the cwd)')
    parser.add_argument('--fragments', metavar='DIR',
                        help='the capture of compile commands (default: REPO/tmp/codedb/cdb-fragments)')
    parser.add_argument('--work', metavar='DIR', help='scratch directory (default: REPO/tmp/swift_ast_lints)')
    parser.add_argument('--reader', metavar='PATH', help='the reader binary (default: WORK/bin/swift_ast_facts, '
                                                         'built when its sources changed)')
    parser.add_argument('--module-cache', metavar='DIR', help='the compiler\'s module cache (default: WORK/modcache)')
    parser.add_argument('--timeout', type=int, default=DEFAULT_TIMEOUT,
                        help='seconds for one module\'s job (default %d)' % DEFAULT_TIMEOUT)
    parser.add_argument('--limit-kb', type=int, default=DEFAULT_LIMIT_KB,
                        help='memory cap of the compiler and reader together (default %d)' % DEFAULT_LIMIT_KB)
    parser.add_argument('--accept-compiler-version', action='store_true',
                        help='read a dump from a compiler other than Swift %s' % WRITTEN_AGAINST)
    parser.add_argument('--examples', type=int, default=0, metavar='N',
                        help='with a survey, also print up to N findings of each lint chosen at random (seeded)')
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return EXIT_CLEAN if e.code == 0 else EXIT_ERROR
    modes = sum(bool(x) for x in (args.rev, args.staged, args.all_swift, args.paths))
    if modes > 1:
        print('swift_ast_lints.py: choose one of REV, --staged, --all-swift and --paths', file=sys.stderr)
        return EXIT_ERROR
    if args.message and not args.staged:
        print('swift_ast_lints.py: --message needs --staged', file=sys.stderr)
        return EXIT_ERROR
    if args.not_a_port and (not args.staged or args.message):
        print('swift_ast_lints.py: --not-a-port needs --staged and cannot be combined with --message', file=sys.stderr)
        return EXIT_ERROR
    try:
        start = args.repo or os.getcwd()
        p = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=start, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
        if p.returncode != 0:
            print('swift_ast_lints.py: not in a git repository: %s' % start, file=sys.stderr)
            return EXIT_ERROR
        root = os.path.realpath(p.stdout.decode().strip())
        repo = sl.Repo(root)
        report = lint_repo(repo, args)
    except (UsageError, sl.UsageError) as e:
        print('swift_ast_lints.py: %s' % e, file=sys.stderr)
        return EXIT_ERROR
    except (EnvironmentProblem, sl.EnvironmentProblem) as e:
        print('swift_ast_lints.py: %s' % e, file=sys.stderr)
        return EXIT_ERROR
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_text(report)
    if report['errors'] or report['selection'].get('merge_port_commits') or \
            report['selection'].get('incomplete_history_fails'):
        return EXIT_ERROR
    if report['incomplete']:
        return EXIT_INCOMPLETE
    ported_count = sum(len(e['findings']) for e in report['ported_lines'])
    return EXIT_FINDINGS if report['findings'] or ported_count else EXIT_CLEAN


def lint_repo(repo, args):
    root = repo.root
    work = os.path.realpath(args.work or os.path.join(root, 'tmp', 'swift_ast_lints'))
    fragments = args.fragments or os.path.join(root, 'tmp', 'codedb', 'cdb-fragments')
    if args.paths:
        source = sl.Source(repo, 'worktree')
        files = []
        for p in args.paths:
            real = os.path.realpath(p)
            if not real.startswith(root + os.sep):
                raise UsageError('not inside the repository: %s' % p)
            files.append(real[len(root) + 1:])
        ported = OrderedDict()
        sel = OrderedDict([('mode', 'paths'), ('description', 'the files named with --paths, whole'),
                           ('files_linted', len(files))])
    else:
        sel_args = argparse.Namespace(all_swift=args.all_swift, staged=args.staged, message=args.message,
                                      not_a_port=args.not_a_port, rev=args.rev)
        source, files, ported, sel = sl.select(repo, sel_args)
        warnings = sl.history_warnings(repo)
        sel['history_warnings'] = warnings
        sel['incomplete_history_fails'] = bool(warnings) and sel['mode'] == 'tree' and \
            not args.allow_incomplete_history
    wanted = list(files) + [p for p in ported if p not in files]
    incomplete = []
    errors = []
    texts = {}
    for rel in wanted:
        try:
            data = source.read_bytes(rel)
        except OSError as e:
            errors.append(OrderedDict([('path', rel), ('error', 'cannot read: %s' % e)]))
            continue
        try:
            with open(os.path.join(root, rel), 'rb') as f:
                tree = f.read()
        except OSError:
            tree = None
        if tree != data:
            incomplete.append((rel, 'its content in %s differs from the working tree, from which the AST is '
                                    'compiled' % source.describe()))
            continue
        texts[rel] = data
    modules_info = []
    results = OrderedDict()
    skipped = collections.Counter()
    if texts:
        capture = swiftdb.read_swift_capture(fragments, root) if os.path.isdir(fragments) else None
        if capture is None:
            for rel in texts:
                incomplete.append((rel, 'there is no capture of compile commands in %s (build the app with '
                                        'tools/swift_migration/codedb/capture_compile_commands.sh)' % fragments))
        else:
            # The modules the code database excludes (a file outside the repository: a Swift package checkout)
            # compile all the same, so they are used too.
            run_modules(repo, args, capture[0] + capture[1], texts, work, results, incomplete, modules_info,
                        skipped)
    findings = []
    notes = []
    ported_lines = []
    for rel in files:
        if rel in results:
            findings.extend(results[rel][0])
            notes.extend(results[rel][1])
    for rel, ranges in ported.items():
        entry = OrderedDict([('path', rel), ('ranges', [[a, b] for a, b in ranges])])
        kept = []
        if rel in results:
            kept = [f for f in results[rel][0] if sl.in_ranges(paired_lines(f), ranges)]
            notes.extend(n for n in results[rel][1] if sl.in_ranges((n['line'] - 1, n['line']), ranges))
        entry['findings'] = [finding_dict(f) for f in kept]
        if rel in sel.get('ported_reasons', {}):
            entry['reason'] = sel['ported_reasons'][rel]
        ported_lines.append(entry)
    counts = OrderedDict((lint, 0) for lint in LINTS)
    for f in findings:
        counts[f.lint] += 1
    for e in ported_lines:
        for f in e['findings']:
            counts[f['lint']] += 1
    note_counts = collections.Counter(n['kind'] for n in notes)
    report = OrderedDict([
        ('selection', sel),
        ('source', source.describe()),
        ('findings', [finding_dict(f) for f in findings]),
        ('ported_lines', ported_lines),
        ('counts', counts),
        ('incomplete', [OrderedDict([('path', p), ('reason', r)]) for p, r in sorted(incomplete)]),
        ('errors', errors),
        ('notes', notes),
        ('note_counts', OrderedDict(sorted(note_counts.items()))),
        ('skipped', OrderedDict(sorted(skipped.items()))),
        ('modules', modules_info),
        ('legend', LINTS),
        ('classification', [OrderedDict([('rule', r), ('status', s), ('how', h)]) for r, s, h in CLASSIFICATION]),
    ])
    import resource
    report['tool_peak_kb'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024
    if args.examples:
        import random
        rnd = random.Random(20261120)
        examples = OrderedDict()
        for lint in LINTS:
            pool = [finding_dict(f) for f in findings if f.lint == lint]
            examples[lint] = rnd.sample(pool, min(args.examples, len(pool)))
        report['examples'] = examples
    return report


def run_modules(repo, args, modules, texts, work, results, incomplete, modules_info, skipped):
    root = repo.root
    wanted = dict((os.path.realpath(os.path.join(root, rel)), rel) for rel in texts)
    by_module, missing = module_jobs(modules, set(wanted), root)
    for real in missing:
        incomplete.append((wanted[real], 'not in the file list of any captured module (added or renamed since the '
                                         'capture; capture again after an app build)'))
    if not by_module:
        return
    swiftc = modules[0].driver_args[0]
    version = compiler_version(swiftc)
    if major_minor(version) != WRITTEN_AGAINST and not args.accept_compiler_version:
        for _, (_, listed) in by_module.items():
            for x in listed:
                incomplete.append((wanted[os.path.realpath(os.path.join(root, x))],
                                   'the compiler is %s; the reader was written against the dump format of Swift %s '
                                   '(--accept-compiler-version reads it anyway)' % (version, WRITTEN_AGAINST)))
        return
    reader = args.reader or ensure_reader(os.path.join(work, 'bin', 'swift_ast_facts'),
                                          log=lambda m: print(m, file=sys.stderr))
    module_cache = args.module_cache or os.path.join(work, 'modcache')
    os.makedirs(module_cache, exist_ok=True)
    sdk = sdk_path()
    demangler = Demangler()
    for name, (module, listed) in by_module.items():
        rels = dict((x, wanted[os.path.realpath(os.path.join(root, x))]) for x in listed)
        mwork = os.path.join(work, 'jobs', name)
        os.makedirs(mwork, exist_ok=True)
        try:
            job, kept = module_frontend_job(module, listed, module_cache, sdk, root, mwork, args.timeout)
        except EnvironmentProblem as e:
            for x in listed:
                incomplete.append((rels[x], str(e)))
            continue
        for x in listed:
            if x not in kept:
                incomplete.append((rels[x], 'the driver did not list it as a file of module %s' % name))
        docs, inc, info = run_job(reader, job, kept, mwork, args.limit_kb, args.timeout, cwd=root, label=name,
                                  reader_args=['--accept-compiler-version'] if args.accept_compiler_version else [])
        info = OrderedDict([('module', name), ('files_in_module', len(module.files))] + list(info.items()))
        modules_info.append(info)
        for x, reason in inc:
            incomplete.append((rels[x], reason))
        for x, facts in docs.items():
            rel = rels[x]
            try:
                findings, notes, sk = lint_document(rel, texts[rel], facts, demangler)
            except sl.LexError as e:
                incomplete.append((rel, 'the token lexer of swift_lints.py cannot read it, so its markers are '
                                        'unknown: %s' % e.message))
                continue
            except UnicodeDecodeError as e:
                incomplete.append((rel, 'not UTF-8: %s' % e))
                continue
            results[rel] = (findings, notes)
            skipped.update(sk)
        # The file may have changed while the compiler read it.
        for x in docs:
            rel = rels[x]
            try:
                with open(os.path.join(root, rel), 'rb') as f:
                    if f.read() != texts[rel]:
                        results.pop(rel, None)
                        incomplete.append((rel, 'it changed while the compiler read it'))
            except OSError:
                results.pop(rel, None)
                incomplete.append((rel, 'it disappeared while the compiler read it'))


def finding_dict(f):
    return OrderedDict([('path', f.path), ('line', f.line), ('column', f.col), ('lint', f.lint),
                        ('message', f.message)])


def print_text(r):
    out = []
    sel = r['selection']
    out.append('Type-aware lints for migration Swift (phase0.md section 6), on the compiler\'s AST.')
    out.append('Files: %s (%s); source: %s.' % (sel.get('description', ''), sel.get('mode'), r['source']))
    for w in sel.get('history_warnings', []):
        out.append(w)
    for e in r['errors']:
        out.append('ERROR: %s: %s' % (e['path'], e['error']))
    if r['findings']:
        out.append('')
        out.append('Findings:')
        for f in r['findings']:
            out.append('%s:%d:%d: %s: %s' % (f['path'], f['line'], f['column'], f['lint'], f['message']))
    if r['ported_lines']:
        out.append('')
        out.append('Ported lines in files that are not migration files:')
        for e in r['ported_lines']:
            out.append('  %s, lines %s%s' % (e['path'], ', '.join('%d-%d' % tuple(x) for x in e['ranges']),
                                            ' (%s)' % e['reason'] if e.get('reason') else ''))
            for f in e['findings']:
                out.append('%s:%d:%d: %s: %s' % (f['path'], f['line'], f['column'], f['lint'], f['message']))
    if r['incomplete']:
        out.append('')
        out.append('INCOMPLETE: %d selected file%s could not be linted; the result is not clean:'
                   % (len(r['incomplete']), '' if len(r['incomplete']) == 1 else 's'))
        for i in r['incomplete']:
            out.append('  %s: %s' % (i['path'], i['reason']))
    out.append('')
    out.append('Counts: ' + ', '.join('%s %d' % kv for kv in r['counts'].items()))
    if r['note_counts']:
        out.append('Notes (not findings): ' + ', '.join('%s %d' % kv for kv in r['note_counts'].items()))
    if r['skipped']:
        out.append('Skipped: ' + ', '.join('%s %d' % kv for kv in r['skipped'].items()))
    for m in r['modules']:
        out.append('Module %s: %d of %d files dumped, %.1f s, compiler peak %s KB, reader peak %s KB, guard peak %s '
                   'KB, dump %s bytes, %s compiler assertion%s' % (
                       m['module'], m.get('primaries', 0), m.get('files_in_module', 0), m.get('seconds', 0),
                       m.get('compiler_peak_kb', '?'), m.get('reader_peak_kb', '?'), m.get('guard_peak_kb', '?'),
                       m.get('dump_bytes', '?'), m.get('assertions', 0), '' if m.get('assertions') == 1 else 's'))
    out.append('This script\'s peak resident memory: %s KB' % r.get('tool_peak_kb', '?'))
    if r.get('examples'):
        out.append('')
        out.append('Examples chosen at random:')
        for lint, ex in r['examples'].items():
            for f in ex:
                out.append('  %s:%d:%d: %s' % (f['path'], f['line'], f['column'], lint))
    out.append('')
    out.append('Legend:')
    for k, v in r['legend'].items():
        out.append('  %s: %s' % (k, v))
    out.append('')
    if r['incomplete']:
        out.append('Result: INCOMPLETE.')
    elif r['findings'] or any(e['findings'] for e in r['ported_lines']):
        out.append('Result: findings.')
    else:
        out.append('Result: clean.')
    print('\n'.join(out))


def main(argv=None):
    return run(sys.argv[1:] if argv is None else argv)


if __name__ == '__main__':
    sys.exit(main())
