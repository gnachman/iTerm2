"""The reserved path prefixes of docs/swift-migration/reserved.md: files
under them are not ported on any path. qualify_unit.py and inventory.py
read the table through this module.

The table is the first in the file: a header row of four cells (path
prefix, date, reason, end), its |---| line, then one row per prefix with
four cells, a relative path without empty, . or .. components (it may be
in backquotes) and a YYYY-MM-DD date. The table ends at the first line
that does not start with |; a later line that starts with | is an error,
since a blank line inside the table would otherwise drop the rows after
it. A prefix matches whole path components: sources/Settings/ and
sources/Settings both match sources/Settings/Foo.m, and neither matches
sources/SettingsExtra/Foo.m.
"""

import os
import re

RESERVED = os.path.join('docs', 'swift-migration', 'reserved.md')
_DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
_TABLE_RULE = re.compile(r'^\|(\s*:?-+:?\s*\|)+$')


class ReservedError(Exception):
    """The reserved-path list cannot be read or breaks the table's rules."""


def _cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def read_reserved(path, required=False):
    """The path prefixes in the first column of the table, as written there
    with backquotes removed. A missing file gives none unless required; a
    file without the table, or a line that breaks its rules, raises
    ReservedError, so that a damaged file never silently reserves nothing."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            lines = f.read().split('\n')
    except FileNotFoundError:
        if required:
            raise ReservedError('the reserved-path list %s does not exist' % path)
        return []
    except OSError as e:
        raise ReservedError('the reserved-path list %s cannot be read (%s)' % (path, e.strerror or e))
    start = next((i for i, line in enumerate(lines) if line.startswith('|')), None)
    if start is None:
        raise ReservedError('%s has no table of reserved path prefixes' % path)
    header = _cells(lines[start])
    if len(header) != 4:
        raise ReservedError('%s:%d: the table header has %d cells, not 4 (path prefix, date, reason, end)' % (
            path, start + 1, len(header)))
    if start + 1 >= len(lines) or not _TABLE_RULE.match(lines[start + 1].strip()):
        raise ReservedError('%s:%d: the table header is not followed by its |---| line' % (path, start + 2))
    out = []
    end = len(lines)
    for n in range(start + 2, len(lines)):
        line = lines[n]
        if not line.startswith('|'):
            end = n
            break
        row = _cells(line)
        where = '%s:%d' % (path, n + 1)
        if len(row) != len(header):
            raise ReservedError('%s: the row has %d cells, not %d' % (where, len(row), len(header)))
        prefix = row[0].strip('`')
        parts = prefix[:-1].split('/') if prefix.endswith('/') else prefix.split('/')
        if not prefix or prefix.startswith('/') or any(x in ('', '.', '..') for x in parts):
            raise ReservedError('%s: "%s" is not a path prefix relative to the repository root' % (where, prefix))
        if not _DATE.match(row[1]):
            raise ReservedError('%s: "%s" is not a date (YYYY-MM-DD)' % (where, row[1]))
        out.append(prefix)
    for n in range(end, len(lines)):
        if lines[n].startswith('|'):
            raise ReservedError('%s:%d: a table line after the table ended (a blank line or text inside the table '
                                'would drop the rows after it)' % (path, n + 1))
    return out


def matches(f, prefix):
    """Whether the repository-relative path f lies under prefix, matching
    whole path components."""
    base = prefix.rstrip('/')
    return f == base or f.startswith(base + '/')


def reserved_prefix(files, prefixes):
    """The first of prefixes under which one of files lies, or None."""
    for p in prefixes:
        if any(matches(f, p) for f in files):
            return p
    return None


def unmatched_prefixes(files, prefixes):
    """The prefixes under which none of files lies, in their order: a typo,
    a wrong case or a renamed directory reserves nothing."""
    files = list(files)
    return [p for p in prefixes if not any(matches(f, p) for f in files)]
