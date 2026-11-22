#!/usr/bin/env python3
"""Cross-checks the ivar ownership in a runtime snapshot against the compiler.

Usage:
  tools/swift_migration/ivar_ownership_check.py [--db PATH] SNAPSHOT

SNAPSHOT is a file written by tools/swift_migration/runtime_snapshot.sh. Its
ivar lines carry the ownership the Objective-C runtime's ivar layouts give
each ivar (ModernTests/RuntimeSnapshotIvarOwnership.swift describes the
labels). The code database (tools/swift_migration/codedb/, default
tmp/codedb/codedb.sqlite) holds what the compiler knew about each ivar: its
type, type class and ownership qualifier, and the ARC mode of the unit that
compiles the class's @implementation. This tool prints both for every ivar
of every Objective-C class in the snapshot, and:

- reports DISAGREES where the two contradict each other: a runtime layout
  that says strong where the compiler says weak or unretained, a class whose
  runtime ARC flag differs from the compiler's ARC mode, and so on. A
  disagreement is either a bug in the snapshot tool or a real surprise; it
  makes the exit status 1.
- where the runtime cannot answer (labels such as unretained-or-manual,
  manual, struct-or-cxx-object, unknown-type), prints the compiler's answer,
  labeled as coming from the compiler. That answer is about the declaration:
  for a class compiled without ARC, ownership is whatever its code does by
  hand, which neither source records (codedb.py ivars gives a retain hint
  from the code).

What it uses from the database: objc_impl and tu for the class's
@implementation (not a category's) and the ARC mode of its unit, and the rows
of objc_ivar for the class recorded by units of that mode (the extractor
records a header's ivars once per mode, not once per unit).
It reads those tables directly rather than through codedb.py ivars, whose
"incomplete" exit status counts text matches of the ivars' names in code no
unit compiles (common words such as data or key make nearly every class
"incomplete"), and which takes many seconds per class. The database records
the tree as it was when it was last updated, which may be older than the
build the snapshot came from; each class's line says when its units were
extracted, and a WARNING line (which does not change the exit status) names
each file of the class, its @implementation and the files that declare its
ivars, changed after that time (--root names the checkout the database's
paths are relative to; the default is this one). A class with no @implementation in the database (a Swift class, a
class from a system framework, or one made at run time) gets no compiler
answer, which is reported as unknown, not as a disagreement.

Exit status: 0 when nothing disagrees; 1 when something does; 2 on bad
arguments, an unreadable snapshot, or a database that cannot be read, has a
schema older than 11, or lacks a column the tool reads.
"""

import argparse
import datetime
import os
import re
import sqlite3
import sys
from collections import OrderedDict

# The oldest schema of the code database whose tables hold the columns this
# tool reads (REQUIRED_COLUMNS). A later schema is read when it still has
# them: codedb.py raises its version for changes elsewhere (schema 12 added
# columns this tool does not read), and a fixed version made the tool refuse
# every current database.
OLDEST_SCHEMA = 11
REQUIRED_COLUMNS = {
    'tu': ('id', 'main_file', 'extracted_at'),
    'objc_impl': ('tu', 'class_name', 'category', 'arc', 'file'),
    'objc_ivar': ('tu', 'class_name', 'name', 'type', 'type_class', 'ownership', 'arc', 'record_has_objects', 'file'),
}

# What the runtime label can tell, and what it cannot.
RUNTIME_SAYS = {
    'strong': 'strong (runtime layout)',
    'weak': 'weak (runtime layout)',
    'unretained-or-manual': 'in neither layout of an ARC class: unretained, or retained by hand (runtime cannot tell)',
    'manual': 'class not compiled with ARC: managed by hand, not in the runtime',
    'unretained-or-unknown': 'in neither layout, ARC flag unknown: unretained or unknown',
    'arc-members': 'holds ARC references in the words the layout marks',
    'cxx-object': 'a C++ object: its destructor runs when the instance is destroyed; what its elements own depends on their types',
    'struct-or-cxx-object': 'a C++ object whose destructor runs when the instance is destroyed, or a C struct with no ARC references (runtime cannot tell)',
    'struct-no-destructor': 'no ARC references and no destructor',
    'struct-unknown': 'struct, ARC flag unknown',
    'c-pointer': 'C pointer: not an ARC reference; ownership of the pointee not in the runtime',
    'scalar': 'no ownership',
    'selector': 'no ownership',
    'bitfield': 'no ownership',
    'unaligned-object': 'object pointer the layouts cannot describe: unknown',
    'unknown-type': 'unknown type: unknown',
    'swift': 'Swift class: ownership from the Swift declaration, not the runtime',
}

OBJECT_CLASSES = ('object', 'block')
NON_OBJECT_CLASSES = ('scalar', 'selector', 'bit-field', 'atomic', 'vector', 'c-pointer', 'other')
AGGREGATE_CLASSES = ('struct', 'union', 'array', 'cxx-object')


def unescape(text):
    """Undoes RuntimeSnapshotFormat.escape: %XX is one byte."""
    data = bytearray()
    i = 0
    raw = text.encode('ascii')
    while i < len(raw):
        if raw[i:i + 1] == b'%' and i + 2 < len(raw) and re.match(rb'[0-9A-F]{2}', raw[i + 1:i + 3]):
            data.append(int(raw[i + 1:i + 3], 16))
            i += 3
        else:
            data.append(raw[i])
            i += 1
    return data.decode('utf-8')


def parse_snapshot(text):
    """{class name: {'language', 'arc_flag', 'ivars': OrderedDict(name:
    {'types', 'ownership', 'layout'}), 'conflicts': [...]}}. Raises
    ValueError for text that is not a runtime snapshot with ivar
    ownership."""
    lines = text.split('\n')
    if not lines or lines[0] != '# Objective-C runtime snapshot, format 3':
        raise ValueError('not a runtime snapshot in format 3 (the format with ivar ownership)')
    classes = OrderedDict()
    current = None
    for number, line in enumerate(lines[1:], start=2):
        if line.startswith('class '):
            current = {'language': None, 'arc_flag': None, 'ivars': OrderedDict(), 'conflicts': []}
            classes[unescape(line[len('class '):])] = current
        elif line.startswith('end class '):
            current = None
        elif line.startswith('  ') and current is not None:
            fields = line[2:].split(' ')
            if fields[0] == 'language' and len(fields) == 2:
                current['language'] = fields[1]
            elif fields[0] == 'ivar-arc-flag' and len(fields) == 2:
                current['arc_flag'] = fields[1]
            elif fields[0] == 'OWNERSHIP-CONFLICT':
                current['conflicts'].append(' '.join(fields[1:]))
            elif fields[0] == 'ivar':
                values = dict(f.split('=', 1) for f in fields[2:] if '=' in f)
                if 'ownership' not in values or 'layout' not in values:
                    raise ValueError('line %d: an ivar line without ownership= and layout=' % number)
                current['ivars'][unescape(fields[1])] = {'types': unescape(values.get('types', '')),
                                                         'ownership': values['ownership'],
                                                         'layout': values['layout']}
    if not classes:
        raise ValueError('the snapshot holds no classes')
    return classes


def compiler_facts(con, class_name):
    """The compiler's facts for a class: {'impls': [(file, arc, extracted_at)],
    'ivars': {name: set of (type, type_class, ownership, arc,
    record_has_objects)}}."""
    impls = con.execute(
        'SELECT DISTINCT i.file, i.arc, t.extracted_at, i.tu FROM objc_impl i JOIN tu t ON t.id = i.tu '
        'WHERE i.class_name = ? AND i.category IS NULL ORDER BY i.file, t.extracted_at', (class_name,)).fetchall()
    # The extractor records a header's declarations once for each way units
    # see it, not once per unit, so an ivar declared in a header has rows
    # from some unit of each ARC mode, not necessarily from the unit of the
    # @implementation. The rows of the @implementation's mode govern.
    modes = sorted(set(r[1] for r in impls))
    ivars = OrderedDict()
    if modes:
        rows = con.execute(
            'SELECT name, type, type_class, ownership, arc, record_has_objects FROM objc_ivar '
            'WHERE class_name = ? AND arc IN (%s) ORDER BY name' % ','.join('?' * len(modes)),
            [class_name] + modes).fetchall()
        for name, typ, type_class, ownership, arc, has_objects in rows:
            ivars.setdefault(name, set()).add((typ, type_class, ownership, arc, has_objects or 0))
    files = set(f for f, _, _, _ in impls)
    if modes:
        files.update(f for (f,) in con.execute(
            'SELECT DISTINCT file FROM objc_ivar WHERE class_name = ? AND arc IN (%s)' % ','.join('?' * len(modes)),
            [class_name] + modes))
    return {'impls': [(f, a, e) for f, a, e, _ in impls], 'ivars': ivars, 'files': sorted(f for f in files if f)}


def parse_time(text):
    """Seconds since the epoch for an extraction time such as
    2026-11-20T12:00:00Z (UTC), or None if it cannot be read."""
    try:
        return datetime.datetime.strptime(text.rstrip('Z'), '%Y-%m-%dT%H:%M:%S').replace(
            tzinfo=datetime.timezone.utc).timestamp()
    except (ValueError, AttributeError):
        return None


def stale_files(root, files, extracted_at):
    """The files (paths relative to root) changed after the earliest
    extraction time of the class's units."""
    times = [t for t in (parse_time(e) for e in extracted_at) if t is not None]
    if not times:
        return []
    earliest = min(times)
    result = []
    for name in files:
        path = name if os.path.isabs(name) else os.path.join(root, name)
        try:
            if os.path.getmtime(path) > earliest:
                result.append(name)
        except OSError:
            continue
    return result


def judge(label, facts):
    """(verdict, text) for one ivar: verdict is 'agrees', 'DISAGREES', or
    'compiler' (the runtime cannot answer; the compiler's answer is given).
    facts is a set of (type, type_class, ownership, arc, has_objects)."""
    if len(facts) != 1:
        return 'compiler', 'the database has %d different answers: %s' % (
            len(facts), '; '.join(describe(f) for f in sorted(facts, key=str)))
    fact = next(iter(facts))
    _, type_class, ownership, arc, has_objects = fact
    text = describe(fact)

    def agree_if(condition):
        return ('agrees' if condition else 'DISAGREES'), text

    if label == 'strong':
        return agree_if(ownership == 'strong')
    if label == 'weak':
        return agree_if(ownership == 'weak')
    if label == 'unretained-or-manual':
        if ownership in ('strong', 'weak') or arc == 0:
            return 'DISAGREES', text
        return 'compiler', text
    if label == 'manual':
        return ('compiler', text) if arc == 0 else ('DISAGREES', text + ', but the runtime says the class is not compiled with ARC')
    if label == 'arc-members':
        return agree_if(has_objects == 1 or (type_class == 'array' and ownership in ('strong', 'weak')))
    if label == 'cxx-object':
        return agree_if(type_class == 'cxx-object')
    if label in ('struct-or-cxx-object', 'struct-no-destructor', 'struct-unknown'):
        if type_class not in AGGREGATE_CLASSES:
            return 'DISAGREES', text
        if type_class == 'array' and ownership in ('strong', 'weak'):
            return 'DISAGREES', text + ', which the layout would list'
        return 'compiler', text
    if label in ('c-pointer', 'scalar', 'selector', 'bitfield'):
        return agree_if(type_class in NON_OBJECT_CLASSES)
    return 'compiler', text


def describe(fact):
    typ, type_class, ownership, arc, has_objects = fact
    parts = [type_class]
    if type_class in AGGREGATE_CLASSES and type_class != 'array':
        parts.append('holds object pointers' if has_objects else 'holds no object pointers')
        if type_class == 'cxx-object':
            parts.append('its destructor runs when the instance is destroyed')
    if ownership != 'none':
        parts.append(ownership)
    parts.append('ARC' if arc else 'manual reference counting')
    return 'compiler: %s (%s)' % (typ, ', '.join(parts))


def check(snapshot, con, out, root='.'):
    """Writes the report and returns the number of disagreements."""
    disagreements = 0
    for class_name, cls in snapshot.items():
        if cls['language'] == 'swift':
            out.write('class %s: a Swift class; ownership comes from the Swift declarations, which this database '
                      'does not hold for stored properties\n' % class_name)
            continue
        facts = compiler_facts(con, class_name)
        if not facts['impls']:
            out.write('class %s: no @implementation in the database, so no compiler answer (unknown)\n' % class_name)
            for name, ivar in cls['ivars'].items():
                out.write('  %s  runtime: %s  [%s]\n' % (name, ivar['ownership'], RUNTIME_SAYS.get(ivar['ownership'], '')))
            continue
        modes = sorted(set(a for _, a, _ in facts['impls']))
        where = ', '.join('%s (%s, extracted %s)' % (f, 'ARC' if a else 'manual reference counting', e)
                          for f, a, e in facts['impls'])
        out.write('class %s: implemented in %s; runtime ARC flag %s\n' % (class_name, where, cls['arc_flag']))
        extracted = [e for _, _, e in facts['impls']]
        for name in stale_files(root, facts['files'], extracted):
            out.write('  WARNING: %s changed after its unit was extracted (%s); the compiler answers may be stale\n' % (
                name, min(extracted)))
        expected_flag = {(1,): 'set', (0,): 'clear'}.get(tuple(modes))
        if cls['arc_flag'] in ('set', 'clear') and expected_flag and cls['arc_flag'] != expected_flag:
            disagreements += 1
            out.write('  DISAGREES: the runtime ARC flag is %s, but the compiler compiled the @implementation %s\n' % (
                cls['arc_flag'], 'with ARC' if modes == [1] else 'without ARC'))
        for conflict in cls['conflicts']:
            disagreements += 1
            out.write('  DISAGREES: the snapshot reports OWNERSHIP-CONFLICT %s\n' % conflict)
        for name, ivar in cls['ivars'].items():
            label = ivar['ownership']
            runtime = 'runtime: %s%s  [%s]' % (label, (' layout=' + ivar['layout']) if ivar['layout'] else '',
                                              RUNTIME_SAYS.get(label, ''))
            if name not in facts['ivars']:
                out.write('  %s  %s  compiler: no row for this ivar (unknown)\n' % (name, runtime))
                continue
            verdict, text = judge(label, facts['ivars'][name])
            if verdict == 'DISAGREES':
                disagreements += 1
            out.write('  %s  %s  %s  %s\n' % (name, runtime, text, verdict))
        missing = [n for n in facts['ivars'] if n not in cls['ivars']]
        for name in missing:
            out.write('  %s  not in the runtime snapshot; the database has: %s (a conditional ivar, or a database '
                      'older than the build)\n' % (name, '; '.join(describe(f) for f in sorted(facts['ivars'][name], key=str))))
    out.write('%d disagreement%s\n' % (disagreements, '' if disagreements == 1 else 's'))
    return disagreements


def open_database(path):
    if not os.path.exists(path):
        raise ValueError('no database at %s' % path)
    con = sqlite3.connect('file:%s?mode=ro' % path, uri=True)
    version = con.execute('PRAGMA user_version').fetchone()[0]
    if version < OLDEST_SCHEMA:
        con.close()
        raise ValueError('the database at %s has schema %d; this tool reads schema %d or later' % (
            path, version, OLDEST_SCHEMA))
    for table, columns in REQUIRED_COLUMNS.items():
        have = set(r[1] for r in con.execute('PRAGMA table_info(%s)' % table))
        missing = [c for c in columns if c not in have]
        if missing:
            con.close()
            raise ValueError('the database at %s (schema %d) has no column %s in table %s, which this tool reads' % (
                path, version, ', '.join(missing), table))
    return con


def main(argv):
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--db', default=os.path.join(root, 'tmp', 'codedb', 'codedb.sqlite'))
    parser.add_argument('--root', default=root, help='the checkout the database paths are relative to')
    parser.add_argument('snapshot')
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2
    try:
        with open(args.snapshot, encoding='utf-8') as f:
            snapshot = parse_snapshot(f.read())
        con = open_database(args.db)
    except (OSError, ValueError, UnicodeDecodeError, sqlite3.Error) as error:
        sys.stderr.write('%s\n' % error)
        return 2
    try:
        return 1 if check(snapshot, con, sys.stdout, args.root) else 0
    except sqlite3.Error as error:
        sys.stderr.write('Cannot read the database: %s\n' % error)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
