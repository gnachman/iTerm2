#!/usr/bin/env python3
"""Cross-check of the code database against the app's object files.

codedb.py crosscheck [--target T] [--file F] [--list-explained]
[--build-root DIR]... runs this.

The database is built by upstream Clang from the captured compile commands;
the app is built by Xcode's Clang. The object files are the ground truth of
what the app does, so for every Objective-C translation unit (.m or .mm) of
the database this compares, read-only:

  selectors sent    the object's undefined _objc_msgSend$SELECTOR symbols
                    (the selector stubs Xcode's Clang emits for each message
                    send) and its __objc_selrefs entries (selectors referenced
                    otherwise: @selector, super sends through
                    objc_msgSendSuper2, which have no stub and appear only
                    here, and sends where no stub is used), against the
                    unit's send and selector_ref rows;
  call sites        per selector, the branch relocations to its stub in the
                    object's code, against the unit's send rows of it (see
                    "Call-site counts" below): the set comparison finds a
                    missed send only when it is the unit's only send of the
                    selector, the counts find the others;
  methods defined   the object's -[Class sel] and +[Class sel] symbols
                    (Class(Category) for a category; an objc_direct method of
                    a category has no category in its symbol), against the
                    unit's objc_method rows that are definitions in an
                    implementation or category implementation (synthesized
                    accessors included);
  ivars defined     the object's _OBJC_IVAR_$_Class.name symbols, against the
                    objc_ivar rows of the classes whose @implementation the
                    unit holds (objc_impl), from the unit itself or from the
                    files it reads (a header's ivars are recorded by the unit
                    that holds the header's claim, also for a header that
                    units read only through a Clang module). Should a class
                    have no ivar in objc_ivar at all while its object defines
                    some, the output names the cause this once was (ivars of
                    a header read only through a module, now recorded).

Every difference is classified by a rule of RULES or COUNT_RULES (printed
with the output), or is UNEXPLAINED. A unit is not compared when its object
file is missing, older than any repository file the unit read (a stale
build), changed or vanished while it was read, a fat file without an arm64
slice, or unreadable, or when its rows in the database are not current. The
Objective-C files of the migration's scope that no captured unit compiles
are counted and listed.

Object files are read one at a time with a small Mach-O reader (the symbol
table, the sections, the relocations of __objc_selrefs and of the code
sections; the arm64 slice of a fat file); nothing else is run. The object
of a unit is the output its captured command named, under Build/; a variant
directory (Variant-NoSanitizers) the capture used and the build no longer
has is tried without it. --build-root DIR looks the objects up under DIR in
place of Build/ (DIR holds Intermediates.noindex), for a build of the same
sources made later or with other flags, such as a sanitizer build
(Objects-normal-tsan is tried for a thread sanitizer build).

Exit status: 0 no unexplained difference and every unit was compared; 1
unexplained differences; 3 some units could not be compared (and none
unexplained); 2 error.
"""

import collections
import os
import re
import struct
import sys

# --- Mach-O ------------------------------------------------------------------

MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
FAT_MAGIC_64 = 0xcafebabf
CPU_TYPE_ARM64 = 0x0100000c
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
N_STAB = 0xe0
N_TYPE = 0x0e
N_SECT = 0x0e
N_UNDF = 0x0
# Section attributes of code (S_ATTR_PURE_INSTRUCTIONS, S_ATTR_SOME_INSTRUCTIONS).
S_ATTR_INSTRUCTIONS = 0x80000000 | 0x00000400
ARM64_RELOC_BRANCH26 = 2
STUB_PREFIX = '_objc_msgSend$'


class MachOError(Exception):
    pass


# call_sites: {selector: the number of branch relocations (bl or b) in code
# sections whose target is the selector's _objc_msgSend$ stub}, one per call
# site. fat: None for a thin file, or how the slice was chosen.
# mangled: the defined symbols with an Itanium C++ mangled name (_Z..., and
# ___Z..._block_invoke for a block in a C++ function), or None to derive
# them from defined_functions.
ObjectFacts = collections.namedtuple('ObjectFacts', 'stubs selrefs methods ivars undefined defined_functions '
                                                    'call_sites fat mangled', defaults=(None, None, None))


def _cstring(data, start):
    end = data.find(b'\0', start)
    if end < 0:
        raise MachOError('unterminated string at %d' % start)
    return data[start:end].decode('utf-8', 'replace')


def thin_slice(data):
    """(the arm64 Mach-O bytes of data, a note): data itself for a thin
    file; for a fat (universal) file its arm64 slice, or MachOError when it
    has none."""
    if len(data) < 8:
        raise MachOError('too short for a Mach-O header')
    magic, nfat = struct.unpack_from('>II', data, 0)
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        return data, None
    is64 = magic == FAT_MAGIC_64
    size = 32 if is64 else 20
    archs = []
    for i in range(nfat):
        if is64:
            cputype, _, offset, length, _, _ = struct.unpack_from('>iiQQII', data, 8 + size * i)
        else:
            cputype, _, offset, length, _ = struct.unpack_from('>iiIII', data, 8 + size * i)
        archs.append((cputype & 0xffffffff, offset, length))
    for cputype, offset, length in archs:
        if cputype == CPU_TYPE_ARM64:
            if offset + length > len(data):
                raise MachOError('fat file: the arm64 slice runs past the end of the file')
            return data[offset:offset + length], 'fat file, arm64 slice read (%d architectures)' % len(archs)
    raise MachOError('fat file without an arm64 slice (%d architectures)' % len(archs))


def read_object(data):
    """The facts of a 64-bit Mach-O object file (bytes; for a fat file, its
    arm64 slice): ObjectFacts of sets: stubs (selectors of _objc_msgSend$
    symbols), selrefs (selectors in __objc_selrefs), methods (-[...] and
    +[...] symbols defined), ivars (Class.name of defined _OBJC_IVAR_$_
    symbols), undefined (every undefined symbol) and defined_functions
    (every defined symbol in a section, with its leading underscore); and
    call_sites, a Counter of the branch relocations to each stub."""
    data, fat = thin_slice(data)
    if len(data) < 32:
        raise MachOError('too short for a Mach-O header')
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', data, 0)
    if magic != MH_MAGIC_64:
        raise MachOError('not a 64-bit little-endian Mach-O file (magic %#x)' % magic)
    off = 32
    sections = []
    symtab = None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, off)
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from('<I', data, off + 64)[0]
            s = off + 72
            for _ in range(nsects):
                sect, seg = data[s:s + 16].rstrip(b'\0').decode(), data[s + 16:s + 32].rstrip(b'\0').decode()
                addr, sz, offset, _, reloff, nreloc, flags = struct.unpack_from('<QQIIIII', data, s + 32)
                sections.append((seg, sect, addr, sz, offset, reloff, nreloc, flags))
                s += 80
        elif cmd == LC_SYMTAB:
            symtab = struct.unpack_from('<IIII', data, off + 8)
        off += size
    symbols = []
    if symtab:
        symoff, nsyms, stroff, _ = symtab
        for i in range(nsyms):
            strx, ntype, nsect, _, value = struct.unpack_from('<IBBhQ', data, symoff + 16 * i)
            symbols.append((_cstring(data, stroff + strx), ntype, nsect, value))
    stubs, methods, ivars, undefined, defined = set(), set(), set(), set(), set()
    for name, ntype, nsect, _ in symbols:
        if ntype & N_STAB:
            continue
        kind = ntype & N_TYPE
        if kind == N_UNDF:
            undefined.add(name)
            if name.startswith(STUB_PREFIX):
                stubs.add(name[len(STUB_PREFIX):])
        elif kind == N_SECT:
            defined.add(name)
            if name.startswith(('-[', '+[')) and name.endswith(']'):
                methods.add(name)
            elif name.startswith('_OBJC_IVAR_$_'):
                ivars.add(name[len('_OBJC_IVAR_$_'):])

    def section_of(address):
        for seg, sect, addr, sz, offset, _, _, _ in sections:
            if addr <= address < addr + sz and offset:
                return offset + address - addr
        return None

    def relocations(reloff, nreloc):
        """{address: (symbolnum, extern, type)}."""
        out = {}
        for i in range(nreloc):
            address, packed = struct.unpack_from('<iI', data, reloff + 8 * i)
            out[address] = (packed & 0xffffff, (packed >> 27) & 1, (packed >> 28) & 0xf)
        return out

    selrefs = set()
    call_sites = collections.Counter()
    for seg, sect, addr, sz, offset, reloff, nreloc, flags in sections:
        if flags & S_ATTR_INSTRUCTIONS:
            for symbolnum, extern, rtype in relocations(reloff, nreloc).values():
                if rtype == ARM64_RELOC_BRANCH26 and extern and symbolnum < len(symbols):
                    name = symbols[symbolnum][0]
                    if name.startswith(STUB_PREFIX):
                        call_sites[name[len(STUB_PREFIX):]] += 1
        if sect != '__objc_selrefs':
            continue
        relocs = relocations(reloff, nreloc)
        for k in range(0, sz, 8):
            value = struct.unpack_from('<Q', data, offset + k)[0]
            reloc = relocs.get(k)
            if reloc is None and value == 0:
                raise MachOError('selector reference at %#x has no relocation and the value 0' % (addr + k))
            if reloc and reloc[1]:
                value += symbols[reloc[0]][3]
            where = section_of(value)
            if where is None:
                raise MachOError('selector reference at %#x points outside every section' % (addr + k))
            selrefs.add(_cstring(data, where))
    return ObjectFacts(stubs, selrefs, methods, ivars, undefined, defined, call_sites, fat, mangled_symbols(defined))


# --- Rules -----------------------------------------------------------------------
#
# Every rule that explains a difference. side: 'object' (in the object file,
# not in the database: the compiler sends it for something the AST has no
# send for), 'database' (in the database, not in the object file: the
# compiler made no send), 'method' (a method the object defines and the
# database does not). selectors: the selectors it applies to, or None for any.
# needs: undefined symbols that must be in the object for the rule to apply
# (the evidence: the runtime function the compiler called in place of the
# send); defines: a method the unit must define. Derived from the evidence
# of the whole-tree run and of the fixture tests (test_codedb_crosscheck.py).

Rule = collections.namedtuple('Rule', 'name side selectors needs defines comment arc', defaults=(False,))

RULES = [
    # Literals and boxing: the AST has an ObjCArrayLiteral, ObjCDictionaryLiteral
    # or ObjCBoxedExpr, not an ObjCMessageExpr, so the extractor records no send.
    Rule('array-literal', 'object', {'arrayWithObjects:count:'}, (), None,
         'an array literal @[...]: the compiler sends +[NSArray arrayWithObjects:count:]'),
    Rule('dictionary-literal', 'object', {'dictionaryWithObjects:forKeys:count:'}, (), None,
         'a dictionary literal @{...}: the compiler sends +[NSDictionary dictionaryWithObjects:forKeys:count:]'),
    Rule('boxed-number', 'object',
         {'numberWithChar:', 'numberWithUnsignedChar:', 'numberWithShort:', 'numberWithUnsignedShort:',
          'numberWithInt:', 'numberWithUnsignedInt:', 'numberWithLong:', 'numberWithUnsignedLong:',
          'numberWithLongLong:', 'numberWithUnsignedLongLong:', 'numberWithFloat:', 'numberWithDouble:',
          'numberWithBool:', 'numberWithInteger:', 'numberWithUnsignedInteger:'}, (), None,
         'a boxed number @(x), @1, @YES: the compiler sends +[NSNumber numberWith...:]'),
    Rule('boxed-string', 'object', {'stringWithUTF8String:'}, (), None,
         'a boxed C string @(s): the compiler sends +[NSString stringWithUTF8String:]'),
    Rule('boxed-value', 'object', {'valueWithBytes:objCType:'}, (), None,
         'a boxed structure @(rect): the compiler sends +[NSValue valueWithBytes:objCType:]'),
    # for (x in collection): the AST has an ObjCForCollectionStmt.
    Rule('fast-enumeration', 'object', {'countByEnumeratingWithState:objects:count:'}, (), None,
         'for (x in collection): the compiler sends countByEnumeratingWithState:objects:count:'),
    # ARC ends every -dealloc with [super dealloc], which the source may not write.
    Rule('arc-super-dealloc', 'object', {'dealloc'}, (), 'dealloc',
         'under ARC the compiler ends -dealloc with [super dealloc] (a super send, in __objc_selrefs)', True),
    # Message sends the compiler turns into calls of runtime functions (Clang's
    # objc runtime entry points for the deployment target): no stub, no selref.
    Rule('runtime-alloc', 'database', {'alloc'}, ('_objc_alloc', '_objc_alloc_init'), None,
         '+alloc is called through objc_alloc or objc_alloc_init'),
    Rule('runtime-alloc-init', 'database', {'init'}, ('_objc_alloc_init',), None,
         '[[X alloc] init] is called through objc_alloc_init'),
    Rule('runtime-allocWithZone', 'database', {'allocWithZone:'}, ('_objc_allocWithZone',), None,
         '+allocWithZone: is called through objc_allocWithZone'),
    Rule('runtime-new', 'database', {'new'}, ('_objc_opt_new',), None, '+new is called through objc_opt_new'),
    Rule('runtime-class', 'database', {'class'}, ('_objc_opt_class',), None,
         '-class and +class are called through objc_opt_class'),
    Rule('runtime-self', 'database', {'self'}, ('_objc_opt_self',), None, '-self is called through objc_opt_self'),
    Rule('runtime-isKindOfClass', 'database', {'isKindOfClass:'}, ('_objc_opt_isKindOfClass',), None,
         'isKindOfClass: is called through objc_opt_isKindOfClass'),
    Rule('runtime-respondsToSelector', 'database', {'respondsToSelector:'}, ('_objc_opt_respondsToSelector',), None,
         'respondsToSelector: is called through objc_opt_respondsToSelector'),
    Rule('runtime-retain', 'database', {'retain'}, ('_objc_retain',), None,
         'manual reference counting: -retain is called through objc_retain'),
    Rule('runtime-release', 'database', {'release'}, ('_objc_release',), None,
         'manual reference counting: -release is called through objc_release'),
    Rule('runtime-autorelease', 'database', {'autorelease'}, ('_objc_autorelease',), None,
         'manual reference counting: -autorelease is called through objc_autorelease'),
    # Code the compiler does not emit: a static or inline function (often in a
    # header) that the unit never calls. Applies when every row of the
    # selector in the unit is in a function whose symbol the object lacks.
    # A C++ function, or a C function of an Objective-C++ unit, is looked up
    # by its mangled name (emitted()).
    Rule('not-emitted', 'database', None, (), None,
         'every send of it in the unit is in a function the object does not define (an unused static or inline '
         'function, as in a header; a C++ function, or a C function compiled as C++, is looked up by its mangled '
         'name): the compiler emitted no code for it'),
    # Code the compiler does not emit because a condition folds to a constant
    # (if (0), const BOOL debug = NO; if (debug), 0 && x, c ? x : y): the
    # extractor marks a send row only where the compiler certainly emits
    # nothing at -O0 (send.in_constant_false_branch; the rule, narrower than
    # what the compiler drops, is in extract_sends.cpp, "Constant
    # conditions"). Applies when every row of the selector in the unit is so
    # marked or is in a function the object does not define, and at least one
    # is marked.
    Rule('constant-false-branch', 'database', None, (), None,
         'every send of it in the unit is in a branch that a constant condition skips (the extractor marks such '
         'rows, in_constant_false_branch), or in a function the object does not define: the compiler emitted no '
         'code for it'),
    # A method declared __attribute__((objc_direct)) is called as a function:
    # the object references its implementation's symbol and sends nothing.
    Rule('direct-method', 'database', None, (), None,
         'a direct method (objc_direct): the compiler calls its implementation -[Class sel] as a function; '
         'applies when the object defines or references such a symbol for the selector'),
    Rule('cxx-destruct', 'method', {'.cxx_destruct', '.cxx_construct'}, (), None,
         'the compiler adds .cxx_destruct (and .cxx_construct) to a class with ivars that need destruction or '
         'construction (ARC object ivars, C++ objects)'),
]


def selector_of_method(name):
    """'sel' from '-[Class(Cat) sel]'."""
    return name[2:-1].split(' ', 1)[1] if ' ' in name else ''


def method_symbol(is_class, container_name, selector):
    return '%s[%s %s]' % ('+' if is_class else '-', container_name, selector)


def function_symbols(enclosing):
    """The symbols that hold the code of an enclosing function or method as
    the database names it (enclosing_name), or None when it cannot be told
    (a C++ function, whose symbol is mangled)."""
    if enclosing is None:
        return None
    if enclosing.startswith(('-[', '+[')):
        # An objc_direct method of a category has no category in its symbol.
        plain = without_category(enclosing)
        return {enclosing, plain} if plain else {enclosing}
    if enclosing.replace('_', 'a').isalnum():
        return {'_' + enclosing}
    return None


def mangled_symbols(defined):
    """The symbols of defined that have an Itanium C++ mangled name."""
    return [s for s in defined if s.lstrip('_').startswith('Z')]


def cxx_components(enclosing):
    """(identifiers, suffix): the identifiers that the mangled name of the
    function enclosing names must contain, in order (Itanium ABI: each as
    <length><name>), and the letter that must follow the last of them:
    'C' for a constructor (X::X, mangled as X then C1, C2 or C3) and 'D'
    for a destructor (X::~X, X then D0, D1 or D2), whose own name is not
    written as an identifier; None otherwise. Template arguments are
    dropped. A leading std is dropped too: the ABI writes std:: as the
    abbreviation St, not as 3std. None when it cannot be told (an
    Objective-C method, an operator, a name that is not made of
    identifiers)."""
    if enclosing is None or enclosing.startswith(('-[', '+[')):
        return None
    parts = enclosing.split('::')
    suffix = None
    if len(parts) > 1 and parts[-1].startswith('~'):
        parts, suffix = parts[:-1], 'D'
    elif len(parts) > 1 and parts[-1] == parts[-2]:
        parts, suffix = parts[:-1], 'C'
    out = []
    for p in parts:
        if '<' in p:
            p = p[:p.index('<')]
        if not p or not p.replace('_', 'a').isalnum() or p[0].isdigit() or p.startswith('operator'):
            return None
        out.append(p)
    if len(out) > 1 and out[0] == 'std':
        out = out[1:]
    return (out, suffix) if out else None


def mangled_names(symbol, components, suffix=None):
    """Whether the mangled symbol contains each component as <length><name>,
    in order. A match inside a longer token (1Foo in 11Foo) or after an
    identifier that ends in a digit (6iTerm2 then 11TexturePage) is not
    told apart: either way the function is taken as emitted, the safe
    direction. For a constructor or destructor of a class template the
    template arguments (I...E) come between the class and C1 or D1."""
    pos = 0
    for n, c in enumerate(components):
        token = '%d%s' % (len(c), c)
        while True:
            i = symbol.find(token, pos)
            if i < 0:
                return False
            pos = i + len(token)
            if n < len(components) - 1 or suffix is None or symbol.startswith(suffix, pos):
                break
            if symbol.startswith('I', pos) and re.match(r'I.*?E%s[0-9]' % suffix, symbol[pos:]):
                break
    return True


def emitted(enclosing, facts):
    """Whether the object holds the code of the function or method the
    database names enclosing: True, False, or None when it cannot be told.
    A C function is found by its C symbol, or, compiled as C++ (an
    Objective-C++ unit), by its mangled name; a C++ function by its mangled
    name, and a function declared extern "C" inside a namespace by the C
    symbol of its last name. Matching mangled names by their identifiers can
    only take a function as emitted that is not (an overload, another
    function of the same names), which is the safe direction: its sends are
    then expected in the object. False is returned only when no symbol of
    the object can be the function's; None for a name that cannot be
    matched (an operator, a lambda)."""
    syms = function_symbols(enclosing)
    if syms is not None and syms & facts.defined_functions:
        return True
    parsed = cxx_components(enclosing)
    if parsed is None:
        return None if syms is None else False
    components, suffix = parsed
    if suffix is None and '_' + components[-1] in facts.defined_functions:
        return True
    mangled = facts.mangled if facts.mangled is not None else mangled_symbols(facts.defined_functions)
    if any(mangled_names(sym, components, suffix) for sym in mangled):
        return True
    return False


# --- Comparison ----------------------------------------------------------------

Difference = collections.namedtuple('Difference', 'kind name rule')


def explain_selector(side, selector, facts, unit):
    for rule in RULES:
        if rule.side != side or (rule.selectors is not None and selector not in rule.selectors):
            continue
        if rule.needs and not any(sym in facts.undefined for sym in rule.needs):
            continue
        if rule.defines and rule.defines not in unit['defined_selectors']:
            continue
        if rule.arc and not unit.get('arc'):
            continue
        if rule.name == 'direct-method':
            suffix = ' %s]' % selector
            if not any(sym.lstrip('\x01').startswith(('-[', '+[')) and sym.endswith(suffix)
                       for sym in facts.undefined | facts.methods):
                continue
        if rule.name == 'constant-false-branch':
            rows = unit.get('constant_false', {}).get(selector)
            if not rows:
                continue
            flagged = 0
            ok = True
            for enclosing, marked in rows:
                if marked:
                    flagged += 1
                elif emitted(enclosing, facts) is not False:
                    ok = False
                    break
            if not ok or not flagged:
                continue
        if rule.name == 'not-emitted':
            places = unit['send_places'].get(selector)
            if not places:
                continue
            ok = True
            for enclosing in places:
                if emitted(enclosing, facts) is not False:
                    ok = False
                    break
            if not ok:
                continue
        return rule.name
    return None


def without_category(name):
    """'-[Class sel]' from '-[Class(Category) sel]'; None when name names no
    category."""
    if not name.startswith(('-[', '+[')) or '(' not in name.split(' ', 1)[0]:
        return None
    head, rest = name.split(' ', 1)
    return head[:head.index('(')] + ' ' + rest


def match_direct_category_methods(object_only, database_only):
    """A method declared objc_direct in a category has a symbol without the
    category's name: -[Class sel], not -[Class(Category) sel]. Pairs each
    database method -[Class(Category) sel] with the object's -[Class sel]
    when neither side has the other. Returns the set of pairs (database
    name, object name)."""
    pairs = set()
    for m in database_only:
        plain = without_category(m)
        if plain is not None and plain in object_only:
            pairs.add((m, plain))
    return pairs


def compare_unit(facts, unit):
    """[Difference] between an object's facts and a unit's rows (unit: a dict
    of sets: selectors, defined_selectors, methods, ivars; send_places
    {selector: the enclosing names of its send and selector_ref rows};
    selref_selectors; arc, whether the unit's implementations are ARC)."""
    out = []
    sent = facts.stubs | facts.selrefs
    for sel in sorted(sent - unit['selectors']):
        out.append(Difference('selector only in the object', sel, explain_selector('object', sel, facts, unit)))
    for sel in sorted(unit['selectors'] - sent):
        out.append(Difference('selector only in the database', sel, explain_selector('database', sel, facts, unit)))
    object_only = facts.methods - unit['methods']
    database_only = unit['methods'] - facts.methods
    pairs = match_direct_category_methods(object_only, database_only)
    object_only = object_only - set(o for _, o in pairs)
    database_only = database_only - set(d for d, _ in pairs)
    for m in sorted(object_only):
        rule = next((r.name for r in RULES if r.side == 'method' and selector_of_method(m) in r.selectors), None)
        out.append(Difference('method only in the object', m, rule))
    for m in sorted(database_only):
        out.append(Difference('method only in the database', m, None))
    for iv in sorted(facts.ivars - unit['ivars']):
        out.append(Difference('ivar only in the object', iv, None))
    for iv in sorted(unit['ivars'] - facts.ivars):
        out.append(Difference('ivar only in the database', iv, None))
    return out


# --- Call-site counts --------------------------------------------------------
#
# The comparison above is of sets, so a send the database misses is found only
# when it is the unit's only send of its selector. Each message send that
# uses a selector stub is one branch relocation (bl, or b for a tail call) to
# _objc_msgSend$SELECTOR in the object's code, so the object's call sites can
# be counted per selector and compared with the database's send sites.
#
# The database's count for a selector (send_site_count) is the number of its
# send rows in the unit: one per message expression in the AST, so a macro
# expanded N times gives N sites, and two sends of the selector in one
# expansion give two sites at the same location (counting distinct locations
# would be wrong there); a send in a static inline function of a header is a
# row of each unit that reads the header, and is emitted once by each unit
# that calls the function; a send in a block counts in its enclosing method,
# where the block's code is emitted once. Left out: super sends (made through
# objc_msgSendSuper2, with no stub) and rows in a function or method whose
# symbol the object does not define (not emitted). Derived from the evidence
# of a sample of units of the whole tree (every Objective-C unit of a
# complete build): with these rules the counts agree for all but a few
# selectors, each explained below or reported.
#
# The database's count leaves out the rows marked as in code a constant
# condition skips, always: a marked row is never a call site, so it can
# neither explain a call site nor cancel one the database misses.
#
# A difference is classified as for the sets: 'object has MORE call sites'
# is the dangerous direction (a send the database does not have), explained
# only by the rules for sends the AST does not hold as message expressions
# (literals, boxing, fast enumeration: their selectors are written by the
# compiler) and by always_inline functions within their bound
# (inlined-function); 'object has FEWER call sites' is explained by the
# runtime-function rules (the compiler called objc_alloc and the like in
# place of a send) and direct methods, or reported.

COUNT_MORE = 'call sites: object has MORE than the database has send sites'
COUNT_FEWER = 'call sites: object has FEWER than the database has send sites'

# Rules of the call-site counts, beyond those of RULES. Derived from the
# whole-tree run against Build/.
COUNT_RULES = [
    ('inlined-function', COUNT_MORE,
     'some sends of the selector are in a C function whose symbol the object lacks: an always_inline function '
     '(NS_INLINE) inlined into each of its callers, which emits its sends once per call; applies when the excess '
     'is at most the sum, over those rows not marked as dead code, of the copies of their function: its '
     'references in the unit (function_ref), each counted once when the referring function has a symbol (or is '
     'not a C function) and as many times as that function has copies when it is itself a C function without '
     'a symbol'),
    ('unevaluated-macro-argument', COUNT_FEWER,
     'a send written in an argument of a macro from outside the repository that the macro writes twice, once in '
     'an operand that is not evaluated (the SDK\'s fortified memcpy and memmove pass the destination to '
     '__builtin_object_size): two rows at one location, one call site; applies when the counts agree once '
     'those extra rows are left out'),
]


def send_site_count(rows, facts):
    """The database's send sites of one selector in a unit: rows is
    [(receiver_kind, enclosing_name, file, line, col, macro_file,
    macro_role)], one per send row. Returns (sites, rows in a C function the
    object has no symbol for, extra rows at a location already counted that
    are in an argument of a macro from outside the repository, among the
    rows not marked as dead code)."""
    n = 0
    hidden = 0
    seen = set()
    extra = 0
    for row in rows:
        kind, enclosing = row[0], row[1]
        if kind in ('super', 'super_class'):
            continue
        if emitted(enclosing, facts) is False:
            if not enclosing.startswith(('-[', '+[')):
                hidden += 1
            continue
        n += 1
        if len(row) > 7 and row[7]:
            # Marked as dead code: left out of the count once, by the caller.
            continue
        where = row[2:5]
        if len(row) > 6 and row[6] == 'argument' and row[5] and row[5].startswith('/'):
            if where in seen:
                extra += 1
        seen.add(where)
    return n, hidden, extra


def constant_false_sites(rows, facts):
    """How many of the rows send_site_count counts are marked as in a branch
    a constant condition skips (an eighth element, 1, of the row)."""
    n = 0
    for row in rows:
        if len(row) < 8 or not row[7] or row[0] in ('super', 'super_class'):
            continue
        if emitted(row[1], facts) is False:
            continue
        n += 1
    return n


def explain_count(direction, selector, facts, unit, hidden=0, extra=0, got=0, want=0, flagged=0):
    side = 'object' if direction == COUNT_MORE else 'database'
    for rule in RULES:
        if rule.side != side or rule.selectors is None or selector not in rule.selectors:
            continue
        if rule.needs and not any(sym in facts.undefined for sym in rule.needs):
            continue
        if rule.defines or rule.arc:
            # arc-super-dealloc is a super send, which has no stub.
            continue
        return rule.name
    if direction == COUNT_FEWER and explain_selector('database', selector, facts, unit) == 'direct-method':
        return 'direct-method'
    if direction == COUNT_FEWER and extra and want - flagged - extra == got:
        return 'unevaluated-macro-argument'
    if direction == COUNT_MORE and hidden and got - (want - flagged) <= inlined_copies(
            unit.get('send_sites', {}).get(selector, ()), facts, unit):
        return 'inlined-function'
    return None


# Deeper nesting of always_inline functions than this is not explained.
MAX_INLINE_DEPTH = 16


def function_copies(name, facts, unit, depth=0):
    """How many copies of the code of the C function name the object can
    hold: one per reference from a function the object defines (or that is
    not a C function, or at file scope), and per reference from a C function
    without a symbol, as many as that function has copies."""
    if depth > MAX_INLINE_DEPTH:
        return 0
    total = 0
    for enclosing, refs in (unit.get('function_refs') or {}).get(name, {}).items():
        e = emitted(enclosing, facts) if enclosing else None
        if e is None or e:
            total += refs
        elif enclosing.startswith(('-[', '+[')):
            continue
        else:
            total += refs * function_copies(enclosing, facts, unit, depth + 1)
    return total


def inlined_copies(rows, facts, unit):
    """The call sites that the rows of a selector in C functions without a
    symbol can add to the object: for each such row not marked as dead code,
    the copies of its function."""
    n = 0
    for row in rows:
        kind, enclosing = row[0], row[1]
        if kind in ('super', 'super_class') or (len(row) > 7 and row[7]):
            continue
        if emitted(enclosing, facts) is not False or enclosing.startswith(('-[', '+[')):
            continue
        n += function_copies(enclosing, facts, unit)
    return n


def compare_counts(facts, unit):
    """[Difference] of call-site counts, for the selectors that both the
    object's stubs and the unit's send rows have (the others are set
    differences)."""
    out = []
    sites = unit.get('send_sites') or {}
    for sel in sorted(set(facts.call_sites or {}) & set(sites)):
        got = facts.call_sites[sel]
        want, hidden, extra = send_site_count(sites[sel], facts)
        flagged = constant_false_sites(sites[sel], facts)
        live = want - flagged
        if got == live:
            continue
        direction = COUNT_MORE if got > live else COUNT_FEWER
        name = '%s (object %d, database %d%s)' % (sel, got, live, ', %d marked' % flagged if flagged else '')
        out.append(Difference(direction, name,
                              explain_count(direction, sel, facts, unit, hidden, extra, got, want, flagged)))
    return out


def unit_rows(con, tu):
    """The rows of one unit that the comparison uses."""
    sends = collections.defaultdict(set)
    sites = collections.defaultdict(list)
    # {selector: [(enclosing, in a branch a constant condition skips)]}, one
    # per send and selector_ref row (a selector_ref is never marked).
    constant_false = collections.defaultdict(list)
    for sel, enclosing, kind, file, line, col, mfile, role, marked in con.execute(
            'SELECT selector, enclosing_name, receiver_kind, file, line, col, macro_file, macro_role, '
            'in_constant_false_branch FROM send WHERE tu = ? ORDER BY id', (tu,)):
        sends[sel].add(enclosing)
        sites[sel].append((kind, enclosing, file, line, col, mfile, role, marked))
        constant_false[sel].append((enclosing, marked))
    selrefs = set()
    for sel, enclosing in con.execute('SELECT selector, enclosing_name FROM selector_ref WHERE tu = ?', (tu,)):
        selrefs.add(sel)
        sends[sel].add(enclosing)
        constant_false[sel].append((enclosing, 0))
    methods = set()
    defined = set()
    for is_class, container, sel in con.execute(
            "SELECT is_class_method, container_name, selector FROM objc_method WHERE tu = ? AND (is_definition = 1 "
            "OR is_synthesized_accessor = 1) AND container_kind IN ('implementation', 'category-implementation')",
            (tu,)):
        methods.add(method_symbol(is_class, container, sel))
        defined.add(sel)
    impls = con.execute('SELECT DISTINCT class_name, category, arc FROM objc_impl WHERE tu = ?', (tu,)).fetchall()
    classes = sorted(set(c for c, cat, _ in impls if cat is None))
    ivars = set()
    for cls in classes:
        for (name,) in con.execute('SELECT DISTINCT i.name FROM objc_ivar i JOIN tu t ON t.id = i.tu WHERE '
                                   'i.class_name = ? AND (i.tu = ? OR (t.target = (SELECT target FROM tu WHERE id = ?) '
                                   'AND i.file IN (SELECT path FROM tu_input WHERE tu = ?)))', (cls, tu, tu, tu)):
            ivars.add('%s.%s' % (cls, name))
    function_refs = collections.defaultdict(dict)
    if con.execute("SELECT 1 FROM sqlite_master WHERE name = 'function_ref'").fetchone():
        for callee, enclosing, refs in con.execute(
                'SELECT callee, enclosing_name, refs FROM function_ref WHERE tu = ?', (tu,)):
            function_refs[callee][enclosing] = refs
    return {'selectors': set(sends) | selrefs, 'send_places': sends, 'selref_selectors': selrefs,
            'function_refs': function_refs, 'methods': methods, 'defined_selectors': defined, 'ivars': ivars,
            'send_sites': sites,
            'constant_false': constant_false, 'arc': any(arc for _, _, arc in impls)}


def object_candidates(output, build_root=None):
    """The paths at which the object file of a captured output path may be:
    the path itself, and without a Variant-* directory the build no longer
    has. With build_root (a directory that holds Intermediates.noindex, as
    Build/ does), the same path under build_root instead, and also with
    Objects-normal-tsan in place of Objects-normal (the directory a thread
    sanitizer build writes)."""
    if build_root is not None:
        marker = '/Intermediates.noindex/'
        if marker not in output:
            return []
        output = build_root.rstrip('/') + output[output.index(marker):]
    candidates = [output]
    parts = output.split('/')
    if any(p.startswith('Variant-') for p in parts):
        candidates.append('/'.join(p for p in parts if not p.startswith('Variant-')))
    if build_root is not None:
        candidates += [c.replace('/Objects-normal/', '/Objects-normal-tsan/') for c in candidates
                       if '/Objects-normal/' in c]
    return candidates


def object_path(output, root, build_roots=None):
    """The object file of a captured output path, as the build has it now:
    under each of build_roots in turn, or (without build_roots) at the
    captured path (object_candidates). None when none exists."""
    for build_root in (build_roots or [None]):
        for c in object_candidates(output, build_root):
            if os.path.exists(c):
                return c
    return None


def newest_input(root, con, tu):
    """(mtime, path) of the newest repository file the unit read."""
    best = (0.0, None)
    for (path,) in con.execute('SELECT path FROM tu_input WHERE tu = ?', (tu,)):
        if path.startswith('/') or path.startswith('Build/'):
            continue
        try:
            m = os.stat(os.path.join(root, path)).st_mtime
        except OSError:
            continue
        if m > best[0]:
            best = (m, path)
    return best


def read_stable(path):
    """The bytes of path and its (mtime, size), or raises OSError or
    MachOError when the file changed while it was read."""
    before = os.stat(path)
    with open(path, 'rb') as f:
        data = f.read()
    after = os.stat(path)
    if (before.st_mtime, before.st_size) != (after.st_mtime, after.st_size) or len(data) != after.st_size:
        raise MachOError('changed while it was read')
    return data, after.st_mtime


EXIT_TEXT = ('exit status: 0 no unexplained difference and every unit compared, 1 unexplained differences (of '
             'sets or of call-site counts), 3 some units could not be compared, 2 error')
SET_LIMIT_TEXT = ('limit of the set comparison: selectors are compared as sets per unit, so a send the database '
                  'misses is a set difference only when it is the unit\'s only send of that selector; the call-site '
                  'counts below find the others')
COUNT_RULE_TEXT = ('call sites: per unit and selector, the branch relocations to the _objc_msgSend$ stub in the '
                   'object\'s code against the unit\'s send rows of the selector (one per message expression: a '
                   'macro expanded N times is N sites), without super sends and rows in functions the object does '
                   'not define; MORE in the object is the dangerous direction')
IVAR_MODULE_NOTE = ('known cause of an ivar only in the object: ivars declared in the braces of an @interface in a '
                    'header that units read only through a Clang module are not in objc_ivar (a gap in the ivar '
                    'table, not in this cross-check)')


def not_captured_sources(codedb, q):
    """The Objective-C implementation files of the migration's scope that
    no captured unit compiles (codedb coverage, files not parsed)."""
    c = q.coverage
    if c is None:
        return []
    np = c.not_parsed
    classes = [('built by another Xcode project', [f for _, fs in np['other_projects'] for f in fs]),
               ('under submodules/', np['submodules']),
               ('compiled by a target of the project, in no unit', [f for f, _ in np['main_project']]),
               ('compiled by no target of any project found', np['no_project'])]
    return sorted((f, label) for label, files in classes for f in files
                  if f.endswith(('.m', '.mm')) and codedb.in_migration_scope(f))


def module_only_ivar_class(con, cls):
    """Whether objc_ivar has no ivar of cls at all while an object defines
    one: what ivars declared in the braces of an @interface in a header that
    units read only through a Clang module look like (IVAR_MODULE_NOTE)."""
    return not con.execute('SELECT 1 FROM objc_ivar WHERE class_name = ? LIMIT 1', (cls,)).fetchone()


def crosscheck(codedb, paths, target=None, file=None, list_explained=False, build_roots=None, out=None):
    """Compare every Objective-C unit (or those of target, or of file) with
    its object file, looked up under build_roots (directories that hold
    Intermediates.noindex, tried in order) or at the captured path. Returns
    the exit status."""
    import time
    out = out or sys.stdout
    started = time.time()
    build_roots = [os.path.abspath(r) for r in build_roots] if build_roots else None
    q = codedb.QueryContext(paths, codedb.QuerySpec('crosscheck', [], EXIT_TEXT, None, False))
    try:
        outputs = {}
        for entry in codedb.read_cdb(paths.cdb):
            if not entry.get('meta') and entry.get('output'):
                outputs[(entry['target'], entry['file'])] = entry['output']
        units = []
        for s in sorted(q.states.values()):
            if not s.file.endswith(('.m', '.mm')):
                continue
            if target is not None and s.target != target:
                continue
            if file is not None and s.file != file:
                continue
            units.append(s)
        totals = collections.Counter()
        unexplained = []
        explained = []
        not_compared = []
        notes = []
        roots_used = collections.Counter()
        compared = 0
        newest_object = 0.0
        ivar_module_cases = []
        for s in units:
            if s.tu is None or s.state != codedb.CURRENT or s.errors:
                not_compared.append((s, 'database rows not current (%s)' % (s.reason or 'parse errors')))
                continue
            output = outputs.get((s.target, s.file))
            obj = object_path(output, paths.root, build_roots) if output else None
            if obj is None:
                not_compared.append((s, 'no object file%s' % (
                    ' for %s under %s' % (output, ', '.join(build_roots)) if output and build_roots else
                    ' at %s' % output if output else ' named by the compile database')))
                continue
            try:
                data, mtime = read_stable(obj)
            except (OSError, MachOError) as e:
                not_compared.append((s, 'object file %s could not be read: %s' % (obj, e)))
                continue
            newest, which = newest_input(paths.root, q.con, s.tu)
            if newest > mtime:
                not_compared.append((s, 'stale build: %s is newer than the object file' % which))
                continue
            try:
                facts = read_object(data)
            except (MachOError, struct.error) as e:
                reason = str(e)
                label = 'fat file' if reason.startswith('fat file') else 'object file %s is not readable' % obj
                not_compared.append((s, '%s: %s' % (label, reason)))
                continue
            del data
            if facts.fat:
                notes.append((s, facts.fat))
            newest_object = max(newest_object, mtime)
            compared += 1
            if build_roots:
                roots_used[next(r for r in build_roots if obj.startswith(r.rstrip('/') + '/'))] += 1
            rows = unit_rows(q.con, s.tu)
            for d in compare_unit(facts, rows) + compare_counts(facts, rows):
                totals[(d.kind, d.rule or 'UNEXPLAINED')] += 1
                (explained if d.rule else unexplained).append((s, d))
                if d.kind == 'ivar only in the object' and not d.rule and module_only_ivar_class(
                        q.con, d.name.split('.', 1)[0]):
                    ivar_module_cases.append((s, d))
        missing_units = not_captured_sources(codedb, q) if target is None and file is None else []
        out.write('Cross-check of the code database against the object files\n')
        if build_roots:
            out.write('object files looked up under: %s (in that order, in place of the captured location under '
                      'Build/); units compared per root: %s. Objects built with other flags (sanitizers) are '
                      'expected to send the same selectors; sanitizer instrumentation may still add or split call '
                      'sites\n' % (', '.join(build_roots), ', '.join('%s %d' % (r, roots_used[r]) for r in build_roots)))
        else:
            out.write('object files looked up at the captured location (under Build/; --build-root to use another '
                      'build)\n')
        out.write('rules (a difference a rule explains; anything else is UNEXPLAINED):\n')
        for r in RULES:
            out.write('  %s (%s): %s%s%s%s\n' % (r.name, {'object': 'selector only in the object',
                                                          'database': 'selector only in the database',
                                                          'method': 'method only in the object'}[r.side], r.comment,
                                                '; needs %s in the object' % ' or '.join(r.needs) if r.needs else '',
                                                '; the unit defines -%s' % r.defines if r.defines else '',
                                                '; the unit is ARC' if r.arc else ''))
        for name, direction, comment in COUNT_RULES:
            out.write('  %s (%s): %s\n' % (name, direction, comment))
        out.write('  (a method -[Class(Category) sel] of the database and -[Class sel] of the object, neither on the '
                  'other side, are the same method: an objc_direct method of a category has no category in its '
                  'symbol)\n')
        out.write(SET_LIMIT_TEXT + '\n')
        out.write(COUNT_RULE_TEXT + '\n')
        out.write('units: %d Objective-C units%s; compared %d; not compared %d\n' % (
            len(units), ' of target %s' % target if target else '', compared, len(not_compared)))
        by_reason = collections.Counter(reason.split(':')[0].split(' (')[0].split(' for ')[0].split(' at ')[0]
                                        for _, reason in not_compared)
        for reason, n in sorted(by_reason.items()):
            out.write('  not compared, %s: %d\n' % (reason, n))
        if target is None and file is None:
            out.write('%d source files in scope have no captured unit%s\n' % (len(missing_units),
                                                                              ':' if missing_units else ''))
            for f, label in missing_units:
                out.write('  %s (%s)\n' % (f, label))
        out.write('differences by kind and rule:\n')
        for (kind, rule), n in sorted(totals.items()):
            out.write('  %s, %s: %d\n' % (kind, rule, n))
        out.write('UNEXPLAINED: %d\n' % len(unexplained))
        for s, d in unexplained:
            out.write('  %s %s: %s: %s\n' % (s.target, s.file, d.kind, d.name))
        if ivar_module_cases:
            out.write(IVAR_MODULE_NOTE + '; applies to: %s\n' % ', '.join(sorted(set(d.name for _, d in
                                                                                        ivar_module_cases))))
        if list_explained:
            out.write('explained: %d\n' % len(explained))
            for s, d in explained:
                out.write('  %s %s: %s: %s (%s)\n' % (s.target, s.file, d.kind, d.name, d.rule))
        for s, note in notes:
            out.write('note: %s %s: %s\n' % (s.target, s.file, note))
        out.write('not compared: %d\n' % len(not_compared))
        for s, reason in not_compared:
            out.write('  %s %s: %s\n' % (s.target, s.file, reason))
        if newest_object > started:
            out.write('the build changed during this run: an object file was written after it started\n')
        out.write('Selectors of super sends (objc_msgSendSuper2) appear only in __objc_selrefs; they are compared as '
                  'selectors like any other.\n')
        out.write(EXIT_TEXT + '\n')
        if unexplained:
            return 1
        if not_compared:
            return 3
        return 0
    finally:
        q.close()
