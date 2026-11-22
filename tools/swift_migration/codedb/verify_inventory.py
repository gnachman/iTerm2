#!/usr/bin/env python3
"""Compares the inventory's parsed view of the Objective-C classes with the
code database, and a runtime snapshot of classes with the code database.

codedb.py verifyinventory [--snapshot FILE] [--only-snapshot] [CLASS...]
runs this.

Inventory side. The inventory (tools/swift_migration/inventory.py) reads the
source text with its own parser, ObjCFile. This compares what ObjCFile finds
in every file of the inventory's scope (git ls-files of inventory.SCOPE_ROOTS,
less inventory.exclusion_reason, .m, .mm, .c and .h files) with what the
compiler recorded for the same files, class by class:

  class      a class with an @interface or @implementation (not a category)
             on one side only; its superclass where both record one and they
             differ
  protocol   the protocols an @interface, class extension or category lists
             (objc_adoption)
  ivar       ivars declared in an @interface, class extension or
             @implementation block (not those synthesized for a property,
             which the inventory does not see), by name and file; where both
             have it, where it is declared, and whether it is an array or a
             bit-field
  method     method definitions in @implementation and category
             @implementation blocks (not accessors the compiler
             synthesizes), by kind, selector and file
  property   property declarations of an @interface, class extension or
             category, by name, file and container; where both have it, the
             attributes (nullability left out: the database records the
             attributes as written but not nullability)

Classes and categories that ObjCFile names with a macro are resolved before
comparing: @implementation THE_CLASS (defined by the file that includes it,
as PTYWindow.m includes iTermWindowImpl.m four times) is read as each class
the database records in that file with that macro, and a category name that
is a macro is read as its definition when every definition is one identifier
and they agree (Profile for NSDictionary). The members of a resolved
container are compared like any other.

Each disagreement is printed with its kind (inventory only, database only,
differs: with both values) and, when a rule explains it, the rule:

  not parsed          the file is read by no unit of the database
  not compiled        the line is in a range every unit that reads the file
                      skips (an inactive #if branch); the inventory reads
                      text. Not applied to a line in any branch (#if, #elif,
                      #else) of a chain with a directive some unit reached
                      more than once with different values (a file included
                      several times, as iTermWindowImpl.m is): the database
                      does not record
                      which inclusion skipped it, so such a disagreement
                      stays unexplained, with a note on the next line
  class named by a macro
                      an item only ObjCFile finds, in a container whose class
                      or category name is a macro that could not be resolved
                      (no row of the database carries it, or its definitions
                      disagree); never an item only the database has, and
                      never another container of the same file
  made by a macro     the database row is in a macro expansion (its
                      selector spelled in the macro's body, pasted, or passed
                      as an argument to a macro that writes the method); the
                      inventory reads text and does not expand macros
  superclass          an @interface in code no unit compiles (the editor's
                      stub at the top of iTermWindowImpl.m) has no superclass
                      to compare

The rest are unexplained: a bug in the inventory's parser or in the database,
to be read. Classes are compared one at a time: a first pass parses every
file and keeps only which classes each file mentions; the second parses the
files of one class at a time (a few parsed files are cached) and queries the
database for that class alone, so memory stays bounded.

Runtime side (--snapshot FILE, a snapshot written by
tools/swift_migration/runtime_snapshot.sh, format 2 or 3; the ivar ownership
of format 3 is compared by ivar_ownership_check.py and codedb.py classstate
--snapshot, not here). For every class in it
(or those named), compares with the database:

  superclass  the snapshot's against objc_class
  ivars       name and type encoding against objc_ivar (with those
              synthesized for properties) and its type_encoding. The
              snapshot lists ivars sorted by name, with no offsets, so their
              order is not compared
  methods     class and instance methods, selector and type encoding,
              against the definitions in objc_method (synthesized accessors
              included) and the Swift members visible to Objective-C
              (swift_objc_decl)

Expected differences, listed but not failing: .cxx_destruct and
.cxx_construct (the compiler adds them for ivars that need destruction or
construction); a method whose image differs from the class's (a category in
another binary or a method a framework adds at run time); a method defined
in Swift (swift_objc_decl). Anything else fails. Classes the snapshot says
are defined in Swift, or whose language is unknown, are not compared.
Protocols and properties are not compared.

Exit status: 0 no unexplained disagreement; 1 unexplained disagreements; 3
none unexplained but the database is incomplete (the status block says why);
2 error (no database, an unreadable or malformed snapshot).
"""

import collections
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import inventory  # noqa: E402

KNOWN_ATTRIBUTES = frozenset(('class', 'direct', 'atomic', 'nonatomic', 'readonly', 'readwrite', 'assign', 'retain',
                              'copy', 'strong', 'weak', 'unsafe_unretained', 'null_resettable'))
NOT_PARSED, NOT_COMPILED, MACRO = 'not parsed', 'not compiled', 'made by a macro'
MACRO_CLASS = 'class named by a macro'
# Not a rule: a line skipped in some inclusions of its file within one unit
# and compiled in others (iTermWindowImpl.m, included four times by
# PTYWindow.m with ENABLE_COMPACT_WINDOW_HACK set differently). The database
# does not record which inclusion skipped it, so the disagreement stays
# unexplained, with this note.
PARTLY = 'partly compiled'
PARTLY_NOTE = ('    note: not explained: the line is skipped in some inclusions of its file and compiled in others, '
               'and the database does not record which inclusion defines this class')
PARSED_CACHE = 16
# Format 3 (what runtime_snapshot.sh writes today) adds ivar ownership and
# layout fields and class lines (ivar-arc-flag, the layouts,
# OWNERSHIP-CONFLICT) that this comparison does not read; ivar_ownership_check.py
# reads them.
SNAPSHOT_HEADERS = ('# Objective-C runtime snapshot, format 2', '# Objective-C runtime snapshot, format 3')


class SnapshotError(Exception):
    pass


# --- The inventory's view ------------------------------------------------------

def inventory_files(root):
    """The files the inventory parses: tracked under its scope roots, not
    excluded by inventory.exclusion_reason, with an implementation or header
    extension, present in the working tree."""
    text = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--'] + list(inventory.SCOPE_ROOTS),
                          capture_output=True, check=True).stdout.decode('utf-8', 'replace')
    out = []
    for path in text.split('\0'):
        if (path and inventory.exclusion_reason(path) is None
                and path.endswith(inventory.IMPL_EXTS + (inventory.HEADER_EXT,))
                and os.path.isfile(os.path.join(root, path))):
            out.append(path)
    return sorted(out)


def read_text(root, path):
    with open(os.path.join(root, path), 'rb') as f:
        return f.read().decode('utf-8', 'replace')


def container_label(cls, category):
    if category is None:
        return cls
    return '%s(%s)' % (cls, category)


def property_kind(category):
    return 'interface' if category is None else 'extension' if category == '' else 'category'


def normalized_attributes(attrs):
    """The attributes that both sides record, as a sorted tuple; getter= and
    setter= without spaces."""
    out = set()
    for a in attrs:
        a = ''.join(a.split())
        if a in KNOWN_ATTRIBUTES or a.startswith('getter=') or a.startswith('setter='):
            out.add(a)
    return tuple(sorted(out))


class InventoryClass:
    def __init__(self):
        self.interfaces = []   # (file, line, superclass)
        self.containers = {}    # (label, file) -> [lines], for every @interface/@implementation
        self.has_class = False
        self.protocols = {}     # (label, protocol) -> (file, line)
        self.ivars = {}         # (name, file) -> fact dict
        self.methods = {}       # (sign, selector, file) -> line
        self.properties = {}    # (name, file, label) -> (attributes, line)
        self.lines = {}         # file -> warnings


def inventory_class(files, parse, cls, aliases):
    """What ObjCFile finds about cls in files. A container that ObjCFile
    names with a macro is read as the class or category the database records
    for that macro in that file (aliases: Aliases)."""
    c = InventoryClass()

    def mine(path, name):
        return name == cls or cls in aliases.classes.get((path, name), ())

    def label_of(path, category):
        return container_label(cls, aliases.categories.get((path, category), category))
    for path in files:
        of = parse(path)
        for cont in of.containers:
            if cont['kind'] == 'protocol' or not mine(path, cont['name']):
                continue
            label = label_of(path, cont['category'])
            c.containers.setdefault((label, path), []).append(cont['line'])
            if cont['category'] is None:
                c.has_class = True
                if cont['kind'] == 'interface':
                    c.interfaces.append((path, cont['line'], cont['superclass']))
            if cont['kind'] == 'interface':
                for p in cont.get('protocols', []):
                    c.protocols.setdefault((label, p), (path, cont['line']))
        for iv in of.ivars:
            if mine(path, iv['class']):
                c.ivars[(iv['name'], path)] = iv
        for m in of.methods:
            if mine(path, m['class']):
                c.methods[(m['sign'], m['selector'], path)] = m['line']
        for p in of.properties:
            if mine(path, p['class']) and p['container_kind'] == 'interface':
                c.properties[(p['name'], path, label_of(path, p['category']))] = (
                    normalized_attributes(p['attributes']), p['line'], property_kind(p['category']))
        if of.warnings:
            c.lines[path] = of.warnings
    return c


class Aliases:
    """The classes and categories that ObjCFile names with a macro, resolved
    from the database where it can: classes, {(file, macro): [class]} from
    the objc_impl and objc_class rows recorded in that file with that macro
    (@implementation THE_CLASS, recorded under the class the macro expands
    to at that place); categories, {(file, macro): category} from the macro's
    definitions when every one is a single identifier and they agree (Profile
    for NSDictionary). unresolved: the (file, macro) pairs left, whose
    disagreements the rule "class named by a macro" explains."""

    def __init__(self, con, macro_containers):
        self.classes, self.categories, self.unresolved = {}, {}, set()
        for (path, name, is_category) in sorted(macro_containers):
            defined = con.execute('SELECT DISTINCT body FROM macro_def WHERE name = ?', (name,)).fetchall()
            if not defined:
                continue
            if not is_category:
                real = sorted(set(n for (n,) in con.execute(
                    'SELECT class_name FROM objc_impl WHERE file = ? AND macro_name = ? UNION SELECT name FROM '
                    'objc_class WHERE file = ? AND macro_name = ?', (path, name, path, name))))
                if real:
                    self.classes[(path, name)] = real
                else:
                    self.unresolved.add((path, name))
            else:
                bodies = set(b.strip() for (b,) in defined)
                if len(bodies) == 1 and bodies.copy().pop().isidentifier():
                    self.categories[(path, name)] = bodies.pop()
                else:
                    self.unresolved.add((path, name))

    def resolved_away(self, name, paths):
        """Whether every container named name in paths was resolved to the
        database's classes, so that name is not a class of its own."""
        return paths and all((p, name) in self.classes for p in paths)


INVENTORY_DECLARED = {'implementation block': 'implementation', 'class extension in a header': 'extension',
                      'class extension in the .m': 'extension', 'header @interface': 'interface',
                      '@interface in the .m': 'interface'}


# --- The database's view -------------------------------------------------------

class DatabaseClass:
    def __init__(self, con, cls, files):
        def keep(rows):
            return [r for r in rows if r[0] in files]
        self.interfaces = keep(con.execute('SELECT DISTINCT file, line, superclass FROM objc_class WHERE name = ?',
                                           (cls,)).fetchall())
        self.impls = keep(con.execute('SELECT DISTINCT file, line, category FROM objc_impl WHERE class_name = ?',
                                      (cls,)).fetchall())
        self.has_class = bool(self.interfaces) or any(c is None for _, _, c in self.impls)
        self.protocols = set()
        self.protocols_files = {}
        for f, label, proto in keep(con.execute(
                "SELECT DISTINCT file, class_or_category, protocol FROM objc_adoption WHERE container_kind != "
                "'protocol' AND (class_or_category = ? OR substr(class_or_category, 1, length(?) + 1) = ? || '(')",
                (cls, cls, cls)).fetchall()):
            self.protocols.add((label, proto))
            self.protocols_files.setdefault((label, proto), f)
        self.ivars = {}
        for f, name, kind, tclass, line in keep(con.execute(
                'SELECT DISTINCT file, name, container_kind, type_class, line FROM objc_ivar WHERE class_name = ? AND '
                'synthesized_by IS NULL', (cls,)).fetchall()):
            self.ivars[(name, f)] = (kind, tclass, line)
        self.methods = {}
        for f, is_class, sel, line, role, macro in keep(con.execute(
                "SELECT DISTINCT file, is_class_method, selector, line, macro_role, macro_name FROM objc_method WHERE "
                "class_name = ? AND is_definition = 1 AND is_implicit = 0 AND is_synthesized_accessor = 0 AND "
                "container_kind IN ('implementation', 'category-implementation')", (cls,)).fetchall()):
            self.methods[('+' if is_class else '-', sel, f)] = (line, role, macro)
        self.properties = {}
        for f, name, label, kind, attrs, line in keep(con.execute(
                "SELECT DISTINCT file, name, container_name, container_kind, attributes, line FROM objc_property WHERE "
                "class_name = ? AND kind = 'declaration' AND container_kind IN ('interface', 'extension', 'category')",
                (cls,)).fetchall()):
            self.properties[(name, f, label)] = (normalized_attributes((attrs or '').split(',')), line, kind)


# --- Comparing -----------------------------------------------------------------

class Report:
    def __init__(self, out):
        self.out = out
        self.counts = collections.Counter()
        self.explained = collections.Counter()
        self.unexplained = 0
        self.current = None

    def add(self, cls, kind, text, rule=None):
        if self.current != cls:
            self.out.write('%s\n' % cls)
            self.current = cls
        self.counts[kind] += 1
        if rule == PARTLY:
            self.unexplained += 1
            self.out.write('  %s: %s\n%s\n' % (kind, text, PARTLY_NOTE))
            return
        if rule:
            self.explained[kind] += 1
        else:
            self.unexplained += 1
        self.out.write('  %s: %s%s\n' % (kind, text, '  [explained: %s]' % rule if rule else ''))


class Explainer:
    """The rules that explain a disagreement."""

    def __init__(self, codedb, q, aliases):
        self.con = q.con
        self.skipped = codedb.skipped_everywhere(q)
        self._read = {}
        self.aliases = aliases
        # The chains (keyed by the line of their #if) with a directive that
        # units reached more than once with different values (pp_condition
        # lists each value, joined with commas): every branch of such a
        # chain, #if, #elif and #else, is skipped in some inclusions only.
        self.mixed = set((f, chain) for f, chain in self.con.execute(
            "SELECT DISTINCT file, chain_line FROM pp_condition WHERE value LIKE '%,%'"))

    def parsed(self, path):
        if path not in self._read:
            self._read[path] = self.con.execute('SELECT 1 FROM tu_input WHERE path = ? LIMIT 1',
                                                (path,)).fetchone() is not None
        return self._read[path]

    def inventory_only(self, path, line, words=()):
        """The rule for an item only ObjCFile finds at path:line, in a
        container named with words (the class and category names ObjCFile
        read)."""
        if not self.parsed(path):
            return NOT_PARSED
        for start, end in self.skipped.get(path, ()):
            if line is not None and start <= line <= end:
                chains = [r[0] for r in self.con.execute(
                    'SELECT DISTINCT chain_line FROM pp_skipped WHERE file = ? AND start_line <= ? AND end_line >= ?',
                    (path, line, line))]
                if any((path, chain) in self.mixed for chain in chains):
                    return PARTLY
                return NOT_COMPILED
        if any((path, w) in self.aliases.unresolved for w in words if w):
            return MACRO_CLASS
        return None


def label_words(label):
    """The class and category names in a container label, Cls(Cat)."""
    cls, _, rest = label.partition('(')
    return (cls, rest[:-1]) if rest else (cls,)


def compare_class(cls, inv, db, explain, report):
    if inv.has_class and not db.has_class:
        where = sorted((f, line) for (label, f), lines in inv.containers.items() if label == cls for line in lines)
        files = sorted(set(f for f, _ in where))
        rules = set(explain.inventory_only(f, line, (cls,)) for f, line in where)
        report.add(cls, 'class inventory only', 'declared or implemented in %s' % ', '.join(files),
                   rules.pop() if len(rules) == 1 else None)
    elif db.has_class and not inv.has_class:
        files = sorted(set(f for f, _, _ in db.interfaces) | set(f for f, _, c in db.impls if c is None))
        report.add(cls, 'class database only', 'declared or implemented in %s' % ', '.join(files))
    # An @interface in code no unit compiles (#ifndef THE_CLASS, as in
    # iTermWindowImpl.m) has no superclass to compare.
    inv_supers = set(s for path, line, s in inv.interfaces if explain.inventory_only(path, line) is None)
    db_supers = set(s for _, _, s in db.interfaces)
    if inv_supers and db.interfaces and inv_supers != db_supers:
        report.add(cls, 'superclass differs', 'inventory %s, database %s' % (
            ', '.join(sorted(str(s) for s in inv_supers)), ', '.join(sorted(str(s) for s in db_supers))))
    for label, proto in sorted(set(inv.protocols) - db.protocols):
        path, line = inv.protocols[(label, proto)]
        report.add(cls, 'protocol inventory only', '%s lists %s in %s:%s' % (label, proto, path, line),
                   explain.inventory_only(path, line, label_words(label)))
    for label, proto in sorted(db.protocols - set(inv.protocols)):
        report.add(cls, 'protocol database only', '%s lists %s' % (label, proto))
    for key in sorted(set(inv.ivars) - set(db.ivars)):
        iv = inv.ivars[key]
        report.add(cls, 'ivar inventory only', '%s in %s:%s (%s)' % (key[0], key[1], iv['line'], iv['declared']),
                   explain.inventory_only(key[1], iv['line'], (cls, iv['class'])))
    for key in sorted(set(db.ivars) - set(inv.ivars)):
        kind, _, line = db.ivars[key]
        report.add(cls, 'ivar database only', '%s in %s:%s (%s)' % (key[0], key[1], line, kind))
    for key in sorted(set(db.ivars) & set(inv.ivars)):
        iv, (kind, tclass, line) = inv.ivars[key], db.ivars[key]
        declared = INVENTORY_DECLARED.get(iv['declared'], iv['declared'])
        if declared != kind:
            report.add(cls, 'ivar differs', '%s in %s:%s: declared in inventory %s, database %s' % (
                key[0], key[1], line, declared, kind))
        if bool(iv['array']) != (tclass == 'array'):
            report.add(cls, 'ivar differs', '%s in %s:%s: array: inventory %s, database type class %s' % (
                key[0], key[1], line, iv['array'] or 'no', tclass))
        if bool(iv['bitfield']) != (tclass == 'bit-field'):
            report.add(cls, 'ivar differs', '%s in %s:%s: bit-field: inventory %s, database type class %s' % (
                key[0], key[1], line, iv['bitfield'] or 'no', tclass))
    for key in sorted(set(inv.methods) - set(db.methods)):
        report.add(cls, 'method inventory only', '%s[%s %s] in %s:%s' % (key[0], cls, key[1], key[2],
                                                                         inv.methods[key]),
                   explain.inventory_only(key[2], inv.methods[key], (cls,)))
    for key in sorted(set(db.methods) - set(inv.methods)):
        line, role, macro = db.methods[key]
        report.add(cls, 'method database only', '%s[%s %s] in %s:%s%s' % (
            key[0], cls, key[1], key[2], line, ' (macro %s, %s)' % (macro, role) if macro else ''),
            MACRO if macro else None)
    for key in sorted(set(inv.properties) - set(db.properties)):
        attrs, line, _ = inv.properties[key]
        report.add(cls, 'property inventory only', '%s of %s in %s:%s' % (key[0], key[2], key[1], line),
                   explain.inventory_only(key[1], line, label_words(key[2])))
    for key in sorted(set(db.properties) - set(inv.properties)):
        attrs, line, _ = db.properties[key]
        report.add(cls, 'property database only', '%s of %s in %s:%s' % (key[0], key[2], key[1], line))
    for key in sorted(set(db.properties) & set(inv.properties)):
        if inv.properties[key][0] != db.properties[key][0]:
            report.add(cls, 'property differs', '%s of %s in %s:%s: attributes inventory (%s), database (%s)' % (
                key[0], key[2], key[1], db.properties[key][1], ','.join(inv.properties[key][0]),
                ','.join(db.properties[key][0])))


def class_index(root, files):
    """{class: [files]} from a first pass that keeps only the names."""
    index = collections.defaultdict(list)
    containers = set()
    warnings = 0
    for path in files:
        of = inventory.ObjCFile(path, read_text(root, path))
        for c in of.containers:
            if c['kind'] != 'protocol':
                containers.add((path, c['name'], False))
                if c['category']:
                    containers.add((path, c['category'], True))
        names = set(c['name'] for c in of.containers if c['kind'] != 'protocol')
        names |= set(iv['class'] for iv in of.ivars) | set(m['class'] for m in of.methods)
        names |= set(p['class'] for p in of.properties if p['container_kind'] == 'interface')
        warnings += len(of.warnings)
        for n in names:
            index[n].append(path)
    return index, containers, warnings


def database_classes(con, files):
    """The classes the database has rows of in these files (a set of names)."""
    names = set()
    for sql in ('SELECT DISTINCT name, file FROM objc_class', 'SELECT DISTINCT class_name, file FROM objc_impl',
                "SELECT DISTINCT class_name, file FROM objc_property WHERE kind = 'declaration' AND class_name IS "
                "NOT NULL", 'SELECT DISTINCT class_name, file FROM objc_ivar'):
        for name, f in con.execute(sql):
            if f in files:
                names.add(name)
    return names


def verify_inventory_side(codedb, q, root, classes, out):
    report = Report(out)
    files = inventory_files(root)
    file_set = set(files)
    index, containers, warnings = class_index(root, files)
    names = sorted(set(classes)) if classes else sorted(set(index) | database_classes(q.con, file_set))
    aliases = Aliases(q.con, set(c for c in containers if q.con.execute(
        'SELECT 1 FROM macro_def WHERE name = ? LIMIT 1', (c[1],)).fetchone()))
    for (path, macro), real in aliases.classes.items():
        for r in real:
            if path not in index[r]:
                index[r].append(path)
    explain = Explainer(codedb, q, aliases)
    cache = collections.OrderedDict()

    def parse(path):
        if path in cache:
            cache.move_to_end(path)
            return cache[path]
        of = inventory.ObjCFile(path, read_text(root, path))
        cache[path] = of
        while len(cache) > PARSED_CACHE:
            cache.popitem(last=False)
        return of
    names = [n for n in names if not aliases.resolved_away(n, index.get(n, []))]
    for cls in names:
        inv = inventory_class(index.get(cls, []), parse, cls, aliases)
        db = DatabaseClass(q.con, cls, file_set)
        compare_class(cls, inv, db, explain, report)
    out.write('\nInventory against the database: %d classes compared, %d files parsed (the inventory\'s parser warned '
              '%d times)\n' % (len(names), len(files), warnings))
    for kind in sorted(report.counts):
        out.write('  %s: %d (explained %d)\n' % (kind, report.counts[kind], report.explained[kind]))
    out.write('  unexplained: %d\n' % report.unexplained)
    return report.unexplained


# --- The runtime snapshot ------------------------------------------------------

def unescape(text):
    """RuntimeSnapshotFormat.escape reversed: %XX is the byte XX."""
    if '%' not in text:
        return text
    data = bytearray()
    i = 0
    raw = text.encode('ascii', 'strict')
    while i < len(raw):
        if raw[i:i + 1] == b'%' and len(raw) >= i + 3:
            data += bytes([int(raw[i + 1:i + 3], 16)])
            i += 3
        else:
            data += raw[i:i + 1]
            i += 1
    return data.decode('utf-8', 'replace')


def read_snapshot(path, wanted=None):
    """Yields (header, class dict) for each class section of a snapshot
    file, read line by line."""
    header = {}
    cls = None
    with open(path, encoding='ascii', errors='strict') as f:
        first = f.readline().rstrip('\n')
        if first not in SNAPSHOT_HEADERS:
            raise SnapshotError('%s: not a format 2 or 3 runtime snapshot (first line %r)' % (path, first))
        for n, line in enumerate(f, 2):
            line = line.rstrip('\n')
            if not line.startswith('  '):
                words = line.split(' ')
                if words[0] in ('architecture', 'build-configuration', 'build-variant'):
                    header[words[0]] = ' '.join(words[1:])
                elif words[0] == 'class' and len(words) == 2:
                    cls = {'name': unescape(words[1]), 'ivars': {}, 'methods': {}, 'language': None,
                           'superclass': None, 'image': None, 'duplicates': []}
                elif words[0] == 'end' and cls is not None:
                    if wanted is None or cls['name'] in wanted:
                        yield header, cls
                    cls = None
                else:
                    raise SnapshotError('%s:%d: unexpected line %r' % (path, n, line))
                continue
            if cls is None:
                raise SnapshotError('%s:%d: a class line outside a class section' % (path, n))
            words = line[2:].split(' ')
            key = words[0]
            fields = dict(w.split('=', 1) for w in words[2:] if '=' in w)
            if key == 'ivar':
                cls['ivars'][unescape(words[1])] = unescape(fields.get('types', ''))
            elif key in ('class-method', 'instance-method'):
                sel = unescape(words[1])
                cls['methods'][(sel[0], sel[1:])] = {'types': unescape(fields.get('types', '')),
                                                     'image': unescape(fields['image']) if 'image' in fields else None}
            elif key in ('language', 'superclass', 'image'):
                cls[key] = unescape(' '.join(words[1:])) if len(words) > 1 else ''
            elif key == 'DUPLICATE':
                cls['duplicates'].append(' '.join(words[1:]))
    if cls is not None:
        raise SnapshotError('%s: the last class section has no end line' % path)


def database_runtime_view(con, cls):
    ivars = collections.defaultdict(set)
    for name, enc in con.execute('SELECT DISTINCT name, type_encoding FROM objc_ivar WHERE class_name = ?', (cls,)):
        # The extractor stores an empty encoding (a vector's) as NULL; the
        # snapshot writes it as types= with nothing after.
        ivars[name].add(enc or '')
    methods = collections.defaultdict(set)
    for is_class, sel, enc in con.execute(
            "SELECT DISTINCT is_class_method, selector, type_encoding FROM objc_method WHERE class_name = ? AND "
            "(is_definition = 1 OR is_synthesized_accessor = 1) AND container_kind IN ('implementation', "
            "'category-implementation')", (cls,)):
        methods[('+' if is_class else '-', sel)].add(enc or '')
    swift = set()
    if 'swift_objc_decl' in set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")):
        for is_class, sel in con.execute('SELECT DISTINCT is_class_member, selector FROM swift_objc_decl WHERE '
                                         'class_name = ? AND selector IS NOT NULL', (cls,)):
            swift.add(('+' if is_class else '-', sel))
    supers = set(s for (s,) in con.execute('SELECT DISTINCT superclass FROM objc_class WHERE name = ?', (cls,)))
    return ivars, methods, swift, supers


def compare_snapshot_class(con, snap, report):
    cls = snap['name']
    if snap['language'] != 'objc':
        report.add(cls, 'runtime not compared', 'the snapshot says the class is defined in %s' % (
            snap['language'] or 'an unknown language'), 'not an Objective-C class')
        return
    ivars, methods, swift, supers = database_runtime_view(con, cls)
    if not ivars and not methods and not supers:
        report.add(cls, 'runtime class not in database', 'no objc_class, objc_ivar or objc_method row')
        return
    if supers and snap['superclass'] not in supers:
        report.add(cls, 'runtime superclass differs', 'runtime %s, database %s' % (
            snap['superclass'] or '(root)', ', '.join(sorted(str(s) for s in supers))))
    for name in sorted(set(snap['ivars']) - set(ivars)):
        report.add(cls, 'runtime ivar runtime only', '%s types=%s' % (name, snap['ivars'][name]))
    for name in sorted(set(ivars) - set(snap['ivars'])):
        report.add(cls, 'runtime ivar database only', name)
    for name in sorted(set(ivars) & set(snap['ivars'])):
        if snap['ivars'][name] not in ivars[name]:
            report.add(cls, 'runtime ivar encoding differs', '%s: runtime %s, database %s' % (
                name, snap['ivars'][name], ', '.join(sorted(str(e) for e in ivars[name]))))
    for key in sorted(set(snap['methods']) - set(methods)):
        m = snap['methods'][key]
        rule = None
        if key[1] in ('.cxx_destruct', '.cxx_construct'):
            rule = 'synthesized by the compiler'
        elif m['image'] is not None and m['image'] != snap['image']:
            rule = 'implemented in another image (%s)' % (m['image'] or 'none')
        elif key in swift:
            rule = 'defined in Swift'
        report.add(cls, 'runtime method runtime only', '%s[%s %s] types=%s' % (key[0], cls, key[1], m['types']), rule)
    for key in sorted(set(methods) - set(snap['methods'])):
        report.add(cls, 'runtime method database only', '%s[%s %s]' % (key[0], cls, key[1]))
    for key in sorted(set(methods) & set(snap['methods'])):
        enc = snap['methods'][key]['types']
        if enc not in methods[key]:
            report.add(cls, 'runtime method encoding differs', '%s[%s %s]: runtime %s, database %s' % (
                key[0], cls, key[1], enc, ', '.join(sorted(str(e) for e in methods[key]))))


def verify_snapshot_side(q, snapshot, classes, out):
    report = Report(out)
    header = {}
    compared = 0
    for header, snap in read_snapshot(snapshot, set(classes) if classes else None):
        compared += 1
        compare_snapshot_class(q.con, snap, report)
    out.write('\nRuntime snapshot against the database: %d classes (%s)\n' % (compared, ', '.join(
        '%s %s' % kv for kv in sorted(header.items())) or 'no header'))
    out.write('  not compared: protocols, properties, the order and offsets of ivars (the snapshot lists ivars sorted '
              'by name, without offsets); a snapshot older than the sources differs where they changed since\n')
    for kind in sorted(report.counts):
        out.write('  %s: %d (explained %d)\n' % (kind, report.counts[kind], report.explained[kind]))
    out.write('  unexplained: %d\n' % report.unexplained)
    return report.unexplained


def verifyinventory(codedb, paths, classes=(), snapshot=None, only_snapshot=False, out=None):
    out = out or sys.stdout
    spec = codedb.QuerySpec('verifyinventory', codedb.NOT_IN_DATABASE_COMMON,
                            'exit status: 0 no unexplained disagreement, 1 unexplained disagreements, 3 none '
                            'unexplained but the database is incomplete, 2 error', None, True)
    q = codedb.QueryContext(paths, spec)
    try:
        unexplained = 0
        if not only_snapshot:
            unexplained += verify_inventory_side(codedb, q, paths.root, classes, out)
        if snapshot:
            try:
                unexplained += verify_snapshot_side(q, snapshot, classes, out)
            except (SnapshotError, UnicodeDecodeError) as e:
                raise codedb.CodeDBError('cannot read the snapshot: %s' % e)
        for line in q.incomplete_lines():
            out.write(line + '\n')
        if unexplained:
            return 1
        return 3 if q.incomplete() else 0
    finally:
        q.close()
