#!/usr/bin/env python3
"""Snapshots of what a Swift module shows the rest of the app, and a diff of
two snapshots (docs/swift-migration/phase0.md section 5).

One run of the Swift compiler, from the module's command captured by the
code database (tmp/codedb/cdb-fragments/swift/, read only), gives three
sections of a snapshot:

  objc    the Objective-C interface the module exports: the generated
          <Module>-Swift.h, one line per class, protocol, category,
          conformance, enum, enum case, method, property and function.
  swift   the module's own declarations as Swift sees them, every access
          level down to private, from the compiler's symbol graph.
  import  the Objective-C declarations Swift can see through the bridging
          header, as Swift imports them (names, optionality from
          nullability, throws and async forms, NS_REFINED_FOR_SWIFT), from
          the same symbol graph. A declaration that is absent is not visible
          to Swift.

The compiler job is the module's separate emit-module job, which the
compiler's own driver prints (-driver-print-jobs) for the captured command
translated by codedb/swiftdb.py (translate_swift_command): it type-checks
declarations and writes the generated header, the symbol graph and a
.swiftmodule, all under the work directory; no code is generated and nothing
is written under Build/. The real build produces its -Swift.h from the same
kind of job (the captured command has -experimental-emit-module-separately).

Commands:

  snapshot   run the compiler for a module (default iTerm2SharedARC) and
             write its snapshot (default tmp/swift-interface/<module>/
             <label>.snapshot). --rev REV snapshots the module as it was at
             REV without checking it out: the files that differ between REV
             and the work tree are given to the compiler from git through a
             virtual file system overlay (-vfsoverlay). The REV side's list
             of Swift files is the module's captured list, less the files
             that are not in the tree at REV (added since, or untracked),
             plus the Swift files that existed at REV and are deleted or
             renamed away since and that the project at REV
             (iTerm2.xcodeproj/project.pbxproj as committed at REV) compiled
             in the module's target, by its Sources build phase or a
             synchronized folder; when the project or the target did not
             exist at REV, a file renamed to a file of the current list
             counts. The files added to and dropped from the list are
             printed. --overlay DIR gives the compiler a directory that
             mirrors repository paths instead.
  normalize  turn a generated header and a symbol graph directory into a
             snapshot, without the compiler.
  diff OLD NEW
             print the declarations added, removed and changed between two
             snapshots, grouped by section and kind. Snapshots whose
             # module: or # compiler: lines differ are refused (exit 2)
             unless --allow-mixed: a diff across compilers or modules is
             mostly noise and would be read as the change's effect.
             --allow-added/--allow-removed/--allow-changed PATTERN and
             --expect FILE name the expected differences; a pattern is
             SECTION:KEY exactly, or glob:PATTERN for an fnmatch pattern on
             the whole SECTION:KEY.
  check      snapshot the work tree and diff it against --rev REV (computed
             the same way) or --against FILE (a stored snapshot).
  imports    write the import section, with Objective-C names, into the
             table swift_import of a code database (--db, required). The
             swift_import tables carry their own schema version in
             swift_import_meta; no other table of the database is touched.
  swiftname NAME
             how Swift spells an Objective-C declaration: NAME is a
             selector, -[Class sel:], a class, protocol or function name, or
             a Swift name.

Exit status of diff and check: 0 no difference outside the allowed ones; 1
differences, or an allowance or expectation that matched no difference
(unless --allow-unused); 2 an error; 3 the result is incomplete (a snapshot says
INCOMPLETE: the module's capture is stale, files are missing, or the module
failed to compile). snapshot exits 0, 2, or 3 (failed to compile, or written
with INCOMPLETE). A snapshot run deletes the previous <label>.snapshot
before it starts, so that a failed run leaves no snapshot that looks current. swiftname exits 0 found, 1 not found, 2 error, 3 found but
the table is stale.

Snapshot format: '#' lines are comments (the diff ignores them, except
'# INCOMPLETE:' lines). Every other line is one declaration:
SECTION<TAB>KEY<TAB>KIND<TAB>ACCESS<TAB>TEXT, sorted. KEY is the stable
name: Objective-C Class.-selector, Class.+selector, Class.property,
Enum.Case; Swift and import the qualified Swift name (Type.method(_:with:)).
A KEY can repeat (Swift overloads); the diff pairs one before with one after
as changed and reports the rest as added or removed. Paths, line numbers,
doc comments, the order of declarations and the compiler's version comment
are not in the declaration lines.

Python 3 standard library. The symbol graph is streamed one symbol at a time.
"""

NOT_DETECTED = """Not detected (an exit status of 0 from diff or check says nothing about these;
the compiler's outputs that the snapshot is made from do not carry them):

  - raw values of Swift enums that the generated header does not print: an
    @objc enum nested in a type is only forward-declared there
    (SWIFT_ENUM_FWD_DECL), so its cases and their raw values are not in the
    objc section, and the symbol graph has no raw values;
  - values of imported NS_ENUM and NS_OPTIONS cases (the import section has
    the case names only);
  - the copy, strong, weak and assign attributes of imported Objective-C
    properties (Swift imports them all as var);
  - the nullability of imported extern constants (the symbol graph prints
    them without optionality);
  - imported members whose Swift name collides with a member of another
    kind of the same name (a property beside a method, inherited or from
    another category) are absent from the symbol graph although Swift can
    still use them: NSString.jsonEncodedString (Swift name jsonEncoded,
    beside -[NSObject jsonEncoded]), TerminalFile.localPath and
    SCPFile.localPath (beside -[TransferrableFile localPath]),
    NSColor.it_hspBrightness (beside -[NSColor it_hspBrightness]); a change
    to them does not show in the import section. Declarations whose types
    Swift cannot import are absent too, as they are absent for Swift;
  - anything in function bodies: the snapshot is the interface only."""

NOT_DETECTED_POINTER = ('note: what the gate cannot see is listed under "Not detected" in swift_interface.py --help; '
                        'an exit status of 0 does not cover it')

__doc__ = __doc__ + '\n' + NOT_DETECTED + '\n'

import argparse
import collections
import fnmatch
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'codedb'))
import codedb  # noqa: E402
import swiftdb  # noqa: E402

FORMAT_LINE = '# swift_interface snapshot 1'
INCOMPLETE_PREFIX = '# INCOMPLETE: '
SECTIONS = ('objc', 'swift', 'import')
DEFAULT_MODULE = 'iTerm2SharedARC'
# The memory limit of the compiler (guard.sh polls the process tree) and the
# time limit of one run.
GUARD_LIMIT_KB = 4000000
TIMEOUT_SECONDS = 900
# A swift-frontend over this resident size, not started by this tool, means
# another heavy compile is running: snapshot refuses to start a second one.
OTHER_COMPILER_KB = 1000000

EXIT_SAME, EXIT_DIFFERENT, EXIT_ERROR, EXIT_INCOMPLETE = 0, 1, 2, 3


class InterfaceError(Exception):
    pass


# --- Streaming JSON -------------------------------------------------------------

_DECODER = json.JSONDecoder()


class JSONStream:
    """Reads one JSON document from a text file a value at a time, keeping
    only a buffer of about a megabyte and the value being decoded."""

    def __init__(self, f, chunk=1 << 20):
        self.f = f
        self.chunk = chunk
        self.buf = ''
        self.pos = 0
        self.eof = False

    def _fill(self):
        if self.eof:
            return False
        data = self.f.read(self.chunk)
        if not data:
            self.eof = True
            return False
        self.buf = self.buf[self.pos:] + data
        self.pos = 0
        return True

    def peek(self):
        """The next character that is not white space, not consumed; '' at
        the end."""
        while True:
            while self.pos < len(self.buf) and self.buf[self.pos] in ' \t\r\n':
                self.pos += 1
            if self.pos < len(self.buf):
                return self.buf[self.pos]
            if not self._fill():
                return ''

    def expect(self, ch):
        if self.peek() != ch:
            raise InterfaceError('malformed JSON: expected %r, found %r' % (ch, self.peek()))
        self.pos += 1

    def value(self):
        self.peek()
        while True:
            try:
                v, end = _DECODER.raw_decode(self.buf, self.pos)
            except json.JSONDecodeError:
                if not self._fill():
                    raise InterfaceError('malformed or truncated JSON')
                continue
            if end >= len(self.buf) and not self.eof and not isinstance(v, (dict, list, str)):
                # A number or literal at the end of the buffer can be cut.
                if self._fill():
                    continue
            self.pos = end
            return v

    def array_items(self):
        self.expect('[')
        if self.peek() == ']':
            self.pos += 1
            return
        while True:
            yield self.value()
            c = self.peek()
            self.pos += 1
            if c == ']':
                return
            if c != ',':
                raise InterfaceError('malformed JSON array: found %r' % c)


def iter_top_array(path, wanted):
    """The items of the array that is the value of the top-level key wanted,
    one at a time. Other arrays are skipped an item at a time."""
    with open(path, 'r', encoding='utf-8') as f:
        s = JSONStream(f)
        s.expect('{')
        if s.peek() == '}':
            return
        while True:
            key = s.value()
            s.expect(':')
            if s.peek() == '[':
                for item in s.array_items():
                    if key == wanted:
                        yield item
            else:
                s.value()
            c = s.peek()
            s.pos += 1
            if c == '}':
                return
            if c != ',':
                raise InterfaceError('malformed JSON object in %s: found %r' % (path, c))


def top_value(path, wanted):
    """The value of a small top-level key that precedes the large arrays."""
    with open(path, 'r', encoding='utf-8') as f:
        s = JSONStream(f)
        s.expect('{')
        while s.peek() not in ('}', ''):
            key = s.value()
            s.expect(':')
            if key == wanted:
                return s.value()
            if s.peek() == '[':
                for _ in s.array_items():
                    pass
            else:
                s.value()
            if s.peek() == ',':
                s.pos += 1
    return None


# --- Entries --------------------------------------------------------------------

Entry = collections.namedtuple('Entry', 'section key kind access text')


def clean(text):
    return ' '.join(text.split())


def entry_line(e):
    return '\t'.join((e.section, clean(e.key), e.kind, e.access, clean(e.text)))


def parse_line(line):
    parts = line.rstrip('\n').split('\t', 4)
    if len(parts) != 5:
        raise InterfaceError('not a snapshot line: %r' % line[:200])
    return Entry(*parts)


# --- The generated Objective-C header ---------------------------------------------

_IDENT = re.compile(r'\s*([A-Za-z_][A-Za-z0-9_]*)')
# A line of attribute macros only (IB_DESIGNABLE, SWIFT_CLASS("..."),
# SWIFT_AVAILABILITY(macos,introduced=14)) before an @interface, @protocol or
# enum.
_MACRO = r'[A-Z_][A-Z0-9_]*(?:\((?:[^()"]|"(?:[^"\\]|\\.)*"|\([^()]*\))*\))?'
_ATTRIBUTE_LINE = re.compile(r'^%s(?:\s+%s)*$' % (_MACRO, _MACRO))
_MACRO_TAIL = re.compile(r'\s+(?:SWIFT|NS|OBJC|API|IB)_[A-Z0-9_]*(?:\((?:[^()"]|"(?:[^"\\]|\\.)*"|\([^()]*\))*\))?\s*$')


def _skip_ws(s, i):
    while i < len(s) and s[i].isspace():
        i += 1
    return i


def _skip_balanced(s, i):
    """The index after the parenthesis group that starts at s[i] == '('."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            i += 1
            while i < len(s) and s[i] != '"':
                i += 2 if s[i] == '\\' else 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _paren_depth(s):
    depth = 0
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            i += 1
            while i < len(s) and s[i] != '"':
                i += 2 if s[i] == '\\' else 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        i += 1
    return depth


def statement_complete(s):
    t = s.rstrip()
    return _paren_depth(t) <= 0 and (t.endswith(';') or t.endswith(';)'))


def objc_selector(decl):
    """The selector of a method declaration '- (T)name:(T)a with:(T)b ATTR;'."""
    s = decl.strip()[1:]
    i = _skip_ws(s, 0)
    if i < len(s) and s[i] == '(':
        i = _skip_balanced(s, i)
    parts = []
    while True:
        m = _IDENT.match(s, i)
        if not m:
            break
        k = _skip_ws(s, m.end())
        if k < len(s) and s[k] == ':':
            k = _skip_ws(s, k + 1)
            if k < len(s) and s[k] == '(':
                k = _skip_balanced(s, k)
            p = _IDENT.match(s, k)
            parts.append(m.group(1) + ':')
            i = p.end() if p else k
            continue
        if not parts:
            parts.append(m.group(1))
        break
    return ''.join(parts)


def objc_property(decl):
    """(name, is_class) of '@property (attrs) TYPE NAME ATTRS;'."""
    s = decl.strip()[len('@property'):].strip()
    attrs = ''
    if s.startswith('('):
        end = _skip_balanced(s, 0)
        attrs = s[1:end - 1]
        s = s[end:]
    s = s.strip().rstrip(';').strip()
    while True:
        t = _MACRO_TAIL.sub('', s)
        if t == s:
            break
        s = t
    m = re.search(r'\(\s*[\^*]\s*(?:(?:_Nullable|_Nonnull|_Null_unspecified|__strong|__weak|const)\s+)*'
                  r'([A-Za-z_]\w*)\s*\)', s)
    if m:
        name = m.group(1)
    else:
        m = re.search(r'([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*$', s)
        name = m.group(1) if m else s
    is_class = 'class' in [a.strip() for a in attrs.split(',')]
    return name, is_class


def _parse_container_head(line, keyword):
    """(name, category or None, superclass or None, [protocols], rest) of an
    @interface or @protocol line."""
    s = line[len(keyword):]
    m = _IDENT.match(s)
    if not m:
        raise InterfaceError('cannot parse %r' % line)
    name = m.group(1)
    i = _skip_ws(s, m.end())
    category = None
    if i < len(s) and s[i] == '(':
        end = _skip_balanced(s, i)
        category = s[i + 1:end - 1].strip()
        i = _skip_ws(s, end)
    superclass = None
    if i < len(s) and s[i] == ':':
        m2 = _IDENT.match(s, i + 1)
        if m2:
            superclass = m2.group(1)
            i = _skip_ws(s, m2.end())
    protocols = []
    if i < len(s) and s[i] == '<':
        end = s.index('>', i)
        protocols = [p.strip() for p in s[i + 1:end].split(',') if p.strip()]
        i = _skip_ws(s, end + 1)
    return name, category, superclass, protocols, s[i:].strip()


def normalize_objc_header(lines):
    """Entries of the generated header's module-specific part (after the
    compiler's fixed preamble, which ends at its first `pragma clang
    attribute push`). Preprocessor lines and comments are not recorded."""
    out = set()
    started = False
    attrs = []
    container = None
    optional = False
    enum = None
    acc = ''

    def add(key, kind, text):
        out.add(Entry('objc', key, kind, '-', text))

    for raw in lines:
        line = raw.strip()
        if not started:
            if 'pragma clang attribute push' in line:
                started = True
            continue
        if not line or line.startswith('//') or line.startswith('#'):
            continue
        if enum is not None:
            if line.startswith('}'):
                enum = None
                continue
            case = line.rstrip(',').strip()
            name = case.split('=')[0].split()[0]
            add('%s.%s' % (enum, name), 'enum-case', case)
            continue
        if acc:
            acc += ' ' + line
            if not statement_complete(acc):
                continue
            line, acc = acc, ''
        elif container is not None and line not in ('@end', '@optional', '@required') \
                and not statement_complete(line):
            acc = line
            continue
        if line == '@end':
            container = None
            optional = False
            continue
        if container is not None:
            if line == '@optional':
                optional = True
                continue
            if line == '@required':
                optional = False
                continue
            prefix = '@optional ' if optional else ''
            decl = line
            if decl.startswith('SWIFT_CLASS_PROPERTY(') and decl.endswith(')'):
                decl = decl[len('SWIFT_CLASS_PROPERTY('):-1].strip()
            if decl.startswith('@property'):
                name, is_class = objc_property(decl)
                add('%s.%s%s' % (container, '+' if is_class else '', name), 'property', prefix + line)
            elif decl[:1] in '-+':
                sel = objc_selector(decl)
                kind = 'init' if decl[0] == '-' and re.match(r'init(?![a-z])', sel) else (
                    'method' if decl[0] == '-' else 'class-method')
                add('%s.%s%s' % (container, decl[0], sel), kind, prefix + line)
            else:
                add('%s.%s' % (container, clean(line)), 'member', prefix + line)
            continue
        # Top level.
        if line in ('extern "C" {', '}') or line.startswith('} //'):
            continue
        if line.startswith('@class ') or (line.startswith('@protocol ') and line.endswith(';')):
            continue
        if line.startswith('@import '):
            add('@import ' + line[len('@import '):].rstrip(';').strip(), 'import', line)
            continue
        if line.startswith('@interface'):
            name, category, superclass, protocols, rest = _parse_container_head(line, '@interface')
            if category is None:
                head = '@interface %s' % name + (' : %s' % superclass if superclass else '') + (
                    ' ' + rest if rest else '')
                add(name, 'class', ' '.join(attrs + [head]))
            else:
                add('%s (%s)' % (name, category), 'category', ' '.join(attrs + ['@interface %s (%s)' % (
                    name, category)] + ([rest] if rest else [])))
            for p in protocols:
                add('%s <%s>' % (name, p), 'conformance', '%s <%s>' % (name, p))
            attrs = []
            container = name
            continue
        if line.startswith('@protocol'):
            name, _, _, protocols, rest = _parse_container_head(line, '@protocol')
            add(name, 'protocol', ' '.join(attrs + ['@protocol %s' % name] + ([rest] if rest else [])))
            for p in protocols:
                add('%s <%s>' % (name, p), 'conformance', '%s <%s>' % (name, p))
            attrs = []
            container = name
            continue
        if line.startswith('typedef SWIFT_ENUM'):
            inner = line[line.index('(') + 1:_skip_balanced(line, line.index('(')) - 1]
            enum = inner.split(',')[1].strip()
            text = line[:-1].strip() if line.endswith('{') else line
            add(enum, 'enum', ' '.join(attrs + [text]))
            attrs = []
            if line.endswith('};'):
                enum = None
            continue
        if line.startswith('SWIFT_ENUM_FWD_DECL('):
            # A forward declaration of an @objc enum the header does not
            # define here (a nested one): its own line, not an attribute of
            # the next @interface.
            inner = line[line.index('(') + 1:_skip_balanced(line, line.index('(')) - 1]
            add(inner.split(',')[-1].strip(), 'enum-forward', line)
            continue
        if not statement_complete(line):
            if _ATTRIBUTE_LINE.match(line) and not acc:
                # An attribute line before an @interface, @protocol or enum.
                attrs.append(line)
                continue
            acc = line
            continue
        add_top_level(add, line)
    return out


def add_top_level(add, line):
    m = re.search(r'([A-Za-z_]\w*)\s*\(', re.sub(r'\b(?:SWIFT|NS|OBJC|API)_[A-Z0-9_]*(?:\([^()]*\))?', '', line))
    if '=' in line and not m:
        name = line.split('=')[0].split()[-1].lstrip('*')
        add(name, 'constant', line)
    elif m:
        add(m.group(1) + '()', 'function', line)
    else:
        add(clean(line), 'declaration', line)


# --- The symbol graph -------------------------------------------------------------

SYMBOL_KINDS = {
    'swift.class': 'class', 'swift.struct': 'struct', 'swift.enum': 'enum', 'swift.protocol': 'protocol',
    'swift.method': 'method', 'swift.type.method': 'class-method', 'swift.property': 'property',
    'swift.type.property': 'class-property', 'swift.init': 'init', 'swift.deinit': 'deinit',
    'swift.enum.case': 'enum-case', 'swift.typealias': 'typealias', 'swift.func': 'function',
    'swift.func.op': 'operator', 'swift.var': 'variable', 'swift.subscript': 'subscript',
    'swift.type.subscript': 'class-subscript', 'swift.associatedtype': 'associatedtype', 'swift.macro': 'macro',
    'swift.actor': 'actor', 'swift.extension': 'extension',
}


def _version(v):
    if not isinstance(v, dict):
        return str(v)
    return '.'.join(str(v[k]) for k in ('major', 'minor', 'patch') if k in v)


def availability_text(av):
    parts = []
    for a in av or ():
        fields = []
        for k in ('introduced', 'deprecated', 'obsoleted'):
            if k in a:
                fields.append('%s: %s' % (k, _version(a[k])))
        if a.get('isUnconditionallyUnavailable'):
            fields.append('unavailable')
        if a.get('isUnconditionallyDeprecated'):
            fields.append('deprecated')
        for k in ('renamed', 'message'):
            if k in a:
                fields.append('%s: %s' % (k, json.dumps(a[k])))
        parts.append('@available(%s)' % ', '.join([a.get('domain', '*')] + fields))
    return ' '.join(parts)


def is_own_symbol(sym, module):
    usr = sym['identifier']['precise']
    loc = (sym.get('location') or {}).get('uri', '')
    if loc:
        return loc.endswith('.swift')
    if usr.startswith(('c:@M@%s@' % module, 'c:@CM@%s@' % module)):
        return True
    return usr.startswith('s:') and not usr.startswith('s:So')


def fragments_text(frags):
    return ''.join(f.get('spelling', '') for f in frags or ())


def symbol_text(sym):
    text = fragments_text(sym.get('declarationFragments'))
    av = availability_text(sym.get('availability'))
    if av:
        text += ' ' + av
    ext = sym.get('swiftExtension')
    if ext is not None:
        cons = ext.get('constraints') or ()
        where = ', '.join('%s %s %s' % (c.get('lhs'), ':' if c.get('kind') == 'conformance' else '==',
                                        c.get('rhs')) for c in cons)
        text += ' [extension%s]' % (' where ' + where if where else '')
    return text


def symbol_graph_files(directory, module):
    """The module's symbol graph files: <module>.symbols.json and the
    extension graphs <module>@<other>.symbols.json, sorted."""
    names = sorted(n for n in os.listdir(directory) if n.endswith('.symbols.json') and (
        n == module + '.symbols.json' or n.startswith(module + '@')))
    if module + '.symbols.json' not in names:
        raise InterfaceError('no %s.symbols.json in %s' % (module, directory))
    return [os.path.join(directory, n) for n in names]


def iter_symbol_entries(directory, module, sections=SECTIONS, imports_out=None):
    """Entries of the swift and import sections. Two streaming passes per
    file: the relationships (protocol requirements, conformances and
    inheritance), then the symbols. imports_out, if given, is called with
    each imported symbol (for the imports table)."""
    for path in symbol_graph_files(directory, module):
        requirement = set()
        rels = []
        for r in iter_top_array(path, 'relationships'):
            kind = r.get('kind')
            if kind in ('requirementOf', 'optionalRequirementOf'):
                requirement.add(r['source'])
            elif kind in ('conformsTo', 'inheritsFrom'):
                rels.append((kind, r['source'], r['target'], r.get('targetFallback'),
                             r.get('swiftConstraints')))
        wanted = set()
        for _, src, tgt, _, _ in rels:
            wanted.add(src)
            wanted.add(tgt)
        where = {}
        for sym in iter_top_array(path, 'symbols'):
            usr = sym['identifier']['precise']
            if '::SYNTHESIZED::' in usr:
                continue
            section = 'swift' if is_own_symbol(sym, module) else 'import'
            key = '.'.join(sym.get('pathComponents') or [sym['names']['title']])
            if usr in wanted:
                where[usr] = (section, key)
            if section == 'import' and imports_out is not None:
                imports_out(sym, key)
            if section not in sections:
                continue
            raw_kind = sym['kind']['identifier']
            kind = 'requirement' if usr in requirement else SYMBOL_KINDS.get(raw_kind, raw_kind)
            yield Entry(section, key, kind, sym.get('accessLevel', '-'), symbol_text(sym))
        for kind, src, tgt, fallback, cons in rels:
            if src not in where:
                continue
            section, key = where[src]
            if section not in sections:
                continue
            target = fallback or (where[tgt][1] if tgt in where else tgt)
            text = '%s : %s' % (key, target)
            if cons:
                text += ' where ' + ', '.join('%s %s %s' % (c.get('lhs'), ':' if c.get('kind') == 'conformance'
                                                            else '==', c.get('rhs')) for c in cons)
            yield Entry(section, '%s : %s' % (key, target), 'conformance' if kind == 'conformsTo' else
                        'inheritance', '-', text)


# --- Snapshots --------------------------------------------------------------------

def write_snapshot(path, module, header_path, sg_dir, sections=SECTIONS, notes=(), incomplete=(), compiler=None,
                   private_sg_dir=None):
    """Normalize the outputs into a snapshot at path: the objc section from
    the header, the import section from sg_dir and the swift section from
    private_sg_dir (or sg_dir when it is not given). Returns the number of
    declaration lines."""
    lines = set()
    if 'objc' in sections:
        with open(header_path, 'r', encoding='utf-8') as f:
            for e in normalize_objc_header(f):
                lines.add(entry_line(e))
    if private_sg_dir is None:
        groups = [(sg_dir, [x for x in ('swift', 'import') if x in sections])]
    else:
        groups = [(sg_dir, [x for x in ('import',) if x in sections]),
                  (private_sg_dir, [x for x in ('swift',) if x in sections])]
    for directory, wanted in groups:
        if wanted:
            for e in iter_symbol_entries(directory, module, wanted):
                lines.add(entry_line(e))
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as out:
        out.write(FORMAT_LINE + '\n')
        out.write('# module: %s\n' % module)
        out.write('# sections: %s\n' % ' '.join(s for s in SECTIONS if s in sections))
        if compiler:
            out.write('# compiler: %s\n' % compiler)
        for n in notes:
            out.write('# note: %s\n' % clean(n))
        for r in incomplete:
            out.write(INCOMPLETE_PREFIX + clean(r) + '\n')
        for line in sorted(lines):
            out.write(line + '\n')
    os.replace(tmp, path)
    return len(lines)


def read_snapshot_meta(path):
    """(sections, incomplete reasons) from a snapshot's comment lines."""
    return read_snapshot_header(path)[:2]


def read_snapshot_header(path):
    """(sections, incomplete reasons, module, compiler) from a snapshot's
    comment lines; module and compiler are None when the line is absent."""
    sections, incomplete, module, compiler = None, [], None, None
    with open(path, 'r', encoding='utf-8') as f:
        first = f.readline().rstrip('\n')
        if first != FORMAT_LINE:
            raise InterfaceError('%s is not a snapshot (first line %r)' % (path, first[:80]))
        for line in f:
            if not line.startswith('#'):
                break
            if line.startswith('# sections: '):
                sections = line[len('# sections: '):].split()
            elif line.startswith('# module: '):
                module = line[len('# module: '):].strip()
            elif line.startswith('# compiler: '):
                compiler = line[len('# compiler: '):].strip()
            elif line.startswith(INCOMPLETE_PREFIX):
                incomplete.append(line[len(INCOMPLETE_PREFIX):].strip())
    return sections, incomplete, module, compiler


def iter_snapshot_groups(path):
    """((section, key), [Entry]) of a snapshot, in order, a group at a time."""
    group_key, group = None, []
    prev = None
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            line = line.rstrip('\n')
            if prev is not None and line < prev:
                raise InterfaceError('%s is not sorted (at %r)' % (path, line[:120]))
            prev = line
            e = parse_line(line)
            k = (e.section, e.key)
            if k != group_key:
                if group:
                    yield group_key, group
                group_key, group = k, []
            group.append(e)
    if group:
        yield group_key, group


# --- The compiler run ---------------------------------------------------------------

# Frontend flags whose value is a path the compiler writes.
OUTPUT_FLAGS = {
    '-o', '-emit-module-path', '-emit-module-doc-path', '-emit-module-source-info-path', '-emit-objc-header-path',
    '-emit-symbol-graph-dir', '-emit-abi-descriptor-path', '-emit-dependencies-path', '-serialize-diagnostics-path',
    '-emit-module-interface-path', '-emit-private-module-interface-path', '-emit-package-module-interface-path',
    '-emit-api-descriptor-path', '-emit-const-values-path', '-emit-reference-dependencies-path',
    '-emit-loaded-module-trace-path', '-emit-tbd-path', '-index-store-path', '-pch-output-dir', '-module-cache-path',
    '-emit-module-semantic-info-path', '-emit-digester-baseline-path', '-emit-module-summary-path',
    '-emit-localized-strings-path', '-index-unit-output-path', '-output-dir',
}


class Work:
    """The files of one compiler run under a work directory."""

    def __init__(self, directory):
        self.dir = os.path.realpath(directory)
        self.out = os.path.join(self.dir, 'out')
        self.sg = os.path.join(self.out, 'sg')
        self.sgp = os.path.join(self.out, 'sg-private')
        self.files = os.path.join(self.dir, 'files.txt')
        self.vfs = os.path.join(self.dir, 'vfs.yaml')
        self.job = os.path.join(self.dir, 'frontend-job.txt')
        self.peak = os.path.join(self.dir, 'peak-kb')
        self.stderr = os.path.join(self.dir, 'compiler-stderr.txt')
        self.deps = os.path.join(self.out, 'deps.d')

    def header(self, module):
        return os.path.join(self.out, module + '-Swift.h')

    def swiftmodule(self, module):
        return os.path.join(self.out, module + '.swiftmodule')


def write_vfs(path, mapping):
    """A virtual file system overlay that maps each absolute path to the file
    holding its contents. Written even when empty, so that every run has
    the same compiler arguments and shares one module cache."""
    roots = [{'type': 'file', 'name': k, 'external-contents': v} for k, v in sorted(mapping.items())]
    with open(path, 'w', encoding='utf-8') as f:
        json.dump({'version': 0, 'case-sensitive': 'true', 'overlay-relative': False, 'roots': roots}, f, indent=1,
                  sort_keys=True)
        f.write('\n')


def check_outputs(job, allowed, root):
    """Raise unless every path the job writes is under one of the allowed
    directories, and none is under the repository's Build/."""
    allowed = [os.path.realpath(a) for a in allowed]
    build = os.path.join(os.path.realpath(root), 'Build')
    for i, x in enumerate(job[:-1]):
        if x in OUTPUT_FLAGS:
            v = job[i + 1]
            if x == '-index-store-path':
                raise InterfaceError('the frontend job has -index-store-path %s; refusing to run it' % v)
            if v == '-':
                continue
            full = os.path.realpath(os.path.join(root, v))
            inside = any(full == a or full.startswith(a + os.sep) for a in allowed)
            if not inside or full == build or full.startswith(build + os.sep):
                raise InterfaceError('the frontend job would write %s (%s) outside the work directory; refusing '
                                     'to run it' % (v, x))


def emit_module_job(jobs, files, file_list_path, extra=()):
    """The driver's separate emit-module job with the bridging header instead
    of the driver's temporary precompiled header, the module's files given by
    file_list_path, and extra appended. It keeps the driver's
    -experimental-skip-non-inlinable-function-bodies-without-types, as the
    real build's job does."""
    pch = [j for j in jobs if '-emit-pch' in j]
    cands = [j for j in jobs if '-frontend' in j and '-emit-module' in j and '-primary-file' not in j]
    if len(cands) != 1:
        raise InterfaceError('the driver printed %d separate emit-module jobs; expected 1' % len(cands))
    header_for = {}
    for j in pch:
        if '-o' in j:
            header_for[j[j.index('-o') + 1]] = j[-1]
    fileset = set(files)
    out = []
    template = cands[0]
    i = 0
    while i < len(template):
        x = template[i]
        if x in ('-filelist', '-primary-filelist'):
            i += 2
            continue
        if x == '-supplementary-output-file-map':
            raise InterfaceError('the emit-module job names its outputs in a supplementary output file map; this '
                                 'tool expects explicit output flags')
        if x == '-import-objc-header' and i + 1 < len(template):
            out += [x, header_for.get(template[i + 1], template[i + 1])]
            i += 2
            continue
        if x in fileset:
            i += 1
            continue
        out.append(x)
        i += 1
    return out + ['-filelist', file_list_path] + list(extra)


def other_heavy_compilers():
    """(pid, rss KB) of every swift-frontend process over OTHER_COMPILER_KB."""
    try:
        text = subprocess.run(['ps', '-Ao', 'pid=,rss=,comm='], capture_output=True, text=True).stdout
    except OSError:
        return []
    found = []
    for line in text.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and os.path.basename(parts[2]) == 'swift-frontend' and parts[1].isdigit() \
                and int(parts[1]) > OTHER_COMPILER_KB:
            found.append((int(parts[0]), int(parts[1])))
    return found


def git_bytes(root, args):
    r = subprocess.run(['git', '-C', root] + args, capture_output=True)
    if r.returncode != 0:
        raise InterfaceError('git %s failed: %s' % (' '.join(args), r.stderr.decode('utf-8', 'replace').strip()))
    return r.stdout


def parse_raw_diff(raw):
    """[(old mode, old blob, status, path)] of `git diff --raw -z --no-renames`."""
    fields = raw.split(b'\0')
    out = []
    i = 0
    while i + 1 < len(fields):
        head = fields[i].decode('ascii')
        if not head.startswith(':'):
            i += 1
            continue
        old_mode, _, old_sha, _, status = head[1:].split()
        out.append((old_mode, old_sha, status, fields[i + 1].decode('utf-8', 'surrogateescape')))
        i += 2
    return out


def rev_overlay(root, rev, into):
    """The overlay that gives the compiler the tree as it was at rev:
    (commit, {repo relative path: file with its contents at rev}, the set of
    paths that exist in the work tree but not at rev, notes). The overlay has
    every regular file that differs between rev and the work tree and exists
    at rev. Untracked files count as not at rev. Submodules and symbolic
    links that differ are not overlaid and are named in the notes."""
    commit = git_bytes(root, ['rev-parse', '--verify', rev + '^{commit}']).decode().strip()
    raw = git_bytes(root, ['diff', '--raw', '-z', '--no-renames', '--abbrev=40', commit, '--'])
    overlay, absent, notes = {}, set(), []
    for old_mode, old_sha, status, path in parse_raw_diff(raw):
        if status.startswith('A') or old_mode == '000000':
            absent.add(path)
            continue
        if old_mode in ('160000', '120000'):
            notes.append('not overlaid (a %s that differs from %s): %s' % (
                'submodule' if old_mode == '160000' else 'symbolic link', rev, path))
            continue
        dest = os.path.join(into, path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as f:
            f.write(git_bytes(root, ['cat-file', 'blob', old_sha]))
        overlay[path] = dest
    for path in git_bytes(root, ['ls-files', '-z', '--others', '--exclude-standard']).split(b'\0'):
        if path:
            absent.add(path.decode('utf-8', 'surrogateescape'))
    return commit, overlay, absent, notes


def parse_name_status(raw):
    """[(status letter, old path, new path or None)] of `git diff
    --name-status -z`."""
    fields = raw.split(b'\0')
    out = []
    i = 0
    while i + 1 < len(fields):
        status = fields[i].decode('ascii')
        if not status:
            i += 1
            continue
        if status[0] in 'RC' and i + 2 < len(fields):
            out.append((status[0], fields[i + 1].decode('utf-8', 'surrogateescape'),
                        fields[i + 2].decode('utf-8', 'surrogateescape')))
            i += 3
            continue
        out.append((status[0], fields[i + 1].decode('utf-8', 'surrogateescape'), None))
        i += 2
    return out


def rev_removed(root, commit):
    """[(path at commit, path in the work tree or None)] of the Swift files
    that existed at commit and are deleted (None) or renamed away since,
    from `git diff --name-status -M` between commit and the work tree."""
    raw = git_bytes(root, ['diff', '--name-status', '-z', '-M', '--no-ext-diff', commit, '--'])
    return sorted((old, new if status == 'R' else None) for status, old, new in parse_name_status(raw)
                  if status in 'DR' and old.endswith('.swift'))


def rev_membership(root, commit):
    """A function (target, path) -> True, False or None: whether the project
    at commit (iTerm2.xcodeproj/project.pbxproj as it was then) compiles the
    repo relative path in the target, through its Sources build phase or a
    synchronized folder of the target (less its membership exceptions).
    None when the project or the target did not exist at commit."""
    rel = os.path.relpath(codedb.project_file(root), root)
    r = subprocess.run(['git', '-C', root, 'cat-file', 'blob', '%s:%s' % (commit, rel)], capture_output=True)
    if r.returncode != 0:
        return lambda target, path: None
    objects = codedb.parse_openstep_plist(r.stdout.decode('utf-8', 'surrogateescape')).get('objects', {})
    path_of = codedb.path_resolver(objects)
    targets = {}
    for o in objects.values():
        if o.get('isa') != 'PBXNativeTarget':
            continue
        files, folders = set(), []
        for phase_id in o.get('buildPhases', []):
            phase = objects.get(phase_id, {})
            if phase.get('isa') == 'PBXSourcesBuildPhase':
                for bf in phase.get('files', []):
                    ref = objects.get(bf, {}).get('fileRef')
                    p = path_of(ref) if ref else None
                    if p:
                        files.add(p)
        for gid in o.get('fileSystemSynchronizedGroups', []):
            base = path_of(gid)
            if base is None:
                continue
            excluded = set()
            for ex in objects.get(gid, {}).get('exceptions', []):
                for m in objects.get(ex, {}).get('membershipExceptions', []):
                    excluded.add(os.path.normpath(os.path.join(base, m)))
            folders.append((base, excluded))
        targets[o.get('name')] = (files, folders)

    def member(target, path):
        if target not in targets:
            return None
        files, folders = targets[target]
        return path in files or any((not base or path.startswith(base + '/')) and path not in excluded
                                    for base, excluded in folders)
    return member


def dir_overlay(directory):
    """{repo relative path: file} of a directory that mirrors repository paths."""
    directory = os.path.realpath(directory)
    overlay = {}
    for d, _, names in os.walk(directory):
        for n in names:
            full = os.path.join(d, n)
            overlay[os.path.relpath(full, directory)] = full
    return overlay


Result = collections.namedtuple('Result', 'status snapshot lines incomplete notes seconds peak_kb header sg_dir '
                                            'private_sg_dir compiler')


# Which access levels each step's symbol graph covers. The emit-module job
# keeps the driver's skipping of function bodies (as the real build does),
# and with skipped bodies the symbol graph cannot go below internal: at the
# private level it asks for the type of a local declaration in a body that
# was not type-checked, and this compiler (built with assertions) aborts
# ("Querying VarDecl's type before type-checking parent stmt", on
# iTermFloatingPaneView.swift). Type-checking every body instead goes over
# the 4 GB memory limit, and -assert-continue turns the abort into errors and
# no header. So the job writes the header, the .swiftmodule and a symbol
# graph at the internal level (the import section comes from it: imported
# declarations are only in a graph emitted with the module), and
# swift-symbolgraph-extract then reads the .swiftmodule at the private level
# for the swift section.
EMIT_LEVEL = 'internal'
EXTRACT_LEVEL = 'private'


def extract_command(job, module_name, work, module_cache):
    """The swift-symbolgraph-extract command that reads the .swiftmodule the
    job wrote, with the job's search paths and Clang arguments, and the
    overlay for the headers the bridging header reads."""
    exe = os.path.join(os.path.dirname(job[0]), 'swift-symbolgraph-extract')
    cmd = [exe, '-module-name', module_name, '-I', work.out, '-minimum-access-level', EXTRACT_LEVEL, '-output-dir',
           work.sgp]
    i = 1
    while i < len(job):
        x = job[i]
        if x in ('-I', '-F', '-Xcc', '-sdk', '-target') and i + 1 < len(job):
            cmd += [x, job[i + 1]]
            i += 2
            continue
        i += 1
    return cmd + ['-module-cache-path', module_cache, '-Xcc', '-ivfsoverlay', '-Xcc', work.vfs]


def run_guarded(paths, cmd, peak_file, stderr_file, root):
    with open(stderr_file, 'w', encoding='utf-8') as errf:
        status, err = codedb.run_in_group([paths.guard, '--limit-kb', str(GUARD_LIMIT_KB), '--peak-file', peak_file,
                                           '--'] + cmd, capture=True, timeout=TIMEOUT_SECONDS, cwd=root)
        errf.write(err)
    return status, err, swiftdb.read_peak(peak_file)


def failure_reason(status, what, stderr_file):
    if status == 137:
        return '%s was killed by the memory watchdog (over %d MB)' % (what, GUARD_LIMIT_KB // 1024)
    if status == codedb.TIMEOUT_STATUS:
        return '%s timed out after %d s' % (what, TIMEOUT_SECONDS)
    return '%s failed (status %d); its messages are in %s' % (what, status, stderr_file)


def snapshot_module(paths, module_name, work_dir, snapshot_path, overlay=None, absent=(), accept_stale=False,
                    sections=SECTIONS, log=print, check_other_compilers=True, project_swift=None, keep_raw=False,
                    removed=(), member_at_rev=None):
    """Run the compiler for one module and write its snapshot. overlay:
    {repo relative path: file with the contents to use}; absent: repo
    relative paths that do not exist in the tree being described (their
    Swift files are left out of the module). removed and member_at_rev
    describe a revision (rev_removed, rev_membership): a Swift file that
    existed at the revision and is deleted or renamed away since is added to
    the module's files when it was in the module then (see rev_file_list).
    The symbol graphs (about 200 MB for the app) are deleted after
    normalizing unless keep_raw; the generated header is kept. A previous
    snapshot at snapshot_path is deleted first, so that a failed run leaves
    none. Returns a Result; status is EXIT_SAME (0), EXIT_ERROR or
    EXIT_INCOMPLETE."""
    root = paths.root
    if os.path.lexists(snapshot_path):
        os.remove(snapshot_path)
    overlay = dict(overlay or {})
    sdk = codedb.current_sdk()[0]
    if project_swift is None:
        def project_swift():
            return codedb.project_swift_sources(root)
    ctx = swiftdb.SwiftContext(paths, codedb.MIGRATION_SCOPE_TEXT, sdk, project_swift=project_swift)
    if not ctx.captured:
        raise InterfaceError('the capture in %s kept no Swift inputs; run capture_compile_commands.sh' %
                             paths.fragments)
    by_name = dict((m.name, m) for m in ctx.modules + ctx.excluded)
    if module_name not in by_name:
        raise InterfaceError('not a captured Swift module: %s (captured: %s)' % (
            module_name, ', '.join(sorted(by_name))))
    module = by_name[module_name]
    incomplete, notes = [], []
    mismatch = ctx.project_mismatch.get(module_name)
    if mismatch:
        added, removed = mismatch
        why = ('the capture is stale: the project now compiles %d Swift files in %s that the captured file list does '
               'not have (%s) and %d that it no longer compiles (%s); capture again with capture_compile_commands.sh'
               % (len(added), module.target, ', '.join(added) or 'none', len(removed), ', '.join(removed) or 'none'))
        if not accept_stale:
            raise StaleCapture(why)
        incomplete.append(why)
        log('INCOMPLETE: ' + why)
    if module_name in ctx.not_compared:
        notes.append('the captured file list of %s was not compared with a project (its target is not in '
                     'iTerm2.xcodeproj)' % module_name)
    if module in ctx.excluded:
        notes.append('%s has files outside the repository (%s)' % (module_name, ', '.join(module.outside[:3])))
    work = Work(work_dir)
    if os.path.exists(work.out):
        shutil.rmtree(work.out)
    os.makedirs(work.sg)
    os.makedirs(work.sgp)
    files, dropped = [], []
    for f in module.files:
        rel = swiftdb.stored_path(f, root)
        if rel in absent:
            dropped.append(rel)
            continue
        if rel not in overlay and not os.path.exists(f):
            incomplete.append('a file of the module is missing: %s' % rel)
            continue
        files.append(f)
    added, unknown = rev_file_list(root, module, removed, member_at_rev)
    for rel in added:
        if rel not in overlay:
            incomplete.append('a file of the module at the revision has no contents in the overlay: %s' % rel)
            continue
        files.append(os.path.join(root, rel))
    for what, which in (('added to the REV side\'s file list (in the module at REV, deleted or renamed since)', added),
                        ('dropped from the REV side\'s file list (not in the tree at REV)', dropped),
                        ('not added to the REV side\'s file list, membership at REV unknown (no project or no '
                         'target %s at REV, and not renamed to a file of the module)' % module.target, unknown)):
        if which:
            notes.append('%s: %s' % (what, ', '.join(which)))
            log('%s: %s' % (what, ', '.join(which)))
    with open(work.files, 'w', encoding='utf-8') as fl:
        fl.write(''.join(x + '\n' for x in files))
    write_vfs(work.vfs, dict((os.path.join(root, k), os.path.realpath(v)) for k, v in overlay.items()))
    module_cache = paths.swift_module_cache
    os.makedirs(module_cache, exist_ok=True)
    args, _ = swiftdb.translate_swift_command(module.driver_args, module_cache, sdk, file_list=work.files)
    args += ['-emit-module', '-emit-module-path', work.swiftmodule(module_name), '-emit-objc-header-path',
             work.header(module_name), '-emit-symbol-graph', '-emit-symbol-graph-dir', work.sg,
             '-symbol-graph-minimum-access-level', EMIT_LEVEL, '-experimental-emit-module-separately',
             '-vfsoverlay', work.vfs]
    status, out, err = swiftdb.run_capture(codedb.run_in_group, args + ['-driver-print-jobs'], timeout=300, cwd=root)
    if status != 0:
        raise InterfaceError('the driver could not print the jobs (status %d): %s' % (status, err.strip()[-2000:]))
    job = emit_module_job(swiftdb.parse_print_jobs(out), files, work.files,
                          extra=['-emit-dependencies-path', work.deps])
    extract = extract_command(job, module_name, work, module_cache)
    for cmd in (job, extract):
        check_outputs(cmd, (work.dir, module_cache), root)
    with open(work.job, 'w', encoding='utf-8') as f:
        f.write(' '.join(shlex.quote(x) for x in job) + '\n')
        f.write(' '.join(shlex.quote(x) for x in extract) + '\n')
    if check_other_compilers:
        others = other_heavy_compilers()
        if others:
            raise InterfaceError('another swift-frontend over %d MB is running (%s); run one heavy compile at a time '
                                 '(retry later, or pass --ignore-other-compilers)' % (
                                     OTHER_COMPILER_KB // 1024, ', '.join('pid %d %d MB' % (p, r // 1024)
                                                                         for p, r in others)))
    t0 = time.time()
    status, err, peak = run_guarded(paths, job, work.peak, work.stderr, root)
    if status != 0:
        why = failure_reason(status, 'the module\'s compile', work.stderr).replace(
            'the module\'s compile failed', 'the module failed to compile')
        log('INCOMPLETE: ' + why)
        for t in [x for x in err.splitlines() if 'error:' in x][:10]:
            log('  ' + t)
        return Result(EXIT_INCOMPLETE, None, 0, incomplete + [why], notes, time.time() - t0, peak, None, None, None,
                      ctx.compiler)
    if 'swift' in sections:
        status, err, peak2 = run_guarded(paths, extract, work.peak + '-extract', work.stderr + '-extract', root)
        peak = max(peak or 0, peak2 or 0)
        if status != 0:
            why = failure_reason(status, 'swift-symbolgraph-extract', work.stderr + '-extract')
            log('INCOMPLETE: ' + why)
            return Result(EXIT_INCOMPLETE, None, 0, incomplete + [why], notes, time.time() - t0, peak, None, None,
                          None, ctx.compiler)
    seconds = time.time() - t0
    n = write_snapshot(snapshot_path, module_name, work.header(module_name), work.sg, sections=sections, notes=notes,
                       incomplete=incomplete, compiler=ctx.compiler, private_sg_dir=work.sgp)
    if not keep_raw:
        for d in (work.sg, work.sgp):
            shutil.rmtree(d, ignore_errors=True)
    return Result(EXIT_INCOMPLETE if incomplete else EXIT_SAME, snapshot_path, n, incomplete, notes, seconds, peak,
                  work.header(module_name), work.sg, work.sgp, ctx.compiler)


class StaleCapture(InterfaceError):
    pass


def rev_file_list(root, module, removed, member_at_rev):
    """(added, unknown): the repo relative paths of the Swift files to add to
    the module's current file list to describe a revision, and those whose
    membership could not be decided. A file deleted or renamed away since
    the revision is added when the project at the revision compiled it in
    the module's target; when the project or the target did not exist then,
    when it was renamed to a file of the module's current list. A file in
    no module then is never added."""
    current = set(swiftdb.stored_path(f, root) for f in module.files)
    added, unknown = [], []
    for old, new in removed:
        if old in current:
            continue
        m = member_at_rev(module.target, old) if member_at_rev else None
        if m is None:
            if new is not None and new in current:
                m = True
            else:
                unknown.append(old)
                continue
        if m:
            added.append(old)
    return added, unknown


# --- Diff -----------------------------------------------------------------------------

DiffItem = collections.namedtuple('DiffItem', 'change section key kind before after allowed')


def display_kind(e):
    return 'extension member' if e.section != 'objc' and '[extension' in e.text else e.kind


GLOB_PREFIX = 'glob:'


class Allowances:
    """Patterns, on SECTION:KEY, of differences that are expected. A pattern
    matches the one key equal to it; a pattern that starts with glob: is an
    fnmatch pattern (*, ?, [...]) matched against the whole SECTION:KEY.
    Keys contain [, ? and * in Swift types and operators, so they are not
    wildcards without glob:."""

    def __init__(self, added=(), removed=(), changed=()):
        self.patterns = {'added': list(added), 'removed': list(removed), 'changed': list(changed)}
        self.used = set()

    @classmethod
    def from_file(cls, path, base=None):
        a = base or cls()
        with open(path, 'r', encoding='utf-8') as f:
            for n, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                word, _, pattern = line.partition(' ')
                if word not in a.patterns or not pattern.strip():
                    raise InterfaceError('%s:%d: expected "added|removed|changed PATTERN", found %r' % (path, n, line))
                a.patterns[word].append(pattern.strip())
        return a

    def allows(self, change, section, key):
        name = '%s:%s' % (section, key)
        for p in self.patterns[change]:
            if (fnmatch.fnmatchcase(name, p[len(GLOB_PREFIX):]) if p.startswith(GLOB_PREFIX) else name == p):
                self.used.add((change, p))
                return True
        return False

    def unused(self):
        return [(c, p) for c in ('added', 'removed', 'changed') for p in self.patterns[c] if (c, p) not in self.used]


def diff_groups(old_groups, new_groups, allow, sections=None):
    """DiffItems of two streams of snapshot groups, merged in key order."""
    old_it, new_it = iter(old_groups), iter(new_groups)
    o, n = next(old_it, None), next(new_it, None)
    while o is not None or n is not None:
        if n is None or (o is not None and o[0] < n[0]):
            key, before, after = o[0], o[1], []
            o = next(old_it, None)
        elif o is None or n[0] < o[0]:
            key, before, after = n[0], [], n[1]
            n = next(new_it, None)
        else:
            key, before, after = o[0], o[1], n[1]
            o, n = next(old_it, None), next(new_it, None)
        if sections is not None and key[0] not in sections:
            continue
        b = [e for e in before if e not in after]
        a = [e for e in after if e not in before]
        while b and a:
            x, y = b.pop(0), a.pop(0)
            yield DiffItem('changed', key[0], key[1], display_kind(y), x, y, allow.allows('changed', *key))
        for x in b:
            yield DiffItem('removed', key[0], key[1], display_kind(x), x, None, allow.allows('removed', *key))
        for y in a:
            yield DiffItem('added', key[0], key[1], display_kind(y), None, y, allow.allows('added', *key))


def entry_desc(e):
    return '%s%s' % ('' if e.access == '-' else e.access + ' ', e.text)


def diff_snapshots(old, new, allow=None, sections=None, out=None, allow_unused=False, allow_mixed=False):
    """Print the differences; return the exit status. An allowance that
    matches no difference makes the status 1 unless allow_unused. Snapshots
    of different modules or compilers are refused (InterfaceError) unless
    allow_mixed."""
    out = out or sys.stdout
    allow = allow or Allowances()
    old_sections, old_inc, old_module, old_compiler = read_snapshot_header(old)
    new_sections, new_inc, new_module, new_compiler = read_snapshot_header(new)
    for what, a, b in (('module', old_module, new_module), ('compiler', old_compiler, new_compiler)):
        if a != b:
            if not allow_mixed:
                raise InterfaceError('the snapshots are of different %ss (%s: %s; %s: %s); refusing to compare them '
                                     '(pass --allow-mixed to compare anyway)' % (what, old, a, new, b))
            out.write('note: the snapshots are of different %ss (old: %s; new: %s), compared because of '
                      '--allow-mixed\n' % (what, a, b))
    common = [s for s in SECTIONS if s in (old_sections or SECTIONS) and s in (new_sections or SECTIONS)]
    if sections is not None:
        common = [s for s in common if s in sections]
    items = list(diff_groups(iter_snapshot_groups(old), iter_snapshot_groups(new), allow, set(common)))
    by_group = collections.OrderedDict()
    for it in sorted(items, key=lambda i: (SECTIONS.index(i.section), i.kind, i.key, i.change)):
        by_group.setdefault((it.section, it.kind), []).append(it)
    counted = 0
    for (section, kind), its in by_group.items():
        c = collections.Counter(i.change for i in its)
        out.write('=== %s: %s (%d added, %d removed, %d changed)\n' % (section, kind, c['added'], c['removed'],
                                                                      c['changed']))
        for i in its:
            tag = '%s%s' % (i.change, ' (allowed)' if i.allowed else '')
            out.write('  %-18s %s\n' % (tag, i.key))
            if i.before is not None:
                out.write('      before: %s\n' % entry_desc(i.before))
            if i.after is not None:
                out.write('      after:  %s\n' % entry_desc(i.after))
            if not i.allowed:
                counted += 1
    unused = allow.unused()
    for c, p in unused:
        if allow_unused:
            out.write('note: an allowance or expectation matched no difference (--allow-unused): %s %s\n' % (c, p))
        else:
            out.write('error: an allowance or expectation matched no difference: %s %s\n' % (c, p))
    skipped = [s for s in SECTIONS if s not in common and (sections is None or s in sections)]
    if skipped:
        out.write('note: sections not in both snapshots, not compared: %s\n' % ', '.join(skipped))
    total = collections.Counter(i.change for i in items)
    out.write('--- %d added, %d removed, %d changed; %d not allowed%s\n' % (
        total['added'], total['removed'], total['changed'], counted,
        '; %d allowances or expectations matched nothing' % len(unused) if unused and not allow_unused else ''))
    if old_inc or new_inc:
        for label, inc in (('old', old_inc), ('new', new_inc)):
            for r in inc:
                out.write('INCOMPLETE (%s snapshot): %s\n' % (label, r))
        return EXIT_INCOMPLETE
    return EXIT_DIFFERENT if counted or (unused and not allow_unused) else EXIT_SAME


# --- Imports table ----------------------------------------------------------------------

# The swift_import tables are this tool's own, in a database whose other
# tables have other owners (codedb.py, swiftdb.py). Their schema version is
# in swift_import_meta; a database with another version (or none) has only
# these tables dropped and created again.
# 2: swift_import_unit gained cmd_digest, tool_digest and bridging_header,
# and swift_import_failure was added (codedb.py update fills the tables).
IMPORT_SCHEMA_VERSION = 2
IMPORT_TABLES = ('swift_import', 'swift_import_input', 'swift_import_unit', 'swift_import_failure',
                 'swift_import_meta')
IMPORT_COLUMNS = ('module', 'usr', 'objc_name', 'selector', 'container', 'swift_name', 'kind', 'access',
                  'declaration', 'params', 'optionality', 'throws', 'async', 'refined', 'availability')

IMPORT_SCHEMA = [
    'CREATE TABLE IF NOT EXISTS swift_import_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID',
    # cmd_digest: the module's translated command (swiftdb.SwiftContext.
    # cmd_digest) and tool_digest: the code that computed the rows
    # (swiftimports.tool_digest), both '' when written by
    # `swift_interface.py imports`; bridging_header: the module's, relative
    # to the repository when inside it.
    'CREATE TABLE IF NOT EXISTS swift_import_unit(module TEXT PRIMARY KEY, compiler TEXT NOT NULL, '
    "created_at TEXT NOT NULL, incomplete TEXT NOT NULL, cmd_digest TEXT NOT NULL DEFAULT '', "
    "tool_digest TEXT NOT NULL DEFAULT '', bridging_header TEXT NOT NULL DEFAULT '')",
    # A module whose last run failed; its earlier rows, if any, are kept.
    'CREATE TABLE IF NOT EXISTS swift_import_failure(module TEXT PRIMARY KEY, reason TEXT NOT NULL, '
    'failed_at TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS swift_import_input(module TEXT NOT NULL, path TEXT NOT NULL, digest TEXT NOT NULL, '
    'PRIMARY KEY(module, path)) WITHOUT ROWID',
    # One row per Objective-C or C declaration Swift can see through the
    # module's bridging header, as Swift imports it. A completion-handler
    # method has two rows with one USR: its callback form and its async form.
    # objc_name: -[Class sel:], +[Class sel], Class.property, Class (class),
    # <Protocol>, function(), Enum.Case or the USR when none of those.
    # swift_name: the qualified Swift name as the symbol graph gives it,
    # which is how callers write it: an Objective-C error parameter imported
    # as throws keeps its label (error: (), which callers pass) only when
    # dropping it would collide with another method of the same name.
    # selector: for methods; params and optionality: name: type per
    # parameter, and per parameter then the result one of optional (T?),
    # iuo (T!, unannotated), nonoptional; refined: NS_REFINED_FOR_SWIFT (the
    # Swift name starts with __).
    'CREATE TABLE IF NOT EXISTS swift_import(module TEXT NOT NULL, usr TEXT NOT NULL, objc_name TEXT NOT NULL, '
    'selector TEXT, container TEXT, swift_name TEXT NOT NULL, kind TEXT NOT NULL, access TEXT NOT NULL, '
    'declaration TEXT NOT NULL, params TEXT, optionality TEXT, throws INTEGER NOT NULL, async INTEGER NOT NULL, '
    'refined INTEGER NOT NULL, availability TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS swift_import_usr ON swift_import(usr)',
    'CREATE INDEX IF NOT EXISTS swift_import_selector ON swift_import(selector)',
    'CREATE INDEX IF NOT EXISTS swift_import_objc_name ON swift_import(objc_name)',
    'CREATE INDEX IF NOT EXISTS swift_import_container ON swift_import(container)',
]


def import_schema_version(con):
    """The schema version of the swift_import tables in an open database, or
    None when there is no swift_import_meta."""
    names = set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))
    if 'swift_import_meta' not in names:
        return None
    row = con.execute("SELECT value FROM swift_import_meta WHERE key='schema_version'").fetchone()
    return row[0] if row else None


def ensure_import_schema(con):
    """Create the swift_import tables, dropping them first (and only them)
    when they have another schema version or none."""
    if import_schema_version(con) != str(IMPORT_SCHEMA_VERSION):
        for t in IMPORT_TABLES:
            con.execute('DROP TABLE IF EXISTS %s' % t)
    for sql in IMPORT_SCHEMA:
        con.execute(sql)
    con.execute("INSERT OR REPLACE INTO swift_import_meta(key, value) VALUES('schema_version', ?)",
                (str(IMPORT_SCHEMA_VERSION),))


_USR_MEMBER = re.compile(r'^c:objc\((cs|pl)\)([^(]+)(?:\((im|cm|py|cpy)\)(.+))?$')


def objc_name_of(usr):
    """(objc_name, selector, container) of a Clang USR."""
    m = _USR_MEMBER.match(usr)
    if m:
        what, container, member_kind, member = m.groups()
        if member_kind is None:
            return (container if what == 'cs' else '<%s>' % container), None, None
        if member_kind in ('im', 'cm'):
            return '%s[%s %s]' % ('-' if member_kind == 'im' else '+', container, member), member, container
        return '%s.%s%s' % (container, '+' if member_kind == 'cpy' else '', member), None, container
    m = re.match(r'^c:objc\(cy\)([^@]+)@([^(]+)(?:\((im|cm|py|cpy)\)(.+))?$', usr)
    if m:
        container, _, member_kind, member = m.groups()
        if member_kind in ('im', 'cm'):
            return '%s[%s %s]' % ('-' if member_kind == 'im' else '+', container, member), member, container
        if member_kind:
            return '%s.%s' % (container, member), None, container
    m = re.match(r'^c:@F@(.+)$', usr)
    if m:
        return m.group(1) + '()', None, None
    m = re.match(r'^c:@E@([^@]+)@(.+)$', usr)
    if m:
        return '%s.%s' % m.groups(), None, m.group(1)
    m = re.match(r'^c:@(?:E|T|S|SA|U|EA)@([^@]+)$', usr)
    if m:
        return m.group(1), None, None
    return usr, None, None


def optionality_of(type_text):
    t = type_text.strip()
    if t.endswith('!'):
        return 'iuo'
    if t.endswith('?'):
        return 'optional'
    return 'nonoptional'


def import_row(module, sym, key):
    usr = sym['identifier']['precise']
    objc_name, selector, container = objc_name_of(usr)
    frags = sym.get('declarationFragments') or ()
    keywords = set(f.get('spelling') for f in frags if f.get('kind') == 'keyword')
    sig = sym.get('functionSignature') or {}
    params, opt = [], []
    for p in sig.get('parameters') or ():
        t = fragments_text(p.get('declarationFragments'))
        ptype = t.split(':', 1)[1] if ':' in t else t
        params.append('%s: %s' % (p.get('name'), clean(ptype)))
        opt.append(optionality_of(ptype))
    # The signature's returns print an unannotated result as T?; the
    # declaration prints it as T!.
    decl_text = fragments_text(frags)
    after_params = decl_text[_skip_balanced(decl_text, decl_text.index('(')):] if '(' in decl_text else ''
    returns = after_params.split('->', 1)[1] if '->' in after_params else fragments_text(sig.get('returns'))
    returns = re.sub(r'\s+(?:where\s.*)?$', '', returns.strip())
    if sig:
        opt.append('-> ' + (optionality_of(returns) if returns.strip() and returns.strip() not in ('Void', '()')
                            else 'void'))
    elif sym['kind']['identifier'] in ('swift.property', 'swift.type.property', 'swift.var'):
        decl = fragments_text(frags)
        m = re.search(r':\s*(.+?)(?:\s*\{.*\})?$', decl)
        if m:
            opt.append(optionality_of(m.group(1)))
    title = sym['names'].get('title', key)
    throws, async_ = int('throws' in keywords or 'rethrows' in keywords), int('async' in keywords)
    return (module, usr, objc_name, selector, container, key,
            SYMBOL_KINDS.get(sym['kind']['identifier'], sym['kind']['identifier']),
            sym.get('accessLevel', '-'), clean(fragments_text(frags)), '; '.join(params) if sig else None,
            ' '.join(opt) or None, throws, async_, int(title.startswith('__')),
            availability_text(sym.get('availability')))


def write_imports(db, module, sg_dir, input_digests, compiler, incomplete=(), cmd_digest='', tool_digest='',
                  bridging_header=''):
    """Replace the module's rows of swift_import from a symbol graph
    directory, a symbol at a time, and clear its failure. Returns the number
    of rows."""
    con = sqlite3.connect(db)
    con.execute('PRAGMA busy_timeout=60000')
    try:
        with con:
            ensure_import_schema(con)
            con.execute('DELETE FROM swift_import WHERE module=?', (module,))
            con.execute('DELETE FROM swift_import_input WHERE module=?', (module,))
            con.execute('DELETE FROM swift_import_unit WHERE module=?', (module,))
            con.execute('DELETE FROM swift_import_failure WHERE module=?', (module,))
            batch = []
            count = [0]
            insert = 'INSERT INTO swift_import(%s) VALUES(%s)' % (', '.join(IMPORT_COLUMNS),
                                                                  ', '.join('?' * len(IMPORT_COLUMNS)))

            def take(sym, key):
                batch.append(import_row(module, sym, key))
                count[0] += 1
                if len(batch) >= 2000:
                    con.executemany(insert, batch)
                    del batch[:]
            for _ in iter_symbol_entries(sg_dir, module, sections=(), imports_out=take):
                pass
            if batch:
                con.executemany(insert, batch)
            con.executemany('INSERT INTO swift_import_input VALUES(?,?,?)',
                            [(module, p, d) for p, d in sorted(input_digests.items())])
            con.execute('INSERT INTO swift_import_unit(module, compiler, created_at, incomplete, cmd_digest, '
                        'tool_digest, bridging_header) VALUES(?,?,?,?,?,?,?)', (
                            module, compiler or '', time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                            '; '.join(incomplete), cmd_digest, tool_digest, bridging_header))
        return count[0]
    finally:
        con.close()


def input_digests(root, deps_path):
    """{repo relative or absolute path: sha256} of the inputs a dependency
    file names."""
    with open(deps_path, 'r', encoding='utf-8', errors='replace') as f:
        deps = swiftdb.parse_dependency_file(f.read())
    out = {}
    for p in deps:
        full = os.path.join(root, p)
        try:
            out[swiftdb.stored_path(full, root)] = swiftdb._file_sha256(full)
        except OSError:
            out[swiftdb.stored_path(full, root)] = 'missing'
    return out


def swiftname(db, root, name, module=None, out=sys.stdout):
    """Print how Swift spells an Objective-C declaration. Returns the exit
    status."""
    if not os.path.exists(db):
        raise InterfaceError('no database at %s; run swift_interface.py imports' % db)
    con = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
    try:
        names = set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))
        if 'swift_import' not in names:
            raise InterfaceError('%s has no swift_import table; run swift_interface.py imports' % db)
        version = import_schema_version(con)
        if version != str(IMPORT_SCHEMA_VERSION):
            raise InterfaceError('the swift_import tables in %s have schema version %s; this tool reads version %d; '
                                 'run swift_interface.py imports again' % (db, version or 'none', IMPORT_SCHEMA_VERSION))
        # A bare property name matches Class.name and Class.+name.
        where, args = ('(objc_name = ? OR selector = ? OR swift_name = ? OR objc_name = ? OR objc_name = ? OR '
                       "(container IS NOT NULL AND objc_name IN (container || '.' || ?, container || '.+' || ?)))"), [
            name, name, name, name + '()', '<%s>' % name, name, name]
        if module:
            where += ' AND module = ?'
            args.append(module)
        rows = list(con.execute('SELECT module, objc_name, swift_name, kind, declaration, optionality, throws, async, '
                                'refined, availability, usr FROM swift_import WHERE %s ORDER BY module, '
                                'objc_name, swift_name' % where, args))
        members = 0
        if not rows or all(r[3] in ('class', 'protocol') for r in rows):
            members = con.execute('SELECT count(*) FROM swift_import WHERE container = ?', (name,)).fetchone()[0]
        for r in rows:
            flags = [f for f, on in (('throws', r[6]), ('async', r[7]), ('NS_REFINED_FOR_SWIFT', r[8])) if on]
            out.write('%s\t%s\t%s\n' % (r[1], r[2], r[4]))
            detail = []
            if r[5]:
                detail.append('optionality: ' + r[5])
            if flags:
                detail.append(', '.join(flags))
            if r[9]:
                detail.append(r[9])
            if detail:
                out.write('    %s\n' % '; '.join(detail))
        if members:
            out.write('%d members of %s are imported (SELECT * FROM swift_import WHERE container = \'%s\')\n' % (
                members, name, name))
        stale = []
        for module_name, in con.execute('SELECT module FROM swift_import_unit'):
            for path, digest in con.execute('SELECT path, digest FROM swift_import_input WHERE module = ?',
                                            (module_name,)):
                full = path if os.path.isabs(path) else os.path.join(root, path)
                try:
                    now = swiftdb._file_sha256(full)
                except OSError:
                    now = 'missing'
                if now != digest:
                    stale.append('%s: input changed: %s' % (module_name, path))
                    break
        incomplete = [r for r in con.execute("SELECT module, incomplete FROM swift_import_unit WHERE incomplete != ''")]
    finally:
        con.close()
    if not rows:
        out.write('%s: not imported. No declaration of that Objective-C name, selector or Swift name is visible to '
                  'Swift through the bridging header (absent from the compiler\'s symbol graph): it is marked '
                  'NS_SWIFT_UNAVAILABLE or unavailable, uses a type Swift cannot import, or is not in a header the '
                  'bridging header reaches.\n' % name)
    for s in stale:
        out.write('STALE: %s; run swift_interface.py imports again\n' % s)
    for m, why in incomplete:
        out.write('INCOMPLETE: %s: %s\n' % (m, why))
    if stale or incomplete:
        return EXIT_INCOMPLETE
    return EXIT_SAME if rows else EXIT_DIFFERENT


# --- Command line -------------------------------------------------------------------------

def default_work_root(root):
    return os.path.join(root, 'tmp', 'swift-interface')


def make_paths(args):
    root = os.path.realpath(args.root)
    work_root = os.path.realpath(args.work or default_work_root(root))
    paths = codedb.Paths(root, fragments=args.fragments, swift_work=work_root)
    for d in ('Build', os.path.join('tmp', 'codedb')):
        forbidden = os.path.join(root, d)
        if work_root == forbidden or work_root.startswith(forbidden + os.sep):
            raise InterfaceError('the work directory may not be under %s/ (%s)' % (d, work_root))
    return paths, work_root


def run_snapshot(paths, work_root, module, label, args, tree=None, log=print, keep_raw=None):
    work_dir = os.path.join(work_root, module, label)
    os.makedirs(work_dir, exist_ok=True)
    snap = os.path.join(work_root, module, label + '.snapshot')
    r = snapshot_module(paths, module, work_dir, snap, **(tree or {}),
                        accept_stale=args.accept_stale, sections=args.sections,
                        check_other_compilers=not args.ignore_other_compilers, log=log,
                        keep_raw=getattr(args, 'keep_raw', False) if keep_raw is None else keep_raw)
    log('%s: %s in %.1f s, compiler peak %s MB%s' % (
        label, ('%d declarations -> %s (%d bytes)' % (r.lines, r.snapshot, os.path.getsize(r.snapshot)))
        if r.snapshot else 'no snapshot', r.seconds, '?' if r.peak_kb is None else r.peak_kb // 1024,
        '; INCOMPLETE' if r.incomplete else ''))
    return r


def overlay_for(args, paths, work_root, module):
    if getattr(args, 'rev', None) and getattr(args, 'overlay', None):
        raise InterfaceError('--rev and --overlay cannot be combined')
    if getattr(args, 'overlay', None):
        return 'overlay', {'overlay': dir_overlay(args.overlay)}
    if getattr(args, 'rev', None):
        into = os.path.join(work_root, module, 'rev-files')
        if os.path.exists(into):
            shutil.rmtree(into)
        commit, overlay, absent, notes = rev_overlay(paths.root, args.rev, into)
        for n in notes:
            sys.stderr.write('note: %s\n' % n)
        return 'rev-' + commit[:12], {'overlay': overlay, 'absent': absent,
                                      'removed': rev_removed(paths.root, commit),
                                      'member_at_rev': rev_membership(paths.root, commit)}
    return 'worktree', {}


def parse_sections(text):
    s = [x.strip() for x in text.split(',') if x.strip()]
    bad = [x for x in s if x not in SECTIONS]
    if bad:
        raise argparse.ArgumentTypeError('unknown section %s (sections: %s)' % (', '.join(bad), ', '.join(SECTIONS)))
    return tuple(s)


def allowances(args):
    a = Allowances(args.allow_added, args.allow_removed, args.allow_changed)
    for p in args.expect or ():
        Allowances.from_file(p, a)
    return a


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0], epilog=__doc__.split('\n\n', 1)[1],
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='command')

    def common(sp, compiler=True):
        sp.add_argument('--root', default=codedb.REPO_ROOT, help='the repository (default: this one)')
        if compiler:
            sp.add_argument('--module', default=DEFAULT_MODULE, help='the Swift module (default %(default)s)')
            sp.add_argument('--fragments', help='the capture (default tmp/codedb/cdb-fragments), read only')
            sp.add_argument('--work', help='the work directory (default tmp/swift-interface)')
            sp.add_argument('--accept-stale', action='store_true',
                            help='proceed when the capture is stale; the snapshot is marked INCOMPLETE')
            sp.add_argument('--ignore-other-compilers', action='store_true',
                            help='start even when another swift-frontend over 1 GB is running')
            sp.add_argument('--keep-raw', action='store_true',
                            help='keep the symbol graphs (deleted after normalizing by default)')
        sp.add_argument('--sections', type=parse_sections, default=SECTIONS,
                        help='comma-separated sections (default: objc,swift,import)')

    def allow_opts(sp):
        sp.add_argument('--allow-added', action='append', default=[], metavar='PATTERN',
                        help='an expected added declaration: SECTION:KEY exactly, or glob:PATTERN (fnmatch on the '
                        'whole SECTION:KEY); may be repeated. A pattern that matches no difference makes the exit '
                        'status 1 (see --allow-unused)')
        sp.add_argument('--allow-removed', action='append', default=[], metavar='PATTERN',
                        help='an expected removed declaration, as --allow-added')
        sp.add_argument('--allow-changed', action='append', default=[], metavar='PATTERN',
                        help='an expected changed declaration, as --allow-added')
        sp.add_argument('--expect', action='append', metavar='FILE',
                        help='a file of expected changes: lines "added|removed|changed PATTERN"; an entry that '
                        'matches no difference makes the exit status 1 (see --allow-unused)')
        sp.add_argument('--allow-unused', action='store_true',
                        help='do not fail when an allowance or expectation matches no difference (it is noted)')
        sp.add_argument('--allow-mixed', action='store_true',
                        help='compare snapshots whose # module: or # compiler: lines differ (refused, exit 2, '
                        'without it)')

    sp = sub.add_parser('snapshot', help='run the compiler and write a snapshot')
    common(sp)
    sp.add_argument('--rev', help='describe the module as it was at this commit')
    sp.add_argument('--overlay', help='a directory mirroring repository paths whose files replace the tree\'s')
    sp.add_argument('--out', help='copy the snapshot here too')
    sp = sub.add_parser('normalize', help='normalize compiler outputs into a snapshot')
    common(sp, compiler=False)
    sp.add_argument('--module', required=True)
    sp.add_argument('--header', help='the generated -Swift.h')
    sp.add_argument('--symbol-graph-dir', help='the directory of <module>.symbols.json (the import section, and '
                    'the swift section without --private-symbol-graph-dir)')
    sp.add_argument('--private-symbol-graph-dir', help='the directory of swift-symbolgraph-extract\'s output (the '
                    'swift section)')
    sp.add_argument('--out', required=True)
    sp = sub.add_parser('diff', help='diff two snapshots', epilog=NOT_DETECTED,
                        formatter_class=argparse.RawDescriptionHelpFormatter)
    sp.add_argument('old')
    sp.add_argument('new')
    sp.add_argument('--sections', type=parse_sections, default=None)
    allow_opts(sp)
    sp = sub.add_parser('check', help='snapshot the work tree and diff it against --rev or --against',
                        epilog=NOT_DETECTED, formatter_class=argparse.RawDescriptionHelpFormatter)
    common(sp)
    sp.add_argument('--rev', help='compare with the module as it was at this commit (for a commit: HEAD~1)')
    sp.add_argument('--against', help='compare with this stored snapshot')
    allow_opts(sp)
    sp = sub.add_parser('imports', help='write the import section into a code database')
    common(sp)
    sp.add_argument('--db', help='the database to write the swift_import tables into (required; there is no '
                    'default, so that the shared tmp/codedb/codedb.sqlite is never written by accident)')
    sp = sub.add_parser('swiftname', help='how Swift spells an Objective-C declaration')
    sp.add_argument('name')
    sp.add_argument('--root', default=codedb.REPO_ROOT)
    sp.add_argument('--db', help='the database (default tmp/codedb/codedb.sqlite)')
    sp.add_argument('--module')
    args = p.parse_args(argv)
    if args.command is None:
        p.print_help()
        return EXIT_ERROR
    try:
        return dispatch(args)
    except StaleCapture as e:
        sys.stderr.write('swift_interface: %s\nPass --accept-stale to proceed; the result is then marked INCOMPLETE.\n'
                         % e)
        return EXIT_INCOMPLETE
    except (InterfaceError, codedb.CodeDBError, OSError) as e:
        sys.stderr.write('swift_interface: error: %s\n' % e)
        return EXIT_ERROR


def run_check(args, paths, work_root, log):
    new = run_snapshot(paths, work_root, args.module, 'worktree', args, log=log)
    if new.snapshot is None:
        return EXIT_INCOMPLETE
    if args.against:
        old_path = args.against
    else:
        label, tree = overlay_for(args, paths, work_root, args.module)
        old = run_snapshot(paths, work_root, args.module, label, args, tree, log=log)
        if old.snapshot is None:
            return EXIT_INCOMPLETE
        old_path = old.snapshot
    return diff_snapshots(old_path, new.snapshot, allowances(args), sections=args.sections, out=sys.stdout,
                          allow_unused=args.allow_unused, allow_mixed=args.allow_mixed)


def dispatch(args):
    log = lambda m: sys.stderr.write(m + '\n')  # noqa: E731
    if args.command == 'normalize':
        if 'objc' in args.sections and not args.header:
            raise InterfaceError('--header is needed for the objc section')
        if set(args.sections) & {'swift', 'import'} and not args.symbol_graph_dir:
            raise InterfaceError('--symbol-graph-dir is needed for the swift and import sections')
        n = write_snapshot(args.out, args.module, args.header, args.symbol_graph_dir, sections=args.sections,
                           private_sg_dir=args.private_symbol_graph_dir)
        log('%d declarations -> %s' % (n, args.out))
        return EXIT_SAME
    if args.command == 'diff':
        return diff_snapshots(args.old, args.new, allowances(args), sections=args.sections, out=sys.stdout,
                              allow_unused=args.allow_unused, allow_mixed=args.allow_mixed)
    if args.command == 'swiftname':
        db = args.db or codedb.Paths(os.path.realpath(args.root)).db
        return swiftname(db, os.path.realpath(args.root), args.name, module=args.module)
    if args.command == 'imports' and not args.db:
        raise InterfaceError('imports needs --db: it writes the swift_import tables into the database named by --db, '
                             'never by default into the shared one under tmp/codedb/')
    paths, work_root = make_paths(args)
    if args.command == 'snapshot':
        label, tree = overlay_for(args, paths, work_root, args.module)
        r = run_snapshot(paths, work_root, args.module, label, args, tree, log=log)
        if r.snapshot and args.out:
            shutil.copyfile(r.snapshot, args.out)
        return r.status
    if args.command == 'check':
        if bool(args.rev) == bool(args.against):
            raise InterfaceError('check needs exactly one of --rev and --against')
        try:
            return run_check(args, paths, work_root, log)
        finally:
            sys.stdout.write(NOT_DETECTED_POINTER + '\n')
    if args.command == 'imports':
        db = args.db
        args.sections = ('import',)
        r = run_snapshot(paths, work_root, args.module, 'imports', args, log=log, keep_raw=True)
        if r.snapshot is None:
            return EXIT_INCOMPLETE
        work = Work(os.path.join(work_root, args.module, 'imports'))
        digests = input_digests(paths.root, work.deps)
        n = write_imports(db, args.module, r.sg_dir, digests, r.compiler, r.incomplete)
        if not args.keep_raw:
            shutil.rmtree(r.sg_dir, ignore_errors=True)
        log('imports: %d rows for %s in %s (%d inputs recorded)' % (n, args.module, db, len(digests)))
        return r.status
    raise InterfaceError('unknown command %s' % args.command)


if __name__ == '__main__':
    sys.exit(main())
