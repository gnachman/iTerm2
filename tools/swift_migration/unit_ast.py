#!/usr/bin/env python3
"""Facts about one Objective-C implementation file from Clang's AST, for the
trivial path's qualifying checks (docs/swift-migration/lifecycle.md section
3, qualify_unit.py conditions T1, T4 and T6).

The file is parsed by upstream clang (the LLVM the code database's extractor
uses, as extraction/extract_check.py finds it) with its command from the
compile database and -fsyntax-only -Xclang -ast-dump=json. The dump is
streamed to a temporary file outside the repository and read one top-level
declaration at a time; only declarations written in the main file are parsed
as JSON. Nothing here lexes C: every extent, kind, type and selector is the
compiler's.

Reported, for the declarations of the main file:

  bodies      every method and C function defined there, with the first and
              last line of its body (the compound statement, opening brace to
              closing brace); body_lines is the sum of (last - first + 1);
  ownership   what moving the file to ARC would change or reject: sends of
              retain, release, autorelease, retainCount, dealloc and drain;
              calls of functions named *Retain, *Release, *Autorelease,
              CFBridging* and objc_retain/release/autorelease*; block
              literals (copied differently under ARC); bridged casts and
              casts between C and Objective-C pointers; sends of methods of
              the alloc, copy, mutableCopy and new families (the caller owns
              the result, so without ARC it must release it or leak it) and
              definitions of such methods (they return a retained object);
  retained    Core Foundation ownership a Swift port cannot promise to
              Objective-C callers, with or without ARC: a definition that
              returns a CF or CG ...Ref of the alloc, new, copy or
              mutableCopy family, named with Create or Copy, or marked
              CF_RETURNS_RETAINED or NS_RETURNS_RETAINED; a call of a
              *Retain, *Release or CFBridging* function or of a Create
              Rule function (CFStringCreate..., CGColorCreate...); a
              __bridge_transfer or __bridge_retained cast. A borrowed ...Ref
              that only passes through is not reported;
  functions   every C function the code refers to, with its line, macro
              expansions included (qualify_unit.py looks for associated
              objects, swizzling, locks and queues among them);
  unsafe      C pointers and C arrays: a variable, parameter, field, method
              result, function type or cast whose type is a pointer to
              anything but an Objective-C object, a pointer to a pointer, a
              function pointer or an array; a dereference, a C subscript, a
              -> member access, an address-of anything but an Objective-C
              object variable (so `&error` passes), a C string literal or
              __func__-style name, and a C function argument of such a type.
              Code that a macro defined outside the main file expanded to
              (DLog, the assertion macros) is not checked for this; its
              arguments are.

A type is an Objective-C object pointer when the identifier before its * is a
class the caller names (the code database's classes, the SDK's and Swift's
@objc classes); anything else is counted as a C pointer, the conservative
answer.

Usage (for a person; qualify_unit.py imports it):

  unit_ast.py [--root DIR] [--cdb FILE] [--like RELPATH] [--clang PATH] FILE

prints the facts of FILE as JSON. --like takes the compile command of another
file (for a file the compile database does not list, such as an old revision
written under tmp/). Exit 0, or 2 on an error.
"""

import argparse
import json
import os
import re
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
for _d in (HERE, os.path.join(HERE, 'extraction'), os.path.join(HERE, 'codedb')):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import codedb  # noqa: E402
import extract_check  # noqa: E402

AST_TIMEOUT = 600
OWNERSHIP_SELECTORS = ('retain', 'release', 'autorelease', 'retainCount', 'dealloc', 'drain')
OWNERSHIP_FUNCTION = re.compile(r'(?:Retain|Release|Autorelease)$|^CFBridging|^objc_(?:retain|release|autorelease)')
OWNERSHIP_CASTS = ('CPointerToObjCPointerCast', 'ARCConsumeObject', 'ARCProduceObject', 'ARCReclaimReturnedObject',
                   'ARCExtendBlockObject')
RETAINED_FAMILIES = ('alloc', 'copy', 'mutableCopy', 'new')
# Core Foundation style types and the Create Rule: a function whose name
# has Create or Copy returns an object the caller owns.
CF_TYPE = re.compile(r'^(?:CF|CG|CT|CV|Sec|IOSurface)\w*Ref$')
CREATE_RULE = re.compile(r'^(?:CF|CG|CT|CV|Sec|IOSurface)\w*(?:Create|Copy)')
RETAINED_ATTRS = ('CFReturnsRetainedAttr', 'NSReturnsRetainedAttr')
TYPED_DECLS = ('VarDecl', 'ParmVarDecl', 'FieldDecl', 'ObjCPropertyDecl', 'CStyleCastExpr')
_QUALIFIERS = re.compile(r'\b(?:_Nonnull|_Nullable|_Null_unspecified|_Nullable_result|__strong|__weak|'
                         r'__autoreleasing|__unsafe_unretained|__kindof|const|volatile|restrict|__restrict)\b')
_FILE_LINE = re.compile(r'^\s*"file": ("(?:[^"\\]|\\.)*"),?$')
_LINE_LINE = re.compile(r'^\s*"line": (\d+),?$')
_TOP_START = '    {'
_TOP_ENDS = ('    }', '    },')


class ASTError(Exception):
    pass


def strip_generics(t):
    """t without <...> lists (generic arguments, protocol qualifiers)."""
    out, depth = [], 0
    for ch in t:
        if ch == '<':
            depth += 1
        elif ch == '>':
            depth = max(depth - 1, 0)
        elif depth == 0:
            out.append(ch)
    return ''.join(out)


def unsafe_type(qual_type, classes):
    """Why qual_type is a C pointer or array, or None: an array, a pointer to
    a pointer, a function pointer, or a pointer whose pointee is not one of
    classes (Objective-C classes)."""
    t = _QUALIFIERS.sub(' ', strip_generics(qual_type or ''))
    if '[' in t:
        return 'a C array (%s)' % qual_type
    for i, ch in enumerate(t):
        if ch != '*':
            continue
        before = t[:i].rstrip()
        if before.endswith('*'):
            return 'a pointer to a pointer (%s)' % qual_type
        if before.endswith('('):
            return 'a function pointer (%s)' % qual_type
        m = re.search(r'([A-Za-z_]\w*)$', before)
        if not m or m.group(1) not in classes:
            return 'a C pointer (%s)' % qual_type
    return None


def is_objc_pointer(qual_type, classes):
    t = _QUALIFIERS.sub(' ', strip_generics(qual_type or '')).strip()
    return t.endswith('*') and unsafe_type(qual_type, classes) is None or t in ('id', 'Class', 'instancetype')


def method_family(selector):
    """The Cocoa method family of a selector among RETAINED_FAMILIES, or
    None."""
    s = selector.lstrip('_')
    for fam in RETAINED_FAMILIES:
        if s.startswith(fam) and (len(s) == len(fam) or not s[len(fam)].islower()):
            return fam
    return None


# --- Reading the dump.

def resolve(node, state):
    """Walk a parsed declaration in the order its keys were written,
    applying the dumper's rule that a location omits its file and line when
    they equal the last ones written; annotate every location with @file and
    @line. state is [file, line] at the declaration's start, and is left at
    its end."""
    if isinstance(node, dict):
        if 'offset' in node:
            if 'file' in node:
                state[0] = node['file']
            if 'line' in node:
                state[1] = node['line']
            node['@file'], node['@line'] = state[0], state[1]
        for k, v in node.items():
            if k != 'includedFrom' and isinstance(v, (dict, list)):
                resolve(v, state)
    elif isinstance(node, list):
        for v in node:
            resolve(v, state)


def main_file_decls(stream, main_file):
    """The top-level declarations of a JSON AST dump (a file object of its
    lines) whose location is in main_file, parsed, with locations
    resolved."""
    state = [None, None]
    buf, start, in_included, mentions = None, None, False, False
    for line in stream:
        text = line.rstrip('\n')
        if buf is None and text == _TOP_START:
            buf, start, mentions = [text], list(state), False
            continue
        if buf is not None:
            buf.append(text)
        if text.endswith('"includedFrom": {'):
            in_included = True
            continue
        m = _FILE_LINE.match(text)
        if m:
            if in_included:
                in_included = False
            else:
                state[0] = json.loads(m.group(1))
                mentions = mentions or state[0] == main_file
            continue
        m = _LINE_LINE.match(text)
        if m:
            state[1] = int(m.group(1))
        if buf is not None and text in _TOP_ENDS:
            if mentions or start[0] == main_file:
                decl = json.loads('\n'.join(buf).rstrip(','))
                resolve(decl, list(start))
                if node_file(decl) == main_file:
                    yield decl
            buf = None


def expansion(loc):
    if not loc:
        return None
    return loc.get('expansionLoc', loc) if 'expansionLoc' in loc else loc


def node_loc(node):
    loc = node.get('loc') or {}
    if not loc.get('@file') and 'expansionLoc' not in loc:
        loc = (node.get('range') or {}).get('begin') or {}
    return loc


def node_file(node):
    loc = expansion(node_loc(node))
    return loc.get('@file') if loc else None


def node_line(node):
    loc = expansion(node_loc(node))
    return loc.get('@line') if loc else None


def from_foreign_macro(node, main_file):
    """Whether node was written by a macro defined outside main_file."""
    loc = node_loc(node)
    sp = loc.get('spellingLoc') if loc else None
    return bool(sp) and sp.get('@file') != main_file


def children(node):
    return node.get('inner') or []


# --- Facts.

class Facts:
    def __init__(self, main_file, classes, arc):
        self.main_file = main_file
        self.classes = classes
        self.arc = arc
        self.bodies = []
        self.ownership = []
        self.unsafe = []
        self.retained = []
        self.functions = []

    def where(self, node):
        line = node_line(node)
        return 'line %s' % line if line else 'an unknown line'

    def add_body(self, name, decl):
        for c in children(decl):
            if c.get('kind') == 'CompoundStmt':
                r = c.get('range') or {}
                b, e = expansion(r.get('begin')), expansion(r.get('end'))
                if b and e and b.get('@line') and e.get('@line'):
                    self.bodies.append((name, b['@line'], e['@line']))
                return

    def top(self, decl):
        kind = decl.get('kind')
        if kind in ('ObjCImplementationDecl', 'ObjCCategoryImplDecl'):
            for m in children(decl):
                if m.get('kind') == 'ObjCMethodDecl' and not m.get('isImplicit'):
                    self.add_body(m.get('mangledName') or m.get('name'), m)
                    self.returns_retained(m, m.get('mangledName') or m.get('name'),
                                          (m.get('returnType') or {}).get('qualType'),
                                          bool(method_family(m.get('name') or '')))
                    if not self.arc and method_family(m.get('name') or ''):
                        self.ownership.append('%s defines %s, of the %s family (returns a retained object)' % (
                            self.where(m), m.get('mangledName') or m.get('name'),
                            method_family(m.get('name'))))
                    self.result_type(m)
        elif kind == 'FunctionDecl':
            self.add_body(decl.get('name'), decl)
            result = ((decl.get('type') or {}).get('qualType') or '').split('(')[0]
            self.returns_retained(decl, decl.get('name'), result,
                                  bool(re.search(r'Create|Copy', decl.get('name') or '')))
        self.walk(decl, checked=True)

    def returns_retained(self, decl, name, result_type, by_name):
        """A definition that returns a Core Foundation object its caller
        owns: by its name's family or Create Rule, or by an attribute."""
        t = _QUALIFIERS.sub(' ', result_type or '').strip()
        # Written attributes only: ARC adds implicit ones to every init.
        attrs = [c.get('kind') for c in children(decl) if c.get('kind') in RETAINED_ATTRS and not c.get('implicit')
                 and not c.get('inherited')]
        if attrs or (by_name and CF_TYPE.match(t)):
            self.retained.append('%s %s returns a retained %s (%s)' % (
                self.where(decl), name, t or 'object', ', '.join(attrs) or 'by its name'))

    def result_type(self, m):
        why = unsafe_type((m.get('returnType') or {}).get('qualType'), self.classes)
        if why:
            self.unsafe.append('%s %s returns %s' % (self.where(m), m.get('mangledName') or m.get('name'), why))

    def walk(self, node, checked, parent=None):
        kind = node.get('kind')
        if checked and from_foreign_macro(node, self.main_file):
            checked = False
        if not self.arc:
            self.ownership_node(node, kind)
        self.retained_node(node, kind)
        if checked:
            self.unsafe_node(node, kind, parent)
        if kind == 'ObjCStringLiteral':
            return
        for c in children(node):
            self.walk(c, checked, node)

    def ownership_node(self, node, kind):
        if kind == 'ObjCMessageExpr' and node.get('selector') in OWNERSHIP_SELECTORS:
            self.ownership.append('%s sends %s' % (self.where(node), node['selector']))
        elif kind == 'ObjCMessageExpr' and method_family(node.get('selector') or ''):
            self.ownership.append('%s sends %s, whose result the caller owns' % (self.where(node), node['selector']))
        elif kind == 'BlockExpr':
            self.ownership.append('%s a block literal' % self.where(node))
        elif kind == 'ObjCBridgedCastExpr' or node.get('castKind') in OWNERSHIP_CASTS:
            self.ownership.append('%s a cast between C and Objective-C pointers (%s)' % (
                self.where(node), node.get('castKind') or kind))
        elif kind == 'DeclRefExpr':
            ref = node.get('referencedDecl') or {}
            if ref.get('kind') == 'FunctionDecl' and OWNERSHIP_FUNCTION.search(ref.get('name') or ''):
                self.ownership.append('%s calls %s' % (self.where(node), ref['name']))

    def retained_node(self, node, kind):
        """Core Foundation ownership, with or without ARC, and every
        function the code refers to (macro expansions included)."""
        if kind == 'DeclRefExpr':
            ref = node.get('referencedDecl') or {}
            name = ref.get('name') or ''
            if ref.get('kind') == 'FunctionDecl':
                self.functions.append((node_line(node), name))
                if OWNERSHIP_FUNCTION.search(name) or CREATE_RULE.match(name):
                    self.retained.append('%s calls %s (Core Foundation ownership)' % (self.where(node), name))
        # The dump does not name the bridge keyword; the casts ARC adds
        # around a bridged cast tell them apart (checked with clang 22):
        # __bridge_transfer is ARCConsumeObject over the bridged cast,
        # __bridge_retained is ARCProduceObject under it, and __bridge has
        # neither directly.
        elif kind == 'ObjCBridgedCastExpr' and any(c.get('castKind') == 'ARCProduceObject' for c in children(node)):
            self.retained.append('%s a __bridge_retained cast' % self.where(node))
        elif node.get('castKind') == 'ARCConsumeObject' and any(c.get('kind') == 'ObjCBridgedCastExpr'
                                                                for c in children(node)):
            self.retained.append('%s a __bridge_transfer cast' % self.where(node))

    def unsafe_node(self, node, kind, parent):
        where = self.where(node)
        if kind in TYPED_DECLS or kind == 'FunctionDecl':
            if not node.get('isImplicit'):
                why = unsafe_type((node.get('type') or {}).get('qualType'), self.classes)
                if why:
                    self.unsafe.append('%s %s %s is %s' % (where, kind, node.get('name') or '', why))
        elif kind == 'ArraySubscriptExpr':
            self.unsafe.append('%s a C subscript' % where)
        elif kind == 'UnaryOperator' and node.get('opcode') == '*':
            self.unsafe.append('%s a dereference' % where)
        elif kind == 'UnaryOperator' and node.get('opcode') == '&':
            operand = (children(node) or [{}])[0]
            if not is_objc_pointer((operand.get('type') or {}).get('qualType'), self.classes):
                self.unsafe.append('%s takes the address of %s' % (
                    where, (operand.get('type') or {}).get('qualType') or 'something'))
        elif kind == 'MemberExpr' and node.get('isArrow'):
            self.unsafe.append('%s a -> member access' % where)
        elif kind in ('StringLiteral', 'PredefinedExpr'):
            self.unsafe.append('%s a C string (%s)' % (where, kind))
        elif kind == 'CallExpr':
            for arg in children(node)[1:]:
                why = unsafe_type((arg.get('type') or {}).get('qualType'), self.classes)
                if why:
                    self.unsafe.append('%s passes %s to a C function' % (where, why))

    def result(self):
        return {'main_file': self.main_file, 'arc': self.arc,
                'bodies': [{'name': n, 'first': a, 'last': b, 'lines': b - a + 1} for n, a, b in self.bodies],
                'body_lines': sum(b - a + 1 for _, a, b in self.bodies),
                'ownership': unique(self.ownership), 'unsafe': unique(self.unsafe),
                'retained': unique(self.retained),
                'functions': [list(x) for x in sorted(set(self.functions), key=lambda x: (x[0] or 0, x[1]))]}


def unique(items):
    """items without repeats, in order (a declaration statement and a block
    show some nodes twice)."""
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def file_facts(clang, args, main_abs, classes, arc, cwd=None, timeout=AST_TIMEOUT):
    """The facts of main_abs, parsed with args (a compile command without
    the compiler, naming main_abs)."""
    cmd = [clang] + list(args) + ['-fsyntax-only', '-Wno-everything', '-Xclang', '-ast-dump=json']
    try:
        st = os.stat(main_abs)
    except OSError as e:
        raise ASTError('%s cannot be read (%s)' % (main_abs, e.strerror or e))
    key = (tuple(cmd), st.st_mtime_ns, st.st_size, bool(arc), hash(frozenset(classes)))
    if key not in _CACHE:
        _CACHE[key] = _file_facts(cmd, main_abs, classes, arc, cwd, timeout)
    return json.loads(json.dumps(_CACHE[key]))


# Facts already computed in this process, by command and file state.
_CACHE = {}


def _file_facts(cmd, main_abs, classes, arc, cwd, timeout):
    with tempfile.TemporaryFile(mode='w+', prefix='unit-ast-') as out:
        status, err = codedb.run_in_group(cmd, cwd=cwd, stdout=out, timeout=timeout)
        if status != 0:
            raise ASTError('clang could not parse %s (exit %s): %s' % (
                main_abs, status, ' | '.join((err or '').strip().splitlines()[:3]) or 'no message'))
        out.seek(0)
        facts = Facts(main_abs, classes, arc)
        for decl in main_file_decls(out, main_abs):
            facts.top(decl)
    return facts.result()


def compile_command(root, relpath, cdb, like=None):
    """(clang args, absolute main file) for relpath, from the compile
    database (the command of like when given), with the main file argument
    naming relpath under root and the module cache under this checkout's
    tmp/extraction/modcache."""
    tool_root = os.path.dirname(os.path.dirname(HERE))
    try:
        args, named, _ = extract_check.compile_command(tool_root, like or relpath, cdb)
    except extract_check.ToolError as e:
        raise ASTError(str(e))
    main_abs = os.path.join(root, relpath)
    return [main_abs if a == named else a for a in args], main_abs


def default_clang():
    try:
        return extract_check.llvm_clang()
    except extract_check.ToolError as e:
        raise ASTError(str(e))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--root', default=os.path.abspath(os.path.join(HERE, '..', '..')))
    p.add_argument('--cdb')
    p.add_argument('--like')
    p.add_argument('--clang')
    p.add_argument('--arc', action='store_true', help='the file is compiled with ARC')
    p.add_argument('--classes', help='a file of Objective-C class names, one per line')
    p.add_argument('file')
    a = p.parse_args(argv)
    try:
        rel = os.path.relpath(os.path.abspath(a.file), a.root)
        cdb = a.cdb or os.path.join(a.root, 'tmp', 'codedb', 'compile_commands.jsonl')
        args, main_abs = compile_command(a.root, rel, cdb, a.like)
        classes = set()
        if a.classes:
            with open(a.classes) as f:
                classes = set(x.strip() for x in f if x.strip())
        facts = file_facts(a.clang or default_clang(), args, main_abs, classes, a.arc, cwd=a.root)
    except (ASTError, OSError) as e:
        print('unit_ast: error: %s' % e, file=sys.stderr)
        return 2
    json.dump(facts, sys.stdout, indent=1)
    sys.stdout.write('\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
