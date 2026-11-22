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
                  checks them again), then refined by refine_visibility()
                  from the import table of the bridging header: the
                  repository classes and protocols the type names, at the top
                  level and inside it (block parameters and result, type
                  arguments, array element, pointee), each judged, an
                  unimported one inside deciding the verdict by position
                  (position_verdict, with what swiftc showed) or leaving it
                  unknown. Records, typedefs and enums inside a type are not
                  judged. Without an import table the reason says visibility
                  was not checked; a type declared in the implementation file
                  is said to be private to it. A lock type gets a note that
                  its value must not be copied
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
import re
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


# --- Visibility to the bridging header, from the import table -----------------

FORWARD_TEXT = 'is only forward-declared in this unit'
NO_TABLE = 'visibility: not checked (the database has no import table: codedb.py update --imports-only fills it)'
FRAMEWORK_CLASS = 'declared in the framework target %s, which Swift reads as that framework\'s module, not through ' \
                  'the bridging header: not checked'


class ImportTable:
    """What the swift_import rows (swiftimports.py, the compiler's symbol
    graph of the bridging header) say about the classes, protocols and
    records a type names. One module with a bridging header is consulted:
    the only one in the table (iTerm2SharedARC today); with none or several
    the visibility is not checked. A row is trusted only while the module's
    import state is current; otherwise the visibility is left undecided,
    with the state's reason. SDK classes and protocols are never in the
    table (Swift imports them as their framework modules), so they are
    recognized from sdk_class and the SDK's protocols. The database has no
    table of C records, enums or typedefs, so a record absent from the table
    is not judged."""

    def __init__(self, codedb, q):
        import swiftimports
        con = q.con
        self.con = con
        self.module = None
        self.state = None
        self.note = NO_TABLE
        self.cache = {}
        if swiftimports.import_tables_version(con) is None:
            return
        modules = [r[0] for r in con.execute('SELECT DISTINCT module FROM swift_import_unit ORDER BY module')]
        if len(modules) != 1:
            self.note = 'visibility: not checked (the import table holds %s modules with a bridging header: %s)' % (
                len(modules), ', '.join(modules) or 'no')
            return
        self.module = modules[0]
        self.note = None
        swift = getattr(q, 'swift', None)
        if swift is not None and swift.captured:
            states = swiftimports.import_states(con, swift, codedb.DigestCache(q.paths.root))
            st = states.get(self.module)
            self.state = st.state if st else 'missing'
            self.reason = st.reason if st else 'not in the import table'
        else:
            self.state = 'not checked'
            self.reason = 'the capture has no Swift inputs, so the import rows cannot be checked'
        if self.state not in ('current', 'not checked'):
            self.note = 'visibility: not decided (the import table of %s is %s: %s)' % (
                self.module, self.state, self.reason)
            self.module_ok = False
        else:
            self.module_ok = True
        self.sdk_protocols = set(r[0] for r in con.execute(
            "SELECT DISTINCT container FROM sdk_method WHERE container_kind = 'protocol' UNION SELECT DISTINCT "
            "container FROM sdk_adoption WHERE container_kind = 'protocol' UNION SELECT DISTINCT protocol FROM "
            "sdk_adoption"))
        self.swift_classes = set(r[0] for r in con.execute(
            'SELECT DISTINCT class_name FROM swift_objc_decl WHERE class_name IS NOT NULL')) if 'swift_objc_decl' in \
            codedb.table_names(con) else set()
        # The repository's classes and protocols by name, to find the ones a
        # type names inside it (in a block, type arguments, an array element
        # or a pointee), which the tables record only as words of its type.
        self.repository_classes = set(r[0] for r in con.execute('SELECT DISTINCT name FROM objc_class'))
        self.repository_protocols = set(r[0] for r in con.execute(
            "SELECT DISTINCT container_name FROM objc_method WHERE container_kind = 'protocol' UNION SELECT DISTINCT "
            "class_or_category FROM objc_adoption WHERE container_kind = 'protocol'"))

    def is_repository(self, kind, name):
        """Whether the repository declares a class (kind 'class') or a
        protocol (kind 'protocol') of this name."""
        return name in (self.repository_classes if kind == 'class' else self.repository_protocols)

    def imported(self, usrs):
        """Whether the import table has a row for one of these Clang USRs
        (the table's key; a protocol's objc_name is written <P>)."""
        key = tuple(usrs)
        if key not in self.cache:
            self.cache[key] = self.con.execute(
                'SELECT 1 FROM swift_import WHERE module = ? AND usr IN (%s) LIMIT 1' % ','.join('?' * len(usrs)),
                (self.module,) + key).fetchone() is not None
        return self.cache[key]

    def judge_class(self, name):
        """(state, text): state is 'visible', 'not-imported' or 'unknown'."""
        if self.imported(('c:objc(cs)' + name,)):
            return 'visible', 'class %s is imported through the bridging header' % name
        if self.con.execute('SELECT 1 FROM sdk_class WHERE name = ? LIMIT 1', (name,)).fetchone():
            return 'visible', 'class %s is an SDK class, imported as its framework module' % name
        targets = set(r[0] for r in self.con.execute(
            'SELECT DISTINCT t.target FROM objc_class c JOIN tu t ON t.id = c.tu WHERE c.name = ?', (name,)))
        if targets and all(':' in t for t in targets):
            return 'unknown', 'class %s is %s' % (name, FRAMEWORK_CLASS % ', '.join(sorted(targets)))
        if targets:
            return 'not-imported', 'class %s is declared in the repository and absent from the import table of %s' % (
                name, self.module)
        if name in self.swift_classes:
            return 'visible', 'class %s is declared in Swift' % name
        return 'unknown', 'class %s is in neither the import table, the repository nor the SDK tables' % name

    def judge_protocol(self, name):
        if self.imported(('c:objc(pl)' + name,)):
            return 'visible', 'protocol %s is imported through the bridging header' % name
        if name in self.sdk_protocols:
            return 'visible', 'protocol %s is an SDK protocol, imported as its framework module' % name
        targets = set(r[0] for r in self.con.execute(
            "SELECT DISTINCT t.target FROM objc_method m JOIN tu t ON t.id = m.tu WHERE m.container_kind = "
            "'protocol' AND m.container_name = ? UNION SELECT DISTINCT t.target FROM objc_adoption a JOIN tu t ON "
            "t.id = a.tu WHERE a.container_kind = 'protocol' AND a.class_or_category = ?", (name, name)))
        if targets and all(':' in t for t in targets):
            return 'unknown', 'protocol %s is %s' % (name, FRAMEWORK_CLASS % ', '.join(sorted(targets)))
        if targets:
            return 'not-imported', 'protocol %s is declared in the repository and absent from the import table of ' \
                                   '%s' % (name, self.module)
        if name in self.swift_classes:
            return 'visible', 'protocol %s is declared in Swift' % name
        return 'unknown', 'protocol %s is in neither the import table, the repository, the SDK nor the Swift ' \
                          'tables' % name

    def judge_record(self, name):
        if self.imported(tuple('c:@%s@%s' % (k, name) for k in ('S', 'SA', 'U', 'UA'))):
            return 'visible', 'record %s is imported through the bridging header' % name
        return 'unknown', 'record %s is absent from the import table: an SDK record (imported as its framework ' \
                          'module) or one the bridging header does not reach; the database has no table of C ' \
                          'records to tell which' % name


def named_types(row):
    """[(kind, name)] of the classes, protocols and records a type names,
    from its objc_ivar or c_static row. A dispatch or os object
    (NSObject<OS_x>) names none: Swift imports it as its own class."""
    facts = set((row.get('import_facts') or '').split())
    out = []
    if row.get('type_class') == 'object' and 'os-object' not in facts:
        if row.get('object_class') and row['object_class'] not in ('id', 'Class'):
            out.append(('class', row['object_class']))
        for p in (row.get('object_protocols') or '').split(','):
            if p.strip():
                out.append(('protocol', p.strip()))
    if row.get('type_class') in ('struct', 'union') and row.get('record_name'):
        out.append(('record', row['record_name']))
    return out


# What swiftc does with a property (a global, for a C array) whose type has,
# in each position, a class that is only forward-declared to the bridging
# header; probed on 2026-11-21 (Apple Swift 6.4, arm64, macOS 13 target):
#   NSArray<U *>, NSDictionary<NSString *, U *>, NSArray<id<P>>, Gen<U *> (a
#     generic class of the header), a block taking U * or id<P> or returning
#     U *: the member is not imported.
#   NSMutableArray, NSMutableDictionary, NSMutableSet, NSOrderedSet,
#     NSMutableOrderedSet, NSEnumerator, NSCountedSet with U * as an
#     argument: imported with the arguments dropped (their API notes import
#     them as non-generic).
#   NSCache, NSMapTable, NSHashTable with U * as an argument: not imported.
#   U *__autoreleasing * and a function pointer taking U *: OpaquePointer.
#   A C array of U *: the declaration is invalid in Swift.
# Other positions, other generic SDK classes, and types nested more than one
# level are not decided.
ERASED_SDK_GENERICS = frozenset(('NSMutableArray', 'NSMutableDictionary', 'NSMutableSet', 'NSOrderedSet',
                                 'NSMutableOrderedSet', 'NSEnumerator', 'NSCountedSet'))
KEPT_SDK_GENERICS = frozenset(('NSCache', 'NSMapTable', 'NSHashTable'))
NOT_CHECKED_PARTS = 'visibility: not checked for the parts of this type'
_IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z_0-9]*')
_ID_PROTOCOLS = re.compile(r'\bid\s*<[^<>]*>')


_QUALIFIERS = r'(?:(?:_Nonnull|_Nullable|_Null_unspecified|__strong|__weak|__unsafe_unretained|__autoreleasing|' \
              r'__kindof|const|volatile)\s*)*'
_QUALIFIER_WORDS = frozenset(('_Nonnull', '_Nullable', '_Null_unspecified', '__strong', '__weak',
                              '__unsafe_unretained', '__autoreleasing', '__kindof', 'const', 'volatile'))
_CLASS_BEFORE_STAR = re.compile(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*' + _QUALIFIERS + r'\*')
_ANGLE_GROUP = re.compile(r'<([^<>]*)>')


def type_names(text):
    """[(kind, name)] of the classes and protocols a printed type names: a
    word written before a pointer star is a class; a word in a list between
    angle brackets with no star is a protocol (id<P>, NSObject<P>, Gen<P>
    is not a type argument without a star). Clang's notes about unnamed and
    anonymous records (with a file path) and the word after struct, union or
    enum are left out."""
    text = re.sub(r'\((?:unnamed|anonymous) [^)]*\)', ' ', text or '')
    text = re.sub(r'\b(?:struct|union|enum)\s+[A-Za-z_][A-Za-z_0-9]*', ' ', text)
    out = []

    def add(kind, name):
        if (kind, name) not in out:
            out.append((kind, name))
    while True:
        m = _ANGLE_GROUP.search(text)
        if not m:
            break
        for item in m.group(1).split(','):
            if '*' in item:
                for name in _CLASS_BEFORE_STAR.findall(item):
                    add('class', name)
            else:
                for name in _IDENTIFIER.findall(item):
                    if name not in ('id', 'Class') and name not in _QUALIFIER_WORDS:
                        add('protocol', name)
        text = text[:m.start()] + text[m.end():]
    for name in _CLASS_BEFORE_STAR.findall(text):
        add('class', name)
    return out


def inner_names(table, row, top):
    """[(kind, name)] of the repository's classes and protocols that the
    type names inside it (type_names), less the top-level ones."""
    return [(kind, name) for kind, name in type_names(row.get('type'))
            if (kind, name) not in top and table.is_repository(kind, name)]


def _direct_pointers(text, names):
    """Whether every class name occurs as NAME * (not NAME **) and every
    protocol inside id<...>."""
    for kind, name in names:
        for m in re.finditer(r'\b%s\b' % re.escape(name), text):
            rest = text[m.end():]
            if kind == 'class' and not re.match(r'\s*\*(?!\s*(?:_\w+\s*)*\*)', rest):
                return False
    return True


def position_verdict(row, names):
    """(verdict, reason) for a type with a class or protocol Swift does not
    import inside it, by position (the probe above), or None when the
    position was not checked."""
    text = row.get('type') or ''
    facts = set((row.get('import_facts') or '').split())
    tclass = row.get('type_class')
    flat = _ID_PROTOCOLS.sub('id', text)
    if tclass == 'block':
        if '<' in flat or not _direct_pointers(text, names):
            return None
        return NO, 'a block whose parameter or result is a class or protocol Swift does not import is not imported ' \
                   '(checked)'
    if tclass == 'c-pointer' and '<' not in flat:
        if 'function-pointer' in facts and _direct_pointers(text, names):
            return DEGRADED, 'a function pointer whose parameter or result is a class Swift does not import is ' \
                             'imported as OpaquePointer (checked)'
        if 'object-pointee' in facts and '(' not in text:
            return DEGRADED, 'a pointer to a pointer to a class Swift does not import is imported as OpaquePointer ' \
                             '(checked)'
        return None
    if tclass == 'array' and '<' not in flat and '(' not in text and _direct_pointers(text, names):
        return NO, 'a C array of a class Swift does not import is invalid in Swift (checked for a global)'
    if tclass == 'object' and '<' in text and '(' not in text:
        args = text[text.index('<') + 1:text.rindex('>')]
        if '<' in _ID_PROTOCOLS.sub('id', args):
            return None
        outer = row.get('object_class')
        if facts & {'generic-bridged', 'generic-repository'}:
            return NO, 'a type argument of %s is a class or protocol Swift does not import, so the member is not ' \
                       'imported (checked)' % outer
        if 'generic-sdk' in facts and outer in ERASED_SDK_GENERICS:
            return DEGRADED, 'Swift imports %s without its type arguments (its API notes), so the argument it ' \
                             'cannot see is erased (checked)' % outer
        if 'generic-sdk' in facts and outer in KEPT_SDK_GENERICS:
            return NO, 'Swift keeps the type arguments of %s, and one is a class or protocol it does not import, ' \
                       'so the member is not imported (checked)' % outer
    return None


def refine_visibility(table, row, verdict, why):
    """The verdict and reason of importability() with its visibility clause
    decided from the import table where it can be. The classes and
    protocols the type names are judged at the top level (a repository one
    that Swift does not import makes the verdict no; a forward-declared one
    that Swift imports lifts unknown to yes) and inside the type (in a
    block, type arguments, an array element or a pointee: decided by
    position_verdict, or unknown with NOT_CHECKED_PARTS). Records inside a
    type, typedefs and enums are not judged. Without a usable table the
    reason says why visibility was not checked."""
    forward = verdict == UNKNOWN and FORWARD_TEXT in why
    if table is None or table.note == NO_TABLE or (VISIBILITY not in why and not forward):
        # Without an import table the reason keeps importability()'s own
        # "visibility: not checked".
        return verdict, why
    if table.module is None or not table.module_ok:
        return verdict, why.replace(VISIBILITY, table.note) if VISIBILITY in why else '%s; %s' % (why, table.note)
    judges = {'class': table.judge_class, 'protocol': table.judge_protocol, 'record': table.judge_record}
    top = named_types(row)
    judged = [judges[kind](name) for kind, name in top]
    inner = inner_names(table, row, top)
    inner_judged = [(kn, judges[kn[0]](kn[1])) for kn in inner]
    missing = [t for s, t in judged if s == 'not-imported']
    unknown = [t for s, t in judged if s == 'unknown']
    inner_missing = [(kn, t) for kn, (s, t) in inner_judged if s == 'not-imported']
    inner_unknown = [t for _, (s, t) in inner_judged if s == 'unknown']
    parts = [t for _, t in judged]
    if inner_judged:
        parts.append('inside the type: %s' % '; '.join(t for _, (_, t) in inner_judged))
    text = 'visibility (import table of %s%s): %s' % (
        table.module, ', whose rows could not be checked for staleness' if getattr(table, 'state', None) ==
        'not checked' else '', '; '.join(parts) if parts else
        'the type names no class or protocol of the repository (classes and protocols are looked for anywhere in '
        'the type; records, typedefs and enums inside it are not judged)')
    if missing:
        return NO, '%s: Swift drops a member of this type until the header that declares it is in the bridging ' \
                   'header (objc-state.md section 1, remedy 4); the type alone is %s: %s' % (
                       '; '.join(missing), verdict, why.replace(VISIBILITY, text))
    top_unknown = [t for (kind, _), (s, t) in zip(top, judged) if s == 'unknown' and kind != 'record']
    if top_unknown and verdict != NO and not forward:
        return UNKNOWN, '%s; the type alone is %s: %s' % ('; '.join(top_unknown), verdict,
                                                         why.replace(VISIBILITY, text))
    if inner_missing:
        decided = position_verdict(row, [kn for kn, _ in inner_missing])
        names = '; '.join(t for _, t in inner_missing)
        if decided is None:
            return UNKNOWN, '%s (%s), in a position whose import was not checked; the type alone is %s: %s' % (
                NOT_CHECKED_PARTS, names, verdict, why.replace(VISIBILITY, text))
        v, reason = decided
        if verdict == NO or (verdict == DEGRADED and v == YES) or verdict == UNKNOWN and v != NO:
            v = verdict
        return v, '%s: %s; the type alone is %s: %s' % (names, reason, verdict, why.replace(VISIBILITY, text))
    if inner_unknown and verdict != NO:
        return UNKNOWN, '%s (%s); the type alone is %s: %s' % (NOT_CHECKED_PARTS, '; '.join(inner_unknown), verdict,
                                                              why.replace(VISIBILITY, text))
    if forward:
        if judged and not unknown:
            return YES, 'the class or protocol is only forward-declared in this unit, but Swift sees it: %s' % text
        return verdict, '%s; %s' % (why, text)
    return verdict, why.replace(VISIBILITY, text)


ONCE_TOKEN_TYPES = ('dispatch_once_t', 'os_once_t')
CXX_NOT_DECIDED = 'not decided: C++ object; operator and member calls are recorded as reads'


def static_written(codedb, refs, row=None):
    """Whether a static is written after its initialization, from its
    references (ref_record dicts): an address taken or a by-reference use
    counts as a possible write, as codedb.py statics counts it; a reference
    in a branch the compiler folds away does not. row (its declaration:
    type, type_class, import_facts, const or is_const) decides two cases the
    references cannot: a non-const C++ object, whose operator and member
    calls (+= on a std::atomic, fetch_add, lock) the extractor records as
    reads, is not decided; a once token is said to be one."""
    writes = [r for r in refs if r['access'] in codedb.STATE_WRITES and not r['in_constant_false_branch']]
    if row is not None:
        facts = set((row.get('import_facts') or '').split())
        const = row.get('const', row.get('is_const'))
        if not const and (row.get('type_class') == 'cxx-object' or facts & {'cxx-record', 'cxx-template'}):
            return CXX_NOT_DECIDED
        typ = row.get('type') or ''
        if any(r['access'] == 'once-token' for r in refs) or any(t in typ for t in ONCE_TOKEN_TYPES):
            others = sorted(set(r['function'] for r in writes))
            return 'once token: dispatch_once writes it%s' % (
                '; also written (counting address-of and by-reference uses) from %s' % ', '.join(others)
                if others else '')
    if not writes:
        return 'no write, address-of or by-reference use recorded after its initialization'
    if all(r['in_once_block'] for r in writes):
        return 'only in a dispatch_once block (every write, address-of or by-reference use recorded)'
    functions = sorted(set(r['function'] for r in writes))
    return 'after initialization (counting address-of and by-reference uses), from %d function%s: %s' % (
        len(functions), '' if len(functions) == 1 else 's', ', '.join(functions))


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
              's.type_class, s.object_class, s.object_protocols, s.record_name, s.ownership_written, s.ownership, s.arc, s.import_facts, '
              's.is_const, s.pointee_const, s.init_kind, s.thread_local, s.macro_name, s.in_migration_scope, s.tu, '
              't.main_file, t.target FROM c_static s JOIN tu t ON t.id = s.tu WHERE s.file = ? AND s.kind != '
              '\'extern\' ORDER BY s.line, s.col, s.name, s.arc DESC')
STATIC_COLS = ('usr', 'name', 'kind', 'enclosing_name', 'file', 'line', 'col', 'type', 'canonical_type', 'type_class',
               'object_class', 'object_protocols', 'record_name', 'ownership_written', 'ownership', 'arc', 'import_facts', 'is_const',
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
        rows = con.execute('SELECT DISTINCT i.file, i.category, i.arc, t.main_file, t.target FROM objc_impl i JOIN tu '
                           't ON t.id = i.tu WHERE i.class_name = ? ORDER BY i.file, i.category', (cls,)).fetchall()
        self.targets = sorted(set(r[4] for r in rows))
        rows = [r[:4] for r in rows]
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
        verdict, why = refine_visibility(getattr(q, 'import_table', None), first, *type_verdict(views))
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
            'runtime': runtime_ownership(getattr(q, 'snapshot', None), cls, name, gov),
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
            verdict, why = refine_visibility(getattr(q, 'import_table', None), first, *type_verdict(views))
            refs = [ref_record(codedb, q, g, cls, own, False) for g in group_refs(as_dicts(
                q.con.execute(STATIC_REF_SQL, (first['usr'],)).fetchall(), REF_COLS))] if first['usr'] else []
            out.append({
                'kind': first['kind'], 'name': first['name'], 'usr': first['usr'], 'enclosing': first['enclosing_name'],
                'type': first['type'], 'canonical_type': first['canonical_type'], 'type_class': first['type_class'],
                'declared': {'file': first['file'], 'line': first['line'], 'col': first['col'],
                             'macro': first['macro_name']},
                'mode': ' and '.join(codedb.MODE_NAMES[m] for m in sorted(set(r['arc'] for r in rows), reverse=True)),
                'ownership': first['ownership'], 'ownership_written': first['ownership_written'],
                'const': bool(first['is_const']), 'pointee_const': first['pointee_const'],
                'initializer': first['init_kind'], 'thread_local': bool(first['thread_local']),
                'import_facts': first['import_facts'], 'importable': {'verdict': verdict, 'reason': why},
                'written': static_written(codedb, refs, first),
                'summary': summary(refs), 'references': refs,
                'marks': q.marks(set(r['tu'] for r in rows)), 'in_migration_scope': bool(first['in_migration_scope']),
            })
    return out


USED_SQL = ('SELECT DISTINCT r.var_usr, r.name, r.var_kind FROM static_ref r WHERE r.file IN (%s) AND r.var_usr IS '
            'NOT NULL ORDER BY r.name, r.var_usr')
USED_REF_SQL = ('SELECT DISTINCT r.file, r.line, r.col, r.enclosing_name, r.access, r.partial, r.in_once_block, '
                'r.in_constant_false_branch FROM static_ref r WHERE r.var_usr = ? AND r.file IN (%s) '
                'ORDER BY r.file, r.line, r.col')
USED_WRITE_SQL = ('SELECT DISTINCT r.file, r.line, r.col, r.enclosing_name, r.access, r.in_once_block, '
                  'r.in_constant_false_branch FROM static_ref r WHERE r.var_usr = ? AND r.access IN (%s)')


def used_elsewhere_rows(codedb, q, own, defined):
    """The statics and globals that the class's implementation files
    reference but do not define (a static in a header, a global of another
    file), one compact record each: the declaration the database has
    (a definition before an extern declaration), whether anything anywhere
    writes it after initialization, and the references from these files by
    function."""
    if not own.files:
        return []
    marks = ','.join('?' * len(own.files))
    out = []
    for usr, name, kind in q.con.execute(USED_SQL % marks, own.files).fetchall():
        if usr in defined:
            continue
        # A global that several targets define (gDebugLogging in the app and
        # in pidinfo) has one USR: the definition in a target that compiles
        # the class comes first.
        decl = q.con.execute("SELECT s.kind, s.file, s.line, s.type, s.type_class, s.import_facts, s.object_class, "
                             "s.object_protocols, s.record_name, s.is_const FROM c_static s JOIN tu t ON t.id = s.tu WHERE s.usr = "
                             "? ORDER BY s.kind = 'extern', t.target NOT IN (%s), s.file, s.line LIMIT 1" % ','.join(
                                 '?' * len(own.targets)), [usr] + own.targets).fetchone()
        refs = [{'file': f, 'line': ln, 'col': c, 'function': fn or '(file scope)', 'access': a, 'partial': bool(p),
                 'in_once_block': bool(o), 'in_constant_false_branch': bool(x)}
                for f, ln, c, fn, a, p, o, x in q.con.execute(USED_REF_SQL % marks, [usr] + own.files)]
        writes = [{'function': fn or '(file scope)', 'access': a, 'in_once_block': bool(o),
                   'in_constant_false_branch': bool(x)}
                  for _, _, _, fn, a, o, x in q.con.execute(USED_WRITE_SQL % ','.join('?' * len(codedb.STATE_WRITES)),
                                                            [usr] + list(codedb.STATE_WRITES))]
        row = dict(zip(('decl_kind', 'file', 'line', 'type', 'type_class', 'import_facts', 'object_class',
                        'object_protocols', 'record_name', 'is_const'), decl)) if decl else None
        once = [{'access': 'once-token', 'function': '', 'in_once_block': False, 'in_constant_false_branch': False}
                for r in refs if r['access'] == 'once-token'][:1]
        rec = {'kind': kind, 'name': name, 'usr': usr, 'references': refs, 'written_anywhere': static_written(
            codedb, writes + once, row)}
        if decl:
            verdict, why = refine_visibility(getattr(q, 'import_table', None), row,
                                             *importability(row['type_class'], row['import_facts']))
            rec.update({'type': row['type'], 'declared': {'kind': row['decl_kind'], 'file': row['file'],
                                                          'line': row['line']},
                        'importable': {'verdict': verdict, 'reason': why}})
        else:
            rec.update({'type': None, 'declared': None,
                        'importable': {'verdict': UNKNOWN, 'reason': 'no declaration of it in the database'}})
        out.append(rec)
    return out


# --- The runtime snapshot -----------------------------------------------------

def load_snapshot(path, wanted=None):
    """{class: {'language', 'arc_flag', 'conflicts', 'ivars': {name: (label,
    layout)}}} from a runtime snapshot in format 3 (runtime_snapshot.sh),
    read line by line, keeping only the classes in wanted (all when None).
    Raises ValueError."""
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import ivar_ownership_check as ioc
    out = {}
    cur = None
    with open(path, encoding='ascii') as f:
        if f.readline().rstrip('\n') != '# Objective-C runtime snapshot, format 3':
            raise ValueError('%s: not a runtime snapshot in format 3 (the format with ivar ownership)' % path)
        for n, line in enumerate(f, 2):
            line = line.rstrip('\n')
            if line.startswith('class '):
                name = ioc.unescape(line[len('class '):])
                cur = {'language': None, 'arc_flag': None, 'conflicts': [], 'ivars': {}}
                if wanted is None or name in wanted:
                    out[name] = cur
            elif line.startswith('end class '):
                cur = None
            elif line.startswith('  ') and cur is not None:
                fields = line[2:].split(' ')
                if fields[0] == 'language' and len(fields) == 2:
                    cur['language'] = fields[1]
                elif fields[0] == 'ivar-arc-flag' and len(fields) == 2:
                    cur['arc_flag'] = fields[1]
                elif fields[0] == 'OWNERSHIP-CONFLICT':
                    cur['conflicts'].append(' '.join(fields[1:]))
                elif fields[0] == 'ivar':
                    values = dict(x.split('=', 1) for x in fields[2:] if '=' in x)
                    if 'ownership' not in values or 'layout' not in values:
                        raise ValueError('%s:%d: an ivar line without ownership= and layout=' % (path, n))
                    cur['ivars'][ioc.unescape(fields[1])] = (values['ownership'], values['layout'])
    return out


def runtime_ownership(snapshot, cls, name, gov):
    """The runtime snapshot's ownership of one ivar against the compiler's
    (ivar_ownership_check.judge over the governing rows), or None without a
    snapshot."""
    if snapshot is None:
        return None
    snap = snapshot.get(cls)
    if snap is None:
        return {'verdict': 'not in the snapshot', 'text': 'the snapshot has no section for %s' % cls}
    if snap['language'] != 'objc':
        return {'verdict': 'not compared', 'text': 'the snapshot says the class is defined in %s' % snap['language']}
    if name not in snap['ivars']:
        return {'verdict': 'not in the snapshot', 'text': 'the snapshot lists no ivar %s (a conditional ivar, or a '
                                                          'snapshot older than the database)' % name}
    import ivar_ownership_check as ioc
    label, layout = snap['ivars'][name]
    facts = set((r['type'], r['type_class'], r['ownership'], r['arc'], r['record_has_objects'] or 0) for r in gov)
    verdict, text = ioc.judge(label, facts)
    return {'verdict': verdict, 'label': label, 'layout': layout, 'runtime_says': ioc.RUNTIME_SAYS.get(label, ''),
            'text': text}


def runtime_class_lines(snapshot, cls, own, ivar_names):
    """Class-level findings of the snapshot: the ARC flag against the
    compiler's mode, OWNERSHIP-CONFLICT lines, ivars only the runtime has.
    [(disagrees, text)]."""
    snap = snapshot.get(cls) if snapshot is not None else None
    if snap is None or snap['language'] != 'objc':
        return []
    out = []
    expected = {(1,): 'set', (0,): 'clear'}.get(tuple(sorted(own.class_modes)))
    if snap['arc_flag'] in ('set', 'clear') and expected and snap['arc_flag'] != expected:
        out.append((True, 'the runtime ARC flag is %s, but the compiler compiled the @implementation %s' % (
            snap['arc_flag'], 'with ARC' if expected == 'set' else 'without ARC')))
    for c in snap['conflicts']:
        out.append((True, 'the snapshot reports OWNERSHIP-CONFLICT %s' % c))
    for name in sorted(set(snap['ivars']) - set(ivar_names)):
        out.append((False, 'ivar %s is in the snapshot (%s) and not in the database' % (name, snap['ivars'][name][0])))
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
        rt = row.get('runtime')
        if rt is not None:
            if 'label' in rt:
                out.write('    runtime      %s%s [%s]: %s; %s\n' % (
                    rt['label'], ' layout=' + rt['layout'] if rt['layout'] else '', rt['runtime_says'],
                    {'agrees': 'agrees', 'DISAGREES': 'OWNERSHIP DISAGREES',
                     'compiler': 'the runtime cannot tell; the compiler\'s answer stands'}[rt['verdict']], rt['text']))
            else:
                out.write('    runtime      %s: %s\n' % (rt['verdict'], rt['text']))
    else:
        out.write('    written      %s\n' % row['written'])
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
    'the visibility of typedefs, enums and C records a type names (the database has no table of them; classes and '
    'protocols are checked against the import table when it is current)',
    'ivars and storage that categories add at run time (associated objects): the database has no table of them',
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


def write_used_elsewhere(out, used):
    out.write('\nstatics and globals its implementation files use but do not define: %d\n' % len(used))
    for u in used:
        d = u['declared']
        out.write('  %s %s  %s  %s\n' % (u['kind'], u['name'], u['type'] or '(type unknown)',
                                       '%s, %s:%d' % (d['kind'], d['file'], d['line']) if d else
                                       'no declaration in the database'))
        out.write('    importable   %s: %s\n' % (u['importable']['verdict'], u['importable']['reason']))
        out.write('    written      %s (anywhere in the database)\n' % u['written_anywhere'])
        by = collections.OrderedDict()
        for r in u['references']:
            by.setdefault((r['function'], r['file']), collections.OrderedDict()).setdefault(
                r['access'] + (' (part)' if r['partial'] else ''), []).append(r['line'])
        for (function, file), accesses in by.items():
            out.write('      %s  %s: %s\n' % (function, file, '; '.join(
                '%s %d (lines %s)' % (a, len(lines), ', '.join(str(n) for n in sorted(set(lines))))
                for a, lines in accesses.items())))


class Session:
    """The QueryContext and the per-run tables shared by every class of a
    run: one for a single class, one for --all."""

    def __init__(self, codedb, paths, runtime_methods=(), snapshot=None, classes=()):
        """classes: the classes of the run, the only ones kept from the
        snapshot (a snapshot of every class in the process holds tens of
        thousands)."""
        spec = codedb.QuerySpec('classstate', codedb.STATE_NOT_IN_DATABASE,
                                codedb.exit_text('ivars or statics printed', True, True), codedb.IVARS_SEARCH_FORMS,
                                True)
        try:
            lists = load_runtime_lists(runtime_methods)
        except ValueError as e:
            raise codedb.CodeDBError(str(e))
        self.q = codedb.QueryContext(paths, spec)
        try:
            self.excluded = collections.Counter()
            if classes:
                self.classes = list(classes)
            else:
                self.classes, self.excluded = all_classes(self.q.con)
            self.q.runtime_lists = lists
            try:
                self.q.snapshot = load_snapshot(snapshot, set(self.classes)) if snapshot else None
            except (ValueError, OSError, UnicodeDecodeError) as e:
                raise codedb.CodeDBError('cannot read the snapshot: %s' % e)
            self.q.import_table = ImportTable(codedb, self.q)
        except BaseException:
            self.q.close()
            raise

    def close(self):
        self.q.close()


def class_document(codedb, q, cls):
    """Everything classstate prints for one class, as a dict."""
    q.state_class = cls
    own = Own(q.con, cls)
    ivars = ivar_rows(codedb, q, cls, own)
    statics = static_rows(codedb, q, cls, own)
    defined = set(r['usr'] for r in statics if r.get('usr'))
    used = used_elsewhere_rows(codedb, q, own, defined)
    runtime = runtime_class_lines(getattr(q, 'snapshot', None), cls, own, [r['name'] for r in ivars])
    impls = [{'file': f, 'category': c, 'mode': codedb.MODE_NAMES[a]} for f, c, a in own.impls]
    return {'class': cls, 'implementations': impls, 'mode': mode_text(codedb, own),
            'where': codedb.class_chain(q.con, cls)[0][1], 'private_methods_consulted': bool(q.runtime_lists),
            'ivars': ivars, 'statics': statics, 'used_elsewhere': used,
            'runtime': [{'disagrees': d, 'text': t} for d, t in runtime],
            'ownership_disagreements': sum(1 for r in ivars if (r.get('runtime') or {}).get('verdict') == 'DISAGREES')
            + sum(1 for d, _ in runtime if d)}


def write_class(codedb, out, doc, snapshot_path, all_mode=False):
    cls, ivars, statics = doc['class'], doc['ivars'], doc['statics']
    rows = ivars + statics
    out.write('Class state of %s: %d ivars, %d statics in its implementation files\n' % (
        cls, len(ivars), len(statics)))
    if all_mode:
        out.write('not made: %s\n' % ALL_NOT_SEARCHED)
    if doc['implementations']:
        out.write('implemented in: %s\n' % ', '.join('%s (%s%s)' % (i['file'], 'category %s, ' % i['category']
                                                                     if i['category'] else '', i['mode'])
                                                     for i in doc['implementations']))
    else:
        out.write('implemented in: no @implementation of %s is in this database\n' % cls)
    where = doc['where']
    if where.startswith('SDK') or where == codedb.SWIFT_CLASS:
        out.write('the class itself is not in the repository (%s); only its categories are\n' % (
            where if where != codedb.SWIFT_CLASS else 'declared in Swift'))
    verdicts = collections.Counter(r['importable']['verdict'] for r in rows)
    out.write('importable: %s\n' % ', '.join('%s %d' % (v, verdicts[v]) for v in (YES, DEGRADED, NO, UNKNOWN)))
    if snapshot_path:
        out.write('ownership against the runtime snapshot %s: %d disagreement%s\n' % (
            snapshot_path, doc['ownership_disagreements'], '' if doc['ownership_disagreements'] == 1 else 's'))
        for r in doc['runtime']:
            out.write('  %s%s\n' % ('OWNERSHIP DISAGREES: ' if r['disagrees'] else '', r['text']))
    else:
        out.write('ownership against the runtime: not cross-checked (give --snapshot)\n')
    for row in rows:
        write_row(out, row)
    write_used_elsewhere(out, doc['used_elsewhere'])


def classstate(codedb, paths, cls, as_json=False, out=None, runtime_methods=(), snapshot=None):
    out = out or sys.stdout
    session = Session(codedb, paths, runtime_methods, snapshot, classes=[cls])
    q = session.q
    try:
        q.search_not_parsed(forms=codedb.search_forms_class(cls), skip_definitions=False)
        q.search_forms_text = codedb.IVARS_SEARCH_FORMS
        doc = class_document(codedb, q, cls)
        ivars, statics = doc['ivars'], doc['statics']
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
        if as_json:
            doc.update({'not_checked': NOT_CHECKED, 'skipped_code': skipped.getvalue().splitlines(),
                        'incomplete': q.incomplete_lines(), 'exit_status': status})
            del doc['where']
            json.dump(doc, out, indent=1, sort_keys=True)
            out.write('\n')
            return status
        write_class(codedb, out, doc, snapshot)
        out.write('\n')
        out.write('not checked by this query:\n')
        for item in NOT_CHECKED:
            out.write('  - %s\n' % item)
        out.write(codedb.STATE_LIMITS_LINE + '\n')
        out.write(skipped.getvalue())
        out.write(status_text.getvalue())
        return status
    finally:
        session.close()


ALL_SQL = ('SELECT DISTINCT class_name, file FROM objc_impl WHERE category IS NULL AND in_migration_scope = 1 '
           'ORDER BY class_name, file')


def all_classes(con):
    """(classes, excluded): the classes with an @implementation (not a
    category) in the migration's scope, less those whose every
    @implementation is in a file the inventory excludes (generated protobuf
    and Core Data code: README.md section 2); excluded counts those by the
    inventory's reason."""
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import inventory
    files = collections.OrderedDict()
    for cls, f in con.execute(ALL_SQL):
        files.setdefault(cls, []).append(f)
    kept, excluded = [], collections.Counter()
    for cls, fs in files.items():
        reasons = [inventory.exclusion_reason(f) for f in fs]
        if all(reasons):
            excluded[reasons[0]] += 1
        else:
            kept.append(cls)
    return kept, excluded
ALL_NOT_SEARCHED = ('the text searches that classstate CLASS makes for one class (files that are not parsed, and the '
                    'ranges every unit skips, for the class\'s and its ivars\' names) are not made by --all; run '
                    'classstate CLASS for a class whose answer must be complete')


def classstate_all(codedb, paths, as_json=False, out=None, runtime_methods=(), snapshot=None, progress=None):
    """The table for every class with an @implementation (not a category) in
    the migration's scope, one class at a time: each class's rows are built,
    written and dropped before the next, so memory does not grow with the
    number of classes. Text: each class as classstate CLASS writes it,
    separated by a line of '='; JSON: one document per line (JSON Lines)
    with a last line {"summary": ...}. Exit status as for classstate: 0, 3
    when the database is incomplete, 2 on error."""
    out = out or sys.stdout
    session = Session(codedb, paths, runtime_methods, snapshot)
    q = session.q
    try:
        classes = session.classes
        totals = collections.Counter()
        verdicts = collections.Counter()
        # A file with several classes lists its statics under each of them.
        distinct_statics = set()
        if not as_json:
            out.write('Class state of every class with an @implementation in the migration\'s scope: %d classes%s\n' % (
                len(classes), ' (left out, generated code the inventory excludes: %s)' % ', '.join(
                    '%s %d' % kv for kv in sorted(session.excluded.items())) if session.excluded else ''))
            out.write('not made: %s\n' % ALL_NOT_SEARCHED)
        for n, cls in enumerate(classes, 1):
            doc = class_document(codedb, q, cls)
            totals['classes'] += 1
            totals['ivars'] += len(doc['ivars'])
            totals['statics'] += len(doc['statics'])
            totals['used_elsewhere'] += len(doc['used_elsewhere'])
            for r in doc['statics']:
                distinct_statics.add(r.get('usr') or (r['declared']['file'], r['name'], r['declared']['line']))
            totals['ownership_disagreements'] += doc['ownership_disagreements']
            for r in doc['ivars'] + doc['statics']:
                verdicts[(r['kind'] == 'ivar' and 'ivar' or 'static', r['importable']['verdict'])] += 1
            if as_json:
                del doc['where']
                json.dump(doc, out, sort_keys=True)
                out.write('\n')
            else:
                out.write('\n' + '=' * 78 + '\n')
                write_class(codedb, out, doc, snapshot, all_mode=True)
            if progress and n % 100 == 0:
                progress('%d of %d classes' % (n, len(classes)))
        status_text = io.StringIO()
        q.write_status(status_text, totals['ivars'] + totals['statics'], 0, 0)
        status = 3 if q.incomplete() else 0
        summary_doc = {'classes': totals['classes'], 'ivars': totals['ivars'], 'statics': totals['statics'],
                       'distinct_statics': len(distinct_statics),
                       'excluded_generated': dict(session.excluded),
                       'used_elsewhere': totals['used_elsewhere'],
                       'ownership_disagreements': totals['ownership_disagreements'] if snapshot else None,
                       'importable': dict(('%s %s' % k, v) for k, v in sorted(verdicts.items())),
                       'not_made': ALL_NOT_SEARCHED, 'not_checked': NOT_CHECKED, 'incomplete': q.incomplete_lines(),
                       'exit_status': status}
        if as_json:
            json.dump({'summary': summary_doc}, out, sort_keys=True)
            out.write('\n')
            return status
        out.write('\n' + '=' * 78 + '\n')
        out.write('%d classes, %d ivars, %d statics defined in their files (%d distinct: a file with several classes '
                  'lists its statics under each), %d uses of statics defined elsewhere\n' % (
                      totals['classes'], totals['ivars'], totals['statics'], len(distinct_statics),
                      totals['used_elsewhere']))
        for kind in ('ivar', 'static'):
            out.write('importable (%ss): %s\n' % (kind, ', '.join('%s %d' % (v, verdicts[(kind, v)])
                                                                for v in (YES, DEGRADED, NO, UNKNOWN))))
        if snapshot:
            out.write('ownership disagreements with the runtime snapshot: %d\n' % totals['ownership_disagreements'])
        out.write('not checked:\n')
        for item in NOT_CHECKED:
            out.write('  - %s\n' % item)
        out.write(codedb.STATE_LIMITS_LINE + '\n')
        out.write(status_text.getvalue())
        return status
    finally:
        session.close()
