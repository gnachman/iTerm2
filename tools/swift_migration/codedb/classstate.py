#!/usr/bin/env python3
"""The ivar and static table of one Objective-C class (docs/swift-migration/
objc-state.md), as a query on the code database.

codedb.py classstate [--update] [--json] CLASS runs this.

Every fact comes from the compiler through the extractor's tables; where the
tables cannot answer, the answer is "unknown" with what would be needed. One
row per ivar of CLASS (declared in its @interface, a class extension or an
@implementation, or synthesized for a property) and one per variable with
static storage that a file holding an @implementation of CLASS or of one of
its categories defines (file statics, function statics, globals; not extern
declarations). Each row has:

  type            as the compiler prints it, with ARC's inferred ownership,
                  and the canonical type
  declared        header @interface, @interface in a source file, class
                  extension, @implementation block, or synthesized for a
                  property (automatically or by @synthesize, with the
                  property's attributes); access control; IBOutlet
  mode            ARC or manual reference counting of the unit that compiles
                  the class's @implementation (objc_impl), and the category
                  files compiled in the other mode; the type and ownership
                  shown are those that mode records
  ownership       under that mode (objc_ivar.ownership), and the qualifier
                  when it is written
  importable      yes, degraded, no or unknown, with the reason, decided from
                  objc_ivar.type_class and import_facts by importability()
                  (the rules it marks "checked" agree with swiftc; a test
                  checks them again). Every yes or degraded verdict is about
                  the type alone and says what is known of its visibility to
                  the bridging header: that the type is declared in the
                  implementation file (private to it), or that whether it and
                  the classes, protocols and typedefs it names are visible was
                  not checked (that needs the importable declarations of the
                  bridging header, a separate Phase 0 item). A lock type gets
                  a note that its value must not be copied
  accessor        the methods of the class named like the ivar without its
                  underscore (getter foo, setter setFoo:): synthesized (with
                  the property and the ivar that backs it), written by hand
                  (not proven trivial), inherited from a superclass or a
                  protocol it adopts (repository, SDK or Swift; the chain
                  through objc_class and sdk_class), unknown where the chain
                  leaves the database, or none; and the methods of other
                  classes that override them (objc_method_override); whether
                  something observes or binds the key is not checked
  users           every reference (ivar_ref, static_ref) by function or
                  method, with its access (read, write, rmw, address, byref,
                  synchronized, once-token, unevaluated) and its lines
  outside         references from outside the class's own code, each listed:
                  from a unit whose main file holds no @implementation of the
                  class (another translation unit), from a category's file
                  that is not the file of the class's @implementation, from a
                  method of another class, from a C function, and through
                  another object (obj->_ivar)
  blocks, lambdas references inside a block (and a dispatch_once block) or
                  a C++ lambda (with how the lambda captures)
  synchronized    references inside a @synchronized body, with the lock

Known limits of the importability verdicts (no occurrence among the tree's
ivars and statics when they were written): a pointer to a bridged generic
(NSArray<NSString *> **), NSSet<Class>, and a block taking a pointer to an
incomplete struct are reported yes, although Swift loses type information
in them. A function-local static in a block, in a file included several
times by one unit, has one USR for every inclusion, so its rows are merged.

Exit status as for the other queries: 0 rows printed, 1 none, 3 answered but
incomplete (any unit not current, a compile database that does not cover the
project, and the other reasons the status block lists; references from a unit
that is not current may be missing), 2 error.
"""

import collections
import io
import json
import os
import sys

# Facts of a part (in-WORD) that leave a block, function pointer, array or
# struct unclassified: whether Swift drops the member, the parameter or the
# whole type depends on whether the part is held by value, which the facts do
# not say, or was not checked with swiftc.
UNCLASSIFIED_PARTS = ('in-atomic', 'in-int128', 'in-complex', 'in-unusual-builtin', 'in-variable-array',
                      'in-dependent-type', 'in-other-type', 'in-too-deep', 'in-unprototyped-function',
                      'in-variadic-function', 'in-object-member-strong', 'in-object-member-weak',
                      'in-object-member-unqualified', 'in-object-member-autoreleasing', 'in-function')
# Facts of a struct's member that make the member, and so the struct, a
# degraded import: (fact, what Swift does with the member).
DEGRADED_MEMBERS = (
    ('array-member', 'a C array member is imported as a tuple (objc-state.md section 1; checked)'),
    ('flexible-array-member', 'the flexible array member is dropped (checked)'),
    ('object-member-unsafe_unretained', '__unsafe_unretained object members are imported as Unmanaged '
                                        '(objc-state.md section 1; checked)'),
    ('in-int128', 'an __int128 member is dropped (checked)'),
    ('in-object-member-strong', 'a member that points to a struct holding strong or weak objects is imported as '
                                'OpaquePointer (checked)'),
    ('in-object-member-weak', 'a member that points to a struct holding strong or weak objects is imported as '
                              'OpaquePointer (checked)'),
    ('in-variadic-function', 'a member that points to a variadic function is imported as OpaquePointer (checked)'),
    ('in-opaque-pointee', 'a member that points to an incomplete struct is imported as OpaquePointer (checked)'),
    ('in-long-double', 'a long double member is imported as Double (checked)'),
    ('in-float16', 'a _Float16 member is imported as Float16, which Swift does not offer on x86_64'),
    ('in-enum-plain', 'a plain C enum member is imported as a struct with a raw value'),
    ('in-generic-sdk', 'an object member loses its type arguments or keeps them unbridged'),
    ('in-generic-repository', 'an object member keeps Objective-C type arguments, unbridged'),
    ('in-kindof', 'an object member loses __kindof'),
    ('in-nsobject-qualified', 'an NSObject<P> * member loses its class'),
    ('in-protocol-key', 'an id<P> set element or dictionary key member becomes AnyHashable'),
)
CXX_FACTS = ('cxx-record', 'cxx-reference', 'member-pointer', 'cxx-template')
SIMD_COUNTS = (2, 3, 4, 8, 16, 32, 64)
SIMD_ELEMENTS = ('float', 'double', 'char', 'signed char', 'unsigned char', 'short', 'unsigned short', 'int',
                 'unsigned int', 'long', 'unsigned long', 'long long', 'unsigned long long')
SIMD_HALF_ELEMENTS = ('_Float16', '__fp16', 'half')
VISIBILITY = 'visibility: not checked (the type and the classes, protocols and typedefs it names must be visible ' \
             'to the bridging header)'
PRIVATE_TYPE = 'visibility: the type is declared in the implementation file itself, so it is private to that file ' \
               'and must move to a header before Swift can name it'
LOCK_NOTE = 'a lock: its value must not be copied, so Swift must reach it through a pointer, never as a stored ' \
            'value'
YES, DEGRADED, NO, UNKNOWN = 'yes', 'degraded', 'no', 'unknown'
# Facts of a part (a block's or function's parameter or result, a pointee)
# whose import loses type information, so that the whole type does too.
LOSSY_PARTS = (('in-generic-sdk', 'type arguments of a generic SDK class'),
               ('in-generic-repository', 'type arguments of a generic class, kept unbridged'),
               ('in-kindof', '__kindof'),
               ('in-nsobject-qualified', 'the class of NSObject<P> *'),
               ('in-protocol-key', 'the protocol of an id<P> set element or dictionary key'))
GENERIC_NOTE = 'Swift keeps the type arguments of a generic class as Objective-C classes (Foo<NSString>), drops ' \
               'them for the classes the SDK\'s API notes import as non-generic, and bridges them only for NSArray, ' \
               'NSDictionary and NSSet'


def importability(type_class, facts):
    """(verdict, reason) for a type, from its type_class and import_facts.
    The rules marked "checked" were confirmed with swiftc -typecheck against a
    test header declaring a property of each kind;
    tests/test_codedb_classstate.py SwiftcAgreementTest repeats that check
    against tests/classstate_fixtures/swiftcheck/Probe.h. The others restate
    objc-state.md section 1. For a yes or degraded verdict the reason ends
    with what is known of the type's visibility to the bridging header: that
    it is declared in the implementation file (private to it), or that it was
    not checked; a lock type gets a note that its value must not be copied."""
    f = set((facts or '').split())
    verdict, why = _verdict(type_class, f)
    if verdict in (YES, DEGRADED):
        why += '; ' + (PRIVATE_TYPE if 'type-in-main-file' in f else VISIBILITY)
    if 'lock-type' in f:
        why += '; ' + LOCK_NOTE
    return verdict, why


def _verdict(type_class, f):
    def parts(names):
        return sorted(f & set(names))

    def lossy():
        return [what for fact, what in LOSSY_PARTS if fact in f]

    cxx = parts(CXX_FACTS) + parts('in-' + x for x in CXX_FACTS)
    if type_class == 'cxx-object' or cxx:
        return NO, 'C++ type (%s): a header that holds C++ cannot be in the bridging header' % (
            ', '.join(cxx) or 'cxx-object')
    for word, why in (('too-deep', 'parts nested more than 8 deep were not read'),
                      ('dependent-type', 'a dependent (template) type')):
        if word in f or 'in-' + word in f:
            return UNKNOWN, why
    if type_class == 'atomic' or 'atomic' in f:
        return NO, '_Atomic: not imported (objc-state.md section 1; checked)'
    if 'int128' in f:
        return NO, '__int128: not imported (objc-state.md section 1; checked)'
    if 'complex' in f:
        return NO, '_Complex: not imported (checked)'
    if 'unusual-builtin' in f:
        return UNKNOWN, 'needs a check of this builtin type (%s) with swiftc' % 'unusual-builtin'
    if type_class == 'bit-field':
        verdict, why = _verdict('scalar', f)
        if verdict != YES:
            return verdict, 'bit-field of a type that is %s: %s' % (verdict, why)
        return DEGRADED, 'bit-field: its value type imports (%s), but it has no address: Swift reaches it only ' \
                         'through an accessor' % why
    if type_class == 'scalar':
        if 'long-double' in f:
            return DEGRADED, 'long double: imported as Double on Apple silicon, differs on Intel (objc-state.md ' \
                             'section 1; checked)'
        if 'float16' in f:
            return DEGRADED, '_Float16 or __fp16: imported as Float16 (checked on arm64), which Swift does not ' \
                             'offer on x86_64'
        if 'enum-plain' in f:
            return DEGRADED, 'plain C enum: imported as a struct with a raw value, no exhaustive switch ' \
                             '(objc-state.md section 1; checked)'
        if 'enum-ns' in f:
            return YES, 'NS_ENUM (enum_extensibility): imported as a Swift enum (checked)'
        if 'enum-options' in f:
            return YES, 'NS_OPTIONS (flag_enum): imported as an OptionSet (checked)'
        if not (f - {'type-in-main-file', 'lock-type'}):
            return YES, 'C scalar'
        return UNKNOWN, 'scalar with facts %s: not classified' % ' '.join(sorted(f))
    if type_class == 'object':
        forward = parts(('forward-declared-class', 'forward-declared-protocol'))
        if forward:
            return UNKNOWN, 'the class or a protocol is only forward-declared in this unit (%s): Swift drops the ' \
                            'member unless the module or header that defines it is visible to it' % ', '.join(forward)
        if 'os-object' in f:
            return YES, 'a dispatch or os object (NSObject<OS_...> *, as dispatch_queue_t): imported as the Swift ' \
                        'class (DispatchQueue, DispatchGroup, OSLog and the others) (checked)'
        if 'nsobject-qualified' in f:
            return DEGRADED, 'NSObject<P> *: imported as any P, the class dropped (checked)'
        if 'protocol-key' in f:
            return DEGRADED, 'an NSSet element or NSDictionary key of type id<P>: imported as AnyHashable (checked)'
        if 'kindof' in f:
            return DEGRADED, '__kindof: imported as the plain class, losing the implicit downcast (checked)'
        if 'generic-sdk' in f:
            return DEGRADED, 'a generic SDK class with type arguments: Swift drops the arguments where the SDK\'s ' \
                             'API notes import the class as non-generic (NSMutableArray<NSString *> is ' \
                             'NSMutableArray), and otherwise imports Foo<NSString>, not Foo<String>; degraded either ' \
                             'way (objc-state.md section 1; checked for both); ' + GENERIC_NOTE
        if 'generic-repository' in f:
            return DEGRADED, 'a generic class of the repository with type arguments: imported as Foo<NSString>, not ' \
                             'Foo<String>, the arguments not bridged (objc-state.md section 1; checked); ' + GENERIC_NOTE
        if 'generic-bridged' in f:
            lost = parts(('in-generic-sdk', 'in-generic-repository', 'in-kindof', 'in-nsobject-qualified',
                          'in-protocol-key'))
            if lost:
                return DEGRADED, 'a bridged collection whose element types lose type information (%s): for ' \
                                 'example NSArray<NSMutableArray<NSString *> *> is [NSMutableArray] ' \
                                 '(objc-state.md section 1; checked)' % ', '.join(lost)
            return YES, 'NSArray, NSDictionary or NSSet with type arguments: bridged to a Swift collection that ' \
                        'keeps them (checked)'
        return YES, 'object'
    if type_class == 'selector':
        return YES, 'SEL: imported as Selector'
    if type_class == 'block':
        if 'variadic-function' in f:
            return NO, 'variadic block: not imported (checked)'
        bad = parts(UNCLASSIFIED_PARTS)
        if bad:
            return UNKNOWN, 'block whose result or parameters involve %s: a block with such a parameter by value ' \
                            'is not imported (checked for a struct with a strong member and for __int128), one ' \
                            'through a pointer is: needs whether the part is held by value' % ', '.join(bad)
        if lossy():
            return DEGRADED, 'block whose parameters or result lose %s (checked)' % ', '.join(lossy())
        return YES, 'block: imported as a closure (checked)'
    if type_class == 'c-pointer':
        if 'objc-imp' in f:
            return DEGRADED, 'IMP: the Swift importer reads the SDK with OBJC_OLD_DISPATCH_PROTOTYPES=1, where IMP is ' \
                             'id (*)(id, SEL, ...), a variadic function pointer: imported as OpaquePointer (checked)'
        if 'cf-type-ref' in f:
            return YES, 'CFTypeRef: imported as AnyObject (checked)'
        if 'va-list' in f:
            return YES, 'va_list: imported as CVaListPointer (checked)'
        if 'function-pointer' in f:
            if 'variadic-function' in f:
                return DEGRADED, 'pointer to a variadic function: imported as OpaquePointer (checked)'
            if 'unprototyped-function' in f:
                return UNKNOWN, 'pointer to a function without a prototype: not checked'
            bad = parts(UNCLASSIFIED_PARTS)
            if bad:
                return UNKNOWN, 'function pointer whose result or parameters involve %s: not checked' % ', '.join(bad)
            if lossy():
                return DEGRADED, 'function pointer whose parameters or result lose %s (checked)' % ', '.join(lossy())
            return YES, 'function pointer: imported as a @convention(c) function (checked)'
        if 'cf-bridged' in f:
            return YES, 'pointer to a struct with objc_bridge (a CF type such as CGContextRef): imported as a ' \
                        'managed class (checked)'
        if 'opaque-pointee' in f:
            return DEGRADED, 'pointer to an incomplete struct: imported as OpaquePointer (checked)'
        if 'object-pointee' in f:
            if lossy():
                return DEGRADED, 'pointer to an object pointer that loses %s: imported as ' \
                                 'AutoreleasingUnsafeMutablePointer (checked)' % ', '.join(lossy())
            return YES, 'pointer to an object or block pointer: imported as AutoreleasingUnsafeMutablePointer ' \
                        '(checked)'
        if 'array-pointee' in f:
            return DEGRADED, 'pointer to a C array: the pointee is imported as a tuple (checked)'
        if parts(('in-array-member', 'in-flexible-array-member')):
            return DEGRADED, 'pointer to a struct with array members: the pointee\'s arrays are imported as tuples ' \
                             'or dropped (checked)'
        if parts(('in-object-member-strong', 'in-object-member-weak')):
            return DEGRADED, 'pointer to a struct holding strong or weak objects, which is not imported: the ' \
                             'pointer is imported as OpaquePointer (checked)'
        bad = parts(UNCLASSIFIED_PARTS)
        if bad:
            return UNKNOWN, 'pointer to a type involving %s: not checked' % ', '.join(bad)
        return YES, 'C pointer: imported as an unsafe pointer (checked)'
    if type_class in ('struct', 'union'):
        if 'incomplete-record' in f:
            return UNKNOWN, 'the record has no definition in this unit'
        if parts(('object-member-strong', 'object-member-weak')):
            return NO, 'a struct holding strong or weak object pointers is not imported (objc-state.md section 1; ' \
                       'checked)'
        if 'object-member-unqualified' in f:
            return UNKNOWN, 'object members with no ownership qualifier in a unit compiled without ARC: Swift reads ' \
                            'the header with ARC, where they are strong (not imported) unless they were written ' \
                            '__unsafe_unretained, which manual reference counting drops from the type: needs the ' \
                            'type as an ARC unit records it'
        degraded = []
        for fact, what in DEGRADED_MEMBERS:
            if fact in f and what not in degraded:
                degraded.append(what)
        if 'object-member-autoreleasing' in f:
            degraded.append('__autoreleasing object members are imported as Unmanaged')
        handled = set(fact for fact, _ in DEGRADED_MEMBERS)
        bad = [p for p in parts(UNCLASSIFIED_PARTS) if p not in handled]
        if bad:
            return UNKNOWN, 'a member involves %s: whether Swift drops the member or the record is not checked' % (
                ', '.join(bad))
        what = 'C union: imported as a struct whose members share storage (checked)' if (
            type_class == 'union' or 'union' in f) else 'C struct'
        if degraded:
            return DEGRADED, '%s; %s' % (what, '; '.join(degraded))
        return YES, what
    if type_class == 'array':
        if parts(('variable-array', 'incomplete-array')):
            return UNKNOWN, 'array without a constant size: not checked'
        bad = parts(UNCLASSIFIED_PARTS)
        if bad:
            return UNKNOWN, 'array of a type involving %s: not checked' % ', '.join(bad)
        return DEGRADED, 'C array: imported as a tuple, no indexing by a variable without unsafe pointers ' \
                         '(objc-state.md section 1; checked)'
    if type_class == 'vector':
        counts = [w[len('vector-elements-'):] for w in f if w.startswith('vector-elements-')]
        elements = [w[len('vector-element-'):] for w in f if w.startswith('vector-element-')]
        simd = len(counts) == 1 and counts[0].isdigit() and int(counts[0]) in SIMD_COUNTS and len(elements) == 1
        if simd and elements[0] in SIMD_ELEMENTS:
            return YES, 'vector of %s %s: imported as SIMD%s (checked)' % (counts[0], elements[0], counts[0])
        if simd and elements[0] in SIMD_HALF_ELEMENTS:
            return DEGRADED, 'vector of %s %s: imported as SIMD%s<Float16> (checked on arm64), which Swift does ' \
                             'not offer on x86_64' % (counts[0], elements[0], counts[0])
        return UNKNOWN, 'vector (%s): not checked' % ' '.join(sorted(f))
    return UNKNOWN, 'type class %s: not classified' % type_class


# --- Reading the tables -------------------------------------------------------

IVAR_SQL = ('SELECT i.name, i.file, i.line, i.col, i.container_kind, i.access, i.type, i.canonical_type, '
            'i.type_class, i.object_class, i.object_protocols, i.record_name, i.record_has_objects, i.bit_width, '
            'i.ownership_written, i.ownership, i.arc, i.import_facts, i.type_encoding, i.is_iboutlet, '
            'i.synthesized_by, i.property_name, i.macro_name, i.in_migration_scope, i.usr, i.tu, t.main_file, '
            't.target FROM objc_ivar i JOIN tu t ON t.id = i.tu WHERE i.class_name = ? '
            'ORDER BY i.file, i.line, i.col, i.name, i.arc DESC')
IVAR_COLS = ('name', 'file', 'line', 'col', 'container_kind', 'access', 'type', 'canonical_type', 'type_class',
             'object_class', 'object_protocols', 'record_name', 'record_has_objects', 'bit_width', 'ownership_written',
             'ownership', 'arc', 'import_facts', 'type_encoding', 'is_iboutlet', 'synthesized_by', 'property_name',
             'macro_name', 'in_migration_scope', 'usr', 'tu', 'main_file', 'target')
IVAR_REF_SQL = ('SELECT r.ivar_name, r.file, r.line, r.col, r.enclosing_name, r.enclosing_class, r.kind, r.access, '
                'r.partial, r.base_kind, r.in_block, r.in_once_block, r.in_lambda, r.sync_lock, r.retain_hint, '
                'r.macro_name, r.in_constant_false_branch, r.in_migration_scope, r.tu, t.main_file, t.target '
                'FROM ivar_ref r JOIN tu t ON t.id = r.tu WHERE r.ivar_class = ? '
                'ORDER BY r.ivar_name, r.file, r.line, r.col, r.enclosing_name')
STATIC_SQL = ('SELECT s.usr, s.name, s.kind, s.enclosing_name, s.file, s.line, s.col, s.type, s.canonical_type, '
              's.type_class, s.object_class, s.record_name, s.ownership_written, s.ownership, s.arc, s.import_facts, '
              's.is_const, s.pointee_const, s.init_kind, s.thread_local, s.macro_name, s.in_migration_scope, s.tu, '
              't.main_file, t.target FROM c_static s JOIN tu t ON t.id = s.tu WHERE s.file = ? AND s.kind != '
              '\'extern\' ORDER BY s.line, s.col, s.name, s.arc DESC')
STATIC_COLS = ('usr', 'name', 'kind', 'enclosing_name', 'file', 'line', 'col', 'type', 'canonical_type', 'type_class',
               'object_class', 'record_name', 'ownership_written', 'ownership', 'arc', 'import_facts', 'is_const',
               'pointee_const', 'init_kind', 'thread_local', 'macro_name', 'in_migration_scope', 'tu', 'main_file',
               'target')
STATIC_REF_SQL = ('SELECT r.name, r.file, r.line, r.col, r.enclosing_name, r.enclosing_class, \'direct\', r.access, '
                  'r.partial, NULL, r.in_block, r.in_once_block, r.in_lambda, r.sync_lock, NULL, r.macro_name, '
                  'r.in_constant_false_branch, r.in_migration_scope, r.tu, t.main_file, t.target FROM static_ref r '
                  'JOIN tu t ON t.id = r.tu WHERE r.var_usr = ? ORDER BY r.file, r.line, r.col, r.enclosing_name')
REF_COLS = ('name', 'file', 'line', 'col', 'enclosing_name', 'enclosing_class', 'kind', 'access', 'partial',
            'base_kind',
            'in_block', 'in_once_block', 'in_lambda', 'sync_lock', 'retain_hint', 'macro_name',
            'in_constant_false_branch', 'in_migration_scope', 'tu', 'main_file', 'target')
# The columns that identify one reference across the units that record it.
REF_KEY = ('file', 'line', 'col', 'enclosing_name', 'enclosing_class', 'kind', 'access', 'partial', 'base_kind',
           'in_block', 'in_once_block', 'in_lambda', 'sync_lock', 'retain_hint', 'macro_name',
           'in_constant_false_branch')
ACCESS_ORDER = ('read', 'write', 'rmw', 'address', 'byref', 'synchronized', 'once-token', 'unevaluated')
CONTAINER_TEXT = {'interface': '@interface', 'extension': 'class extension', 'implementation': '@implementation block'}
SOURCE_SUFFIXES = ('.m', '.mm', '.c', '.cc', '.cpp', '.cxx')


def as_dicts(rows, cols):
    return [dict(zip(cols, r)) for r in rows]


def group_refs(rows):
    """[(first row, {tu: count}, set of main files, set of targets)] for
    references grouped by REF_KEY, in order."""
    groups = collections.OrderedDict()
    for r in rows:
        k = tuple(r[c] for c in REF_KEY)
        g = groups.get(k)
        if g is None:
            g = groups[k] = [r, collections.Counter(), set(), set()]
        g[1][r['tu']] += 1
        g[2].add(r['main_file'])
        g[3].add(r['target'])
    return list(groups.values())


class Own:
    """Where CLASS's own code is: the files of its @implementation and of its
    category @implementations (objc_impl), and the main files of the units
    that compile them."""

    def __init__(self, con, cls):
        rows = con.execute('SELECT DISTINCT i.file, i.category, i.arc, t.main_file FROM objc_impl i JOIN tu t ON '
                           't.id = i.tu WHERE i.class_name = ? ORDER BY i.file, i.category', (cls,)).fetchall()
        self.impls = sorted(set((f, c, a) for f, c, a, _ in rows), key=lambda r: (r[0], r[1] or '', -r[2]))
        self.files = sorted(set(f for f, _, _ in self.impls))
        self.class_files = sorted(set(f for f, c, _ in self.impls if c is None))
        self.category_files = sorted(set(f for f, c, _ in self.impls if c is not None) - set(self.class_files))
        self.mains = set(m for _, _, _, m in rows)
        self.class_mains = set(m for f, c, _, m in rows if c is None)
        self.modes = set(a for _, _, a in self.impls)
        # The mode of the class's @implementation, which decides how its ivars
        # are held; the categories' modes when it has none in the database.
        self.class_modes = set(a for _, c, a in self.impls if c is None) or self.modes


def mode_text(codedb, own):
    """The ARC mode of the class's @implementation, and the category files
    compiled in the other mode."""
    if not own.impls:
        return 'unknown: no @implementation of the class is in this database'
    main = sorted(set(a for _, c, a in own.impls if c is None), reverse=True)
    if not main:
        return 'no @implementation of the class is in this database; its categories: %s' % ', '.join(
            '%s (category %s, %s)' % (f, c, codedb.MODE_NAMES[a]) for f, c, a in own.impls)
    text = ' and '.join(codedb.MODE_NAMES[m] for m in main)
    others = [(f, c, a) for f, c, a in own.impls if c is not None and a not in main]
    if others:
        text += ' (the @implementation); %s' % '; '.join('%s in %s (category %s)' % (codedb.MODE_NAMES[a], f, c)
                                                          for f, c, a in others)
    return text


def lock_text(codedb, q, desc, cls):
    return codedb.lock_name(q, desc, cls) if desc else None


def ref_record(codedb, q, g, cls, own, is_ivar):
    """The JSON form of one grouped reference, with the reasons it is from
    outside the class's own code."""
    r, tus, mains, targets = g
    outside = []
    other_units = sorted(m for m in mains if m not in own.mains)
    if other_units:
        outside.append('from another translation unit (%s)' % ', '.join(other_units))
    elif own.class_mains and not (mains & own.class_mains):
        outside.append('from a category\'s file, not the file of the @implementation (%s)' % ', '.join(sorted(mains)))
    ec = r['enclosing_class']
    if ec is not None and ec != cls:
        outside.append('from a method of class %s' % ec)
    if ec is None and r['enclosing_name']:
        outside.append('from a C function')
    if ec is None and not r['enclosing_name']:
        outside.append('at file scope')
    if is_ivar and r['base_kind'] in ('parameter', 'local', 'other'):
        outside.append('through another object (%s)' % codedb.BASE_TEXT.get(r['base_kind'], r['base_kind']))
    return {
        'file': r['file'], 'line': r['line'], 'col': r['col'],
        'function': r['enclosing_name'] or '(file scope)', 'function_class': ec,
        'access': r['access'], 'partial': bool(r['partial']), 'kind': r['kind'],
        'base': r['base_kind'], 'in_block': bool(r['in_block']), 'in_once_block': bool(r['in_once_block']),
        'in_lambda': r['in_lambda'], 'synchronized_on': lock_text(codedb, q, r['sync_lock'], cls),
        'retain_hint': r['retain_hint'], 'macro': r['macro_name'],
        'in_constant_false_branch': bool(r['in_constant_false_branch']),
        'references_here': max(tus.values()), 'units': sorted(mains), 'targets': sorted(targets),
        'outside_own_code': outside, 'marks': q.marks(tus), 'in_migration_scope': bool(r['in_migration_scope']),
    }


def protocol_declares(codedb, con, name, sel):
    """The protocol that the class or category container name lists,
    directly or through protocol inheritance, and that declares the instance
    method sel (in the repository or the SDK), or None."""
    todo = sorted(codedb.direct_adoptions(con, name))
    seen = set()
    while todo:
        proto = todo.pop(0)
        if proto in seen:
            continue
        seen.add(proto)
        if con.execute("SELECT 1 FROM objc_method WHERE container_kind = 'protocol' AND container_name = ? AND "
                       "selector = ? AND is_class_method = 0 LIMIT 1", (proto, sel)).fetchone() or con.execute(
                "SELECT 1 FROM sdk_method WHERE container_kind = 'protocol' AND container = ? AND selector = ? AND "
                "is_class_method = 0 LIMIT 1", (proto, sel)).fetchone():
            return proto
        todo += codedb.protocol_parents(con, proto)
    return None


def inherited_accessor(codedb, con, chain, sel):
    """Where a superclass of the class declares or defines the instance
    method sel, or a protocol it adopts declares it: 'inherited from NAME
    (repository|SDK|Swift)', with the protocol when that is where it is
    declared; 'unknown: superclass chain not followed past NAME' when the
    chain leaves what the database records; or None. chain is
    codedb.class_chain's."""
    for i, (name, where, _) in enumerate(chain):
        if i == 0:
            continue
        proto = protocol_declares(codedb, con, name, sel) if where != codedb.SWIFT_CLASS else None
        if proto:
            return 'inherited from %s (%s, declared by its protocol %s)' % (
                name, 'SDK' if where.startswith('SDK') else 'repository', proto)
        if where.startswith('repository'):
            if con.execute('SELECT 1 FROM objc_method WHERE class_name = ? AND selector = ? AND is_class_method = 0 '
                           'LIMIT 1', (name, sel)).fetchone():
                return 'inherited from %s (repository)' % name
        elif where.startswith('SDK'):
            if con.execute('SELECT 1 FROM sdk_method WHERE ' + codedb.same_class_sql('container') + ' AND selector = ? '
                           'AND is_class_method = 0 LIMIT 1', (name, name, name, sel)).fetchone():
                return 'inherited from %s (SDK)' % name
            if con.execute('SELECT 1 FROM objc_method WHERE class_name = ? AND selector = ? AND is_class_method = 0 '
                           'LIMIT 1', (name, sel)).fetchone():
                return 'inherited from %s (a repository category on that SDK class)' % name
        elif where == codedb.SWIFT_CLASS:
            if con.execute('SELECT 1 FROM swift_objc_decl WHERE class_name = ? AND selector = ? AND is_class_member = 0 '
                           'LIMIT 1', (name, sel)).fetchone():
                return 'inherited from %s (Swift)' % name
            return 'unknown: superclass chain not followed past %s (declared in Swift)' % name
        else:
            return 'unknown: superclass chain not followed past %s (its superclass %s is not recorded)' % (
                chain[i - 1][0], name)
    if chain and chain[0][1] == 'not recorded':
        return 'unknown: the class itself is not recorded in objc_class, so its superclass chain is not known'
    return None


NONE_TEXT = 'none in the repository and SDK headers; private framework methods not consulted (give --runtime-methods)'


def capitalized(name):
    return name[:1].upper() + name[1:]


def accessor_candidates(con, cls, ivar_name, ivar_usr, chain):
    """[(selector, form, always)] for an ivar: for each name the ivar's can
    stand for (without one leading underscore, without one trailing
    underscore, or as it is), the getter and the setter (always reported),
    the is-prefixed getter, and the getter= and setter= names of a property
    of the class or a repository superclass whose name is that name or that
    the ivar backs (reported only when something has them)."""
    names = []
    if ivar_name.startswith('_') and len(ivar_name) > 1:
        names.append((ivar_name[1:], 'without the leading underscore'))
    if ivar_name.endswith('_') and len(ivar_name) > 1:
        names.append((ivar_name[:-1], 'without the trailing underscore'))
    if not names:
        names.append((ivar_name, 'the ivar\'s name'))
    out = []
    seen = set()

    def add(sel, form, always):
        if sel and sel not in seen:
            seen.add(sel)
            out.append((sel, form, always))
    repository = [n for n, where, _ in chain if where.startswith('repository')] or [cls]
    for base, form in names:
        add(base, 'getter, %s' % form, True)
        add('set%s:' % capitalized(base), 'setter, %s' % form, True)
        add('is%s' % capitalized(base), 'is-prefixed getter, %s' % form, False)
        for c in repository:
            for getter, setter, pname in con.execute(
                    "SELECT DISTINCT p.getter_selector, p.setter_selector, p.name FROM objc_property p WHERE "
                    "p.kind = 'declaration' AND p.class_name = ? AND (p.name = ? OR p.usr IN (SELECT s.usr FROM "
                    "objc_property s WHERE s.kind = 'synthesize' AND s.class_name = ? AND s.ivar_usr = ?))",
                    (c, base, cls, ivar_usr or '')).fetchall():
                add(getter, 'getter= of property %s of %s' % (pname, c), False)
                add(setter, 'setter= of property %s of %s' % (pname, c), False)
    return out


def runtime_inherited(lists, chain, sel):
    """(text, found) from the run-time method lists for an instance method
    sel inherited along chain (codedb.class_chain's)."""
    if not lists:
        return NONE_TEXT, False
    labels = []
    for rm in lists:
        labels.append(rm.label())
        for name, _, _ in chain[1:]:
            if rm.has_class(name):
                impl = rm.implementer(name, False, sel)
                if impl:
                    return 'inherited from %s (framework, private or public; from the run-time list of %s)' % (
                        impl, rm.label()), True
                break
    return 'none in the repository, the SDK headers and the run-time list%s of %s' % (
        's' if len(labels) > 1 else '', '; '.join(labels)), False


def swift_overrides(con, usrs):
    """['Class (Swift, file:line)'] of the Swift declarations that override
    one of usrs (swift_objc_decl.is_override; a Swift override var has a
    getter row and, when settable, a setter row, each with overrides_usr)."""
    if not usrs or not con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = "
                                   "'swift_objc_decl'").fetchone():
        return []
    return ['%s (Swift, %s:%d)' % r for r in con.execute(
        'SELECT DISTINCT class_name, file, line FROM swift_objc_decl WHERE is_override = 1 AND overrides_usr IN (%s) '
        'ORDER BY class_name, file, line' % ','.join('?' * len(usrs)), usrs).fetchall()]


def accessor_info(con, cls, ivar_name, ivar_usr, codedb=None, chain=None, lists=(), swift_note=None):
    """The methods named like the ivar (accessor_candidates), in CLASS and
    its categories, inherited from a superclass or a protocol it adopts, or
    in the run-time method lists; and their overrides in other classes, in
    Objective-C and in Swift. swift_note: why the Swift overrides are not
    known (the Swift side not captured, or a module not current), or None.
    Each entry says whether private framework methods were consulted."""
    chain = chain if chain is not None else [(cls, 'not recorded', set())]
    consulted = bool(lists)
    out = []
    for sel, form, always in accessor_candidates(con, cls, ivar_name, ivar_usr, chain):
        rows = con.execute(
            'SELECT DISTINCT m.usr, m.file, m.line, m.is_definition, m.is_synthesized_accessor, m.is_implicit, '
            'm.property_usr, m.container_kind FROM objc_method m WHERE m.selector = ? AND m.is_class_method = 0 AND '
            'm.class_name = ? ORDER BY m.is_definition DESC, m.file, m.line', (sel, cls)).fetchall()
        if not rows:
            inherited = inherited_accessor(codedb, con, chain, sel) if codedb is not None else None
            found = inherited is not None and not inherited.startswith('unknown')
            if not found:
                text, found = runtime_inherited(lists, chain, sel)
                inherited = text if (found or inherited is None) else '%s; %s' % (inherited, text)
            if found or always:
                out.append({'selector': sel, 'form': form, 'state': inherited,
                            'private_methods_consulted': consulted})
            continue
        defs = [r for r in rows if r[3] or r[4]]
        usrs = sorted(set(r[0] for r in rows if r[0]))
        overrides = ['%s (%s:%d)' % r for r in con.execute(
            'SELECT DISTINCT m.class_name, m.file, m.line FROM objc_method_override o JOIN objc_method m ON m.id = '
            'o.method WHERE o.overridden_usr IN (%s) AND m.class_name IS NOT NULL AND m.class_name != ? ORDER BY '
            'm.class_name, m.file, m.line' % ','.join('?' * len(usrs)), usrs + [cls]).fetchall()] if usrs else []
        overrides += swift_overrides(con, usrs)
        entry = {'selector': sel, 'form': form, 'overridden_by': overrides, 'private_methods_consulted': consulted}
        if swift_note:
            entry['swift_overrides'] = swift_note
        if not defs:
            entry['state'] = 'declared, with no definition in this database (dynamic, forwarded or in Swift)'
        elif all(r[4] for r in defs):
            prop = con.execute("SELECT name, attributes, ivar_usr, ivar_name FROM objc_property WHERE kind = "
                               "'synthesize' AND class_name = ? AND usr = ? LIMIT 1",
                               (cls, defs[0][6])).fetchone() if defs[0][6] else None
            if prop and prop[2] and prop[2] != ivar_usr:
                entry['state'] = 'synthesized for property %s, which is backed by %s, not this ivar' % (
                    prop[0], prop[3])
            else:
                attrs = con.execute('SELECT attributes FROM objc_property WHERE usr = ? AND kind != \'synthesize\' '
                                    'LIMIT 1', (defs[0][6],)).fetchone() if defs[0][6] else None
                entry['state'] = 'synthesized%s' % (' (property %s, %s)' % (prop[0], attrs[0] if attrs else '?')
                                                    if prop else '')
                if attrs and 'nonatomic' not in attrs[0].split(','):
                    entry['state'] += '; atomic, so not trivial by objc-state.md section 2'
        else:
            d = [r for r in defs if not r[4]][0]
            entry['state'] = 'written by hand at %s:%d (not proven trivial)' % (d[1], d[2])
        if lists:
            text, found = runtime_inherited(lists, chain, sel)
            if found:
                entry['state'] += '; overrides a framework method: ' + text
        out.append(entry)
    return out


def accessor_text(entries):
    parts = []
    for e in entries:
        text = '-%s (%s) %s' % (e['selector'], e['form'], e['state']) if e.get('form') else '-%s %s' % (
            e['selector'], e['state'])
        if e.get('overridden_by'):
            text += '; overridden by %s' % ', '.join(e['overridden_by'])
        if e.get('swift_overrides'):
            text += '; ' + e['swift_overrides']
        parts.append(text)
    return '; '.join(parts) + ('; key-value observing and bindings of the key not checked' if any(
        not e['state'].startswith('none') for e in entries) else '')


def governing_views(decl_rows, own):
    """The rows of one declaration recorded in the mode of the class's
    @implementation (Own.class_modes), which decides how the ivar is held,
    and their distinct views. When no unit of that mode recorded it, or the
    class has no @implementation in the database, every row."""
    rows = [r for r in decl_rows if not own.class_modes or r['arc'] in own.class_modes] or decl_rows
    views = collections.OrderedDict()
    for r in rows:
        views.setdefault((r['arc'], r['type'], r['ownership'], r['import_facts'], r['type_class']), []).append(
            r['main_file'])
    return rows, views


def declared_record(codedb, q, cls, first, decl_rows):
    kind = first['container_kind']
    synth = first['synthesized_by']
    in_source = first['file'].endswith(SOURCE_SUFFIXES)
    if synth:
        where = 'synthesized %s for property %s' % ('automatically' if synth == 'automatic' else 'by @synthesize',
                                                    first['property_name'])
    elif kind == 'interface':
        where = '@interface in a source file' if in_source else 'header @interface'
    elif kind == 'extension':
        where = 'class extension in a source file' if in_source else 'class extension in a header'
    else:
        where = CONTAINER_TEXT.get(kind, kind)
    backing = q.con.execute("SELECT DISTINCT p.name, p.attributes, p.is_implicit FROM objc_property p WHERE p.kind = "
                            "'synthesize' AND p.class_name = ? AND p.ivar_usr = ? ORDER BY p.name",
                            (cls, first['usr'])).fetchall() if first['usr'] else []
    props = []
    for name, attrs, implicit in backing:
        decl = q.con.execute("SELECT attributes FROM objc_property WHERE class_name = ? AND name = ? AND kind != "
                             "'synthesize' LIMIT 1", (cls, name)).fetchone()
        props.append({'name': name, 'synthesize_attributes': attrs, 'attributes': decl[0] if decl else attrs,
                      'synthesized': 'automatically' if implicit else 'by @synthesize'})
    return {'where': where, 'container_kind': kind, 'file': first['file'], 'line': first['line'], 'col': first['col'],
            'access': first['access'], 'iboutlet': bool(first['is_iboutlet']), 'macro': first['macro_name'],
            'backs_properties': props}


def users_by_function(refs):
    """{function: {access: [lines]}} in order of the number of references."""
    by = collections.OrderedDict()
    for r in refs:
        f = (r['function'], r['file'])
        by.setdefault(f, collections.OrderedDict()).setdefault(r['access'] + (' (part)' if r['partial'] else ''),
                                                                []).extend([r['line']] * r['references_here'])
    return sorted(by.items(), key=lambda kv: (-sum(len(v) for v in kv[1].values()), kv[0]))


def summary(refs):
    count = collections.Counter()
    for r in refs:
        count[r['access']] += r['references_here']
    return {'references': sum(count.values()), 'by_access': dict(count),
            'functions': len(set((r['function'], r['file']) for r in refs)),
            'outside_own_code': sum(r['references_here'] for r in refs if r['outside_own_code']),
            'in_blocks': sum(r['references_here'] for r in refs if r['in_block']),
            'in_lambdas': sum(r['references_here'] for r in refs if r['in_lambda']),
            'synchronized': sum(r['references_here'] for r in refs if r['synchronized_on'])}


def type_verdict(views):
    """importability over the governing views: one verdict when they agree."""
    verdicts = collections.OrderedDict()
    for (_, _, _, facts, tclass), _ in views.items():
        verdicts.setdefault(importability(tclass, facts), True)
    if len(verdicts) == 1:
        return next(iter(verdicts))
    return UNKNOWN, 'units disagree: %s' % '; '.join('%s (%s)' % v for v in verdicts)


def swift_override_note(q):
    """Why Swift overrides of the accessors are not known, or None when the
    Swift side of the database is captured and every module is current."""
    if q.swift_states is None:
        return 'Swift overrides not known (the Swift side is not in this database)'
    stale = sorted(s.module for s in q.swift_states.values() if s.state != 'current')
    if stale:
        return 'Swift overrides not known (module stale: %s)' % ', '.join(stale)
    return None


def ivar_rows(codedb, q, cls, own):
    decls = as_dicts(q.con.execute(IVAR_SQL, (cls,)).fetchall(), IVAR_COLS)
    by_decl = collections.OrderedDict()
    for d in decls:
        by_decl.setdefault((d['name'], d['file'], d['line'], d['col']), []).append(d)
    chain = codedb.class_chain(q.con, cls)
    lists = getattr(q, 'runtime_lists', ())
    swift_note = swift_override_note(q)
    if lists:
        # One pass over each list for every selector the accessors ask about.
        wanted = set(sel for rows in by_decl.values() for sel, _, _ in accessor_candidates(
            q.con, cls, rows[0]['name'], rows[0]['usr'], chain))
        for rm in lists:
            rm.prefetch(wanted)
    refs_by_name = collections.defaultdict(list)
    for r in as_dicts(q.con.execute(IVAR_REF_SQL, (cls,)).fetchall(), REF_COLS):
        refs_by_name[r['name']].append(r)
    out = []
    for (name, _, _, _), rows in by_decl.items():
        gov, views = governing_views(rows, own)
        first = gov[0]
        verdict, why = type_verdict(views)
        refs = [ref_record(codedb, q, g, cls, own, True) for g in group_refs(refs_by_name.get(name, []))]
        conflict = None
        if (len(set((a, t, o) for a, t, o, _, _ in views)) > 1
                or len(set((r['type'], r['ownership']) for r in rows)) > 1):
            conflict = ['%s: %s, %s (recorded by %s)' % (codedb.MODE_NAMES[r['arc']], r['type'], r['ownership'],
                                                          r['main_file']) for r in rows]
        out.append({
            'kind': 'ivar', 'name': name, 'type': first['type'], 'canonical_type': first['canonical_type'],
            'type_class': first['type_class'], 'object_class': first['object_class'],
            'protocols': first['object_protocols'], 'record': first['record_name'], 'bit_width': first['bit_width'],
            'type_encoding': first['type_encoding'],
            'declared': declared_record(codedb, q, cls, first, rows),
            'mode': mode_text(codedb, own), 'ownership': first['ownership'],
            'ownership_written': first['ownership_written'], 'views_conflict': conflict,
            'import_facts': first['import_facts'], 'importable': {'verdict': verdict, 'reason': why},
            'accessor': accessor_info(q.con, cls, name, first['usr'], codedb, chain, lists, swift_note),
            'summary': summary(refs), 'references': refs,
            'marks': q.marks(set(r['tu'] for r in rows)), 'in_migration_scope': bool(first['in_migration_scope']),
        })
    return out


def static_rows(codedb, q, cls, own):
    out = []
    for f in own.files:
        decls = as_dicts(q.con.execute(STATIC_SQL, (f,)).fetchall(), STATIC_COLS)
        by_usr = collections.OrderedDict()
        for d in decls:
            by_usr.setdefault(d['usr'] or (d['name'], d['line'], d['col']), []).append(d)
        for usr, rows in by_usr.items():
            first = rows[0]
            views = collections.OrderedDict()
            for r in rows:
                views.setdefault((r['arc'], r['type'], r['ownership'], r['import_facts'], r['type_class']), [])
            verdict, why = type_verdict(views)
            refs = [ref_record(codedb, q, g, cls, own, False) for g in group_refs(as_dicts(
                q.con.execute(STATIC_REF_SQL, (first['usr'],)).fetchall(), REF_COLS))] if first['usr'] else []
            out.append({
                'kind': first['kind'], 'name': first['name'], 'enclosing': first['enclosing_name'],
                'type': first['type'], 'canonical_type': first['canonical_type'], 'type_class': first['type_class'],
                'declared': {'file': first['file'], 'line': first['line'], 'col': first['col'],
                             'macro': first['macro_name']},
                'mode': ' and '.join(codedb.MODE_NAMES[m] for m in sorted(set(r['arc'] for r in rows), reverse=True)),
                'ownership': first['ownership'], 'ownership_written': first['ownership_written'],
                'const': bool(first['is_const']), 'pointee_const': first['pointee_const'],
                'initializer': first['init_kind'], 'thread_local': bool(first['thread_local']),
                'import_facts': first['import_facts'], 'importable': {'verdict': verdict, 'reason': why},
                'summary': summary(refs), 'references': refs,
                'marks': q.marks(set(r['tu'] for r in rows)), 'in_migration_scope': bool(first['in_migration_scope']),
            })
    return out


# --- Writing ------------------------------------------------------------------

def ref_line(r):
    parts = ['%s:%d:%d' % (r['file'], r['line'], r['col']), r['function'], r['access'] + (' (part)' if r['partial']
                                                                                         else '')]
    if r['kind'] != 'direct':
        parts.append(r['kind'].replace('-', ' '))
    if r['in_block']:
        parts.append('in block')
    if r['in_once_block']:
        parts.append('in dispatch_once block')
    if r['in_lambda']:
        parts.append('in lambda (%s)' % r['in_lambda'])
    if r['synchronized_on']:
        parts.append('under @synchronized (%s)' % r['synchronized_on'])
    if r['macro']:
        parts.append('in macro %s' % r['macro'])
    parts += r['outside_own_code'] + r['marks']
    return '  '.join(parts)


def write_row(out, row):
    s = row['summary']
    out.write('\n%s %s  %s\n' % (row['kind'], row['name'], row['type']))
    if row['kind'] == 'ivar':
        d = row['declared']
        decl = '%s, %s:%d:%d, %s' % (d['where'], d['file'], d['line'], d['col'], d['access'])
        if d['iboutlet']:
            decl += ', IBOutlet'
        for p in d['backs_properties']:
            decl += '; backs property %s (%s), synthesized %s' % (p['name'], p['attributes'], p['synthesized'])
        if d['macro']:
            decl += '; made by macro %s' % d['macro']
    else:
        d = row['declared']
        decl = '%s%s, %s:%d:%d' % (row['kind'], ' in %s' % row['enclosing'] if row['enclosing'] else '', d['file'],
                                   d['line'], d['col'])
        extras = [x for x in ('const' if row['const'] else None, 'thread-local' if row['thread_local'] else None,
                              'initializer %s' % row['initializer']) if x]
        decl += '; ' + ', '.join(extras)
    out.write('    declared     %s\n' % decl)
    if row['canonical_type'] != row['type']:
        out.write('    canonical    %s\n' % row['canonical_type'])
    out.write('    mode         %s\n' % row['mode'])
    own = row['ownership'] if row['ownership'] != 'none' else 'none (not an object or block)'
    if row['ownership_written']:
        own += ' (written __%s)' % row['ownership_written']
    out.write('    ownership    %s\n' % own)
    if row.get('views_conflict'):
        out.write('    CONFLICT     units record it differently: %s\n' % '; '.join(row['views_conflict']))
    imp = row['importable']
    out.write('    importable   %s: %s\n' % (imp['verdict'], imp['reason']))
    if row['kind'] == 'ivar':
        out.write('    accessor     %s\n' % accessor_text(row['accessor']))
        out.write('    encoding     %s\n' % (row['type_encoding'] or '(empty: the compiler gives no encoding)'))
    if row['marks']:
        out.write('    marks        %s\n' % ', '.join(row['marks']))
    out.write('    users        %d references in %d functions%s\n' % (
        s['references'], s['functions'], ': ' + ', '.join('%s %d' % (a, s['by_access'][a]) for a in ACCESS_ORDER
                                                          if s['by_access'].get(a)) if s['references'] else ''))
    for (function, file), accesses in users_by_function(row['references']):
        out.write('      %s  %s: %s\n' % (function, file, '; '.join(
            '%s %d (lines %s)' % (a, len(lines), ', '.join(str(n) for n in sorted(set(lines))))
            for a, lines in accesses.items())))
    outside = [r for r in row['references'] if r['outside_own_code']]
    out.write('    outside      %d references from outside the class\'s own code%s\n' % (
        s['outside_own_code'], ':' if outside else ''))
    for r in outside:
        out.write('      %s\n' % ref_line(r))
    for label, key in (('blocks', 'in_block'), ('lambdas', 'in_lambda'), ('synchronized', 'synchronized_on')):
        hits = [r for r in row['references'] if r[key]]
        out.write('    %-12s %d%s\n' % (label, sum(r['references_here'] for r in hits), ':' if hits else ''))
        for r in hits:
            out.write('      %s\n' % ref_line(r))


NOT_CHECKED = [
    'whether the class, protocols and typedefs of a type are visible to the bridging header (the Phase 0 item '
    '"Code database, what Swift can import")',
    'key-value observing, bindings and key-value coding of the accessor names (objc-state.md section 2)',
    'locks other than @synchronized, queues and threads (concurrency.md)',
    'how often each reference runs (cold, warm, hot: the dossier and the perf harness)',
    'references from Swift: Swift imports no ivar and the Swift tables record no reference to a C static',
]


def load_runtime_lists(files):
    """entry_points.RuntimeMethods for each run-time method list file
    (sdk_selectors.py --runtime-methods), or CodeDBError."""
    if not files:
        return []
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import entry_points
    out = []
    for f in files:
        try:
            out.append(entry_points.load_runtime_methods(f))
        except entry_points.CensusError as e:
            raise ValueError(str(e))
    return out


def classstate(codedb, paths, cls, as_json=False, out=None, runtime_methods=()):
    out = out or sys.stdout
    spec = codedb.QuerySpec('classstate', codedb.STATE_NOT_IN_DATABASE,
                            codedb.exit_text('ivars or statics printed', True, True), codedb.IVARS_SEARCH_FORMS, True)
    try:
        lists = load_runtime_lists(runtime_methods)
    except ValueError as e:
        raise codedb.CodeDBError(str(e))
    q = codedb.QueryContext(paths, spec)
    q.state_class = cls
    q.runtime_lists = lists
    try:
        q.search_not_parsed(forms=codedb.search_forms_class(cls), skip_definitions=False)
        q.search_forms_text = codedb.IVARS_SEARCH_FORMS
        own = Own(q.con, cls)
        ivars = ivar_rows(codedb, q, cls, own)
        statics = static_rows(codedb, q, cls, own)
        rows = ivars + statics
        skipped = io.StringIO()
        names = [cls] + sorted(set(r['name'] for r in ivars))
        codedb.skipped_search_incomplete(q, codedb.write_skipped_search(
            q, skipped, names, 'declarations of or references to the class or its ivars'), len(rows))
        status_text = io.StringIO()
        marked = sum(1 for r in rows if r['marks'])
        outside = sum(1 for r in rows if not r['in_migration_scope'])
        q.write_status(status_text, len(rows), marked, outside)
        status = q.exit_status(len(rows))
        impls = [{'file': f, 'category': c, 'mode': codedb.MODE_NAMES[a]} for f, c, a in own.impls]
        if as_json:
            json.dump({'class': cls, 'implementations': impls, 'mode': mode_text(codedb, own),
                       'private_methods_consulted': bool(q.runtime_lists),
                       'ivars': ivars, 'statics': statics, 'not_checked': NOT_CHECKED,
                       'skipped_code': skipped.getvalue().splitlines(), 'incomplete': q.incomplete_lines(),
                       'exit_status': status}, out, indent=1, sort_keys=True)
            out.write('\n')
            return status
        out.write('Class state of %s: %d ivars, %d statics in its implementation files\n' % (
            cls, len(ivars), len(statics)))
        if impls:
            out.write('implemented in: %s\n' % ', '.join('%s (%s%s)' % (i['file'], 'category %s, ' % i['category']
                                                                         if i['category'] else '', i['mode'])
                                                         for i in impls))
        else:
            out.write('implemented in: no @implementation of %s is in this database\n' % cls)
        where = codedb.class_chain(q.con, cls)[0][1]
        if where.startswith('SDK') or where == codedb.SWIFT_CLASS:
            out.write('the class itself is not in the repository (%s); only its categories are\n' % (
                where if where != codedb.SWIFT_CLASS else 'declared in Swift'))
        verdicts = collections.Counter(r['importable']['verdict'] for r in rows)
        out.write('importable: %s\n' % ', '.join('%s %d' % (v, verdicts[v]) for v in (YES, DEGRADED, NO, UNKNOWN)))
        for row in rows:
            write_row(out, row)
        out.write('\n')
        out.write('not checked by this query:\n')
        for item in NOT_CHECKED:
            out.write('  - %s\n' % item)
        out.write(codedb.STATE_LIMITS_LINE + '\n')
        out.write(skipped.getvalue())
        out.write(status_text.getvalue())
        return status
    finally:
        q.close()
