#!/usr/bin/env python3
"""Checks the reflective-site registry against the code database, and
regenerates what in it is derived from the database.

Part of the Objective-C to Swift migration (docs/swift-migration/
hidden-callers.md section 2; the registry is
docs/swift-migration/reflective-sites.md).

Usage:

  reflective_registry.py check  [--db DB] [--doc DOC]
  reflective_registry.py update [--db DB] [--doc DOC]

The registry's section 3 has one bullet per dynamic reflective call of the
migration's scope: a row of the database's reflective_call table with
argument_kind 'dynamic' and in_migration_scope 1, counted once per distinct
(file, line, column, call, argument index), written as

  - `FILE:LINE` in `ENCLOSING`: `CALL` on `ARGUMENT`

with the argument cut to 87 characters and "..." when longer than 90, and
backquotes in it written as single quotes. A row matches a bullet with the
same file, enclosing function, call and argument; the line is not part of
the match, so that a site that moved is still the same site. Rows and
bullets that share all four are paired in line order.

check reports, and exits 1 on any of them:
  NEW SITE         a row with no bullet: a dynamic site nobody has read
                   (read it and write its entry; update refuses to run);
  STALE BULLET     a bullet with no row: the site is gone or changed;
  LINE MOVED       a bullet whose line is not its row's line;
  SUMMARY          a cell of the table "Database rows by mechanism and
                   classification" that differs from the count of bullets
                   whose call is of that mechanism (mechanism_of, not the
                   ### heading the bullet sits under) and whose group has
                   that classification (the **CLASS.** paragraph after it);
  NAMES            a name in the table "Names that must be preserved" that
                   no Names: line of sections 3 to 9 lists, or the reverse.

update rewrites the bullet lines from the rows and the summary table from
the bullets, and only those; it refuses while there is a NEW SITE or a
STALE BULLET, because those need a person to read the site. The prose
(the entries' paragraphs and the names table's Sites column) cites places
by file and function, not by line, so that nothing in it moves with the
code; check does not read it. The bullets of sections 4 to 9 keep
FILE:LINE, which entry_points.py parses; they are not regenerated.

check is the lint of hidden-callers.md section 2: a new use of a reflective
API whose name is not a literal is a new dynamic row, so a NEW SITE. It sees
only the calls of the extractor's table (extractor/reflective_table.h) in
Objective-C; conversions to strings (NSStringFromSelector,
NSStringFromClass), names built by naming convention and Swift are not
rows (docs/swift-migration/phase0.md section 10).

Exit status: 0 nothing to report, 1 differences (check) or refused
(update), 2 error.
"""

import argparse
import collections
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DOC = os.path.join(ROOT, 'docs', 'swift-migration', 'reflective-sites.md')
DEFAULT_DB = os.path.join(ROOT, 'tmp', 'codedb', 'codedb.sqlite')

BULLET_RE = re.compile(r'^- `([^`]+):(\d+)` in `([^`]+)`: `([^`]+)` on `(.*)`$')
CLASS_RE = re.compile(r'^\s+\*\*(CLOSED|GENERIC|OPEN-INTERNAL|OPEN-EXTERNAL|NOT-REFLECTIVE|UNRESOLVED)\.\*\*')
CLASSES = ('CLOSED', 'GENERIC', 'OPEN-INTERNAL', 'OPEN-EXTERNAL', 'NOT-REFLECTIVE', 'UNRESOLVED')
SUMMARY_HEADING = '### Database rows by mechanism and classification'
NAMES_HEADING = '### Names that must be preserved'


class RegistryError(Exception):
    pass


def mechanism_of(call):
    """The mechanism a row is counted under in the summary table, from its
    call (the rule the registry was first generated with; an entry's bullets
    sit under the ### heading of the mechanism most of its rows have, so a
    row can sit under another heading than the one it is counted under)."""
    if call == 'NSSelectorFromString':
        return 'Selector from a string'
    if call.startswith('performSelector') or call in ('methodForSelector:', 'sendAction:to:from:', 'setSelector:',
                                                      'scheduledTimerWithTimeInterval:target:selector:userInfo:'
                                                      'repeats:'):
        return 'Calling by selector'
    if call in ('respondsToSelector:', 'methodSignatureForSelector:', 'instanceMethodSignatureForSelector:'):
        return 'Responds-to checks and forwarding'
    if call in ('setAction:', 'initWithTitle:action:keyEquivalent:', 'addItemWithTitle:action:keyEquivalent:'):
        return 'Target-action (menu items and controls)'
    if call in ('NSClassFromString', 'objc_allocateClassPair', 'object_setClass'):
        return 'Class from a string or made at run time'
    if call in ('setValue:forKey:', 'valueForKey:', 'valueForKeyPath:', 'addObserver:forKeyPath:options:context:',
                'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'bind:toObject:withKeyPath:options:',
                'initWithKey:ascending:'):
        return 'Key-value coding, observing, bindings and sort keys'
    return 'Runtime method and property functions'


def bullet_argument(text):
    """The argument as a bullet writes it."""
    a = (text or '').replace('\n', ' ').replace('`', "'")
    return a[:87] + '...' if len(a) > 90 else a


def database_rows(db):
    """[(file, line, enclosing, call, argument as a bullet writes it)], one
    per distinct dynamic in-scope reflective call."""
    if not os.path.exists(db):
        raise RegistryError('no database at %s' % db)
    con = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
    try:
        rows = con.execute(
            "SELECT DISTINCT file, line, col, function_or_selector, argument_index, argument_text, enclosing_name "
            "FROM reflective_call WHERE argument_kind = 'dynamic' AND in_migration_scope = 1 "
            "ORDER BY file, line, col, function_or_selector, argument_index").fetchall()
    except sqlite3.Error as e:
        raise RegistryError('%s: %s' % (db, e))
    finally:
        con.close()
    return [(f, line, enc or '', fn, bullet_argument(arg)) for f, line, col, fn, idx, arg, enc in rows]


def sections(text):
    """{number: (start, end)} offsets of the ## N. sections."""
    marks = [(int(m.group(1)), m.start()) for m in re.finditer(r'^## (\d+)\. ', text, re.M)]
    out = {}
    for i, (n, start) in enumerate(marks):
        out[n] = (start, marks[i + 1][1] if i + 1 < len(marks) else len(text))
    return out


def parse_bullets(text):
    """[dict] of the bullets of section 3, in order, each with its line
    index in text, mechanism (### heading) and classification (the **CLASS.**
    paragraph that follows its group)."""
    secs = sections(text)
    if 3 not in secs:
        raise RegistryError('the registry has no section 3')
    lines = text.split('\n')
    start = text[:secs[3][0]].count('\n')
    end = text[:secs[3][1]].count('\n')
    out = []
    mechanism = None
    pending = []
    for i in range(start, end):
        ln = lines[i]
        if ln.startswith('### '):
            mechanism = ln[4:].strip()
        m = BULLET_RE.match(ln)
        if m:
            b = dict(index=i, file=m.group(1), line=int(m.group(2)), enc=m.group(3), fn=m.group(4),
                     arg=m.group(5), mechanism=mechanism, cls=None)
            out.append(b)
            pending.append(b)
            continue
        c = CLASS_RE.match(ln)
        if c and pending:
            for b in pending:
                b['cls'] = c.group(1)
            pending = []
    if pending:
        raise RegistryError('bullets without a classification paragraph, first: %s:%d' % (
            pending[0]['file'], pending[0]['line']))
    return out


def match(rows, bullets):
    """(pairs [(row, bullet)], new rows, stale bullets): rows and bullets
    with the same file, enclosing function, call and argument, paired in
    line order."""
    by_key = collections.defaultdict(list)
    for b in bullets:
        by_key[(b['file'], b['enc'], b['fn'], b['arg'])].append(b)
    rows_by_key = collections.defaultdict(list)
    for r in rows:
        rows_by_key[(r[0], r[2], r[3], r[4])].append(r)
    pairs, new, stale = [], [], []
    for key in sorted(set(by_key) | set(rows_by_key)):
        rs = sorted(rows_by_key.get(key, []), key=lambda r: r[1])
        bs = sorted(by_key.get(key, []), key=lambda b: b['line'])
        for r, b in zip(rs, bs):
            pairs.append((r, b))
        new.extend(rs[len(bs):])
        stale.extend(bs[len(rs):])
    return pairs, new, stale


def parse_summary(text):
    """({mechanism: {class: n}}, [line indices of the table's mechanism rows],
    index of the Total row)."""
    lines = text.split('\n')
    try:
        at = lines.index(SUMMARY_HEADING)
    except ValueError:
        raise RegistryError('the registry has no "%s" table' % SUMMARY_HEADING[4:])
    header = None
    table = collections.OrderedDict()
    rows = []
    total = None
    for i in range(at + 1, len(lines)):
        ln = lines[i]
        if not ln.startswith('|'):
            if header is None:
                continue
            break
        cells = [c.strip() for c in ln.strip('|').split('|')]
        if header is None:
            header = cells
            continue
        if set(ln) <= set('|- '):
            continue
        name = cells[0].strip('*')
        if name == 'Total':
            total = i
            continue
        table[name] = dict((h, int(v.strip('*'))) for h, v in zip(header[1:], cells[1:]) if h in CLASSES)
        rows.append(i)
    if header is None or [h for h in header[1:] if h != 'Total'] != list(CLASSES):
        raise RegistryError('the summary table does not have the columns Mechanism, %s, Total' % ', '.join(CLASSES))
    return table, rows, total


def counts_of(bullets, mechanisms):
    out = collections.OrderedDict((m, collections.Counter()) for m in mechanisms)
    for b in bullets:
        out.setdefault(mechanism_of(b['fn']), collections.Counter())[b['cls']] += 1
    return out


def summary_lines(counts):
    lines = []
    totals = collections.Counter()
    for m, c in counts.items():
        lines.append('| %s | %s | %d |' % (m, ' | '.join(str(c[k]) for k in CLASSES), sum(c.values())))
        totals.update(c)
    total_line = '| **Total** | %s | **%d** |' % (' | '.join('**%d**' % totals[k] for k in CLASSES),
                                                  sum(totals.values()))
    return lines, total_line


def names_problems(text):
    secs = sections(text)
    listed = set()
    for n in range(3, 10):
        if n not in secs:
            continue
        for ln in text[secs[n][0]:secs[n][1]].split('\n'):
            if ln.startswith('  Names: ') and ln.strip() != 'Names: none.':
                listed |= set(re.findall(r'`([^`]+)`', ln))
    if NAMES_HEADING not in text:
        raise RegistryError('the registry has no "%s" table' % NAMES_HEADING[4:])
    table_text = text.split(NAMES_HEADING, 1)[1].split('\n## ', 1)[0]
    table = set(re.findall(r'^\| `([^`]+)` \|', table_text, re.M))
    out = ['name in a Names: line but not in the names table: %s' % n for n in sorted(listed - table)]
    out += ['name in the names table but in no Names: line: %s' % n for n in sorted(table - listed)]
    return out


def run(command, db, doc, out):
    with open(doc, encoding='utf-8') as f:
        text = f.read()
    rows = database_rows(db)
    bullets = parse_bullets(text)
    pairs, new, stale = match(rows, bullets)
    moved = [(r, b) for r, b in pairs if r[1] != b['line']]
    table, table_rows, total_row = parse_summary(text)
    counts = counts_of(bullets, list(table))
    summary = []
    for m in counts:
        for k in CLASSES:
            have = table.get(m, {}).get(k, 0)
            if have != counts[m][k]:
                summary.append('%s, %s: the table says %d, section 3 has %d' % (m, k, have, counts[m][k]))
    names = names_problems(text)
    out.write('database rows (dynamic, in scope, distinct file, line, column, call, argument index): %d\n' % len(rows))
    out.write('bullets in section 3: %d\n' % len(bullets))
    for title, items in (('NEW SITE (a row with no bullet: read it and write its entry)',
                          ['%s:%d in %s: %s on %s' % r for r in new]),
                         ('STALE BULLET (a bullet with no row)',
                          ['%s:%d in %s: %s on %s' % (b['file'], b['line'], b['enc'], b['fn'], b['arg']) for b in stale]),
                         ('LINE MOVED (update rewrites it)',
                          ['%s:%d now %d in %s: %s' % (b['file'], b['line'], r[1], b['enc'], b['fn']) for r, b in moved]),
                         ('SUMMARY (update rewrites the table)', summary),
                         ('NAMES', names)):
        out.write('%s: %d\n' % (title, len(items)))
        for item in items:
            out.write('  %s\n' % item)
    if command == 'check':
        return 1 if (new or stale or moved or summary or names) else 0
    if new or stale:
        out.write('update refused: new or stale sites need a person to read them first\n')
        return 1
    lines = text.split('\n')
    for r, b in moved:
        lines[b['index']] = lines[b['index']].replace('`%s:%d`' % (b['file'], b['line']), '`%s:%d`' % (b['file'], r[1]), 1)
    mech_lines, total_line = summary_lines(counts)
    if len(mech_lines) != len(table_rows):
        raise RegistryError('section 3 has a mechanism the summary table lacks')
    for i, ln in zip(table_rows, mech_lines):
        lines[i] = ln
    lines[total_row] = total_line
    new_text = '\n'.join(lines)
    if new_text != text:
        tmp = doc + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(new_text)
        os.replace(tmp, doc)
    out.write('updated %s: %d bullet lines, summary table %s\n' % (doc, len(moved), 'rewritten' if summary else
                                                                   'unchanged'))
    return 1 if names else 0


def main(argv=None, out=None):
    out = out or sys.stdout
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('command', choices=('check', 'update'))
    p.add_argument('--db', default=DEFAULT_DB, help='the code database (read only)')
    p.add_argument('--doc', default=DEFAULT_DOC, help='the registry')
    args = p.parse_args(argv)
    try:
        return run(args.command, args.db, args.doc, out)
    except (RegistryError, OSError) as e:
        print('reflective_registry: error: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
