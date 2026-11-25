#!/usr/bin/env python3
"""The path a unit takes (trivial, light or full) and the qualifying checks
behind it, for one Objective-C class or category, or for every unit under
sources/.

Part of the Objective-C to Swift migration (docs/swift-migration/
lifecycle.md section 3, "Which path"). Each condition of that
section is printed PASS, FAIL or MANUAL with its evidence and the query or
search that produced it. Facts the compiler sees come from the code database
(tools/swift_migration/codedb/, phase0.md section 10), read through the
entry-point census (entry_points.py), which also supplies the parsed xibs,
storyboards, sdef, property lists, Core Data models and reflective-site
registry. Text search is used only for what the database does not record (C
function calls such as dispatch_async or objc_setAssociatedObject, and
@synchronized on self), only in the unit's own files, and is labelled as
such. Where a condition cannot be decided from these, it is MANUAL, never
PASS.

Usage:

  qualify_unit.py [options] CLASS [--callers-thread TEXT]
  qualify_unit.py [options] 'CLASS(CATEGORY)'
  qualify_unit.py [options] --list
  qualify_unit.py [options] --classify

CLASS is the class whose non-category @implementation the database records.
The unit is that implementation file, the header beside it, and the files of
the class's categories named CLASS+Something. CLASS(CATEGORY) is a category
unit: the files holding @implementation CLASS (CATEGORY) and the headers
beside them; it takes the trivial or the full path (the light conditions are
written for a class and are not evaluated for it). --callers-thread records a
person's answer to the one condition no tool decides (5c, every caller on one
known thread), for example --callers-thread "main thread: called only from
-[Foo menuAction:]"; the answer is printed as the evidence and the condition
is then RECORDED.

--list checks every class with a non-category @implementation under sources/
(generated files left out) in one process and prints those with no FAIL,
sorted by implementation size, with the conditions that are MANUAL for each
(5c is MANUAL for all of them unless recorded, and is not listed).

Options: --json; --root (the repository, default: this tool's); --db, --cdb,
--fragments, --swift-work, --extractor, --swift-reader (as codedb.py takes
them); --registry (default docs/swift-migration/reflective-sites.md);
--hot-paths (default docs/swift-migration/hot-paths.md).

The conditions (ids in brackets):
  [1]  the implementation is 500 lines or fewer (lines of its .m/.mm files);
  [2]  three or fewer files outside the unit use it: files with a send to a
       method of the class or with the class as receiver, a Swift reference
       to it, an access to one of its instance variables, a subclass, or a
       category of it, from the database, and files that name it as a whole
       word outside comments, strings, imports and @class (text search); the
       bridging header and the unit's own tests (test files whose name
       contains the class name) do not count; files the database does not
       parse (no unit, a stale unit, code not compiled in this
       configuration) that name the class make it MANUAL;
  [3a] not named in a xib or storyboard (custom class, outlet owner, action
       target, binding, delegate); a First Responder action with one of its
       selectors is MANUAL;
  [3b] not named in the sdef, a property list or a Core Data model;
  [3c] not archived: adopts neither NSCoding nor NSSecureCoding and defines
       neither initWithCoder: nor encodeWithCoder:; its name as a whole
       string literal outside the unit is MANUAL;
  [3d] not in the reflective-site registry (names table, an entry's names,
       an entry's site in the unit), not looked up by name (the database's
       reflective calls), and no reflective site in the unit (the database's
       dynamic reflective calls, and NSStringFromClass, NSStringFromSelector,
       NSStringFromProtocol, sel_getName, class_getName and
       object_getClassName in the unit's files, which the registry also
       registers);
  [3e] not reached by key-value coding or observing: a key or key path
       naming one of its properties sent to the class (MANUAL when the
       receiver's class is not known), manual change notifications or
       keyPathsForValuesAffecting methods in the class, Swift key paths;
  [3f] the entry-point census finds nothing but ordinary sends: no method of
       the class has selector references, calls by name, key-value coding,
       registry names, Interface Builder, scripting or resource text; a hit
       on a selector another class of the repository also has is MANUAL;
  [4a] no C++; [4b] no +load or +initialize; [4c] no -dealloc that does more
       than release; [4d] no atomic property; [4e] no associated object;
  [4f] no swizzling (method_exchangeImplementations and the like, in the
       unit or naming the class; condition 3d leaves these calls to it);
  [4g] no instance variable of it accessed from outside the unit (ivar_ref
       rows, object_getIvar and the like): Swift cannot express a public
       ivar;
  [5a] no lock; [5b] no dispatch queue and no thread API (a timer, a
       delayed perform or dispatch_after is MANUAL: "schedules work");
  [5c] every caller on one known thread: MANUAL, or RECORDED with
       --callers-thread (never PASS; RECORDED does not change the exit
       status);
  [6]  not on the hot-path list (performance.md section 2's directories, as
       inventory.py's HOT_PATH_DIRS, and hot-paths.md): FAIL; MANUAL when a
       file under those directories or named PTYTextView* uses the class;
  [7]  stores nothing in user defaults, a profile, an arrangement or a file:
       FAIL on direct uses in the unit (sends to the storage classes or of
       the storage selectors, the profile-key macros, which are the string
       macros of any header defining at least 20 of them, arrangement and
       preference key constants, C file functions); MANUAL on a send to a
       repository method that itself stores directly (one level).

The trivial path's conditions (lifecycle.md section 3), each PASS, FAIL or
MANUAL; the unit is trivial only when every one is PASS (a MANUAL is never
settled by reading here):
  [T1] the method and function bodies of the implementation files total at
       most 50 lines, opening brace to closing brace, from Clang's AST
       (unit_ast.py); MANUAL when the file cannot be parsed;
  [T2] no state: no instance variable, no property with storage (a
       synthesize row), no static or global variable that is not const
       (objc_ivar, objc_property, c_static);
  [T3] no lock, queue, thread API or timer: 5a and 5b both PASS, and no
       such C function (dispatch_*, pthread_*, os_unfair_lock*, atomics)
       among the calls in Clang's AST, which sees through macros;
  [T4] compiled with ARC (objc_impl), or nothing in it that ARC changes or
       rejects (unit_ast.py's ownership list), so the port itself is the
       move to ARC and no arc commit comes first; and, with or without
       ARC, no Core Foundation ownership a Swift port cannot promise to
       Objective-C callers (unit_ast.py's retained list: a CF or CG ...Ref
       returned retained by name or attribute, a Retain, Release or Create
       Rule call, a __bridge_transfer or __bridge_retained cast);
  [T5] no C++: 4a PASS;
  [T6] no C pointer or C array (unit_ast.py's unsafe list). A borrowed CF
       or CG ...Ref that only passes through (a CGContextRef parameter
       handed to drawing calls) is not a C pointer and passes;
  [T7] no +load or +initialize, associated object, swizzling (4b, 4e, 4f
       PASS, and none of their C functions among the calls in Clang's AST)
       and no -dealloc at all;
  [T8] nothing that forces the full path whatever the size: not a hot path
       (6), stores nothing (7), not archived (3c), all PASS; no Objective-C
       subclass outside the unit (interop.md); nothing in the unit's files
       adopts NSCoding or defines initWithCoder:/encodeWithCoder:; no Core
       Data (a class of the unit, or a category's class, is an entity's
       class, or the unit sends to a Core Data class).
Names in the sdef, a xib, a selector string or the registry do not stop a
trivial unit; its port carries the runtime snapshot comparison and a test
through each such door instead.

The path printed: trivial when T1 to T8 PASS; otherwise, for a class, light
when no light condition FAILs (each MANUAL still settled by reading) and full
when one does; for a category, full.

--classify does the same for every class unit --list considers (one per
implementation file, naming every class it implements) and every category
unit under sources/, and prints how many take each path and the trivial
units by body lines. A category in a file named for its class (Foo+Bar.m)
is part of the class's unit and is also classified alone, marked part_of
and counted apart (split_counts), since it can move alone. It runs clang
once on each implementation file that reaches T1 (about 1 to 5 seconds each).

Exit status: 0 when no light condition FAILs (MANUAL ones still need a
person), 1 when any FAILs, 2 on error; for a category unit 0 when it is
trivial and 1 otherwise. --list and --classify exit 0.
"""

import argparse
import collections
import json
import os
import re
import sqlite3
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import entry_points as ep  # noqa: E402  (puts codedb on the path)
import inventory  # noqa: E402
import unit_ast  # noqa: E402

codedb = ep.codedb

MAX_TRIVIAL_BODY_LINES = 50
TRIVIAL_CONDITIONS = collections.OrderedDict([
    ('T1', 'The method and function bodies total at most %d lines (Clang\'s AST).' % MAX_TRIVIAL_BODY_LINES),
    ('T2', 'No instance variable, property with storage, or static or global variable that is not const.'),
    ('T3', 'No lock, dispatch queue, thread API or timer (5a and 5b).'),
    ('T4', 'Compiled with ARC, or nothing in it that ARC changes or rejects.'),
    ('T5', 'No C++ (4a).'),
    ('T6', 'No C pointer or C array.'),
    ('T7', 'No +load, +initialize, associated object, swizzling or -dealloc.'),
    ('T8', 'Nothing that forces the full path: hot path (6), stored state (7, 3c, NSCoding, Core Data), an '
           'Objective-C subclass.'),
])
# The order the trivial checks run in, cheapest first; the clang run last.
TRIVIAL_ORDER = ('T2', 'T5', 'T7', 'T3', 'T8', 'T1', 'T4', 'T6')
# Core Data classes: a send to one is stored state (T8).
CORE_DATA_CLASSES = ('NSManagedObjectContext', 'NSEntityDescription', 'NSPersistentContainer', 'NSFetchRequest',
                     'NSPersistentStoreCoordinator', 'NSManagedObjectModel', 'NSPersistentStore')
# The C functions T3 and T7 look for in Clang's AST, as the light
# conditions' text searches do in the unit's own text.
AST_THREAD_FUNCTIONS = re.compile(r'^(?:dispatch_(?!after)\w+|pthread_\w+|os_unfair_lock\w*|OSAtomic\w*|'
                                  r'OSSpinLock\w*|atomic_\w+|objc_sync_\w+)$')
AST_TIMER_FUNCTIONS = re.compile(r'^dispatch_after\w*$')
AST_STATE_FUNCTIONS = re.compile(r'^(?:%s)$' % '|'.join(re.escape(x) for x in ('objc_setAssociatedObject',
                                 'objc_getAssociatedObject', 'objc_removeAssociatedObjects', 'method_exchangeImplementations',
                                 'method_setImplementation', 'class_replaceMethod', 'class_addMethod',
                                 'imp_implementationWithBlock', 'object_setClass', 'objc_allocateClassPair',
                                 'object_getIvar', 'object_setIvar', 'class_getInstanceVariable', 'ivar_getOffset',
                                 'object_getInstanceVariable', 'object_setInstanceVariable')))
_CATEGORY_UNIT = re.compile(r'^([A-Za-z_]\w*)\(([A-Za-z_]\w*)\)$')
MAX_LINES = 500
MAX_USERS = 3
HOT_PATHS = os.path.join('docs', 'swift-migration', 'hot-paths.md')
CONDITIONS = collections.OrderedDict([
    ('1', 'The unit\'s implementation is %d lines or fewer.' % MAX_LINES),
    ('2', 'Three or fewer files outside the unit use it (code database). The bridging header and the unit\'s own '
          'tests do not count.'),
    ('3a', 'No class in it is named in a xib or a storyboard.'),
    ('3b', 'No class in it is named in the sdef, a property list or a Core Data model.'),
    ('3c', 'No class in it is named in an archive.'),
    ('3d', 'No class in it is named in the reflective-site registry, and it has no reflective site.'),
    ('3e', 'No class in it is named in a key-value coding or observing site.'),
    ('3f', 'The entry-point census finds nothing but ordinary sends.'),
    ('4a', 'It has no C++.'),
    ('4b', 'It has no +load or +initialize.'),
    ('4c', 'It has no -dealloc that does more than release.'),
    ('4d', 'It has no atomic property.'),
    ('4e', 'It has no associated object.'),
    ('4f', 'It has no swizzling.'),
    ('4g', 'No instance variable of it is accessed from outside the unit (Swift cannot express a public ivar).'),
    ('5a', 'It takes no lock.'),
    ('5b', 'It uses no dispatch queue and no thread API.'),
    ('5c', 'Every caller is on one known thread.'),
    ('6', 'It is not on the hot-path list (performance.md section 2).'),
    ('7', 'It stores nothing in user defaults, a profile, an arrangement or a file.'),
])
CONDITION_IDS = tuple(CONDITIONS)
# The order --list evaluates them in, cheapest first, stopping at a FAIL.
LIST_ORDER = ('1', '6', '2', '4a', '4b', '4d', '4c', '4e', '4f', '4g', '5a', '5b', '7', '3a', '3b', '3c', '3d', '3e',
              '3f',
              '5c')

CONVERSIONS = ('NSStringFromClass', 'NSStringFromSelector', 'NSStringFromProtocol', 'sel_getName', 'class_getName',
               'object_getClassName')
SWIZZLE_FUNCTIONS = ('method_exchangeImplementations', 'method_setImplementation', 'class_replaceMethod',
                     'class_addMethod', 'imp_implementationWithBlock', 'object_setClass', 'objc_allocateClassPair')
ASSOCIATED_FUNCTIONS = ('objc_setAssociatedObject', 'objc_getAssociatedObject', 'objc_removeAssociatedObjects')
ASSOCIATED_SELECTORS = ('it_setAssociatedObject:forKey:', 'it_associatedObjectForKey:')
LOCK_CLASSES = ('NSLock', 'NSRecursiveLock', 'NSCondition', 'NSConditionLock', 'NSDistributedLock')
LOCK_TEXT = re.compile(r'@synchronized|\bos_unfair_lock\w*|\bpthread_(?:mutex|rwlock|cond)\w*|\bOSSpinLock\w*|'
                       r'\bdispatch_semaphore\w*|\bstd::(?:mutex|recursive_mutex|lock_guard|unique_lock)\b|'
                       r'\bOSAtomic\w*|\batomic_\w+|\b_Atomic\b|\bstd::atomic\b')
THREAD_CLASSES = ('NSThread', 'NSOperationQueue', 'NSOperation', 'NSBlockOperation', 'iTermThread')
THREAD_SELECTOR = re.compile(r'^performSelector(?:OnMainThread|InBackground|:onThread)|^detachNewThread')
THREAD_TEXT = re.compile(r'\bdispatch_(?!after\b)\w+|\bDispatchQueue\b|\bNSOperationQueue\b|\bNSThread\b|'
                         r'\bpthread_create\b|'
                         r'\biTermGCD\b|\biTermThread\b')
TIMER_CLASSES = ('NSTimer', 'CADisplayLink')
TIMER_SELECTOR = re.compile(r'^performSelector:withObject:afterDelay:|^performSelector:afterDelay:')
TIMER_TEXT = re.compile(r'\bdispatch_after\b|\bCADisplayLink\b|\bNSTimer\b')
IVAR_FUNCTIONS = ('object_getIvar', 'object_setIvar', 'class_getInstanceVariable', 'ivar_getOffset',
                  'object_getInstanceVariable', 'object_setInstanceVariable')
# Per-frame and per-token code (performance.md section 2): the hot
# directories, and PTYTextView, whose per-frame parts the section names.
HOT_SENDER_PREFIXES = ('PTYTextView',)
# Test code: a mention there is not an app caller (the census counts test
# callers apart), so it does not make 3e or 3f MANUAL.
TEST_LIKE_DIRS = ep.TEST_DIRS + ('AILiveHarness/',)
STALE_EVIDENCE_MAX = 10
# Profile and arrangement keys. Key macros are derived from the database:
# the string-literal macros of every header that defines at least
# KEY_HEADER_MIN of them (today ITAddressBookMgr.h: KEY_, COLORS_,
# KEYTEMPLATE_). Arrangement and preference keys are constants, matched by
# name.
KEY_HEADER_MIN = 20
STORED_CONSTANT = re.compile(r'ARRANGEMENT|^kPreferenceKey')
_STRING_MACRO_BODY = re.compile(r'^\s*@"(?:\\.|[^"\\])*"\s*$')
_ENCLOSING = re.compile(r'^([-+])\[([A-Za-z_]\w*)(?:\([^)]*\))? ([^\]]+)\]$')
_USR_METHOD = re.compile(r'\(cs\)([A-Za-z_]\w*)\((im|cm)\)(\S+)$')
_IMPORT_LINE = re.compile(r'^[ \t]*(?:#[ \t]*(?:import|include)\b|@class\b|@import\b|import\b)[^\n]*', re.M)
CXX_TEXT = re.compile(r'\bstd::|\bnamespace\s+\w|\btemplate\s*<|#\s*include\s*<(?:vector|map|set|string|memory|'
                      r'unordered_map|unordered_set|algorithm|functional|atomic|mutex)>')
STORAGE_CLASSES = ('NSUserDefaults', 'iTermUserDefaults', 'iTermPreferences', 'iTermProfilePreferences',
                   'NSKeyedArchiver', 'NSKeyedUnarchiver', 'NSFileManager', 'NSFileHandle', 'NSOutputStream',
                   'ProfileModel', 'iTermProfileModel')
STORAGE_SELECTORS = ('writeToFile:atomically:', 'writeToFile:atomically:encoding:error:', 'writeToURL:atomically:',
                     'writeToURL:atomically:encoding:error:', 'writeToFile:options:error:', 'writeToURL:options:error:',
                     'writeToURL:error:', 'encodeObject:forKey:', 'archivedDataWithRootObject:',
                     'archivedDataWithRootObject:requiringSecureCoding:error:')
STORAGE_TEXT = re.compile(r'\b(?:fopen|fwrite|mkstemp|creat)\s*\(')
KVO_SELECTORS = ('willChangeValueForKey:', 'didChangeValueForKey:', 'willChange:valuesAtIndexes:forKey:',
                 'didChange:valuesAtIndexes:forKey:', 'willChangeValueForKey:withSetMutation:usingObjects:',
                 'didChangeValueForKey:withSetMutation:usingObjects:')
KVO_CLASS_METHOD = re.compile(r'^(?:keyPathsForValuesAffecting\w+|automaticallyNotifiesObserversForKey:|'
                              r'automaticallyNotifiesObserversOf\w+)$')
DEALLOC_ALLOWED_SENDS = ('release', 'autorelease', 'dealloc')
DEALLOC_ALLOWED_CALLS = re.compile(r'^(?:DLog|RLog|NSLog|\w+Release)$')
C_KEYWORDS = frozenset(('if', 'for', 'while', 'switch', 'return', 'sizeof', 'do', 'else', '__typeof__', 'typeof',
                        '@synchronized', 'super', 'self'))
CENSUS_COLUMNS = ('selector_refs', 'by_name', 'kvc', 'registry', 'ib', 'scripting', 'text')
_COMMENTS_AND_STRINGS = re.compile(r'/\*.*?\*/|//[^\n]*|@?"(?:\\.|[^"\\\n])*"', re.S)
_RECEIVER = re.compile(r'^(?:const\s+|__kindof\s+)*([A-Za-z_]\w*)')
_USR_CLASS = re.compile(r'\(cs\)([A-Za-z_]\w*)')
_STRING_LITERAL = re.compile(r'"([A-Za-z_]\w*)"')
_IDENTIFIER = re.compile(r'[A-Za-z_]\w*')
NOT_CLASSES = frozenset(('id', 'Class', 'instancetype', 'SEL', 'void'))


class QualifyError(Exception):
    pass


Condition = collections.namedtuple('Condition', 'id status evidence how')


def receiver_class(rtype):
    """The class a receiver type names ('Foo *', 'Foo * _Nonnull', 'Foo' for
    a class receiver), or None for id, Class and unknown types."""
    if not rtype:
        return None
    m = _RECEIVER.match(rtype)
    if not m or m.group(1) in NOT_CLASSES:
        return None
    return m.group(1)


def strip_comments(text):
    """text with comments and string literals blanked (line numbers kept)."""
    return _COMMENTS_AND_STRINGS.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


def worst(statuses):
    return 'FAIL' if 'FAIL' in statuses else 'MANUAL' if 'MANUAL' in statuses else 'PASS'


class Facts:
    """What every class's checks read, gathered once: the census (code
    database, resources, registry), indexes of class users, implementations
    and selectors, and the files the database does not parse."""

    def __init__(self, census, hot_paths_path=None, clang=None):
        self.census = census
        self.con = census.con
        self.root = census.root
        self.clang = clang
        self._ast = {}
        self._objc_classes = None
        con = self.con
        self.impls = collections.defaultdict(set)  # class: {(file, line)} of non-category @implementations
        self.categories = collections.defaultdict(set)  # class: {(category, file)}
        for cls, cat, f, line in con.execute('SELECT DISTINCT class_name, category, file, line FROM objc_impl'):
            if os.path.isabs(f):
                continue
            if cat:
                self.categories[cls].add((cat, f))
            else:
                self.impls[cls].add((f, line))
        self.selector_classes = collections.defaultdict(set)  # selector: classes that declare or define it
        for sel, cls in con.execute("SELECT DISTINCT selector, class_name FROM objc_method WHERE class_name IS NOT "
                                    "NULL AND container_kind != 'protocol'"):
            self.selector_classes[sel].add(cls)
        if census.swift_tables:
            for sel, cls in con.execute('SELECT DISTINCT selector, class_name FROM swift_objc_decl WHERE selector IS '
                                        'NOT NULL AND class_name IS NOT NULL'):
                self.selector_classes[sel].add(cls)
        self.users = self._users()
        self.file_classes = collections.defaultdict(set)  # file: classes it implements (or has categories of)
        for cls, fl in self.impls.items():
            for f, _ in fl:
                self.file_classes[f].add(cls)
        for cls, cats in self.categories.items():
            for _, f in cats:
                self.file_classes[f].add(cls)
        self.key_macros, self.key_families = self._key_macros()
        self._writer_methods = None
        self._type_index = None
        # The files whose facts the database may lack: units that are not
        # current (their main files) and Swift modules that are not current.
        self.unit_state = collections.defaultdict(list)  # file: [state] of units whose main file it is
        for s in census.q.states.values():
            self.unit_state[s.file].append('%s%s' % (s.state, ' (parse errors)' if s.errors else ''))
        tests = census.test_targets
        self.test_files = set(s.file for s in census.q.states.values() if s.target in tests)
        if census.q.swift_states is not None:
            for m in census.q.swift.modules:
                if m.target in tests:
                    self.test_files.update(ep.swiftdb.stored_path(f, self.root) for f in m.files)
        stale = set(s.file for s in census.q.not_current())
        if census.q.swift_states is not None:
            current = codedb.CURRENT
            for m in census.q.swift.modules:
                st = census.q.swift_states.get(m.name) if hasattr(m, 'name') else None
                if st is not None and st.state != current:
                    stale.update(ep.swiftdb.stored_path(f, self.root) for f in m.files)
        self.stale_files = sorted(f for f in stale if f and not os.path.isabs(f))
        self._stale_index = None
        self._lines = {}
        self._texts = {}
        self._literals = None
        self.hot_listed = self._hot_paths(hot_paths_path or os.path.join(self.root, HOT_PATHS))

    # --- Indexes built once.

    def _users(self):
        """{class: {file: first evidence}}: files with a send to a method of
        the class or with the class as receiver, a Swift reference to a
        member of it, a subclass declaration, or a category of it."""
        users = collections.defaultdict(dict)

        def add(cls, f, what):
            if cls and f and not os.path.isabs(f):
                users[cls].setdefault(f, what)
        for f, line, sel, usr, rtype in self.con.execute(
                'SELECT file, line, selector, target_usr, receiver_type FROM send ORDER BY file, line'):
            m = _USR_CLASS.search(usr or '')
            if m:
                add(m.group(1), f, '%s:%d sends %s' % (f, line, sel))
            rc = receiver_class(rtype)
            if rc:
                add(rc, f, '%s:%d sends %s to %s' % (f, line, sel, rtype))
        if self.census.swift_tables:
            for f, line, kind, cls, usr, sel, prop in self.con.execute(
                    'SELECT file, line, kind, class_name, usr, selector, property FROM swift_ref ORDER BY file, line'):
                m = _USR_CLASS.search(usr or '')
                for c in set(x for x in (cls, m.group(1) if m else None) if x):
                    add(c, f, '%s:%d Swift %s %s' % (f, line, kind, sel or prop or ''))
            for f, line, cls, usr in self.con.execute(
                    'SELECT file, line, class_name, overrides_usr FROM swift_objc_decl WHERE is_override = 1 AND '
                    'overrides_usr IS NOT NULL'):
                m = _USR_CLASS.search(usr or '')
                if m and m.group(1) != cls:
                    add(m.group(1), f, '%s:%d Swift subclass %s overrides a member' % (f, line, cls))
        for f, line, cls, name in self.con.execute(
                'SELECT file, min(line), ivar_class, ivar_name FROM ivar_ref GROUP BY file, ivar_class, ivar_name'):
            add(cls, f, '%s:%d accesses the instance variable %s' % (f, line, name))
        for name, sup, f, line in self.con.execute('SELECT DISTINCT name, superclass, file, line FROM objc_class WHERE '
                                                   'superclass IS NOT NULL'):
            add(sup, f, '%s:%d declares the subclass %s' % (f, line, name))
        for cls, container, f, line in self.con.execute(
                "SELECT DISTINCT class_name, container_name, file, min(line) FROM objc_method WHERE container_kind IN "
                "('category', 'category-implementation') AND class_name IS NOT NULL GROUP BY 1, 2, 3"):
            add(cls, f, '%s:%d category %s' % (f, line, container))
        return users

    def _key_macros(self):
        """({macro name: header}, [family prefix]): the string-literal
        macros of every header that defines at least KEY_HEADER_MIN of
        them, and the prefixes (up to the first _) they use."""
        by_header = collections.defaultdict(set)
        for name, f, body in self.con.execute("SELECT DISTINCT name, file, body FROM macro_def WHERE file LIKE "
                                              "'%.h'"):
            if f and not os.path.isabs(f) and _STRING_MACRO_BODY.match(body or ''):
                by_header[f].add(name)
        keys = {}
        for f, names in by_header.items():
            if len(names) >= KEY_HEADER_MIN:
                for n in names:
                    keys[n] = f
        families = sorted(set(n.split('_')[0] + '_' for n in keys if '_' in n))
        return keys, families

    def writer_methods(self):
        """{(class, '-' or '+', selector): first evidence}: the repository
        methods that store directly (condition 7's direct uses: a send to a
        storage class or of a storage selector, a key macro, an arrangement
        or preference key constant), one level, from the database."""
        if self._writer_methods is None:
            out = {}

            def add(enclosing, what):
                m = _ENCLOSING.match(enclosing or '')
                if m:
                    out.setdefault((m.group(2), m.group(1), m.group(3)), what)
            for f, line, sel, rtype, enc in self.con.execute(
                    'SELECT file, line, selector, receiver_type, enclosing_name FROM send WHERE enclosing_name LIKE '
                    "'_[%'"):
                if receiver_class(rtype) in STORAGE_CLASSES or sel in STORAGE_SELECTORS:
                    add(enc, '%s:%d sends %s to %s' % (f, line, sel, rtype or 'an object'))
            marks = ','.join('?' * len(self.key_macros))
            for part in ep.chunks(sorted(self.key_macros)):
                marks = ','.join('?' * len(part))
                for f, line, name, enc in self.con.execute(
                        'SELECT file, line, name, enclosing_name FROM macro_expansion WHERE name IN (%s)' % marks,
                        part):
                    add(enc, '%s:%d uses the key %s' % (f, line, name))
            for f, line, name, enc in self.con.execute('SELECT file, line, name, enclosing_name FROM static_ref'):
                if STORED_CONSTANT.search(name):
                    add(enc, '%s:%d uses the key %s' % (f, line, name))
            self._writer_methods = out
        return self._writer_methods

    def type_index(self, names):
        """{class name: [(file, line)]}: the first line of each C-family or
        Swift file of the repository that names the class as a whole word
        outside comments, string literals, imports and @class lines (text
        search, one pass for all names; prime with every name first)."""
        names = set(names)
        if self._type_index is None or not names <= self._type_index[0]:
            found = collections.defaultdict(list)
            for f in self.census.source_files:
                text = self.text(f, keep=False)
                if not text:
                    continue
                text = _IMPORT_LINE.sub('', strip_comments(text))
                seen = set()
                for m in _IDENTIFIER.finditer(text):
                    tok = m.group(0)
                    if tok in names and tok not in seen:
                        seen.add(tok)
                        found[tok].append((f, text.count('\n', 0, m.start()) + 1))
            self._type_index = (frozenset(names), found)
        return dict((n, self._type_index[1].get(n, [])) for n in names)

    def stale_index(self):
        """{identifier: [file]} of the stale files (read once)."""
        if self._stale_index is None:
            index = collections.defaultdict(list)
            for f in self.stale_files:
                for tok in set(_IDENTIFIER.findall(self.text(f))):
                    index[tok].append(f)
            self._stale_index = index
        return self._stale_index

    def string_literals(self, names):
        """{name: [(file, line)]}: lines of the repository's C-family and
        Swift files holding one of names as a whole string literal; one pass
        over the files for all names (prime with every name first)."""
        names = set(names)
        if self._literals is None or not names <= self._literals[0]:
            found = collections.defaultdict(list)
            for f in self.census.source_files:
                text = self.text(f, keep=False)
                if '"' not in text:
                    continue
                for n, line in enumerate(text.split('\n'), 1):
                    for m in _STRING_LITERAL.finditer(line):
                        if m.group(1) in names:
                            found[m.group(1)].append((f, n))
            self._literals = (frozenset(names), found)
        return dict((n, self._literals[1].get(n, [])) for n in names)

    def _hot_paths(self, path):
        """Cells of the first column of hot-paths.md's table."""
        out = []
        try:
            with open(path, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.startswith('|') and not line.startswith('|---'):
                        cell = line.strip('|\n').split('|')[0].strip().strip('`')
                        if cell and cell != 'Unit':
                            out.append(cell)
        except OSError as e:
            raise QualifyError('the hot-path list %s cannot be read (%s)' % (path, e.strerror or e))
        return out

    # --- Files.

    def text(self, f, keep=True):
        if f in self._texts:
            return self._texts[f]
        try:
            with open(os.path.join(self.root, f), 'r', encoding='utf-8', errors='replace') as fh:
                text = fh.read()
        except OSError:
            text = ''
        if keep:
            self._texts[f] = text
        return text

    def lines(self, f):
        if f not in self._lines:
            self._lines[f] = self.text(f, keep=False).count('\n')
        return self._lines[f]

    def objc_classes(self):
        """Every Objective-C class name the database knows: the repository's
        (objc_class), the SDK's (sdk_class) and Swift's @objc classes; a
        pointer to one of them is not a C pointer (unit_ast.py)."""
        if self._objc_classes is None:
            tables = codedb.table_names(self.con)
            names = set(n for (n,) in self.con.execute('SELECT DISTINCT name FROM objc_class'))
            if 'sdk_class' in tables:
                names.update(n for (n,) in self.con.execute('SELECT DISTINCT name FROM sdk_class'))
            if self.census.swift_tables:
                names.update(n for (n,) in self.con.execute('SELECT DISTINCT class_name FROM swift_objc_decl WHERE '
                                                            'class_name IS NOT NULL'))
            names.update(self.impls)
            self._objc_classes = names
        return self._objc_classes

    def ast(self, f, arc):
        """unit_ast.py's facts of the implementation file f (relative), or an
        ASTError; computed once."""
        if f not in self._ast:
            try:
                args, main_abs = unit_ast.compile_command(self.root, f, self.census.paths.cdb)
                self._ast[f] = unit_ast.file_facts(self.clang or unit_ast.default_clang(), args, main_abs,
                                                   self.objc_classes(), arc, cwd=self.root)
            except unit_ast.ASTError as e:
                self._ast[f] = e
        return self._ast[f]

    def unit(self, cls, category=None):
        """(implementation files, unit files): the non-category
        implementation file, the header beside each implementation file, and
        the files of categories named CLASS+Something; for a category unit,
        the files of @implementation CLASS (CATEGORY) and their headers."""
        if category:
            impl = sorted(set(f for cat, f in self.categories.get(cls, ()) if cat == category))
            if not impl:
                raise QualifyError('the code database records no @implementation %s (%s)' % (cls, category))
            impl_files = set(impl)
        else:
            impl = sorted(set(f for f, _ in self.impls.get(cls, ())))
            if not impl:
                raise QualifyError('the code database records no Objective-C @implementation of %s (is it a Swift '
                                   'class, misspelled, or in a file no unit compiles?)' % cls)
            impl_files = set(impl)
            for cat, f in self.categories.get(cls, ()):
                if os.path.basename(f).startswith(cls + '+'):
                    impl_files.add(f)
        unit = set(impl_files)
        for f in impl_files:
            h = os.path.splitext(f)[0] + '.h'
            if os.path.exists(os.path.join(self.root, h)):
                unit.add(h)
        return sorted(impl_files), sorted(unit)


class Checker:
    """The conditions for one class."""

    def __init__(self, facts, cls, callers_thread=None):
        self.f = facts
        self.c = facts.census
        self.con = facts.con
        m = _CATEGORY_UNIT.match(cls)
        self.name = cls
        self.cls, self.category = (m.group(1), m.group(2)) if m else (cls, None)
        self.container = '%s(%s)' % (self.cls, self.category) if self.category else None
        self.callers_thread = callers_thread
        self.impl, self.unit = facts.unit(self.cls, self.category)
        self.unit_set = set(self.unit)
        self.impl_lines = sum(facts.lines(f) for f in self.impl if f.endswith(('.m', '.mm')))
        # Units of the implementation files that are not current: rows from
        # them may be missing or wrong, so a database PASS is MANUAL.
        self.stale = ['%s: %s' % (f, ', '.join(s)) for f in self.impl for s in [facts.unit_state.get(f, ['NOT IN '
                      'THE COMPILE DATABASE'])] if any(x != codedb.CURRENT for x in s)]
        self._methods = None
        self._sends = None

    # --- Helpers.

    def db_status(self, status, evidence):
        """A PASS from the unit's own database rows is MANUAL when its units
        are not current."""
        if status != 'FAIL' and self.stale:
            evidence.append('the unit\'s rows may be missing or wrong, so this is not a PASS: %s' %
                            '; '.join(self.stale))
            return 'MANUAL'
        return status

    def unit_sends(self):
        """[(file, line, selector, receiver type, enclosing)] of every send in
        the unit's files."""
        if self._sends is None:
            marks = ','.join('?' * len(self.unit))
            self._sends = self.con.execute(
                'SELECT DISTINCT file, line, selector, receiver_type, enclosing_name FROM send WHERE file IN (%s) '
                'ORDER BY file, line' % marks, self.unit).fetchall()
        return self._sends

    def unit_text_hits(self, pattern):
        """['file:line: match'] of pattern in the unit's files, comments and
        string literals left out."""
        out = []
        for f in self.unit:
            text = strip_comments(self.f.text(f))
            for m in pattern.finditer(text):
                out.append('%s:%d: %s (text)' % (f, text.count('\n', 0, m.start()) + 1, m.group(0)))
        return out

    def stale_mentions(self, tokens):
        """['file mentions TOKEN ...'] for the app files outside the unit
        whose unit or module is not current and that mention one of tokens:
        the database may lack references there. (Code that is not compiled
        is the census's own heading; test files are counted apart.)"""
        out = collections.OrderedDict()
        tokens = sorted(set(t for t in tokens if t))
        index = self.f.stale_index()

        def app_file(f):
            return f not in self.unit_set and not f.startswith(TEST_LIKE_DIRS) and f not in self.f.test_files
        for tok in tokens:
            for f in index.get(tok, ()):
                if app_file(f):
                    out.setdefault((f, tok), '%s mentions %s, and its unit or module is not current' % (f, tok))
        found = list(out.values())
        if len(found) > STALE_EVIDENCE_MAX:
            found = found[:STALE_EVIDENCE_MAX] + ['and %d more such mentions' % (len(found) - STALE_EVIDENCE_MAX)]
        return found

    def methods(self):
        if self._methods is None:
            if self.category:
                # Only the category's own methods, in the shape of
                # Census.class_methods.
                out = collections.OrderedDict()
                for sel, is_cls, f, line, kind, container, prop, definition in self.con.execute(
                        "SELECT DISTINCT selector, is_class_method, file, line, container_kind, container_name, "
                        "property_usr IS NOT NULL, is_definition OR is_synthesized_accessor FROM objc_method WHERE "
                        "class_name = ? AND container_name = ? ORDER BY selector, is_class_method, file, line",
                        (self.cls, self.container)):
                    d = out.setdefault((is_cls, sel), {'objc': [], 'swift': [], 'property': False, 'defined': False})
                    d['objc'].append((f, line, kind, container))
                    d['property'] = d['property'] or bool(prop)
                    d['defined'] = d['defined'] or bool(definition)
                self._methods = out
            else:
                self._methods = self.c.class_methods(self.cls)
        return self._methods

    def selectors(self):
        return sorted(set(sel for _, sel in self.methods()))

    def properties(self):
        if self.category:
            return self.con.execute('SELECT DISTINCT name, attributes, file, line FROM objc_property WHERE class_name '
                                    '= ? AND container_name = ? ORDER BY file, line',
                                    (self.cls, self.container)).fetchall()
        return self.con.execute('SELECT DISTINCT name, attributes, file, line FROM objc_property WHERE class_name = ? '
                                'ORDER BY file, line', (self.cls,)).fetchall()

    # --- The conditions.

    def check_1(self):
        ev = ['%s: %d lines' % (f, self.f.lines(f)) for f in self.impl]
        others = sorted(set(c for c, fl in self.f.impls.items() if c != self.cls for f, _ in fl if f in self.impl))
        if others:
            ev.append('the implementation files also implement: %s' % ', '.join(others))
        ev.append('total: %d' % self.impl_lines)
        return Condition('1', 'PASS' if self.impl_lines <= MAX_LINES else 'FAIL', ev,
                         'line count of the implementation files (objc_impl rows of %s without a category, and its '
                         'categories in files named %s+*)' % (self.cls, self.cls))

    def check_2(self):
        users = dict(self.f.users.get(self.cls, {}))
        for f, line in self.f.type_index([self.cls])[self.cls]:
            users.setdefault(f, '%s:%d names the class (text search: a type, a cast or a variable)' % (f, line))
        counted, own, bridging = [], [], []
        for f in sorted(users):
            if f in self.unit_set:
                continue
            if f.endswith('-Bridging-Header.h'):
                bridging.append(f)
            elif f.startswith(ep.TEST_DIRS) and self.cls in os.path.basename(f):
                own.append(f)
            else:
                counted.append(f)
        ev = ['%d file%s outside the unit use it%s' % (len(counted), '' if len(counted) == 1 else 's',
                                                       ':' if counted else '')]
        ev += ['  %s' % users[f] for f in counted]
        ev += ['not counted: %s (the unit\'s own tests)' % f for f in own]
        ev += ['not counted: %s (the bridging header)' % f for f in bridging]
        self.counted_users = counted
        self.user_evidence = users
        known = self.unit_set | set(counted) | set(own) | set(bridging)

        def not_counted_kind(f):
            if f.endswith('-Bridging-Header.h'):
                return 'the bridging header'
            if f.startswith(ep.TEST_DIRS) and self.cls in os.path.basename(f):
                return 'the unit\'s own tests'
            return None
        unparsed = collections.OrderedDict()
        for f, n, where in self.c.uncompiled_index().get(self.cls, ()):
            if f not in known and not not_counted_kind(f):
                unparsed.setdefault(f, '%s:%d names it, in %s' % (f, n, where))
        for f in self.f.stale_index().get(self.cls, ()):
            if f not in known and not not_counted_kind(f):
                unparsed.setdefault(f, '%s names it, and its unit or module is not current' % f)
        if len(counted) > MAX_USERS:
            status = 'FAIL'
        elif unparsed:
            status = 'MANUAL'
            ev.append('files the database does not parse (or not as they are now) name the class; read them:')
            ev += ['  %s' % x for x in unparsed.values()]
        else:
            status = 'PASS'
        ev.append('a mention that is no send, Swift reference, ivar access, subclass or category (a variable\'s '
                  'type, a cast) is found by a text search of the C-family and Swift files for the class name as a '
                  'whole word (comments, string literals, imports and @class lines left out)')
        return Condition('2', status, ev,
                         'code database: send rows whose target_usr names (cs)%s or whose receiver type is %s; '
                         'swift_ref rows of class %s or a USR naming it; objc_class rows with superclass %s and Swift '
                         'overrides of its members; categories of it (objc_method); ivar_ref rows of its instance '
                         'variables; a text search for the name as a whole word; then the census\'s index of code not '
                         'compiled and the text of stale units\' files for the name' % ((self.cls,) * 4))

    def check_3a(self):
        res = self.c.resources
        cls = self.cls
        fail, manual = [], []
        for c in res.classes:
            if c.cls == cls:
                (manual if c.file in res.other_project else fail).append(
                    '%s:%d customClass on %s' % (c.file, c.line, c.desc))
        for o in res.outlets:
            if o.owner.cls == cls:
                (manual if o.file in res.other_project else fail).append(
                    '%s:%d outlet %s owned by %s' % (o.file, o.line, o.property, o.owner.desc))
            if o.property in ('delegate', 'dataSource') and o.dest.cls == cls:
                (manual if o.file in res.other_project else fail).append(
                    '%s:%d the %s of %s' % (o.file, o.line, o.property, o.owner.desc))
        sels = set(self.selectors())
        for a in res.actions:
            if a.target.cls == cls:
                (manual if a.file in res.other_project else fail).append(
                    '%s:%d action %s targeting %s' % (a.file, a.line, a.selector, a.target.desc))
            elif a.target.kind == 'first-responder' and a.selector in sels:
                manual.append('%s:%d First Responder action %s, a selector of the class: it reaches the class if an '
                              'instance is in the responder chain' % (a.file, a.line, a.selector))
        for k in res.keyed:
            if k.target.cls == cls:
                (manual if k.file in res.other_project else fail).append(
                    '%s:%d %s %s on %s' % (k.file, k.line, k.kind, k.key_path, k.target.desc))
        if manual:
            manual = [m + ('' if 'First Responder' in m else ' (in a directory another project builds)')
                      for m in manual]
        status = 'FAIL' if fail else 'MANUAL' if manual else 'PASS'
        return Condition('3a', status, fail + manual or ['none (%d xibs and storyboards parsed)' % res.counts['ib']],
                         'entry_points.py Resources: every xib and storyboard parsed as XML (custom classes, outlets, '
                         'actions with their resolved targets, bindings and runtime attributes)')

    def check_3b(self):
        res = self.c.resources
        cls = self.cls
        fail = []
        for item in res.sdef:
            if item.cocoa_class == cls or (item.kind in ('class', 'class-extension') and
                                           cls in self.c.sdef_receivers(item.cocoa_class)):
                fail.append('%s:%d sdef %s "%s" (cocoa class %s)' % (
                    item.file, item.line, item.kind, item.name, item.cocoa_class))
        for p in res.plist:
            if p.kind != 'services message' and p.value == cls:
                fail.append('%s:%s %s' % (p.file, p.line or '?', p.kind))
        for c in res.coredata:
            if c.kind == 'entity' and c.cls == cls:
                fail.append('%s:%d Core Data entity %s' % (c.file, c.line, c.entity))
        return Condition('3b', 'FAIL' if fail else 'PASS', fail or ['none'],
                         'entry_points.py Resources: the sdef, property lists, project files (Info.plist build '
                         'settings) and Core Data models, parsed')

    def coding(self):
        """Evidence that the class is archived with NSCoding."""
        out = []
        if self.category:
            where, params = 'class_or_category = ?', (self.container,)
        else:
            where, params = '(class_or_category = ? OR class_or_category LIKE ?)', (self.cls, self.cls + '(%')
        for proto, f, line in self.con.execute(
                "SELECT DISTINCT protocol, file, line FROM objc_adoption WHERE %s AND protocol IN ('NSCoding', "
                "'NSSecureCoding')" % where, params):
            out.append('%s:%d adopts %s' % (f, line, proto))
        for (is_cls, sel), info in self.methods().items():
            if not is_cls and sel in ('initWithCoder:', 'encodeWithCoder:') and info['defined']:
                out.append('defines -%s (%s)' % (sel, ', '.join('%s:%d' % (x[0], x[1]) for x in info['objc'])))
        return out

    def check_3c(self):
        fail = self.coding()
        # A category is not archived by its own name; the class's archive does
        # not change when one of its categories moves.
        manual = [] if self.category else [
            '%s:%d the class name as a whole string literal (an archive key, a lookup by name, or a log?)' % fl
            for fl in self.f.string_literals([self.cls])[self.cls] if fl[0] not in self.unit_set]
        ev = fail + manual or ['none']
        status = self.db_status('FAIL' if fail else 'MANUAL' if manual else 'PASS', ev)
        return Condition('3c', status, ev,
                         'code database: objc_adoption of NSCoding or NSSecureCoding by %s or its categories, and '
                         'definitions of initWithCoder: and encodeWithCoder:; text: "%s" as a string literal in the '
                         'repository\'s C-family and Swift files' % (self.cls, self.cls))

    def check_3d(self):
        cls = self.cls
        fail, manual = [], []
        reg = self.c.registry
        if reg is None:
            manual.append('the registry cannot be read: %s' % self.c.registry_error)
        else:
            reg_file = os.path.relpath(self.c.registry_path, self.c.root)
            for nr in reg.names:
                how = ep.name_matches_class(nr.name, cls)
                if how:
                    fail.append('%s:%d names table: %s (%s)' % (reg_file, nr.line, nr.name, how))
            for e in reg.entries:
                if any(ep.name_matches_class(n, cls) for n in e.names):
                    fail.append('%s:%d section %d entry names the class (%s)' % (
                        reg_file, e.line, e.section, e.classification))
                for s in e.sites:
                    if s.file in self.unit_set:
                        fail.append('%s:%d section %d entry for a site in the unit: %s:%d (%s)' % (
                            reg_file, e.line, e.section, s.file, s.line, e.classification))
                        break
        for f, line, call, arg in self.con.execute(
                "SELECT DISTINCT file, line, function_or_selector, argument_text FROM reflective_call WHERE kind = "
                "'class' AND (argument_text = ? OR resolved_class = ?) ORDER BY file, line", (cls, cls)):
            fail.append('%s:%d %s looks the class up by name' % (f, line, call))
        marks = ','.join('?' * len(self.unit))
        for f, line, call, arg in self.con.execute(
                "SELECT DISTINCT file, line, function_or_selector, argument_text FROM reflective_call WHERE "
                "argument_kind = 'dynamic' AND file IN (%s) ORDER BY file, line" % marks, self.unit):
            if call in SWIZZLE_FUNCTIONS + IVAR_FUNCTIONS:
                continue  # conditions 4f and 4g
            fail.append('%s:%d dynamic reflective call %s on %s' % (f, line, call, arg))
        for hit in self.unit_text_hits(re.compile(r'\b(?:%s)\b' % '|'.join(CONVERSIONS))):
            fail.append('%s: a conversion between names and classes or selectors in the unit (the registry '
                        'registers every one, harmless ones included)' % hit)
        ev = fail + manual or ['none']
        status = self.db_status('FAIL' if fail else 'MANUAL' if manual else 'PASS', ev)
        return Condition('3d', status, ev,
                         'entry_points.py parse_registry of %s (names table, entries\' Names lines and sites); code '
                         'database: reflective_call rows of kind class naming %s, and dynamic reflective_call rows in '
                         'the unit\'s files; text: %s in the unit\'s files' % (
                             ep.REGISTRY_PATH, cls, ', '.join(CONVERSIONS)))

    def check_3e(self):
        cls = self.cls
        props = set(p[0] for p in self.properties())
        fail, manual = [], []
        if props:
            for f, line, call, kind, arg, rtype in self.con.execute(
                    "SELECT DISTINCT file, line, function_or_selector, kind, argument_text, receiver_type FROM "
                    "reflective_call WHERE kind IN ('key', 'key-path') AND argument_text IS NOT NULL ORDER BY file, "
                    "line"):
                if arg.split('.')[0] not in props:
                    continue
                rc = receiver_class(rtype)
                if rc == cls:
                    fail.append('%s:%d %s "%s" sent to %s' % (f, line, call, arg, rtype))
                elif rc is None or rc in ('NSObject',):
                    manual.append('%s:%d %s "%s" sent to %s, whose class is not known' % (
                        f, line, call, arg, rtype or 'an unknown type'))
        for f, line, sel, rtype, enclosing in self.unit_sends():
            if sel in KVO_SELECTORS:
                fail.append('%s:%d %s sends %s' % (f, line, enclosing, sel))
        for (is_cls, sel), info in self.methods().items():
            if is_cls and KVO_CLASS_METHOD.match(sel) and info['defined']:
                fail.append('defines +%s' % sel)
        if self.c.swift_tables:
            for f, line, kind, member in self.con.execute(
                    "SELECT DISTINCT file, line, kind, coalesce(property, selector) FROM swift_ref WHERE "
                    "class_name = ? "
                    "AND kind IN ('keypath', 'dynamic') ORDER BY file, line", (cls,)):
                (fail if kind == 'keypath' else manual).append('%s:%d Swift %s reference to %s' % (
                    f, line, kind, member))
        manual += self.stale_mentions(props)
        ev = fail + manual or ['none (properties: %s)' % (', '.join(sorted(props)) or 'none')]
        status = self.db_status('FAIL' if fail else 'MANUAL' if manual else 'PASS', ev)
        return Condition('3e', status, ev,
                         'code database: reflective_call rows of kind key or key-path whose key names a property of '
                         '%s (objc_property), judged by their receiver type; sends of %s in the unit; +%s methods; '
                         'swift_ref rows of kind keypath or dynamic of class %s' % (
                             cls, ', '.join(KVO_SELECTORS[:2]) + ' and the like',
                             'keyPathsForValuesAffecting*', cls))

    def check_3f(self):
        table, _, _ = ep.method_table(self.c, self.cls)
        fail, manual, ignored = [], [], []
        hit_methods = [m for m in table if any(m[k] for k in CENSUS_COLUMNS)]
        sdk = self.c.sdk_declarations(m['method'][1:] for m in hit_methods)
        for m in hit_methods:
            hits = [(k, m[k]) for k in CENSUS_COLUMNS if m[k]]
            sel = m['method'][1:]
            others = sorted(self.f.selector_classes.get(sel, set()) - {self.cls})
            text = '%s: %s' % (m['method'], ', '.join('%s %d' % kv for kv in hits))
            if any(d.container == 'NSObject' and d.kind in ('class', 'protocol')
                   for d in sdk.get((m['method'][0] == '+', sel), ())):
                ignored.append('not evidence: %s (NSObject declares the selector, so every object answers it and the '
                               'hit is not about this class)' % text)
            elif others:
                manual.append('%s (the selector is also a method of %s%s, so the hit may be theirs)' % (
                    text, ', '.join(others[:5]), ' and %d more' % (len(others) - 5) if len(others) > 5 else ''))
            else:
                fail.append(text + ' (no other class in the repository has the selector)')
        all_sdk = self.c.sdk_declarations(m['method'][1:] for m in table)
        nsobject = set(sel for (is_cls, sel), decls in all_sdk.items()
                       if any(d.container == 'NSObject' and d.kind in ('class', 'protocol') for d in decls))
        manual += self.stale_mentions(tok for m in table if m['method'][1:] not in nsobject
                                      for tok in ep.search_tokens(m['method'][1:]))
        status = 'FAIL' if fail else 'MANUAL' if manual else 'PASS'
        return Condition('3f', status, fail + manual + ignored or ['none: only Objective-C sends and Swift references '
                                                                   '(%d methods)' % len(table)],
                         'entry_points.py method_table for %s (the census\'s per-method counts: %s); a selector '
                         'shared with another class (objc_method, swift_objc_decl) makes a hit MANUAL; a hit on a '
                         'selector the SDK\'s NSObject class or protocol declares is not evidence (sdk_method)' % (
                             self.cls, ', '.join(CENSUS_COLUMNS)))

    def check_4a(self):
        fail = ['%s is Objective-C++' % f for f in self.impl if f.endswith('.mm')]
        marks = ','.join('?' * len(self.impl))
        for f, args in self.con.execute('SELECT DISTINCT main_file, arguments FROM tu WHERE main_file IN (%s)' % marks,
                                        self.impl):
            if 'objective-c++' in args and not f.endswith('.mm'):
                fail.append('%s is compiled as Objective-C++ (tu arguments)' % f)
        fail += self.unit_text_hits(CXX_TEXT)
        return Condition('4a', 'FAIL' if fail else 'PASS', fail or ['none'],
                         'file names, the code database\'s tu arguments of the implementation files, and a text '
                         'search of the unit\'s files for C++ constructs')

    def check_4b(self):
        fail = []
        for (is_cls, sel), info in self.methods().items():
            if is_cls and sel in ('load', 'initialize') and info['defined']:
                fail.append('defines +%s at %s' % (sel, ', '.join('%s:%d' % (x[0], x[1]) for x in info['objc'])))
        ev = fail or ['none']
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('4b', status, ev,
                         'code database: objc_method definitions of +load and +initialize of %s' % self.cls)

    def dealloc_body_calls(self, f, line):
        """C function and macro calls in the body of a method starting at
        f:line (text, comments and strings left out)."""
        text = strip_comments(self.f.text(f))
        lines = text.split('\n')
        start = sum(len(x) + 1 for x in lines[:max(line - 1, 0)])
        i = text.find('{', start)
        if i < 0:
            return []
        depth, j = 0, i
        while j < len(text):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = text[i + 1:j]
        out = []
        for m in re.finditer(r'(@?[A-Za-z_]\w*)\s*\(', body):
            name = m.group(1)
            if name in C_KEYWORDS or DEALLOC_ALLOWED_CALLS.match(name):
                continue
            out.append('%s:%d calls %s()' % (f, text.count('\n', 0, i + 1 + m.start()) + 1, name))
        return out

    def check_4c(self):
        rows = self.con.execute(
            "SELECT DISTINCT file, line, container_name FROM objc_method WHERE class_name = ? AND selector = 'dealloc' "
            "AND is_class_method = 0 AND is_definition = 1 ORDER BY file, line", (self.cls,)).fetchall()
        if not rows:
            ev = ['no -dealloc']
            return Condition('4c', self.db_status('PASS', ev), ev,
                             'code database: objc_method definitions of -dealloc of %s' % self.cls)
        fail = []
        for f, line, container in rows:
            name = '-[%s dealloc]' % container
            for (sel,) in self.con.execute('SELECT DISTINCT selector FROM send WHERE enclosing_name = ? ORDER BY 1',
                                           (name,)):
                if sel not in DEALLOC_ALLOWED_SENDS:
                    fail.append('%s sends %s' % (name, sel))
            fail += self.dealloc_body_calls(f, line)
        ev = fail or ['-dealloc at %s only releases' % ', '.join('%s:%d' % (r[0], r[1]) for r in rows)]
        return Condition('4c', self.db_status('FAIL' if fail else 'PASS', ev), ev,
                         'code database: the sends in -dealloc (send rows by enclosing_name; allowed: %s); text: C '
                         'function and macro calls in its body (allowed: DLog, RLog, NSLog, *Release)' % ', '.join(
                             DEALLOC_ALLOWED_SENDS))

    def check_4d(self):
        fail = ['%s:%d @property %s (%s): atomic' % (f, line, name, attrs) for name, attrs, f, line in
                self.properties() if 'nonatomic' not in attrs.split(',')]
        ev = fail or ['none (%d properties)' % len(self.properties())]
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('4d', status, ev,
                         'code database: objc_property rows of %s whose attributes lack nonatomic' % self.cls)

    def check_4e(self):
        fail = ['%s:%d %s sends %s' % (f, line, enc, sel) for f, line, sel, rtype, enc in self.unit_sends()
                if sel in ASSOCIATED_SELECTORS]
        fail += self.unit_text_hits(re.compile(r'\b(?:%s)\b' % '|'.join(ASSOCIATED_FUNCTIONS)))
        ev = fail or ['none']
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('4e', status, ev,
                         'code database: sends of %s in the unit; text: %s in the unit\'s files' % (
                             ', '.join(ASSOCIATED_SELECTORS), ', '.join(ASSOCIATED_FUNCTIONS)))

    def check_4f(self):
        fail = []
        marks = ','.join('?' * len(SWIZZLE_FUNCTIONS))
        for f, line, call, arg in self.con.execute(
                'SELECT DISTINCT file, line, function_or_selector, argument_text FROM reflective_call WHERE '
                'function_or_selector IN (%s) ORDER BY file, line' % marks, SWIZZLE_FUNCTIONS):
            if f in self.unit_set or re.search(r'\b%s\b' % re.escape(self.cls), arg or ''):
                fail.append('%s:%d %s on %s' % (f, line, call, arg))
        for f, line, sel, rtype, enc in self.unit_sends():
            if receiver_class(rtype) == 'iTermSelectorSwizzler' or 'swizzle' in sel.lower():
                fail.append('%s:%d %s sends %s' % (f, line, enc, sel))
        ev = fail or ['none']
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('4f', status, ev,
                         'code database: reflective_call rows of %s in the unit or naming %s; sends to '
                         'iTermSelectorSwizzler or of a selector containing "swizzle" in the unit' % (
                             ', '.join(SWIZZLE_FUNCTIONS), self.cls))

    def check_4g(self):
        fail = []
        for f, line, name, enc in self.con.execute(
                'SELECT file, min(line), ivar_name, enclosing_name FROM ivar_ref WHERE ivar_class = ? GROUP BY file, '
                'ivar_name ORDER BY file', (self.cls,)):
            if f not in self.unit_set and not os.path.isabs(f):
                fail.append('%s:%d %s accesses the instance variable %s' % (f, line, enc or '(file scope)', name))
        marks = ','.join('?' * len(IVAR_FUNCTIONS))
        for f, line, call, arg in self.con.execute(
                'SELECT DISTINCT file, line, function_or_selector, argument_text FROM reflective_call WHERE '
                'function_or_selector IN (%s) ORDER BY file, line' % marks, IVAR_FUNCTIONS):
            if f in self.unit_set or re.search(r'\b%s\b' % re.escape(self.cls), arg or ''):
                fail.append('%s:%d %s on %s' % (f, line, call, arg))
        ev = fail or ['none']
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('4g', status, ev,
                         'code database: ivar_ref rows of the instance variables of %s in files outside the unit; '
                         'reflective_call rows of %s in the unit or naming the class' % (
                             self.cls, ', '.join(IVAR_FUNCTIONS)))

    def check_5a(self):
        fail = ['%s:%d %s sends %s to %s' % (f, line, enc, sel, rtype) for f, line, sel, rtype, enc in
                self.unit_sends() if receiver_class(rtype) in LOCK_CLASSES]
        marks = ','.join('?' * len(self.unit))
        for f, line, lock in self.con.execute(
                'SELECT DISTINCT file, line, sync_lock FROM ivar_ref WHERE sync_lock IS NOT NULL AND file IN (%s) '
                'ORDER BY file, line' % marks, self.unit):
            fail.append('%s:%d an ivar used inside @synchronized (%s)' % (f, line, lock))
        fail += self.unit_text_hits(LOCK_TEXT)
        ev = fail or ['none']
        status = self.db_status('FAIL' if fail else 'PASS', ev)
        return Condition('5a', status, ev,
                         'code database: sends to %s in the unit, ivar_ref rows inside @synchronized; text: '
                         '@synchronized, os_unfair_lock, pthread mutexes, dispatch semaphores, atomics in the unit\'s '
                         'files' % ', '.join(LOCK_CLASSES))

    def check_5b(self):
        fail = ['%s:%d %s sends %s to %s' % (f, line, enc, sel, rtype) for f, line, sel, rtype, enc in
                self.unit_sends() if receiver_class(rtype) in THREAD_CLASSES or THREAD_SELECTOR.match(sel)]
        fail += self.unit_text_hits(THREAD_TEXT)
        timers = ['schedules work: timer: %s:%d %s sends %s to %s' % (f, line, enc, sel, rtype)
                  for f, line, sel, rtype, enc in self.unit_sends()
                  if receiver_class(rtype) in TIMER_CLASSES or TIMER_SELECTOR.match(sel)]
        timers += ['schedules work: timer: %s' % x for x in self.unit_text_hits(TIMER_TEXT)]
        ev = fail + timers or ['none']
        status = self.db_status('FAIL' if fail else 'MANUAL' if timers else 'PASS', ev)
        if timers and not fail:
            ev.append('a timer, a delayed perform or dispatch_after is neither a dispatch queue nor a thread API, but '
                      'it runs the work later on a run loop: read it')
        return Condition('5b', status, ev,
                         'code database: sends to %s and of performSelectorOnMainThread:/InBackground:/onThread: and '
                         'detachNewThread* in the unit; text: dispatch_* (not dispatch_after), DispatchQueue, '
                         'NSOperationQueue, NSThread, pthread_create, iTermGCD, iTermThread in the unit\'s files; '
                         'MANUAL for sends to %s, performSelector:withObject:afterDelay: and dispatch_after' % (
                             ', '.join(THREAD_CLASSES), ', '.join(TIMER_CLASSES)))

    def check_5c(self):
        if self.callers_thread:
            return Condition('5c', 'RECORDED', ['recorded by a person: %s' % self.callers_thread],
                             '--callers-thread (a person\'s answer; no tool decides this)')
        ev = ['no tool decides this; read the callers (condition 2) and record the answer with --callers-thread']
        users = getattr(self, 'user_evidence', {})
        ev += ['  %s' % users[f] for f in getattr(self, 'counted_users', [])]
        return Condition('5c', 'MANUAL', ev, 'none: a person reads the call sites')

    def check_6(self):
        fail = ['%s is under %s' % (f, d) for f in self.unit for d in inventory.HOT_PATH_DIRS if f.startswith(d)]
        names = set([self.cls] + [os.path.basename(f) for f in self.unit] +
                    [os.path.splitext(os.path.basename(f))[0] for f in self.unit] + self.unit)
        fail += ['hot-paths.md lists %s' % x for x in self.f.hot_listed if x in names]
        hot_list = '%s, and files named %s*' % (', '.join(inventory.HOT_PATH_DIRS), '*, '.join(HOT_SENDER_PREFIXES))

        def hot(f):
            return f.startswith(inventory.HOT_PATH_DIRS) or os.path.basename(f).startswith(HOT_SENDER_PREFIXES)
        if self.category:
            # A category's callers are the senders of its own selectors.
            sels = self.selectors()
            manual = []
            for part in ep.chunks(sels):
                for f, line, sel in self.con.execute(
                        'SELECT DISTINCT file, line, selector FROM send WHERE selector IN (%s) ORDER BY file, line' %
                        ','.join('?' * len(part)), part):
                    if f not in self.unit_set and hot(f):
                        manual.append('used from per-frame or per-token code: %s:%d sends %s' % (f, line, sel))
        else:
            manual = ['used from per-frame or per-token code: %s' % what
                      for f, what in sorted(self.f.users.get(self.cls, {}).items())
                      if f not in self.unit_set and hot(f)]
        if not manual and not self.category:
            # One level: a user file's own class is used from hot code.
            for f, what in sorted(self.f.users.get(self.cls, {}).items()):
                if f in self.unit_set:
                    continue
                for other in sorted(c for c in self.f.file_classes.get(f, set()) - {self.cls}
                                    if any(g == f for g, _ in self.f.impls.get(c, ()))):
                    hot_uses = sorted((g, w) for g, w in self.f.users.get(other, {}).items()
                                      if hot(g) and other not in self.f.file_classes.get(g, ()))
                    for g, w in hot_uses[:3]:
                        manual.append('used from %s (%s), and %s is used from per-frame or per-token code: %s' % (
                            f, what, other, w))
        if manual:
            manual.append('read whether these run per frame, per cell or per token (performance.md section 2)')
        ev = fail + manual or ['not under %s; not in hot-paths.md; not sent to from per-frame or per-token code '
                               '(list: %s)' % (', '.join(inventory.HOT_PATH_DIRS), hot_list)]
        return Condition('6', 'FAIL' if fail else 'MANUAL' if manual else 'PASS', ev,
                         'inventory.py HOT_PATH_DIRS (performance.md section 2), the first column of hot-paths.md\'s '
                         'table, and the database\'s users of the class in per-frame or per-token files (%s)' %
                         hot_list)

    def check_7(self):
        fail, manual = [], []
        for f, line, sel, rtype, enc in self.unit_sends():
            rc = receiver_class(rtype)
            if rc in STORAGE_CLASSES:
                fail.append('%s:%d %s sends %s to %s' % (f, line, enc, sel, rtype))
            elif sel in STORAGE_SELECTORS or 'rrangement' in sel:
                fail.append('%s:%d %s sends %s' % (f, line, enc, sel))
        for (is_cls, sel), info in self.methods().items():
            if 'rrangement' in sel and info['defined']:
                fail.append('defines %s%s (an arrangement)' % ('+' if is_cls else '-', sel))
        marks = ','.join('?' * len(self.unit))
        for f, line, name in self.con.execute(
                'SELECT DISTINCT file, line, name FROM static_ref WHERE file IN (%s) ORDER BY file, line' % marks,
                self.unit):
            if STORED_CONSTANT.search(name):
                fail.append('%s:%d uses %s (an arrangement or preference key)' % (f, line, name))
        keys = self.f.key_macros
        for f, line, name in self.con.execute(
                'SELECT DISTINCT file, line, name FROM macro_expansion WHERE file IN (%s) ORDER BY file, line' % marks,
                self.unit):
            if name in keys:
                fail.append('%s:%d uses the profile key %s (defined in %s)' % (f, line, name, keys[name]))
        if self.f.key_families:
            family = re.compile(r'\b(?:%s)[A-Z0-9_]+\b' % '|'.join(re.escape(x) for x in self.f.key_families))
            seen = set(x.split(':')[0] + ':' + x.split(':')[1] for x in fail if x.count(':') >= 2)
            for hit in self.unit_text_hits(family):
                if hit.split(':')[0] + ':' + hit.split(':')[1] not in seen:
                    fail.append('%s: a profile key by name (text fallback)' % hit)
        fail += self.unit_text_hits(STORAGE_TEXT)
        writers = self.f.writer_methods()
        for f, line, sel, usr, enc in self.con.execute(
                'SELECT DISTINCT file, line, selector, target_usr, enclosing_name FROM send WHERE file IN (%s) '
                'ORDER BY '
                'file, line' % marks, self.unit):
            m = _USR_METHOD.search(usr or '')
            if not m or m.group(1) == self.cls:
                continue
            key = (m.group(1), '+' if m.group(2) == 'cm' else '-', m.group(3))
            if key in writers:
                manual.append('%s:%d %s sends %s%s to %s, which stores (%s)' % (
                    f, line, enc, key[1], sel, key[0], writers[key]))
        if manual and not fail:
            manual.append('it may store through these methods (one level of helper): read them')
        ev = fail + manual or ['none (direct uses in the unit and sends to methods that store directly)']
        status = self.db_status('FAIL' if fail else 'MANUAL' if manual else 'PASS', ev)
        return Condition('7', status, ev,
                         'code database: sends in the unit to %s, of %s, or of a selector containing "rrangement"; '
                         'macro_expansion rows of the profile keys (string macros of headers defining at least %d: '
                         '%s); static_ref rows of arrangement and preference keys; MANUAL: sends to repository methods '
                         'that themselves store directly (one level); text: the key families and fopen, fwrite, '
                         'mkstemp, creat in the unit\'s files. Archiving with NSCoding is condition 3c' % (
                             ', '.join(STORAGE_CLASSES), ', '.join(STORAGE_SELECTORS), KEY_HEADER_MIN,
                             ', '.join(self.f.key_families) or 'none found'))

    # --- The trivial path's conditions.

    def light(self, cid):
        """The light condition cid, computed once."""
        if not hasattr(self, '_light'):
            self._light = {}
        if cid not in self._light:
            self._light[cid] = getattr(self, 'check_' + cid)()
        return self._light[cid]

    def from_light(self, tid, cids, extra_fail=(), extra_ev=()):
        """A trivial condition that holds when the light conditions cids all
        PASS (and extra_fail is empty)."""
        found = [self.light(c) for c in cids]
        ev = ['%s %s: %s' % (c.id, c.status, '; '.join(c.evidence[:3])) for c in found] + list(extra_ev)
        ev += list(extra_fail)
        status = worst([c.status for c in found] + (['FAIL'] if extra_fail else []))
        return Condition(tid, status, ev, 'the light conditions %s%s' % (
            ', '.join(cids), ' and the extra checks listed' if extra_ev or extra_fail else ''))

    def arc_files(self):
        """{implementation file: True when every unit compiles it with ARC}."""
        out = {}
        marks = ','.join('?' * len(self.impl))
        for f, arc in self.con.execute('SELECT DISTINCT file, arc FROM objc_impl WHERE file IN (%s)' % marks,
                                       self.impl):
            out[f] = out.get(f, True) and bool(arc)
        return out

    def asts(self):
        """[(file, facts or ASTError)] of the implementation files."""
        arc = self.arc_files()
        return [(f, self.f.ast(f, arc.get(f, False))) for f in self.impl]

    def ast_condition(self, tid, judge, how):
        ev, statuses = [], []
        for f, facts in self.asts():
            if isinstance(facts, unit_ast.ASTError):
                ev.append('%s: not measured: %s' % (f, facts))
                statuses.append('MANUAL')
                continue
            status, lines = judge(f, facts)
            statuses.append(status)
            ev += lines
        return Condition(tid, worst(statuses), ev, how)

    def check_T1(self):
        total = [0]

        def judge(f, facts):
            total[0] += facts['body_lines']
            return 'PASS', ['%s: %d body lines: %s' % (f, facts['body_lines'], ', '.join(
                '%s %d' % (b['name'], b['lines']) for b in facts['bodies']) or 'no bodies')]
        c = self.ast_condition('T1', judge, 'Clang\'s AST of each implementation file (unit_ast.py): every method '
                                            'and C function body, opening brace line to closing brace line')
        self.body_lines = total[0] if c.status != 'MANUAL' else None
        if c.status == 'MANUAL':
            return c
        ev = c.evidence + ['total: %d (at most %d)' % (total[0], MAX_TRIVIAL_BODY_LINES)]
        return Condition('T1', 'PASS' if total[0] <= MAX_TRIVIAL_BODY_LINES else 'FAIL', ev, c.how)

    def check_T2(self):
        fail = []
        for cls in self.unit_classes():
            for name, container, f, line in self.con.execute(
                    'SELECT DISTINCT name, container_kind, file, line FROM objc_ivar WHERE class_name = ? ORDER BY '
                    'file, line', (cls,)):
                fail.append('%s:%d instance variable %s of %s (%s)' % (f, line, name, cls, container))
            for name, f, line in self.con.execute(
                    "SELECT DISTINCT name, file, line FROM objc_property WHERE class_name = ? AND kind = 'synthesize' "
                    "ORDER BY file, line", (cls,)):
                fail.append('%s:%d property %s of %s has storage (synthesized)' % (f, line, name, cls))
        marks = ','.join('?' * len(self.unit))
        for name, kind, f, line in self.con.execute(
                "SELECT DISTINCT name, kind, file, line FROM c_static WHERE file IN (%s) AND kind IN ('file-static', "
                "'global', 'local-static') AND is_const = 0 ORDER BY file, line" % marks, self.unit):
            fail.append('%s:%d %s variable %s is not const' % (f, line, kind, name))
        ev = fail or ['none']
        return Condition('T2', self.db_status('FAIL' if fail else 'PASS', ev), ev,
                         'code database: objc_ivar rows and synthesize rows of objc_property of %s (none for a '
                         'category, which cannot add storage; associated objects are T7); c_static rows in the unit\'s '
                         'files that are file-static, global or local-static and not const' % (
                             ', '.join(self.unit_classes()) or 'no class'))

    def ast_function_hits(self, pattern):
        """['file:line calls NAME (Clang's AST)'] of the C functions the
        implementation files refer to whose name matches pattern, macro
        expansions included (the text search misses a call a macro from
        another header makes)."""
        out = []
        for f, facts in self.asts():
            if not isinstance(facts, unit_ast.ASTError):
                out += ['%s:%s calls %s (Clang\'s AST)' % (f, line, name) for line, name in facts['functions']
                        if pattern.match(name)]
        return out

    def check_T3(self):
        fail = self.ast_function_hits(AST_THREAD_FUNCTIONS)
        manual = self.ast_function_hits(AST_TIMER_FUNCTIONS)
        c = self.from_light('T3', ('5a', '5b'), extra_fail=fail)
        if manual and c.status == 'PASS':
            return Condition('T3', 'MANUAL', c.evidence + ['schedules work: %s' % x for x in manual], c.how)
        return c

    def check_T4(self):
        def judge(f, facts):
            bad = ['%s: Core Foundation ownership: %s' % (f, x) for x in facts['retained']]
            if not facts['arc']:
                bad = ['%s: not ARC, and ARC changes or rejects: %s' % (f, x) for x in facts['ownership']] + bad
            if bad:
                return 'FAIL', unit_ast.unique(bad)
            if facts['arc']:
                return 'PASS', ['%s: compiled with ARC, and no Core Foundation ownership' % f]
            return 'PASS', ['%s: not ARC, but nothing in it that ARC changes or rejects, so the port is the move '
                            'to ARC' % f]
        return self.ast_condition('T4', judge, 'code database: objc_impl.arc; Clang\'s AST (unit_ast.py\'s '
                                               'ownership list for a file without ARC, and its retained list for '
                                               'every file)')

    def check_T5(self):
        return self.from_light('T5', ('4a',))

    def check_T6(self):
        def judge(f, facts):
            if facts['unsafe']:
                return 'FAIL', ['%s: %s' % (f, x) for x in facts['unsafe']]
            return 'PASS', ['%s: none' % f]
        return self.ast_condition('T6', judge, 'Clang\'s AST of each implementation file (unit_ast.py\'s unsafe '
                                               'list)')

    def unit_definitions(self, where, params=()):
        """['file:line +[Container sel]'] of the method definitions in the
        unit's files that match where."""
        marks = ','.join('?' * len(self.unit))
        return ['%s:%d %s[%s %s]' % (f, line, '+' if is_cls else '-', container, sel)
                for f, line, is_cls, container, sel in self.con.execute(
                    'SELECT DISTINCT file, line, is_class_method, container_name, selector FROM objc_method WHERE '
                    'is_definition = 1 AND file IN (%s) AND (%s) ORDER BY file, line' % (marks, where),
                    tuple(self.unit) + tuple(params))]

    def check_T7(self):
        # In the unit's files, so that every class of a file counts.
        fail = ['defines %s' % x for x in self.unit_definitions(
            "(selector = 'dealloc' AND is_class_method = 0) OR (selector IN ('load', 'initialize') AND "
            "is_class_method = 1)")]
        fail += self.ast_function_hits(AST_STATE_FUNCTIONS)
        return self.from_light('T7', ('4b', '4e', '4f'), extra_fail=fail,
                               extra_ev=[] if fail else ['no -dealloc, +load or +initialize in the unit\'s files'])

    def check_T8(self):
        extra = []
        for cls in self.unit_classes():
            for name, f, line in self.con.execute('SELECT DISTINCT name, file, line FROM objc_class WHERE superclass '
                                                  '= ? ORDER BY file, line', (cls,)):
                if f not in self.unit_set:
                    extra.append('%s:%d declares the Objective-C subclass %s of %s (interop.md)' % (f, line, name, cls))
        marks = ','.join('?' * len(self.unit))
        for who, proto, f, line in self.con.execute(
                "SELECT DISTINCT class_or_category, protocol, file, line FROM objc_adoption WHERE file IN (%s) AND "
                "protocol IN ('NSCoding', 'NSSecureCoding') ORDER BY file, line" % marks, self.unit):
            extra.append('%s:%d %s adopts %s (archived)' % (f, line, who, proto))
        extra += ['defines %s (archived)' % x for x in self.unit_definitions(
            "selector IN ('initWithCoder:', 'encodeWithCoder:') AND is_class_method = 0")]
        # Core Data is stored state too.
        for c in self.c.resources.coredata:
            if c.kind == 'entity' and c.cls in set(self.unit_classes()) | {self.cls}:
                extra.append('%s:%d %s is the class of the Core Data entity %s' % (c.file, c.line, c.cls, c.entity))
        extra += ['%s:%d %s sends %s to %s (Core Data)' % (f, line, enc, sel, rtype)
                  for f, line, sel, rtype, enc in self.unit_sends() if receiver_class(rtype) in CORE_DATA_CLASSES]
        return self.from_light('T8', ('6', '7', '3c'), extra_fail=extra,
                               extra_ev=[] if extra else ['no Objective-C subclass outside the unit; nothing in the '
                                                          'unit\'s files adopts NSCoding or uses Core Data'])

    def unit_classes(self):
        """The classes whose non-category @implementation is in the unit's
        files (none for a category unit): a port moves every one."""
        if self.category:
            return []
        return sorted(c for c, fl in self.f.impls.items() if any(f in self.unit_set for f, _ in fl))

    def trivial(self, stop=False):
        """{id: Condition} of the trivial conditions in TRIVIAL_ORDER; with
        stop, nothing after the first that is not PASS."""
        out = collections.OrderedDict()
        self.body_lines = None
        for tid in TRIVIAL_ORDER:
            out[tid] = getattr(self, 'check_' + tid)()
            if stop and out[tid].status != 'PASS':
                break
        return out

    def run(self, stop_on_fail=False):
        """{id: Condition}, in LIST_ORDER; with stop_on_fail, nothing after
        the first FAIL."""
        out = {}
        for cid in LIST_ORDER:
            c = self.light(cid)
            out[cid] = c
            if stop_on_fail and c.status == 'FAIL':
                break
        return out


def condition_dicts(conditions, texts):
    return [collections.OrderedDict([('id', c.id), ('condition', texts[c.id]), ('status', c.status),
                                     ('evidence', c.evidence), ('how', c.how)]) for c in conditions]


def path_of(trivial, light_fails, category):
    if all(c.status == 'PASS' for c in trivial):
        return 'trivial'
    return 'full' if category or light_fails else 'light'


def qualify(facts, cls, callers_thread=None):
    ch = Checker(facts, cls, callers_thread)
    trivial = ch.trivial()
    trivial = [trivial[tid] for tid in TRIVIAL_CONDITIONS]
    if ch.category:
        conditions = []
    else:
        found = ch.run()
        conditions = [found[cid] for cid in CONDITION_IDS]
    fails = any(c.status == 'FAIL' for c in conditions)
    path = path_of(trivial, fails, ch.category)
    status = (0 if path == 'trivial' else 1) if ch.category else (1 if fails else 0)
    return collections.OrderedDict([
        ('class', cls), ('unit_files', ch.unit), ('implementation_lines', ch.impl_lines),
        ('body_lines', ch.body_lines), ('path', path),
        ('database_incomplete', database_incomplete(facts.census)),
        ('conditions', condition_dicts(conditions, CONDITIONS)),
        ('trivial_conditions', condition_dicts(trivial, TRIVIAL_CONDITIONS)),
        ('exit_status', status),
    ])


def database_incomplete(census):
    """Why the database's answers may be incomplete (the runtime method
    lists are not used here)."""
    return census.objc_incomplete() + census.swift_incomplete() + census.registry_incomplete() + [
        'INCOMPLETE: %s: %s' % p for p in census.resources.problems]


def list_classes(facts):
    """Every class with a non-category @implementation under sources/
    (generated files left out) that no condition FAILs, sorted by size."""
    census = facts.census
    classes = sorted(c for c, fl in facts.impls.items() if any(
        f.startswith('sources/') and not census.is_generated(f) for f, _ in fl))
    sels = set()
    for c in classes:
        sels.update(sel for _, sel in census.class_methods(c))
    census.prepare_whole_tree(sels)
    facts.string_literals(classes)
    facts.type_index(classes)
    out = []
    for c in classes:
        try:
            ch = Checker(facts, c)
        except QualifyError:
            continue
        found = ch.run(stop_on_fail=True)
        if any(x.status == 'FAIL' for x in found.values()):
            continue
        manual = sorted(cid for cid, x in found.items() if x.status == 'MANUAL' and cid != '5c')
        out.append(collections.OrderedDict([('class', c), ('file', ch.impl[0]), ('lines', ch.impl_lines),
                                            ('users', len(ch.counted_users)), ('manual', manual)]))
    out.sort(key=lambda d: (d['lines'], d['class']))
    return collections.OrderedDict([('considered', len(classes)), ('qualifying', len(out)),
                                    ('database_incomplete', database_incomplete(census)), ('classes', out),
                                    ('exit_status', 0)])


def classify(facts):
    """Every class unit --list considers, and every category unit under
    sources/ whose file belongs to no class unit, with its path."""
    census = facts.census
    classes = sorted(c for c, fl in facts.impls.items() if any(
        f.startswith('sources/') and not census.is_generated(f) for f, _ in fl))
    covered = {}  # category file inside a class unit: that class
    for c in classes:
        try:
            impl = facts.unit(c)[0]
        except QualifyError:
            continue
        mains = set(f for f, _ in facts.impls[c])
        for f in impl:
            if f not in mains:
                covered.setdefault(f, c)
    cats = sorted(set('%s(%s)' % (c, cat) for c, cl in facts.categories.items() for cat, f in cl
                      if f.startswith('sources/') and not census.is_generated(f)
                      and not any(f == g for g, _ in facts.impls.get(c, ()))))
    sels = set()
    for c in classes:
        sels.update(sel for _, sel in census.class_methods(c))
    census.prepare_whole_tree(sels)
    facts.string_literals(classes)
    facts.type_index(classes)
    out = []
    seen_files = {}
    for name in classes + cats:
        try:
            ch = Checker(facts, name)
        except QualifyError:
            continue
        main = ch.impl[0] if ch.category else min(f for f, _ in facts.impls[ch.cls])
        if main in seen_files:
            # Another class of a file already classified: one unit per file.
            seen_files[main]['classes'].append(name)
            continue
        trivial = ch.trivial(stop=True)
        blocked = [t for t, c in trivial.items() if c.status != 'PASS']
        if blocked:
            fails = bool(ch.category) or any(x.status == 'FAIL' for x in ch.run(stop_on_fail=True).values())
            path = 'full' if fails else 'light'
        else:
            path = 'trivial'
        part_of = covered.get(main) if ch.category else None
        out.append(collections.OrderedDict([('unit', name), ('classes', [name]), ('file', main), ('path', path),
                                            ('part_of', part_of),
                                            ('body_lines', ch.body_lines), ('implementation_lines', ch.impl_lines),
                                            ('not_trivial_because', blocked[:1]),
                                            ('stop_status', trivial[blocked[0]].status if blocked else None)]))
        seen_files[main] = out[-1]
    def count(units):
        return collections.OrderedDict((p, sum(1 for u in units if u['path'] == p)) for p in ('trivial', 'light',
                                                                                              'full'))
    counts = count([u for u in out if not u['part_of']])
    split_counts = count([u for u in out if u['part_of']])
    out.sort(key=lambda u: (('trivial', 'light', 'full').index(u['path']), u['body_lines'] or 0,
                            u['implementation_lines'], u['unit']))
    return collections.OrderedDict([('units', sum(counts.values())), ('counts', counts),
                                    ('split_counts', split_counts),
                                    ('database_incomplete', database_incomplete(census)), ('classified', out),
                                    ('exit_status', 0)])


def write_classify(d, out):
    out.write('Paths of %d units under sources/ (lifecycle.md section 3): %s\n' % (
        d['units'], ', '.join('%s %d' % kv for kv in d['counts'].items())))
    out.write('Categories in files named for their class, which are part of the class\'s unit and may also move '
              'alone: %s\n' % ', '.join('%s %d' % kv for kv in d['split_counts'].items()))
    out.write('(light means no light condition FAILs; each MANUAL is still settled by reading)\n')
    for line in d['database_incomplete']:
        out.write(line + '\n')
    out.write('%-8s %5s %5s  %-50s  %-4s  %s\n' % ('path', 'body', 'lines', 'unit', 'stop', 'file'))
    for u in d['classified']:
        out.write('%-8s %5s %5d  %-50s  %-4s  %s\n' % (
            u['path'], '-' if u['body_lines'] is None else u['body_lines'], u['implementation_lines'],
            ', '.join(u['classes']) + (' (in %s\'s unit)' % u['part_of'] if u['part_of'] else ''),
            ','.join(u['not_trivial_because']) or '-', u['file']))


def write_conditions(conditions, out):
    for c in conditions:
        out.write('\n%-7s %-4s %s\n' % (c['status'], c['id'], c['condition']))
        for e in c['evidence']:
            out.write('             %s\n' % e)
        out.write('             how: %s\n' % c['how'])


def write_text(d, out):
    out.write('Qualifying checks (lifecycle.md section 3) for %s\n' % d['class'])
    out.write('Unit: %s (%d implementation lines, %s body lines)\n' % (
        ' '.join(d['unit_files']), d['implementation_lines'],
        'unmeasured' if d['body_lines'] is None else d['body_lines']))
    for line in d['database_incomplete']:
        out.write(line + '\n')
    out.write('\nTrivial path:\n')
    write_conditions(d['trivial_conditions'], out)
    if d['conditions']:
        out.write('\nLight path:\n')
        write_conditions(d['conditions'], out)
    else:
        out.write('\nLight path: not evaluated for a category unit (trivial or full).\n')
    fails = [c['id'] for c in d['conditions'] if c['status'] == 'FAIL']
    manual = [c['id'] for c in d['conditions'] if c['status'] == 'MANUAL']
    not_trivial = [c['id'] for c in d['trivial_conditions'] if c['status'] != 'PASS']
    out.write('\nPath: %s%s.\n' % (d['path'], ' (not trivial: %s)' % ', '.join(not_trivial) if not_trivial else ''))
    if d['conditions']:
        verdict = 'FAIL: ' + ', '.join(fails) if fails else 'no condition FAILs'
        out.write('Result: %s; MANUAL: %s. Exit %d.\n' % (verdict, ', '.join(manual) or 'none', d['exit_status']))
    else:
        out.write('Exit %d.\n' % d['exit_status'])


def write_list(d, out):
    out.write('Classes under sources/ that no automatic condition FAILs, by implementation size: %d of %d\n' % (
        d['qualifying'], d['considered']))
    out.write('(every one needs 5c, the callers\' thread, answered by a person; "manual" lists the other conditions '
              'a person must still read)\n')
    for line in d['database_incomplete']:
        out.write(line + '\n')
    out.write('%6s  %-5s  %-50s  %-8s  %s\n' % ('lines', 'users', 'class', 'manual', 'file'))
    for c in d['classes']:
        out.write('%6d  %-5d  %-50s  %-8s  %s\n' % (c['lines'], c['users'], c['class'], ','.join(c['manual']) or '-',
                                                    c['file']))


def build_parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--root', default=os.path.abspath(os.path.join(HERE, '..', '..')))
    for opt in ('--db', '--cdb', '--fragments', '--extractor', '--swift-work', '--swift-reader', '--registry',
                '--hot-paths'):
        p.add_argument(opt)
    p.add_argument('--json', action='store_true')
    p.add_argument('--clang', help='the clang for the AST checks (default: upstream clang 22, as unit_ast.py finds it)')
    p.add_argument('--list', action='store_true', help='every class under sources/ with no FAIL, by size')
    p.add_argument('--classify', action='store_true', help='the path of every unit under sources/')
    p.add_argument('--callers-thread', metavar='TEXT', help='a person\'s answer to condition 5c')
    p.add_argument('cls', metavar='CLASS', nargs='?')
    return p


def main(argv=None, out=None):
    out = out or sys.stdout
    args = build_parser().parse_args(sys.argv[1:] if argv is None else argv)
    if int(bool(args.list)) + int(bool(args.classify)) + int(bool(args.cls)) != 1:
        print('qualify_unit: error: give a CLASS, --list or --classify', file=sys.stderr)
        return 2
    try:
        paths = codedb.Paths(args.root, db=args.db, cdb=args.cdb, fragments=args.fragments, extractor=args.extractor,
                             swift_reader=args.swift_reader, swift_work=args.swift_work)
        census = ep.Census(paths, registry_path=args.registry)
        try:
            facts = Facts(census, args.hot_paths, clang=args.clang)
            if args.list:
                d = list_classes(facts)
            elif args.classify:
                d = classify(facts)
            else:
                d = qualify(facts, args.cls, args.callers_thread)
        finally:
            census.close()
    except (QualifyError, ep.CensusError, codedb.CodeDBError, sqlite3.Error, OSError) as e:
        print('qualify_unit: error: %s' % e, file=sys.stderr)
        return 2
    if args.json:
        json.dump(d, out, indent=1)
        out.write('\n')
    elif args.list:
        write_list(d, out)
    elif args.classify:
        write_classify(d, out)
    else:
        write_text(d, out)
    return d['exit_status']


if __name__ == '__main__':
    sys.exit(main())
